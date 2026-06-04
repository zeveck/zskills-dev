---
title: Entirely Remove the /quickfix Skill
created: 2026-06-03
status: complete
---

# Plan: Entirely Remove the /quickfix Skill

## Overview

Remove `/quickfix` from zskills completely: the skill directory (source +
mirror), its dedicated test suite, its catalog/doc pages, every cross-skill
prose/script reference, every conformance assertion that pins it, and all
user-facing counts that include it. End state: `grep -rin quickfix` over the
**live** tree (excluding the historical `docs/plans/`, `docs/reports/`,
`docs/issues/`, `CHANGELOG.md`) returns zero hits, and `bash tests/run-all.sh`
passes clean.

**Decision already settled (do not relitigate):** the "PR-without-a-worktree"
capability is dropped entirely; `/do` remains the one-commit-PR path. This is a
wide-but-mechanical, fully test-gated change — every omission surfaces as a red
suite, so correctness is enforced by CI, not by hoping the sweep was complete.

**Why these phases, in this order.** A removal has an unavoidable property: the
test suite cannot be green with the skill deleted while assertions still
reference it. But *removing an assertion is always safe*, and *deleting a test
that references a still-present skill is always safe*. So the suite stays green
between every phase if and only if we **de-reference the test layer first
(Phase 1), then delete the skill (Phase 2)**, then do prose/script/docs
(Phases 3–5) which never touch test-pass state except via the two gated
regenerations (managed.md, DocsRegistry.js), each performed within its phase.
Every phase ends on a green `bash tests/run-all.sh`.

**Execution context.** `main_protected: true` — run via `/run-plan
plans/QUICKFIX_REMOVAL_PLAN.md` (worktree mode), never `/quickfix` (which is
being deleted) and never direct-to-main.

## Critical invariants every phase must honor

1. **Render discipline.** Never hand-edit `.claude/rules/zskills/managed.md`.
   Edit `CLAUDE_TEMPLATE.md`, then regenerate via `/update-zskills --rerender`
   (canonical renderer `scripts/render-managed-rules.py`). `tests/test-managed-md-up-to-date.sh`
   diffs template-render vs checked-in managed.md — drift = FAIL.
2. **DocsRegistry regen.** Never hand-edit `docs/DocsRegistry.js`. After
   deleting `docs/skills/quickfix.md`, run `bash scripts/build-catalog.sh` and
   commit the regenerated registry. `tests/test-doc-viewer-catalog.sh` byte-diffs
   committed vs fresh — stale entry = FAIL.
3. **Source↔mirror parity.** Every file under `skills/` has an identical twin
   under `.claude/skills/`; every file under `hooks/` a twin under `.claude/hooks/`.
   EDIT BOTH. Pairs in this plan: `collect.py`, `briefing.py`, `clear-tracking.sh`,
   `block-main-edits.sh`, `block-bypassed-land-pr.sh`. SINGLE copy (no mirror):
   `scripts/land-pr-bypass-message.sh`.
4. **Skill-versioning gate (quadruple-enforced: warn-config-drift,
   /commit 2.5, block-stale-skill-version hook, conformance).** Any edited
   `skills/<name>/SKILL.md` OR any regular file under a skill dir
   (modes/references/scripts) requires a `metadata.version` bump: date →
   `2026.06.03` (America/New_York), hash recomputed via
   `scripts/skill-content-hash.sh`. Bump in source AND mirror (same value).
