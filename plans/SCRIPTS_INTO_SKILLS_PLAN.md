---
title: Move skill-owned scripts into the skills that use them
created: 2026-04-25
status: active
---

# Plan: Move skill-owned scripts into the skills that use them

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

`/update-zskills` currently copies ~16 scripts from `$PORTABLE/scripts/`
into the consumer's top-level `scripts/`, mixing zskills-managed
infrastructure with consumer-owned files. Move skill-machinery scripts
into their owning skills (`skills/<owner>/scripts/<name>`, mirrored to
`.claude/skills/<owner>/scripts/<name>`); leave genuinely
consumer-facing utilities at `scripts/`. Update all callers to use the
new paths, teach `/update-zskills` to install via the skill mirror, and
have it migrate stale Tier-1 scripts off existing consumer installs.

**Two tiers**, locked here. The only judgment call left at draft time
is each script's row, not the framework:

- **Tier 1 — Skill machinery.** Moves into the owning skill's
  `scripts/` subdir; `/update-zskills` Step D no longer copies it to
  consumer `scripts/`; consumers receive it via the skill mirror.
- **Tier 2 — Consumer-facing or repo tooling.** Stays at `scripts/`.
  Hooks, CLAUDE_TEMPLATE.md, README config schemas continue to name
  `scripts/<x>.sh`. Includes both consumer-facing utilities and
  release-only repo tooling consumed by CI.

(No Tier 3 / delete entries — `build-prod.sh` was reclassified
Tier 2 after R1/D1 verified it is consumed by
`.github/workflows/ship-to-prod.yml:80`.)

| Script                       | Tier   | Owner / disposition          |
|------------------------------|--------|------------------------------|
| `apply-preset.sh`            | 1      | `update-zskills`             |
| `briefing.cjs`               | 1      | `briefing`                   |
| `briefing.py`                | 1      | `briefing`                   |
| `build-prod.sh`              | 2      | release-only repo tooling; never installed to consumers (called by `.github/workflows/ship-to-prod.yml:80`; documented in `RELEASING.md:5,47,64,71,78,82`) |
| `clear-tracking.sh`          | 1      | `update-zskills`             |
| `compute-cron-fire.sh`       | 1      | `run-plan`                   |
| `create-worktree.sh`         | 1      | `create-worktree`            |
| `land-phase.sh`              | 1      | `commit`                     |
| `port.sh`                    | 1      | `update-zskills`             |
| `post-run-invariants.sh`     | 1      | `run-plan`                   |
| `sanitize-pipeline-id.sh`    | 1      | `create-worktree`            |
| `statusline.sh`              | 1      | `update-zskills` (source moves; install destination still `~/.claude/statusline-command.sh`) |
| `stop-dev.sh`                | 2      | currently functional generic implementation; consumer stack writes PIDs to `var/dev.pid`. **Note:** full conversion to a formal failing stub is deferred to a follow-up plan covering the consumer stub-callout pattern. |
| `test-all.sh`                | 2      | already a partial template (`{{E2E_TEST_CMD}}` placeholders); customized by consumer with their own test commands. **Note:** full conversion to a formal failing stub is deferred to the same follow-up plan. |
| `worktree-add-safe.sh`       | 1      | `create-worktree`            |
| `write-landed.sh`            | 1      | `commit`                     |

13 Tier 1 moves, 3 Tier 2 stay-puts (`build-prod.sh`, `stop-dev.sh`,
`test-all.sh`), zero deletes.

**Skills with only Tier-2 references are unchanged in their script
choices.** `verify-changes`, `cleanup-merged`, `fix-report`,
`manual-testing` reference scripts that have moved Tier (now Tier-1
`port.sh`, `clear-tracking.sh`) — these skills' callsites ARE swept by
Phase 3b's grep-driven sweep, alongside the originally-Tier-1 scripts.

### Alternative considered — middle path adopted (was: maximalist)

D14 originally raised: the user complained about `scripts/`-pollution;
reducing 16 → 6 still leaves a populated `scripts/` directory. The
draft's first cut argued for keeping `clear-tracking.sh`, `port.sh`,
and `statusline.sh` at `scripts/` based on hook help-text matching,
config-schema literal strings, and install-destination considerations.

User feedback exposed circular reasoning in those defenses: each was
"the existing call form references `scripts/<x>.sh`, therefore the
script must stay at `scripts/<x>.sh`." That justifies the status quo
by appealing to it. The cleaner question is whether the script is
zskills machinery (move into a skill, update callers and hook
help-text) or consumer-customizable (stays at `scripts/`).

**The COUNT-vs-EXISTENCE framing is partially resolved.** Tier-1
machinery now leaves consumer `scripts/` entirely (13 moves). What
remains in `scripts/` is genuinely consumer-customizable
(`stop-dev.sh`, `test-all.sh`) plus release-only repo tooling
(`build-prod.sh`) that never ships to consumers. The split is now
ownership-driven, not call-form-driven.

**Stub-callout pattern (out of scope for this plan).** The principled
end state for `stop-dev.sh` and `test-all.sh` is the consumer
stub-callout pattern — zskills's tools defer to a consumer-owned
`scripts/<stub>.sh` if present, with a documented signature.
Generalizing this convention (and converting `stop-dev.sh` /
`test-all.sh` into formal failing stubs, plus a new
`post-create-worktree.sh` callout and the `dev-port.sh` callout) is
DEFERRED TO A FOLLOW-UP PLAN. This plan ships the Tier-1 moves and
leaves the Tier-2 scripts as-is for now.

**EXISTENCE axis.** Post-this-plan, zskills machinery no longer
appears in consumer `scripts/`; consumer-customizable stubs remain
there pending the follow-up plan. If a future review concludes that
even consumer-customizable scripts shouldn't live at `scripts/`, that
decision belongs in the follow-up plan, not here.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Inventory cleanup: fix dead refs, write ownership registry | ⬚ |  |  |
| 2 — Move single-owner Tier 1 scripts (apply-preset, compute-cron-fire, post-run-invariants, briefing.*, statusline) | ⬚ |  |  |
| 3a — Move shared Tier 1 scripts and update same-skill internals (create-worktree, worktree-add-safe, land-phase, write-landed, sanitize-pipeline-id, clear-tracking, port [+ config-driven default_port]) | ⬚ |  |  |
| 3b — Update cross-skill callers (grep-driven sweep across skills/ .claude/skills/ CLAUDE.md README.md RELEASING.md) and tests | ⬚ |  |  |
| 4 — Update `/update-zskills` install flow: drop Tier-1 copies, install via skill mirror, add stale-Tier-1 migration | ⬚ |  |  |
| 5 — Update zskills tests + sweep README/CLAUDE.md/CLAUDE_TEMPLATE for residual references | ⬚ |  |  |
| 6 — Docs and close-out: CHANGELOG, plan registry, frontmatter flip | ⬚ |  |  |

## Phase 1 — Inventory cleanup: fix dead refs, write ownership registry

### Goal

Close one pre-existing hole (four dead references that fail at runtime)
and seed the ownership table in a place future agents will read. (The
"orphan" originally listed here — `build-prod.sh` — was reclassified
Tier 2 after R1/D1 verification; no deletion happens.)

### Work Items

- [ ] 1.2 — **Dead reference fix in `skills/fix-issues/SKILL.md`.** Three
      references to scripts that don't exist on disk and never have:
      - `:301` `node scripts/skipped-issues.cjs --check-gh`
      - `:500` `node ${CLAUDE_SKILL_DIR}/scripts/sync-issues.js`
      - `:505` `node ${CLAUDE_SKILL_DIR}/scripts/issue-stats.js`

      Each appears in user-instruction prose telling the agent to run a
      script that does not exist. The block falls through to "use the
      script output directly — do NOT manually grep". Replace each
      block with the manual fallback the script would have produced
      (grep `plans/SPRINT_REPORT.md` for `[skipped]` lines; grep open
      `gh issue list` against `plans/*ISSUES*.md`; tally label counts
      via `gh issue list --json labels`). The replacement prose is
      grep-able recipes the agent can execute today, so the skill
      stops promising machinery it doesn't have.
- [ ] 1.3 — **Dead reference fix in `skills/review-feedback/SKILL.md:34`**:
      `node scripts/review-feedback.js feedback.json`. Replace with a
      `jq`-free bash recipe (parse the JSON via the same
      `BASH_REMATCH` idiom used in hooks; per memory `feedback_no_jq_in_skills.md`)
      OR strip the optional summary step entirely and have the agent
      read `feedback.json` directly with the Read tool. Pick the
      simpler — strip the helper step.
- [ ] 1.4 — **Write the ownership registry** at
      `skills/update-zskills/references/script-ownership.md` (new
      file). Contents: the Tier table verbatim from the Overview
      (preserve the 3-column markdown format
      `| Script | Tier | Owner / disposition |` — Phase 4 WI 4.2's
      hash-file generator AND WI 4.8 case 6a's drift test parse it
      with `awk -F'|'` against this exact column layout) plus a
      brief paragraph documenting the cross-skill path convention
      (next item) and the STALE_LIST that Phase 4 reads. This is the
      authoritative file Phase 4's migration logic greps. **Format
      contract:** column 1 = ` `script-name.ext` `, column 2 = ` 1 `
      or ` 2 ` (literal digit, with surrounding whitespace), column
      3 = owner-or-disposition. Future agents adding rows must
      preserve this layout or update both parsers.
- [ ] 1.5 — Mirror update-zskills:
      `rm -rf .claude/skills/update-zskills && cp -a skills/update-zskills/ .claude/skills/update-zskills/`.
      Mirror fix-issues and review-feedback the same way after WIs
      1.2 / 1.3.

### Design & Constraints

**Cross-skill path convention** (recorded in
`skills/update-zskills/references/script-ownership.md` per WI 1.4 and
referenced from every later phase):

- **Source-tree zskills tests** invoke scripts via the absolute
  `"$REPO_ROOT/skills/<owner>/scripts/<name>"` form. The bare-relative
  `skills/<owner>/scripts/<name>` form is FORBIDDEN (per D16 — picking
  one form prevents test/script inconsistency). `tests/run-all.sh`
  exports `CLAUDE_PROJECT_DIR="$REPO_ROOT"` (Phase 5 WI 5.7) so
  cross-skill invocations also resolve under tests.
- **Shipped (consumer-side) and cross-skill callers** MUST use
  the bare-`$CLAUDE_PROJECT_DIR` form
  `"$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<name>"`.
  The harness sets `CLAUDE_PROJECT_DIR` in spawned bash blocks
  (verified by inspection of existing
  `grep -rn 'CLAUDE_PROJECT_DIR' skills/`); zskills' own tests
  export it via `tests/run-all.sh` (Phase 5 WI 5.7). The earlier
  round's `:-$MAIN_ROOT` fallback (round-4 form) added
  complexity without value: many cross-skill callsites in skill
  prose lack `MAIN_ROOT` in scope (e.g., the four `port.sh` callers
  in `briefing`, `manual-testing`, `fix-report`, `verify-changes`
  are bare prose snippets with NO `MAIN_ROOT` computation), causing
  the fallback to silently produce an empty path
  (`/.claude/skills/...`, absolute root). Trust the harness
  contract; if `CLAUDE_PROJECT_DIR` is unset at a callsite, fail
  loud rather than silently expand to an invalid path. Research
  verified `CLAUDE_SKILL_DIR` is **not** harness-defined — earlier
  `fix-issues` uses of `${CLAUDE_SKILL_DIR}/scripts/...` were
  already broken (dead refs — see WI 1.2).
- **Same-skill internal callers** (e.g., `create-worktree.sh`
  invoking `worktree-add-safe.sh` in its own skill) use a path
  computed from the script's own location
  (`SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)`) rather than
  `$CLAUDE_PROJECT_DIR`, so the script keeps working when zskills
  tests run it from the source tree. **Symlink caveat (D18):**
  scripts must be invoked by direct path, not via symlink. If symlink
  invocation becomes a need, switch to the `readlink -f` resolution
  form documented in Phase 3a Design.

**Why fix the dead refs now and not file as separate issues.** Per
memory `feedback_dont_defer_hole_closure.md`: when an incident is a
hole, closing the hole IS the change. The dead refs are
agent-instructional — an agent following the skill literally runs a
command that doesn't exist. Fixing them costs three Edits; deferring
them keeps shipping a skill that lies.

**No premature back-compat.** Per memory
`feedback_no_premature_backcompat.md`, zskills has no external
consumers protecting `scripts/<name>` source-tree paths for Tier 1
scripts. Source tree migrates to skill-dir-only.

**Mirror discipline.** Every phase that edits `skills/<name>/`
finishes with
`rm -rf .claude/skills/<name> && cp -a skills/<name>/ .claude/skills/<name>/`
(batched copy, never per-file Edit on `.claude/skills/`; per memory
`feedback_claude_skills_permissions.md`).

### Acceptance Criteria

- [ ] `test -f scripts/build-prod.sh` (Tier-2; not deleted; verified
      consumed by `.github/workflows/ship-to-prod.yml:80`).
- [ ] `grep -rn 'skipped-issues\.cjs\|sync-issues\.js\|issue-stats\.js\|review-feedback\.js' skills/ .claude/skills/`
      returns zero matches (all dead references gone).
- [ ] `test -f skills/update-zskills/references/script-ownership.md`
      and `test -f .claude/skills/update-zskills/references/script-ownership.md`.
