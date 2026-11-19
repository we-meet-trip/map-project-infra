#!/bin/sh
# user 부트스트랩 진입점을 감싼다(user 이미지 안에서 돈다).
#
# 1) 준비 단계가 이번에 새로 연 경우에만 돈다. 이미 끝난 DB 에서 다시 돌면 거절된다.
# 2) 진입점은 정해진 이름 밖의 환경변수가 하나라도 있으면 멈춘다(허용 목록 방식).
#    Docker 가 넣는 HOSTNAME, 이미지가 넣는 JAVA_VERSION 같은 값도 지운다. 값을
#    명령줄로 다시 넘기지 않으려고 env -i 대신 지우는 쪽을 쓴다.
set -eu
[ -f /state/user-bootstrap.pending ] || { echo "user 부트스트랩: 이미 끝남 — 건너뜀"; exit 0; }
for name in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p'); do
  case "$name" in
    PATH|JAVA_HOME|HOME|LANG|LC_ALL|TZ|TMPDIR) ;;
    USER_BOOTSTRAP_URL|USER_BOOTSTRAP_USERNAME|USER_BOOTSTRAP_PASSWORD|USER_BOOTSTRAP_EXPECTED_DATABASE|USER_BOOTSTRAP_MARKER) ;;
    *) unset "$name" 2>/dev/null || true ;;
  esac
done
exec /usr/bin/env -u PWD -u OLDPWD -u SHLVL -u _ java -Xmx192m \
  -Dloader.main=map.bootstrap.UserBootstrapApplication -cp /app/app.jar \
  org.springframework.boot.loader.launch.PropertiesLauncher bootstrap
