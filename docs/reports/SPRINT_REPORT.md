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

## Sprint — 2026-06-03 03:28 [UNFINALIZED]

**Mode:** auto | **Source:** default rubric (N=1) | **Landing:** pr | **Sprint:** sprint-20260603-055752-collectsk

### Fixed
| # | Title | Worktree | Commit | Tests | Agent Verify | User Verify |
|---|-------|----------|--------|-------|-------------|-------------|
| #1034 | dashboard collect.py: _read_state_file silently drops issues.skipped (dict) | /tmp/zskills-fix-issue-1034 (fix/issue-1034) | 4070ff2 | 7555/7556 (1 = known concurrent-live-server flake; passes in isolation) | PASS (fresh verifier: guard-completeness audit found all 3 column-iteration sites, non-tautology proven, mirror+version verified) | N/A (collector Python; dismiss-chip data-path covered by new round-trip test — a post-merge dashboard glance to confirm chip renders is optional) |

### Skipped — Not selected this fire (N=1)
| # | Bucket | Reason |
|---|--------|--------|
| #1032, #1029, #1020 | race-lost (not attempted) | claimed by concurrent pipelines; N=1 took the top unclaimed pick |
| #67 | deferred | "GitLab support — deferred until prerequisite plans land" — Action now: none |

### Not Fixed
(none)

**Per-fire summary:** Picked #1034 (actionable) — symmetric issues.skipped dict-preserve in collect.py + 3 column-iteration guards + round-trip test. Pool: 5 open candidates; #1032/#1029/#1020 held by concurrent pipelines, #67 deferred, so #1034 was the sole actionable unclaimed pick at N=1.

## Sprint — 2026-06-11 04:26 [UNFINALIZED]

**Mode:** auto | **Focus:** user-pinned (#1149 #1150 — review-finding fixes)

### Fixed
| # | Title | Worktree | Commit | Tests | Agent Verify | User Verify |
|---|-------|----------|--------|-------|-------------|-------------|
| #1149 | zsh BASH_SOURCE self-location failure (Layer-3 self-waive on mirror-less lane) | /tmp/zskills-fix-issue-1149 | 9b1670a3+aa693b1b → PR #1151 MERGED | new 5-case zsh-resolution suite | PASS (four-arm zsh/bash repro; transcript evidence; post-commit gates green) | N/A |
| #1150 | Polish batch: prose residues, rules-fail nudge, version-preserve guard, guide drift | /tmp/zskills-fix-issue-1150 | c461d843 (rebased) → PR #1152 MERGED | +2 rules cases, +5 init cases | PASS (own measurements: scope flag, 39,656-byte render; 3g locked case intact) | N/A |

Notes: #1149 triaged bug-unclear-cause by rubric but user-pinned → investigate-first in-batch (root cause PROVEN before patch: zsh leaves BASH_SOURCE unset; fence-sourced helpers self-located to cwd; fix = ${BASH_SOURCE[0]:-$0} idiom ×3 sites — affects every zsh-default consumer, e.g. macOS). Repo-wide tracker sync scoped out this sprint (user-pinned candidates; both researched at file time). No skips, no timeouts, no conflicts at fix time.

Fix-cycle: PR #1151's first CI run failed on migration case 6d — 2 Tier-1 registry hashes orphaned by the #1145/#1147 SQUASH-merges (intermediate blobs unreachable on fresh clones; passed locally via pre-squash object stores). Pruned in aa693b1b; latent main-CI landmine defused for all future PRs.

### Skipped — none

## Sprint — 2026-06-12 12:03 [UNFINALIZED]

**Mode:** auto | **Focus:** explicit issue set (#1154 #1156 #1155 #1148), user-decomposed into 3 work items | **Landing:** pr (main_protected)

User-directed scope: 4 named issues split into an independent hook fix + a coupled macOS-portability cluster. #1154/#1156-P0 grouped into ONE worktree (shared `skills/update-zskills/scripts/` surface). #1155 fixed as its P0 subset only (issue stays OPEN for the plan-scale remainder → /draft-plan). #1156 P1 deferred (issue stays OPEN). #1159 deliberately excluded (hook semantics need a design round).

### Fixed
| # | Title | Worktree | Commit | Tests | Agent Verify | User Verify |
|---|-------|----------|--------|-------|-------------|-------------|
| #1148 | block-unsafe hook false-positives (xargs read-only sweep; literal-/tmp rm in compound w/ unrelated $VAR) | fix-issue-1148 | 7bb9eed | 11 new (allow+deny) in test-hooks-block-unsafe.sh | PASS (full suite 7734/7734) | N/A |
| #1154 | zsh cascade/paths extractor regex compile-fail → silent default | fix-issue-1154 | 5f16fb19 | zsh cases 6/7 + cron BSD + worktree BSD | PASS (7731/7731; zsh repro 8→0 compile-fail, configured values extracted) | N/A |
| #1156 (P0 items 1+2 only) | realpath -m BSD fallback (create-worktree.sh) + date -d→-r fallback (compute-cron-fire.sh) | fix-issue-1154 (grouped) | 5f16fb19 | test-compute-cron-fire BSD case + test-create-worktree case 27 | PASS (7731/7731) | N/A |
| #1155 (P0 subset only) | zsh-safe arg/regex idiom: land-pr arg loop, /do loop guard, run-plan config reads | fix-issue-1155 | 6ecbb13 | bash↔zsh fence probes + conformance 738/738 | PASS (7723/7723) | N/A |

**PR close semantics:** #1148 → `Fixes #1148`; #1154 → `Fixes #1154`, #1156 → `Part of #1156` (P0 only, stays open for P1); #1155 → `Part of #1155` (P0 only, stays open for plan-scale remainder).

### Follow-ups (NOT skips — deliberate scope boundaries)
| Item | Disposition |
|------|-------------|
| #1156 P1 (readlink -f, init-state date probe, bash-3.2-isms in ~15 scripts, $CLAUDE_PROJECT_DIR quoting nit) | Issue stays OPEN; future fix-sprint or plan |
| #1155 remainder (~105 lines across ~20 more skills + conformance tripwire + macOS-only shell-pin decision) | → /draft-plan; HOLD drafting until real-Mac shell-pin probe runs (probe spec in #1155 mitigation section; ~20 min, evaluator's Mac) |
| #1159 | Deliberately excluded from this sprint; hook semantics deserve their own design round |

### Skipped / Not Fixed
None.
