---
title: zskills Path Configuration
created: 2026-05-06
status: active
---

# Plan: zskills Path Configuration

> **Landing mode: PR** — This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

zskills currently writes plans, issue trackers, and forensic reports to
hardcoded paths in the consumer repo root (`plans/`, `reports/`,
`SPRINT_REPORT.md`, `FIX_REPORT.md`, `PLAN_REPORT.md`, `VERIFICATION_REPORT.md`,
`NEW_BLOCKS_REPORT.md`, `var/`). This plan introduces two configurable
output paths (`output.plans_dir` defaulting to `docs/plans`, `output.issues_dir`
defaulting to `.zskills/issues`) plus a fixed `.zskills/audit/` for forensic
exhaust. All readers and writers go through a new sourceable helper at
`skills/update-zskills/scripts/zskills-paths.sh` (mirror at
`.claude/skills/update-zskills/scripts/zskills-paths.sh`) that sets
`$ZSKILLS_PLANS_DIR`, `$ZSKILLS_ISSUES_DIR`, and `$ZSKILLS_AUDIT_DIR` (without
`export`; callers that spawn child processes export explicitly). A new
`/update-zskills --migrate-paths` command moves a consumer's existing files,
rewrites cross-references, and writes a `.pre-paths-migration` move-manifest.
The full design is settled in
`/tmp/zskills-proposal-path-config/plans/ZSKILLS_PATH_CONFIG_PROPOSAL.md` —
implementing agents do NOT re-litigate D1 (separate `issues_dir` key), D2
(default `docs/plans`), the helper location, or the runtime-read posture.

**Locked decisions (do not relitigate):**

1. Helper lives at `skills/update-zskills/scripts/zskills-paths.sh` (source of
   truth) with a mirror at `.claude/skills/update-zskills/scripts/zskills-paths.sh`,
   sibling to `zskills-resolve-config.sh`. Sourceable shim. No `set -e`.
   `_ZSK_`-prefixed internals. Caller provides the project root via env var
   `$CLAUDE_PROJECT_DIR` (matching `zskills-resolve-config.sh`); helper accepts
   `$ZSKILLS_PATHS_ROOT` as an OPTIONAL override (defaults to
   `$CLAUDE_PROJECT_DIR`). Helper never derives from `pwd`, never from
   `$SCRIPT_DIR/..`, never from `git rev-parse` itself. Fails loud (non-zero
   stderr) when BOTH `$CLAUDE_PROJECT_DIR` and `$ZSKILLS_PATHS_ROOT` are
   unset.
2. Helper fallback when `output.plans_dir` is absent → legacy `plans/`
   (NOT `docs/plans/`). Same for `output.issues_dir` → legacy `plans/`.
   `docs/plans/` and `.zskills/issues/` are the OFFICIAL DOCUMENTED defaults
   and the MIGRATION TARGET, but absence of config means legacy preservation.
3. `update-zskills` install/upgrade auto-backfill of missing schema fields
   is EXEMPT for `output.plans_dir` and `output.issues_dir`. They stay unset
   unless `/update-zskills --migrate-paths` writes them.
4. `/update-zskills --migrate-paths` is the ONLY path that writes the new
   keys and moves files. No automatic flips on install/upgrade. Migration
   writes BOTH keys atomically (or neither) — never one without the other.
5. `plans/blocks/<category>/` follows `plans_dir` (no special-case). After
   migration: `docs/plans/blocks/<category>/`. Side-effect of the helper, not
   a separate work item.
6. Conformance lives in `tests/fixtures/forbidden-literals.txt` (read by
   `tests/test-skill-conformance.sh` AND `hooks/warn-config-drift.sh`).
   `scripts/test-all.sh` is a stub (`exit 1`); the orchestrator is
   `tests/run-all.sh`.
7. Hook fence broadens `hooks/block-unsafe-project.sh.template:201` from
   `\.zskills/tracking` to `\.zskills`. Re-rendered into consumer
   `.claude/hooks/` via `/update-zskills install` / `--rerender`.
8. Migration cross-reference rewrite uses an ADAPTED context-signature
   approach (NOT a verbatim lift from `update-zskills/SKILL.md:747-814` —
   that algorithm requires a rendered template input, which plan files lack).
   See Phase 5b for the adapted spec.
9. `.pre-paths-migration` lifecycle = write-once, never-read, never-cleaned.
   Content = move manifest (`from\tto\n` lines). Path keys
   (`output.plans_dir`, `output.issues_dir`) are written to config ONLY at
   the END of a successful migration — so any mid-migration abort leaves the
   helper resolving to the legacy `plans/`, where the un-moved files still
   live.
10. Mirror discipline: edit `skills/<name>/` source only; run
    `bash scripts/mirror-skill.sh <name>` per skill at end of each phase;
    assert `diff -rq skills/X .claude/skills/X` clean as an AC.
    `block-diagram/` skills are NOT mirrored under `.claude/skills/` today —
    see Locked Decision 13 for the in-scope vs out-of-scope split.
11. Commit discipline: one commit per phase. Phase 1 (foundations) MUST be a
    SINGLE commit. Phase 2 split into 2a (writers excluding `/run-plan`) and
    2b (`/run-plan` writer + isolated CANARY1 gate); Phase 5 split into 5a
    (deterministic moves) and 5b (cross-reference rewrite).
    `mirror-skill.sh` extension (Locked Decision 13) lands as part of Phase
    1.5 — a SEPARATE single-purpose commit BEFORE Phase 2a — so the 14-skill
    Phase 2a commit's rollback unit excludes the runtime-tool change.
12. **PREREQUISITE — viewer-URL cleanup.** The branch
    `cleanup/remove-zimulink-viewer-refs` (commits `85c9c32` +
    `88b9a68`) MUST be merged to main BEFORE Phase 4 dispatches. **Verified
    state of cleanup branch at refinement time:**
    `grep -rn "viewer/?file\|/viewer/?file" /tmp/zskills-cleanup-zimulink-viewer-refs/skills /tmp/zskills-cleanup-zimulink-viewer-refs/.claude/skills`
    returns ZERO hits — the two commits collectively remove every viewer
    URL in `briefing.cjs`, `briefing.py`, `briefing/SKILL.md`, and
    `fix-report/SKILL.md`. Phase 4's first work item re-verifies the merge.
    The plan does NOT re-author or duplicate that cleanup.

    **Abandonment policy:** the day-count begins at **Phase 1 landing
    on main** (round-3 DA F11). If the cleanup branch is not merged
    within **14 days from that landing date**, Phase 4 dispatch surfaces
    a user-facing blocker. The implementer derives "Phase 1 landing
    date" via `git log --format='%cI' -1 <Phase-1-commit-sha>` (taken
    from the Progress Tracker's Phase 1 commit cell). The user picks
    one of:
    - **(a) Wait** — keep this plan paused on Phase 4 until the cleanup
      branch lands.
    - **(b) Absorb** — fold the cleanup commits' textual changes into this
      plan's Phase 4. **Workflow** (round-3 DA F11):
      1. From the cleanup worktree
         (`/tmp/zskills-cleanup-zimulink-viewer-refs/`), push the branch
         to origin so it's available for cherry-pick:
         `git -C /tmp/zskills-cleanup-zimulink-viewer-refs push -u origin cleanup/remove-zimulink-viewer-refs`.
      2. From INSIDE the Phase 4 feature worktree (NOT main), cherry-pick
         the two commits in order:
         `git cherry-pick 85c9c32 88b9a68`. If conflicts surface, resolve
         per CLAUDE.md "Protect untracked files before git operations"
         discipline (inventory with `git status -s | grep '^??'` first).
      3. Verify the cherry-picks: `grep -rn 'viewer/?file' skills/briefing/ skills/fix-report/`
         returns zero hits in the worktree.
      4. Update Locked Decision 12 in this plan: append "absorbed at
         <date>" to the LD 12 prose in a follow-up patch commit on
         the Phase 4 feature branch.
      5. Mark the cleanup-branch worktree as `.landed` per CLAUDE.md:
         write `/tmp/zskills-cleanup-zimulink-viewer-refs/.landed` with
         `status: full`, listing both cherry-picked SHAs.
    - **(c) Defer** — proceed with Phases 1, 2a, 2b, 3, 5a, 5b, 6 minus
      Phase 4. Feasible because Phase 4 only touches briefing + dashboard,
      not the helper or migration tool. Add a deferred entry in the plan
      Progress Tracker; landing Phase 4 later requires a follow-up
      mini-plan.

      **Caveat under (c) (round-3 reviewer F4):** `briefing.cjs`,
      `briefing.py`, and the dashboard server continue to read
      `mainPath/'reports'/` and root-level `*REPORT*.md`. After Phase 6
      self-migration, those locations are EMPTY (audit files moved to
      `.zskills/audit/`), so the dashboard's briefing UI shows an empty
      state until Phase 4 lands as a follow-up. This is NOT data-loss
      (audit files are intact under `.zskills/audit/`) and the helper +
      schema dashboards still function — only the briefing-report list
      is empty. The follow-up mini-plan MUST include in its Overview:
      "Phase 4 deferred (LD 12 abandonment path c) — dashboard briefing
      reports empty until landed; viewer-URL leakage to be re-checked
      pre-merge."

      Phase 6 §6.2's auto-canary list MUST skip the dashboard smoke
      under (c) (the dashboard test fixture-loads will not find report
      data); document this in the verifier report. Phase 6 §6.13's
      regression grep STILL runs under (c) (the cleanup branch was
      never merged, so the leak window still applies — but ZERO viewer
      URLs in main is a pre-existing state, not a Phase 4 outcome).
      Phase 6.11 conformance must NOT depend on briefing-parity (Phase
      4.5 didn't run) under (c).
    Phase 4 PAUSES until the user explicitly picks (a), (b), or (c). Phase
    6 includes a final regression grep that closes the leak window between
    cleanup-merge and Phase 6.
13. **`block-diagram/` migration scope.** `mirror-skill.sh` hardcodes
    `SRC="$REPO_ROOT/skills/$NAME"` (verified at `scripts/mirror-skill.sh:22`)
    and there are no `.claude/skills/add-block` or `.claude/skills/add-example`
    mirror destinations today. Path-config Phase 1.5 EXTENDS `mirror-skill.sh`
    to accept `block-diagram/<name>` as a SRC root (see Phase 1.5 work
    items) BEFORE migrating `add-example`/`add-block`. The extension also
    creates the missing `.claude/skills/<add-block,add-example>` mirror
    destinations in the same Phase 1.5 commit. **`block-diagram/model-design`
    is intentionally NOT mirrored** under `.claude/skills/` (verified
    `grep -rln "plans/\|reports/\|SPRINT_REPORT" block-diagram/` returns
    only `block-diagram/add-block/SKILL.md` — model-design has no
    path-config literals; mirroring it now would silently change install
    policy). The Phase 1.5 extension is therefore opt-in — a caller
    explicitly running `bash scripts/mirror-skill.sh block-diagram/model-design`
    WOULD create a mirror, but no agent in this plan does so. Phase 1.5 AC
    asserts `ls .claude/skills/ | grep -E "model-design|add-block|add-example"`
    yields exactly `add-block` and `add-example` (no `model-design`). If
    the extension proves harder than expected, Phase 1.5 STOPS and surfaces
    a separate `MIRROR_SKILL_BLOCKDIAG` plan; block-diagram path-config
    migration is then deferred until that plan lands.
14. **Conformance-scanner scope is `skills/` only.** `tests/test-skill-conformance.sh:1152`
    walks `find "$REPO_ROOT/skills" -name '*.md'` and is NOT a gate over
    `block-diagram/`, `scripts/`, `hooks/`, `tests/`. Path-config does NOT
    extend this scanner (out of scope; would expand to a
    `EXTEND_CONFORMANCE_SCANNER` plan). Per-phase explicit grep "phase exit"
    assertions (in Acceptance Criteria) substitute as gates for non-`skills/`
    surface. The Phase 1 AC therefore states "≥X new conformance violations
    in `skills/` ONLY", with separate explicit-grep ACs for
    `block-diagram/`, `scripts/`, `hooks/`, `tests/`, AND for the
    Python-source files in `skills/briefing/scripts/` and
    `skills/zskills-dashboard/scripts/zskills_monitor/` (Phase 4 AC; the
    scanner walks `*.md` only and skips `.py`/`.cjs`).
15. **Conformance-scanner detection modes — PER-FENCE only.** The scanner
    has TWO detection modes (`tests/test-skill-conformance.sh:1066-1124`):
    (i) inside `bash`/`sh`/`shell`/empty fences; (ii) PROSE-IMPERATIVE on
    bullet/numbered lines containing a code-span AND a sentence-starting
    `Run|Execute|Invoke`. Plain prose ("Read `SPRINT_REPORT.md`") is NOT
    caught.

    **Allow-hardcoded markers are PER-FENCE.** A `<!-- allow-hardcoded:
    <literal> reason: ... -->` marker on the line preceding a fence-opener
    applies to the ENTIRE fence body (the scanner adds it to
    `allowed_in_fence[]` on fence-open and resets `allowed_in_fence=[]` on
    fence-close, lines 1078, 1093). There is NO per-line marker mechanism.
    Markers in PROSE accumulate in `prev_lines[]` but only commit to
    `allowed_in_fence[]` on fence-open — at line 1110 the prose-imperative
    check uses `${allowed_in_fence[$literal]:-}`, which is empty outside
    a fence. Therefore: **prose-imperative hits (bullet/numbered with
    Run/Execute/Invoke + code-span) are NOT escapable via markers; the
    prose must be restructured to avoid the literal.**

    The plan does NOT rely on conformance to catch all literals. Each
    phase ends with an EXPLICIT grep sweep (per work item) plus the
    conformance gate; the delta between the two is the prose-only surface
    the implementer must visually review.

16. **`git rev-parse --git-common-dir` audit is REPO-WIDE in Phase 1.5.**
    Verified at refinement time:
    `grep -rln "git rev-parse --git-common-dir" skills/ block-diagram/ scripts/ hooks/`
    returns 24 files. The PR-mode resolution-bug surface is repo-wide,
    not run-plan-localized. Phase 1.5 (a separate single-purpose commit
    AFTER Phase 1 and BEFORE Phase 2a) AUDITS all 24 sites and partitions
    each `git rev-parse --git-common-dir` fence into a documented class:
    - **MAIN-only** (fence is invoked from main, never from a worktree):
      no change required; the existing `MAIN_ROOT=$(...)` semantic is
      correct.
    - **PR-mode-relevant** (fence runs inside a worktree on a feature
      branch — orchestrator bookkeeping, post-run-invariants, etc.): the
      fence MUST be rewritten to source the helper with
      `ZSKILLS_PATHS_ROOT="$WORKTREE_PATH"`, NOT MAIN_ROOT.
    - **Untouched** (fence is a research/inspection idiom unrelated to
      path resolution).

    Phase 1.5's audit produces an audit-table commit message section
    enumerating every site by `<path>:<line>:<class>`. The actual
    rewrites for PR-mode-relevant fences happen in their owning skill's
    phase (Phase 2a, 2b, 3, or 4); Phase 1.5 only PRODUCES THE AUDIT
    (and lands no source-code edits beyond the mirror-skill.sh extension
    + the AUDIT.md artifact).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Foundations (helper + schema + conformance + hook fence) | ⬜ | | single-commit phase |
| 1.5 — `mirror-skill.sh` extension + repo-wide PR-mode audit | ⬜ | | one commit; produces AUDIT.md artifact + extends mirror-skill.sh; no skill rewrites |
| 2a — Bash writer migration (excluding `/run-plan`) | ⬜ | | one commit; 12 `skills/` + 2 `block-diagram/` = 14 skills total |
| 2b — `/run-plan` writer migration + CANARY1 gate | ⬜ | | self-migration hazard isolated; one commit |
| 3 — Bash reader migration + scripts | ⬜ | | readers + post-run-invariants.sh + build-prod.sh |
| 4 — Briefing + dashboard migration | ⬜ | | depends on cleanup/remove-zimulink-viewer-refs merge (locked decision 12) |
| 5a — Migration tool deterministic moves | ⬜ | | --migrate-paths flag + 4 simple test cases |
| 5b — Cross-reference rewrite + complex test cases | ⬜ | | adapted context-signature; 6 cross-ref test cases incl. `--rewrite-only` recovery (5b's 6 + 5a's 4 = 10 total) |
| 6 — Self-migration + canary gating + docs | ⬜ | | apply --migrate-paths to zskills repo; CANARY1/6/7/8/9/10; docs |

## Out of Scope

- `.claude/` install paths, `~/.claude/statusline-command.sh`, `.playwright/`,
  worktree-local files (`.worktreepurpose`, `.zskills-tracked`, `.landed`).
- Per-leaf path overrides (`narrative_dir`, `audit_dir`, etc.) — explicitly
  rejected; tier boundary is the only meaningful split.
- Dashboard `/viewer/` HTTP route — does not exist; references removed by
  `cleanup/remove-zimulink-viewer-refs` (a PREREQUISITE, see Locked Decision 12).
- Extending `tests/test-skill-conformance.sh` to walk
  `block-diagram/`, `scripts/`, `hooks/`, `tests/`, `*.py`, `*.cjs`
  (Locked Decision 14).
- GitLab support — issue #67 deferred.
- Backwards-compat shim for legacy paths beyond the helper's silent-config
  fallback to `plans/`. zskills is pre-backwards-compat.
- Mirroring `block-diagram/model-design` — verified clean of path-config
  literals (Locked Decision 13); not in scope to add a new mirror policy.

---

## Phase 1 — Foundations

### Goal

Land the helper script, the schema additions, the conformance-test fixture
extensions, the helper unit-test suite, and the hook regex broadening in a
SINGLE commit. The conformance test from this phase will fail on every
unmigrated `skills/`-resident writer/reader, which is the gating signal
Phases 2a/2b/3 unwind.

### Work Items

- [ ] **1.1 — Pre-flight mirror parity check.** Before any edit, run
  `diff -rq skills/ .claude/skills/ | grep -v '^Only in '` and assert empty.
  If non-empty, surface as a separate housekeeping commit on main BEFORE
  Phase 1 dispatch (per EPHEMERAL_TO_TMP precedent).

- [ ] **1.2 — Create `skills/update-zskills/scripts/zskills-paths.sh`.** New
  file. Shape per Design & Constraints below. After write, `chmod +x` not
  required (sourceable lib). Add a Tier-1 row to
  `skills/update-zskills/references/script-ownership.md` for the new helper.
  Exact row format (preserves the existing `column 1 = backtick-quoted name,
  column 2 = digit, column 3 = owner` contract per prior-art research §2):

  ```markdown
  | `zskills-paths.sh`           | 1      | sourceable helper setting $ZSKILLS_PLANS_DIR / $ZSKILLS_ISSUES_DIR / $ZSKILLS_AUDIT_DIR; sibling to zskills-resolve-config.sh; vars are NOT exported (callers spawning child processes export explicitly) |
  ```

  Re-derive insertion point via
  `grep -n '^| \`zskills-resolve-config' skills/update-zskills/references/script-ownership.md`
  and insert below that row (alphabetical-by-helper-name within Tier 1).

- [ ] **1.3 — Extend `config/zskills-config.schema.json`** (the source of
  truth — verified by `find /workspaces/zskills -name '*.schema.json'` →
  `./config/zskills-config.schema.json` only; install flow at
  `skills/update-zskills/SKILL.md:304-305` copies this to
  `.claude/zskills-config.schema.json` at consumer install). Add the
  `output` object with `plans_dir` and `issues_dir` string properties. See
  Design & Constraints below for the exact schema fragment. AC explicitly
  asserts the change is in `config/`, NOT only in `.claude/`.

- [ ] **1.4 — Add a forward-protection comment in `update-zskills` SKILL.md
  near the existing backfill section.** Verify the location BEFORE editing:
  `grep -n "backfill" skills/update-zskills/SKILL.md` returns multiple hits
  (271, 283, 287, 300, 303, 1019, 1159, 1536, 1558). Insert the
  forward-protection comment as a sub-bullet immediately AFTER the
  `commit.co_author` backfill block (the block ending around line 303 — the
  implementer re-derives via grep). Wording:

  ```markdown
  > **Path-config keys are EXEMPT from auto-backfill.** `output.plans_dir`
  > and `output.issues_dir` MUST NOT be inserted into
  > `.claude/zskills-config.json` during install or `--rerender`. Their
  > absence is meaningful — the helper falls back to legacy `plans/`,
  > preserving consumer-current behavior. Only `/update-zskills
  > --migrate-paths` writes these keys (and writes BOTH or NEITHER).
  > See plan `docs/plans/ZSKILLS_PATH_CONFIG.md` (or
  > `plans/ZSKILLS_PATH_CONFIG.md` pre-migration).
  ```

  Re-verify post-edit:
  `grep -n "Path-config keys are EXEMPT" skills/update-zskills/SKILL.md`
  returns exactly one line within the `Step B` / backfill section
  (re-derive Step B's section bound with
  `grep -n "^#### Step [A-Z]" skills/update-zskills/SKILL.md`).

  **Self-conformance hygiene.** This comment introduces literals
  `plans/ZSKILLS_PATH_CONFIG.md` and `docs/plans/ZSKILLS_PATH_CONFIG.md`.
  The first matches `re:^plans/` (forbidden-literals fixture, item 1.5).
  Add an `<!-- allow-hardcoded: plans/ZSKILLS_PATH_CONFIG.md reason:
  forward-protection comment quoting pre-migration path -->` marker on
  the line IMMEDIATELY BEFORE the comment block (the marker applies to
  the next fence; since this is prose, restructure: wrap the literal in
  a backticked code-span on the same line as the marker so it's not
  a prose-imperative). The cleanest pattern: render the comment INSIDE
  a fenced markdown blockquote that is itself preceded by an
  allow-hardcoded marker, so the literals fall inside an escapable
  context. AC re-runs the conformance test post-edit to confirm the
  count delta is exactly `$ACTUAL_VIOLATIONS` (i.e., the forward-
  protection block did NOT introduce a new uncaught hit).

  **Note:** This is a forward-protection-only comment — there is no
  existing positive backfill code-path for these keys to "exempt from."
  Phase 5 will edit the same file (adding the `--migrate-paths` algorithm)
  in a separate commit. Do not pre-stub Phase 5 here.

- [ ] **1.5 — Append literals to `tests/fixtures/forbidden-literals.txt`.**
  Add the path-config literal set listed in Design & Constraints, with `re:`
  prefix where word-boundary or anchor regex is needed. Allow-hardcoded
  exemptions are PER-FENCE markers ONLY (per Locked Decision 15;
  `tests/test-skill-conformance.sh:1078, 1093, 1110`), NOT a file-level
  allowlist and NOT per-line. Implementer adds the markers AT EACH
  legitimate fence-opener within the exempted skills (helper, migration
  tool, schema, CHANGELOG, RELEASING). Prose-imperative hits cannot be
  escaped — the prose must be restructured.

  Pre-flight: count actual current violations by running the conformance
  suite once with the new fixture but BEFORE any migration:

  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  bash tests/test-skill-conformance.sh > "$TEST_OUT/.test-results.txt" 2>&1 || true
  grep -c "^DRIFT" "$TEST_OUT/.test-results.txt"
  ```

  AC names the resulting count (set as `$ACTUAL_VIOLATIONS`). The
  implementing agent records this number in the verifier report; it is
  the gate Phases 2a/2b/3 unwind to zero. **Per-phase checkpoint counts**:
  Phases 2a / 2b / 3 each spec an EXPECTED REMAINING count post-phase
  (see those phases' ACs). `2a expected = $ACTUAL_VIOLATIONS - <2a contribution>`,
  etc. Implementer derives the contribution counts at Phase 1.5 audit
  time by grepping each affected skill in isolation.

- [ ] **1.6 — Broaden `hooks/block-unsafe-project.sh.template:201`.** Change
  the literal anchor `\.zskills/tracking` → `\.zskills`. Update the
  `block_with_reason` message to mention the broader scope. Verified safe:
  the regex requires a recursive-flag token (`-[a-zA-Z]*[rR][a-zA-Z]*` or
  `--recursive`); non-recursive `rm -f .zskills-tracked` and `rm
  .zskills-tracked` (no flag) both fail that clause and pass through.

  After editing, NO mirror step is required — the file lives at top-level
  `hooks/`, not under a skill. Consumer re-render copies the template to
  `.claude/hooks/block-unsafe-project.sh` at `/update-zskills install` /
  `--rerender` time. Within zskills itself, the template change IS the
  source of truth.

- [ ] **1.7 — Add hook regression cases to `tests/test-hooks.sh`.** Five
  new cases modeled on the existing `test-hooks.sh:1990-2013` `mktemp`
  fixture pattern:
  - `rm -rf .zskills/issues` — must BLOCK (broadened scope catches the
    new sibling dir).
  - `rm -rf .zskills/audit` — must BLOCK (broadened scope catches the
    new sibling dir).
  - `rm -f .zskills-tracked` — must ALLOW (non-recursive flag, regression
    case).
  - `rm -rf .zskills/tracking` — must BLOCK (still — original behavior
    preserved under broader regex).
  - `rm -f x.zskills.bak` — must ALLOW (substring-not-prefix; the regex's
    word-boundary structure is `\.zskills` which would match this if
    naïvely implemented; document explicitly that the recursive-flag
    requirement gates the block, so a non-recursive delete passes
    regardless of the path-shape).

  AC: `bash tests/test-hooks.sh` count delta is exactly +5; verifier
  records the five test names in the report.

- [ ] **1.8 — Author the helper unit test `tests/test-zskills-paths.sh`.**
  Mirror the shape of the sibling
  `tests/test-zskills-resolve-config.sh`. Register in `tests/run-all.sh`
  alphabetically (insertion point: after the existing
  `run_suite "test-zskills-resolve-config.sh"` block — re-derive via
  `grep -n test-zskills-resolve-config tests/run-all.sh`).

  **Critical idiom — `tests/run-all.sh:7` exports `CLAUDE_PROJECT_DIR`
  globally for all suites.** Case 5 below MUST run in a subshell that
  unsets both vars; otherwise the inherited export defeats the test:

  ```bash
  # Case 5 — both unset → fail loud.
  ( unset CLAUDE_PROJECT_DIR ZSKILLS_PATHS_ROOT
    source skills/update-zskills/scripts/zskills-paths.sh
  ) 2> "$TEST_OUT/case5.stderr"
  rc=$?
  [ "$rc" != "0" ] || fail "Case 5: expected non-zero, got $rc"
  grep -q "ZSKILLS_PATHS_ROOT" "$TEST_OUT/case5.stderr" || \
    fail "Case 5: stderr did not name ZSKILLS_PATHS_ROOT"
  grep -q "CLAUDE_PROJECT_DIR" "$TEST_OUT/case5.stderr" || \
    fail "Case 5: stderr did not name CLAUDE_PROJECT_DIR"
  ```

  Helper uses `(return 0 2>/dev/null) && return 1 || exit 1` so the
  subshell-source path returns 1 (the subshell wraps the return into the
  subshell's exit code).

  Cases (≥9):

  | # | Setup | Expected |
  |---|-------|----------|
  | 1 | Empty config | `$ZSKILLS_PLANS_DIR == $ROOT/plans` (legacy fallback) |
  | 2 | `output.plans_dir = "docs/plans"` | `$ZSKILLS_PLANS_DIR == $ROOT/docs/plans` |
  | 3 | `output.plans_dir = "/tmp/x"` | `$ZSKILLS_PLANS_DIR == /tmp/x` (absolute as-is) |
  | 4 | `output.plans_dir = "../external/zskills"` | `$ZSKILLS_PLANS_DIR == $ROOT/../external/zskills` (joined; see Design & Constraints) |
  | 5 | Both `$CLAUDE_PROJECT_DIR` AND `$ZSKILLS_PATHS_ROOT` unset (subshell-unset) | helper exits non-zero with stderr message naming the variables (idiom above) |
  | 6a | Garbage config (`not json at all`) | helper falls back silently to legacy `plans/` (no regex match, no abort) |
  | 6b | Truncated JSON (`{"output":{"plans_dir":"DROP"}` — missing outer `}`) | helper falls back silently to legacy `plans/` (closing-brace anchor rejects unbalanced JSON; round-3 reviewer F6) |
  | 7 | `output.plans_dir = ""` (empty string) | helper falls back to legacy `plans/` (treats empty as "absent") |
  | 8 | `$ZSKILLS_PATHS_ROOT` set, `$CLAUDE_PROJECT_DIR` unset | helper succeeds, uses `$ZSKILLS_PATHS_ROOT` |
  | 9 | After source, verify `env \| grep '^ZSKILLS_PLANS_DIR='` returns empty | confirms vars are NOT exported by helper itself (caller-side export contract) |

- [ ] **1.9 — Run `tests/run-all.sh` capturing to file.** Use the canonical
  idiom AND route output through orchestrator-level redirection (per DA
  finding 13: `tests/run-all.sh:20` captures to a local `output` variable
  per suite, not to disk):

  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1 || true
  ```

  Confirm: (a) hook test count increased by 5 (per 1.7), (b)
  `test-skill-conformance.sh` has `$ACTUAL_VIOLATIONS` new failures (recorded
  in 1.5), (c) `test-zskills-paths.sh` PASSES with ≥9 cases green, (d) all
  other suites green.

- [ ] **1.10 — Mirror update-zskills.** `bash scripts/mirror-skill.sh
  update-zskills`. Assert `diff -rq skills/update-zskills
  .claude/skills/update-zskills` empty.

- [ ] **1.11 — Single-commit landing.** All artifact changes (helper, schema
  in `config/`, schema-exception forward-protection text, fixture, hook
  template, hook test, helper unit test, `tests/run-all.sh` registration,
  mirror) must land as ONE commit. Commit subject:
  `feat(paths): introduce zskills-paths helper, schema, conformance, hook fence`.

  Phase 1 commit file inventory (verifier checks `git log -1 --stat` and
  matches against this enumeration; commit must touch ALL of and ONLY
  these files):
  - `skills/update-zskills/scripts/zskills-paths.sh` (NEW)
  - `.claude/skills/update-zskills/scripts/zskills-paths.sh` (NEW, mirror)
  - `config/zskills-config.schema.json` (modified)
  - `skills/update-zskills/SKILL.md` (modified — backfill comment)
  - `.claude/skills/update-zskills/SKILL.md` (modified, mirror)
  - `skills/update-zskills/references/script-ownership.md` (modified)
  - `.claude/skills/update-zskills/references/script-ownership.md` (modified, mirror)
  - `tests/fixtures/forbidden-literals.txt` (modified)
  - `hooks/block-unsafe-project.sh.template` (modified)
  - `tests/test-hooks.sh` (modified)
  - `tests/test-zskills-paths.sh` (NEW)
  - `tests/run-all.sh` (modified — registration line)

  ~12 files. Verifier asserts this exact set.

  **Note** (round-3 reviewer F7): `.claude/zskills-config.schema.json` is
  NOT in this commit. It is re-rendered from
  `config/zskills-config.schema.json` by `/update-zskills install` at
  consumer install time, per `skills/update-zskills/SKILL.md:304-305`.
  The verifier asserts the EXACT 12-file set named above; the
  consumer-installed copy is updated by a downstream operation (not by
  this commit, not by a Phase 1 mirror step).

### Design & Constraints

**Helper API (`skills/update-zskills/scripts/zskills-paths.sh`):**

Sourceable shim. No `set -e`, no `set -u` (would break callers). Header
comment matching `zskills-resolve-config.sh:1-25` style. The helper:

```bash
#!/bin/bash
# skills/update-zskills/scripts/zskills-paths.sh — sourceable shim.
# Resolves $ZSKILLS_PLANS_DIR, $ZSKILLS_ISSUES_DIR, $ZSKILLS_AUDIT_DIR from
# .claude/zskills-config.json.
#
# Usage:
#   # Default: harness sets $CLAUDE_PROJECT_DIR.
#   source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
#   # PR-mode override (worktree): caller sets $ZSKILLS_PATHS_ROOT.
#   ZSKILLS_PATHS_ROOT="$WORKTREE_PATH" \
#     source "$WORKTREE_PATH/.claude/skills/update-zskills/scripts/zskills-paths.sh"
#
# Contract:
#   - Project root: prefer $ZSKILLS_PATHS_ROOT, else $CLAUDE_PROJECT_DIR.
#     If both unset, helper fails loud (non-zero, stderr naming both vars).
#   - Empty / missing config keys → fall back to LEGACY <root>/plans for
#     PLANS_DIR and ISSUES_DIR. Audit dir is always <root>/.zskills/audit.
#   - Resolved values are absolute. Relative paths in config are JOINED
#     with <root> (including paths starting with "../" — they resolve
#     against <root>, NOT the caller's cwd). Absolute paths (starting
#     with "/") are used as-is.
#   - Idempotent — re-sourcing yields the same vars.
#   - Internal vars prefixed `_ZSK_PATHS_` and unset at end.
#   - No stdout (sourceable; would corrupt caller capture). Errors → stderr.
#   - Resolved vars are SET but NOT export-ed. Callers spawning child
#     processes (Python, node) MUST `export ZSKILLS_PLANS_DIR` etc.
#     themselves immediately after sourcing. See caller-side examples below.

# Resolve project root with override-then-default precedence.
_ZSK_PATHS_ROOT="${ZSKILLS_PATHS_ROOT:-${CLAUDE_PROJECT_DIR:-}}"
if [ -z "$_ZSK_PATHS_ROOT" ]; then
  echo "zskills-paths.sh: neither ZSKILLS_PATHS_ROOT nor CLAUDE_PROJECT_DIR is set — caller must provide one (absolute path)" >&2
  # Use return when sourced, exit when executed (mirror dual-mode pattern
  # from sanitize-pipeline-id.sh).
  (return 0 2>/dev/null) && return 1 || exit 1
fi

# Pre-init vars to empty (empty-pattern-guard from DRIFT_ARCH_FIX). NOT export.
ZSKILLS_PLANS_DIR=""
ZSKILLS_ISSUES_DIR=""
ZSKILLS_AUDIT_DIR=""

_ZSK_PATHS_CFG="$_ZSK_PATHS_ROOT/.claude/zskills-config.json"
_ZSK_PATHS_PLANS_RAW=""
_ZSK_PATHS_ISSUES_RAW=""

if [ -f "$_ZSK_PATHS_CFG" ]; then
  _ZSK_PATHS_BODY=$(cat "$_ZSK_PATHS_CFG" 2>/dev/null) || _ZSK_PATHS_BODY=""
  # Nested-key scoping per zskills-resolve-config.sh idiom (BASH_REMATCH).
  # Trailing `[^}]*\}` closing-brace anchor (round-3 reviewer F6): a
  # malformed input like `{"output":{"plans_dir":"DROP"}` (missing outer
  # `}`) used to match because `[^}]*` greedily consumed past the value;
  # the trailing `\}` requires a real close, so unbalanced JSON falls
  # back to legacy plans/ instead of yielding a path-shaped string.
  if [[ "$_ZSK_PATHS_BODY" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"plans_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
    _ZSK_PATHS_PLANS_RAW="${BASH_REMATCH[1]}"
  fi
  if [[ "$_ZSK_PATHS_BODY" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"issues_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
    _ZSK_PATHS_ISSUES_RAW="${BASH_REMATCH[1]}"
  fi
  unset _ZSK_PATHS_BODY
fi

# Empty config (or empty-string value) → LEGACY plans/ for both.
[ -z "$_ZSK_PATHS_PLANS_RAW" ]  && _ZSK_PATHS_PLANS_RAW="plans"
[ -z "$_ZSK_PATHS_ISSUES_RAW" ] && _ZSK_PATHS_ISSUES_RAW="plans"

# Resolve absolute. Only "/" prefix is treated as already-absolute. All
# other forms (including "..", "../..", "../foo") are JOINED with <root>;
# this preserves intent for `plans_dir: "../external/zskills"` (resolves
# to <root>/../external/zskills) and avoids the prior "use as-is" trap
# where "../external/zskills" would resolve against the caller's cwd.
case "$_ZSK_PATHS_PLANS_RAW" in
  /*) ZSKILLS_PLANS_DIR="$_ZSK_PATHS_PLANS_RAW" ;;
  *)  ZSKILLS_PLANS_DIR="$_ZSK_PATHS_ROOT/$_ZSK_PATHS_PLANS_RAW" ;;
esac
case "$_ZSK_PATHS_ISSUES_RAW" in
  /*) ZSKILLS_ISSUES_DIR="$_ZSK_PATHS_ISSUES_RAW" ;;
  *)  ZSKILLS_ISSUES_DIR="$_ZSK_PATHS_ROOT/$_ZSK_PATHS_ISSUES_RAW" ;;
esac
ZSKILLS_AUDIT_DIR="$_ZSK_PATHS_ROOT/.zskills/audit"

unset _ZSK_PATHS_ROOT _ZSK_PATHS_CFG _ZSK_PATHS_PLANS_RAW _ZSK_PATHS_ISSUES_RAW
```

