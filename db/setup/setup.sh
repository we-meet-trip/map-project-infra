#!/bin/bash
# 빈 데이터 볼륨에서 DB 를 서비스가 붙을 수 있는 상태로 만든다(빠른 시작용).
#
# compose 의 일회성 서비스들이 아래 단계를 순서대로 부른다. 자바·파이썬 단계(user
# 부트스트랩·user 마이그레이션·hub 마이그레이션)는 각 서비스 이미지가 맡고, 이 파일은
# 그 사이의 psql 단계만 한다. 모든 단계는 다시 불러도 안전하다 — 이미 끝난 일은
# 건너뛴다. 그래서 두 번째 `docker compose up` 은 아무것도 바꾸지 않고 지나간다.
#
#   user-prepare   첫 부팅 직후의 빈 DB 에 user 부트스트랩 표식과 준비 SQL 을 건다
#   user-activate  user 부트스트랩이 끝난 뒤 실행·마이그레이션 로그인을 연다
#   platform       PostGIS, 나머지 스키마, hub·agent·admin·exporter 역할과 비밀번호
#   finish         hub 첫 마이그레이션에 잠시 준 권한을 거두고 역할 SQL 을 다시 건다
#
# 역할 SQL 은 각 서비스 레포의 것을 읽기 전용으로 붙여 쓴다(형제 clone). 사본을 두지
# 않는 이유는, 서비스가 표를 바꿀 때 권한 목록도 같이 바뀌는데 사본은 조용히 어긋나기
# 때문이다.
#
# 비밀값은 명령줄에 싣지 않는다. psql 에는 표준입력의 \set 줄로 넘긴다.
set -euo pipefail

DB=${MAP_PROJECT_POSTGRES_DB:?}
STATE=/state
SQL_USER=/sql/user
SQL_HUB=/sql/hub/database-roles.sql
SQL_AGENT=/sql/agent/database-roles.sql
export PGHOST=postgres PGDATABASE="$DB" PGUSER=${MAP_PROJECT_POSTGRES_USER:?} PGPASSWORD=${MAP_PROJECT_POSTGRES_PASSWORD:?}

psql_run() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }
psql_value() { psql -X -q -At -v ON_ERROR_STOP=1 -c "$1"; }
# \set 줄. 값 안의 작은따옴표는 psql 규칙대로 두 번 쓴다.
var() { printf "\\\\set %s '%s'\n" "$1" "${2//\'/\'\'}"; }
# DSN 의 비밀번호 부분만 꺼낸다(생성 스크립트가 만든 값은 16진수라 인코딩이 없다).
dsn_password() { printf '%s' "$1" | sed -E 's#^[a-z+]+://[^:]+:([^@]+)@.*$#\1#'; }
role_exists() { [ "$(psql_value "SELECT count(*) FROM pg_roles WHERE rolname = '$1'")" = 1 ]; }

user_prepare() {
  mkdir -p "$STATE"
  if role_exists map_user_owner; then
    rm -f "$STATE/user-bootstrap.pending"
    echo "user-prepare: 이미 준비됨 — 건너뜀"; return
  fi
  local marker=${USER_BOOTSTRAP_MARKER:?} password=${USER_BOOTSTRAP_PASSWORD:?}
  { var db "$DB"; var marker "$marker"
    printf '%s\n' "SELECT format('COMMENT ON DATABASE %I IS %L', :'db', 'map-user-bootstrap:v1:' || :'marker') \\gexec"
  } | psql_run
  { var expected_database "$DB"; var marker "$marker"; var bootstrap_password "$password"
    cat "$SQL_USER/user-database-bootstrap-prepare.sql"; } | psql_run
  touch "$STATE/user-bootstrap.pending"
  echo "user-prepare: 끝"
}

