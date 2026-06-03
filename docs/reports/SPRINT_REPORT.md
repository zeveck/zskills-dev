---
title: /fix-issues Sprint Report
status: complete
---

# /fix-issues sprint — sprint-20260601-080624-dq30m8

**Mode:** N=2, dashboard, auto, every 30m
**Picks:** #920 + #924

## Landed (2)

### #920 — claim parser accepts "Fix issue #N"
- **PR:** https://github.com/zeveck/zskills-dev/pull/934 — merged after auto-rebase (BEHIND on first poll).
- **Fix:** Added optional `(issue[s]?:?[[:space:]]+)?` filler between close-keyword and `#N` at all 3 regex sites (leading-anchored, strong-sep loop, weak-sep loop) shared as `_DO_ISSUE_FILLER` / `_QF_ISSUE_FILLER`. Filler is regex-optional and itself requires `#N` adjacency — backtracking on `"Fix issue ticketing for #906"` correctly fails to capture.
- **Files (7):** `/do` + `/quickfix` parsers (mirrored) + tests + conformance index sentinels bumped `[3→4]/[4→5]/[5→6]` per site.
- **Tests:** 6871/6871.

### #924 — `extract_cd_target` skips shell preambles
- **PR:** https://github.com/zeveck/zskills-dev/pull/938 — merged clean.
- **Fix:** segment-walking loop. Splits command on `&&|||;\n` separators; per-segment skip env-vars + optional `env`, then check first token against inert whitelist (`set/export/unset/source/./...`); first `cd` segment extracts. ANY OTHER real statement stops the walk (preserves "first effective cwd wins"). Chosen over regex extension because regex can't enforce "every preceding segment is inert."
- **Files (5):** source-of-truth helper `hooks/_lib/resolve-effective-worktree-root.sh` rewritten; inlined helper re-synced byte-identical at `hooks/block-unsafe-project.sh.template` and `hooks/block-stale-skill-version.sh`; mirrors; 8 new test cases (CE8-CE15) covering each preamble shape.
- **Hook line-2 stamps:** `2026.05.0 → 2026.06.0` on both source hooks.
- **Drift gate:** `test-hook-helper-drift.sh` verified inlined helpers byte-identical across all 3 sites.
- **Tests:** 6840/6840 (24/24 in targeted suite — 16 prior + 8 new).

## Significance

#924 closes a recurring foot-gun I've been hitting throughout this session — every time a bash call started with `. resolver.sh` or `set -e` before `cd $WT_PATH && git commit`, the hook resolved to the main repo and false-positive-blocked the worktree commit. The "use literal paths instead of `$WT_PATH`" workaround I've been applying repeatedly is now obsolete on main.

#920 closes a related foot-gun: descriptions naturally phrased "Fix issue #N: …" silently ran unclaimed, racing concurrent `/fix-issues` crons.

## Sprint metadata

- Sprint pipeline ID: fix-issues.sprint-20260601-080624-dq30m8
- Sprint worktree: /tmp/zskills-fix-issues-sprint-20260601-080624-dq30m8
- Issue claims released cleanly.
- Cron: `*/30 * * * *` — next fire ~30 min.

## Sprint — 2026-06-02 19:23 [UNFINALIZED]

**Mode:** auto | **Source:** dashboard Ready queue | **Landing:** pr | **Sprint:** sprint-20260602-214439-dashqueu

### Fixed
| # | Title | Worktree | Commit | Tests | Agent Verify | User Verify |
|---|-------|----------|--------|-------|-------------|-------------|
| #1012 | /manual-testing — user-invocable: false + re-scope to general playwright-cli UI verification | /tmp/zskills-fix-issue-1012 (fix/issue-1012) | 54d2ff3 | 7383/7383 pass | PASS (fresh verifier: diff+acceptance audit, version+mirror recheck, full suite) | N/A (no app UI/editor/styles files) |
| #1002 | Build pipeline: rewrite_dev_urls broaden + promote to shared finalizer + CANARY strip parity + 3 new tests | /tmp/zskills-fix-issue-1002 (fix/issue-1002) | b65c00f | 7410/7410 pass (new: rewrite 15/15, prod-tree 10/10, strip-parity 5/5) | PASS (fresh verifier: symptom-fix proven non-tautological, both judgment calls confirmed, build-stage grep 0 non-allowlisted hits) | N/A (build scripts + tests) |

### Skipped — Too Vague
(none)

### Skipped — Too Complex (need /run-plan)
(none)

### Skipped — Cherry-Pick Conflict
(none)

### Not Fixed
(none)

**Per-fire summary:** Picked #1012 (actionable), #1002 (actionable) from a 2-candidate dashboard Ready pool (#1012, #1002). 0 skips. Both researched on-demand (auto mode), implemented, independently verified, committed. Landing PRs dispatched in Phase 6.
