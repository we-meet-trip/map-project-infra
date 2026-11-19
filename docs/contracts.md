# 계약

이 저장소가 정하거나 여러 저장소가 함께 지키는 이름과 경로를 모은다. 각 서비스의 API 자체는 그 서비스 저장소의 `docs/contracts.md` 가 정한다.

## 포트 (모두 127.0.0.1)

| 서비스 | 호스트 → 컨테이너 | 프로필 |
|---|---|---|
| proxy 공개 관문 | 8090 → 80 | backend·full |
| user | 8080 → 8080 | backend·full |
| agent | 8000 → 8000 | backend·full |
| hub | 8001 → 8000 | backend·full |
| yolo | 8004 → 8000 | vision |
| osrm-foot / osrm-bicycle | 5000 / 5001 → 5000 | routing |
| postgres | 5432 → 5432 | infra·full |
| redis | 16379 → 6379 | infra·full |
| admin / admin-web | 8002 → 8000 / 8003 → 80 | 관리 스택 |
| prometheus / grafana | 9090 / 3000 | 관리 스택 monitoring |

관문의 내부 창구(8081)는 호스트에 열지 않는다.

## 관문 경로 (`proxy/default.conf`)

| 창구 | 경로 | 넘기는 곳 |
|---|---|---|
| 공개 :80 | `/healthz` | 관문 자체 |
| 공개 :80 | `/healthz/app` | user `/actuator/health` |
| 공개 :80 | `/api/v1/` (일정 생성·초대 경로는 주소당 상한) | user |
| 공개 :80 | `/ws/chat` | user (WebSocket) |
| 공개 :80 | `/ws/vision` | yolo (WebSocket) |
| 공개 :80 | `/actuator` | 막음 |
| 공개 :80 | 그 밖 | 404 |
| 내부 :8081 | `/user/` · `/hub/` · `/agent/` | 접두를 떼고 각 서비스로 |

서비스끼리 부를 때는 `http://proxy:8081/<서비스>` 를 쓴다(`MAP_PROJECT_AGENT_BASE_URL`·`MAP_PROJECT_HUB_BASE_URL`·`ADMIN_USER_BASE_URL`).

## 환경변수 이름

- 여러 서비스가 **같은 값**을 읽는 이름은 `MAP_PROJECT_` 를 붙인다(내부 토큰, 좌표 봉투 열쇠, 외부 키, DB·Redis 위치, Redis DB 번호, 스트림 이름 등).
- 한 서비스만 읽는 이름은 그 서비스 접두를 붙인다: `USER_`·`AGENT_`·`HUB_`·`YOLO_`·`ADMIN_`·`CLIENT_`(앱 빌드값).
- 이름이 같아도 서비스마다 따로 정하는 값은 서비스 접두로 나눈다: 인증 강제(`USER_`/`AGENT_`/`HUB_AUTH_ENFORCED`), 로그 레벨(`AGENT_`/`HUB_`/`YOLO_LOG_LEVEL`). 캐시 DB 번호는 user(`USER_REDIS_DB_CACHE`)와 hub·관리 콘솔(`MAP_PROJECT_REDIS_DB_HUB_CACHE`)이 다른 값이라 둘로 나눈다.
- 이미지가 이름을 정해 둔 값(Postgres `POSTGRES_*`, Grafana `GF_*`, exporter `DATA_SOURCE_NAME`, Redis `REDIS_PASSWORD`)은 `.env` 에서는 접두 이름을 쓰고, compose `environment:` 에서 원래 이름으로 넘긴다.
- 서비스마다 받는 이름 전체는 `docker compose --profile '*' config --format json` 의 `services.<서비스>.environment` 가 기준이다.

## 공유 비밀값

| 이름 | 나눠 갖는 곳 | 형식 |
|---|---|---|
| `MAP_PROJECT_LOCATION_WIRE_KEY` | user·agent·hub — 서비스 사이로 오가는 좌표를 감싸는 열쇠. 없거나 틀리면 셋 모두 기동을 멈춘다 | 32바이트 base64 |
| `USER_LOCATION_ENC_KEYS` | user 저장 본문 암호화 | `k1:<32바이트 base64>` |
| `AGENT_CHECKPOINT_ENC_KEYS` | agent 체크포인트 봉인 | `k1:<32바이트 base64>`, 봉투 열쇠와 달라야 한다 |
| `MAP_PROJECT_INTERNAL_SERVICE_TOKEN` | 서비스끼리 부를 때 | 무작위 문자열 |
| `MAP_PROJECT_USER_ADMIN_INTERNAL_TOKEN` · `MAP_PROJECT_HUB_ADMIN_INTERNAL_TOKEN` | 관리 콘솔 → user·hub 관리 API | 무작위 문자열, 서로 달라야 한다 |
| `MAP_PROJECT_VISION_INTERNAL_TOKEN` | yolo → user 사용 승인 | 무작위 문자열 |

`scripts/make-local-env.sh` 가 모두 만든다. `.env.example` 에는 빈 자리만 있다.

## 이미지 이름

로컬 빌드: `map-project-<서비스>:local`(user·agent·hub·yolo·admin·admin-web). user·hub 이미지는 DB 준비 단계와 서빙이 나눠 쓴다. compose 프로젝트 이름을 바꿔도 이미지 이름은 그대로다. 받아 쓰기 덧칠(`docker-compose.registry.yml`·`docker-compose.admin.registry.yml`): `${MAP_PROJECT_IMAGE_REGISTRY}/map-project-<서비스>:${MAP_PROJECT_IMAGE_TAG}` — 이 저장소는 이미지를 게시하지 않으므로 직접 빌드해 올린 레지스트리를 적는다.

## 소유

| 무엇 | 정하는 곳 |
|---|---|
| compose 구성·포트·프로필·관문 경로·DB 준비 순서·환경변수 이름 체계 | 이 저장소 |
| 스키마 안 표·역할 SQL | 각 서비스 저장소(`scripts/database-roles.sql`, user `scripts/sql/`) |
| 서비스 API·헤더·스트림 본문 | 각 서비스 저장소의 `docs/contracts.md` |
