#!/usr/bin/env bash
# verify-signature.sh metaquotes|microsoft <file>
#
# Checks an installer's Authenticode signature before it runs. It passes only
# when osslsigncode verifies the primary signature, timestamp and revocation
# lists included, and the signer's organisation is exactly MetaQuotes Ltd or
# Microsoft Corporation. Exit code 0: passed; 1: refused; 2: wrong usage.
#   metaquotes  mt5setup.exe, against Debian's CA bundle. osslsigncode fetches
#               DigiCert's revocation lists itself.
#   microsoft   the WebView2 installer, against the two Microsoft roots pinned
#               in the image. Microsoft serves its revocation lists in a way
#               osslsigncode's own download refuses, so they're fetched here.
# No file hash is pinned: the signature is the check, and MetaQuotes and
# Microsoft replace their files without notice.
set -euo pipefail

roots=/opt/mt5/certs/microsoft-roots.pem
microsoft_crls=http://www.microsoft.com/pkiops/crl

log() { printf '%s [mt5] %s\n' "$(date -u +%FT%TZ)" "$*"; }
refuse() {
  log "REFUSED: $(basename "$file") $*"
  exit 1
}

if (( $# != 2 )) || [[ "$1" != metaquotes && "$1" != microsoft ]]; then
  echo "Usage: verify-signature.sh metaquotes|microsoft <file>" >&2
  exit 2
fi
kind="$1"
file="$2"
[[ -f "$file" ]] || refuse "doesn't exist."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

log "$(basename "$file"): $(stat -c %s "$file") bytes, SHA-256 $(sha256sum "$file" | cut -d' ' -f1)"

# -index 0: the primary signature. The WebView2 installer also carries a
# second, self-signed one, Microsoft's internal "EdgeBuild" signature.
args=(verify -index 0)
if [[ "$kind" == metaquotes ]]; then
  organisation="MetaQuotes Ltd"
  args+=(-CAfile /etc/ssl/certs/ca-certificates.crt)
else
  organisation="Microsoft Corporation"
  # The signer's certificate comes through Code Signing PCA 2011 or PCA 2024
  # (newer installers), the timestamp's through Time-Stamp PCA 2010.
  crl() {
    curl -fsS --retry 3 --retry-all-errors --retry-delay 5 --connect-timeout 30 --max-time 120 \
      -o "$tmp/crl.der" "$microsoft_crls/$1" &&
      openssl crl -inform DER -in "$tmp/crl.der" >> "$2"
  }
  if ! { crl MicCodSigPCA2011_2011-07-08.crl "$tmp/signer.crl" &&
    crl 'Microsoft%20Code%20Signing%20PCA%202024.crl' "$tmp/signer.crl" &&
    crl 'Microsoft%20Time-Stamp%20PCA%202010(1).crl' "$tmp/timestamp.crl"; }; then
    refuse "can't be checked: Microsoft's revocation lists couldn't be fetched from $microsoft_crls/."
  fi
  # -ignore-cdp: only these lists, no download attempts of osslsigncode's own.
  args+=(-CAfile "$roots" -TSA-CAfile "$roots" -CRLfile "$tmp/signer.crl"
    -TSA-CRLfile "$tmp/timestamp.crl" -ignore-cdp)
fi

# osslsigncode's own fetch of DigiCert's lists makes one attempt, and its first
# lookup of the server's name sometimes fails. Only that is retried.
for attempt in 1 2 3; do
  rc=0
  report="$(timeout 120 osslsigncode "${args[@]}" -in "$file" 2>&1)" || rc=$?
  if (( rc == 0 )) || ! grep -q -E 'HTTP failure|Faile?d to get CRL' <<< "$report"; then
    break
  fi
  if (( attempt < 3 )); then
    log "a revocation list couldn't be fetched; checking again in 5 s"
    sleep 5
  fi
done

# The first "Subject:" and "Issuer :" after "Signer's certificate:" belong to
# the primary signature's signer, as /C=../O=../CN=.. fields.
signer="$(awk '/^Signer.s certificate:/ { s = 1 } s && /Subject:/ { sub(/^[ \t]*Subject: */, ""); print; exit }' <<< "$report")"
issuer="$(awk '/^Signer.s certificate:/ { s = 1 } s && /Issuer *:/ { sub(/^[ \t]*Issuer *: */, ""); print; exit }' <<< "$report")"
timestamp="$(awk '/^[ \t]*Timestamp time:/ { sub(/^[ \t]*Timestamp time: */, ""); print; exit }' <<< "$report")"

if (( rc != 0 )) || ! grep -q -x 'Signature verification: ok' <<< "$report"; then
  log "osslsigncode's report:"
  while IFS= read -r line; do
    printf '    %s\n' "$line"
  done <<< "$report"
  refuse "failed its signature check (osslsigncode exit code $rc)."
fi
# A whole field, so that "O=MetaQuotes Ltd2" doesn't pass.
IFS=/ read -r -a fields <<< "$signer"
signed_by=no
for field in "${fields[@]}"; do
  [[ "$field" == "O=$organisation" ]] && signed_by=yes
done
if [[ "$signed_by" != yes ]]; then
  refuse "has a valid signature, but not from $organisation: $signer"
fi
log "signature ok: signed by $signer, through ${issuer##*/CN=}, timestamp ${timestamp:-none}"
