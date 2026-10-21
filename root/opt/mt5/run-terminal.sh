#!/usr/bin/env bash
# run-terminal.sh: starts MetaTrader 5 on the desktop. The desktop's autostart
# runs it, and the base's watchdog runs it again whenever it ends
# (RESTART_APP=true). The autostart runs it without exec, so the watchdog keeps
# seeing its "sh .../autostart" process while MT5 runs.
#
# The first start installs three things, in order. Each leaves a marker file in
# $WINEPREFIX, so a restart resumes where the last attempt stopped:
#   1. the Wine prefix (.prefix-ready);
#   2. Microsoft Edge WebView2, which MT5's HTML panes use, once Microsoft's
#      signature passes (.webview2-installed);
#   3. MT5, once MetaQuotes' signature passes (.mt5-installed).
# A failed step is retried 60 s later, and MT5 doesn't start before all three
# are done. Otherwise MetaEditor would install WebView2 by itself, unchecked.
#
# Every start then sets Edge's Windows version and MT5's AI-agent servers,
# links the /mql5 mount, and runs MT5 in the foreground.
set -euo pipefail

export WINEPREFIX="${WINEPREFIX:-/config/.wine}"
# No Wine Mono (.NET) or Gecko (Internet Explorer): MT5 uses neither. Wine
# offers to download them whenever it creates or refreshes the prefix, as at
# the first start after an image update with a newer Wine, and MT5 would wait
# behind that dialog. A WINEDLLOVERRIDES of your own replaces this.
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES-mscoree,mshtml=}"
mt5_dir="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
webview2_dir="$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
mt5_url=https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe
# The URL MetaQuotes' own Linux installer, mt5linux.sh, uses.
webview2_url=https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/f2910a1e-e5a6-4f17-b52d-7faf525d17f8/MicrosoftEdgeWebview2Setup.exe
# MT5's process as Wine shows it: the Windows path of terminal64.exe first.
mt5_process='^[A-Za-z]:\\.*\\terminal64\.exe( |$)'
log_file=/config/log/mt5/run-terminal.log
retry_delay=60

# One log: svc-mt5-log copies this file into docker logs. When openbox starts
# this script, its output would otherwise go to /dev/null.
mkdir -p "${log_file%/*}"
exec >> "$log_file" 2>&1

log() { printf '%s [mt5] %s\n' "$(date -u +%FT%TZ)" "$*"; }

# The container is stopping (stop-terminal.sh): don't start MT5 again.
if [[ -e /run/mt5/stopping ]]; then
  exec sleep infinity
fi

# MT5 may already be running: restarted by itself for an update (LiveUpdate),
# or started from the menu. A second copy would exit at once, and the watchdog
# would run this script again every second, so wait for that copy instead.
if pid="$(pgrep -o -f "$mt5_process")"; then
  log "MT5 is already running (pid $pid); waiting for it to exit"
  while kill -0 "$pid" 2> /dev/null; do
    sleep 5
  done
  log "MT5 (pid $pid) exited"
  exit 0
fi

notice_pid=
tmp=
# notice <text>: a small window on the desktop while MT5 can't start yet.
# Openbox maximizes every window it manages, so this one asks not to be
# managed (overrideRedirect), and stays small and centred.
notice() {
  close_notice
  xmessage -center -buttons OK \
    -xrm '*overrideRedirect: True' \
    -xrm '*font: -*-helvetica-bold-r-normal--17-*-*-*-*-*-iso8859-1' \
    -xrm '*message.scrollVertical: never' -xrm '*message.scrollHorizontal: never' \
    -xrm '*message.borderWidth: 0' \
    -xrm '*message.leftMargin: 16' -xrm '*message.rightMargin: 16' \
    -xrm '*message.topMargin: 12' -xrm '*message.bottomMargin: 8' \
    "$1" > /dev/null 2>&1 &
  notice_pid=$!
}
close_notice() {
  if [[ -n "$notice_pid" ]]; then
    kill "$notice_pid" 2> /dev/null || true
    notice_pid=
  fi
}
cleanup() {
  close_notice
  if [[ -n "$tmp" ]]; then
    rm -rf "$tmp"
  fi
}
trap cleanup EXIT

# fail <reason>: MT5 can't start this time. Waiting before exiting keeps the
# watchdog from retrying in a tight loop.
fail() {
  log "ERROR: $1. Retrying in $retry_delay s."
  notice "MetaTrader 5 can't start yet: $1.

Retrying in $retry_delay seconds. The container's log (docker logs) has the details."
  sleep "$retry_delay"
  exit 1
}

# download <url> <file>
download() {
  log "downloading $1"
  curl -fsSL --retry 3 --retry-all-errors --retry-delay 5 --connect-timeout 30 --max-time 900 -o "$2" "$1"
}