5. **Capture test output out-of-tree.** `TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"; mkdir -p "$TEST_OUT"; bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` then read the file. Never pipe.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — De-reference the test/conformance layer | ✅ | 4856595 | run-all.sh 7395/7395 passed, 0 failed; grep -rin quickfix tests/ = 0 hits |
| 2 — Delete the skill + catalog/doc pages | ✅ | 0eb0d05 | skill+mirror+catalog deleted; DocsRegistry regen (no drift); count-pinned assertions corrected 25→24 (CLAUDE.md core count, version-delta REAL_LINES/CORE_COUNT floors); run-all 7390/7390 passed, 0 failed |
| 3 — Cross-skill prose, scripts, hooks (+ version bumps + mirrors) | ✅ | (HEAD of branch) | All /quickfix refs removed from skill prose/scripts/hooks/agent-def in source+mirror; 13 skills version-bumped (land-pr, do, commit, run-plan, work-on-plans, session-report, cleanup-merged, draft-plan, draft-tests, refine-plan, update-zskills, briefing, zskills-dashboard); grep -rin quickfix over skills/.claude/skills/.claude/agents/hooks/.claude/hooks/scripts = 0 hits; run-all 7390/7390 passed, 0 failed (post-commit) |
| 4 — CLAUDE_TEMPLATE.md + re-render managed.md + CLAUDE.md | ✅ | (HEAD of branch) | quickfix removed from CLAUDE_TEMPLATE.md (impl-dispatch, land-pr 5→4, user-invocable 8→7/7→6, decision-table row, PEERS-not-TIERS bullet, draft-plan/investigate bullets retargeted to /do, exec-modes example, --force list) + CLAUDE.md L123 prose; managed.md re-rendered via scripts/render-managed-rules.py (drift test green); grep -n quickfix on all 3 = 0 hits |
| 5 — Public docs + skill/caller counts | ✅ | (HEAD of branch) | quickfix removed from README.md, PRESENTATION.html, docs/skills/ (README + 10 reference pages), docs/guides/ (workflows/installing-zskills/inspecting-and-monitoring), config/zskills-config.schema.json, references/skill-description-budget.md, reports/TECHNICAL.html; counts corrected (skills 25→24, user-facing 23→22, land-pr callers 5→4/8→7, TECHNICAL 28→27 / 25→24 source / 15+10→14+10); DocsRegistry regen = no drift; grep -rin quickfix over all target files = 0 hits; run-all 7390/7390 passed, 0 failed |
| 6 — Full-suite verification + zero-reference sweep | ✅ | (HEAD of branch) | Independent verifier flagged 5 stale count literals the count phases missed (no test pinned them): `25 core` in skills/.claude mirror update-zskills SKILL.md → `24 core` (+ metadata.version bump 2026.06.03+ec2689 on both); `23 user-facing` ×2 in docs/README.md + ×1 in docs/guides/README.md → `22 user-facing`. test-skill-conformance "5 caller copies" inspected = already-correct (Phase 1 did 6→5), left as-is. Stale-count greps (`25 core`/`25 skills`, `23 user-facing`) clean modulo plan/historical files; run-all 7390/7390 passed, 0 failed |

---

## Phase 1 — De-reference the test/conformance layer

### Goal
Remove every quickfix reference from the test suite while the skill still
exists, so the suite is green both now and after the Phase 2 deletion.

### Work Items
- [ ] **Delete `tests/test-quickfix.sh`** (2423 lines) and **remove its
  registration** at `tests/run-all.sh:101` (`run_suite "test-quickfix.sh"
  "tests/test-quickfix.sh"`).
- [ ] **`tests/test-skill-conformance.sh` — surgical removals** (verify each
  line by content, not blind line number — the file may have shifted):
  - §A auto-grammar: remove the quickfix lines (≈L599, L607–616, L643–647);
    KEEP the `do`/`work-on-plans`/`cleanup-merged`/`run-plan`/`fix-issues`
    assertions (≈L626–641). Reword the comment (≈L619) to drop `/quickfix`
    while keeping `/cleanup-merged`.
  - §B behavior-contracts block (`=== /quickfix — behavior contracts ===`,
    ≈L655–669): delete whole block.
  - §C issue-claim-wiring block (`=== /quickfix — issue-claim wiring ===`,
    ≈L671–684): delete whole block.
  - §D implementer-pins: delete the two `check_in_file_near quickfix
    modes/execute.md|modes/land.md` (≈L774–775) + their comment; KEEP the
    other-skill pins above.
  - §E `LAND_PR_CALLERS` array: remove the `"skills/quickfix/modes/land.md"`
    entry (≈L969). Rewrite the two `pass "... all 8 callers ..."` strings
    (≈L985, L1023) → `7 callers`.
  - §F `LANDPR_MARKER_BASENAME`: remove `["skills/quickfix/modes/land.md"]=...`
    (≈L1049).
  - §G `ALL_CALLERS`: remove the entry (≈L1070) AND remove the quickfix
    special-case `if` branch (≈L1123–1133) and its now-dead comment (≈L1112–1119).
  - §H `FENCE_CALLERS`: remove the entry (≈L1171); trim stale comments
    (≈L1163, L1194–1198).
  - §I fulfilled.quickfix byte-anchor block (≈L1223–1230): delete (reads a
    deleted file).
  - §J STATUS case-arm loop: remove `"quickfix modes/land.md"` from the pair
    list (≈L1578) + comment (≈L1572–1573); KEEP commit/do/fix-issues/run-plan/land-pr.
  - §K #682 PEERS-not-TIERS propagation-prose (≈L3006–3027): REMOVE the two
    positive-pin assertions — the one pinning `They are PEERS, not TIERS` and
    the one pinning `Pick by **project policy, not task size**` (both pin prose
    deleted in Phase 4) — plus the negative-pin assertion for `larger than
    /quickfix` (stays green but meaningless; remove for hygiene) and the
    block comment.
  - §A also: rename/scrub the `QUICKFIX_GRAMMAR_REDESIGN` echo header (≈L597
    `echo "=== auto grammar (QUICKFIX_GRAMMAR_REDESIGN Phase 2) ==="`) and the
    comment (≈L601) — case-insensitive `QUICKFIX` would otherwise be a Phase-6
    sweep hit.
  - **Count-prose honesty:** RE-DERIVE (do not blind-decrement) every caller
    -count string in this file after removal — `≈L954` "8 callers (5 impl + 3
    drafting)", `L985`/`L1023` "all 8 callers", `L1057`, `L1064` "all 4
    callers", `L1194`, `L1559` "the 5 caller skills". Each names a DIFFERENT
    subset (all-callers vs impl-only vs non-/run-plan vs --no-monitor set), so
    recount each from its actual referent, not by subtracting one.
