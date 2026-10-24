#!/usr/bin/env bash
# Access-layer tests for the meta-trade-browser image, and T21: the window the desktop
# shows while MetaTrader can't start.
#
# Each configuration runs the image on an internal Docker network, which has
# no internet: MetaTrader's first-start downloads fail at once, and the access layer
# doesn't need MetaTrader. Other containers of the same image probe it with curl and
# openssl, so no host port is used, except by --host. Everything the script
# starts is removed when it ends.
#
# Usage: tests/access.sh [--host] [image]
#   --host  also run T15, host networking on the host's 127.0.0.1:3911. It
#           binds a port on this machine, so it runs only when asked.
#   image   defaults to meta-trade-browser:dev.
set -euo pipefail

host_test=no
if [[ "${1:-}" == --host ]]; then
  host_test=yes
  shift
fi
image="${1:-meta-trade-browser:dev}"

run="mt-access-$$"
net="$run-net"
tmp="$(mktemp -d)"
user=trader
password='access-test-password-1'
key='dGhlIHNhbXBsZSBub25jZQ=='
passes=0
failures=0

cleanup() {
  docker ps -aq --filter "name=^$run-" | xargs -r docker rm -f > /dev/null 2>&1 || true
  docker network rm "$net" > /dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

pass() {
  passes=$((passes + 1))
  printf '  ok    %s\n' "$1"
}
fail() {
  failures=$((failures + 1))
  printf '  FAIL  %s\n' "$1"
}
# check <description> <expected> <actual>
check() {
  if [[ "$3" == "$2" ]]; then
    pass "$1"
  else
    fail "$1: expected '$2', got '$3'"
  fi
}
# check_true <description> <command...>
check_true() {
  local description="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    pass "$description"
  else
    fail "$description"
  fi
}

# The compose example's hardening, so the tests see what users run.
hardening=(
  --memory 1g --cpus 1 --pids-limit 1024 --shm-size 256m
  --security-opt no-new-privileges:true
  --cap-drop ALL
  --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER
  --cap-add SETUID --cap-add SETGID --cap-add KILL
)
# A password file as echo writes it, with a line break at the end.
printf '%s\n' "$password" > "$tmp/password"
printf '%s' 'only8chr' > "$tmp/short"
printf '%s' 'securepassword' > "$tmp/placeholder"
: > "$tmp/docker.sock"
with_password=(-v "$tmp/password:/run/secrets/password:ro" -e FILE__PASSWORD=/run/secrets/password)
# A certificate of your own, and a key that doesn't belong to it.
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=mt-access-test \
  -keyout "$tmp/tls.key" -out "$tmp/tls.crt" 2> /dev/null
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$tmp/other.key" 2> /dev/null
own_cert=(-v "$tmp/tls.crt:/config/ssl/cert.pem:ro" -v "$tmp/tls.key:/config/ssl/cert.key:ro")

# start <network> <name> [docker run options...]
start() {
  local network="$1" name="$run-$2"
  shift 2
  docker run -d --name "$name" --network "$network" "${hardening[@]}" "$@" "$image" > /dev/null
}

# health <name> [path]: the status of a request to the container's health-check
# server, on its socket file. The path defaults to /healthz.
health() {
  docker exec "$run-$1" curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    --unix-socket /run/mt/health.sock "http://localhost${2:-/healthz}" 2> /dev/null || true
}

# until_health <name> <status>: waits up to 60 s for the health check to answer
# that status; succeeds if it did.
until_health() {
  local _
  for _ in $(seq 1 60); do
    [[ "$(health "$1")" == "$2" ]] && return 0
    sleep 1
  done
  return 1
}

# ready <name>: waits until the health check answers 200: nginx is up, and
# Selkies answers through it.
ready() {
  local name="$run-$1" _
  for _ in $(seq 1 90); do
    if [[ "$(docker inspect -f '{{.State.Running}}' "$name" 2> /dev/null)" != true ]]; then
      fail "$1 stopped: $(docker logs "$name" 2>&1 | grep 'mt-access' | tr '\n' ' ')"
      return 1
    fi
    if [[ "$(health "$1")" == 200 ]]; then
      return 0
    fi
    sleep 1
  done
  fail "$1 wasn't ready after 90 s"
  return 1
}

# refused <description> <text in the REFUSED line> [docker run options...]:
# the container must stop, and its log must name the reason. It starts at
# once, and refusals_checked checks it: the refusals all start together,
# rather than one after another.
refusals=()
refused() {
  local name="$run-refused-$((${#refusals[@]} / 3))"
  docker run -d --name "$name" --network "$net" "${hardening[@]}" "${@:3}" "$image" > /dev/null
  refusals+=("$name" "$1" "$2")
}

# refusals_checked: checks the containers refused started, in order. Each gets
# up to 60 s to stop.
refusals_checked() {
  local i name description text state reason
  for ((i = 0; i < ${#refusals[@]}; i += 3)); do
    name="${refusals[i]}" description="${refusals[i + 1]}" text="${refusals[i + 2]}"
    timeout 60 docker wait "$name" > /dev/null 2>&1 || true
    state="$(docker inspect -f '{{.State.Status}}' "$name")"
    reason="$(docker logs "$name" 2>&1 | grep -F '[mt-access] REFUSED:' || true)"
    if [[ "$state" == exited ]] && grep -qF -- "$text" <<< "$reason"; then
      pass "$description"
    else
      fail "$description: state '$state', reason '${reason:-none}'"
    fi
    docker rm -f "$name" > /dev/null 2>&1 || true
  done
  refusals=()
}

# code [--from <probe>] <curl options and URL...>: the HTTP status, 000 when
# nothing answers.
code() {
  local from=probe
  if [[ "$1" == --from ]]; then
    from="$2"
    shift 2
  fi
  docker exec "$run-$from" curl -sk --http1.1 -o /dev/null -w '%{http_code}' --max-time 5 "$@" || true
}

# ws <host:port> <path> <origin>: the status of a stream handshake.
ws() {
  code -u "$user:$password" --max-time 3 \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' -H "Sec-WebSocket-Key: $key" \
    -H "Origin: $3" "https://$1$2"
}

# security_headers <curl options and URL...>: succeeds when all four are there.
# Only the desktop's own page may frame it (its file panel is a frame).
security_headers() {
  local headers
  headers="$(docker exec "$run-probe" curl -sk -D - -o /dev/null --max-time 5 "$@" | tr -d '\r')"
  grep -qx "Content-Security-Policy: frame-ancestors 'self'" <<< "$headers" &&
    grep -qx 'X-Frame-Options: SAMEORIGIN' <<< "$headers" &&
    grep -qx 'X-Content-Type-Options: nosniff' <<< "$headers" &&
    grep -qx 'Referrer-Policy: no-referrer' <<< "$headers"
}

# logged <name> <text>: succeeds when the container's log has the text. The
# log is read in full first: under pipefail, "docker logs | grep -q" can fail
# when grep stops early and docker logs gets SIGPIPE.
logged() {
  local logs
  logs="$(docker logs "$run-$1" 2>&1)"
  grep -qF -- "$2" <<< "$logs"
}

# listeners <name>: the container's listening TCP and UDP sockets, as
# hexadecimal address:port, without Docker's DNS server on 127.0.0.11.
listeners() {
  docker exec "$run-$1" sh -c '
    for f in tcp tcp6; do awk "NR > 1 && \$4 == \"0A\" { print \$2 }" /proc/net/$f; done
    for f in udp udp6; do awk "NR > 1 { print \$2 }" /proc/net/$f; done' |
    grep -v '^0B00007F:' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

ip_of() {
  docker inspect -f "{{(index .NetworkSettings.Networks \"$net\").IPAddress}}" "$run-$1"
}

# cert_field <name> <openssl x509 options...>: one field of the container's own
# certificate, the value only.
cert_field() {
  docker exec "$run-$1" openssl x509 -in /config/ssl/cert.pem -noout "${@:2}" | tail -n 1 | sed 's/^ *//'
}

# cert_days <name>: how many days the container's own certificate is valid.
cert_days() {
  docker exec "$run-$1" sh -c '
    s=$(date -d "$(openssl x509 -in /config/ssl/cert.pem -noout -startdate | cut -d= -f2)" +%s)
    e=$(date -d "$(openssl x509 -in /config/ssl/cert.pem -noout -enddate | cut -d= -f2)" +%s)
    echo $(((e - s) / 86400))'
}

# selkies_env <name> <regex>: the variables in Selkies' environment that match,
# sorted, on one line.
selkies_env() {
  local pid
  pid="$(docker exec "$run-$1" pgrep -o -f 'selkies --addr')"
  docker exec -u abc "$run-$1" sh -c "tr '\0' '\n' < /proc/$pid/environ | grep -E '$2' | sort | paste -s -d ' '"
}

# trusted <URL> <curl options...>: the HTTP status with the probe trusting
# only /tmp/main.pem, the main container's own certificate. 000 when the
# certificate isn't accepted for that name.
trusted() {
  docker exec "$run-probe" curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    --cacert /tmp/main.pem "${@:2}" "$1" || true
}

# notice_window <name>: the window the desktop shows while MetaTrader can't
# start (notice.py), as "<how many> framed|unframed small|full
# centred|off centre by <x>,<y>". Small means its frame, title bar included, is
# smaller than the screen: openbox marks every window maximized, as it does
# MetaTrader's dialogs, but a fixed size keeps them small. Centred means the
# frame, to 2 px. Asked again for up to 10 s until it's "1 framed small
# centred": after a failed step, the window closes and opens again every 60 s.
# Its position comes from xwininfo: xdotool's counts the frame's offset twice.
notice_window() {
  local window _
  for _ in $(seq 1 10); do
    window="$(docker exec "$run-$1" sh -c '
      set -- $(xdotool search --onlyvisible --classname "^mt-notice\$")
      [ $# -gt 0 ] || { echo 0; exit; }
      count=$#
      id=$1
      extents="$(xprop -id "$id" _NET_FRAME_EXTENTS | sed -n "s/.* = //p" | tr -d ,)"
      framed=framed
      [ -n "$extents" ] || { framed=unframed; extents="0 0 0 0"; }
      set -- $(xwininfo -id "$id" | awk "
        /Absolute upper-left X/ { x = \$NF } /Absolute upper-left Y/ { y = \$NF }
        /^ *Width:/ { w = \$NF } /^ *Height:/ { h = \$NF } END { print x, y, w, h }")
      x=$1 y=$2 w=$3 h=$4
      set -- $extents $(xdotool getdisplaygeometry)
      size=small
      if [ $((w + $1 + $2)) -ge "$5" ] || [ $((h + $3 + $4)) -ge "$6" ]; then size=full; fi
      dx=$(((2 * x + w - $1 + $2 - $5) / 2))
      dy=$(((2 * y + h - $3 + $4 - $6) / 2))
      place=centred
      if [ "${dx#-}" -gt 2 ] || [ "${dy#-}" -gt 2 ]; then place="off centre by $dx,$dy"; fi
      echo "$count $framed $size $place"' 2> /dev/null || true)"
    [[ "$window" == "1 framed small centred" ]] && break
    sleep 1
  done
  printf '%s' "$window"
}

echo "Image: $image"
docker network create --internal "$net" > /dev/null
for probe in probe probe2; do
  docker run -d --name "$run-$probe" --network "$net" --memory 256m \
    --cap-drop ALL --security-opt no-new-privileges:true \
    --entrypoint sleep "$image" infinity > /dev/null
done

echo "T1, T10: settings that must stop the container"
refused "T1: no password" "no password"
refused "T1: 8 characters" "shorter than 12 characters" \
  -v "$tmp/short:/run/secrets/password:ro" -e FILE__PASSWORD=/run/secrets/password
refused "T1: unreadable password file" "can't be read" -e FILE__PASSWORD=/run/secrets/missing
refused "T1: placeholder" "well-known placeholder" \
  -v "$tmp/placeholder:/run/secrets/password:ro" -e FILE__PASSWORD=/run/secrets/password
refused "T10: SELKIES_ALLOWED_ORIGINS=*" "includes '*'" "${with_password[@]}" -e 'SELKIES_ALLOWED_ORIGINS=*'
refused "T10: TRUSTED_PROXIES=0.0.0.0/0" "covers every address" "${with_password[@]}" -e TRUSTED_PROXIES=0.0.0.0/0
refused "T10: TRUSTED_PROXIES=::/0" "covers every address" "${with_password[@]}" -e TRUSTED_PROXIES=::/0
refused "T10: TRUSTED_PROXIES that isn't an address" "isn't an IP address" "${with_password[@]}" -e TRUSTED_PROXIES=proxy.example
refused "T10: DEV_MODE" "DEV_MODE is set" "${with_password[@]}" -e DEV_MODE=1
refused "T10: PIXELFLUX_WAYLAND=true" "PIXELFLUX_WAYLAND=true" "${with_password[@]}" -e PIXELFLUX_WAYLAND=true
refused "T10: SELKIES_MODE=webrtc" "WebRTC streaming" "${with_password[@]}" -e SELKIES_MODE=webrtc
refused "T10: SELKIES_ENABLE_DUAL_MODE=true" "WebRTC streaming" "${with_password[@]}" -e SELKIES_ENABLE_DUAL_MODE=true
refused "T10: SELKIES_COMPUTER_USE_BIND" "SELKIES_COMPUTER_USE_BIND" "${with_password[@]}" -e SELKIES_COMPUTER_USE_BIND=8090
refused "T10: another SELKIES_UNIX_SOCKET" "SELKIES_UNIX_SOCKET must stay" "${with_password[@]}" -e SELKIES_UNIX_SOCKET=/tmp/other.sock
refused "T10: SELKIES_ENABLE_BASIC_AUTH=true" "SELKIES_ENABLE_BASIC_AUTH=true" "${with_password[@]}" -e SELKIES_ENABLE_BASIC_AUTH=true
refused "T10: the Docker socket mounted" "Docker socket is mounted" "${with_password[@]}" -v "$tmp/docker.sock:/var/run/docker.sock:ro"
refused "T10: SYS_ADMIN (privileged)" "CAP_SYS_ADMIN" "${with_password[@]}" --cap-add SYS_ADMIN
refused "T10: only TLS_CERT_FILE (deprecated)" "only one of TLS_CERT_FILE" "${with_password[@]}" -e TLS_CERT_FILE=/config/ssl/cert.pem
refused "T10: a certificate and a key that don't belong together" "don't belong together" "${with_password[@]}" \
  -v "$tmp/tls.crt:/config/ssl/cert.pem:ro" -v "$tmp/other.key:/config/ssl/cert.key:ro"
refused "T10: a certificate without its key" "cert.pem and cert.key must both be there" "${with_password[@]}" \
  -v "$tmp/tls.crt:/config/ssl/cert.pem:ro"
refused "T10: LISTEN_ADDRESS that isn't an address" "LISTEN_ADDRESS must be one IP address" "${with_password[@]}" -e LISTEN_ADDRESS=all
refused "T10: SUBFOLDER without slashes" "SUBFOLDER must start and end with '/'" "${with_password[@]}" -e SUBFOLDER=mt
refused "T10: SELKIES_FILE_TRANSFERS=off" "SELKIES_FILE_TRANSFERS must be" "${with_password[@]}" -e SELKIES_FILE_TRANSFERS=off
refused "T10: SELKIES_FILE_TRANSFERS=none|locked" "SELKIES_FILE_TRANSFERS must be" "${with_password[@]}" -e 'SELKIES_FILE_TRANSFERS=none|locked'
refused "T10: SELKIES_CLIPBOARD_ENABLED=off" "SELKIES_CLIPBOARD_ENABLED must be" "${with_password[@]}" -e SELKIES_CLIPBOARD_ENABLED=off
refusals_checked

echo "Defaults (T2, T3, T5-T8, T13, T14, T16, T17, T19-T21)"
start "$net" main "${with_password[@]}"
if ready main; then
  t="$run-main:3001"
  check "T2: no login" 401 "$(code "https://$t/")"
  check "T2: login" 200 "$(code -u "$user:$password" "https://$t/")"
  check "T2: wrong password" 401 "$(code -u "$user:${password}x" "https://$t/")"
  check_true "T2: the four headers on a 401" security_headers "https://$t/"
  check_true "T2: the four headers on a 200" security_headers -u "$user:$password" "https://$t/"
  check_true "T2: a password file ending in a line break works, and the log says so" logged main "ends in a line break"
  check "T3: nothing on port 3000" 000 "$(code "http://$run-main:3000/")"
  check "T4: without TRUSTED_PROXIES, a second address also gets the login" 401 "$(code --from probe2 "https://$t/")"
  check "T5: stream from its own origin" 101 "$(ws "$t" /api/websockets "https://$t")"
  check "T5: stream from another port on the same host" 403 "$(ws "$t" /api/websockets "https://$run-main:3002")"
  check "T5: stream from another site" 403 "$(ws "$t" /api/websockets https://evil.example)"
  check "T6: POST /api/recording from another site" 403 \
    "$(code -u "$user:$password" -X POST -H 'Origin: https://evil.example' "https://$t/api/recording")"
  check "T7: /devmode" 404 "$(code -u "$user:$password" "https://$t/devmode")"
  check "T7: /pelorus/" 404 "$(code -u "$user:$password" "https://$t/pelorus/")"
  check "T8: POST /api/upload with transfers off" 403 \
    "$(code -u "$user:$password" -X POST -H "Origin: https://$t" -F 'file=@/etc/hostname' "https://$t/api/upload")"
  check "T8: GET /api/files/ with transfers off" 403 \
    "$(code -u "$user:$password" -H "Origin: https://$t" "https://$t/api/files/")"
  if docker exec -u abc "$run-main" sudo -n true > /dev/null 2>&1; then
    fail "T13: sudo works for the desktop user"
  else
    pass "T13: no sudo for the desktop user"
  fi
  check "T13: runnable terminals" "" "$(docker exec -u abc "$run-main" sh -c '
    for n in xterm st stterm uxterm lxterminal gnome-terminal konsole xfce4-terminal terminator foot weston-terminal; do
      p=$(command -v "$n" 2> /dev/null) && [ -x "$p" ] && echo "$n"
    done; true')"
  # By the programs the menu runs: MetaTrader's own terminal64.exe isn't a terminal.
  check "T13: terminals in the menu" 0 \
    "$(docker exec "$run-main" sh -c 'sed -n "s|.*<command>\([^ <]*\).*|\1|p" /config/.config/openbox/menu.xml |
      xargs -r -n 1 basename |
      grep -c -x -E "xterm|st|stterm|uxterm|lxterminal|gnome-terminal|konsole|xfce4-terminal|terminator|foot|weston-terminal|x-terminal-emulator" || true')"
  check "T13: the menu's entries" "MetaTrader,MetaEditor" \
    "$(docker exec "$run-main" sh -c 'sed -n "s|.*<item label=\"\([^\"]*\)\".*|\1|p" /config/.config/openbox/menu.xml | paste -s -d ,')"
  env_json="$(docker inspect -f '{{json .Config.Env}}' "$run-main")"
  check_true "T14: docker inspect shows the password file's path" grep -qF 'FILE__PASSWORD=/run/secrets/password' <<< "$env_json"
  if grep -qF -- "$password" <<< "$env_json"; then
    fail "T14: docker inspect shows the password"
  else
    pass "T14: docker inspect doesn't show the password"
  fi
  check "T14: the plain-text password left the startup environment" no \
    "$(docker exec "$run-main" sh -c '[ -e /run/s6/container_environment/PASSWORD ] && echo yes || echo no')"
  check "T14: /config belongs to the desktop's user, 1000:1000 by default" "1000:1000" \
    "$(docker exec "$run-main" stat -c '%u:%g' /config)"
  check "T14: password file owner and mode" "640 root:www-data" "$(docker exec "$run-main" stat -c '%a %U:%G' /etc/nginx/.htpasswd)"
  check "T14: password hash type" "$user:\$6\$" "$(docker exec "$run-main" cut -c1-$((${#user} + 4)) /etc/nginx/.htpasswd)"
  selkies_pid="$(docker exec "$run-main" pgrep -o -f 'selkies --addr')"
  check "T14: Selkies' environment has no PASSWORD" 0 \
    "$(docker exec -u abc "$run-main" sh -c "tr '\0' '\n' < /proc/$selkies_pid/environ | grep -c '^PASSWORD=' || true")"
  check "T19: Selkies runs with sound, but without its own login, microphone, webcam, file transfers, or audio, video and file panels" \
    "SELKIES_AUDIO_ENABLED=true SELKIES_ENABLE_BASIC_AUTH=false SELKIES_FILE_TRANSFERS=none SELKIES_MICROPHONE_ENABLED=false|locked SELKIES_UI_SIDEBAR_SHOW_AUDIO_SETTINGS=false|locked SELKIES_UI_SIDEBAR_SHOW_FILES=false SELKIES_UI_SIDEBAR_SHOW_VIDEO_SETTINGS=false|locked SELKIES_WEBCAM_ENABLED=false|locked" \
    "$(selkies_env main '^SELKIES_((AUDIO|MICROPHONE|WEBCAM)_ENABLED|ENABLE_BASIC_AUTH|FILE_TRANSFERS|UI_SIDEBAR_SHOW_(AUDIO|VIDEO)_SETTINGS|UI_SIDEBAR_SHOW_FILES)=')"
  check "T20: the container's own certificate is issued to" "subject=O=meta-trade-browser, CN=localhost" \
    "$(cert_field main -subject)"
  check "T20: ...for these names only" "DNS:localhost, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1" \
    "$(cert_field main -ext subjectAltName)"
  check "T20: ...and can't sign others" "CA:FALSE" "$(cert_field main -ext basicConstraints)"
  check "T20: ...for TLS servers only" "TLS Web Server Authentication" "$(cert_field main -ext extendedKeyUsage)"
  check "T20: ...valid for 825 days" 825 "$(cert_days main)"
  check_true "T20: the log says it was made" logged main "[mt-cert] Made the desktop's own certificate"
  docker exec "$run-main" cat /config/ssl/cert.pem | docker exec -i "$run-probe" sh -c 'cat > /tmp/main.pem'
  main_ip="$(ip_of main)"
  check "T20: trusted, it's accepted for localhost" 401 \
    "$(trusted "https://localhost:3001/" --resolve "localhost:3001:$main_ip")"
  check "T20: trusted, it's accepted for 127.0.0.1" 401 \
    "$(trusted "https://127.0.0.1:3001/" --connect-to "127.0.0.1:3001:$main_ip:3001")"
  check "T20: trusted, it's refused for any other name" 000 \
    "$(trusted "https://mt.example.com:3001/" --resolve "mt.example.com:3001:$main_ip")"
  check "T16: listening sockets (only HTTPS on 3001)" "00000000:0BB9" "$(listeners main)"
  check "T16: listening abstract sockets" 0 \
    "$(docker exec "$run-main" sh -c 'awk "NR > 1 && \$4 == \"00010000\" && \$8 ~ /^@/" /proc/net/unix | wc -l')"
  check "T16: Selkies' socket folder and socket" "2750 abc:mtsock 775 abc:mtsock" \
    "$(docker exec "$run-main" stat -c '%a %U:%G' /run/selkies /run/selkies/selkies.sock | tr '\n' ' ' | sed 's/ $//')"
  check "T17: switching the stream to WebRTC" 403 \
    "$(code -u "$user:$password" -X POST -H "Origin: https://$t" -H 'Content-Type: application/json' -d '{"mode": "webrtc"}' "https://$t/api/switch")"
  check "Health: /healthz answers without a login" "200 ok" \
    "$(health main) $(docker exec "$run-main" curl -s --unix-socket /run/mt/health.sock http://localhost/healthz)"
  check "Health: other paths on the health socket" 404 "$(health main /)"
  check "Health: the HTTPS port is the desktop, whatever the host name" 401 \
    "$(code -H 'Host: localhost' "https://$t/")"
  docker exec "$run-main" s6-svc -d /run/service/svc-selkies
  check_true "Health: 500 while Selkies is down" until_health main 500
  docker exec "$run-main" s6-svc -u /run/service/svc-selkies
  check_true "Health: 200 once Selkies is back" until_health main 200
  docker exec "$run-main" pkill -9 nginx
  check_true "Health: nginx starts again after kill -9, despite its old socket" until_health main 200
  check "Health: the login works after nginx's restart" 200 "$(code -u "$user:$password" "https://$t/")"
  code -A access-test-agent -u "$user:$password" "https://$t/" > /dev/null
  agent_line="$(docker logs "$run-main" 2>&1 | grep -F access-test-agent || true)"
  check_true "Q5: a request is logged with its user and status" grep -q "user=$user \[.*\" 200 " <<< "$agent_line"
  if logged main 'GET /healthz'; then
    fail "Q5: health checks are logged"
  else
    pass "Q5: health checks aren't logged"
  fi
  # Offline, the first start fails at step 2, and the window says why.
  for _ in $(seq 1 120); do
    logged main "Retrying in 60 s" && break
    sleep 1
  done
  check "T21: the startup window: one, framed like MetaTrader's windows, not filling the screen, centred" \
    "1 framed small centred" "$(notice_window main)"
  # The size changes the way the desktop sets it, as when a browser connects.
  # The restart below brings the old size back.
  docker exec "$run-main" sh -c '
    mode="$(cvt 1600 900 | sed -n "s/^Modeline //p" | tr -d "\"")"
    name="${mode%% *}"
    xrandr --newmode $mode && xrandr --addmode screen "$name" && xrandr --output screen --mode "$name"' \
    > /dev/null 2>&1 || true
  check "T21: the screen changes size" "1600 900" "$(docker exec "$run-main" xdotool getdisplaygeometry)"
  check "T21: the window is centred again" "1 framed small centred" "$(notice_window main)"
  # The certificate the base makes, as its init-nginx makes it.
  docker exec -u abc "$run-main" openssl req -new -x509 -days 3650 -nodes \
    -out /config/ssl/cert.pem -keyout /config/ssl/cert.key \
    -subj "/C=US/ST=CA/L=Carlsbad/O=Linuxserver.io/OU=LSIO Server/CN=*" > /dev/null 2>&1
  docker restart "$run-main" > /dev/null
  if ready main; then
    check "Restart: the login still works" 200 "$(code -u "$user:$password" "https://$t/")"
    check "Restart: the plain-text password left the startup environment again" no \
      "$(docker exec "$run-main" sh -c '[ -e /run/s6/container_environment/PASSWORD ] && echo yes || echo no')"
    check "T20: the base's certificate is replaced at a start" "subject=O=meta-trade-browser, CN=localhost" \
      "$(cert_field main -subject)"
    check_true "T20: the log says so" logged main "[mt-cert] Replaced the base image's certificate"
  fi
fi
docker rm -f "$run-main" > /dev/null

echo "TRUSTED_PROXIES (T3, T4)"
start "$net" proxies "${with_password[@]}" -e "TRUSTED_PROXIES=$(ip_of probe)"
if ready proxies; then
  t="$run-proxies:3001"
  check "T4: the listed proxy without a login" 401 "$(code "https://$t/")"
  check "T4: the listed proxy with a login" 200 \
    "$(code -u "$user:$password" -H 'X-Forwarded-For: 203.0.113.7' "https://$t/")"
  check "T4: an unlisted address" 403 "$(code --from probe2 -u "$user:$password" "https://$t/")"
  check_true "T4: the listed proxy's X-Forwarded-For is logged" logged proxies "forwarded=203.0.113.7"
  check "T3: nothing on port 3000" 000 "$(code "http://$run-proxies:3000/")"
fi
docker rm -f "$run-proxies" > /dev/null

echo "File transfers on (T18), SELKIES_ENABLE_BASIC_AUTH empty (T19), a certificate near its expiry (T20)"
start "$net" files "${with_password[@]}" -e SELKIES_FILE_TRANSFERS=true -e SELKIES_ENABLE_BASIC_AUTH=
if ready files; then
  t="$run-files:3001"
  check "T18: SELKIES_FILE_TRANSFERS=true turns on both directions, and the file panel" \
    "SELKIES_FILE_TRANSFERS=upload,download SELKIES_UI_SIDEBAR_SHOW_FILES=true" \
    "$(selkies_env files '^SELKIES_(FILE_TRANSFERS|UI_SIDEBAR_SHOW_FILES)=')"
  check "T19: Selkies starts, its login off, when SELKIES_ENABLE_BASIC_AUTH is empty" false \
    "$(docker exec "$run-files" cat /run/s6/container_environment/SELKIES_ENABLE_BASIC_AUTH)"
  check "T18: upload" 200 \
    "$(code -u "$user:$password" -X POST -H "Origin: https://$t" -H 'X-Upload-Path: access-test.txt' \
      --data-binary @/etc/hostname "https://$t/api/upload")"
  check "T18: the file list" 200 "$(code -u "$user:$password" "https://$t/api/files/")"
  check_true "T18: the file list may be framed by the desktop's own page only" \
    security_headers -u "$user:$password" "https://$t/api/files/"
  check "T18: download" "$(docker exec "$run-probe" cat /etc/hostname)" \
    "$(docker exec "$run-probe" curl -sk --max-time 5 -u "$user:$password" "https://$t/api/files/access-test.txt" || true)"
  check "T18: the upload is in MetaTrader's Experts folder" yes \
    "$(docker exec "$run-files" sh -c '[ -f "/config/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/access-test.txt" ] && echo yes || echo no')"
  check "T18: the folder's spaces made no stray folders" no \
    "$(docker exec "$run-files" sh -c '[ -e /config/.wine/drive_c/Program ] && echo yes || echo no')"
  # The container's own certificate, 10 days from expiry.
  docker exec -u abc "$run-files" openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -noenc -days 10 \
    -subj /O=meta-trade-browser/CN=localhost -out /config/ssl/cert.pem -keyout /config/ssl/cert.key > /dev/null 2>&1
  docker restart "$run-files" > /dev/null
  if ready files; then
    check "T20: a start in its last 30 days renews it" 825 "$(cert_days files)"
    check_true "T20: the log says so" logged files "[mt-cert] Renewed the desktop's own certificate"
  fi
fi
docker rm -f "$run-files" > /dev/null

echo "Uploads with the EA folder mounted (T18)"
# Open to all, because the user running this script may not be 1000.
mkdir -m 0777 "$tmp/mql5"
start "$net" files-ro "${with_password[@]}" -e SELKIES_FILE_TRANSFERS=true -v "$tmp/mql5:/mql5:ro"
if ready files-ro; then
  check "T18: with the EA folder read-only, uploads go to MetaTrader's Experts folder" \
    "FILE_MANAGER_PATH=/config/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts" \
    "$(selkies_env files-ro '^FILE_MANAGER_PATH=')"
fi
docker rm -f "$run-files-ro" > /dev/null
start "$net" files-ea "${with_password[@]}" -e SELKIES_FILE_TRANSFERS=true -v "$tmp/mql5:/mql5"
if ready files-ea; then
  t="$run-files-ea:3001"
  check "T18: with the EA folder writable, uploads go to its Experts" "FILE_MANAGER_PATH=/mql5/Experts" \
    "$(selkies_env files-ea '^FILE_MANAGER_PATH=')"
  check_true "T18: the log says so" logged files-ea "File transfers: upload,download, in /mql5/Experts."
  check "T18: upload into the EA folder" 200 \
    "$(code -u "$user:$password" -X POST -H "Origin: https://$t" -H 'X-Upload-Path: access-test.txt' \
      --data-binary @/etc/hostname "https://$t/api/upload")"
  check "T18: the upload is in the EA folder on the host" yes \
    "$([[ -f "$tmp/mql5/Experts/access-test.txt" ]] && echo yes || echo no)"
  # The desktop's user owns what it made there, so root removes it.
  docker exec "$run-files-ea" find /mql5 -mindepth 1 -delete
fi
docker rm -f "$run-files-ea" > /dev/null

echo "CUSTOM_PORT, PASSWORD and FILE_MANAGER_PATH (T3, warnings)"
start "$net" plain -e CUSTOM_PORT=3000 -e "PASSWORD=$password" -e FILE_MANAGER_PATH=/config/uploads
if ready plain; then
  check "T3: nothing on port 3000 with CUSTOM_PORT=3000" 000 "$(code "http://$run-plain:3000/")"
  check_true "CUSTOM_PORT is warned about" logged plain "CUSTOM_PORT is set, but there is no plain HTTP"
  check_true "PASSWORD given directly is warned about" logged plain "PASSWORD is set directly"
  check "FILE_MANAGER_PATH (deprecated) is still honoured" "FILE_MANAGER_PATH=/config/uploads" \
    "$(selkies_env plain '^FILE_MANAGER_PATH=')"
  check_true "FILE_MANAGER_PATH is warned about, with its removal date" logged plain \
    "FILE_MANAGER_PATH is deprecated, and images from 2026-12-22 on ignore it"
  check "the login works with PASSWORD" 200 "$(code -u "$user:$password" "https://$run-plain:3001/")"
fi
docker rm -f "$run-plain" > /dev/null

# tls <name> [openssl s_client options]: what s_client prints. It prints "New,
# <protocol>, Cipher is <cipher>" for a handshake that worked, and "New, (NONE),
# Cipher is (NONE)" for one that didn't. Its session summary names the attempted
# protocol either way.
tls() {
  docker exec "$run-probe" sh -c "echo | openssl s_client -connect $run-$1:3001 ${2:-} 2>&1" || true
}

echo "A certificate of your own mounted in /config/ssl (T9)"
start "$net" tls "${with_password[@]}" "${own_cert[@]}"
if ready tls; then
  check_true "T9: the mounted certificate is served" grep -q 'subject=.*CN *= *mt-access-test' <<< "$(tls tls)"
  check_true "T9: TLS 1.2 accepted" grep -q '^New, TLSv1.2, Cipher is [A-Z]' <<< "$(tls tls -tls1_2)"
  check_true "T9: TLS 1.3 accepted" grep -q '^New, TLSv1.3, Cipher is [A-Z]' <<< "$(tls tls -tls1_3)"
  check_true "T9: TLS 1.1 refused" grep -q '^New, (NONE), Cipher is (NONE)' <<< "$(tls tls '-tls1_1 -cipher DEFAULT@SECLEVEL=0')"
  check_true "T9: the log says it's yours" logged tls "Certificate: yours, in /config/ssl."
  docker restart "$run-tls" > /dev/null
  if ready tls; then
    check_true "T9: still served after a restart" grep -q 'subject=.*CN *= *mt-access-test' <<< "$(tls tls)"
  fi
fi
docker rm -f "$run-tls" > /dev/null

echo "TLS_CERT_FILE and TLS_KEY_FILE, deprecated (T9)"
start "$net" tls-env "${with_password[@]}" \
  -v "$tmp/tls.crt:/run/secrets/tls.crt:ro" -v "$tmp/tls.key:/run/secrets/tls.key:ro" \
  -e TLS_CERT_FILE=/run/secrets/tls.crt -e TLS_KEY_FILE=/run/secrets/tls.key
if ready tls-env; then
  check_true "T9: the given certificate is served" grep -q 'subject=.*CN *= *mt-access-test' <<< "$(tls tls-env)"
  check_true "T9: they're warned about, with their removal date" logged tls-env \
    "TLS_CERT_FILE and TLS_KEY_FILE are deprecated, and images from 2026-12-22 on ignore them"
fi
docker rm -f "$run-tls-env" > /dev/null

echo "A certificate of your own copied into /config/ssl, and an empty one (T20)"
start "$net" tls-copy "${with_password[@]}" \
  -v "$tmp/tls.crt:/run/secrets/tls.crt:ro" -v "$tmp/tls.key:/run/secrets/tls.key:ro"
if ready tls-copy; then
  # The key file belongs to whoever runs this script, so root copies it, and
  # hands it to the desktop's user.
  docker exec "$run-tls-copy" sh -c 'cp /run/secrets/tls.crt /config/ssl/cert.pem && cp /run/secrets/tls.key /config/ssl/cert.key && chown abc:abc /config/ssl/cert.pem /config/ssl/cert.key'
  own="$(docker exec "$run-tls-copy" sha256sum /config/ssl/cert.pem)"
  docker restart "$run-tls-copy" > /dev/null
  if ready tls-copy; then
    check "T20: a certificate of your own in /config/ssl is left alone" "$own" \
      "$(docker exec "$run-tls-copy" sha256sum /config/ssl/cert.pem)"
    # What a removed mount leaves behind.
    docker exec "$run-tls-copy" sh -c ': > /config/ssl/cert.pem && : > /config/ssl/cert.key'
    docker restart "$run-tls-copy" > /dev/null
    if ready tls-copy; then
      check "T20: an empty cert.pem is replaced with the container's own" 825 "$(cert_days tls-copy)"
      check "T20: the log says it was made, at the first start and again now" 2 \
        "$(docker logs "$run-tls-copy" 2>&1 | grep -cF "[mt-cert] Made the desktop's own certificate" || true)"
    fi
  fi
fi
docker rm -f "$run-tls-copy" > /dev/null

echo "A VPN sidecar's network (T11)"
docker run -d --name "$run-tailnet" --network "$net" --cap-add NET_ADMIN --memory 128m --entrypoint sh "$image" \
  -c 'ip link add tailscale0 type dummy && ip link set tailscale0 up && exec sleep infinity' > /dev/null
start "container:$run-tailnet" sidecar "${with_password[@]}"
if ready sidecar; then
  check_true "T11: a tailscale0 interface isn't taken for host networking" logged sidecar "Host networking: no"
  check "T11: reachable through the sidecar" 401 "$(code "https://$run-tailnet:3001/")"
fi
docker rm -f "$run-sidecar" "$run-tailnet" > /dev/null

echo "SUBFOLDER=/mt/ (T12), SELKIES_FILE_TRANSFERS=false (T8), SELKIES_COMMAND_ENABLED=true (warning)"
start "$net" sub "${with_password[@]}" -e SUBFOLDER=/mt/ -e SELKIES_FILE_TRANSFERS=false -e SELKIES_COMMAND_ENABLED=true
if ready sub; then
  t="$run-sub:3001"
  check "T12: the desktop under /mt/" 200 "$(code -u "$user:$password" "https://$t/mt/")"
  check "T12: the stream under /mt/" 101 "$(ws "$t" /mt/api/websockets "https://$t")"
  check "T12: outside /mt/" 404 "$(code -u "$user:$password" "https://$t/")"
  check "T8: POST /api/upload with SELKIES_FILE_TRANSFERS=false" 403 \
    "$(code -u "$user:$password" -X POST -H "Origin: https://$t" -F 'file=@/etc/hostname' "https://$t/mt/api/upload")"
  check_true "T8: the log says file transfers: none" logged sub "File transfers: none."
  check_true "SELKIES_COMMAND_ENABLED=true is warned about" logged sub "WARNING: SELKIES_COMMAND_ENABLED=true"
fi
docker rm -f "$run-sub" > /dev/null

if [[ "$host_test" == yes ]]; then
  echo "Host networking (T15), on this machine's 127.0.0.1:3911"
  before="$(ss -Hltnu | awk '{ print $1, $5 }' | sort)"
  abstract_before="$(ss -Hxl | grep -c '@/tmp/.X11-unix' || true)"
  docker run -d --name "$run-host" --network host "${hardening[@]}" "${with_password[@]}" \
    -e CUSTOM_HTTPS_PORT=3911 "$image" > /dev/null
  if ready host; then
    after="$(ss -Hltnu | awk '{ print $1, $5 }' | sort)"
    abstract_after="$(ss -Hxl | grep -c '@/tmp/.X11-unix' || true)"
    check "T15: the only new listener on this machine" "tcp 127.0.0.1:3911" \
      "$(comm -13 <(echo "$before") <(echo "$after") | tr '\n' ' ' | sed 's/ $//')"
    check "T15: no new abstract X socket" "$abstract_before" "$abstract_after"
    check_true "T15: the log warns about host networking" logged host "host networking: only nginx listens"
    check "T15: login on 127.0.0.1:3911" 401 \
      "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 https://127.0.0.1:3911/ || true)"
  fi
  docker rm -f "$run-host" > /dev/null
fi

echo
echo "$passes passed, $failures failed"
(( failures == 0 ))
