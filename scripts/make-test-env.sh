#!/usr/bin/env bash
# 시험 스택용 .env.test 를 만든다.
#
# 원본은 반드시 .env.example 이다. .env 를 원본으로 삼으면 실제 발급처 키가
# 시험 스택으로 새어 들어가고, 그러면 시험이 실제 계정의 하루 한도를 대신 태운다.
# 원본을 example 로 고정하는 것이 그 사고를 구조적으로 막는 방법이라 선택지를
# 두지 않는다.
#
# 비밀번호·토큰·암호 열쇠는 로컬 생성기(make-local-env.sh)가 만든다. 여기서는
# 시험 스택만의 값(DB 이름, 인증 켜기, 스텁, 서명 열쇠, 저장소 비밀번호, 시험 계정)을
# 얹는다. 다시 만들어도(--force) 이미 있는 비밀번호·열쇠와 손으로 넣은 값은 옮겨
# 온다 — 저장소는 처음 초기화될 때의 비밀번호를 볼륨에 새겨 두고, 좌표 열쇠를 바꾸면
# 그 열쇠로 봉한 값을 영영 읽지 못한다.
#
# 사용: ./scripts/make-test-env.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."
DST=.env.test
if [ -f "$DST" ] && [ "${1:-}" != "--force" ]; then
  echo "이미 있다: $DST (덮어쓰려면 --force — 비밀번호와 열쇠는 옮겨 온다)" >&2
  exit 1
fi
command -v openssl >/dev/null || { echo "openssl 이 필요하다" >&2; exit 1; }
OLD=$(mktemp); TMP=$(mktemp)
trap 'rm -f "$OLD" "$TMP"' EXIT
[ -f "$DST" ] && cp "$DST" "$OLD"

# (1) 비밀값은 로컬 생성기로. DB 이름만 시험용으로 갈라 둔다.
MAP_PROJECT_ENV_FILE=$DST MAP_PROJECT_ENV_DB=map_test ./scripts/make-local-env.sh --force >/dev/null
cp "$DST" "$TMP"

set_kv() {  # 값 하나를 바꾼다. 키가 없으면 끝에 붙인다.
  local key=$1 val=$2 out
  if grep -qE "^${key}=" "$TMP"; then
    out=$(awk -v k="$key" -v v="$val" 'BEGIN{FS=OFS="="} $1==k {print k "=" v; next} {print}' "$TMP")
    printf '%s\n' "$out" > "$TMP"
  else
    printf '%s=%s\n' "$key" "$val" >> "$TMP"
  fi
}
prev() { [ -s "$OLD" ] && grep -E "^$1=" "$OLD" | head -1 | cut -d= -f2- | tr -d '\r' || true; }

# (2) 외부 호출을 전부 스텁으로 돌린다. 키가 비어도 스텁으로 떨어지지만, 그 경우와
#     의도적으로 끈 경우를 로그에서 가를 수 없어 명시한다.
set_kv HUB_PLACES_STUB_MODE true

# (3) 오버레이가 요구하는 표식. 이 값이 없으면 시험 오버레이가 뜨지 않는다.
set_kv MAP_PROJECT_STACK_ENV test

# (4) 서명 열쇠 한 쌍. 인증을 켜면 이 값이 비어 있을 때 BFF 가 부팅하지 않는다.
jwt_priv=$(prev USER_JWT_PRIVATE_KEY); jwt_pub=$(prev USER_JWT_PUBLIC_KEY)
if [ -z "$jwt_priv" ] || [ -z "$jwt_pub" ]; then
  KEYDIR=$(mktemp -d)
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$KEYDIR/k.pem" 2>/dev/null
  openssl rsa -in "$KEYDIR/k.pem" -pubout -out "$KEYDIR/k.pub" 2>/dev/null
  # 설정 파일은 한 줄이어야 하므로 머리말과 줄바꿈을 걷어 낸다.
  jwt_priv=$(grep -v -- '-----' "$KEYDIR/k.pem" | tr -d '\n')
  jwt_pub=$(grep -v -- '-----' "$KEYDIR/k.pub" | tr -d '\n')
  rm -rf "$KEYDIR"
fi
set_kv USER_JWT_PRIVATE_KEY "$jwt_priv"
set_kv USER_JWT_PUBLIC_KEY "$jwt_pub"

# (5) 인증을 켠 채로 만든다. 시험만 꺼 두면 토큰을 싣지 않는 호출이 시험에서는
#     통과하고 켠 환경에서만 401 이 된다 — 시험이 잡으라고 있는 어긋남을 못 잡는다.
set_kv USER_AUTH_ENFORCED true
set_kv AGENT_AUTH_ENFORCED true
set_kv HUB_AUTH_ENFORCED true
# 인증을 켜면 와일드카드 출처로는 BFF 가 부팅하지 않는다. 브라우저에서 시험 API 를
# 부르는 웹 앱 출처 하나만 연다. e2e.sh 의 교차 출처 검사와 같은 값이어야 한다.
set_kv USER_CORS_ALLOWED_ORIGINS "https://app.example.com"

# (6) 저장소 비밀번호도 켠 채로 만든다. hub·agent·admin 은 URL 로 읽으므로 함께 맞춘다.
redis_pw=$(prev MAP_PROJECT_REDIS_PASSWORD); [ -n "$redis_pw" ] || redis_pw=$(openssl rand -hex 32)
set_kv MAP_PROJECT_REDIS_PASSWORD "$redis_pw"
set_kv MAP_PROJECT_REDIS_URL "redis://:${redis_pw}@redis:6379"
set_kv ADMIN_REDIS_URL "redis://:${redis_pw}@redis:6379"

# (7) 손으로 넣는 값(앞단 주소, 받아 쓸 판)은 다시 만들 때 살려 둔다.
for k in MAP_PROJECT_EDGE_DOMAIN MAP_PROJECT_EDGE_EMAIL MAP_PROJECT_IMAGE_REGISTRY MAP_PROJECT_IMAGE_TAG; do
  kept=$(prev "$k"); [ -n "$kept" ] && set_kv "$k" "$kept"
done

# (8) 시험 계정은 시험 스택에서만 켠다.
tester_pw=$(prev USER_TESTER_SEED_PASSWORD); [ -n "$tester_pw" ] || tester_pw=$(openssl rand -hex 16)
set_kv USER_TESTER_SEED_ENABLED true
set_kv USER_TESTER_SEED_PASSWORD "$tester_pw"

umask 077
cp "$TMP" "$DST"
