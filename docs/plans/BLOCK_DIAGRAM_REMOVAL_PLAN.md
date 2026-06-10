---
title: Remove the block-diagram Add-Ons Entirely
created: 2026-06-10
status: active
---

# Plan: Remove the block-diagram Add-Ons Entirely

## Overview

Remove the block-diagram add-on pack from zskills completely: the
`block-diagram/` source tree (3 skills: `/add-block`, `/add-example`,
`/model-design`, plus the `zsbd` plugin manifest and screenshots), its two
installed mirrors (`.claude/skills/add-block/`, `.claude/skills/add-example/`
— `model-design` has NO mirror, a pre-existing asymmetry), its doc pages
(`docs/skills/block-diagram/`), its two smoke-test suites, every `--with-addons`
/ `--with-block-diagram-addons` install path, every cross-skill / script /
hook / CI reference, and every test assertion that pins any of it.

**Falsifiable end state:**

```bash
git ls-files -z | xargs -0 grep -lirE 'block-diagram|zsbd|with-addons' -- 2>/dev/null \
  | grep -vE '^(docs/plans/|docs/reports/|docs/issues/|CHANGELOG\.md$|\.pre-paths-migration|references/skill-versioning\.md$)'
```

returns **zero files**, and `bash tests/run-all.sh` passes clean. The
exclusions are deliberate: `CHANGELOG.md`, `docs/plans/`, `docs/reports/`,
`docs/issues/`, and `.pre-paths-migration` are HISTORICAL surfaces that
document past work and must NOT be rewritten (this plan file itself lives in
`docs/plans/`). `references/skill-versioning.md` is excluded ONLY for its
explicitly-marked historical design-record lines (a design-history doc whose
§1.7 heading + §1.7/§1.9 "Chosen" records legitimately name the removed
pack): Phase 4 marks and lists them (case-INSENSITIVELY — the §1.7 heading's
capital `Block-diagram` is invisible to a case-sensitive grep), Phase 5
adjudicates the file's hits against that exact list — any unmarked hit there
is a real miss.