- [ ] **`tests/test-skill-invariants.sh`**: remove the `ISSUE_606_PAIRS` entry
  `"skills/quickfix/SKILL.md|ZSKILLS_PIPELINE_ID"` (≈L92); trim comment (≈L80).
- [ ] **`tests/test-block-main-edits.sh` (C18b, ≈L239–257):** the assertion
  tests a property (hook message must not bare-recommend `/quickfix`) of a
  feature being removed. **Delete the C18b assertion block entirely** (its
  `[[ "$HOOK_OUT" != *'/quickfix'* ]]` live code is itself a sweep hit). Keep
  C18a (`/do pr`). Removing an assertion is always green; the Phase-3 hook edit
  then has no test to satisfy.
- [ ] **Fixture swaps (behavior-preserving):** in
  `tests/test-issues-skip-reason-parse.sh` (≈L99,101,113,247) and
  `tests/test-fix-issues-dashboard.sh` (≈L275), replace the `/quickfix` literal
  with `/do`. Both are "unrecognized skip-route → actionable-null (None)"
  fixtures; `/do` is equally unrecognized by `_parse_action_now` (which only
  branches `/draft-plan`/`/run-plan`/`/investigate`), so the expected result is
  unchanged. **Verify** the expected-output assertions still pass after the swap.
- [ ] **`tests/test-do.sh` comment scrub:** reword the ~10 `/quickfix`
  symmetry comments, and FIX the two dangling references to the now-deleted
  file `tests/test-quickfix.sh` at ≈L32 and ≈L258 (retarget to an existing
  test or drop the reference). Comments only — no logic.
- [ ] **`tests/test-do-quickfix-multi-issue-fanout.sh` — rename (MANDATORY,
  not optional):** `git mv` → `tests/test-do-multi-issue-fanout.sh`; strip the
  quickfix mentions in its header comments and change the
  `PIPELINE_ID="quickfix.test-release"` label to `do.test-release`. It is not
  registered in `run-all.sh`; leave it unregistered (note it) OR wire it in —
  decide and record. (It drives `claim-issue.sh` directly; no skill dependency.)
- [ ] **Do NOT touch** (verified no-edit, but list so the implementer doesn't
  "fix" them): #976 user-invocable check (schema-driven, ≈L3692–3728); the
  dynamic per-skill frontmatter/hash/mirror loops; `tests/test-doc-viewer-catalog.sh`
  count-range (stays in 25..50); `test-skill-frontmatter-survival.sh` (dynamic glob).

### Design & Constraints
- The conformance helpers `check`/`check_fixed`/`check_in_file*` fail-on-absence
  (`grep -r "$skill_dir/"` non-zero, or explicit `[ ! -f ] → fail`). That is
  WHY every positive quickfix assertion must be physically removed, not merely
  expected-to-pass-vacuously.
