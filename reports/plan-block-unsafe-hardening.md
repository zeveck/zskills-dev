# Plan Report — Block-Unsafe Hooks Hardening

## Phase — 5 CHANGELOG + class-pinned matrices + drift gate + finalization [UNFINALIZED]

**Plan:** plans/BLOCK_UNSAFE_HARDENING.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-block-unsafe-hardening (PR mode, branch `feat/block-unsafe-hardening`)
**Commits:** `e18d1e8`

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 5.1 | CHANGELOG H3 entry under `## 2026-05-06` with 13 body bullets (9 plan-mandated + 4 emergent-deviation) | Done | `e18d1e8` |
| 5.2 | Class-pinned negative matrices in `tests/test-hooks.sh` (144 project + 192 generic + 48 adjacent-class) with mandatory per-iteration setup_project_test_on_main + matrix-invariant assertion | Done | `e18d1e8` |
| 5.3 | Class-pinned positive matrix (24 cases: 6 verbs × 4 shapes) | Done | `e18d1e8` |
| 5.4 | NEW `tests/test-hook-helper-drift.sh` (D7 drift gate) — 3/3 PASS standalone | Done | `e18d1e8` |
| 5.5 | Full suite RC 0; 2699/2699 PASS (+412 from Phase 4 baseline 2287) | Done | `e18d1e8` |
| 5.6 | `plans/PLAN_INDEX.md` BLOCK_UNSAFE_HARDENING moved Ready → Complete | Done | `e18d1e8` |
| 5.7 | PR landing — orchestrator's responsibility (post-Phase 5 commit, Phase 6 follow-up if substantive) | Pending Phase 6 | — |

### Verification

- AC1 (CHANGELOG H3 = 1 + ≥1 BLOCK_UNSAFE_HARDENING mention): PASS
- AC2 (project + generic negative matrix ≥ 336 PASS — spirit met; literal grep `^PASS matrix-` hits color-prefix mismatch): PASS (drift recorded)
- AC2b (adjacent-class ≥ 24): PASS (48; loop emits both pathsub + flagval)
- AC3 (positive matrix ≥ 24 PASS — spirit met): PASS (24; drift recorded for color-prefix)
- AC4 (4 traced reproducers PR1/PR2/PR3/GR1 PASS): PASS
- AC5 (full suite RC 0): PASS (2699/2699)
- AC6 (drift gate RC 0; 0 FAIL): PASS (3/3 PASS)
- AC7 (CI green): DEFERRED to `/land-pr`
- AC8 (exactly 5 commits Phase 1-5): DRIFT — chunked-exec produces 13 commits including bookkeeping; squash-merge consolidates
- AC9 (no migrated bare-substring sites): PASS (line 312 = `git add .claude/logs/?` rule, out of scope)
- AC10 (PLAN_INDEX moved to Complete): PASS

### Drift recorded

- `PLAN-TEXT-DRIFT: phase=5 bullet=AC2/AC3 field=grep-pattern plan="^PASS matrix-/positive-matrix-" actual="color-prefix mismatch from helper pass()"` — semantic spirit met (336 + 24 cases all PASS).
- `PLAN-TEXT-DRIFT: phase=5 bullet=AC2b field=case-count plan=24 actual=48` — adjacent-class loop emits 2 expects per iteration; 48 ≥ 24 satisfies AC.
- `PLAN-TEXT-DRIFT: phase=5 bullet=AC8 field=commit-count plan=5 actual=13` — chunked-exec assumption mismatch; squash-merge collapses.
- `PLAN-TEXT-DRIFT: phase=5 bullet=AC9 field=line-filter plan="^(56|227):" actual="^(56|227|312): — line 312 = git add .claude/logs/? rule (helper-insertion shifted from line 227)"`.

Test suite delta: 2287 (post-Phase-4) → **2699 (+412)**. Drift gate verifies inlined helper bodies byte-identical to source-of-truth.

---

## Phase — 4 Migrate block-unsafe-generic.sh — destructive-verb sites + bypass-canary tests [UNFINALIZED]

