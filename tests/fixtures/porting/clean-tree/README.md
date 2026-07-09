# Ported tree — clean fixture

A fully ported page: no Claude-lane constructs anywhere, so the gate passes
with zero violations and zero unknowns.

The runner schedules recurring fires itself, children are dispatched via
`codex exec`, and bundled scripts resolve from the repo root.

```bash
codex exec --json "run the next phase" -o /tmp/last.txt
```
