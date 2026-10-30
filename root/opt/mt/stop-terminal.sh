#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# stop-terminal.sh: Gracefully stops MetaTrader during s6 container shutdown.
# Requests a clean exit via taskkill so charts and settings persist (up to 20s).
# Restores pre-exit Config/accounts.dat to prevent Wine corruption on restart.
set -euo pipefail

log_file=/config/log/mt/run-terminal.log
mt_process='^[A-Za-z]:\\.*\\terminal64\.exe( |$)'
accounts="${WINEPREFIX:-/config/.wine}/drive_c/Program Files/MetaTrader 5/Config/accounts.dat"

# Log to run-terminal.log if writable by desktop user, else stdout.
out=/dev/stdout
if s6-setuidgid abc touch "$log_file" 2> /dev/null; then
  out="$log_file"
fi
log() { printf '%s [mt-stop] %s\n' "$(date -u +%FT%TZ)" "$*" >> "$out"; }
now_us() { echo "${EPOCHREALTIME//[!0-9]/}"; }

timeout_s=20

# Inhibit run-terminal.sh from restarting MetaTrader during shutdown.
touch /run/mt/stopping

if ! pid="$(pgrep -o -f "$mt_process")"; then
  log "MetaTrader isn't running"
  exit 0
fi
saved=no
if [[ -f "$accounts" ]] && s6-setuidgid abc cp -p "$accounts" "$accounts.mt-stop"; then
  saved=yes
fi
log "asking MetaTrader (pid $pid) to close"
started="$(now_us)"
# Graceful close request (equivalent to File > Exit).
s6-setuidgid abc timeout 10 wine taskkill /im terminal64.exe >> "$out" 2>&1 ||
  log "taskkill failed; waiting anyway"
closed=yes
while kill -0 "$pid" 2> /dev/null; do
  if (( $(now_us) - started > timeout_s * 1000000 )); then
    closed=no
    break
  fi
  sleep 0.2
done
if [[ "$closed" == yes ]]; then
  tenths=$((($(now_us) - started) / 100000))
  log "MetaTrader closed in $((tenths / 10)).$((tenths % 10)) s"
else
  log "MetaTrader didn't close within $timeout_s s; stopping unsaved with container"
fi
if [[ "$saved" == yes ]] && s6-setuidgid abc mv -f "$accounts.mt-stop" "$accounts"; then
  log "restored Config/accounts.dat from before shutdown for clean restart login"
fi