**Decisions already settled (do not relitigate):** `zsbd` is already delisted
from `marketplace.json` (#1062); NO legacy `--with-addons` consumers exist;
this is a clean, complete retreat — no deprecation shims, no tombstones. The
"23 core" skill count is UNCHANGED everywhere (block-diagram skills were never
counted in it); only `reports/TECHNICAL.html`'s "26 total = 23 + 3 add-ons"
framing changes.

**Why these phases, in this order.** A removal's structural property: the
suite cannot be green with the tree deleted while assertions still reference
it — but *removing an assertion about a still-present subject is always safe*.
So Phase 1 de-references everything in the test layer that does NOT pin
current plugin.json/mirror state (those edits would go red early). Phase 2
deletes the trees together with the small set of edits that are
*mutually* locked to the deletion (manifest-content pins, mirror
reverse-check, the conformance mirror-source fallback, the find that
hard-errors on a missing dir, and CI's fatal `validate --strict
./block-diagram` step). Phase 3 strips the functional
addon machinery from skills/scripts/hooks — each script change lands in the
SAME commit as the test that locks it (stage-check regex ↔ enforcement case 19;
mirror-skill arm ↔ Test 9; version-delta kind-column ↔ the delta test's row
shape). Phase 4 is prose-only root docs. Phase 5 is the sweep the /quickfix
precedent proved necessary: a green suite does NOT catch stale unpinned count
literals — 5 of them survived /quickfix's count phases. Every phase ends on a
green `bash tests/run-all.sh`.

**Execution context.** `main_protected: true` — execute via `/run-plan
docs/plans/BLOCK_DIAGRAM_REMOVAL_PLAN.md` in worktree mode. Implementation is
dispatched to `subagent_type: "implementer"` subagents; verification to the
verifier subagent. Each phase is one commit (Phase 3 may be 2–3 commits, but
each lockstep pair below must be INSIDE one commit). All line numbers are
marked ≈L — **verify by content, not blind line number**; the file may have
shifted since inventory.

## Critical invariants every phase must honor

1. **Source↔mirror parity (`test-skills-mirror-parity.sh`,
   `test-hooks-mirror-parity` in test-hooks).** Every file under `skills/<S>/`
   has a byte-identical twin under `.claude/skills/<S>/`; every `hooks/*.sh` a
   twin under `.claude/hooks/`. EDIT/DELETE BOTH IN THE SAME COMMIT. Pairs in
   this plan — skill mirrors touched: `update-zskills`, `commit`, `fix-issues`,
   `create-worktree`, `do`, `plans`, `run-plan`, `research-and-plan`,
   `draft-plan`, `briefing` (refresh via `bash scripts/mirror-skill.sh <S>`
   after each source edit). Hook mirror touched: `warn-config-drift.sh` ONLY
   (copy `hooks/warn-config-drift.sh` → `.claude/hooks/`).
   `block-unmaterialised-skill.sh` has NO `.claude/hooks/` mirror — it is
   plugin-lane-only (registered solely in `hooks/hooks.json` and listed in
   `tests/test-hooks-mirror-parity.sh` `EXCLUDE_BASENAMES` ≈L44–49); do NOT
   create one. Deletion pairs:
   `block-diagram/add-block` ↔ `.claude/skills/add-block`,
   `block-diagram/add-example` ↔ `.claude/skills/add-example` (same commit;
   `model-design` has no mirror — do not invent one, do not "fix" the
   asymmetry).
2. **Skill-versioning quadruple gate (warn-config-drift Edit-warn, /commit 2.5,
   `block-stale-skill-version.sh` PreToolUse deny, conformance CI).** ANY edit
   to a skill body or any regular file under a skill dir requires a
   `metadata.version` bump in source AND mirror, same commit:
   ```bash
   today=$(TZ=America/New_York date +%Y.%m.%d)
   hash=$(bash scripts/skill-content-hash.sh skills/<S>)
   bash scripts/frontmatter-set.sh skills/<S>/SKILL.md metadata.version "$today+$hash"
   bash scripts/mirror-skill.sh <S>
   ```
   Compute the hash AFTER all content edits to that skill. If a `git commit`
   is DENIED by the PreToolUse hook, the deny message carries the exact bump
   command — run it, re-stage, re-commit; do NOT treat the deny as a test
   failure.
3. **Hook version stamps.** Every edited `hooks/*.sh` gets its line-2
   `# zskills-hook-version:` stamp bumped (e.g. `2026.06.1` → `2026.06.2`) and
   its `.claude/hooks/` mirror refreshed, same commit.
4. **DocsRegistry is build output.** Never hand-edit `docs/DocsRegistry.js` —
   regenerate via `bash scripts/build-catalog.sh` and commit the result;
   `tests/test-doc-viewer-catalog.sh` byte-diffs committed vs fresh.
5. **Tests are never weakened — and this plan does not weaken any.** Every
   test deletion here is *subject-removal* (the asserted subject ceases to
   exist), and every numeric floor change is *re-derived from the new ground
   truth* (26 rows → 23 because `ls -d skills/*/ | wc -l` is 23 and the 3
   addon rows are gone). Re-run the exact scan/count command against the
   post-removal tree BEFORE changing any floor — a floor lowered below what
   the new ground truth supports is a loosening and is forbidden. Concretely:
   the ensure-worktree adopter floor stays at **6** (the skills/-only scan
   already yields 6 invocation lines today; the 2 block-diagram lines were
   *in addition*, 8 total — see Phase 1). The two meta-checks
   deleted in Phase 1 (the #458 scanner-scope tripwire and the invariants
   block-diagram meta-lint) exist SOLELY to guarantee scanners cover
   `block-diagram/` — when `block-diagram/` ceases to exist, the property they
   guard is vacuous, and they fail BY DESIGN once scanners narrow; deleting
   them in the same commit as the narrowing is the correct, honest move, not a
   weakening. Record this rationale in each commit message.
6. **Capture test output out-of-tree, never pipe:**
   ```bash
   TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
   mkdir -p "$TEST_OUT"
   bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
   ```
   Then READ the file. Report the command and per-suite results with explicit
   pass COUNTS (match counts, not just "0 failed").
7. **Suite green at the end of every phase** — `bash tests/run-all.sh` passes
   before the phase's commit is considered done.
8. **Historical surfaces are off-limits in every phase:** `CHANGELOG.md`,
   `docs/plans/`, `docs/reports/`, `docs/issues/`, `.pre-paths-migration`.
   Never "clean up" block-diagram mentions there.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — De-reference the test layer | ✅ | f4479288 | 19 test files; 7658/7658 passed; floor 6 kept; survivors per plan |
| 2 — Delete the trees + deletion-coupled edits | ✅ | 30c097d3 | 14 deletes + 8 edits; 7617/7617; −41 accounted; AC3 comment-hit → Phase 3 F |
| 3 — Strip addon machinery (skills, scripts, hooks, CI) | ✅ | 6b09c4ba | 56 files; 10 skill bumps+mirrors; 2 regex adaptations verified; post-commit 119/119+13/13 |
| 4 — Root docs + counts | ✅ | ff56972f | 5 docs files; receipts matched; 7614/7614; 3 leftovers → Phase 5 |
| 5 — Final sweep + verification | ✅ | | zero-ref sweep EMPTY; residual 19 hits all adjudicated survivors; count sweep clean (23 core intact); registry byte-clean; TECHNICAL.html internal-consistency fixes (handoff items 1–3); 7614/7614 |

---

## Phase 1 — De-reference the test layer

### Goal
Remove every block-diagram reference from the test suite that does NOT pin
current on-disk state (plugin.json content, live mirrors), so the suite is
green now (tree still present) and stays green when Phase 2 deletes the tree.
ONE commit — the meta-check deletions and the scanner narrowings they guard
are mutually locked and must not be split.

### Work Items

- [ ] **`tests/test-skill-conformance.sh` — single-touch, all in this phase:**
  - **Materialiser-presence entry** (≈L247): remove the line
    `block-diagram/.claude-plugin/plugin.json \` from the `for _art in` list
    (the assertion asserts the file EXISTS; it is deleted in Phase 2).
  - **`check_fixed` adopter entries** (≈L1930–1931): delete the two lines
    `check_fixed block-diagram/add-block "ensure-worktree invocation" 'bash "$HELPER"'`
    and the `block-diagram/add-example` sibling. Keep the other 4
    (draft-plan, refine-plan, draft-tests, fix-issues).
  - **ensure-worktree caller scan** (≈L1994–1995): the
    `grep -rn --include='*.md' ... "$REPO_ROOT/skills/" "$REPO_ROOT/block-diagram/"`
    process-substitution — drop the `"$REPO_ROOT/block-diagram/"` root (it
    would hard-error when the dir disappears). **The floor STAYS `-lt 6` —
    do NOT lower it.** Re-derivation (verified): the skills/-only scan
    already yields exactly 6 invocation lines today —
    `fix-issues/modes/sync.md`, `fix-report/SKILL.md`, `refine-plan/SKILL.md`,
    `draft-plan/SKILL.md`, `draft-tests/SKILL.md`, `fix-issues/modes/sprint.md`
    — the 2 block-diagram lines were IN ADDITION (8 total across both roots).
    Re-run `grep -rn --include='*.md' -E 'bash[[:space:]]+"\$HELPER".*\\$'
    skills/ | wc -l` to confirm 6 before committing. Rewrite the adjacent
    floor comment (≈L1979–1982): its adopter list is stale even today
    (predates fix-report and fix-issues/sync) — replace with the real set:
    draft-plan, refine-plan, draft-tests, fix-report, fix-issues (sprint +
    sync modes) = 5 skills / 6 invocation lines. Reword the pass string
    `skills/+block-diagram/` → `skills/`.
  - **#458 scanner-scope tripwire — DELETE ENTIRELY** (≈L2060–2113, the block
    from the `# Regression fixture (#458)` comment through the
    `fail "deny-list scanner scope regression"` fi): it counts ≥3
    `block-diagram` scan-root references across this file and
    `tests/lib/forbidden-literals-scan.sh` and fails BY DESIGN once the
    scanners narrow. Same commit as the narrowings below (Invariant 5
    rationale in the commit message).
  - **Scanner-root narrowings** (same commit as the tripwire deletion): every
    dual-root scan in this file becomes skills-only — the inline
    prose-imperative `find "$REPO_ROOT/skills" "$REPO_ROOT/block-diagram"`
    sites and the `scan_positive_side "$REPO_ROOT/skills" ... "$REPO_ROOT/block-diagram"`
    extra-root call (≈L2146, ≈L2206, ≈L2293, ≈L2483, ≈L2819, ≈L3023, ≈L3095,
    ≈L3167 — find them ALL by content:
    `grep -n 'block-diagram' tests/test-skill-conformance.sh` must return
    hits ONLY inside the per-skill-version mirror-source fallback block when
    done). Update adjacent comments.
  - **EXCEPTION — do NOT touch the "Phase 1b" block-diagram mirror-source
    fallback** (≈L3206–3210, inside the `=== Per-skill version mirror
    parity ===` loop): the `.claude/skills/{add-block,add-example}` mirrors
    still exist until Phase 2, and without this fallback the loop fails them
    as orphaned mirrors (`MIRROR_ONLY_OK` is `playwright-cli social-seo`
    only) → suite red. It is deleted in Phase 2, same commit as the mirrors.
- [ ] **`tests/lib/forbidden-literals-scan.sh`** (≈L3, ≈L9, ≈L24, ≈L176): drop
  the `$scan_root/block-diagram` second root from the dual-root `find` and the
  header comments. SAME COMMIT as the #458 tripwire deletion (the tripwire
  counts this file's dual-root find).
- [ ] **`tests/test-skill-file-drift-extended-scope.sh`** (≈L47): delete the
  synthetic `block-diagram/synth` extra-root case — its assertion INVERTS once
  `forbidden-literals-scan.sh` drops the second root, so it must die in the
  same commit as that narrowing.
- [ ] **`tests/test-skill-invariants.sh` — single-touch, all in this phase:**
  - **Phase C explicit file list** (≈L224): delete the block-diagram entry;
    update the "4 skills" comment → 3.
  - **Block-diagram meta-lint + exempt machinery — DELETE ENTIRELY**
    (≈L464–534: the `# Meta-lint: every framework-wide cross-skill check...`
    comment block, the awk continuation-joiner, the while-loop, and BOTH
    closing `check 'meta: framework-wide checks cover block-diagram/' ...`
    lines). Also delete every `# block-diagram-exempt:` marker line in the
    file (the one above the CLAUDE.md count check at ≈L578 and its
    explanatory comment lines) — the opt-out machinery is dead once the
    meta-lint is gone. SAME COMMIT as stripping ` block-diagram/` from check
    lines (below) — the meta-lint reds otherwise.
  - **Strip ` block-diagram/` from framework-wide check lines**: the
    flat-tracking-marker check (≈L460–461 `skills/ block-diagram/` → `skills/`)
    and any other `check` invocation enumerating both roots (find them:
    `grep -n 'block-diagram' tests/test-skill-invariants.sh`); Tier-1 fallback
    lists (≈L396–435) cleaned to skills-only; comment cleanups ≈L213, ≈L450.
  - **CLAUDE.md count checks** (≈L578–582): KEEP the skills-count check
    (`CLAUDE.md skills/ count matches ls -d skills/*/` — dynamic, unchanged at
    23); DELETE the sibling
    `CLAUDE.md block-diagram/ count matches ls -d block-diagram/*/ (minus screenshots)`
    check (it `ls`-es a dir that Phase 2 deletes, and pins a CLAUDE.md literal
    Phase 4 removes). Rewrite the surviving check's preceding comment to drop
    the "sibling assertion below" framing.
  - Done-check: `grep -n 'block-diagram' tests/test-skill-invariants.sh` → 0.
- [ ] **`tests/test-plugin-marketplace.sh`**: delete every zsbd block including
  the D10 version-lockstep assertion (≈L113–118, reads
  `block-diagram/.claude-plugin/plugin.json` which Phase 2 deletes — must be
  gone BEFORE the tree is). KEEP the ≈L76–77 `set(by_name) == {"zs"}`
  assertion. ADD a standalone replacement for the version-presence coverage the
  D10 check carried: assert `isinstance(zs_ver, str)` (and non-empty) for the
  zs marketplace/plugin version, so removing the lockstep does not silently
  drop the only check that zs carries a string version.
- [ ] **`tests/test-plugin-self-load.sh`** (≈L5–10, ≈L33, ≈L44–49, ≈L56) and
  **`tests/test-plugin-live-load.sh`** (≈L57, ≈L168–178): delete the zsbd
  validate halves (they run validation against `./block-diagram`, gone in
  Phase 2); retitle headers/echo banners to zs-only. ALSO rewrite the
  live-load ≈L151 design comment (`We do NOT grep for the literal zs/zsbd
  tokens: F4 ...`) to drop the zsbd token — it sits OUTSIDE the ≈L57/≈L168–178
  ranges and would otherwise fail this phase's exact-set AC. Done-checks:
  `grep -in 'zsbd\|block-diagram\|addon' tests/test-plugin-self-load.sh` → 0
  AND `grep -in 'zsbd\|block-diagram\|addon' tests/test-plugin-live-load.sh`
  → 0.
- [ ] **`tests/test-skill-version-delta.sh` — tree-coupled edits ONLY (the
  kind-COLUMN edits stay for Phase 3; this file is deliberately two-touch):**
  - Header comment (≈L4–12): drop the two addon-enumeration bullets.
  - Fixture-builder docstring (≈L37): drop the trailing
    `Plus block-diagram/.` sentence (outside all other enumerated ranges —
    it would otherwise survive into Phase 2, whose AC demands tests/ hits
    ONLY in the two Phase-3 survivors).
  - Fixture writes (≈L94–99): delete the `addon-installed` and
    `addon-not-installed` `write_skill` calls (including their ≈L93 and
    ≈L97–98 explanatory comments) and the `mkdir ... "$FIXT/block-diagram"`
    element of the mkdir line (≈L41).
  - `assert_row` calls: delete the two addon rows
    (`assert_row addon-installed ...`, `assert_row addon-not-installed ...`).
  - Row count check: `LINE_COUNT = "7"` → `"5"`; comment "5 core + 2 addon" →
    "5 core".
  - Real-repo smoke: `REAL_LINES -ge 26` → `-ge 23` (re-derived:
    `ls -d skills/*/ | wc -l` = 23, addon rows cease to exist); the ≈L149
    header comment "row count is at least 23 core + 3 addon = 26." → "at
    least 23 core"; pass-string
    "≥ 23 core + 3 addon = 26" → "≥ 23 core"; DELETE the `ADDON_COUNT` awk
    line and the `[ "$ADDON_COUNT" -ge 3 ]` clause (subject-removal — it goes
    to 0 the moment Phase 2 lands) AND the `addon=$ADDON_COUNT (≥3)`
    fragments of the kind-split pass/fail strings (≈L167/≈L169 — they would
    otherwise reference a now-unset variable); KEEP `CORE_COUNT`
    (`awk -F'\t' '$2 == "core"'`)
    and `[ "$CORE_COUNT" -ge 23 ]` FOR NOW — it is rewritten in Phase 3 when
    the kind column drops. Clean the ≈L164–165 comment (mentions
    block-diagram).
  - Do NOT touch `assert_row`'s 5-field format, the `NF != 5` invariant, or
    the `kind` arguments of the surviving core rows — those change in Phase 3
    with the script.
  - Done-check: `grep -in 'addon\|block-diagram'
    tests/test-skill-version-delta.sh` → 0 (the kept `core` kind args and
    `CORE_COUNT` awk carry neither literal).
- [ ] **`tests/test-update-zskills-version-surface.sh` — tree-coupled edits
  ONLY (this file is deliberately two-touch, like the delta test; its oracle
  helpers invoke the REAL `skill-version-delta.sh` and parse the TSV
  positionally — those field refs are rewritten in Phase 3 B's lockstep
  commit, NOT here):**
  - **Test 4 (≈L300–338) — surgical, NOT wholesale.** The addon material is
    interleaved with Test 4's SHARED fixture and its CORE assertion. Delete
    ONLY: the `"$T4/source/block-diagram"` element of the mkdir line (≈L307),
    the `write_skill "$T4/source/block-diagram/add-block" ...` line (≈L311),
    and the two addon sub-case blocks (≈L325–338: the `Site B addon hidden
    by default` if/else + the `# Now with addon flag.` … `BLOCK_ADD` block
    through its closing `fi`). KEEP everything else in ≈L305–324 — the `$T4`
    mktemp + fixture (minus the two deleted elements above) and the `Site B
    core skills shown with (new)` assertion: Test 6's contrast complement
    (≈L421 `INSTALL_OUT=$(render_site_b_block "$T4/source" ...)`) REUSES
    `$T4`, and wholesale deletion of a ≈L307–339 range would silently
    destroy core coverage (fewer PASS lines, exit code unchanged) and break
    Test 6.
  - Delete the header's "Site C — addon rows hidden" bullet (≈L24), the
    oracle doc comment `# Optionally include addon rows.` (≈L95), the
    fixture-builder docstring line `block-diagram/<name>/SKILL.md` (≈L141),
    and the `"$T1/source/block-diagram"` element of the T1 mkdir line
    (≈L179) — all comment/fixture-scaffold lines outside the ranges above.
  - Delete the `show_addons` parameter plumbing: the `show_addons="${3:-0}"`
    third args in `render_site_b_block`/`render_site_c_table`, the
    `-v show_addons=` awk flags, and the `$2 == "addon" && show_addons == 0
    { next }` filter clauses (with no addon fixtures the clauses never
    match — behavior-preserving on 5-field input). Drop the now-meaningless
    trailing `0` third args at the four surviving call sites (≈L316, ≈L346,
    ≈L421, ≈L422).
  - **LEAVE every positional `$3`/`$4`/`$5` field reference in the oracle
    helpers untouched** (≈L84–85 `$5 == "bumped" || $5 == "new"`, ≈L103
    printf, ≈L127–133 Site C awk) — the 5-field format persists until
    Phase 3 drops the kind column; shifting them now reds the suite.
  - Done-check: `grep -in 'addon\|block-diagram'
    tests/test-update-zskills-version-surface.sh` → 0 (the deliberately-kept
    positional field refs carry neither literal).
- [ ] **`tests/test-update-zskills-lane-aware.sh`** (≈L280–284): delete AC5c
  (the `--with-addons`-is-refused case — it pins SKILL.md prose Phase 3
  rewrites). KEEP AC5a/AC5b (bare-`install` refusal — W6.1 SURVIVES this
  plan). **Deliberately LEAVE the `refuse_gate` helper's `ADDON_FLAG`
  machinery in place for now** (≈L262 comment, ≈L265–267 signature +
  condition, ≈L288 AC5d "(no install/addons)" label) — it models the exact
  SKILL.md W6.1 condition and is simplified in Phase 3 in lockstep with the
  W6.1 rewrite (see Phase 3 item A).
- [ ] **`tests/test-skill-version-enforcement.sh`** — comment-only cleanup
  here: the case 12b comment (≈L94 region) cites the
  `(^|/)(skills|block-diagram)/` anchor — leave it for Phase 3 (it documents
  the hook regex that Phase 3 narrows). Do NOT delete case 19 in this phase
  (it locks against the stage-check regex, narrowed in Phase 3).
- [ ] **`tests/test-canary-failures.sh` cases 9–11 (≈L999–1052) — RENAME, do
  not delete:** these use `add-block`/`add-example` as SYNTHETIC marker names
  exercising generic delegation-pair hook semantics (case 10 is the ONLY
  delegation-pair deny case in the suite — coverage must survive). Rename the
  identifiers generic: e.g. `add-block.Gain` → `parent-skill.Gain`,
  `requires.add-example.Gain` → `requires.child-skill.Gain`,
  `skill: add-example` → `skill: child-skill`, `parent: add-block` →
  `parent: parent-skill`; rewrite the case comments to describe a generic
  parent↔child delegation pair (drop "block-diagram"). Keep marker SHAPE,
  pipeline-subdir layout, and pass/deny expectations byte-equivalent in
  structure. Verify the 3 cases still pass.
- [ ] **`tests/test-build-rewrite-marketplace-repo.sh`** (≈L13, ≈L70, ≈L87,
  ≈L93, ≈L118–121) — RENAME, do not delete: the synthetic marketplace fixture
  entry `{ "name": "zsbd", "source": "./block-diagram" }` tests that
  rewrite-marketplace leaves NON-zs entries untouched — coverage must survive.
  Rename to `{ "name": "other-addon", "source": "./other-addon" }` and update
  the field-access assertions (`by["zsbd"]["source"]` → `by["other-addon"]["source"]`,
  expected value `./other-addon`) and the header/pass/fail strings.
- [ ] **`tests/fixtures/draft-tests/p3/delegate-skip.md`** (≈L58, ≈L60) —
  RENAME, do not delete: the fixture's `### Execution: delegate /add-block to
  scaffold the new sub-skill` heading + `Delegate to /add-block ...` line use
  `/add-block` as a synthetic delegate-target exercising draft-tests
  phase-3 delegate-skip detection (consumed by
  `tests/test-draft-tests-phase3.sh` ≈L444/≈L510, which contains NO add-block
  literal itself — verified — so a fixture-side rename is safe). Rename to a
  surviving skill (e.g. `/create-worktree`) in both lines; verify
  `test-draft-tests-phase3.sh` still passes. Without this rename the fixture
  ambushes Phase 5's residual `add-block` sweep.
- [ ] **`tests/test-skill-description-budget.sh`** (≈L39 comment, ≈L83): narrow
  the skill-enumeration `find` to `"$REPO_ROOT/skills"` only (the dual-root
  form hard-errors when the dir disappears).
- [ ] **`tests/test-doc-viewer-catalog.sh`** — delete EXACTLY two pieces: the
  comment line `# block-diagram is an optional add-on, not part of the core
  set.` (≈L154) and the `if grep -q '"docs/skills/block-diagram/' ...
  fi` assertion block (≈L162–166; vacuous once the pages don't exist).
  **The `for dir in plans reports evals issues tracking` exclusion loop
  between them (≈L155–161) MUST SURVIVE** — it guards unrelated internal
  dirs, and deleting it would be a silent coverage loss (it only removes
  pass lines). Keep the loop's surviving intro comment line (≈L153).
- [ ] **Self-healing cosmetic cleanups** (comments / labels only, no logic):
  `tests/test-tmpdir-hardcode-guard.sh` (≈L91–93, ≈L205),
  `tests/test-plugin-mirrorless-resolution.sh` (≈L81),
  `tests/test-update-zskills-migration.sh` (≈L493),
  `tests/canary-ensure-worktree.sh` (≈L11).
- [ ] **Do NOT touch in this phase** (deliberate survivors, listed so the
  implementer doesn't "helpfully" finish them early):
  - `tests/test-add-block-smoke.sh`, `tests/test-add-example-smoke.sh`, and
    their `run_suite` registrations in `tests/run-all.sh` (≈L198–199) — they
    exercise the REAL tree; deleted with it in Phase 2.
  - `tests/test-plugin-manifest.sh` — its `zs: skills references ./skills/ and
    ./block-diagram/` assertion pins CURRENT plugin.json; editing it now goes
    red. Phase 2.
  - `tests/test-skill-frontmatter-survival.sh` — same: its manifest sanity
    checks grep the live zs + zsbd manifests. Phase 2.
  - `tests/test-skills-mirror-parity.sh` — its reverse check would FAIL if
    narrowed to skills-only while `.claude/skills/{add-block,add-example}`
    still exist. Phase 2.
  - `tests/test-skill-conformance.sh` ≈L3206–3210 — the per-skill-version
    mirror-source fallback (see the EXCEPTION above): deleting it while the
    two addon mirrors exist reds the orphaned-mirror check. Phase 2, same
    commit as the mirror deletions.
  - `tests/test-mirror-skill.sh` Test 9 (synthetic; locks the script arm —
    Phase 3) and `tests/test-skill-version-enforcement.sh` case 19 (synthetic;
    locks the stage-check regex — Phase 3).
  - `tests/test-suite-registry.sh` floor (`-gt 150`) — dynamic, self-heals at
    −2 suites; do not edit.
  - All historical surfaces (Invariant 8).

### Design & Constraints
- The two meta-check deletions (#458 tripwire, invariants meta-lint) and their
  corresponding scanner/check narrowings are MUTUALLY LOCKED — splitting them
  across commits reds the suite in between. One commit for the whole phase.
- The conformance `check`/`check_fixed` helpers fail-on-absence — that is why
  every positive block-diagram assertion must be physically removed, not left
  to pass vacuously.
- Floors changed here are re-derivations, not loosenings: state in the commit
  message how each new floor was derived (Invariant 5).

### Acceptance Criteria
- [ ] `grep -rin 'block-diagram\|zsbd\|with-addons' tests/` returns hits ONLY
  in the documented Phase-2/3 survivors: `test-add-block-smoke.sh`,
  `test-add-example-smoke.sh`, `test-plugin-manifest.sh`,
  `test-skill-frontmatter-survival.sh`, `test-skills-mirror-parity.sh`,
  `test-skill-conformance.sh` (mirror-source fallback block ≈L3206–3210
  ONLY), `test-mirror-skill.sh` (Test 9),
  `test-skill-version-enforcement.sh` (case 19 + comments). NOTE:
  `run-all.sh` is deliberately NOT in this set — its two smoke-test
  registration lines contain only `add-block`/`add-example`, which match
  none of the grep terms (verified). List the actual hit files in the phase
  report and confirm the set matches.
- [ ] `grep -n 'block-diagram' tests/test-skill-invariants.sh
  tests/lib/forbidden-literals-scan.sh` → 0 hits each;
  `grep -n 'block-diagram' tests/test-skill-conformance.sh` → hits ONLY
  inside the mirror-source fallback block (≈L3206–3210).
- [ ] Canary cases 9–11, the rewrite-marketplace non-zs-entry case, and
  `test-draft-tests-phase3.sh` (delegate-skip fixture renamed) still PASS
  with renamed identifiers (coverage preserved, not deleted).
- [ ] `bash tests/run-all.sh` passes — state the command and per-suite results
  with pass counts (Invariant 6 idiom).

### Dependencies
None — first phase.

---

## Phase 2 — Delete the trees + deletion-coupled edits

### Goal
Physically remove the block-diagram source tree, its mirrors, its doc pages,
and its smoke tests — together with the small set of edits that hard-fail or
flip the moment the tree/manifest changes. ONE commit.

### Work Items

- [ ] **Delete the trees:**
  ```bash
  git rm -r block-diagram/ docs/skills/block-diagram/ \
    .claude/skills/add-block/ .claude/skills/add-example/
  ```
  (`block-diagram/` includes the zsbd manifest
  `block-diagram/.claude-plugin/plugin.json`, README.md, add-block/,
  add-example/, model-design/, screenshots/. There is NO
  `.claude/skills/model-design/` — do not error hunting for it.) Verify with
  `test ! -e` on each path afterward; do not suppress errors.
- [ ] **Delete the smoke tests + registrations:**
  `git rm tests/test-add-block-smoke.sh tests/test-add-example-smoke.sh`; in
  `tests/run-all.sh` delete the two registration lines (≈L198–199):
  `run_suite "test-add-example-smoke.sh" ...` and
  `run_suite "test-add-block-smoke.sh" ...`.
- [ ] **`.claude-plugin/plugin.json`** (≈L12): `"skills": ["./skills/",
  "./block-diagram/"]` → `"skills": ["./skills/"]`. Do NOT add a `hooks`
  field (manifest hooks reference causes a duplicate-hooks load error — the
  no-hooks-field invariant survives).
- [ ] **`.gitignore`** (≈L34–41): delete the `!block-diagram/.claude-plugin/`
  and `!block-diagram/.claude-plugin/**` unignore rules and rewrite the
  comment block above them to mention only `.claude-plugin/`.
- [ ] **`tests/test-plugin-manifest.sh` — full rewrite to zs-only** (this file
  is wholly owned by this phase; its zs-skills assertion pins the manifest
  content changed above, and its top-of-file
  `find block-diagram -mindepth 2 -name SKILL.md ...` (≈L39) hard-errors on
  the missing dir):
  - Delete the `EXPECTED_BD_SKILLS` find/derivation (≈L39) and the roster
    assertion (`zsbd roster: disk has exactly add-block/add-example/model-design`).
  - Delete the entire zsbd half of the Python block: `ZSBD` constant, zsbd
    load/parse, `check_required(zsbd, ...)`, zsbd name check, the
    dependencies-present-on-zsbd check, zsbd agents-absent, zsbd skills/hooks
    checks (≈L51–124 region).
  - KEEP and adapt the zs dependencies-ABSENT check (drop the "on zsbd
    present" sibling, keep `"dependencies" not in zs`).
  - TIGHTEN the zs skills assertion (≈L108–109): from "references ./skills/
    and ./block-diagram/" to exact equality `zs.get("skills") == ["./skills/"]`.
  - Retitle the header comment block and the `===` echo banner (≈L36) to
    "plugin manifest validation (zs)".
- [ ] **`tests/test-skill-frontmatter-survival.sh`** (≈L17–20, ≈L72–94, ≈L100):
  - Header comment (≈L17–20): rewrite the scenario-2 description that names
    `block-diagram/.claude-plugin/plugin.json` (zsbd) — zs-manifest-only
    framing. (Outside the code ranges below — without this edit the phase's
    exact-set AC fails on a comment line.)
  - `covered_by_plugin()`: delete the `block-diagram/*/SKILL.md` case arm and
    its comment.
  - Delete the `ZSBD_MANIFEST` variable, the zsbd glob sanity check (greps a
    now-deleted file), and rewrite the zs sanity check to assert the exact
    `"skills": ["./skills/"]` manifest content — keep the
    coverage-assumption framing honest. (Do NOT use a "block-diagram is not
    declared" negative assertion — it would retain the literal this phase's
    AC and done-check require gone; exact equality subsumes it.)
  - Drop `block-diagram/*/SKILL.md` from the enumeration glob (≈L100).
  - Done-check: `grep -in 'zsbd\|block-diagram\|addon'
    tests/test-skill-frontmatter-survival.sh` → 0.
- [ ] **`tests/test-skills-mirror-parity.sh`** (≈L11–13, ≈L31, ≈L90–110,
  ≈L133): delete the addon forward-check section (block-diagram →
  `.claude/skills/` parity) and narrow the reverse check (every
  `.claude/skills/<name>` must have a source) to `skills/<name>` only —
  legal now ONLY because the two addon mirrors die in this same commit.
  Update header comments.
- [ ] **`tests/test-skill-conformance.sh`** (≈L3206–3210, the Phase-1
  deliberate survivor): delete the "Phase 1b" block-diagram mirror-source
  fallback inside the per-skill version mirror-parity loop — the
  `if [ -f "$REPO_ROOT/block-diagram/$name/SKILL.md" ]` arm, its
  `src_dir=` assignment, and the two comment lines above it (un-nest the
  surviving allow-list/fail else-branch accordingly). Legal now ONLY because
  the two addon mirrors die in this same commit — no mirror falls through to
  the fallback anymore. Done-check:
  `grep -n 'block-diagram' tests/test-skill-conformance.sh` → 0.
- [ ] **`.github/workflows/test.yml`** (≈L207–210): DELETE the
  `claude plugin validate --strict ./block-diagram` block (the command + its
  `::warning` + `exit 1`). This is deletion-coupled, NOT cosmetic: the step
  is FATAL when a `claude` CLI is reachable on the runner — the code is
  `|| { echo "::warning::…"; exit 1; }` (the ≈L145–147 comment claiming
  `|| true` semantics is WRONG; trust the code) — and it validates a dir
  this commit deletes. KEEP the `claude plugin validate --strict .` half.
  The surrounding comment/banner rewordings stay in Phase 3 F (prose-only).
- [ ] **DocsRegistry no-drift proof:** run `bash scripts/build-catalog.sh` and
  confirm `git diff docs/DocsRegistry.js` is EMPTY (the registry already
  excludes block-diagram pages — the deletion of `docs/skills/block-diagram/`
  must not change the generated output). If a diff appears, STOP and
  investigate — do not hand-edit.
- [ ] **Do NOT touch in this phase:** `scripts/build-catalog.sh`'s exclusion
  comment/logic (cosmetic once the dir is gone — Phase 3);
  `scripts/build-prod.sh` / `build-plugin-release.sh` globs (release-only,
  not suite-gated — Phase 3); the CI workflow's COMMENTS and echo banner
  (prose-only — Phase 3; the fatal zsbd validate BLOCK is deleted in this
  phase, see above); all skill SKILL.md prose (Phase 3); CLAUDE.md /
  RELEASING.md / TECHNICAL.html (Phase 4); historical surfaces
  (Invariant 8).

### Design & Constraints
- Mirror-parity (Invariant 1) is why the source tree and the two
  `.claude/skills/` mirrors die in ONE commit, and why the mirror-parity
  test's reverse-check narrowing rides in the same commit.
- `test-suite-registry.sh` self-heals: distinct-suite count drops by 2 but
  stays above the 150 floor — verify it passes, do not edit it.
- Deleting whole skill dirs does NOT trip the skill-version stage-check (no
  staged SKILL.md edits, only deletions — /quickfix precedent, PR #1073).

### Acceptance Criteria
- [ ] `test ! -e block-diagram && test ! -e docs/skills/block-diagram &&
  test ! -e .claude/skills/add-block && test ! -e .claude/skills/add-example`
  all hold.
- [ ] `grep -rin 'block-diagram\|zsbd\|with-addons' tests/ .claude-plugin/
  .gitignore` returns hits ONLY in `test-mirror-skill.sh` (Test 9) and
  `test-skill-version-enforcement.sh` (case 19 + comments) — the two Phase-3
  survivors. In particular `grep -n 'block-diagram'
  tests/test-skill-conformance.sh` → 0 (fallback deleted with the mirrors).
- [ ] `grep -n 'validate --strict ./block-diagram' .github/workflows/test.yml`
  → 0 (the fatal Tier-2 zsbd block is gone; the `--strict .` half survives).
- [ ] `bash scripts/build-catalog.sh` produces a byte-identical
  `docs/DocsRegistry.js` (no drift).
- [ ] `bash tests/run-all.sh` passes — state the command and per-suite results
  with pass counts.

### Dependencies
Phase 1 (every tree-coupled test assertion already gone).

---

## Phase 3 — Strip addon machinery (skills, scripts, hooks, CI)

### Goal
Remove every functional and prose reference to the addon lane from skill
bodies, helper scripts, hooks, and CI — with each script↔test lockstep pair
inside one commit, every edited skill version-bumped (date = the day the
commit lands, `TZ=America/New_York`; recomputed hash) and re-mirrored, and
every edited hook stamp-bumped and (where a mirror exists) re-mirrored.

### Work Items

**A. update-zskills (heaviest surface — bump + re-mirror at the end):**
- [ ] `skills/update-zskills/SKILL.md`:
  - ≈L20: usage synopsis — delete `[--with-addons | --with-block-diagram-addons]`.
  - ≈L122–129: delete the entire "Add-on flags" section (`--with-addons` and
    `--with-block-diagram-addons` bullets + the "Without an add-on flag, only
    the 23 core skills..." / "If core is already installed..." paragraph;
    keep any adjacent non-addon prose intact).
  - ≈L416–417: parser intro sentence — drop "and add-on flags".
  - ≈L422: delete `ADDON_FLAG=""` declaration line (and its trailing comment).
  - ≈L429: delete the parser case arm
    `--with-addons|--with-block-diagram-addons) ADDON_FLAG="$tok" ;;`.
  - ≈L436–438: delete the `--with-addons` orthogonality sentence.
  - ≈L989 + ≈L1040–1055: **W6.1 hard-refuse — REWRITE, do NOT delete.** The
    bare-`install` refusal on a `detect==plugin` consumer SURVIVES this plan
    (it blocks mirror re-creation; `tests/test-update-zskills-lane-aware.sh`
    AC5a/AC5b still pin it). Drop only the `--with-addons` disjunct: the
    policy-reversal heading "explicit `install` / `--with-addons`" → "explicit
    `install`"; the condition's `$ADDON_FLAG` disjunct; the error string
    `refusing 'install' / '--with-addons' on the plugin lane` → `refusing
    'install' on the plugin lane`. Re-run AC5a/AC5b mentally against the new
    wording before moving on.
  - ≈L2106–2119: delete Step E ("Install add-ons") entirely. Then fix the
    fallout: ≈L2161 Step F.5 "skills, hooks, scripts, and add-ons have been
    installed" → drop "and add-ons". **Do NOT re-letter the surviving step
    headings** — Step F stays Step F, and the heading
    `#### Step F.5 — Mirror the source-repo tag` must remain byte-identical:
    `tests/test-update-zskills-version-surface.sh` Test 7 (≈L460–469) pins
    it as a literal grep anchor. Heading gaps are precedented (Step C.9
    precedes Step C.5 at ≈L1813/≈L1850). Fix ONLY textual range references
    like "Steps B–E" (≈L2326–2327) by enumerating the surviving letters —
    verify by reading the actual step headings, not by assuming.
  - ≈L2200: delete the report-template line `- Add-ons: N add-on skills
    installed (omit this line if no add-on flag was used)`.
  - ≈L2216–2236 AND ≈L2416–2427: delete BOTH sites of the `show_addons`
    delta-renderer machinery — the explanatory paragraph (≈L2218–2219), the
    `show_addons=0` / `case "$ARGS" in *--with-addons*...` / `[ -d ...add-block ]`
    lines, and ALL THREE `$2 == "addon" && show_addons == 0 { next }` awk
    clauses (one at ≈L2235; TWO at ≈L2421 and ≈L2427 — the second site holds
    two awk programs, verified). The surviving awks consume the NEW 4-field
    delta format (see item B) — rewrite field references in the same edit:
    with the `kind` column gone the fields shift (`$1`=name, `$2`=source-ver,
    `$3`=installed-ver, `$4`=status); update every `$2`/`$3`/`$4`/`$5`
    reference in all three renderer awk programs accordingly (the FOURTH
    delta-consuming awk, at ≈L935, is handled in the next bullet).
  - ≈L935 — **the FOURTH delta-TSV awk consumer** (Site A audit gap-report
    spec): `n_changed=$(printf '%s\n' "$delta_tsv" | awk -F'\t'
    '$5 == "bumped" || $5 == "new"' | wc -l)` → `$4 == "bumped" || $4 ==
    "new"`. It contains NEITHER `== "addon"` nor `show_addons`, so the two
    done-checks below CANNOT see it — and no test pins it (version-surface
    Test 7 asserts keyword anchors only, and its oracles shift to `$4` in
    item B while this spec would silently stay at `$5`, making `n_changed`
    permanently 0 in audit gap reports with the suite green). Same commit
    as B.
  - Done-checks (all three, same commit):
    `grep -c '== "addon"' skills/update-zskills/SKILL.md` → 0 AND
    `grep -c 'show_addons' skills/update-zskills/SKILL.md` → 0 AND
    `grep -c '\$5' skills/update-zskills/SKILL.md` → 0 — the third check
    covers ALL FOUR delta-consuming awk fences (verified today: every `$5`
    in the file lives at exactly ≈L935, ≈L2236, ≈L2422–2423, ≈L2428 — no
    other `$5` exists, so file-wide zero is the correct post-shift state).
    This is the SKILL.md half of the kind-column lockstep — same commit as B.
  - ≈L2322–2324: delete update-path step 4 "Update installed add-ons" — and
    **do NOT renumber the subsequent steps**: leave the numbering gap (steps
    5. / 5.5. / 5.7. keep their numbers; Test 7 pins
    `^5\.7\. \*\*Mirror the source-repo tag` as a literal regex anchor).
    Update only prose cross-references to the deleted step, if any exist —
    verify by grep, not assumption.
- [ ] **`tests/test-update-zskills-lane-aware.sh` — refuse_gate simplification
  (SAME commit as the W6.1 rewrite above; the helper models the exact
  SKILL.md condition):** drop the `ADDON_FLAG` second parameter — ≈L262
  comment (`($MODE==install || $ADDON_FLAG non-empty)` → `$MODE==install`),
  ≈L265–267 `local MODE="$1" ADDON_FLAG="$2" PROJ="$3"` → two-arg form and
  `if { [ "$MODE" = install ] || [ -n "$ADDON_FLAG" ]; }` → drop the
  disjunct; update every surviving call site (AC5a/AC5b/AC5d) to the two-arg
  form; reword the AC5d label "(no install/addons)" → "(no install)".
  Done-check: `grep -cin 'addon' tests/test-update-zskills-lane-aware.sh`
  → 0. Without this, Phase 5's residual sweep hits `ADDON_FLAG` with no
  survivors-list entry.
- [ ] `skills/update-zskills/verifiers/verify-install-lib.sh` ≈L257: comment
  rewrite only (drop block-diagram mention).
- [ ] `skills/update-zskills/references/script-ownership.md` ≈L43:
  mirror-skill.sh row — drop the `block-diagram/<name>` form.
- [ ] `skills/update-zskills/scripts/resolve-repo-version.sh` ≈L42–43: comment
  rewrite.

**B. skill-version-delta kind-column — script + BOTH consumer tests, ONE
commit (with A's awk rewrites). The delta TSV has FOUR consumer surfaces: the
delta test, the version-surface test's oracles, and the SKILL.md awk fences
(four programs: the ≈L935 audit gap-report spec + the three renderer awks) —
all shift together:**
- [ ] `skills/update-zskills/scripts/skill-version-delta.sh`: drop
  `"$ZSKILLS_PATH/block-diagram"/*/` from the for-loop; delete the
  `case "$src_skill" in ... kind=...` block entirely; output becomes 4
  tab-fields: `printf '%s\t%s\t%s\t%s\n' "$name" "$src_ver" "$inst_ver"
  "$status"`. Rewrite the header comment (format line, kind explanation, the
  render-time-filter paragraph — all die).
- [ ] `tests/test-skill-version-delta.sh` — column-shape edits (the
  tree-coupled half already landed in Phase 1): `assert_row` drops its `kind`
  parameter and builds a 4-field needle; every surviving `assert_row` call
  drops the `core` argument; the comment "Format: <name>\t<kind>\t..." →
  4-field; the `NF != 5` invariant → `NF != 4` (with message); replace the
  `CORE_COUNT` awk + `-ge 23` clause with a plain row-count assertion
  (`REAL_LINES -ge 23` already exists — delete the CORE_COUNT block and its
  pass/fail strings).
- [ ] `tests/test-update-zskills-version-surface.sh` — oracle field-shifts
  (SAME commit; this file invokes the REAL `skill-version-delta.sh` at ≈L37
  and parses the TSV positionally — Phase 1 deliberately left these refs at
  the 5-field shape). Field map: old `$3`/`$4`/`$5` → new `$2`/`$3`/`$4`
  (`$1`=name unchanged). Concretely: `render_site_a_line` ≈L84–85
  `$5 == "bumped" || $5 == "new"` → `$4 ==`; `render_site_b_block` ≈L103
  `printf ..., $1, $3, $5` → `$1, $2, $4`; `render_site_c_table` ≈L127–133
  — `$5 == "bumped" { printf ..., $1, $4, $3 }` → `$4 == "bumped"
  { ..., $1, $3, $2 }`, `$5 == "unchanged" { ..., $1, $3 }` → `$4 ==
  "unchanged" { ..., $1, $2 }`, `$5 == "new"` → `$4 == "new"`. Find every
  ref by content (`grep -n "\\$5\|\\$4\|\\$3" tests/test-update-zskills-version-surface.sh`),
  not just these line anchors.

**C. Other skills (each gets version bump + re-mirror):**
- [ ] `skills/commit/SKILL.md` ≈L299: drop the `block-diagram/<owner>/...`
  path form from step 2.5 prose.
- [ ] `skills/fix-issues/modes/sprint.md` ≈L1684–1686: delete the awk
  else-branch that resolves `block-diagram/` script paths.
- [ ] `skills/create-worktree/scripts/ensure-worktree.sh` ≈L4–5: comment —
  rewrite the consumer enumeration "Six consumer skills (plan-family +
  block-diagram + /fix-issues)" to the re-derived post-removal truth:
  FIVE consumer skills / six invocation sites (draft-plan, refine-plan,
  draft-tests, fix-report, fix-issues sprint+sync). Do NOT write "4" — the
  addon adopters were in addition to the 6 skills/-side invocation lines,
  and the old comment had already drifted (predates fix-report and
  fix-issues/sync).
- [ ] `skills/do/SKILL.md` ≈L28: delete the `/add-block` triage-table row;
  `skills/do/modes/direct.md` ≈L80: delete the `/model-design` bullet.
- [ ] `skills/plans/SKILL.md` ≈L243: rewrite the example to a surviving skill;
  ≈L389: KEEP the skip-rule, rewrite its attribution to drop block-diagram.
- [ ] `skills/run-plan/modes/execute-phase.md` ≈L17, ≈L47: swap/delete the
  `/add-block` examples (use a surviving skill); ≈L711–714 + ≈L723: KEEP the
  past-failure lesson verbatim (the historical anecdote names "Step 7 of
  `/add-block`" — it stays; listed as a documented Phase-5 sweep survivor,
  source + mirror) but GENERALIZE the live instruction "the fix agent calls
  `/add-example`" (≈L723) into a skill-agnostic form ("fix agent re-runs the
  relevant skill/verification") — the lesson stays, the dead dispatch target
  goes.
- [ ] `skills/research-and-plan/SKILL.md` ≈L122: drop `/add-block` from the
  list.
- [ ] `skills/draft-plan/SKILL.md` ≈L433: rewrite the "/add-block delegate
  phases" sizing guidance around a surviving example.
- [ ] `skills/briefing/scripts/briefing.py` ≈L1968–1969, ≈L1982–1983: delete
  the `add-block`/`add-example` entries from `_DOGFOOD_SOURCE_CANON` and
  `_DOGFOOD_SOURCE_PREFIXES`.

**D. Hooks (line-2 stamp bump + `.claude/hooks/` mirror refresh each):**
- [ ] `hooks/warn-config-drift.sh`: FUNCTIONAL regexes ≈L126 and ≈L226 —
  `(^|/)(skills|block-diagram)/...` → `(^|/)skills/...` (preserve the rest of
  each pattern exactly); comments ≈L103, ≈L213, ≈L222–223. Before committing,
  `grep -rn 'skills|block-diagram' tests/test-hooks*.sh tests/hooks/` to
  confirm no test pins the dual-root pattern; if one does, update it in this
  same commit. Bump line-2 `# zskills-hook-version:`.
- [ ] `hooks/block-unmaterialised-skill.sh` ≈L26–28: comment condense (logic
  unchanged). Bump line-2 stamp. **NO mirror to refresh** — this hook is
  plugin-lane-only (registered in `hooks/hooks.json` only; listed in
  `tests/test-hooks-mirror-parity.sh` `EXCLUDE_BASENAMES` ≈L44–49); do NOT
  create `.claude/hooks/block-unmaterialised-skill.sh`.
- [ ] Also clean the case-12b comment in
  `tests/test-skill-version-enforcement.sh` (≈L90–94) that documents the old
  dual-root anchor — same commit as the warn-config-drift narrowing.

**E. scripts/ — each lockstep pair in one commit:**
- [ ] `scripts/mirror-skill.sh` (≈L3, ≈L10–13, ≈L31, ≈L38–45): delete the
  `block-diagram/*)` case arm, the usage line's `|block-diagram/<skill-name>`
  form, and the header/two-tree-resolution comments. SAME COMMIT:
  `tests/test-mirror-skill.sh` Test 9 (≈L191–208, synthetic fixture) —
  delete the whole test block (subject-removal: the arm it exercises is gone).
- [ ] `scripts/skill-version-stage-check.sh` (≈L5 comment, ≈L61 regex):
  `^(skills|block-diagram)/` → `^skills/`. SAME COMMIT:
  `tests/test-skill-version-enforcement.sh` case 19 (≈L476–500) — delete the
  whole case (it asserts block-diagram paths ARE gated; fails by design once
  the regex narrows) plus its mention in the comment at ≈L363. NOTE: the
  PreToolUse hook `block-stale-skill-version.sh` runs this script on THESE
  very commits — after the regex edit it still gates `skills/` edits, so all
  Phase-3 skill bumps remain enforced; nothing special to do, just don't be
  surprised by deny envelopes (Invariant 2 recovery).
- [ ] `scripts/switch-install-path.sh` ≈L109: `is_shipped_skill` — drop the
  `block-diagram/$1` disjunct (keep the `skills/$1` test).
- [ ] `scripts/build-prod.sh` ≈L106: drop the second (block-diagram) glob.
- [ ] `scripts/build-plugin-release.sh` ≈L167: drop the block-diagram glob;
  ≈L189–190: single-manifest version write — delete the zsbd half of the D10
  dual-write and fix the log text ("both plugin.json files" → "plugin.json").
- [ ] `scripts/_lib/finalize-prod-tree.sh` ≈L151: comment only.
- [ ] `scripts/build-catalog.sh` ≈L24: delete the block-diagram exclusion
  comment (and the exclusion logic if present — it is a no-op now); then
  re-run `bash scripts/build-catalog.sh` and confirm zero registry drift.

**F. CI — `.github/workflows/test.yml` (comments/banner only — the fatal
zsbd validate block was already deleted in Phase 2):**
- [ ] ≈L136, ≈L143: rewrite the comments ("both plugin.json files (zs +
  zsbd)" → zs-only; drop the `validate --strict ./block-diagram` mention;
  while there, fix the Tier-2 comment's stale `|| true` claim to match the
  actual warn-then-fail code).