**Plan:** plans/BLOCK_UNSAFE_HARDENING.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-block-unsafe-hardening (PR mode, branch `feat/block-unsafe-hardening`)
**Commits:** `d566512`

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 4.1 | Inline `is_git_subcommand` + `is_destruct_command` (byte-identical to `hooks/_lib/git-tokenwalk.sh`) AND `is_git_subcommand_in_chain` (byte-identical to project hook) AND a NEW `is_destruct_command_in_chain` wrapper | Done | `d566512` |
| 4.2 | Migrate 7 git-verb sites (`checkout --`, `restore`, `clean -f`, `reset --hard`, `add -A/--all/.`, `commit --no-verify`, `push` outer gate) — all use `is_git_subcommand_in_chain` for cd-chain parity | Done | `d566512` |
| 4.3 | Migrate kill-family (line 140) to `is_destruct_command_in_chain` (4 calls: `kill -9/KILL/SIGKILL`, `kill -s 9/...` positional-pair via `:next:`, `killall`, `pkill`) | Done | `d566512` |
| 4.4 | Mirror to `.claude/hooks/block-unsafe-generic.sh` byte-equal | Done | `d566512` |
| 4.5 | GR1-GR25 (29 invocations) bypass-canary tests in `tests/test-hooks.sh` | Done | `d566512` |
| 4.6 | Full suite 2287/2287 PASS (+29 from Phase 3 baseline) | Done | `d566512` |

### Deviations from plan body (all surfaced + accepted)

| # | Deviation | Type | Disposition |
|---|-----------|------|-------------|
| 1 | GR1 regex curated to identifier-only substrings | plan-text bug | Plan's literal R5 regex contains substrings that trip UNCHANGED rules (RM_RECURSIVE, fuser, find, rsync, xargs lines 146/217/225/232/239) — making `expect_allow` impossible. Curated regex preserves R5 spirit (grep over hook source); test annotated. |
| 2 | GR12b flipped to `expect_allow` | behavior improvement | Plan locked `git clean foo;rm -f bar` as `expect_deny` assuming `read -ra` tokenization. The wrapper `is_git_subcommand_in_chain` normalizes `;` to newline before tokenizing per-segment, closing the carve-out. Net less over-match. Test annotated. |
| 3 | `is_destruct_command_in_chain` wrapper added | architectural extension | Pre-existing tests at `tests/test-hooks.sh:165-167` exercise `cmd && kill -9 …` chain forms; first-token-anchored `is_destruct_command` would not match. Same construction as `is_git_subcommand_in_chain`. Lives only in the generic hook. |
| 4 | `clean -f` regex extended to `-[a-zA-Z]*f[a-zA-Z]*` | plan-text correction | Plan literal `-[a-zA-Z]*f([[:space:]]\|$)` does NOT match `git clean -fd` (existing test). Original bare regex was `-[a-zA-Z]*f`. Extension preserves coverage of `-fd`/`-df`/`-fdq`. |

### Verification

- AC1 (no migrated bare-substring sites): PASS
- AC2 (`grep -cF 'is_git_subcommand'` ≥ 8): PASS (14 — includes wrapper-internal references)
- AC3 (`grep -cF 'is_destruct_command'` ≥ 5): PASS (10 — includes wrapper-internal references)
- AC4 (mirror byte-equal): PASS
- AC5 (3 helper-body byte-identity diffs): PASS
- AC6 (test-hooks.sh RC 0; GR1-GR25 PASS): PASS (29 GR* PASS)
- AC7 (full suite RC 0): PASS (2287/2287)
- AC8 (no positive case removed): PASS
- AC9 (3-path scope): PASS
- AC10 (GR1 PRESENT + PASSING): PASS
- AC11 (DA-C-2 pipeline locks GR20 + GR21): PASS
- AC12 (segment-truncation invariant GR11/GR12): PASS
- AC13 (positional-pair GR17/GR18): PASS
- AC14 (carve-out lock GR12a/GR12b — GR12b flipped per deviation 2): PASS
- AC15 (line-120 migration GR12c-allow/deny): PASS

NOT migrated (per round-1 DA-C-2): RM_RECURSIVE (line 217), find -delete (225), rsync --delete (232), xargs … rm (239), fuser combined-flag (146), STASH_BOUNDARY (106), KILL_SUBST (175), XARGS_KILL (157). These remain bare-substring whole-buffer scans that intentionally cover pipeline-fed and combined-flag forms first-token-anchored helpers would lose. Phase 5 CHANGELOG documents this open-class scope.

### Drift tokens recorded

