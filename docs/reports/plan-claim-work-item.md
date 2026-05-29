# Plan Report — Ownership-aware work-item claims (#803)

## Phase — 2 Wire /do, /quickfix, /investigate onto claim-issue.sh

**Plan:** docs/plans/claim-work-item.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-claim-work-item (branch `feat/claim-work-item`)
**Commit:** `bffe378`

### Work Items
| # | Item | Status | Notes |
|---|------|--------|-------|
| W2.1 | /investigate acquire/release | Done | synth `investigate.issue-$N`; acquire before reproduction; success-path + per-STOP releases |
| W2.2 | /do worktree+direct | Done | issue parsed via `--force`; acquire after `do.${TASK_SLUG}`+worktree; release in **Phase 5 Report** (not Phase 4 Land); direct synthesizes `do.<issue>` |
| W2.3 | /do PR mode | Done | acquire at A5.5; finalize release; **C2 inline-releases at all 3 pre-finalize exits** (exit 5/2/1); no HOLD-on-created |
| W2.4 | /quickfix | Done | reuse `quickfix.$SLUG`; acquire at Tracking-setup before branch; release in Phase 7 finalize + fail sites |
| W2.5 | Version bump + mirror (do/quickfix/investigate) | Done | `2026.05.29` ×3; hashes match; mirrors byte-equal |
| W2.6 | Conformance sentinels | Done | +17 positive assertions; FAIL if wiring dropped; no existing assertion weakened |

### Verification
- Full suite: **`Overall: 6502/6502 passed, 0 failed`** (baseline 6485 + 17 sentinels). Verified by separate agent; Layer 3 validation passed; known monitor-collect flake did not fire.
- C1/M1 (no acquire before non-empty PIPELINE_ID + bare-integer issue) holds at all 5 acquire sites; foreign→STOP (not next-candidate); no jq; no forbidden literals.

### Advisory note (plan-text drift, non-numeric — not auto-corrected)
The plan's W2.1 calls `/investigate`'s reproduction-skip (≈:74-88) an "abandon point" needing a release. In reality that gate **proceeds** with lower confidence (not an abandon); the genuine couldn't-reproduce abandon is covered by the Report-section catch-all release. Release coverage is therefore complete. Minor plan-accuracy note; no behavioral gap.

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
