---
title: Plugin-Lane Verification — pre-launch gap-closing
created: 2026-05-29
status: active
---

# Plan: Plugin-Lane Verification — pre-launch gap-closing

## Overview

The plugin-distribution lane landed via PR #799 (dual-path migration). zskills
launches with BOTH install lanes (legacy `/update-zskills` AND the plugin lane
via `claude --plugin-dir .`), so the plugin lane needs pre-launch verification.

A read-only inspection mapped the shipped lane against the
`docs/plans/PLUGIN_DISTRIBUTION.md` contracts and found it **already
well-covered**: D4 (`test-hook-template-sibling.sh`), D11
(`test-sessionstart-materialise*.sh`), D16(a) skip-shim
(`test-plugin-hook-skip-on-double-register.sh`), D24 renderer-equivalence
(`test-managed-md-renderer-equivalence.sh`), and manifest/marketplace
structure (`test-plugin-{manifest,marketplace,self-load}.sh`) all ship with
tests. **This plan does NOT re-test those** — it closes the narrow set of
genuine gaps the inspection surfaced.

Scope: 3 additive static smokes (fail-closed gaps in existing coverage) +
one live dual-lane behavioral validation (the `claude` CLI is available, so
it is RUNNABLE, not a paper canary) + a synthetic-consumer legacy-installer
migration test. The plan also confirms (does NOT fix) three rough edges an
active audit is currently addressing.

**Non-goals (explicit):** do not re-test the already-covered contracts; do
not fix the rough edges (the audit owns them); no Layer-3/LLM-judgment
verification; no markdown "canary" that rots — every check is a runnable
shell test with a pass/fail line, or it is explicitly labeled an attended
one-shot with a runnable harness.

## Progress Tracker
| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Static smokes: hooks.json↔script gate, shim-sourcing, D3 fallback | ⬚ | | |
| 2 — Live dual-lane behavioral validation (claude --plugin-dir .) | ⬚ | | |
| 3 — Synthetic-consumer legacy-installer migration (D27 dual-install) | ⬚ | | |

## Conventions all phases follow

(Same house style as the rest of `tests/`; confirmed against
`test-plugin-self-load.sh`, `test-sessionstart-materialise.sh`,
`test-hooks-mirror-parity.sh`.)

- Harness boilerplate: `set -u`; `pass`/`fail` helpers incrementing
  `PASS_COUNT`/`FAIL_COUNT`; final **`Results: N passed, M failed`** line
  (load-bearing — `run-all.sh:36` greps it); exit non-zero on any failure.
- Register each new `tests/test-*.sh` in `tests/run-all.sh` (the
  `run_suite` block; plugin suites cluster around lines 206-226 post-#831 —
  grep the landmark, the count shifts as suites are added).
- Sandboxing: `TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT`. NEVER write
  into the real repo, the real `$HOME`, or the real `~/.claude`.
- **No jq** — Python 3 stdlib `json` or bash regex (`BASH_REMATCH`).
- Parse `hooks/hooks.json` with Python stdlib `json` (it is real JSON), not
  bash regex — the registered-command strings contain `${CLAUDE_PLUGIN_ROOT}`
  and shell punctuation that a regex would mangle.
- These phases add ONLY `tests/` files + a `run-all.sh` edit → no SKILL.md
  touched → no `metadata.version` bump and no `.claude/skills/` mirror.
- The `claude` CLI is present (v2.1.157, `claude plugin` subcommand works);
  Phase 2 may rely on it but MUST degrade to a clean SKIP (not a fail) if it
  is absent on another machine (mirror `test-plugin-self-load.sh`'s
  CLI-absent SKIP pattern).

## Phase 1 — Static smokes: hooks.json↔script gate, shim-sourcing, D3 fallback

### Goal
Add three fail-closed static assertions covering gaps the inspection found
in existing plugin coverage, as one new `tests/test-plugin-hooks-integrity.sh`.

