#!/bin/bash

set -euo pipefail

APP_PATH="${1:-ABPlayer.app}"
KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-notary-abplayer}"
SUBMIT_ZIP="${NOTARY_SUBMIT_ZIP:-ABPlayer-notarize.zip}"
RELEASE_ZIP="${NOTARY_RELEASE_ZIP:-ABPlayer-release.zip}"

if [ ! -d "$APP_PATH" ]; then
	echo "Error: app bundle not found: $APP_PATH"
	echo "Usage: $0 [path-to-app-bundle]"
	exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
	echo "Error: xcrun not found. Install Xcode command line tools first."
	exit 1
fi

if ! command -v ditto >/dev/null 2>&1; then
	echo "Error: ditto not found."
	exit 1
fi

if ! command -v spctl >/dev/null 2>&1; then
	echo "Error: spctl not found."
	exit 1
fi

echo "[1/5] Preparing archive for notarization: $SUBMIT_ZIP"
rm -f "$SUBMIT_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMIT_ZIP"

echo "[2/5] Submitting to Apple notary service (profile: $KEYCHAIN_PROFILE)"
xcrun notarytool submit "$SUBMIT_ZIP" \
	--keychain-profile "$KEYCHAIN_PROFILE" \
	--wait

echo "[3/5] Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "[4/5] Verifying Gatekeeper assessment"
spctl --assess --type execute --verbose=4 "$APP_PATH"

echo "[5/5] Creating release archive: $RELEASE_ZIP"
rm -f "$RELEASE_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$RELEASE_ZIP"

echo "Done. Notarized app: $APP_PATH"
echo "Done. Release zip: $RELEASE_ZIP"
