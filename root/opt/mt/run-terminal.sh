#!/usr/bin/env bash
# run-terminal.sh: starts MetaTrader on the desktop. The desktop's autostart
# runs it, and the base's watchdog runs it again whenever it ends
# (RESTART_APP=true). The autostart runs it without exec, so the watchdog keeps
# seeing its "sh .../autostart" process while MetaTrader runs.
#
# The first start installs three things, in order (four when MT_PYTHON=true).
# Each leaves a marker file in $WINEPREFIX, so a restart resumes where the last
# attempt stopped:
#   1. the Wine prefix (.prefix-ready);
#   2. Microsoft Edge WebView2, which MetaTrader's HTML panes use, once Microsoft's
#      signature passes (.webview2-installed);
#   3. MetaTrader, once MetaQuotes' signature passes (.mt5-installed);
#   4. when MT_PYTHON=true, Windows Python, once the Python Software Foundation's
#      signature passes and it reports python_version (.python-installed: an
#      image with a newer one upgrades it in place, and an older image leaves it
#      alone). Then the MetaTrader5 package and numpy, the versions in
#      python-requirements.txt, once their hashes match (.python-packages holds
#      that file's SHA-256: an image with another list installs its versions).
# A failed step is retried 60 s later, and MetaTrader doesn't start before every
# step is done. Otherwise MetaEditor would install WebView2 by itself, unchecked.
# .installing marks this first install while it's under way, and Python waits
# like the other steps only then. Turned on later, or upgraded, Python never
# holds MetaTrader back: a failure is logged, MetaTrader starts all the same,
# and the next start tries again. MetaTrader and MetaEditor find that Python by
# themselves.
#
# Every start then sets Edge's Windows version and MetaTrader's AI-agent servers,
# links the /mql5 mount, and runs MetaTrader in the foreground.
#
# While it installs, or a step fails, a window on the desktop (notice.py) shows
# the step it's on, or why it failed and when it tries again.
set -euo pipefail

export WINEPREFIX="${WINEPREFIX:-/config/.wine}"
# No Wine Mono (.NET) or Gecko (Internet Explorer): MetaTrader uses neither. Wine
# offers to download them whenever it creates or refreshes the prefix, as at
# the first start after an image update with a newer Wine, and MetaTrader would wait
# behind that dialog. A WINEDLLOVERRIDES of your own replaces this.
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES-mscoree,mshtml=}"
mt_dir="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
webview2_dir="$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
# Windows Python, for MT_PYTHON=true. Renovate keeps it on 3.14, the newest series
# MetaQuotes publishes MetaTrader5 wheels for. A new series would install next to
# this one, in its own folder, so moving to one takes more than this line.
# renovate: datasource=github-tags depName=python/cpython extractVersion=^v(?<version>\d+\.\d+\.\d+)$
python_version=3.14.10
python_series="${python_version%.*}"
python_dir="$WINEPREFIX/drive_c/Program Files/Python${python_series//./}"
# The MetaTrader5 package and numpy, pinned with their hashes. Renovate keeps
# the list current.
python_requirements=/opt/mt/python-requirements.txt
mt_url=https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe
# The URL MetaQuotes' own Linux installer, mt5linux.sh, uses.
webview2_url=https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/f2910a1e-e5a6-4f17-b52d-7faf525d17f8/MicrosoftEdgeWebview2Setup.exe
python_url="https://www.python.org/ftp/python/$python_version/python-$python_version-amd64.exe"
# MetaTrader's process as Wine shows it: the Windows path of terminal64.exe first.
mt_process='^[A-Za-z]:\\.*\\terminal64\.exe( |$)'
log_file=/config/log/mt/run-terminal.log
retry_delay=60
steps=3
if [[ "${MT_PYTHON:-}" == true ]]; then
  steps=4
fi

# One log: svc-mt-log copies this file into docker logs. When openbox starts
# this script, its output would otherwise go to /dev/null.
mkdir -p "${log_file%/*}"
exec >> "$log_file" 2>&1

