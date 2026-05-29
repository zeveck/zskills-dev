---
title: Lane-aware /update-zskills (don't flip a plugin consumer)
created: 2026-05-29
status: active
---

# Plan: Lane-aware `/update-zskills`

## Overview

`/update-zskills` audits `.claude/` and fills gaps (mirrors `skills/`→`.claude/skills/`,
copies hooks, registers `settings.json` hooks, renders `managed.md`). It has **zero
lane-awareness**: a pure **plugin-lane** consumer has no `.claude/` mirror, so the audit
sees every skill/hook as "missing" and gap-fill copies them all in — **silently flipping the
consumer onto the legacy lane** (the exact destructive behavior dogfooding + #801 surfaced).

This plan adds the **smallest correct** retrofit: one early branch that detects a pure-plugin
install and, instead of mirroring, does the lane-safe config/mode subset. It reuses machinery
that already exists (`detect-install-state.sh` from #799, the config-only `apply-preset.sh`
from #801) and **adds no new scripts, flags, strings, or subcommands**. It also folds in two
one-line doc-drift fixes left by #801.

**Non-destructive guarantee for dogfooding (load-bearing):** the branch keys on
`detect_install_state == plugin`, which means "plugin artifacts present AND no legacy mirror."
The zskills dev repo (which dogfoods both lanes) has the legacy mirror present, so it
classifies as `update-zskills` (verified) — the branch **never fires** there, and
`/update-zskills install` / `--rerender` dogfooding is preserved unchanged.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Lane-aware plugin-context branch + doc-drift + tests | ⬚ | | |

## Phase 1 — Lane-aware plugin-context branch

### Goal

Make `/update-zskills` detect a pure-plugin install and, in that case only, skip the
mirror/gap-fill and instead apply a preset config-only (if given) or print a
plugin-managed-vs-config-managed explanation — so a plugin consumer is never silently flipped,
while every other lane (`update-zskills`, `dual`, `fresh`) behaves exactly as today.

### Work Items

- [ ] **W1 — Add the lane branch.** In `skills/update-zskills/SKILL.md`, after the arg parser
  (Step 0.25) and **at/above the Default-Mode "Smart Detection" install-state fork**
  (currently ~SKILL.md:948-957, the dispatch into Fill-All-Gaps / Pull-Latest), insert a
  single branch:
  1. Source `detect-install-state.sh` via the dual-locate pattern (see Design); resolve
     `MAIN_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"` and call `detect_install_state "$MAIN_ROOT"`.
  2. **If `lane == plugin`:** do NOT run Step 0 asset-locate, the audit's gap-fill, or any
     `.claude/`-mirroring step. Instead:
     - If a preset arg (`cherry-pick|locked-main-pr|direct`) was parsed (`$PRESET_ARG`
       non-empty): apply it config-only via the existing Step F call to `apply-preset.sh`
       (already lane-portable at SKILL.md:1702), then print the result and exit.
     - Else (bare): print the plugin-lane explanation (see Design), then exit 0.
  3. **Else** (`lane` is `update-zskills`, `dual`, or `fresh`, OR detection was unreachable):
     proceed to the existing behavior **unchanged**.
  This is the ONLY control-flow addition. `--rerender`, `--migrate-paths`,
  `--switch-install-path`, and explicit `install` keep their existing terminal/dispatch
  behavior (the branch sits on the bare/default path; `install` is addressed in Design).

- [ ] **W2 — Doc-drift fix (independent of W1).** #801 made `apply-preset.sh` config-only and
  made `block-unsafe-generic.sh`'s `BLOCK_MAIN_PUSH` a **config-derived runtime value** (read
  from `execution.main_protected`, fail-closed) — apply-preset NO LONGER edits the hook. But
  `skills/update-zskills/SKILL.md` prose still describes apply-preset splicing the hook. **Do
  NOT blanket-remove `BLOCK_MAIN_PUSH`** — the hook still has the variable (now config-derived),
  so some mentions are still accurate. Re-grep `grep -n BLOCK_MAIN_PUSH
  skills/update-zskills/SKILL.md` and `grep -n 'hook file is missing' …`; for each occurrence
  apply this verified disposition (re-confirm line numbers — they drift):
  - **STALE → fix** (prose saying apply-preset *edits/splices/sets the hook's* `BLOCK_MAIN_PUSH`
    line): ~lines 88, 590-592, 650, 826, 1957, and the Step F "exit 3 = hook file missing"
    (~:1709-1711, → "missing config"). Reword to: apply-preset is config-only; the hook reads
    `main_protected` from config at runtime.
  - **MISLEADING → reframe/drop** (preset tables presenting `BLOCK_MAIN_PUSH` as a value the
    preset *sets in the hook*): the table columns ~:92, :432 and the Step 0.6 trailing note
    ~:726, :730. The push-block now derives from `main_protected`, so drop the `BLOCK_MAIN_PUSH`
    column (or relabel it a derived note), and cut the "belt-and-suspenders, set by Step 0.25"
    framing.
  - **ACCURATE → leave** (describing the hook's OWN runtime variable): ~:1228 ("blocks push when
    `BLOCK_MAIN_PUSH=1`") — still true; optionally add "(derived from config `main_protected`)".
  Prose-only; do not change behavior. If unsure whether an occurrence is stale, read the
  surrounding paragraph and decide by the rule "does it claim apply-preset/Step F writes the
  hook? → stale."

- [ ] **W3 — Mirror + version.** Apply W1+W2 edits to BOTH `skills/update-zskills/SKILL.md` and
  the byte-equal mirror `.claude/skills/update-zskills/SKILL.md` (keep them identical —
  `tests/test-skills-mirror-parity.sh`). Bump `metadata.version` on `update-zskills` in BOTH
  copies (`bash scripts/skill-content-hash.sh skills/update-zskills` →
  `bash scripts/frontmatter-set.sh skills/update-zskills/SKILL.md metadata.version
  "<today-ET>+<hash>"`, then sync the mirror). (No Tier-1 hash-registry interaction: this plan
  edits only SKILL.md prose + adds a test; it does NOT modify any registered Tier-1 script, so
  `references/tier1-shipped-hashes.txt` is untouched.)

- [ ] **W4 — Tests.** Add `tests/test-update-zskills-lane-aware.sh` exercising
  `detect_install_state`-driven branch selection against fixtures (see Acceptance Criteria for
  the exact cases). NEVER weaken existing tests; keep `tests/test-skills-mirror-parity.sh`
  green. Wire the new test into `tests/run-all.sh`.

### Design & Constraints

**Signal = `detect_install_state == plugin` (NOT `CLAUDE_PLUGIN_ROOT`).** `lane == plugin`
means "plugin-materialised artifacts present AND no legacy `.claude/skills` mirror" — the exact
flip-risk, and the only state in which the materialiser actually wrote the plugin install.
`CLAUDE_PLUGIN_ROOT` was rejected: it is set in any `claude --plugin-dir .` session (including
the dev repo's legacy-lane dogfooding), so keying on it would make `/update-zskills install`
wrongly hit the plugin branch and refuse to install — breaking dogfooding. This is the correct
use of `detect_install_state`: it answers "what's installed on disk" (clobber/flip-safety),
**not** "how was I invoked."

**Lane outcomes (and why dogfooding is safe):**
- `plugin` (pure plugin, no mirror) → branch fires → preset-or-explain, no flip. Bug fixed.
- `update-zskills` → branch does NOT fire → legacy behavior. **The dev repo classifies here
  (verified: legacy mirror present, no sentinelled artifacts) — so its `/update-zskills
  install`/`--rerender` dogfooding runs unchanged.**
- `dual` (rare accident — crash mid-switch, or a pre-fix flip) → branch does NOT fire → legacy
  behavior (the mirror already exists, so gap-fill is a non-destructive update; the materialiser
  + `switch-install-path` already own dual detection/warning/recovery — `/update-zskills` must
  NOT add its own dual handling).
- `fresh` → branch does NOT fire → install (legacy bootstrap), unchanged.

**Explicit-flag opt-in (`install`, `--with-addons`):** the branch keys on the bare/default
path only. Explicit `/update-zskills install` or `--with-addons` are a user *forcing* a
legacy/mirror action; leave them allowed (do NOT intercept) — typing them is opt-in. The
destructive case this plan fixes is the *silent* flip on a **bare** call; an explicit flag is a
deliberate choice, not a surprise. (A flipped-then-`install` consumer is already `dual`/
`update-zskills` anyway, so the bare-path branch wouldn't have fired regardless.)

**Dual-locate + fail-soft sourcing of `detect-install-state.sh`** (it is NOT mirrored into
`.claude/hooks/_lib/` on the legacy lane):
```bash
DIS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/detect-install-state.sh" ]; then
  DIS="${CLAUDE_PLUGIN_ROOT}/hooks/_lib/detect-install-state.sh"
elif [ -n "${PORTABLE:-}" ] && [ -f "${PORTABLE}/hooks/_lib/detect-install-state.sh" ]; then
  DIS="${PORTABLE}/hooks/_lib/detect-install-state.sh"
fi
LANE="update-zskills"   # fail-soft default = legacy behavior (safe)
if [ -n "$DIS" ]; then . "$DIS"; LANE="$(detect_install_state "$MAIN_ROOT")"; fi
```
Fail-soft to legacy is safe: a pure-plugin consumer always has `$CLAUDE_PLUGIN_ROOT` set (so
detection is reachable and returns `plugin`); the only unreachable case is a pure-legacy
session, which *should* proceed with legacy behavior anyway.

**Plugin-branch explanation text (bare call)** — reuse existing phrasing; no new canonical
strings. Print to stdout, e.g.:
> You're on the plugin lane. Skills, hooks, and rules are plugin-managed — update them with
> `/plugin marketplace update`, not `/update-zskills`. To change landing mode here, run
> `/zs:update-zskills <cherry-pick|locked-main-pr|direct>` or edit
> `.claude/zskills-config.json` directly (config is the single source of truth for mode). To
> switch install lanes, use `scripts/switch-install-path.sh` (or
> `/update-zskills --switch-install-path=...`).

**`managed.md` is not touched by this branch** — because the plugin branch skips the entire
gap-fill (including Step B's render), the sentinel-clobber landmine (a sentinel-less re-render
shifting `detect_install_state`) cannot occur on this path.

**Reuse inventory (build nothing new):** `hooks/_lib/detect-install-state.sh` (D27);
`apply-preset.sh` config-only (exits 0 applied / 1 no-change / 2 usage / 3 missing-config / 4
malformed); Step F wrapper (SKILL.md:1701-1712); Step 0.6 preset keyword set;
`switch-install-path.sh` for lane changes. **Anti-overbuild (hard constraints):** NO
`CLAUDE_PLUGIN_ROOT` keying; NO `dual` arm; NO interactive greenfield prompt; NO new mode flag;
NO create-config path (the materialiser already seeds config on fresh plugin installs, so a
plugin consumer reaching `/update-zskills` always has config present; `apply-preset` exit-3
covers the degenerate absent case); NO new canonical strings; NO hook edits.

### Acceptance Criteria

- [ ] **AC1 — Pure-plugin not flipped.** Fixture: a project with plugin-materialised
  (sentinelled) artifacts and NO `.claude/skills/` mirror → `detect_install_state` returns
  `plugin` → a bare `/update-zskills` run performs NO mirror/gap-fill write (assert
  `.claude/skills/` stays empty, no `settings.json` hook registrations added) and prints the
  plugin-lane explanation.
- [ ] **AC2 — Preset config-only on plugin lane.** Same fixture + `<preset>` arg (e.g.
  `direct`) → `apply-preset.sh` updates only `execution.landing`/`execution.main_protected` in
  config; NO mirror; exit reflects apply-preset's code.
- [ ] **AC3 — Dogfooding/legacy NOT intercepted (load-bearing).** Fixture with a legacy mirror
  present (classifies `update-zskills` or `dual`) → branch does NOT fire → legacy audit/gap-fill
  path runs as before. Explicitly assert the dev-repo-shaped case is not intercepted.
- [ ] **AC4 — Fail-soft.** When `detect-install-state.sh` is unreachable (no
  `$CLAUDE_PLUGIN_ROOT`, no `$PORTABLE`) → `LANE` defaults to `update-zskills` → legacy
  behavior; no crash.
- [ ] **AC5 — Doc-drift gone (correctly scoped).** No remaining prose in
  `skills/update-zskills/SKILL.md` claims apply-preset/Step F *edits or splices* the hook's
  `BLOCK_MAIN_PUSH` line; the preset tables no longer present `BLOCK_MAIN_PUSH` as a value the
  preset *sets in the hook*; the "exit 3 = hook file missing" prose now reads "missing config."
  (A mention describing the hook's own config-derived runtime `BLOCK_MAIN_PUSH` variable, e.g.
  ~:1228, MAY remain — it is accurate; do NOT assert a `BLOCK_MAIN_PUSH`-free grep.) Source and
  `.claude` mirror byte-equal; `update-zskills` `metadata.version` bumped in both. The
  implementer states the disposition (fixed / reframed / left-accurate) of each occurrence.
- [ ] **AC6 — Suite green by exit code.** `bash tests/run-all.sh` exits 0 (check the exit code,
  not just "0 failed" — some suites emit no `Results:` line yet flip the exit code);
  `tests/test-skills-mirror-parity.sh` green; new `test-update-zskills-lane-aware.sh` green and
  wired into `run-all.sh`.

### Dependencies

None. Builds on #801 (config-only `apply-preset.sh`, config-driven gates) and #799
(`detect-install-state.sh`), both merged to main.

## Plan Quality

**Drafting process:** /draft-plan, 1 round of adversarial review (reviewer + devil's-advocate
+ refiner), with an explicit scope-creep-challenge mandate per the user's anti-overbuild
directive.
**Convergence:** converged at round 1 — both findings were scope corrections, not correctness
defects; the core design (one `detect_install_state == plugin` branch, fail-soft, dogfooding-
safe) was affirmed by both reviewers and empirically verified (dev repo classifies
`update-zskills`, so the branch never fires there).
**Remaining concerns:** none substantive. The doc-drift (W2) is intentionally bounded to
prose; the verify-before-fix pass established the stale-vs-accurate disposition so the
implementer won't over-correct the still-valid runtime `BLOCK_MAIN_PUSH` mention.

### Round History
| Round | Reviewer | Devil's Advocate | Resolved |
|-------|----------|------------------|----------|
| 1 | REVISE — W2/AC5 doc-drift under-specified (6-7 spots, AC5 grep-clean unsatisfiable) | REVISE — same W2/AC5 under-build + W3 Tier-1 hedge is dead-weight overbuild | 2/2 — W2 rescoped with verified per-occurrence disposition; AC5 reframed to "no apply-preset-edits-hook prose" (not grep-clean); W3 Tier-1 hedge cut; +1 Design sentence on explicit-flag opt-in |