- The `pass "... all N callers ..."` strings are prose-only (not numeric
  comparisons), so a stale count won't fail the run — but rewrite them anyway
  for honesty; a reviewer will flag `8` against a 7-entry array.
- This phase does NOT yet edit `CLAUDE_TEMPLATE.md` — but it removes the §K
  assertions that pin that template's prose. Ordering rationale: §K assertions
  pinning *deleted-in-Phase-4* prose must go no later than Phase 4; removing
  them in Phase 1 is safe (removing an assertion never fails) and keeps Phase 4
  a pure template edit + re-render.

### Acceptance Criteria
- [ ] `grep -rin quickfix tests/` returns **zero hits** (case-insensitive —
  catches `QUICKFIX_GRAMMAR_REDESIGN`). The whole test layer is quickfix-free,
  including the renamed fanout file.
- [ ] `bash tests/run-all.sh` passes (skill still present; suite no longer
  references it). State the exact command + per-suite results.

### Dependencies
None — first phase.

---

## Phase 2 — Delete the skill + catalog/doc pages

### Goal
Physically remove the skill, its mirror, and its live catalog/doc entries;
regenerate the doc registry so the drift gate passes.

### Work Items
- [ ] `git rm -r skills/quickfix/ .claude/skills/quickfix/` (both trees;
  mirror-parity requires deleting together).
- [ ] `git rm docs/skills/quickfix.md`.
- [ ] `git rm docs/reports/doc-rewrite-evidence/factsheet-quickfix.md` (live
  factsheet for the skill; safe to drop).
- [ ] Regenerate the doc registry: `bash scripts/build-catalog.sh`, then stage
  the regenerated `docs/DocsRegistry.js` (the `{ name: "/quickfix" ... }` entry
  at ≈L49 must disappear via regen, NOT hand-edit). **If `scripts/build-catalog.sh`
  is not the generator, locate the actual generator (read `tests/test-doc-viewer-catalog.sh`
  for the command it invokes) and use that.**
- [ ] **Count-pinned assertions broken by the deletion (added during execution
  — the live skill count drops 25→24 the moment the skill dir is removed):**
  these pin a count that *includes* the removed skill, so they must be
  corrected here, with the deletion. Honest expected-value corrections, NOT
  weakening:
  - `CLAUDE.md:9` `(25 core)` → `(24 core)` (the dynamic
    `test-skill-invariants.sh` check compares this literal to `ls -d skills/*/`;
    this is the one CLAUDE.md edit pulled forward from Phase 4 — the L123
    `/quickfix` prose mention still lands in Phase 4).
  - `tests/test-skill-version-delta.sh`: floor `REAL_LINES -ge 28` → `-ge 27`
    (24 core + 3 addon) and `CORE_COUNT -ge 25` → `-ge 24`; update both
    derivation comments ("25 core + 3 addon = 28" → "24 core + 3 addon = 27").

### Design & Constraints
- `tests/test-doc-viewer-catalog.sh` byte-diffs committed `DocsRegistry.js`
  against a fresh generation — so the regen output MUST be committed in this
  same phase or the suite goes red.
- The catalog entry-count range is `25..50`; removing one entry stays in range.
- The Internal-Skills membership check is hardcoded to `land-pr manual-testing`
  — unaffected.

### Acceptance Criteria
- [ ] `skills/quickfix`, `.claude/skills/quickfix`, `docs/skills/quickfix.md`
  no longer exist (`test ! -e`).
- [ ] `docs/DocsRegistry.js` contains no `quickfix` entry and matches a fresh
  `build-catalog.sh` run (no drift).
- [ ] `bash tests/run-all.sh` passes. State command + per-suite results.

### Dependencies
Phase 1 (test layer must no longer reference the skill before it is deleted).

---

## Phase 3 — Cross-skill prose, scripts, hooks (+ version bumps + mirrors)

### Goal
Remove every quickfix mention from other skills' bodies, their scripts, and the
hooks — in both source and mirror — bumping each affected skill's version.

