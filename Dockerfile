# syntax=docker/dockerfile:1
# metatrader-docker: MetaTrader in the browser, on linuxserver's Selkies desktop.
FROM ghcr.io/linuxserver/baseimage-selkies:debiantrixie@sha256:df4a9259e7535526005785202bd08b3b066250a64c65877802b2354fd6a975dd

# Strip Wine debug symbols to save ~1 GB. Set false for crash backtraces.
ARG STRIP_WINE_DEBUG=true

# Pinned WineHQ staging release; updated via Renovate.
# renovate: datasource=deb depName=winehq-staging
ARG WINE_VERSION=11.19~trixie-1

# Runtime defaults: locked-down Selkies streaming over Unix socket to nginx,
# audio enabled without mic/webcam, and default trader user (1000:1000).
ENV TITLE=MetaTrader \
    CUSTOM_USER=trader \
    PUID=1000 \
    PGID=1000 \
    PIXELFLUX_WAYLAND=false \
    WINEPREFIX=/config/.wine \
    WINEDEBUG=fixme-all,err-toolbar \
    HARDEN_DESKTOP=true \
    RESTART_APP=true \
    START_DOCKER=false \
    PELORUS=false \
    SELKIES_ALLOWED_ORIGINS= \
    SELKIES_COMMAND_ENABLED=false \
    SELKIES_UNIX_SOCKET=/run/selkies/selkies.sock \
    SELKIES_ENABLE_DUAL_MODE=false \
    SELKIES_ENABLE_SHARING=false \
    SELKIES_ENABLE_COLLAB=false \
    SELKIES_PRINTING_ENABLED=false \
    SELKIES_CLIPBOARD_ENABLED=true \
    SELKIES_FILE_TRANSFERS=none \
    SELKIES_UI_SIDEBAR_SHOW_FILES=auto \
    SELKIES_AUDIO_ENABLED=true \
    SELKIES_MICROPHONE_ENABLED='false|locked' \
    SELKIES_WEBCAM_ENABLED='false|locked' \
    SELKIES_UI_SIDEBAR_SHOW_AUDIO_SETTINGS='false|locked' \
    SELKIES_UI_SIDEBAR_SHOW_VIDEO_SETTINGS='false|locked' \
    NO_WEBCAM=true \
    NO_GAMEPAD=true \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2

# Install WineHQ staging (verified by GPG fingerprint) and osslsigncode.
RUN <<'EOF'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

curl -fsSL -o /tmp/winehq.key https://dl.winehq.org/wine-builds/winehq.key
fpr="$(gpg --show-keys --with-colons /tmp/winehq.key | awk -F: '$1 == "fpr" { print $10; exit }')"
test "$fpr" = D43F640145369C51D786DDEA76F1A20FF987672F
mkdir -p /etc/apt/keyrings
gpg --dearmor -o /etc/apt/keyrings/winehq-archive.gpg /tmp/winehq.key
rm /tmp/winehq.key
echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/winehq-archive.gpg] https://dl.winehq.org/wine-builds/debian trixie main" \
  > /etc/apt/sources.list.d/winehq.list
dpkg --add-architecture i386
apt-get update
apt-get install -y --no-install-recommends \
  winehq-staging="$WINE_VERSION" wine-staging="$WINE_VERSION" \
  wine-staging-amd64="$WINE_VERSION" wine-staging-i386:i386="$WINE_VERSION" \
  osslsigncode
apt-mark hold winehq-staging wine-staging wine-staging-amd64 wine-staging-i386

if [ "$STRIP_WINE_DEBUG" = true ]; then
  lib=/opt/wine-staging/lib/wine
  before="$(du -sm "$lib" | cut -f1)"
  count=0
  while IFS= read -r -d '' f; do
    objdump -f "$f" > /dev/null 2>&1 || continue
    strip --strip-debug "$f"
    count=$((count + 1))
  done < <(find "$lib/x86_64-windows" "$lib/i386-windows" -type f -print0)
  # Verify stripped DLLs retain the Wine builtin mark.
  for f in "$lib/x86_64-windows/ntdll.dll" "$lib/i386-windows/ntdll.dll"; do
    test "$(head -c 80 "$f" | tail -c 16)" = "Wine builtin DLL"
  done
  echo "Stripped debug information from $count Wine DLLs: $before MB -> $(du -sm "$lib" | cut -f1) MB"
fi

# Remove unused Docker packages to eliminate base image CVEs.
apt-get purge -y --auto-remove \
  docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin containerd.io
apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade -y
apt-get clean
rm -rf /var/lib/apt/lists/*

# Remove shared base snakeoil certificates (nginx generates unique certs in /config/ssl).
find /etc/ssl/certs -lname '*ssl-cert-snakeoil.pem' -delete
rm -f /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/ssl/private/ssl-cert-snakeoil.key
EOF

# Base image patches (asserted against upstream changes):
# - Isolate sockets for host networking (group mtsock; drop Xvfb abstract socket).
# - Clean up stale healthcheck socket on nginx start.
# - Exclude threads from desktop shutdown signal waiting to prevent a 5s delay.
# - Remove upstream donation banner from startup log.
# - Defer upload directory creation to init-mt-access.
RUN <<'EOF'
#!/bin/bash
set -euo pipefail
groupadd --system mtsock
usermod -aG mtsock abc
usermod -aG mtsock www-data

run=/etc/s6-overlay/s6-rc.d/svc-selkies/run
test "$(grep -c '^exec s6-setuidgid abc \\$' "$run")" -eq 1
sed -i 's/^exec s6-setuidgid abc \\$/umask 0002\n&/' "$run"
test "$(grep -c -x 'umask 0002' "$run")" -eq 1

run=/etc/s6-overlay/s6-rc.d/svc-xorg/run
test "$(grep -c '^ *-nolisten "tcp" \\$' "$run")" -eq 1
sed -i 's/^\( *\)-nolisten "tcp" \\$/&\n\1-nolisten "local" \\/' "$run"
test "$(grep -c '^ *-nolisten "local" \\$' "$run")" -eq 1

run=/etc/s6-overlay/s6-rc.d/svc-nginx/run
test "$(grep -c '^exec /usr/sbin/nginx ' "$run")" -eq 1
sed -i 's|^exec /usr/sbin/nginx |rm -f /run/mt/health.sock\n&|' "$run"
test "$(grep -c -x 'rm -f /run/mt/health.sock' "$run")" -eq 1

run=/etc/s6-overlay/s6-rc.d/svc-de/finish
test "$(grep -c -F 'pstree -p "$PARENT_PID"' "$run")" -eq 1
sed -i 's/pstree -p "\$PARENT_PID"/pstree -p -T "$PARENT_PID"/' "$run"
test "$(grep -c -F 'pstree -p -T "$PARENT_PID"' "$run")" -eq 1

run=/etc/s6-overlay/s6-rc.d/init-adduser/run
test "$(grep -c -x 'To support LSIO projects visit:' "$run")" -eq 1
test "$(grep -c -x 'https://www.linuxserver.io/donate/' "$run")" -eq 1
sed -i '/^To support LSIO projects visit:$/,/^$/d' "$run"
test "$(grep -c -F 'linuxserver.io/donate' "$run")" -eq 0
test "$(grep -c -x 'GID/UID' "$run")" -eq 1

run=/etc/s6-overlay/s6-rc.d/init-nginx/run
test "$(grep -c -x -F 's6-setuidgid abc mkdir -p ${FILE_MANAGER_PATH}' "$run")" -eq 1
sed -i '/^s6-setuidgid abc mkdir -p \${FILE_MANAGER_PATH}$/d' "$run"
test "$(grep -c -F 'mkdir -p ${FILE_MANAGER_PATH}' "$run")" -eq 0
EOF

COPY root/ /

# Validate GTK 3 availability and syntax for notice.py.
RUN /usr/bin/python3 -I -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk' && \
    /usr/bin/python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' /opt/mt/notice.py

# Verify pinned root CAs:
# - WebView2: Microsoft Root CA 2011 (signing) & 2010 (timestamps)
# - Python: Microsoft Identity Verification Root CA 2020
RUN <<'EOF'
#!/bin/bash
set -euo pipefail
# pinned <file> <SHA-256>...: asserts pem file contains exact certificate fingerprints.
pinned() {
  local pem="$1" tmp actual
  shift
  if grep -v -E '^(-----(BEGIN|END) CERTIFICATE-----|[A-Za-z0-9+/=]+)$' "$pem"; then
    echo "$pem holds more than certificates" >&2
    exit 1
  fi
  # Verify openssl can inspect each certificate block individually.
  test "$(grep -c -- '-----BEGIN CERTIFICATE-----' "$pem")" -eq $#
  tmp="$(mktemp -d)"
  awk -v d="$tmp" '/-----BEGIN CERTIFICATE-----/ { n++ } n { print > (d "/" n ".pem") }' "$pem"
  actual="$(for f in "$tmp"/*.pem; do openssl x509 -in "$f" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d :; done | sort)"
  rm -rf "$tmp"
  test "$actual" = "$(printf '%s\n' "$@" | sort)"
}
pinned /opt/mt/certs/microsoft-roots.pem \
  847DF6A78497943F27FC72EB93F9A637320A02B561D0A91B09E87A7807ED7C61 \
  DF545BF919A2439C36983B54CDFC903DFA4F37D3996D8D84B4C31EEC6F3C163E
pinned /opt/mt/certs/microsoft-identity-root.pem \
  5367F20C7ADE0E2BCA790915056D086B720C33C1FA2A2661ACF787E3292E1270
EOF

# Metadata labels (placed last to preserve layer cache).
ARG IMAGE_VERSION=dev
ARG IMAGE_REVISION=
ARG IMAGE_CREATED=
# Override upstream base labels.
LABEL org.opencontainers.image.title="metatrader-docker" \
      org.opencontainers.image.description="MetaTrader in the browser: WineHQ staging on linuxserver's Selkies desktop, secure by default. Not affiliated with MetaQuotes or Microsoft." \
      org.opencontainers.image.authors="Brayan Luna" \
      org.opencontainers.image.vendor="Brayan Luna" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/blunan/metatrader-docker" \
      org.opencontainers.image.url="https://github.com/blunan/metatrader-docker" \
      org.opencontainers.image.documentation="https://github.com/blunan/metatrader-docker#readme" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.ref.name="" \
      build_version="metatrader-docker version ${IMAGE_VERSION}" \
      maintainer="Brayan Luna"

# Healthcheck succeeds when MetaTrader and desktop respond.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5m --retries=3 \
  CMD ["/opt/mt/healthcheck.sh"]

EXPOSE 3001
