# Plan Report — plans-claim-chip-parity

## Phase — 1 Claim primitive + on-disk schema + PreToolUse hook

**Plan:** plans/plans-claim-chip-parity.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-plans-claim-chip-parity (branch `feat/plans-claim-chip-parity`)
**Commit:** `9c8fd56`

### Work Items
| # | Item | Status | Notes |
|---|------|--------|-------|
| W1.1 | claim-plan.sh primitive (acquire/refresh/release/is-stale/sweep/list) | Done | 663 lines; 7-field D5 schema; sibling-clone of claim-issue.sh + new `refresh` subcommand |
| W1.2 | claim-fence-helpers.sh (`sweep_stale_plan_claims`) | Done | 26 lines |
| W1.3 | block-run-plan-unclaimed.sh PreToolUse hook | Done | 256 lines; cp- + feat/ branch regex (non-greedy slug capture); reads `branch_prefix` via inline Python json |
| W1.4 | update-zskills SKILL.md Step 3.7.1 (plan_claim_ttl_seconds backfill) | Done | Idempotent sed detection regex mirrors 3.7 |
| W1.5 | tests/test-plan-claim-script.sh | Done | 19 tests pass |
| W1.6 | tests/test-plan-claim-race-baseline.sh | Done | 2 tests pass |
| W1.7 | tests/test-plan-claim-ttl-config-resolver.sh | Done | 8 tests pass (5 levels + 2 floor + no-config-file) |
| W1.8 | skills/run-plan/SKILL.md metadata.version bump | Done | 2026.05.22+7ae04d |
| W1.9 | tests/test-plan-claim-hook-deny.sh | Done | 9 tests pass — 4 branch shapes (cp-, cp-…-phase-1, cp-…-phase-12, feat/) × claim absent/present + negative control |
| W1.10 | tests/test-plan-claim-main-root-anchor.sh | Done | 4 tests pass — acquire/refresh/release from worktree anchor to MAIN |

### Verification
- **Full test suite**: `Overall: 5415/5415 passed, 0 failed` (baseline 5371; +44 from new Phase 1 tests + 2 conformance picks).
- **Acceptance criteria** (verifier-confirmed with file:line citations):
  - AC1.1 PASS — 7 D5 schema fields written
  - AC1.2 PASS — race baseline: 1 exit 0 + 1 exit 10
  - AC1.3 PASS — pipeline-mismatch refresh exits 12 without mutation
  - AC1.4 PASS — hook denies all 4 branch shapes, all consult same plan-scoped dir
  - AC1.5 PASS — SKILL.md metadata.version matches today + content hash
  - AC1.6 PASS — claim writes anchor to MAIN_ROOT from worktree CWD (DA7)
- **Locked decisions**: D1 (sibling-clone) / D5 (storage+schema) / D7 (hook regex+config-read pattern) / DA13 (slug sanitisation) / TTL 5-level chain — all conform.

### Notes
- Verifier added 5 `run_suite` lines to `tests/run-all.sh` to register the new test files. Without registration the suite would have skipped them entirely. In-scope addition.
- No prose changes to `skills/run-plan/SKILL.md` (only metadata.version) — Phase 2a owns that prose.
- Test output: `/tmp/zskills-tests/zskills-pr-plans-claim-chip-parity/.test-results.txt`.
