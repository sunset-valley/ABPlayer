# Task Plan: UI Test File Entitlement

## Implementation Plan

1. Add a dedicated entitlements file for the UI test target.
2. Point the `ABPlayerUITests` target at that file through `Project.swift`.
3. Inspect the changed files and run a lightweight project generation/build verification if practical.

## Verification Plan

- Run `tuist generate` or inspect generated project settings after generation.
- Run a focused build of the UI test target if generation succeeds.
- Skip full UI test execution unless required, because the requested change is build configuration only.

## Risks / Open Questions

- The authorization dialog may also depend on the host app, runner app, or TCC state. The production and dev app entitlement already includes read/write access, so this task scopes the fix to the UI test target as requested.

## Progress Log

- 2026-04-25: Created plan and began configuration update.
- 2026-04-25: Added UI test entitlements, regenerated the project, and verified `build-for-testing`.
