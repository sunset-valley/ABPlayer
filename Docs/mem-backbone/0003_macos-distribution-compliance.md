# macOS Distribution Compliance Checklist

## Summary

ABPlayer is distributed outside the Mac App Store via Developer ID signing and Notarization (evidenced by the Sparkle auto-update integration). This document captures the compliance gaps found during the March 2026 audit and provides a checklist to reach a notarizable, shippable state. Items are ordered by priority — blocking issues must be resolved before `xcrun notarytool submit` will succeed.

---

## Distribution Path

| Channel | Status |
|---------|--------|
| Direct download (Developer ID + Notarization) | Target path |
| Mac App Store | **Not applicable** — Sparkle is incompatible with App Store rules |

---

## TODO: Blocking Issues (Notarization will fail without these)

- [ ] **Enable Hardened Runtime** (`Project.swift`)
  - Add `"ENABLE_HARDENED_RUNTIME": true` to the Release configuration's base settings.
  - Required by `xcrun notarytool` since macOS Catalina; submissions without it are rejected.

- [ ] **Create `ABPlayer.entitlements`** (`ABPlayer/Resources/ABPlayer.entitlements`)
  - Minimum required entries:
    - `com.apple.security.network.client = true` (URLSession outbound connections)
    - `com.apple.security.files.user-selected.read-only = true` (user-opened audio/video files)
  - Reference from `Project.swift` via `CODE_SIGN_ENTITLEMENTS` build setting.
  - Verify that `URLSessionProxyInjector`'s `method_exchangeImplementations` usage still works under Hardened Runtime. Method swizzling is generally permitted, but test after enabling.

- [ ] **Switch code signing to Developer ID Application** (`Project.swift` Release config)
  - Current value: `CODE_SIGN_IDENTITY = "-"` (ad hoc — cannot be notarized)
  - Required value: `CODE_SIGN_IDENTITY = "Developer ID Application"`
  - Also set `CODE_SIGN_STYLE = "Manual"` and `DEVELOPMENT_TEAM = "<your-team-id>"` in Release.

- [ ] **Create `PrivacyInfo.xcprivacy`** (`ABPlayer/Resources/PrivacyInfo.xcprivacy`)
  - Required for App Store and strongly expected for all distributions since May 2024.
  - Minimum declarations needed:
    - `NSPrivacyAccessedAPICategoryUserDefaults` → reason `CA92.1` (app's own preferences)
    - `NSPrivacyAccessedAPICategoryFileTimestamp` → reason `C617.1` (file timestamps shown to user)
  - Set `NSPrivacyTracking = false` and `NSPrivacyTrackingDomains = []`.
  - Add `NSPrivacyCollectedDataTypes` entry for crash data (Sentry).

---

## TODO: High-Priority Issues (Rejection risk or user trust)

- [ ] **Migrate Sparkle appcast to HTTPS and remove ATS exception** (`Project.swift:27-38`)
  - Current: `SUFeedURL = "https://s3.kcoding.cn/..."` with `NSExceptionAllowsInsecureHTTPLoads = true`
  - The URL already uses `https://`, but the ATS exception domain `s3.kcoding.cn` has `NSExceptionAllowsInsecureHTTPLoads = true`, which opens the door to HTTP downgrade.
  - Action: Confirm the CDN enforces HTTPS (no HTTP redirect), then delete the `NSAppTransportSecurity` dictionary from `infoPlist` entirely.
  - Sparkle's EdDSA signing (`SUPublicEDKey`) protects update integrity, but a clean ATS configuration avoids notarization flags.

- [ ] **Disable `sendDefaultPii` in Sentry or make it opt-in** (`ABPlayerApp.swift:163`)
  - Current: `options.sendDefaultPii = true` — sends IP addresses and device identifiers to Sentry's US servers.
  - Action: Change to `false`. If PII data is needed for debugging, add a user-facing opt-in toggle in Settings.
  - Required disclosure in privacy policy regardless of setting.

---

## TODO: Medium-Priority Issues (UX / future hardening)

- [ ] **Address FFmpeg runtime download and execution**
  - The app downloads `ffmpeg` from `evermeet.cx` at runtime, writes it to `~/.abplayer/bin/`, sets `0o755`, and runs it via `Process()`.
  - On macOS Ventura+, Gatekeeper will quarantine unsigned downloaded executables. Users will see a system security dialog on first run.
  - Options (choose one):
    1. Bundle a pre-signed, pre-notarized `ffmpeg` binary inside `ABPlayer.app/Contents/Resources/`.
    2. Guide users to install via Homebrew and detect it at the standard paths (already supported: `/opt/homebrew/bin/ffmpeg`, `/usr/local/bin/ffmpeg`).
    3. Download and immediately run `xattr -d com.apple.quarantine` — fragile and requires entitlement.
  - Option 2 is the lowest-effort path if FFmpeg bundling is too large.

- [ ] **Validate custom download endpoints**
  - `transcription_download_endpoint` (UserDefaults) and the FFmpeg mirror URL are user-configurable.
  - Currently no URL validation; a malicious or misconfigured value could redirect model/binary downloads.
  - Add a domain allowlist or at minimum enforce HTTPS scheme before use.

---

## Context and Rationale

| Finding | File | Risk |
|---------|------|------|
| No Hardened Runtime | `Project.swift` | Notarization rejection |
| No entitlements file | — | Notarization rejection; missing network/file declarations |
| Ad-hoc code signing | `Project.swift` | Notarization rejection |
| No `PrivacyInfo.xcprivacy` | — | App Store rejection; expected for all distributions |
| ATS HTTP exception | `Project.swift:31` | Notarization flag; potential MITM on update feed |
| `sendDefaultPii = true` | `ABPlayerApp.swift:163` | PII data sent to US servers without explicit disclosure |
| FFmpeg runtime download | Services layer | Gatekeeper quarantine dialog on first run |
| Unconstrained custom endpoints | UserDefaults | Open redirect to untrusted sources |

---

## Not Applicable (if staying outside App Store)

The following issues only apply to Mac App Store submissions and do **not** block Developer ID notarization:

- Removing Sparkle
- Enabling App Sandbox
- Restricting `Process()` / subprocess execution
- Restricting Objective-C runtime swizzling

---

## Related Docs

- Architecture overview: [`../knowledge-graph/`](../knowledge-graph/)
- Workflow and commit conventions: [`.agent/rules/workflow.md`](../../.agent/rules/workflow.md)
