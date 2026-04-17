<!--
  FIXTURE — NOT A REAL PLAN.

  This file contains the yellow-circle emoji (U+1F7E1) in PROSE only
  (never in a markdown table row starting with '|'). The fixture tests
  that scripts/post-run-invariants.sh invariant #6 does NOT false-positive
  on prose mentions of the sentinel after the row-scoped grep fix.

  If invariant #6 ever regresses to whole-file grep, this fixture will
  fire #6 and the canary regression test will fail.
-->

# Prose-Sentinel Fixture

## Overview

This plan discusses the in-progress sentinel — the 🟡 emoji — extensively
in prose. For instance, the Progress Tracker uses 🟡 to mark a phase
that is currently running. Drift Log entries may also reference 🟡 when
explaining historical phase transitions.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Example | ✅ Done | `abc1234` | all clean |
| 2 — Example | ⬚ | | |

## Drift Log

The phase progression from ⬚ to 🟡 to ✅ tracks:
- ⬚: not started
- 🟡: in progress (mid-execution)
- ✅: done (landed)

This prose must NOT trigger invariant #6 because the table rows above
only contain ✅ and ⬚ — no 🟡 in any row.
