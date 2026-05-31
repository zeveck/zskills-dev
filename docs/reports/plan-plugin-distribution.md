# Plan Report — Plugin Distribution (Dual-Path)

> **PLAN COMPLETE** — all 6 phases ✅. Suite `6249/6249, 0 failed`. The dual-path
> distribution infrastructure + docs are landed on `feat/plugin-distribution`.
> **One human-gated step remains OUTSIDE this plan's PR:** the actual release
> publish (push `prod/main` + `prod/<version>` tags via `build-plugin-release.sh --push`,
> marketplace activation). All tooling is built and dry-run-verified; trigger the
> release per `RELEASING.md` when ready.

## Phase — 6 Marketplace activation docs + dual-path onboarding (README + PLUGIN_INSTALL.md)

**Plan:** docs/plans/PLUGIN_DISTRIBUTION.md
**Status:** Completed (verified) — FINAL phase
**Worktree:** /tmp/zskills-pr-plugin-distribution (branch `feat/plugin-distribution`)
**Commit:** 05aebeb

### Work Items
| # | Item | Status | Notes |
|---|------|--------|-------|
| W6.1 | `docs/guides/PLUGIN_INSTALL.md` | Done | 257 lines: side-by-side comparison, install/slash-prefix/update per lane, D26 default + tradeoff matrix, D1 pin idiom, D20(b) gitignore, marketplace promotion (doc-only), Known-tradeoffs bare-slash gap, switching-lanes pointer |
| W6.2 | `docs/guides/PLUGIN_MIGRATION.md` | Confirmed (Phase 5) | bidirectional, optional framing, both-direction Abort/Rollback — satisfactory, no augment |
| W6.3 | marketplace promotion | Documented only | human-gated; not executed |
| W6.4 | issue #432 closeout | n/a | already CLOSED |
| W6.5 | MW-EXAMPLE cleanup | n/a | absent everywhere (no-op tombstone) |
| W6.6 | README.md both lanes | Done | two-lane table + D26 default + link to PLUGIN_INSTALL.md; existing /update-zskills content preserved |

### Verification (proportionate to docs-only)
- Scope: `README.md` + new `docs/guides/PLUGIN_INSTALL.md` only. All required PLUGIN_INSTALL sections confirmed present. README references both lanes + links the install doc.
- Full suite: `6249/6249 passed, 0 failed`.
- No publish performed (no git push, no prod-tag, no marketplace activation).
- Surfaced (non-blocking): `block-unsafe-generic.sh` false-positives on `kill -0 $(pgrep ...)` liveness probes (no signal sent) — flagged as a framework refinement, not patched.

## Phase — 5 Dual-path hardening (plugin-mode CI, switch-install-path, release builder, shim fix)

**Plan:** docs/plans/PLUGIN_DISTRIBUTION.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-plugin-distribution (branch `feat/plugin-distribution`)
**Commit:** 63ef305 (landing deferred — finish-auto PR mode lands once after the final phase)

### Work Items
| # | Item | Status | Notes |
|---|------|--------|-------|
| W5.1 | plugin-mode CI lane (3 tiers) | Done | `.github/workflows/test.yml`; Tier 1 mandatory, Tier 2 best-effort, Tier 3 deferred |
| W5.2 | plugin.json version bump (D10) | Done | zs + zsbd → 2026.05.1 lockstep; marketplace test asserts equality |
| W5.3 | `/update-zskills --switch-install-path` sub-mode (D15) | Done | source + mirror byte-equal; version bumped |
| W5.5 | `scripts/build-plugin-release.sh` | Done | no self-delete; --push-gated; D3 template copy + D4 suffixless siblings; local dry-run strip = 0 hits |
| W5.6 | `scripts/switch-install-path.sh` bidirectional (D25) | Done | lock-LAST both directions; + `migrate-strip-settings.py`; file-removal proven sentinel/basename-gated |
| W5.7 | hook double-fire testbed (D16(a)) | Done | **caught + fixed a real Phase-1 shim bug** (BASH_SOURCE[0]→outermost frame) |
| W5.8/W5.9 | RELEASING.md + CLAUDE.md dual-path release/dogfood docs | Done | + `docs/guides/PLUGIN_MIGRATION.md` |
| W5.10 | issue closeout | n/a | no open plugin/distribution issue found |

### New tests
- `tests/test-switch-install-path.sh` (26 assertions, both directions non-interactive), `tests/test-plugin-hook-skip-on-double-register.sh` (14 assertions, 4 scenarios)

### Verification (fresh-eyes verifier, with 3 high-risk scrutiny points)
1. **File-removal safety** (switch-install-path.sh): PROVEN — every `rm` double-gated by sentinel OR shipped-basename match; consumer files + `.zskills/` preserved (tests assert).
2. **Shim BASH_SOURCE fix**: confirmed correct in BOTH plain-bash (frame pushed → `[last]`=hook) and claude-2.1.149 (depth-1 → `[0]==[last]`=hook); NOT a claude-harness regression; the old `[0]` silently no-op'd the guard under plain bash.
3. **build-plugin-release.sh**: no self-delete (script survives run), `--push`-gated (no remote push), strip set verified on local ref (0 hits), local refs cleaned up.
- Full suite: `6249/6249 passed, 0 failed`.

