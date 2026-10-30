#!/usr/bin/env bash
# run-terminal.sh: Launches MetaTrader under openbox and the container watchdog.
#
# On first run, provisions components sequentially and creates marker files in $WINEPREFIX:
#   1. Wine prefix (.prefix-ready)
#   2. Microsoft Edge WebView2 (.webview2-installed)
#   3. MetaTrader 5 (.mt5-installed)
#   4. Windows Python & verified wheels (.python-installed, .python-packages; if MT_PYTHON=true)
#
# Retries failed steps every 60s, reporting progress via notice.py.
# On normal start: configures WebView2, agent servers, /mql5 symlinks, then launches terminal64.exe.
set -euo pipefail

export WINEPREFIX="${WINEPREFIX:-/config/.wine}"
# Disable Mono and Gecko dialogs; MetaTrader requires neither.
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES-mscoree,mshtml=}"
mt_dir="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
webview2_dir="$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
# Windows Python for MT_PYTHON=true (pinned to newest MetaTrader5-compatible series).
# renovate: datasource=github-tags depName=python/cpython extractVersion=^v(?<version>\d+\.\d+\.\d+)$
python_version=3.14.10
python_series="${python_version%.*}"
python_dir="$WINEPREFIX/drive_c/Program Files/Python${python_series//./}"
# Pinned requirements with hashes; updated via Renovate.
python_requirements=/opt/mt/python-requirements.txt
mt_url=https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe
# Pinned WebView2 bootstrapper URL used by MetaQuotes' mt5linux.sh installer.
webview2_url=https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/f2910a1e-e5a6-4f17-b52d-7faf525d17f8/MicrosoftEdgeWebview2Setup.exe
python_url="https://www.python.org/ftp/python/$python_version/python-$python_version-amd64.exe"
# Match Wine Windows process path for terminal64.exe.
mt_process='^[A-Za-z]:\\.*\\terminal64\.exe( |$)'
log_file=/config/log/mt/run-terminal.log
retry_delay=60
steps=3
if [[ "${MT_PYTHON:-}" == true ]]; then
  steps=4
fi

# Append stdout/stderr to log_file; svc-mt-log streams it to docker logs.
mkdir -p "${log_file%/*}"
exec >> "$log_file" 2>&1

log() { printf '%s [mt] %s\n' "$(date -u +%FT%TZ)" "$*"; }

# Inhibit relaunch while container is stopping.
if [[ -e /run/mt/stopping ]]; then
  exec sleep infinity
fi

