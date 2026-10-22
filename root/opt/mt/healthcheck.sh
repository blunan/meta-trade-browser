#!/usr/bin/env bash
# healthcheck.sh: Docker's health check (HEALTHCHECK in the Dockerfile). It
# passes when MetaTrader is running and the desktop answers: nginx's health-check
# server, on a socket file inside the container, answers 200 only when Selkies
# answers through it. No port, certificate or login is involved.
# It can't tell whether MetaTrader is connected to the broker or whether an EA is
# running: MetaTrader's status bar and Journal show that.
set -euo pipefail

# MetaTrader's process as Wine shows it: the Windows path of terminal64.exe first.
if ! pgrep -f '^[A-Za-z]:\\.*\\terminal64\.exe( |$)' > /dev/null; then
  echo "MetaTrader isn't running"
  exit 1
fi
status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 \
  --unix-socket /run/mt/health.sock http://localhost/healthz)" || true
if [[ "$status" != 200 ]]; then
  echo "the desktop doesn't answer (nginx's health check: ${status/#000/no answer})"
  exit 1
fi
echo "ok: MetaTrader is running, and the desktop answers"