- `PLAN-TEXT-DRIFT: phase=4 bullet=4.2-clean-f-regex plan="-[a-zA-Z]*f([[:space:]]|$)" actual="-[a-zA-Z]*f[a-zA-Z]* required to preserve -fd coverage from existing test"`
- `PLAN-TEXT-DRIFT: phase=4 bullet=4.5-GR1-regex plan="literal R5 grep regex" actual="curated identifier-only substrings; literal trips unchanged rules"`
- `ARCH-EXTENSION-DRIFT: is-destruct-command-in-chain plan="line-140 uses bare is_destruct_command" actual="wrapper required for pre-existing chain tests at lines 165-167"`
- `BEHAVIOR-IMPROVEMENT-DRIFT: GR12b plan="expect_deny (locks space-elided ; carve-out)" actual="expect_allow (wrapper closes the carve-out via sed-normalize)"`

### Test suite delta

Baseline (pre-Phase-1): 2111
Post-Phase-2: 2238 (+127)
Post-Phase-3: 2258 (+20)
Post-Phase-4: **2287 (+29)**

No regressions. Pre-existing chain tests (`commit then chained kill -9`, `commit then chained fuser -k`, `commit then chained xargs kill`) all PASS via the new `is_destruct_command_in_chain` wrapper. `clean -fd` preserved by the regex extension.

---

## Phase — 3 Migrate block-unsafe-project.sh — 6 call sites + bypass-canary tests [UNFINALIZED]

**Plan:** plans/BLOCK_UNSAFE_HARDENING.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-block-unsafe-hardening (PR mode, branch `feat/block-unsafe-hardening`)
**Commits:** `561a73c`

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 3.1 | Inline `is_git_subcommand` from `hooks/_lib/git-tokenwalk.sh` after `block_with_reason()` | Done | `561a73c` |
| 3.2 | Replace 6 outer-gate sites (lines 404, 411, 540, 546, 616, 719 pre-edit; 489, 496, 625, 631, 701, 804 post-edit) | Done | `561a73c` |
| 3.3 | Mirror to `.claude/hooks/block-unsafe-project.sh` (byte-identical) | Done | `561a73c` |
| 3.4 | PR1-PR10 bypass-canary tests in `tests/test-hooks.sh` (R1, R2, R4 reproducers; class-pinned negatives; positive regressions; XCC5-XCC14 + JSON-quote-injection battery) | Done | `561a73c` |
| 3.5 | Full suite 2258/2258 PASS | Done | `561a73c` |

### Architectural drifts (Phase 3 emergent)

Two emergent additions not in the plan body — surfaced by pre-existing tests and committed with documented rationale:

1. **Hook-local `is_git_subcommand_in_chain` wrapper.** The plan's first-token-anchored `is_git_subcommand` (Phase 2 source-of-truth, contract: tokens[0] must be `git`) does not match `cd /tmp/wt && git commit` chains. Two pre-existing tests (`extract_cd_target: multi-line cd to main-branch worktree blocked`, `main_protected + worktree-cd: commit on main-via-worktree still blocked`) regressed under the migration. Fix: a hook-local wrapper that splits `$COMMAND` on segment boundaries (`&&`, `||`, `;`, `|`, real newline, JSON-escaped `\n`) and applies `is_git_subcommand` per segment. The 6 outer gates use the wrapper. The source-of-truth helper stays unchanged (its first-token-anchored contract is correct for its unit-test surface). Phase 5.4's drift gate enforces byte-equality of the inlined helper body. The wrapper is documented in the commit message.

2. **`expect_project_deny`/`expect_project_allow` JSON-shape fix.** The harness's JSON envelope put `command` middle-of-envelope (`tool_input.command`, then `transcript_path`). The hook's greedy sed extraction otherwise bleeds `transcript_path` into the extracted `COMMAND`. The OLD bare-substring regexes were forgiving of the bleed; the new strict tokenize-then-walk classifier was not. Fix: reshape the JSON to put `command` LAST (after `transcript_path`) — same pattern as the pre-existing `run_main_protected_test` helper (with rationale comment at lines 1000-1006). The fix is "fix the code, not the test" — the helper had a latent bug exposed only by the new classifier.

### Verification

- AC1 (no bare-substring sites for migrated verbs): PASS
- AC2 (`grep -cF 'is_git_subcommand'` ≥ 7): PASS (12)
- AC3 (mirror byte-equal): PASS
- AC4 (inlined helper byte-identical to source-of-truth): PASS
- AC5 (test-hooks.sh exit 0; PR1-PR10 PASS): PASS
- AC6 (full suite RC 0): PASS (2258/2258)
- AC7 (pre-existing positive cases preserved): PASS
- AC8 (3-path scope only): PASS
- AC9 (R3 absent from test surface): PASS
- AC10 (subcommand quote-strip exercised): PASS (2)