# Wait if MetaTrader is already running (e.g. LiveUpdate restart or menu launch).
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
# Python error message to display on desktop if post-install update fails.
python_warning=
# notice <field>...: updates desktop notice.py dialog (tab-separated).
notice() {
  if [[ -z "$notice_pid" ]]; then
    exec {notice_fd}> >(exec /usr/bin/python3 -I /opt/mt/notice.py > /dev/null)
    notice_pid=$!
  fi
  # Subshell prevents SIGPIPE if window closes.
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

# fail <reason>: logs error, updates notice dialog, and pauses before exiting.
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

# reg_sz <key> <name>: reads a string value from user.reg.
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

# Force WebView2 to run as Windows 11 under Wine so HTML panes render.
edge_as_win11() {
  if [[ "$(reg_sz 'Software\\Wine\\AppDefaults\\msedgewebview2.exe' Version)" == win11 ]]; then
    return 0
  fi
  wine reg add 'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe' /v Version /t REG_SZ /d win11 /f > /dev/null ||
    return 1
  log "Edge (WebView2) now runs as Windows 11"
}

# webview2_version: returns the installed WebView2 version.
webview2_version() {
  local exes=("$webview2_dir"/*/msedgewebview2.exe)
  [[ -f "${exes[0]}" ]] || return 1
  basename "$(dirname "${exes[0]}")"
}

# python_current: checks whether installed Python is at least $python_version.
python_current() {
  local installed
  installed="$(cat "$WINEPREFIX/.python-installed" 2> /dev/null || true)"
  [[ -n "$installed" ]] &&
    [[ "$(printf '%s\n' "$python_version" "$installed" | sort -V | tail -n 1)" == "$installed" ]]
}

# packages_current: checks whether installed packages match current requirements hash.
packages_current() {
  local installed
  installed="$(cat "$WINEPREFIX/.python-packages" 2> /dev/null || true)"
  [[ -n "$installed" && "$installed" == "$(sha256sum < "$python_requirements" | cut -d' ' -f1)" ]]
}

# python_ready: checks if Python and dependencies are up to date when MT_PYTHON=true.
python_ready() {
  [[ "${MT_PYTHON:-}" == true ]] || return 0
  python_current && packages_current
}

# python_failed <reason>: fatal on first install; non-fatal warning on subsequent starts.
python_failed() {
  if [[ -f "$WINEPREFIX/.installing" ]]; then
    fail "$1"
  fi
  log "WARNING: $1. MetaTrader starts all the same, and the next start tries again."
  python_warning="${1^}."
}

prepare_prefix() {
  local started=$SECONDS offset
  notice install "Step 1 of $steps: setting up Wine"
  if [[ -f "$WINEPREFIX/.mt5-installed" ]]; then
    # Prefix holds MetaTrader from a previous container run.
    log "step 1 of $steps: the Wine prefix already holds MetaTrader; keeping it as it is"
  else
    log "step 1 of $steps: creating the Wine prefix"
    offset="$(stat -c %s "$log_file")"
    if ! wineboot -i; then
      # Detect Docker 29.4.2 seccomp bug blocking 32-bit socketcall.
      if grep -qF 'socket : Function not implemented' < <(tail -c "+$((offset + 1))" "$log_file"); then
        fail "the Wine prefix couldn't be created: the container's seccomp profile blocks socketcall, a system call Wine's 32-bit programs need, as Docker 29.4.2's does. Update Docker to 29.4.3 or later"
      fi
      fail "the Wine prefix couldn't be created"
    fi
    touch "$WINEPREFIX/.installing"
    # Suppress Wine crash dialog so watchdog can restart without user input.
    wine reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f > /dev/null ||
      fail "the Wine prefix's settings couldn't be written"
    # Set Windows 11 mode to avoid MetaTrader anti-debugger false positive (WineHQ #58043).
    wine reg add 'HKCU\Software\Wine' /v Version /t REG_SZ /d win11 /f > /dev/null ||
      fail "the Wine prefix's settings couldn't be written"
    edge_as_win11 || fail "the Wine prefix's settings couldn't be written"
    # Wait for registry to flush to disk.
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
  # Poll until WebView2 binary appears (Edge Update continues running in background).
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
  # Installer may exit 1 on success; verify expected binaries exist.
  log "the MetaTrader installer exited with code $rc"
  for file in terminal64.exe MetaEditor64.exe metatester64.exe; do
    [[ -f "$mt_dir/$file" ]] || fail "the MetaTrader install is incomplete: $file is missing"
  done
  touch "$WINEPREFIX/.mt5-installed"
  log "step 3 of $steps done in $((SECONDS - started)) s"
}

# install_python: downloads, verifies, and installs Windows Python and wheel requirements.
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
    # Verify installed version matches expected release.
    installed="$(wine "$python_dir/python.exe" -I -c 'import platform; print(platform.python_version())' |
      tr -d '\r')" || { python_failed "Python's version couldn't be read"; return 1; }
    [[ "$installed" == "$python_version" ]] ||
      { python_failed "the Python installer left Python $installed, not $python_version"; return 1; }
    printf '%s\n' "$python_version" > "$WINEPREFIX/.python-installed"
  fi
  log "installing the MetaTrader5 package"
  notice install "Step 4 of $steps: installing the MetaTrader5 package"
  # Install wheel requirements by hash. Z: maps to container root /.
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

# Configure loopback MCP agent servers (ports 22345/22346) in Config/assistant.ini (UTF-16LE).
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

# Symlink /mql5 subdirectories into MetaTrader's MQL5/<section>/Mounted.
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
  # Silence noisy Wine setup output unless user set custom WINEDEBUG.
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
# Keep notice dialog visible until terminal64 appears (or keep error warning open).
if [[ -n "$python_warning" ]]; then
  notice warning "$python_warning"
  exec {notice_fd}>&-
  notice_pid=
elif [[ -n "$notice_pid" ]]; then
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