### Work Items
- [ ] **land-pr** (`skills/land-pr/`): SKILL.md — frontmatter `description`
  (drop `/quickfix,`), the "Eight callers / five implementation callers" prose
  (→ "Seven callers / four implementation callers", drop `/quickfix`), the
  "other 7 caller skills" list (→ "other 6", drop `/quickfix`), the
  bash-regex-idiom mention (re-anchor to `/do` or `/commit`), the `source:`
  schema enum comment (drop `quickfix,`). **Derived counts** (recount, don't
  blind-decrement — each is a different subset): `≈L61` "the other 4 callers do
  not" (impl-minus-/run-plan: 4→3), `≈L355` "None of the 5 callers in this
  plan" (4), `≈L1108` "The 4 non-/run-plan callers" (3). Also
  `references/caller-loop-pattern.md` (drop `/quickfix`);
  `references/fix-cycle-agent-prompt-template.md` (drop the two `/quickfix`
  mentions, including the trailing sentence).
- [ ] **do** (`skills/do/`): SKILL.md (5 peer/`auto`-mirror/symmetry mentions)
  + `modes/pr.md` (5 mentions). The `skills/quickfix/SKILL.md:672` citation at
  `≈L445` is **already stale on main** (line 672 is the review-VERDICT idiom,
  not the pipeline-id idiom it claims). Fix = **drop the cross-skill
  parenthetical citation entirely**; the idiom is self-contained in this file's
  own `echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"` line and the surviving
  conformance anchor `tests/test-skill-conformance.sh:1050`. Do NOT chase a
  quickfix line number.
- [ ] **commit** (`skills/commit/modes/pr.md`): 3 mentions, incl. the same
  stale `skills/quickfix/SKILL.md:672` citation at `≈L96` — apply the identical
  fix (drop the cross-skill citation; reference the local echo + `:1050`).
- [ ] **agent definition** — `.claude/agents/implementer.md:3`: drop
  `/quickfix,` from the `description:` caller list. NOT a skill (no
  `metadata.version` bump) and has NO mirror, but it IS a live source-of-truth
  file materialised to consumers via `hooks/session-start-materialise.sh`, so
  it must be clean for the zero-hit goal. (`.claude/agents/verifier.md` has no
  quickfix reference — confirmed; leave it.)
- [ ] **run-plan** (`modes/pr.md`): caller-list comment.
- [ ] **work-on-plans** (`modes/execute.md`): the "byte-for-byte equality WITH
  /quickfix" assertion — **re-anchor to `/do`** (do not leave a comparison to a
  deleted skill).
- [ ] **session-report** (SKILL.md): swap the `/quickfix` example to `/do`.
- [ ] **cleanup-merged** (SKILL.md): 3 mentions.
- [ ] **draft-plan** (SKILL.md L128), **draft-tests** (SKILL.md L148),
  **refine-plan** (SKILL.md L140): drop `/quickfix` from the `auto`-token /
  lighter-alternative lists.
- [ ] **update-zskills** (SKILL.md L560, L821): drop `/quickfix` from the
  downstream-consumer + sanitize-pipeline-id lists.
- [ ] **Scripts (edit source + mirror):**
  - `zskills-dashboard/.../collect.py` (≈L2074, L2190 docstrings; ≈L2139
    example) — comment-only; `/quickfix` is NOT a functional triage route
    (`_parse_action_now` only branches `/draft-plan` + `/investigate`).
  - `briefing/scripts/briefing.py` (≈L1936, L1956, L2053) — remove the 3
    `'quickfix'` canonicalization-map entries (inert after removal).
  - `update-zskills/scripts/clear-tracking.sh` (≈L49, L105, L139) — drop
    `|fulfilled.quickfix.*` from both case patterns and `,quickfix` from the
    printf summary.
- [ ] **Hooks (edit source + mirror):**
  - `hooks/block-main-edits.sh` (≈L160–165): delete the `/quickfix`-is-not-a-
    valid-alternative carve-out paragraph. (`tests/test-block-main-edits.sh`
    C18b stays green via its absent-OR branch; update the C18 comment to drop
    the quickfix rationale.)
  - `hooks/block-bypassed-land-pr.sh` (≈L377): drop ` / /quickfix`.
  - `scripts/land-pr-bypass-message.sh` (≈L50 delete line, L67 drop
    `, /quickfix`) — SINGLE copy, no mirror.
