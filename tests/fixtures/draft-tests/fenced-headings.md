---
title: Fenced-Headings Fixture
created: 2026-04-29
status: active
---

# Plan: Fenced Headings

## Overview

A fixture plan with a Completed phase whose body contains a fenced
` ```markdown ` block with `## Example Section` at column 0 inside the
fence. The Completed phase's checksum MUST include the fenced lines (a
naive `^## ` scan would terminate the prior phase's checksum at the
in-code heading, silently dropping authentic phase content from the
gate).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Embedded | Done | aaa1111 | done |
| 2 — Pending | ⬚ | | pending |

---

## Phase 1 — Embedded

### Goal

A Completed phase containing a fenced markdown block with an in-code
level-2 heading.

### Work Items

- [ ] 1.1 — set up.

The drafter prompt should look like the following Markdown example:

```markdown
## Example Section

This `## Example Section` heading appears at column 0 inside a fenced
code block. The boundary scan MUST NOT terminate the Completed phase
here; the bytes are part of Phase 1's authored body.
```

After the fenced block, more authored prose MUST also be included in
Phase 1's checksum.

### Acceptance Criteria

- [ ] AC-1.1 — the fenced block is part of Phase 1.

### Dependencies

None.

---

## Phase 2 — Pending

### Goal

A Pending phase.

### Work Items

- [ ] 2.1 — do something.

### Acceptance Criteria

- [ ] criterion to be ID-prefixed (assign AC-2.1).

### Dependencies

Phase 1.