### Work Items
- [ ] **Gap 1 — hooks.json registered-script existence/sibling gate.** Parse
  `hooks/hooks.json` (Python stdlib `json`), extract every registered hook
  command, and resolve each to a `${CLAUDE_PLUGIN_ROOT}`-relative script
  path. For each, assert ONE of: (a) the script file exists in-tree, OR
  (b) a committed `<script>.template` sibling exists (the D4
  release-time-generated suffixless case — `block-unsafe-project.sh`,
  `block-agents.sh`). FAIL if a registered script is neither present nor a
  `.template` sibling. (Today nothing fails-closed on a dangling
  hooks.json entry — this closes that.)
- [ ] **Gap 2 — shim-sourcing assertion.** For every `hooks.json`-registered
  `*.sh` that exists in-tree, assert it SOURCES
  `hooks/_lib/plugin-hook-skip-if-mirrored.sh` (grep the source line) —
  EXCEPT a named exclusion list. A hook missing the shim double-fires when
  both lanes are installed; conformance checks the version stamp but NOT
  shim-sourcing, so this closes that.
  **Named exclusions (verified during review — these legitimately do NOT
  source the shim and MUST be excluded or the test false-FAILs):**
  - `session-start-materialise.sh` — a SessionStart hook with its OWN
    dual-install probe (`detect-install-state.sh`), not a double-fire-prone
    PreToolUse hook (`grep plugin-hook-skip-if-mirrored
    hooks/session-start-materialise.sh` → 0 matches; this is correct).
  - The `.template`-only D4 pair (`block-unsafe-project.sh`,
    `block-agents.sh`) — not present as `*.sh` in-tree; instead assert their
    `.template` files source the shim (verified: both `.template`s contain
    the source line), so the release-generated siblings will too.
  Build the exclusion list explicitly by name with rationale (mirror Gap-1's
  named `.template` allow-list) so a future hook that genuinely forgets the
  shim still FAILS. **(refine 2026-05-31, finding C1): there are exactly SEVEN
  in-tree `block-*.sh`** (`block-bad-cron`, `block-bypassed-land-pr`,
  `block-fix-issue-unclaimed`, `block-main-edits`, `block-run-plan-unclaimed`,
  `block-stale-skill-version`, `block-unsafe-generic`) + `warn-config-drift.sh`
  — these all source the shim today and must stay asserted. (`block-agents.sh`
  + `block-unsafe-project.sh` are the `.template`-only pair excluded above —
  do NOT count them in the in-tree set; the draft's "8" was internally
  contradictory with its own exclusion list.)
- [ ] **Gap 3 — D3 bundled-fallback branch (in the MATERIALISER, not the
  renderer).** Review verified the prefer-consumer-then-bundled fallback lives
  in `hooks/session-start-materialise.sh` (grep `elif [ -f
  "$PLUGIN/CLAUDE_TEMPLATE.md"` — post-#831 it's ≈ lines 303-322, NOT the
  draft's stale 228-231; **grep the landmark, don't trust the number**), NOT
  in `scripts/render-managed-rules.py` (a pure `--template <path>` consumer
  with no fallback — do NOT target it). **(refine 2026-05-31, finding H3):
  the CONSUMER-PRESENT branch is ALREADY covered** — `test-sessionstart-materialise.sh`
  copies a consumer `CLAUDE_TEMPLATE.md` and asserts managed.md renders from
  it. The genuine gap is the **consumer-ABSENT → `$PLUGIN` bundled-fallback
  branch**, which NO existing test exercises (`grep 'PLUGIN/CLAUDE_TEMPLATE'
  tests/test-sessionstart-*.sh` → 0). So implement ONLY that branch: in a
  tmpdir with a fake `$PLUGIN` and NO consumer `CLAUDE_TEMPLATE.md`, assert the
  bundled copy is chosen (sentinel line). Do NOT re-build the present-branch
  test (duplicate coverage). Read `session-start-materialise.sh` first to
  confirm the `$PROJ`/`$PLUGIN` wiring and whether the block runs in isolation
  or needs the surrounding probe stubbed.
- [ ] Register `tests/test-plugin-hooks-integrity.sh` in `tests/run-all.sh`.
- [ ] Run `bash tests/run-all.sh`; confirm the new suite appears, passes, and
  the `Overall:` tally rises by the new case count with zero regressions.
  **Also assert `run-all.sh`'s exit code is 0** (some suites — e.g.
  `test-skill-description-budget.sh` — fail via exit code without emitting a
  `failed` line; the `Overall:` line alone is necessary but not sufficient).

