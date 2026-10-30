#!/usr/bin/env bash
# verify-signature.sh metaquotes|microsoft|python <file>
#
# Verifies Authenticode signatures, timestamps, CRLs, and exact Subject O:
#   metaquotes -> mt5setup.exe against system CA bundle
#   microsoft  -> WebView2 installer against pinned microsoft-roots.pem
#   python     -> Python installer against pinned microsoft-identity-root.pem
# Exit codes: 0 = valid signature, 1 = verification failed, 2 = usage error.
set -euo pipefail

certs=/opt/mt/certs
microsoft_crls=http://www.microsoft.com/pkiops/crl

log() { printf '%s [mt] %s\n' "$(date -u +%FT%TZ)" "$*"; }
refuse() {
  log "REFUSED: $(basename "$file") $*"
  exit 1
}

if (( $# != 2 )) || [[ "$1" != metaquotes && "$1" != microsoft && "$1" != python ]]; then
  echo "Usage: verify-signature.sh metaquotes|microsoft|python <file>" >&2
  exit 2
fi
kind="$1"
file="$2"
[[ -f "$file" ]] || refuse "doesn't exist."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Extracts signature certificates into $tmp/cert-<n>.pem.
certs_split=no
signature_certs() {
  if [[ "$certs_split" == no ]]; then
    osslsigncode extract-signature -pem -in "$file" -out "$tmp/sig.pem" > /dev/null 2>&1 || return 1
    openssl pkcs7 -in "$tmp/sig.pem" -print_certs 2> /dev/null |
      awk -v d="$tmp" '/-----BEGIN CERTIFICATE-----/ { n++ } n { print > (d "/cert-" n ".pem") }' ||
      return 1
    certs_split=yes
  fi
}

log "$(basename "$file"): $(stat -c %s "$file") bytes, SHA-256 $(sha256sum "$file" | cut -d' ' -f1)"

# -index 0 selects the primary signature (ignores internal EdgeBuild signature).
args=(verify -index 0)
if [[ "$kind" == metaquotes ]]; then
  organisation="MetaQuotes Ltd"
  args+=(-CAfile /etc/ssl/certs/ca-certificates.crt)
else
  crl() {
    curl -fsS --retry 3 --retry-all-errors --retry-delay 5 --connect-timeout 30 --max-time 120 \
      -o "$tmp/crl.der" "$microsoft_crls/$1" &&
      openssl crl -inform DER -in "$tmp/crl.der" >> "$2"
  }
  if [[ "$kind" == microsoft ]]; then
    organisation="Microsoft Corporation"
    roots="$certs/microsoft-roots.pem"
    # Fetch CRLs for Code Signing PCAs and Time-Stamp PCA 2010.
    crl_ok=no
    if crl MicCodSigPCA2011_2011-07-08.crl "$tmp/signer.crl" &&
      crl 'Microsoft%20Code%20Signing%20PCA%202024.crl' "$tmp/signer.crl" &&
      crl 'Microsoft%20Time-Stamp%20PCA%202010(1).crl' "$tmp/timestamp.crl"; then
      crl_ok=yes
    fi
  else
    organisation="Python Software Foundation"
    roots="$certs/microsoft-identity-root.pem"
    # Discover intermediate CRL from signer cert (Identity Verification PKI hierarchy).
    issuer_crl=
    if signature_certs; then
      issuer_crl="$(openssl pkcs7 -in "$tmp/sig.pem" -print_certs -text -noout 2> /dev/null |
        sed -n -E "s|^ *URI:$microsoft_crls/(Microsoft%20ID%20Verified%20CS%20[A-Z]{3}%20CA%20[0-9]{2}\\.crl)\$|\1|p" |
        head -n 1)" || true
    fi
    if [[ -z "$issuer_crl" ]]; then
      refuse "has no signature through Microsoft's ID Verified code signing, which signs Python's installers."
    fi
    crl_ok=no
    if crl 'Microsoft%20Identity%20Verification%20Root%20Certificate%20Authority%202020.crl' "$tmp/signer.crl" &&
      crl 'Microsoft%20ID%20Verified%20Code%20Signing%20PCA%202021.crl' "$tmp/signer.crl" &&
      crl "$issuer_crl" "$tmp/signer.crl" &&
      crl 'Microsoft%20Identity%20Verification%20Root%20Certificate%20Authority%202020.crl' "$tmp/timestamp.crl" &&
      crl 'Microsoft%20Public%20RSA%20Timestamping%20CA%202020.crl' "$tmp/timestamp.crl"; then
      crl_ok=yes
    fi
  fi
  if [[ "$crl_ok" != yes ]]; then
    refuse "can't be checked: Microsoft's revocation lists couldn't be fetched from $microsoft_crls/."
  fi
  # -ignore-cdp: use only explicitly provided CRLs.
  args+=(-CAfile "$roots" -TSA-CAfile "$roots" -CRLfile "$tmp/signer.crl"
    -TSA-CRLfile "$tmp/timestamp.crl" -ignore-cdp)
fi

# Retry on transient CRL lookup failure.
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

# Extract signer Subject, Issuer, and Timestamp.
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
# Parse exact organizationName from matching signer certificate.
serial="$(awk '/^Signer.s certificate:/ { s = 1 } s && /Serial *:/ { sub(/^[ \t]*Serial *: */, ""); print; exit }' <<< "$report")"
matches=0
if [[ -n "$serial" ]] && signature_certs; then
  for cert in "$tmp"/cert-*.pem; do
    [[ -f "$cert" && "$(openssl x509 -in "$cert" -noout -serial 2> /dev/null)" == "serial=$serial" ]] || continue
    if openssl x509 -in "$cert" -noout -subject -nameopt multiline 2> /dev/null |
      ORGANISATION="$organisation" awk '
        { i = index($0, " = "); name = substr($0, 1, i - 1); gsub(/^ +| +$/, "", name) }
        i && name == "organizationName" && substr($0, i + 3) == ENVIRON["ORGANISATION"] { found = 1 }
        END { exit !found }'; then
      matches=$((matches + 1))
    else
      matches=0
      break
    fi
  done
fi
if (( matches == 0 )); then
  refuse "has a valid signature, but not from $organisation: $signer"
fi
log "signature ok: signed by $signer, through ${issuer##*/CN=}, timestamp ${timestamp:-none}"
