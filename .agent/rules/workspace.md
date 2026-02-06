---
trigger: model_decision
description: Workspace paths and source-of-truth path rules
---

# Workspace Rules

- Workspace root: `/Volumes/Data/Code/mine/ABPlayer`
- App source root (relative): `ABPlayer/Sources`
- App source root (absolute): `/Volumes/Data/Code/mine/ABPlayer/ABPlayer/Sources`
- Test root: `ABPlayer/Tests`
- Use `Project.swift` as source-of-truth for buildable folders.

# Path Resolution

- Prefer workspace-relative paths (for example: `ABPlayer/Sources/Views/MainSplitView.swift`).
- If a path comes from docs as `file:///...`, convert it to a filesystem path before reading.
- If a path contains `#L...` anchors, remove the anchor before reading.
- Before reading an uncertain path, verify existence with `glob`.

# Project Management

- Use `Tuist` to manage and generate the Xcode project.
