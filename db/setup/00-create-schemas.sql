-- =========================================================================
-- map-project-infra / postgres 스키마 준비
--
-- db/setup/setup.sh 의 platform 단계가 user 부트스트랩 뒤에 실행한다(compose 의
-- db-platform). 멱등 — CREATE IF NOT EXISTS 만 사용하므로 다시 돌려도 안전하다.
-- POSTGRES_USER 환경변수가 변경되어도 동작하도록 current_user 를
-- 동적으로 사용한다(특정 사용자명에 하드코딩하지 않음).
-- =========================================================================

-- PostGIS 확장 활성화.
-- 공간(geo) 좌표·거리 계산에 사용되는 GIS 기능을 데이터베이스에 등록한다.
-- 이미 활성화된 경우 IF NOT EXISTS 로 건너뛴다.
CREATE EXTENSION IF NOT EXISTS postgis;

-- 도메인별 스키마 분리.
--   user_service : 사용자/계정/즐겨찾기 등 user 서비스 영역(Spring 측 BFF 소유)
--   hub_data     : 외부 데이터(날씨/지역 등) 캐시 영역(hub 서비스 소유)
--   langgraph    : LangGraph 체크포인트/상태 저장 영역(agent 서비스 소유)
--   admin_data   : 운영 감사/계정/세션 영역(admin 서비스 소유)
-- 각 서비스는 자기 스키마 외부의 테이블에 직접 쓰기 접근하지 않는 것이 원칙.
-- admin_data 는 여기서 생성만 하고, 소유권은 map_admin 역할 생성 이후
-- 10-admin.sh 에서 이전한다(ALTER SCHEMA ... OWNER TO map_admin).
CREATE SCHEMA IF NOT EXISTS user_service;
CREATE SCHEMA IF NOT EXISTS hub_data;
CREATE SCHEMA IF NOT EXISTS langgraph;
CREATE SCHEMA IF NOT EXISTS admin_data;

-- 현재 로그인 ROLE 의 기본 search_path 를 변경한다.
-- DO $$ ... $$ 블록 + format(%I) 를 사용하는 이유:
--   ALTER ROLE 은 식별자(ROLE 이름)를 파라미터로 받을 수 없기 때문에
--   current_user 를 동적 SQL 로 안전하게 인용(%I)하여 주입한다.
-- 결과: 본 ROLE 로 접속한 세션은 테이블을 user_service → hub_data → public
-- 순서로 자동 검색하므로, 평소 쿼리에서 스키마 접두사를 생략해도 동작한다.
DO $$
BEGIN
  EXECUTE format(
    'ALTER ROLE %I SET search_path = user_service, hub_data, public',
    current_user
  );
END
$$;
