# ABPlayer Agent Entry

Use this file as the first stop before coding.

- Trigger repository-local skills from `.agent/skills/*` before falling back to global skills.
- Apply repository-local rules from `.agent/rules/*` for coding, build, test, and workflow behavior.

## Quick Facts

```
Workspace Root: /Volumes/Data/Code/mine/ABPlayer
Source Root:    /Volumes/Data/Code/mine/ABPlayer/ABPlayer/Sources
Test Root:      /Volumes/Data/Code/mine/ABPlayer/ABPlayer/Tests
Build Tool:     Tuist
Platform:       macOS 15.7+ | Swift 6.2 | SwiftUI
```

## Agent Startup Checklist

1. Check `.agent/skills/` and trigger any repository-local skill that matches the task.
2. Read [`.agent/rules/workspace.md`](.agent/rules/workspace.md) to confirm paths and `Project.swift` source-of-truth.
3. If editing Swift code, read [`.agent/rules/swift-style.md`](.agent/rules/swift-style.md).
4. If touching ViewModel/View/Model boundaries, read [`.agent/rules/mvvm.md`](.agent/rules/mvvm.md).
5. Build and test with the commands in [`.agent/rules/build.md`](.agent/rules/build.md) and [`.agent/rules/test.md`](.agent/rules/test.md).
6. For commit/collaboration behavior, follow [`.agent/rules/workflow.md`](.agent/rules/workflow.md).

## Decision Map

| Task                            | Read First       | Why                                             |
| ------------------------------- | ---------------- | ----------------------------------------------- |
| Resolve path / locate file      | `workspace.md`   | Avoid wrong paths and align with project layout |
| Add or refactor Swift code      | `swift-style.md` | Match code conventions and Swift 6.2 patterns   |
| Change MVVM responsibilities    | `mvvm.md`        | Keep layer boundaries and testability           |
| Build after changes             | `build.md`       | Use project-standard build command              |
| Run test suite                  | `test.md`        | Use project-standard test command               |
| Handle ambiguity / quick commit | `workflow.md`    | Follow collaboration and commit conventions     |
| Create or update documentation  | `doc.md`         | Follow doc routing, naming, and quality rules   |

## Rules Reference

```
.agent/
|-- rules/
    |-- workspace.md     # Paths, Project.swift, Tuist workflow
    |-- swift-style.md   # Swift style, concurrency, errors, memory
    |-- mvvm.md          # MVVM contract and boundaries
    |-- build.md         # Build command
    |-- test.md          # Test command
|   |-- workflow.md      # Collaboration + quick-commit convention
|   `-- doc.md           # Documentation routing, naming, and quality
`-- skills/              # Repository-local skill definitions (trigger when relevant)
```

## Command Quick Reference

- Build: `xcodebuild -workspace ABPlayer.xcworkspace -scheme ABPlayer -destination 'platform=macOS' build 2>&1 | tail -20`
- Test: `tuist test`

## Rule Triggers

| File             | Trigger          | Core Topics                                           |
| ---------------- | ---------------- | ----------------------------------------------------- |
| `workspace.md`   | `model_decision` | Root/source/test paths, path resolution, Tuist        |
| `swift-style.md` | `model_decision` | `@Observable`, `async/await`, typed errors, DI        |
| `mvvm.md`        | `mvvm_decision`  | Input/Output, `transform(input:)`, testing boundaries |
| `build.md`       | `model_decision` | Build command                                         |
| `test.md`        | `model_decision` | Test command                                          |
| `workflow.md`    | `model_decision` | Ambiguity handling, quick-commit format               |
| `doc.md`         | `model_decision` | Doc routing, naming, structure, archival              |
