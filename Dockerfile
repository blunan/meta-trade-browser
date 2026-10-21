# syntax=docker/dockerfile:1
# mt5-desktop: MetaTrader 5 in the browser, on linuxserver's Selkies desktop.
FROM ghcr.io/linuxserver/baseimage-selkies:debiantrixie@sha256:5b3f10459933740554081efbca9c8d5e006faf5116b54ab40b7bfad7c8111849

# CI passes the real values; a local build is "dev".
ARG IMAGE_VERSION=dev
ARG IMAGE_REVISION=
ARG IMAGE_CREATED=
# Wine's Windows DLLs carry debug information that only crash backtraces use.
# Stripping it saves about 1 GB unpacked. Set to false for a troubleshooting build.
ARG STRIP_WINE_DEBUG=true

# Every label the base sets describes the base, so each one is replaced.
LABEL org.opencontainers.image.title="mt5-desktop" \
      org.opencontainers.image.description="MetaTrader 5 in the browser: WineHQ staging on linuxserver's Selkies desktop, secure by default. Not affiliated with MetaQuotes or Microsoft." \
      org.opencontainers.image.authors="Brayan Luna" \
      org.opencontainers.image.vendor="Brayan Luna" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/blunan/trader-bot" \
      org.opencontainers.image.url="https://github.com/blunan/trader-bot" \
      org.opencontainers.image.documentation="https://github.com/blunan/trader-bot#readme" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.ref.name="" \
      build_version="mt5-desktop version ${IMAGE_VERSION}" \
      maintainer="Brayan Luna"

# Same-origin streaming only, no commands from the web page, no switch to
# WebRTC, and Selkies on a socket file that only nginx can reach.
ENV TITLE=MetaTrader5 \
    PIXELFLUX_WAYLAND=false \
    WINEPREFIX=/config/.wine \
    WINEDEBUG=fixme-all,err-toolbar \
    HARDEN_DESKTOP=true \
    RESTART_APP=true \
    START_DOCKER=false \
    PELORUS=false \
    SELKIES_ALLOWED_ORIGINS= \
    SELKIES_COMMAND_ENABLED=false \
    SELKIES_ENABLE_BASIC_AUTH=false \
    SELKIES_UNIX_SOCKET=/run/selkies/selkies.sock \
    SELKIES_ENABLE_DUAL_MODE=false \
    SELKIES_ENABLE_SHARING=false \
    SELKIES_ENABLE_COLLAB=false \
    SELKIES_PRINTING_ENABLED=false \
    SELKIES_CLIPBOARD_ENABLED=true \
    SELKIES_FILE_TRANSFERS=none \
    SELKIES_AUDIO_ENABLED=false \
    NO_WEBCAM=true \
    NO_GAMEPAD=true \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2

# Wine: WineHQ staging, pinned. The repository key is trusted only if its
# fingerprint matches. The strip and the purge run in this same layer, so what
# they remove doesn't stay behind in it.
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
  winehq-staging=11.19~trixie-1 wine-staging=11.19~trixie-1 \
  wine-staging-amd64=11.19~trixie-1 wine-staging-i386:i386=11.19~trixie-1 \
  osslsigncode=2.9-2
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
  # Wine recognises its own DLLs by this mark, so the strip must keep it.
  for f in "$lib/x86_64-windows/ntdll.dll" "$lib/i386-windows/ntdll.dll"; do
    test "$(head -c 80 "$f" | tail -c 16)" = "Wine builtin DLL"
  done
  echo "Stripped debug information from $count Wine DLLs: $before MB -> $(du -sm "$lib" | cut -f1) MB"
fi

# Docker-in-Docker is never used here (START_DOCKER=false), and these packages
# carried all of the base's fixable HIGH and CRITICAL findings.
apt-get purge -y --auto-remove \
  docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin containerd.io
apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade -y
apt-get clean
rm -rf /var/lib/apt/lists/*

# Debian's "snakeoil" key pair was generated once, when the base was built, so
# every copy of the base has the same one. Nothing here uses it (nginx gets its
# own certificate in /config/ssl). The base's layer still holds it, but gone
# from the filesystem it can't be used by mistake.
find /etc/ssl/certs -lname '*ssl-cert-snakeoil.pem' -delete
rm -f /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/ssl/private/ssl-cert-snakeoil.key
EOF

# Changes to the base's setup. Each edit is checked, so a base update that
# changes these scripts fails here.
# - With host networking, nothing but nginx's port may be reachable. Selkies'
#   socket file is shared with nginx through the group mt5sock (Selkies
#   creates it group-writable), and Xvfb drops its abstract socket, which
#   host networking would share.
# - nginx's health-check socket outlives a killed nginx, which then can't
#   start again, so nginx's start script removes a leftover one first.
RUN <<'EOF'
#!/bin/bash
set -euo pipefail
groupadd --system mt5sock
usermod -aG mt5sock abc
usermod -aG mt5sock www-data

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
sed -i 's|^exec /usr/sbin/nginx |rm -f /run/mt5/health.sock\n&|' "$run"
test "$(grep -c -x 'rm -f /run/mt5/health.sock' "$run")" -eq 1
EOF

COPY root/ /

# The WebView2 installer is verified against exactly these two Microsoft roots:
# Root Certificate Authority 2011 (code signing) and 2010 (timestamps).
RUN <<'EOF'
#!/bin/bash
set -euo pipefail
pem=/opt/mt5/certs/microsoft-roots.pem
expected='847DF6A78497943F27FC72EB93F9A637320A02B561D0A91B09E87A7807ED7C61
DF545BF919A2439C36983B54CDFC903DFA4F37D3996D8D84B4C31EEC6F3C163E'
if grep -v -E '^(-----(BEGIN|END) CERTIFICATE-----|[A-Za-z0-9+/=]+)$' "$pem"; then
  echo "$pem holds more than certificates" >&2
  exit 1
fi
test "$(grep -c -- '-----BEGIN CERTIFICATE-----' "$pem")" -eq 2
tmp="$(mktemp -d)"
awk -v d="$tmp" '/-----BEGIN CERTIFICATE-----/ { n++ } n { print > (d "/" n ".pem") }' "$pem"
actual="$(for f in "$tmp"/*.pem; do openssl x509 -in "$f" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d :; done | sort)"
rm -rf "$tmp"
test "$actual" = "$(sort <<< "$expected")"
EOF

EXPOSE 3001
