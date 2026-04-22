---
trigger: model_decision
description: Documentation routing and naming rules for Docs/
---

# Documentation Rules

- Write documentation in English.
- Place documents only under `Docs/specs`, `Docs/specs_finished`, `Docs/knowledge-graph`, `Docs/knowledge-mem-exchange`, `Docs/mem-backbone`, or `Docs/postmortem`.
- Use this filename format for all new non-spec docs: `NNNN_short-topic.md`.
- Use this directory format for all task specs: `Docs/specs/NNNN_short-topic/`.
- `NNNN` must be a 4-digit zero-padded number (for example: `0001`, `0042`, `0120`).
- Every task spec directory must contain `spec.md` and `plan.md`.
- Exception: `Docs/specs/TEMPLATE/` is the reusable task spec template directory and does not consume a numeric ID.

## File ID Management via `.config`

Each doc subdirectory contains a `.config` file that tracks the next available numeric ID:

```
nextId=5
```

**Workflow for creating a new doc:**

1. Read `Docs/<target-dir>/.config` to get `nextId`.
2. Use that value (zero-padded to 4 digits) as the filename or task spec directory prefix.
3. For non-spec docs, write the new `NNNN_short-topic.md` file.
4. For task specs, create `Docs/specs/NNNN_short-topic/spec.md` and `Docs/specs/NNNN_short-topic/plan.md` from `Docs/specs/TEMPLATE/`.
5. Increment `nextId` by 1 and write the updated value back to `.config`.

**Collision handling:** If a file or task spec directory with that prefix already exists (e.g., concurrent sessions), increment `nextId` and retry until the prefix is unique, then save the final incremented value to `.config`.

# Directory Decision Guide

- `Docs/knowledge-graph`: Durable project knowledge (architecture, domain concepts, data flow, module maps, key contracts).
- `Docs/knowledge-mem-exchange`: Session-to-session handoff notes (current context, pending decisions, short-term continuity).
- `Docs/mem-backbone`: Reusable operating memory (repeatable workflows, stable conventions, command playbooks, checklists). Playbook-style docs should use numbered steps with prerequisites and expected output.
- `Docs/postmortem`: Failure analysis (incident timeline, root cause, impact, mitigation, prevention actions).
- `Docs/specs`: Per-task directories that separate product goals (`spec.md`) from implementation planning (`plan.md`) before implementation starts.
- `Docs/specs_finished`: Completed task spec directories moved from `Docs/specs` after manual finish/archive action.

# When To Create Or Update Docs

- Create or update a `specs` task directory before starting any development task that changes Swift source, tests, build configuration, app behavior, or user-visible behavior.
- Keep active/in-progress task specs in `Docs/specs`.
- When a task spec is completed, move the entire `Docs/specs/NNNN_short-topic/` directory to `Docs/specs_finished/NNNN_short-topic/` and keep the directory name unchanged.
- `Docs/specs_finished` is archive-only for completed task specs and does not use a `.config` counter for new ID allocation.
- Create or update `knowledge-graph` docs when introducing or changing architecture, module boundaries, or core domain behavior.
- Create or update `knowledge-mem-exchange` docs at task handoff, context switching, or when unresolved decisions must be carried forward.
- Create or update `mem-backbone` docs when a pattern is repeated and should become a standard operating rule.
- Create or update `postmortem` docs after bugs, regressions, outages, failed releases, or major debugging efforts.
- When a doc is obsolete, move it to a `Docs/<directory>/archive/` subfolder. Do not delete docs outright.
- Archive docs are out of scope for routine updates/cleanup unless explicitly requested.

# Document Structure Template

Every doc should include at minimum:

- **Summary**: One-paragraph overview of the topic.
- **Details**: Main content with clear headings.
- **Related Docs**: Relative markdown links to related docs (e.g., `[see also](../postmortem/0003_foo.md)`).

# Task Spec Directory Template

Use `Docs/specs/TEMPLATE/` when creating a new task spec directory.

`spec.md` should include:

- **Summary**: User-visible outcome and why it matters.
- **Scope**: What is included in this task.
- **Non-Goals**: What is explicitly excluded.
- **Requirements**: Observable behavior, assumptions, and constraints.
- **Constraints**: Product, platform, compatibility, accessibility, performance, or data constraints.
- **Acceptance Criteria**: Concrete conditions for completion.
- **Related Docs**: Links to relevant specs, knowledge docs, postmortems, or playbooks.

Task specs should constrain goals, outcomes, boundaries, and verification. Do not prescribe implementation details, internal structure, file changes, class names, algorithms, or UI layout details unless the user explicitly requires them or they are fixed project constraints.

`plan.md` should include:

- **Implementation Plan**: Ordered development steps.
- **Verification Plan**: Focused tests, manual checks, and any intentionally skipped coverage.
- **Risks / Open Questions**: Issues that may change execution.
- **Progress Log**: Short updates as implementation proceeds.

# Content Quality Rules

- Keep documents factual, concise, and actionable.
- Prefer explicit sections with clear headings instead of long prose.
- Record decisions with rationale and follow-up actions.
- Link related docs across directories using relative markdown links (e.g., `[see also](../postmortem/0003_foo.md)`).
- Avoid duplication; update the existing doc when the topic already exists.
- **Write for a reader who is not already in your head.** Start with the user-visible behavior or outcome, then explain the mechanism. Do not lead with implementation chains, async internals, or code paths — those go at the end if needed at all. If a non-expert reader cannot understand the first paragraph, rewrite it.
