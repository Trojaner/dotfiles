#!/usr/bin/env bash
# Install the Enes Sadık Özbek Root CA into the system trust store on Linux.
# Supports Debian/Ubuntu (update-ca-certificates) and RHEL/Fedora/Arch
# (update-ca-trust).

set -eu -o pipefail

BASE_DIR=$(cd "$(dirname "$0")" && pwd)
CERT_FILE="$BASE_DIR/root-ca.crt"
CERT_NAME="enes-sadik-ozbek-root-ca.crt"

if [ ! -f "$CERT_FILE" ]; then
  echo "Certificate not found: $CERT_FILE" >&2
  exit 1
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

if [ -d /usr/local/share/ca-certificates ] && command -v update-ca-certificates >/dev/null 2>&1; then
  # Debian / Ubuntu
  DEST="/usr/local/share/ca-certificates/$CERT_NAME"
  echo "Installing to $DEST"
  $SUDO install -m 644 "$CERT_FILE" "$DEST"
  $SUDO update-ca-certificates
elif [ -d /etc/pki/ca-trust/source/anchors ] && command -v update-ca-trust >/dev/null 2>&1; then
  # RHEL / Fedora / CentOS / Arch
  DEST="/etc/pki/ca-trust/source/anchors/$CERT_NAME"
  echo "Installing to $DEST"
  $SUDO install -m 644 "$CERT_FILE" "$DEST"
  $SUDO update-ca-trust extract
elif [ -d /etc/ca-certificates/trust-source/anchors ] && command -v trust >/dev/null 2>&1; then
  # Arch / p11-kit fallback
  DEST="/etc/ca-certificates/trust-source/anchors/$CERT_NAME"
  echo "Installing to $DEST"
  $SUDO install -m 644 "$CERT_FILE" "$DEST"
  $SUDO trust extract-compat
else
  echo "Unsupported distribution: no known trust store directory found." >&2
  echo "Install manually with your distribution's CA tools." >&2
  exit 1
fi

echo "Installed Enes Sadık Özbek Root CA into the system trust store."

# Optional: install into per-user NSS DB (Firefox, Chromium on Linux).
if command -v certutil >/dev/null 2>&1; then
  for nssdir in "$HOME"/.pki/nssdb "$HOME"/.mozilla/firefox/*.default* "$HOME"/snap/firefox/common/.mozilla/firefox/*.default*; do
    [ -d "$nssdir" ] || continue
    echo "Adding to NSS DB: $nssdir"
    certutil -A -n "Enes Sadik Ozbek Root CA" -t "CT,C,C" -i "$CERT_FILE" -d "sql:$nssdir" || true
  done
fi