- [ ] **Version bumps** for every skill whose dir had a file edited: land-pr,
  do, commit, run-plan, work-on-plans, session-report, cleanup-merged,
  draft-plan, draft-tests, refine-plan, update-zskills, briefing,
  zskills-dashboard. Bump `metadata.version` (date `2026.06.03` + recomputed
  hash) in source AND mirror SKILL.md.

### Design & Constraints
- Use `scripts/skill-content-hash.sh` + `scripts/frontmatter-set.sh
  <skill>/SKILL.md metadata.version "<date>+<hash>"` for each bump. The
  `block-stale-skill-version.sh` PreToolUse hook will DENY the commit on any
  un-bumped edited skill — recover by running the suggested bump command from
  the deny message, then re-stage.
- collect.py / briefing.py / clear-tracking.sh live under skill dirs, so their
  owning skills (`zskills-dashboard`, `briefing`, `update-zskills`) bump even
  though only a script changed ("any regular file under the skill directory").
- Hooks are NOT skills — editing `block-main-edits.sh` etc. needs no version
  bump, but DOES need the mirror updated.

### Acceptance Criteria
- [ ] `grep -rin quickfix skills/ .claude/skills/ .claude/agents/ hooks/ .claude/hooks/ scripts/`
  returns zero hits.
- [ ] Every edited skill's source and mirror SKILL.md carry the new
  `metadata.version`, and source == mirror.
- [ ] `bash tests/run-all.sh` passes (incl. mirror-parity + skill-version
  conformance). State command + per-suite results.