### Design & Constraints
- Parse `hooks.json` with Python `json` (see Conventions). The registered
  command typically looks like
  `bash ${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh`; extract the basename after
  `hooks/` and before any args.
- Gap 1's `.template`-sibling allowance MUST be explicit and named, not a
  blanket "or skip" — list which basenames are permitted to be
  `.template`-only (derive from D4: the two consumer-customizable hooks) so a
  future genuinely-dangling entry still fails.
- Gap 2: the `.template`-only pair can't be grepped as `*.sh`; assert the
  `.template` file sources the shim instead, so the generated sibling will too.
- All three are pure static/hermetic — no network, no real `claude`, no
  real `$HOME`.

### Acceptance Criteria
- [ ] `tests/test-plugin-hooks-integrity.sh` exists, emits the canonical
  `Results:` line, exits non-zero on failure, is registered in `run-all.sh`.
- [ ] Gap-1 assertion FAILS if `hooks.json` is pointed at a fabricated
  nonexistent script with no `.template` (prove the fail-closed during dev
  against a tmpdir copy, then assert against the real tree → pass).
- [ ] Gap-2 assertion FAILS if a registered hook's shim-source line is
  removed (prove against a tmpdir copy).
- [ ] Gap-3 asserts BOTH fallback branches (consumer-present, consumer-absent).
- [ ] `bash tests/run-all.sh` exits 0; tally rises by new cases; no regression.

### Dependencies
None.

## Phase 2 — Live dual-lane behavioral validation

### Goal
Validate the plugin lane under a real `claude --plugin-dir .` invocation,
split honestly into (i) a CI-gateable part — load `validate` exit-0 +
graceful-degradation on the `.template`-only hooks (net-new over the
parse-only `test-plugin-self-load.sh`) — and (ii) an ATTENDED one-shot —
hook-fire + dual-lane double-fire prevention, which review CONFIRMED cannot
run in unauthenticated CI (`claude -p` requires login; isolated HOME has no
creds → "Not logged in"). Be honest: the recurring-CI delta is the
graceful-degradation check; the behavioral hook-fire validation is a
pre-launch attended run, not a CI gate.