# reg_sz <key> <name>: a string value from the prefix's user.reg, where Wine
# writes keys with doubled backslashes. Empty when there's none.
reg_sz() {
  KEY="$1" NAME="$2" awk '
    BEGIN { key = tolower(ENVIRON["KEY"]); name = "\"" tolower(ENVIRON["NAME"]) "\"=\"" }
    /^\[/ { inside = (tolower(substr($0, 2, length(key) + 1)) == key "]"); next }
    inside && index(tolower($0), name) == 1 {
      value = substr($0, length(name) + 1)
      sub(/"\r?$/, "", value)
      print value
      exit
    }' "$WINEPREFIX/user.reg" 2> /dev/null || true
}

# Under Wine, MT5 and MetaEditor set Edge (WebView2) to Windows XP, and their
# HTML panes (Help, Market, Mailbox) stay blank. As Windows 11 they render.
# They write their value only when there's none, so this one stays.
edge_as_win11() {
  if [[ "$(reg_sz 'Software\\Wine\\AppDefaults\\msedgewebview2.exe' Version)" == win11 ]]; then
    return 0
  fi
  wine reg add 'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe' /v Version /t REG_SZ /d win11 /f > /dev/null ||
    return 1
  log "Edge (WebView2) now runs as Windows 11"
}

# webview2_version: prints the installed WebView2 version; fails if there's none.
webview2_version() {
  local exes=("$webview2_dir"/*/msedgewebview2.exe)
  [[ -f "${exes[0]}" ]] || return 1
  basename "$(dirname "${exes[0]}")"
}

prepare_prefix() {
  local started=$SECONDS
  if [[ -f "$WINEPREFIX/.mt5-installed" ]]; then
    # From an earlier version of this image, which marked only the MT5 install.
    log "step 1 of 3: the Wine prefix already holds MT5; keeping it as it is"
  else
    log "step 1 of 3: creating the Wine prefix"
    wineboot -i || fail "the Wine prefix couldn't be created"
    # A crash ends the program, and the watchdog restarts it, instead of
    # leaving a dialog that waits for a click.
    wine reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f > /dev/null ||
      fail "the Wine prefix's settings couldn't be written"
    # As Windows 10, Wine's default, MT5's copy protection reports "a debugger
    # has been found" (WineHQ bug 58043). MetaQuotes' installer sets 11 too.
    wine reg add 'HKCU\Software\Wine' /v Version /t REG_SZ /d win11 /f > /dev/null ||
      fail "the Wine prefix's settings couldn't be written"
    edge_as_win11 || fail "the Wine prefix's settings couldn't be written"
    # Nothing else runs in a new prefix yet, so this returns once Wine has
    # written the registry to disk.
    wineserver -w
  fi
  touch "$WINEPREFIX/.prefix-ready"
  log "step 1 of 3 done in $((SECONDS - started)) s"
}

install_webview2() {
  local started=$SECONDS rc=0 setup="$tmp/MicrosoftEdgeWebview2Setup.exe" _
  log "step 2 of 3: Microsoft Edge WebView2, for MT5's and MetaEditor's HTML panes"
  download "$webview2_url" "$setup" || fail "the WebView2 download failed"
  /opt/mt5/verify-signature.sh microsoft "$setup" ||
    fail "the WebView2 installer didn't pass its signature check, so it wasn't run"
  log "installing WebView2"
  timeout 900 wine "$setup" /silent /install || rc=$?
  log "the WebView2 installer exited with code $rc"
  # Edge Update installs the runtime, and then keeps running. So from here on,
  # "wineserver -w", which waits for every Wine program to end, never returns.
  for _ in $(seq 60); do
    webview2_version > /dev/null && break
    sleep 5
  done
  webview2_version > /dev/null || fail "WebView2 wasn't installed within 5 minutes"
  touch "$WINEPREFIX/.webview2-installed"
  log "step 2 of 3 done in $((SECONDS - started)) s: WebView2 $(webview2_version)"
}

install_mt5() {
  local started=$SECONDS rc=0 setup="$tmp/mt5setup.exe" file
  log "step 3 of 3: MetaTrader 5"
  download "$mt5_url" "$setup" || fail "the MT5 download failed"
  /opt/mt5/verify-signature.sh metaquotes "$setup" ||
    fail "mt5setup.exe didn't pass its signature check, so it wasn't run"
  log "installing MT5"
  timeout 900 wine "$setup" /auto || rc=$?
  # It exits with 1 even when it succeeds, so its files decide.
  log "the MT5 installer exited with code $rc"
  for file in terminal64.exe MetaEditor64.exe metatester64.exe; do
    [[ -f "$mt5_dir/$file" ]] || fail "the MT5 install is incomplete: $file is missing"
  done
  touch "$WINEPREFIX/.mt5-installed"
  log "step 3 of 3 done in $((SECONDS - started)) s"
}

# MT5's and MetaEditor's AI-agent (MCP) servers listen on 127.0.0.1:22346 and
# 22345, protected only by an API key. They're off unless MT5_AI_AGENTS=true:
# Enable in each [MCP.*] section of Config/assistant.ini, a UTF-16 file. MT5
# adds the endpoints and keys itself.
set_ai_agents() {
  local file="$mt5_dir/Config/assistant.ini" enable=0 state=off current='' updated
  if [[ "${MT5_AI_AGENTS:-}" == true ]]; then
    enable=1
    state="on (MT5_AI_AGENTS=true)"
  fi
  if [[ -f "$file" ]] && ! current="$(iconv -f UTF-16 -t UTF-8 "$file" 2> /dev/null)"; then
    log "Config/assistant.ini couldn't be read, so it's replaced"
    current=''
  fi
  updated="$(if [[ -n "$current" ]]; then printf '%s\n' "$current"; fi | awk -v enable="$enable" '
    function finish() { if (mcp && !done) print "Enable=" enable "\r" }
    {
      line = $0
      sub(/\r$/, "", line)
      line = tolower(line)
      if (line ~ /^\[/) {
        finish()
        mcp = (line ~ /^\[mcp\./)
        done = 0
        seen[line] = 1
      } else if (mcp && line ~ /^[ \t]*enable[ \t]*=/) {
        if (!done) print "Enable=" enable "\r"
        done = 1
        next
      }
      print
    }
    END {
      finish()
      if (!("[mcp.metaeditor]" in seen)) print "[MCP.MetaEditor]\r\nEnable=" enable "\r"
      if (!("[mcp.metatrader]" in seen)) print "[MCP.MetaTrader]\r\nEnable=" enable "\r"
    }')"
  if [[ "$updated" != "$current" ]]; then
    mkdir -p "${file%/*}"
    { printf '\xff\xfe'; printf '%s\n' "$updated" | iconv -f UTF-8 -t UTF-16LE; } > "$file.new" || return 1
    mv -f "$file.new" "$file"
    log "MT5's AI-agent servers: $state"
  fi
}

# The optional /mql5 mount holds your own EAs, indicators and the rest. Each of
# its sections appears in MT5's MQL5 folder as <section>/Mounted, a link into
# the mount.
link_mounts() {
  local name=Mounted section src dest linked=()
  if [[ ! -d /mql5 ]]; then
    log "no /mql5 mount"
    return 0
  fi
  for section in Experts Indicators Scripts Include Libraries Presets; do
    src="/mql5/$section"
    if [[ ! -d "$src" ]] && ! mkdir "$src" 2> /dev/null; then
      log "/mql5/$section is missing and can't be created (read-only?): skipped"
      continue
    fi
    dest="$mt5_dir/MQL5/$section"
    mkdir -p "$dest"
    if [[ -L "$dest/$name" || ! -e "$dest/$name" ]]; then
      ln -sfn "$src" "$dest/$name"
      linked+=("$section")
    else
      log "MQL5/$section/$name exists and isn't a link: left alone"
    fi
  done
  if (( ${#linked[@]} > 0 )); then
    log "/mql5 linked into MQL5 as <section>/$name: ${linked[*]}"
  fi
}

if [[ ! -f "$WINEPREFIX/.prefix-ready" || ! -f "$WINEPREFIX/.webview2-installed" ||
  ! -f "$WINEPREFIX/.mt5-installed" ]]; then
  started=$SECONDS
  notice "Installing MetaTrader 5. This takes a couple of minutes."
  tmp="$(mktemp -d)"
  # Wine reports dozens of harmless errors while it builds the prefix and the
  # installers run. With the image's WINEDEBUG they stay out of the log; a
  # WINEDEBUG of your own applies to the install too.
  wine_debug="${WINEDEBUG-}"
  if [[ "$wine_debug" == fixme-all,err-toolbar ]]; then
    export WINEDEBUG=-all
  fi
  [[ -f "$WINEPREFIX/.prefix-ready" ]] || prepare_prefix
  [[ -f "$WINEPREFIX/.webview2-installed" ]] || install_webview2
  [[ -f "$WINEPREFIX/.mt5-installed" ]] || install_mt5
  export WINEDEBUG="$wine_debug"
  rm -rf "$tmp"
  tmp=
  log "first start done in $((SECONDS - started)) s"
fi

edge_as_win11 || log "WARNING: Edge's Windows version couldn't be set, so the HTML panes may stay blank"
set_ai_agents || fail "MT5's AI-agent servers couldn't be set in Config/assistant.ini"
link_mounts
close_notice
log "starting MetaTrader 5"
exec wine "$mt5_dir/terminal64.exe" /portable
