# Plugin-Lane Root Resolution Fix

**Status:** ✅ COMPLETE — all 3 phases executed, verified, and merged via PR #1046 (main @ `5c8fc9a`, 2026-06-03). Mirror-less plugin install verified working LIVE (`claude --plugin-dir` → `/zs:update-zskills` reports `lane: plugin`; bundled verifier `Overall: PASS`). Full suite `7601/7601`. See `docs/reports/plan-plugin-lane-root-resolution-fix.md`.
**Landing:** PR (main_protected). Executed via `/run-plan ... finish auto`.

## Problem (root cause — empirically proven this session)

On the **plugin lane**, zskills skills cannot resolve their bundled scripts on a **mirror-less** consumer (the normal plugin install). `/zs:update-zskills` verifier → `FAIL / lane=none`; `zskills-resolve-config.sh` fails to source `zskills-paths.sh` → `ZSKILLS_SKILLS_ROOT` unset → ~201 `$ZSKILLS_SKILLS_ROOT/...` call sites across ~43 files break.

### Proven facts (direct probes vs a real `claude --plugin-dir` runtime)
1. Bare `${CLAUDE_PLUGIN_ROOT}` is substituted in skill **markdown**; the `${CLAUDE_PLUGIN_ROOT:-}` form is **not**; and the var is **absent from the env** of scripts a skill launches/sources. (`MARKDOWN_ROOT=[/tmp/ptest]`, `COLONDASH_GUARD=false`, `SUBSCRIPT_ENV_ROOT=[EMPTY]`.)
2. The lane-resolution **fence** is `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/…" ]`. The first conjunct uses the `:-` form → never substituted → empty env → **always false** on the plugin lane → the (working, bare-token) `-f` clause is short-circuited away → `else` legacy `.claude/skills` path → **absent mirror-less** → the `.` (source) fails before any script code runs.
3. Same defect inside `zskills-paths.sh:54-57` and `zskills-resolve-config.sh:69-75`; verifier `vi_detect_lane` (verify-install-lib.sh:80) keys plugin detection solely on the env var.
4. **Masked by the dev repo's `.claude/skills/` mirror** (dual-install) — every prior "verified/dogfooded/ready" run resolved via the mirror; the dev-tree mirror also masks `tests/test-plugin-mirrorless-resolution.sh` (it pre-`export`s the env var). Only a true mirror-less consumer exposes it.

### Proven fix primitives (all verified live)
- Bare-token markdown substitution → a fence CAN learn the absolute plugin root.
- `BASH_SOURCE[0]` self-location works for **executed AND sourced** scripts → real plugin tree, **env-independent, cwd-independent (proven from cwd `/` and a repo subdir), worktree-safe, readlink-safe**.
- `export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"` (bare RHS) propagates the substituted value to children.

## Scope boundary (do NOT touch)
- **Hooks are unaffected** — hook subprocesses get `CLAUDE_PLUGIN_ROOT` from the runtime + `hooks.json` substitution. The hook `.sh`/`.template` files branching on `${CLAUDE_PLUGIN_ROOT:-}` are correct and conformance-locked.
- The OTHER `.claude/skills`-referencing `.sh` scripts are already mirror-less-safe (`create-worktree.sh`, `claim-issue.sh`, `claim-plan.sh`, `port.sh`, `backfill-plan-completed.sh` use BASH_SOURCE-relative resolution) or operate ON the mirror by design (`skill-version-delta.sh`, `migrate-paths.sh`). Confirmed; out of scope.
- **`CLAUDE_TEMPLATE.md:24`** — the lone `${CLAUDE_PLUGIN_ROOT}` ref is **agent-read prose** (cron-fire handler: "Read `${CLAUDE_PLUGIN_ROOT}/skills/<skill>/SKILL.md` … try the plugin path first"), NOT a shell fence. Already correct (probe-plugin-first, fall back). **Leave as-is** — do NOT mechanically rewrite it.

## The canonical NEW fence idiom (pin this; Phase 2 applies it)

