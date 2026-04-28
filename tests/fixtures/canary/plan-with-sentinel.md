<!--
  FIXTURE — NOT A REAL PLAN.

  This file intentionally contains the yellow-circle emoji (U+1F7E1) in
  the Progress Tracker table row below to test skills/run-plan/scripts/post-run-invariants.sh
  invariant #6 firing. Invariant #6 greps for that character in --plan-file
  and fails if it finds one. The presence of the sentinel here is the whole
  point of the fixture; do NOT "clean" it up.

  Loaded by tests/test-canary-failures.sh invariant #6 fire-case.
-->

# Canary Fixture Plan (with in-progress sentinel)

## Progress Tracker

| Phase              | Status | PR | Notes |
|--------------------|--------|----|-------|
| 1 — first phase    | ✅     |    |       |
| 2 — other          | 🟡     |    |       |
| 3 — last phase     | ⬚     |    |       |
