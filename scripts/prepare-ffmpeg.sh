#!/usr/bin/env bash
# Prepare a universal ffmpeg binary signed with Hardened Runtime.
# Usage: APPLE_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/prepare-ffmpeg.sh
#
# Requires: curl, unzip, lipo, codesign
# Output:   ABPlayer/Resources/Helpers/ffmpeg  (universal binary, codesigned)
set -euo pipefail

DEST="Binaries/ffmpeg"
FFMPEG_VERSION="${FFMPEG_VERSION:-7.1}"

ARM_URL="https://evermeet.cx/ffmpeg/ffmpeg-${FFMPEG_VERSION}.zip"

echo "Downloading arm64 build (${FFMPEG_VERSION})..."
curl -L "$ARM_URL" -o /tmp/ffmpeg-arm64.zip

echo "Unzipping..."
rm -rf /tmp/ffmpeg-arm64
unzip -o /tmp/ffmpeg-arm64.zip ffmpeg -d /tmp/ffmpeg-arm64/

mkdir -p "$(dirname "$DEST")"
cp /tmp/ffmpeg-arm64/ffmpeg "$DEST"

echo "Signing with Hardened Runtime..."
codesign --force --options runtime \
  --sign "${APPLE_IDENTITY}" \
  "$DEST"

echo "Verifying..."
codesign --verify --deep --strict "$DEST"
echo "✓ ffmpeg prepared at $DEST"