```bash
# Lane-portable resolve-config bootstrap. The harness substitutes the BARE
# ${CLAUDE_PLUGIN_ROOT} token in plugin-skill markdown (absolute path); on
# the legacy lane it is unset/empty. The bare-token -f test (NOT a
# "${X:-}" guard, which the harness does NOT substitute) selects the lane.
# MUST NOT run under `set -u` (the bare token would be unbound on the
# legacy lane) — enforced by a conformance assertion (Phase 3).
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  _zsk_proj="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$_zsk_proj" ] || _zsk_proj="$(cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." 2>/dev/null && pwd)"
  . "$_zsk_proj/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
```

- Drops the never-substituting `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]` first conjunct; the bare `-f` test substitutes to a real path on plugin (true) and a missing path on legacy (false → else).
- `set -e` safe: a non-matching `[ -f ]` as an `if` condition returns non-zero without aborting (verified).
- **`set -u` UNSAFE by necessity** (bare token is unbound on legacy). Substitution and `:-`-safety are mutually exclusive for this token. Enforced negatively: Phase 3 adds a conformance assertion forbidding `set -u`/`set -euo` above a resolution fence. (Today zero skill `.md` fences use `set -u` — verified — so this codifies an existing invariant.)
- **F4 fix:** the else uses a guarded two-step fallback (not the inline `${CLAUDE_PROJECT_DIR:-$(…)}`) so a no-git + unset-env edge yields a clean error, never a `//.claude/...` double-slash.

---

## Phase 1 — Env-independent core + ONE end-to-end vertical slice (atomic; load-bearing)  [x]

