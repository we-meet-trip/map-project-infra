#!/usr/bin/env bash
# 로컬 기동 2단계: user-BFF 를 호스트 JVM 으로 실행(gradlew bootRun, 포그라운드).
# 도커 백엔드의 "호스트 포트"(agent:8000/hub:8001/pg:5432/redis:16379)에 연결한다.
set -uo pipefail

# INFRA_DIR = map-project-infra(.env 소유). MAP_ROOT = 그 상위(형제 레포 map-project-user 접근용).
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP_ROOT="$(cd "$INFRA_DIR/.." && pwd)"
ENVF="$INFRA_DIR/.env"
[ -f "$ENVF" ] || { echo "✗ $ENVF 없음"; exit 1; }

# 8080 선점 시 중복 기동을 막는다.
if lsof -ti:8080 >/dev/null 2>&1; then
  echo "✗ 8080 사용 중. 먼저 ./map-down.sh 로 정리하세요."; exit 1
fi
# 동기 facade 는 요청 처리 중 agent·hub 를 호출하므로 백엔드 준비를 선검사.
for pair in "hub:8001" "agent:8000"; do
  port="${pair##*:}"
  if [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/health")" != "200" ]; then
    echo "✗ ${pair%%:*}(:$port) 미응답. 먼저 ./map-up-1-backend.sh 실행."; exit 1
  fi
done

# 컨테이너로 띄울 때 compose 가 user 에 넣는 값을 그대로 렌더해 내보낸다. 그래야 실행
# 방식(도커·호스트 JVM)에 따라 같은 코드가 다른 설정으로 도는 일이 없다 — 예전에는
# 이 길로 띄우면 내부 토큰이 빠져 추천 호출이 전부 401 이었다. 값은 화면에 찍지 않는다.
# 호스트에서 도므로 컨테이너 DNS 대신 호스트 포트를 쓴다:
# postgres 5432, redis 16379(컨테이너 6379), agent 8000, hub 8001.
exports=$(docker compose --env-file "$ENVF" -f "$INFRA_DIR/docker-compose.yml" --profile full config --format json \
  | python3 -c '
import json, shlex, sys
env = json.load(sys.stdin)["services"]["user"]["environment"]
env.update({"MAP_PROJECT_POSTGRES_HOST": "localhost", "MAP_PROJECT_POSTGRES_PORT": "5432",
            "USER_REDIS_HOST": "localhost", "USER_REDIS_PORT": "16379",
            "MAP_PROJECT_AGENT_BASE_URL": "http://localhost:8000", "MAP_PROJECT_HUB_BASE_URL": "http://localhost:8001"})
for key, value in sorted(env.items()):
    # 빈 값은 설정 파일의 기본값을 이기고 형 변환에서 기동을 깨뜨리므로 내보내지 않는다.
    if value not in (None, ""):
        print("export %s=%s" % (key, shlex.quote(str(value))))
') || { echo "✗ compose 설정을 렌더하지 못했다(.env 확인)"; exit 1; }
eval "$exports"

echo "== BFF bootRun(8080) — 'Started UserApplication' 출력 시 준비. 종료 Ctrl+C =="
cd "$MAP_ROOT/map-project-user"
# exec 로 현재 셸을 대체 → Ctrl+C(SIGINT)가 gradle/JVM 에 직접 전달된다.
exec ./gradlew bootRun --console=plain
