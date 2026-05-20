---
name: Explore
description: Fast read-only search agent for code exploration. The built-in `subagent_type: "Explore"` ships pinned to Haiku in this environment — this project-level override forces opus to comply with the "never Haiku" rule (CLAUDE.md `## Subagent Dispatch`). When in doubt prefer `subagent_type: "general-purpose"`, which inherits the parent model with no override.
tools: Read, Grep, Glob, Bash
model: opus
---

# Explore subagent (project override)

This file exists solely to override the built-in Explore subagent's Haiku
model frontmatter at the project level. CLAUDE.md `## Subagent Dispatch` is
explicit: never dispatch on Haiku. The built-in `Explore` ships pinned to
Haiku 4.5, so without this override an agent dispatching
`subagent_type: "Explore"` (no explicit `model:` arg) would silently run on
Haiku — and the `block-agents.sh` hook would not catch it because the
hook's Step 2 lookup at `.claude/agents/<subagent_type>.md` would have no
file to read.

This file fixes that bypass: the hook now resolves `Explore` → `model:
opus` and the gate behaves as documented.

When a session genuinely wants the fast Haiku Explore, it must pass
`model: "haiku"` explicitly — which the hook will then deny under the
`agents.min_model` floor (correctly, per the project rule). The right
escape valve for fast read-only search is `subagent_type: "general-
purpose"` with `tools: Read, Grep, Glob` and the parent's inherited model.