The fence migration is the load-bearing fix (a self-locating script is useless if the fence can't source it), so Phase 1 ships a COMPLETE working slice for one skill, proven on a real mirror-less consumer, before the wide sweep.

- **Scripts (env-independent via BASH_SOURCE):**
  - `zskills-paths.sh:54-57`: derive `ZSKILLS_SKILLS_ROOT` from `$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../..` (script at `<skills_root>/update-zskills/scripts/`). Keep the `CLAUDE_PROJECT_DIR` git fallback for config reads only. Keep any `${CLAUDE_PLUGIN_ROOT:-}` reads `:-`-guarded (run under callers' `set -u`).
  - `zskills-resolve-config.sh:69-75`: source `zskills-paths.sh` as a `BASH_SOURCE`-relative sibling.
  - `verify-install-lib.sh` (NOTE: entry `verify-install.sh:32` runs `set -u`, so KEEP `${CLAUDE_PLUGIN_ROOT:-}` throughout — no bare token):
    - `vi_detect_lane`: detect **plugin** from the CONSUMER `--project-dir`'s on-disk **materialised sentinels** (reuse `vi_has_materialiser_sentinel` over the 5 artifacts) + absence of a `.claude/skills` mirror. **F2 fix: do NOT key the plugin signal on the verifier's own BASH_SOURCE location** — sourcing the lib from the dev tree (or any env-unset run) would then false-classify legacy/none as plugin and break `tests/test-verify-install.sh` cases 3c/3e/3f. Lane is a property of the consumer dir, not of where the lib lives. KEEP vocabulary `plugin|legacy|dual|none`; preserve `dual` (sentinels + populated `.claude/skills`) and `none`.
    - `vi_check_plugin` `plugin.root-reachable` (~line 428): resolve the plugin root from the verifier's own `BASH_SOURCE` (`verifiers/→update-zskills/→skills/→root`, 4 levels) **only after** lane==plugin is established by the sentinel check above. (On legacy `vi_check_plugin` isn't called, so the BASH_SOURCE root is never consumed off-plugin.)
- **Fence:** apply the new idiom to `skills/update-zskills/SKILL.md` only, this phase.
- **`references/canonical-config-prelude.md` §1 (F-Issue3):** §1 currently documents the OLD `:-`-guarded two-line form as the PREFERRED, "resolves correctly on both install lanes" idiom (~lines 37-65) — that claim IS the bug. REPLACE the §1 block AND its surrounding prose (drop the false both-lane-correct assertion), don't merely propagate it.

**Acceptance (must exercise a REAL fence guard, not a direct absolute source):**
- Against a real mirror-less materialised consumer with EMPTY env: a synthetic fence rendered as the harness would (bare token → absolute literal) sources resolve-config.sh successfully and `ZSKILLS_SKILLS_ROOT` resolves to a real dir.
- Real `claude --plugin-dir` mirror-less dispatch of `/zs:update-zskills` → verifier `lane: plugin`, `Overall: PASS`, **watched FAIL → PASS** (attended proof of harness substitution — see Phase 3 on CI vs attended).
- Legacy lane regression: resolution still works; `tests/test-verify-install.sh` legacy/none/de-hooked cases stay green (F2 guard).

## Phase 2 — Mechanical sweep across all remaining skills  [x]

- Apply the new idiom to all remaining fence sites. **Do NOT hard-code the counts** (the two reviewers disagreed by ±1–4): derive them at execution and report live numbers. Enumeration:
  - guard fence-lines: `grep -rcF -- '[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]' skills/ block-diagram/`.
  - distinct skills to version-bump: `grep -rlF -- '[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]' skills/ block-diagram/ | sed -E 's#.*/(skills\|block-diagram)/([^/]+)/.*#\2#' | sort -u`.
  - mirror files to re-sync: `grep -rlF -- '[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]' .claude/skills/`.
  (Indicative magnitudes: ~230–231 fence-lines, ~47–48 source files, 24 skills, ~49–53 mirror files — VERIFY by grep, don't trust the band.)
- **Handle ALL variants (one transform does not fit):**
  1. two-line dual-path guard, `-f` test, `. "…"` source (majority);
  2. single-line `:-`-default collapse — `skills/draft-plan/references/brainstorm.md:337` (`${CLAUDE_PLUGIN_ROOT:-$CLAUDE_PROJECT_DIR/.claude}`) + its mirror;
  3. **`-x` path-SELECTION fences — `skills/zskills-dashboard/SKILL.md:91,97`**: drop ONLY the `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] &&` first conjunct; **preserve the `[ -x … ]` test, the `VAR=…` assignment shape (not a `source`), and the `$MAIN_ROOT` else-anchor** (locally derived at :81-83, NOT `$CLAUDE_PROJECT_DIR`). A blind canonical-idiom transform here corrupts dashboard semantics.
  4. **~8 distinct target scripts** (also `zskills-paths.sh`, `zskills-stub-lib.sh`, `port.sh`, `sanitize-pipeline-id.sh`, `clear-tracking.sh`, `verify-install.sh`, …) — transform must be target-agnostic.
- Bump `metadata.version` per edited skill (`scripts/skill-content-hash.sh` + `frontmatter-set.sh`).
- **Re-mirror `skills/` → `.claude/skills/`** for every edited file (derive the set by grep) so `test-skill-conformance.sh` source/mirror byte-sync passes. Edit source only, then batch-cp.
- Re-render `managed.md` if affected. (CLAUDE_TEMPLATE.md needs no change — prose.)

**Acceptance:** zero remaining `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]`-guarded AND zero `${CLAUDE_PLUGIN_ROOT:-$…}`-default resolution fences in `skills/**`/`block-diagram/**`; dashboard `-x` fences retain `-x`+`$MAIN_ROOT`; source/mirror byte-sync; `bash tests/run-all.sh` green.

## Phase 3 — De-mask tests + conformance lock-in  [x]

- **De-mask `tests/test-plugin-mirrorless-resolution.sh`:** positive cases pre-`export CLAUDE_PLUGIN_ROOT` AND source the absolute path directly (case 5 `unset`s but still sources the absolute path), bypassing the fence. Add ≥1 case that renders a synthetic fence with the bare token substituted to the consumer's plugin path and NO pre-export, then runs THAT. **F5 honesty:** a shell-only test can only prove *shell self-bootstrap of an already-substituted fence* — it CANNOT prove the harness performs the substitution. State this; the real harness-substitution proof is the attended `tests/test-plugin-live-load.sh` (`ZSKILLS_LIVE_ATTENDED=1`) + manual `/zs:update-zskills` FAIL→PASS, which are NOT CI gates.
- **Conformance (`tests/test-skill-conformance.sh`):**
  - Add an assertion forbidding the `:-`-guarded / `:-`-default resolution forms in skill `.md`.
  - **Add an assertion forbidding `set -u`/`set -euo` above a resolution fence** (F1 — codifies the invariant the new idiom depends on).
  - **Resolve the existing fixture conflict:** the `syn-pass-dualpath` PASS fixture at `tests/test-skill-conformance.sh:~2667` contains the OLD form and would fail the new forbidding assertion — rewrite it (and any sibling synthetic case) to the new idiom in the SAME PR. The preamble detector keys on the `zskills-resolve-config.sh` substring, retained by the new idiom.

**Acceptance:** `bash tests/run-all.sh` green (command + per-suite counts); de-masked mirror-less test proves shell self-bootstrap; conformance forbids both broken forms AND `set -u`-above-fence; attended live-load FAIL→PASS captured (manual).

## Risks / notes
- Symlinked plugin cache → `readlink -f` in script self-location.
- New idiom is `set -u`-unsafe by necessity — the conformance assertion is the guardrail; without it a future `set -euo pipefail` reflex silently breaks the legacy lane.
- Diff looks large (24 version bumps + ~50 mirror files) but semantic surface = 3 scripts + 1 fence idiom + tests.
- Verifier self-located root is plugin-root ONLY on the plugin lane; consume it on the plugin path only.
- **Supersedes "plugin lane ready to ship"** — the lane is NOT consumer-ready until this lands.

## Drift Log

No completed phases — all 3 phases reviewed as remaining. Structural history of the plan document itself:

| Version | Change |
|---------|--------|
| v1 | Initial draft (3 phases; scripts-first framing; ~256/50 estimate). |
| v2 | Fresh-agent review folded in: phasing corrected (fence migration is load-bearing, not scripts); pinned the new idiom; enumerated 3 variants; verifier BASH_SOURCE + sentinel detection; de-mask; conformance-conflict; mirror re-sync; corrected numbers to 231/47/24. |
| v3 (this) | 1-round /refine-plan: **F1** set-u regression → conformance assertion forbidding `set -u` above fences (rejected the DA's "keep the `:-` guard" fix — verified it reintroduces the bug); **F2** verifier lane-detection keyed on consumer sentinels, NOT the verifier's own BASH_SOURCE (avoids dev-tree/env-unset false-positive that breaks test-verify-install.sh); **F4** guarded else fallback (no `//` double-slash); **F5** CI proves shell-bootstrap only, harness-substitution proof is attended; **Issue-1** added the `-x`/`$MAIN_ROOT` dashboard variant; **Issue-2** CLAUDE_TEMPLATE.md is prose → leave as-is; **Issue-3** §1 prelude documents the broken form as "preferred" → replace it; numbers de-hardcoded → grep-derived. |

## Plan Review

**Refinement process:** /refine-plan, 1 round (user-requested), reviewer + devil's-advocate + refiner, grounded in live code + the session's runtime probes.
**Convergence:** 1 round (user budget). All round-1 findings dispositioned (fixed or justified) in v3; a confirming round was not run (budget=1).
**Remaining concerns:** none unresolved. One finding was REJECTED on verify-before-fix grounds: the DA's F1 suggestion to "keep the `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]` precondition" — the probe (`COLONDASH_GUARD=false`) proves that conjunct is false on the plugin lane and short-circuits, reintroducing the very bug; adopted the DA's alternative (conformance assertion) instead.

### Round History
| Round | Reviewer | Devil's Advocate | Substantive | Disposition |
|-------|----------|------------------|-------------|-------------|
| 1 | 3 (1 med, 2 low) | 5 (2 critical, 3 med) | 8 | 7 fixed + 1 rejected-with-evidence (DA F1 "keep guard") |