- [ ] `grep -c 'Tier 1' skills/update-zskills/references/script-ownership.md`
      ≥ 1 (table is present).
- [ ] `diff -r skills/fix-issues .claude/skills/fix-issues` is empty;
      same for `review-feedback` and `update-zskills`.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

None.

## Phase 2 — Move single-owner Tier 1 scripts

### Goal

Move scripts whose only zskills caller is one skill into that skill's
`scripts/` subdir. No cross-skill path updates needed yet — these
scripts have a single owner and the owner uses a same-skill internal
path.

Scripts moved in this phase: `apply-preset.sh` (→ `update-zskills`),
`compute-cron-fire.sh` (→ `run-plan`), `post-run-invariants.sh` (→
`run-plan`), `briefing.cjs` (→ `briefing`), `briefing.py` (→
`briefing`), `statusline.sh` (→ `update-zskills`).

### Work Items

- [ ] 2.1 — **`apply-preset.sh` → `skills/update-zskills/scripts/apply-preset.sh`.**
      `git mv scripts/apply-preset.sh skills/update-zskills/scripts/apply-preset.sh`
      (creates the subdir). Update `skills/update-zskills/SKILL.md:939`
      and `:1009` from `bash scripts/apply-preset.sh "$PRESET_ARG"` to
      `bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/apply-preset.sh" "$PRESET_ARG"`
      (bare `$CLAUDE_PROJECT_DIR` form per Phase 1 Design;
      round-5 dropped the earlier `:-$MAIN_ROOT` fallback).
      Update `:245`, `:824`, `:1001`, `:1081` prose mentions to the
      new path.
      Per D5: also update `apply-preset.sh`'s self-doc strings
      (verified by `grep -n 'scripts/apply-preset' scripts/apply-preset.sh`
      lines 5,157,166): rewrite to path-agnostic form using
      `$(basename "$0")` (recommended) OR update to the new path.
- [ ] 2.2 — **`compute-cron-fire.sh` → `skills/run-plan/scripts/compute-cron-fire.sh`.**
      `git mv scripts/compute-cron-fire.sh skills/run-plan/scripts/`.
      Update `skills/run-plan/SKILL.md:1429`, `:1435`, `:1446`, and
      `skills/run-plan/references/finish-mode.md:154`. Same-skill
      callers — switch to
      `bash "$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/compute-cron-fire.sh"`
      (bare `$CLAUDE_PROJECT_DIR` form per Phase 1 Design).
      Per D5: update self-doc strings inside the script to
      path-agnostic `$(basename "$0")` form (verify with
      `grep -n 'scripts/compute-cron-fire' scripts/compute-cron-fire.sh`).
- [ ] 2.3 — **`post-run-invariants.sh` → `skills/run-plan/scripts/post-run-invariants.sh`.**
      `git mv` and update `skills/run-plan/SKILL.md:1639`, `:1653` and
      `skills/run-plan/references/finish-mode.md:50`. Same-skill →
      `$CLAUDE_PROJECT_DIR/.claude/skills/run-plan/scripts/...`
      (bare `$CLAUDE_PROJECT_DIR` form per Phase 1 Design).
      Per D5: update self-doc strings to path-agnostic form (verify
      with `grep -n 'scripts/post-run-invariants' scripts/post-run-invariants.sh`).
