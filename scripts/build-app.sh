#!/usr/bin/env bash
# Build the direct-distribution Yeet.app (no sandbox) from the Swift package.
# For the Mac App Store build use ./scripts/release-appstore.sh
#   ./scripts/build-app.sh            -> build/Yeet.app (release)
#   ./scripts/build-app.sh --install  -> also copy to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

echo "▸ swift build -c release"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Yeet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Yeet" "$APP/Contents/MacOS/Yeet"
# Info.plist uses Xcode build variables – fill them in for the SwiftPM build.
VERSION="${MARKETING_VERSION:-1.0.0}"
BUILD="${BUILD_NUMBER:-1}"
sed -e "s/\$(EXECUTABLE_NAME)/Yeet/" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/vn.stevetran.yeet/" \
    -e "s/\$(MARKETING_VERSION)/$VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD/" \
    Support/Info.plist > "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Support/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"

# Signing. macOS ties the Full Disk Access grant to the code signature:
#  - with a real certificate (Apple Development / Developer ID) the grant survives rebuilds;
#  - with an ad-hoc signature every rebuild looks like a *new* app and the grant is lost.
# Override with: SIGN_IDENTITY="Apple Development: Name (TEAMID)" ./scripts/build-app.sh
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi
if [[ -n "$IDENTITY" ]]; then
  echo "▸ codesign with \"$IDENTITY\""
  codesign --force --deep --options runtime --entitlements Support/Yeet.entitlements --sign "$IDENTITY" "$APP"
else
  echo "▸ codesign ad-hoc (no certificate found)"
  codesign --force --deep --sign - "$APP"
  echo "  ⚠︎ Ad-hoc: Full Disk Access must be granted again after every rebuild."
  echo "    Quick reset: tccutil reset SystemPolicyAllFiles vn.stevetran.yeet, then add Yeet.app again"
fi
echo "✓ Built $APP"

if [[ $INSTALL == 1 ]]; then
  rm -rf "/Applications/Yeet.app"
  cp -R "$APP" /Applications/
  echo "✓ Installed to /Applications/Yeet.app"
fi
