# 0004 — FFmpeg Bundle & Notarization Playbook

## Summary

ABPlayer currently downloads ffmpeg at runtime to `~/.abplayer/bin/ffmpeg` and executes it via `Foundation.Process`. This approach breaks under Hardened Runtime because macOS quarantines downloaded executables and Gatekeeper may block unsigned or unverified binaries. The correct solution for notarization is to **bundle a Developer-ID-signed ffmpeg binary inside the app**, eliminating the runtime download entirely. This playbook covers the full chain: binary preparation → Tuist bundling → code changes → signing/entitlements → notarization workflow.

---

## Background: Why Runtime Download Breaks

When Hardened Runtime is enabled (`ENABLE_HARDENED_RUNTIME = YES`):

- Files downloaded over the network receive the `com.apple.quarantine` extended attribute.
- macOS routes quarantined executables through Gatekeeper before first run.
- Unsigned or improperly signed binaries are silently blocked.
- Clearing quarantine programmatically from within an app requires invasive entitlements that Apple dislikes.

Bundling the binary avoids all of this: it is signed as part of the app, notarization covers it, and no quarantine xattr is ever set.

---

## Architecture Decision

**Bundle a static, codesigned ffmpeg binary at `Contents/MacOS/ffmpeg`.**

| Option | Size impact | User friction | Notarization risk | Verdict |
|---|---|---|---|---|
| Bundle signed binary | +~90 MB | None | None | ✅ Recommended |
| Runtime download | 0 | Low (auto) | High (quarantine) | ❌ Breaks |
| Homebrew detection only | 0 | High (manual install) | None | ⚠️ Fallback only |
| FFmpegKit XCFramework | +250–500 MB | None | None | ❌ Too heavy |

The updated priority order in `effectiveFFmpegPath()`:
1. User-configured custom path (override for power users)
2. **Bundled binary** (`Bundle.main.url(forAuxiliaryExecutable: "ffmpeg")`) ← new primary
3. System paths (Homebrew: `/opt/homebrew/bin/ffmpeg`, `/usr/local/bin/ffmpeg`)
4. ~~Runtime download~~ (removed)

---

## Phase 1 — Prepare the FFmpeg Binary

### 1.1 Create preparation script

Create `scripts/prepare-ffmpeg.sh`. This script downloads static ffmpeg builds for arm64 and x86_64, combines them into a Universal binary, and codesigns it.

```bash
#!/usr/bin/env bash
# Usage: APPLE_IDENTITY="Developer ID Application: ..." ./scripts/prepare-ffmpeg.sh
set -euo pipefail

DEST="ABPlayer/Resources/Helpers/ffmpeg"
FFMPEG_VERSION="7.1"   # update as needed

ARM_URL="https://evermeet.cx/ffmpeg/ffmpeg-${FFMPEG_VERSION}.zip"
X64_URL="https://evermeet.cx/pub/ffmpeg/ffmpeg-${FFMPEG_VERSION}.zip"

echo "Downloading arm64 build..."
curl -L "$ARM_URL" -o /tmp/ffmpeg-arm64.zip
unzip -o /tmp/ffmpeg-arm64.zip ffmpeg -d /tmp/ffmpeg-arm64/

echo "Downloading x86_64 build..."
curl -L "$X64_URL" -o /tmp/ffmpeg-x64.zip
unzip -o /tmp/ffmpeg-x64.zip ffmpeg -d /tmp/ffmpeg-x64/

echo "Creating Universal binary..."
mkdir -p "$(dirname "$DEST")"
lipo -create \
  /tmp/ffmpeg-arm64/ffmpeg \
  /tmp/ffmpeg-x64/ffmpeg \
  -output "$DEST"

echo "Signing with Hardened Runtime..."
codesign --force --options runtime \
  --sign "${APPLE_IDENTITY}" \
  "$DEST"

echo "Verifying..."
codesign --verify --deep --strict "$DEST"
echo "✓ ffmpeg prepared at $DEST"
```

> **Note:** evermeet.cx may serve the same URL for both architectures. Check their download page and adjust URLs if they provide separate arm64/x86_64 endpoints. If only arm64 is needed (macOS 26.0+ is Apple Silicon only), skip the `lipo` step.

### 1.2 Gitignore the binary

Add to `.gitignore`:
```
ABPlayer/Resources/Helpers/ffmpeg
```

The binary is large (~90 MB) and must not be committed. CI downloads and signs it fresh each build.

---

## Phase 2 — Bundle ffmpeg via Tuist

In `Project.swift`, add a `copyFiles` action to both `ABPlayer` and `ABPlayerDev` targets to place the binary in `Contents/MacOS/` (the directory searched by `Bundle.main.url(forAuxiliaryExecutable:)`):

```swift
.target(
  name: "ABPlayer",
  // ... existing config ...
  copyFiles: [
    .init(
      destination: .executables,
      files: [.glob(pattern: "ABPlayer/Resources/Helpers/ffmpeg")]
    )
  ],
  dependencies: [ /* existing */ ]
)
```

The `.executables` destination maps to `Contents/MacOS/`. Tuist will include the file in the app bundle during the build phase.

> **Important:** The `ffmpeg` file must exist on disk before `tuist generate` and `xcodebuild` run. In CI, run `scripts/prepare-ffmpeg.sh` before the build step.

---