user_activate() {
  if [ ! -f "$STATE/user-bootstrap.pending" ]; then
    echo "user-activate: 할 일 없음 — 건너뜀"; return
  fi
  local marker=${USER_BOOTSTRAP_MARKER:?}
  { var expected_database "$DB"; var marker "$marker"
    cat "$SQL_USER/user-database-bootstrap-finalize.sql"; } | psql_run
  { var expected_database "$DB"; var marker "$marker"
    var runtime_password "${USER_DATABASE_PASSWORD:?}"; var migrator_password "${USER_MIGRATION_PASSWORD:?}"
    cat "$SQL_USER/user-database-bootstrap-activate.sql"; } | psql_run
  rm -f "$STATE/user-bootstrap.pending"
  echo "user-activate: 끝"
}

platform() {
  # PostGIS 확장 스크립트는 두 뷰를 PUBLIC 에 열어 둔다. user 의 권한 검사는
  # spatial_ref_sys 만 예외로 보므로 두 뷰를 다시 닫는다.
  psql_run <<'SQL'
BEGIN;
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;
REVOKE SELECT ON TABLE public.geometry_columns, public.geography_columns FROM PUBLIC;
COMMIT;
SQL
  psql_run -f /setup/00-create-schemas.sql
  psql_run -f "$SQL_HUB"
  psql_run -f "$SQL_AGENT"
  POSTGRES_USER=$PGUSER POSTGRES_DB=$DB bash /setup/10-admin.sh
  psql_run <<'SQL'
BEGIN;
DO $exporter$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'map_pg_exporter') THEN
    CREATE ROLE map_pg_exporter LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
END
$exporter$;
GRANT pg_monitor TO map_pg_exporter;
SELECT format('GRANT CONNECT ON DATABASE %I TO map_admin, map_pg_exporter', current_database()) \gexec
GRANT USAGE ON SCHEMA public TO map_hub_owner, map_admin;
COMMIT;
SQL
  { var hub_runtime "$(dsn_password "${HUB_DATABASE_URL:?}")"
    var hub_migrator "$(dsn_password "${HUB_MIGRATION_DATABASE_URL:?}")"
    var agent_runtime "${AGENT_DATABASE_PASSWORD:?}"
    var agent_migrator "$(dsn_password "${AGENT_CHECKPOINT_MIGRATION_DSN:?}")"
    var exporter "$(dsn_password "${MAP_PROJECT_POSTGRES_EXPORTER_DSN:?}")"
    cat <<'SQL'
BEGIN;
ALTER ROLE map_hub_runtime LOGIN PASSWORD :'hub_runtime';
ALTER ROLE map_hub_migrator LOGIN PASSWORD :'hub_migrator';
ALTER ROLE map_agent_runtime LOGIN PASSWORD :'agent_runtime';
ALTER ROLE map_agent_migrator LOGIN PASSWORD :'agent_migrator';
ALTER ROLE map_pg_exporter LOGIN PASSWORD :'exporter';
COMMIT;
SQL
  } | psql_run
  # hub 의 첫 마이그레이션은 스키마가 있어도 DB CREATE 권한을 요구한다. 아직 표가 없을
  # 때만 잠시 주고, finish 단계에서 거둔다.
  if [ "$(psql_value "SELECT to_regclass('hub_data.alembic_version') IS NULL")" = t ]; then
    { var db "$DB"; printf '%s\n' "SELECT format('GRANT CREATE ON DATABASE %I TO map_hub_owner', :'db') \\gexec"; } | psql_run
    echo "platform: hub 첫 마이그레이션 권한을 잠시 열었다"
  fi
  echo "platform: 끝"
}

finish() {
  { var db "$DB"; printf '%s\n' "SELECT format('REVOKE CREATE ON DATABASE %I FROM map_hub_owner', :'db') \\gexec"; } | psql_run
  psql_run -f "$SQL_HUB"
  psql_run -f "$SQL_AGENT"
  echo "finish: 끝"
}

case "${1:-}" in
  user-prepare) user_prepare ;;
  user-activate) user_activate ;;
  platform) platform ;;
  finish) finish ;;
  *) echo "쓰임: $0 user-prepare|user-activate|platform|finish" >&2; exit 2 ;;
esac