- [ ] ≈L165: echo banner `"== zs + zsbd plugin.json schema =="` → zs-only.
- [ ] ≈L167: echo banner `"== marketplace.json schema (incl. D10 version
  lockstep) =="` → drop the `(incl. D10 version lockstep)` clause (the D10
  lockstep assertion died in Phase 1 with the zsbd manifest checks; this
  banner is the only D10 reference outside planned edit regions and carries
  no sweepable literal — it goes permanently stale if left).

**G. Version bumps + mirrors (PER-COMMIT discipline, not phase-end):**
`block-stale-skill-version.sh` checks each commit's STAGED set
(`scripts/skill-version-stage-check.sh` reads `git diff --cached`), so if
Phase 3 lands as 2–3 commits, EACH commit must carry the bumps for exactly
the skills whose files it touches — "hash AFTER edits" applies within a
commit, not across the phase.
- [ ] In each commit, for every skill it touches (full phase set:
  `update-zskills`, `commit`, `fix-issues`, `create-worktree`, `do`, `plans`,
  `run-plan`, `research-and-plan`, `draft-plan`, `briefing`) — run the
  Invariant-2 bump sequence (hash AFTER that commit's edits, source + mirror
  via `bash scripts/mirror-skill.sh <S>`), then verify
  `diff -rq skills/<S> .claude/skills/<S>` is clean for each.
