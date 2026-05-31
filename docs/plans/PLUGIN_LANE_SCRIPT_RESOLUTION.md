---
title: Plugin-lane script resolution + dual-install hardening
created: 2026-05-29
status: active
---

# Plan: Plugin-lane script resolution + dual-install hardening

## Overview

The plugin install lane boots (plugin loads, `/zs:` skills resolve, the SessionStart
materialiser writes its 5 artifacts + seeds config, hooks fire) but **cannot execute any
workflow skill**: skill bodies — and several bundled scripts themselves — reach for
scripts/helpers at paths that only exist on the legacy `/update-zskills` lane (which mirrors
`skills/` into the consumer's `.claude/skills/`). A pure-plugin consumer has **no**
`.claude/skills/` mirror — skills live at `${CLAUDE_PLUGIN_ROOT}/skills/<skill>/`. Reproduced:
`git archive HEAD` → release tree; point `CLAUDE_PLUGIN_ROOT` at it; run a skill against a
consumer with only the 5 materialised artifacts + config; the first bundled-script call
(`bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"`)
fails `No such file or directory`. Masked through #799's entire review because **all** testing
ran in the dev repo where `CLAUDE_PROJECT_DIR` has the full mirror, so every reference resolved
via the fallback and the plugin path was never exercised.

**Three reference families break on a mirror-less plugin consumer** (counts re-derived
2026-05-29; re-derive at execution — they drift):

1. **Config-helper sources in skill `.md` bodies** — guarded two-line dual-path blocks whose
   **plugin branch points at the wrong path** `${CLAUDE_PLUGIN_ROOT}/scripts/<helper>` (correct:
   `${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/<helper>`) for `zskills-resolve-config.sh`,
   `zskills-paths.sh`, `zskills-stub-lib.sh`. **168 line-pairs** (`[ -f ]` test + `. "..."`
   source). #799's D6 specced this wrong primary. Re-derive:
   `grep -rc '\${CLAUDE_PLUGIN_ROOT}/scripts/zskills-' skills/ block-diagram/` (line-hits, ÷2 ≈ pairs).
2. **Bundled-script invocations in skill `.md` bodies** — `bash`/`python3`/`VAR="…"`-assignment/
   `$(… )`-capture forms pointing at `$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<x>`,
   with **no correct plugin-root branch**, PLUS the 15 path-prefix-form sites
   `${CLAUDE_PLUGIN_ROOT:-$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills}/scripts/<x>` (whose
   plugin branch wrongly resolves to `${CLAUDE_PLUGIN_ROOT}/scripts/<x>`). **≈144 invocation
   sites + 15 path-prefix.** Re-derive (EXCLUDE the family-1 legacy source lines — note BOTH the
   `. "..."` dot-shorthand AND the `source "..."` keyword form must be excluded; ~13 else-branches
   use the `source` keyword and the dot-anchor alone misses them):
   `grep -rn --include='*.md' '\$CLAUDE_PROJECT_DIR/\.claude/skills/[a-z0-9-]*/scripts/' skills/ block-diagram/ | grep -vE '(\.|source) "\$CLAUDE_PROJECT_DIR/\.claude/skills/update-zskills/scripts/zskills-(resolve-config|paths|stub-lib)\.sh"'`.
3. **Mirror-path references INSIDE bundled scripts** — e.g.
   `skills/run-plan/scripts/post-run-invariants.sh:85`
   (`source "$PROJECT_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"`,
   unconditional → hard-fails on plugin) and
   `skills/zskills-dashboard/scripts/backfill-plan-completed.sh:84,88` (primary + fallback both
   mirror-path; `2>/dev/null` then hard-error). **16 mirror-path refs inside `scripts/`**, of
   which the runtime-reached ones must be fixed. Re-derive:
   `grep -rn '\.claude/skills/[a-z0-9-]*/scripts/' skills/*/scripts/ block-diagram/*/scripts/`.

This plan also folds in two coupled hardening items sharing the lane-detection machinery:
(A) **dual-install blocking** for clients (dual is a dogfooding/transient state only, currently
merely WARNed), and (B) a **doc-wording fix** (`CLAUDE.md:20,22` calls dual "a supported,
permanent state").

**Legacy safety is non-negotiable and BYTE-IDENTICAL:** the legacy `/update-zskills` lane (the
only lane any consumer runs today) must behave exactly as now. Critically, today's bundled-script
calls anchor on `$CLAUDE_PROJECT_DIR` (the MAIN repo), **never** `ZSKILLS_PATHS_ROOT` — so the
new `ZSKILLS_SKILLS_ROOT` legacy branch MUST anchor on `$CLAUDE_PROJECT_DIR` only (NOT
`ZSKILLS_PATHS_ROOT`), or worktree-anchoring sessions would silently change which mirror copy
runs (a regression — see Plan Quality finding DA#1).

## Resolution mechanism (decided; adversarially reviewed — 3 sub-mechanisms)

Build-time staging (stage helpers into plugin-root `scripts/`) was **DISQUALIFIED**: it makes dev
(`--plugin-dir .`, root `scripts/` empty of these helpers) ≠ prod (staged), re-creating the
masking that hid this bug. The chosen approach keeps **dev==prod** (everything resolves under
`${CLAUDE_PLUGIN_ROOT}`, == repo root in `--plugin-dir` dogfooding) and uses a per-family fix:

- **Family 1 (config-helper `.md` sources):** keep the inline two-line dual-path bootstrap, change
  ONLY the plugin branch path `scripts/` → `skills/update-zskills/scripts/`. Legacy `else` branch
  unchanged (already `$CLAUDE_PROJECT_DIR/.claude/...`).
- **Family 2 (bundled-script `.md` invocations):** use a shared `ZSKILLS_SKILLS_ROOT` export so
  lane logic lives in one file; call form `bash "$ZSKILLS_SKILLS_ROOT/<owner>/scripts/<x>"`.
- **Family 3 (mirror-path refs INSIDE bundled scripts):** use `$(dirname "${BASH_SOURCE[0]}")`-
  relative sibling resolution (lane-agnostic on the 1:1 tree), with the existing mirror path as a
  guarded fallback. Scripts cannot easily import `ZSKILLS_SKILLS_ROOT`, so BASH_SOURCE-relative is
  the right primitive here (it's already the pattern in `claim-plan.sh:75-89`, which is plugin-safe).

## Canonical forms (verbatim — the spec all phases apply)

**Family 1 — config-helper bootstrap.** ONLY change vs today: `/scripts/` →
`/skills/update-zskills/scripts/` in BOTH the `[ -f ]` test and the source line of the plugin
branch. The legacy `else` branch is **unchanged**:

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
```

**`ZSKILLS_SKILLS_ROOT` export (added inside `zskills-paths.sh`; legacy branch anchored on
`$CLAUDE_PROJECT_DIR`, NOT `ZSKILLS_PATHS_ROOT`, to preserve today's main-anchored behavior):**

```bash
# Lane-portable skills root. Plugin: the plugin tree (never a worktree). Legacy: the consumer
# mirror under $CLAUDE_PROJECT_DIR — anchored on CLAUDE_PROJECT_DIR (NOT ZSKILLS_PATHS_ROOT),
# matching today's hardcoded `$CLAUDE_PROJECT_DIR/.claude/skills/...` invocation behavior.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/skills" ]; then
  ZSKILLS_SKILLS_ROOT="${CLAUDE_PLUGIN_ROOT}/skills"
else
  ZSKILLS_SKILLS_ROOT="$CLAUDE_PROJECT_DIR/.claude/skills"
fi
export ZSKILLS_SKILLS_ROOT
```

**Family 2 — bundled-script invocation.** After the standard bootstrap (the fence sources
`zskills-resolve-config.sh` — which W1.2 makes re-export `ZSKILLS_SKILLS_ROOT` — via the corrected
Family-1 form), every `bash "$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<x>"` (and its
`python3`/`VAR=`/`$(…)` variants) becomes:

```bash
bash "$ZSKILLS_SKILLS_ROOT/<owner>/scripts/<x>"
```

**Family 3 — inside a bundled script.** Replace an unconditional/guarded mirror source with
BASH_SOURCE-relative resolution + mirror fallback, e.g. (run-plan/scripts → ../../update-zskills/scripts):

```bash
_self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for _cand in "$_self_dir/../../update-zskills/scripts/zskills-paths.sh" \
             "${CLAUDE_PROJECT_DIR:-$_self_dir/../../..}/.claude/skills/update-zskills/scripts/zskills-paths.sh"; do
  [ -f "$_cand" ] && { . "$_cand"; break; }
done
```

**Allowlist (REPOINT — skill-owned, live ONLY under `skills/update-zskills/scripts/`):**
`zskills-resolve-config.sh`, `zskills-paths.sh`, `zskills-stub-lib.sh`, `resolve-repo-version.sh`,
`skill-version-delta.sh`, `port.sh`, `apply-preset.sh`, `json-set-string-field.sh`.

**Denylist (LEAVE — `${CLAUDE_PLUGIN_ROOT}/scripts/<x>` is correct): root tooling**
(`frontmatter-*`, `skill-content-hash.sh`, `skill-version-stage-check.sh`, `skill-version-compare.sh`,
`render-managed-rules.py`, `managed_rules_substitution.py`, `build-*`, `install-helpers-into.sh`,
`land-pr-bypass-message.sh`, `mirror-skill.sh`, `migrate-*`, `stop-dev.sh`, `switch-install-path.sh`,
`test-all.sh`) **and ALL `${CLAUDE_PLUGIN_ROOT}/hooks/` references** (incl. the
`.claude/hooks/verify-response-validate.sh` / `inject-bash-timeout.sh` paths, which the
materialiser writes — leave pinned). No skill body currently mis-references root tooling via the
plugin-root form (re-derive to confirm 0), so the denylist is a **migration-regex guard**.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Foundation: corrected primitives + spec + conformance fixtures | ✅ Done | `425d03f` | ZSKILLS_SKILLS_ROOT + corrected paths; +regression test; 6560/6560 |
| 2 — Family 1: repoint config-helper `.md` sources (~168 pairs) | ✅ Done | `e3125f3` | 336→0 wrong-form; 23 skills bumped; 6560/6560 |
| 3 — Family 2: migrate bundled-script `.md` invocations + bootstraps + 10 pinned assertions | ✅ Done | `ac29a24` | 161 invocations + 15 path-prefix → SSR; 49 bootstraps; 15 assertions; 6560/6560 |
| 4 — Family 3: fix mirror-path refs inside bundled scripts | ✅ Done | `d29be66` | post-run-invariants/backfill/stub-lib BASH_SOURCE-relative + paths.sh guard; 6560/6560 |
| 5 — Mirror-less prod-tree verification gate | ⬚ | | |
| 6 — Dual-install hardening + doc-wording fix | ⬚ | | |

## Phase 1 — Foundation: corrected primitives + spec + conformance fixtures

### Goal
Establish the corrected lane-portable primitives and fix the authoritative spec, so later phases
apply a known-correct, conformance-passing pattern.

### Work Items
- [ ] **W1.1** — Add the `ZSKILLS_SKILLS_ROOT` export (verbatim above) inside
  `skills/update-zskills/scripts/zskills-paths.sh`, placed AFTER the file's existing root
  resolution; the legacy branch anchors on `$CLAUDE_PROJECT_DIR` only. Mirror byte-equal to
  `.claude/skills/update-zskills/scripts/zskills-paths.sh`.
- [ ] **W1.2** — Make `zskills-resolve-config.sh` source `zskills-paths.sh` (it does NOT today —
  verified `grep -n zskills-paths …/zskills-resolve-config.sh` = empty), via the corrected
  Family-1 bootstrap, so any fence that sources resolve-config also gets `$ZSKILLS_SKILLS_ROOT`.
  **Mirror byte-equal.** (This is a 141-consumer hot file — mirror failure trips
  `test-skills-mirror-parity.sh`.)
- [ ] **W1.3** — Correct `references/canonical-config-prelude.md` (top-level `./references/`, NOT
  under the skill dir): lines encoding `${CLAUDE_PLUGIN_ROOT}/scripts/zskills-…` (≈11, 47-48) →
  `${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/…`; the path-prefix form (≈61) →
  `$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/<x>`; document the Family-2 call form. Grep-clean:
  zero `${CLAUDE_PLUGIN_ROOT}/scripts/zskills-` in the file after.
- [ ] **W1.4** — Update the `syn-pass-dualpath` fixture in `tests/test-skill-conformance.sh`
  (~2384-2424) to the corrected plugin path.
- [ ] **W1.5** — Add `tests/test-zskills-skills-root.sh`: assert `ZSKILLS_SKILLS_ROOT` =
  `${CLAUDE_PLUGIN_ROOT}/skills` when `CLAUDE_PLUGIN_ROOT` set + dir exists; =
  `$CLAUDE_PROJECT_DIR/.claude/skills` when unset; **and that it does NOT change when
  `ZSKILLS_PATHS_ROOT` is exported to a worktree** (the regression guard). Wire into `run-all.sh`
  (explicit `run_suite`).
- [ ] **W1.6** — Bump `metadata.version` on `update-zskills` (source + mirror byte-equal). **Order
  within the phase: edit → mirror → bump LAST → then run tests** (editing `scripts/` changes the
  skill content-hash; running `run-all.sh` before the bump trips the conformance stale-hash gate).

### Design & Constraints
- Legacy `else` branches stay byte-identical. bash-only; no jq; Python stdlib only.
- The per-fence conformance check is a substring match on `zskills-resolve-config.sh`
  (`test-skill-conformance.sh:2300,2339`) — changing the path does NOT break detection; W1.4 keeps
  the fixture accurate. `POS_VAR_RE` keys only on the 6 config vars, NOT `ZSKILLS_SKILLS_ROOT`, so
  a pure bundled-script fence is not forced to source a helper by conformance.

### Acceptance Criteria
- [ ] `grep -rn '\${CLAUDE_PLUGIN_ROOT}/scripts/zskills-' references/canonical-config-prelude.md` → 0.
- [ ] `tests/test-zskills-skills-root.sh` passes all three cases (plugin-set, unset, PATHS_ROOT-worktree-unchanged), wired into `run-all.sh`.
- [ ] `bash tests/run-all.sh` exits 0; mirror-parity green; `update-zskills` `metadata.version` bumped in both copies; source↔mirror byte-equal.

### Dependencies
None.

## Phase 2 — Family 1: repoint config-helper `.md` sources (~168 pairs)

### Goal
Correct every config-helper dual-path bootstrap's plugin branch path, across all skill bodies,
source + mirror.

### Work Items
- [ ] **W2.1** — Rewrite every plugin-branch `${CLAUDE_PLUGIN_ROOT}/scripts/<helper>` →
  `${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/<helper>` for the three two-line helpers,
  in BOTH the `[ -f ]` test and the `. "..."` source line. Do NOT touch the legacy `else` branch.
  Re-derive: `grep -rn '\${CLAUDE_PLUGIN_ROOT}/scripts/zskills-' skills/ block-diagram/`.
- [ ] **W2.2** — Mirror every edited file byte-equal into `.claude/skills/`.
- [ ] **W2.3** — Bump `metadata.version` on every touched skill dir (source + mirror), LAST. Re-derive
  set: `grep -rl '\${CLAUDE_PLUGIN_ROOT}/scripts/zskills-' skills/ block-diagram/ | sed -E 's#^(skills\|block-diagram)/([a-z0-9-]+)/.*#\1/\2#' | sort -u`.

### Design & Constraints
Mechanical, uniform substitution; only the token inside the `${CLAUDE_PLUGIN_ROOT}/...` plugin
branch changes. Never touch `${CLAUDE_PLUGIN_ROOT}/hooks/` or denylist basenames. After the sweep,
re-grep for surviving `${CLAUDE_PLUGIN_ROOT}/scripts/zskills-` (must be 0).

### Acceptance Criteria
- [ ] `grep -rn '\${CLAUDE_PLUGIN_ROOT}/scripts/zskills-' skills/ block-diagram/` → 0.
- [ ] Mirror byte-equal; touched skills' versions bumped; `bash tests/run-all.sh` exits 0.

### Dependencies
Phase 1.

## Phase 3 — Family 2: migrate bundled-script `.md` invocations + bootstraps + pinned assertions

### Goal
Rewrite bundled-script invocations to the `$ZSKILLS_SKILLS_ROOT` form, ensure each fence
bootstraps the export, and update ALL pinned conformance/smoke assertions in lockstep.

### Work Items
- [ ] **W3.1** — Rewrite ALL invocation forms whose path token is
  `$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<x>` → `$ZSKILLS_SKILLS_ROOT/<owner>/scripts/<x>`,
  regardless of the preceding command: `bash "..."`, `python3 "..."`, variable assignment
  (`HELPER="..."; … bash "$HELPER"`), and `$(bash "...")` capture. **EXCLUDE the family-1 legacy
  source lines** for `zskills-{resolve-config,paths,stub-lib}.sh` in BOTH the `. "..."` dot-shorthand
  AND the `source "..."` keyword forms (these are Family-1's else-branch — rewriting them is a
  chicken-and-egg: `ZSKILLS_SKILLS_ROOT` is SET BY sourcing them; ~13 else-branches use the
  `source` keyword and a `. "`-only filter misses them). Re-derive the target set with the
  corrected EXCLUSION grep from Overview §2 (scope `--include='*.md'`; the `.sh` self-comment
  lines are out of scope automatically).
- [ ] **W3.2** — Rewrite the 15 path-prefix-form sites
  `${CLAUDE_PLUGIN_ROOT:-$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills}/scripts/<x>` (for
  `port.sh`, `apply-preset.sh`, `resolve-repo-version.sh`, `skill-version-delta.sh`,
  `json-set-string-field.sh`) → `$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/<x>` (all are
  update-zskills-owned). One site is in `update-zskills/SKILL.md` Step 0.7 (plugin-lane-only path)
  — confirm it still resolves there.
- [ ] **W3.3** — For every fence that references `$ZSKILLS_SKILLS_ROOT` but has NO in-fence helper
  source (≈39 fences across ≈12 files; heaviest: `run-plan/modes/execute-phase.md` ≈13), add the
  corrected Family-1 bootstrap (source `zskills-resolve-config.sh`, which now re-exports
  `ZSKILLS_SKILLS_ROOT`) at fence-top. **EXCEPTION:** illustrative/template fences with
  placeholder args (e.g. `create-worktree/SKILL.md`'s `[--prefix P]` examples) are documentation,
  NOT executed — do NOT inject a live source there; instead leave the path as a documented literal
  or annotate. The implementer must classify each of the 39 as executable vs illustrative.
- [ ] **W3.4** — Update **all 10** pinned literal assertions across 4 test files that pin
  `bash/python3/… "$CLAUDE_PROJECT_DIR/.claude/skills/.../scripts/<x>"` — change each to the new
  `$ZSKILLS_SKILLS_ROOT/...` literal OR a path-insensitive substring (`scripts/<x>`):
  `tests/test-skill-conformance.sh` ~lines 269, 293, 295, 379, 401, 432, 483 (7); plus
  `tests/test-draft-tests.sh:151`, `tests/test-add-block-smoke.sh:41`,
  `tests/test-fix-report-smoke.sh:155` (3). **Re-confirm line numbers (they drift).** Do NOT touch
  `test-skill-conformance.sh:366` (it pins a `.claude/hooks/` path — denylist).
- [ ] **W3.5** — Mirror byte-equal; bump `metadata.version` on every touched skill (LAST).

### Design & Constraints
- Preserve all command args, captures, redirects, `|| true` exactly; only the path token changes.
- Family-3 (script internals) is OUT of this phase (Phase 4).
- Verify no fence references `$ZSKILLS_SKILLS_ROOT` before it is in scope.

### Acceptance Criteria
- [ ] Family-2 grep (EXCLUSION form) → only helper-self-comments / template-doc literals remain
  (each remaining hit explicitly classified by the implementer as illustrative).
- [ ] All 10 assertions updated and passing; `test-skill-conformance.sh`, `test-draft-tests.sh`,
  `test-add-block-smoke.sh`, `test-fix-report-smoke.sh` green.
- [ ] Mirror byte-equal; touched skills' versions bumped; `bash tests/run-all.sh` exits 0.

### Dependencies
Phase 1 (export). May run after/alongside Phase 2.

## Phase 4 — Family 3: fix mirror-path refs inside bundled scripts

### Goal
Make bundled scripts resolve their sibling-skill dependencies lane-agnostically, so a real
plugin run doesn't hard-fail inside a script.

### Work Items
- [ ] **W4.1** — Audit all 16 `.claude/skills/.../scripts/` refs inside `skills/*/scripts/` +
  `block-diagram/*/scripts/`. Classify each: (i) **runtime-reached unconditional/guarded mirror
  source** → fix with the Family-3 BASH_SOURCE-relative form (confirmed targets:
  `run-plan/scripts/post-run-invariants.sh:85`, `zskills-dashboard/scripts/backfill-plan-completed.sh:84,88`);
  (ii) already BASH_SOURCE-relative-first (e.g. `claim-plan.sh:75-89`) → leave; (iii) comments →
  optional. For the stub-lib `[ -f ]`-guarded sites (`create-worktree.sh:372`, `port.sh:54`) that
  silently no-op on plugin: add the plugin-tree candidate so consumer stub-callouts fire on the
  plugin lane too.
- [ ] **W4.2** — Mirror byte-equal; bump `metadata.version` on touched skills (LAST).

### Design & Constraints
- BASH_SOURCE-relative is the right primitive inside scripts (they can't cheaply import
  `ZSKILLS_SKILLS_ROOT`); keep the existing mirror path as a guarded fallback so legacy is
  unchanged. The 1:1 tree layout makes `../../<owner>/scripts/` correct on both lanes.
- Do NOT alter script behavior beyond the resolution path.

### Acceptance Criteria
- [ ] `post-run-invariants.sh` and `backfill-plan-completed.sh` resolve `zskills-paths.sh` on a
  mirror-less plugin consumer (proven by the Phase-5 gate exercising a run-plan/dashboard path).
- [ ] Mirror byte-equal; versions bumped; `bash tests/run-all.sh` exits 0.

### Dependencies
None hard, but lands before Phase 5 (the gate exercises these).

## Phase 5 — Mirror-less prod-tree verification gate

### Goal
Add the test that would have caught this whole class: a real release-layout, mirror-less
plugin-consumer dogfood. **Mandatory acceptance gate for the plan.**

### Work Items
- [ ] **W5.1** — Add `tests/test-plugin-mirrorless-resolution.sh`:
  1. `REL=$(mktemp -d); git archive --format=tar HEAD | tar -x -C "$REL"`; then **apply
     build-plugin-release.sh's FULL strip set** to `$REL` so `$REL` matches the SHIPPED tree, not a
     superset (closes the latent dev≠prod prune seam — DA#7). The strip set must match
     `scripts/build-plugin-release.sh` exactly — **prefer driving the test off that script's strip
     logic (source/extract it) rather than a hand-enumerated list** (a hand list drifts). As of
     2026-05-29 the script strips ALL of: README prod-strip blocks, `RELEASING.md`, `*CANARY*`,
     `canary*-bad.sh` hooks, `build-*.sh`, `dev_only:true` skills + their mirrors, and
     `MW-EXAMPLE`-marked files (the plan's earlier 4-item list omitted RELEASING.md + MW-EXAMPLE —
     re-confirm against the script at execution). (0 `dev_only` skills today, but make the gate
     robust to future ones.)
  2. `PROJ=$(mktemp -d)`; write only `$PROJ/.claude/zskills-config.json` with real
     `testing.full_cmd` + `timezone`; NO `.claude/skills/`.
  3. With `CLAUDE_PLUGIN_ROOT="$REL"` and `CLAUDE_PROJECT_DIR="$PROJ"` **fully overridden for every
     sub-invocation** (do NOT rely on `run-all.sh`'s global `CLAUDE_PROJECT_DIR=$REPO_ROOT` — that
     would false-GREEN via the live mirror): source `$REL/skills/update-zskills/scripts/zskills-resolve-config.sh`
     DIRECTLY (not by extracting a fence from markdown — DA-brittleness) and assert `$ZSKILLS_SKILLS_ROOT == $REL/skills`
     and `$FULL_TEST_CMD` non-empty.
  4. Invoke `bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" foo` →
     exit 0 + expected output; AND run a Family-3 script (`post-run-invariants.sh` help/dry path or
     `backfill-plan-completed.sh`) to prove script-internal resolution works mirror-less.
  5. **Negative control:** assert `$REL/scripts/zskills-resolve-config.sh` does NOT exist (proves
     the test targets the real failure mode).
  6. **Legacy-unchanged control:** `CLAUDE_PLUGIN_ROOT` unset + a consumer WITH a
     `.claude/skills/update-zskills/scripts/` mirror → same resolution succeeds via legacy branch.
- [ ] **W5.2** — Wire into `tests/run-all.sh` (explicit `run_suite`). The test must set
  `CLAUDE_PROJECT_DIR`/`CLAUDE_PLUGIN_ROOT` per-case, overriding the global export.
- [ ] **W5.3** — Add the dogfood as a step in `.github/workflows/test.yml` `plugin-mode` job.

### Design & Constraints
- `git archive HEAD` captures only COMMITTED state — so the migrated forms must be committed
  before this test is meaningful (it runs per-phase but is authoritative at plan close). The
  build-strip in step 1 mirrors `build-plugin-release.sh` without creating/pushing refs.
- The plugin tree intentionally contains `.claude/skills/` (it's tracked) — it is NEVER consulted
  on the plugin lane; mirror-less-ness is a property of the CONSUMER (`$PROJ`), not `$REL`.
- Reuse `test-sessionstart-dual-install-detect.sh` for lane-detection — don't duplicate. `Results:
  N passed, M failed` line; assert by exit code. Clean up temp dirs.

### Acceptance Criteria
- [ ] Test passes (positive, script-internal, negative-control, legacy-unchanged) and is wired in.
- [ ] Reverting any one migrated fence/script makes it go RED (implementer demonstrates).
- [ ] CI `plugin-mode` runs the dogfood.

### Dependencies
Phases 2, 3, 4.

## Phase 6 — Dual-install hardening + doc-wording fix

### Goal
Make dual-install a blocked client state, fix the misleading doc wording — without breaking the
dogfooding repo OR the documented lane-switch flow.

### Work Items
- [ ] **W6.1** — In `skills/update-zskills/SKILL.md`, add a **hard-refuse arm** for explicit
  `install` / `--with-addons` when `detect_install_state == plugin`, pointing at
  `scripts/switch-install-path.sh`. Reverses the current "not intercepted (opt-in)" carve-out
  (~956-959) — justify in prose (single-lane clients).
- [ ] **W6.2 (CRITICAL carve-out)** — The hard-refuse MUST NOT deadlock
  `scripts/switch-install-path.sh --to-update-zskills`, which instructs the user to
  `/plugin uninstall` → **restart** → `/update-zskills install` while `detect_install_state` may
  still return `plugin`. **A bare reorder (remove sentinels first) does NOT survive the mandated
  restart** (round-2 finding #2): on the restart, if the plugin is still loaded the SessionStart
  materialiser sees `fresh` and **re-materialises all 5 sentinelled artifacts**, re-arming
  `detect==plugin` → the subsequent `/update-zskills install` is refused again → deadlock.
  **Resolution: a `.zskills/switch-in-progress` marker** written by
  `switch-install-path.sh --to-update-zskills` at its START and removed only after the lane-lock
  is written LAST, honored by BOTH: (i) the W6.1 hard-refuse (skip the refuse when the marker is
  present), AND (ii) `hooks/session-start-materialise.sh` (skip re-materialise when the marker is
  present, so it does not re-arm `detect==plugin` across the switch's restart). The marker is the
  load-bearing state; it survives the restart, which the reorder cannot. Add a test
  (W6.5) that drives the full switch flow and asserts no deadlock.
- [ ] **W6.3** — In `hooks/session-start-materialise.sh`, escalate the `dual`/`update-zskills`
  arms: drop the once-per-session `.zskills/dual-install-warned` gate so the conflict surfaces
  every session until consolidated; make the message imperative ("dual install is not a supported
  client state — run `scripts/switch-install-path.sh` to pick one lane"). Keep `exit 0`/no-clobber
  (a SessionStart hook cannot uninstall a lane — document this bound in a comment).
- [ ] **W6.4** — Fix `CLAUDE.md` (~20, ~22): replace "supported, permanent state" /
  "both first-class, neither retired" with: clients are single-lane; dual is a dogfooding-repo /
  mid-switch transient the system tolerates without corruption and pushes to consolidate.
  (`CLAUDE.md` is hand-maintained, NOT generated — no re-render.) Add a one-line "single-lane per
  consumer" note in `docs/plans/PLUGIN_DISTRIBUTION.md` marking the old framing superseded (do not
  rewrite that completed plan).
- [ ] **W6.5** — Tests: extend `tests/test-update-zskills-lane-aware.sh` (or sibling) to assert the
  explicit-install hard-refuse fires when `detect_install_state == plugin` and NOT for
  `update-zskills`/`dual`/`fresh` (dev-repo-shaped case included); AND that the reordered
  `switch-install-path.sh --to-update-zskills` no longer trips the refuse (the carve-out works).
  Reuse `test-sessionstart-dual-install-detect.sh` for detection.
- [ ] **W6.6** — Bump `metadata.version` on `update-zskills` (source + mirror, LAST).

### Design & Constraints
- Hard-refuse keyed on `detect_install_state == plugin` (NOT `CLAUDE_PLUGIN_ROOT`), so the dev repo
  (classifies `update-zskills`; artifacts un-sentinelled) is never blocked. The materialiser is
  advisory-only — the real block lives in Step 0.7 (the writer that re-creates the mirror).

### Acceptance Criteria
- [ ] Explicit `/update-zskills install` on a `detect==plugin` fixture is refused; on
  `update-zskills`/`dual`/`fresh` unchanged; dev repo NOT refused.
- [ ] `switch-install-path.sh --to-update-zskills` completes end-to-end without tripping the refuse
  (carve-out verified by W6.5).
- [ ] `CLAUDE.md` no longer calls dual "a supported, permanent state."
- [ ] `bash tests/run-all.sh` exits 0; mirror byte-equal; `update-zskills` version bumped.

### Dependencies
Phase 1 (consistent lane-detection idioms). Otherwise independent of 2–5.

## Plan Quality

**Drafting process:** /draft-plan (auto) — 3 parallel research agents (reference-surface +
mechanism; test/conformance/build/verification; dual-install + docs + prior-plan overlap) → draft
→ 1 adversarial review round (reviewer + devil's-advocate) → refine.

**Mechanism decision:** build-time staging (c) **disqualified** (re-creates dev≠prod masking).
Chosen: per-family fix keeping dev==prod — corrected inline bootstrap (family 1), shared
`ZSKILLS_SKILLS_ROOT` export anchored on `$CLAUDE_PROJECT_DIR` on the legacy branch (family 2),
BASH_SOURCE-relative resolution inside scripts (family 3). The mirror-less prod-tree gate (Phase 5)
makes dev==prod *verifiable*.

**Convergence:** converged at round 2. Round 1 found 6 blocking + ~9 non-blocking issues; round 2
confirmed those resolved and caught 3 more in the refined material (the W6.2 reorder failing across
restart; the exclusion grep missing the `source` keyword form; the Phase-5 strip set omitting
RELEASING.md/MW-EXAMPLE). All round-2 findings are now folded in; no remaining substantive design
issues. **Remaining concerns:** (1) the ~330-site sweep across 3 families is large; mitigated by
uniform per-family forms, EXCLUSION-aware re-derivation greps (corrected for both `.`/`source`
forms), the mirror-parity gate, and the Phase-5 dogfood that fails red on any missed plugin path.
(2) The 10 pinned assertions + ~39-fence bootstraps must move in lockstep with the rewrites or the
suite goes red mid-phase — called out in W3.3/W3.4 with bump-LAST ordering. (3) The
`switch-in-progress` marker (W6.2) must be honored by BOTH the refuse and the materialiser and
cleared at lock-write — verified by W6.5.

### Round History
| Round | Reviewer findings | Devil's-advocate findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1 | missed family-3 (script internals: post-run-invariants.sh:85, backfill:84/88); family-2 forms broader (python3/VAR=); W3.2 target unpinned; counts; canonical-prelude location; W1.2 not a no-op; conformance preamble recognition; line-366 hooks exclusion; ZSKILLS_SKILLS_ROOT anchoring; brittle fence-extraction | DA#1 ZSKILLS_PATHS_ROOT regression; DA#2 39-fence bootstrap under-stated + template-fence hazard; DA#3 W3.1 over-matches legacy source lines (chicken-egg); DA#4 3 extra test assertions; DA#5 git-archive false-RED + run-all global CLAUDE_PROJECT_DIR false-GREEN; DA#6 W6.1 deadlocks switch-install-path; DA#7 git-archive vs pruned prod tree seam; mid-phase hash-gate ordering | all folded into Phases 1/3/4/5/6 + canonical forms + bump-LAST ordering |
| 2 | family-3 depth arithmetic SOUND; 10 assertions confirmed; round-1 resolutions verified; W3.2 other-sites note; W4.1 keep `ZSKILLS_PATHS_ROOT=` line | #2 W6.2 reorder fails across restart (materialiser re-arms) → use `switch-in-progress` marker honored by refuse AND materialiser; #3 exclusion grep misses `source` keyword (13 lines) → alternate `(\.\|source)`; #4 Phase-5 strip set omits RELEASING.md+MW-EXAMPLE → drive off build script | 3/3 folded into W6.2 / Overview§2+W3.1 / W5.1 |