### Release-publish scope (IMPORTANT — human-gated, NOT done)
Per "execute actions with care," the actual release-publish actions were deliberately NOT performed autonomously: no `git push` of `prod/main` or `prod/<version>` tags, no marketplace activation. The infrastructure is built and dry-run-verified; triggering the release is a human decision (see Phase 6 note + RELEASING.md).

### Notes
- D16(a) plan-note corrected (the `${BASH_SOURCE[0]}` empirical claim was stale; updated to the shipped outermost-frame form).
- No UI changes — no user sign-off required.

## Phase — 4 Conformance test surface (0 retirements; 16 new stabilise; 2 restructured)

**Plan:** docs/plans/PLUGIN_DISTRIBUTION.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-plugin-distribution (branch `feat/plugin-distribution`)
**Commit:** e7575bb (landing deferred — finish-auto PR mode lands once after the final phase)

### Work Items
| # | Item | Status | Notes |
|---|------|--------|-------|
| W4.1 | 0 retirements | Done (confirm) | 9 `/update-zskills` tests + `test-hook-helper-drift.sh` all green + present |
| W4.2 | restructure `test-skill-conformance.sh` | Done | (a) dual-path sourcing form already covered (Phase 3 `syn-pass-dualpath`); (b) added 6-artifact materialiser-presence tripwire (+23 lines) |
| W4.3 | restructure version-enforcement trio | Confirmed already-satisfied (no edit) | line-2 `# zskills-hook-version:` stamp already covered in conformance test; version enforcement is lane-agnostic. Surfaced rather than churn passing tests. |
| W4.4 | 5-iteration stability | Done | 5 consecutive `bash tests/run-all.sh` → `6173/6173, 0 failed` each; no flakes |
| W4.5 | accounting | Done | delta `0 retired + 16 new + 3 restructured`; 14/16 new exist (2 are Phase 5); top-level test count 152 |
| W4.6 | forbidden-literals audit | Done (confirm) | deny-list clean against `tests/fixtures/forbidden-literals.txt` |

### Verification
- Orchestrator-side review (proportionate to a +23-line additive test change): diff reviewed (additive presence tripwire, weakens nothing), independent full-suite run `6173/6173 passed, 0 failed`, no failing suites.
- W4.3 was correctly NOT churned — the version-enforcement trio's only concrete D8 hook (line-2 hook-version stamp) is already covered; surfaced for plan-author confirmation rather than guess-editing passing tests.

### Notes
- No UI changes — no user sign-off required.
- Drift (informational): plan's absolute test-count orientation drifted (135 base → 152 now); the load-bearing +16/0/3 delta holds.

## Phase — 3 Dual-path recognition + cron-fire path-aware rules + script-path fallback + migrate-crons

**Plan:** docs/plans/PLUGIN_DISTRIBUTION.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-plugin-distribution (branch `feat/plugin-distribution`)
**Commit:** 9d22c48 (landing deferred — finish-auto PR mode lands once after the final phase)

### Work Items
| # | Item | Status | Notes |
|---|------|--------|-------|
| W3.1 | Per-site dual-path fallback (D6) | Done | 151 resolver-sourcing sites (44 files) + legacy script-path refs, source + `.claude/skills` mirror; re-grep = 0 unwrapped legacy-only sources |
| W3.2 | `references/canonical-config-prelude.md` two-line form preferred | Done | legacy not deprecated, no deadline |
| W3.3 | Cron-fire rule OR-match + dual SKILL.md path (D12/D12-prose) | Done | `CLAUDE_TEMPLATE.md`; managed.md re-rendered via Phase-2 renderer |
| W3.4 | `skills/migrate-crons/SKILL.md` (D13, OPTIONAL) | Done | mirrored; description trimmed to fit budget |
| W3.5 | conformance accepts both sourcing forms | Done | |
| W3.6 | `tests/test-skill-frontmatter-survival.sh` (F-DA2-6 gate) | Done | has negative control |
| W3.7 | version bump touched skill dirs (D22) | Done | 24 dirs, source + mirror equal |