- [ ] Verify both edited hooks carry bumped line-2 stamps;
  `warn-config-drift.sh` `.claude/hooks/` mirror byte-identical;
  `block-unmaterialised-skill.sh` has NO mirror — do not create one.

**Do NOT touch in this phase:** the W6.1 bare-`install` refusal core (rewrite
only, per item A); the D16(a) plugin-hook-skip shim and `hooks/hooks.json`
(already clean); `CLAUDE.md`/`RELEASING.md`/`references/`/`reports/`
(Phase 4); historical surfaces (Invariant 8). The "23 core" literals at
`skills/update-zskills/SKILL.md` ≈L127 region — the surviving prose keeps
saying 23 core; do not decrement anything.
`skills/research-and-go/SKILL.md` ≈L52 (and its mirror) — the space-form
"block diagram tool blocks" example is an ADJUDICATED consumer-app-domain
survivor (see Phase 5's space-form sweep): it names a consumer-project goal,
not the removed pack; "helpfully" rewriting it costs an 11th version bump +
mirror refresh for zero functional gain.

### Design & Constraints
- The four lockstep groups in this phase (delta column ↔ delta test +
  version-surface oracles + SKILL.md awks; W6.1 rewrite ↔ lane-aware
  refuse_gate; mirror-skill arm ↔ Test 9; stage-check regex ↔ case 19) each
  live in ONE commit. If the phase is split into multiple commits, split
  BETWEEN groups, never through one.
- Design call (settled): the `kind` column is DROPPED, not kept as a vestigial
  always-`core` column — the only consumers are the FOUR delta-consuming awk
  programs in SKILL.md (the three `show_addons` renderers — filter clauses
  deleted wholesale, surviving field refs shifted — plus the ≈L935 audit
  gap-report spec, which has NO filter clause and shifts `$5`→`$4` only),
  the delta test, and the version-surface oracles (both rewritten in
  lockstep).
- `briefing.py`, `ensure-worktree.sh`, `resolve-repo-version.sh`,
  `verify-install-lib.sh`, `script-ownership.md`, `skill-version-delta.sh`
  live UNDER skill dirs — their owning skills bump even though SKILL.md prose
  may be the smaller part of the change.
- Hooks are not skills: no `metadata.version`, but line-2 stamp + mirror are
  mandatory (Invariant 3).

### Acceptance Criteria
- [ ] `grep -rin 'block-diagram\|zsbd\|with-addons\|--with-block-diagram'
  skills/ .claude/skills/ hooks/ .claude/hooks/ scripts/ tests/
  .github/workflows/` → 0 hits.
- [ ] `bash scripts/skill-version-delta.sh "$(pwd)"` emits exactly 4
  tab-fields per row, ≥23 rows, no `addon`/`core` kind tokens.
- [ ] W6.1 still refuses bare `install` on a plugin-lane consumer:
  `test-update-zskills-lane-aware.sh` AC5a/AC5b pass;
  `grep -cin 'addon' tests/test-update-zskills-lane-aware.sh` → 0.
- [ ] Version-surface Test 7 anchors intact: `grep -q '#### Step F.5 — Mirror
  the source-repo tag' skills/update-zskills/SKILL.md` and
  `grep -qE '^5\.7\. \*\*Mirror the source-repo tag'
  skills/update-zskills/SKILL.md` both succeed (no step re-lettering /
  renumbering happened); `test-update-zskills-version-surface.sh` passes.
- [ ] `grep -c '== "addon"' skills/update-zskills/SKILL.md` → 0,
  `grep -c 'show_addons' skills/update-zskills/SKILL.md` → 0, AND
  `grep -c '\$5' skills/update-zskills/SKILL.md` → 0 (all three awk filter
  clauses + both plumbing sites gone, and ALL FOUR delta-consuming awk
  fences — including the ≈L935 audit gap-report spec — shifted off `$5`).
- [ ] Every bumped skill: source/mirror SKILL.md `metadata.version` equal,
  dated the day its commit landed (`TZ=America/New_York`), hash matches a
  fresh `skill-content-hash.sh` run.
- [ ] `bash tests/run-all.sh` passes — state the command and per-suite results
  with pass counts.

### Dependencies
Phase 2 (tree gone — the greps above would otherwise hit live sources; the
update-zskills Step-E deletion describes installing from a dir that must
already be absent).

---

## Phase 4 — Root docs + counts

### Goal
Remove block-diagram from the always-loaded agent docs and the human-facing
technical report, with every count RE-DERIVED from the post-removal tree —
never blind-decremented.

### Work Items

- [ ] **`CLAUDE.md`** (4 sites — root file only; CLAUDE_TEMPLATE.md and
  `managed.md` are ALREADY CLEAN, verified — do NOT re-render):
  - ≈L10: delete the roster bullet `` `block-diagram/` — add-on skills (3) ``.
  - ≈L15: rewrite the `.claude-plugin/` bullet: marketplace lists the single
    `zs` plugin (drop the "interim", the zsbd-delisted-but-bundled clause, and
    the `block-diagram/.claude-plugin/plugin.json` shipped-on-disk sentence).
    KEEP the no-`hooks`-field / duplicate-load warning verbatim.
  - ≈L24 (the "Two install lanes" paragraph): rewrite 3 sub-clauses — drop
    `--with-addons` from the W6.1 sentence (the bare-`install` refusal
    wording stays); drop the D10 "bump BOTH plugin.json.version files in
    lockstep" sentence (now: bump `plugin.json.version`); drop "validates
    both manifests + marketplace" → "validates the manifest + marketplace".
  - ≈L117 (`## Skill versioning`): "Every source skill under
    `skills/<name>/SKILL.md` and `block-diagram/<name>/SKILL.md`" → drop the
    second path.
  - The `(23 core)` literal at ≈L9 is UNCHANGED (dynamic invariants check
    still pins it — leave it).
- [ ] **`RELEASING.md`**: ≈L28–35 — rewrite the version-bump step to
  single-manifest (delete the zsbd-manifest sentence, the D10 lockstep test
  reference, and the zsbd-delisted/bundled explanation); ≈L73–74 — rewrite the
  rewrite-marketplace residue-invariant prose (drop "and the `zsbd`
  `./block-diagram` source"; keep the `ref`/`source.source` untouched-fields
  framing — the renamed `other-addon` fixture still covers non-zs entries).
- [ ] **`references/skill-description-budget.md`** ≈L5: drop the
  `block-diagram/*/SKILL.md` second glob from the scope line.
- [ ] **`references/skill-versioning.md`** (design-history doc — LIGHT-TOUCH
  forward-looking edits only, NOT a rewrite). Two distinct treatments —
  verified line map:
  - **Forward edits** (these document LIVE hook/conformance behavior that
    Phase 3 narrowed): ≈L155 and ≈L190 enumeration-root examples →
    skills-only; ≈L393 audit grep example → skills-only.
  - **Mark as historical** (dated design records — do NOT reword their
    content): the §1.7 heading at ≈L196 (`## 1.7 — Block-diagram add-ons …`
    — capital B, INVISIBLE to case-sensitive greps) and its `**Chosen.**`
    record ≈L198–200, plus the §1.9 `**Chosen.**` record at ≈L230 (names
    `block-diagram/<name>/SKILL.md` in the migration enumeration; contains
    NO count). "block-diagram add-ons removed 2026-06; retained for history"
    is acceptable marker wording. The "26 + 3 = 29" figure sits at ≈L198
    INSIDE the historical record — do NOT re-derive or update it; rewriting
    a dated design record falsifies history.
  - Derive and report the marked-line list CASE-INSENSITIVELY:
    `grep -niE 'block-diagram|zsbd|with-addons'
    references/skill-versioning.md` — after the forward edits, every
    remaining hit must be on the reported marked list (expected: ≈L196,
    ≈L198, ≈L200, ≈L230 plus their added marker lines).
- [ ] **`reports/TECHNICAL.html`** — rewrite to the 23-skill basis with
  RECOMPUTED numbers (run these from the worktree root and use the actual
  outputs; the old values 53,483 / 17,648 / 26 INCLUDE the deleted tree):
  ```bash
  ls -d skills/*/ | wc -l                                  # skill count (expect 23)
  find skills -type f \( -name "*.md" -o -name "*.sh" -o -name "*.py" \) -exec cat {} + | wc -l   # skills LOC
  find skills -type f \( -name "*.md" -o -name "*.sh" -o -name "*.py" \) | wc -l                  # file count
  cat skills/*/SKILL.md | wc -l                            # SKILL.md prose lines
  ls skills/*/SKILL.md | wc -l                             # SKILL.md body count (expect 23)
  ```
  - ≈L173: "13 user-facing + 10 internal helpers; 23 source skills + 3
    block-diagram add-ons = 26 total" → "= 23 total" framing (13 + 10 = 23
    stands on its own; drop the add-on clause).
  - ≈L174: LOC stat — recomputed value; sub-label `skills/ &
    block-diagram/` → `skills/`.
  - ≈L175: "26 SKILL.md bodies (23 source + 3 add-ons)" → "23 SKILL.md
    bodies" + recomputed prose-line value; keep the historical
    /quickfix-//doc-removal narrative as-is — do NOT append a mention of
    this removal (this phase's AC and Phase 5's sweeps require this file to
    carry zero `block-diagram`/`addon`/`add-on` literals; the removal is
    documented in CHANGELOG.md and this plan).
  - ≈L199–200: LOC table rows — `skills/ + block-diagram/` → `skills/`,
    recomputed LOC + file counts; "(23 source + 3 add-on)" → "23".
  - ≈L216: delete the `/add-block (block-diagram)` row from the top-10 table
    (and re-check the table is still a correct top-10 of SURVIVING skills —
    if a new #10 enters, add it from a fresh
    `wc -l skills/*/SKILL.md | sort -rn | head` run).
  - ≈L229: the reproduce-commands `<pre>` — `find skills block-diagram ...`
    → `find skills ...`.
  - ≈L246: closing banner "26 skills (13 user-facing + 10 helpers + 3
    add-ons)" → "23 skills (13 user-facing + 10 helpers)".
  - Update the "As of" date lines (≈L165, ≈L248) to the recompute date.
