#!/bin/bash
# Create a self-signed code-signing certificate so rebuilds keep a stable
# identity — and therefore keep their Accessibility permission.
#
# Without this, every rebuild is signed ad-hoc with a fresh identity, macOS
# treats it as a different app, and the cursor silently stops moving until you
# re-grant permission by hand.
#
# This creates a local certificate only. It does not make the app notarized or
# distributable; it just keeps macOS's permission bookkeeping happy.
set -euo pipefail

CERT_NAME="AMM Local Signing"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
	echo "Certificate \"$CERT_NAME\" already exists. Nothing to do."
	exit 0
fi

echo "Creating a self-signed code-signing certificate: $CERT_NAME"
echo
echo "Keychain Access will open. Do this:"
echo "  1. Menu: Keychain Access > Certificate Assistant >"
echo "           Create a Certificate..."
echo "  2. Name:          $CERT_NAME"
echo "  3. Identity Type: Self Signed Root"
echo "  4. Certificate Type: Code Signing"
echo "  5. Click Create, then Done."
echo
echo "Then re-run ./scripts/build.sh --install"
echo

open -a "Keychain Access"
