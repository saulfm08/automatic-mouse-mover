#!/bin/bash
# Build Automatic Mouse Mover as a native, signed .app bundle.
#
#   ./scripts/build.sh            build into ./build
#   ./scripts/build.sh --install  build, then install into /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Automatic Mouse Mover"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

echo "==> Cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling (arm64, optimized)"
# Universal builds are pointless here: the machines that can run macOS 26+
# on Intel cannot run this app's target OS. Keep it lean and native.
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

echo "==> Assembling bundle"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/icon.icns" "$APP/Contents/Resources/icon.icns"

# Signing identity: macOS ties Accessibility permission to the app's code
# signature. An ad-hoc signature (-) changes on every rebuild, which makes the
# system silently drop the grant and the cursor stops moving. If a self-signed
# certificate named "AMM Local Signing" exists in the login keychain we use it,
# so the identity is stable across rebuilds. See scripts/create-signing-cert.sh.
IDENTITY="-"
if security find-certificate -c "AMM Local Signing" >/dev/null 2>&1; then
	IDENTITY="AMM Local Signing"
	echo "==> Signing with stable identity: $IDENTITY"
else
	echo "==> Signing ad-hoc (run scripts/create-signing-cert.sh to keep"
	echo "    Accessibility permission across rebuilds)"
fi

codesign --force --deep --sign "$IDENTITY" \
	--identifier com.pg.amm \
	--options runtime \
	"$APP" 2>&1 | sed 's/^/    /'

echo "==> Verifying"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
ARCH="$(lipo -archs "$APP/Contents/MacOS/amm")"
echo "    architecture: $ARCH"

if [[ "$INSTALL" == "1" ]]; then
	echo "==> Installing to /Applications"
	# Quit any running copy first, or the replace fails with "file busy".
	osascript -e 'quit app "Automatic Mouse Mover"' 2>/dev/null || true
	pkill -x amm 2>/dev/null || true
	sleep 1
	rm -rf "/Applications/$APP_NAME.app"
	cp -R "$APP" "/Applications/$APP_NAME.app"
	echo "    installed: /Applications/$APP_NAME.app"
fi

echo
echo "Done: $APP"
