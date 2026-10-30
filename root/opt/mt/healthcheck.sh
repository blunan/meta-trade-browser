#!/usr/bin/env bash
# healthcheck.sh: Container healthcheck.
# Verifies terminal64.exe process is running and desktop/nginx responds on Unix socket.
set -euo pipefail

# Match Wine Windows process path for terminal64.exe.
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
