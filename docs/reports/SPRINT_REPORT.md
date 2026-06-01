---
title: /fix-issues Sprint Report
status: complete
---

# /fix-issues sprint — sprint-20260601-001427-dq30m3

**Mode:** N=2, dashboard, auto, every 30m
**Picks:** #864 + #863 (both claimed clean, claim-before-worktree discipline)

## Landed (2)

### #864 — /do pr holds claim during pr-ready window
- **PR:** https://github.com/zeveck/zskills-dev/pull/890 — merged clean (no rebase needed)
- **Files (5):** `skills/do/modes/pr.md` 3-group case-arm split (merged → RELEASE, pr-ready|created → HOLD with stderr advisory citing manual-reap command, terminal-failure → RELEASE, unknown → HOLD-with-WARN); `skills/do/SKILL.md` version bump to `12f9ca`; mirrors; new `tests/test-do-pr-claim-release.sh` (+205 lines, 15 assertions covering all 10 LAND_OUTCOME values + source-drift guard).
- **Tests:** 6653/6653.

### #863 — /do + /quickfix parse all #N + fan-out claim ops
- **PR:** https://github.com/zeveck/zskills-dev/pull/894 — merged after auto-rebase resolved a non-trivial conflict with PR #890 (#864) at `skills/do/modes/pr.md:530`.
- **Files (18, +1223/-410):** parser scalar → `ISSUE_NUMS` array in both `skills/do/SKILL.md` and `skills/quickfix/SKILL.md`; fan-out at 3 acquire sites with partial-rollback on rc=10; fan-out at 9 release sites (4 in /do, 5 in /quickfix); back-compat `$ISSUE_NUM = ${ISSUE_NUMS[0]:-}` preserved; conformance sentinels updated; new `tests/test-do-quickfix-multi-issue-fanout.sh` (16 cases) + multi-issue parse assertions in `tests/test-do.sh` and `tests/test-quickfix.sh`; version bumps to `fda0cc` (/do, later re-bumped `065fb4` post-merge), `c444a9` (/quickfix).
- **Tests:** 6692/6692 pre-rebase; post-rebase both new suites 15/15 + 16/16 verified.

## Sprint mechanics — multi-region conflict resolution this fire

PR #894's rebase hit a non-trivial 35-line conflict block at `skills/do/modes/pr.md:530-577`. The two changes overlapped on the same case-arm region:
- **`HEAD` side (#864, just landed):** 3-group LAND_OUTCOME case-arm with HOLD semantics for `pr-ready|created`.
- **Theirs side (#863):** uniform release-all loop iterating `ISSUE_NUMS`.

Naïve `checkout --theirs` would have **dropped #864's HOLD semantics** (which had just shipped 30 min earlier). Per memory `feedback_single_region_rebase_conflict_edit_directly` + the user's earlier warning ("Be careful you didn't lose something of theirs in the process"), resolved by **manually merging both improvements** — wrapped #864's case-arm logic inside #863's `for _ISSUE_N in "${ISSUE_NUMS[@]}"` loop. Post-resolution both new test suites pass (15/15 + 16/16); content from neither side dropped. Version re-bumped to `065fb4` to reflect the post-merge content hash.

## Sprint metadata

- Sprint pipeline ID: fix-issues.sprint-20260601-001427-dq30m3
- Sprint worktree: /tmp/zskills-fix-issues-sprint-20260601-001427-dq30m3
- Issue claims released cleanly.
- Cron: `*/30 * * * *` — next fire ~30 min.
