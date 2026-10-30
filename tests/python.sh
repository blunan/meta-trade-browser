#!/usr/bin/env bash
# Verifies Python integration (MT_PYTHON=true) against a running container:
# asserts MetaTrader5 IPC connects and no unexpected network ports listen.
#
# Usage: tests/python.sh [container]
#   container  Container name (default: metatrader-docker-dev)
set -euo pipefail

name="${1:-metatrader-docker-dev}"
tmp="$(mktemp -d)"
script=
passes=0
failures=0

cleanup() {
  if [[ -n "$script" ]]; then
    kill "$script" 2> /dev/null || true
  fi
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

# listeners: the container's listening TCP and UDP sockets, as hexadecimal
# address:port, without Docker's DNS server on 127.0.0.11 (as in tests/access.sh).
listeners() {
  docker exec "$name" sh -c '
    for f in tcp tcp6; do awk "NR > 1 && \$4 == \"0A\" { print \$2 }" /proc/net/$f; done
    for f in udp udp6; do awk "NR > 1 { print \$2 }" /proc/net/$f; done' |
    grep -v '^0B00007F:' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

echo "Container: $name"
check "listening sockets before a script attaches (only HTTPS on 3001)" "00000000:0BB9" "$(listeners)"

# A script that attaches, says so, and stays attached for 20 s. Before
# MetaTrader's first login, initialize() fails after about a minute.
docker exec -u abc "$name" wine python -I -c '
import time
import MetaTrader5 as mt5
ok = mt5.initialize()
print("initialize", ok, mt5.last_error(), "version", mt5.version(), flush=True)
if ok:
    time.sleep(20)
    mt5.shutdown()
' > "$tmp/script.log" 2>&1 &
script=$!
for _ in $(seq 1 90); do
  grep -q '^initialize ' "$tmp/script.log" && break
  kill -0 "$script" 2> /dev/null || break
  sleep 1
done
result="$(grep '^initialize ' "$tmp/script.log" | tr -d '\r' || true)"
printf '        %s\n' "${result:-the script printed nothing: $(tr -d '\r' < "$tmp/script.log" | tail -n 3)}"
check "initialize() connects to MetaTrader (logged in to an account?)" "initialize True" \
  "$(cut -d' ' -f1-2 <<< "$result")"
check "listening sockets while a script is attached (only HTTPS on 3001)" "00000000:0BB9" "$(listeners)"
wait "$script" || true
script=

echo
echo "$passes passed, $failures failed"
(( failures == 0 ))