- [ ] **Do NOT touch:** `CLAUDE_TEMPLATE.md` and
  `.claude/rules/zskills/managed.md` (verified zero hits — no re-render
  needed; if you believe otherwise, grep first); `README.md`,
  `PRESENTATION.html`, `index.html`, `docs/DocsRegistry.js`, docs viewer app
  files, `hooks/hooks.json`, `.claude/settings.json`,
  `.claude/zskills-config.json`, `tests/fixtures/` (ALL verified already
  clean); every "23 core" count (unchanged); historical surfaces
  (Invariant 8).

### Design & Constraints
- These files are not skills — no version bumps, no mirrors.
- The CLAUDE.md ≈L10 bullet deletion is safe ONLY because Phase 1 already
  deleted the invariants sibling check that pinned "add-on skills (3)"
  against `ls -d block-diagram/*/`.
- TECHNICAL.html numbers must come from the commands above run in THIS
  worktree, post-Phase-3 — paste actual outputs, never arithmetic on the old
  published values.

### Acceptance Criteria
- [ ] `grep -in 'block-diagram\|zsbd\|with-addons\|add-on\|addon' CLAUDE.md
  RELEASING.md references/skill-description-budget.md reports/TECHNICAL.html`
  → 0 hits; `references/skill-versioning.md` retains ONLY explicitly-marked
  historical mentions — list them in the phase report via the
  case-INSENSITIVE `grep -niE 'block-diagram|zsbd|with-addons'` (a
  case-sensitive grep misses the capital-B §1.7 heading and would
  under-report the list Phase 5 adjudicates against).