- [ ] 2.4 — **`briefing.cjs` and `briefing.py` → `skills/briefing/scripts/`.**
      `git mv scripts/briefing.cjs skills/briefing/scripts/`;
      `git mv scripts/briefing.py skills/briefing/scripts/`.
      Update **all 11 references** (verified by
      `grep -nc 'briefing\.\(cjs\|py\)' skills/briefing/SKILL.md` = 11)
      in `skills/briefing/SKILL.md` (the
      `node scripts/briefing.cjs` invocations at
      `:18,19,26,27,28,67,82,111,193,210,224`) to
      `node "$CLAUDE_PROJECT_DIR/.claude/skills/briefing/scripts/briefing.cjs"`
      (and similarly for `briefing.py`; bare `$CLAUDE_PROJECT_DIR`
      form per Phase 1 Design). Authoritative truth is the
      grep, not the line-number list — drive edits by
      `grep -rn 'scripts/briefing\.\(cjs\|py\)' skills/briefing/`
      and address every match.
      Also update self-doc strings inside `briefing.cjs` and
      `briefing.py` (verified at
      `grep -n 'scripts/briefing' scripts/briefing.cjs` lines
      8,9,10,11,12,1892 and `briefing.py` lines 9-16, 1617, 1703):
      rewrite to path-agnostic usage using the
      LANGUAGE-APPROPRIATE form (D21 fix — `$(basename "$0")` is bash
      command substitution; inside JS/Python source it is a literal
      string and prints verbatim, NOT the script's basename).

      The three correct forms by language:
      - **`.sh` scripts**: `$(basename "$0")` (bash command
        substitution, fine inside shell scripts).
      - **`.cjs`** (Node): add at top:
        `const SELF = require('path').basename(__filename);`
        then in usage strings: `\`Usage: node ${SELF} ...\``.
      - **`.py`** (Python): add at top:
        `import os, sys` then `SELF = os.path.basename(sys.argv[0])`
        then in usage: `f"Usage: python3 {SELF} ..."`.

      For `briefing.cjs`, use the `path.basename(__filename)` form.
      For `briefing.py`, use the `os.path.basename(sys.argv[0])` form.
      Do NOT paste `$(basename "$0")` into JS or Python source.
- [ ] 2.5 — Update `skills/update-zskills/SKILL.md` dependency-check
      prose. The check at `:410-411`, `:487-489`, `:533`, `:971` says
      "node enables `scripts/briefing.cjs`" / "requires briefing.cjs
      or briefing.py in `scripts/`". Rewrite to keep BOTH halves of
      the original check (per D6: artifact + interpreter) but with
      the new path: "requires `node` (or `python3` fallback) AND
      `[ -f .claude/skills/briefing/scripts/briefing.cjs ]` (or
      `briefing.py`)". The artifact half catches partial skill-mirror
      installs; do NOT drop it.
- [ ] 2.6 — Update `tests/test-briefing-parity.sh:62,84,86,128,129`.
      MANDATE the absolute-anchored form:
      `node "$REPO_ROOT/skills/briefing/scripts/briefing.cjs"` and
      `python3 "$REPO_ROOT/skills/briefing/scripts/briefing.py"`.
      The bare-relative form (`node skills/briefing/scripts/briefing.cjs`)
      is FORBIDDEN — pick one form, apply consistently. Also export
      `CLAUDE_PROJECT_DIR="$REPO_ROOT"` at the top of the test (see
      Phase 3 design note on harness env propagation).
- [ ] 2.7 — Update `tests/test-apply-preset.sh:7`:
      `SCRIPT="$REPO_ROOT/skills/update-zskills/scripts/apply-preset.sh"`.
- [ ] 2.7b — **`statusline.sh` → `skills/update-zskills/scripts/statusline.sh`.**
      `git mv scripts/statusline.sh skills/update-zskills/scripts/statusline.sh`.
      Single-owner: only `update-zskills` Step C.5 (line 891) handles
      it. Update Step C.5 line 891 from
      `cp $PORTABLE/scripts/statusline.sh ~/.claude/statusline-command.sh`
      to
      `cp $PORTABLE/.claude/skills/update-zskills/scripts/statusline.sh ~/.claude/statusline-command.sh`.
      The install destination is unchanged (still `~/.claude/`); only
      the source location changes. Also update the prose mention at
      `:483` ("`statusline.sh` — session statusline helper") to drop
      the bare `scripts/` framing if implied.
      Update self-doc strings inside `statusline.sh` (verify with
      `grep -n 'statusline\|scripts/' scripts/statusline.sh`) to
      path-agnostic `$(basename "$0")` form.
- [ ] 2.8 — Mirror each touched skill:
      `rm -rf .claude/skills/update-zskills && cp -a skills/update-zskills/ .claude/skills/update-zskills/`,
      same for `run-plan` and `briefing`.
- [ ] 2.9 — Run `bash tests/run-all.sh`. Expect green; if not, fix
      paths in whatever WI missed a reference (do NOT weaken tests).

### Design & Constraints

**Why these five together.** Single-owner moves are independent of
each other; they share only the mechanical pattern (`git mv`, update
N references in one skill, mirror). Bundling them into one phase
keeps the diff coherent and gives one revert-point if the pattern
itself is wrong.

**Why `briefing.cjs/.py` are Tier 1.** Only `briefing` and
`update-zskills` reference them. `update-zskills`'s usage is a
**dependency check** (does `node`/`python3` exist on PATH so
`/briefing` will work?), not an invocation. The consumer never runs
`node scripts/briefing.cjs` directly — they invoke `/briefing`. So
"belongs inside the skill that uses it" is satisfied by the briefing
skill. The dependency check in `update-zskills` becomes "node/python3
present on PATH", with no `scripts/briefing.*` filename mention.

**Why `statusline.sh` moves to `update-zskills`.** Single-owner:
Step C.5 of `update-zskills/SKILL.md` is the only zskills caller, and
the install destination (`~/.claude/statusline-command.sh`) is
unaffected by the source move — only the `cp` source path changes.
Co-locating the source with its installer keeps owner-and-source
together (the principled split, per the Overview's reframed
maximalist note).

**Same-skill internal path form.** Because zskills' own tests run
scripts from `skills/<owner>/scripts/...` directly (no
`$CLAUDE_PROJECT_DIR` available outside the harness), scripts that
invoke peer scripts in the same skill should use `$(dirname "$0")`
resolution rather than hardcoding `$CLAUDE_PROJECT_DIR`. None of the
five scripts moved in this phase invoke a peer script — applies
later, in Phase 3 (`create-worktree.sh` → `worktree-add-safe.sh`,
`sanitize-pipeline-id.sh`).

**Mirror discipline.** Per Phase 1.

### Acceptance Criteria

- [ ] `! test -e scripts/apply-preset.sh && test -f skills/update-zskills/scripts/apply-preset.sh && test -f .claude/skills/update-zskills/scripts/apply-preset.sh`.
- [ ] `! test -e scripts/compute-cron-fire.sh && test -f skills/run-plan/scripts/compute-cron-fire.sh && test -f .claude/skills/run-plan/scripts/compute-cron-fire.sh`.
- [ ] `! test -e scripts/post-run-invariants.sh && test -f skills/run-plan/scripts/post-run-invariants.sh && test -f .claude/skills/run-plan/scripts/post-run-invariants.sh`.
- [ ] `! test -e scripts/briefing.cjs && ! test -e scripts/briefing.py && test -f skills/briefing/scripts/briefing.cjs && test -f skills/briefing/scripts/briefing.py && test -f .claude/skills/briefing/scripts/briefing.cjs && test -f .claude/skills/briefing/scripts/briefing.py`.
- [ ] `! test -e scripts/statusline.sh && test -f skills/update-zskills/scripts/statusline.sh && test -f .claude/skills/update-zskills/scripts/statusline.sh`.
- [ ] Step C.5 source path updated:
      `grep -F '.claude/skills/update-zskills/scripts/statusline.sh' skills/update-zskills/SKILL.md | wc -l` ≥ 1
      AND `! grep -E '\$PORTABLE/scripts/statusline\.sh' skills/update-zskills/SKILL.md`.
- [ ] All five executable bits preserved:
      `for f in skills/update-zskills/scripts/apply-preset.sh skills/run-plan/scripts/compute-cron-fire.sh skills/run-plan/scripts/post-run-invariants.sh skills/briefing/scripts/briefing.py; do test -x "$f" || exit 1; done`
      (`.cjs` does not need `+x` since it's invoked via `node`).
- [ ] `grep -rn 'scripts/apply-preset\|scripts/compute-cron-fire\|scripts/post-run-invariants\|scripts/briefing\.' skills/ .claude/skills/`
      returns zero matches (all old-path refs purged).
- [ ] **Briefing dependency check retains the artifact half (D6 fix).**
      The dependency-check prose at `:410-411, :487-489, :533, :971`
      MUST mention `[ -f .claude/skills/briefing/scripts/briefing.cjs ]`
      OR `briefing.py`:
      `grep -E '\.claude/skills/briefing/scripts/briefing\.(cjs|py)' skills/update-zskills/SKILL.md | wc -l`
      ≥ 1.
- [ ] **Language-appropriate self-doc forms in use (D21 fix).**
      `grep -F 'path.basename(__filename)' skills/briefing/scripts/briefing.cjs | wc -l`
      ≥ 1; `grep -F 'os.path.basename(sys.argv[0])' skills/briefing/scripts/briefing.py | wc -l`
      ≥ 1; and verify NO bash literal leaked into JS/Python source:
      `grep -F '$(basename "$0")' skills/briefing/scripts/briefing.cjs skills/briefing/scripts/briefing.py | wc -l`
      = 0.
- [ ] `diff -r skills/update-zskills .claude/skills/update-zskills` empty;
      same for `run-plan` and `briefing`.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 1 (registry doc).

## Phase 3a — Move shared Tier 1 scripts and update same-skill internals

### Goal

Move the seven shared Tier 1 scripts (`create-worktree.sh`,
`worktree-add-safe.sh`, `land-phase.sh`, `write-landed.sh`,
`sanitize-pipeline-id.sh`, `clear-tracking.sh`, `port.sh`) into their
owning skills, and update same-skill internal references
(script-to-script calls inside the same skill, the
`create-worktree.sh` install-integrity gate, and the
config-driven `port.sh` default-port read). Cross-skill caller
updates are deferred to Phase 3b.

### Work Items

- [ ] 3a.1 — **`create-worktree.sh` and `worktree-add-safe.sh` →
      `skills/create-worktree/scripts/`.**
      `git mv scripts/create-worktree.sh skills/create-worktree/scripts/`;
      `git mv scripts/worktree-add-safe.sh skills/create-worktree/scripts/`.
      Update `create-worktree.sh` internals: the
      `$MAIN_ROOT/scripts/worktree-add-safe.sh` invocation and the
      `$MAIN_ROOT/scripts/sanitize-pipeline-id.sh` invocation become
      same-skill internals — switch to:
      ```bash
      SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
      bash "$SCRIPT_DIR/worktree-add-safe.sh" ...
      bash "$SCRIPT_DIR/sanitize-pipeline-id.sh" ...
      ```
      Same-skill internal resolution keeps zskills tests working
      without `$CLAUDE_PROJECT_DIR`.

      Also update self-doc / usage strings inside `create-worktree.sh`
      and `worktree-add-safe.sh`: rewrite to path-agnostic form using
      `$(basename "$0")` (recommended for resilience) OR update any
      hardcoded `scripts/<name>` mentions to the new path.
- [ ] 3a.2 — **Update install-integrity gate at
      `scripts/create-worktree.sh:45` (now
      `skills/create-worktree/scripts/create-worktree.sh:45` after the
      move).** The check
      `if [ ! -x "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" ]; then ... exit 5`
      becomes:
      ```bash
      if [ ! -x "$SCRIPT_DIR/sanitize-pipeline-id.sh" ]; then
        echo "create-worktree: $SCRIPT_DIR/sanitize-pipeline-id.sh missing or not executable (install-integrity)" >&2
        exit 5
      fi
      ```
      The check is now cheap (same-dir peer, near-tautology) but kept
      as defense against half-deployed skill mirrors. Update the error
      message at line 46 to reference the new path.

      Verified by:
      `sed -n '40,50p' scripts/create-worktree.sh` shows the existing
      gate at lines 44-46.
- [ ] 3a.3 — **`sanitize-pipeline-id.sh` → `skills/create-worktree/scripts/sanitize-pipeline-id.sh`.**
      Owner is `create-worktree` because: (a) `create-worktree.sh`
      invokes it as an install-integrity gate (line 45), so the two
      scripts ship together; (b) the script is the pipeline-infra
      one-liner and `create-worktree` is the pipeline-infra skill;
      (c) `run-plan` was the alternative but `create-worktree` already
      depends-on it via install-integrity, so co-locating eliminates
      the cross-skill path inside one of the most-frequently-called
      scripts.
      `git mv` it. Update self-doc strings to path-agnostic
      `$(basename "$0")` form.
- [ ] 3a.4 — **`land-phase.sh` and `write-landed.sh` →
      `skills/commit/scripts/`.** Owner is `commit` because both are
      landing primitives and `commit/modes/land.md` is the human-facing
      home for landing. `git mv` both. Update self-doc strings to
      path-agnostic form.
- [ ] 3a.4b — **`clear-tracking.sh` → `skills/update-zskills/scripts/clear-tracking.sh`.**
      Owner is `update-zskills` (it's the install/maintenance skill;
      tracking-state hygiene is its concern). `git mv` it. Update
      self-doc strings to path-agnostic `$(basename "$0")` form.
      Internal `MAIN_ROOT` computation
      (`git rev-parse --git-common-dir`) at script line 11 is
      location-agnostic and continues to work from the new path —
      verified by reading the script.
- [ ] 3a.4c — **`port.sh` → `skills/update-zskills/scripts/port.sh`,
      AND fix the hardcoded `DEFAULT_PORT=8080`.** Owner is
      `update-zskills` (it's installed and configured by
      `/update-zskills`). `git mv` the file.

      **Overlap warning.** `plans/DEFAULT_PORT_CONFIG.md` Phase 1 makes
      the same `dev_server.default_port` schema-field addition + this
      repo's config + `update-zskills` greenfield-template + backfill
      edits. Whichever plan lands first, the other's overlapping work
      items (Phase 1 of DEFAULT_PORT_CONFIG / sub-WIs 3a.4c.i and
      3a.4c.iii here, plus the schema/this-repo-config edits) become
      no-ops. **Run `/refine-plan` on the second plan before
      `/run-plan` to drop the redundant WIs.** DEFAULT_PORT_CONFIG goes
      further than this plan does (also migrates `test-all.sh`,
      `briefing.cjs`, `briefing.py`, and adds `{{DEFAULT_PORT}}`
      template substitution); those non-overlapping WIs survive
      regardless of order.

      At script line 29, `DEFAULT_PORT=8080` is hardcoded. Replace
      with a config read using the same `BASH_REMATCH` idiom already
      in the script (lines 19-25 read `dev_server.main_repo_path` from
      `.claude/zskills-config.json`):
      ```bash
      DEFAULT_PORT=8080  # fallback when config field is absent
      if [ -f "$_ZSK_CFG" ]; then
        if [[ "$_ZSK_CFG_BODY" =~ \"dev_server\"[[:space:]]*:[[:space:]]*\{[^}]*\"default_port\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
          DEFAULT_PORT="${BASH_REMATCH[1]}"
        fi
      fi
      ```
      (Reuse `$_ZSK_CFG_BODY` from the existing block; reorder so
      `default_port` is parsed before `unset _ZSK_CFG_BODY` runs.)

      Add to `config/zskills-config.schema.json` under the
      `dev_server` `properties` block (currently lines 86-99) a new
      field:
      ```json
      "default_port": {
        "type": "integer",
        "default": 8080,
        "description": "Default dev server port for the main repo; worktrees get a hash-derived port in 9000-60000."
      }
      ```

      **No interactive prompt added.** Round-5 verification of
      `skills/update-zskills/SKILL.md` Step 0.5 / 0.6 confirmed:
      Step 0.5 (lines ~170-227) is a BASH_REMATCH config-merge
      algorithm with NO `read -p` prompt loop; Step 0.6 (lines
      ~348-386) prompts ONLY for landing-mode. Adding a
      `default_port` prompt is out-of-character and unnecessary —
      `default_port` is optional with a documented default
      (8080); existing consumer configs without it work fine
      because `port.sh`'s BASH_REMATCH read falls back to 8080 on
      no-match. Sub-WIs:

      - **3a.4c.i** — Add `"default_port": 8080,` to the
        greenfield JSON config template at
        `skills/update-zskills/SKILL.md:282-286` (the
        `dev_server: { ... }` block written on first install).
        Place it as the second field, after `cmd`. NOTE: Phase 5
        WI 5.5.a drops the `port_script` field from this same
        block; if Phase 5 has already landed, this WI just adds
        `default_port`. AC:
        `grep -F '"default_port"' skills/update-zskills/SKILL.md`
        ≥ 1 match.
      - **3a.4c.ii** — DO NOT add an interactive prompt in Step
        0.5 or Step 0.6. The field is optional; `port.sh` falls
        back to 8080 when absent. Existing consumers' configs
        upgrade silently.
      - **3a.4c.iii** — Optional: extend the Step 0.5
        BASH_REMATCH read block (lines ~170-227) to also extract
        `default_port`. Skip if no install-side logic needs it
        (the script reads it directly at runtime).

      Update `port.sh`'s self-doc header to the pinned form:
      ```bash
      #!/bin/bash
      # port.sh -- deterministic dev-server port for the current project root.
      #
      # Main repo (dev_server.main_repo_path, read at runtime from
      # .claude/zskills-config.json) -> dev_server.default_port (default 8080).
      # Worktrees -> stable port in 9000-60000 derived from the project root path.
      # DEV_PORT env var overrides everything.
      #
      # Usage:  bash $(basename "$0")   (prints port to stdout)
      ```
      Apply verbatim — the rewrite is mechanical, not
      judgment-class.
- [ ] 3a.5 — Mirror three touched skills:
      ```bash
      for s in create-worktree commit update-zskills; do
        rm -rf .claude/skills/$s && cp -a skills/$s/ .claude/skills/$s/
      done
      ```
      Verify with
      `for s in create-worktree commit update-zskills; do diff -r skills/$s .claude/skills/$s || echo DRIFT $s; done`.
- [ ] 3a.6 — Verify scripts run from source tree.
      `bash skills/create-worktree/scripts/create-worktree.sh --help`
      should exit 0 (or print usage). `bash tests/run-all.sh` is NOT
      expected to fully pass here — Phase 3b updates the cross-skill
      callers that tests trace through. Phase 3a's gate is: same-skill
      internals + install-integrity gate work in isolation.

### Design & Constraints

**Why split same-skill internals from cross-skill sweep.** Per D17
(major): combining all 11 WIs across 8 skills produced a 30-edit
phase. Phase 3a is now the bounded "move + same-skill internals" cut;
Phase 3b is the grep-driven cross-skill sweep + tests. Splitting gives
`/run-plan` a natural midpoint and lets a reviewer audit each half
independently.

**Phase 3a is intentionally a mid-state (D26 + R2.2 fix).** End-of-3a
leaves cross-skill callers naming `scripts/<name>` while the source
files have moved. `bash tests/run-all.sh` is EXPECTED RED at end-of-3a
— this is by design; Phase 3b updates the cross-skill callers and
makes tests green. The /run-plan verifier MUST accept this — DO NOT
block on `tests/run-all.sh` for Phase 3a. The gating signals for 3a
are the structural ACs below (move succeeded, install-integrity gate
updated, mirrors clean) PLUS the positive-pass signal
`bash skills/create-worktree/scripts/create-worktree.sh --help`
exits with usage text. Per memory `feedback_verifier_test_ungated.md`,
"verifier must attest to tests" — the explicit attestation here is
"tests intentionally red at this midpoint; gating is structural,
not test-suite-green." For PR-mode landing, mark CI failures on the
3a commit as expected; do NOT block the PR. Phase 3b's commit is the
first one that must be CI-green.

**`sanitize-pipeline-id.sh` ownership.** Choosing a single owner
(`create-worktree`) over inlining-as-function: the script is 15
lines, but it has dedicated tests
(`tests/test-create-worktree.sh:834-836` covers it indirectly,
`scripts/sanitize-pipeline-id.sh` itself is a single command boundary
the hooks can audit). Inlining would scatter that across seven
SKILL.md files and break test coverage. Single-owner has one drift
failure mode (consumer install where `create-worktree` is absent),
which the install flow makes implausible: `/update-zskills` installs
all skills atomically (per memory `feedback_no_premature_backcompat.md`,
no piecemeal-install API exists for consumers). Risk acknowledged,
accepted.

**`land-phase.sh` and `write-landed.sh` ownership.** Both are
landing primitives. `commit/modes/land.md` is the doc home for
landing. Picking `commit` over `run-plan` (which has more numerical
callers) keeps the script with its conceptual home.

**Same-skill internal callers** use `$(dirname "$0")` not
`$CLAUDE_PROJECT_DIR`. This applies to:
- `create-worktree.sh` invoking `worktree-add-safe.sh`
- `create-worktree.sh` invoking `sanitize-pipeline-id.sh`

This lets zskills tests run the scripts in source-tree directly, with
no harness env var needed. **Symlink resilience caveat (D18):** scripts
should be invoked by direct path, not via symlink. `$(dirname "$0")`
resolves to the symlink's directory, not the target's. If symlink
invocation becomes a need, switch to
`SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)`.

**Mirror discipline.** Per Phase 1.

### Acceptance Criteria

- [ ] None of the seven shared Tier 1 scripts exist at
      `scripts/<name>` anymore:
      `! test -e scripts/create-worktree.sh && ! test -e scripts/worktree-add-safe.sh && ! test -e scripts/sanitize-pipeline-id.sh && ! test -e scripts/land-phase.sh && ! test -e scripts/write-landed.sh && ! test -e scripts/clear-tracking.sh && ! test -e scripts/port.sh`.
- [ ] All seven exist at the canonical skill-dir location AND the
      mirror (loop test as in original Phase 3 AC; preserved verbatim
      in Phase 3b ACs below).
- [ ] All seven executable bits preserved.
- [ ] **`port.sh` config-driven default_port:**
      `grep -F 'default_port' skills/update-zskills/scripts/port.sh | wc -l` ≥ 1
      AND `grep -F 'default_port' config/zskills-config.schema.json | wc -l` ≥ 1.
- [ ] `grep -n "$SCRIPT_DIR" skills/create-worktree/scripts/create-worktree.sh` ≥ 3
      matches (gate + two same-skill invocations).
- [ ] `grep -c '$MAIN_ROOT/scripts/' skills/create-worktree/scripts/create-worktree.sh`
      = 0 (old form purged from internal logic).
- [ ] `diff -r skills/create-worktree .claude/skills/create-worktree`
      empty; same for `commit`.
- [ ] **Positive-pass invocation signal (D26 + R2.2 fix).** The moved
      `create-worktree.sh` runs from its new location and prints
      usage text:
      `bash skills/create-worktree/scripts/create-worktree.sh --help 2>&1 | grep -q -i usage`.
      This is the gating signal in lieu of `tests/run-all.sh` for
      Phase 3a — full `tests/run-all.sh` green is INTENTIONALLY
      deferred to Phase 3b (see Design note above).

### Dependencies

Phases 1, 2.

## Phase 3b — Update cross-skill callers via grep-driven sweep

### Goal

Update every cross-skill caller of the five shared Tier 1 scripts.
Phase 3a left the source tree with scripts moved + same-skill
internals updated, but cross-skill callers in `do`, `fix-issues`,
`quickfix`, `research-and-plan`, `research-and-go`, `run-plan`,
`commit/modes/land.md` (cross-skill ref because it's a markdown
recipe, not a same-script call) all still name the old paths. This
phase sweeps and updates them.

### Work Items

- [ ] 3b.1 — **Grep-driven cross-skill sweep, all seven scripts.**
      For each of `{sanitize-pipeline-id, create-worktree, land-phase,
      write-landed, worktree-add-safe, clear-tracking, port}`, run:
      ```bash
      grep -rn 'scripts/<name>' skills/ .claude/skills/ CLAUDE.md README.md RELEASING.md
      ```
      Update EVERY match to the cross-skill form. Distinguish two
      patterns currently in use, both becoming the same target
      (bare `$CLAUDE_PROJECT_DIR` form per Phase 1 Design;
      round-5 dropped the earlier `:-$MAIN_ROOT` fallback):
      - bare `scripts/<name>` →
        `$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<name>`
      - `$MAIN_ROOT/scripts/<name>` →
        `$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<name>`

      Same-skill internal callers (in scripts themselves, e.g.,
      `create-worktree.sh` invoking peer scripts) use `$SCRIPT_DIR/<name>`
      instead — these were handled in Phase 3a.

      **SNAPSHOT AT DRAFT TIME — DO NOT USE AS ACTION LIST.
      RE-RUN THE GREP.** The line numbers below are a sanity check
      to compare against your live grep output (does the grep find
      AT LEAST these matches?), NOT the spec. Authoritative truth =
      the recursive grep above; line numbers stale on first edit.

      - `create-worktree.sh` callers verified by
        `grep -rn 'scripts/create-worktree\.sh' skills/` returns 14
        matches across `skills/create-worktree/SKILL.md:7,16,34,100`,
        `skills/do/modes/pr.md:73`, `skills/do/modes/worktree.md:9,45,52`,
        `skills/fix-issues/SKILL.md:682,797,852`,
        `skills/run-plan/SKILL.md:708,712,902,911`. Both invocations
        and prose mentions update.
      - `sanitize-pipeline-id.sh` callers verified by
        `grep -rn 'scripts/sanitize-pipeline-id' skills/` returns
        `skills/create-worktree/SKILL.md:93` (prose mention; updates
        to cross-skill form even though same-skill, because the
        SKILL.md is markdown — the same-skill `$SCRIPT_DIR` form
        only applies inside bash scripts, not skill prose),
        `skills/do/modes/pr.md:61`,
        `skills/fix-issues/SKILL.md:445`,
        `skills/quickfix/SKILL.md:355` (uses `$MAIN_ROOT/scripts/...` —
        same target),
        `skills/research-and-go/SKILL.md:74`,
        `skills/research-and-plan/SKILL.md:336`.
      - `write-landed.sh` callers verified by
        `grep -rn 'scripts/write-landed' skills/`:
        `skills/commit/modes/land.md:50`,
        `skills/fix-issues/modes/cherry-pick.md:67,77`,
        `skills/fix-issues/modes/direct.md:53,81,100,120`,
        `skills/fix-issues/modes/pr.md:33,105,137`,
        `skills/fix-issues/references/failure-protocol.md:115`,
        `skills/run-plan/modes/cherry-pick.md:113`,
        `skills/run-plan/modes/pr.md:63,136,238,252,307,640`.
      - `land-phase.sh` callers verified by
        `grep -rn 'scripts/land-phase' skills/`:
        `skills/create-worktree/SKILL.md:95`,
        `skills/fix-issues/modes/pr.md:155`,
        `skills/run-plan/SKILL.md:507,512,756,763`,
        `skills/run-plan/modes/cherry-pick.md:121,123`,
        `skills/run-plan/modes/pr.md:656`.
      - `clear-tracking.sh` callers verified by
        `grep -rn 'scripts/clear-tracking' skills/`:
        `skills/research-and-go/SKILL.md:294`,
        `skills/run-plan/SKILL.md:1551,1569`. Each becomes
        `bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/clear-tracking.sh"`.
      - `port.sh` callers verified by
        `grep -rn 'scripts/port' skills/`:
        `skills/briefing/SKILL.md:129`,
        `skills/fix-report/SKILL.md:163,365`,
        `skills/manual-testing/SKILL.md:25`,
        `skills/update-zskills/SKILL.md:326,414,704`
        (the last three are dependency-check / install prose),
        `skills/verify-changes/SKILL.md:438`. Each becomes
        `bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/port.sh"`.

      Authoritative truth = the grep (re-run in the implementing
      session); the line lists above are a snapshot at draft time.
- [ ] 3b.2 — **Update CLAUDE.md and README.md script mentions.**
      `grep -n 'scripts/land-phase\|scripts/sanitize-pipeline-id\|scripts/write-landed\|scripts/create-worktree\|scripts/worktree-add-safe' CLAUDE.md README.md`
      shows:
      - `CLAUDE.md:11` (helper-scripts overview list)
      - `CLAUDE.md:44` (mention of `scripts/land-phase.sh` removing
        per-worktree dir)
      - `CLAUDE.md:151` (mention of `scripts/sanitize-pipeline-id.sh`)
      - `CLAUDE.md:154` (mention of `scripts/write-landed.sh`)
      - `README.md:275` (mention of `scripts/write-landed.sh`)
      - `README.md:455-465` (helper-scripts list — now mostly
        Tier-1; rewriting handled by Phase 5 WI 5.5.d).

      Update each: prose-form path becomes either
      `.claude/skills/<owner>/scripts/<name>` or "the script bundled
      in the `<owner>` skill" (CLAUDE.md and README.md are
      human-facing — agents read CLAUDE.md but it doesn't `bash`
      execute; consumers don't invoke scripts via README path-strings
      directly).

      For `CLAUDE.md:11` (helper-scripts overview): rewrite to
      `scripts/ — consumer-customizable stubs (stop-dev.sh,
      test-all.sh) and release-only repo tooling (build-prod.sh);
      skill machinery (including port.sh, clear-tracking.sh,
      statusline.sh) moved to .claude/skills/<owner>/scripts/`.
- [ ] 3b.3 — **Update cross-skill `sanitize-pipeline-id.sh` callers.**
      Driven by 3b.1 grep. Each becomes
      `bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "$ARG"`
      (bare `$CLAUDE_PROJECT_DIR` form per Phase 1 Design).
- [ ] 3b.4 — **Update cross-skill `create-worktree.sh` callers.**
      Driven by 3b.1 grep. Each
      `bash "$MAIN_ROOT/scripts/create-worktree.sh"` becomes
      `bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh"`.
- [ ] 3b.5 — **Update cross-skill `land-phase.sh` callers.**
      Driven by 3b.1 grep. Each `bash scripts/land-phase.sh` becomes
      `bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/land-phase.sh"`.
- [ ] 3b.6 — **Update cross-skill `write-landed.sh` callers.**
      Driven by 3b.1 grep. Each becomes
      `bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh"`.
- [ ] 3b.6b — **Update cross-skill `clear-tracking.sh` and `port.sh`
      callers.** Driven by 3b.1 grep. Each `bash scripts/<name>` (or
      `$(bash scripts/port.sh)` interpolation) becomes
      `bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/<name>"`.

      For the `update-zskills/SKILL.md` self-references:

      - **3b.6b.x — Update Step C bullet at
        `skills/update-zskills/SKILL.md:704`.** Current text reads
        "For `scripts/port.sh` and `scripts/test-all.sh`: copy
        as-is from `$PORTABLE/scripts/`." Split the bullet:
        remove the `port.sh` half (port.sh is now Tier-1, ships
        via the skill mirror, never copied to consumer
        `scripts/`); keep the `test-all.sh` half (Tier-2, still
        copied). New bullet text:

        ```
        - For `scripts/test-all.sh`: copy as-is from
          `$PORTABLE/scripts/`. Reads `testing.unit_cmd` from
          `.claude/zskills-config.json` at runtime — no
          install-time fill. (Tier-2 placeholder; consumer
          customizes.)
        ```

        AC: `! grep -F 'scripts/port.sh' skills/update-zskills/SKILL.md`
        (post-3b.6b, the SKILL no longer references the old path).
      - **`:414` (dependency check prose).** Update path-string to
        the new home (skill-mirror location).
      - **`:326` (config-table `{{PORT_SCRIPT}}` row).** SKIP in
        Phase 3b — Phase 5 WI 5.5.a deletes the row entirely
        (along with the `port_script` schema property and the
        greenfield-template field). No half-update needed here;
        avoiding two-step churn on a row that's about to be
        removed.
- [ ] 3b.7 — **Hook help-text update (NEW).** Hooks
      `hooks/block-unsafe-project.sh.template` and the
      `.claude/hooks/block-unsafe-project.sh` mirror print user-facing
      block-reason strings instructing the user to `! bash
      scripts/clear-tracking.sh`. Update each to point at the new
      location.

      Authoritative grep at draft time:
      `grep -n 'scripts/clear-tracking' hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh`
      shows lines 89, 91, 103, 114, 194, 208 in each file (line 203
      and line 205-206 are the regex-match pattern, NOT user-facing
      help-text — DO NOT edit those).

      For each user-facing help-text line, change
      `! bash scripts/clear-tracking.sh` →
      `! bash .claude/skills/update-zskills/scripts/clear-tracking.sh`.

      **Compatibility constraints (per `feedback_hook_skill_interaction.md`):**
      - The leading-space pattern at `:203` (`echo "Run: bash scripts/clear-tracking.sh"`)
        is documentation explaining that the regex `_CT_EXEC_CMD` at
        `:205` correctly distinguishes a command-verb `bash` from
        `bash` inside an echo string. Read the comment block at
        `:198-208` to confirm; the regex match logic does not depend
        on the `scripts/` prefix in the help-text strings, only on
        the `bash <something>clear-tracking` pattern. Updating the
        help-text to point at the new path therefore does NOT change
        regex behavior — verify by mental-running both regexes
        against `! bash .claude/skills/update-zskills/scripts/clear-tracking.sh`
        (matches `_CT_EXEC_CMD` because `bash` is preceded by `!` /
        start of input, followed by space, followed by a path
        containing `clear-tracking`).
      - Hook help-text is plain literal strings; no
        `$CLAUDE_PROJECT_DIR` expansion is attempted in the print —
        a literal `.claude/skills/update-zskills/scripts/clear-tracking.sh`
        is correct relative to the consumer repo root, which is the
        cwd where the hook fires.

      Note: `stop-dev.sh` references in `hooks/block-unsafe-generic.sh:159,177`
      are UNCHANGED (Tier-2 stays at `scripts/`).
- [ ] 3b.8 — Mirror touched skills (now nine):
      ```bash
      for s in run-plan fix-issues do quickfix research-and-plan research-and-go briefing fix-report manual-testing verify-changes; do
        rm -rf .claude/skills/$s && cp -a skills/$s/ .claude/skills/$s/
      done
      ```
      Plus re-mirror `create-worktree`, `commit`, and `update-zskills`
      if 3b prose edits touched their SKILL.md/modes.

      Also mirror the hook (Phase 3b WI 3b.7):
      `cp hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh`
      then `chmod +x` (verify with
      `diff hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh | head`).
- [ ] 3b.9 — Update tests that copy these scripts into fixture trees:
      - `tests/test-create-worktree.sh:834-836` (currently copies
        `scripts/sanitize-pipeline-id.sh` and `scripts/worktree-add-safe.sh`
        into a fixture worktree; switch to
        `"$REPO_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh"`
        and `"$REPO_ROOT/skills/create-worktree/scripts/worktree-add-safe.sh"`).
      - `tests/test-quickfix.sh:139-140` (currently copies
        `scripts/sanitize-pipeline-id.sh`; switch to
        `"$REPO_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh"`).
      - `tests/test-canary-failures.sh:139,147,198,201` (paths to
        `land-phase.sh` and `write-landed.sh`; switch to
        `"$REPO_ROOT/skills/commit/scripts/<name>"`).

      MANDATE the absolute `$REPO_ROOT/skills/<owner>/scripts/<name>`
      form. The bare-relative form is FORBIDDEN.
- [ ] 3b.10 — `bash tests/run-all.sh`. Expect green.

### Design & Constraints

**Grep-driven, not enumeration-driven.** Per R8/D3/D10 (major):
prior draft enumerated specific line numbers (`run-plan:712, :911`)
and missed 10+ prose mentions. The authoritative truth for "did we
get them all" is the recursive grep, not a curated list. WIs above
list line numbers only as worked examples; the grep at the start of
each WI drives actual edits.

**Cross-skill path is the longer form.** `bash
"$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<name>"`
is more typing than `bash scripts/<name>`. Accepted: the current
short form silently breaks when consumers do not have the script
(which is exactly what `/update-zskills` Phase 4 will stop
installing). The explicit path is worth the verbosity.

**`$CLAUDE_PROJECT_DIR` env propagation.** `CLAUDE_PROJECT_DIR` is
set by Claude Code in all spawned bash blocks. For zskills' own
tests (which run outside the harness), `tests/run-all.sh` exports
`CLAUDE_PROJECT_DIR="$REPO_ROOT"` (Phase 5 WI 5.7).

**Bare `$CLAUDE_PROJECT_DIR` form — no fallback (round-5 fix).**
The earlier round's `:-$MAIN_ROOT` fallback (round-4 form)
added complexity without value. Many cross-skill callsites in
skill prose (notably the four `port.sh` callers in `briefing`,
`manual-testing`, `fix-report`, `verify-changes`) are bare prose
snippets with NO `MAIN_ROOT` in scope; the fallback there
silently expands to an empty path (`/.claude/skills/...`,
absolute root) — a worse failure mode than a loud unset-variable
error. Every cross-skill caller uses the bare form:

```bash
bash "$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<name>"
```

Trust the harness contract. The harness sets it; tests export it.
If `CLAUDE_PROJECT_DIR` is unset at a callsite, fail loud. WIs
3b.3-3b.6 use this form verbatim; WI 3b.1 grep-driven sweep
applies the same form to every match.

**Tests update with the move.** Tests live in `tests/` and continue
to call from absolute paths anchored on `$REPO_ROOT`. They now read
from `skills/<owner>/scripts/`. This is a real change — the source
tree's `scripts/` directory no longer holds the canonical copy of
Tier 1 scripts. zskills' own test harness is therefore aware of the
move.

**Mirror discipline.** Per Phase 1.

### Acceptance Criteria

- [ ] All seven Tier 1 scripts at the canonical skill-dir location AND
      the mirror:
      ```bash
      for f in \
        skills/create-worktree/scripts/create-worktree.sh \
        skills/create-worktree/scripts/worktree-add-safe.sh \
        skills/create-worktree/scripts/sanitize-pipeline-id.sh \
        skills/commit/scripts/land-phase.sh \
        skills/commit/scripts/write-landed.sh \
        skills/update-zskills/scripts/clear-tracking.sh \
        skills/update-zskills/scripts/port.sh \
        .claude/skills/create-worktree/scripts/create-worktree.sh \
        .claude/skills/create-worktree/scripts/worktree-add-safe.sh \
        .claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh \
        .claude/skills/commit/scripts/land-phase.sh \
        .claude/skills/commit/scripts/write-landed.sh \
        .claude/skills/update-zskills/scripts/clear-tracking.sh \
        .claude/skills/update-zskills/scripts/port.sh; do
        test -f "$f" || { echo MISSING "$f"; exit 1; }; done
      ```
- [ ] **Recursive zero-match for old paths everywhere** (this is the
      authoritative completeness measure, replacing the loose `≥ N`
      thresholds per R9):
      ```bash
      grep -rn 'scripts/create-worktree\.sh\|scripts/worktree-add-safe\.sh\|scripts/sanitize-pipeline-id\.sh\|scripts/land-phase\.sh\|scripts/write-landed\.sh\|scripts/clear-tracking\.sh\|scripts/port\.sh' skills/ .claude/skills/ CLAUDE.md README.md
      ```
      returns zero matches. (RELEASING.md already excluded — Tier-1
      scripts have no RELEASING references; verified by grep at draft
      time.)
- [ ] **Hook help-text updated for `clear-tracking.sh`:**
      `grep -c 'scripts/clear-tracking' hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh`
      shows ONLY the regex-pattern lines (lines 205-206 — `_CT_EXEC_CMD`
      / `_CT_EXEC_DIR` regex strings) and the explanatory comment at
      `:203`; help-text strings now point at the new location:
      `grep -c '\.claude/skills/update-zskills/scripts/clear-tracking' hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh`
      ≥ 6 each (six help-text lines: 89, 91, 103, 114, 194, 208).
- [ ] **`stop-dev.sh` hook references unchanged (Tier-2 stays):**
      `grep -c 'scripts/stop-dev' hooks/block-unsafe-generic.sh` ≥ 2
      (verifies we did not over-edit the hook — only `clear-tracking`
      lines change).
- [ ] **Recursive zero-match for `$MAIN_ROOT/scripts/<tier-1>` form
      (old `quickfix` and `create-worktree` SKILL.md style):**
      ```bash
      grep -rn '\$MAIN_ROOT/scripts/\(create-worktree\|sanitize-pipeline-id\|worktree-add-safe\|land-phase\|write-landed\)' skills/ .claude/skills/
      ```
      returns zero matches.
- [ ] All touched mirrors are clean:
      `for s in create-worktree commit update-zskills run-plan fix-issues do quickfix research-and-plan research-and-go briefing fix-report manual-testing verify-changes; do diff -r skills/$s .claude/skills/$s || exit 1; done`.
- [ ] **`bash tests/run-all.sh` exits 0** (including
      `test-create-worktree.sh`, `test-quickfix.sh`,
      `test-canary-failures.sh`). NOTE: requires
      `CLAUDE_PROJECT_DIR` exported by `tests/run-all.sh` per Phase 5
      WI 5.7 (or set manually if Phase 5 hasn't landed yet).

(Removed: redundant `grep -rn 'CLAUDE_SKILL_DIR' ... = 0` AC — this
duplicates Phase 1's dead-ref AC per R17. Phase 1 leaves zero; this
phase's edits do not introduce new `CLAUDE_SKILL_DIR` mentions
because the canonical form is `$CLAUDE_PROJECT_DIR`. If a regression
check is desired, the Phase 1 AC already covers it.)

### Dependencies

Phases 1, 2, 3a.

## Phase 4 — Update `/update-zskills` install flow and add stale-Tier-1 migration

### Goal

(a) Stop copying Tier 1 scripts into consumer `scripts/`. Consumers
receive them via the existing skill-mirror path
(`.claude/skills/<owner>/scripts/<name>`). (b) Detect stale Tier 1
scripts on consumer disk left over from prior installs and offer to
remove them after verifying they match a known zskills version.

### Work Items

- [ ] 4.1 — **Edit `skills/update-zskills/SKILL.md` Step D.** Per R4
      verification (`sed -n '895,910p' skills/update-zskills/SKILL.md`),
      Step D currently lists THREE scripts: `clear-tracking.sh`,
      `apply-preset.sh`, `stop-dev.sh`. After this refactor:
      - REMOVE the `apply-preset.sh` bullet (Tier-1, ships via skill
        mirror after Phase 2).
      - REMOVE the `clear-tracking.sh` bullet (Tier-1 after the
        scope adjustment, ships via skill mirror after Phase 3a/3b).
      - KEEP the `stop-dev.sh` bullet (Tier-2; consumer-customizable
        stub).
      - ADD bullets for `test-all.sh` if not already present (Tier-2;
        consumer-customizable stub with `{{E2E_TEST_CMD}}`
        placeholders) — verify by reading Step D's current prose; do
        NOT introduce a duplicate bullet if `test-all.sh` is already
        named.
      - ADD a closing note: "Tier-1 scripts (skill machinery, e.g.,
        `port.sh`, `clear-tracking.sh`, `statusline.sh`,
        `apply-preset.sh`, briefing helpers, worktree helpers) ship
        via the skill mirror at `.claude/skills/<owner>/scripts/`.
        They are NOT copied to `scripts/`. See
        `references/script-ownership.md` for the full table."

      The acceptance criterion below uses zero-match-of-Tier-1 names
      in Step D rather than a per-script regex, so adding/removing
      bullets within Tier-2 won't trip it.
- [ ] 4.2 — **Generate `skills/update-zskills/references/tier1-shipped-hashes.txt`.**
      Per R3 (major) and D8 (major): `git log --all` on a fresh
      auto-clone of `/tmp/zskills` only sees one branch; tarball
      installs see no history at all. Switch to a static
      hashes-file shipped IN the source tree.

      Generate the file once during Phase 4 by running, against the
      zskills repo (any working clone with full history). Per R2.3:
      the Tier-1 name list is parsed from `script-ownership.md` (the
      single source of truth), NOT hardcoded — eliminating the
      three-way drift risk between ownership table, generation loop,
      and STALE_LIST array:
      ```bash
      OUT=skills/update-zskills/references/tier1-shipped-hashes.txt
      : > "$OUT"

      # Single source of truth: parse Tier-1 names from
      # script-ownership.md (column 2 where column 3 == "1").
      TIER1_NAMES=$(awk -F'|' '$3 ~ /^[[:space:]]*1[[:space:]]*$/ {
        gsub(/[[:space:]`]/, "", $2); print $2
      }' skills/update-zskills/references/script-ownership.md)

      for name in $TIER1_NAMES; do
        # Tier-1 scripts may live at scripts/<name> (pre-Phase-3) or
        # skills/<owner>/scripts/<name> (post-Phase-3). Enumerate
        # blob hashes from both locations across all branches.
        for path in "scripts/$name" "skills/*/scripts/$name"; do
          git log --all --pretty=format:%H -- $path \
            | while read commit; do
                git rev-parse "${commit}:${path}" 2>/dev/null
              done
        done
      done | sort -u > "$OUT.raw"

      # LF-normalize (D25 fix). Each line is already a hex sha (no
      # CRLF risk in the hash output itself), but for any future
      # generator that emits multi-byte content, normalize on
      # write. Verify: every line is a 40-char hex sha.
      tr -d '\r' < "$OUT.raw" > "$OUT"
      rm "$OUT.raw"
      grep -v '^[0-9a-f]\{40\}$' "$OUT" && { echo "non-hash lines"; exit 1; }
      ```

      **Hash content normalization (D25 fix).** All hashes in
      `tier1-shipped-hashes.txt` are computed against LF-normalized
      file content — `git hash-object` on a tree blob already
      reflects whatever content was committed (which on the zskills
      release machine is LF). On the CONSUMER side (WI 4.4),
      `git hash-object --stdin` is fed `tr -d '\r' < target`, so
      Windows checkouts with core.autocrlf=true compute the same
      LF-normalized hash and match the release file. Cross-platform
      coverage is exercised by test case 1/2 in WI 4.8 (fixtures
      with both LF and CRLF endings — see WI 4.8 below).

      Mirror the file: also placed at
      `.claude/skills/update-zskills/references/tier1-shipped-hashes.txt`
      via the standard skill mirror.

      `build-prod.sh` is intentionally NOT in this list — Tier 2,
      stays at `scripts/`, never migrated off (and `script-ownership.md`
      column 3 = "2", so the awk parser excludes it automatically).
- [ ] 4.3 — **Add a CI / test check that
      `tier1-shipped-hashes.txt` is regenerated when a Tier-1 script
      changes.** Implemented as test case 6c in WI 4.8 below
      (commit-cohabitation check, D23 fix — replaced the original
      regenerate-and-diff approach because it's environmentally
      non-deterministic on shallow CI clones). Case 6c asserts that
      the last commit touching any Tier-1 script is an ancestor of
      the last commit touching the hash file — i.e., the hash file
      was regenerated AFTER the last script change.
- [ ] 4.4 — **Add a new sub-step "Step D.5 — Migrate stale Tier-1
      scripts" immediately after Step D.** Spec:
      ````markdown
      #### Step D.5 — Migrate stale Tier-1 scripts

      Earlier zskills versions copied skill-machinery scripts to the
      consumer's `scripts/`. Detect any leftover copies and offer to
      remove them after verifying they match a known zskills version
      (so a user-modified script is preserved with a warning).

      The STALE_LIST is the Tier-1 column of
      `references/script-ownership.md`:

      ```bash
      STALE_LIST=(
        apply-preset.sh
        briefing.cjs
        briefing.py
        clear-tracking.sh
        compute-cron-fire.sh
        create-worktree.sh
        land-phase.sh
        port.sh
        post-run-invariants.sh
        sanitize-pipeline-id.sh
        statusline.sh
        worktree-add-safe.sh
        write-landed.sh
      )
      ```

      Note: `statusline.sh` is a **defensive entry**. The current
      Step C.5 copies `statusline.sh` directly from
      `$PORTABLE/scripts/` to `~/.claude/statusline-command.sh`
      (no intermediate consumer-side `scripts/statusline.sh`
      step). However, consumers may have a leftover
      `scripts/statusline.sh` from manual copies, third-party
      tutorials, or pre-refactor experiments. Defensive migration:
      matches → MIGRATE; user-modified → KEPT. Expect this entry
      to be a no-op for most consumers (the live install at
      `~/.claude/statusline-command.sh` is separate and
      unaffected).

      (Note: `build-prod.sh` is NOT in STALE_LIST — it is Tier-2 repo
      tooling consumed by `.github/workflows/ship-to-prod.yml`, not
      skill machinery. Verified by R1/D1.)

      ```bash
      KNOWN_HASHES=$PORTABLE/.claude/skills/update-zskills/references/tier1-shipped-hashes.txt
      DEFER_MARKER=.zskills/tier1-migration-deferred

      MIGRATED=()
      KEPT=()
      for name in "${STALE_LIST[@]}"; do
        target="scripts/$name"
        [ -f "$target" ] || continue

        # git is required (Phase 4 preconditions). git hash-object works
        # on any file regardless of whether it is in a repo.
        # CRLF-normalize for cross-platform consumer compat (D25 fix —
        # Windows consumers with core.autocrlf=true store files as LF
        # in the index but check out as CRLF; raw `git hash-object`
        # would hash the CRLF bytes and never match the LF-hashed
        # release file). Strip \r before hashing through stdin.
        consumer_hash=$(tr -d '\r' < "$target" | git hash-object --stdin)

        # Match against the static, version-shipped hashes file.
        if [ -f "$KNOWN_HASHES" ] && grep -qxF "$consumer_hash" "$KNOWN_HASHES"; then
          MIGRATED+=("$name")
        else
          KEPT+=("$name")
        fi
      done

      if [ "${#MIGRATED[@]}" -gt 0 ]; then
        echo "Found ${#MIGRATED[@]} stale Tier-1 script(s) at scripts/ that"
        echo "match a known zskills version. These now ship via skill mirrors."
        printf '  - %s\n' "${MIGRATED[@]}"
        read -r -p "Remove? [y/N] " ans
        if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
          for name in "${MIGRATED[@]}"; do
            rm -- "scripts/$name" \
              && echo "removed scripts/$name" \
              || { echo "ERROR: rm scripts/$name failed" >&2; exit 1; }
          done
        else
          echo "Kept. To migrate later, re-run /update-zskills."
        fi
      fi

      # The defer marker is a NEWLINE-DELIMITED LIST of deferred
      # filenames (D24 fix — boolean marker permanently muted future
      # Tier-1 additions; per-file list re-prompts when a NEW Tier-1
      # filename appears in KEPT).
      DEFERRED_NAMES=()
      if [ -f "$DEFER_MARKER" ]; then
        while IFS= read -r line; do
          [ -n "$line" ] && DEFERRED_NAMES+=("$line")
        done < "$DEFER_MARKER"
      fi

      # Filter KEPT to only files NOT already deferred.
      KEPT_NEW=()
      for name in "${KEPT[@]}"; do
        skip=0
        for d in "${DEFERRED_NAMES[@]}"; do
          [ "$name" = "$d" ] && skip=1 && break
        done
        [ "$skip" -eq 0 ] && KEPT_NEW+=("$name")
      done

      if [ "${#KEPT_NEW[@]}" -gt 0 ]; then
        echo "WARNING: ${#KEPT_NEW[@]} Tier-1 script(s) at scripts/ do NOT match"
        echo "any known zskills version (likely user-modified). NOT removing."
        printf '  - %s\n' "${KEPT_NEW[@]}"
        echo
        echo "Review each: if your modifications are still needed, port them"
        echo "into a skill subdir (.claude/skills/<owner>/scripts/) and delete"
        echo "the scripts/ copy. If they were unintentional, delete the file."
        echo "To defer these files on subsequent /update-zskills runs:"
        echo "  mkdir -p .zskills"
        for name in "${KEPT_NEW[@]}"; do
          echo "  echo $name >> $DEFER_MARKER"
        done
        echo "(Future Tier-1 additions NOT in this list will re-prompt.)"
      fi
      ```
      ````

      **Hash-file location and tarball compatibility (D8 fix).**
      `$KNOWN_HASHES` reads from `$PORTABLE/.claude/skills/update-zskills/references/tier1-shipped-hashes.txt` —
      a file that ships INSIDE the zskills repo and is therefore
      present in tarball installs (it's just a file, no `.git`
      required). Tarball installs now have a working hash check, not
      a defensive empty-known-hashes path that classifies every file
      KEPT.

      **Defer marker (D8 + D24).** If the consumer has user-modified
      Tier-1 scripts they intend to keep, they record those filenames
      in `.zskills/tier1-migration-deferred` (one per line) to
      suppress the warning for THOSE FILES on subsequent runs. Per
      D24: the marker is a per-file list, NOT a boolean. When zskills
      ships a new Tier-1 entry six months later, the consumer's
      existing defer list does NOT mute it — the new filename
      re-prompts because it's not in the list. The `MIGRATED` flow
      still runs unconditionally (it lists files that DO match
      upstream); only the `KEPT` warning is filtered against the
      deferred list. Append-only on user defer (do not overwrite).

      **No silent error suppression.** Per CLAUDE.md
      (`Never suppress errors on operations you need to verify`):
      `git hash-object` is NOT wrapped in `2>/dev/null || ...` —
      if git is missing the script fails loudly. The `rm` call uses
      `&& echo ... || { echo ERROR; exit 1; }`, not `2>/dev/null`.
      The `read -r -p` prompt is explicit (no silent default).
- [ ] 4.5 — **Verify Step C.5 (statusline) source-path edit landed
      from Phase 2 WI 2.7b.** `statusline.sh` is Tier 1 (per scope
      adjustment); WI 2.7b updated Step C.5 line 891 from
      `$PORTABLE/scripts/statusline.sh` to
      `$PORTABLE/.claude/skills/update-zskills/scripts/statusline.sh`.
      The install destination at `~/.claude/statusline-command.sh` is
      unchanged. This WI is regression-only: re-grep
      `grep -n statusline skills/update-zskills/SKILL.md` and verify
      no occurrence references `scripts/statusline.sh` (bare) or
      `$PORTABLE/scripts/statusline.sh`.
- [ ] 4.6 — **Verify Phase 2 dependency-check edits remain in place.**
      Per R10: WI 4.4-original duplicated WI 2.5. Phase 2 already
      rewrites `:410-411, :487-489, :533, :971`. This WI is the
      regression check: re-grep `grep -n 'briefing\.cjs\|briefing\.py' skills/update-zskills/SKILL.md`
      and verify no occurrence references `scripts/briefing.*`. No
      edit expected.
- [ ] 4.7 — Mirror update-zskills:
      `rm -rf .claude/skills/update-zskills && cp -a skills/update-zskills/ .claude/skills/update-zskills/`.
- [ ] 4.8 — **Add a test for Step D.5 migration logic.** New file
      `tests/test-update-zskills-migration.sh` with these cases:
      1. Consumer `scripts/create-worktree.sh` matches a historical
         zskills hash with **LF endings** (use a hash from
         `tier1-shipped-hashes.txt`, copy that exact blob to fixture
         path) → MIGRATED list contains it; after `y` confirmation
         the file is removed.
      2. Consumer `scripts/create-worktree.sh` modified by user (one
         line different from any shipped hash) → KEPT list contains
         it; file preserved.
      2b. **Cross-platform CRLF fixture (D25 fix).** Same shipped
         content as case 1, but with CRLF endings on disk
         (`sed -i 's/$/\r/' fixture/scripts/create-worktree.sh` or
         `unix2dos`). The migration's `tr -d '\r' | git hash-object
         --stdin` MUST produce the LF-equivalent hash and classify
         this fixture as MIGRATED. Asserts cross-platform parity
         (Windows consumers with core.autocrlf=true).
      2c. **New Tier-1 scripts: hash-matched migrate.** Three
         additional fixtures, one each for `scripts/port.sh`,
         `scripts/clear-tracking.sh`, `scripts/statusline.sh` —
         each populated with a hash from
         `tier1-shipped-hashes.txt`. Each → MIGRATED list contains
         it; after `y` confirmation the file is removed.
         (`statusline.sh` migrate-on-match is expected to be
         uncommon in practice — see WI 4.4 note explaining its
         defensive STALE_LIST inclusion. The fixture exercises
         the code path; real consumers are unlikely to have
         `scripts/statusline.sh` matching a known hash.)
      2d. **New Tier-1 scripts: user-modified KEPT.** Three
         additional fixtures (same names as 2c), each with a
         user-modified line. Each → KEPT list contains it; file
         preserved.
      3. Consumer `scripts/foo.sh` not in STALE_LIST → ignored
         (does not appear in either list).
      4. `$KNOWN_HASHES` file is missing (deliberately removed) →
         every existing Tier-1 file is KEPT (defensive default —
         never remove without verification).
      5. User answers `n` to the prompt → file preserved; report says
         "Kept".
      6. **STALE_LIST drift + hash-file format + commit-cohabitation.**
         This case has three independently asserted parts; the original
         "regenerate from `git log --all` and diff" approach is
         REPLACED — it is environmentally non-deterministic on shallow
         clones (`actions/checkout@v4` defaults to `fetch-depth: 1`,
         per D23) and varies with developer-local branch state.

         **6a. STALE_LIST drift (D27 fix — explicit parsers).**
         `script-ownership.md` is the SINGLE SOURCE OF TRUTH; parse
         BOTH lists with the recipes pinned here so future format
         changes break the test rather than silently passing:
         ```bash
         # Parse Tier-1 names from script-ownership.md (column 2 of
         # the markdown table where column 3 is "1").
         TIER1_FROM_DOC=$(awk -F'|' '$3 ~ /^[[:space:]]*1[[:space:]]*$/ {
           gsub(/[[:space:]`]/, "", $2); print $2
         }' skills/update-zskills/references/script-ownership.md | sort)

         # Extract STALE_LIST array from SKILL.md (everything between
         # `STALE_LIST=(` and the matching `)`).
         TIER1_FROM_LIST=$(awk '
           /^STALE_LIST=\(/ { f=1; next }
           /^\)/ { f=0 }
           f { gsub(/[[:space:]]/, ""); print }
         ' skills/update-zskills/SKILL.md | sort)

         diff <(echo "$TIER1_FROM_DOC") <(echo "$TIER1_FROM_LIST") || {
           echo "DRIFT: STALE_LIST out of sync with script-ownership.md"
           exit 1
         }
         ```

         **6b. Hash-file format check (D23 fix).**
         Every line in `tier1-shipped-hashes.txt` must be a 40-char
         lowercase hex sha; no blanks, no extras:
         ```bash
         while IFS= read -r line; do
           [[ "$line" =~ ^[a-f0-9]{40}$ ]] || {
             echo "Bad line in tier1-shipped-hashes.txt: $line"
             exit 1
           }
         done < skills/update-zskills/references/tier1-shipped-hashes.txt
         ```

         **6c. Commit-cohabitation (D23 fix — replaces the brittle
         regenerate-and-diff).** When a Tier-1 script changes, the
         hash file must change in the same commit (or later). Equiv:
         the last commit that touched the hash file must NOT be an
         ancestor of any Tier-1 script's last-touched commit.
         ```bash
         # Skip on shallow clones (CI's actions/checkout@v4 default).
         if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
           echo "warning: shallow clone; skipping commit-cohabitation check"
         else
           LAST_HASH_COMMIT=$(git log -1 --pretty=format:%H \
             -- skills/update-zskills/references/tier1-shipped-hashes.txt)
           for name in $TIER1_FROM_DOC; do
             # Tier-1 scripts may live at scripts/<name> (pre-Phase-3)
             # OR skills/<owner>/scripts/<name> (post-Phase-3).
             LAST_SCRIPT_COMMIT=$(git log -1 --pretty=format:%H \
               -- "scripts/$name" "skills/*/scripts/$name")
             [ -z "$LAST_SCRIPT_COMMIT" ] && continue
             if ! git merge-base --is-ancestor \
                  "$LAST_SCRIPT_COMMIT" "$LAST_HASH_COMMIT"; then
               echo "Tier-1 script $name changed after hash file regenerated"
               exit 1
             fi
           done
         fi
         ```
         Document: case 6c only runs when full git history is present
         (`git rev-parse --is-shallow-repository` returns false). On
         shallow clones, skip with a warning, do not fail.

      Use `/tmp/zskills-tests/$(basename "$(pwd)")/` per the
      test-output idiom in CLAUDE.md.
- [ ] 4.9 — Register the new test in `tests/run-all.sh` (alphabetical
      with siblings).
- [ ] 4.10 — `bash tests/run-all.sh`.

### Design & Constraints

**git is required.** `git hash-object --stdin` (fed CRLF-normalized
content) is the migration-side hash function. If git is not on
PATH, the migration fails fast — same precondition as the existing
`apply-preset.sh` toolchain (per memory
`feedback_no_premature_backcompat.md`, no fallback machinery for
git-less environments; CLAUDE.md mentions git pervasively). The R2/D7
draft used `git -C "$target".. hash-object` (malformed: `git -C`
chdir target is `<file>..` which fails) with a `sha1sum` fallback
(different hash algorithm — `git hash-object` prepends `blob <size>\0`
before SHA-1, `sha1sum` does not, so they NEVER match). Both
branches are removed. The current canonical form is
`tr -d '\r' < "$target" | git hash-object --stdin` (D25 fix —
strips Windows CRLF before hashing so the consumer hash matches the
LF-normalized release hash; without the `tr` step every Tier-1
script on a Windows consumer with core.autocrlf=true is
mis-classified KEPT).

**Why static `tier1-shipped-hashes.txt`, not `git log --all`.** Per
R3/D8: `/update-zskills` auto-clones zskills to `/tmp/zskills` with
default refs (one branch + remote tracking). `git log --all --
scripts/<name>` only enumerates locally-known commits; refs that
shipped a Tier-1 hash on a feature branch never tagged are missed.
Tarball installs have no `.git` at all. Static hashes file shipped
inside the zskills repo (and inside the skill mirror at
`.claude/skills/update-zskills/references/`) eliminates the
git-enumeration cliff: it's just a file, present in any install
mode. Regeneration is gated by test case 6 (WI 4.8) — a Tier-1
script change requires an updated hashes file in the same commit.

**Why hash-based detection, not just filename.** Consumer may have
edited `scripts/sanitize-pipeline-id.sh` to add a project-specific
sanitization rule. Blindly removing it on update would silently
discard their work. Hash check against
`tier1-shipped-hashes.txt` (which contains every blob hash that ever
shipped a Tier-1 script) decides: in-set → exact upstream copy, safe
to remove; not-in-set → user-modified → keep + warn.

**STALE_LIST drift detection (R12/D20 + D23 + D27).** Three
independent assertions in WI 4.8 case 6:
- 6a: parse Tier-1 names from `script-ownership.md` (the single
  source of truth) and from `STALE_LIST` array in SKILL.md, sort,
  diff. Catches drift between ownership table and stale list.
  Parsers are pinned in case 6a (D27 fix — recipe explicit, not
  hand-waved).
- 6b: every line in `tier1-shipped-hashes.txt` is a 40-char hex
  sha (format check).
- 6c: commit-cohabitation — the last commit touching any Tier-1
  script must be an ancestor of the last commit touching
  `tier1-shipped-hashes.txt` (script changed → hash file
  re-generated in same/later commit). Replaces the original
  "regenerate from `git log --all`" approach (D23 fix), which was
  non-deterministic on shallow clones (`actions/checkout@v4` defaults
  to `fetch-depth: 1`) and varied with developer-local branch state.
  Case 6c skips with a warning on shallow clones; does not fail.

**Tarball install / per-file defer marker.** Per D8 + D24: tarball
installs have no `.git` to enumerate, but the static hashes file
ships INSIDE the source tree, so they have a working hash check now
(no perpetual KEPT-warning loop). For consumers with genuinely
user-modified Tier-1 scripts they intend to keep, the defer marker
is a per-file list (newline-delimited filenames); appending a name
suppresses the KEPT warning for THAT file on subsequent runs. New
Tier-1 entries that arrive in later zskills versions re-prompt
because their filenames are absent from the marker. The MIGRATED
flow still fires for files that DO match upstream — only the
user-modified warning is per-file-acknowledged.

**Why CHANGELOG / RELEASING / historical CHANGELOG are NOT swept by
this phase.** Per D12: WIs in this plan only ADD a new CHANGELOG
entry (in Phase 6); they MUST NOT edit any existing CHANGELOG row,
which describes past state correctly. RELEASING.md is consulted for
Tier-2 `build-prod.sh` (no edit) but not for Tier-1 history.

**No silent error suppression** in the migration bash. Per CLAUDE.md
(`Never suppress errors on operations you need to verify`):
`git hash-object` is NOT wrapped in `2>/dev/null` — if git is missing
the script fails loudly. The `rm` uses
`&& echo ... || { echo ERROR; exit 1; }`. The `read -r -p` prompt is
explicit (no silent default).

**Mirror discipline.** Per Phase 1.

### Acceptance Criteria

- [ ] `grep -c '^#### Step D' skills/update-zskills/SKILL.md` ≥ 1.
- [ ] **Old-Tier-1 names absent from Step D's bullet list.** Extract
      Step D body via the `f=1;next` form below (D22 fix — the
      `awk '/START/,/END/'` range form would return only the header
      line, since `^#### Step` matches the start line itself):
      ```bash
      awk '/^#### Step D —/{f=1;next} /^#### Step/{f=0} f' \
          skills/update-zskills/SKILL.md \
        | grep -E 'apply-preset|create-worktree|land-phase|write-landed|sanitize-pipeline-id|worktree-add-safe|compute-cron-fire|post-run-invariants|briefing\.|clear-tracking|port\.sh|statusline' \
        | wc -l
      ```
      = 0 (Step D no longer enumerates any Tier-1 name as a thing to
      copy — including the three reclassified scripts
      `clear-tracking.sh`, `port.sh`, `statusline.sh`).
- [ ] `grep -c '^#### Step D\.5 — Migrate stale Tier-1' skills/update-zskills/SKILL.md` = 1.
- [ ] `grep -c 'STALE_LIST' skills/update-zskills/SKILL.md` ≥ 1.
- [ ] `test -f skills/update-zskills/references/tier1-shipped-hashes.txt`
      and the file contains only 40-char hex SHA lines (no blanks):
      `! grep -v '^[0-9a-f]\{40\}$' skills/update-zskills/references/tier1-shipped-hashes.txt`.
- [ ] `test -f .claude/skills/update-zskills/references/tier1-shipped-hashes.txt`
      and `diff skills/update-zskills/references/tier1-shipped-hashes.txt .claude/skills/update-zskills/references/tier1-shipped-hashes.txt`
      is empty.
- [ ] STALE_LIST does NOT contain `build-prod.sh`:
      `! grep -E '^\s*build-prod\.sh\s*$' skills/update-zskills/SKILL.md`
      (build-prod is Tier-2 per R1/D1).
- [ ] `test -f tests/test-update-zskills-migration.sh && test -x tests/test-update-zskills-migration.sh`.
- [ ] `grep -c 'test-update-zskills-migration' tests/run-all.sh` ≥ 1.
- [ ] `bash tests/test-update-zskills-migration.sh` exits 0 (nine
      cases green: 1, 2, 2b, 2c, 2d, 3, 4, 5, 6 — case 6 has three
      sub-parts 6a/6b/6c per the WI 4.8 spec; cases 2c/2d cover the
      newly-Tier-1 scripts `port.sh`, `clear-tracking.sh`,
      `statusline.sh`).
- [ ] `bash tests/run-all.sh` exits 0.
- [ ] `diff -r skills/update-zskills .claude/skills/update-zskills`
      empty.

### Dependencies

Phases 1, 2, 3a, 3b.

## Phase 5 — Update zskills tests and sweep README/CLAUDE.md/CLAUDE_TEMPLATE

### Goal

Catch any test path that still names `scripts/<tier-1>.sh` directly,
update README and CLAUDE.md to reflect the new locations of Tier-1
scripts, and confirm hook help-text paths and CLAUDE_TEMPLATE for
Tier-2 scripts remain accurate.

### Work Items

- [ ] 5.1 — Sweep `tests/` for any remaining Tier-1 path references:
      ```bash
      grep -rn 'scripts/apply-preset\|scripts/briefing\.\|scripts/compute-cron-fire\|scripts/create-worktree\|scripts/land-phase\|scripts/post-run-invariants\|scripts/sanitize-pipeline-id\|scripts/worktree-add-safe\|scripts/write-landed' tests/
      ```
      Each match is an unmigrated test path. Update each to the
      mandated absolute form
      `"$REPO_ROOT/skills/<owner>/scripts/<name>"` (per D16; the
      bare-relative form is forbidden).
- [ ] 5.2 — Sweep `hooks/` and `.claude/hooks/` for Tier-1 mentions
      (research said zero; re-verify):
      ```bash
      grep -rn 'scripts/apply-preset\|scripts/briefing\.\|scripts/compute-cron-fire\|scripts/create-worktree\|scripts/land-phase\|scripts/post-run-invariants\|scripts/sanitize-pipeline-id\|scripts/worktree-add-safe\|scripts/write-landed' hooks/ .claude/hooks/
      ```
      Expected: zero matches. If any: file an issue (out of scope
      for this plan to rewrite hooks; report the unexpected
      finding).
- [ ] 5.3 — Verify hook help-text post-edit. After Phase 3b WI 3b.7:
      `grep -n 'clear-tracking' hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh`
      shows the user-facing help-text strings now reference
      `.claude/skills/update-zskills/scripts/clear-tracking.sh` (six
      lines per file: 89, 91, 103, 114, 194, 208), with the
      regex-pattern lines (~205-206) and the explanatory comment
      (~203) untouched. `stop-dev` references in
      `hooks/block-unsafe-generic.sh:159,177` remain unchanged
      (Tier-2). Re-run the grep at WI execution time to confirm
      Phase 3b WI 3b.7 landed cleanly.
- [ ] 5.4 — **Update CLAUDE_TEMPLATE.md.**
      - `:15` (`bash scripts/stop-dev.sh`) → unchanged (Tier-2).
      - `:177` (`clear-tracking.sh in scripts/`) → REWRITE: point at
        `.claude/skills/update-zskills/scripts/clear-tracking.sh`
        (now Tier-1 after the scope adjustment). Verify the
        surrounding prose still parses; this template becomes the
        consumer CLAUDE.md, so the path needs to match the
        skill-mirror install location consumers will have.
      - **5.4.X — Drop both `{{PORT_SCRIPT}}` placeholders at `:13`.**
        `CLAUDE_TEMPLATE.md:13` uses `{{PORT_SCRIPT}}` twice in
        user-facing prose: ``determined automatically by `{{PORT_SCRIPT}}` ``
        and ``Run `bash {{PORT_SCRIPT}}` to see your port``.
        Rewrite the prose to drop both placeholders. Recommended
        replacement: ``The port is determined automatically — run
        `bash .claude/skills/update-zskills/scripts/port.sh` to
        see it. Override with `DEV_PORT=NNNN` env var.`` This
        coordinates with WI 5.5.a (deletes the `{{PORT_SCRIPT}}`
        row from the SKILL.md config-table and the `port_script`
        schema property), so no placeholder-substitution step
        needs `{{PORT_SCRIPT}}` after Phase 5.
      - Re-grep after edit:
        `grep -nE 'scripts/(port|clear-tracking|statusline)' CLAUDE_TEMPLATE.md`
        should return zero matches (Tier-1 paths gone from the
        template; only Tier-2 `stop-dev`, `test-all` may remain).
      - Also: `grep -F PORT_SCRIPT CLAUDE_TEMPLATE.md` should
        return zero matches.
- [ ] 5.5 — **Update README.md.** The grep
      `grep -n 'scripts/' README.md`
      shows several blocks; address per ownership tier:

      **5.5.a** — `:200` `"port_script": "scripts/port.sh"` → DROP
      the `port_script` config field. After this refactor `port.sh`
      lives at one canonical path inside the `update-zskills` skill;
      there is no consumer-side custom port script (that's the
      stub-callout pattern, which is the deferred follow-up plan's
      scope). Concrete edits:
      - Remove the `"port_script": "scripts/port.sh",` line from the
        config example at `:200`.
      - Update prose at `:228` (`dev_server.cmd / port_script /
        main_repo_path` enumeration) to drop the `port_script` slot
        — leaves `dev_server.cmd / main_repo_path`.
      - In `config/zskills-config.schema.json`, remove the
        `port_script` property (currently at `:91-94`).
      - In `skills/update-zskills/SKILL.md` config-table at `:326`
        (`{{PORT_SCRIPT}}` row) — remove the row and any
        `{{PORT_SCRIPT}}` placeholder substitution downstream
        (verify with `grep -n PORT_SCRIPT skills/update-zskills/`).
        Also remove `port_script` from the greenfield JSON template
        at `:282-286` if WI 3a.4c.i did not already drop it.
      - **Also remove `port_script` from
        `/workspaces/zskills/.claude/zskills-config.json:25`** (this
        repo's own consumer config). After the schema change, a
        leftover field would fail any future schema validation and
        contradicts the just-removed schema property.
      - CHANGELOG entry at Phase 6 notes the deprecation.

      **5.5.b** — `:275` mention of `scripts/write-landed.sh` →
      rewrite. Replace with prose like:
      `/commit land` writes a `.landed` marker via the script bundled
      in the `commit` skill"  — no code example needed (README is
      human-facing; consumers don't invoke the script directly).

      **5.5.c** — `:318` `scripts/clear-tracking.sh` → rewrite to
      point at the new location:
      `.claude/skills/update-zskills/scripts/clear-tracking.sh`
      (Tier-1 after the scope adjustment).

      **5.5.d** — README helper-scripts list at `:455-465` (verified by
      `sed -n '455,465p' README.md`) currently enumerates:
      `port.sh`, `test-all.sh`, `briefing.cjs/.py`, `land-phase.sh`,
      `post-run-invariants.sh`, `write-landed.sh`,
      `worktree-add-safe.sh`, `sanitize-pipeline-id.sh`,
      `clear-tracking.sh`. Rewrite the block:
      - REMOVE Tier-1 entries: `briefing.cjs/.py` (briefing skill),
        `land-phase.sh` (commit skill), `post-run-invariants.sh`
        (run-plan skill), `write-landed.sh` (commit skill),
        `worktree-add-safe.sh` (create-worktree skill),
        `sanitize-pipeline-id.sh` (create-worktree skill),
        `port.sh` (update-zskills skill — Tier-1 after scope
        adjustment), `clear-tracking.sh` (update-zskills skill —
        Tier-1 after scope adjustment).
      - KEEP Tier-2 entries: `test-all.sh`, `stop-dev.sh` (if
        listed). `build-prod.sh` is release-only repo tooling and
        typically not in the consumer-facing helper-scripts block;
        if present, KEEP.
      - ADD a closing line: "Skill machinery scripts moved into
        their owning skills under `.claude/skills/<owner>/scripts/`
        — see the `update-zskills` skill's
        `references/script-ownership.md` for the full table."

      Post-edit, the consumer-facing Helper Scripts list is just
      `test-all.sh` and `stop-dev.sh` (plus the closing pointer
      line).
- [ ] 5.6 — **Update CLAUDE.md (D28 fix — line numbers stale after
      Phase 3b).** Phase 3b WI 3b.2 already lists CLAUDE.md edits as
      part of its grep-driven sweep — this WI consolidates the
      verification to avoid double-edit. If Phase 3b shipped, run the
      verification grep below; if it returns non-zero matches, then
      Phase 3b skipped them — re-run the grep to find CURRENT line
      numbers (the draft-time enumeration at `:11, :44, :151, :154`
      is stale because Phase 3b's edits shifted lines) and fix each.

      ```bash
      grep -rn 'scripts/land-phase\|scripts/sanitize-pipeline-id\|scripts/write-landed\|scripts/create-worktree\|scripts/worktree-add-safe\|scripts/port\|scripts/clear-tracking\|scripts/statusline' CLAUDE.md
      ```

      For each remaining match, rewrite the path-mention as one of:
      - "the landing script (now bundled in the `commit` skill)"
        (for `land-phase`, `write-landed`).
      - "the sanitize-pipeline-id script (bundled in the
        `create-worktree` skill)" (for `sanitize-pipeline-id`,
        `create-worktree`, `worktree-add-safe`).
      - "the port-resolution / tracking-clear / statusline scripts
        (bundled in the `update-zskills` skill)" (for `port.sh`,
        `clear-tracking.sh`, `statusline.sh`).
      - Or simply drop the path-mention if the surrounding paragraph
        doesn't depend on path.

      Specifically extend the CLAUDE.md `:11` overview rewrite
      (already in Phase 3b WI 3b.2) to acknowledge the additional
      moves: `port.sh`, `clear-tracking.sh`, `statusline.sh` are
      now in `update-zskills` skill.

      Agents reading CLAUDE.md don't execute these paths directly;
      the Skill / script invocation sites that DO execute were swept
      in Phase 3b. CLAUDE.md edits here are prose-only.

      Verify with
      `grep -c 'scripts/land-phase\|scripts/sanitize-pipeline-id\|scripts/write-landed\|scripts/create-worktree\|scripts/worktree-add-safe\|scripts/port\|scripts/clear-tracking\|scripts/statusline' CLAUDE.md`
      = 0 after edits.
- [ ] 5.7 — **Update `tests/run-all.sh` to export
      `CLAUDE_PROJECT_DIR=$REPO_ROOT`.** Per D4 / Phase 3b Design:
      tests run outside the harness, and Phase 3b cross-skill
      invocations use `$CLAUDE_PROJECT_DIR` as the resolution root.
      Add `export CLAUDE_PROJECT_DIR="$REPO_ROOT"` near the top of
      `tests/run-all.sh` (after `REPO_ROOT` is computed) so all
      sub-tests inherit it.
- [ ] 5.8 — Re-run `bash tests/run-all.sh` to confirm Phase 5 edits
      didn't regress.

### Design & Constraints

**Why this phase has real edits, not just verification.** The
original draft framed Phase 5 as "mostly verification" but R5 (major)
showed README has a script-list block at `:455-465` enumerating
Tier-1 scripts that this plan must rewrite. CLAUDE.md has four
mentions (`:11, :44, :151, :154`) that go stale once Tier-1 scripts
move. Phase 5 owns these consumer-doc edits.

**Hook help-text — `clear-tracking` updated, `stop-dev` unchanged.**
Phase 3b WI 3b.7 (added in the round-4 scope adjustment) rewrites the
`clear-tracking.sh` help-text in `block-unsafe-project.sh` (six
help-text lines per file across hooks/ and .claude/hooks/) to point
at the new `.claude/skills/update-zskills/scripts/clear-tracking.sh`
location. The regex-pattern lines (`_CT_EXEC_CMD`/`_CT_EXEC_DIR`)
remain literal-substring-match on `clear-tracking` and continue to
match the new path. `stop-dev.sh` references in
`hooks/block-unsafe-generic.sh:159,177` are unchanged (Tier-2 stays
at `scripts/`).

**Mirror discipline** — README and CLAUDE.md are not skills; no
skill mirror needed unless WI 5.1 turns up an unexpected skill-side
path.

### Acceptance Criteria

- [ ] **Tests + hooks zero-match-of-old-paths:**
      ```bash
      grep -rn 'scripts/apply-preset\|scripts/briefing\.\|scripts/compute-cron-fire\|scripts/create-worktree\|scripts/land-phase\|scripts/post-run-invariants\|scripts/sanitize-pipeline-id\|scripts/worktree-add-safe\|scripts/write-landed' tests/ hooks/ .claude/hooks/
      ```
      returns zero matches.
- [ ] **Tier-2 hook help-text intact** (per R7, use rg-friendly form):
      `grep -c 'scripts/stop-dev' hooks/block-unsafe-generic.sh` ≥ 2
      (Tier-2 stop-dev references unchanged).
- [ ] **Tier-1 `clear-tracking` hook help-text moved** (was Tier-2):
      `grep -rn '\.claude/skills/update-zskills/scripts/clear-tracking' hooks/ .claude/hooks/ | wc -l`
      ≥ 8 (six help-text lines × two files); old bare
      `scripts/clear-tracking.sh` now appears only in the regex-pattern
      lines (`_CT_EXEC_CMD`/`_CT_EXEC_DIR`) and the `:203` comment —
      verify by reading lines 198-208 of each file.
- [ ] **README zero-match-of-old-Tier-1 (now extended):**
      `grep -E 'scripts/(apply-preset|briefing\.|compute-cron-fire|create-worktree|land-phase|post-run-invariants|sanitize-pipeline-id|worktree-add-safe|write-landed|port\.sh|clear-tracking|statusline)' README.md | wc -l`
      = 0.
- [ ] **README Tier-2 references intact:**
      `grep -c 'scripts/test-all\|scripts/stop-dev' README.md` ≥ 1.
- [ ] **`port_script` config field dropped:**
      `! grep -F 'port_script' README.md`
      AND `! grep -F 'port_script' config/zskills-config.schema.json`
      AND `! grep -F '{{PORT_SCRIPT}}' skills/update-zskills/SKILL.md`.
- [ ] **CLAUDE.md zero-match-of-old-Tier-1 (now extended):**
      `grep -E 'scripts/(apply-preset|briefing\.|compute-cron-fire|create-worktree|land-phase|post-run-invariants|sanitize-pipeline-id|worktree-add-safe|write-landed|port\.sh|clear-tracking|statusline)' CLAUDE.md | wc -l`
      = 0.
- [ ] **CLAUDE_TEMPLATE Tier-2 references intact:**
      `grep -c 'scripts/stop-dev' CLAUDE_TEMPLATE.md` ≥ 1.
      Note: the `clear-tracking` reference at `CLAUDE_TEMPLATE.md:177`
      (per WI 5.4) needs reframing — `clear-tracking.sh` is now Tier-1.
      Update `:177` to point at `.claude/skills/update-zskills/scripts/clear-tracking.sh`
      (mirror discipline: this file is the template that becomes
      consumer CLAUDE.md, so the update propagates to consumers via
      the existing template-install path).
- [ ] `tests/run-all.sh` exports `CLAUDE_PROJECT_DIR`:
      `grep -E 'export\s+CLAUDE_PROJECT_DIR' tests/run-all.sh | wc -l`
      ≥ 1.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phases 1, 2, 3a, 3b, 4.

## Phase 6 — Docs and close-out

### Goal

CHANGELOG entry, plan registry entry if applicable, frontmatter flip
to `complete`.

### Work Items

- [ ] 6.1 — **`CHANGELOG.md`: ADD ONE entry** under the unreleased /
      current section in the existing style. Use exactly this literal
      so the AC can grep for it:
      ```
      - refactor(scripts): move Tier-1 scripts into owning skills; /update-zskills migrates stale copies
      ```
      Per D12: do NOT edit any existing CHANGELOG row — historical
      entries describe past state correctly. Insertion only.
- [ ] 6.1b — **`CHANGELOG.md`: ADD a second entry** documenting the
      `port_script` config-field drop and the new
      `dev_server.default_port` field. Literal:
      ```
      - feat(config): drop dev_server.port_script (port.sh now lives in update-zskills skill); add dev_server.default_port for main-repo port override
      ```
- [ ] 6.2 — If `plans/PLAN_INDEX.md` exists, add a row for
      `SCRIPTS_INTO_SKILLS_PLAN.md` in the same style as siblings.
      Otherwise skip (disjunctive — `/plans` will rebuild).
- [ ] 6.3 — Frontmatter flip: `status: complete` and add
      `completed: <date>` line.

### Design & Constraints

**No edits to historical entries.** Per D12: WI 6.1 only inserts a
new line at the top of the unreleased section. Do NOT modify lines
describing prior `scripts/...` work — those entries describe a state
that was correct at the time. The grep AC below pins the literal
string of the new entry.

No skill edits, no mirror needed.

### Acceptance Criteria

- [ ] **CHANGELOG entries present (literal pin per R6/D11):**
      ```bash
      grep -F 'refactor(scripts): move Tier-1 scripts into owning skills' CHANGELOG.md \
        && grep -F 'feat(config): drop dev_server.port_script' CHANGELOG.md
      ```
      exits 0.
- [ ] `grep -q 'SCRIPTS_INTO_SKILLS' plans/PLAN_INDEX.md` succeeds OR
      file absent.
- [ ] `head -10 plans/SCRIPTS_INTO_SKILLS_PLAN.md` shows
      `status: complete` and `completed:` lines.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phases 1–5.

## Plan Quality

**Drafting process:** /draft-plan with 3 rounds of adversarial review (max)
**Convergence:** converged in round 3 (final convergence-check verified all 8 round-2 fixes landed; zero new majors, zero contradictions, zero broken ACs)
**Remaining concerns:** none. R2.1 (README block could inline owner mapping) was reviewer-marked optional UX nit and accepted as indirection-by-design. Two minor sharpness issues from round 3 (N1 STALE_LIST awk parser indented inside a code fence — copy-paste hazard the implementing agent fixes inline; N2 case 6c failure message could point at "regenerate hashes file" remediation) — both are single-Edit nudges, not blocking.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 17 (R1–R17)       | 20 (D1–D20)               | 35 verified+fixed; 2 confirmations/false-alarms (R13, D13, D15); 0 deferred |
| 2     | 7 (R2.1–R2.7)     | 9 (D21–D29)               | 14 fixed (D21 lang-split, D22 awk prose, D23 case6 redesign, D24 per-file defer marker, D25 CRLF normalize, D26+R2.2 Phase 3a verifier contract, D27 STALE_LIST parser pinned, D28 stale line numbers in WI 5.6, D29 EXISTENCE-axis paragraph, R2.3 single-source-of-truth name list, R2.4 dropped WI 3b.7, R2.6 SNAPSHOT warning header, R2.7 fallback-form required); 1 noted-not-fixed (R2.1 — accepted indirection); 1 false-alarm (R2.5) |
| 4     | user-driven scope adjustment | (n/a) | Three scripts reclassified Tier-2 → Tier-1: `clear-tracking.sh`, `port.sh`, `statusline.sh`. Original Tier-2 rationale was circular. Edits: ownership table, "maximalist alternative" subsection rewrite, Phase 2 added `statusline.sh` move WI, Phase 3a added `clear-tracking.sh` and `port.sh` move WIs (port.sh also gains config-driven `dev_server.default_port`), Phase 3b extended grep sweep + new hook help-text WI 3b.7 + cross-skill caller WI 3b.6b, Phase 4 STALE_LIST extended + test cases 2c/2d added, Phase 5 README/CLAUDE.md/CLAUDE_TEMPLATE sweeps extended (drops `port_script` config field), Phase 6 CHANGELOG gains second entry. Stub-callout follow-up work (post-create-worktree, dev-port, formal stop-dev/test-all stub conversion, generalized convention) DEFERRED to a follow-up plan. |
| 3     | combined convergence-check | combined convergence-check | 8/8 round-2 fixes verified landed; 0 new majors, 0 new criticals; 2 minor sharpness items recorded (N1, N2) — non-blocking. **Converged.** |
| 5     | post-round-4 convergence-check (F1–F7) | (n/a) | 7 findings on the round-4 scope expansion. **F1 (major)** — dropped the round-4 `:-$MAIN_ROOT` fallback form on `CLAUDE_PROJECT_DIR` everywhere (16 callsite occurrences + Phase 1 / Phase 3b Design rationale rewritten); cross-skill callers in skill prose lacked `MAIN_ROOT` in scope, making the fallback silently expand to an empty path. **F2 (major)** — dropped the hand-waved "add a Step 0.5/0.6 prompt for `default_port`" instruction (Step 0.5 has no prompt loop; Step 0.6 only asks landing-mode); replaced with concrete sub-WIs 3a.4c.i/ii/iii (greenfield template gets `"default_port": 8080,`; no install prompt; optional BASH_REMATCH read). **F3 (major)** — added explicit sub-bullet 3b.6b.x for surgical edit at `update-zskills/SKILL.md:704` (split the Step C bullet; remove `port.sh` half, keep `test-all.sh`). **F4 (minor)** — added WI 5.4.X for both `{{PORT_SCRIPT}}` placeholders at `CLAUDE_TEMPLATE.md:13`; clarified that Phase 3b skips `:326` (Phase 5 deletes the row). **F5 (minor)** — added bullet to WI 5.5.a removing `port_script` from this repo's own `.claude/zskills-config.json:25`. **F6 (minor)** — softened `statusline.sh` STALE_LIST rationale to "defensive entry"; added expectation note to test case 2c. **F7 (minor)** — pinned the `port.sh` self-doc rewrite verbatim in WI 3a.4c. |
