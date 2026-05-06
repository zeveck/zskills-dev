# Plan Report — Block-Unsafe Hooks Hardening

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
