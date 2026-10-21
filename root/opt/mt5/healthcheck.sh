#!/usr/bin/env bash
# healthcheck.sh: Docker's health check (HEALTHCHECK in the Dockerfile). It
# passes when MT5 is running and the desktop answers: nginx's health-check
# server, on a socket file inside the container, answers 200 only when Selkies
# answers through it. No port, certificate or login is involved.
# It can't tell whether MT5 is connected to the broker or whether an EA is
# running: MT5's status bar and Journal show that.
set -euo pipefail

# MT5's process as Wine shows it: the Windows path of terminal64.exe first.
if ! pgrep -f '^[A-Za-z]:\\.*\\terminal64\.exe( |$)' > /dev/null; then
  echo "MT5 isn't running"
  exit 1
fi
status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 \
  --unix-socket /run/mt5/health.sock http://localhost/healthz)" || true
if [[ "$status" != 200 ]]; then
  echo "the desktop doesn't answer (nginx's health check: ${status/#000/no answer})"
  exit 1
fi
echo "ok: MT5 is running, and the desktop answers"
