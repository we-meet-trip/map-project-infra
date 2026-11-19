#!/bin/bash
# =========================================================================
# map-project-infra / postgres 초기화 — map_admin 읽기전용 역할 (admin 모니터링)
#
# db/setup/setup.sh 의 platform 단계가 00-create-schemas.sql 다음에 실행한다.
# 멱등이라 compose 를 다시 올릴 때마다 돌아도 안전하다.
#
# 비밀번호는 MAP_PROJECT_ADMIN_DB_PASSWORD(컨테이너 env, 공유 .env 유래) 단일 출처에서
# 온다. admin 컨테이너의 ADMIN_DATABASE_URL 비밀번호와 반드시 일치해야 한다.
#
# admin_data 스키마 소유권을 map_admin 으로 넘긴다.
#   - hub_data 는 계속 SELECT-only(읽기전용 4중 보장의 DB 계층 유지).
#   - admin_data 는 map_admin 소유 → admin 레포 Alembic 이 이 DSN 으로
#     테이블(audit_logs/admin_accounts/admin_sessions)을 생성·관리한다.
# =========================================================================
set -euo pipefail

export MAP_PROJECT_ADMIN_DB_PASSWORD="${MAP_PROJECT_ADMIN_DB_PASSWORD:?MAP_PROJECT_ADMIN_DB_PASSWORD must be set (infra .env)}"

# 따옴표 heredoc(<<'EOSQL')으로 $$·:'var' 를 psql 로 그대로 전달한다.
# 비밀번호는 psql 이 환경에서 \getenv 로 읽어 psql 변수 :'mapadminpw' 로 안전하게
# 인용한다(PostgreSQL 15 이상). -v 로 주면 값이 psql 명령줄(프로세스 목록)에 드러난다.
psql -v ON_ERROR_STOP=1 \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'EOSQL'
\getenv mapadminpw MAP_PROJECT_ADMIN_DB_PASSWORD
-- 역할이 없을 때만 생성(gexec: 생성 SQL 을 조건부 실행).
SELECT 'CREATE ROLE map_admin LOGIN'
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'map_admin')
\gexec

-- 비밀번호는 매 실행마다 동기화(신규/기존 모두 idempotent).
ALTER ROLE map_admin LOGIN PASSWORD :'mapadminpw';

-- hub_data 읽기전용: 스키마 USAGE + 기존 테이블 SELECT + 미래 테이블 SELECT.
-- (최초 부팅 시엔 hub_data 테이블이 아직 없어 ALL TABLES 는 0건 부여되지만,
--  ALTER DEFAULT PRIVILEGES 가 이후 hub Alembic 이 만드는 테이블을 자동 커버.)
GRANT USAGE ON SCHEMA hub_data TO map_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA hub_data TO map_admin;
-- hub 표는 hub 의 소유 역할(map_hub_owner)이 만든다. 기본 권한은 표를 만드는 역할마다 따로
-- 걸리므로 FOR ROLE 로 그 역할을 지정한다(빼면 이 스크립트를 돌린 운영자 역할이 만드는 표에만
-- 적용되어, hub 마이그레이션이 만든 표를 콘솔이 읽지 못한다). 이 역할은 같은 platform 단계에서
-- hub 역할 SQL 이 먼저 만든다.
ALTER DEFAULT PRIVILEGES FOR ROLE map_hub_owner IN SCHEMA hub_data GRANT SELECT ON TABLES TO map_admin;

-- admin_data 소유권 이전: map_admin 이 admin_data 를 소유(RW).
-- 00-create-schemas.sql 이 admin_data 를 superuser 소유로 생성해 두었으므로,
-- 여기서 소유권만 map_admin 으로 넘긴다. 소유자는 자동으로 전권(CREATE/DML)을
-- 가지므로 별도 GRANT 불필요. admin 레포 Alembic 이 이 스키마에 테이블을 만든다.
ALTER SCHEMA admin_data OWNER TO map_admin;

-- 편의용 search_path. admin_data 를 앞에 두어 Alembic 의 alembic_version(무수식
-- 생성)이 admin_data 에 안착하게 한다. hub_data 읽기는 뒤이어 계속 동작.
ALTER ROLE map_admin SET search_path = admin_data, hub_data, public;
EOSQL

echo "10-admin.sh: map_admin read-only role ensured on hub_data"