**Variables are NOT `export`-ed by the helper itself** (per zskills
convention; consistent with `zskills-resolve-config.sh`). For child-process
boundaries (Python via `python3 - <<EOF`, node via `node -e ...`), the
caller MUST export AFTER sourcing:

```bash
source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
export ZSKILLS_PLANS_DIR ZSKILLS_ISSUES_DIR ZSKILLS_AUDIT_DIR
python3 - <<'PY'
import os
plans_dir = os.environ["ZSKILLS_PLANS_DIR"]
PY
```

This pattern is enforced at every Python-embed site by an explicit grep
AC in Phase 2a.10's owning work item:
`grep -A3 'source.*zskills-paths\.sh' skills/work-on-plans/SKILL.md | grep -c 'export ZSKILLS_PLANS_DIR'`
must equal the count of Python embeds (re-derived at edit time via
`grep -c '^python3 - <<' skills/work-on-plans/SKILL.md`).

Caller pattern at every CALL SITE (default — main-mode, no child process):

```bash
# Default — harness sets $CLAUDE_PROJECT_DIR; helper uses it.
source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
# now use $ZSKILLS_PLANS_DIR, $ZSKILLS_ISSUES_DIR, $ZSKILLS_AUDIT_DIR
```

For PR-mode bookkeeping (committing on the feature branch in a worktree),
caller passes `$WORKTREE_PATH` via `$ZSKILLS_PATHS_ROOT`:

```bash
ZSKILLS_PATHS_ROOT="$WORKTREE_PATH"
source "$WORKTREE_PATH/.claude/skills/update-zskills/scripts/zskills-paths.sh"
```

Config in worktree is git-tracked, so the worktree's checkout of
`.claude/zskills-config.json` is identical to main's — same resolution
semantics, but the resolved paths are rooted under `$WORKTREE_PATH`.

**Critical hazard — `git rev-parse --git-common-dir` from a worktree:**
existing skill bash fences sometimes derive `MAIN_ROOT` via
`MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)`. From a
worktree that resolves to MAIN, NOT the worktree. The repo-wide audit
runs in **Phase 1.5** (Locked Decision 16) and produces an
`AUDIT-PR-MODE-RESOLUTION.md` artifact enumerating all 24 sites. The
actual rewrites for PR-mode-relevant fences happen in their owning
skill's phase (2a, 2b, 3, or 4) per the audit's classification.

**Schema fragment (`config/zskills-config.schema.json` — source of truth;
the consumer-installed copy at `.claude/zskills-config.schema.json` is
re-rendered from this file by `/update-zskills install` per
`skills/update-zskills/SKILL.md:304-305`):**

Add a top-level `output` object with two string properties (peer of
`testing`, `dev_server`, `commit`, etc.):

```json
"output": {
  "type": "object",
  "additionalProperties": false,
  "description": "Output-path overrides for zskills-managed files. Distinct from `testing.output_file` (which configures test-result capture). Absent keys fall back to legacy `plans/` (NOT to the documented defaults). Set explicitly via /update-zskills --migrate-paths.",
  "properties": {
    "plans_dir": {
      "type": "string",
      "description": "Directory for Tier-1 user-curated plans (NAME_PLAN.md, PLAN_INDEX.md). Documented default: docs/plans. Absent → legacy plans/. Resolved as: absolute (starts with /) used as-is; everything else joined with project root. Distinct from testing.output_file."
    },
    "issues_dir": {
      "type": "string",
      "description": "Directory for issue trackers (ISSUES_PLAN.md, BUILD_ISSUES.md, DOC_ISSUES.md, QE_ISSUES.md). Documented default: .zskills/issues. Absent → legacy plans/. Same resolution rules as plans_dir. Distinct from testing.output_file."
    }
  }
}
```

**Forbidden-literals fixture additions (`tests/fixtures/forbidden-literals.txt`):**

Append the following block (read shape from existing entries; `re:` prefix
for regex, plain literal otherwise; one literal per line; comments with `#`):

```
# --- Path-config conformance (ZSKILLS_PATH_CONFIG plan, Phase 1) ---
# These literals are forbidden outside zskills-paths.sh, the migration tool,
# the schema, and explicit per-fence allow-hardcoded markers. Anchor patterns
# require word-boundary or punctuation context to avoid false positives on
# user prose.
re:(^|[^A-Za-z0-9_])SPRINT_REPORT\.md
re:(^|[^A-Za-z0-9_])FIX_REPORT\.md
re:(^|[^A-Za-z0-9_])PLAN_REPORT\.md
re:(^|[^A-Za-z0-9_])VERIFICATION_REPORT\.md
re:(^|[^A-Za-z0-9_])NEW_BLOCKS_REPORT\.md
re:(^|[^A-Za-z0-9_])BUILD_ISSUES\.md
re:(^|[^A-Za-z0-9_])DOC_ISSUES\.md
re:(^|[^A-Za-z0-9_])QE_ISSUES\.md
re:(^|[^A-Za-z0-9_])ISSUES_PLAN\.md
re:^plans/
re:^reports/
re:"plans/
re:"reports/
re:'plans/
re:'reports/
re:\$MAIN_ROOT/plans
re:\$MAIN_ROOT/reports
re:\$WORKTREE_PATH/plans
re:\$WORKTREE_PATH/reports
re:(^|[^A-Za-z0-9_])var/dev\.(pid|log)
re:^[[:space:]]*mkdir[[:space:]].*[^A-Za-z0-9_]reports/
```

Allow-hardcoded escapes — these markers are PER-FENCE in skill `.md`
files (per Locked Decision 15; `tests/test-skill-conformance.sh:1078,
1093, 1110`), NOT file-level and NOT per-line. Skills that legitimately
mention the literals MUST place a `<!-- allow-hardcoded: <literal>
reason: ... -->` marker on the line preceding each affected fence. **Prose-
imperative hits cannot be escaped — the prose must be restructured.**

- `skills/update-zskills/scripts/zskills-paths.sh` — helper itself
  (shell scripts in `skills/update-zskills/scripts/` aren't walked by the
  conformance scanner, but markers in the `.md` files that REFERENCE the
  helper are needed wherever a fence shows the literal paths).
- `skills/update-zskills/SKILL.md` — `--migrate-paths` algorithm prose
  (Phase 5) — Phase 5a/5b add per-fence markers AT EACH legitimate hit.
  Enumerated explicitly in Phase 5a.2 and 5b.1: expected count of
  added `allow-hardcoded` markers in `update-zskills/SKILL.md` post-
  Phase-5b is **N=8** (4 from 5a algorithm prose fences + 4 from 5b
  cross-ref-rewrite fences). Verifier asserts via `grep -c
  "allow-hardcoded" skills/update-zskills/SKILL.md` delta.
- `skills/update-zskills/references/path-config-upgrade.md` (Phase 5b
  authors). Expected count: **N=2** (one fence per upgrade-task narrative).
- `config/zskills-config.schema.json` and `.claude/zskills-config.schema.json`
  — JSON files; not walked by the markdown conformance scanner.
- `CHANGELOG.md` — historical refs immutable; not under `skills/`, so
  not walked.
- `RELEASING.md` — same; not walked.

Implementer counts the per-fence markers needed by running an explicit
grep post-edit:
```bash
grep -rn "allow-hardcoded:" skills/update-zskills/SKILL.md skills/update-zskills/references/ \
  > "$TEST_OUT/.allow-hardcoded-markers.txt"
```
and reports the count. Phase 5a/5b ACs verify the exact counts above.

**Hook regex change (`hooks/block-unsafe-project.sh.template:201`):**

Before:
```
if [[ "$COMMAND" =~ rm[[:space:]]+([^\;\&\|]*[[:space:]])?(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)[^\;\&\|]*\.zskills/tracking ]]; then
```

After:
```
if [[ "$COMMAND" =~ rm[[:space:]]+([^\;\&\|]*[[:space:]])?(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)[^\;\&\|]*\.zskills ]]; then
```

Updated `block_with_reason` message:
> "BLOCKED: Cannot recursively delete inside `.zskills/`. The tree holds
> tracking markers, audit history, issues, monitor state, and dashboard
> runtime. To clear tracking specifically: `! bash
> .claude/skills/update-zskills/scripts/clear-tracking.sh`"

The regex requires a recursive-flag token. Non-recursive `rm -f
.zskills-tracked` (only `-f`, no `-r`/`-R`) fails the recursive-flag clause
and passes through, as does `rm .zskills-tracked` (no flag).
`rm -rf .zskills/issues` and `rm -rf .zskills/audit` both match the new
rule (intended).

### Acceptance Criteria

- [ ] `skills/update-zskills/scripts/zskills-paths.sh` exists, sourceable
  cleanly:
  `bash -c 'CLAUDE_PROJECT_DIR=/tmp source skills/update-zskills/scripts/zskills-paths.sh; echo "$ZSKILLS_PLANS_DIR"'`
  prints `/tmp/plans`.
- [ ] `skills/update-zskills/scripts/zskills-paths.sh` mirrored to
  `.claude/skills/update-zskills/scripts/zskills-paths.sh` (post-mirror diff
  empty).
- [ ] `tests/test-zskills-paths.sh` exists with at least 10 cases (the
  9 base cases plus 6a/6b malformed-JSON variants count as 2; total ≥
  10 per the 1.8 table); `bash tests/test-zskills-paths.sh` PASSES.
