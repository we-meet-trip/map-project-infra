# 다이어그램 근거표

그림의 모든 노드와 엣지를 코드·설정 줄에 묶는다. 교차 검토는 이 표로 한다. 줄 번호는 이 저장소 기준이다.
확인 방법의 "렌더"는 `./scripts/make-local-env.sh` 로 만든 `.env` 로
`docker compose -f <파일> --profile '*' config --format json` 을 돌려 본 것이다.

## system — 전체 시스템 (`docs/diagrams/src/system.dot`)

| 요소 | 주장 | 근거 file:line | 확인 방법 |
|---|---|---|---|
| 노드 서비스 스택 | 프로젝트 이름 map-project, 네트워크 map-net | `docker-compose.yml:35`, `docker-compose.yml:847` | 렌더의 `name`, `networks.default.name` |
| 노드 관리 스택 | 프로젝트 이름 map-admin, 서비스 스택의 map-net 에 얹힌다 | `docker-compose.admin.yml:37`, `docker-compose.admin.yml:300-305` | 렌더 |
| 노드 client | 앱은 이 저장소 밖(map-project-client)이고 관문으로 들어온다 | `proxy/default.conf:67`, `proxy/default.conf:168` | — |
| 노드 proxy | 공개 관문 :8090(컨테이너 80), 내부 창구 :8081 | `docker-compose.yml:796`, `docker-compose.yml:817`, `proxy/default.conf:67`, `proxy/default.conf:231` | 렌더의 `ports` |
| 노드 user | :8080 | `docker-compose.yml:347`, `docker-compose.yml:483` | 렌더 |
| 노드 agent | :8000, 합성 LLM 이 기본 | `docker-compose.yml:495`, `docker-compose.yml:581`, `docker-compose.yml:527`, `.env.example:159` | 렌더의 `AGENT_LLM_PROVIDER=fake` |
| 노드 hub | :8001(컨테이너 8000) | `docker-compose.yml:598`, `docker-compose.yml:710` | 렌더 |
| 노드 DB 준비 사슬 | 일회성 단계 7개(`db-user-prepare` … `db-finish`), 끝나면 멈춘다 | `docker-compose.yml:90`, `docker-compose.yml:173`, `db/setup/setup.sh` | 렌더의 `restart: "no"` |
| 노드 yolo | :8004, vision 프로필(기본 꺼짐) | `docker-compose.yml:739`, `docker-compose.yml:770`, `docker-compose.yml:772` | `--profile full` 렌더에 없음 |
| 노드 osrm | :5000·:5001, routing 프로필(기본 꺼짐) | `docker-compose.yml:276`, `docker-compose.yml:292`, `docker-compose.yml:297`, `docker-compose.yml:330` | `--profile full` 렌더에 없음 |
| 노드 postgres | PostGIS, :5432 | `docker-compose.yml:184`, `docker-compose.yml:207` | 렌더 |
| 노드 redis | :16379(컨테이너 6379) | `docker-compose.yml:227`, `docker-compose.yml:257` | 렌더 |
| 노드 admin-web·admin | :8003·:8002 | `docker-compose.admin.yml:142`, `docker-compose.admin.yml:159`, `docker-compose.admin.yml:110`, `docker-compose.admin.yml:127` | 렌더 |
| 노드 모니터링 | prometheus·grafana·exporter, monitoring 프로필(기본 꺼짐) | `docker-compose.admin.yml:167`, `docker-compose.admin.yml:172`, `docker-compose.admin.yml:195`, `docker-compose.admin.yml:200` | 렌더 |
| 노드 Gemini API | 키를 넣을 때만 부른다(기본 합성 제공자) | `.env.example:159`, `docker-compose.yml:508`, `docker-compose.yml:752` | 본보기의 키 자리는 비어 있음 |
| 노드 공공·지도 API | 키가 없으면 hub 가 스텁으로 답한다 | `docker-compose.yml:645`, `.env.example` (5) 외부 API 키 절 | 본보기의 키 자리는 비어 있음 |
| 엣지 client → proxy | HTTP·WebSocket | `proxy/default.conf:168`, `proxy/default.conf:182`, `proxy/default.conf:198` | — |
| 엣지 proxy → user | `/api/v1`, `/ws/chat` 을 user 로 | `proxy/default.conf:168-169`, `proxy/default.conf:182-183` | nginx -t (CI) |
| 엣지 proxy → yolo | `/ws/vision` 을 yolo 로 | `proxy/default.conf:198-202` | nginx -t (CI) |
| 엣지 user → agent | 내부 창구 `/agent` | `.env.example:103`, `docker-compose.yml:357`, `proxy/default.conf:275-277` | 렌더 |
| 엣지 user → hub, agent → hub | 내부 창구 `/hub` | `.env.example:104`, `docker-compose.yml:382`, `docker-compose.yml:514`, `proxy/default.conf:266-268` | 렌더 |
| 엣지 yolo → user | 사용 승인 확인 | `docker-compose.yml:758` | 렌더 |
| 엣지 user → postgres | `user_service` 스키마, 실행 역할 `map_user_runtime` | `docker-compose.yml:416`, `db/setup/00-create-schemas.sql` | 렌더 |
| 엣지 hub → postgres | `hub_data` 스키마, 실행 역할 `map_hub_runtime` | `docker-compose.yml:630`, `scripts/make-local-env.sh` (HUB_DATABASE_URL) | 렌더 |
| 엣지 agent → postgres (점선) | `langgraph` 체크포인터, 기본 꺼짐 | `docker-compose.yml:505`, `.env.example:162` | 렌더의 `AGENT_CHECKPOINT_ENABLED=false` |
| 엣지 user·agent·hub → redis | 세션·스트림·캐시 | `docker-compose.yml:432`, `docker-compose.yml:533`, `docker-compose.yml:665` | 렌더 |
| 엣지 DB 준비 사슬 → postgres | 역할·스키마·마이그레이션 | `db/setup/setup.sh` (user-prepare·user-activate·platform·finish) | psql 단계 임시 컨테이너 2회 반복 |
| 엣지 hub → osrm (점선) | 도보·자전거 경로, 주소를 채울 때만 | `docker-compose.yml:663`, `.env.example` (5b) 절 | 본보기 값은 비어 있음 |
| 엣지 hub → 공공·지도 API (점선) | 키를 넣을 때만 | `docker-compose.yml:645` | — |
| 엣지 agent·yolo → Gemini (점선) | 키를 넣고 제공자를 gemini 로 둘 때만 | `docker-compose.yml:508`, `docker-compose.yml:752` | — |
| 엣지 admin-web → admin | 화면이 API 를 부른다 | `docker-compose.admin.yml:142-159` | — |
| 엣지 admin → postgres | `admin_data` 쓰기, `hub_data` 읽기 | `docker-compose.admin.yml:43`, `db/setup/10-admin.sh` | psql 단계 임시 컨테이너 |
| 엣지 admin → redis | 진단 읽기 | `docker-compose.admin.yml:62` | 렌더 |
| 엣지 admin → proxy | 관리 API 는 내부 창구로 user·hub 를 부른다 | `.env.example:105`, `docker-compose.admin.yml:56`, `docker-compose.admin.yml:58` | 렌더 |
| 엣지 모니터링 → postgres·redis (점선) | exporter 가 지표를 읽는다 | `docker-compose.admin.yml:167-290` | 렌더 |
