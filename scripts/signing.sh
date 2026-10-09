#!/bin/zsh
# Creates (once) a local code-signing identity in a private keychain.
# macOS ties privacy grants to the signature's designated requirement; an
# ad-hoc signature changes on every build, a fixed certificate does not.
set -euo pipefail
cd "$(dirname "$0")/.."

DIR="$PWD/.signing"
KC="$DIR/savisul.keychain-db"
NAME="SAVISUL Local Signing"

mkdir -p "$DIR"
chmod 700 "$DIR"

if [[ ! -f "$DIR/password" ]]; then
  /usr/bin/openssl rand -hex 24 > "$DIR/password"
  chmod 600 "$DIR/password"
fi
PASS="$(cat "$DIR/password")"

if [[ ! -f "$KC" ]]; then
  security create-keychain -p "$PASS" "$KC"
  security set-keychain-settings "$KC"
fi
security unlock-keychain -p "$PASS" "$KC"

# codesign only finds identities on the user's keychain search list.
if ! security list-keychains -d user | grep -q "$KC"; then
  CURRENT=("${(@f)$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')}")
  security list-keychains -d user -s "${CURRENT[@]}" "$KC"
fi

if ! security find-identity -p codesigning "$KC" | grep -q "$NAME"; then
  cat > "$DIR/cert.cnf" << EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
O = SAVISUL
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -config "$DIR/cert.cnf" 2>/dev/null
  P12PASS="$(/usr/bin/openssl rand -hex 12)"
  /usr/bin/openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
    -name "$NAME" -out "$DIR/identity.p12" -passout "pass:$P12PASS"
  security import "$DIR/identity.p12" -k "$KC" -P "$P12PASS" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null
  rm -f "$DIR/key.pem" "$DIR/identity.p12"
  touch "$DIR/fresh-identity"
fi

echo "$KC"