- [ ] Every number in TECHNICAL.html's edited stats matches a quoted command
  output from this worktree (show command + output in the phase report).
- [ ] `bash tests/run-all.sh` passes (the dynamic CLAUDE.md skills-count check
  still green) — state the command and per-suite results with pass counts.

### Dependencies
Phase 1 (sibling count check gone), Phase 3 (tree + machinery gone so the
recomputed numbers are final).

---

## Phase 5 — Final sweep + verification

### Goal
Prove the removal is complete: zero live references, no stale counts, no
missed `addon`-class residuals (the class the /quickfix removal missed), no
registry drift, full suite green.

### Work Items

- [ ] **Zero-reference sweep (the Overview's falsifiable end state):**
  ```bash
  git ls-files -z | xargs -0 grep -lirE 'block-diagram|zsbd|with-addons' -- 2>/dev/null \
    | grep -vE '^(docs/plans/|docs/reports/|docs/issues/|CHANGELOG\.md$|\.pre-paths-migration|references/skill-versioning\.md$)'
  ```
  Expected: EMPTY. Any hit is a real miss — fix it (and its mirror/version
  bump if it's in a skill); do not add exclusions beyond this documented set.
  The `references/skill-versioning.md` exclusion is ADJUDICATED, not blanket:
  separately run `grep -niE 'block-diagram|zsbd|with-addons'
  references/skill-versioning.md` (case-INSENSITIVE — the zero-sweep itself
  is `-i`, and the §1.7 heading's capital `Block-diagram` is invisible to a
  case-sensitive cross-check) and confirm every hit is on the
  Phase-4-reported marked-historical list — an unmarked hit there is a miss.
- [ ] **Residual `addon`/`add-on` + skill-name + space-form sweep (judgment
  pass — this is the class /quickfix missed; the space-form term catches
  what every hyphenated pattern is blind to):**
  ```bash
  git ls-files -z | xargs -0 grep -nirE 'add-on|addon|add-block|add-example|model-design|block.?diagram' -- 2>/dev/null \
    | grep -vE '^(docs/plans/|docs/reports/|docs/issues/|CHANGELOG\.md:|\.pre-paths-migration)'
  ```
  (`block.?diagram` with `-i` matches `block-diagram`, `Block-diagram`, AND
  the space form `block diagram` — the last is invisible to the zero-sweep's
  hyphenated pattern.) Adjudicate EVERY hit individually. Known-legitimate
  survivors to expect and leave: the `other-addon` synthetic fixture in
  `tests/test-build-rewrite-marketplace-repo.sh` (generic non-zs-entry
  coverage, renamed in Phase 1 — only if the generic name was kept as
  `other-addon`); marked-historical lines in `references/skill-versioning.md`
  (Phase 4 — includes the capital-B §1.7 heading); the past-failure
  historical narrative in
  `skills/run-plan/modes/execute-phase.md` (≈L711–714, "Block Expansion Plan
  Phase 1 … Step 7 of `/add-block`") AND its byte-identical
  `.claude/skills/run-plan/` mirror copy — Phase 3 deliberately kept the
  names in the historical anecdote while generalizing the live instruction;
  the space-form example at `skills/research-and-go/SKILL.md` ≈L52
  (`/research-and-go Implement all missing block diagram tool blocks from
  the gap analysis`) AND its byte-identical `.claude/skills/research-and-go/`
  mirror copy — ADJUDICATED consumer-app-domain prose (it names a goal in a
  consumer project's domain, same class as qe-audit's "add blocks, connect
  ports" workflow example; it never referenced the removed pack), verified
  today as the ONLY space-form hit outside historical surfaces.
  Anything else — stale prose, a missed count, a dangling example —
  gets fixed here with the appropriate bump/mirror discipline.
- [ ] **Stale-count sweep (re-derive, don't pattern-match blindly):**
  ```bash
  grep -rn '26 total\|26 skills\|26 SKILL\|3 add-ons\|3 addon\|= 26\|+ 3 ' \
    --include='*.md' --include='*.html' --include='*.sh' --include='*.py' . \
    | grep -vE '^\./(docs/plans/|docs/reports/|docs/issues/|CHANGELOG\.md|\.git/)'
  ```
  plus confirm the invariant counts: `ls -d skills/*/ | wc -l` = 23 and
  CLAUDE.md still says `(23 core)`. Adjudicate each hit (some `+ 3 ` hits will
  be arithmetic noise — judge, don't mass-edit). EXPECTED legitimate hit: the
  `26 + 3 = 29` figure at `references/skill-versioning.md` ≈L198 sits inside
  a Phase-4 marked-historical design record — leave it (it is not "live"
  framing).
- [ ] **DocsRegistry final proof:** `bash scripts/build-catalog.sh` then
  `git diff --exit-code docs/DocsRegistry.js` (must be clean).
- [ ] **Full suite:** Invariant-6 idiom; read `"$TEST_OUT/.test-results.txt"`;
  confirm by PASS COUNT per suite.
- [ ] **Tracker completion:** update this plan's Progress Tracker — all phases
  ✅ with commit hashes and one-line notes (suite counts, sweep results).
- [ ] **Final report:** files deleted (by tree), files edited (by category:
  tests / manifests / skills / scripts / hooks / CI / docs), skills
  version-bumped (the 10), hooks stamp-bumped (the 2), counts changed (26→23
  total in TECHNICAL.html only; delta floor 26→23, delta row-count 7→5;
  ensure-worktree adopter floor UNCHANGED at 6 — re-derived, not lowered;
  "23 core" unchanged everywhere), and the historical surfaces deliberately
  left untouched.

### Design & Constraints
- The sweep greps run over `git ls-files` (tracked files only) so gitignored
  state (`.zskills/`, `.playwright/`, plugin caches) doesn't pollute results.
- If a sweep hit requires editing a skill file at this late stage, the full
  Invariant-2 discipline applies (bump + mirror, same commit) — no "it's just
  one word" exceptions; `block-stale-skill-version.sh` will deny the commit
  anyway.
- Precedent (QUICKFIX_REMOVAL_PLAN Phase 6): the independent verifier caught
  5 stale count literals there that no test pinned. Dispatch the verification
  of this phase to a verifier subagent with the three sweep commands verbatim
  and instructions to adjudicate hits independently of this plan's
  expectations.

### Acceptance Criteria
- [ ] Zero-reference sweep: EMPTY output (command shown verbatim in report).
- [ ] Residual sweep: every hit listed and adjudicated; only the documented
  legitimate survivors remain.
- [ ] Stale-count sweep: no live `26`-total / `3 add-ons` framing anywhere;
  `(23 core)` intact.
- [ ] `docs/DocsRegistry.js` matches a fresh `build-catalog.sh` run.
- [ ] `bash tests/run-all.sh` passes — state the command and EVERY suite's
  result with pass counts; name any skipped suite and why.

### Dependencies
All prior phases.

---

## Plan Quality

**Drafting process:** /draft-plan — consolidated 3-agent research (file:line
inventory, test-semantics analysis, atomicity constraints, /quickfix
precedent), draft with independent spot-verification of every lockstep pair
(case 19 synthetic-sandbox confirmed; plugin-manifest zs-skills pin confirmed;
mirror-parity reverse-check coupling confirmed; version-delta 5-field
format + `NF != 5` invariant + `$2=="core"` consumers confirmed; invariants
meta-lint + exempt machinery read in full), then 2 rounds of adversarial
review (independent reviewer + devil's-advocate per round), each finding
re-verified against the live tree before fixing.

**Convergence:** converged at round 2 after fixes. Both round-2 agents
confirmed all round-1 fixes hold (phase-boundary suite simulations green;
delta field map correct; floors re-derived not lowered; survivor lists
complete for round-1 keeps). Round-2 findings were enumeration/spec
tightenings — a missed fourth delta-TSV awk consumer joined an existing
lockstep, a deletion range respecified to element level, comment-line refs
enumerated, line-action maps corrected, case-sensitivity aligned — with no
structural rework (no phase added/removed/reordered, no lockstep group
changed shape).

**Remaining concerns:** none open. One judgment call made (round-2 F4): the
space-form "block diagram" example at `skills/research-and-go/SKILL.md` ≈L52
is kept as a documented consumer-app-domain survivor (with a new Phase 5
space-form sweep term + adjudication entry) rather than rewritten — verified
as the only space-form hit outside historical surfaces; rewriting would add
an 11th version bump for zero functional gain.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1 | 7 raw | 9 raw (→ 13 unique combined) | 13/13 fixed |
| 2 | 4 raw | 4 raw (→ 7 unique combined) | 7/7 fixed |