- [ ] `tests/run-all.sh` registers the new helper test alphabetically.
- [ ] Helper fails loud when BOTH `$ZSKILLS_PATHS_ROOT` AND
  `$CLAUDE_PROJECT_DIR` are unset (exit non-zero with stderr message
  naming both variables).
- [ ] Case 9 of helper test confirms vars NOT exported by helper itself.
- [ ] `config/zskills-config.schema.json` (source of truth) parses cleanly:
  `python3 -c "import json; json.load(open('config/zskills-config.schema.json'))"`
  exits 0 and contains `"output"` object.
- [ ] `tests/fixtures/forbidden-literals.txt` contains all 21 listed
  patterns (count via `grep -c '^re:\|^[A-Z]' tests/fixtures/forbidden-literals.txt`
  delta).
- [ ] `tests/test-skill-conformance.sh` is now FAILING with `$ACTUAL_VIOLATIONS`
  new violations (the count recorded in 1.5; expected — gates Phases 2a/2b/3).
  Verifier MUST attest to this in their report by quoting the
  `$ACTUAL_VIOLATIONS` value. Note: this gates `skills/` ONLY; per Locked
  Decision 14, `block-diagram/`, `scripts/`, `hooks/`, `tests/`,
  `*.py`, `*.cjs` use explicit grep ACs in their respective phases.
- [ ] All other tests in `tests/run-all.sh` green. Verifier runs
  `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` and reads
  the file. The failure list is exactly the conformance-fixture set.
- [ ] `hooks/block-unsafe-project.sh.template:201` regex contains
  `\.zskills` (not `\.zskills/tracking`). `tests/test-hooks.sh` count
  increased by exactly 5 (per 1.7).
- [ ] `skills/update-zskills/SKILL.md` contains the `Path-config keys are
  EXEMPT from auto-backfill` block (single line via grep) AT or AFTER the
  existing Step B / `co_author` backfill section. The literal
  `plans/ZSKILLS_PATH_CONFIG.md` in the comment is escaped via
  `<!-- allow-hardcoded: ... -->` so the conformance test count delta
  remains exactly `$ACTUAL_VIOLATIONS` (no new uncaught hit).
- [ ] `diff -rq skills/update-zskills .claude/skills/update-zskills` empty.
- [ ] One commit lands all changes; `git log -1 --stat` shows the 12-file
  inventory listed in 1.11 (no surprise files).

### Dependencies

None. Phase 1 is the foundation. Phase 1's ACs do NOT depend on Phase
1.5 (round-3 DA F4): Phase 1 touches no `block-diagram/` skills, so the
`mirror-skill.sh` extension landed in 1.5 is not required for Phase 1's
mirror-parity assertions. Phase 2a's ACs DO depend on Phase 1.5 (the
extension is needed to mirror `block-diagram/add-block` and
`block-diagram/add-example`).

---

## Phase 1.5 — `mirror-skill.sh` extension + repo-wide PR-mode audit

### Goal

Two pieces of housekeeping that need to land BEFORE Phase 2a, in a single
small focused commit (per Locked Decision 11). Bundling them with Phase
2a's 14-skill migration would make the rollback unit too large for a
runtime-tool change. Keeping them separate also matches the rollback
ergonomics flagged in round-2 reviewer F11.

### Work Items

- [ ] **1.5.1 — Extend `mirror-skill.sh` to accept `block-diagram/<name>`
  as a SRC root.** Verified: current `scripts/mirror-skill.sh:22` hardcodes
  `SRC="$REPO_ROOT/skills/$NAME"`. Edit to detect `block-diagram/<NAME>`
  invocations:

  ```bash
  # Two-tree resolution: if NAME contains "/" and matches block-diagram/X,
  # use that as SRC; otherwise default to skills/<NAME>.
  case "$NAME" in
    block-diagram/*)
      SRC="$REPO_ROOT/$NAME"
      DST="$REPO_ROOT/.claude/skills/${NAME#block-diagram/}"
      ;;
    *)
      SRC="$REPO_ROOT/skills/$NAME"
      DST="$REPO_ROOT/.claude/skills/$NAME"
      ;;
  esac
  ```

  After editing, verify by running
  `bash scripts/mirror-skill.sh block-diagram/add-example` against an
  unchanged source and assert `diff -rq block-diagram/add-example
  .claude/skills/add-example` clean. Add the `add-block` and `add-example`
  mirror destinations as part of this commit (they don't exist today —
  verified via `ls .claude/skills/`). Update the `Usage:` header comment
  in `mirror-skill.sh` to document the new invocation form.

  **`block-diagram/model-design` is intentionally NOT mirrored.** Verified
  by `grep -rln "plans/\|reports/\|SPRINT_REPORT" block-diagram/` → only
  `block-diagram/add-block/SKILL.md`. The script extension is opt-in —
  a caller could explicitly `bash scripts/mirror-skill.sh block-diagram/model-design`
  but no agent in this plan does. Phase 1.5 AC asserts that
  `.claude/skills/` contains exactly `add-block` and `add-example` from
  block-diagram (NOT `model-design`).

  **Update `script-ownership.md`** for `mirror-skill.sh` row to document
  the new `block-diagram/<name>` invocation form (per round-2 DA F18).
  Re-derive the row via `grep -n 'mirror-skill.sh' skills/update-zskills/references/script-ownership.md`.

  **EXTEND existing `tests/test-mirror-skill.sh`** (verified at
  refinement time: file exists at 199 lines with 8 cases, registered in
  `tests/run-all.sh:73`; cases run inside isolated fixture repos under
  `/tmp/zskills-mirror-test-<label>-$$/` per the existing
  `make_fixture` helper, so they are idempotent and do not mutate the
  real `.claude/skills/qe-audit/`). Re-derive existing case count BEFORE
  editing:

  ```bash
  grep -c '^# --- Test' tests/test-mirror-skill.sh   # expected at refinement: 8
  grep -n 'block-diagram' tests/test-mirror-skill.sh # expected: 0 (no block-diagram coverage today)
  ```

  Add ONE new case using the existing `make_fixture` / `cd $F` pattern
  so it stays idempotent: a fixture with a `block-diagram/add-example/`
  source tree (a single `SKILL.md` plus a small subdir suffices) and an
  empty `.claude/skills/`; invoke
  `bash "$HELPER" block-diagram/add-example` from inside the fixture;
  assert `diff -rq "$F/block-diagram/add-example" "$F/.claude/skills/add-example"`
  is empty AND `[ ! -d "$F/.claude/skills/block-diagram" ]` (the script
  must NOT create a `.claude/skills/block-diagram/` parent — the DST is
  `.claude/skills/<basename>`). The new case lands as `# --- Test 9`
  appended at the bottom; `tests/run-all.sh` registration is unchanged
  (already registered at line 73).

  Do NOT use `Write` to overwrite the existing file — the implementer
  uses `Edit` to append the new case.

  **Fallback:** if extending the script proves harder than the diff above
  (e.g., orphan-removal logic conflicts), STOP this phase and surface a
  separate `MIRROR_SKILL_BLOCKDIAG` plan; per Locked Decision 13 block-
  diagram path-config migration is then deferred to that plan.

  **Hook-safety invariant (round-3 DA F15).** `mirror-skill.sh` uses
  per-file `rm` (no `-r` flag) for orphan removal — verified at
  `scripts/mirror-skill.sh:5,36-58`. The broadened hook fence (Phase 1)
  blocks recursive deletes inside `.zskills/` but does NOT block
  per-file `rm`, so Phase 1.5 mirroring is hook-safe even before
  consumers re-render. **Future edits to `mirror-skill.sh` MUST preserve
  this discipline** (no `rm -r`, `rm -rf`, or `find -delete` against
  the mirror destinations) — otherwise Phase 1.5's safety degrades.
  Document this invariant in the script's header comment.

- [ ] **1.5.2 — Author the repo-wide `git rev-parse --git-common-dir`
  audit artifact.** New file: `docs/AUDIT-PR-MODE-RESOLUTION.md`
  (intermediate location; gets moved to `docs/plans/` adjacent at Phase
  6 self-migration). Run:

  ```bash
  grep -rln "git rev-parse --git-common-dir" \
    skills/ block-diagram/ scripts/ hooks/ \
    | sort > "$TEST_OUT/audit-sites.txt"
  wc -l "$TEST_OUT/audit-sites.txt"
  ```

  Expected count at refinement time: 24 files (verified at HEAD
  refinement-time). The 24 sites span MULTIPLE LANGUAGES — verified at
  refinement: at least 2 Python sites
  (`skills/zskills-dashboard/scripts/zskills_monitor/collect.py:184`
  doc-comment; `skills/zskills-dashboard/scripts/zskills_monitor/server.py:96`
  prose comment) plus bash-fence and bash-script-body sites. The audit
  format MUST accommodate non-bash-fence call sites (round-3 DA F2).

  For each occurrence (file:line, surrounding ±10 lines), document the
  classification:
  - **MAIN-only** — fence/call runs only when invoked from main;
    existing `MAIN_ROOT=...` semantic correct. No rewrite needed.
  - **PR-mode-relevant** — fence/call runs inside a worktree on a
    feature branch (orchestrator bookkeeping, post-run-invariants,
    land-phase, etc.); MUST be rewritten in its owning skill's phase
    to source the helper with `ZSKILLS_PATHS_ROOT="$WORKTREE_PATH"`
    (or, in Python sites, to take an explicit `main_root` parameter
    rather than calling `git rev-parse --git-common-dir` itself —
    Phase 4 work).
  - **Untouched** — call site is a research/inspection idiom (prose
    docstring or commented-out reference) with no path resolution
    downstream.

  Audit table format in `AUDIT-PR-MODE-RESOLUTION.md` — REQUIRED
  columns (column headers MUST match this spec exactly; the Phase
  1.5 verifier asserts schema match per DA F17):

  ```markdown
  | File | Line | Lang | Site context | Class | Owning phase |
  |------|------|------|--------------|-------|--------------|
  | skills/run-plan/scripts/post-run-invariants.sh | 52 | bash | bash-script-body | PR-mode-relevant | 3 |
  | skills/run-plan/SKILL.md | NNN | bash | bash-fence-in-SKILL.md | PR-mode-relevant | 2b |
  | skills/commit/scripts/land-phase.sh | NNN | bash | bash-script-body | MAIN-only | n/a |
  | skills/zskills-dashboard/scripts/zskills_monitor/collect.py | 184 | python | python-doc-comment | Untouched | n/a |
  | skills/zskills-dashboard/scripts/zskills_monitor/server.py | 96 | python | python-prose-comment | Untouched | n/a |
  | hooks/block-unsafe-project.sh.template | NNN | bash | bash-script-body (script IS the file) | MAIN-only | n/a |
  | ... (all 24 sites) ... |
  ```

  Allowed `Lang` values: `bash`, `python`. Allowed `Site context`
  values: `bash-fence-in-SKILL.md`, `bash-script-body`,
  `python-subprocess-call`, `python-doc-comment`, `python-prose-comment`,
  `prose-only-mention`. Implementer adds new context values only if
  none of the above fit, AND notes the addition in the audit's prose.

  **AC for the audit (1.5.2 specifically):**
  - Every one of the 24 sites appears as a row.
  - Column headers match the spec EXACTLY (verifier asserts schema:
    `head -2 docs/AUDIT-PR-MODE-RESOLUTION.md` matches the header +
    separator lines above).
  - Phase 2a / 2b / 3 / 4 each cite the audit rows owned by that
    phase. Verifier samples `grep -c '| 2b |' docs/AUDIT-PR-MODE-RESOLUTION.md`
    ≥ 1 (i.e., the table is searchable by owning-phase column —
    catches DA F17 phantom-citation hazard).
  - Per-skill conformance-violation contribution counts: a SECOND
    table is appended to `AUDIT-PR-MODE-RESOLUTION.md` (round-3
    reviewer F13) — see 1.5.2.b below.

- [ ] **1.5.2.b — Append per-skill conformance-violation contribution
  table to `AUDIT-PR-MODE-RESOLUTION.md`.** The Phase 1 conformance
  fixture sets `$ACTUAL_VIOLATIONS` (the total skill-resident
  literal-hit count); Phases 2a/2b/3 ACs reference per-phase
  CONTRIBUTION counts to assert checkpoint deltas. Without per-skill
  counts, those ACs become "tests not meaningfully runnable" (round-3
  reviewer F13 invokes the verifier-test-ungated antipattern). Author
  the second table now:

  ```markdown
  ## Per-skill conformance-violation contributions (set at Phase 1.5 audit time)

  | Skill | Owning phase | Violations contributed |
  |-------|--------------|------------------------|
  | qe-audit | 2a | <count> |
  | plans | 2a | <count> |
  | … (all 14 writer skills + the readers) … |
  | run-plan | 2b | <count> |
  | (Total) | — | $ACTUAL_VIOLATIONS |
  ```

  Implementer derives each row by re-running the conformance-grep
  scoped per skill at audit time (per Phase 1 §1.5 prose). Phase 2a /
  2b / 3 verifier reads this table to compute the expected post-phase
  violation count; the `$ACTUAL_VIOLATIONS - <2a contribution>`
  formula in §Phase 2a AC becomes runnable once the table is filled.

- [ ] **1.5.3 — Surface and fix `scripts/build-prod.sh` block-diagram
  glob bug** (round-3 DA F10). Verified at refinement time:
  `scripts/build-prod.sh:81` iterates
  `block-diagram/skills/*/SKILL.md` — but the actual structure is
  `block-diagram/<name>/SKILL.md` (no `skills/` segment;
  `ls block-diagram/` returns `add-block add-example model-design
  README.md screenshots`). The glob silently matches nothing. Per
  CLAUDE.md "skill-framework repo — surface bugs, don't patch": fold
  the one-character fix into THIS commit (the natural moment, since
  Phase 1.5 already extends `mirror-skill.sh` for the same
  block-diagram structure):

  ```diff
  - for skill_file in skills/*/SKILL.md block-diagram/skills/*/SKILL.md; do
  + for skill_file in skills/*/SKILL.md block-diagram/*/SKILL.md; do
  ```

  Re-derive the line at edit time (`grep -n 'block-diagram' scripts/build-prod.sh`)
  in case the file has shifted. After the fix, sanity-smoke:
  `bash scripts/build-prod.sh` produces an artifact tree containing
  `block-diagram/add-block/` AND `block-diagram/add-example/`
  (model-design is correctly excluded if it has `dev_only: true`,
  otherwise included — verify by reading its frontmatter at edit
  time).

  **Note:** this fixes a pre-existing latent bug; it is NOT a Phase 6
  AC dependency, but folding here closes the bug rather than carrying
  it forward.

- [ ] **1.5.4 — Single commit.** Subject:
  `chore(paths): extend mirror-skill.sh for block-diagram + repo-wide PR-mode audit + fix block-diagram glob in build-prod`.
  File inventory:
  - `scripts/mirror-skill.sh` (modified — extension)
  - `scripts/build-prod.sh` (modified — fix block-diagram glob, per 1.5.3)
  - `skills/update-zskills/references/script-ownership.md` (modified — mirror-skill.sh row update)
  - `.claude/skills/update-zskills/references/script-ownership.md` (mirror)
  - `.claude/skills/add-block/` (NEW — mirror destinations)
  - `.claude/skills/add-example/` (NEW — mirror destinations)
  - `tests/test-mirror-skill.sh` (modified — file exists with 8 cases at refinement; this commit appends Case 9 for `block-diagram/<name>` resolution)
  - `tests/run-all.sh` — UNCHANGED (test-mirror-skill.sh already registered at line 73; do NOT re-add)
  - `docs/AUDIT-PR-MODE-RESOLUTION.md` (NEW)

  Verifier asserts `git log -1 --stat` matches.

### Acceptance Criteria

- [ ] `scripts/mirror-skill.sh` accepts `block-diagram/<name>` form;
  `bash scripts/mirror-skill.sh block-diagram/add-example` exits 0 and
  produces a clean diff.
- [ ] `.claude/skills/add-block/` and `.claude/skills/add-example/`
  exist and contain a clean mirror of their `block-diagram/` source.
- [ ] `.claude/skills/model-design/` does NOT exist (model-design out of
  scope per Locked Decision 13).
- [ ] `tests/test-mirror-skill.sh` PASSES with the existing 8 cases plus
  the new block-diagram case (9 total — verified post-edit by
  `grep -c '^# --- Test' tests/test-mirror-skill.sh` returning 9, and
  `bash tests/test-mirror-skill.sh` exiting 0).
- [ ] `docs/AUDIT-PR-MODE-RESOLUTION.md` enumerates ALL 24 sites with
  classification; verifier samples 5 random rows and confirms the
  classification matches the actual file content.
- [ ] One commit; the rollback unit is a runtime-tool extension only,
  separate from Phase 2a's 14-skill migration.

### Dependencies

Phase 1 (the helper exists; needed by AUDIT.md to reference the source
path).

---

## Phase 2a — Bash writer migration (excluding `/run-plan`)

### Goal

Every skill that WRITES affected paths (excluding `/run-plan`, the highest-
risk site, isolated to Phase 2b) sources the helper and replaces hardcoded
literals with the resolved env vars. Mirror per skill. Uses the
`mirror-skill.sh` extension landed in Phase 1.5.

### Writer enumeration completeness check

Before any per-skill edit, run a final writer enumeration to confirm the
work-item list covers every affected skill (per round-2 reviewer F7):

```bash
grep -rln '\(SPRINT\|FIX\|PLAN\|VERIFICATION\|NEW_BLOCKS\)_REPORT\.md' skills/ block-diagram/
grep -rln '\(BUILD\|DOC\|QE\)_ISSUES\.md\|ISSUES_PLAN\.md' skills/ block-diagram/
grep -rln '^[[:space:]]*PLAN_INDEX\|"PLAN_INDEX' skills/ block-diagram/
```

Expected output set, verified at refinement time: 12 `skills/` + 2
`block-diagram/` = 14 skills. Implementer reconciles against the work-
item list 2a.1 through 2a.11. **`skills/cleanup-merged/SKILL.md` and
`skills/commit/SKILL.md` were sampled — both contain ZERO `plans/`,
`reports/`, or report-literal references at refinement time** (verified
by `grep -c "plans/" skills/cleanup-merged/SKILL.md skills/commit/SKILL.md`
→ both 0). They are READERS via grep-presence only. They do NOT need
migration. If the enumeration grep produces a file NOT in the work-item
list, STOP and surface — do NOT freelance the additional skill.

### Work Items

The following sites are MIGRATED in this phase. File:line references are
research-time anchors — implementer re-derives via grep before each edit
(per RESTRUCTURE_RUN_PLAN line-drift discipline; per-skill grep recipes
provided below in lieu of trusting fixed line numbers).

- [ ] **2a.1 — `/qe-audit`** (smallest first, warm-up).
  `skills/qe-audit/SKILL.md` — re-derive sites via
  `grep -n 'plans/QE_ISSUES\|QE_ISSUES.md' skills/qe-audit/SKILL.md`.
  Replace each occurrence of `plans/QE_ISSUES.md` with
  `$ZSKILLS_ISSUES_DIR/QE_ISSUES.md` (research-time anchor count: 4 — at
  lines 23, 169, 194, 279). Source helper at top of any new bash fence;
  for prose-doc references, keep prose form but rewrite the path token.
  Mirror via `bash scripts/mirror-skill.sh qe-audit`.

- [ ] **2a.2 — `/add-example`** (block-diagram).
  `block-diagram/add-example/SKILL.md` — re-derive sites via
  `grep -n 'DOC_ISSUES\|plans/' block-diagram/add-example/SKILL.md`.
  Replace `plans/DOC_ISSUES.md` references with
  `$ZSKILLS_ISSUES_DIR/DOC_ISSUES.md`. Mirror via
  `bash scripts/mirror-skill.sh block-diagram/add-example` (uses Phase 1.5
  extension).

- [ ] **2a.3 — `/add-block`** (block-diagram, includes NEW_BLOCKS_REPORT
  and `plans/blocks/`). `block-diagram/add-block/SKILL.md`. Re-derive each
  hit-set BEFORE editing:

  ```bash
  grep -n 'BUILD_ISSUES\|DOC_ISSUES\|NEW_BLOCKS_REPORT\|plans/blocks\|reports/new-blocks-' block-diagram/add-block/SKILL.md
  ```

  Substitutions:
  - `BUILD_ISSUES.md` (research-time count: 5 at 322, 548, 568, 717, 842) → `$ZSKILLS_ISSUES_DIR/BUILD_ISSUES.md`
  - `DOC_ISSUES.md` (count 6 at 322, 333, 355, 357, 359, 839) → `$ZSKILLS_ISSUES_DIR/DOC_ISSUES.md`
  - `NEW_BLOCKS_REPORT.md` (count 2 at 663, 844) → `$ZSKILLS_AUDIT_DIR/NEW_BLOCKS_REPORT.md`
  - `reports/new-blocks-{slug}.md` → `$ZSKILLS_AUDIT_DIR/new-blocks-{slug}.md`
  - `plans/blocks/{category}/{number}-{name}.md` (count 4 around 110, 117,
    130, 191) → `$ZSKILLS_PLANS_DIR/blocks/{category}/{number}-{name}.md`
  - `PLAN_REPORT.md` reference at line 664 (comparison only — keep prose).
  Mirror via `bash scripts/mirror-skill.sh block-diagram/add-block`.

  **Discovered during planning (NOT in proposal):** `NEW_BLOCKS_REPORT.md`
  is the fifth top-level regenerated report, parallel to PLAN_REPORT etc.
  Surfacing here per "surface bugs don't patch."

- [ ] **2a.4 — `/plans`.** `skills/plans/SKILL.md` — re-derive via
  `grep -n 'PLAN_INDEX.md\|plans/blocks/' skills/plans/SKILL.md`. Replace
  `PLAN_INDEX.md` site references (research-time count: 9 at 14, 84, 105,
  204, 219, 272, 370, 408, 519) with `$ZSKILLS_PLANS_DIR/PLAN_INDEX.md`.
  Source helper in any bash fence. The `Skip plans/blocks/ subdirectories`
  prose around line 405-407 → `Skip $ZSKILLS_PLANS_DIR/blocks/ subdirectories`.
  Mirror.