### Dependencies
Phase 1 (conformance arrays no longer pin quickfix as a land-pr caller, so
editing land-pr prose won't desync an assertion). Phase 2 (skill gone, so its
own files aren't in the grep set).

---

## Phase 4 — CLAUDE_TEMPLATE.md + re-render managed.md + CLAUDE.md

### Goal
Remove quickfix from the always-loaded agent instructions and regenerate the
rendered copy through the gated renderer.

### Work Items
- [ ] **`CLAUDE_TEMPLATE.md`** (edit the TEMPLATE only):
  - L18 impl-agent dispatch: drop `, and \`/quickfix\`'s agent-dispatched mode`.
  - L233 land-pr rule: drop `/quickfix` from the caller list; `5 callers` /
    `5 caller skills` → `4`.
  - L288 user-invocable rule: drop `/quickfix` from both lists; `8 caller
    skills` → `7`, `other 7 callers` → `6`.
  - L307 decision-table row (`One-commit PR — edit in-place ... | /quickfix`):
    delete the entire row.
  - L323 `/quickfix` vs `/do` PEERS-not-TIERS bullet: delete the entire bullet.
  - L326 `/draft-plan` vs `/do`/`/quickfix` bullet: keep the bullet, remove the
    `/quickfix` references (→ `/draft-plan vs /do`; the "/do or /quickfix
    co-equal peers" clause → `/do`).
  - L327 `/investigate` vs `/quickfix` bullet: retarget to `/do` (`/investigate
    vs /do`; "may dispatch /quickfix or /do" → "may dispatch /do").
  - L344 Execution-Modes `/quickfix Fix README typo --force` example: delete.
  - L349 flag-convention `--force` list: drop `, \`/quickfix\``.
- [ ] **Re-render:** `/update-zskills --rerender` (or run
  `scripts/render-managed-rules.py`), then `git add .claude/rules/zskills/managed.md`.
- [ ] **`CLAUDE.md`** (repo-root, NOT the template): L123 impl-agent dispatch
  (drop the `/quickfix` mention); L9 `(25 core)` → `(24 core)`.

### Design & Constraints
- `.claude/rules/zskills/managed.md` MUST come from the renderer, never a hand
  edit — `tests/test-managed-md-up-to-date.sh` will fail on any drift between
  template-render and the checked-in file.
- The §K conformance assertions that pinned L323/L326 prose were already removed
  in Phase 1, so this phase's prose deletion won't trip them.
- Confirm `/update-zskills --rerender` is the live regen path (read
  `tests/test-managed-md-up-to-date.sh` header for the exact remediation
  command); fall back to invoking `scripts/render-managed-rules.py` directly if
  the slash path isn't available in the execution context.

### Acceptance Criteria
- [ ] `grep -n quickfix CLAUDE_TEMPLATE.md .claude/rules/zskills/managed.md CLAUDE.md`
  returns zero hits.
- [ ] managed.md is byte-identical to a fresh template render
  (`test-managed-md-up-to-date.sh` green).
- [ ] `bash tests/run-all.sh` passes. State command + per-suite results.

### Dependencies
Phase 1 (§K assertions removed). Independent of Phases 2–3 otherwise, but
sequence after 3 to keep the running grep-sweep monotonic.

---

## Phase 5 — Public docs + skill/caller counts

### Goal
Remove quickfix from human-facing docs and correct every skill/caller count.

### Work Items
- [ ] **README.md:** L16 `25`→`24`; L17–18 + L39 + L435 `23 user-facing`→`22`;
  L501 `core 25`→`24`; L461 delete the `/quickfix` build-table row; L495 drop
  `/quickfix` from the land-pr caller list; L67 swap the `/zs:quickfix` /
  `/quickfix` prefix EXAMPLE to a surviving skill (e.g. `/zs:do` / `/do`).
- [ ] **PRESENTATION.html:** L269 `25 Skills`→`24`; L284 `25`→`24` + `23`→`22`;
  L285 `23`→`22`; L289 comment `25`→`24`; L710 `25`→`24` + `23`→`22`; L336–339
  delete the `/quickfix` skill-card `<div>`; L410 drop `/quickfix` from the
  land-pr card caller list.
- [ ] **docs/skills/README.md:** L3 `23`→`22`; L27 + L61 delete the `/quickfix`
  rows.
- [ ] **docs/skills/*.md reference pages:** edit land-pr.md, do.md (substantive
  peer prose), investigate.md, cleanup-merged.md, session-report.md,
  draft-plan.md, draft-tests.md, update-zskills.md, refine-plan.md, commit.md —
  drop `/quickfix` from caller lists / retarget comparison prose to `/do`.
- [ ] **docs/guides/:** workflows.md (substantive — remove the co-equal-peer
  framing at L10, L37, the `/quickfix` code line L52–56, the two peers-not-tiers
  bullets L58–63, and the `/investigate` recipe alt L162/L167–168);
  installing-zskills.md (L118/119/124/125 — swap the `/zs:` example skill to a
  survivor); inspecting-and-monitoring.md (L140 marker keep-list).
- [ ] **config/zskills-config.schema.json:** L77 co-author description — drop
  `/quickfix and `.
- [ ] **references/skill-description-budget.md:** L65/67 delete the `/quickfix`
  budget bullet; L92 drop `and /quickfix`.
- [ ] **reports/TECHNICAL.html** (top-level `reports/`, NOT `docs/reports/` —
  3 hits at ≈L175, L218, L238; hand-authored, no generator). **Decision: edit
  it** — remove the `/quickfix` table row (≈L218) and the two other mentions,
  and correct the count at ≈L175 ("28 SKILL.md bodies (25 source + 3 add-ons)"
  → "27 … (24 source + 3 add-ons)"). First confirm no generator exists
  (`grep -rln TECHNICAL.html scripts/`); if one is found, regen instead of
  hand-editing.

### Design & Constraints
- These files are not skills; no version bumps. `docs/skills/*.md` are
  doc-viewer source — confirm whether editing them requires a
  `build-catalog.sh` re-run (the registry references paths, not bodies; body
  edits likely don't change the registry, but re-run + check for drift to be
  safe since Phase 2 already established the gate).
- Counts must stay internally consistent: skills 25→24, user-facing 23→22,
  helpers stay 2; land-pr callers 8→7 / 5→4 / "other 7"→6.

### Acceptance Criteria
- [ ] `grep -rin quickfix README.md PRESENTATION.html docs/skills/ docs/guides/
  config/ references/ reports/TECHNICAL.html` returns zero hits.
- [ ] No remaining `25` skill-count or `23 user-facing` literal anywhere live;
  land-pr caller counts read 7/4/6 consistently.
- [ ] `bash tests/run-all.sh` passes (incl. doc-viewer-catalog drift gate).
  State command + per-suite results.

### Dependencies
Phase 2 (DocsRegistry already regenerated; doc-page deletions consistent).

---

## Phase 6 — Full-suite verification + zero-reference sweep

### Goal
Prove the removal is complete and the suite is green, with historical archives
explicitly excluded.

### Work Items
- [ ] Run the FULL suite: `TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")";
  mkdir -p "$TEST_OUT"; bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1`;
  read the file; confirm every suite passes (match the explicit pass COUNT, not
  just "0 failed").
- [ ] **Zero-reference sweep over the LIVE tree:**
  `grep -rin quickfix . --exclude-dir=.git --exclude-dir=plans
  --exclude-dir=docs/plans --exclude-dir=docs/reports --exclude-dir=docs/issues
  --exclude=CHANGELOG.md --exclude=.pre-paths-migration` → **expected: ZERO
  hits.** (`plans/` is excluded because THIS plan file legitimately names
  quickfix; on completion it relocates to `docs/plans/` per repo convention.)
  `tests/` and
  top-level `reports/` are NOT excluded (they were scrubbed in Phases 1 and 5),
  so any hit here is a real miss to fix. The fanout-test rename (Phase 1) and
  the `reports/TECHNICAL.html` edit (Phase 5) are what make this literally zero.

### Design & Constraints
- The historical exclusions are deliberate: `docs/plans/` (517 hits across 20
  files), `docs/reports/` (~30 files), `CHANGELOG.md` (3 hits) document past
  work and must NOT be scrubbed (rewriting history erases the record of what
  `/quickfix` was).

### Acceptance Criteria
- [ ] Full `bash tests/run-all.sh` green — report the command and EACH suite's
  result with pass counts; name any suite skipped and why.
- [ ] Live-tree `quickfix` grep returns zero (modulo the documented optional
  test-file label).
- [ ] A short final report listing: files deleted, files edited (by category),
  counts changed, and the historical surfaces deliberately left untouched.

### Dependencies
All prior phases.

## Plan Quality

**Drafting process:** /draft-plan — 3 parallel research agents (footprint /
conformance / prose), 1 draft, 1 reviewer + 1 devil's-advocate adversarial
round, refine with verify-before-fix, then an independent whole-live-tree
completeness sweep.
**Convergence:** Converged after round 1 + a completeness-sweep confirmation,
then a final independent-verifier pass during Phase 6. Every round-1 finding was
reproduced and fixed (or justified); the post-refine whole-tree grep found no
missed file category and only a trivial plan-file self-reference (fixed in the
Phase 6 sweep exclusions). The Phase 6 verifier caught 5 stale count literals
the count-correction phases had missed — `25 core` in `skills/update-zskills/SKILL.md`
+ its mirror, and `23 user-facing` in `docs/README.md` (×2) and
`docs/guides/README.md` — none of which were pinned by a test (so the suite was
green while the prose was wrong). These were corrected to `24 core` / `22 user-facing`
(quickfix was both a core and a user-facing skill, so both counts drop by one),
with the corresponding `metadata.version` bump on `update-zskills`. The verifier's
flag on `tests/test-skill-conformance.sh` "5 caller copies" was inspected and
found to be a false positive: Phase 1 had already correctly decremented it 6→5
(the `_LP_PAIR` loop now enumerates 5 copies — the 4 callers commit/do/fix-issues/run-plan
plus the canonical `caller-loop-pattern.md` reference), so it was left unchanged.
**Remaining concerns / verify-at-execution:** (1) confirm `scripts/build-catalog.sh`
is the registry generator (reviewer verified it is — test invokes it at L23);
(2) `scripts/render-managed-rules.py --config --template --out` is the headless
managed.md regen path if `/update-zskills --rerender` can't run under a
/run-plan implementer (DA verified the signature); (3) the fixture `/quickfix`→`/do`
swap must keep the expected parser output (both are unrecognized skip-routes →
None) — verify the assertion after editing.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1 | 1 critical (`implementer.md` omitted), 3 major (`reports/TECHNICAL.html` scope, Phase-1 acceptance under-spec, land-pr derived counts), 1 minor (`:672` re-anchor) | 1 critical (tests/ sweep vs. left-in survivors contradiction; dangling `test-quickfix.sh` refs), 2 high (C18b test-body literals, stale `:672` citation), 2 medium (`reports/TECHNICAL.html`, conformance count-prose), 2 low (ordering + regen paths — confirmed sound) | 12/12 substantive fixed; 4 low/confirms need no action |
| Sweep | Whole-live-tree grep: complete coverage confirmed (all categories mapped; `.github`/`.claude-plugin`/`index.html`/`block-diagram`/`social-seo`/`hooks.json` clean) | — | 1 trivial (plan-file self-ref) fixed |