## Phase 3 — Code Changes

### 3.1 Update `effectiveFFmpegPath()` in `TranscriptionSettings.swift`

Replace the current method body (lines 409–418):

```swift
func effectiveFFmpegPath() -> String? {
  // 1. User override
  if !ffmpegPath.isEmpty, Self.isFFmpegValid(at: ffmpegPath) {
    return ffmpegPath
  }
  // 2. Bundled binary (primary – notarization-safe)
  if let bundledURL = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"),
     Self.isFFmpegValid(at: bundledURL.path) {
    return bundledURL.path
  }
  // 3. System install (Homebrew fallback)
  return Self.autoDetectFFmpegPath()
}
```

### 3.2 Remove / deprecate runtime download

The `downloadFFmpeg(progress:)` method and associated UI can be removed or hidden behind a compile-time flag. The `isFFmpegDownloaded`, `downloadedFFmpegPath`, `deleteDownloadedFFmpeg()`, and `effectiveFFmpegDownloadURL` properties become dead code once the bundled path is the primary source. Remove them to reduce surface area.

If a migration grace period is desired, keep `downloadedFFmpegPath` as a fallback between step 2 and step 3 above and show a deprecation banner in Settings.

---

## Phase 4 — Entitlements & Hardened Runtime

### 4.1 Create `ABPlayer/Resources/ABPlayer.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- URLSession: Sparkle updates, Sentry, TelemetryDeck, HuggingFace model downloads -->
  <key>com.apple.security.network.client</key>
  <true/>
  <!-- User-opened media files (open panel) -->
  <key>com.apple.security.files.user-selected.read-only</key>
  <true/>
  <!-- Read files the user drags or opens from arbitrary locations -->
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
</dict>
</plist>
```

> Do **not** add `com.apple.security.app-sandbox` — the app is not sandboxed. Adding it without full sandbox hardening will break the app.

Consult `0003_macos-distribution-compliance.md` for the full entitlements checklist including Sparkle XPC requirements.

### 4.2 Update `Project.swift` base build settings

```swift
settings: .settings(
  base: [
    "SWIFT_VERSION": "6.2",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "CODE_SIGN_STYLE": "Manual",
    "CODE_SIGN_IDENTITY": "Developer ID Application",
    "CODE_SIGN_ENTITLEMENTS": "ABPlayer/Resources/ABPlayer.entitlements",
    "DEVELOPMENT_TEAM": "<YOUR_TEAM_ID>",
  ],
  configurations: [
    .debug(name: "Debug"),
    .release(name: "Release"),
  ]
)
```

---

## Phase 5 — CI Notarization Workflow

### 5.1 GitHub Actions secrets required

| Secret | Value |
|---|---|
| `APPLE_SIGNING_CERTIFICATE` | Base64-encoded `.p12` (Developer ID Application) |
| `APPLE_SIGNING_CERTIFICATE_PASSWORD` | `.p12` password |
| `APPLE_ID` | Apple ID email for notarytool |
| `APPLE_ID_PASSWORD` | App-specific password |
| `APPLE_TEAM_ID` | 10-character team ID |

### 5.2 Release build steps (in order)

```bash
# 1. Install signing certificate into keychain
echo "$APPLE_SIGNING_CERTIFICATE" | base64 --decode > cert.p12
security import cert.p12 -k ~/Library/Keychains/login.keychain \
  -P "$APPLE_SIGNING_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign

# 2. Prepare ffmpeg binary
APPLE_IDENTITY="Developer ID Application: ... ($APPLE_TEAM_ID)" \
  ./scripts/prepare-ffmpeg.sh

# 3. Generate Tuist project
tuist generate --no-open

# 4. Archive
xcodebuild archive \
  -workspace ABPlayer.xcworkspace \
  -scheme ABPlayer \
  -destination 'generic/platform=macOS' \
  -archivePath build/ABPlayer.xcarchive \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID"

# 5. Export for Developer ID distribution
xcodebuild -exportArchive \
  -archivePath build/ABPlayer.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist scripts/ExportOptions.plist

# 6. Notarize
xcrun notarytool submit build/export/ABPlayer.app \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_ID_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

# 7. Staple
xcrun stapler staple build/export/ABPlayer.app

# 8. Package (DMG or zip for Sparkle)
# ... existing release.sh packaging steps
```

### 5.3 `scripts/ExportOptions.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
  <key>teamID</key>
  <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

---

## Verification Checklist

After a successful notarized build:

- [ ] `codesign --verify --deep --strict ABPlayer.app` — exits 0
- [ ] `codesign -dv --verbose=4 ABPlayer.app/Contents/MacOS/ffmpeg` — shows `runtime` flag and Developer ID identity
- [ ] `spctl --assess --type exec -vv ABPlayer.app` — shows `accepted`
- [ ] `xcrun stapler validate ABPlayer.app` — shows `The validate action worked`
- [ ] Launch app on a clean macOS user account; open a video file; trigger transcription — ffmpeg runs without Gatekeeper dialog
- [ ] `effectiveFFmpegPath()` returns a path inside `ABPlayer.app/Contents/MacOS/`

---

## Related Docs

- [0003_macos-distribution-compliance.md](0003_macos-distribution-compliance.md) — Full compliance checklist (Hardened Runtime, entitlements, Sparkle, Sentry PII)
