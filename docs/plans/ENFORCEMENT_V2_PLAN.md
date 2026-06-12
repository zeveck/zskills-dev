---
title: Enforcement v2 — Warn When Watched, Block When Autonomous, Project-Tunable Per Check
created: 2026-06-12
status: "active"
---

# Plan: Enforcement v2 — Warn When Watched, Block When Autonomous, Project-Tunable Per Check

## Overview

**Issues consolidated: #1159 (cascade v2 + attended-detection predicate), #1165
(main-write semantics + move-to-worktree), #1160 (config-UX batch).** History:
#1148 (closed by #1167) motivated the false-positive scrutiny that produced
this redesign's teachable rule.

One teachable rule drives everything in this plan:

> **Warn when a human can see it; block when no one's watching; projects can
> override per-check.**

Concretely:

- **Detection predicate (Probe-B-verified, #1159 comments).** Every
  PreToolUse hook record carries a `permission_mode` field (enum
  `bypassPermissions | default | acceptEdits | plan`; present in EVERY
  record, subagent records included). Hooks ENFORCE (current deny behavior)
  when `permission_mode == "bypassPermissions"` OR the field is
  absent/unrecognized (fail-safe) OR a zskills pipeline is LIVE
  (`.zskills/tracked` marker — written at pipeline dispatch into the
  WORKTREE root (create-worktree.sh ≈L407 is the writer), removed at
  pipeline completion — read at the EFFECTIVE LOCAL root the same way the
  hooks already read it (resolve_effective_worktree_root: env override →
  cd-target → toplevel), with the MAIN root as an additional OR-arm, plus
  a fresh `.zskills/inflight/` sentinel arm at the main root; bare
  `.zskills/tracking/` dir existence is deliberately NOT a signal — stale
  finished-pipeline subdirs accumulate there for weeks, verified in the
  dogfood repo); otherwise they WARN — emit the deny text as a warning and
  allow. Extraction of `permission_mode` is spoof-proof by construction
  (unescaped-quote anchoring; see Phase 1) so command content can never
  demote enforce→warn. The warn envelope is DECISION-LESS by hard
  invariant (it never carries a `permissionDecision` — Settled decision
  2), so the permission prompt a watched session would otherwise get
  still fires: the warn arm is always backed by the active permission
  gate, never substituted for it.
- **Every warn/deny message names its own switch.** Each message ends with
  its toggle path + effective source, e.g.
  `[hooks.git_discipline.push_to_main — block|warn|off in .claude/zskills-config.json; currently: attended default]`.
- **Project-only per-check toggles.** A new `hooks` block in
  `.claude/zskills-config.json`: per-group `enabled` booleans acting as
  ceilings + per-check tristate `"block" | "warn" | "off"`. Groups:
  `git_destructive, fs_destructive, process_kill, git_discipline,
  main_protection, pr_discipline, tracking`. Fail-closed: missing
  config / parse error / Python unavailable → shipped defaults (current
  behavior). No user-tier hook config; no posture knob (deliberately
  deferred).
- **Cascade v2 (#1159, per its scope-trim comment).** The user tier
  `~/.claude/zskills-config.json` gains (a) a plain project > user >
  built-ins cascade for THREE workflow keys (`execution.landing`,
  `execution.branch_prefix`, `execution.max_concurrent_worktrees`) and
  (b) RAISE-ONLY floors for EXACTLY TWO safety keys
  (`execution.main_protected` — true wins over false; `agents.min_model`
  — stricter tier wins). `zskills_version` stays project-only.
- **Main-write semantics (#1165).** "Locked main means no COMMIT, not no
  write": `block-main-edits`' Edit/Write gate demotes to WARN in watched
  sessions; the commit / cherry-pick / push gates on main stay HARD always.
  The tool asymmetry this removes is real (#1165 N4): Bash writes to main
  already pass the hooks, so demoting Edit/Write REMOVES the asymmetry
  rather than opening a new hole. A first-class **move-to-worktree helper**
  ships so dirty-main work can be carried into a worktree without `git
  stash` (hard-denied) and with a sanctioned restore of main.
- **Config-UX batch (#1160).** The init interview gains a clearly-separated
  second question offering a PERSONAL (user-tier) config — accept writes an
  EMPTY scaffold (never seeded values); declines are recorded at the scope
  of the thing declined (project decline in gitignored `.zskills/`;
  personal decline under `~/.claude/`) so update runs stop re-asking; the
  update report becomes the single config-news channel via a
  new-config-surface nudge.

**Falsifiable end state:**

1. **Watched warn.** In a session with `permission_mode: "default"` and no
   live pipeline markers, `git add .` on main produces a USER-VISIBLE
   WARNING (on the warn channel pinned by the Phase 1 gating probe) ending
   in `[hooks.git_discipline.git_add_all — …]` and the command RUNS. The
   same input with `permission_mode: "bypassPermissions"` produces the
   deny envelope.
2. **Bypass parity.** For all 23 predicate-demotable emission sites, a
   parity test feeds `permission_mode: "bypassPermissions"` input and
   asserts the deny envelope still fires with the current STOP text (plus
   the new trailing tag). A spoof-parity case (counterfeit
   `"permission_mode":"default"` literal embedded in `tool_input.command`,
   real field `bypassPermissions` or absent) also still denies.
   Autonomous-mode protection is never weakened.
3. **Toggles.** Project `hooks.git_discipline.git_add_all: "off"` → silent
   allow; `"block"` → deny even watched; group `enabled: false` → whole
   group off.
4. **Cascade v2.** User-tier `execution.landing: "pr"` is effective in a
   project whose config has no `landing`; project value wins when present.
   Project `main_protected: false` + user `true` → protected (floor).
   User `agents.min_model: "opus"` + project `"sonnet"` → opus floor; user
   `"haiku"` + project `"sonnet"` → sonnet (raise-only, never lowers).
   A malformed user file changes nothing (per-tier fail-closed).
5. **Move-to-worktree.** With a dirty main (tracked edits — including
   staged-new, deleted, and staged-only/index-divergent states — +
   untracked files), `move-to-worktree.sh` yields a worktree containing
   the dirt with the staged/unstaged split preserved, a clean main,
   zero `git stash` invocations, and refuses to touch main if any
   carried file fails working-tree byte-verification OR index
   blob-verification.
6. **Config-UX.** `/zs:update-zskills` init asks the personal-config
   question once; accept writes the empty scaffold + schema copy to
   `~/.claude/`; decline writes the user-scope
   `~/.claude/zskills-config.declined` marker and is not re-asked in ANY
   project (project-config declines use the per-project
   `.zskills/config-offer-declined`); the update report lists config keys
   added since the consumer's recorded version.
7. `bash tests/run-all.sh` passes clean at every phase boundary.

## Settled decisions (do not relitigate)

1. The predicate is the Probe-B-pinned form with a LIVE pipeline arm:
   enforce iff `permission_mode == "bypassPermissions"` OR field
   absent/unrecognized (fail-safe) OR a zskills pipeline is LIVE —
   defined as `.zskills/tracked` (or legacy `.zskills-tracked`) present
   at the EFFECTIVE LOCAL root (the worktree root when the session or
   the command's `cd`-target lives in a worktree — that is where every
   on-disk writer puts the marker: create-worktree.sh ≈L407,
   execute-phase.md ≈L249–252, do/modes/pr.md ≈L122–136; main root
   otherwise), OR present at the MAIN root (orchestrator-written markers
   per CLAUDE.md Tracking Enforcement prose — kept as an OR-arm even
   though no skill currently implements the main-root write), OR an
   `.zskills/inflight/` sentinel at the main root younger than the
   documented TTL (7200s, `check-inflight-batch.sh` convention; honest
   limitation: a single pipeline phase longer than 2h ages its sentinel
   out and falls back to the tracked-marker arm — accepted, the tracked
   marker is the primary signal). Bare `.zskills/tracking/` dir
   existence is NOT a signal: finished pipelines leave subdirs there
   indefinitely (20+ stale subdirs dated May 31–Jun 1 verified in the
   dogfood repo on Jun 12), which would make "enforce" permanent in
   every repo that ever ran a pipeline. Known stickiness in the other
   direction, accepted explicitly: some flows remove the worktree's
   `tracked` only at worktree cleanup (fix-issues direct.md ≈L166–175
   removes it only when the worktree is clean; draft-plan/refine-plan
   worktrees keep it until deletion), so a session living in an
   abandoned worktree stays enforce-mode — that fails TOWARD
   enforcement, worktrees are pipeline artifacts, and the main session
   is unaffected. Warn otherwise. No other inputs (no TTY sniffing, no
   env vars, no transcript heuristics).
2. **Warn channel = decide-then-pin via the Phase 1 GATING probe, and
   the warn envelope is DECISION-LESS under every pinned form.** The
   warn-mode audience is the HUMAN (the predicate fires warn precisely
   when a human is watching), so the warning must demonstrably reach the
   user — WITHOUT touching the permission system. HARD INVARIANT: the
   warn path never emits a `permissionDecision` (no
   `hookSpecificOutput` decision at all). A `permissionDecision:
   "allow"` would BYPASS the permission system for exactly the
   dangerous commands being warned about — auto-approving them in
   watched sessions, a regression below today's status quo (today's
   hooks emit nothing on their allow paths, leaving the prompt intact).
   The invariant is unit-tested: the flush emission must NOT match
   `permissionDecision` (Phase 1 suite). Two emission forms are
   pre-specced in Phase 1: **W-A** (exit 0 + bare
   `{"systemMessage":"…"}` stdout JSON — decision-less; the same
   `systemMessage` field session-start-greeting.sh and
   session-rules-context.sh use, both on SessionStart; whether a
   decision-less `systemMessage` surfaces on PreToolUse is exactly what
   the probe decides — no repo artifact or doc proves it today) and
   **W-B** (stderr + exit 0 — the warn-config-drift.sh shape, proven
   non-breaking but NOT proven user-visible on PreToolUse). A headless
   `claude -p` probe in Phase 1 selects the form; W-A is pinned if its
   systemMessage reaches a user-facing stream record (pass-criterion
   grammar pinned in the Phase 1 probe spec); else W-B is pinned via
   its own two-branch evidence ladder (also pinned in Phase 1); if
   NEITHER form demonstrably reaches the user, that is a
   Failure-Protocol STOP (the design premise is falsified — surface, do
   not ship demotions). Warn-mode text is human-addressed: no
   agent-directed advice (agent guidance belongs in deny mode, which
   IS model-visible via `permissionDecisionReason`).
3. Hook toggles are **PROJECT-ONLY**. No user-tier hook config, no posture
   knob — deliberately deferred, not forgotten.
4. Group keys are named **exactly**: `git_destructive`, `fs_destructive`,
   `process_kill`, `git_discipline`, `main_protection`, `pr_discipline`,
   `tracking`. Do not rename, merge, or add groups.
5. Cascade v2 scope is **exactly** 3 workflow keys + 2 raise-only floors
   (#1159 scope-trim comment governs, not the issue body).
   `zskills_version` stays project-only.
6. **Explicit per-check toggle values are always honored** — including for
   keep-hard checks. A project that commits `reset_hard: "warn"` to its
   reviewed config made a deliberate choice. The hard/demotable class
   controls only the UNSET default (hard → block always; demotable →
   predicate-driven).
7. `block-main-edits`' Edit/Write gate is predicate-demotable; the
   commit / cherry-pick / push gates on main are NOT (keep-hard list in the
   Toggle-key registry below).
8. The move-to-worktree helper is **copy-based** (diff + apply + untracked
   copy), never stash-based. `git stash` stays hard-denied. The sanctioned
   restore of main is **helper-mediated**: the helper performs the restore
   internally so the agent never types a denied command — no marker file,
   no hook carve-out, no general bypass (mechanism specced in Phase 5).
   The helper creates its worktree with `--no-preflight` (branches off
   current LOCAL HEAD — the documented dirty-tolerant escape), so the
   carried diff is always same-base and the create-worktree preflight
   refusals (exit 7 divergent / exit 10 #225 AHEAD) survive untouched as
   the universal default for every other caller.
9. `block-unmaterialised-skill.sh` is OUT of predicate/toggle scope
   (different envelope — UserPromptExpansion `{"decision":"block"}` — and
   init-gating, not safety enforcement). It is the single tag-tripwire
   exemption.
10. `block-agents.sh` gets NO `hooks.*` key — its switch IS
    `agents.min_model` (existing config), and its messages name that
    switch. It stays keep-hard.
11. The landing seed default stays `"direct"` (#1120 — settled; cascade v2
    changes who can set the value, not the default).
12. The legacy lane is untouched except through shared code (hooks and
    resolver are shared; the `.claude/hooks/` mirrors update in lockstep).
    #1155 fence-wrap is OUT of scope. New bash fences in SKILL.mds follow
    the #1169 setopt-guard idiom; sourceable helpers use the
    `setopt LOCAL_OPTIONS KSH_ARRAYS BASH_REMATCH` form.
13. **Toggle reads are MAIN-ROOT-ONLY, and the toggle surface is itself
    gated.** The toggle loader reads exactly
    `<main root>/.claude/zskills-config.json` where main root =
    `zskills_enforcement_config_root()` (git-common-dir parent →
    `CLAUDE_PROJECT_DIR` → pwd) — a worktree's checkout copy of the
    config is NEVER consulted **for toggles**, so worktree-local config
    edits cannot disarm any toggle. (Scope honesty: the key that ARMS
    main-protection, `execution.main_protected`, is still read at the
    LOCAL toplevel by `is_main_protected()` — existing behavior,
    unchanged by this plan; see the Phase 4 read-root pin.) Edit/Write
    writes to the main config's hooks block are gated by the new
    `hooks.main_protection.config_hooks_tamper` Edit/Write arm in
    block-main-edits, placed ABOVE the hook's worktree-self early-exit
    so a worktree-rooted session editing the MAIN root's config by
    absolute path is still gated (Phase 2 pins the insertion point);
    direct Bash writes naming the file as a write DESTINATION are gated
    by the row-50 arm in block-unsafe-generic. Both are demotable: deny
    in enforce mode; WARN when watched — a watching human seeing their
    agent flip its own toggles is the design's answer, stated
    explicitly. Self-protection: `config_hooks_tamper` is EXEMPT from
    its group's `enabled` ceiling (a `main_protection.enabled: false`
    write cannot silently disarm the tamper check itself), and flipping
    its own per-check toggle is itself a tamper-gated write — the gate
    evaluates under the PRE-write config, so an autonomous agent cannot
    turn it off (the write denies before the new value takes effect);
    a watched session can warn through it, and that watched-write →
    persistent-autonomous-effect asymmetry is accepted with rationale
    (the warn names the flip to the watching human; every warn/deny
    text for this check carries the recovery line naming the
    human-mediated re-enable path). **Threat model, stated:** this gate
    is anti-casual, not anti-adversarial. Residual surface accepted
    with rationale: Bash-mediated writes that never name the file as a
    literal destination (variable destinations, programmatic writes,
    heredocs computing the path) are not caught — but they remain
    visible in the session transcript, full integrity checking (hashes,
    committed-copy comparison) is deliberately out of scope, the
    predicate makes autonomous sessions deny the direct forms, and
    project review owns the committed config.
14. **One tag-emission form per hook class, pinned.** Small hooks build
    each message with a dedicated
    `$(zskills_enforcement_tag <group> <check>)` call line per site; the
    two big hooks tag INSIDE the `gate_with_reason` wrapper (sites pass
    bare group/check args and are counted by wrapper call lines);
    block-agents uses a static literal tag (no hooks.* key — Settled
    decision 10). Tripwires and phase ACs count exactly these forms —
    never a mix.

## Design-history dispositions

| Decision | Disposition |
|---|---|
| #308 (block-main-edits hard deny on Edit/Write to main) | **REVISED** — the original rationale ("orchestrator on main bypasses worktree discipline") is re-satisfied by warn-when-watched + the still-hard commit/cherry-pick/push gates; #1165 N4 showed the hard Edit/Write deny was an asymmetry, not a defense (Bash writes already passed). The allowlist, containment logic, and worktree-self check survive byte-for-byte. |
| INSTALL_REDESIGN Phase 5 PROJECT-ONLY carve-outs (`block-agents.sh` ≈L6–12 header; `block-unsafe-generic.sh` ≈L34 push-gate carve-out; resolver Pass-1 comment ≈L209–210) | **REVERSED for floors only** — the original rationale was "a user file silently LOWERING a project's protection inverts trust." Raise-only floors preserve that exact property: the user tier can only RAISE `main_protected`/`min_model`, never lower. The carve-out comments are rewritten to state the floor contract. |
| docs/guides/zskills-config.md ≈L83–89 ("`execution.*` never cascades from the user tier … documented behavior, not a bug") | **INVERTS** — Phase 7 rewrites the paragraph: 3 workflow keys cascade plainly, 2 safety keys are raise-only floors, the rest of `execution.*` (and `zskills_version`) stays project-only. |
| #1120 (config seed `landing: "direct"`) | **SURVIVES** — defaults unchanged. |
| block-bypassed-land-pr header ≈L40–44 ("the deny decision is UNCONDITIONAL") | **SURVIVES as the default** (keep-hard, predicate never demotes it); per-check toggle is an explicit reviewed project override, which is a different thing than a runtime condition. Header reworded to say so. |
| Test 15 (`tests/test-zskills-resolve-config.sh` ≈L687–730: execution.* + zskills_version project-tier-only) | **RE-SPECCED** per Invariant 3 — 15a's subject changes (workflow keys now cascade; dashboard_* stays project-only); 15b (`zskills_version`) unchanged. Old + new expected values go in the commit message. |
| create-worktree.sh preflight exit 7 (ff-only refusal on divergent local main) + #225 exit-10 AHEAD refusal | **SURVIVES untouched** — the loud refusal stays the universal default for every caller (silently branching from `origin/$BASE` would mirror the exact hazard class #225 closed: worktrees silently OMITTING local-only commits). move-to-worktree routes around it via the existing documented `--no-preflight` escape (base = current LOCAL HEAD, ≈L275–281 of create-worktree.sh), which also makes its carried diff same-base by construction. |
| D16(a) conditional-skip shim; `git stash` hard-deny; #1132 single-path rule; #394 lock-LAST | **SURVIVE untouched.** |

## Why these phases, in this order

- **Phase 1 — enforcement library first.** The predicate, toggle loader,
  warn emitter, tag formatter, and known-check registry are ONE helper in
  `hooks/_lib/` that every later phase inlines. Building it with its own
  unit suite before touching any hook means each hook retarget is a
  mechanical integration, not a design step. Phase 1 also carries the
  GATING warn-channel probe (Settled decision 2): no demotion lands
  anywhere until the warn channel is proven user-visible.
- **Phase 2 — the seven small hooks before the two big ones.** The
  integration pattern (inline helper, gate wrapper, tag, parity test,
  stamp/mirror lockstep) is proven on a 238-line hook before it is applied
  to the 1138/1277-line pair. block-main-edits' demotion (the #1165
  headline) lands here.
- **Phase 3 — block-unsafe-generic + block-unsafe-project as their own
  phase/commits.** Research flags block-unsafe-project (1277L, `.template`
  sibling, tracking gates) as the riskiest file; it gets its own commit.
  The message-tag tripwire lands at the END of this phase because only now
  are all 49 in-scope emissions tagged (47 hooks.*-keyed + 2
  agents.min_model static-tagged).
- **Phase 4 — cascade v2** is independent of Phases 1–3 (different files)
  but must precede Phase 6: the personal-config scaffold's `_comment`
  documents the cascade contract, which must be true when written.
- **Phase 5 — move-to-worktree helper** depends on Phase 2 only for the
  message cross-reference (the demoted main-edit deny/warn body gains a
  pointer to the helper here, not in Phase 2 — avoids a forward
  reference to a script that doesn't exist yet). The create-worktree
  preflight is NOT reworked (Settled decision 8; Design-history row).
- **Phase 6 — config-UX** last among behavior phases: it advertises
  surfaces (user tier, hooks block) that Phases 1–4 created.
- **Phase 7 — docs + conformance sweep** rewrites every guide paragraph the
  earlier phases invalidated and runs the final cross-cutting sweep.

## Execution context

`main_protected: true` — execute via `/run-plan docs/plans/ENFORCEMENT_V2_PLAN.md`
in worktree mode. Implementation dispatches to `subagent_type: "implementer"`;
verification to the verifier subagent. Each phase is one commit unless the
phase says otherwise (Phase 3 is two commits — one per big hook). All line
numbers are ≈L — **verify by content, not blind line number**.

No attended steps are required by Phases 1–6 on the expected path. The
Phase 1 warn-channel probe is GATING but headless (`claude -p` —
scriptable); if the `claude` CLI is unavailable to the implementer, that
is a Failure-Protocol STOP to surface, not a skip. ONE conditional
exception: if the probe's W-A leg fails AND its W-B leg shows only
process-level stderr propagation, pinning W-B requires a one-time
attended confirmation (the probe spec's step 4(b) — surface to the
user, who runs one watched command interactively). Phase 7 carries ONE
optional attended check (live interactive confirmation of the
probe-pinned warn channel) with a documented non-gating fallback.

Coordination hazards: #1146 (dual-read retirement) touches the legacy
`.zskills-tracked` fallbacks in block-unsafe-project — if it lands mid-plan,
rebase the Phase 3 commit onto its result (the pipeline-LIVE predicate
also dual-reads the legacy `.zskills-tracked` root marker — drop that arm
in lockstep when #1146 lands). Parallel sprints touching `skills/update-zskills/SKILL.md`
will conflict on the `metadata.version` line — edit the conflict region
directly, never `checkout --ours/--theirs`.

## Critical invariants every phase must honor

1. **Skill-versioning quadruple gate.** ANY edit to a skill body or any
   regular file under a skill dir requires a `metadata.version` bump in
   source AND mirror, same commit:
   ```bash
   today=$(TZ=America/New_York date +%Y.%m.%d)
   hash=$(bash scripts/skill-content-hash.sh skills/<S>)
   bash scripts/frontmatter-set.sh skills/<S>/SKILL.md metadata.version "$today+$hash"
   bash scripts/mirror-skill.sh <S>
   ```
   Compute the hash AFTER all content edits to that skill, per commit. A
   denied `git commit` carries the exact bump command — run it, re-stage,
   re-commit; do NOT treat the deny as a test failure.
2. **Hook-edit lockstep.** Every edited `hooks/<x>.sh` ships, in the SAME
   commit: the line-2 `# zskills-hook-version:` stamp bump, the byte-equal
   `.claude/hooks/<x>.sh` mirror refresh, and — for `block-agents.sh` and
   `block-unsafe-project.sh` — the regenerated byte-equal `.sh.template`
   sibling. Gated by `tests/test-hooks-mirror-parity.sh` and
   `tests/test-hook-template-sibling.sh`.
3. **Helper-inline drift gate.** The Phase 1 enforcement helper lives in
   `hooks/_lib/zskills-enforcement.sh` (source of truth) and is INLINED
   verbatim into each consuming hook (the `.claude/hooks/` mirrors cannot
   reach `_lib/` at runtime). `tests/test-hook-helper-drift.sh`'s FN map
   gains every new function + its consumer list, same commit as the first
   inline.
4. **Bypass parity — autonomous protection is never weakened.** For EVERY
   predicate-demoted emission site (23 total), a test feeds the hook
   `permission_mode: "bypassPermissions"` input and asserts the deny
   envelope (`"permissionDecision":"deny"` + the site's distinctive STOP
   substring) still fires. Phase 2 lands 5 such cases; Phase 3 lands 18.
   At least one parity case per big hook is a SPOOF case: a counterfeit
   `"permission_mode":"default"` literal inside `tool_input.command`
   (escaped in the fixture JSON, as the harness necessarily serializes
   it) with the real top-level field `bypassPermissions` — still deny;
   and a sibling with the real field ABSENT — still deny (fail-safe).
   These tests may never be deleted or loosened by later phases.
5. **Tests are never weakened.** Every re-specified assertion (Test 15a,
   block-main-edits C-cases, etc.) is an intended behavior change of the
   subject, stated as such in the commit message with the old and new
   expected values. A floor lowered or an assertion dropped without a named
   re-spec rationale is a weakening and is forbidden.
6. **Fail-closed toggles.** Missing config, unparseable config, or
   unavailable Python → shipped defaults (hard checks block; demotable
   checks follow the predicate). Per-tier fail-closed for the cascade: a
   malformed user-tier file is IGNORED entirely — it never disarms a floor
   and never errors a hook or the resolver.
7. **Triplet registration.** Every new test suite lands with its
   `tests/run-all.sh` registration and its `tests/test-suite-registry.sh`
   entry in the SAME commit.
8. **Capture test output out-of-tree, never pipe:**
   ```bash
   TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
   mkdir -p "$TEST_OUT"
   bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
   ```
   Then READ the file; report per-suite pass COUNTS.
9. **Suite green at every phase boundary** — `bash tests/run-all.sh`
   passes before the phase's last commit is considered done.
10. **Python lockstep.** Any change to the dashboard config loader is a
    3-file lockstep: `collect.py` (≈L336–365), `briefing.py` (≈L83),
    `server.py` — keep the SYNC NOTE comments accurate.
11. **No general bypass.** No phase may introduce an env var, marker, or
    flag that turns enforcement off wholesale. The only overrides are the
    per-check project toggles and the predicate itself.
12. **Historical surfaces are off-limits:** `CHANGELOG.md`, `docs/plans/`
    (other than THIS file's tracker), `docs/reports/`, `docs/issues/`.

## Toggle-key registry — all 50 deny emissions, classed

> (Heading deliberately does NOT match `^## Phase \d` — keeps /run-plan's
> phase extraction from treating this section as a phase.)
>
> This table IS the toggle-key registry: it must stay in sync with the
> helper's `KNOWN_CHECKS` list (Phase 1) and the schema's `hooks` block —
> the Phase 3 conformance tripwire mechanically enforces lib ↔ schema; this
> table is the drafting source of truth. Class `hard` = unset default is
> block-always (predicate never demotes); `demotable` = unset default is
> block-when-enforce / warn-when-watched. Explicit per-check toggle values
> override class in BOTH cases (Settled decision 6).
>
> 37 distinct `hooks.<group>.<check>` keys cover 47 emission sites
> (rows 1–36 and 39–47 are today's keyed sites; rows 49–50 are the NEW
> `config_hooks_tamper` sites this plan adds per Settled decision 13);
> 2 sites (rows 37–38) are governed by the existing `agents.min_model`;
> 1 site (row 48, block-unmaterialised-skill) is exempt (Settled
> decision 9). 50 total; in-scope (tagged) = 49.

| # | Hook | ≈L | Check (message gist) | Toggle key | Class |
|---|---|---|---|---|---|
| 1 | block-unsafe-generic.sh | 748 | git stash drop/clear | hooks.git_destructive.stash_drop | hard |
| 2 | block-unsafe-generic.sh | 757 | git stash write subcommands | hooks.git_destructive.stash_write | hard |
| 3 | block-unsafe-generic.sh | 775 | git checkout -- discards | hooks.git_destructive.checkout_discard | hard |
| 4 | block-unsafe-generic.sh | 781 | git restore discards | hooks.git_destructive.restore_discard | hard |
| 5 | block-unsafe-generic.sh | 794 | git switch --discard-changes/-f | hooks.git_destructive.switch_discard | hard |
| 6 | block-unsafe-generic.sh | 800 | git clean -f | hooks.git_destructive.clean_force | hard |
| 7 | block-unsafe-generic.sh | 806 | git reset --hard | hooks.git_destructive.reset_hard | hard |
| 8 | block-unsafe-generic.sh | 822 | kill -9 / killall / pkill | hooks.process_kill.kill_9 | hard |
| 9 | block-unsafe-generic.sh | 828 | fuser -k | hooks.process_kill.fuser_k | hard |
| 10 | block-unsafe-generic.sh | 840 | xargs … kill | hooks.process_kill.xargs_kill | hard |
| 11 | block-unsafe-generic.sh | 858 | kill $(lsof…)/`pgrep…` substitution | hooks.process_kill.kill_substitution | hard |
| 12 | block-unsafe-generic.sh | 931 | recursive rm non-literal/non-/tmp | hooks.fs_destructive.rm_recursive | hard |
| 13 | block-unsafe-generic.sh | 938 | find … -delete non-literal | hooks.fs_destructive.find_delete | hard |
| 14 | block-unsafe-generic.sh | 945 | rsync --delete non-literal | hooks.fs_destructive.rsync_delete | hard |
| 15 | block-unsafe-generic.sh | 997 | xargs into destructive cmd | hooks.fs_destructive.xargs_destructive | hard |
| 16 | block-unsafe-generic.sh | 1008 | git add . / -A | hooks.git_discipline.git_add_all | **demotable** |
| 17 | block-unsafe-generic.sh | 1015 | --no-verify | hooks.git_discipline.no_verify | hard |
| 18 | block-unsafe-generic.sh | 1133 | push to main/master | hooks.main_protection.push_to_main | **demotable** |
| 19 | block-unsafe-project.sh | 336 | requires.* unfulfilled (push) | hooks.tracking.requires_unfulfilled | **demotable** |
| 20 | block-unsafe-project.sh | 338 | requires.* unfulfilled (commit/cp) | hooks.tracking.requires_unfulfilled | **demotable** |
| 21 | block-unsafe-project.sh | 350 | step.* impl without verification | hooks.tracking.step_unverified | **demotable** |
| 22 | block-unsafe-project.sh | 361 | step.* verified without report | hooks.tracking.step_unreported | **demotable** |
| 23 | block-unsafe-project.sh | 607 | recursive delete inside .zskills/ | hooks.fs_destructive.zskills_tree_delete | hard |
| 24 | block-unsafe-project.sh | 621 | agent running clear-tracking | hooks.fs_destructive.clear_tracking_agent | hard |
| 25 | block-unsafe-project.sh | 633 | git add .claude/logs/ | hooks.git_discipline.logs_add_all | **demotable** |
| 26 | block-unsafe-project.sh | 776 | piped test output | hooks.git_discipline.test_pipe | **demotable** |
| 27 | block-unsafe-project.sh | 796 | testing.full_cmd unset w/ test infra | hooks.git_discipline.full_cmd_unset | **demotable** |
| 28 | block-unsafe-project.sh | 812 | commit on protected main | hooks.main_protection.commit_on_main | **demotable** |
| 29 | block-unsafe-project.sh | 835 | commit without test run | hooks.git_discipline.tests_not_run | **demotable** |
| 30 | block-unsafe-project.sh | 853 | UI changed, no playwright | hooks.git_discipline.ui_unverified | **demotable** |
| 31 | block-unsafe-project.sh | 977 | cherry-pick on protected main | hooks.main_protection.cherry_pick_on_main | **demotable** |
| 32 | block-unsafe-project.sh | 989 | cherry-pick without test run | hooks.git_discipline.tests_not_run | **demotable** |
| 33 | block-unsafe-project.sh | 1245 | push to protected main (form 1) | hooks.main_protection.push_to_main | **demotable** |
| 34 | block-unsafe-project.sh | 1259 | push to protected main (form 2) | hooks.main_protection.push_to_main | **demotable** |
| 35 | block-unsafe-project.sh | 1268 | push to protected main (form 3) | hooks.main_protection.push_to_main | **demotable** |
| 36 | block-main-edits.sh | 209–237 | Edit/Write to protected main | hooks.main_protection.main_edit | **demotable** |
| 37 | block-agents.sh | 168 | Haiku-pinned subagent_type | (agents.min_model — no hooks.* key) | hard |
| 38 | block-agents.sh | 184 | dispatch model below floor | (agents.min_model — no hooks.* key) | hard |
| 39 | block-fix-issue-unclaimed.sh | 316 | issue held by foreign pipeline | hooks.tracking.issue_unclaimed | **demotable** |
| 40 | block-fix-issue-unclaimed.sh | 329 | no claim for issue | hooks.tracking.issue_unclaimed | **demotable** |
| 41 | block-run-plan-unclaimed.sh | 285 | no claim for plan slug | hooks.tracking.plan_unclaimed | **demotable** |
| 42 | block-stale-skill-version.sh | (stage-check STOP relay) | stale metadata.version at commit | hooks.git_discipline.stale_skill_version | hard |
| 43 | block-bad-cron.sh | ≈L328 | one-shot cron, no fire within 8d | hooks.tracking.cron_invalid | hard |
| 44 | block-bad-cron.sh | ≈L345 | negative fire delta (defensive) | hooks.tracking.cron_invalid | hard |
| 45 | block-bad-cron.sh | (third emit_deny site) | remaining CronCreate reject rule | hooks.tracking.cron_invalid | hard |
| 46 | block-bypassed-land-pr.sh | ≈L376 | direct gh pr create/merge (static fallback) | hooks.pr_discipline.direct_gh_pr | hard |
| 47 | block-bypassed-land-pr.sh | (primary deny site) | direct gh pr create/merge | hooks.pr_discipline.direct_gh_pr | hard |
| 48 | block-unmaterialised-skill.sh | 151 | state-writing skill pre-init | EXEMPT (different envelope; init gate) | — |
| 49 | block-main-edits.sh | (new arm, ABOVE the worktree-self early-exit — fires regardless of main_protected AND in worktree sessions) | Edit/Write to main's .claude/zskills-config.json touching the hooks block | hooks.main_protection.config_hooks_tamper | **demotable** |
| 50 | block-unsafe-generic.sh | (new check) | direct shell write whose DESTINATION is .claude/zskills-config.json | hooks.main_protection.config_hooks_tamper | **demotable** |

Drafter classification notes (bind the implementer):

- `cron_invalid` sits in `tracking` because CronCreate registers recurring
  pipeline fires — it is pipeline-scheduling correctness, and no other
  group fits. It stays hard: a warned-through malformed cron is a cron
  that silently never fires.
- The claim gates (#39–41) are demotable: they are tracking-discipline
  (the warn text surfaces the foreign claim and a watching human
  adjudicates), matching the #1159 demotable set ("tracking-discipline
  gates"). The hard cross-session protections (claims releases, marker
  trees) remain guarded by the fs_destructive checks. Honest caveat: in
  the two-concurrent-WATCHED-sessions incident class (#877/#865 — two
  terminals, or interactive + cron fire) the warn fires in the stealing
  session while the harmed pipeline lives in the other; no single human
  sees both sides, so warn-and-allow can still create the double claim.
  The classing is inherited from #1159 (settled); projects wanting hard
  cross-session exclusion set `issue_unclaimed`/`plan_unclaimed` to
  `"block"` (Settled decision 6) — say so in the docs (Phase 7).
- `no_verify` (#17) is hard despite living in git_discipline: bypassing
  pre-commit hooks defeats every other gate in this table.
- `config_hooks_tamper` (#49–50, Settled decision 13) sits in
  `main_protection` because the gated file is the main root's config (the
  toggle loader never reads worktree copies). It is demotable: a watched
  human SEEING their agent rewrite the toggle file is the warn-mode
  design working as intended; an autonomous agent doing it is denied.
  Self-protection, pinned precisely (it is NOT absolute): (a) the check
  is EXEMPT from the `main_protection.enabled` group ceiling (mode
  resolution special-case, Phase 1) — a ceiling write cannot silently
  take the tamper check down with the group; (b) flipping
  `config_hooks_tamper`'s own per-check value is itself a tamper-gated
  write evaluated under the PRE-write config, so an autonomous session
  cannot disarm it (deny fires before the new value exists); (c) a
  WATCHED session can warn through the flip, and the flipped value then
  persists into autonomous sessions — accepted asymmetry, with the
  mitigation that every warn/deny text for this check ends with the
  recovery line: how to re-enable (delete the key or set `"block"` in
  `.claude/zskills-config.json` via a human-reviewed edit). The deny
  text must name that human-mediated path so an autonomous agent
  instructed to change config has an actionable hand-back instead of a
  deny loop.
- Demotable sites total **23** (rows 16, 18, 19–22, 25–36, 39–41,
  49–50); demotable keys total **16**; hard in-scope sites total **26**;
  exempt **1**.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Enforcement library: predicate, toggles, warn-channel probe (GATING), schema | ⬚ | | |
| 2 — Small-hook retarget (7 hooks) + bypass parity ×5 | ⬚ | | |
| 3 — Big-hook retarget (generic + project) + tag tripwire + bypass parity ×18 | ⬚ | | |
| 4 — Cascade v2: workflow keys + raise-only floors | ⬚ | | |
| 5 — move-to-worktree helper (stash-free dirty-main carry) | ⬚ | | |
| 6 — Config-UX: personal-config offer, decline marker, update nudge | ⬚ | | |
| 7 — Docs rewrite + conformance sweep | ⬚ | | |

---

## Phase 1 — Enforcement library: predicate, toggles, warn-channel probe (GATING), schema

### Goal

Land `hooks/_lib/zskills-enforcement.sh` — the single source of truth for
the watched/enforce predicate, lazy toggle loading, mode resolution, the
message-tag formatter, and the warn emitter — plus its unit suite, the
GATING warn-channel visibility probe (decide-then-pin, Settled decision
2), the schema `hooks` block, and the drift-gate FN-map extension. No
hook behavior changes in this phase (no hook sources the helper yet).

### Work Items

- [ ] **`hooks/_lib/zskills-enforcement.sh`** with EXACTLY these functions
  (names are pinned; the drift gate and later phases reference them):

  ```bash
  # zskills_enforcement_config_root — no args
  #   echoes ${ZSKILLS_ENF_CONFIG_ROOT} when set (test override — every
  #   existing hook root is env-overridable; this fn gets its own, NOT
  #   REPO_ROOT, whose semantics are "the hook's session root"); else
  #   the MAIN repo root: $(git rev-parse --git-common-dir) parent
  #   when inside a git checkout; else ${CLAUDE_PROJECT_DIR}; else pwd.
  #   This is the toggle-file root and the main-root marker/sentinel
  #   root (Settled decision 13; per-hook table in Phases 2–3).
  #   Worktree-local config copies are never consulted for toggles.

  # zskills_enforcement_predicate  — args: $1 = hook stdin JSON,
  #                                        $2 = main root, $3 = effective LOCAL root
  #   ($2 = the zskills_enforcement_config_root value the hook computed;
  #    $3 = the hook's effective local root — for Bash-matcher hooks the
  #    resolve_effective_worktree_root value (env override → cd-target →
  #    toplevel/pwd fallback; the SAME `hooks/_lib/
  #    resolve-effective-worktree-root.sh` helpers block-unsafe-project
  #    and block-stale-skill-version already inline for their Tier-1
  #    marker read at ≈L889); for Edit/Write and CronCreate hooks, which
  #    have no cd-target in their input, the session root —
  #    ${REPO_ROOT:-${CLAUDE_PROJECT_DIR:-}} → toplevel → pwd, i.e.
  #    block-main-edits' existing MAIN_ROOT chain. Per-hook pins in
  #    Phases 2–3.)
  #   echoes ONE of "enforce-autonomous" | "enforce-pipeline" | "watched".
  #   Pure bash + file tests, NO Python.
  #   PERM=""
  #   [[ "$1" =~ (^|[^\\])\"permission_mode\"[[:space:]]*:[[:space:]]*\"([a-zA-Z]+)\" ]] && PERM="${BASH_REMATCH[2]}"
  #   # SPOOF-PROOF BY CONSTRUCTION: in valid JSON, any quote inside a
  #   # string value (tool_input.command, new_string, …) is escaped as
  #   # \" — so a counterfeit "permission_mode" literal embedded in
  #   # command content can only appear with a backslash before its
  #   # opening quote, which (^|[^\\]) rejects. Only the real top-level
  #   # key (whose quote follows `{`, `,` or whitespace) can match,
  #   # regardless of field order. The value class [a-zA-Z]+ cannot span
  #   # an escape. No tool_input stripping or field-order assumption
  #   # needed.
  #   enforce-autonomous iff:
  #     PERM == "bypassPermissions"
  #     OR PERM not in {default, acceptEdits, plan}   (absent/unrecognized — fail-safe)
  #   else enforce-pipeline iff a pipeline is LIVE:
  #     [ -f "$3/.zskills/tracked" ] OR [ -f "$3/.zskills-tracked" ]
  #       (the LOCAL-root read — this is where the on-disk writers put
  #       the marker: create-worktree.sh ≈L407 writes
  #       $WT_PATH/.zskills/tracked; execute-phase.md ≈L1800 removes the
  #       WORKTREE copy. Without this arm a live pipeline's worktree
  #       agents would read as watched — verified live: this plan's own
  #       draft-plan worktree carries .zskills/tracked while the main
  #       root does not. Legacy dual-read; drop when #1146 lands)
  #     OR [ -f "$2/.zskills/tracked" ] OR [ -f "$2/.zskills-tracked" ]
  #       (main-root OR-arm: CLAUDE.md Tracking Enforcement says the
  #       orchestrator writes the marker in both roots; no skill
  #       implements the main-root write today, but the read is kept so
  #       prose-compliant orchestrators are honored)
  #     OR an inflight sentinel younger than the TTL exists:
  #        [ -d "$2/.zskills/inflight" ] && find "$2/.zskills/inflight" \
  #          -name '*.json' -mmin -120 2>/dev/null | head -1 returns a line
  #        (120 min = 7200 s, the check-inflight-batch.sh default TTL.
  #        Honesty notes: this ages by file MTIME where
  #        check-inflight-batch's own `check` ages by the started_at
  #        JSON field — congruent today only because sentinels are only
  #        ever written/rewritten whole; and only the 5 cron-shaped
  #        workers write sentinels, with runs >2h aging out mid-run —
  #        the tracked-marker arms are the primary signal, the sentinel
  #        arm is supplementary)
  #   NOTE: bare [ -d "$2/.zskills/tracking" ] is deliberately NOT tested —
  #   finished pipelines leave subdirs there indefinitely (verified: 20+
  #   stale dirs in the dogfood repo), which would make enforce permanent.
  #   NOTE: the permission_mode VALUE inside subagent records dispatched
  #   from a default-mode parent is unpinned by Probe B (which verified
  #   field PRESENCE only). If subagents inherit "default", the
  #   LOCAL-root tracked arm is what keeps worktree pipeline agents
  #   enforced — that is why the $3 arm is load-bearing, not cosmetic.
  #   otherwise echoes "watched".

  # zskills_enforcement_load_toggles — arg: $1 = config file path
  #   ($1 = "$(zskills_enforcement_config_root)/.claude/zskills-config.json")
  #   Lazy + cached: first call populates _ZSK_ENF_TOGGLES (newline-separated
  #   "group.check=value" + "group.enabled=bool" lines) via ONE Python call
  #   (zskills_resolve_python convention); subsequent calls are no-ops.
  #   Python unavailable / file missing / json.load error → _ZSK_ENF_TOGGLES=""
  #   and _ZSK_ENF_TOGGLES_LOADED=1 (shipped defaults; never errors).

  # zskills_enforcement_mode — args: $1=group $2=check $3=class(hard|demotable) $4=predicate-result
  #   ($4 is the tri-valued predicate echo; both enforce-* values are the
  #   enforce arm for mode resolution — they differ only in _ZSK_ENF_SOURCE)
  #   echoes "block" | "warn" | "off" and sets _ZSK_ENF_SOURCE to one of:
  #   "project config: block|warn|off" | "group disabled in project config" |
  #   "autonomous default" ($4==enforce-autonomous) |
  #   "pipeline-active default" ($4==enforce-pipeline) |
  #   "attended default" ($4==watched).
  #   Resolution order:
  #     group enabled == false                → off   (group ceiling)
  #       EXCEPT check == config_hooks_tamper — the tamper check is
  #       ceiling-EXEMPT (Settled decision 13 self-protection: a group
  #       ceiling write must not take the tamper gate down with it);
  #       only its own explicit per-check value can turn it off, and
  #       writing that value is itself tamper-gated at write time
  #     per-check explicit value              → that value
  #     unset + class == hard                 → block
  #     unset + demotable + $4 == enforce-*   → block
  #     unset + demotable + $4 == watched     → warn

  # zskills_enforcement_tag — args: $1=group $2=check
  #   echoes "[hooks.$1.$2 — block|warn|off in .claude/zskills-config.json; currently: ${_ZSK_ENF_SOURCE}]"
  #   The emitted string MUST match the pinned literal regex (unit-suite
  #   case — the tripwires count CALL LINES, so only this unit assertion
  #   catches a typo in the one printf that builds the string):
  #     ^\[hooks\.[a-z_]+\.[a-z0-9_]+ — block\|warn\|off in \.claude/zskills-config\.json; currently: .+\]$
  #   (block-agents' static tag is the sole non-matching form — Settled
  #   decisions 10/14.)

  # zskills_enforcement_json_escape — arg: $1 = raw text; echoes the
  #   JSON-escaped string (no surrounding quotes). PURE BASH — byte-for-
  #   byte the json_escape contract already proven in
  #   block-stale-skill-version.sh ≈L541–568: LC_ALL=C; backslash first,
  #   then quote, then named control escapes (\n \r \t \b \f), then
  #   [[:cntrl:]] strip as defense-in-depth (the bash $'\x00'-$'\x1f'
  #   range form is a verified trap — see that hook's comment). Needed
  #   because flush W-A must serialize arbitrary multi-line STOP prose;
  #   zero Python (the performance contract's one-Python-call budget is
  #   already spent by the toggle loader on emitting paths). In Phase 2
  #   block-stale-skill-version RETARGETS its local json_escape twin to
  #   this lib function (drift-gated), so the logic has ONE source — not
  #   a third copy.

  # zskills_enforcement_warn — arg: $1 = full message (already tagged)
  #   Accumulates $1 into _ZSK_ENF_WARNINGS (newline-joined), prefixed
  #   "WARNING (not blocked by this check): " — non-committal because a
  #   SIBLING hook on the same matcher may still deny the same call.
  #   Emits nothing itself; the caller continues scanning.

  # zskills_enforcement_flush_warnings — no args; called once on the
  #   hook's final allow path. Empty _ZSK_ENF_WARNINGS → emits nothing.
  #   Otherwise emits the accumulated warnings on the warn channel PINNED
  #   by this phase's probe:
  #     Form W-A: printf the DECISION-LESS user-channel JSON:
  #       {"systemMessage":"<joined, escaped via zskills_enforcement_json_escape>"}
  #       (same field session-start-greeting.sh / session-rules-context.sh
  #       use; NO hookSpecificOutput, NO permissionDecision)
  #     Form W-B: printf '%s\n' "$_ZSK_ENF_WARNINGS" >&2
  #   Exactly ONE form ships (dead branch deleted, not flag-switched).
  #   HARD INVARIANT (Settled decision 2, unit-tested): under EITHER
  #   pinned form the warn-path output contains NO permissionDecision —
  #   the warn channel must never auto-approve (or otherwise touch) the
  #   permission flow for the very commands it warns about.
  #   Deny-path interaction, pinned: when a later check in the same scan
  #   resolves to block, the deny emission APPENDS any accumulated
  #   warnings to its permissionDecisionReason after the STOP text
  #   (newline-separated) — warned checks still name their switches even
  #   when a sibling check denies the call; nothing is silently dropped.
  ```

  Plus a data constant `_ZSK_ENF_KNOWN_CHECKS` — one `group.check:class`
  token per line, exactly the 37 keys of the Toggle-key registry table
  above (hard/demotable classes as tabled; includes
  `main_protection.config_hooks_tamper:demotable`). The unit suite and
  the Phase 3 tripwire both read this list.

  Performance contract (pinned in the file header): the predicate is pure
  bash + at most one `find` over `.zskills/inflight/` (only when that dir
  exists); the toggle loader runs ONLY when a gate is about to emit
  (lazy) — zero added cost on the no-violation path, and at most ONE
  Python invocation per hook fire.

- [ ] **Warn-channel visibility probe — GATING (Settled decision 2).**
  Headless, scriptable; attended only on the W-B fallback branch (below):
  1. Build a scratch consumer dir with a throwaway
     `.claude/settings.json` registering a one-off PreToolUse/Bash probe
     hook that emits Form W-A verbatim — the DECISION-LESS JSON
     `{"systemMessage":"ZSKILLS_WARN_PROBE_TOKEN"}` + exit 0. (Whether
     a decision-less systemMessage surfaces on PreToolUse is
     undocumented; deciding it is this probe's job.) The scratch
     settings ALSO allowlist the probe's trivial Bash command (so the
     headless run executes it without an interactive prompt), and every
     probe run uses DEFAULT permission-mode — never `bypassPermissions`,
     which would both falsify the watched-leg evidence AND flip the very
     `permission_mode` predicate input the later phases' fixtures stage.
  2. Run `claude -p '<prompt that runs a trivial echo>' --output-format
     stream-json` in that dir; capture stdout to
     `$TEST_OUT/warn-probe-a.json` AND stderr separately to
     `$TEST_OUT/warn-probe-a.stderr`.
  3. **W-A pass criterion, pinned mechanically:** a quoted `$PYTHON`
     one-liner walks each stream-json line-record and PASSES iff the
     token appears in a record whose top-level `"type"` is `"system"`
     OR in the final `"result"` record — and NOT merely inside an
     `"assistant"`/`"user"` record's tool_use/tool_result payload (the
     hook's own stdout echoing back through the tool transcript is the
     vacuous-pass trap). The one-liner prints the matched record's
     (type, field-path); the implementer quotes that record verbatim in
     the phase report and records the observed (type, field) next to
     the pin in the lib header. Separately record what the MODEL saw
     (grep the assistant turns) — document, don't gate. ALSO assert the
     probe run's tool call still went through the NORMAL permission
     flow (no auto-approval artifact in the stream) — with a
     decision-less envelope this is expected by construction; quote the
     evidence.
  4. W-A visible → pin Form W-A in `zskills_enforcement_flush_warnings`.
     W-A not visible → **W-B fallback leg, both branches pre-written
     (decide-then-pin):** re-run with the probe hook emitting Form W-B
     (token to stderr + exit 0), capturing `2> $TEST_OUT/warn-probe-b.stderr`.
     (a) If the token reaches a user-facing STREAM record (same pinned
     criterion as step 3), pin W-B on that evidence. (b) If it appears
     only in the CLI's own stderr capture or the harness transcript
     file — process-level propagation, NOT proof of interactive
     visibility — W-B may be pinned ONLY after a one-time ATTENDED
     confirmation: surface to the user (Failure-Protocol-style pause),
     have them run one watched `git add .` in the scratch consumer
     interactively and confirm the warning renders; record the
     confirmation verbatim. Quote the observed record/evidence in the
     phase report either way.
  5. NEITHER form demonstrably visible → Failure-Protocol STOP: the
     watched-warn premise is falsified; surface to the user before any
     demotion lands.
  6. **Multi-hook composition legs (same scratch dir, GATING; legs run
     with whichever form steps 4–5 PINNED, not W-A unconditionally):**
     (a) register TWO warn-emitting probe hooks (distinct tokens, each
     emitting the PINNED form) plus
     a byte-copy of `inject-bash-timeout.sh` (allow + `updatedInput`)
     on the same Bash matcher; run one Bash call; PASS = both tokens
     observable — per the step-3 stream criterion under W-A; under W-B,
     assert both tokens in the stderr capture instead (the step-3
     criterion applies only to W-A; under W-B no warn envelopes co-fire
     on stdout at all, and the updatedInput leg below is unchanged) —
     AND the injected `timeout` (600000) was still applied.
     **Applied-evidence ladder, pre-written (the stream-json
     observability of `updatedInput` is itself an unverified harness
     surface — don't improvise mid-probe):** (i) if a stream record
     (e.g. the assistant `tool_use` input) shows the injected timeout,
     quote it; (ii) if the timeout is visible in NO record, that is
     INVISIBLE, not clobbered — fall back to the behavioral check: make
     the probe Bash command a `sleep 130`-class call that only completes
     if the 600s extension applied (the un-extended 120s default kills
     it); completion = applied, quote the timing evidence. Only
     (iii) a VISIBLY reverted/clobbered merge — or the behavioral check
     failing — is the Failure-Protocol STOP: if the
     updatedInput merge is clobbered by a co-emitted warn envelope,
     STOP — Layer 0 of the
     verifier-cannot-run defense rides on it. (b) register the probe
     warn hook plus a denying sibling; assert the deny wins, and RECORD
     (document, don't gate) whether the warn's systemMessage still
     surfaced — if it is dropped, the lib's deny-path append rule (see
     flush spec) is what preserves the warned text, note that in the
     report.
  The probe transcript (commands + matched records) goes in the phase
  report verbatim; the pinned form is recorded in the lib file header
  with a DATED assumption note ("pinned against claude-cli <version> on
  <date>; envelope semantics are harness behavior, re-run the probe on
  CLI upgrades"). **Drift canary (cheap, not CI):** the probe script
  itself ships at `tests/manual/warn-channel-probe.sh` — NOT
  triplet-registered, never run by `tests/run-all.sh` (it is a manual
  probe, not a suite — exempt from Invariant 7 by design, stated here
  so the verifier doesn't flag it) — as a
  manually-runnable recheck for future CLI upgrades; a header comment
  says exactly when to re-run it. The headless stream is a PROXY for
  interactive rendering — state that caveat in the probe script header
  and the phase report (the Phase 7 attended check is the live-session
  confirmation).

  The file is sourceable under zsh consumers: any function using
  `BASH_REMATCH`/arrays carries `setopt LOCAL_OPTIONS KSH_ARRAYS
  BASH_REMATCH` guards per the #1169 idiom (LOCAL_OPTIONS form — it is a
  sourceable helper).

- [ ] **Schema: `config/zskills-config.schema.json`** gains the `hooks`
  block: an object with exactly the 7 group properties; each group is an
  object with optional boolean `enabled` and per-check properties (the
  registry's check names for that group) each
  `"enum": ["block", "warn", "off"]`; `additionalProperties: false` at
  both levels so typos are schema-visible. Example consumer config shape
  (write this example into the schema description or a docs comment):

  ```json
  {
    "hooks": {
      "git_discipline": { "git_add_all": "off", "tests_not_run": "block" },
      "main_protection": { "enabled": true, "main_edit": "warn" },
      "tracking": { "enabled": false }
    }
  }
  ```

  Do NOT add a `hooks` block to
  `skills/update-zskills/scripts/zskills-defaults.json` — toggle defaults
  are class-derived (absence semantics), not literal values; adding them
  would freeze predicate-driven behavior into a literal and churn the
  congruence-marker count for no benefit. (Document that rationale in the
  SCHEMA description, not in the defaults file — `zskills-defaults.json`
  is on this phase's Do-NOT-touch list.)

- [ ] **Unit suite `tests/test-zskills-enforcement-lib.sh`** (triplet
  registration per Invariant 7; `HOME` sandboxed to a tmp dir for ALL
  cases, modeled on `tests/test-zskills-resolve-config.sh` ≈L65) covering
  at minimum:
  predicate × {bypassPermissions→enforce-autonomous, default→watched,
  acceptEdits→watched, plan→watched, absent→enforce-autonomous, garbage
  value→enforce-autonomous,
  default+`.zskills/tracked` at the LOCAL root ($3) with the MAIN root
  ($2) clean→enforce-pipeline (the DA1 fixture — the production marker
  placement),
  default+`.zskills/tracked` at the MAIN root only→enforce-pipeline
  (the OR-arm),
  default+legacy `.zskills-tracked` at either root→enforce-pipeline,
  default+fresh `.zskills/inflight/<skill>/<id>.json` sentinel→enforce-pipeline,
  default+inflight sentinel BACKDATED past the TTL (`touch -d`/`touch -t`)→watched,
  default+STALE `.zskills/tracking/<finished-pipeline>/` subdir with
  requires/step markers but NO tracked file at either root→**watched**
  (the DA2 fixture — bare dir existence must not enforce),
  SPOOF: embedded escaped `\"permission_mode\":\"default\"` inside
  tool_input.command + real field bypassPermissions→enforce-autonomous,
  SPOOF + real field absent→enforce-autonomous};
  config_root × {inside main checkout, inside a linked worktree (echoes
  the MAIN root, not the worktree), non-git dir with CLAUDE_PROJECT_DIR,
  ZSKILLS_ENF_CONFIG_ROOT override wins};
  mode resolution × {hard unset → block on all three predicate values;
  demotable unset → block/block/warn by predicate value; explicit
  off/warn/block override both classes; group `enabled:false` ceiling
  beats per-check block; CEILING EXEMPTION —
  `main_protection.enabled:false` + `config_hooks_tamper` unset →
  config_hooks_tamper still resolves per predicate (NOT off), while
  sibling main_protection checks go off; explicit
  `config_hooks_tamper:"off"` → off (Settled decision 6 honored)};
  _ZSK_ENF_SOURCE × {autonomous default,
  pipeline-active default, attended default, each explicit-toggle
  source}; fail-closed × {no config file, malformed JSON,
  `ZSKILLS_PYTHON=/bin/false` simulated-unavailable → defaults};
  warn accumulation × {two warns in one scan → ONE flush emission
  containing both, prefix `WARNING (not blocked by this check): `;
  zero warns → flush emits nothing};
  **warn-path decision-less invariant (Settled decision 2):** the flush
  emission for a multi-line, quote-and-backslash-bearing warning does
  NOT match `permissionDecision` (grep -c → 0) AND — under W-A — parses
  as valid JSON via `$PYTHON -c 'import json,sys;json.load(sys.stdin)'`
  (locks the escape path against hostile STOP prose);
  json_escape × {quotes, backslashes, newlines, tabs, a raw control
  byte 0x01 (stripped, output still valid JSON)};
  emitted tag matches the PINNED literal regex from the
  `zskills_enforcement_tag` spec above (this is the only mechanical
  check of the emitted string — the tripwires count call lines);
  KNOWN_CHECKS list has 37 entries, 23 sites' worth
  demotable per the registry (assert the demotable key count = 16 keys),
  every key's group ∈ the 7 names.

- [ ] **Drift gate:** extend `tests/test-hook-helper-drift.sh`'s
  `fn_source()` map (≈L29–44) with the eight `zskills_enforcement_*`
  functions (`config_root`, `predicate`, `load_toggles`, `mode`, `tag`,
  `json_escape`, `warn`, `flush_warnings`) + `_ZSK_ENF_KNOWN_CHECKS`, consumer list
  initially EMPTY (no hook inlines it yet). A zero-consumer entry IS
  expressible in the gate's design (map entry present, hook iteration
  list unchanged); Phases 2–3 then add each inlining hook to the
  iteration list in the SAME commit as its inline — the gate only checks
  hooks it iterates, so a forgotten list entry is silent drift (this is
  why each phase carries an explicit consumer-list work item).

### Design & Constraints

- NO hook files change in this phase. NO resolver changes.
- The Python toggle dump is a self-contained heredoc using stdlib `json`
  only (no jq — project convention).
- Do NOT touch: any `hooks/block-*.sh`, `.claude/hooks/`,
  `zskills-resolve-config.sh`, `zskills-defaults.json`, any skill files,
  `tests/test-skill-conformance.sh`.

### Acceptance Criteria

- [ ] **GATING:** the warn-channel probe ran; the phase report quotes the
  probe transcript, names the pinned form (W-A or W-B), quotes the
  user-stream record proving visibility (per the pinned pass-criterion
  grammar, with the matched record's type+field named) plus the note on
  what the model saw, AND quotes the multi-hook composition results
  (both warn tokens observed; `updatedInput` timeout still applied;
  deny-sibling behavior recorded). No pinned form → the phase is NOT
  done (Failure-Protocol STOP). The probe script exists at
  `tests/manual/warn-channel-probe.sh` and is NOT registered in
  `tests/run-all.sh`.
- [ ] Warn-path decision-less invariant case passes: flush output for a
  hostile multi-line warning contains no `permissionDecision` and (W-A)
  round-trips through `json.load`.
- [ ] `bash tests/test-zskills-enforcement-lib.sh` passes; state per-case
  counts.
- [ ] `grep -c ':hard$\|:demotable$' hooks/_lib/zskills-enforcement.sh`
  (the KNOWN_CHECKS lines) → 37.
- [ ] Schema validates: `python3 -c "import json;json.load(open('config/zskills-config.schema.json'))"`
  exits 0, and the `hooks` property enumerates exactly 7 groups
  (main_protection including `config_hooks_tamper`).
- [ ] `bash tests/run-all.sh` green (Invariant 8 capture idiom); report
  per-suite counts.

### Dependencies

None — first phase.

---

## Phase 2 — Small-hook retarget (7 hooks) + bypass parity ×5

### Goal

Integrate the enforcement library into the seven small hooks: demote the
demotable checks (block-main-edits Edit/Write; the two claim gates), add
the `config_hooks_tamper` Edit/Write arm (Settled decision 13), tag
EVERY message in all seven (including the keep-hard ones), honor per-check
toggles everywhere, and land the 5 bypass-parity cases — with all mirrors,
stamps, and the block-agents `.template` regenerated in lockstep.

**Root arguments, pinned for every hook in this phase (R9/R2-4/DA1/DA3) —
two roots per hook, never conflated:**

- `ENF_ROOT=$(zskills_enforcement_config_root)` — the MAIN root, used for
  the toggle-loader path (`$ENF_ROOT/.claude/zskills-config.json`), the
  predicate's `$2`, and the tamper arm's target comparison. NOTE the
  corrected fact (the round-1 text was wrong): block-main-edits does NOT
  compute `MAIN_ROOT` from a git-common-dir expression — on disk
  (≈L125–132) `MAIN_ROOT` is `${REPO_ROOT:-${CLAUDE_PROJECT_DIR:-}}` →
  `git rev-parse --show-toplevel` → pwd; git-common-dir appears only
  inside the worktree-self check as a comparison operand. The two
  expressions coincide in a main-checkout session and DIVERGE in a
  worktree session (CLAUDE_PROJECT_DIR = worktree vs common-dir parent =
  main root). There is NO equality assert: `config_root()` is
  authoritative for toggles/predicate/tamper-target (Settled decision
  13); `MAIN_ROOT` remains the hook's containment/session root.
- `ENF_LOCAL` — the effective LOCAL root, the predicate's `$3` (the
  tracked-marker read root). For the Bash-matcher hooks in this phase
  (the two claim hooks, block-bypassed-land-pr,
  block-stale-skill-version): `resolve_effective_worktree_root
  "${LOCAL_ROOT:-}" "$(extract_cd_target)" "$(git rev-parse
  --show-toplevel 2>/dev/null || pwd)"` — block-stale-skill-version
  already inlines both helpers (reuse); the claim hooks and
  block-bypassed-land-pr inline them now (drift-gate consumer list
  updated in the same commit, R15). For the non-Bash hooks
  (block-main-edits: Edit/Write; block-bad-cron: CronCreate), no
  cd-target exists in their input — `ENF_LOCAL` = the session root,
  which for block-main-edits is exactly its existing `MAIN_ROOT` chain
  (THIS reuse claim is true on disk) and for block-bad-cron is
  `${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null ||
  pwd)}`.

### Work Items

- [ ] **block-main-edits.sh** (238L — the #1165 headline):
  - Inline the enforcement helper; add `block-main-edits.sh` to the
    drift-gate iteration list + per-hook fn coverage, SAME commit (R15).
  - **NEW `config_hooks_tamper` arm (registry row 49), placed ABOVE the
    worktree-self early-exit** — insertion point by CONTENT anchor, not
    line number: immediately after the `MAIN_ROOT`
    canonicalization block (the `RESOLVED_MAIN`/`MAIN_ROOT="${RESOLVED_MAIN%/}"`
    lines) and BEFORE the `# ── Worktree-self check ──` comment block.
    Rationale: the worktree-self check exits 0 for worktree-rooted
    sessions, but the tamper arm gates a MAIN-root file, so
    worktree-self is irrelevant to it — without this placement a
    pipeline agent in a worktree could Edit the main root's config by
    absolute path completely ungated (DA3). This placement also makes
    it fire regardless of `main_protected` (the config gate sits
    further down). Two consequences the implementer must handle:
    (1) the target-path resolution the arm needs (the
    ABS_FILE_PATH/RESOLVED_FILE normalization, on disk ≈L171–192,
    currently AFTER the config gate) is HOISTED into a function called
    by both arms — the tamper arm and the main_edit arm must normalize
    the target identically, one code path; (2) the arm compares the
    resolved target against `$(zskills_enforcement_config_root)/.claude/zskills-config.json`
    — config_root, NOT `MAIN_ROOT`, because in a worktree session
    MAIN_ROOT is the worktree and the file being protected is the MAIN
    root's (the divergence is load-bearing here; see the root pins
    above). Trigger: resolved target == the config path AND — for Edit —
    `new_string` OR `old_string` contains the literal `"hooks"` (the
    edited region intersects the hooks block); for Write, the `content`
    field contains `"hooks"` — a full-file Write of a config carrying a
    hooks block is IN scope BY DESIGN even when the hooks block is
    unchanged (an autonomous agent rewriting the toggle file wholesale
    is precisely what this gates; a watched session gets one warn —
    accepted noise, stated here so nobody "fixes" it). Route through
    `zskills_enforcement_mode main_protection config_hooks_tamper
    demotable "$PRED"` with a STOP text naming the tamper hazard + tag
    + the RECOVERY LINE (Settled decision 13: name the human-mediated
    re-enable/change path — "config changes to the hooks block need a
    human-reviewed edit or committed project review") in BOTH warn and
    deny variants. Edits to the config NOT touching a `"hooks"` key
    fall through untouched.
  - After the existing allowlist (≈L201–206), before the deny emission
    (≈L209): compute `PRED=$(zskills_enforcement_predicate "$INPUT" "$ENF_ROOT" "$MAIN_ROOT")`
    (ENF_ROOT = config_root for toggles/predicate-$2; MAIN_ROOT doubles
    as ENF_LOCAL for this Edit/Write hook — see the root pins),
    `MODE=$(zskills_enforcement_mode main_protection main_edit demotable "$PRED")`.
    `off` → exit 0. `warn` → `zskills_enforcement_warn` with the existing
    STOP text (s/STOP: Edit\/Write to main is blocked/Edit\/Write to main
    is normally blocked/) + tag, then `zskills_enforcement_flush_warnings`
    and exit 0. `block` → existing deny envelope, message now ending with
    the tag. Warn-arm text is human-addressed (Settled decision 2): keep
    the factual body + tag; the `/do pr` / `/run-plan` recommendations
    stay in the DENY arm only.
  - The existing config gate (≈L154–165, fail-OPEN `"main_protected": true`
    literal grep) is UNTOUCHED in this phase (Phase 4 adds the user-tier
    floor read).
  - `tests/test-block-main-edits.sh` re-spec (Invariant 5, old/new values
    in the commit message): C1/C2/C15–C17 deny cases now run with
    `permission_mode: "bypassPermissions"` injected into the fixture input
    (still DENY — these become 1 of the 5 parity cases via C1; keep all
    five as deny-under-bypass). NEW cases: watched (default, no markers) →
    allow + warn-channel output contains `[hooks.main_protection.main_edit`
    (assert on the Phase-1-pinned channel: the systemMessage JSON for W-A,
    stderr for W-B); watched + `.zskills/tracked` present → DENY; watched +
    a stale `.zskills/tracking/<id>/` subdir but NO tracked file → allow +
    warn (the DA2 fixture); toggle `"off"` → silent allow; toggle
    `"block"` + watched → DENY; toggle `"warn"` + bypass → allow + warn
    (explicit override honored, Settled decision 6); tamper arm —
    Edit of `.claude/zskills-config.json` with `"hooks"` in new_string ×
    {bypass → DENY (parity case), watched → warn, no-`"hooks"` edit →
    falls through to the main_edit arm,
    **`main_protected` ABSENT/false → tamper arm STILL fires** (the
    placement's headline property — without this fixture a one-block-
    too-late insertion ships green, R2-6),
    **worktree-session fixture: session root = a linked worktree
    (REPO_ROOT points at it), Edit targets the MAIN root's config by
    absolute path with `"hooks"` in new_string → still gated** (warn
    watched / deny bypass — proves the arm sits above the worktree-self
    exit, DA3),
    group ceiling `main_protection.enabled:false` + tamper edit →
    STILL gated (ceiling exemption),
    self-protection: config currently WITHOUT a config_hooks_tamper
    value, Edit setting `config_hooks_tamper:"off"`, bypass → DENY
    (the gate evaluates under the pre-write config),
    warn/deny text contains the recovery line (substring assert)}.
    C5–C9 allowlist cases unchanged.
- [ ] **block-fix-issue-unclaimed.sh** (2 sites → `hooks.tracking.issue_unclaimed`,
  demotable) and **block-run-plan-unclaimed.sh** (1 site →
  `hooks.tracking.plan_unclaimed`, demotable): same integration pattern;
  warn arm allows worktree creation with the foreign-claim/no-claim text
  as a warning. Although these two hooks parse stdin with Python
  elsewhere, their `permission_mode` read uses the SAME inlined lib
  predicate as every other hook (the unescaped-quote regex is
  spoof-proof; one drift-gated extraction path, not two). Both are
  Bash-matcher hooks with no root resolution today: they inline
  `extract_cd_target` + `resolve_effective_worktree_root` for
  `ENF_LOCAL` (root pins above; drift-gate consumer list, same commit).
  Extend
  `tests/test-block-fix-issue-unclaimed-ownership.sh`
  and `tests/test-plan-claim-hook-deny.sh`: existing deny cases gain
  `permission_mode: "bypassPermissions"` in fixture stdin (parity cases
  ×3 across the two hooks), plus one watched→warn case each.
- [ ] **Keep-hard small hooks — tags + toggle honoring only** (predicate
  is consulted but unset-default stays block):
  - `block-stale-skill-version.sh` → tag `hooks.git_discipline.stale_skill_version`
    appended to the relayed stage-check STOP message. Its local
    `json_escape` twin (≈L541–568) is RETARGETED to the lib's
    `zskills_enforcement_json_escape` (byte-identical contract — the
    lib function was specced FROM this twin), so the escape logic has
    one drift-gated source; list the hook as a consumer of that
    function in the drift gate, same commit.
  - `block-bad-cron.sh` → all 3 `emit_deny` REASONs end with
    `hooks.tracking.cron_invalid` tag.
  - `block-bypassed-land-pr.sh` → both deny messages (incl. the
    STATIC_FALLBACK ≈L376) end with `hooks.pr_discipline.direct_gh_pr`
    tag; header ≈L40–44 reworded: "the deny default is unconditional; an
    explicit project toggle is the only override."
  - `block-agents.sh` → both messages (≈L168, ≈L184) end with the static
    tag `[agents.min_model — set in .claude/zskills-config.json; raise-only across config tiers]`.
    No enforcement-lib inline here (no hooks.* key — Settled decision 10).
  - Each keep-hard hook with a hooks.* key inlines the lib and routes its
    deny through `zskills_enforcement_mode <group> <check> hard "$PRED"`
    so explicit `warn`/`off` toggles work; `off` for these hooks means the
    project deliberately disabled the gate.
- [ ] **Drift-gate consumer list (R15):** every hook that inlines the lib
  in this phase (all 7 except block-agents, which takes no lib — Settled
  decision 10) is added to `tests/test-hook-helper-drift.sh`'s hook
  iteration list with its fn coverage, in the SAME commit as the inline.
  The gate only checks hooks it iterates — a missing list entry is
  silent drift, so this is a checklist item, not an afterthought.
- [ ] **Lockstep per Invariant 2:** stamp bumps on all 7 hooks, all 7
  `.claude/hooks/` mirrors, `block-agents.sh.template` regenerated.
- [ ] Extend `tests/test-block-bad-cron.sh`,
  `tests/test-block-bypassed-land-pr.sh`, and the
  `tests/test-canary-failures.sh` expectations (`expect_deny_substring`
  ≈L41 keys on `"permissionDecision":"deny"` + substring — the added tag
  must not break existing substrings; verify, don't assume).

### Design & Constraints

- Bypass-parity test count landed this phase: **5** (main_edit ×1,
  config_hooks_tamper ×1, issue_unclaimed ×2, plan_unclaimed ×1).
- The warn-arm transformation of message text is mechanical: the lib
  prefixes `WARNING (not blocked by this check): ` (non-committal — a
  sibling hook on the same matcher may still deny the call) and keeps
  the body; do not rewrite STOP prose beyond the block-main-edits
  s/is blocked/is normally blocked/ noted above, EXCEPT that
  agent-directed advice lines are kept deny-arm-only (Settled decision
  2 — the warn audience is the human).
- block-main-edits' messages do NOT yet mention move-to-worktree (the
  helper doesn't exist until Phase 5 — Phase 5 adds the pointer to the
  deny text).
- Do NOT touch: `block-unsafe-generic.sh`, `block-unsafe-project.sh`
  (Phase 3 — registry row 50's Bash-side tamper arm lands THERE, not
  here), `zskills-resolve-config.sh` (Phase 4), any skill SKILL.md,
  `block-unmaterialised-skill.sh` (exempt).

### Acceptance Criteria

- [ ] All 5 bypass-parity cases pass:
  `bash tests/test-block-main-edits.sh && bash tests/test-block-fix-issue-unclaimed-ownership.sh && bash tests/test-plan-claim-hook-deny.sh`.
- [ ] Tag presence spot-check (Settled decision 14 forms; the Phase 3
  tripwire formalizes this). Call-line form for the six lib-tagging
  hooks:
  `grep -cE 'zskills_enforcement_tag[[:space:]]+[a-z_]+[[:space:]]+[a-z0-9_]+' hooks/block-main-edits.sh hooks/block-bad-cron.sh hooks/block-bypassed-land-pr.sh hooks/block-stale-skill-version.sh hooks/block-fix-issue-unclaimed.sh hooks/block-run-plan-unclaimed.sh`
  → per-file counts 2/3/2/1/2/1 respectively; static-literal form for
  block-agents:
  `grep -cE '\[agents\.min_model — ' hooks/block-agents.sh` → 2.
- [ ] `bash tests/test-hooks-mirror-parity.sh` and
  `bash tests/test-hook-template-sibling.sh` pass (lockstep proof).
- [ ] `bash tests/run-all.sh` green; per-suite counts reported.

### Dependencies

Phase 1 (library + drift-gate entry).

---

## Phase 3 — Big-hook retarget (generic + project) + tag tripwire + bypass parity ×18

### Goal

Apply the proven integration pattern to `block-unsafe-generic.sh` (18
existing sites + the new row-50 tamper check = 19) and
`block-unsafe-project.sh` (17 sites) — one commit each — then land the
message-tag conformance tripwire and the lib↔schema registry-sync
tripwire now that all 49 in-scope emissions are tagged.

**Root arguments, pinned (R9/DA1/DA3):** both hooks pass `ENF_ROOT`
(main root) to the toggle path and the predicate's `$2`, and
`ENF_LOCAL` (effective local root) to the predicate's `$3`. For
block-unsafe-project: `ENF_ROOT` REUSES its existing `TRACKING_ROOT`
(≈L859–864, env-overridable for tests — keep that property; same
git-common-dir-parent CORE as the Phase 1 config_root spec, so no
equality assert is needed — but the fallback TAILS differ in non-git
contexts: TRACKING_ROOT's degenerate `.git/..` cd yields EMPTY where
config_root falls back to `CLAUDE_PROJECT_DIR`/pwd; that divergence is
fail-safe — an empty TRACKING_ROOT makes the toggle path unresolvable,
so the lib serves shipped defaults, fail-closed — and hooks fire inside
checkouts in practice; reuse as-is), and `ENF_LOCAL` reuses
its existing `LOCAL_ROOT` (already computed via
`resolve_effective_worktree_root` at ≈L885 — the SAME root its Tier-1
`TRACKED_MARKER` read uses at ≈L889, which is exactly the alignment the
predicate needs). **Hoist pin (same gap class as the Phase 2
block-main-edits hoist):** both reused computations currently sit BELOW
several emission sites that will need them — the first emission is the
recursive-`.zskills`-delete block (`rm … .zskills` →
`block_with_reason`, ≈L607), well above TRACKING_ROOT's first
computation (≈L863) and LOCAL_ROOT's (≈L885). Hoist both computations
VERBATIM (keeping their `${VAR:-…}` env-override guards) above that
first emission site; the later per-section `${VAR:-…}` re-computations
(the file already recomputes them at ≈L994/1001 and ≈L1060/1067) then
no-op idempotently. A missed hoist fails LOUD (unset/empty root at the
first watched-warn fixture), but pin it anyway — don't rely on the
failure. The hook's two-root split is therefore unchanged; the
predicate simply consumes both existing roots, computed earlier. For block-unsafe-generic
(which resolves no root outside the push arm, ≈L1118–1122) both helper
calls are new: it inlines `extract_cd_target` +
`resolve_effective_worktree_root` for `ENF_LOCAL` (drift-gate consumer
list, same commit) and calls `zskills_enforcement_config_root` for
`ENF_ROOT`, shared by all 19 sites.

### Work Items

- [ ] **Commit 1 — block-unsafe-generic.sh:** inline the lib; route all
  sites through `zskills_enforcement_mode` with the registry's
  group/check/class. **NEW row-50 `config_hooks_tamper` check —
  DESTINATION-ANCHORED, narrowed (DA4):** fires when `$COMMAND`
  (post-redaction, post-#772 re-injection — the same scanned text every
  other check sees) contains a WRITE whose TARGET is the config file:
  a `>` / `>>` redirection whose immediately-following token ends in
  `zskills-config.json`; `tee` (or `tee -a`) with an argument ending in
  `zskills-config.json`; `sed -i` with a file argument ending so; or
  `mv`/`cp` whose LAST (destination) argument ends so. The bare
  presence of the filename plus an unrelated indicator does NOT fire —
  reads like `grep landing .claude/zskills-config.json > out.txt`
  (redirect target is NOT the config) and inspection/backup `cp` FROM
  the config are out of scope by construction. Class demotable.
  Sanctioned-writer interplay, VERIFIED and pinned: zskills' own config
  writers are Bash-mediated with VARIABLE destinations — the init seed
  fence (update-zskills SKILL.md ≈L1210–1232) writes via a Python
  heredoc to `"$zs_cfg_tmp"` then `mv "$zs_cfg_tmp" "$ZS_CONFIG"`; no
  token ending in the literal `zskills-config.json` is a write
  destination there, so the destination-anchored trigger does not fire
  on it (the fence's literal filename appears only in ASSIGNMENTS and
  the `>&2` is an fd-dup, not a file redirect). Phase 6's personal
  scaffold keeps the same variable-destination tmp+mv shape (pinned
  there as load-bearing). Note the textual trigger also matches a
  user-tier `~/.claude/zskills-config.json` literal destination —
  accepted: user-tier keys are cascade/raise-only (a write there cannot
  lower protection), and a warn/deny on a direct literal write to it is
  acceptable noise. Residual non-coverage (variable-destination /
  programmatic writes that never name the file as a literal
  destination) is accepted per Settled decision 13's threat model
  (anti-casual, transcript-visible) — do not chase it with shell
  parsing. Demotable: `git_add_all`
  (≈L1008), `push_to_main` (≈L1133), `config_hooks_tamper` (new). The
  row-50 STOP/warn text carries the same RECOVERY LINE as row 49
  (Settled decision 13: name the human-mediated path — fixture asserts
  the substring). The other 16 stay hard. The `block_with_reason` helper gains a sibling
  `gate_with_reason <group> <check> <class> <msg>` that resolves mode,
  **appends `$(zskills_enforcement_tag "$1" "$2")` to the message
  itself** (Settled decision 14 — sites pass bare group/check args; the
  tag is built in exactly one place), returns (continues scanning) on
  warn/off — accumulating via `zskills_enforcement_warn` — and falls
  through to `block_with_reason` on block, where any already-accumulated
  warnings are APPENDED to the deny's permissionDecisionReason per the
  lib's pinned deny-path rule (nothing silently dropped). Warn must NOT
  exit the scan loop early, or a single warned check would mask a later
  hard check in the same command; the hook's final allow path calls
  `zskills_enforcement_flush_warnings`. Drift-gate iteration list updated
  (R15). Stamp bump + mirror.
  Extend `tests/test-hooks-misc.sh` (or the suite that pins these gates —
  re-derive by grepping for the message substrings): every existing deny
  case for the 16 hard sites unchanged; the 3 demotable sites gain
  bypass-parity (deny under `bypassPermissions`) + watched→warn cases,
  including the SPOOF parity case of Invariant 4 (counterfeit
  permission_mode literal in the command string).
- [ ] **Commit 2 — block-unsafe-project.sh:** same pattern for 17 sites
  (15 demotable, 2 hard per the registry). The tracking gates (≈L336–361)
  route through `hooks.tracking.*`. **The demotion is REAL and testable
  (DA1/DA2/DA3):** the predicate's pipeline arm keys on the LIVE
  `.zskills/tracked` marker read at the EFFECTIVE LOCAL root — the
  marker's real lifecycle is worktree-scoped: create-worktree.sh ≈L407
  writes `$WT_PATH/.zskills/tracked` at dispatch, `execute-phase.md`
  ≈L1800 removes the WORKTREE copy at completion — via the hook's
  existing `LOCAL_ROOT` (the same root its Tier-1 `TRACKED_MARKER` read
  at ≈L889 already uses), plus the main-root and inflight OR-arms — NOT
  on `.zskills/tracking/` dir existence. So an in-flight pipeline's
  worktree agents (tracked marker present at their local root, or
  reachable via cd-target extraction when the orchestrator runs
  `cd /tmp/wt && git commit`) keep every tracking gate enforced, while
  a FINISHED pipeline's leftover `requires.*`/`step.*` markers under
  `.zskills/tracking/<id>/` — with the tracked marker already removed —
  produce warn in a watched session. That second state is the
  watched→warn tracking-gate fixture: markers present, NO tracked file
  at either root, NO fresh sentinel, `permission_mode: "default"` →
  warn + allow.
  Stamp bump + mirror +
  **`.sh.template` regenerated byte-equal, same commit** + drift-gate
  iteration list updated (R15). Extend
  `tests/test-hooks-main-protected.sh` + `tests/test-hooks-misc.sh`:
  parity cases for all 15 demotable sites (incl. one SPOOF case),
  watched→warn cases for at least `commit_on_main`, `push_to_main`,
  `tests_not_run`, and the stale-pipeline tracking-gate fixture above.
- [ ] **Commit 3 — conformance tripwires** in
  `tests/test-skill-conformance.sh` (model: the gate allow/block-list
  tripwire ≈L1734–1777 — sed-extracted lists + anti-vacuous emptiness
  check):
  1. **Tag-format tripwire — exactly the Settled-decision-14 forms, one
     per hook class.** Big hooks (wrapper-tagged), pinned counts:
     ```bash
     grep -cE '^[[:space:]]*gate_with_reason[[:space:]]+(git_destructive|fs_destructive|process_kill|git_discipline|main_protection|pr_discipline|tracking)[[:space:]]+[a-z0-9_]+' "hooks/$H"
     ```
     → `block-unsafe-generic.sh:19 block-unsafe-project.sh:17`.
     Small hooks (call-line-tagged), pinned counts:
     ```bash
     grep -cE 'zskills_enforcement_tag[[:space:]]+[a-z_]+[[:space:]]+[a-z0-9_]+' "hooks/$H"
     ```
     → `block-main-edits.sh:2 block-fix-issue-unclaimed.sh:2
     block-run-plan-unclaimed.sh:1 block-stale-skill-version.sh:1
     block-bad-cron.sh:3 block-bypassed-land-pr.sh:2`.
     Static-literal hook:
     `grep -cE '\[agents\.min_model — ' hooks/block-agents.sh` → 2.
     Anti-vacuous: a zero count for any listed hook FAILS.
     `block-unmaterialised-skill.sh` is asserted ABSENT from all three
     forms (exemption is explicit, not silent).
     **Warn-emission assertions (DA8 — call-line counts can't see the
     emitted string):** in every lib-inlining hook, (a) the inlined
     `zskills_enforcement_tag` printf format string matches the pinned
     emitted-tag skeleton from the Phase 1 lib spec (one grep over the
     inlined function body), (b) the literal warn prefix
     `WARNING (not blocked by this check): ` appears exactly once (in
     the inlined warn function), and (c) the inlined flush function
     body contains NO `permissionDecision` literal — the decision-less
     invariant, which holds under WHICHEVER form was pinned
     (mechanically checked at every inline copy, not just the lib
     source).
  2. **Registry-sync tripwire.** Extract the key set from
     `_ZSK_ENF_KNOWN_CHECKS` in `hooks/_lib/zskills-enforcement.sh` and
     the per-group check properties from
     `config/zskills-config.schema.json`; assert set-equality (37 keys)
     and that every group/check pair found by tripwire 1's two
     group-bearing forms is a member. Anti-vacuous: either extraction
     yielding < 30 keys FAILS (guards against a sed/format drift
     extracting nothing). (Phase 7 extends this tripwire to the docs key
     list and the TSV rows once those exist — DA16.)

### Design & Constraints

- Bypass-parity test count landed this phase: **18** (generic 3 +
  project 15). Running total with Phase 2: **23** — matches the
  registry's demotable-site count exactly; the verifier checks this sum.
- block-unsafe-project is the riskiest file in the repo for this plan
  (1277L + template + tracking gates) — its commit contains NOTHING else.
- The generic push gate's fail-CLOSED config default (absent
  `main_protected` → block push, PROJECT-ONLY carve-out ≈L34) and the
  project hook's fail-OPEN `is_main_protected()` (≈L558) keep their
  fail directions — the predicate composes orthogonally with each hook's
  config default (it gates HOW a triggered check lands, not whether the
  config arms it).
- Do NOT touch: the resolver, skill files, `warn-config-drift.sh`,
  the impl-dispatch conformance pins (≈L714–732), the congruence-marker
  section (≈L2489–2560).

### Acceptance Criteria

- [ ] Both tripwires pass AND fail correctly: demonstrate the anti-vacuous
  arm by temporarily breaking one tag in a scratch copy (not committed)
  and showing the tripwire FAILs — quote the failure line in the phase
  report.
- [ ] `grep -rE '"permission_mode"' tests/ | grep -c bypassPermissions` ≥ 23
  (parity coverage floor; exact suite-level counts reported per suite).
- [ ] Template sibling + mirror parity suites pass.
- [ ] `bash tests/run-all.sh` green; per-suite counts reported.

### Dependencies

Phases 1–2 (library proven; pattern established; remaining tags are this
phase's, so the tripwire can only land here).

---

## Phase 4 — Cascade v2: workflow keys + raise-only floors

### Goal

Give the user tier `~/.claude/zskills-config.json` its #1159-scoped powers:
plain cascade for `execution.landing`, `execution.branch_prefix`,
`execution.max_concurrent_worktrees`; raise-only floors for
`execution.main_protected` and `agents.min_model` — in the bash resolver,
the 3-copy Python loader, and the floor-reading hooks, with per-tier
fail-closed everywhere, Test 15a re-specced, and the load-bearing landing
readers migrated onto new resolver variables.

### Work Items

- [ ] **Resolver (`skills/update-zskills/scripts/zskills-resolve-config.sh`,
  310L):**
  - `_zsk_extract_cascade_keys()` (≈L172–206) gains execution-block-scoped
    extraction (the `ensure-worktree.sh` ≈L180 BASH_REMATCH idiom — match
    inside the `"execution": { … }` object, never top-level) for
    `landing`, `branch_prefix`, `max_concurrent_worktrees`. Export names,
    PINNED (R6/R7 — chosen to collide with nothing):
    `ZSKILLS_CFG_LANDING` and `ZSKILLS_CFG_BRANCH_PREFIX` are NEW names,
    exported EMPTY when the key is unset in BOTH tiers — the resolver
    deliberately carries NO built-in default for these two, so every
    consumer fence keeps its OWN unset-default (fix-issues/run-plan keep
    `cherry-pick`, /do keeps `direct`) and no behavior flips for
    unconfigured projects. The names are distinct from the fence-local
    `LANDING_MODE`/`CFG_LANDING`/`BRANCH_PREFIX` variables those fences
    already use, so sourcing the resolver clobbers nothing.
    `max_concurrent_worktrees` KEEPS its existing exported name
    `ZSKILLS_MAX_CONCURRENT_WORKTREES` and its resolver default `3`
    (live consumers: `fix-issues/modes/sprint.md` ≈L184/211/1533/1575/1596,
    `tests/test-fix-issues-worktree-cap.sh` — NO rename, only the move
    from project-only to cascade). Called user-body-first then project
    (project wins) — the existing two-pass structure already does this.
    NO new `# zskills-defaults-congruence:` markers (the resolver holds
    no literal defaults for landing/branch_prefix to keep congruent);
    the conformance count pin (≈L2559) stays at **5**.
  - NEW `_zsk_extract_floor_keys()` — called for BOTH tiers, merging
    raise-only: `ZSKILLS_MAIN_PROTECTED` (PINNED export name — distinct
    from the fence-local `MAIN_PROTECTED` vars in ensure-worktree.sh and
    update-zskills/SKILL.md; exported `true` iff either tier carries
    the literal `"main_protected": true` inside its execution block) and
    `ZSKILLS_MIN_MODEL` (display-only, per the lattice below). Carries
    the `setopt LOCAL_OPTIONS KSH_ARRAYS BASH_REMATCH` guard like its
    siblings; `unset -f` at ≈L270 alongside the others.
  - **min_model merge lattice (pinned — implementers do not re-derive).**
    ENFORCEMENT AUTHORITY = `block-agents.sh`, which merges the two raw
    tier literals itself and resolves `"auto"`/`"inherit"` DYNAMICALLY
    first (its existing transcript machinery, ≈L56–60; fallback sonnet
    when the transcript is unreadable, ≈L84–86) — so the merge compares
    real ordinals via `model_ordinal()` (≈L91–105: haiku=1, sonnet=2,
    opus=3, unknown=0/no-constraint). Effective floor = the HIGHER
    ordinal after resolution; on a TIE the **project literal wins** (its
    message names the project switch). Because auto is resolved BEFORE
    comparison, a user's explicit floor can never be silently lowered by
    a project `"auto"` in a low-model session (DA15 closed).
    The bash resolver and the Python 3-copy export a DISPLAY-ONLY merged
    `ZSKILLS_MIN_MODEL` using the static approximation (auto/inherit
    rank as ordinal 2, tie→project literal) — pinned as approximate in a
    comment, never read by enforcement.
  - `_zsk_extract_project_only_keys()` (≈L222–261) drops
    `max_concurrent_worktrees` (moved to cascade) and keeps
    `zskills_version` + `dashboard_completed_days` +
    `dashboard_completed_limit` (the real key name — the draft's
    `dashboard_limit` does not exist) project-only. Rewrite the Pass-1
    comment (≈L209–210) to the new contract.
  - Per-tier fail-closed is structural for the bash reader: the user-tier
    pass is the same literal-extraction over the user body; a garbage file
    simply matches nothing. For floors this is inherently safe — raise-only
    OR/max merges mean a malformed file can only fail to RAISE, never
    lower. State this in the resolver header.
  - Skill-version bump for `update-zskills` (Invariant 1) + mirror.
- [ ] **Python 3-copy lockstep (Invariant 10):** `collect.py` ≈L336–365
  (`user.pop("execution", None)` ≈L361), `briefing.py` ≈L83, `server.py`
  ≈L285 — replace the blanket pop with: pop user `execution`, then
  re-merge `landing`/`branch_prefix`/`max_concurrent_worktrees`
  (project > user) and floors (`main_protected` OR-merge; `min_model`
  max-ordinal with the display-only static lattice incl.
  auto=2/tie→project, commented as approximate — block-agents is the
  enforcement authority). Keep the SYNC NOTEs accurate. Malformed user
  file → `try/except` → user tier contributes nothing. These three files
  live under skill dirs: Invariant-1 `metadata.version` bumps +
  `mirror-skill.sh` for **`zskills-dashboard`** (collect.py, server.py)
  and **`briefing`** (briefing.py), same commit (R16).
- [ ] **Floor-reading hooks gain the two-tier read** (same raise-only
  guarantee, each preserving its own fail direction; stamp + mirror +
  template lockstep per Invariant 2):
  - `block-agents.sh` ≈L44–49: read `min_model` from project, then from
    `${HOME}/.claude/zskills-config.json`; resolve each tier's
    `auto`/`inherit` to the session model FIRST (existing ≈L56–60
    machinery), then effective = higher ordinal, tie→project literal
    (the pinned lattice above). Rewrite the ≈L6–12 carve-out header to
    the floor contract. Template regen.
  - `block-main-edits.sh` ≈L154–165 and `block-unsafe-project.sh`
    `is_main_protected()` ≈L558: protected iff project literal-true OR
    user literal-true (fail-OPEN direction preserved: both absent →
    allow). **Read-root pin (R2-7):** each gate's PROJECT-tier read
    keeps its existing root — block-main-edits reads
    `$MAIN_ROOT/.claude/zskills-config.json`, `is_main_protected()`
    keeps its LOCAL-toplevel `${REPO_ROOT:-$(git rev-parse
    --show-toplevel …)}` read (≈L560; a worktree reads its own
    branch-current copy — existing, documented behavior at ≈L640–646;
    changing the ARMING key's read root is out of scope, only TOGGLES
    are main-root-only per Settled decision 13). The user-tier read is
    additive: `${HOME}/.claude/zskills-config.json`, OR-merged
    raise-only.
  - `block-unsafe-generic.sh` push gate ≈L1111–1127: enforce iff NOT
    (project says `"main_protected": false` AND user does not say true) —
    i.e. user true overrides project false; the fail-CLOSED direction
    (absent everywhere → block push) is preserved. Rewrite the ≈L34
    carve-out comment.
  - `block-fix-issue-unclaimed.sh` / `block-run-plan-unclaimed.sh`
    (Python `branch_prefix` readers ≈L184–194): project > user > `feat/`.
- [ ] **Test 15 re-spec + new cascade tests**
  (`tests/test-zskills-resolve-config.sh`, HOME sandbox ≈L65 already
  exists): 15a's subject changes (Invariant 5; commit message carries old
  + new). The EXISTING fixture (≈L694–700, quoted exactly) sets user-tier
  `"max_concurrent_worktrees": 9`, `"dashboard_completed_days": 99`,
  `"dashboard_completed_limit": 9999`. OLD — all ignored (expected
  `3/14/500`); NEW — `max_concurrent_worktrees=9` IS effective when the
  project doesn't set it (expected `9/14/500`), dashboard keys still
  ignored. 15b (`zskills_version` ignored) byte-unchanged. 15c
  (project mcw=5 effective) unchanged. NEW cases: user `landing: "pr"` →
  `ZSKILLS_CFG_LANDING=pr` when project silent / project `landing` wins /
  both unset → `ZSKILLS_CFG_LANDING` EMPTY (the no-resolver-default
  contract); same trio for `branch_prefix`; floors — user
  `main_protected:true` + project `false` → `ZSKILLS_MAIN_PROTECTED=true`;
  user `min_model:"opus"` + project `"sonnet"` → opus; user `"haiku"` +
  project `"sonnet"` → sonnet; project `"auto"` + user `"sonnet"` →
  `auto` (display-lattice tie→project); malformed user file → all of
  the above fall back to project/built-ins (extends Test 13's precedent
  to the new keys).
- [ ] **Landing-reader migration — precisely scoped to the VERIFIED
  extraction-fence inventory (R4/DA10).** Exactly SIX files contain a
  config-extraction read of `landing`/`branch_prefix` (re-verified
  against the worktree at refine time — the fences use escaped
  `\"landing\"` BASH_REMATCH, so grep for `\\\"landing\\\"` /
  `CFG_LANDING`):
  - `skills/create-worktree/scripts/ensure-worktree.sh` ≈L180/183
    (inline BASH_REMATCH → source resolver; lane-portable resolution as
    the canonical prelude documents; its `main_protected` read migrates
    to `ZSKILLS_MAIN_PROTECTED`, which gives it the user-tier floor for
    free).
  - The landing-mode RESOLUTION fences in **5 skill surfaces**:
    `do/SKILL.md` (Phase 1.5, ≈L897–926), `fix-issues/SKILL.md`
    (≈L141–152), `run-plan/SKILL.md` (≈L108–121), `commit/SKILL.md`
    (≈L86–87), `update-zskills/SKILL.md` (≈L491–497, execution-scoped —
    this fence also reads `branch_prefix` and migrates both).
    `draft-plan/SKILL.md` ≈L921, `refine-plan/SKILL.md` ≈L742,
    `draft-tests/modes/land.md` ≈L160, and `do/modes/pr.md` carry ONLY
    prose mentions of `execution.landing` (the #581 auto-land
    explanation) — **no fence exists there; do not invent one** (the
    draft's 8-surface list was wrong; this list is re-derived from
    disk).
  - **Per-fence migration contract (R7 — zero behavior change):** each
    fence replaces ONLY its config-extraction source — the
    `cat config + BASH_REMATCH` read becomes "source
    `zskills-resolve-config.sh` (lane-portable prelude), read
    `$ZSKILLS_CFG_LANDING`". Everything else is PRESERVED byte-for-byte
    in behavior: arg-flag precedence stays first (/do, /fix-issues,
    /run-plan, /commit), /do's enum remap (`cherry-pick`→`worktree`,
    unknown→`direct`) keeps mapping INTO its own `LANDING_MODE` local,
    and every fence keeps its own unset-default (`cherry-pick` for
    fix-issues/run-plan, `direct` for /do) — possible because
    `ZSKILLS_CFG_LANDING` is empty-when-unset. Commit message states
    "no behavior change intended" with the equivalence argument
    (Invariant 5).
  - **NOT migrated, by design:** `skills/update-zskills/scripts/apply-preset.sh`
    ≈L150–153 probes `CURRENT_LANDING` from the PROJECT FILE to decide
    whether to rewrite that file (≈L220–222) — using the cascaded
    effective value would skip needed project-file writes when the user
    tier already matches (R5). Annotate the probe with a one-line
    comment saying exactly that. The two claim hooks' Python
    `branch_prefix` readers are covered in the floor-hooks bullet (they
    cannot source the resolver; their Python does the two-tier read
    directly).
  - Conformance tripwire: for each migrated file, assert the resolution
    fence sources `zskills-resolve-config.sh` and references
    `$ZSKILLS_CFG_LANDING` (positive-side fence-local check, modeled on
    the existing per-fence prelude check); anti-vacuous pinned file
    count = **6** (5 skill surfaces + ensure-worktree.sh). Also assert
    apply-preset.sh does NOT reference `ZSKILLS_CFG_LANDING` (the R5
    exclusion is pinned, not assumed).
  - Skill-version bumps (Invariant 1) for every touched skill
    (`create-worktree`, `do`, `fix-issues`, `run-plan`, `commit`,
    `update-zskills`) + `mirror-skill.sh` each.
- [ ] **HOME sandboxing for every floor-reading hook/resolver suite
  (DA9).** After this phase, four hooks and the resolver read
  `${HOME}/.claude/zskills-config.json` — a dev machine's personal
  config (which Phase 6 actively promotes creating) must not flip test
  outcomes. Add `HOME="$TMP_HOME"` (model: `test-zskills-resolve-config.sh`
  ≈L65) to ALL cases — not just the new floor cases — in:
  `tests/test-block-main-edits.sh`, `tests/test-hooks-main-protected.sh`,
  `tests/test-hooks-misc.sh`,
  `tests/test-block-fix-issue-unclaimed-ownership.sh`,
  `tests/test-plan-claim-hook-deny.sh`, `tests/test-canary-failures.sh`
  (block-agents reproducers ≈L744+), and
  `tests/test-fix-issues-worktree-cap.sh` (sources the resolver; its
  "absent field → 3" case is exactly what a personal mcw would break) —
  then re-derive completeness with
  `grep -rl 'block-agents\|block-main-edits\|block-unsafe\|zskills-resolve-config' tests/`
  and sandbox any suite the grep finds that the list missed (verified
  2026-06-12: none of the six hook suites contains the string `HOME`).

### Design & Constraints

- This phase does NOT touch the predicate/toggle code paths (Phases 1–3)
  beyond the floor reads listed; keep the diffs separable.
- `zskills_version` MUST remain project-only (Test 15b is the lock).
- Do NOT touch: `dashboard_completed_days`/`dashboard_completed_limit` semantics,
  the 6 existing cascadable strings, `warn-config-drift.sh`,
  `forbidden-literals.txt`.
- May be 2 commits (resolver+tests+Python; then hooks+skill migration) if
  one commit gets unwieldy — each independently green.

### Acceptance Criteria

- [ ] `bash tests/test-zskills-resolve-config.sh` passes with the new
  cases; commit message quotes Test 15a old (`3/14/500`) vs new
  (`9/14/500`) expectations.
- [ ] Floor proof, quotable: with TMP_HOME user config
  `{"execution":{"main_protected":true}}` and a project config saying
  `false`, `tests/test-hooks-main-protected.sh`'s new floor case shows
  the commit-on-main gate firing.
- [ ] Congruence section passes with the count pin UNCHANGED at 5.
- [ ] Landing-reader tripwire passes at exactly 6 pinned files +
  the apply-preset exclusion assertion.
- [ ] DA9 proof: `grep -l 'TMP_HOME\|HOME=' <the 7 suites listed>`
  shows all 7; quote one pre-existing allow case from
  test-hooks-main-protected.sh now running under the sandbox.
- [ ] 3-copy lockstep: `grep -n "max_concurrent_worktrees" dashboards
  collect.py briefing.py server.py` (re-derive exact paths) shows the
  selective merge in all three; SYNC NOTEs updated.
- [ ] `bash tests/run-all.sh` green; per-suite counts reported.

### Dependencies

Phase 1 only (none structural — but run after Phase 3 per the ordering
rationale so hook edits don't interleave between phases).

---

## Phase 5 — move-to-worktree helper (stash-free dirty-main carry)

### Goal

Ship the #1165 move-to-worktree flow as a first-class helper
(`skills/create-worktree/scripts/move-to-worktree.sh`): create a worktree
branched off current LOCAL HEAD (via the existing `--no-preflight`
escape, so the carry is same-base by construction), carry dirty +
untracked files into it, and perform a sanctioned, verified restore of
main — stash-free. The create-worktree preflight is NOT modified
(Settled decision 8; Design-history row — the #225 refusal stays the
universal default).

### Work Items

- [ ] **`skills/create-worktree/scripts/move-to-worktree.sh`** (new,
  agent-invocable):
  ```
  bash skills/create-worktree/scripts/move-to-worktree.sh <branch-name|--auto> [--keep-main-dirty]
  ```
  Exit-code map, PINNED (R11): `0` success; `2` usage error; `6`
  create-worktree.sh failure (its rc reported in the message); `7`
  base-mismatch or apply failure (main untouched); `8`
  byte/index-verification mismatch (no unverified file is ever
  destroyed; the step-6 exit leaves main fully untouched, while
  step-7 TOCTOU re-check skips leave main PARTIALLY restored — the
  mismatched files preserved, the message listing the skipped files).
  Contract (each step verified, #394-style — destructive step LAST):
  1. **Inventory** main: `git -C "$MAIN_ROOT" status --porcelain -z
     --untracked-files=all` → tracked-changed list (staged + unstaged)
     and untracked list, EXCLUDING `.zskills/` and the three legacy
     root markers `.zskills-tracked`, `.landed`, `.worktreepurpose`
     (the block-main-edits allowlist names, ≈L203–208 — they stay with
     main). Pinned flags + per-status parsing (DA7/R2-9): `-z` for
     NUL-safe parsing (rename entries are TWO NUL-separated fields —
     verified: `R  new\0old\0`; both paths enter the tracked-changed
     list); `--untracked-files=all` because the default porcelain
     aggregates an untracked dir to one `?? newdir/` DIRECTORY entry
     (verified) and steps 5–7 are strictly per-FILE. All ORDINARY
     tracked status codes (`M`, `A`, `D`, `R`, two-letter combos of
     those) are carried — no per-code refusal; the two-patch carry of
     step 4 plus the HEAD-sourced restore of step 7 handle every one
     (transcript below). Exception, stated honestly: UNMERGED entries
     (`UU`/`AA`/`DD` during a paused merge) are NOT carryable —
     `git diff` on conflicted paths emits combined-diff output that
     `git apply` cannot apply, so the helper fails the step-4 apply →
     rc 7, main untouched (fail-safe refusal, not destruction); the
     message tells the user to resolve the merge first. The porcelain choice is also what structurally EXCLUDES
     gitignored files (node_modules, build artifacts) from the carry —
     state that in the helper header; it is load-bearing, not a side
     effect. Empty inventory → create the worktree anyway, note "main
     was clean", skip steps 3–6.
  2. **Create the worktree** via `create-worktree.sh <branch> --no-preflight`
     — the documented dirty-tolerant arm (≈L275–281): base = current
     LOCAL HEAD, local main untouched, no fetch/ff-merge/AHEAD refusal
     to trip. `--auto` derives the branch name from the existing
     auto-naming convention — re-derive it from create-worktree.sh, do
     not invent a new scheme. Non-zero rc → exit 6.
  3. **Base guard:** assert `git -C "$WT" rev-parse HEAD` ==
     `git -C "$MAIN_ROOT" rev-parse HEAD`. Mismatch (should be
     impossible with --no-preflight) → STOP, exit 7. This guard is why
     no 3-way apply arm exists: the carried diff is against the same
     SHA the worktree sits on.
  4. **Carry tracked changes — TWO patches, preserving the
     staged/unstaged split (R2-5 closure; verified end-to-end,
     transcript below):**
     `git -C "$MAIN_ROOT" diff --binary --cached > "$TMPDIR/staged.patch"`
     (HEAD → index) applied with
     `git -C "$WT" apply --index --whitespace=nowarn "$TMPDIR/staged.patch"`
     (updates the worktree's INDEX and working tree together), then
     `git -C "$MAIN_ROOT" diff --binary > "$TMPDIR/unstaged.patch"`
     (index → working tree) applied with
     `git -C "$WT" apply --whitespace=nowarn "$TMPDIR/unstaged.patch"`.
     This reproduces main's EXACT state in the worktree — index =
     HEAD+staged, working tree = index+unstaged — so staged-only
     content (index blob ∉ {HEAD, worktree}, e.g. the
     staged-then-reverted state where `git diff HEAD` is EMPTY despite
     a staged snapshot) is carried, not silently dropped: the single
     worktree-state-only patch of the earlier draft destroyed it
     (verified: `MM` with index X / worktree==HEAD gives `diff HEAD` =
     0 bytes, `diff --cached` = the X hunks). Each patch applied only
     if non-empty; rename patches apply via `--index` (verified).
     (`--whitespace=nothing` is NOT a valid git option — verified
     rc 129 `unrecognized whitespace option`; `nowarn` is the verified
     valid spelling). Either apply failing → STOP: leave main dirty,
     report the failing files, exit 7. Main is never modified on this
     path. Empty tracked list → skip (untracked-only move).
  5. **Carry untracked files:** copy each (preserving relative paths,
     creating parent dirs) into the worktree — per-FILE from the
     `-uall` inventory (never a directory copy).
  6. **Verify before any destruction — worktree bytes AND index
     content (R2-5):** for every carried tracked path, (a) byte-compare
     (`cmp`) the worktree copy against main's working-tree version —
     for a deleted file (` D`/`D `), "absent in BOTH worktree and main
     working tree" counts as match (a naive cmp on missing files would
     rc-fail a perfectly carryable state, R2-9); and (b) compare index
     blob ids: `git -C "$MAIN_ROOT" ls-files -s -- <file>` vs
     `git -C "$WT" ls-files -s -- <file>` — equal blob hash (both-empty
     counts as match: a rename's old path is absent from both indexes).
     Untracked carried files get check (a) only. ANY mismatch → STOP:
     leave main untouched, print the mismatch list, exit 8 with a
     message telling the user to reconcile manually.
  7. **Sanctioned restore of main** (skipped under `--keep-main-dirty`):
     per verified tracked file — re-run BOTH step-6 checks immediately
     before destruction (TOCTOU guard: a concurrent session touching
     main between steps 6 and 7 must not have its work destroyed;
     re-check mismatch → skip that file, report, continue, final rc 8),
     then `git -C "$MAIN_ROOT" restore --staged --worktree --source=HEAD -- <file>`
     — restores INDEX AND WORKTREE from HEAD and, unlike
     `git checkout HEAD -- <file>`, succeeds on EVERY inventory state:
     `checkout HEAD --` exits 1 on a staged-NEW (`A `) path absent from
     HEAD (verified: `error: pathspec … did not match`, rc 1 — under
     `set -euo pipefail` that kills the helper mid-restore with main
     half-restored), while `restore --staged --worktree --source=HEAD`
     handles `MM`/`A `/` D`/rename paths at rc 0, unstages-and-removes
     a staged-new file, and resurrects a deleted one (full transcript
     below). Then `rm` each re-verified untracked file (parent dirs
     left in place).
     **Sanctioning mechanism — helper-mediation, specced and closed:**
     PreToolUse hooks gate the agent's literal Bash command string; the
     agent types `bash …/move-to-worktree.sh <branch>`, which matches no
     deny pattern, and the `git restore --staged --worktree
     --source=HEAD` runs as a subprocess the hook never sees. No marker
     file, no hook edit, no new allow-arm — the safety argument is that
     the helper restores ONLY files it has verified (twice) to exist
     identically in the worktree in BOTH working-tree bytes and INDEX
     content, so the "discards uncommitted changes permanently" hazard
     the hook exists for is structurally absent — for the index as well
     as the working tree (R2-5). This is NOT a general
     bypass: the conformance tripwire below pins the helper's internals.
  8. Print the worktree path + a carried-files summary as the last stdout
     lines (machine-readable: `WORKTREE_PATH=<path>`).
  Constraints: `set -euo pipefail`; NO `git stash` anywhere (it is
  hard-denied for agents AND unsafe-by-construction here — a copy-based
  move never destroys before verifying); NO `git clean`; bash 3.2
  compatible like its siblings. Document the known limitation in the
  header: the worktree branches off LOCAL HEAD — if local main is ahead
  of or behind origin, the branch rebases later through the normal PR
  flow; that is the existing `--no-preflight` contract, not new risk.
- [ ] **Conformance tripwire (safety pins for the helper):** in
  `tests/test-skill-conformance.sh` — `move-to-worktree.sh` contains no
  `git stash`, no `git clean`, no `reset --hard`, and NO `checkout` at
  all (`grep -c 'checkout'` → 0 — the restore primitive is
  `git restore --staged --worktree --source=HEAD`, required present
  ≥1 by literal grep; `checkout HEAD --` was the earlier draft's form
  and dies rc 1 on staged-new paths, DA6); the inventory uses
  `--untracked-files=all` (literal grep ≥1, DA7); literal greps,
  anti-vacuous: the file exists and is non-empty. The first
  `restore --staged --worktree` occurrence appears AFTER the first
  `cmp` occurrence (assert by extracting line numbers — destruction
  follows verification).
- [ ] **New suite `tests/test-move-to-worktree.sh`** (triplet): scratch
  repo fixtures covering — dirty tracked (INCLUDING a staged hunk —
  asserting the staged/unstaged SPLIT survives in the worktree:
  `git -C "$WT" show :f.txt` carries the index content while the
  working-tree copy carries the unstaged content) + untracked move
  (end state: worktree has the dirt, main `git status --porcelain
  -uall` EMPTY, main SHA unchanged); **staged-NEW `A ` file** (the DA6
  fixture — helper succeeds rc 0, main clean, file present+staged in
  the worktree); **worktree-deleted ` D` file** (carried as a deletion,
  both-absent verify, main's copy resurrected by restore); **staged
  rename `R `** (-z two-field parse; both paths carried; main clean
  after); **staged-then-reverted** (index X, working tree == HEAD — the
  R2-5 fixture: `git diff HEAD` is empty but X must SURVIVE in the
  worktree INDEX, asserted via `git -C "$WT" show :<file>`; a helper
  that carries only worktree state destroys X silently);
  `--keep-main-dirty` (main untouched);
  verification-failure injection (corrupt the worktree copy between
  steps — simulate via a fixture hook/wrapper — main stays dirty, rc 8);
  **unmerged `UU` refusal** (paused-merge conflict fixture — the
  combined-diff fails the step-4 apply, helper exits 7, main untouched,
  message says resolve the merge first; pins the step-1 unmerged
  exception); clean-main no-op arm; `.zskills/` exclusion (a `.zskills/tracked`
  file on main is NOT carried or deleted); **gitignored file on main is
  NOT carried** (locks the porcelain-based exclusion property);
  **untracked NESTED-dir files carry per-file** (the DA7 fixture — the
  default porcelain's `?? dir/` aggregation must not reach the
  copy/cmp/rm loop); local-main-ahead-of-origin +
  dirty fixture → helper still succeeds (no preflight to trip) and the
  worktree HEAD == local main HEAD.
- [ ] **block-main-edits deny-text pointer (deferred from Phase 2):** the
  DENY message (model-visible via permissionDecisionReason — Settled
  decision 2 keeps agent-directed advice deny-arm-only) gains one line
  recommending `bash skills/create-worktree/scripts/move-to-worktree.sh`
  (lane-portable spelling per the managed-rules path conventions). Stamp
  bump + mirror; re-run the Phase 2 suite expectations (substring
  additions only).
- [ ] Skill-version bump for `create-worktree` (Invariant 1) + mirror;
  `script-ownership.md` row for the new script if create-worktree's
  scripts are Tier-1-registered (re-derive from
  `skills/update-zskills/references/script-ownership.md` — follow
  whatever discipline the existing create-worktree scripts use, including
  `tier1-shipped-hashes.txt` if applicable). Document the new script +
  rc map in `skills/create-worktree/SKILL.md` (the existing exit-code
  table ≈L86–90 is create-worktree.sh's and is UNCHANGED — add a
  separate short block for move-to-worktree.sh).

### Design & Constraints

- The helper must never delete or overwrite ANYTHING on main before the
  byte-verification of step 6 passes (and re-passes per file in step 7) —
  this ordering is the entire safety argument and is pinned by the
  tripwire.
- **Verified command transcripts (scratch repos, 2026-06-12)** — the
  drafter/refiner ran these; implementers inherit them as ground truth:
  ```
  $ git apply --whitespace=nothing /dev/null
  error: unrecognized whitespace option 'nothing'   (rc=129)
  $ git apply --whitespace=nowarn /dev/null
  error: No valid patches in input ...              (rc=128 — option ACCEPTED, empty patch rejected)
  # fixture: staged + unstaged dirt on f.txt  → status 'MM f.txt'
  $ git checkout -- f.txt        # index-sourced
  → status 'M  f.txt'            # staged hunk SURVIVES — wrong tool
  # fixture: staged-NEW file → status 'A  brandnew.txt'
  $ git checkout HEAD -- brandnew.txt
  error: pathspec 'brandnew.txt' did not match any file(s) known to git   (rc=1)
  → status 'A  brandnew.txt'     # unchanged — checkout HEAD -- is DEAD on A-files (DA6)
  # fixture: index X / worktree reverted to HEAD → status 'MM f.txt'
  $ git diff --binary HEAD -- f.txt | wc -c   → 0     # worktree-only carry drops X (R2-5)
  $ git diff --cached --binary -- f.txt | wc -c → 102 # the staged snapshot lives here
  # END-TO-END (round-2 refine): main dirty with {MM index!=HEAD!=worktree,
  # A staged-new, ' D' worktree-deleted, untracked nested dir}; worktree at HEAD.
  $ git diff --binary --cached > staged.patch          # HEAD → index
  $ git -C wt apply --index --whitespace=nowarn staged.patch    (rc=0)
  $ git diff --binary > unstaged.patch                 # index → worktree
  $ git -C wt apply --whitespace=nowarn unstaged.patch          (rc=0)
  → wt porcelain == main porcelain (A /MM/ D all reproduced; index blobs MATCH per ls-files -s)
  $ git restore --staged --worktree --source=HEAD -- f.txt brandnew.txt d.txt   # per-file loop
  → rc=0 each; main porcelain EMPTY; HEAD unchanged; wt keeps the dirt
  → wt index f.txt == X, wt worktree f.txt == Y   # staged/unstaged split PRESERVED
  # rename fixture: 'R  old.txt -> new.txt' (porcelain -z = 'R new.txt\0old.txt\0')
  $ git -C wt apply --index … staged.patch → rc=0, wt shows the rename
  $ git restore --staged --worktree --source=HEAD -- old.txt new.txt → rc=0, main clean
  # untracked dir: default porcelain → '?? newdir/' (ONE dir entry);
  # --untracked-files=all → '?? newdir/a.txt' '?? newdir/b.txt' (per-file)  (DA7)
  ```
- Do NOT touch: `create-worktree.sh` (preflight refusals 7/10 are
  KEEPERS — Design-history row), `worktree-add-safe.sh` internals,
  `ensure-worktree.sh` (migrated in Phase 4 — keep diffs apart),
  `block-unsafe-generic.sh`'s stash/checkout deny arms (no carve-outs —
  Settled decision 8).

### Acceptance Criteria

- [ ] `bash tests/test-move-to-worktree.sh` passes; quote the
  dirty-move case's end-state assertions (worktree diff non-empty —
  including the staged-hunk file with its split preserved — main
  `git status --porcelain -uall` empty, main SHA unchanged) AND the
  staged-then-reverted case's index-survival assertion
  (`git -C "$WT" show :<file>` == the staged content X).
- [ ] `grep -c 'git stash' skills/create-worktree/scripts/move-to-worktree.sh` → 0;
  `grep -c 'checkout' …` → 0;
  `grep -c 'restore --staged --worktree --source=HEAD' …` ≥ 1;
  `grep -c 'untracked-files=all' …` ≥ 1.
- [ ] Ahead+dirty proof: fixture with local main 1 commit ahead of
  origin + dirty file → helper exits 0, worktree HEAD == LOCAL main
  HEAD, main clean afterwards (quote the assertions).
- [ ] `bash tests/run-all.sh` green; per-suite counts reported.

### Dependencies

Phase 2 (block-main-edits demotion exists for the deny-text pointer);
Phase 4 ordering only (keep ensure-worktree diffs apart).

---

## Phase 6 — Config-UX: personal-config offer, decline marker, update nudge

### Goal

Land the #1160 batch in `skills/update-zskills/SKILL.md` + `init-state.sh`:
a clearly-separated second interview question offering a PERSONAL config
(empty scaffold, never seeded), decline markers that stop re-asking, and a
new-config-surface nudge that makes the update report the single
config-news channel.

### Work Items

- [ ] **Second interview question** (init arm A3, ≈L1175–1247, after the
  existing project-config question; also the update arm's conditional
  re-offer block ≈L1320–1326): clearly separated ("Separately — a
  PERSONAL config…"), explaining the v2 contract in one breath (workflow
  keys apply where projects don't override; safety keys raise-only).
  Non-interactive sessions skip both questions (existing discipline).
  - **Accept** → write `~/.claude/zskills-config.json` EXACTLY:
    ```json
    {
      "$schema": "./zskills-config.schema.json",
      "_comment": "zskills personal config (v2 contract): unset keys track shipped defaults; workflow keys (execution.landing, execution.branch_prefix, execution.max_concurrent_worktrees, plus the cascadable string keys) apply wherever the project config does not override them; safety keys (execution.main_protected, agents.min_model) are raise-only floors — they can raise a project's protection, never lower it."
    }
    ```
    plus a sibling copy of `config/zskills-config.schema.json` at
    `~/.claude/zskills-config.schema.json`. NEVER seeded values — a
    seeded literal freezes today's default and silently stops tracking
    shipped-default changes (the freeze trap; state this in the SKILL.md
    prose so future editors don't "helpfully" seed it). Atomic tmp+mv
    writes — and the fence MUST keep the VARIABLE-destination shape
    (`mv "$zs_user_cfg_tmp" "$ZS_USER_CONFIG"`, like the init seed
    fence): the Phase 3 row-50 tamper check is destination-anchored on
    the literal filename, so a literal-destination write here would
    warn/deny on zskills' own sanctioned writer. This shape is
    LOAD-BEARING — say so in a fence comment (DA4). The CONFIG is
    never-clobber-existing (#1079 discipline); the
    SCHEMA SIBLING is refresh-on-update (DA13): the update arm rewrites
    `~/.claude/zskills-config.schema.json` whenever it differs from the
    shipped schema (atomic tmp+mv; it is a generated copy, not user
    content — with `additionalProperties: false` in the hooks block, a
    stale sibling would flag future VALID keys as editor errors).
  - **Re-offer rule:** the personal question is asked only when
    `~/.claude/zskills-config.json` is absent AND no personal-decline
    record exists.
- [ ] **Decline markers** (`init-state.sh` — new consts + writers per the
  existing `ZSKILLS_INIT_DONE_REL` pattern). Two scopes, matching the
  two questions (DA14 — a decline lives at the scope of the thing
  declined):
  - PROJECT decline: `ZSKILLS_CONFIG_DECLINED_REL=".zskills/config-offer-declined"`
    — gitignored, per-project, one `project: <ISO date>` line. The
    PROJECT-config re-offer (update arm ≈L1320–1326) adds "AND no
    `project:` decline line" to its condition.
  - PERSONAL decline: `~/.claude/zskills-config.declined` (USER scope —
    declining the user-global personal-config question in one project
    suppresses it in EVERY project; a per-project marker would re-ask N
    times for one global file; writing under `~/.claude/` is already
    what the accept path does). One-line ISO date. The personal question
    keys on this file per the re-offer rule above.
  Both written via atomic tmp+mv by a new
  `zskills_write_config_declined <project|personal>` (idempotent).
  Writer/reader/fixtures all source the consts from `init-state.sh`
  (#1132 single-path rule). Tier-1 discipline: `init-state.sh` is a
  shipped Tier-1 script — refresh
  `skills/update-zskills/references/tier1-shipped-hashes.txt` (+ mirror
  twin) per the existing case-6a gate.
- [ ] **New-config-surface nudge** in the update-arm summary
  (≈L1338–1348):
  - New data file `skills/update-zskills/references/config-key-versions.tsv`:
    `<dotted key>\t<zskills version introduced>\t<shipped default>\t<where to set>` —
    backfill every current `zskills-defaults.json` leaf key with its
    introduction version (use `2026.06.0` for anything older when the
    true version is unrecoverable; precision matters only going forward)
    plus rows for the NEW surfaces this plan adds (the `hooks.*` groups —
    one row per group, not per check — and the user-tier cascade keys).
  - Update-arm logic: resolve the consumer's recorded version (config
    `zskills_version` or init-done `version:` line — the #1132
    single-path resolver ≈L273–299 already does this); emit one report
    line per key whose introduced-version is newer: `key — default
    <value> — set in <where>`. **Version comparison is NUMERIC
    dot-segment, pinned (R12)** — `YYYY.MM.N` strings compare wrong
    lexicographically (`2026.06.10 < 2026.06.2` as strings, and the TSV
    backfill's `2026.06.0` guarantees mixed-width N). The update-arm
    fence does the compare in Python (the prelude's `$PYTHON`):
    ```
    "$PYTHON" -c 'import sys; a,b=(tuple(int(x) for x in v.split("+")[0].split(".")) for v in sys.argv[1:3]); sys.exit(0 if a>b else 1)' "$INTRODUCED" "$RECORDED"
    ```
    No keys newer → no section (silence, not
    noise). The update report is the SINGLE config-news channel — no
    SessionStart nags, no per-session reminders.
  - Conformance pin: every leaf key in `zskills-defaults.json` has a TSV
    row (anti-drift; anti-vacuous: TSV ≥ 20 rows).
- [ ] Extend `tests/test-update-zskills-init.sh` (accept-path case 4
  ≈L383; update-arm conditional offer case 10 ≈L664/680): personal-accept
  writes scaffold + schema sibling byte-pinned to the JSON above
  (TMP_HOME sandbox); personal-decline writes the USER-scope marker
  (`$TMP_HOME/.claude/zskills-config.declined`) and the question is
  suppressed on the next run AND from a second scratch project sharing
  the same TMP_HOME (the DA14 property); project-decline line suppresses
  the project re-offer; existing user file → question suppressed without
  a marker; never-clobber (pre-existing user CONFIG untouched by accept
  path — should be unreachable, assert anyway); schema-sibling refresh
  (DA13): a stale sibling differing from the shipped schema is rewritten
  by the update arm while the config file is untouched.
- [ ] Skill-version bump (Invariant 1) + `mirror-skill.sh update-zskills`.

### Design & Constraints

- The scaffold is EMPTY by design — resist seeding. The only keys ever
  pre-filled in any config remain the PROJECT seed's (existing A3 fence,
  unchanged).
- The PROJECT decline marker lives in gitignored `.zskills/` (never the
  project's `.claude/` — agent writes there trigger permission prompts).
  The PERSONAL decline marker lives under `~/.claude/` — user-global
  state at user scope, the same surface the accept path already writes.
- Do NOT touch: the project-config seed fence's contents (≈L1202–1247)
  beyond the decline-marker condition; `render-managed-rules.py`;
  hooks (none change here).

### Acceptance Criteria

- [ ] `bash tests/test-update-zskills-init.sh` passes including the new
  cases; quote the scaffold byte-pin assertion.
- [ ] `bash tests/test-update-zskills-migration.sh` passes (Tier-1 hash
  sync, case 6a).
- [ ] TSV conformance pin passes; `wc -l` of the TSV reported.
- [ ] `bash tests/run-all.sh` green; per-suite counts reported.

### Dependencies

Phase 4 (the scaffold `_comment` documents cascade-v2 semantics, which
must be live); Phase 1 (the TSV's `hooks.*` rows describe a shipped
surface).

---

## Phase 7 — Docs rewrite + conformance sweep

### Goal

Rewrite every guide/template paragraph the earlier phases invalidated,
re-render the managed rules in lockstep, and run the final cross-cutting
sweep proving no stale prose or untagged emission survives.

### Work Items

- [ ] **`docs/guides/zskills-config.md`:**
  - Cascade section (≈L59–89): rewrite the tier model — project > user >
    built-ins for the cascadable strings AND the 3 workflow keys;
    raise-only floors for the 2 safety keys; `zskills_version` +
    dashboard keys project-only. The ≈L83–89 paragraph ("…documented
    behavior, not a bug") INVERTS — replace with the floor contract and
    one worked example per direction (user raises; user cannot lower).
  - New **`hooks` toggle section**: the teachable rule verbatim, the
    7 groups, the tristate semantics, group `enabled` ceilings (and the
    `config_hooks_tamper` ceiling EXEMPTION + self-protection property,
    Settled decision 13), the unset-default classes, fail-closed
    behavior, the main-root-only toggle read + tamper gate + its
    anti-casual threat model, the claim-gate two-watched-sessions
    caveat with the `"block"` override recipe (registry drafter note),
    and a worked example config. Reference the toggle-key registry's
    key names — list all 37 (this list is tripwire-locked; see the
    DA16 item below).
  - Per-field resolution table (≈L298+): rows for the 5 cascade-v2 keys
    + the `hooks` block.
- [ ] **`CLAUDE_TEMPLATE.md` ≈L387–394 reword + managed.md lockstep:**
  "When `main_protected: true`, agents cannot commit, cherry-pick, or
  push to main" stays true (those gates are hard) but gains the
  Edit/Write nuance: locked main means no COMMIT, not no write — watched
  sessions get warnings on main edits; autonomous sessions are blocked;
  per-check overrides live in `hooks.*`. The Tracking Enforcement
  paragraph (≈L392–394) gains one sentence: tracking gates warn in
  watched non-pipeline sessions and block otherwise. Mention
  move-to-worktree as the sanctioned dirty-main escape. Then
  `/update-zskills --rerender`-equivalent: regenerate
  `.claude/rules/zskills/managed.md` via `scripts/render-managed-rules.py`
  in the SAME commit (`tests/test-managed-md-up-to-date.sh` is the lock).
- [ ] **`docs/guides/installing-zskills.md`** manifest tables (≈L176–211):
  add the `~/.claude/zskills-config.json` (empty scaffold, optional,
  never committed) + schema-sibling rows to the install-footprint tables
  (#1158's commit is the precedent for table edits).
- [ ] **Hooks sections of the guides:** re-derive the list —
  `grep -rln 'block-unsafe\|block-main-edits\|permissionDecision' docs/guides/`
  — and update every description of unconditional blocking to the
  predicate model + tag convention. Quote the teachable rule once per
  guide, not per paragraph.
- [ ] **Registry-sync tripwire extension (DA16):** extend the Phase 3
  registry-sync tripwire to two more copies now that they exist —
  (a) the docs key list in `docs/guides/zskills-config.md` (extract the
  37 `hooks.<group>.<check>` mentions; assert set-equality with
  `_ZSK_ENF_KNOWN_CHECKS`), and (b) the TSV: one row per `hooks.<group>`
  (7 rows; group-level per Phase 6) plus rows for the cascade-v2 keys —
  assert presence. Anti-vacuous floors on both extractions. (The TSV's
  introduced-version COLUMN is unverifiable by construction — record
  that as accepted in the tripwire comment rather than pretending a
  check exists.)
- [ ] **Final sweep (quotable commands):**
  - Stale-prose sweep:
    `git grep -n "never cascades from the user tier\|documented behavior, not a bug" -- docs/ CLAUDE_TEMPLATE.md .claude/rules/` → 0 hits.
  - Tag tripwire + registry-sync tripwire green (Phase 3 suites + the
    DA16 extension above).
  - Bypass-parity census: report the 23 parity case names suite-by-suite.
  - `bash tests/run-all.sh` full green.
- [ ] **Optional attended check (non-gating, and no longer load-bearing):**
  one live watched session (`ZSKILLS_LIVE_ATTENDED=1` discipline) runs
  `git add .` in a main_protected scratch consumer and confirms the
  WARNING text is visible interactively. The warn channel's
  user-visibility was already PROVEN by the GATING Phase 1 probe
  (Settled decision 2; if the W-B(b) branch was taken, an attended
  confirmation already happened in Phase 1) — this check only confirms
  the same channel in a live interactive session vs. the probe's
  headless stream. If not run,
  record ATTENDED-PENDING in the tracker notes AND file a follow-up
  issue (R17) so the confirmation isn't silently dropped.

### Design & Constraints

- Docs phase touches NO hook/script behavior. If the sweep finds a code
  defect, that is a Failure-Protocol STOP for triage, not a quiet Phase 7
  fix.
- `managed.md` changes ride the same commit as `CLAUDE_TEMPLATE.md`
  (render lockstep) — never hand-edit `managed.md`.
- Do NOT touch: `CHANGELOG.md`, `docs/plans/` history, `README.md` beyond
  a one-line hooks-behavior pointer if it describes unconditional
  blocking (re-derive by grep).

### Acceptance Criteria

- [ ] Stale-prose sweep returns 0 hits (quote the command + output).
- [ ] `bash tests/test-managed-md-up-to-date.sh` passes.
- [ ] All conformance tripwires pass (tag format ×9 hooks with pinned
  counts 19/17/2/2/2/1/1/3/2 — generic/project/main-edits/agents/
  fix-issue/run-plan/stale/bad-cron/land-pr; registry-sync 37 keys +
  the DA16 docs/TSV extension; landing-reader ×6 files +
  apply-preset exclusion; move-to-worktree safety pins; TSV pin).
- [ ] `bash tests/run-all.sh` green — per-suite counts reported; final
  bypass-parity census = 23 named cases.

### Dependencies

Phases 1–6 (documents all of them).

---

## Plan Quality

Drafted via /draft-plan with 3 rounds of adversarial review: consolidated
research (codebase surfaces + patterns/prior-art, file:line-anchored) →
this draft → adversarial review rounds (senior reviewer + devil's
advocate per round — combined into one seat for the round-3 convergence
check — findings deduped via an overlap map) → refiner pass per round.

Verification notes from drafting: every load-bearing anchor in this plan
was re-verified against the worktree at draft time (block-main-edits deny
emission — ONE site, ≈L209–237, where prior research counted 2; per-hook
deny counts 18/17/1/2/2/1/1/3/2 re-derived by grep; resolver function
names `_zsk_extract_cascade_keys`/`_zsk_extract_project_only_keys`
≈L172/L222; Test 15a/b/c labels ≈L713–729; create-worktree preflight
≈L287–318 with exits 5/6/7/10; `model_ordinal()` ≈L91–105; congruence
count pin ≈L2559; schema at `config/zskills-config.schema.json`). Where
research and disk disagreed, disk won — the registry table reflects disk.

Round-1 refine re-verification (2026-06-12): `git apply
--whitespace=nothing` invalid (rc 129) / `nowarn` valid /
`checkout -- ` leaves staged dirt / `checkout HEAD --` cleans — scratch
transcript in Phase 5; landing extraction fences = exactly 5 SKILL.md
files + ensure-worktree.sh (draft's 8-surface list had 3 prose-only
files); apply-preset probe is a project-file-literal read by design;
`ZSKILLS_MAX_CONCURRENT_WORKTREES` name + consumers verified; Test 15a
fixture literals are 9/99/9999 with key `dashboard_completed_limit`;
zero `HOME` in the six hook suites + test-fix-issues-worktree-cap.sh;
20+ stale `.zskills/tracking/` subdirs (May 31–Jun 1) with no
`.zskills/tracked` in the live dogfood repo; block-main-edits gates
main-config Edit/Write only under `main_protected:true` and never Bash;
`--no-preflight` base = current local HEAD (create-worktree.sh
≈L275–281); inflight TTL 7200s (check-inflight-batch.sh ≈L125).

Round-2 refine re-verification (2026-06-12, scratch transcripts +
disk reads): `.zskills/tracked` writers are ALL worktree-pathed
(create-worktree.sh L407 `$WT_PATH/.zskills/tracked`; execute-phase.md
L249–252/L1800; do/modes/pr.md L122–136) and this plan's own draft-plan
worktree carries the marker while the main root does not — the
predicate gained the effective-LOCAL-root arm ($3) reusing the
`resolve_effective_worktree_root` helpers the hooks already inline;
block-main-edits' MAIN_ROOT chain is REPO_ROOT→CLAUDE_PROJECT_DIR→
show-toplevel→pwd (git-common-dir appears only inside the worktree-self
check at L140–152, which exits 0 for worktree sessions BEFORE
everything — the tamper arm moved above it); the path-resolution block
sits at L171–192, AFTER the config gate (hoist specced);
`is_main_protected()` reads the LOCAL toplevel (L558–560, read-root
pinned as unchanged); inject-bash-timeout emits
`permissionDecision:"allow"` envelopes while session-rules-context/
session-start-greeting emit bare decision-less `{"systemMessage":…}`
(SessionStart) — W-A re-specced decision-less, PreToolUse legality is
the probe's question; the init seed fence (SKILL.md L1210–1232) writes
via Python-heredoc + `mv "$zs_cfg_tmp" "$ZS_CONFIG"` (variable
destination — the destination-anchored row-50 trigger does not fire on
it); `git checkout HEAD -- <staged-new>` → rc 1 pathspec error
(reproduced); `git status --porcelain` aggregates `?? newdir/`
(reproduced; `-uall` per-file); staged-then-reverted: `git diff HEAD` =
0 bytes vs `diff --cached` = the snapshot (reproduced); the two-patch
carry (`apply --index` staged + plain unstaged) + per-file
`git restore --staged --worktree --source=HEAD` verified end-to-end on
{MM-divergent, A, D, R, untracked-dir} — main porcelain empty, HEAD
unchanged, worktree split preserved, index blobs matching; porcelain
`-z` rename = two NUL fields (reproduced); inflight `check` ages by
`started_at` JSON field where the predicate's `find -mmin` ages by
mtime (noted in spec); fix-issues direct.md L166–175 removes the
worktree `tracked` only when clean (stickiness accepted in Settled
decision 1).

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1 | 18 (R1–R18: 0 CRIT / 9 MAJ / 9 MIN) | 16 (DA1–DA16: 5 CRIT / 6 MAJ / 5 MIN) | 34/34 addressed (32 fixed, 1 moot-by-redesign, 1 fixed-via-sibling) |
| 2 | 9 (R2-1…R2-9: 1 CRIT / 5 MAJ / 3 MIN) | 11 (DA1–DA11: 3 CRIT / 5 MAJ / 3 MIN) | 20/20 addressed (3 cross-seat overlaps: R2-1≡DA2 warn-allow bypass; R2-4≡DA3 root anchor; R2-8≡DA10 count drift) — every empirical claim reproduced before fixing |
| 3 | combined seat (reviewer + devil's advocate): 0 CRIT / 0 MAJ / 5 MINOR / 2 NIT (F1–F7) | — (combined into the reviewer seat) | 7/7 fixed in the convergence-fold refiner pass |

Converged at round 3.

### Remaining concerns

Honest residuals carried to execution — each is documented in-body with
its rationale and mitigation; none is a plan-text contradiction:

1. **PreToolUse systemMessage legality is unknown until the Phase 1
   probe** — the warn design rides on it; the probe's
   Failure-Protocol STOP branch (neither form demonstrably visible) is
   real, not theoretical.
2. **Bash-mediated variable-destination config writes remain ungated** —
   the row-50 tamper gate is anti-casual and transcript-visible only; a
   write that never names the config file as a literal destination
   passes (accepted per Settled decision 13's threat model).
3. **Watched-session warn-through of the tamper gate persists into later
   autonomous sessions** — a config edit warned-through while watched
   keeps its effect when no one is watching (accepted asymmetry;
   recovery-line mitigation).
4. **The sub-agent `permission_mode` VALUE is unpinned** — Probe B
   verified field PRESENCE only; the LOCAL-root tracked arm is the
   operative protection for worktree pipeline agents.
5. **Claim-gate demotion leaves a two-watched-sessions double-claim
   window** — two concurrently watched sessions can both warn-through
   the same claim (documented `"block"` recipe for projects that care).
6. **The probe pin has no CI canary** — drift on CLI upgrade is covered
   only by the manual recheck script (`tests/manual/warn-channel-probe.sh`)
   plus the dated assumption note in the lib header.
