#!/usr/bin/env bash
# 로컬 빠른 시작용 .env 를 만든다. 외부 키는 하나도 넣지 않는다.
#
# 원본은 .env.example 이다. 본보기에는 비밀값 자리가 비어 있으므로, 여기서 비밀번호·
# 토큰·암호 열쇠를 이 기계에서만 쓰는 무작위값으로 채운다. 같은 비밀번호가 여러
# 자리(로그인 비밀번호와 그것을 담은 접속 문자열)에 들어가므로 한곳에서 만들어 맞춘다.
#
# 다시 만들어도(--force) 이미 있는 비밀번호와 열쇠는 그대로 옮겨 온다. 좌표를 봉한
# 열쇠를 바꾸면 그 열쇠로 봉해 둔 값을 영영 읽지 못하고, DB 비밀번호를 바꾸면 이미
# 만들어 둔 데이터 볼륨의 로그인과 어긋난다.
#
# 사용: ./scripts/make-local-env.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=.env.example
DST=${MAP_PROJECT_ENV_FILE:-.env}
[ -f "$SRC" ] || { echo "원본이 없다: $SRC" >&2; exit 1; }
if [ -f "$DST" ] && [ "${1:-}" != "--force" ]; then
  echo "이미 있다: $DST (다시 만들려면 --force — 비밀번호와 열쇠는 옮겨 온다)" >&2
  exit 1
fi
command -v openssl >/dev/null || { echo "openssl 이 필요하다" >&2; exit 1; }
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
cp "$SRC" "$TMP"

set_kv() {  # 값 하나를 바꾼다. 키가 없으면 끝에 붙인다(sed -i 는 BSD·GNU 가 달라 쓰지 않는다).
  local key=$1 val=$2 out
  if grep -qE "^${key}=" "$TMP"; then
    out=$(awk -v k="$key" -v v="$val" 'BEGIN{FS=OFS="="} $1==k {print k "=" v; next} {print}' "$TMP")
    printf '%s\n' "$out" > "$TMP"
  else
    printf '%s=%s\n' "$key" "$val" >> "$TMP"
  fi
}
prev() { [ -f "$DST" ] && grep -E "^$1=" "$DST" | head -1 | cut -d= -f2- | tr -d '\r' || true; }
keep_or() { local v; v=$(prev "$1"); [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"; }
hex() { openssl rand -hex 32; }
b64() { openssl rand -base64 32 | tr -d '\n'; }
# 접속 문자열 안의 비밀번호를 옮겨 온다. 없으면 새로 만든다.
keep_dsn_pw() { local v; v=$(prev "$1"); if [ -n "$v" ]; then printf '%s' "$v" | sed -E 's#^[a-z+]+://[^:]+:([^@]+)@.*$#\1#'; else hex; fi; }

DB=$(grep -E '^MAP_PROJECT_POSTGRES_DB=' "$TMP" | cut -d= -f2-)
DB=${MAP_PROJECT_ENV_DB:-${DB:-map}}
set_kv MAP_PROJECT_POSTGRES_DB "$DB"

set_kv MAP_PROJECT_POSTGRES_PASSWORD "$(keep_or MAP_PROJECT_POSTGRES_PASSWORD "$(hex)")"

admin_pw=$(keep_or MAP_PROJECT_ADMIN_DB_PASSWORD "$(hex)")
set_kv MAP_PROJECT_ADMIN_DB_PASSWORD "$admin_pw"
set_kv ADMIN_DATABASE_URL "postgresql+psycopg://map_admin:${admin_pw}@postgres:5432/${DB}"

set_kv USER_DATABASE_PASSWORD "$(keep_or USER_DATABASE_PASSWORD "$(hex)")"
set_kv USER_MIGRATION_URL "jdbc:postgresql://postgres:5432/${DB}?currentSchema=user_service"
set_kv USER_MIGRATION_USERNAME map_user_migrator
set_kv USER_MIGRATION_PASSWORD "$(keep_or USER_MIGRATION_PASSWORD "$(hex)")"
set_kv USER_BOOTSTRAP_PASSWORD "$(keep_or USER_BOOTSTRAP_PASSWORD "$(hex)")"
set_kv USER_BOOTSTRAP_MARKER "$(keep_or USER_BOOTSTRAP_MARKER "$(hex)")"

set_kv HUB_DATABASE_URL "postgresql+psycopg://map_hub_runtime:$(keep_dsn_pw HUB_DATABASE_URL)@postgres:5432/${DB}"
set_kv HUB_MIGRATION_DATABASE_URL "postgresql+psycopg://map_hub_migrator:$(keep_dsn_pw HUB_MIGRATION_DATABASE_URL)@postgres:5432/${DB}"

set_kv AGENT_DATABASE_PASSWORD "$(keep_or AGENT_DATABASE_PASSWORD "$(hex)")"
set_kv AGENT_CHECKPOINT_MIGRATION_DSN "postgresql://map_agent_migrator:$(keep_dsn_pw AGENT_CHECKPOINT_MIGRATION_DSN)@postgres:5432/${DB}"

set_kv MAP_PROJECT_POSTGRES_EXPORTER_DSN "postgresql://map_pg_exporter:$(keep_dsn_pw MAP_PROJECT_POSTGRES_EXPORTER_DSN)@postgres:5432/${DB}?sslmode=disable"

for k in MAP_PROJECT_INTERNAL_SERVICE_TOKEN MAP_PROJECT_USER_ADMIN_INTERNAL_TOKEN \
         MAP_PROJECT_HUB_ADMIN_INTERNAL_TOKEN MAP_PROJECT_VISION_INTERNAL_TOKEN \
         MAP_PROJECT_GRAFANA_ADMIN_PASSWORD ADMIN_BOOTSTRAP_PASSWORD; do
  set_kv "$k" "$(keep_or "$k" "$(hex)")"
done

# 세 열쇠는 서로 달라야 한다. 하나로 합치면 한 서비스가 뚫렸을 때 다른 용도로 봉한
# 값까지 함께 열린다(agent 는 봉투 열쇠와 체크포인트 열쇠가 같으면 부팅하지 않는다).
set_kv MAP_PROJECT_LOCATION_WIRE_KEY "$(keep_or MAP_PROJECT_LOCATION_WIRE_KEY "$(b64)")"
set_kv USER_LOCATION_ENC_ACTIVE_KID k1
set_kv USER_LOCATION_ENC_KEYS "$(keep_or USER_LOCATION_ENC_KEYS "k1:$(b64)")"
set_kv AGENT_CHECKPOINT_ENC_ACTIVE_KID k1
set_kv AGENT_CHECKPOINT_ENC_KEYS "$(keep_or AGENT_CHECKPOINT_ENC_KEYS "k1:$(b64)")"

umask 077
cp "$TMP" "$DST"
echo "$DST 를 만들었다. 운영 콘솔 첫 로그인: ADMIN_BOOTSTRAP_USER / ADMIN_BOOTSTRAP_PASSWORD (이 파일 안)."