**Net-new value statement (review F5 — record so this isn't mistaken for a
redundant test):** `test-plugin-self-load.sh` already does parse-level
`claude plugin validate --strict`. This phase adds ONLY: (a) graceful
degradation — a `--plugin-dir .` load from the source tree (where the two
D4 suffixless hooks don't exist yet) does NOT fatally error; and (b) a
runnable, explicit-PASS/FAIL attended harness for real hook-firing + the
real dual-lane skip-shim path, to be run once before launch. If during
implementation (a) turns out to be already covered or not observable via
any non-interactive command, say so and reduce Phase 2 to the attended
harness alone (do not pad it).

### Work Items
- [ ] Add `tests/test-plugin-live-load.sh`. Preamble: if `command -v claude`
  fails OR `claude plugin --help` fails → print `Results: 0 passed, 0 failed`
  + a `SKIP: claude CLI unavailable` line and exit 0 (mirror
  `test-plugin-self-load.sh`'s SKIP pattern). Never fail on CLI-absent.
- [ ] **Hermetic env setup.** In `mktemp -d`: create an isolated `HOME` and
  `XDG_CONFIG_HOME` (so the real `~/.claude` is never touched), and a
  throwaway project dir. Point the plugin at the REAL repo via
  `--plugin-dir "$REPO_ROOT"` (read-only; the plugin dir is not written to)
  OR a fresh `git clone` of the repo into the tmpdir if `--plugin-dir`
  mutates its target (verify which during implementation — read
  `claude plugin --help` and test before relying on either).
- [ ] **Load assertion (deterministic, CI-gateable):** run
  `claude plugin validate .` with the isolated env; assert **exit 0 and the
  "Validation passed" output** — do NOT assert the literal tokens `zs`/`zsbd`
  appear (review F4 verified `validate` prints only "✔ Validation passed",
  it does NOT name the plugins). If plugin-name recognition is wanted,
  investigate `claude plugin details <name>` as a separate non-interactive
  command; if it too requires auth, drop name-recognition and keep exit-0.
- [ ] **Hook-fire assertion — ATTENDED one-shot (review F5: NOT CI-runnable).**
  Review verified `claude -p "<prompt>" --plugin-dir .` with isolated HOME
  prints `Not logged in · Please run /login` and exits WITHOUT running the
  prompt — so PreToolUse hooks never fire headlessly in an unauthenticated
  sandbox. Therefore ship this as a clearly-labeled runnable function
  `run_attended_hookfire_check` guarded behind `ZSKILLS_LIVE_ATTENDED=1`
  that the CI path SKIPS (records "skipped: attended-only, headless auth
  unavailable") and a human runs once before launch in an authed env. The
  function asserts an observable hook side-effect (e.g. a deny-envelope on a
  known-blocked command, or a marker a hook writes) and prints explicit
  PASS/FAIL — never faked, never prose-only. Do NOT pretend this is a
  recurring CI gate.
- [ ] **Both-lanes skip-shim real-session check:** the existing
  `test-plugin-hook-skip-on-double-register.sh` simulates the shim with fake
  hooks/settings. This phase's incremental value is asserting the shim's
  behavior under a REAL dual-install (plugin loaded via `--plugin-dir` AND a
  mirrored `.claude/hooks/` copy registered in an isolated consumer
  `settings.json`), confirming the consumer-lane hook fires and the plugin
  copy defers exactly once. Same feasibility gate as the hook-fire check: if
  it can't be made deterministic headlessly, ship it as the same attended,
  flag-guarded, explicit-PASS/FAIL function.
- [ ] **Graceful-degradation check (rough edge c — CONFIRM, do not fix):**
  from the source tree (where the D4 suffixless `block-unsafe-project.sh` /
  `block-agents.sh` do NOT yet exist — only `.template`), assert that a
  `claude --plugin-dir .` load does NOT hard-error on the two missing
  registered hooks (the harness should simply not run them). If the live
  load errors fatally on missing hook scripts, that is a real finding →
  record it in the phase report and STOP for the audit (do not fix here).
- [ ] Register `tests/test-plugin-live-load.sh` in `tests/run-all.sh`.

### Design & Constraints
- **Isolation is mandatory.** Export `HOME="$TMP/home"`,
  `XDG_CONFIG_HOME="$TMP/home/.config"`, and any `CLAUDE_CONFIG_DIR` the CLI
  honors, BEFORE invoking `claude`, so the test cannot read or mutate the
  developer's real config, credentials, or installed plugins. Verify the
  correct isolation env var by reading `claude` docs / `claude --help`
  during implementation; if isolation cannot be guaranteed, the whole live
  phase SKIPs rather than risk touching real state.
- **Auth/network:** `claude -p` may require auth/network. If the headless
  invocation needs credentials not present in the isolated env, the
  hook-fire sub-check SKIPs (not fails) — record "skipped: headless auth
  unavailable" in the report. The load/validate assertion (parse-level)
  should work offline.
- **No real PR/dispatch, no `gh`, no writes outside `$TMP`.**
- Confirm rough edge (c) here as an acceptance check, not a fix.

### Acceptance Criteria
- [ ] `tests/test-plugin-live-load.sh` exists, registered, SKIPs cleanly when
  `claude` is absent (exit 0, `0 passed, 0 failed`, explicit SKIP line).
- [ ] When `claude` is present: `claude plugin validate .` exits 0 +
  "Validation passed" (NOT a zs/zsbd token grep — see F4).
- [ ] Hook-fire + dual-lane sub-checks are ATTENDED `ZSKILLS_LIVE_ATTENDED=1`
  functions with explicit PASS/FAIL output (CI SKIPs them with a recorded
  reason) — never faked, never prose-only, never claimed as CI gates.
- [ ] Graceful-degradation: source-tree load does not fatally error on the
  two `.template`-only hooks (or the finding is recorded + surfaced).
- [ ] Isolated HOME/XDG proven: the test writes nothing under the real
  `~/.claude` (assert by snapshotting/ignoring — e.g. the harness only ever
  references `$TMP`).
- [ ] `bash tests/run-all.sh` exits 0; no regression.

### Dependencies
None (independent of Phase 1).

## Phase 3 — Synthetic-consumer legacy-installer migration (D27 dual-install)

### Goal
Exercise the legacy `/update-zskills` install flow end-to-end into a
throwaway consumer dir and confirm it still works in the dual-lane world.
**Scope correction (review F3): the dual-install DETECTION + materialiser-
declines-to-clobber assertion is ALREADY covered** by
`tests/test-sessionstart-dual-install-detect.sh` (verified: its case 4 is
`dual → detect == dual; materialiser EXITS EARLY, does NOT materialise`).
So this phase does NOT re-assert detection — its net-new scope is the
END-TO-END legacy-installer-into-a-throwaway-consumer run (the original
effort's "Phase 8 synthetic-consumer migration"), which the unit-level
probe test does not exercise.

### Work Items
- [ ] **First, confirm the redundancy (F3):** read
  `tests/test-sessionstart-dual-install-detect.sh` and confirm it covers the
  `dual → no-clobber` contract. If it does (expected), this phase does NOT
  duplicate it — record "detection covered by existing test" and scope to the
  installer run below. If a coverage gap remains, note it precisely.
- [ ] **No standalone installer script exists (reviewer F3):** the legacy
  install flow is SKILL.md prose; the existing `tests/test-update-zskills-*.sh`
  (agent-install, migration, paths-migration, rerender, version-surface)
  **transcribe the SKILL.md bash blocks into oracle functions** (e.g.
  `run_step_c_install` in `test-update-zskills-agent-install.sh`). REUSE that
  oracle-function scaffold — do NOT invent an `install.sh`. Read those tests
  first to learn the sandbox-bootstrap pattern.
- [ ] Add (or extend) a test that, in `mktemp -d`, bootstraps a throwaway
  consumer repo and runs the legacy install oracle end-to-end into it
  (mirror/skill copy, hook registration in a synthesized `.claude/settings.json`,
  `managed.md` render), asserting the consumer ends up with a working legacy
  install. This is the genuinely net-new coverage.
- [ ] Decide test placement: a net-new `tests/test-synthetic-consumer-install.sh`
  if the existing tests don't already do the full end-to-end, OR extend the
  closest existing one. Note the choice + rationale in the report. Register
  any new file in `run-all.sh`.
- [ ] Run `bash tests/run-all.sh`; **exit 0** (not just `Overall:` 0-failed),
  no regression.

### Design & Constraints
- Sandbox only; never run the installer against the real repo or real `$HOME`.
- This is the original effort's "Phase 8 (synthetic-consumer migration)".
- The D27 detection logic lives in `hooks/_lib/detect-install-state.sh`
  (sourced by `session-start-materialise.sh` — grep the source line, ≈68
  post-#831, NOT the draft's ~49), NOT inline in the materialiser — read the
  `_lib` file if you need the detection contract.
- **Rough-edge re-baseline (refine 2026-05-31 vs post-#831 source):**
  - **(a) stale shim header comment — STILL PRESENT, keep as observation.**
    `hooks/_lib/plugin-hook-skip-if-mirrored.sh:16` (and :57) still describe
    `${BASH_SOURCE[0]}` while the actual code at line 65 uses the OUTERMOST
    entry (`${BASH_SOURCE[${#BASH_SOURCE[@]}-1]}`). #831 didn't touch the shim.
    Record as a doc-comment-vs-code mismatch; not fixed by this plan.
  - **(b) switch-install-path WARN text — RESOLVED by #831 → convert to a
    REGRESSION ASSERTION.** The two materialiser dual-install WARN sites
    (`session-start-materialise.sh:76,82`) now consistently say "run
    `scripts/switch-install-path.sh` to pick one lane (--to-plugin /
    --to-update-zskills)". (The shim's line-144 skew-WARN uses different
    wording but is a DIFFERENT hook for a DIFFERENT condition — version-skew,
    not dual-install — so it's not an inconsistency.) Since it's fixed, add a
    small static assertion that the two materialiser WARN sites stay
    consistent (a regression guard), rather than a "confirm-the-edge" note.
  - **(c) suffixless hooks only post-release-build — STILL PRESENT, keep as
    observation** (the graceful-degradation check in Phase 2 covers it).
- **`scripts/switch-install-path.sh` NOW EXISTS** (+ `tests/test-switch-install-path.sh`
  registered in run-all.sh) — drop the draft's "may not exist (Phase-5/D25)"
  hedge; the regression assertion in (b) tests it as present.

### Acceptance Criteria
- [ ] A test runs the legacy install oracle end-to-end into a throwaway
  consumer dir and asserts a working legacy install results. (Dual-install
  DETECTION is NOT re-asserted here — covered by
  `test-sessionstart-dual-install-detect.sh` per F3.)
- [ ] Reuses existing `test-update-zskills-*` scaffolding where possible
  (no duplicated installer-bootstrap logic).
- [ ] Rough edges (a)/(b) recorded as resolved-or-audit-pending observations,
  not fixed.
- [ ] `bash tests/run-all.sh` exits 0; no regression.

### Dependencies
None (independent of Phases 1-2).

## Plan Quality

**Drafting process:** /draft-plan — read-only inspection (Phase-1 research) +
1 adversarial round (reviewer + devil's-advocate, parallel)
**Convergence:** Converged at round 1 — all findings dispositioned (8 fixed,
6 confirmed-OK / no-action). Remaining substantive issues: 0.
**Remaining concerns:** None blocking. Two implementation-time investigations
are flagged in-plan as guards, not open issues: whether `--plugin-dir`
mutates its target (Phase 2 keeps the fresh-clone hedge), and whether Gap-3's
materialiser fallback is already covered by an existing sessionstart test
(Phase 1 says check-then-drop-if-covered). The honest outcome of review F5:
Phase 2's recurring-CI contribution is graceful-degradation + validate-exit-0;
the real hook-fire/dual-lane validation is an attended pre-launch one-shot
(`claude -p` needs login, unavailable in unauth CI) — the plan states this
plainly rather than overpromising a CI gate.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1 | 10 (2 MINOR-correctness [Gap-3 wrong file, Gap-2 false-FAIL], 1 MINOR [no install.sh], 1 MINOR [D27 enum], 6 verified-OK) | 9 (2 CRITICAL [Gap-2 false-FAIL, Gap-3 wrong file], 3 HIGH [Phase 3 redundant, validate overpromise, hook-fire not CI-runnable], 4 MED/LOW incl. 2 conceded-OK) | 19/19 |

### Disposition table (verify-before-fix; both agents cross-verified)
| Finding | Evidence | Disposition |
|---|---|---|
| Gap-2 shim-sourcing false-FAILs on `session-start-materialise.sh` (registered, no shim, own probe) | Verified (hooks.json:51; grep→0 matches) | Fixed — added named exclusion list (materialiser + .template pair) |
| Gap-3 targets `render-managed-rules.py` but fallback is in `session-start-materialise.sh:228-231` | Verified (renderer has no env/fallback logic) | Fixed — retargeted to materialiser block + check-existing-coverage-first |
| Phase 3 coexistence assertion already in `test-sessionstart-dual-install-detect.sh` (case 4) | Verified (test header lines 13-14) | Fixed — re-scoped Phase 3 to net-new end-to-end installer run only |
| `claude plugin validate` prints only "Validation passed", doesn't name zs/zsbd | Verified (ran it, exit 0, no name token) | Fixed — assertion softened to exit-0 + "Validation passed" |
| Hook-fire not CI-runnable (`claude -p` needs login; isolated HOME → "Not logged in") | Verified (ran it) | Fixed — reframed as attended `ZSKILLS_LIVE_ATTENDED=1` one-shot; CI delta stated honestly |
| No `install.sh`; existing tests transcribe SKILL.md into oracle functions | Verified (ls scripts/; `run_step_c_install`) | Fixed — Phase 3 reuses oracle-function pattern |
| D27 returns `dual` only if BOTH lanes planted | Verified (detect-install-state arms) | Fixed — folded into Phase 3 re-scope (detection deferred to existing test) |
| Detection logic in `hooks/_lib/detect-install-state.sh`, not inline | Verified (source line ~49) | Fixed — citation corrected |
| Isolated HOME is sufficient (no real ~/.claude leak) | Verified (DA conceded) | Confirmed-OK — kept cross-platform SKIP hedge defensively |
| `--plugin-dir` mutation unresolved (login aborted before load) | Judgment — couldn't reproduce | Confirmed — kept fresh-clone hedge as load-bearing |
| Phase-1 exit-code caveat (description-budget fails by exit code) correct | Verified (run-all.sh:48) | Confirmed-OK — no change |
| hooks.json parses as JSON; uniform command shape supports Gap-1 | Verified (hooks.json:7-51) | Confirmed-OK — no change |
| .template pair sources shim; self-load SKIP pattern exists; run-all cluster ~200-206; em-dash headers parse | Verified (multiple) | Confirmed-OK — no change |

## Drift Log

Re-baselined 2026-05-31 against the post-#831 codebase ("Plugin-lane script
resolution + dual-install hardening"), which landed after the original draft
(#800). No phases were executed, so this is a *staleness* re-baseline, not a
drift-vs-completed-work record. Structural deltas applied:

| Item | As drafted (pre-#831) | Current reality | Action |
|------|----------------------|-----------------|--------|
| `scripts/switch-install-path.sh` | "may not exist (Phase-5/D25)" | EXISTS + `test-switch-install-path.sh` registered | Dropped the absence hedge |
| Rough edge (b) WARN consistency | listed as confirm-as-observation | RESOLVED by #831 (materialiser WARNs consistent) | Converted to a regression assertion |
| In-tree `block-*.sh` count | "8" | 7 (the 2 `.template`-only excluded) | Corrected to 7 |
| Gap-3 D3 fallback | "implement both branches" | consumer-present branch already covered | Narrowed to the bundled-fallback branch only |
| Line refs (D3 fallback, detect-state source, run-all cluster, claude ver) | 228-231 / ~49 / 200-206 / 2.1.156 | 303-322 / ~68 / 206-226 / 2.1.157 | Refreshed + reaffirmed grep-the-landmark |
| Rough edges (a) shim header, (c) suffixless-post-build | confirm-as-observation | STILL PRESENT | Kept as observations (corrected cites) |
| `test-plugin-mirrorless-resolution.sh` (added by #831) | not in inventory | covers script-resolution (NOT Phase-1's gaps) | Noted; Phase-1 gaps remain genuinely uncovered |

**Cross-cutting notes (in-scope to NOTE, out-of-scope to FIX here):** the
plugin-mode CI job does not run the full suite under the plugin lane (only
manifest validation; Tier-3 live load deferred), and `RUN_E2E` is unset in CI
(e2e tests dark). These intersect the plan's CI-gating phases but are tracked
separately (issue-sized), not fixed by this plan.

**Coordination:** a separate `/do` adds a D4 suffixless-hook existence gate —
Phase 1 Gap-1 (hooks.json↔script existence with `.template` allowance) is
adjacent; the implementer must NOT duplicate the D4 gate (coordinate / assume
it exists).

## Plan Review

**Refinement process:** /refine-plan — establish-current-reality preamble +
1 adversarial round (reviewer + devil's-advocate, both re-grounded on post-#831
source).
**Convergence:** Converged at round 1 — both agents independently verified the
same staleness set; all findings dispositioned (4 substantive fixes applied:
C1 count, H1/rough-edge-b resolved→assertion, H2 switch-install-path exists,
H3 Gap-3 narrowed; line refs refreshed; rough edges a/c confirmed still-present
and kept). 0 substantive issues open.
**Remaining concerns:** None blocking. The plan is execution-ready against the
current lane. Honest residue (unchanged intent): the live dual-lane hook-fire
canary remains attended-only (`claude -p` needs login — not CI-runnable); the
two cross-cutting CI gaps (plugin-mode-full-suite, RUN_E2E) are tracked
separately.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Substantive | Resolved |
|-------|-------------------|---------------------------|-------------|----------|
| 1 | 9 (2 MED fixes, 2 stale-line, 5 confirm) | 8 (1 CRITICAL count, 2 HIGH stale-premise/exists, 1 HIGH Gap-3-narrow, rest confirm) | 4 | 4/4 |
