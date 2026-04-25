# Task Spec: UI Test File Entitlement

## Summary

UI tests should run without triggering a macOS file access authorization dialog for user-selected read/write file access.

## Scope

- Ensure the UI test target declares the file access entitlement needed for user-selected read/write files.
- Ensure the entitlement declaration is part of the Tuist source of truth so regenerated Xcode projects keep the setting.

## Non-Goals

- No changes to app file import behavior.
- No changes to UI test logic.
- No changes to production app entitlements beyond what already exists.

## Requirements

- The UI test bundle must carry `com.apple.security.files.user-selected.read-write`.
- The generated Xcode project must be able to reference the UI test entitlement from `Project.swift`.

## Constraints

- Keep the entitlement scoped to the UI test target.
- Preserve existing target names, bundle identifiers, and test scheme behavior.

## Acceptance Criteria

- `ABPlayerUITests` has a code signing entitlement file configured.
- The entitlement file includes `com.apple.security.files.user-selected.read-write` set to `true`.
- The project builds or the configuration can be regenerated without losing the entitlement setting.

## Related Docs

- [Documentation rules](../../../.agent/rules/doc.md)
- [Workflow rules](../../../.agent/rules/workflow.md)
- [Workspace rules](../../../.agent/rules/workspace.md)