Helper sanity: 3/3 spot-checks correct. Both pre-existing regressed tests recovered. Hygiene clean (no `--no-verify`, no new `jq`, no skill bumps, no `[ ]` artifacts).

### Plan-text drift recorded

- `PLAN-TEXT-DRIFT: phase=3 bullet=WI-3.4-case-count plan="21 new cases" actual="20 PR1-PR10 PASS lines"` — cosmetic; counting depends on whether parent PR10 line is counted alongside its 11 children.
- `ARCH-EXTENSION-DRIFT: wrapper-helper` — `is_git_subcommand_in_chain` is an emergent addition (cd-chain segment-walker); documented in commit body.
- `EMERGENT-FIX-DRIFT: test-helper-JSON-shape` — `expect_project_deny`/`expect_project_allow` reshape; documented in commit body and in code comment at the helper site.

---

## Phase — 2 Source-of-truth helpers + harness extension + unit tests [UNFINALIZED]

**Plan:** plans/BLOCK_UNSAFE_HARDENING.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-block-unsafe-hardening (PR mode, branch `feat/block-unsafe-hardening`)
**Commits:** `57706e9`

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 2.1 | `tests/test-tokenize-then-walk.sh` (127 cases) | Done | `57706e9` |
| 2.2 | `hooks/_lib/git-tokenwalk.sh` (helpers, 130 lines) | Done | `57706e9` |
| 2.3 | `tests/test-hooks-helpers.sh` (harness + self-test) | Done | `57706e9` |
| 2.4 | `tests/run-all.sh` `run_suite` line | Done | `57706e9` |
| 2.5 | Run full suite — 2238/2238 PASS | Done | `57706e9` |
| 2.6 | `skills/update-zskills/SKILL.md` install-loop comment + `metadata.version` bump (`2026.05.06+7b1a80` → `2026.05.06+9b0e21`); mirror byte-identical | Done | `57706e9` |

### Verification

- AC1 (helper file exists, `bash -n` 0, both functions reachable): PASS
- AC2 (test file +x and exits 0): PASS
- AC3 (`grep -c '^PASS'` ≥ 124): PASS (127)
- AC4 (single `run_suite` line in run-all.sh): PASS
- AC5 (full suite RC 0): PASS (2238/2238)
- AC6 (helper-name mentions): PASS
- AC7 (XCC18, XKL2 direct R1/R5 reproducers PASSING): PASS
- AC8 (XCC21/XCP21/XPU21, XCC23/24/25, XCC26/27 PASSING): PASS
- AC9 (no NEW jq usage): PASS — drift recorded (pre-existing comment in `inject-bash-timeout.sh:18`)
- AC10 (XCC8/XCC29 PASSING): PASS — drift recorded (XCC8 is `--no-pager` passthrough; the GIT_SUB_REST exposure case is XCC28a/b)
- AC11 (XKL6/XKL7 positional-pair `-s 9`): PASS
- AC12 (XKL8/XRM6 pipeline-fed not-covered locks): PASS
- AC13 (harness self-test passes; branch=main, main_protected=true): PASS
- AC14 (XCC30/31/32/34 carve-out locks): PASS
- AC15 (XKL9/XKL10 over-match-tolerance locks): PASS
- AC16 (XKL11/XKL12 prefix-bypass locks): PASS

Tests: full suite 2238/2238 PASS (delta +127 from baseline 2111). Helper sanity: 4/4 spot-checks correct (`is_git_subcommand`, `is_destruct_command` both behave per spec on positive + negative invocations).

### Plan-text drift recorded

- `PLAN-TEXT-DRIFT: phase=2 bullet=AC9 field=first-clause-grep plan="grep -rF 'jq' hooks/ returns 0" actual="1 match at hooks/inject-bash-timeout.sh:18 (pre-existing comment)"`
- `PLAN-TEXT-DRIFT: phase=2 bullet=AC10 field=case-id plan="XCC8 (GIT_SUB_REST exposure)" actual="XCC8 is '--no-pager' passthrough; XCC28 is the GIT_SUB_REST exposure case"`
- `PLAN-TEXT-DRIFT: phase=2 bullet=AC3-prose field=case-count plan="Grand total: 124 cases" actual="127 cases (XCC28 split adds 3)"`

