# /draft-tests — worked example

This directory holds purpose-built example plans demonstrating skill
behavior; nothing here is executed by `tests/run-all.sh` or `/run-plan`
— fixtures and worked examples co-locate under `tests/fixtures/` to
keep them out of any future `plans/` glob.

## Files

- `DRAFT_TESTS_EXAMPLE_PLAN_before.md` — a small, illustrative,
  purpose-built plan used to show the before state. **Not** a copy of
  any real `plans/*.md` file.
- `DRAFT_TESTS_EXAMPLE_PLAN.md` — the same plan after a hypothetical
  `/draft-tests` invocation has run against it. One Pending phase has
  gained a `### Tests` subsection. Completed phases are byte-identical
  to the before file.

## Before/after diff

```bash
diff DRAFT_TESTS_EXAMPLE_PLAN_before.md DRAFT_TESTS_EXAMPLE_PLAN.md
```

The diff shows:

1. A `### Tests` subsection appended to the Pending phase (and only the
   Pending phase). The Completed phase is untouched.
2. AC-ID prefixes (`AC-2.1 — `, `AC-2.2 — `) added to the Pending
   phase's bullets that lacked them. The Completed phase's existing
   AC-IDs are unchanged.

## Why these files live under `tests/fixtures/`, not `plans/`

The PLAN_INDEX rebuild scanner (`zskills_monitor.collect`) globs
`plans/*.md` (top-level only). A future change to recursive globbing
would silently surface example plans in the live index. Co-locating
with fixtures is defensive: nothing in tooling globs `tests/fixtures/`,
so example plans cannot accidentally become live plans.

## How they were produced

The "after" file is hand-authored to show the same edits a real
`/draft-tests` invocation would produce on the "before" file. It is
**evidence, not infrastructure** — the test suite asserts the diff
shape (AC-6.3) but does not re-run the skill against the before file
during `tests/run-all.sh`.
