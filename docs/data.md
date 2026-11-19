# 데이터 카드

이 저장소는 데이터를 담지 않는다. 실행에 쓰는 자료는 모두 사용하는 사람이 직접 받거나 만든다.

## 경로 엔진 그래프 (OSRM, 선택 기능)

| 항목 | 내용 |
|---|---|
| 출처 | OpenStreetMap 기여자들이 만든 지도 자료의 대한민국 추출본(배포처에서 직접 받는다) |
| 이용조건 | OpenStreetMap 자료는 ODbL 1.0 을 따른다. 파생 자료(그래프)를 배포하면 ODbL 의무가 따른다. 표시할 때 "© OpenStreetMap contributors" 를 밝힌다 |
| 이 저장소에 담는가 | 담지 않는다. 원본 `.pbf` 와 그래프(`*.osrm*`)는 `.gitignore` 로 막는다 |
| 만드는 법 | `scripts/osrm-rebuild.sh` → `scripts/osrm-release.py build`. 고정한 원본 파일·제공자 체크섬·새 빌드 볼륨·출력 디렉터리를 반드시 준다. 이미 쓰는 서빙 볼륨은 빌드 대상으로 받지 않는다 |
| 쓰는 곳 | `docker-compose.yml` 의 `osrm-foot`·`osrm-bicycle`(routing 프로필)이 `osrm-data` 볼륨의 `/foot`·`/bicycle/korea.osrm` 을 읽기 전용으로 붙인다. hub 는 `MAP_PROJECT_OSRM_FOOT_BASE_URL`·`MAP_PROJECT_OSRM_BICYCLE_BASE_URL` 를 채웠을 때만 부른다 |
| 확인 | `scripts/osrm-acceptance.py` 가 공개 지점 좌표로 도로를 따르는 경로가 나오는지 본다(사용자 자료를 쓰지 않는다) |
| 한계 | 그래프는 원본 판에 묶인다. 원본을 바꾸면 다시 만들어야 하고, 같은 그래프를 다시 받을 수 있다는 보장이 없다 |

## 성향별 저장 비율 통계 (선택 기능)

| 항목 | 내용 |
|---|---|
| 무엇 | 성향 묶음(연령대·성별) × 장소별로 "보여 준 횟수" 와 "저장까지 간 횟수" 를 센 비율 파일. agent 가 후보 랭킹에 조금 얹는다 |
| 만드는 법 | 쌓인 세션 자료로 agent 의 `eval/segment_stats.py` 가 만든다. 표본이 문턱보다 적은 칸은 내보내지 않는다(한 사람을 가리키게 되는 것을 막는다) |
| 이 저장소에 담는가 | 담지 않는다. `segstats/` 에 두면 agent 가 읽기 전용으로 붙여 쓴다(`segstats/.gitignore` 가 파일을 막는다). 경로는 `AGENT_SEGMENT_STATS_PATH` |
| 한계 | 공개본에는 쌓인 세션 자료가 없으므로 이 파일도 없다. 없으면 랭킹은 통계 없이 돈다 |

## DB 스키마

| 스키마 | 소유 역할 | 쓰는 서비스 |
|---|---|---|
| `user_service` | `map_user_owner` | user(실행 역할 `map_user_runtime`) |
| `hub_data` | `map_hub_owner` | hub(실행 역할 `map_hub_runtime`), 관리 콘솔은 읽기만 |
| `langgraph` | `map_agent_owner` | agent 체크포인터(기본 꺼짐) |
| `admin_data` | `map_admin` | 관리 콘솔 |

표 구조는 각 서비스 저장소의 마이그레이션이 정한다. 이 저장소는 스키마·역할·권한을 만드는 순서만 갖는다(`db/setup/`).

## 비공개 운영 자료와의 비호환

공개본은 비공개 개발본과 이름(저장소·이미지·환경변수·볼륨)이 다르고, 비공개 운영의 스냅숏·백업·설정과 호환되지 않는다. 공개본은 언제나 빈 데이터 볼륨에서 시작한다.