Phase 3.5 disposition: all three are non-numeric / qualitative; auto-correction scope (numeric-arithmetic class only) does not apply. Recorded in this report; future `/refine-plan` may consolidate.

### Helper byte-identity status

`hooks/_lib/git-tokenwalk.sh` body is byte-identical to plan WI 2.2's verbatim block (modulo the trailing markdown ` ``` ` fence which doesn't belong in a `.sh` file). Phase 5.4's drift gate at `tests/test-hook-helper-drift.sh` will assert byte-equality across this file and the (forthcoming) inlined copies in Phase 3 / Phase 4 hooks + Plan B's hook (Phase 6 / D6).

---

## Phase — 1 Reference doc + reproducer trace verifications [UNFINALIZED]

**Plan:** plans/BLOCK_UNSAFE_HARDENING.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-block-unsafe-hardening (PR mode, branch `feat/block-unsafe-hardening`)
**Commits:** `2c0c4f1`

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 1.1 | Author `references/block-unsafe-hardening.md` | Done | `2c0c4f1` |
| 1.2 | Verify plan registered in `plans/PLAN_INDEX.md` | Done (already present, no edit needed) | `2c0c4f1` |

### Verification

- AC1 (`grep -c '^### D[1-7] —'` == 7): PASS
- AC2 (`grep -cE '^### R[1-5]( |$)'` == 5): PASS
- AC3 (`grep -cF 'BLOCK_UNSAFE_HARDENING' plans/PLAN_INDEX.md` >= 1): PASS (1)
- AC4 (post-commit diff scope = only `references/block-unsafe-hardening.md`): PASS
- AC5 (`is_git_subcommand`, `is_destruct_command` mentions present): PASS (12 / 6)
- AC6-A (`grep -c 'permissionDecisionReason'` >= 4): PASS (9)
- AC6-B (`grep -c '^### R3 — UNTRACED'` == 1): PASS

Tests: skipped — doc-only phase, no source-code changes (per SKILL three-case decision tree).

Verifier spot-checked R1 by re-running the deny-envelope capture; output matched the doc's quoted JSON. R5 self-confirmed (the verifier's own attempt to invoke `kill -9 …` in a Bash arg was denied by `block-unsafe-generic.sh` — same hook the doc documents).

### Findings

- **R2 expectation drift**: the plan's anticipated R2 fire (`sed -n '404,420p' …`) does NOT fire in synthesis because the literal command contains no destructive-verb substring. Documented in the reference doc as `UNTRACED-IN-SYNTHESIS` with the round-2 DA2-H-1 methodological caveat (synthesis-no-fire ≠ "guaranteed safe").
- **R4 line-number drift**: the plan said "expect line 411 to fire"; in the synthesized main-protected fixture, line 404 fires first because `is_main_protected && is_on_main` are both true (line 411 is unreachable when 404 already exited). Both lines share the same defect; Phase 3 migrates both. Recorded in the reference doc.
- **Line-540 cherry-pick verification (DA2-H-5)**: outcome (b) — synthesized `printf %s git\ cherry-pick\ abc` does NOT fire today (the wire-format backslash-escaped space breaks the regex's literal-whitespace requirement). Overview wording in the reference doc stays as "structurally identical and unprotected by prior patches" (hypothesis form). Documented in §3.1 of the reference doc.
- **Drift correction (Phase 3.5)**: zero numeric drifts detected in Phase 1's `### Acceptance Criteria` section. The qualitative drifts above are advisory only and recorded in the reference doc itself (per the plan's own discipline at WI 1.1.2.R3 and DA2-H-1).

### Plan-text drift tokens emitted

- `PLAN-TEXT-DRIFT: phase=1 bullet=1.1.2.R2 field=expected-fire plan=expect-line-411-fire actual=does-not-fire-in-synthesis-no-substring-match` — qualitative, non-numeric; not auto-corrected.
- `PLAN-TEXT-DRIFT: phase=1 bullet=1.1.2.R4 field=line-fired plan=line-411 actual=line-404-first-due-to-main-protected-precondition` — qualitative.
- `PLAN-TEXT-DRIFT: phase=1 bullet=1.1.3 field=table-format plan=4-row-table-from-Overview actual=Overview-is-prose-not-a-table` — qualitative.

These are advisory and do not affect Phase 1 acceptance. Phase 3.5's auto-correction scope is numeric arithmetic only; qualitative discrepancies above were absorbed into the reference doc's narrative.
