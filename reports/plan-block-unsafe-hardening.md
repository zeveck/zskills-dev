# Plan Report — Block-Unsafe Hooks Hardening

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
