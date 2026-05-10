# Post-RESTRUCTURE verification plan

**Purpose:** when the user returns after running RESTRUCTURE in a separate session, execute this plan to confirm the restructure didn't break anything. The plan is ordered cheapest → most expensive; stop and report at the first failing phase.

**Baseline reference:** `reports/baseline-pre-restructure.md` (committed `62d7237`) captures the pre-state. Pre-restructure HEAD was `879d147` (or whatever commit the RESTRUCTURE plan started from); restructure commits land on top.

## Phase 1 — Static gates (automated, <2 minutes)

Run in this order; halt at first failure:

1. **Working tree state.** `git status -s` — should be clean.
2. **Full unit + integration suite.** `bash tests/run-all.sh` — expected 531 / 531 or higher.
   - `test-skill-conformance.sh` is the load-bearing check here: 86 patterns across the 4 target skills + /verify-changes. If any FAIL, the restructure dropped a critical invariant.
   - `test-skill-invariants.sh` enforces mirror parity — must still pass across any new `modes/` / `references/` subdirs.
   - `test-compute-cron-fire.sh` (29 cases) and `test-apply-preset.sh` (16 cases) should be untouched by RESTRUCTURE; any change here is a red flag.
3. **E2E suite.** `RUN_E2E=1 bash tests/run-all.sh` — expected 542 / 542.
4. **Bash syntax of everything.** `for f in scripts/*.sh tests/*.sh; do bash -n "$f" || echo FAIL $f; done` — catches broken extractions.

Halt criterion for Phase 1: any non-pass → specific-pattern investigation before proceeding.

## Phase 2 — Structural integrity (~5 minutes)

5. **Mirror parity across all skill files, including new subdirs.**
   ```bash
   diff -rq skills/ .claude/skills/ | grep -v '^Only in' | head
   ```
   Every source file must have a mirror. RESTRUCTURE that forgot to mirror a new `modes/*.md` file would surface here.
6. **Cross-reference resolution.** For each target skill, grep its SKILL.md for references to sibling files:
   ```bash
   for s in run-plan commit do fix-issues; do
     echo "=== /$s references ==="
     grep -oE 'modes/[a-z0-9-]+\.md|references/[a-z0-9-]+\.md' skills/$s/SKILL.md | sort -u | \
       while read ref; do
         [ -f "skills/$s/$ref" ] && echo "OK: $ref" || echo "MISSING: $ref"
       done
   done
   ```
   Any `MISSING` = SKILL.md references a file the RESTRUCTURE forgot to create.
7. **Byte-preservation spot-check.** For each target skill, compare total byte count pre/post:
   - Pre-state byte counts are in `reports/baseline-pre-restructure.md` (SHA-256 hashes + line counts per SKILL.md).
   - Total bytes across `skills/<skill>/**/*.md` should be approximately equal to the pre-state SKILL.md byte count (allowing for small additions from new file headers / cross-refs).
   - If the post-restructure total is significantly smaller, content was dropped (not just moved). If significantly larger, content was duplicated or expanded.
8. **H2/H3 header inventory delta.** `reports/baseline-pre-restructure.md` lists the pre-state headers. Every pre-state header must still exist SOMEWHERE in the post-state skill tree. Script:
   ```bash
   for s in run-plan commit do fix-issues; do
     echo "=== /$s ==="
     for pre_header in $(grep -E '^##[^#]|^### ' reports/baseline-pre-restructure.md | \
                         awk '/^### \/'$s'/{f=1;next} /^### \//{f=0} f'); do
       grep -rFq "$pre_header" skills/$s/ || echo "LOST: $pre_header"
     done
   done
   ```

## Phase 3 — Fresh-eyes review (~10 minutes)

9. **Dispatch a fresh reviewer agent** with context about the RESTRUCTURE's acceptance criteria (byte-preservation, no behavior changes, progressive-disclosure pattern). Ask it to:
   - Sample 3-5 random mode files and verify they stand alone (the SKILL.md + that one mode file should be sufficient to execute the mode).
   - Check that SKILL.md still makes sense as an entry point — does it route cleanly to the right mode?
   - Flag any cross-references or text that look like they got split incoherently (e.g., a sentence that references "see Phase 5c below" where Phase 5c is now in a different file).
   - Check the Failure Protocol is intact and reachable from every mode.

## Phase 4 — Behavioral confirmation (optional, expensive)

10. **Canary diff.** If the user ran any canaries pre-restructure (per `reports/restructure-readiness.md` recommendations), compare their output against the equivalent post-restructure runs (RESTRUCTURE's Phase 5 runs CANARY1/6/7/8 + CI_FIX_CYCLE).
11. **Ad-hoc test.** If there's uncertainty about a specific mode, run a minimal plan that exercises it:
    - `/run-plan` cherry-pick happy path: CANARY1_HAPPY
    - `/run-plan` chunked: CANARY7_CHUNKED_FINISH
    - `/fix-issues` or CI: CI_FIX_CYCLE_CANARY

## Phase 5 — Report

12. Produce `reports/post-restructure-verification.md` summarizing:
    - Which phases of this verification plan passed/failed
    - What the RESTRUCTURE delivered (files added/modified/moved — `git log` summary)
    - Any blockers for merge to main (if RESTRUCTURE ran in a worktree/branch)
    - Greenlight or specific fix-list

## What to look for specifically (RESTRUCTURE risk zones)

Based on the known-complex blocks in `/run-plan` that are most likely to get fragmented during extraction:

- **CI fix cycle block** (~100 lines in SKILL.md): re-push → --watch → re-check → auto-merge → .landed transitions. Must land in ONE file coherently, not split. If split, flag.
- **Phase 5c chunked-finish cron setup**: now thin (one line to `compute-cron-fire.sh`), so low drift risk. Make sure `bash scripts/compute-cron-fire.sh` still appears somewhere.
- **PR-mode bookkeeping**: the `cd "$WORKTREE_PATH"` + commit-on-feature-branch idiom. Splitting this across files loses the implicit ordering.
- **Failure Protocol**: must stay reachable from Phase 6 landing, Phase 1 preflight, and Phase 5b. References from multiple callers.
- **Final-verify gate (Step 0b)**: three-branch routing (marker-only / marker+fulfilled / no-marker). If extracted, ensure all three branches land together.

## Timing

- Phases 1-2: ~7 minutes. Always run.
- Phase 3: ~10 minutes if I dispatch an agent and wait. Worth it.
- Phase 4: only if Phase 1-3 surface something that needs behavioral confirmation, or if the user wants extra assurance.
- Phase 5: ~5 minutes to write up.

Total: ~20-30 minutes for a thorough verification; ~10 minutes for Phases 1-2 only if everything's clean.

## Stop conditions

- If Phase 1 fails: report the specific failure and investigate before continuing. Most likely causes: dropped conformance pattern (fixable by restoring text in whichever file should contain it), mirror not in sync (run `cp` to fix), bash syntax error in an extracted file.
- If Phase 2 fails: likely a missed `modes/*.md` file or a broken cross-reference. Show the user the missing piece and ask whether it's intentional (plan decision) or an oversight.
- If Phase 3 flags semantic drift: discuss with user; may be a case-by-case judgment.
