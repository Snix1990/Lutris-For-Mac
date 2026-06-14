#!/bin/bash
# Signiert beide Apps mit Self-Signed Zertifikat
# Berechtigungen bleiben so über Rebuilds erhalten.

CERT_NAME="LutrisForMac Development"

# Hole SHA-1 Hash (eindeutig, vermeidet "ambiguous")
CERT_HASH=$(security find-identity -v -p codesigning 2>/dev/null | grep "$CERT_NAME" | head -1 | awk '{print $2}')

if [ -z "$CERT_HASH" ]; then
    echo "Zertifikat '$CERT_NAME' nicht gefunden. Führe 'bash setup_cert.sh' aus."
    bash "$(dirname "$0")/setup_cert.sh"
    CERT_HASH=$(security find-identity -v -p codesigning 2>/dev/null | grep "$CERT_NAME" | head -1 | awk '{print $2}')
fi

if [ -z "$CERT_HASH" ]; then
    echo "FEHLER: Konnte kein Signatur-Zertifikat erstellen."
    exit 1
fi

for app in "/Users/mac/Desktop/LutrisForMac.app" "/Users/mac/Desktop/LutrisForMacWIP.app"; do
    codesign --force --deep --sign "$CERT_HASH" "$app" 2>&1 | grep -v "replacing existing signature"
done
echo "Signiert mit $CERT_NAME ($CERT_HASH)"
