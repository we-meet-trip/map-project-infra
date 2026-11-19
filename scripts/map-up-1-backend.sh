#!/usr/bin/env bash
# 로컬 기동 1단계: 도커 백엔드 기동(postgres·redis·DB 준비 사슬·hub·agent).
# 헬스 게이트 통과 후 종료(컨테이너는 detached 로 계속 실행).
set -uo pipefail

# INFRA_DIR = map-project-infra (compose/.env 소유). 스크립트 위치 기준이라 cwd 무관.
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$INFRA_DIR/docker-compose.yml")
ENVF="$INFRA_DIR/.env"

echo "== [0/3] 사전 점검 (Docker 데몬 · .env) =="
# Docker 데몬이 꺼져 있으면 이후 모든 compose 호출이 실패하므로 선제 차단.
if ! docker info >/dev/null 2>&1; then
  echo "  ✗ Docker 데몬 꺼짐. Docker Desktop 실행 후 재시도: open -a Docker"; exit 1
fi
# 비밀번호·토큰·암호 열쇠는 생성 스크립트가 만든다. 외부 키는 필요 없다 — 모델은
# 합성 제공자(AGENT_LLM_PROVIDER=fake)가 기본이고 hub 는 키가 없으면 스텁으로 답한다.
[ -f "$ENVF" ] || { echo "  ✗ $ENVF 없음. 먼저 ./scripts/make-local-env.sh 를 실행한다."; exit 1; }
echo "  ✓ Docker 가동 · .env 존재"

echo "== [1/3] postgres · redis 기동 =="
"${COMPOSE[@]}" up -d postgres redis

echo "== [2/3] DB 준비 사슬 + hub · agent 빌드·기동 =="
# 항상 빌드한다. 도커는 바뀐 것이 없으면 캐시로 즉시 끝내므로 반복 기동이
# 느려지지 않는다. 예전 이미지가 그대로 떠서 고친 것이 반영되지 않는 상태는
# 겉으로 드러나지 않는다 — 컨테이너는 정상이고 로그도 조용하다.
# MAP_SKIP_BUILD=1 을 주면 빌드를 건너뛴다(소스를 건드리지 않은 것이 확실할 때만).
#
# hub 는 빈 DB 준비 사슬(db-* · user-db-* · hub-db-migrate)이 끝난 뒤에 뜬다. 사슬은
# user 이미지로 user 스키마를 먼저 만들므로 user 이미지도 함께 빌드된다. 두 번째
# 기동부터 사슬은 할 일 없이 지나간다.
build=(--build); [ "${MAP_SKIP_BUILD:-0}" = "1" ] && build=()
"${COMPOSE[@]}" --profile backend up -d "${build[@]}" hub agent

echo "== [3/3] 헬스 체크 =="
fail=0
for pair in "hub:8001" "agent:8000"; do
  name="${pair%%:*}"; port="${pair##*:}"; ok=0
  for i in $(seq 1 20); do
    if [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/health")" = "200" ]; then
      echo "  ✓ $name (:$port) 200"; ok=1; break
    fi
    sleep 3
  done
  if [ "$ok" != 1 ]; then
    echo "  ✗ $name (:$port) 헬스 실패. 로그: docker compose -f \"$INFRA_DIR/docker-compose.yml\" logs $name"
    fail=1
  fi
done
[ "$fail" = 0 ] || exit 1

echo ""
echo "== ✅ 백엔드 준비 완료. 다음(별도 터미널): map-up-2-bff.sh =="