log() { printf '%s [mt] %s\n' "$(date -u +%FT%TZ)" "$*"; }

# The container is stopping (stop-terminal.sh): don't start MetaTrader again.
if [[ -e /run/mt/stopping ]]; then
  exec sleep infinity
fi

# MetaTrader may already be running: restarted by itself for an update (LiveUpdate),
# or started from the menu. A second copy would exit at once, and the watchdog
# would run this script again every second, so wait for that copy instead.
if pid="$(pgrep -o -f "$mt_process")"; then
  log "MetaTrader is already running (pid $pid); waiting for it to exit"
  while kill -0 "$pid" 2> /dev/null; do
    sleep 5
  done
  log "MetaTrader (pid $pid) exited"
  exit 0
fi

notice_pid=
notice_fd=
tmp=
# notice <field>...: updates the window on the desktop while MetaTrader can't
# start yet, opening it the first time. notice.py lists the lines it takes; the
# fields go out tab-separated. Its errors go to this script's log.
notice() {
  if [[ -z "$notice_pid" ]]; then
    exec {notice_fd}> >(exec /usr/bin/python3 -I /opt/mt/notice.py > /dev/null)
    notice_pid=$!
  fi
  # In a subshell, so a window that has gone can't end this script with SIGPIPE.
  (
    IFS=$'\t'
    printf '%s\n' "$*" >&"$notice_fd"
  ) 2> /dev/null || true
}
close_notice() {
  if [[ -n "$notice_pid" ]]; then
    kill "$notice_pid" 2> /dev/null || true
    exec {notice_fd}>&-
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

# fail <reason>: MetaTrader can't start this time. Waiting before exiting keeps the
# watchdog from retrying in a tight loop.
fail() {
  log "ERROR: $1. Retrying in $retry_delay s."
  notice retry "$retry_delay" "${1^}."
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

# Under Wine, MetaTrader and MetaEditor set Edge (WebView2) to Windows XP, and their
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

# python_current: succeeds when Python is installed, at this image's version or
# a newer one. A newer one, from an image you went back from, stays: its
# installer doesn't downgrade.
python_current() {
  local installed
  installed="$(cat "$WINEPREFIX/.python-installed" 2> /dev/null || true)"
  [[ -n "$installed" ]] &&
    [[ "$(printf '%s\n' "$python_version" "$installed" | sort -V | tail -n 1)" == "$installed" ]]
}

# packages_current: succeeds when the packages are the ones in this image's
# python-requirements.txt.
packages_current() {
  local installed
  installed="$(cat "$WINEPREFIX/.python-packages" 2> /dev/null || true)"
  [[ -n "$installed" && "$installed" == "$(sha256sum < "$python_requirements" | cut -d' ' -f1)" ]]
}

# python_ready: succeeds unless MT_PYTHON=true needs Python or its packages
# installed, or brought up to this image's.
python_ready() {
  [[ "${MT_PYTHON:-}" == true ]] || return 0
  python_current && packages_current
}

# python_failed <reason>: during the first install, the same as fail. Otherwise
# MetaTrader starts all the same, with the Python it had, if any.
python_failed() {
  if [[ -f "$WINEPREFIX/.installing" ]]; then
    fail "$1"
  fi
  log "WARNING: $1. MetaTrader starts all the same, and the next start tries again."
}

prepare_prefix() {
  local started=$SECONDS
  notice install "Step 1 of $steps: setting up Wine"
  if [[ -f "$WINEPREFIX/.mt5-installed" ]]; then
    # From an earlier version of this image, which marked only the MetaTrader install.
    log "step 1 of $steps: the Wine prefix already holds MetaTrader; keeping it as it is"
  else
    log "step 1 of $steps: creating the Wine prefix"
    wineboot -i || fail "the Wine prefix couldn't be created"
    touch "$WINEPREFIX/.installing"
    # A crash ends the program, and the watchdog restarts it, instead of
    # leaving a dialog that waits for a click.
    wine reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f > /dev/null ||
      fail "the Wine prefix's settings couldn't be written"
    # As Windows 10, Wine's default, MetaTrader's copy protection reports "a debugger
    # has been found" (WineHQ bug 58043). MetaQuotes' installer sets 11 too.
    wine reg add 'HKCU\Software\Wine' /v Version /t REG_SZ /d win11 /f > /dev/null ||
      fail "the Wine prefix's settings couldn't be written"
    edge_as_win11 || fail "the Wine prefix's settings couldn't be written"
    # Nothing else runs in a new prefix yet, so this returns once Wine has
    # written the registry to disk.
    wineserver -w
  fi
  touch "$WINEPREFIX/.prefix-ready"
  log "step 1 of $steps done in $((SECONDS - started)) s"
}

install_webview2() {
  local started=$SECONDS rc=0 setup="$tmp/MicrosoftEdgeWebview2Setup.exe" _
  log "step 2 of $steps: Microsoft Edge WebView2, for MetaTrader's and MetaEditor's HTML panes"
  notice install "Step 2 of $steps: downloading Microsoft Edge WebView2"
  download "$webview2_url" "$setup" || fail "the WebView2 download failed"
  notice install "Step 2 of $steps: checking Microsoft's signature"
  /opt/mt/verify-signature.sh microsoft "$setup" ||
    fail "the WebView2 installer didn't pass its signature check, so it wasn't run"
  log "installing WebView2"
  notice install "Step 2 of $steps: installing Microsoft Edge WebView2"
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
  log "step 2 of $steps done in $((SECONDS - started)) s: WebView2 $(webview2_version)"
}

install_mt() {
  local started=$SECONDS rc=0 setup="$tmp/mt5setup.exe" file
  log "step 3 of $steps: MetaTrader"
  notice install "Step 3 of $steps: downloading MetaTrader"
  download "$mt_url" "$setup" || fail "the MetaTrader download failed"
  notice install "Step 3 of $steps: checking MetaQuotes' signature"
  /opt/mt/verify-signature.sh metaquotes "$setup" ||
    fail "the MetaTrader installer didn't pass its signature check, so it wasn't run"
  log "installing MetaTrader"
  notice install "Step 3 of $steps: installing MetaTrader"
  timeout 900 wine "$setup" /auto || rc=$?
  # It exits with 1 even when it succeeds, so its files decide.
  log "the MetaTrader installer exited with code $rc"
  for file in terminal64.exe MetaEditor64.exe metatester64.exe; do
    [[ -f "$mt_dir/$file" ]] || fail "the MetaTrader install is incomplete: $file is missing"
  done
  touch "$WINEPREFIX/.mt5-installed"
  log "step 3 of $steps done in $((SECONDS - started)) s"
}

# install_python: fails, after python_failed, if Python or its packages couldn't
# be installed. Python itself is installed only when it isn't current.
install_python() {
  local started=$SECONDS setup="$tmp/python-$python_version-amd64.exe" installed versions
  if python_current; then
    log "step 4 of $steps: the MetaTrader5 package (MT_PYTHON=true)"
  else
    log "step 4 of $steps: Python $python_version and the MetaTrader5 package (MT_PYTHON=true)"
    notice install "Step 4 of $steps: downloading Python $python_version"
    download "$python_url" "$setup" || { python_failed "the Python download failed"; return 1; }
    notice install "Step 4 of $steps: checking the Python Software Foundation's signature"
    /opt/mt/verify-signature.sh python "$setup" ||
      { python_failed "the Python installer didn't pass its signature check, so it wasn't run"; return 1; }
    log "installing Python $python_version"
    notice install "Step 4 of $steps: installing Python $python_version"
    timeout 900 wine "$setup" /quiet InstallAllUsers=1 PrependPath=1 \
      Include_launcher=0 Include_test=0 Include_doc=0 Include_tcltk=0 ||
      { python_failed "the Python installer failed"; return 1; }
    [[ -f "$python_dir/python.exe" ]] ||
      { python_failed "the Python install is incomplete: python.exe is missing"; return 1; }
    # Any installer the Python Software Foundation signed passes the check, an
    # older 3.14 too, so Python must also be the version this image asks for.
    installed="$(wine "$python_dir/python.exe" -I -c 'import platform; print(platform.python_version())' |
      tr -d '\r')" || { python_failed "Python's version couldn't be read"; return 1; }
    [[ "$installed" == "$python_version" ]] ||
      { python_failed "the Python installer left Python $installed, not $python_version"; return 1; }
    printf '%s\n' "$python_version" > "$WINEPREFIX/.python-installed"
  fi
  log "installing the MetaTrader5 package"
  notice install "Step 4 of $steps: installing the MetaTrader5 package"
  # Only the versions in python-requirements.txt, and only files with a hash
  # listed there. Z: is Wine's drive for /.
  timeout 900 wine "$python_dir/python.exe" -I -m pip install --no-cache-dir \
    --disable-pip-version-check --no-warn-script-location --require-hashes --only-binary=:all: \
    --no-deps -r "Z:$python_requirements" ||
    { python_failed "the MetaTrader5 package couldn't be installed"; return 1; }
  versions="$(wine "$python_dir/python.exe" -I -c \
    'import platform, MetaTrader5, numpy; print(f"Python {platform.python_version()}, MetaTrader5 {MetaTrader5.__version__}, numpy {numpy.__version__}")' \
    | tr -d '\r')" || { python_failed "the MetaTrader5 package couldn't be imported"; return 1; }
  sha256sum < "$python_requirements" | cut -d' ' -f1 > "$WINEPREFIX/.python-packages"
  log "step 4 of $steps done in $((SECONDS - started)) s: $versions"
}

# MetaTrader's and MetaEditor's AI-agent (MCP) servers listen on 127.0.0.1:22346 and
# 22345, protected only by an API key. They're off unless MT_AI_AGENTS=true:
# Enable in each [MCP.*] section of Config/assistant.ini, a UTF-16 file. MetaTrader
# adds the endpoints and keys itself.
set_ai_agents() {
  local file="$mt_dir/Config/assistant.ini" enable=0 state=off current='' updated
  if [[ "${MT_AI_AGENTS:-}" == true ]]; then
    enable=1
    state="on (MT_AI_AGENTS=true)"
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
    log "MetaTrader's AI-agent servers: $state"
  fi
}

# The optional /mql5 mount holds your own EAs, indicators and the rest. Each of
# its sections appears in MetaTrader's MQL5 folder as <section>/Mounted, a link into
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
    dest="$mt_dir/MQL5/$section"
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
  ! -f "$WINEPREFIX/.mt5-installed" ]] || ! python_ready; then
  started=$SECONDS
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
  [[ -f "$WINEPREFIX/.mt5-installed" ]] || install_mt
  python_ready || install_python || true
  export WINEDEBUG="$wine_debug"
  rm -rf "$tmp"
  tmp=
  log "install done in $((SECONDS - started)) s"
fi

edge_as_win11 || log "WARNING: Edge's Windows version couldn't be set, so the HTML panes may stay blank"
set_ai_agents || fail "MetaTrader's AI-agent servers couldn't be set in Config/assistant.ini"
link_mounts
# The window stays until MetaTrader's own appears, at most 60 s, so the desktop
# isn't empty in between. exec ends this script, so a background job closes it.
if [[ -n "$notice_pid" ]]; then
  notice start
  exec {notice_fd}>&-
  (
    timeout 60 xdotool search --sync --onlyvisible --classname '^terminal64\.exe$' > /dev/null 2>&1 || true
    kill "$notice_pid" 2> /dev/null || true
  ) &
  notice_pid=
fi
log "starting MetaTrader"
rm -f "$WINEPREFIX/.installing"
exec wine "$mt_dir/terminal64.exe" /portable
