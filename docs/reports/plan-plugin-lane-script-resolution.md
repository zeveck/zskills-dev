# Plan Report — Plugin-lane script resolution + dual-install hardening

## Phase — 4 Family 3: fix mirror-path refs inside bundled scripts

**Status:** Completed (verified) — commit `d29be66`
- W4.1: 3 runtime-reached mirror sources (post-run-invariants.sh, backfill x2) + 2 stub-lib sites fixed with `$(dirname BASH_SOURCE)`-relative resolution (mirror fallback). Already-relative scripts (claim-plan/claim-issue) left.
- Source-guard: `zskills-paths.sh:57` `$CLAUDE_PROJECT_DIR` → `${CLAUDE_PROJECT_DIR:-}` (Phase-1 latent unbound-var-under-set-u, strictly safe).
- W4.2: 4 skill dirs bumped, mirror byte-equal. Verifier caught + fixed a Tier-1 registry obligation (new blob hashes → tier1-shipped-hashes.txt). Final suite 6560/6560.
- **Carry-forward:** any phase editing a Tier-1 script must register its new blob hash in tier1-shipped-hashes.txt + re-bump update-zskills, same commit.

## Phase — 3 Family 2: migrate bundled-script `.md` invocations

**Status:** Completed (verified) — commit `ac29a24`
- W3.1: 161 bundled-script invocations → `$ZSKILLS_SKILLS_ROOT/<owner>/scripts/<x>`; EXCLUSION grep after = 0; legacy config-helper source lines (238) preserved (chicken-and-egg intact).
- W3.2: 15 path-prefix sites → `$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/<x>`.
- W3.3: 49 bootstraps added to executable fences; 3 illustrative doc-example fences left (placeholder args).
- W3.4: 15 test assertion/anchor updates (lockstep, NONE weakened — independently confirmed); hooks denylist assertion untouched.
- W3.5: 22 skill dirs bumped, mirror byte-equal. Full suite 6560/6560.
- Drift: plan estimates (~144/~39/10) were undercounts; actual 161/49/15. No missed work (EXCLUSION grep=0 is the completeness check).

## Phase — 2 Family 1: repoint config-helper `.md` sources

**Status:** Completed (verified) — commit `e3125f3`
- W2.1: 336→0 wrong-form plugin-branch refs (rewritten to `${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/`); legacy `else` byte-identical.
- W2.2/W2.3: 23 skill dirs, mirror byte-equal, per-skill version bumps (hash-matched). Full suite 6560/6560.

## Phase — 1 Foundation: corrected primitives + spec + conformance fixtures

**Plan:** docs/plans/PLUGIN_LANE_SCRIPT_RESOLUTION.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-plugin-lane-script-resolution (branch `feat/plugin-lane-script-resolution`)
**Commits:** 425d03f (impl), e460b5f (tracker)

### Work Items
| # | Item | Status |
|---|------|--------|
| W1.1 | `ZSKILLS_SKILLS_ROOT` export in zskills-paths.sh (legacy anchored on CLAUDE_PROJECT_DIR) | Done |
| W1.2 | resolve-config sources paths.sh (re-exports the var) via corrected bootstrap | Done |
| W1.3 | canonical-config-prelude.md repointed (grep-clean: 0 wrong paths) | Done |
| W1.4 | syn-pass-dualpath conformance fixture corrected | Done |
| W1.5 | tests/test-zskills-skills-root.sh (5 cases incl. DA#1 regression guard), wired into run-all.sh | Done |
| W1.6 | update-zskills metadata.version bumped (2026.05.30+7bb753), source↔mirror byte-equal | Done |

### Verification
- Full suite: `Overall: 6560/6560 passed, 0 failed` (baseline 6555 + new test; zero regressions). Verified by a separate verifier agent; Layer-3 response validation exit 0.
- Scope clean (exactly the Phase-1 files); mirror parity green; canonical-prelude grep-clean.
- `test-skill-version-enforcement.sh` sandbox fix (W1.2 made resolve-config source paths.sh) — fixture-completeness, NOT a weakening.

### Notes
Foundation phase — establishes the corrected lane-portable primitives + spec the family-1/2/3 migrations (Phases 2–4) apply. No reference sites rewritten yet.
