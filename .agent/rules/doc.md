---
trigger: model_decision
description: Documentation routing and naming rules for Docs/
---

# Documentation Rules

- Write documentation in English.
- Place documents only under `Docs/knowledge-graph`, `Docs/knowledge-mem-exchange`, `Docs/mem-backbone`, or `Docs/postmortem`.
- Use this filename format for all new docs: `NNNN_short-topic.md`.
- `NNNN` must be a 4-digit zero-padded number (for example: `0001`, `0042`, `0120`).

## File ID Management via `.config`

Each doc subdirectory contains a `.config` file that tracks the next available numeric ID:

```
nextId=5
```

**Workflow for creating a new doc:**

1. Read `Docs/<target-dir>/.config` to get `nextId`.
2. Use that value (zero-padded to 4 digits) as the filename prefix.
3. Write the new doc file.
4. Increment `nextId` by 1 and write the updated value back to `.config`.

**Collision handling:** If a file with that prefix already exists (e.g., concurrent sessions), increment `nextId` and retry until the prefix is unique, then save the final incremented value to `.config`.

# Directory Decision Guide

- `Docs/knowledge-graph`: Durable project knowledge (architecture, domain concepts, data flow, module maps, key contracts).
- `Docs/knowledge-mem-exchange`: Session-to-session handoff notes (current context, pending decisions, short-term continuity).
- `Docs/mem-backbone`: Reusable operating memory (repeatable workflows, stable conventions, command playbooks, checklists). Playbook-style docs should use numbered steps with prerequisites and expected output.
- `Docs/postmortem`: Failure analysis (incident timeline, root cause, impact, mitigation, prevention actions).

# When To Create Or Update Docs

- Create or update `knowledge-graph` docs when introducing or changing architecture, module boundaries, or core domain behavior.
- Create or update `knowledge-mem-exchange` docs at task handoff, context switching, or when unresolved decisions must be carried forward.
- Create or update `mem-backbone` docs when a pattern is repeated and should become a standard operating rule.
- Create or update `postmortem` docs after bugs, regressions, outages, failed releases, or major debugging efforts.
- When a doc is obsolete, move it to a `Docs/<directory>/archive/` subfolder. Do not delete docs outright.

# Document Structure Template

Every doc should include at minimum:

- **Summary**: One-paragraph overview of the topic.
- **Details**: Main content with clear headings.
- **Related Docs**: Relative markdown links to related docs (e.g., `[see also](../postmortem/0003_foo.md)`).

# Content Quality Rules

- Keep documents factual, concise, and actionable.
- Prefer explicit sections with clear headings instead of long prose.
- Record decisions with rationale and follow-up actions.
- Link related docs across directories using relative markdown links (e.g., `[see also](../postmortem/0003_foo.md)`).
- Avoid duplication; update the existing doc when the topic already exists.
