# UI Testing Gate Playbook

## Summary

This playbook defines the repository standard for UI testing: UI tests are a release gate, and all UI tests must pass before a task is considered complete. The goal is to catch interaction regressions early and keep annotation-related workflows reliable.

## Details

### Policy

1. Treat UI tests as required verification, not optional checks.
2. Do not merge code when any UI test is failing.
3. New UI behavior must include or update UI tests in the same change.
4. If a test is flaky, fix the root cause or stabilize the test before shipping.

### Standard Commands

1. Preferred full test command:
   - `tuist test -- -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData"`
2. Optional focused UI test run:
   - `xcodebuild test -workspace ABPlayer.xcworkspace -scheme ABPlayer-Workspace -destination 'platform=macOS,arch=arm64' -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData" -only-testing:ABPlayerUITests`

### Why `derivedDataPath` Is Required

Use `-derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData"` to avoid macOS automation permission prompts triggered when test runners are built from removable/external volumes. This keeps UI tests non-blocking and repeatable.

### Completion Checklist

1. Run the full test command with the internal derived data path.
2. Confirm all UI tests in `ABPlayerUITests` pass.
3. If a UI test fails, fix test/app behavior and rerun until green.
4. Record any new UI test assumptions in docs when needed.

### Annotation Menu Baseline

Current baseline for annotation-menu UI automation is `ABPlayer/UITests/AnnotationMenuUITests.swift` with these required passing cases:

- `testAddStyle`
- `testRenameStyle`
- `testChangeKind`
- `testCannotDeleteUsedStyle`

## Related Docs

- [Project structure](../knowledge-graph/0001_project-structure.md)
- [Annotation style system redesign](../knowledge-graph/0005_annotation-style-system-redesign.md)
- [Test rule](../../.agent/rules/test.md)
