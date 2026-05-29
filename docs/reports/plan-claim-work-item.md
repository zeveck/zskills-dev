# Plan Report — Ownership-aware work-item claims (#803)

## Phase — 1 Shared self-re-entry helper + wire into both twins + tests

**Plan:** docs/plans/claim-work-item.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-claim-work-item (branch `feat/claim-work-item`)
**Commit:** `49e705a`

### Work Items
| # | Item | Status | Notes |
|---|------|--------|-------|
| W1.1 | Helper `claim-self-reentry.sh` | Done | bash subprocess; absent/malformed claim.json → 10 (never steal); release-style try/except reader; no jq |
| W1.2 | `_locate_self_reentry()` in both twins | Done | mirrors `_locate_sanitizer()` precedence verbatim |
| W1.3 | Wire `claim-issue.sh` EEXIST arm | Done | helper subprocess; not-locatable → WARN + return 10 |
| W1.4 | Wire `claim-plan.sh` EEXIST arm | Done | identical shape |
| W1.5 | Both headers: D3 exit-code contract | Done | acquire 0/2/10/11, release 0/2/12 |
| W1.6 | `tests/test-claim-self-reentry.sh` | Done | 15 cases: helper unit (incl. truncated→10), both-kind integration, worktree-cwd MAIN_ROOT proof |
| W1.7 | Version bump + mirror (create-worktree, fix-issues, run-plan) | Done | `2026.05.29` ×3; hashes match; mirrors byte-equal |
| W1.8 | No script-ownership / STALE_LIST churn | Done | `grep claim script-ownership.md` = 0 |

### Verification
- Full suite: **`Overall: 6485/6485 passed, 0 failed`** (baseline 6470 + 15 new cases).
- Verifier (separate agent) confirmed each W-item; Layer 3 response-validation passed.
- Known pre-existing flake (`test_zskills_monitor_collect.sh` worktree-portable case, #150/#759) reads the live claim during dogfooding; did NOT fire on the committed run; green standalone (71/71) and on a clean full-suite re-run.
- No plan-text drift detected.
- Constraints honored: no jq; MAIN_ROOT via caller's git-common-dir (never `$PWD`); no TTL/heartbeat/sweep; no caller-interface/schema/script-name changes; no conformance assertion weakened.

### Landing
Bundled-PR mode (`finish auto`): commits accumulate on `feat/claim-work-item`; PR opens/merges once after the final phase.
