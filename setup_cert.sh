#!/bin/bash
# Einmalig ausführen: Erzeugt ein Self-Signed Code-Signing Zertifikat
# Danach bleiben Berechtigungen über App-Updates erhalten.

CERT_NAME="LutrisForMac Development"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "Zertifikat '$CERT_NAME' existiert bereits."
    exit 0
fi

echo "Erzeuge Code-Signing Zertifikat '$CERT_NAME' …"

TMPDIR=$(mktemp -d)
cd "$TMPDIR"

cat > cert.conf << 'EOF'
[v3_req]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
  -days 3650 -nodes \
  -subj "/CN=$CERT_NAME" \
  -config cert.conf -extensions v3_req 2>/dev/null

openssl pkcs12 -export -in cert.pem -inkey key.pem \
  -out cert.p12 -passout pass:123 -legacy 2>/dev/null

security import cert.p12 -k ~/Library/Keychains/login.keychain -P 123 -A 2>/dev/null

cp cert.pem /tmp/lutris_cert.pem
security add-trusted-cert -d -r trustRoot -p codeSign -p basic /tmp/lutris_cert.pem 2>/dev/null

cd /
rm -rf "$TMPDIR"

echo "Zertifikat '$CERT_NAME' wurde angelegt und ist bereit."
echo "Jetzt mit 'bash sign.sh' signieren."