- [ ] **2a.5 — `/draft-plan`, `/draft-tests`, `/refine-plan` — argument
  parsing.** Per user refinement #5: bare-token output filenames (e.g.,
  `/draft-plan FOO.md`) currently get prepended with `plans/`. After this
  edit, the prepend becomes `$ZSKILLS_PLANS_DIR/`, which falls back to
  `plans/` when config silent — so legacy users see no behavior change.
  Sites (re-derive via
  `grep -n 'plans/\|prepend' skills/draft-plan/SKILL.md skills/draft-tests/SKILL.md skills/refine-plan/SKILL.md`):
  - `skills/draft-plan/SKILL.md` (research-time anchors 50, 63, 70-72, 86,
    94, 117, 534, 537) — output-path resolution algorithm.
  - `skills/draft-tests/SKILL.md` (66, 84, 94-98) — same.
  - `skills/refine-plan/SKILL.md` (67, 74-79, 87, 135) — same.

  Update prose: "If the token contains `/`, use as-is; otherwise resolve
  via `$ZSKILLS_PLANS_DIR/<token>` (sourcing
  `zskills-paths.sh` from the orchestrator's bash fence)." Mirror all
  three skills.

- [ ] **2a.6 — `/research-and-plan`, `/research-and-go`.** Re-derive via
  `grep -n 'plans/' skills/research-and-plan/SKILL.md skills/research-and-go/SKILL.md`:
  - `skills/research-and-plan/SKILL.md` (anchors 41, 155, 163, 206, 317,
    361, 386, 389, 392-393) — sub-plan output `plans/<SLUG>_<N>.md` →
    `$ZSKILLS_PLANS_DIR/<SLUG>_<N>.md`. Line-386-area "Update
    plans/PLAN_INDEX.md" → "Update `$ZSKILLS_PLANS_DIR/PLAN_INDEX.md`".
  - `skills/research-and-go/SKILL.md` (anchor 120) —
    `META_PLAN_PATH="plans/META_${SCOPE_UPPER}.md"` →
    `META_PLAN_PATH="$ZSKILLS_PLANS_DIR/META_${SCOPE_UPPER}.md"` (source
    helper above this assignment).
  Mirror both.

  **Discovered during planning:** `/research-and-go` was missed by the
  proposal's writer list. Surfacing per "surface bugs don't patch."

- [ ] **2a.7 — `/fix-issues`.** Re-derive via
  `grep -rn 'SPRINT_REPORT\|ISSUES_PLAN\|plans/.*ISSUES' skills/fix-issues/`:
  - 13 SPRINT_REPORT.md prose references → `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`
  - 5 ISSUES_PLAN / `plans/*ISSUES*.md` glob references — update to
    `$ZSKILLS_ISSUES_DIR/*ISSUES*.md` (lines 517, 521, 536) and
    `$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md` elsewhere.
  - cherry-pick mode references in `skills/fix-issues/modes/cherry-pick.md` (anchors 53, 113).
  - failure-protocol references in `skills/fix-issues/references/failure-protocol.md` (45, 84).
  Critical: lines 303-309 area has `plans/SPRINT_REPORT.md` (wrong path) —
  rewrite to `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`. Mirror.

- [ ] **2a.8 — `/fix-report`.** Re-derive via
  `grep -n 'SPRINT_REPORT\|FIX_REPORT' skills/fix-report/SKILL.md`:
  - 9 SPRINT_REPORT.md, 4 FIX_REPORT.md prose references → audit dir.
  - Locked Decision 12 prerequisite: viewer-URL refs in
    `skills/fix-report/SKILL.md` and `skills/briefing/` are removed by the
    cleanup-branch BEFORE Phase 4. Phase 2a does NOT touch viewer URLs;
    that's Phase 4's prerequisite gate.
  Mirror.

- [ ] **2a.9 — `/verify-changes`.** Re-derive via
  `grep -n 'reports/verify\|VERIFICATION_REPORT' skills/verify-changes/SKILL.md`:
  - `skills/verify-changes/SKILL.md` (anchors 551, 561, 566, 573-577, 651,
    654, 657, 689) — `reports/verify-{scope}.md` →
    `$ZSKILLS_AUDIT_DIR/verify-{scope}.md`; `VERIFICATION_REPORT.md` →
    `$ZSKILLS_AUDIT_DIR/VERIFICATION_REPORT.md`. Mirror.

- [ ] **2a.10 — `/work-on-plans` (writer side).** Re-derive via
  `grep -n 'reports/\|PLAN_INDEX\|plans/' skills/work-on-plans/SKILL.md`:
  - Line 116-area — the ONLY `mkdir -p "$MAIN_ROOT/reports"` invocation in
    skills. Replace with `mkdir -p "$ZSKILLS_AUDIT_DIR"` (source helper above).
  - Lines 119-120 — `WORK_STATE` and `PLAN_INDEX` — rewrite `PLAN_INDEX` to
    use `$ZSKILLS_PLANS_DIR/PLAN_INDEX.md`. `WORK_STATE` stays unchanged
    (`.zskills/work-on-plans-state.json` is fixed).
  - Lines 661, 1160 — `reports/work-on-plans-<sprint-id>.md` →
    `$ZSKILLS_AUDIT_DIR/work-on-plans-<sprint-id>.md`.
  - **Embedded Python — env-var pass (DECIDED).** Sites at lines 193, 222,
    254, 258, 748, 775. The wrapping bash fence MUST `export
    ZSKILLS_PLANS_DIR` immediately after sourcing the helper (per Phase 1
    Design & Constraints — helper does NOT export; caller must). The
    Python block reads via `os.environ.get("ZSKILLS_PLANS_DIR")` and fails
    loud if the var is unset:

    ```bash
    source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
    export ZSKILLS_PLANS_DIR ZSKILLS_ISSUES_DIR ZSKILLS_AUDIT_DIR
    python3 - <<'PY'
    import os, sys
    plans_dir = os.environ.get("ZSKILLS_PLANS_DIR")
    if not plans_dir:
        print("FATAL: ZSKILLS_PLANS_DIR not exported by wrapping bash fence", file=sys.stderr)
        sys.exit(1)
    PY
    ```

    AC: `grep -A3 'source.*zskills-paths\.sh' skills/work-on-plans/SKILL.md
    | grep -c 'export ZSKILLS_PLANS_DIR'` matches the count of Python
    embeds (re-derived via `grep -c "^python3 - <<" skills/work-on-plans/SKILL.md`,
    expected count: 6). Add a Phase 1 §1.8-style helper-test case (case 9
    already covers "vars NOT exported by helper itself"; this is enforced
    at the SKILL.md level via grep AC, not unit test).

    Add a Python-side comment at every site: `# plans_dir resolved via
    zskills-paths.sh in the wrapping bash fence — see Phase 2a.10 of
    ZSKILLS_PATH_CONFIG plan.`. The bash fence MUST `export` (not just
    assign) so the spawned Python process sees the value.
  Mirror.

  **Discovered during planning:** `/work-on-plans` writes
  `reports/work-on-plans-<sprint-id>.md` — proposal missed it. Surfacing.

- [ ] **2a.11 — `/briefing report` writer side.** `skills/briefing/SKILL.md`
  — re-derive via
  `grep -n 'reports/\|reports directory' skills/briefing/SKILL.md`. Lines
  81-area ("write it to reports/") and 374-area ("Missing reports/
  directory — created automatically") — update to `$ZSKILLS_AUDIT_DIR`.
  (Note: `briefing.cjs`/`briefing.py` themselves are Phase 4. Here we only
  touch SKILL.md prose.) Mirror.

- [ ] **2a.12 — Mirror parity verification.** After all per-skill mirrors,
  run:

  ```bash
  for s in qe-audit plans draft-plan draft-tests refine-plan \
           research-and-plan research-and-go fix-issues fix-report \
           verify-changes work-on-plans briefing; do
    diff -rq "skills/$s" ".claude/skills/$s"
  done
  for s in add-example add-block; do
    diff -rq "block-diagram/$s" ".claude/skills/$s"
  done
  ```
  Assert all clean (silent output). 12 + 2 = **14 skill-pair diffs total**.

- [ ] **2a.13 — Per-phase commit.** One commit. Subject:
  `feat(paths): migrate writer skills (excluding /run-plan) to zskills-paths helper`.

### Design & Constraints

**Transformation pattern (verbatim, applied per skill):**

A bash fence that previously read:
```bash
echo "..." >> "$MAIN_ROOT/SPRINT_REPORT.md"
```
becomes:
```bash
source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
mkdir -p "$ZSKILLS_AUDIT_DIR"  # always create before write — idempotent
echo "..." >> "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md"
```

A prose reference that previously read:
> Read `SPRINT_REPORT.md` from the repo root.

becomes:
> Read `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md` (resolved via
> `.claude/skills/update-zskills/scripts/zskills-paths.sh`).

A bash assignment that previously read:
```bash
PLAN_INDEX="$MAIN_ROOT/plans/PLAN_INDEX.md"
```
becomes:
```bash
source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
PLAN_INDEX="$ZSKILLS_PLANS_DIR/PLAN_INDEX.md"
```

**Byte-preservation discipline:** apart from the literal path swap and the
helper-source line, no semantic changes. No reordering, no rewording prose
beyond the path. This phase is mechanical (per RESTRUCTURE_RUN_PLAN
precedent).

**`||true` audit:** sourcing the helper above the existing bash fence
must NOT swallow errors. The helper itself fails loud on missing project
root. Do not wrap `source ... || true`.

**`set -u` hazard:** if a skill bash fence runs under `set -u` (rare), the
helper's project-root check will fire if neither var is set. Callers must
ensure `$CLAUDE_PROJECT_DIR` is set (the harness default) or explicitly
provide `$ZSKILLS_PATHS_ROOT`.

**Allow-hardcoded escapes are a last resort.** Only the helper, the
schema description, and the migration tool are allowed. Any other use must
include `<!-- allow-hardcoded: <literal> reason: ... -->` on the line
preceding a fence (per Locked Decision 15) and be reviewed post-edit.

### Acceptance Criteria

- [ ] `tests/test-skill-conformance.sh` — the per-skill literal violations
  for the writers in this phase (under `skills/`) are now ZERO. Block-diagram
  skills are NOT walked by the conformance scanner; their gating is the
  explicit-grep AC below.
- [ ] **Per-phase checkpoint count.** Conformance test fail count post-2a
  is `$ACTUAL_VIOLATIONS - <2a contribution>`, where `<2a contribution>`
  is the per-skill violation count summed across the 12 `skills/`-resident
  writers (computed at Phase 1.5 audit time and recorded in the
  AUDIT-PR-MODE-RESOLUTION.md companion section). Verifier asserts the
  observed count equals the expected.
- [ ] Explicit `block-diagram/` grep AC:
  ```bash
  grep -rEn '(^|[^A-Za-z0-9_])(SPRINT|FIX|PLAN|VERIFICATION|NEW_BLOCKS)_REPORT\.md|(^|[^A-Za-z0-9_])(BUILD|DOC|QE)_ISSUES\.md|(^|[^A-Za-z0-9_])ISSUES_PLAN\.md|^plans/|^reports/' \
    block-diagram/add-block/SKILL.md block-diagram/add-example/SKILL.md
  ```
  returns ZERO non-allow-hardcoded hits.
- [ ] `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` green
  for all suites EXCEPT conformance for unmigrated readers (Phase 3 work).
- [ ] `diff -rq skills/<X> .claude/skills/<X>` clean for all 12 migrated
  `skills/` entries; `diff -rq block-diagram/<X> .claude/skills/<X>` clean
  for the 2 block-diagram skills (14 pairs total).
- [ ] No new `|| true` or `2>/dev/null` introduced.
- [ ] One commit total.

### Dependencies

Phase 1 (helper, schema, conformance fixture, hook). Phase 1.5
(`mirror-skill.sh` extension; AUDIT.md citations).

---

## Phase 2b — `/run-plan` writer migration + CANARY1 gate

### Goal

Migrate the `/run-plan` writer surface — the highest-density site for
PR-mode bookkeeping fences — and immediately gate via a manual CANARY1
run. Isolation per CREATE_WORKTREE_SKILL Phase 1a/1b precedent: a
regression here is the most-likely failure mode (it strands every later
phase that dispatches via `/run-plan`).

### Work Items

- [ ] **2b.1 — `/run-plan` (writer side).** Re-derive sites via
  `grep -n 'SPRINT_REPORT\|PLAN_REPORT\|reports/plan-\|reports/verify-' skills/run-plan/SKILL.md skills/run-plan/modes/*.md skills/run-plan/references/*.md`:
  - SPRINT_REPORT.md updates (already-landed handling) at anchors 2083,
    2085, 2094 → `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`.
  - PLAN_REPORT.md regen at anchors 1150, 1836, 1839 → `$ZSKILLS_AUDIT_DIR/PLAN_REPORT.md`.
  - `reports/plan-{slug}.md` writes throughout (≈14 prose hits + bash
    fences in `modes/cherry-pick.md` lines 18, 152, 156 and `modes/pr.md`
    lines 182, 189, 237) → `$ZSKILLS_AUDIT_DIR/plan-{slug}.md`.
  - `reports/verify-worktree-...md` reads (`modes/cherry-pick.md:18`) →
    use `$ZSKILLS_AUDIT_DIR/verify-worktree-...md`.
  - `references/failure-protocol.md` lines 50, 81 — template `**Plan:**
    plans/FEATURE_PLAN.md` and "See reports/plan-{slug}.md" → use the env
    vars in the rendered output.

- [ ] **2b.2 — Apply PR-mode rewrites for `/run-plan`-owned fences from
  the Phase 1.5 audit.** The audit (Phase 1.5.2) classified each
  `git rev-parse --git-common-dir` site under `skills/run-plan/` as MAIN-
  only or PR-mode-relevant. For each PR-mode-relevant fence (cited from
  the audit table), apply the verbatim rewrite below. The PR-mode
  bookkeeping rule is documented at `skills/run-plan/SKILL.md` (re-derive
  via `grep -n 'in PR mode' skills/run-plan/SKILL.md`):
  *"in PR mode, orchestrator bookkeeping ... commits inside the worktree
  on the feature branch, not on `main`."*

  **Before (main-only, derives MAIN from common-dir — INCORRECT for
  worktree-resident bookkeeping):**
  ```bash
  MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
  source "$MAIN_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  ```

  **After (PR-mode-aware, sources from $WORKTREE_PATH):**
  ```bash
  # In PR mode, write paths resolve under $WORKTREE_PATH — NOT main.
  ZSKILLS_PATHS_ROOT="$WORKTREE_PATH"
  source "$WORKTREE_PATH/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  ```

  AC: `grep -rn 'git rev-parse --git-common-dir' skills/run-plan/` post-
  edit returns hits ONLY in audit-classified MAIN-only or Untouched fences;
  every PR-mode-relevant hit is rewritten. Verifier cross-checks against
  the AUDIT-PR-MODE-RESOLUTION.md table.

- [ ] **2b.3 — Mirror `/run-plan`.**
  `bash scripts/mirror-skill.sh run-plan`. Assert
  `diff -rq skills/run-plan .claude/skills/run-plan` clean.

- [ ] **2b.4 — Per-phase commit.** One commit. Subject:
  `feat(paths): migrate /run-plan writer to zskills-paths helper (PR-mode-aware)`.

- [ ] **2b.5 — Manual CANARY1 run.** After the commit lands LOCALLY (not
  pushed yet), verifier executes:

  ```bash
  /run-plan plans/CANARY1_HAPPY.md finish auto pr
  ```

  (Pre-self-migration the path is still `plans/...`; post-self-migration
  it would be `docs/plans/...` — Phase 6 handles that flip.) Asserts:
  (a) plan file resolves correctly via the helper, (b)
  `plan-canary1-happy.md` written under `$ZSKILLS_AUDIT_DIR`, (c) tracker
  updates commit on feature branch in PR mode, (d) verifier report cites
  the resolved paths, NOT `reports/` or `SPRINT_REPORT.md` literals.
  Evidence captured in the verify report.

### Design & Constraints

Same byte-preservation, `|| true`, `set -u` rules as Phase 2a.

**Why isolated:** `/run-plan` is the orchestrator that all subsequent
phases (3, 4, 5a, 5b, 6) dispatch through. A path-resolution regression
here breaks every downstream dispatch. Per prior-art research §8 finding
7: "Phase 2 should be split into 'non-/run-plan writers' sub-phase and
'/run-plan writer' sub-phase, with the second one running CANARY1
immediately after." This phase IS the second sub-phase.

### Acceptance Criteria

- [ ] `tests/test-skill-conformance.sh` — `/run-plan` literal violations
  ZERO.
- [ ] **Per-phase checkpoint count.** Conformance test fail count post-2b
  is `<2a remaining> - <2b contribution>` (from Phase 1.5 audit). Verifier
  attests.
- [ ] PR-mode audit verified: every `git rev-parse --git-common-dir` site
  under `skills/run-plan/` classified PR-mode-relevant in Phase 1.5 has
  been rewritten per 2b.2. Verifier cross-references the audit table.
- [ ] CANARY1 PASSES manually (per 2b.5). Evidence cited in verify report.
- [ ] `diff -rq skills/run-plan .claude/skills/run-plan` clean.
- [ ] One commit total (2b.4); CANARY1 evidence is a verifier-report
  artifact, not a separate commit.

### Dependencies

Phase 1.5 (audit table for site classification). Phase 2a (the helper
sourcing pattern is normalized across writers).

---

## Phase 3 — Bash reader migration + scripts

### Goal

Every skill that READS affected paths sources the helper. Plus the two
load-bearing bash scripts: `skills/run-plan/scripts/post-run-invariants.sh`
and `scripts/build-prod.sh`.

### Work Items

- [ ] **3.1 — `/briefing` reader prose.** `skills/briefing/SKILL.md`. The
  prose surrounding the two reimplementations — note that root `*REPORT*.md`
  scan is going away (those files all live under `$ZSKILLS_AUDIT_DIR`
  post-migration). Re-derive via
  `grep -n 'FIX_REPORT\|VERIFICATION_REPORT\|SPRINT_REPORT' skills/briefing/SKILL.md`.
  Update prose around 142, 143, 159, 160 — example output snippets
  reference report filenames. Keep the filenames in the example but
  rewrite the surrounding path prose. Mirror.

  **Note:** `briefing.cjs` and `briefing.py` themselves are Phase 4.

- [ ] **3.2 — `/work-on-plans` reader side.** Already partially migrated
  in 2a.10 (PLAN_INDEX writer-side). Re-verify lines 171, 173-175, 177,
  181 (`else, scan plans/*.md frontmatter`) — update glob to scan
  `$ZSKILLS_PLANS_DIR/*.md`. Lines 516, 608-611, 1024, 1209 — dispatch
  arg construction; rewrite `plans/<FILE>.md` to
  `$ZSKILLS_PLANS_DIR/<FILE>.md`. Mirror.

- [ ] **3.3 — `/fix-report` reader side.** Already covered in 2a.8 (writer
  side touches reads). Verify residual reads at 30, 173, 256, 293, 417,
  453 — all read paths get audit-dir prefix. Mirror.

- [ ] **3.4 — `/run-plan` reader side.** Already covered in 2b.1. Verify
  `PLAN_FILE_FOR_READ` resolution (`SKILL.md:386-426`) handles
  `$ZSKILLS_PLANS_DIR` correctly — the path joining logic must use the
  resolved env var, not literal `plans/`. Mirror.

- [ ] **3.5 — `/refine-plan` reader.** `skills/refine-plan/SKILL.md` —
  plan-file reads (covered in 2a.5). Verify any remaining `plans/`
  references update. Mirror.

- [ ] **3.6 — `/session-report` reader.** `skills/session-report/SKILL.md`
  (anchors 62, 77, 142) — `ls plans/*.md` enumerations. Replace with
  sourcing the helper and using `ls "$ZSKILLS_PLANS_DIR"/*.md`. Mirror.

- [ ] **3.7 — `/investigate`, `/quickfix`, `/do` reader prose.**
  - `skills/investigate/SKILL.md:282-area` — "No reports/investigate-*.md" →
    audit-dir reference.
  - `skills/quickfix/SKILL.md:326-area` — `plans/` redirect rule.
  - `skills/do/SKILL.md:273, 911-area` — redirect rules + invariant
    statement "NOT write SPRINT_REPORT.md, PLAN_REPORT.md…" — keep
    filenames as invariant evidence but qualify the path. Mirror all three.

  **PR-mode audit follow-up.** `skills/do/SKILL.md` and
  `skills/do/modes/{pr,worktree}.md` were classified in Phase 1.5's audit.
  Apply any PR-mode-relevant fence rewrites per the audit table; if the
  audit classified them all MAIN-only, no rewrite needed (cite the audit
  row in the verifier report).

- [ ] **3.8 — `/plans` SKILL.md remaining reader sites.**
  `skills/plans/SKILL.md:332-area` example PLAN_INDEX row → use
  `$ZSKILLS_PLANS_DIR` value when emitting index rows. Lines 333, 357,
  405-407 — `plans/blocks/` subdir convention →
  `$ZSKILLS_PLANS_DIR/blocks/`. Mirror.

- [ ] **3.9 — `skills/run-plan/scripts/post-run-invariants.sh`.** This is
  a PR-mode-relevant fence per Phase 1.5's audit (verified at refinement
  time: `post-run-invariants.sh:51-57` resolves `MAIN_ROOT` from
  `git rev-parse --git-common-dir`, but the script runs INSIDE the worktree
  at end-of-`/run-plan` and the report-existence check at line 103 is
  EXPECTED to find the report at the worktree's `.zskills/audit/` in PR
  mode, NOT MAIN's). The fix:

  Delete the existing `MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)`
  block at lines 51-61. Replace with EXPLICIT TWO-VARIABLE resolution
  (per round-3 DA F1: collapsing to a single `PROJECT_ROOT` loses the
  MAIN-rooted git-state queries that invariants #2/#3/#4/#7 need —
  worktree registry at line 75, branch existence at 83, origin remote at
  95, fetch+merge-base+diff at 136/138/139):

  ```bash
  # Resolve MAIN_ROOT for git-state queries (worktree registry, branch
  # refs, origin, fetch+merge-base). These ALWAYS point at main, even in
  # PR mode — the registry, local branch list, and remote-tracking refs
  # live on main's .git, not the worktree's.
  MAIN_ROOT_GIT_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
  [ -z "$MAIN_ROOT_GIT_DIR" ] && {
    echo "ERROR: post-run-invariants.sh must run from inside a git repository" >&2
    exit 1
  }
  MAIN_ROOT=$(cd "$MAIN_ROOT_GIT_DIR/.." && pwd)
  [ -z "$MAIN_ROOT" ] || [ "$MAIN_ROOT" = "/" ] && {
    echo "ERROR: MAIN_ROOT resolved to '$MAIN_ROOT' — aborting" >&2
    exit 1
  }

  # Resolve PROJECT_ROOT for path resolution (REPORT_PATH at line 103,
  # plan tracker reads). When the orchestrator passed --worktree <path>
  # AND that path exists on disk, the worktree IS the project root — the
  # feature-branch bookkeeping (audit dir, tracker) lives there in PR
  # mode. Otherwise PROJECT_ROOT == MAIN_ROOT (direct/main mode).
  if [ -n "$WORKTREE_PATH" ] && [ -d "$WORKTREE_PATH" ]; then
    PROJECT_ROOT="$WORKTREE_PATH"
  else
    PROJECT_ROOT="$MAIN_ROOT"
  fi

  # Source the helper with PROJECT_ROOT (worktree path in PR mode, main
  # in direct mode) so $ZSKILLS_AUDIT_DIR resolves to the right tree.
  ZSKILLS_PATHS_ROOT="$PROJECT_ROOT"
  source "$PROJECT_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  ```

  **Lines 75/83/95/136/138/139 KEEP `$MAIN_ROOT`** verbatim — verified at
  refinement time:
  - line 75: `git -C "$MAIN_ROOT" worktree list --porcelain` (worktree registry lives on main's `.git`)
  - line 83: `git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH_NAME"` (branch refs live on main)
  - line 95: `git -C "$MAIN_ROOT" ls-remote --exit-code --heads origin "$BRANCH_NAME"` (origin remote configured on main)
  - line 136: `git -C "$MAIN_ROOT" fetch origin main`
  - lines 138/139: `git -C "$MAIN_ROOT" merge-base --is-ancestor main origin/main` and `git -C "$MAIN_ROOT" diff origin/main main`

  These DO NOT change. Only the report-path resolution (line 103-area)
  switches to `$PROJECT_ROOT`-derived `$ZSKILLS_AUDIT_DIR`:

  ```bash
  REPORT_PATH="$ZSKILLS_AUDIT_DIR/plan-${PLAN_SLUG}.md"
  ```

  The implementer re-greps post-edit to confirm:
  ```bash
  grep -nE '\$MAIN_ROOT|\$PROJECT_ROOT|\$ZSKILLS_AUDIT_DIR' \
    skills/run-plan/scripts/post-run-invariants.sh
  ```
  Expected: `$MAIN_ROOT` references survive at the 6 lines above (75, 83,
  95, 136, 138, 139); `$PROJECT_ROOT` appears only in the resolution
  block; `$ZSKILLS_AUDIT_DIR` appears at the REPORT_PATH assignment.

  Update line 105-area failure message to name the resolved path. Mirror
  via `bash scripts/mirror-skill.sh run-plan`.

  **Smoke AC:** invoke against a fixture worktree with a real branch
  ref so invariants #2/#3 actually run (per round-3 DA F1: bare
  `--branch ""` skips registry + branch checks, hiding a buggy MAIN_ROOT
  resolution). The fixture wires up a worktree-registered feature
  branch on top of an init repo:

  ```bash
  fmain=/tmp/postrun-fixture-main
  fwt=/tmp/postrun-fixture-wt
  rm -rf "$fmain" "$fwt"
  mkdir -p "$fmain"
  ( cd "$fmain" && git init -q && git config user.email t@t && git config user.name t \
    && echo seed > .seed && git add -A && git commit -qm init )
  # Create a real worktree at $fwt on a feature branch — exercises invariants #2/#3
  ( cd "$fmain" && git worktree add -b smoke-feature "$fwt" )
  mkdir -p "$fwt/.zskills/audit" "$fwt/.claude/skills/update-zskills/scripts"
  cp skills/update-zskills/scripts/zskills-paths.sh \
     "$fwt/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  echo '{}' > "$fwt/.claude/zskills-config.json"
  touch "$fwt/.zskills/audit/plan-test.md"
  bash skills/run-plan/scripts/post-run-invariants.sh \
    --worktree "$fwt" --branch smoke-feature --landed-status "" \
    --plan-slug test --plan-file ""
  rc=$?
  ```

  Expectations:
  - `rc` is 0 in the "happy" smoke (REPORT_PATH resolves to
    `$fwt/.zskills/audit/plan-test.md`, exists).
  - The script logs do NOT mention an INVARIANT-FAIL #2/#3/#5 — i.e.,
    MAIN_ROOT-rooted queries (worktree registry, branch ref) found the
    expected entries, AND PROJECT_ROOT-rooted REPORT_PATH found the
    file.

  Add a SECOND smoke that flips `--landed-status landed` and removes the
  worktree from the registry to verify invariant #2 actually FIRES (so we
  know it isn't dead under the new code path):

  ```bash
  ( cd "$fmain" && git worktree remove --force "$fwt" )
  bash skills/run-plan/scripts/post-run-invariants.sh \
    --worktree "$fwt" --branch smoke-feature --landed-status landed \
    --plan-slug test --plan-file "" 2>&1 | tee "$TEST_OUT/postrun-smoke2.log"
  rc=$?
  grep -q 'INVARIANT-FAIL' "$TEST_OUT/postrun-smoke2.log" || \
    echo "FAIL: invariants did not fire on removed worktree — MAIN_ROOT may be wrong" >&2
  ```

  If the second smoke does NOT log an INVARIANT-FAIL, the MAIN_ROOT
  resolution block is buggy (it's pointing at the worktree, not main).
  This catches the silent-MAIN-collapse hazard the round-3 DA flagged.

- [ ] **3.10 — `scripts/build-prod.sh`.** Re-derive sites via
  `grep -n 'plans/CANARY\|plans/' scripts/build-prod.sh`. Source the
  helper at the top of the script (it's not under a skill, so the source
  path uses `$(git rev-parse --show-toplevel)` for the project root):

  ```bash
  ROOT=$(git rev-parse --show-toplevel)
  ZSKILLS_PATHS_ROOT="$ROOT"
  source "$ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  # ... later ...
  for plan in "$ZSKILLS_PLANS_DIR"/CANARY_*.md; do
    [ -e "$plan" ] || continue  # set -e safety on empty glob
    # ...
  done
  ```

  Verify the script still produces correct release artifacts. Manual-run
  AC: invoke `bash scripts/build-prod.sh` and confirm a build artifact
  produced; verify `skills/update-zskills/scripts/zskills-paths.sh` AND
  `.claude/skills/update-zskills/scripts/zskills-paths.sh` are PRESENT in
  the produced artifact tree (the helper must NOT be classified dev-only
  or stripped).

- [ ] **3.11 — Test fixture references.**

  **First, RE-DERIVE the fixture line via grep** (round-3 DA F18 — the
  research-time anchor `:501` may have drifted; verified at refinement
  to be at line 501 with `i5b_primary=$(setup_fixture_repo)` immediately
  preceding the `touch` invocation):

  ```bash
  grep -n 'i5b_primary.*touch\|reports/plan-canary-5\.md' tests/test-canary-failures.sh
  ```

  Re-read the current line and the surrounding ±50 lines. Two
  interpretations:
  - **(A) "canary recovers from missing fixture":** the touch creates a
    pre-existing legacy file the canary then reads/processes. After
    migration, canary code reads `.zskills/audit/`, so the fixture should
    move there. Update to:
    `mkdir -p "$i5b_primary/.zskills/audit" && touch "$i5b_primary/.zskills/audit/plan-canary-5.md"`.
  - **(B) "canary recovers from legacy-shaped fixture during a
    mid-migration window":** the test asserts that the canary correctly
    handles a CONSUMER mid-migration state where the file is still at the
    legacy path. In that case, KEEP the legacy fixture path, add a
    `<!-- allow-hardcoded reason: testing legacy mid-migration window -->`
    comment, AND add a parallel new-path fixture for the post-migration
    case.

  The implementing agent picks one based on the read; AC requires the
  choice + justification be cited in the verifier report. Do NOT silently
  pick (A) — that's the antipattern of weakening tests to make them pass.

  Re-derive other test-fixture sites via
  `grep -rn 'reports/\|plans/' tests/`.

- [ ] **3.12 — Mirror + commit.** Mirror all touched skills. One commit:
  `feat(paths): migrate reader skills + load-bearing scripts to zskills-paths helper`.

### Design & Constraints

**Transformation example #1 (skill prose):**

Before:
> The briefing scans `$MAIN_ROOT/SPRINT_REPORT.md`,
> `$MAIN_ROOT/FIX_REPORT.md`, `$MAIN_ROOT/PLAN_REPORT.md`,
> `$MAIN_ROOT/VERIFICATION_REPORT.md`.

After:
> The briefing scans the audit dir at
> `$ZSKILLS_AUDIT_DIR/{SPRINT_REPORT,FIX_REPORT,PLAN_REPORT,VERIFICATION_REPORT}.md`
> (resolved via `.claude/skills/update-zskills/scripts/zskills-paths.sh`).

**Transformation example #2 (bash script):**

Before (`scripts/build-prod.sh:67-68` area):
```bash
for f in plans/CANARY_*.md; do
  cp "$f" "$STAGE_DIR/plans/"
done
```

After:
```bash
ROOT=$(git rev-parse --show-toplevel)
ZSKILLS_PATHS_ROOT="$ROOT"
source "$ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
for f in "$ZSKILLS_PLANS_DIR"/CANARY_*.md; do
  [ -e "$f" ] || continue  # skip empty-glob (set -e safety)
  cp "$f" "$STAGE_DIR/plans/"
done
```

**`post-run-invariants.sh` is load-bearing.** The script asserts the
report exists at the end of `/run-plan`. Wrong path → every `/run-plan`
fails closed. Verifier must run a smoke `/run-plan` post-edit AND the
fixture-worktree smoke from 3.9.

### Acceptance Criteria

- [ ] `tests/test-skill-conformance.sh` — ALL `skills/`-resident
  path-config literal violations now zero (count == 0).
- [ ] Explicit grep AC for `scripts/`:
  ```bash
  grep -rEn '(^|[^A-Za-z0-9_])(SPRINT|FIX|PLAN|VERIFICATION|NEW_BLOCKS)_REPORT\.md|^plans/|^reports/' \
    scripts/build-prod.sh skills/run-plan/scripts/post-run-invariants.sh
  ```
  returns ZERO non-allow-hardcoded hits.
- [ ] Explicit grep AC for `tests/`:
  ```bash
  grep -rEn '(^|[^A-Za-z0-9_])(SPRINT|FIX|PLAN|VERIFICATION|NEW_BLOCKS)_REPORT\.md|^plans/|^reports/' tests/
  ```
  returns ONLY allow-hardcoded-marked or fixture-test-data hits (cited
  per-hit in verifier report).
- [ ] `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` green
  — all suites including conformance.
- [ ] Per 3.9 smoke (TWO invocations):
  - First (happy): `--worktree /tmp/postrun-fixture-wt --branch smoke-feature`
    against an in-registry worktree → exits 0; REPORT_PATH resolves to
    `$fwt/.zskills/audit/plan-test.md`.
  - Second (regression-fire): worktree removed from registry +
    `--landed-status landed` → logs at least one INVARIANT-FAIL (proves
    the MAIN_ROOT-rooted git-state queries still run). If no FAIL fires,
    the MAIN_ROOT collapse hazard regressed.
- [ ] `bash scripts/build-prod.sh` produces a build artifact (manual
  smoke); the resulting tree contains both `skills/update-zskills/scripts/zskills-paths.sh`
  AND `.claude/skills/update-zskills/scripts/zskills-paths.sh`.
- [ ] `diff -rq skills/<X> .claude/skills/<X>` clean for every touched
  skill.
- [ ] CANARY7 (`plans/CANARY7_CHUNKED_FINISH.md`, cron-chunked
  multi-phase) passes manually — gates cross-cron-turn path stability.
- [ ] One commit.

### Dependencies

Phase 1 (helper). Phase 1.5 (audit table). Phases 2a + 2b (writers — readers
depend on writer paths resolving).

---

## Phase 4 — Briefing + dashboard migration

### Goal

Migrate the JS (`briefing.cjs`) and Python (`briefing.py`) parallel
reimplementations in lockstep, plus the dashboard server's Python
`json.loads`-based config-read in `server.py` and `collect.py`.

### Work Items

- [ ] **4.0 — Verify cleanup-branch prerequisite (Locked Decision 12).**
  BEFORE any other Phase 4 work, run:

  ```bash
  git log main --oneline | grep -E "85c9c32|88b9a68" | head
  # Phase 4.0 leak window: NO viewer URLs allowed in briefing/ or
  # fix-report/, marker or no marker. The cleanup branch removed every
  # such URL with no allow-hardcoded markers. Per round-3 reviewer F8,
  # do NOT exclude allow-hardcoded matches here — a marker-protected
  # viewer URL would be a regression that the marker filter would hide.
  # (Phase 6.13's repo-wide regression grep DOES tolerate markers for
  # breadth; Phase 4.0's narrow leak-window check does NOT.)
  grep -rn 'viewer/?file\|/viewer/?file' \
    skills/briefing/ skills/fix-report/
  ```

  Pass conditions:
  - Both cleanup commits (`85c9c32`, `88b9a68`) appear in `git log main`,
    OR a squash/merge commit referencing both.
  - The grep returns ZERO hits (NO marker-protected hits accepted).

  **If the grep returns hits (cleanup not merged):** Phase 4 PAUSES.
  Surface to the user via the verifier report with EXACTLY this prompt:

  > Phase 4 is blocked. The viewer-URL cleanup branch
  > (`cleanup/remove-zimulink-viewer-refs`, commits `85c9c32` + `88b9a68`)
  > has not been merged to main. Per Locked Decision 12 abandonment
  > policy, please pick one:
  > (a) WAIT — pause this plan until the cleanup branch lands.
  > (b) ABSORB — cherry-pick the two cleanup commits onto this Phase 4
  >     feature branch before continuing.
  > (c) DEFER — skip Phase 4 entirely; proceed with Phases 5a, 5b, 6.
  >     Briefing + dashboard migration becomes a follow-up mini-plan.

  Do NOT auto-pick. Do NOT re-author the cleanup. Resume Phase 4 only
  after the user picks (a), (b), or (c).

  **End-of-phase re-check (closes leak window):** before commit, re-run
  the grep above and assert STILL zero hits. A commit that landed on main
  between 4.0's pre-check and 4.10's commit could re-introduce a
  `viewer/?file` URL; the re-check catches that. Phase 6 also includes a
  final re-check (per 6.13.5).

- [ ] **4.1 — Add a JS config-read helper to `briefing.cjs`.** New
  function early in the file:

  ```javascript
  function readZskillsPaths(mainPath) {
    const path = require('path');
    const fs = require('fs');
    const cfgPath = path.join(mainPath, '.claude', 'zskills-config.json');
    let cfg = {};
    try {
      cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    } catch (e) { /* missing/malformed → empty (silent fallback) */ }
    const output = (cfg && cfg.output) || {};
    const plansDir = output.plans_dir || 'plans';   // legacy fallback
    const issuesDir = output.issues_dir || 'plans'; // legacy fallback
    // Use-as-is: only absolute paths. All other forms (including "../foo")
    // are joined with mainPath. Mirrors bash helper semantics.
    const resolve = (rel) => path.isAbsolute(rel) ? rel : path.join(mainPath, rel);
    return {
      plansDir: resolve(plansDir),
      issuesDir: resolve(issuesDir),
      auditDir: path.join(mainPath, '.zskills', 'audit'),
    };
  }
  ```

  Place near the top after the require block.

- [ ] **4.2 — Replace `briefing.cjs` literals.** Re-derive via
  `grep -n "'reports'\|'plans'\|reports/\|plans/" skills/briefing/scripts/briefing.cjs`.
  Every `path.join(mainPath, 'reports')` → `paths.auditDir`. Every
  `path.join(mainPath, 'plans')` → `paths.plansDir`. Sites (research-time
  anchors):
  - 482-483, 485-486 (root `reports/` scan)
  - 491-494 (root-level `*REPORT*.md` scan) — REMOVE entirely. Those files
    now live under `paths.auditDir`. Merge into the audit-dir scan.
  - 1298, 1302, 1309-1310 (`scanPlans` function)
  - 1316-1319 (enumerate plans)
  - 1407 (`reportPath`)
  - 1445-1456 (briefing reports check)
  - 1490-1494, 1500-1512 (`preserveCheckboxes`)
  - 1591-1620 (root-level `*REPORT*.md` — REMOVE root scan)
  - 1868 ("Plan ${t} complete but no report in reports/") — update message
  - 1886-1895 (mkdir + write briefing report)
  - 784, 1080 — `// Filter out VERIFICATION_REPORT` filter is fine; the
    filename itself is unchanged.

  Viewer-URL sites in `briefing.cjs`, `briefing.py`, `briefing/SKILL.md`,
  and `fix-report/SKILL.md` are removed by Phase 4.0's prerequisite. Phase
  4 does not touch viewer URLs. (Per round-2 reviewer F3: do NOT cite
  research-time line numbers like `:802, 1126` here — those line numbers
  drift and would invite the implementer to revisit lines that 4.0
  proved are gone.)

- [ ] **4.3 — Add Python config-read to `briefing.py`.** Mirror the JS
  helper with `json.load`:

  ```python
  def read_zskills_paths(main_path):
      import json, os
      cfg_path = os.path.join(main_path, '.claude', 'zskills-config.json')
      cfg = {}
      try:
          with open(cfg_path, 'r', encoding='utf-8') as f:
              cfg = json.load(f)
      except (OSError, ValueError):
          pass
      output = (cfg.get('output') if isinstance(cfg, dict) else None) or {}
      plans_rel = output.get('plans_dir') or 'plans'
      issues_rel = output.get('issues_dir') or 'plans'
      def resolve(rel):
          # Use-as-is: only absolute. All other forms join with main_path.
          return rel if os.path.isabs(rel) else os.path.join(main_path, rel)
      return {
          'plans_dir': resolve(plans_rel),
          'issues_dir': resolve(issues_rel),
          'audit_dir': os.path.join(main_path, '.zskills', 'audit'),
      }
  ```

- [ ] **4.4 — Replace `briefing.py` literals.** Re-derive via
  `grep -n "'reports'\|'plans'\|reports/\|plans/" skills/briefing/scripts/briefing.py`.
  Same sites as 4.2 but in Python (research-time anchors):
  - 476-481 (reports_dir enumeration)
  - 485-488 (root-level scan — REMOVE)
  - 537-542 (`scan_plans`)
  - 544 (glob plans)
  - 619 (`report_path`)
  - 853 (`# Filter out VERIFICATION_REPORT`)
  - 950, 962, 966 (`generate_report_path`)
  - 1303-1314 (briefing reports)
  - 1344-1363 (`preserve_checkboxes`)
  - 1432-1460 (REMOVE root-level scan)
  - 1672 (warning message)
  - 1684-1695 (output write).

  Viewer-URL sites — handled by cleanup-branch prerequisite, verified in
  4.0 (do not re-cite line numbers; per round-2 reviewer F3).

- [ ] **4.5 — Lockstep verification.** Run `tests/test-briefing-parity.sh`
  before and after to verify the parity test still passes. The parity test
  compares output equivalence — the rewrite must produce byte-identical
  briefing outputs given identical inputs.

- [ ] **4.6 — Dashboard server: extend `_read_config`-based path reads.**
  `skills/zskills-dashboard/scripts/zskills_monitor/server.py`. The
  existing `_read_config` (anchors 220-231) returns the parsed config
  dict. Add helper:

  ```python
  def _resolve_paths(main_root: pathlib.Path) -> Dict[str, pathlib.Path]:
      cfg = _read_config(main_root)
      output = cfg.get('output', {}) if isinstance(cfg, dict) else {}
      plans_rel = output.get('plans_dir') or 'plans'
      issues_rel = output.get('issues_dir') or 'plans'
      def resolve(rel: str) -> pathlib.Path:
          p = pathlib.Path(rel)
          return p if p.is_absolute() else main_root / rel
      return {
          'plans_dir': resolve(plans_rel),
          'issues_dir': resolve(issues_rel),
          'audit_dir': main_root / '.zskills' / 'audit',
      }
  ```

  Replace `plans_dir = main_root / "plans"` at anchor 724 with
  `plans_dir = _resolve_paths(main_root)['plans_dir']`. Update line
  726-area's 404 error message to name the resolved path. Update line
  730-area's glob.

- [ ] **4.7 — Dashboard collector: same pattern in `collect.py`.** Sites:
  - anchor 528 — `report_path = main_root / "reports" / f"plan-{slug}.md"`
    → use the resolved `audit_dir`.
  - anchors 1093, 1097 (`plans_dir = main_root / "plans"` and
    `plans_dir.glob("*.md")`).
  - anchor 1201 (second `plans_dir.glob`).
  - anchor 582 — relative-to-main path emission unchanged in shape, but
    verify the new path string is what the UI displays (`app.js:1514-1517`).

  **Helper-share decision:** copy the `_resolve_paths` body into
  `collect.py` (NOT a shared module) — the dashboard collector is a
  separate process and shared-module imports add deployment complexity.
  Document the mirroring discipline inline ("when editing
  server.py:_resolve_paths, mirror in collect.py:_resolve_paths").

- [ ] **4.8 — Mirror dashboard.** `bash scripts/mirror-skill.sh
  zskills-dashboard`. Mirror briefing too. Assert clean.

- [ ] **4.9 — Smoke test the dashboard.** Manual verification: start the
  dashboard server, navigate to `/api/plan/<slug>` for a known plan,
  assert the response includes content from the resolved plans dir.
  Capture evidence in the verify report.

- [ ] **4.10 — Commit.** Subject:
  `feat(paths): migrate briefing and dashboard to runtime path config`.

### Design & Constraints

**Why Python `json.load`, not bash regex, here:** the dashboard is native
Python; bash regex would be a foreign idiom. The existing `_read_config`
already uses `json.loads`. Per domain research §3, this is the right
pattern.

**Lockstep:** every change to `briefing.cjs` MUST have its mirror in
`briefing.py`, and vice versa. Implement edits in pairs (cjs change →
immediate py change → next cjs change). Don't batch.

**Use-as-is is absolute-only.** All three implementations (bash, JS,
Python) treat ONLY paths starting with `/` as absolute. Paths starting
with `..` are JOINED with project root (per Locked Decision 1 / domain
research §10). This avoids the `..hidden` false-positive flagged in DA
finding 19, AND aligns with the "out-of-tree paths resolve relative to
consuming repo root" intent.

**Cleanup-branch dependency.** Per Locked Decision 12 / Phase 4 work
item 4.0: viewer-URL refs are removed by `cleanup/remove-zimulink-viewer-refs`
BEFORE this phase. Phase 4 verifies-and-pauses with explicit user
abandonment-policy prompt; it does NOT re-author. Phase 6 includes a
final re-grep AC closing any post-merge leak window.

**Dashboard worktree-blindness preserved.** Per domain research §3, the
dashboard does NOT know about worktrees — main-only. The `_resolve_paths`
helper takes `main_root` as input; this is correct and unchanged.

### Acceptance Criteria

- [ ] Cleanup-branch prerequisite verified per 4.0 (zero viewer-URL grep
  hits across `skills/briefing/`, `skills/fix-report/`).
- [ ] End-of-phase re-grep (per 4.0 closing) — STILL zero viewer-URL hits
  pre-commit; closes the cleanup-merge → 4.10 leak window.
- [ ] `tests/test-briefing-parity.sh` passes (output byte-equivalence
  between cjs and py preserved).
- [ ] `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` green.
- [ ] Manual: dashboard `/api/plan/<slug>` returns content for a plan
  located at `$ZSKILLS_PLANS_DIR` (verify with a custom config setting
  `output.plans_dir = "docs/plans"` against a fixture tree).
- [ ] **Explicit grep AC for the Python sources** (per Locked Decision 14;
  conformance scanner does not walk `*.py`):
  ```bash
  grep -nE "main_root[[:space:]]*/[[:space:]]*[\"']plans[\"']|main_root[[:space:]]*/[[:space:]]*[\"']reports[\"']|path\.join\(main[Pp]ath,[[:space:]]*[\"']plans[\"']\)|path\.join\(main[Pp]ath,[[:space:]]*[\"']reports[\"']\)" \
    skills/briefing/scripts/briefing.cjs \
    skills/briefing/scripts/briefing.py \
    skills/zskills-dashboard/scripts/zskills_monitor/server.py \
    skills/zskills-dashboard/scripts/zskills_monitor/collect.py
  ```
  returns ZERO hits.
- [ ] `grep -rn "viewer/?file" skills/briefing/ skills/fix-report/` returns
  zero hits (re-confirms 4.0).
- [ ] `diff -rq skills/briefing .claude/skills/briefing` clean.
- [ ] `diff -rq skills/zskills-dashboard .claude/skills/zskills-dashboard` clean.
- [ ] One commit.

### Dependencies

Phase 1 (helper, schema). Phase 1.5 (audit). Locked Decision 12
prerequisite (cleanup branch merged OR user-picked abandonment-policy
path). Phases 2a/2b/3 are independent of this phase but conformance gates
cumulatively.

---

## Phase 5a — Migration tool: deterministic moves

### Goal

Ship the deterministic step + flag handling + 4 simple test cases. The
deterministic step orders write-of-config-keys LAST so any mid-failure
leaves the consumer recovering via the helper's legacy-`plans/` fallback.

### Work Items

- [ ] **5a.1 — Implement `--migrate-paths` as a real script.** Per DA
  finding 16, implement at `skills/update-zskills/scripts/migrate-paths.sh`
  and have `skills/update-zskills/SKILL.md` dispatch to it. This gives
  testability AND aligns with sibling helpers. The bash script is the
  deterministic move logic. The agent-runnable upgrade prompt (Phase 5b)
  remains a `references/path-config-upgrade.md` doc dispatched after.

- [ ] **5a.2 — Add `--migrate-paths` flag handling in `update-zskills/SKILL.md`.**
  Re-derive flag-parsing section via
  `grep -n '^### Step 0\|--rerender\|--migrate' skills/update-zskills/SKILL.md`.
  Add the flag dispatching to `bash
  $ZSK/scripts/migrate-paths.sh "$MAIN_ROOT"`. Document interaction with
  `--rerender` (per the script algorithm in 5a.3): the script triggers
  `--rerender` AS THE FIRST FILE-SYSTEM CHANGE — so the broadened hook
  regex is in place BEFORE any moves into `.zskills/audit/` or
  `.zskills/issues/` (protecting the migration's own filesystem actions
  from a stale narrower hook).

  **Per-fence allow-hardcoded markers.** This SKILL.md edit introduces
  4 fences containing forbidden literals (e.g., `plans/`, `reports/`,
  `SPRINT_REPORT.md`). Add a `<!-- allow-hardcoded: ... -->` marker on
  the line preceding EACH of those 4 fences. AC:
  `grep -B1 '^```' skills/update-zskills/SKILL.md | grep -c "allow-hardcoded.*Phase 5a"`
  returns 4. (Phase 5b adds 4 more in its own section, total 8 — see
  Phase 1 Design § allow-hardcoded enumeration.)

- [ ] **5a.3 — Implement the deterministic migration script.** New file
  `skills/update-zskills/scripts/migrate-paths.sh`. Contract:

  ```bash
  #!/bin/bash
  # migrate-paths.sh — Deterministic file relocation for ZSKILLS_PATH_CONFIG.
  # Usage: bash migrate-paths.sh <main-root>
  # Exit 0 = migration applied or no-op; non-zero = mid-migration failure.
  set -u
  MAIN_ROOT="${1:-}"
  [ -z "$MAIN_ROOT" ] && { echo "usage: migrate-paths.sh <main-root>" >&2; exit 1; }
  cd "$MAIN_ROOT" || exit 1
  ```

  Algorithm (steps execute in this order; CONFIG WRITE IS LAST per
  Locked Decision 9). **Hook-rerender is HOISTED to step 2.5 — BEFORE
  any file moves** (per round-2 DA F19): hook strengthens BEFORE
  filesystem changes, so any `rm -rf .zskills/...` rollback during steps
  3-7 is already protected.

  1. **Detection.** Inventory existing artifacts: top-level
     `SPRINT_REPORT.md`, `FIX_REPORT.md`, `PLAN_REPORT.md`,
     `VERIFICATION_REPORT.md`, `NEW_BLOCKS_REPORT.md`, `reports/`,
     `plans/`, `var/`, `plans/{ISSUES_PLAN,BUILD_ISSUES,DOC_ISSUES,QE_ISSUES}.md`,
     `plans/blocks/` if present. If nothing to migrate AND config has no
     `output.plans_dir`/`output.issues_dir` set, print "no-op" and exit 0.
     If `.pre-paths-migration` already exists, refuse (idempotent re-run
     safety) — exit 0 with "already migrated" notice.

  2. **Resolve target dirs (in memory ONLY — do NOT write config yet).**
     Read existing `.claude/zskills-config.json`. If user has
     `output.plans_dir` set, use it; else use `docs/plans`. If user has
     `output.issues_dir`, use it; else use `.zskills/issues`. Store both as
     bash vars `TARGET_PLANS`, `TARGET_ISSUES`.

  2.5. **Trigger `--rerender` BEFORE any file moves.** Run the
     `update-zskills/SKILL.md` Step C re-render so the broadened hook
     regex copies into `.claude/hooks/block-unsafe-project.sh`. This
     protects the subsequent `mkdir`/`mv` operations from a stale
     narrower hook that would have allowed `rm -rf .zskills/audit` if
     the migration aborted mid-way. **Note:** at this point config still
     lacks `output.plans_dir`/`issues_dir`; rerender must be template-
     substitution-free for path-config keys. Verify ONCE per release
     that `update-zskills/SKILL.md`'s Step C does NOT depend on
     `output.*` keys. Future schema additions that introduce
     `{{PLANS_DIR}}`-style template substitution MUST revisit this
     ordering (CI guard added in 5a.4 case 4 below).

  3. **Move forensic + narrative reports → `.zskills/audit/`.** `mkdir -p
     .zskills/audit`. For each of the five top-level reports plus every
     file in `reports/`, run `git mv` if tracked, `mv` if untracked.
     Verify EACH move with explicit branching:

     ```bash
     for f in SPRINT_REPORT.md FIX_REPORT.md PLAN_REPORT.md \
              VERIFICATION_REPORT.md NEW_BLOCKS_REPORT.md; do
       [ -e "$f" ] || continue
       if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
         git mv "$f" ".zskills/audit/$f"
       else
         mv "$f" ".zskills/audit/$f"
       fi
       if [ -e ".zskills/audit/$f" ] && [ ! -e "$f" ]; then
         echo "moved: $f"
       else
         echo "FAIL: move $f → .zskills/audit/$f did not complete" >&2
         exit 1
       fi
     done
     ```

     Same loop shape (with `else echo FAIL; exit 1`) for every move
     throughout. Per CLAUDE.md "verify after every destructive op": never
     `&& echo` (which is silent on failure); always explicit `if/then/else
     echo FAIL >&2; exit 1`.

  4. **Move plans → `$TARGET_PLANS`.** `mkdir -p "$TARGET_PLANS"`.
     `git mv plans/<NAME>_PLAN.md "$TARGET_PLANS/"` for each. Same for
     `plans/PLAN_INDEX.md` and any `plans/CANARY*.md`. Recursively move
     `plans/blocks/` to `$TARGET_PLANS/blocks/`. Use the same explicit
     verification pattern from step 3.

  5. **Move issue trackers → `$TARGET_ISSUES`.** `mkdir -p "$TARGET_ISSUES"`.
     `git mv plans/{ISSUES_PLAN,BUILD_ISSUES,DOC_ISSUES,QE_ISSUES}.md
     "$TARGET_ISSUES/"` for any present.

  6. **Move `var/` runtime files.** Detect if `var/dev.pid` / `var/dev.log`
     are tracked: `git ls-files --error-unmatch <path> >/dev/null 2>&1`.
     `git mv` if tracked, plain `mv` otherwise. Targets:
     `.zskills/dev-server.pid`, `.zskills/dev-server.log`. After moves, if
     `var/` exists and is empty: `rmdir var/` with explicit failure check
     (don't suppress).

     **Stub-script handling (DEFER, per DA finding 5).** `tier1-shipped-hashes.txt`
     does NOT cover `start-dev.sh` / `stop-dev.sh` (verified at
     `script-ownership.md:173-186`). `migrate-paths.sh` does NOT attempt
     auto-edit of these scripts. ALWAYS print to stdout the deferral
     notice naming both files; the agent-runnable upgrade prompt
     (Phase 5b) handles them.

  7. **Update `.gitignore`.** Re-read `.gitignore`. The migration is
     defensive — search-and-only-add pattern (so `var/` removal is
     conditional on its presence; absent line is fine):

     ```bash
     # Add .zskills/audit/ if not already present (idempotent).
     if ! grep -qE '^\.zskills/audit/$' .gitignore; then
       echo ".zskills/audit/" >> .gitignore
     fi
     # Add .zskills/issues/ ONLY if $TARGET_ISSUES is under .zskills/.
     case "$TARGET_ISSUES" in
       .zskills/*|"$MAIN_ROOT/.zskills/"*)
         if ! grep -qE '^\.zskills/issues/$' .gitignore; then
           echo ".zskills/issues/" >> .gitignore
         fi
         ;;
     esac
     # Remove obsolete var/ line if present (no-op if absent).
     if grep -qE '^var/$' .gitignore; then
       sed -i.bak '\|^var/$|d' .gitignore && rm -f .gitignore.bak
     fi
     ```

     Verify effective ignore via:
     ```bash
     mkdir -p .zskills/audit && touch .zskills/audit/.tmp-ignore-check
     # Use git check-ignore -v to inspect the matching pattern (catches
     # umbrella-vs-specific anchor differences AND positive !include rules
     # that would falsely include a file that should be ignored).
     match=$(git check-ignore -v .zskills/audit/.tmp-ignore-check 2>/dev/null) || {
       echo "FAIL: .zskills/audit/ not effectively ignored" >&2
       rm -f .zskills/audit/.tmp-ignore-check
       exit 1
     }
     # Pattern must be one of: ".zskills/audit/", ".zskills/", or a
     # parent-include rule. Reject positive !.zskills/audit*-style and
     # !.zskills/-style override rules — both forms re-include an
     # otherwise-ignored path. (Round-3 DA F14: prior copy-paste typo
     # had the alternation listing `*!\.zskills/audit*` twice.)
     case "$match" in
       *!\.zskills/audit*|*!\.zskills/*)
         echo "FAIL: positive include rule overrides .zskills ignore: $match" >&2
         rm -f .zskills/audit/.tmp-ignore-check
         exit 1 ;;
     esac
     rm -f .zskills/audit/.tmp-ignore-check
     ```

     This catches the order-hazard from DA finding 11 (e.g., umbrella
     `.zskills/` ignore preceding `!.zskills/audit/`) AND positive-
     include rules per round-2 DA F15.

  8. **(reserved — was `--rerender` step in round-2 plan; now hoisted to 2.5).**

  9. **Write `.pre-paths-migration` move manifest.** Per Locked Decision 9:
     write-once. Content = tab-separated `from\tto\n` for every move
     performed (kept in a bash array during steps 3-6). Refuse to write if
     `.pre-paths-migration` already exists (idempotent guard, per
     `test-update-zskills-rerender.sh` precedent).

     **Note on ordering** (per round-2 reviewer F13): manifest is written
     AFTER all moves succeed, AFTER hook rerender, BEFORE config-key
     write. So a config-write-failure leaves a manifest + moved files +
     rerendered hook + no config keys. Recovery: helper falls back to
     legacy `plans/` (where moved files no longer live) — read fails
     loudly. The manifest's existence prevents idempotent re-run from
     attempting the moves again. Recovery path: user removes
     `.pre-paths-migration` AND restores files from manifest, OR sets the
     two config keys manually (referencing the manifest's TO column).

  10. **Write the config keys (LAST).** Use the `apply-preset.sh`
      JSON-edit pattern, anchored on the enclosing `{` of an `output`
      object — create the object if absent. **Atomically write BOTH keys
      or NEITHER.** If config already has `output.plans_dir` set, leave it
      and check that `output.issues_dir` is also present; if EITHER is
      missing, write both with the resolved targets from step 2. Never
      write only one.

      Rationale: per Locked Decision 9, putting the config write LAST
      means a mid-migration abort (e.g., step 4 fails) leaves the consumer
      with no `output.plans_dir` set, so the helper falls back to legacy
      `plans/`, where any un-moved files still live. The user sees a
      partial-but-functional state, not a broken state.

  11. **Print summary** to stdout:

     ```
     MIGRATED: SPRINT_REPORT.md → .zskills/audit/SPRINT_REPORT.md
     MIGRATED: ... (continue per move) ...
     Wrote .pre-paths-migration with N entries.
     Re-rendered hooks (broadened recursive-delete fence — applied EARLY).
     Wrote output.plans_dir = "<TARGET_PLANS>" and output.issues_dir = "<TARGET_ISSUES>".
     For start-dev.sh / stop-dev.sh customizations, see
     .claude/skills/update-zskills/references/path-config-upgrade.md.
     ```

- [ ] **5a.4 — New test suite: `tests/test-update-zskills-paths-migration.sh`.**
  Modeled on `tests/test-update-zskills-migration.sh`. Phase 5a registers
  4 of the 9 test cases (the simple ones); Phase 5b adds 5 more.

  **Phase 5a cases:**
  - **Case 1: legacy-only fixture.** Synthetic repo with `plans/FOO_PLAN.md`,
    `reports/plan-foo.md`, `SPRINT_REPORT.md`, `var/dev.pid`. Run
    `migrate-paths.sh`. Assert: legacy paths absent, new paths present,
    `.pre-paths-migration` exists, manifest matches moves, config gained
    `output.plans_dir = "docs/plans"` AND `output.issues_dir = ".zskills/issues"`
    (BOTH keys, atomic — locked decision 4).
  - **Case 2: pre-configured.** Fixture with `output.plans_dir = "stash"`
    AND `output.issues_dir = ".zskills/issues"` already set. Run. Assert:
    plans go to `stash/`, NOT `docs/plans/`; issues land in `.zskills/issues/`.
  - **Case 3: idempotent re-run.** Run twice. Second run prints "already
    migrated" and exits 0; `.pre-paths-migration` mtime unchanged.
  - **Case 4: empty fixture (no legacy).** No-op; `.pre-paths-migration`
    NOT created; config unchanged.

  **Future-proofing CI guard for rerender ordering** (per round-2 DA F4):
  add a sub-assertion in Case 1 that scans `update-zskills/SKILL.md`'s
  Step C section for any new `{{...}}` template placeholders that
  reference path-config keys. If found, fail with: "Step C now substitutes
  path-config keys; revisit migrate-paths.sh step 2.5/9 ordering." This
  catches future template additions that would break the rerender-before-
  config-write invariant.

  Register in `tests/run-all.sh` alphabetically.

- [ ] **5a.5 — Update `script-ownership.md`.** Add a Tier-1 row for
  `migrate-paths.sh`:

  ```markdown
  | `migrate-paths.sh`           | 1      | one-shot deterministic mover for /update-zskills --migrate-paths; writes .pre-paths-migration; updates .gitignore; rerenders hook EARLY (step 2.5), writes output.plans_dir / output.issues_dir LAST |
  ```

- [ ] **5a.6 — Mirror update-zskills.** `bash scripts/mirror-skill.sh
  update-zskills`. Assert clean.

- [ ] **5a.7 — Commit.** Subject:
  `feat(update-zskills): add --migrate-paths deterministic mover and 4 test cases`.

### Design & Constraints

**Verify after every move.** Per CLAUDE.md "Never suppress errors on
operations you need to verify": every `git mv` / `mv` is followed by
explicit `if/then/else echo FAIL >&2; exit 1`, never `&& echo "moved"`,
never `2>/dev/null`. CLAUDE.md cites the past failure: "five worktree
removals all silently failed because errors were suppressed."

**Atomic config write.** Step 10 writes BOTH `plans_dir` and `issues_dir`
or NEITHER. Never one without the other. Avoids the asymmetric mixed-state
flagged in DA finding 9.

**Config write is LAST.** Per Locked Decision 9 / DA finding 25, ordering
file moves before config write means mid-failure leaves the helper resolving
to legacy `plans/`, where partial moves haven't broken anything.

**Hook rerender is FIRST file-system change** (per round-2 DA F19). Hook
strengthens BEFORE filesystem changes that create `.zskills/audit/`,
`.zskills/issues/`, etc. — so a mid-migration agent invoking
`rm -rf .zskills/audit` for cleanup is BLOCKED by the broadened hook.

**Effective gitignore verification.** Per DA finding 11 + round-2 DA F15,
the migration must verify `git check-ignore -v` returns the new patterns
AS effective AND not overridden by a positive-include rule. Step 7's
`tmp-ignore-check` file does this.

**Test outputs to `/tmp/zskills-tests/...`** per CLAUDE.md canonical
idiom.

### Acceptance Criteria

- [ ] `skills/update-zskills/scripts/migrate-paths.sh` exists, executable.
- [ ] `tests/test-update-zskills-paths-migration.sh` registered in
  `tests/run-all.sh`; cases 1-4 PASS.
- [ ] `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` green.
- [ ] `skills/update-zskills/SKILL.md` documents `--migrate-paths` (the
  flag, the script dispatch, the agent-runnable follow-up).
- [ ] `script-ownership.md` has the new Tier-1 row.
- [ ] `grep -c "allow-hardcoded.*Phase 5a" skills/update-zskills/SKILL.md`
  returns 4 (per 5a.2 marker enumeration).
- [ ] `diff -rq skills/update-zskills .claude/skills/update-zskills` clean.
- [ ] One commit.

### Dependencies

Phase 1 (schema, helper). Phases 2a/2b/3/4 SHOULD land first — otherwise
consumers running `--migrate-paths` would move files to paths that the
unmigrated skills/scripts won't find.

---

## Phase 5b — Cross-reference rewrite + complex test cases

### Goal

Add the cross-reference rewrite step to `migrate-paths.sh` plus the
remaining 5 test cases (so 4 + 5 = 9 cases total). Authors the agent-
runnable upgrade prompt for long-tail customizations (start-dev.sh /
stop-dev.sh).

### Work Items

- [ ] **5b.1 — Add cross-reference rewrite to `migrate-paths.sh`.** New
  function appended AFTER step 7 (gitignore update) and BEFORE step 9
  (manifest write) — so that if the cross-ref rewrite aborts, the
  manifest is NOT yet written and the script's idempotent guard does not
  refuse re-run.

  Specification (NOT a verbatim lift from
  `update-zskills/SKILL.md:747-814`; that algorithm requires a rendered
  template input which plans don't have).

  **Fence-tracking implementation** (per round-2 reviewer F8). The
  function must maintain fence state across lines while scanning. Use the
  conformance scanner's idiom verbatim (`tests/test-skill-conformance.sh:1066-1124`)
  as the model:

  ```bash
  cross_ref_rewrite() {
    local file="$1"
    local target_plans="$2"
    local in_fence=0
    local fence_lang=""
    local out_file
    out_file=$(mktemp)
    while IFS= read -r line || [ -n "$line" ]; do
      # Fence open/close detection (mirror of test-skill-conformance.sh idiom).
      if [[ "$line" =~ ^[[:space:]]*\`\`\`([a-zA-Z0-9_+-]*)[[:space:]]*$ ]]; then
        if [ "$in_fence" -eq 0 ]; then
          in_fence=1
          fence_lang="${BASH_REMATCH[1]}"
        else
          in_fence=0
          fence_lang=""
        fi
        printf '%s\n' "$line" >> "$out_file"
        continue
      fi
      # Decide if line is a structural reference (4 enclosure types).
      local rewrite=0
      # Enclosure 1: markdown link [...](TOKEN)
      if [[ "$line" =~ \[[^]]*\]\((plans/[A-Za-z][A-Za-z0-9_-]*\.md|reports/(plan|verify|briefing|new-blocks)-[a-z0-9-]+\.md) ]]; then
        rewrite=1
      fi
      # Enclosure 2: backticked code-span containing TOKEN
      if [[ "$line" =~ \`[^\`]*(plans/[A-Za-z][A-Za-z0-9_-]*\.md|reports/(plan|verify|briefing|new-blocks)-[a-z0-9-]+\.md)[^\`]*\` ]]; then
        rewrite=1
      fi
      # Enclosure 3: bash/shell command-line — either inside a bash/sh/shell/empty fence
      # OR starts with `$ ` OR contains shell metachars indicating an invocation.
      if [ "$in_fence" -eq 1 ] && { [ "$fence_lang" = "bash" ] || [ "$fence_lang" = "sh" ] || [ "$fence_lang" = "shell" ] || [ -z "$fence_lang" ]; }; then
        if [[ "$line" =~ (plans/[A-Za-z][A-Za-z0-9_-]*\.md|reports/(plan|verify|briefing|new-blocks)-[a-z0-9-]+\.md) ]]; then
          rewrite=1
        fi
      fi
      if [[ "$line" =~ ^\$[[:space:]] ]] || [[ "$line" =~ [\|\>\<\;][[:space:]]*$ ]]; then
        if [[ "$line" =~ (plans/[A-Za-z][A-Za-z0-9_-]*\.md|reports/(plan|verify|briefing|new-blocks)-[a-z0-9-]+\.md) ]]; then
          rewrite=1
        fi
      fi
      # Enclosure 4: slash-command invocation
      if [[ "$line" =~ /(run-plan|draft-plan|refine-plan|draft-tests|work-on-plans|research-and-plan|research-and-go)[[:space:]]+(plans/[A-Za-z][A-Za-z0-9_-]*\.md|reports/(plan|verify|briefing|new-blocks)-[a-z0-9-]+\.md) ]]; then
        rewrite=1
      fi
      if [ "$rewrite" -eq 1 ]; then
        # Substitute `plans/X.md` → `<TARGET_PLANS>/X.md`; `reports/Y.md` → `.zskills/audit/Y.md`.
        line="${line//plans\//${target_plans}\/}"
        # The reports/ regex is narrower (only plan-/verify-/briefing-/new-blocks- prefix).
        line=$(printf '%s\n' "$line" \
          | sed -E "s#reports/(plan|verify|briefing|new-blocks)-#.zskills/audit/\\1-#g")
      fi
      printf '%s\n' "$line" >> "$out_file"
    done < "$file"
    # Preserve original file mode/owner across the swap (round-3
    # reviewer F10): mktemp produces 0600; markdown plans are 0644 in
    # tracked state. `chmod --reference` is Linux-only — the `|| true`
    # is acceptable because absence (e.g., macOS) means the file gets
    # 0600 once and `git add` normalizes on commit. Also reject
    # symlinked plans defensively (plans should not be symlinks).
    if [ -L "$file" ]; then
      echo "WARN: cross_ref_rewrite skipping symlink: $file" >&2
      rm -f "$out_file"
      return 0
    fi
    chmod --reference="$file" "$out_file" 2>/dev/null || true
    mv "$out_file" "$file"
  }
  ```

  This skeleton tracks `in_fence` and `fence_lang` across lines, mirroring
  the conformance-scanner state machine.

  **Known limitation — nested fences (round-3 DA F19).** The fence-tracker
  uses the conformance-scanner idiom verbatim (`tests/test-skill-conformance.sh:1066-1124`),
  which only detects three-backtick fences. A plan file documenting how
  to write fences (e.g., a code example using four-backtick outer fence
  containing a three-backtick inner fence) flips state spuriously. This
  is the same limitation the conformance scanner has — accepting it
  here keeps both tools aligned. **Mitigation:** Phase 5b post-rewrite
  AC adds a sanity grep to surface plan files containing nested fences
  for human review:

  ```bash
  grep -lE '^[[:space:]]*\`\`\`\`' "$TARGET_PLANS"/*.md \
    > "$TEST_OUT/nested-fence-candidates.txt" || true
  ```

  If non-empty, the verifier reports the file list (no auto-action;
  user reviews whether the rewrite produced expected output).

  **What gets rewritten — STRUCTURAL REFERENCES only:**

  A line is a "structural reference" iff the path token (`plans/X.md` or
  `reports/Y.md` for matching slugs) is enclosed by ONE of:
  1. **Markdown link:** `[<anything>](<TOKEN>)` or
     `[<anything>](<TOKEN>#anchor)`
  2. **Backticked code-span:** `` `<TOKEN>` ``
  3. **Bash/shell command-line:** the line either (a) starts with `$ ` or
     ends with shell metachars indicating an invocation (`|`, `>`, `<`,
     `;`), OR (b) is inside a fenced code block opened with
     ```` ```bash ```` / ```` ```sh ```` / ```` ```shell ```` / ```` ``` ````
     (empty lang).
  4. **Slash-command invocation:** the line contains the literal
     `/run-plan ` or `/draft-plan ` or `/refine-plan ` or `/draft-tests `
     or `/work-on-plans ` or `/research-and-plan ` or `/research-and-go `
     followed by `<TOKEN>`.

  **What does NOT get rewritten — naked prose:**

  Any line where `<TOKEN>` appears without the four enclosures above.
  Example NON-match: `we used to keep our plans under plans/ before this
  migration` — token is bare, no enclosure, preserve.

  **Path tokens (regexes; literal-quoted in the script):**

  ```
  re1: \([^A-Za-z0-9_/.-]\|^\)plans/\([A-Za-z][A-Za-z0-9_-]*\.md\)
  re2: \([^A-Za-z0-9_/.-]\|^\)reports/\(plan\|verify\|briefing\|new-blocks\)-\([a-z0-9-]\+\.md\)
  ```

  **Why broadened (round-3 DA F12):** real plan filenames in zskills
  include kebab-case (`plans/cross-platform-hooks.md` verified at
  refinement time); the original `[A-Z][A-Z0-9_]*` would have left such
  links broken post-migration. The broader char class
  `[A-Za-z][A-Za-z0-9_-]*` matches both ALL_CAPS_UNDERSCORE
  (e.g., `ZSKILLS_PATH_CONFIG`) and kebab-or-mixed
  (`cross-platform-hooks`). The leading char class excludes leading
  digits/hyphens, and the trailing `\.md` anchor excludes
  `plans/foo.md.bak`-style false positives (verify post-edit:
  `echo 'plans/foo.md.bak' | grep -E 'plans/[A-Za-z][A-Za-z0-9_-]*\.md'`
  must NOT match `plans/foo.md.bak` as a whole token — but **note**: the
  regex DOES match the leading `plans/foo.md` substring. That is fine
  for backup-file references because the cross-ref rewrite operates per
  enclosure, and backup names are not enclosed in markdown links /
  backticks / shell args / slash-commands. Implementer verifies the
  fixture in Case 6 includes a `.md.bak` line that is NON-matched
  through enclosure-rule).

  **Substitution:**
  - `plans/X.md` → `<TARGET_PLANS>/X.md` (where `<TARGET_PLANS>` is the
    resolved value from step 2 of 5a.3).
  - `reports/Y.md` → `.zskills/audit/Y.md`.

  **Variants `re1` does NOT match — but DO get caught by an additional
  scan over plan files** (per round-2 DA F5: don't defer hole closure):
  - `$MAIN_ROOT/plans/...`
  - `$WORKTREE_PATH/plans/...`
  - `/workspaces/zskills/plans/...` (absolute paths)

  These appear primarily in fences whose surrounding context is a
  `bash` example. The cross-ref rewrite ALSO greps each in-scope plan
  for these forms post-rewrite and emits a WARNING (NOT silent skip)
  listing each match for the user to review. AC: a Phase 5b case
  asserts the warning fires for a known fixture.

  **Concrete examples (3 match, 2 non-match):**

  | Line | Verdict |
  |------|---------|
  | `[See PLAN_X](plans/PLAN_X.md)` | MATCH (markdown link) → `[See PLAN_X](docs/plans/PLAN_X.md)` |
  | `Run \`/run-plan plans/CANARY1_HAPPY.md\`` | MATCH (slash-command + backtick) → `Run \`/run-plan docs/plans/CANARY1_HAPPY.md\`` |
  | `cp plans/PLAN_INDEX.md /tmp/` (inside `bash` fence) | MATCH (shell line) → `cp docs/plans/PLAN_INDEX.md /tmp/` |
  | `we previously kept plans/ at the repo root` | NON-MATCH (naked prose) — preserve |
  | `the user types plans/FOO.md as the argument` | NON-MATCH (naked prose) — preserve |

  **Scope — which plan files get rewritten (frontmatter decision tree):**

  Read the YAML frontmatter of each `<NAME>_PLAN.md` in `<TARGET_PLANS>/`
  POST-MOVE.

  | Frontmatter status | Action |
  |---|---|
  | `status: active` | REWRITE |
  | `status: proposal` | REWRITE |
  | (no frontmatter) | REWRITE |
  | (frontmatter exists but no `status:` field) | REWRITE |
  | `status: complete` AND filename matches `CANARY*.md` | REWRITE the slash-command-invocation lines ONLY (per DA finding 17 / reviewer finding 10 — canary plans need correct self-invocation paths even when frozen as historical narrative) |
  | `status: complete` AND filename does NOT match `CANARY*.md` | PRESERVE (frozen) — additionally SCAN and emit a stdout warning listing every legacy-path token found, so the user can decide whether to re-run the upgrade prompt for that plan. |
  | `status: deferred`/`paused`/anything else | PRESERVE (treated as frozen by default) — same SCAN + warning emit as above |

  **Warning emission contract** (round-3 DA F13 + DA F16). For every
  PRESERVED plan that contains a legacy-path token, the rewriter
  emits TWO outputs:

  1. **stderr** (so the run-log captures it visibly): one line per
     hit, in the format
     `WARN <plan-file>:<line>: legacy token '<token>' preserved (frozen plan; see path-config-upgrade.md)`.
     Example:
     `WARN docs/plans/OLD_FEATURE.md:42: legacy token 'plans/OTHER.md' preserved (frozen plan; see path-config-upgrade.md)`.
  2. **`.pre-paths-migration-warnings`** (a sibling of the manifest at
     repo root): the same lines, appended. The file is created on
     first warning; subsequent rewrites (e.g., `--rewrite-only` reruns)
     append further entries with a leading blank-line and a timestamp
     header `# rewrite-only: <ISO timestamp>`. The user can inspect
     this file to drive selective manual upgrades via
     `path-config-upgrade.md` task 3.

  Phase 5b.4 Case 8 asserts both outputs (per round-3 DA F16 — the
  vague "stdout WARNING" of round 2 is replaced with this exact
  format).

  **`--rewrite-only` flag (round-3 reviewer F5 / DA F5).** Phase 5b
  adds a flag-aware entry-point to `migrate-paths.sh` so mid-version-
  skip recovery (5b.2 task 4) can re-run JUST the cross-ref rewrite
  against an already-migrated tree. Argument parsing gains an OPTIONAL
  flag in front of the positional `<main-root>`:

  ```bash
  REWRITE_ONLY=0
  if [ "${1:-}" = "--rewrite-only" ]; then
    REWRITE_ONLY=1; shift
  fi
  MAIN_ROOT="${1:-}"
  [ -z "$MAIN_ROOT" ] && {
    echo "usage: migrate-paths.sh [--rewrite-only] <main-root>" >&2
    exit 1
  }
  ```

  Behavior under `--rewrite-only`:
  - **(a) Precondition: `.pre-paths-migration` MUST already exist.** If
    absent → exit 1 with stderr message: "no prior migration to rewrite
    — run `migrate-paths.sh <main-root>` first." This protects against
    invoking `--rewrite-only` against a not-yet-migrated repo (where
    `<TARGET_PLANS>` is unresolved and the rewriter would scan the
    legacy tree).
  - **(b) Skip steps 1-7 entirely** (detection, target resolution from
    fresh, rerender, file moves, gitignore — all already done).
  - **(c) Resolve `<TARGET_PLANS>`** by reading the EXISTING config's
    `output.plans_dir` value (NOT recomputing from defaults). If the
    config lacks `output.plans_dir`, exit 1 with: "config missing
    output.plans_dir; rewrite cannot proceed."
  - **(d) Execute ONLY the cross-ref rewrite** (the `cross_ref_rewrite()`
    function from this work item) over plan files matching the
    frontmatter decision tree above (lines for `status: active`,
    `proposal`, no-frontmatter, completed-canary self-invocation only).
  - **(e) Skip the manifest write** (step 9): the manifest already
    exists from the earlier run. Append a single trailer line:

    ```
    rewrite-only: <ISO-8601 timestamp>\t<count of files modified>
    ```

    This makes the second-pass rewrite traceable without re-writing the
    file from scratch (preserves the original move history).
  - **(f) Skip the config-key write** (step 10): config keys already
    exist from the earlier run. Idempotent re-runs of `--rewrite-only`
    against an already-rewritten tree are no-ops at the cross-ref level
    (the rewriter is itself idempotent — no legacy tokens remain to
    match).
  - **(g) Print summary**:
    ```
    REWROTE: <N> structural references in <M> plan files
    (--rewrite-only — manifest preserved; config unchanged)
    ```
  - **Exit 0** on success; non-zero on any rewrite failure.

  Phase 5b.4 Case 10 (added below) tests `--rewrite-only` mid-version-
  skip recovery.

  **Tracking-marker awareness (per DA finding 15):** `.zskills/tracking/`
  files reference plan slugs (filename basenames), NOT plan paths. They
  do NOT need rewrite. Verify post-rewrite:

  ```bash
  grep -rln '^plan_path:' .zskills/tracking/ 2>/dev/null
  ```

  Should return empty (markers reference slugs, never paths). If non-
  empty, surface a blocker.

- [ ] **5b.2 — Author the agent-runnable upgrade prompt.** New file:
  `skills/update-zskills/references/path-config-upgrade.md`. Mirrored at
  `.claude/skills/update-zskills/references/path-config-upgrade.md`.
  Content:

  ```markdown
  # Agent Upgrade Prompt — Path Config Long Tail

  Run this after `/update-zskills --migrate-paths` if the migration
  printed a "see path-config-upgrade.md" notice for `start-dev.sh` /
  `stop-dev.sh` or for plan files that were skipped (e.g., `status:
  complete` non-canary plans containing executable references).

  Tasks:

  1. Read `scripts/start-dev.sh`. If it writes to `var/dev.pid` or
     `var/dev.log`, propose a diff swapping those paths to
     `.zskills/dev-server.pid` and `.zskills/dev-server.log` respectively.
     If you see customization beyond the shipped defaults, surface the
     diff and ask the user before editing.

  2. Same for `scripts/stop-dev.sh`. The PID-read path moves identically.

  3. Read your active plan files (frontmatter `status: active` or
     `proposal`). If any contain shell commands referencing
     `plans/<NAME>.md` or `reports/<...>.md` paths AND the previous
     `--migrate-paths` cross-ref rewrite missed them (e.g., they're in a
     status:complete plan with non-canary slug), propose updates pointing
     at the new locations. Show diffs; ask before applying.

  4. **Mid-version-skip recovery** (per round-2 DA F10). If
     `.pre-paths-migration` already exists AND the `migrate-paths.sh`
     script has been updated to include cross-ref rewrite (verify by
     `grep -c "cross_ref_rewrite" .claude/skills/update-zskills/scripts/migrate-paths.sh`
     returns ≥1), the migration ran under an OLDER 5a-only version and
     the cross-ref rewrites for in-tree plan files were never applied.
     Apply them now: invoke
     `bash .claude/skills/update-zskills/scripts/migrate-paths.sh --rewrite-only "$MAIN_ROOT"`
     (the `--rewrite-only` flag is added in 5b.1 to support this path).

  5. Re-run `bash tests/run-all.sh` (or your project's test command) and
     verify everything passes.
  ```

- [ ] **5b.3 — Register the script-ownership row for the upgrade prompt.**
  Add a Tier-N reference-doc row (NOT a script — `tier1-shipped-hashes.txt`
  does NOT apply since it's a markdown reference doc):

  ```markdown
  | `path-config-upgrade.md`     | N      | agent-runnable upgrade prompt for path-config long-tail (start-dev.sh, stop-dev.sh, status:complete non-canary plans, mid-version-skip recovery) |
  ```

- [ ] **5b.4 — Add the remaining 6 test cases to `tests/test-update-zskills-paths-migration.sh`** (Cases 5-10; Case 10 is the `--rewrite-only` recovery added per round-3 reviewer F5 / DA F5).

  - **Case 5: customized stub.** `scripts/start-dev.sh` differs from
    shipped defaults; assert `migrate-paths.sh` declines to touch the
    file (per DA finding 5 deferral rule); summary mentions upgrade
    prompt.
  - **Case 6: cross-reference rewrite — structural references.** Plan
    with `[See plans/BAR.md](plans/BAR.md)` inline link, `\`plans/BAZ.md\``
    backticked, "we used to keep these in `plans/`" prose. Assert: link
    rewritten, backtick rewritten, prose NOT rewritten.
  - **Case 7: completed-canary self-invocation.** Plan with
    `status: complete` AND filename `CANARY7_TEST.md` containing line
    `Run /run-plan plans/CANARY7_TEST.md finish auto`. Assert: REWRITTEN
    to `docs/plans/CANARY7_TEST.md`. Compare to the non-canary completed
    case below.
  - **Case 8: completed-non-canary plan with legacy tokens.** Plan with
    `status: complete` AND filename `OLD_FEATURE.md` containing
    `[See OTHER](plans/OTHER.md)` link at line 42. Assert (per round-3
    DA F16):
    - The plan file is NOT rewritten (byte-equal to pre-run).
    - Captured stderr contains a line matching the regex
      `^WARN .*OLD_FEATURE\.md:42: legacy token 'plans/OTHER\.md' preserved`.
    - The repo-root file `.pre-paths-migration-warnings` exists and
      contains the same line.
  - **Case 9: hook re-render and effective gitignore.** After migration:
    (a) `.claude/hooks/block-unsafe-project.sh` contains the broadened
    `\.zskills` regex (NOT `\.zskills/tracking`); (b) `git check-ignore
    -v .zskills/audit/dummy` exits 0 with the matching pattern (no
    `!`-prefixed override).
  - **Case 10: `--rewrite-only` mid-version-skip recovery.** Two-phase
    fixture. **Phase A** (simulates an older migration that did NOT
    include cross-ref rewrite): create a fixture with a migrated tree
    (`.pre-paths-migration` present, plans moved to `docs/plans/`,
    config has `output.plans_dir = "docs/plans"`) BUT leave a plan file
    `docs/plans/STILL_LEGACY.md` (status: active) containing the line
    `Run \`/run-plan plans/SOMETHING.md\`` (not yet rewritten). **Phase
    B**: invoke `bash migrate-paths.sh --rewrite-only "$FIXTURE"`.
    Assert:
    - exit 0;
    - `STILL_LEGACY.md` line is now `Run \`/run-plan docs/plans/SOMETHING.md\``;
    - `.pre-paths-migration` STILL exists (not overwritten) and gained a
      trailer `rewrite-only:	<ISO timestamp>	1` line;
    - config keys UNCHANGED (`output.plans_dir = "docs/plans"`,
      `output.issues_dir = ".zskills/issues"` — both still set, no flip);
    - re-running `--rewrite-only` again is idempotent (exits 0; trailer
      gains a second line; no plan content changes).
    AND a NEGATIVE case (precondition enforcement): a pristine fixture
    WITHOUT `.pre-paths-migration` invoked with `--rewrite-only` exits
    non-zero with stderr containing "no prior migration to rewrite."

  **Per-fence allow-hardcoded markers added to update-zskills/SKILL.md**
  during 5b: 4 markers (one per cross-ref-rewrite algorithm fence). AC:
  `grep -c "allow-hardcoded.*Phase 5b" skills/update-zskills/SKILL.md`
  returns 4. Combined with 5a's 4, total markers added by Phase 5 to
  `update-zskills/SKILL.md` = 8 (matches Phase 1 enumeration).

  Per-fence markers added to `path-config-upgrade.md`: 2 (one per
  upgrade-task narrative fence containing forbidden literals).

- [ ] **5b.5 — Mirror update-zskills.** Mirror clean.

- [ ] **5b.6 — Commit.** Subject:
  `feat(update-zskills): cross-reference rewrite + agent upgrade prompt for path config`.

### Design & Constraints

**Adapted, NOT lifted.** The original
`skills/update-zskills/SKILL.md:747-814` algorithm operates on a
`$RENDERED_TEMPLATE` produced by substituting placeholders in
`CLAUDE_TEMPLATE.md`. Plan files have no template input, so the
"context signature = ±2-line template neighbourhood" concept does NOT
transfer. The adapted approach uses ENCLOSURE TYPE (markdown link,
backtick, shell line, slash-command) as the structural-reference signal.
This is sharper than ±2-line context for plan content (where prose and
structural refs may be on adjacent lines).

**Fence tracking is line-by-line state.** The implementation skeleton
in 5b.1 maintains `in_fence` and `fence_lang` across lines, mirroring
`tests/test-skill-conformance.sh:1066-1124`. Implementer must read that
section as the reference; do NOT freelance an alternative state machine.

**Why slash-command is its own enclosure type:** the shell-line check
catches lines inside fenced code blocks. Slash commands often appear in
prose — "Then run `/run-plan plans/X.md`." Treating slash-command-prefix
as a structural enclosure means the test-case 7 self-invocation in
canary plans rewrites correctly.

**Test outputs to `/tmp/zskills-tests/...`.**

### Acceptance Criteria

- [ ] `migrate-paths.sh` cross-ref rewrite function present; verifier
  reads the function source and confirms: (a) 4 enclosure types, (b)
  fence-tracking idiom matches `test-skill-conformance.sh:1066-1124`
  shape, (c) frontmatter decision tree, (d) `$MAIN_ROOT/...` /
  `$WORKTREE_PATH/...` SCAN-and-warn fallback.
- [ ] `skills/update-zskills/references/path-config-upgrade.md` exists,
  mirrored, includes the mid-version-skip recovery task (per Case 5b.2
  task 4).
- [ ] `tests/test-update-zskills-paths-migration.sh` cases 5, 6, 7, 8, 9,
  10 PASS — total case count is 10 (4 from Phase 5a + 6 from Phase 5b,
  including `--rewrite-only` recovery in Case 10).
- [ ] `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` green.
- [ ] `grep -c "allow-hardcoded.*Phase 5b" skills/update-zskills/SKILL.md`
  returns 4; total `Phase 5a + 5b` allow-hardcoded markers = 8.
- [ ] `diff -rq skills/update-zskills .claude/skills/update-zskills` clean.
- [ ] One commit.

### Dependencies

Phase 5a (the `migrate-paths.sh` script + flag dispatch).

---

## Phase 6 — Self-migration + canary gating + docs

### Goal

Apply `/update-zskills --migrate-paths` to the zskills repo itself, gate
via the canary suite (CANARY1, 6, 7, 8, 9, 10), and update CHANGELOG,
RELEASING, CLAUDE_TEMPLATE, README, and the plan registry.

### Work Items

- [ ] **6.1 — Apply `--migrate-paths` to zskills.** From a feature branch
  (NOT main). BEFORE running:

  ```bash
  # Copy the active plan to /tmp so the agent has a stable read source
  # mid-migration (the plan file itself is being moved). ALSO copy the
  # post-rewrite version for canary self-invocations (per round-2 DA F14).
  cp plans/ZSKILLS_PATH_CONFIG.md /tmp/ZSKILLS_PATH_CONFIG.md.preserve
  # Snapshot tracking markers (none should reference plan PATHS, but
  # verify before moving).
  ls .zskills/tracking/*/ 2>/dev/null \
    | xargs -I {} grep -ln '^plan_path:\|plans/' {} 2>/dev/null \
    > /tmp/tracking-paths-check.txt
  if [ -s /tmp/tracking-paths-check.txt ]; then
    echo "BLOCKER: tracking markers reference plan paths — review and resolve before migrating" >&2
    cat /tmp/tracking-paths-check.txt >&2
    exit 1
  fi
  ```

  (Per round-2 reviewer F14: prose said "blocker," code said "WARN" —
  unified to BLOCKER + exit 1; consistent with failure-modes section #7.)

  Then run the documented migration. Verify:
  - `git ls-files | grep -E '^(plans|reports)/'` returns empty (legacy
    paths gone).
  - `git ls-files | grep -E '^docs/plans/'` returns ~50+ entries.
  - `.zskills/audit/` is gitignored (not in `git ls-files`) but contains
    the migrated reports.
  - `.zskills/issues/` is gitignored; ISSUES_PLAN/BUILD/DOC/QE not present
    (zskills self-content, not consumer artifacts).
  - `.pre-paths-migration` exists and is a tab-separated manifest.
  - `var/` directory is gone (was already absent in zskills repo;
    migration is a no-op for var/ here — consumers may differ).
  - `.gitignore` has `.zskills/audit/` line.
  - `.claude/zskills-config.json` has BOTH `output.plans_dir = "docs/plans"`
    AND `output.issues_dir = ".zskills/issues"` (atomic — locked decision 4).
  - `git check-ignore -v .zskills/audit/dummy` exits 0 with a matching
    pattern (per round-2 DA F15: verbose flag exposes the rule, catches
    positive-include overrides).

- [ ] **6.2 — Run the full canary suite as plan-gating.** **Path-resolution
  rule** (per round-2 DA F14 + round-3 reviewer F9): for each canary, the
  implementing agent re-derives the resolved canary path POST-MIGRATION
  by sourcing the helper, NOT by typing `docs/plans/...`. Hardcoding
  `docs/plans/` here is correct for the zskills self-migration (the
  documented default and the value Phase 6.1 wrote into the config),
  but the hardcoding makes this work item brittle if a future zskills
  release changes the default OR a user pre-set a different
  `output.plans_dir` before self-migrating. Use the helper:

  ```bash
  source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  CANARY1_PATH="$ZSKILLS_PLANS_DIR/CANARY1_HAPPY.md"
  CANARY6_PATH="$ZSKILLS_PLANS_DIR/CANARY6_MULTI_PR.md"
  CANARY7_PATH="$ZSKILLS_PLANS_DIR/CANARY7_CHUNKED_FINISH.md"
  # Verify each resolves to a real file before invoking:
  for p in "$CANARY1_PATH" "$CANARY6_PATH" "$CANARY7_PATH"; do
    [ -f "$p" ] || { echo "FAIL: canary not at $p" >&2; exit 1; }
  done
  ```

  The `/run-plan` argument MUST be the resolved path
  (`$ZSKILLS_PLANS_DIR/CANARY1_HAPPY.md` substituted to its full string),
  NOT a token. Phase 2a.5 argument-parsing prepends `$ZSKILLS_PLANS_DIR/`
  only when the token is `/`-free; once the agent provides
  `plans/CANARY...`, that bypasses the prepend logic and the file isn't
  found.

  **Why hardcode `docs/plans/` in the example commands below** (round-3
  reviewer F9 + DA F6): for THIS plan's Phase 6 (zskills self-migration)
  the documented default IS `docs/plans/`, so the example commands
  literal-quote that path for clarity. The implementer treats them as
  guidance — the actual `/run-plan` argument is the
  `$CANARYN_PATH` variable derived above (which equals
  `docs/plans/CANARY...` only because Phase 6.1 wrote the default into
  config). Generalised CONSUMER guidance lives in
  `skills/update-zskills/references/path-config-upgrade.md` and resolves
  via the helper.

  - **CANARY1** (smoke happy path): RE-DERIVE the path POST-MIGRATION
    before invoking (using `$CANARY1_PATH` above). Pre-migration:
    `/run-plan plans/CANARY1_HAPPY.md`. Post-migration:
    `/run-plan "$CANARY1_PATH"` (resolves to
    `docs/plans/CANARY1_HAPPY.md` for zskills self-migration). Asserts:
    plan resolves, audit-dir report written, tracker updated.
    **Auto-dispatched** — `/run-plan "$CANARY1_PATH" finish auto`.
  - **CANARY6** (multi-PR sequential): exercises PR-mode bookkeeping on
    feature branch. Critical for the helper's worktree-vs-main resolution.
    **Auto-dispatched** — `/run-plan "$CANARY6_PATH" finish auto pr`.
  - **CANARY7** (chunked finish): cross-cron-turn path stability.
    **Auto-dispatched** — `/run-plan "$CANARY7_PATH" finish auto`.
  - **CANARY8** (parallel pipelines): two `/run-plan` invocations on
    disjoint plans. Tier-2 audit dir filename uniqueness preserved.
    **Manual canary** — implementer must NOT auto-dispatch; user runs in
    two windows. Cited reason: requires two simultaneous Claude Code
    sessions, which a single agent cannot orchestrate.
  - **CANARY9** (cross-branch final-verify): cross-branch verify writes +
    final-verify markers under `.zskills/tracking/`. **Manual canary**
    (per round-2 reviewer F1 + DA F13: corrected from round-1's incorrect
    auto-dispatch claim). Cited reason from
    `plans/CANARY9_FINAL_VERIFY.md:21` verbatim: *"This is a manual canary
    — it requires multiple cron-fired turns over real wall-clock time
    (10 min minimum, up to ~2 h if the verify takes a while)."* The
    implementing agent does NOT dispatch this; the user runs it manually
    per the canary plan's runbook. If the implementer believes the canary
    is auto-dispatchable, the change must be made to the canary plan
    ITSELF first, not flipped silently here.
  - **CANARY10** (PR mode finish): single-PR happy path complement to
    CANARY6. **Manual canary** (per round-2 reviewer F1: corrected from
    round-1's incorrect auto-dispatch claim). Cited reason from
    `plans/CANARY10_PR_MODE.md:22` verbatim: *"This is a manual canary —
    it requires real GitHub state (PR creation, GitHub Actions run,
    merge). The user has explicitly confirmed they're happy to run this
    manually."*

  Each canary's PASS evidence captured in the verify report. Manual
  canaries (CANARY8, CANARY9, CANARY10) include evidence of user-driven
  execution per their runbooks; auto canaries (CANARY1, 6, 7) note the
  dispatching session ID.

  **Canary-failure remediation** (per round-2 reviewer F19):
  - If a canary fails in 6.2, do NOT proceed to 6.3+.
  - Diagnose the failure first.
  - For fix-forward: commit the fix in a follow-up commit on the same
    Phase 6 feature branch (do NOT amend the migration squash).
  - For revert: use a clean `git revert` commit (do NOT undo the
    `git mv`s manually).
  - Re-run the failed canary; only proceed if it passes.

- [ ] **6.3 — Update `CHANGELOG.md`.** ADD ONE entry at the top of the
  unreleased section:

  ```
  - feat(paths): introduce `output.plans_dir` and `output.issues_dir`
    config keys; default `docs/plans/` and `.zskills/issues/`; new
    `/update-zskills --migrate-paths` for in-place upgrade. Note:
    consumers who hand-edited `.claude/zskills-config.schema.json` will
    see those edits overwritten on re-install (rare; schema source of
    truth is `config/zskills-config.schema.json`).
  ```

  Per `feedback_no_premature_backcompat`: do NOT touch any existing
  CHANGELOG row.

- [ ] **6.4 — Update `RELEASING.md` (minimal note only).** Per prior art
  (SCRIPTS_INTO_SKILLS_PLAN) AND verified at refinement time
  (`grep -n RELEASING scripts/build-prod.sh` → line 57): RELEASING.md is
  stripped from prod builds. Route the full migration narrative to
  CHANGELOG + README; RELEASING.md gets a minimal one-line note pointing
  at the CHANGELOG entry. (Round-3 DA F20: round-2's "if NOT stripped,
  update fully" branch was dead at refinement; trimmed.)

  ```markdown
  ### Migration: ZSKILLS_PATH_CONFIG (post-<version>)

  See CHANGELOG entry for `feat(paths)` and
  `.claude/skills/update-zskills/references/path-config-upgrade.md` for
  the long-tail customization upgrade prompt.
  ```

  **If a future commit removes the strip from build-prod.sh, this work
  item must be revised** to include the full migration narrative
  inline.

- [ ] **6.5 — Update `CLAUDE.md`.** Add one sentence under the
  tracking-markers paragraph noting the broadened hook fence (re-derive
  insertion point via
  `grep -n 'Tracking markers' /workspaces/zskills/CLAUDE.md`). Path
  convention itself doesn't need a CLAUDE.md rule.

- [ ] **6.6 — Update `CLAUDE_TEMPLATE.md`.** Re-derive line via
  `grep -n 'var/dev' CLAUDE_TEMPLATE.md`. Replace `var/dev.pid`,
  `var/dev.log` with `.zskills/dev-server.pid`, `.zskills/dev-server.log`.

- [ ] **6.6.1 — Update `update-zskills` install sources for `var/dev` →
  `.zskills/dev-server.{pid,log}` (closes the install-time propagation
  hole; round-3 reviewer F2 / P0).** The `--migrate-paths` step (Phase
  5a step 6) moves an EXISTING consumer's `var/dev.pid` →
  `.zskills/dev-server.pid`, but the SOURCES that `/update-zskills
  install` copies into a fresh consumer still emit `var/dev.pid`. Without
  this work item, every new consumer install AFTER this plan ships would
  re-introduce the legacy path. Per "skill-framework repo — surface bugs
  don't patch": fix the source.

  Edit each of the following at refinement-derived line ranges (the
  implementer re-derives via `grep -n 'var/dev' <file>` BEFORE editing):

  - **`skills/update-zskills/stubs/start-dev.sh`** — verified at
    refinement time to reference `var/dev.pid` and `var/dev.log` at
    lines 5, 10, 11, 13, 16. Update the contract comment AND the stderr
    error message:
    - `var/dev.pid` → `.zskills/dev-server.pid` (everywhere)
    - `var/dev.log` → `.zskills/dev-server.log` (everywhere)
    - The `mkdir -p .zskills` precondition is needed if no other line
      in the stub creates the directory (today none does — the consumer
      provides `npm run dev > … &`); add a `mkdir -p .zskills` at the
      top of the example contract block in the comment.

  - **`scripts/stop-dev.sh`** (NOT a stub today — it is a generic
    functional implementation per `references/script-ownership.md:51`,
    and full conversion to a failing stub is a separate follow-up plan).
    For path-config purposes: re-derive `grep -n 'var/dev' scripts/stop-dev.sh`
    and swap each `var/dev.pid` reference to `.zskills/dev-server.pid`.
    Do NOT change the script's lifecycle / failing-stub posture — that's
    out of scope.

  - **`skills/update-zskills/references/script-ownership.md`** — line ~51
    (re-derive via `grep -n 'var/dev' .../script-ownership.md`): update
    the `stop-dev.sh` row's note "consumer stack writes PIDs to
    `var/dev.pid`" → "consumer stack writes PIDs to
    `.zskills/dev-server.pid`."

  - **`skills/update-zskills/SKILL.md`** — verified 4 references at
    refinement time (lines 550, 929, 1110, 1119). Re-derive via
    `grep -n 'var/dev' skills/update-zskills/SKILL.md` and rewrite
    each `var/dev.pid` (and `var/dev.log` if present) to
    `.zskills/dev-server.pid` (or `.log`) IN PROSE. Each fence containing
    the literal needs an `<!-- allow-hardcoded: var/dev.pid reason: …
    -->` marker only if it remains; after rewrite, the markers are NOT
    needed because the literal `var/dev.pid` is gone. **AC**:
    `grep -rn 'var/dev\.\(pid\|log\)' skills/update-zskills/`
    returns ZERO hits post-edit.

  Mirror impact: re-run `bash scripts/mirror-skill.sh update-zskills`
  after edits. Files in commit inventory:
  - `skills/update-zskills/stubs/start-dev.sh` (modified)
  - `.claude/skills/update-zskills/stubs/start-dev.sh` (modified, mirror)
  - `scripts/stop-dev.sh` (modified)
  - `skills/update-zskills/references/script-ownership.md` (modified)
  - `.claude/skills/update-zskills/references/script-ownership.md` (modified, mirror)
  - `skills/update-zskills/SKILL.md` (modified)
  - `.claude/skills/update-zskills/SKILL.md` (modified, mirror)

  This work item lands in the same Phase 6 commit as 6.6, 6.7 (docs
  sweep). The migration tool (Phase 5a step 6) and these install
  sources together close the propagation hole — both paths must change
  for the bug to actually close (Phase 5a handles existing consumers;
  6.6.1 handles every future install).

  **AC additions** (folded into Phase 6 §AC):
  - `grep -rn 'var/dev\.\(pid\|log\)' skills/update-zskills/ scripts/stop-dev.sh CLAUDE_TEMPLATE.md README.md`
    returns ZERO hits.
  - `diff -rq skills/update-zskills .claude/skills/update-zskills` clean
    (mirror parity preserved).

- [ ] **6.7 — Update `README.md`.** Re-derive via
  `grep -n 'var/dev\|plans/\|reports/' README.md`. Replace `var/dev.pid`
  → `.zskills/dev-server.pid`. Sweep for any other `plans/`/`reports/`
  mentions in active-context paragraphs.

- [ ] **6.8 — Sweep `docs/` and `references/` directories.** Per Phase 6
  template work item from SCRIPTS_INTO_SKILLS_PLAN. Implementer
  re-derives the grep at run-time, NOT pre-bake (paths have moved by now;
  pre-baked regex would falsely flag `docs/plans/...`):

  ```bash
  # The implementer composes the grep at Phase 6 time. Suggested shape:
  # - look for plans/[A-Z]*.md outside docs/plans/ (token without prefix)
  # - look for reports/(plan|verify|briefing|new-blocks)- outside
  #   .zskills/audit/
  # Skip block-diagram/*/references/ if those dirs don't exist (verified
  # at planning time: ls block-diagram/add-block/ → no references/).
  grep -rEn '(\bplans/[A-Z]|\breports/(plan|verify|briefing|new-blocks)-)' \
    docs/ skills/*/references/ 2>&1 \
    | tee "$TEST_OUT/sweep.txt"
  ```

  For each match in active context, rewrite to the new locations. Mirror
  affected skills.

- [ ] **6.9 — Plan registry: `docs/plans/PLAN_INDEX.md`.** Add a row for
  this plan's post-migration filename following sibling format. Use
  `/plans` to regenerate if available.

- [ ] **6.10 — Plan frontmatter flip.** Edit
  `docs/plans/ZSKILLS_PATH_CONFIG.md`: `status: active` → `status:
  complete`; add `completed: 2026-MM-DD` (date of landing). The agent
  reads from `/tmp/ZSKILLS_PATH_CONFIG.md.preserve` (per 6.1) if needed
  during the brief window between move and the flip.

- [ ] **6.11 — Conformance test final green.** Run
  `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1`.
  ALL suites green, including `test-skill-conformance.sh` (zero
  path-literal hits in `skills/`). Verifier attests.

- [ ] **6.12 — Mirror final pass.**
  ```bash
  for s in $(ls skills); do
    bash scripts/mirror-skill.sh "$s"
  done
  for s in add-block add-example; do
    bash scripts/mirror-skill.sh "block-diagram/$s"
  done
  ```
  Assert `diff -rq skills/ .claude/skills/` clean (excluding the
  `playwright-cli` and `social-seo` install-only entries; excluding
  `model-design` per Locked Decision 13).

- [ ] **6.13 — Final regression grep AC** (closes the cleanup-merge →
  Phase 6 leak window per Locked Decision 12 abandonment policy /
  round-2 reviewer F2):

  ```bash
  # Re-confirm zero viewer URL refs across the FULL repo (round-3 DA F8:
  # tests/ was missing; added). Capture per-line diagnostic to file (per
  # CLAUDE.md test-output rule). The grep regex matches every viewer-URL
  # form removed by the cleanup branch — verify by re-reading the
  # cleanup commits BEFORE running:
  #   git show 85c9c32 88b9a68 | grep -E '^-.*viewer'
  # and confirm each removed line is matched by the regex below.
  grep -rEn 'viewer/?file=|viewer\.html\?file=|view-file=' \
    skills/ block-diagram/ scripts/ hooks/ tests/ docs/ \
    2>/dev/null \
    > "$TEST_OUT/regression-grep.txt" || true
  hits=$(wc -l < "$TEST_OUT/regression-grep.txt")
  if [ "$hits" -gt 0 ]; then
    echo "REGRESSION: $hits viewer URL refs leaked since cleanup-merge" >&2
    cat "$TEST_OUT/regression-grep.txt" >&2
    exit 1
  fi
  ```

  This catches any unrelated commit that may have re-introduced viewer
  URLs between the cleanup-branch merge and Phase 6 dispatch.

  **Note on `allow-hardcoded` filtering** (round-3 DA F9): the
  filter is INTENTIONALLY DROPPED here — viewer URLs are not in
  `forbidden-literals.txt`, so `allow-hardcoded` markers don't apply
  to them today. Any future `allow-hardcoded`-marked viewer URL is
  itself a regression that should land via plan, not be silently
  excluded. If a legitimate exception arises, add a per-hit
  allowlist of file:line pairs HERE (in this work item) at that
  time.

- [ ] **6.14 — Commit.** Subject:
  `feat(paths): self-migrate zskills repo to docs/plans + .zskills/audit`.
  This commit moves ~50+ plan files via `git mv` plus the doc updates.
  Check the diff carefully (`git diff --cached --stat`) — every file
  should be either a rename, a doc update, or a frontmatter flip. No
  surprise content changes.

### Design & Constraints

**Self-migration is a feature-branch operation.** Don't apply
`--migrate-paths` directly to main — go through PR mode. Per
CREATE_WORKTREE_SKILL Phase 3 lesson: self-migration on a non-feature
branch is a hazard class.

**Failure modes to guard:**

1. **Legacy `plans/` left over.** Symptom: `git ls-files plans/` non-empty
   after migration. Cause: `git mv` failed silently. Fix (designed-out):
   per Phase 5a step 3 every move has explicit `if/then/else echo FAIL;
   exit 1`. If still hits: re-run with verification per move; do NOT
   silence errors.
2. **`reports/` accidentally committed somewhere.** Symptom:
   `git ls-files reports/` non-empty. Fix: re-derive via grep, move stray
   files to `.zskills/audit/`.
3. **`.gitignore` order wrong.** Symptom: `.zskills/audit/` content shows
   up in `git status` as untracked AFTER migration. Cause: existing
   pattern conflict (e.g., `!.zskills/audit/`). Fix (designed-out):
   Phase 5a step 7 verifies `git check-ignore -v` post-edit; failure
   surfaces immediately, including positive-include overrides.
4. **CANARY1 fails because `docs/plans/CANARY1_HAPPY.md` not found.**
   Cause: re-derive-post-migration step missed. Fix: re-run with
   resolved-path argument (per 6.2 path-resolution rule).
5. **Dashboard misses migrated paths.** Cause: dashboard server hot-cached
   the old `main_root / "plans"` value. Fix: graceful restart of dashboard
   server. NEVER `kill -9` per CLAUDE.md.
6. **`.pre-paths-migration` overwritten on re-run.** Cause: implementer
   forgot the write-once policy. Phase 5a step 9 + Phase 5a Case 3 catch
   this.
7. **Tracking markers reference moved plan paths.** Pre-checked in 6.1's
   first bash block. If non-empty, surface a BLOCKER (exit 1) — don't
   migrate.
8. **Viewer URL leaked between cleanup-merge and Phase 6.** Caught by
   6.13's repo-wide regression grep.
9. **Canary fails mid-Phase-6.** Per 6.2 canary-failure remediation:
   diagnose, then fix-forward (NOT amend) OR clean revert (NOT manual
   undo).

**Canaries gate the PR.** CI runs `tests/run-all.sh` and the auto
canaries. Manual canaries (CANARY8, CANARY9, CANARY10) are noted in the
PR body as "manually verified on <date>" with evidence link to the
verifier report.

**Build-prod helper presence (per DA finding 17).** Phase 6 verifies
`scripts/build-prod.sh` produces an artifact that includes BOTH
`skills/update-zskills/scripts/zskills-paths.sh` AND
`.claude/skills/update-zskills/scripts/zskills-paths.sh`. The helper
must NOT be classified dev-only.

### Acceptance Criteria

- [ ] `git ls-files | grep -E '^(plans|reports|var)/'` returns empty.
- [ ] `git ls-files | grep -E '^docs/plans/'` returns ~50+ entries.
- [ ] `.zskills/audit/` exists, populated, gitignored. `git check-ignore
  -v .zskills/audit/dummy` exits 0 with the matching pattern (verbose
  inspection rejects positive-include overrides).
- [ ] `.pre-paths-migration` exists, is tab-separated, lists every move.
- [ ] CANARY1, CANARY6, CANARY7 PASS via `/run-plan` (auto-dispatched
  with the post-migration path per 6.2 path-resolution rule). Each
  canary's evidence includes the dispatching session ID.
- [ ] CANARY8, CANARY9, CANARY10 PASS via MANUAL run per their canary
  plans' own runbooks. Evidence includes the user session(s) per each
  canary's manual-canary contract (CANARY8: two simultaneous Claude
  Code session IDs; CANARY9: cron-fired turn timestamps; CANARY10:
  GitHub PR/CI/merge state references).
- [ ] `CHANGELOG.md` contains the new entry.
- [ ] `CLAUDE_TEMPLATE.md`, `README.md` updated.
- [ ] `bash scripts/build-prod.sh` artifact tree contains
  `skills/update-zskills/scripts/zskills-paths.sh` and
  `.claude/skills/update-zskills/scripts/zskills-paths.sh`.
- [ ] `tests/run-all.sh` green — ALL suites including conformance.
- [ ] `diff -rq skills/ .claude/skills/` clean (modulo install-only
  `playwright-cli`, `social-seo`; modulo `model-design` per Locked
  Decision 13).
- [ ] Plan frontmatter flipped to `status: complete` with `completed:`.
- [ ] **6.13 final regression grep:** zero `viewer/?file=` refs across
  the full repo (defense-in-depth catches post-cleanup leaks).
- [ ] One commit (the migration squash).

### Dependencies

Phases 1, 1.5, 2a, 2b, 3, 4, 5a, 5b all complete. Locked Decision 12
prerequisite (cleanup branch merged OR user-picked abandonment-policy
path) verified at Phase 4.

---

## Plan Quality

**Drafting process:** /draft-plan with 3 rounds of adversarial review (reviewer + devil's advocate parallel agents per round, then refiner with verify-before-fix discipline).

**Convergence:** Converged at round 3. Findings trajectory: round 1 → round 2 → round 3 = 47 → 40 → 25 substantive findings. P0 trajectory: 6 → 5 → 1 → 0 (post-round-3 refinement). All P0 and P1 findings addressed through three rounds.

**Remaining concerns (non-blocking):**

1. **Decimal phase numbering precedent partly false.** Round-3 reviewer (R3) flagged that `Phase 1.5` decimal numbering may not be parseable by `/run-plan`. The round-3 refiner Justified-not-fixed citing precedent in `run-plan/SKILL.md`, `IMPROVE_STALENESS_DETECTION.md`, and `SKILL_VERSIONING.md`. Orchestrator verification: only `run-plan/SKILL.md` and `do/SKILL.md` have `Phase X.Y` style — both are skill source documentation, NOT `/run-plan`-executable plans. Zero precedent in `plans/*.md`. Risk: low. Mitigation: if `/run-plan` rejects `1.5` at dispatch time, rename to `Phase 1b` (mechanical, ~10 occurrence find-replace across the plan).

2. **Single Justified-not-fixed: round-1 R7 (viewer-URL site enumeration).** Superseded by Locked Decision 12's prerequisite reframing — the cleanup branch (`cleanup/remove-zimulink-viewer-refs`, commits `85c9c32` + `88b9a68`) handles all viewer-URL removal; verified clean by orchestrator (`grep -rn 'viewer/?file' /tmp/zskills-cleanup-zimulink-viewer-refs/skills` returns 0). Acceptable disposition.

3. **Phase 1.5 `mirror-skill.sh` extension is in the same Phase 1.5 commit as the repo-wide audit + build-prod.sh glob fix + audit-row table authoring + script-ownership update.** Not single-purpose. If any sub-step fails verification, all four roll back. Defensible because the four sub-steps are tightly coupled (the audit drives Phase 2a/2b/3/4 work; the mirror-script extension drives block-diagram migration; the glob fix is one-char surface-bugs-don't-patch). Reviewer may want this split if executing under high-risk conditions.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1 | 25 (3 P0, 9 P1, 13 P2) | 22 (3 P0, 8 P1, 11 P2) | 43 Fixed, 4 Justified-not-fixed |
| 2 | 20 (2 P0, 7 P1, 11 P2) | 20 (3 P0, 6 P1, 11 P2) | 33 Fixed, 7 Justified-not-fixed (incl. 1 verified-false-premise) |
| 3 | 5 (1 P0, 4 P1) | 20 (0 P0, 7 P1, 13 P2) | 23 Fixed, 1 Justified-not-fixed (verified premise check), 1 verified-false-premise (decimal numbering — see Remaining Concerns #1) |

**Plan size growth:** 1,464 → 2,154 → 2,811 → 3,343 lines across drafting + 3 refinement rounds. Growth was load-bearing: each refinement added concrete bash, exact regex literals, frontmatter decision trees, audit-row schemas, and verification idioms that closed specification gaps. Per project memory ("Plan FILE vs plan PROMPT vs plan SUMMARY: concise applies to prompts and summaries, NOT plan files; plan files are specs for the implementing agent").

**Cleanup-branch prerequisite:** The cleanup branch `cleanup/remove-zimulink-viewer-refs` (commits `85c9c32` + `88b9a68`) must merge to main before Phase 4 begins. Phase 4.0 verifies and gates. See Locked Decision 12 for the full abandonment-policy decision tree.
