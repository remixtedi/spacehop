#!/bin/bash
# Creates a local self-signed code signing identity for spacehop, one time.
# Ported from Interspace (cnrad/interspace@87c1c34 scripts/setup-signing.sh, MIT). See AUDIT.md.
#
# macOS ties the Accessibility grant to the signature of the binary. With a stable
# identity the grant stays valid after a rebuild.
#
# The identity lives in its own keychain, so the login keychain is not changed and
# codesign never shows a password prompt. The private key never leaves this Mac.
set -euo pipefail

IDENTITY="spacehop local signing"
KEYCHAIN="$HOME/Library/Keychains/spacehop-signing.keychain-db"
SECRET_DIR="$HOME/.config/spacehop"
SECRET_FILE="$SECRET_DIR/signing-keychain-password"
OPENSSL=/usr/bin/openssl # LibreSSL: writes a PKCS#12 file that `security import` can read

if [ -f "$KEYCHAIN" ] && [ -f "$SECRET_FILE" ] &&
   security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    echo "Signing identity already exists."
    exit 0
fi

umask 077
mkdir -p "$SECRET_DIR"
PASSWORD="$("$OPENSSL" rand -hex 24)"
printf '%s' "$PASSWORD" > "$SECRET_FILE"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.conf" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$IDENTITY" -out "$WORK/identity.p12" -passout "pass:$PASSWORD"

rm -f "$KEYCHAIN"
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN" # no auto-lock timeout
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
# Lets codesign use the key with no prompt.
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null

echo "Created signing identity \"$IDENTITY\" in $KEYCHAIN"
