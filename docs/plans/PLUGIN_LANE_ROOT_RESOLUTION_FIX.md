# Plugin-Lane Root Resolution Fix

**Status:** DRAFT v2 (fresh-agent reviewed; revisions folded in). Pending one-round `/refine-plan`.
**Landing:** PR (main_protected). Execute via `/run-plan` after refine.

## Problem (root cause — empirically proven this session)

On the **plugin lane**, zskills skills cannot resolve their bundled scripts on a **mirror-less** consumer (the normal plugin install). `/zs:update-zskills` verifier → `FAIL / lane=none`; `zskills-resolve-config.sh` fails to source `zskills-paths.sh` → `ZSKILLS_SKILLS_ROOT` unset → 201 `$ZSKILLS_SKILLS_ROOT/...` call sites across 43 files break.

### Proven facts (direct probes vs a real `claude --plugin-dir` runtime)
1. Bare `${CLAUDE_PLUGIN_ROOT}` is substituted in skill **markdown**; the `${CLAUDE_PLUGIN_ROOT:-}` form is **not**; and the var is **absent from the env** of scripts a skill launches/sources. (`MARKDOWN_ROOT=[/tmp/ptest]`, `COLONDASH_GUARD=false`, `SUBSCRIPT_ENV_ROOT=[EMPTY]`.)
2. The lane-resolution **fence** guards on `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]` → always false on plugin lane → `else` legacy `.claude/skills` path → **absent mirror-less** → the `.` (source) fails before any script code runs.
3. Same env-branch defect inside `zskills-paths.sh:54-57` and `zskills-resolve-config.sh:69-75`; verifier `vi_detect_lane` (verify-install-lib.sh:80) keys plugin detection solely on the env var.
4. **Masked by the dev repo's `.claude/skills/` mirror** (dual-install) — every prior "verified/dogfooded/ready" run resolved via the mirror. Only a true mirror-less consumer exposes it.

### Proven fix primitives (all verified live)
- Bare-token markdown substitution → a fence CAN learn the absolute plugin root.
- `BASH_SOURCE[0]` self-location works for **executed AND sourced** scripts → real plugin tree, **env-independent, cwd-independent, worktree-safe, readlink-safe**. (`EXEC_SELFDIR`/`SRC_SELFDIR=[/tmp/ptest]` from cwd `/` and `/workspaces/zskills/docs`.)
- `export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"` (bare RHS) propagates the substituted value to children.

## Scope boundary (do NOT touch)
- **Hooks are unaffected** — hook subprocesses get `CLAUDE_PLUGIN_ROOT` from the runtime + `hooks.json` substitution. The 14 hook `.sh`/`.template` files branching on `${CLAUDE_PLUGIN_ROOT:-}` are correct and conformance-locked.
- The 14 OTHER `.claude/skills`-referencing `.sh` scripts are already mirror-less-safe (`create-worktree.sh`, `claim-issue.sh`, `claim-plan.sh`, `port.sh`, `backfill-plan-completed.sh` already use BASH_SOURCE-relative resolution) or are legacy-by-design (`skill-version-delta.sh`, `migrate-paths.sh` operate ON the mirror). Confirmed by review; out of scope.

## The canonical NEW fence idiom (pin this; Phase 2 applies it everywhere)

Replace the broken guarded form. New two-line dual-path form:

```bash
# Lane-portable resolve-config bootstrap. Bare ${CLAUDE_PLUGIN_ROOT} is
# substituted in plugin-skill markdown (absolute path) and empty on the
# legacy lane; the -f test (NOT a "${X:-}" guard) is what distinguishes lanes.
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "${CLAUDE_PROJECT_DIR:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." 2>/dev/null && pwd)}/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
```

