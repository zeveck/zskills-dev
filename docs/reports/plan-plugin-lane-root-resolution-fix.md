# Plan Report — Plugin-Lane Root Resolution Fix

**Plan:** `docs/plans/PLUGIN_LANE_ROOT_RESOLUTION_FIX.md`
**Status:** ✅ COMPLETE (all 3 phases) — 2026-06-03
**Landing:** PR #1046 (squash-merged to `main` @ `5c8fc9a`)
**Mode:** `/run-plan … finish auto` (PR mode, `main_protected: true`), one accumulating PR per plan.

## Outcome

The CRITICAL plugin-lane root-resolution bug is fixed and the lane is verified working on a real **mirror-less** plugin consumer. Pre-fix, every `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/…" ]` fence short-circuited false mirror-less (the harness substitutes only the bare token, never the `:-` form, and the var is absent from launched-script env) → `ZSKILLS_SKILLS_ROOT` unset → ~200 call sites broke; the verifier reported false `lane=none FAIL` (#1026). Masked for the project's life by the dev repo's `.claude/skills/` mirror.

## Phases

| Phase | Scope | Result |
|-------|-------|--------|
| 1 — Env-independent core + vertical slice | `zskills-paths.sh` (+`resolve-config.sh`) self-locate via `BASH_SOURCE`/`readlink -f`; `verify-install-lib.sh` `vi_detect_lane` re-keyed onto consumer materialised sentinels (F2); `update-zskills/SKILL.md` 13 fences + `references/canonical-config-prelude.md` §1 migrated | ✅ committed; suite 7585/7585; hard gate PASS |
| 2 — Mechanical sweep | new fence idiom across 24 skills / ~243 fence sites (majority scripted; `draft-plan/brainstorm` `:-`-default + `zskills-dashboard` `-x` by hand); 51 source + 51 mirror; per-skill `metadata.version` bumped | ✅ (coupled with Phase 3) |
| 3 — De-mask + conformance | 11 fence-extraction harnesses de-masked faithfully (bind `CLAUDE_PLUGIN_ROOT` empty under their injected `set -u` → legacy else-branch; no real-path masking); new conformance assertions forbid the `:-`-guarded / `:-`-default resolution forms AND `set -u` above a resolution fence in skill `.md` (proven by FAIL+PASS fixtures); `syn-pass-dualpath` fixture rewritten | ✅ committed; suite 7601/7601 |

Phases 2 and 3 are structurally coupled: the sweep makes the suite red until the harnesses are de-masked, so they landed together in one PR. Phase 1's vertical slice landed in the same PR's first commit.

## Verification (hard gate — orchestrator-run at top level)

- **Baseline FAIL (pre-fix):** mirror-less consumer + harness-rendered fence → `ZSKILLS_SKILLS_ROOT=UNSET` (deterministic).
- **Live FAIL→PASS (post-fix):** real `claude --plugin-dir` mirror-less dispatch of `/zs:update-zskills` → **`Install lane: plugin`**; SessionStart materialiser wrote the 5 artifacts; `managed.md` rendered with no leftover `{{TOKEN}}` placeholders.
- **Bundled verifier (mirror-less consumer):** `lane.detect → plugin`, `plugin.mirror-less PASS`, `plugin.root-reachable PASS`, all 5 artifact sentinels → **8 PASS, 0 WARN, 0 FAIL — Overall: PASS**.
- **Re-confirmed on merged main (`5c8fc9a`):** same live dispatch + bundled verifier → Overall: PASS.
- `test-plugin-live-load.sh` (attended) 7/7; legacy regression `test-verify-install.sh` 29/29.
- Full suite: **`Overall: 7601/7601 passed, 0 failed`**.

## Notes / follow-ups

- The attended `ZSKILLS_LIVE_ATTENDED=1 bash tests/test-plugin-live-load.sh` + manual `/zs:update-zskills` FAIL→PASS remain non-CI gates (per plan F5); both were exercised GREEN this session.
- Filed in passing: issue #1037 (`block-unsafe-generic.sh` push-target extraction not `git -C <dir>` aware — self-blocks `/land-pr` Step 6b). Not part of this plan.
