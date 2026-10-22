#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# stop-terminal.sh: the stop part of mt-stop. When the container stops, s6
# runs it while the desktop is still up. It asks MetaTrader to close, as File > Exit
# does, so MetaTrader saves its charts and settings, and waits for it. Otherwise MetaTrader
# would be killed without saving. It waits up to 20 s: s6 gives this whole
# step 25 s at most (timeout-down).
# MetaEditor isn't asked: a "Save changes?" dialog would just wait there.
#
# Under Wine, the Config/accounts.dat that MetaTrader writes while closing works only
# until the container stops: at the next container start, MetaTrader logs "Accounts
# deleted due security reason", deletes it, and doesn't log in. The copy it
# wrote while running survives, so that one is put back once MetaTrader has closed.
set -euo pipefail

log_file=/config/log/mt/run-terminal.log
mt_process='^[A-Za-z]:\\.*\\terminal64\.exe( |$)'
accounts="${WINEPREFIX:-/config/.wine}/drive_c/Program Files/MetaTrader 5/Config/accounts.dat"

# Into MetaTrader's log, which svc-mt-log copies into docker logs, as long as the
# desktop user can write it.
out=/dev/stdout
if s6-setuidgid abc touch "$log_file" 2> /dev/null; then
  out="$log_file"
fi
log() { printf '%s [mt-stop] %s\n' "$(date -u +%FT%TZ)" "$*" >> "$out"; }
now_us() { echo "${EPOCHREALTIME//[!0-9]/}"; }

timeout_s=20

# While this file exists, run-terminal.sh sleeps instead of starting MetaTrader, so
# the watchdog can't bring MetaTrader back in the middle of the stop.
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
# Without /f, taskkill sends the same close request as File > Exit.
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
  log "MetaTrader didn't close within $timeout_s s, so it stops unsaved with the container"
fi
if [[ "$saved" == yes ]] && s6-setuidgid abc mv -f "$accounts.mt-stop" "$accounts"; then
  log "put back Config/accounts.dat from before the close, so that MetaTrader logs in by itself at the next start"
fi
