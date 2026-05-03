#!/usr/bin/env bash
# Install the Enes Sadık Özbek Root CA into the macOS System keychain
# and trust it for SSL, code signing, and any other policies.

set -eu -o pipefail

BASE_DIR=$(cd "$(dirname "$0")" && pwd)
CERT_FILE="$BASE_DIR/root-ca.crt"

if [ ! -f "$CERT_FILE" ]; then
  echo "Certificate not found: $CERT_FILE" >&2
  exit 1
fi

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script is intended for macOS." >&2
  exit 1
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

echo "Adding Enes Sadık Özbek Root CA to /Library/Keychains/System.keychain (will prompt for sudo)..."
$SUDO security add-trusted-cert \
  -d \
  -r trustRoot \
  -k /Library/Keychains/System.keychain \
  "$CERT_FILE"

echo "Installed. Verify with:"
echo "  security find-certificate -c 'Enes Sadık Özbek' /Library/Keychains/System.keychain"
