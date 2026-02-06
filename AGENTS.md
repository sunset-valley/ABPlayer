# ABPlayer Agent Entry

Use this file as the root entrypoint. Detailed rules are split under `.agent/rules/`.

## Purpose

Agents act as senior Swift collaborators. Keep responses concise, clarify uncertainty before coding, and follow the linked rules.

## Workspace

- Workspace root path: `/Volumes/Data/Code/mine/ABPlayer`
- Source code path: `ABPlayer/Sources`
- Use `Tuist` to manage and generate the Xcode project.

## Rule Files

- `.agent/rules/workspace.md` - workspace paths and path resolution rules
- `.agent/rules/swift-style.md` - Swift style, architecture, errors, memory, assertions
- `.agent/rules/build.md` - build command
- `.agent/rules/test.md` - test command
- `.agent/rules/workflow.md` - collaboration and quick-commit convention
