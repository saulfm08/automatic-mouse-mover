#!/bin/bash
# Build, sign, notarize and package a distributable release.
#
#   ./scripts/release.sh 2.0.0
#
# Requires, one time only:
#   1. A "Developer ID Application" certificate in the login keychain.
#      Create it at https://developer.apple.com/account/resources/certificates/add
#      (see docs/RELEASING.md — it needs a CSR generated on this Mac).
#   2. A stored notarytool credential profile named "AMM":
#      xcrun notarytool store-credentials "AMM" \
#          --apple-id saulfm08@gmail.com \
#          --team-id B3CW6K4QQ3 \
#          --password <app-specific-password>
#
# Without these the script stops before producing anything, rather than
# emitting an artifact that would be rejected on every downloader's Mac.
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
	echo "usage: $0 <version>   e.g. $0 2.0.0" >&2
	exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Automatic Mouse Mover"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/AutomaticMouseMover-$VERSION.zip"
DMG="$DIST/AutomaticMouseMover-$VERSION.dmg"
NOTARY_PROFILE="AMM"

# --- Preflight -------------------------------------------------------------

# `|| true` is required: grep exits non-zero when it matches nothing, and
# `set -e` would kill the script here before the explanatory error below runs.
IDENTITY="$(security find-identity -v -p codesigning \
	| grep "Developer ID Application" \
	| head -1 \
	| sed -E 's/.*"(.+)"/\1/' || true)"

if [[ -z "$IDENTITY" ]]; then
	cat >&2 <<-'MSG'
	ERROR: No "Developer ID Application" certificate found.

	This is the only certificate type that can notarize an app for
	distribution outside the App Store. "Apple Development" and
	"Apple Distribution" certificates cannot.

	See docs/RELEASING.md for how to create one.
	MSG
	exit 1
fi
echo "==> Signing identity: $IDENTITY"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
	cat >&2 <<-MSG
	ERROR: No notarytool credential profile named "$NOTARY_PROFILE".

	Create one with:
	  xcrun notarytool store-credentials "$NOTARY_PROFILE" \\
	      --apple-id saulfm08@gmail.com \\
	      --team-id B3CW6K4QQ3 \\
	      --password <app-specific-password>

	See docs/RELEASING.md.
	MSG
	exit 1
fi

# --- Build -----------------------------------------------------------------

echo "==> Building $VERSION"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc \
	-O -whole-module-optimization \
	-target arm64-apple-macos13.0 \
	-framework AppKit \
	-framework CoreGraphics \
	-framework ApplicationServices \
	-framework IOKit \
	-o "$APP/Contents/MacOS/amm" \
	"$ROOT/Sources/AMM/Settings.swift" \
	"$ROOT/Sources/AMM/IdleAssertion.swift" \
	"$ROOT/Sources/AMM/MouseMover.swift" \
	"$ROOT/Sources/AMM/AppDelegate.swift" \
	"$ROOT/Sources/AMM/main.swift"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/icon.icns" "$APP/Contents/Resources/icon.icns"

# Stamp the requested version so the bundle matches the release tag.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

# --- Sign ------------------------------------------------------------------

# The hardened runtime is mandatory for notarization.
echo "==> Signing"
codesign --force --timestamp --options runtime \
	--sign "$IDENTITY" \
	"$APP"

codesign --verify --strict --verbose=2 "$APP"

# --- Notarize --------------------------------------------------------------

echo "==> Submitting for notarization (this usually takes 1-5 minutes)"
ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" \
	--keychain-profile "$NOTARY_PROFILE" \
	--wait

# Staple the ticket into the bundle so it validates offline, then rebuild the
# zip from the stapled app — the submitted zip does not contain the ticket.
echo "==> Stapling"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# --- Package DMG -----------------------------------------------------------

echo "==> Building DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" \
	-srcfolder "$STAGE" \
	-ov -format UDZO \
	"$DMG" >/dev/null
rm -rf "$STAGE"

# The DMG is signed and stapled separately from the app inside it.
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# --- Verify ----------------------------------------------------------------

echo
echo "==> Verification (what a downloader's Mac will decide)"
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/    /'
xcrun stapler validate "$APP" 2>&1 | sed 's/^/    /'

echo
echo "Artifacts:"
echo "  $ZIP"
echo "  $DMG"