### Verification
- Phase-3 review agent (fresh eyes) confirmed all work items; **found + fixed a real regression** the implementer missed: migrate-crons' 590-byte description broke `test-skill-description-budget.sh` (over the 7500 cap). Clean-main check confirmed it was migrate-crons-caused, not pre-existing; trimmed to 290 bytes, re-bumped version.
- Worktree rebased onto current `origin/main` (which had advanced to `a59444d`), pulling commit `8179288` (#766).
- **Full suite: `Overall: 6167/6167 passed, 0 failed`.** ZERO failures.

### CORRECTION — the Phase 2 "pre-existing failures" claim was FALSE
Phase 2's report (below) originally stated "suite 6110/6112 (2 pre-existing)". The user challenged this; investigation proved it wrong. Both `test_zskills_monitor_collect.sh` (73/73) and `test_plans_rebuild_uses_collect.sh` (20/20) **pass on clean main** — they were never pre-existing failures. Real causes (both worktree-environment artifacts, NOT Phase 2 code regressions):
1. **monitor-collect** — the worktree branch (based at 6a5c590) was missing upstream `8179288`/#766, which strips the volatile `claim.age_seconds` from a worktree-portability byte-check; the failure fired because /run-plan holds a plan claim. Fixed by rebasing onto origin/main.
2. **plans-rebuild** — a stale gitignored `.zskills/audit/PLAN_INDEX.md` cache (listing archived canary plans). Fixed by regenerating the cache.
The root process failure: the verification baseline was captured *inside the stale/contaminated worktree* and the false "pre-existing" framing propagated. Future phases must check suspect failures against clean main before any "pre-existing" classification.

### Notes
- No UI changes — no user sign-off required.
- Description budget now at 7453/7500 (WARN band) — future skill additions need trimming.
- Advisory (not blocking): 4 legacy `.claude/skills/update-zskills/scripts/` refs remain unconverted (out of W3.1's strict scope — printed hint strings / dashboard bespoke bootstrap / update-zskills-lane-only tools). Most notable: `skills/run-plan/modes/execute-phase.md` `clear-tracking.sh` user-facing hint prints a legacy path on the plugin lane — candidate follow-up.

## Phase — 2 SessionStart materialiser + dual-install detection + renderer equivalence

**Plan:** docs/plans/PLUGIN_DISTRIBUTION.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-plugin-distribution (branch `feat/plugin-distribution`)
**Commit:** f750100 (landing deferred — finish-auto PR mode lands once after the final phase)

### Work Items
| # | Item | Status | Notes |
|---|------|--------|-------|
| W2.1 | `hooks/session-start-materialise.sh` (5 artifacts, D27 probe-first, D20(a) overwrite guard) | Done | f750100 |
| W2.2 | `scripts/managed_rules_substitution.py` + `scripts/render-managed-rules.py` (D24 single renderer) | Done | substitution map lifted verbatim from inlined dict |
| W2.3 | Template-bundling read-order fallback (consumer CLAUDE_TEMPLATE.md → plugin copy) | Done | release-time copy is W5.5 |
| W2.4 | `tests/test-hook-template-sibling.sh` (D4 byte-equality when both exist) | Done | tolerates absent sibling |
| W2.5 | Plugin hook self-references (`resolve_src` dual-path) | Done | |
| W2.6 | Root `CLAUDE.md` dual-path dogfood-loop prose | Done | |
| W2.7 | Port `/update-zskills` Step B/D to Python renderer + equivalence gate + version bump | Done | LLM-prose deleted; `metadata.version`→2026.05.28+174af3 |
| W2.8 | `hooks/_lib/detect-install-state.sh` (`detect_install_state()` 4 lanes, D27) | Done | |

### New files
- `hooks/session-start-materialise.sh`, `hooks/_lib/detect-install-state.sh`
- `scripts/managed_rules_substitution.py`, `scripts/render-managed-rules.py`
- 8 new tests: `test-sessionstart-materialise.sh`, `test-sessionstart-materialise-overwrite-guard.sh`, `test-sessionstart-dual-install-detect.sh`, `test-render-managed-rules-correctness.sh`, `test-managed-md-renderer-equivalence.sh` (A11 gate), `test-inject-bash-timeout-parity.sh`, `test-verify-response-validate-parity.sh`, `test-hook-template-sibling.sh`

### Verification
- Test suite (`bash tests/run-all.sh`): 6110/6112 passed, 2 failed at the time. ⚠️ **CORRECTION (see Phase 3 section above): the "pre-existing" characterization of `test_zskills_monitor_collect.sh` and `test_plans_rebuild_uses_collect.sh` was FALSE.** Both pass on clean main; they were worktree-staleness artifacts (missing #766 + stale gitignored cache), since fixed. Suite is 6167/6167 green after Phase 3.
- A11 renderer-equivalence gate: PASS, non-trivial (Path A no-sentinel vs Path B sentinel-stripped, 5 fixture configs).
- `test-managed-md-up-to-date.sh` refactor verified meaningful (renders + diffs, not a no-op); `test-update-zskills-rerender.sh` stays green.
- `test-hooks-mirror-parity.sh` exclusion of `session-start-materialise.sh` verified LEGITIMATE — it is a plugin-lane-only hook with no `/update-zskills` mirror by design (legacy lane writes the 5 artifacts directly at install).
- Acceptance criteria A3/A4/A11/A12: met.

### Notes
- No UI changes — no user sign-off required.
- Drift: implementer's PLAN-TEXT-DRIFT token referenced the test-suite baseline count passed in the dispatch prompt (6053/6055 → actual 6055/6057), not a plan-file acceptance criterion; no plan correction needed. Verifier independently found zero plan-file drift.