- Drops the never-substituting `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]` guard; the bare `-f` test substitutes to a real path on plugin (true) and to a missing path on legacy (false → else).
- `export` (defense-in-depth) propagates the value to any child the sourced script later launches.
- The `else` self-heals `CLAUDE_PROJECT_DIR` via git-common-dir (matches the script's own fallback) for the case the harness didn't set it.
- set -u: skill fences do NOT enable `set -u` (verified — no `set -u`/`set -euo` precedes any resolution block; `set -e` cases checked, none gate resolution). Bare unset → empty, not unbound.

## Phase 1 — Env-independent core + ONE end-to-end vertical slice (atomic; the load-bearing fix)  [ ]

Per review: the fence migration is the actually-load-bearing change (a self-locating script is useless if the fence can't source it). So Phase 1 delivers a COMPLETE working slice for one skill, proven on a real mirror-less consumer, before the wide sweep.

- **Scripts (env-independent via BASH_SOURCE):**
  - `zskills-paths.sh:54-57`: derive `ZSKILLS_SKILLS_ROOT` from `$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../..` (script at `<skills_root>/update-zskills/scripts/`). Keep `CLAUDE_PROJECT_DIR` git fallback for config reads only.
  - `zskills-resolve-config.sh:69-75`: source `zskills-paths.sh` as a `BASH_SOURCE`-relative sibling.
  - `verify-install-lib.sh`: `vi_detect_lane` — when `$CLAUDE_PLUGIN_ROOT` env empty, detect **plugin** via (a) on-disk materialised sentinels (reuse `vi_has_materialiser_sentinel`) AND/OR (b) **the verifier's own BASH_SOURCE landing under a plugin tree (NOT `<proj>/.claude/skills`)** — the (b) signal covers the pre-materialise / D27-refused timing gap the review flagged. KEEP the existing return vocabulary (`plugin|legacy|dual|none` — NOT `update-zskills`). Reimplement inline (the lib is deliberately self-contained; do NOT source `detect-install-state.sh`). Preserve `dual` detection (sentinelled artifacts + populated `.claude/skills`). `vi_check_plugin` `plugin.root-reachable`: resolve root from the verifier's BASH_SOURCE (`verifiers/ → update-zskills/ → skills/ → root`), used on the plugin lane only.
- **Fence (apply the new idiom to `skills/update-zskills/SKILL.md` only, this phase).**
- **Update `references/canonical-config-prelude.md`** (repo root) — rewrite §1/§3/§4/§6 to the new idiom (all paste the dual-path form, not just §1).

**Acceptance (must exercise a REAL fence guard, not a direct absolute source):**
- Against a real mirror-less materialised consumer with EMPTY env: a synthetic fence rendered the way the harness does (bare token → absolute literal) sources resolve-config.sh successfully and `ZSKILLS_SKILLS_ROOT` resolves to a real dir.
- Real `claude --plugin-dir` mirror-less dispatch of `/zs:update-zskills` → verifier `lane: plugin`, `Overall: PASS`. **Watched FAIL → PASS** (the gate missing when this shipped).
- Legacy lane regression: resolution still works in the dev repo.

## Phase 2 — Mechanical sweep across all remaining skills  [ ]

- Apply the new idiom to all remaining fence sites. **Corrected scope: 231 guard-if lines across 47 files in `skills/`; 255 incl. `block-diagram/`; 24 distinct skills need a `metadata.version` bump.**
- **Handle all ≥3 variants** (one transform is insufficient):
  1. two-line dual-path guard (majority);
  2. single-line `:-`-default collapse — `skills/draft-plan/references/brainstorm.md:337` (`${CLAUDE_PLUGIN_ROOT:-$CLAUDE_PROJECT_DIR/.claude}`), also broken (the `:-` default doesn't substitute);
  3. **~8 distinct target scripts** (not just `zskills-resolve-config.sh`: also `zskills-paths.sh`, `zskills-stub-lib.sh`, `port.sh`, `sanitize-pipeline-id.sh`, `clear-tracking.sh`, `verify-install.sh`, etc.) — the transform must be target-agnostic.
- Bump `metadata.version` per edited skill (`scripts/skill-content-hash.sh` + `frontmatter-set.sh`).
- **Re-mirror `skills/` → `.claude/skills/`** (49 mirror files carry the fence) so `test-skill-conformance.sh` source/mirror-sync passes. Edit source only, then batch-cp (avoid per-edit permission storms).
- Update `CLAUDE_TEMPLATE.md` (1 ref) and re-render `managed.md`.

**Acceptance:** zero remaining `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]`-guarded resolution fences AND zero `${CLAUDE_PLUGIN_ROOT:-$...}`-default fences in `skills/**`/`block-diagram/**`; source/mirror byte-sync; `bash tests/run-all.sh` green.

## Phase 3 — De-mask tests + conformance lock-in  [ ]

- **De-mask `tests/test-plugin-mirrorless-resolution.sh`:** the mask is two-fold — positive cases (1/2/3/5) both pre-`export CLAUDE_PLUGIN_ROOT` AND source the absolute path directly, bypassing the fence. Add ≥1 case that does NEITHER: render a synthetic fence with the bare token substituted to the consumer's plugin path and NO pre-export, run THAT, assert resolution. De-mask cases 2/3/5 similarly.
- **Conformance:** add an assertion in `tests/test-skill-conformance.sh` forbidding the `:-`-guarded / `:-`-default resolution forms in skill `.md`. **Resolve the existing conflict:** rewrite the `test-skill-conformance.sh:2667` positive fixture and the `syn-pass-dualpath` synthetic-PASS case (~line 2700) to the new idiom in the SAME PR (the preamble detector still keys on the `zskills-resolve-config.sh` substring, which the new idiom retains).
- **Behavioral gate in CI/attended:** capture the mirror-less `/zs:update-zskills` FAIL→PASS in the live-load attended suite if feasible.

**Acceptance:** `bash tests/run-all.sh` green (state command + per-suite counts); de-masked mirror-less test proves fence self-bootstrap; conformance forbids the broken forms.

## Risks / notes
- Symlinked plugin cache → `readlink -f` in script self-location (physical path).
- Diff looks large (24 version bumps + 49 mirror files) but semantic surface = 3 scripts + 1 fence idiom + tests.
- Verifier self-located root is correct as plugin-root ONLY on the plugin lane (legacy `../../..` = `<proj>/.claude`); consume it on the plugin path only — document this invariant.
- **Supersedes "plugin lane ready to ship"** — the lane is NOT consumer-ready until this lands.
