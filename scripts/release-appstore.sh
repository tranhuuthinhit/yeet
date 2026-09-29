#!/usr/bin/env bash
# Command-line alternative to Xcode's Product → Archive → Distribute App.
# Builds the sandboxed Mac App Store version of Yeet and uploads it to App Store Connect.
#
#   ./scripts/release-appstore.sh            archive + upload to App Store Connect
#   ./scripts/release-appstore.sh --export   archive + export a signed .pkg to build/AppStore (no upload)
#
# Config: scripts/appstore.env (see appstore.env.example) or environment variables.
# Requires: Xcode 15.3+, a paid Apple Developer account,
#           and an app record for bundle id vn.stevetran.yeet in App Store Connect.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE=upload
[[ "${1:-}" == "--export" ]] && MODE=export

[[ -f scripts/appstore.env ]] && set -a && source scripts/appstore.env && set +a

: "${TEAM_ID:?TEAM_ID is missing (set it in scripts/appstore.env)}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
BUNDLE_ID="vn.stevetran.yeet"

ARCHIVE="build/Yeet-AppStore.xcarchive"
EXPORT_DIR="build/AppStore"
OPTIONS="build/ExportOptions-AppStore.plist"
mkdir -p build

# App Store Connect API key → xcodebuild authentication (also lets automatic signing
# create the App ID / provisioning profile on the fly).
AUTH=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
  [[ -f "$ASC_KEY_PATH" ]] || { echo "✗ API key not found: $ASC_KEY_PATH"; exit 1; }
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  echo "▸ Authenticating with App Store Connect API key $ASC_KEY_ID"
else
  echo "▸ Authenticating with the Apple ID signed in to Xcode (Settings → Accounts)"
fi

echo "▸ Archive AppStore  v$MARKETING_VERSION ($BUILD_NUMBER)"
rm -rf "$ARCHIVE"
xcodebuild archive \
  -project Yeet.xcodeproj -scheme Yeet -configuration AppStore \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  | { command -v xcpretty >/dev/null && xcpretty || cat; }

# Sanity checks before handing it to Apple.
APP="$ARCHIVE/Products/Applications/Yeet.app"
[[ -d "$APP" ]] || { echo "✗ Archive does not contain Yeet.app"; exit 1; }
codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "com.apple.security.app-sandbox" \
  || { echo "✗ App Sandbox is not enabled in the AppStore build"; exit 1; }
ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
[[ "$ID" == "$BUNDLE_ID" ]] || { echo "✗ Bundle id is $ID, expected $BUNDLE_ID"; exit 1; }
echo "✓ Archive OK: $ID, sandbox enabled"

DESTINATION=upload
[[ $MODE == export ]] && DESTINATION=export
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$DESTINATION</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "▸ Export ($DESTINATION)"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTIONS" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

if [[ $MODE == upload ]]; then
  echo "✓ Uploaded v$MARKETING_VERSION ($BUILD_NUMBER) to App Store Connect."
  echo "  The build shows up in TestFlight / App Store once Apple finishes processing it (usually 5–30 minutes)."
else
  echo "✓ Exported package: $(ls "$EXPORT_DIR"/*.pkg 2>/dev/null || echo "$EXPORT_DIR")"
  echo "  Upload it with the Transporter app or: xcrun altool --upload-package <pkg> ..."
fi
