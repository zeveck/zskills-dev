---
title: Plugin-Lane Install Redesign — Zero Files Required, One File When Wanted
created: 2026-06-10
status: active
---

# Plan: Plugin-Lane Install Redesign — Zero Files Required, One File When Wanted

## Overview

Redesign the zskills plugin-lane install so that a plugin consumer needs
**zero zskills-written files in their repo by default, and exactly one
(`.claude/zskills-config.json`) when they want configuration**. Concretely:

- **Delete** the SessionStart materialiser (`hooks/session-start-materialise.sh`,
  488 lines) and the entire lane-switch complex (`scripts/switch-install-path.sh`,
  `scripts/migrate-strip-settings.py`, the `.claude/zskills-install-lane` lock,
  the `.zskills/switch-in-progress` marker, `docs/guides/switching-install-lanes.md`,
  and the D20 `zskills-materialised:` sentinel convention).
- **Deliver plugin-natively** what the materialiser used to write: verifier/implementer
  agents from the plugin's own `agents/` tree (or, on the empirically-forced fallback
  branch, as a slim init-time write), Layer-0 bash-timeout injection via a
  `hooks/hooks.json` PreToolUse entry (or the frontmatter fallback), and the
  Layer-3 validator relocated under a skill `scripts/` dir so both lanes resolve
  it uniformly.
- **De-parameterize** the managed rules (`CLAUDE_TEMPLATE.md`) so they are
  install-level, not project-level, and deliver them through the branch Phase 1
  selects (SessionStart `additionalContext` / user-level rules file / init-time render).
- **Add a config cascade**: project `.claude/zskills-config.json` > user
  `~/.claude/zskills-config.json` > built-in defaults, per-key shallow merge —
  so a zero-config consumer gets working defaults with no file at all.
- **Make setup explicit**: `/zs:update-zskills` (bare call, plugin lane) becomes the
  one-time init — gitignore-first, `.zskills/init-done` written LAST (lock-LAST).
  The `UserPromptExpansion` gate retargets from the materialised-sentinel check to
  `init-done`, blocking only state-writing skills with a friendly setup pointer.
- **Consolidate the root turds**: `.landed`, `.worktreepurpose`, `.zskills-tracked`
  move into `.zskills/` (writers flag-day, readers dual-read).

**Falsifiable end state** (primary branches — see `## Findings — Phase 1` for selected
branches; fallback-branch deltas are listed below):

1. **Zero-write default.** A fresh, mirror-less plugin consumer (real
   `claude plugin marketplace add <path>` install of the prod-stripped tree, NOT
   `--plugin-dir`) can run a full session — including dispatching the verifier and
   implementer subagents (on branch **1A**; on 1B the agents arrive at init, so
   the dispatch clause applies only post-init — see the 1B delta below) — and
   zskills writes **nothing** into the project:
   `git status --porcelain` unchanged, no `.claude/` or `.zskills/` paths created,
   until the user runs `/zs:update-zskills`.
2. **Exact post-init footprint.** After `/zs:update-zskills` (init), the
   project-side zskills footprint is exactly: one `.zskills/` umbrella entry in
   `.gitignore`, the optional `.claude/zskills-config.json` (+ its schema sibling,
   only if the config was created), and gitignored `.zskills/` runtime state
   (`init-done`, `setup-confirmed`, tracking, etc.). Nothing else.
3. **Machinery gone from the live tree:**
   ```bash
   git ls-files -z | xargs -0 grep -lirE 'session-start-materialise|switch-install-path|migrate-strip-settings|zskills-install-lane|switch-in-progress|zskills-materialised|config-seeded-notice' -- 2>/dev/null \
     | grep -vE '^(docs/plans/|docs/reports/|docs/issues/|CHANGELOG\.md$|\.pre-paths-migration|(\.claude/)?skills/update-zskills/scripts/init-state\.sh$)'
   ```
   returns **zero files**. The exclusions are HISTORICAL surfaces (this plan file
   itself lives in `docs/plans/`) and must not be rewritten — plus ONE deliberate
   live survivor: `skills/update-zskills/scripts/init-state.sh` (and its mirror
   twin) retains the `zskills-materialised:` sentinel prefix and the
   `config-seeded-notice` path as FROZEN legacy-residue detection constants — the
   Phase 6a A1.5 cleanup must recognize residue written by pre-redesign releases
   forever (upgraded consumers arrive with sentinelled artifacts indefinitely).
   No other live file may carry these strings.
4. **Legacy lane unchanged.** A `/update-zskills`-lane consumer behaves identically
   before and after every phase: mirror install, `.claude/hooks/` copies,
   `.claude/agents/` with frontmatter hooks, `managed.md` render — all still work.
   (Sole planned delta: the legacy update flow gains the idempotent `.zskills/`
   gitignore umbrella append — Phase 6a A2; a deliberate additive change, not a
   defect.)
5. `bash tests/run-all.sh` passes clean.

**Fallback-branch deltas to end-state items 1–2** (each is selected ONLY by a
recorded Phase 1 finding, never by implementer preference):

- Branch **1B / T-C** (plugin `agents/` dispatch or hooks.json timeout delivery
  empirically dead): init additionally writes `.claude/agents/verifier.md`,
  `.claude/agents/implementer.md`, and (T-C only) `.claude/hooks/inject-bash-timeout.sh`
  — three more project-side files, written at init, never at session start.
  End-state item 1 (zero writes before init) still holds, but its
  "including dispatching the verifier and implementer" clause holds only
  POST-init on 1B (pre-init there are no project agents and no plugin-native
  dispatch — by design; the gate blocks the dispatching skills pre-init anyway).
- Branch **R-c** (SessionStart `additionalContext` empirically dead — R-c is
  the next branch in selection order; R-a is demoted below it per the Claim-4
  scope-of-load hazard): init additionally renders
  `.claude/rules/zskills/managed.md` project-side. Items 1 and 3 still hold.

**Precondition / ordering vs BLOCK_DIAGRAM_REMOVAL_PLAN.** That plan is a HARD
PRECONDITION and must execute FIRST — but at this plan's drafting time it was
only DRAFTED, not landed (the worktree shows `block-diagram/` present and
`scripts/switch-install-path.sh`'s `is_shipped_skill` block-diagram arm ≈L108
intact). Phase 1 carries an execution-time pre-flight that verifies the BD
plan has landed on main and STOPs if it has not. Prospectively, the BD plan's
Phase 3 edits `scripts/switch-install-path.sh` (≈L109 `is_shipped_skill`)
and `hooks/block-unmaterialised-skill.sh` (comment condense) — both files this plan
later deletes or rewrites. Deleting a file the BD plan already edited is fine; if
execution order ever inverts despite the pre-flight, the BD plan's edits to a
file this plan has already
deleted simply no-op (its implementer must skip-with-note, not error). This plan's
work items reference EXPECTED post-BD-removal line positions where they differ;
all line refs are ≈L — **verify by content**.

## Settled decisions (do not relitigate)

From the consolidated research (§I) — these are closed; reviewers and implementers
must not reopen them:

1. The SessionStart materialiser is **deleted**, not slimmed. Setup is **explicit**
   (`/zs:update-zskills` init).
2. Init is **gitignore-first** and **lock-LAST** (`.zskills/init-done` written only
   after every prior init step succeeds — the #394 migration-script contract).
3. **Zero-files default**; `.claude/zskills-config.json` stays at its current
   project location when wanted. `~/.claude/zskills-config.json` is the user tier.
4. The config seed default stays `landing: direct` (#1120 — settled; do not flip
   to `pr`).
5. The lane-switch machinery is **deleted** (no replacement "switch" flow; a
   consumer who wants the other lane uninstalls one and installs the other —
   documented in Phase 9).
6. The **D16(a) shim stays** (`hooks/_lib/plugin-hook-skip-if-mirrored.sh`) — this
   dogfood repo is permanently dual-loaded and the shim is the only double-fire
   defense. Correction to any earlier framing that said otherwise.
7. Turds consolidate into `.zskills/` with a writers-flag-day + readers-dual-read
   window (retirement of dual-read is a post-plan follow-up, not in-plan).
8. The gate keys on the **`.zskills/init-done` marker** (lock-LAST), not on a
   gitignore-predicate; gate shape is an **allow-list** (read-only skills allowed,
   everything else blocked pre-init — fails safe for new skills).
9. `verify-response-validate.sh` relocates under a **skill scripts dir** (research
   option ii). This plan fixes the owner as
   `skills/update-zskills/scripts/verify-response-validate.sh` (the cross-cutting
   infra bucket, same as `clear-tracking.sh`, with the #865 dual-lane conformance-pin
   precedent at conformance ≈L1954–1957).
10. Legacy `/update-zskills` lane keeps working **unchanged** at every phase
    boundary — its frontmatter-hook agents, `.claude/hooks/` copies, and mirror
    install are not redesigned by this plan. (One carved-out planned addition:
    the Phase 6a A2 idempotent `.zskills/` gitignore umbrella append also lands
    in the legacy update flow — see end-state item 4.)

## Design-history dispositions

Every prior design decision this plan touches, with its original rationale shown
obsolete or re-satisfied (research §D). Implementers cite these instead of
re-deriving:

| Decision | Disposition |
|---|---|
| D11 (no plugin-native agents) | **REVERSED** — each leg re-satisfied by Phase 1 claims 1/2/6 (dispatch works or init-fallback) and 3/4 (rules delivery). The "no `agents` field in plugin.json" assertion SURVIVES (duplicate-load trap, #1062 hooks-field precedent); only the W1.1 "no agents dir" sentence reverses. |
| D16 (conditional-skip shim) | **SURVIVES** — dogfood dual-load is permanent. |
| D20 (materialised-sentinel convention) | **RETIRES** with the materialiser; the #1079 lessons (atomic writes, 0-byte healable, failure must not poison retry) **port to the init writer**. |
| D24 (one renderer, one substitution map) | **SURVIVES** — `scripts/render-managed-rules.py` keeps both lanes; the map shrinks (Phase 4); output location may move per rules branch. |
| D25 / W6.2 (switch-in-progress skip) | **RETIRED outright** — the marker existed only because the materialiser re-armed; with no materialiser there is nothing to skip. The cleanest obsolete-rationale case. |
| D27 (dual-install probe) | **RETIRES as materialiser-caller**; the refuse-on-mirrored-consumer hazard survives inside init's refuse arm (Phase 6a). |
| W6.1 (hard-refuse explicit `install` on plugin lane) | **SURVIVES in spirit** minus the switch-in-progress carve-out (carve-out dies in Phase 7 with the switch machinery). |
| W6.3 (every-session dual-install nag) | **RETIRES**; the "never once-per-session-gate a nag" lesson carries into the greeting design. |
| D3, D4, D6 (~151 resolver sites), D12, D1/D10 | **SURVIVE untouched.** D6 in particular: no resolver-site rework anywhere in this plan. |

Incident lessons encoded into work items: #1079 (atomic init writes), #1088/#1089
(SessionStart channel semantics: `additionalContext` = model channel,
`systemMessage` = user channel), #1120 (direct default settled), #1121→#1128 (gate
chokepoint must be deterministic per-invocation; cure exempted), #1132 (writer/gate/
fixture share ONE path definition; BOTH gate branches live-validated).

## Why these phases, in this order

The redesign's structural property: **build the replacement while the old machinery
still runs, switch the entry point, then delete** — never leave a boundary where a
lane has no working Layer-0/Layer-3/rules/agents delivery.

- **Phase 1** resolves the six platform unknowns empirically and records branch
  selections in this file. Every later branch-dependent item names its claim and
  specs both branches fully — Phase 1 selects, it never designs.
- **Phases 2–3** make agent + hook + Layer-3 delivery plugin-native. These are
  ADDITIVE (the materialiser still exists and still writes for plugin consumers),
  so each boundary is safe on both lanes.
- **Phase 4** de-parameterizes the rules and stands up the selected delivery
  channel — additive for the same reason.
- **Phase 5** adds the config cascade so a zero-config consumer has working
  defaults BEFORE init makes the config optional-by-design.
- **Phase 6a** builds the explicit init inside `/update-zskills` Step 0.7's
  bare-call arm (including the A1.5 residue cleanup). **Phase 6b** retargets the
  gate + verify-install onto `init-done`. (One design surface, split into two
  phases for single-dispatch sizing — round 3.) At the 6b boundary BOTH the old
  (materialiser) and new (init) paths work; the gate already keys on the new
  marker.
- **Phase 7** deletes — materialiser, switch complex, D27/D20/W6.2 — only now that
  every consumer-visible function has a live replacement. All
  hard-fail-on-delete lockstep pairs (conformance presence list, seed-dict
  extraction, hook-helper-drift consumer list, suite/run-all/registry triplets,
  hooks.json SessionStart entry vs integrity Gap 1) ride in the deletion commits.
- **Phase 8** consolidates the root turds — it needs init to exist (the one-shot
  main-root migrate is an init step) and is kept apart from Phase 7 so the
  deletion commits stay reviewable.
- **Phase 9** rewrites the docs that describe all of the above, fixes the
  RELEASING.md dangling ref, runs the mirror-less DEV-QUAL, and sweeps.

## Execution context

`main_protected: true` — execute via `/run-plan docs/plans/INSTALL_REDESIGN_PLAN.md`
in worktree mode. Implementation dispatches to `subagent_type: "implementer"`;
verification to the verifier subagent. Each phase is one commit unless a phase
says otherwise (Phases 6a, 7, and 8 may be 2–3 commits; Phase 6b is one commit —
every lockstep pair named
below must be INSIDE one commit). All line numbers are ≈L — **verify by content,
not blind line number**; the tree WILL have shifted by execution time (the
BLOCK_DIAGRAM_REMOVAL_PLAN — a hard precondition, verified landed by Phase 1's
pre-flight — moves lines in
`test-update-zskills-lane-aware.sh`, `skills/update-zskills/SKILL.md`, and
deletes lines in `scripts/switch-install-path.sh`).

Phase 1 requires live `claude` sessions against synthetic plugins — it is
attended work (`ZSKILLS_LIVE_ATTENDED=1` discipline); headless `claude -p` probes
are acceptable where the recipe says so. No other phase requires attended runs
except Phase 6b's live gate validation (both branches) and Phase 9's DEV-QUALs.

**Attended-step protocol (applies to Phase 1, Phase 6b's live gate validation,
and Phase 9 §C — the #1132 lesson: live validation must be REAL, both
branches).** Under `/run-plan` implementer dispatch, an implementer CANNOT run
attended `claude` sessions. The protocol: the implementer completes every
headless-able work item, then STOPs and returns an explicit **ATTENDED-PENDING
list** naming each observable that still requires a live attended run (probe,
transcript, marker). It must NEVER simulate, fabricate, or fixture-substitute
attended evidence — the realistic failure mode is an implementer "validating"
a live gate branch against a fixture and reporting it as live (#1132's exact
class). The phase's Progress Tracker entry stays in-progress (⏳, with an
`attended-pending` note) until a human or the orchestrator runs the attended
steps and records the transcripts/markers in the phase report. The verifier
treats simulated-attended-evidence — any claimed live observable not backed by
a real attended transcript/marker — as a verification FAIL.

## Critical invariants every phase must honor

1. **Skill-versioning quadruple gate** (warn-config-drift Edit-warn, `/commit` 2.5,
   `block-stale-skill-version.sh` PreToolUse deny, conformance CI). ANY edit to a
   skill body or any regular file under a skill dir requires a `metadata.version`
   bump in source AND mirror, same commit:
   ```bash
   today=$(TZ=America/New_York date +%Y.%m.%d)
   hash=$(bash scripts/skill-content-hash.sh skills/<S>)
   bash scripts/frontmatter-set.sh skills/<S>/SKILL.md metadata.version "$today+$hash"
   bash scripts/mirror-skill.sh <S>
   ```
   Compute the hash AFTER all content edits to that skill, per commit (the
   PreToolUse hook checks each commit's STAGED set). If a `git commit` is DENIED,
   the deny message carries the exact bump command — run it, re-stage, re-commit;
   do NOT treat the deny as a test failure.
2. **Source↔mirror↔agents parity.** Every file under `skills/<S>/` has a
   byte-identical twin under `.claude/skills/<S>/`; every surviving `hooks/*.sh` a
   twin under `.claude/hooks/` (subject to the parity tests' exclusion lists —
   update those lists in the SAME commit as any hook add/move/delete). From
   Phase 2 (branch 1A): root `agents/{verifier,implementer}.md` must stay
   body-identical to `.claude/agents/{verifier,implementer}.md` modulo the
   frontmatter `hooks:` block — enforced by the new `tests/test-agents-parity.sh`.
   Edited hooks get their line-2 `# zskills-hook-version:` stamp bumped, same
   commit.
3. **Tests are never weakened — and this plan does not weaken any.** Every test
   deletion here is *subject-removal* (the asserted subject — materialiser, switch
   script, sentinel, 5th TSV field of a marker path — ceases to exist), and every
   re-specified assertion (resolver Tests 3/4 going from "empty config → empty
   vars" to "empty config → built-in defaults") is an *intended behavior change of
   the subject*, stated as such in the commit message with the old and new
   expected values. A floor lowered or an assertion dropped without a named
   subject-removal/re-spec rationale is a weakening and is forbidden.
4. **Capture test output out-of-tree, never pipe:**
   ```bash
   TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
   mkdir -p "$TEST_OUT"
   bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
   ```
   Then READ the file. Report the command and per-suite results with explicit
   pass COUNTS (match counts, not just "0 failed").
5. **Suite green at every phase boundary** — `bash tests/run-all.sh` passes before
   the phase's last commit is considered done.
6. **#1132 single-path-definition rule.** Any path that a writer writes, a gate
   reads, and a fixture fakes (here: `.zskills/init-done`, `.zskills/setup-confirmed`)
   is defined in exactly ONE place —
   `skills/update-zskills/scripts/init-state.sh` — and the init writer, the
   `block-unmaterialised-skill.sh` gate, the greeting hook, verify-install, the
   `zskills-resolve-config.sh` ZSKILLS_VERSION fallback (Phase 5 carries a
   documented temporary literal; Phase 6a A0 retargets it), and every test
   fixture all source it. Fixtures derive paths from the WRITER's
   definition, never from a re-typed literal. Both gate branches (block AND allow)
   get live validation, not just fixture validation.
7. **Layer-0 STOP rule.** No branch, fallback, or intermediate phase boundary may
   leave verifier/implementer Bash calls at the 120s default on EITHER lane. If an
   implementer discovers a state where that would happen, it is a Failure-Protocol
   STOP, not a judgment call.
8. **Mirror-less validation discipline.** Never accept "works in this repo" as
   plugin-lane evidence — this repo carries the dogfood mirror and dual lanes
   (#799/#831 dogfood-mask). Plugin-lane claims are validated against a
   prod-stripped tree installed via `claude plugin marketplace add <path>` (and
   `--plugin-dir` only as the fast iteration loop, never the sole proof).
9. **Lock-LAST for init.** `.zskills/init-done` (and `setup-confirmed`) are
   written ONLY after all earlier init steps succeed; any earlier failure leaves
   the consumer re-runnable (#394 contract; #1079 atomic-write + 0-byte-healable
   lessons apply to every init write).
10. **Legacy lane unchanged at every boundary.** `.claude/agents/` frontmatter
    hooks stay; legacy hook copies stay; `/update-zskills` mirror install stays.
    Run the legacy-lane suites (`test-update-zskills-*`, mirror-parity) at every
    boundary and treat any behavior change there as a defect of the phase —
    with ONE carved-out planned addition: Phase 6a A2's idempotent `.zskills/`
    gitignore umbrella append lands in the legacy update flow by design (end-state
    item 4); it is not a defect.
11. **Historical surfaces are off-limits in every phase:** `CHANGELOG.md`,
    `docs/plans/`, `docs/reports/`, `docs/issues/`, `.pre-paths-migration`.
    `docs/plans/PLUGIN_DISTRIBUTION.md` gets ONLY the Phase 9 superseded-note
    (precedent: its existing line-12 note), never a body rewrite.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Empirical verification → recorded branch selections | ✅ | d592c80a | 1A / T-A(scoped-filter) / R-b; 2 ATTENDED-PENDING (non-gating); evidence preserved |
| 2 — Plugin-native agents + hooks.json Layer-0 timeout | ✅ | 18a004e2 | 1A+T-A landed; STOP rule live-proven shape (b); 7651/7651 (+37 accounted) |
| 3 — Layer-3 relocation (verify-response-validate.sh) | ✅ | d51f79d7 | R100 move; 14 sites dual-lane; materialiser 5→4; post-commit 119/119+13/13 |
| 4 — Rules de-parameterization + delivery channel | ✅ | 3f54ddc8 | 10 tokens out; R-b hook live; 7662/7662; 1 ATTENDED-PENDING → Phase 9 DEV-QUAL |
| 5 — Config cascade (project > user > built-ins) | ✅ | 6afc555b | 2-pass bash + Python helper ×3; carve-outs documented; congruence pinned; post-commit 119/119+13/13 |
| 6a — Explicit init (Step 0.7 rework, residue cleanup, lock-LAST) | ✅ | 5e80c4eb | init-state.sh + 49-case oracle; W6.1 byte-untouched; 7752/7752; ATTENDED-PENDING ×1 → Phase 9 |
| 6b — Gate retarget + verify-install rework | ⬚ | | |
| 7 — Deletions: materialiser, switch complex, sentinels | ⬚ | | |
| 8 — Root-turd consolidation into .zskills/ | ⬚ | | |
| 9 — Docs, release/dogfood, DEV-QUAL, final sweep | ⬚ | | |

---

## Phase 1 — Empirical verification → recorded branch selections

### Goal

Resolve the six platform-behavior claims that every branch-dependent work item in
Phases 2–7 hangs on, using isolated synthetic plugins and marker-file observables
— and record the results + selected branches in the **## Findings — Phase 1**
section of THIS file. No production code changes. Phase 1's output is a decision
table, not a diff.

### Harness discipline (applies to every claim)

Lift the patterns from `tests/test-plugin-live-load.sh` — read it first:

- **Isolation:** run probes under `env -i` with a sandbox `CLAUDE_CONFIG_DIR`
  in `$TMP`; copy ONLY the credential seed the live-load test copies (≈L of its
  credential-seed block — verify by content). Never point a probe at this repo's
  real config dir.
- **Synthetic plugins in `$TMP`:** build a minimal plugin tree
  (`.claude-plugin/plugin.json` + whatever the claim needs) under
  `mktemp -d`; never stage probe artifacts inside the repo.
- **Marker-file observables, never prose-grep:** every probe's pass signal is a
  file the probed mechanism writes (or a command that demonstrably completed),
  not a substring of model output. Where the observable IS model knowledge
  (claims 3/4: "does the model see the token?"), use a unique random token and
  require it verbatim in the response to a single direct question.
- **BOTH install shapes:** every claim that can differ by load path runs under
  (a) `claude --plugin-dir <synthetic>` AND (b) a local test marketplace
  (`claude plugin marketplace add <path>` pointing a `zsprobe` plugin at the
  synthetic tree) + `claude plugin install`. The #799/#831 dogfood-mask shipped
  precisely because `--plugin-dir` hides marketplace-resolution differences.
  Record both results per claim; a claim "passes" only if it passes in shape (b).
- **Attended gating:** interactive probes run attended; prefer headless
  `claude -p "<one instruction>"` where the recipe allows. Cap each probe at 3
  attempts; an inconclusive probe after 3 attempts is recorded as FAIL (fallback
  branch selected) — fallbacks are all strict subsets of current behavior, so
  "couldn't prove it" safely selects the conservative branch.

### Work Items

- [ ] **Claim 1 — plugin `agents/` bare-name dispatch.** Synthetic plugin with
  `agents/zsprobe-agent.md` (frontmatter `name: zsprobe-agent`,
  `tools: Bash`; body: "immediately run
  `touch <marker-path-from-prompt>` and stop"). In a scratch project, drive a
  session that dispatches `subagent_type: "zsprobe-agent"` (bare) and, in a
  second session, `subagent_type: "zsprobe:zsprobe-agent"`-style scoped spelling.
  Observable: the marker file exists. Also probe the **duplicate-load trap**: add
  an explicit `"agents"` field to the manifest alongside the auto-loaded dir and
  record whether the CLI errors (the #1062 hooks-field precedent predicts it
  might). **Sub-probe (project-twin precedence, one Findings line):** with the
  plugin agent loaded, ALSO place a same-named `.claude/agents/zsprobe-agent.md`
  in the scratch project (distinct marker path) and record which one a bare-name
  dispatch reaches — shadow, duplicate, or error (this is exactly the state an
  upgraded materialiser-era consumer sits in until the Phase 6a A1.5 cleanup
  runs). Record: bare works? scoped works? manifest-field behavior? twin
  precedence?
  → Selects **1A** (bare-name dispatch works in shape (b): ship root `agents/`,
  dispatch sites unchanged) or **1B** (init writes `.claude/agents/` copies;
  dispatch sites unchanged either way).
- [ ] **Claim 2 — hooks.json PreToolUse fires on SUBAGENT tool calls + identity
  field.** Synthetic plugin with `hooks/hooks.json` registering a PreToolUse/Bash
  capture hook that appends its full stdin JSON as one JSONL line to a fixed
  `$TMP` path. Scratch project carries a `.claude/agents/probe.md` agent. Session:
  orchestrator runs one Bash command, then dispatches the probe agent which runs
  one Bash command. Diff the JSONL records: did the subagent's call produce a
  record, and does any field identify the calling agent (e.g. `agent_type`/agent
  name)? The Findings row MUST also record what the ORCHESTRATOR main-thread
  call carries (field present with a distinct value, or absent) — T-A's
  absent⇒extend rule (Phase 2) means identity-less orchestrator calls also get
  the extension, i.e. T-A degenerates to T-B for orchestrator calls; that
  widening is ACCEPTED (same rationale as T-B), but it must be a recorded fact,
  not a surprise. → Feeds the **T-branch** selection (with claim 6).
- [ ] **Claim 3 — SessionStart `additionalContext` injection.** Synthetic plugin
  whose hooks.json SessionStart hook emits the documented JSON envelope with
  `additionalContext` carrying `ZSPROBE_<random>` plus ~15KB of filler. Probe:
  ask the model (headless ok) to repeat the token. Then `/clear` (attended) and
  ask again — does it re-inject? Record: token visible? at 15KB? post-/clear?
  (#1088/#1089: `additionalContext` is the MODEL channel — exactly what rules
  want.) **Sub-probe (combined envelope):** emit ONE envelope carrying BOTH
  `additionalContext` AND `systemMessage` — record whether both channels
  deliver (Phase 7's R-b greeting-fold hangs on this; if combined delivery
  fails, Phase 7 keeps two SessionStart entries instead of folding).
  **Sub-probe (enablement scope):** after a USER-scope install of the synthetic
  plugin (shape (b)), open a session in a SECOND unrelated scratch project and
  record whether the SessionStart hook fires there. Nothing in this repo has
  ever probed plugin enablement-scope semantics; R-b's hook and Phase 7's
  greeting fire wherever the plugin is enabled, so this row is the factual
  basis for the Phase 4 scope-acceptance statement. → Selects
  rules branch **R-b** viability.
- [ ] **Claim 4 — `~/.claude/rules/*.md` user-level auto-load.** In the sandboxed
  `CLAUDE_CONFIG_DIR`, write a rules file carrying a unique token; ask the model
  to repeat it. Also write a CONFLICTING instruction token in a project-level
  rules file and record which wins (precedence). **Sub-probe (scope of load):**
  open a session in a SECOND scratch project with NO zskills install at all and
  ask for the token — record whether the user-level file loads for EVERY
  project (expected: yes — it is user-global). → Selects rules branch **R-a**
  viability; note R-a is demoted below R-c in selection order (see the AC) —
  the user-global file is static text that cannot condition on project, so it
  imposes zskills rules on non-zskills projects and double-delivers on
  legacy-lane zskills projects with no possible guard. R-a is selectable only
  by explicit plan amendment citing this sub-probe's result.
- [ ] **Claim 5 — `${CLAUDE_PLUGIN_ROOT}` substitution in skill bodies.**
  Synthetic plugin skill whose fenced bash echoes `${CLAUDE_PLUGIN_ROOT}` in
  double quotes, in single quotes, and via the #1046–48 bare-token fence idiom.
  Determine: text-substitution before the model sees it, or a real env var in the
  Bash tool? Simplification-opportunity only — NO later work item hard-depends on
  this; record the finding for Phase 3's fence idiom choice (fallback = existing
  bare-token + BASH_SOURCE self-location idiom, always valid).
- [ ] **Claim 6 — `updatedInput` honored from hooks.json.** **PRIMARY
  discriminator — command REWRITE, marker-observable:** register a PreToolUse/
  Bash hook in the synthetic plugin whose `updatedInput` envelope REWRITES the
  `command` field to `touch <marker-path>`; the session instructs exactly one
  innocuous Bash call (`echo zsprobe-noop`). Marker present ⇒ the hooks.json
  `updatedInput` envelope was honored (the executed command came from the hook,
  not the model) — a file observable, per harness discipline. **Negative
  control:** same session shape with NO hook registered ⇒ marker absent. The
  two arms are trivially distinguishable and independent of the harness's
  auto-background behavior and of any output-shape grep. Marker absent (or
  present in the control) after 3 attempts → FAIL → T-C (conservative).
  **Timeout-field semantics follow by composition, not by a separate shape
  probe:** the production frontmatter path already ships the SAME
  `timeout: 600000` `updatedInput` envelope (known-working Layer-0), so once
  command-rewrite proves hooks.json envelopes are honored, register the real
  timeout-style hook and compose the claim-2 capture hook AFTER it — record
  whether the capture's stdin `tool_input` shows `timeout: 600000`
  (composition result goes in the Findings row; Phase 2's STOP check reuses
  it). **Supporting evidence only (demoted, never the pass/fail signal):** a
  `sleep 150 && touch <marker2>` arm — the marker2 alone is NON-discriminating
  because at the 120s default the harness AUTO-BACKGROUNDS rather than kills
  (managed.md "Bash tool timeouts and bg behavior"), and tool-result
  shape-grepping is an unverified platform claim inside the harness; record it
  if run, decide on the rewrite discriminator. Control arm: the rewrite probe
  via a project `.claude/agents/` agent with a FRONTMATTER hook (known-working
  path) to validate the harness. Run in BOTH install shapes. → With
  claim 2, selects the **T branch**:
  - **T-A**: claims 2 (fires in subagent, identity field present) + 6 pass →
    hooks.json delivery, filtered to `{verifier, implementer}`.
  - **T-B**: claim 6 passes, claim 2 fires but NO identity field → hooks.json
    delivery, **unconditional 600s for all Bash calls**. This is a semantic
    widening and this plan ACCEPTS it explicitly: managed.md already instructs
    orchestrators to pass 600000 for long commands; widening the ceiling-raise to
    all callers changes no documented contract and removes the
    bg+Monitor trigger globally.
  - **T-C**: claim 6 fails OR claim 2 does not fire on subagent calls →
    frontmatter delivery: init writes `.claude/hooks/inject-bash-timeout.sh` and
    `.claude/agents/{verifier,implementer}.md` WITH frontmatter hooks. **T-C
    forces branch 1B regardless of claim 1's result** (plugin agents ignore
    frontmatter hooks, so frontmatter-delivered Layer-0 requires project-side
    agents). Record this coupling in the Findings table if T-C is selected.
- [ ] **Append the Findings.** Fill the `## Findings — Phase 1` table below
  (edit THIS plan file in the worktree; the tracker update rides the same
  commit). Every cell gets a result + the evidence path (`$TMP` transcript/marker
  listing copied to `/tmp/zskills-tests/<worktree>/phase1-evidence/` — quote key
  excerpts in the phase report since `$TMP` is ephemeral).
- [ ] Clean up synthetic plugins/marketplaces from the sandbox config
  (`claude plugin marketplace remove` the test entries); verify with
  `claude plugin marketplace list` against the SANDBOX config dir only.

### Design & Constraints

- **Attended-step protocol applies (Execution context):** under `/run-plan`
  dispatch the implementer STOPs with an ATTENDED-PENDING list for every probe
  requiring a live session — it never simulates a probe result. An unrun probe
  is NOT a FAIL-selects-fallback; it is pending until actually run.
- Probes must not touch this repo's `~/.claude` (live marketplace entries, real
  config) — everything under the sandbox `CLAUDE_CONFIG_DIR`.
- An inconclusive result is a FAIL → fallback branch. Do not re-litigate a
  fallback selection later in the plan ("maybe it works after all") — re-probing
  is a plan amendment, not an implementer call.
- No production files change in this phase except this plan file.

### Acceptance Criteria

- [ ] `## Findings — Phase 1` table fully populated: 6 claims × (result shape (a),
  result shape (b), selected branch, evidence pointer) — no empty cells, no
  "probably".
- [ ] Selected branches named for: agents delivery (1A/1B), timeout delivery
  (T-A/T-B/T-C), rules delivery (pick the first viable in order **R-b, R-c**;
  R-a is demoted below R-c per the Claim-4 scope-of-load hazard — user-global
  rules impose on non-zskills projects and double-deliver on legacy zskills
  projects with no possible guard — and since R-c is always viable, R-a is
  reachable only by explicit plan amendment), fence idiom note (claim 5).
- [ ] Claim 6's rewrite-marker discriminator demonstrated: marker present with
  the hook registered AND absent in the no-hook negative control (file
  observables, both install shapes), with the capture-composition result
  recorded — or the claim is recorded FAIL → T-C.
- [ ] `git status` in the worktree shows ONLY this plan file modified.
- [ ] `bash tests/run-all.sh` passes — state the command and per-suite results
  with pass counts (no tree changes, but run it; Invariant 4 idiom).

### Dependencies

None in-plan — first phase. **Execution-time pre-flight (hard precondition):**
verify the BLOCK_DIAGRAM_REMOVAL_PLAN has EXECUTED and landed on main before
starting — check that `block-diagram/` is gone from the tree (or, if the BD
plan's final shape kept it, that its tracker shows all phases ✅ with commit
hashes). At this plan's drafting time it was only DRAFTED (`block-diagram/`
present; `scripts/switch-install-path.sh` `is_shipped_skill` ≈L108 intact).
If the pre-flight fails, STOP and surface — do not proceed, do not attempt to
execute the BD plan from here.

---

## Findings — Phase 1

> (Heading deliberately does NOT match `^## Phase \d` — keeps /run-plan's
> phase extraction from treating this section as a phase.)
> Populated by the Phase 1 implementer. Later phases implement the SELECTED
> branch; both branches of every dependent item are fully specced below.

| Claim | Shape (a) `--plugin-dir` | Shape (b) marketplace install | Selected branch | Evidence |
|---|---|---|---|---|
| 1 — agents/ bare dispatch | PASS — bare AND scoped both dispatch (markers). Manifest `agents` field: `validate` REJECTS (rc=1 "agents: Invalid input") AND breaks agent load — never add it (auto-load dir only; #1062-class trap confirmed). Project twin SHADOWS plugin agent on bare dispatch (A1.5 stale-agents hazard proven live). | PASS — bare dispatch works on a real user-scope marketplace install (marker) | **1A** — ship root `agents/`; dispatch sites unchanged | phase1-evidence/claim1-*.txt |
| 2 — hooks.json PreToolUse in subagents + identity | PASS — fires on subagent Bash (capture rec); `agent_type`+`agent_id` PRESENT on subagent calls (value = bare agent name for project agents); ABSENT on orchestrator main-thread calls (recorded fact: T-A absent⇒EXTEND covers orchestrator = accepted T-B-equivalent widening for identity-less calls) | PASS — subagent capture fired; **`agent_type` value is PLUGIN-SCOPED (`zsprobe:zsprobe-agent`) even for bare dispatch** → Phase 2's T-A filter MUST match `{verifier, implementer}` by suffix/basename (accept `zs:verifier` and `verifier`) | feeds **T-A** | phase1-evidence/claim2-*.jsonl |
| 3 — SessionStart additionalContext (15KB, /clear) | PASS — 16,423-byte envelope delivered; token verbatim; re-injection per fresh session proven by construction | PASS — delivered under marketplace install; **enablement-scope fact: user-scope install (the CLI default) fires the hook in EVERY project incl. unrelated ones** (proj3 probe) — factual basis for the Phase 4 scope-acceptance statement. ATTENDED-PENDING ×2 (conservative fallbacks documented): combined-envelope `systemMessage` co-delivery rendering (headless-unobservable; if unproven Phase 7 keeps two SessionStart entries); literal interactive `/clear` arm (functionally covered by fresh-session evidence) | **R-b viable → SELECTED** (first in R-b, R-c order) | phase1-evidence/claim3-*.txt |
| 4 — ~/.claude/rules auto-load + precedence | (config-level, shape-independent) PASS — user-level rules auto-load; project rules load; PROJECT wins conflicts (COLOR=RED in proj, BLUE elsewhere); user-level file loads in EVERY project (proj2 probe) — R-a's scope hazard is factual | n/a | R-a demotion CONFIRMED (selectable only by plan amendment) | phase1-evidence/claim4-*.txt |
| 5 — ${CLAUDE_PLUGIN_ROOT} in skill fences | PASS — TEXT SUBSTITUTION before the model sees the body: even single-quoted `'${CLAUDE_PLUGIN_ROOT}'` arrived resolved; plugin-root script invocation ran (marker) | (substitution is render-time, shape-independent; shape (b) skill load exercised via claims 1/2/6 plugins) | note: direct plugin-root refs are safe in skill bodies; existing bare-token idiom remains valid (no migration forced) | phase1-evidence/claim5.txt |
| 6 — updatedInput from hooks.json | PASS — rewrite discriminator: marker PRESENT with hook (model faithfully reported its echo's stdout vanished = executed command was the hook's rewrite); marker ABSENT in no-hook negative control | PASS — rewrite marker present under marketplace install | **T-A** (claims 2+6 both pass with identity). Composition: sibling hooks in the same event see the ORIGINAL tool_input (updatedInput is execution-level, not hook-chain-level); real inject-bash-timeout.sh emits `timeout: 600000` envelope in plugin context (standalone check) — Phase 2's live STOP check uses the REWRITE discriminator, not capture-composition | phase1-evidence/claim6-*.txt/.jsonl |

**Selected:** agents = **1A** ; timeout = **T-A** (filter must accept plugin-scoped `agent_type` values, e.g. `zs:verifier`; absent⇒EXTEND covers orchestrator + legacy frontmatter) ; rules = **R-b** ; couplings noted = **none forced (T-C not selected); NEW Phase-2 input: scoped-agent_type filter; A1.5 twin-shadowing hazard confirmed live; manifest `agents` field FORBIDDEN**

**Probe integrity:** all probes ran in an `env -i` sandbox `CLAUDE_CONFIG_DIR` (mktemp); real `~/.claude/.credentials.json` md5 byte-identical before/after (`80f4c8d6…`); sandbox marketplace removed post-run (`plugin marketplace list` → none); evidence preserved at `/tmp/zskills-tests/zskills-pr-install-redesign-plan/phase1-evidence/`.

---

## Phase 2 — Plugin-native agents + hooks.json Layer-0 timeout

### Goal

Deliver the verifier/implementer agents and Layer-0 bash-timeout injection
plugin-natively (per the Phase 1 selections), with the parity test, conformance
retargets, manifest assertion, and release-tree staging that lock them — all
ADDITIVE: the materialiser still exists and still serves not-yet-migrated
consumers.

### Work Items

**A. Agents (Claim 1).**

- [ ] **Branch 1A (bare dispatch works):** create root `agents/verifier.md` and
  `agents/implementer.md` as checked-in SOURCE files — body-identical to
  `.claude/agents/{verifier,implementer}.md` minus the frontmatter `hooks:` block
  (plugin agents ignore frontmatter hooks; Layer-0 comes from item B). Keep
  `name:`, `tools:` allowlist (`Read, Grep, Glob, Bash, Edit, Write`), and the
  scope-creep prose byte-identical to the `.claude/agents` copies.
  - New suite `tests/test-agents-parity.sh`: asserts root `agents/<n>.md` vs
    `.claude/agents/<n>.md` body-identical modulo the frontmatter `hooks:` block,
    and that the `.claude/agents` copies STILL carry the `hooks:` block (legacy
    Layer-0 — Invariant 10) while the root copies do NOT. Register in
    `tests/run-all.sh` + satisfy `tests/test-suite-registry.sh` (≈L97 enumeration)
    — the suite/run-all/registry triplet rides one commit.
  - `tests/test-plugin-manifest.sh` ≈L99–103: KEEP the "no `agents` field in
    plugin.json" assertion (duplicate-load trap unless Claim 1's manifest-field
    probe proved otherwise — if it proved an explicit field is REQUIRED for
    shape-(b) loading, add the field and invert the assertion, citing the
    Findings row). ADD a tree-shape assertion: `agents/verifier.md` and
    `agents/implementer.md` exist at plugin root.
  - **Release staging:** add `agents/` staging to the SHARED
    `scripts/_lib/finalize-prod-tree.sh` (parallel to the D3 CLAUDE_TEMPLATE copy
    and D4 siblings) and add root `agents/` to the URL tree-walk (≈L257–280 —
    verify by content). Both build lanes (`build-prod.sh` serves it via the
    shared finalizer; `build-plugin-release.sh` likewise) — confirm by grepping
    each script for the finalizer call, not by assumption.
  - Conformance `tests/test-skill-conformance.sh` ≈L732–798 (.claude/agents file
    pins — `name:`, `inject-bash-timeout` reference, scope-creep prose): extend
    the loop/pins to cover the root `agents/` twins WHERE the assertion applies
    (the `inject-bash-timeout` frontmatter reference pin applies ONLY to the
    `.claude/agents` copies on 1A — split the pin per location).
- [ ] **Branch 1B (bare dispatch dead):** do NOT create root `agents/`. Instead
  record in this phase's report that agent delivery moves to Phase 6a init
  (init copies `${CLAUDE_PLUGIN_ROOT}/.claude/agents/{verifier,implementer}.md` →
  project `.claude/agents/`, atomic-write + never-clobber-newer, #1079
  discipline — the `.claude/agents` files are tracked and therefore present in
  the released plugin tree; verify with `git ls-files .claude/agents/`). No
  parity suite, no manifest tree-shape assertion, no finalizer change. Phase 6a's
  init item A4 implements it.
- [ ] **Both branches:** dispatch sites stay literally `subagent_type: "implementer"`
  / verifier — conformance ≈L694–714 impl pins and ≈L365–368 verifier pins are
  UNTOUCHED. List in the phase report: `grep -rn 'subagent_type: "implementer"' skills/`
  count unchanged before/after.

**B. Layer-0 timeout (Claims 2 + 6).**

- [ ] **Branches T-A / T-B (hooks.json delivery):**
  - Add a PreToolUse/Bash entry to `hooks/hooks.json`:
    `bash "${CLAUDE_PLUGIN_ROOT}/hooks/inject-bash-timeout.sh"`.
  - Edit `hooks/inject-bash-timeout.sh` (114 lines): source the D16 shim like the
    other 12 command hooks (it has no settings.json same-basename sibling on the
    legacy lane — legacy delivers it via frontmatter, not settings.json — so the
    shim no-ops; sourcing it satisfies `test-plugin-hooks-integrity.sh` Gap 2's
    "every hooks.json hook sources the shim" assertion without an exclusion
    entry). Then:
    - **T-A:** read the agent-identity field (exact name per the Findings row)
      from stdin JSON. Pinned semantics — no per-branch hedging:
      **absent identity ⇒ EXTEND** (the legacy frontmatter path feeds this SAME
      byte-identical script identity-less stdin, and every existing test case
      asserts 600000 on identity-less input — absent-identity input is by
      construction a frontmatter-declared call, i.e. verifier/implementer);
      **present ∈ `{verifier, implementer}` ⇒ extend**;
      **present-and-foreign ⇒ pass through** (empty envelope). Consequence
      (recorded in the Claim-2 Findings row): if orchestrator main-thread calls
      carry NO identity field, they also extend — T-A degenerates to T-B for
      orchestrator calls, an ACCEPTED widening (same rationale as T-B).
    - **T-B:** extend unconditionally (the accepted widening — cite the Findings
      row in the commit message).
    Bump the line-2 `# zskills-hook-version:` stamp; refresh the
    `.claude/hooks/inject-bash-timeout.sh` mirror byte-identically (the SAME file
    serves the legacy frontmatter path — absent-identity extends, which is
    exactly what the frontmatter context needs on T-A; on T-B unconditional is
    unconditional in both contexts).
  - Extend `tests/test-inject-bash-timeout.sh` (219 lines, pure stdin/stdout —
    KEEP all existing cases): add identity-filter cases (T-A: verifier extends,
    implementer extends, **no-field EXTENDS** — pins the absent⇒extend rule the
    existing identity-less cases already imply — foreign agent passes through)
    or unconditional cases (T-B).
  - New structural pin (new suite or a section in
    `tests/test-plugin-hooks-integrity.sh`): hooks.json contains exactly one
    PreToolUse entry referencing `inject-bash-timeout.sh` under
    `${CLAUDE_PLUGIN_ROOT}/hooks/`. Update integrity Gap 2/Gap 3 expectations in
    the same commit as the hooks.json edit. If it lands as a NEW suite, the
    run-all.sh registration + suite-registry entry ride the same commit
    (triplet).
  - Retarget `tests/canary-verifier-timeout-injection.sh` ≈L94–107 per lane: the
    frontmatter-declaration assertion stays pinned to `.claude/agents/` (legacy);
    add the plugin-lane assertion (hooks.json entry present; on 1A, root
    `agents/` files carry NO `hooks:` block).
- [ ] **Branch T-C (hooks.json delivery dead):** no hooks.json entry; no script
  filter change. Layer-0 stays frontmatter-delivered on BOTH lanes; the plugin
  lane gets `.claude/hooks/inject-bash-timeout.sh` + frontmatter-bearing
  `.claude/agents/` written at Phase 6a init (item A4; coupling: T-C ⇒ 1B).
  In THIS phase, only land the canary/conformance prose that documents the
  selected branch, and verify `canary-verifier-timeout-injection.sh` still
  passes unmodified.
- [ ] **Layer-0 STOP check (branch-appropriate, marker-observable):**
  - **T-A/T-B:** demonstrate THIS phase's landed hooks.json entry actually
    fires and emits the extension on a verifier-dispatched Bash call: in a
    scratch consumer, register a claim-2-style capture hook AFTER the landed
    `inject-bash-timeout.sh` entry and assert the capture's recorded
    `tool_input` carries `timeout: 600000` for a verifier-dispatched call —
    per the Phase-1-recorded composition result. If Phase 1 recorded
    capture-composition as unreliable, substitute a PROBE-ONLY variant of the
    landed hook that additionally touches a marker file whenever it emits the
    extension envelope (never shipped; file-observable). Supporting evidence
    (not the signal): a verifier-dispatched `sleep 150 && touch <marker2>`
    completes. A missing capture record / probe marker is an Invariant-7
    Failure-Protocol STOP, not a pass. Record in the phase report.
  - **T-C:** nothing new lands in this phase (frontmatter delivery arrives at
    Phase 6a init item A4), and the still-live materialiser keeps serving the
    known-working frontmatter path — so no boundary leaves verifier Bash at
    120s. The new-mechanism STOP check DEFERS to Phase 6a A4's validation;
    this phase's evidence is `canary-verifier-timeout-injection.sh` passing
    unmodified. State the deferral explicitly in the phase report.

### Design & Constraints

- This phase must not edit the materialiser SCRIPT (zero edits to
  `session-start-materialise.sh`). Note an EXPECTED output flip on 1A: the
  materialiser's `resolve_src` (≈L117–127) prefers `$PLUGIN/agents/<n>.md` over
  `.claude/agents/<n>.md`, so once root `agents/` exists, materialised
  `.claude/agents/` copies on plugin consumers lose the frontmatter `hooks:`
  block. That content flip is Layer-0-safe by construction — 1A implies
  T ∈ {T-A, T-B} (T-C forces 1B), so this same phase's hooks.json entry
  supplies the 600s extension for exactly those consumers. State the flip in
  the phase report; do NOT "fix" it by editing the materialiser. The
  materialised `.claude/hooks/inject-bash-timeout.sh` copy and the hooks.json
  edit also coexist
  (on a dual-delivery consumer the PreToolUse hook firing twice is idempotent:
  setting timeout=600000 twice is the same envelope; note this in the hook
  header comment).
- `tests/test-inject-bash-timeout-parity.sh`: if its sentinel-half (materialised
  copy vs source comparison keyed on the D20 sentinel) fails against this phase's
  stamp bump, update the EXPECTATION, do not skip the test — its sentinel-half is
  deleted in Phase 7, not here.
- Do NOT touch: dispatch-site literals; `.claude/agents/` frontmatter (Invariant
  10); the D16 shim itself; `plugin.json` `hooks` field (must remain ABSENT —
  duplicate-load trap).

### Acceptance Criteria

- [ ] Branch-appropriate delivery landed and probed live (the Layer-0 STOP check
  marker quoted in the report), in install shape (b).
- [ ] 1A only: `bash tests/test-agents-parity.sh` passes; manifest tree-shape
  assertion passes; a locally-built release tree
  (`bash scripts/build-prod.sh` to a temp dir) contains root `agents/` — show the
  `ls` output.
- [ ] T-A/T-B only: `grep -c 'inject-bash-timeout' hooks/hooks.json` → 1;
  integrity suite green including Gap 2 for the new entry.
- [ ] Conformance impl/verifier dispatch pins (≈L694–714, ≈L365–368) byte-untouched:
  `git diff <phase-base>..HEAD -- tests/test-skill-conformance.sh` shows no edits
  in those assertion blocks (agents-file-pin edits at ≈L732–798 are expected on 1A).
- [ ] `bash tests/run-all.sh` passes — state the command and per-suite results
  with pass counts.

### Dependencies

Phase 1 (branch selections recorded).

---

## Phase 3 — Layer-3 relocation (verify-response-validate.sh)

### Goal

Relocate the Layer-3 validator from a materialised hook copy to a skill-bundled
script that BOTH lanes resolve uniformly, retargeting every call site and the
conformance pin in one lockstep commit.

### Work Items

- [ ] `git mv hooks/verify-response-validate.sh skills/update-zskills/scripts/verify-response-validate.sh`
  and `git rm .claude/hooks/verify-response-validate.sh`; then
  `bash scripts/mirror-skill.sh update-zskills` so the mirror gains
  `.claude/skills/update-zskills/scripts/verify-response-validate.sh`. Update the
  hook-mirror-parity exclusion/inclusion lists (`tests/test-hooks-mirror-parity.sh`
  and the test-hooks sub-suite) in the SAME commit — the file is no longer a hook.
- [ ] **Retarget every call site.** Re-derive the list (do not trust the
  inventory):
  `grep -rn 'verify-response-validate' skills/ .claude/skills/ tests/ hooks/ CLAUDE.md` —
  inventory says ~14 sites across 6 skill files / 5 skills:
  `verify-changes/SKILL.md` ≈L33,50; `commit/SKILL.md` ≈L325,340; `do/SKILL.md`
  ≈L1021,1026,1068,1073; `do/modes/pr.md` ≈L285,291;
  `run-plan/modes/execute-phase.md` ≈L537,741; `fix-issues/modes/sprint.md`
  ≈L2536,2541. Each literal
  `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"` becomes
  `bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/verify-response-validate.sh"`,
  with the fence (or the fence immediately above) sourcing the canonical
  resolution prelude that exports `$ZSKILLS_SKILLS_ROOT` (per
  `references/canonical-config-prelude.md` and the per-fence positive-side check
  in conformance) — verify the exact exported variable name by reading
  `zskills-paths.sh` / the prelude reference FIRST; if the canonical name
  differs, use the canonical one everywhere.
- [ ] **Conformance pin retarget** (same commit): `tests/test-skill-conformance.sh`
  ≈L366 pins the OLD literal — rewrite to pin the NEW dual-lane form, modeled on
  the clear-tracking #865 dual-lane pin pattern (≈L1954–1957). The pin must
  REJECT any reintroduction of the `.claude/hooks/` form.
- [ ] **Test surfaces for the move (same commit):**
  - `tests/test-verify-response-validate-parity.sh` (≈L20–35 asserts
    `hooks/` + `.claude/hooks/` copies present + byte-equal — BOTH subjects
    cease to exist): DELETE, with the run-all.sh + suite-registry entries
    removed in the same commit (triplet) and a subject-removal rationale in
    the commit message. The mirror-parity property it guarded now lives in the
    skills source↔mirror parity suite (the file is skill-bundled).
  - `tests/test-verify-response-validate.sh` ≈L22
    (`HOOK="$REPO_ROOT/hooks/verify-response-validate.sh"`): retarget to the
    new `skills/update-zskills/scripts/` path. All behavior cases unchanged.
  - `tests/canary-verify-response-validate.sh` ≈L31 (same `HOOK=` literal):
    retarget identically.
  - `tests/test-update-zskills-agent-install.sh` ≈L65,91 (legacy consumer
    portable-build hook enumeration includes `verify-response-validate.sh`)
    and ≈L162,174,205 (copies it into the portable tree + asserts the
    installed `.claude/hooks/` copy): REWORK — the legacy lane now delivers
    the script via the skills mirror, so the hook-enumeration entries drop and
    the assertion retargets to
    `.claude/skills/update-zskills/scripts/verify-response-validate.sh`
    (executable). This suite is EDITED by this phase — Phase 6a's AC says it
    "passes", not "passes unchanged".
- [ ] **verify-install lockstep (same commit as the materialiser shrink — M-fix
  for the spec-broken window):** `skills/update-zskills/verifiers/verify-install-lib.sh`
  `vi_check_plugin` (≈L475–510) FAILs unless ALL 5 sentinelled artifacts are
  present; with the materialiser shrunk to 4 it would fail every healthy
  plugin install until Phase 6b. Shrink its artifact list 5→4 (drop
  `hooks/verify-response-validate.sh`) in the SAME commit, and update
  `tests/test-verify-install.sh` fixtures (`make_plugin_good` ≈L140–156
  fabricates the 5 independently) to 4. The fixture↔lib independence is itself
  a gap: add a NEW congruence assertion (fixture artifact set derived from, or
  asserted equal to, the lib's `artifacts=()` list) so the two cannot drift —
  new-test item, this commit.
- [ ] **Version bumps:** the 5 touched skills (`verify-changes`, `commit`, `do`,
  `run-plan`, `fix-issues`) + `update-zskills` (gains the script) — Invariant-1
  bump + re-mirror each, per commit.
- [ ] **Legacy lane rework in `skills/update-zskills/SKILL.md` — a multi-site
  edit, not a one-liner.** The skill names `verify-response-validate.sh` at 6+
  sites (re-derive: `grep -n 'verify-response-validate' skills/update-zskills/SKILL.md`
  — currently ≈L1453–1458 the hook-install copy instruction + no-settings.json
  note, ≈L1502 the hooks prose, ≈L1543 the hook enumeration list, ≈L1779 a
  report-template line listing the artifact). Rework each: (a) the Step-C-region
  hook-install enumeration drops the moved file (the skills mirror now carries
  it); (b) add an update-path cleanup that removes a stale
  `.claude/hooks/verify-response-validate.sh` on legacy update — if that proves
  intrusive, document the stale copy as harmless dead residue instead (choose
  ONE, state which in the report); (c) the ≈L1779 report-template line retargets
  to the new path — it is a verbatim-printed template string; apply
  allow-hardcoded-style judgment per the skill-file hardcode discipline if the
  new literal trips the deny-list, with an inspectable marker, not an exemption
  by silence.
- [ ] **Materialiser tolerance (this phase only — materialiser dies in Phase 7):**
  the materialiser's artifact list includes `verify-response-validate.sh` (one of
  its 5 artifacts). Remove that artifact from its write list — concretely, two
  edits to `hooks/session-start-materialise.sh` itself (this phase's deliberate
  carve-out from the otherwise zero-materialiser-edits posture): the
  `for hook in inject-bash-timeout verify-response-validate` write loop (≈L304)
  drops the second entry, and the header's 5-artifact enumeration comment
  (≈L10–14) drops its line. Bump the hook's line-2 `# zskills-hook-version:`
  stamp. Also remove the
  conformance presence list ≈L240–252 entry for it IF the presence list pins the
  materialised artifact (verify by content); the materialiser keeps writing the
  other artifacts. This is a forward-only shrink: plugin consumers get Layer-3
  from the plugin skills tree as of this phase.
- [ ] Update `skills/update-zskills/references/script-ownership.md` (new row) and
  `tests/test-sessionstart-materialise.sh` expectations (artifact count 5→4) —
  same commit as the materialiser shrink; flag as subject-removal (the artifact
  ceases to be materialised because it is now skill-bundled).
- [ ] **5→4 shrink lockstep — three MORE suites assert the 5-artifact set and
  ride the SAME commit as the shrink (they run unconditionally; two hard-fail,
  one goes vacuous, the moment the materialiser stops writing the 5th):**
  - `tests/test-broken-python3-stub-e2e.sh` case 3 (≈L155–185; run-all ≈L121):
    executes the materialiser and asserts all 5 artifacts including
    `.claude/hooks/verify-response-validate.sh` (`H2`) — rework case 3 (and the
    `H2` fixture var) to the 4-artifact set.
  - `tests/test-sessionstart-dual-install-detect.sh` case 2'b (≈L110–122;
    run-all ≈L375): asserts the materialiser "writes all 5 artifacts" —
    rework to 4.
  - `tests/test-sessionstart-materialise-overwrite-guard.sh` scenario D
    (≈L99–110): `stat`s `verify-response-validate.sh` mtime across two
    materialiser runs — post-shrink the file is never written, BOTH `stat`
    substitutions come back empty, `"" = ""` → **vacuous PASS** that silently
    untests mtime-idempotency for four phases. RETARGET scenario D onto a
    still-materialised artifact (`inject-bash-timeout.sh`).
  All three are interim 4-artifact edits; Phase 7 commit 1 still owns their
  materialiser-deletion fate (retarget/delete) and receives them in this
  Phase-3-edited form.

### Design & Constraints

- Zero `${CLAUDE_PLUGIN_ROOT}` literals existed at any call site (verified in
  research) — every edit is old-literal → new-resolved-form; there is no second
  legacy spelling to chase.
- The relocated script's CONTENT does not change (7-phrase whitelist, 200-byte
  minimum) — relocation only. Any content drift is out of scope.
- Do NOT touch: `hooks/inject-bash-timeout.sh` (stays a hook — legacy frontmatter
  + Phase 2 delivery need it under `hooks/`); the D6 resolver sites; dispatch-site
  pins.

### Acceptance Criteria

- [ ] `grep -rnE '(\.claude/)?hooks/verify-response-validate' skills/ .claude/skills/ hooks/ tests/`
  → 0 hits beyond the TWO allowed survivors — the wider pattern also catches
  bare `hooks/...` pins like the
  deleted parity suite's `SRC=` line. Allowed survivors: (1) the conformance
  pin's rejection arm may quote the old literal — if so, exactly that one hit,
  inside the pin; (2) `hooks/_lib/detect-install-state.sh`'s sentinel-evidence
  entry (`"$claude/hooks/verify-response-validate.sh"`, ≈L84) — it is CORRECT
  mid-window (an upgraded consumer's still-present sentinelled artifact remains
  valid plugin-lane evidence) and is single-owned by Phase 7 commit 3's detect
  rework; do NOT edit it in this phase.
- [ ] `test -f skills/update-zskills/scripts/verify-response-validate.sh` and the
  mirror twin both exist, byte-identical; `test ! -e hooks/verify-response-validate.sh`.
- [ ] On the legacy lane (this repo): `bash .claude/skills/update-zskills/scripts/verify-response-validate.sh <<<"x"`
  exits per its contract (smoke the relocated path actually executes).
- [ ] All 5+1 skill versions bumped, source/mirror equal, dated landing day.
- [ ] `bash tests/run-all.sh` passes — state the command and per-suite results
  with pass counts.

### Dependencies

Phase 1 (none of this is branch-dependent, but Phase 2's conformance edits touch
the same file — serialize to avoid conflict churn). Can technically swap with
Phase 2; do not parallelize.

---

## Phase 4 — Rules de-parameterization + delivery channel

### Goal

Make the managed rules install-level (no per-project tokens that require a
project render to be correct) and stand up the Phase-1-selected delivery channel
for plugin consumers — additive; legacy `--rerender` flow unchanged in shape.

### Work Items

**A. De-parameterize `CLAUDE_TEMPLATE.md` (389 lines, 10 tokens — re-derive the
token list by grepping the template for the renderer's substitution markers
before editing):**

- [ ] `PROJECT_NAME` (≈L1): static title ("Project Agent Rules" or equivalent —
  no token).
- [ ] `SOURCE_LAYOUT` (≈L5): drop the section (project-specific by nature; the
  project's own CLAUDE.md owns architecture).
- [ ] `DEV_SERVER_CMD` (≈L98), `DEFAULT_PORT`/`MAIN_REPO_PATH` (≈L100),
  `AUTH_BYPASS` (≈L106), `UNIT_TEST_CMD`/`FULL_TEST_CMD` (≈L113–136),
  `TEST_FILE_PATTERNS` (≈L163): replace baked literals with config-resolution
  prose — the rules now INSTRUCT the agent to resolve these via the canonical
  prelude (`zskills-resolve-config.sh`) at point of use, instead of carrying a
  rendered value. Keep the surrounding rule prose (test discipline, dev-server
  prohibitions) intact.
- [ ] `TIMEZONE` (≈L228 — **inside the Worktree Rules `.landed` heredoc**; note:
  Phase 8 edits this SAME heredoc's path — keep the heredoc structure intact so
  the Phase 8 diff stays clean): token → `${TIMEZONE:-UTC}` with the prelude
  sourced per the skill-file hardcode discipline.
- [ ] **Non-token legacy-mirror-only paths (same de-parameterization pass):**
  the template also bakes literal `.claude/skills/update-zskills/...` paths
  that are WRONG on a mirror-less plugin consumer — ≈L100 (`bash
  .claude/skills/update-zskills/scripts/port.sh` + the
  `references/stub-callouts.md` pointer) and ≈L167 (the hardcode-discipline
  prelude path `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`).
  Rewrite each to a dual-path or descriptive form (e.g. "the `update-zskills`
  skill's `scripts/port.sh` — under `${CLAUDE_PLUGIN_ROOT}/skills/` on the
  plugin lane, `.claude/skills/` on the legacy mirror"). Re-derive the full set:
  `grep -n '\.claude/skills/' CLAUDE_TEMPLATE.md` and adjudicate every hit.
- [ ] Shrink the substitution map in `scripts/render-managed-rules.py` (D24: ONE
  renderer, both lanes — the renderer survives even if the map goes empty; it
  remains the single render path + `--rerender` entry point). Re-render
  `.claude/rules/zskills/managed.md` in the SAME commit
  (`tests/test-managed-md-up-to-date.sh` gates template↔managed sync). Renderer
  fixture tests are self-contained — update fixtures alongside.
- [ ] **Canonical built-in-defaults artifact (THE single source — every later
  defaults copy pins to this):** new checked-in
  `skills/update-zskills/scripts/zskills-defaults.json` carrying the built-in
  defaults (timezone UTC, `landing: direct`, `main_protected: false`,
  `branch_prefix: feat/`, `output.file: .test-results.txt`, default_port 8080,
  ci.auto_fix true / max 2, `agents.min_model: auto`, output dirs
  `docs/plans|issues|reports`) — PORT the values from the materialiser seed
  (≈L324–392; the seed itself stays untouched until Phase 7). Lane-portable by
  construction (legacy mirror + plugin tree both ship
  `skills/update-zskills/scripts/`). Consumers of this file: the renderer's
  no-config mode (below, this phase), the Phase 5 family-4 Python merge helper
  (loads it directly — no copied dict), the Phase 6a A3 interview seed (reads
  it directly — no re-typed dict). The bash families 1/2 keep inline literals
  PINNED to it by the Phase 5 congruence check (bash can't cheaply parse
  JSON). Version-bump + re-mirror `update-zskills`.
- [ ] **Renderer no-config call shape (required by every R branch):** the
  renderer's `--config` is `required=True` and hard-errors on a missing/invalid
  JSON file (≈L43–66) — but the redesign's consumers are config-OPTIONAL, and
  R-b's hook / R-a's write / R-c's init render must all work with no config
  file at either tier. Add a no-config mode (e.g. `--defaults <path>`, or
  `--config` made optional) that LOADS the canonical
  `zskills-defaults.json` defined above — no second in-renderer copy of the
  values, no forward reference to later phases. Update the renderer's fixture
  tests (`test-render-managed-rules-correctness.sh`) with a no-config case. The
  legacy `--rerender` call shape (explicit `--config`) is unchanged.

**B. Delivery channel (Claims 3/4 — implement the selected branch; all three
fully specced):**

- [ ] **R-b (SessionStart `additionalContext` — preferred if Claim 3 passed):**
  new hook `hooks/session-rules-context.sh` registered in `hooks/hooks.json`
  SessionStart (ALONGSIDE the materialiser's entry — multiple SessionStart hooks
  are legal; the materialiser entry dies in Phase 7). The hook: resolves its own
  plugin root (BASH_SOURCE self-location per #1046–48), renders the
  de-parameterized template via `scripts/render-managed-rules.py` (plugin tree
  ships it — verify it is in the released tree; if not, add it to the finalizer
  staging in this commit, TOGETHER with `scripts/managed_rules_substitution.py`
  — the renderer imports it at ≈L34, so staging the renderer alone ships an
  ImportError — and the canonical `zskills-defaults.json`), emits the result as
  `additionalContext`
  (MODEL channel — #1088/#1089). **Zero writes.** Sources the D16 shim
  (Gap 2) — no settings.json sibling exists, so it no-ops on dual installs but
  satisfies the integrity assertion. Guard: skip (empty output) when the legacy
  mirror is present (`detect`-style mirror check) OR a project
  `.claude/rules/zskills/managed.md` exists — a rules copy already delivered
  from disk (legacy render, R-c render, or a STALE materialiser-era copy on an
  upgraded consumer that Phase 6a A1.5 hasn't cleaned yet); double-delivery
  would duplicate ~15KB of rules in context every session. After A1.5 removes
  a sentinelled stale copy, the guard naturally opens and the hook takes over.
  Update `test-plugin-hooks-integrity.sh` Gap 1/2/3
  expectations same commit; add `session-rules-context.sh` to
  `tests/test-hooks-mirror-parity.sh` `EXCLUDE_BASENAMES` (≈L41 — plugin-lane-only
  hook, no `.claude/hooks/` mirror) same commit; new structural test asserting
  the hook emits a well-formed envelope containing a known template landmark on
  a synthetic tree (renders via the no-config renderer mode when no config
  exists) AND that a fixture with a project managed.md present yields empty
  output (the widened guard) — registered in run-all.sh + suite-registry in
  the same commit (triplet).
- [ ] **R-a (user-level rules file — DEMOTED below R-c; reachable only by plan
  amendment citing the Claim-4 scope-of-load sub-probe):** the file is
  user-GLOBAL — it loads for EVERY project, imposing zskills rules on
  non-zskills projects and double-delivering on legacy-lane zskills projects,
  and a static file cannot guard against either. Spec retained for the
  amendment case: no new hook. Phase 6a init (and every subsequent
  `/zs:update-zskills` run) writes `~/.claude/rules/zskills.md` from the
  rendered template, atomic write, unconditional overwrite (refresh-on-update
  is the staleness mitigation — the rules carry a generated-by + version header
  line). Spec lands as prose in the SKILL.md update-path (Invariant-1 version
  bump + mirror for `update-zskills` in that commit); the actual write fence is
  a Phase 6a init step (item A5). Document the stale-after-update risk AND the
  scope-of-load acceptance (the amendment must state why global imposition is
  acceptable) in the file header.
- [ ] **R-c (per-project render at init — zero-platform-risk fallback):** no new
  hook. Phase 6a init renders `.claude/rules/zskills/managed.md` project-side
  (today's output location, init-triggered instead of materialiser-triggered) —
  a strict subset of current behavior. End-state item 2 gains this file
  (documented in the Overview's fallback deltas).
- [ ] In ALL branches: the LEGACY lane's render flow (`/update-zskills` Step B →
  `.claude/rules/zskills/managed.md`) is unchanged in mechanism; it simply
  renders the now-de-parameterized template. Run the legacy render path once and
  diff: the only changes are the de-parameterized sections.

### Design & Constraints

- The de-parameterization changes WHAT every consumer's rules say (commands → "
  resolve via config"). That is the point — but the rule PROHIBITIONS (never
  kill -9, never weaken tests, worktree rules...) must survive verbatim. Diff the
  rendered output against the old render and account for every removed line.
- `tests/test-managed-md-up-to-date.sh` self-heals (demands re-render in the same
  commit) — let it drive, don't fight it.
- **R-b scope acceptance (explicit, keyed to the Claim-3 enablement-scope
  sub-probe):** if the sub-probe shows a USER-scope install fires the
  SessionStart hook in every project, this plan ACCEPTS that R-b (and the
  Phase 7 greeting) delivers ~15KB of zskills rules context in non-zskills
  projects under a user-scope install. Rationale: it is strictly less invasive
  than the status quo (the materialiser WRITES 5 files into every such
  project; R-b writes nothing), and the cure is project-scope enablement —
  Phase 9's install guide MUST recommend project-scoped installation as the
  documented shape and state this trade. If the sub-probe instead shows
  enablement is inherently project-scoped, record that and drop the caveat
  from the docs item.
- Do NOT touch: `.zskills`/tracking prose in the template beyond the named tokens
  (Phase 8 owns the heredoc path edit); the `Cron-fired prompts` section's
  `zs:` recognition prose (still correct).

### Acceptance Criteria

- [ ] `grep -c '{{' CLAUDE_TEMPLATE.md` (or the renderer's actual token syntax —
  verify first) → 0, or exactly the residual set the phase report enumerates
  with rationale.
- [ ] `bash tests/test-managed-md-up-to-date.sh` passes (template and managed.md
  re-rendered in lockstep).
- [ ] Renderer no-config mode: `test-render-managed-rules-correctness.sh`'s new
  no-config case passes (render succeeds with no config file at either tier;
  output uses the built-in defaults).
- [ ] R-b only: live probe (synthetic or this repo via `--plugin-dir` with the
  mirror-guard temporarily satisfied in a SCRATCH copy — never modify this
  repo's state): model can quote a rules landmark token; zero files written —
  `git status --porcelain` empty in the probe project.
- [ ] Legacy render diff reviewed and quoted in the phase report (prohibition
  prose intact).
- [ ] `bash tests/run-all.sh` passes — state the command and per-suite results
  with pass counts.

### Dependencies

Phase 1 (R-branch selection). Independent of Phases 2–3 in content; keep order
for conflict hygiene (hooks.json, conformance).

---

## Phase 5 — Config cascade (project > user > built-ins)

### Goal

Give zero-config consumers working defaults: per-key shallow merge of project
`.claude/zskills-config.json` over user `~/.claude/zskills-config.json` over
built-in defaults, implemented per-reader-family (research option B), with the
family-3 hooks carve-out documented as deliberate.

### Work Items

- [ ] **Family 1 — `zskills-resolve-config.sh` (195 lines, BASH_REMATCH parsing):**
  two-pass read — extract from the USER body first (if
  `~/.claude/zskills-config.json` exists and parses), then from the PROJECT body;
  a key whose regex MATCHES in the project body wins (match-success = presence —
  the pragmatic presence test for the bash-regex family; document that a
  present-but-empty project value therefore wins over a user value). After both
  passes, fill built-in defaults for still-empty keys: `TIMEZONE→UTC`,
  `TEST_OUTPUT_FILE→.test-results.txt`, `MAX_CONCURRENT_WORKTREES→3` (already),
  `DASHBOARD_COMPLETED→14/500` (already). `UNIT_TEST_CMD`/`FULL_TEST_CMD`/
  `DEV_SERVER_CMD`/`COMMIT_CO_AUTHOR` have NO sane built-in — they stay empty
  (the three-case config-driven trees in consuming skills already handle empty).
  `ZSKILLS_VERSION`: project config stamp first; fall back to reading the
  version line from `.zskills/init-done` (Phase 6a writes it there for
  config-less consumers — until Phase 6a lands this fallback simply finds no
  file and yields empty; safe). **#1132 note:** the `.zskills/init-done`
  literal here is a temporary re-type — `init-state.sh` (the single path
  definition) does not exist until Phase 6a; Phase 6a item A0 RETARGETS this
  fallback to source `init-state.sh` and use `$ZSKILLS_INIT_DONE_REL`, and
  Invariant 6's sourcing set includes the resolver from that point.
- [ ] **Family 2 — `zskills-paths.sh` (output.* dirs):** same two-pass + defaults
  (`docs/plans|issues|reports`).
- [ ] **Family 3 — hooks (`block-unsafe-generic.sh` reads
  `execution.main_protected`; `block-agents.sh` reads `agents.min_model`):**
  **deliberate carve-out — project-only reads stay.** Rationale (record in each
  hook's header comment): these are SAFETY settings; a user-level file silently
  weakening a project's `main_protected` or model floor inverts the trust
  direction. Existing fail-open defaults unchanged. No code change beyond the
  comment.
- [ ] **Family 4 — Python readers (`collect.py`, `briefing.py`):** add a shared
  ~10-line merge helper (load user dict, load project dict, shallow per-key
  update, then defaults) — the defaults come from LOADING the canonical
  `zskills-defaults.json` (Phase 4), never a copied dict. Place the helper
  where both can import it without a new package boundary (verify how
  briefing.py/collect.py currently share code; if
  they don't, duplicate the helper with a sync comment, smallest-footprint call
  — the defaults still load from the ONE JSON in both copies).
- [ ] **Family 5 — inline fence readers (documented carve-out, no code
  change):** `skills/commit/SKILL.md` (≈L61–140) and
  `skills/fix-issues/SKILL.md` (≈L131) read `execution.landing` directly from
  the project config in their mode-selection fences (the hardcode discipline
  blesses inline self-resolution); routing them through the resolver is out of
  proportion. Decision: **`execution.*` keys are PROJECT-TIER-ONLY across the
  whole cascade** — consistent with the family-3 safety carve-out (landing /
  main_protected / branch_prefix / min_model describe the project's repo
  discipline, not a user preference). Record the rule HERE and in the Phase 9
  cascade docs (zskills-config.md must state that `execution.*` does not
  cascade from the user tier — so a user-tier `execution.landing` being
  silently ignored is documented behavior, not a bug).
- [ ] **Built-in defaults congruence net (canonical source =
  `zskills-defaults.json`, Phase 4):** the materialiser seed-dict (≈L324–392,
  EXTRACTED by conformance ≈L2364–2420) stays untouched in this phase (that
  extraction hard-fails on absence — Phase 7 lockstep). The bash families 1/2
  define their defaults inline (bash can't cheaply parse JSON); family 4 loads
  the JSON directly. Add a NEW conformance congruence check with two arms:
  (i) bash family-1/2 inline defaults ≡ `zskills-defaults.json` values, and
  (ii) materialiser seed-dict ≡ `zskills-defaults.json` for the overlapping
  keys — so NO copy can drift from the canonical artifact while it exists.
  Phase 7 deletes arm (ii) with the materialiser (subject-removal); arm (i)
  survives unchanged. The Phase 6a interview seed reads the JSON directly and
  needs no arm of its own.
- [ ] **Tests — `tests/test-zskills-resolve-config.sh` (500 lines) extension:**
  - HOME-sandboxed user-tier cases (`HOME=$TMP_HOME` so `~` resolves into the
    sandbox — verify the script expands `~` via `$HOME`; if it hardcodes a path,
    parameterize it test-visibly first).
  - Precedence: project>user per key; user fills project-absent keys; partial
    merge (user sets timezone, project sets tests.unit_cmd → both effective).
  - Malformed user file → ignored with the project+defaults result (fail-open,
    matching existing malformed-project behavior).
  - **Tests 3/4 re-spec (FLAG as intended assertion change, Invariant 3):** old:
    empty config → vars EMPTY; new: empty config → built-in defaults
    (`TIMEZONE=UTC`, `TEST_OUTPUT_FILE=.test-results.txt`, cmd vars still
    empty). State old/new expectations in the commit message.
  - Same treatment for `zskills-paths.sh` coverage and a Python-helper unit case.
- [ ] **Skill version bumps (Invariant 1) — this phase edits skill-owned files:**
  `zskills-resolve-config.sh` + `zskills-paths.sh` live under
  `skills/update-zskills/scripts/`, `briefing.py` under
  `skills/briefing/scripts/`, `collect.py` under
  `skills/zskills-dashboard/scripts/zskills_monitor/`. Bump + re-mirror
  `update-zskills`, `briefing`, and `zskills-dashboard` (per commit, after all
  content edits).

### Design & Constraints

- No reader may WRITE anything (the cascade is read-side only — the
  merge-once-materialise option A was REJECTED because it writes a project file
  for zero-config consumers).
- `~/.claude/zskills-config.json` is the fixed user-tier location (settled).
- Do NOT touch: the ~151 D6 resolver call SITES (they all go through the two
  family-1/2 scripts — that's why the cascade is cheap); hook fail-open defaults;
  the materialiser seed-dict (Phase 7).

### Acceptance Criteria

- [ ] With NO config files at either tier (sandboxed): sourcing
  `zskills-resolve-config.sh` yields `TIMEZONE=UTC`,
  `TEST_OUTPUT_FILE=.test-results.txt`, empty cmd vars — show the env dump.
- [ ] Precedence cases pass; malformed-user case passes; congruence check green.
- [ ] `bash tests/test-zskills-resolve-config.sh` passes with the new case count
  stated (old count → new count, all additions enumerated).
- [ ] `update-zskills`, `briefing`, `zskills-dashboard` versions bumped,
  source/mirror equal, dated landing day.
- [ ] `bash tests/run-all.sh` passes — state the command and per-suite results
  with pass counts.

### Dependencies

None hard; ordered before Phase 6a so init can rely on defaults-without-config.

---

## Phase 6a — Explicit init (Step 0.7 rework, residue cleanup, lock-LAST)

### Goal

Rework `/update-zskills` Step 0.7's bare-call arm into the explicit plugin-lane
init (gitignore-first, lock-LAST), including the A1.5 materialiser-residue
cleanup. The materialiser and switch machinery still exist (Phase 7 deletes
them), and the gate + verify-install are re-keyed in Phase 6b — this phase only
ADDS the new init path. (Phases 6a/6b are ONE design surface split for
single-dispatch sizing — round 3; their lockstep pairs never cross the split.)

### Work Items

**A. Init (in `skills/update-zskills/SKILL.md`, Step 0.7 bare-call arm
≈L1086–1185 — REWORK; read the whole of Step 0.7 ≈L976–1185 first, including the
#1080 guard ≈L1147–1160, and port its surviving verify/guard semantics into the
new arm rather than re-deriving them):**

- [ ] **A0 — shared path definition:** new
  `skills/update-zskills/scripts/init-state.sh` defining (and ONLY here)
  `ZSKILLS_INIT_DONE_REL=".zskills/init-done"`,
  `ZSKILLS_SETUP_CONFIRMED_REL=".zskills/setup-confirmed"`, plus
  `zskills_init_done_present()` / `zskills_write_init_markers()` (atomic:
  tmp+mv; init-done CONTENT = `version: <zskills version>` + `date:` lines —
  this doubles as the version record for config-less consumers, read by the
  Phase 5 ZSKILLS_VERSION fallback). Writer fences, gate, greeting,
  verify-install, and ALL fixtures source THIS file (Invariant 6). ALSO in
  this item: retarget the Phase 5 `zskills-resolve-config.sh` ZSKILLS_VERSION
  fallback's temporary `.zskills/init-done` literal to source `init-state.sh`
  and use `$ZSKILLS_INIT_DONE_REL` (closes the #1132 re-type window Phase 5
  documented). `init-state.sh` ALSO defines the **frozen legacy-residue
  detection constants** (and ONLY here — see end-state item 3's carve-out):
  the D20 sentinel prefix literal (`zskills-materialised:`), the
  `.zskills/config-seeded-notice` path, the list of the 5 project-side
  paths the retired materialiser ever wrote, AND the **frozen legacy seed
  shape** (the exact value-bearing key/value set the pre-redesign
  materialiser's config seed wrote — same frozen-residue family as the
  sentinel: residue detection must match what old releases ACTUALLY wrote,
  never a live `zskills-defaults.json` derivation, which drifts as defaults
  evolve) — all commented as
  legacy-residue-detection-only, consumed by A1.5. These constants survive
  Phase 7's sentinel retirement BY DESIGN (upgraded consumers carry residue
  forever). **Literal-string discipline:** the frozen literals appear NOWHERE
  outside `init-state.sh` (and its mirror twin) in any live file — including
  prose and comments; every other surface (A1.5 fences, SKILL.md prose,
  fixtures, this plan's later phases) refers to them REFERENTIALLY ("the D20
  sentinel prefix constant", `$ZSKILLS_LEGACY_*`), never by re-typed literal.
- [ ] **A1 — route:** bare `/zs:update-zskills` on a plugin-lane consumer
  (CLAUDE_PLUGIN_ROOT context / no legacy mirror): if `init-done` present → run
  the update behaviors (A1.5 residue cleanup; refresh rules per R-branch;
  **conditional config offer** — when no `.claude/zskills-config.json` exists
  AND A1.5 did not just remove one THIS run (a consumer who accepted the
  seeded-config removal has chosen zero-config; immediately re-offering
  creation would contradict the choice — the offer stays available on a LATER
  bare run), offer creation via the same A3 interview, honoring the A3
  non-interactive
  skip, so A3's "a later interactive run can still offer config via the update
  path" promise is real; re-run verify-install; refresh the version line in
  init-done) and stop; if absent → init sequence A1.5 + A2–A7
  in order. The legacy-lane bare-call behavior is UNCHANGED. The W6.1 refuse arm
  (explicit `install` on a plugin consumer → refuse) SURVIVES with its
  switch-in-progress carve-out UNTOUCHED in this phase (carve-out dies in
  Phase 7 with the marker).
- [ ] **A1.5 — materialiser-residue cleanup (runs on BOTH the init arm and the
  update arm, BEFORE A2; the sentinel is the safe-to-delete discriminator):**
  upgraded (materialiser-era) consumers otherwise keep stale artifacts FOREVER
  — sentinelled `.claude/agents` twins shadowing/duplicating plugin agents
  (Claim-1 twin-precedence row), a stale managed.md double-delivering under
  R-b's guard, and residue contradicting Overview item 2.
  - **Sentinelled-artifact removal (unconditional, deterministic):** for each
    of the 5 legacy materialiser paths (constants from `init-state.sh`): if
    the file exists AND carries the D20 `zskills-materialised:` sentinel →
    delete it. User-owned and legacy-lane-installed files never carry the
    sentinel and are NEVER touched. On branches that re-create some of these
    at init (1B agents, T-C hook, R-c managed.md), A1.5 runs FIRST and A4/A5
    write fresh copies.
  - **Seeded-config cure (M8):** when `.zskills/config-seeded-notice` exists
    AND `.claude/zskills-config.json` matches the untouched legacy seed shape:
    offer
    removal — "this config was auto-seeded by the old installer and never
    customized; remove it and run on built-in defaults?" **Comparison spec
    (round 3):** compare ONLY the value-bearing seed keys, EXCLUDING
    `zskills_version`, `project_name`, and `$schema` — the materialiser stamps
    `zskills_version` AFTER seeding (it is not in any defaults JSON) and bakes
    a per-project `project_name`, so a naive whole-shape comparison would
    NEVER match genuine residue and route every untouched seed to "user
    customized". The reference shape is the FROZEN legacy seed shape constant
    from `init-state.sh` (A0) — residue detection, same family as the frozen
    sentinel — NOT a live `zskills-defaults.json` derivation. Accept → delete
    config + schema sibling + the notice. Decline (or non-interactive, or
    shape-mismatch = user customized it) → KEEP the config as user-owned and
    delete the notice anyway (post-Phase-7, the offer never repeats — W6.3
    no-nag lesson — and deletion of a removed config sticks because no
    materialiser re-seeds; see the mid-window caveat below for why neither
    holds before Phase 7).
  - **Mid-window caveat (known transient, converges at Phase 7 — same family
    as A3's):** during the Phase 6a→Phase 7 window the materialiser is still
    live and its `safe_to_write` treats ABSENT as writable — so on the
    primary branches (1A agents, T-A/T-B hook, R-b managed.md) every
    sentinelled artifact A1.5 deletes is re-materialised at the next
    SessionStart, and an accepted config removal is re-seeded with the notice
    re-touched, so the offer RE-FIRES next run. Only init-written
    UN-sentinelled copies are loop-free (1B agents, T-C hook, R-c managed.md
    — the materialiser refuses to clobber sentinel-less non-empty files).
    A1.5's cleanup therefore re-pollutes per session mid-window and becomes
    permanent only when Phase 7 deletes the materialiser. Document this in
    the CHANGELOG entry; do NOT edit the materialiser to avoid it
    (zero-edits constraint), and do not treat the re-pollution as an A1.5
    defect during Phase 6a/6b validation.
  - Print what was removed in the init/update summary (A7).
- [ ] **A2 — gitignore-first:** append the umbrella `.zskills/` entry to the
  project `.gitignore` — lift the `migrate-paths.sh` ≈L1077–1116 pattern
  verbatim in spirit: idempotent append (skip if an equivalent entry already
  covers), then VERIFY with `git check-ignore -v .zskills/probe` and detect a
  negative-override (`!`) that defeats it → STOP with a human-readable message
  (do not write init-done). Legacy consumers upgrading later get the same append
  via their normal update path — add the same idempotent append to the legacy
  update flow (small Step C-region item) so both lanes converge on the umbrella
  entry.
- [ ] **A3 — optional config interview:** within the PLUGIN-LANE INIT ARM
  ONLY, gate the interview on `init-done` ABSENT (today Step 0.6 gates on
  config-absent, which the materialiser seed defeated). **Lane scoping is
  load-bearing:** Step 0.6 sits ABOVE Step 0.7's lane check and runs on BOTH
  lanes — a bare "re-gate Step 0.6 on init-done" would make every legacy
  `/update-zskills` run re-enter the interview (legacy never has init-done),
  violating Invariant 10. Implement the init-done gate inside the 0.7 init arm
  (or as a plugin-lane-conditional inside 0.6); the legacy lane's Step 0.6
  keeps its existing config-absent gate byte-untouched. Offer config creation;
  on accept, write
  `.claude/zskills-config.json` with the seed shape derived from the canonical
  `zskills-defaults.json` (Phase 4 — no re-typed dict;
  `landing: direct` — settled #1120 — `main_protected: false`,
  `agents.min_model: auto`, ...), atomic write,
  NEVER-clobber an existing file; copy the schema sibling and stamp
  `zskills_version` (reuse the existing F.5-region scripts) ONLY when the config
  file exists. On decline: write NOTHING (defaults flow from the Phase 5
  cascade; version lives in init-done). **Mid-window materialiser-seeded
  config (known transient, dies in Phase 7):** during the Phase 6a→Phase 7 window the
  still-live materialiser seeds a config at the FIRST session start, so by the
  time init runs, a config usually already exists. Handle explicitly: when a
  config is present, the interview becomes "a config already exists (it may
  have been auto-seeded) — review/keep it"; accept = keep (never clobber),
  decline = leave it in place (init never deletes a config). A mid-window
  consumer therefore cannot reach the zero-config end state until Phase 7 —
  document as known-transient in the CHANGELOG entry, do NOT edit the
  materialiser to avoid it (zero-edits constraint).
  **Non-interactive arm:** in a headless/non-interactive context the interview
  is SKIPPED entirely — no config written, defaults assumed, init proceeds to
  A4 (a later interactive `/zs:update-zskills` run can still offer config via
  the update path).
- [ ] **A4 — branch-dependent artifact writes (Claims 1/2/6):** on **1A + T-A/T-B**:
  none — this step is a no-op (the zero-files goal). On **1B**: copy
  `${CLAUDE_PLUGIN_ROOT}/.claude/agents/{verifier,implementer}.md` → project
  `.claude/agents/` (atomic, never-clobber-newer — port the materialiser's
  #1079 atomic-write + 0-byte self-heal logic ≈L261–290). **1B + T-A/T-B
  coupling hazard:** project-side agents DO honor frontmatter hooks, and the
  source agents' `hooks:` block points at
  `$CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh` — which only T-C
  writes. A verbatim copy on T-A/T-B would exit-127 on every verifier/
  implementer Bash call. So: when T ∈ {T-A, T-B}, A4 STRIPS the frontmatter
  `hooks:` block from the copies (symmetric to Phase 2's 1A strip; Layer-0
  comes from hooks.json) — add a strip-verification test case to A8's suite.
  On **T-C**: copy verbatim WITH the `hooks:` block and additionally copy
  `${CLAUDE_PLUGIN_ROOT}/hooks/inject-bash-timeout.sh` → project
  `.claude/hooks/`. Spec ALL combinations in the SKILL.md prose as
  branch-conditional fences keyed on the recorded Phase 1 Findings (the landed
  text implements only the selected branch; the unselected branch's spec lives
  in this plan, not in shipped prose).
- [ ] **A5 — rules delivery step (R-branch):** R-b: no-op (hook delivers). R-a:
  write `~/.claude/rules/zskills.md` (atomic, overwrite, generated-by header).
  R-c: render `.claude/rules/zskills/managed.md` project-side via the D24
  renderer.
- [ ] **A6 — verify:** run verify-install. **Phasing (round 3 — the rework
  lands in Phase 6b item C):** in THIS phase A6 invokes verify-install
  REPORT-ONLY (non-blocking, results printed in the init summary) — the
  pre-rework plugin-section checks are sentinel-era and would FALSE-FAIL a
  healthy init right after A1.5 removes sentinelled artifacts, wedging init in
  a delete→fail→re-materialise loop. Phase 6b's item C flips A6 to the hard
  gate: a verify-install failure STOPS init (no init-done written; consumer
  re-runs after fixing). State the report-only interim in this phase's report.
- [ ] **A7 — lock-LAST:** `zskills_write_init_markers()` writes
  `setup-confirmed` + `init-done` (in that order, both atomic). Print the
  post-init footprint summary (exactly what was created).
- [ ] **A8 — port the materialiser's test assertions** (research: suite
  `test-sessionstart-materialise.sh` ≈L168–238, 301–360, 371–448 is the ONLY
  coverage of the #1136/#1137/#1079 behaviors): new
  `tests/test-update-zskills-init.sh` covering — gitignore idempotent-append +
  negative-override STOP; config never-clobber; atomic/0-byte-heal on the
  marker writes; abort-mid-init leaves NO init-done and NO partial poison
  (re-run succeeds); init-done content carries version; ordering oracle
  (gitignore verified BEFORE any other write — model on
  `test-update-zskills-agent-install.sh`'s `run_step_c` step-extraction
  pattern); **A1.5 cleanup cases** — sentinelled artifact removed,
  UN-sentinelled (user-owned) file at the same path NEVER removed,
  seeded-config+notice fixture → removal offer semantics (accept deletes
  config+schema+notice; decline keeps config, deletes notice; shape-mismatch
  keeps config), notice consumed exactly once, **and an anti-#1132-mask case:
  a seeded-config fixture stamped with a FOREIGN `zskills_version` (and an
  arbitrary `project_name`) must still MATCH the untouched-seed shape and be
  offered for removal — pins the excluded-keys comparison spec so a fixture
  built from the same derived shape as the comparator can never mask the
  real-residue mismatch.** Cleanup fixtures derive the
  sentinel prefix + paths + legacy seed shape by sourcing `init-state.sh`'s
  legacy-residue
  constants, never a re-typed literal (#1132). Register in run-all +
  suite-registry (triplet, one commit).

### Design & Constraints

- This phase deliberately leaves BOTH setup paths alive (materialiser +
  init); the gate is not yet re-keyed (Phase 6b). Mid-window behavior of the
  A1.5 cleanup and the A3 interview is documented in their known-transient
  caveats — re-pollution per session is expected, not a defect.
- `tests/test-update-zskills-lane-aware.sh` (344 lines): the W6.1 refuse cases
  (AC5a/AC5b-region — post-BD-removal shape) must still pass UNCHANGED in this
  phase; the bare-call-arm cases get reworked to the init flow. The ~60% that
  dies with the switch machinery dies in Phase 7, not here.
- Do NOT touch: the materialiser (zero edits this phase); the
  switch scripts/marker/carve-out; `detect-install-state.sh` (at all — Phase 6b
  ADDs env-context evidence, Phase 7 owns removals); the
  `block-unmaterialised-skill.sh` gate (Phase 6b); verify-install internals
  beyond A6's report-only invocation (Phase 6b); D16 shim; seed-dict in the
  materialiser (the Phase 5 congruence net already
  pins it to `zskills-defaults.json`; the A3 interview seed reads that JSON
  directly, so no new congruence arm is needed here).
- update-zskills gets ONE version bump per commit covering the A edits
  (Invariant 1).
- **Sizing — TWO commits, each independently green (Invariant 5):**
  (1) A0 + A1 + A1.5 + A2 + A3 with the
  matching `test-update-zskills-init.sh` cases; (2) A4–A7 + the remaining A8
  cases. The lockstep pairs named above never split across these commits.

### Acceptance Criteria

- [ ] Scratch mirror-less install (shape (b)): full init transcript — gitignore
  entry appended + check-ignore verified, interview offered, markers written
  LAST (attended-step protocol applies — Execution context). **Footprint
  check is DELTA-scoped, not exact-set (the materialiser is
  still live this phase — any pre-init session writes its artifacts + seeded
  config before init can run):** snapshot `git status --porcelain` +
  `find .zskills .claude -maxdepth 2` immediately BEFORE running init and
  again AFTER; the DELTA must be exactly the init-created set (gitignore
  umbrella entry, `.zskills/{init-done,setup-confirmed}`, optional
  config+schema if accepted, plus selected fallback-branch deltas) **plus the
  A1.5 REMOVALS of enumerated-materialiser-set files inside the snapshot
  window (deletions of sentinelled artifacts / the seeded config + schema +
  notice are the cleanup WORKING, not a delta violation — list them as
  expected removals)** and nothing
  else. Files from the ENUMERATED materialiser set (post-Phase-3: verifier.md,
  implementer.md, inject-bash-timeout.sh, managed.md, seeded config+schema,
  `.zskills/config-seeded-notice`) may pre-exist the snapshot and are excluded
  from the check. The EXACT Overview item-2 footprint demo moves to Phase 9 §C
  (post-Phase-7, materialiser deleted — there it is satisfiable and is
  asserted exactly).
- [ ] Abort-mid-init case: kill init between A2 and A7 in the test harness → no
  init-done, re-run completes cleanly.
- [ ] Legacy lane: `test-update-zskills-agent-install.sh` passes (in its
  Phase-3-edited form — not "unchanged"; Phase 3 retargeted its
  verify-response-validate expectations) and the W6.1 refuse cases pass
  unchanged.
- [ ] `bash tests/run-all.sh` passes — state the command and per-suite results
  with pass counts.

### Dependencies

Phases 2 (artifact delivery for A4 branches), 4 (rules delivery for A5), 5
(cascade for A3's decline path).

---

## Phase 6b — Gate retarget + verify-install rework

### Goal

Retarget the `UserPromptExpansion` gate onto `.zskills/init-done` with the
#1132 single-path-definition discipline, rework verify-install's plugin section
into the redesign's own acceptance vehicle (and flip Phase 6a's A6 to the hard
gate), and run the live both-branch gate validation. One commit. The
materialiser and switch machinery still exist (Phase 7 deletes them).

### Work Items

**B. Gate retarget (`hooks/block-unmaterialised-skill.sh`, 100 lines):**

- [ ] Re-key: blocks `^zs:` invocations of STATE-WRITING skills when
  `zskills_init_done_present()` is false (sourcing `init-state.sh` via
  `${CLAUDE_PLUGIN_ROOT}` with BASH_SOURCE self-location fallback, #1046–48
  idiom). Keep the `UserPromptExpansion` event and the cure exemption —
  `zs:update-zskills` ALWAYS allowed (#1121→#1128: the chokepoint stays
  deterministic per-invocation).
- [ ] **Allow-list** (settled shape — allow these, block everything else
  pre-init): `briefing`, `session-report`, `plans`, `manual-testing`,
  `update-zskills`. Everything else — including `run-plan`, `fix-issues`, `do`,
  `commit`, `land-pr`, `create-worktree`, `draft-plan`, `draft-tests`,
  `refine-plan`, `research-and-plan`, `research-and-go`, `work-on-plans`,
  `investigate`, `fix-report`, `verify-changes`, `cleanup-merged`, `qe-audit`,
  `zskills-dashboard` — is blocked (each writes state: markers, branches, audit
  files, monitor state). New skills default to blocked (fails safe).
- [ ] **Legacy-mirror allow:** when the legacy mirror is present (the
  `detect-install-state.sh` 23-name anchor evidence — call the script, do not
  re-implement), ALLOW unconditionally — a mirrored repo is initialised by
  definition, and this is what keeps dogfood (`--plugin-dir` + mirror) working
  without a magic `.zskills/init-done` in this repo.
- [ ] Friendly block message: `zskills needs one-time setup — run
  /zs:update-zskills, then re-run your command.` (exact wording may be refined;
  must name the cure command).
- [ ] **Tests — `tests/test-block-unmaterialised-skill.sh` (122 lines) rekey:**
  fixtures create/remove the marker by SOURCING `init-state.sh` and using its
  writer function (never a re-typed path — #1132). Cases: block-when-absent for
  a state-writing skill; allow-when-present; allow-list members pass pre-init;
  cure (`zs:update-zskills`) passes pre-init; legacy-mirror allow; **wrong-key
  regression** — a fixture with the OLD sentinel-bearing
  `.claude/agents/verifier.md` but NO init-done is still BLOCKED (the old key
  no longer unlocks).
- [ ] **Allow/block-list conformance tripwire:** new section in
  `tests/test-skill-conformance.sh` asserting every `skills/<name>` appears in
  EITHER the gate's allow-list OR a block-acknowledged list maintained beside
  it (in the hook or a sibling fixture) — so adding a new skill without
  consciously categorizing it fails CI with a message naming the choice. The
  gate itself still fails safe (unlisted ⇒ blocked); the tripwire exists
  because a read-only new skill silently blocking pre-init would otherwise
  ship with no signal.
- [ ] **Live validation, BOTH branches (#1132 — the allow path has NEVER been
  run live):** in a scratch mirror-less install (shape (b)): (1) pre-init, a
  `zs:`-prefixed state-writing invocation is blocked with the friendly message;
  (2) run `/zs:update-zskills`, then the SAME invocation passes. Attended —
  the **attended-step protocol (Execution context) applies**: under `/run-plan`
  dispatch the implementer STOPs with this as an ATTENDED-PENDING observable;
  it never simulates either branch (fixture runs are NOT live validation).
  Record transcript excerpts in the phase report.
- [ ] Bump the hook's line-2 stamp. NO `.claude/hooks/` mirror exists for this
  hook (plugin-lane-only, in the parity EXCLUDE list) — do not create one.

**C. verify-install rework (`skills/update-zskills/verifiers/verify-install-lib.sh`,
693 lines — plugin-lane section ≈L475–560 is built on the dying sentinels):**

- [ ] Replace the plugin-section checks with: plugin reachable
  (CLAUDE_PLUGIN_ROOT/skills resolvable), `init-done` + `setup-confirmed`
  present (via `init-state.sh`), gitignore covers `.zskills/`
  (`git check-ignore`), config VALID-if-present (schema check; absent is OK by
  design), rules delivered per R-branch (R-b: hook registered in the plugin's
  hooks.json; R-a: user rules file exists + version header current; R-c:
  managed.md present), and branch-dependent artifacts (1B/T-C files present
  when those branches are selected). ALSO a **version-currency WARN** (m-class
  staleness cure): compare `init-done`'s `version:` line against
  `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`'s `version`; on mismatch
  WARN and point at a bare `/zs:update-zskills` run (the A1 update arm
  refreshes the line) — a config-less consumer's version record is otherwise
  permanently stale after marketplace updates, since nothing re-runs init.
  `vi_detect_lane` re-key: plugin evidence =
  CLAUDE_PLUGIN_ROOT/env context; mirror evidence unchanged. **Do not remove
  the sentinel/lock evidence rules from `detect-install-state.sh` itself in
  this phase** — only ADD the env-context evidence (the switch machinery still
  consumes detect until Phase 7; subtractive edits ride with the deletions).
  Note: the region rework kills the OLD plugin-section
  `plugin.mirror-less` WARN text (≈L525), which recommends the soon-deleted
  `scripts/switch-install-path.sh` — any surviving mirror-present WARN in the
  new section must recommend the uninstall-one-install-the-other model
  instead, never the switch script. (The sibling switch-script mention at
  ≈L664, `lane.dual-unsupported`, sits OUTSIDE this region and is owned by
  Phase 7 commit 2's lockstep.)
- [ ] **Flip Phase 6a's A6 to the hard gate** (same commit as the lib rework):
  the init flow's A6 verify step goes from report-only (Phase 6a interim) to
  STOP-on-failure (no init-done written; consumer re-runs after fixing) — now
  safe because the reworked plugin-section checks are init-keyed, not
  sentinel-keyed. SKILL.md prose edit + an A8-suite case asserting a failing
  verify-install blocks the lock write.
- [ ] `tests/test-verify-install.sh` (735 lines) REWORK in lockstep: the plugin
  fixtures rebuild around init-state markers; **the anti-hollow property is
  load-bearing** — keep (or add) explicit broken-install fixtures that must
  FAIL verify-install (missing init-done; gitignore overridden; 1B branch:
  missing agents file). A verify-install that can no longer fail is a defect.

### Design & Constraints

- Both setup paths (materialiser + init) are still alive. The gate keyed on
  init-done plus the legacy-mirror allow means: a
  materialiser-era plugin consumer who updates mid-window gets BLOCKED until
  they run `/zs:update-zskills` once — acceptable and self-curing (the message
  names the cure); note it in the CHANGELOG entry.
- Do NOT touch: the materialiser (zero edits this phase); the
  switch scripts/marker/carve-out; `detect-install-state.sh` evidence REMOVALS
  (this phase only ADDs env-context evidence);
  D16 shim; seed-dict in the materialiser; the Phase 6a init flow beyond the
  named A6 hard-gate flip.
- update-zskills gets ONE version bump covering the C edits (+ the A6 flip)
  this commit (Invariant 1); the gate hook gets its line-2 stamp bump.
- **Sizing — ONE commit** (the former Phase-6 commit 3): B (gate) + C
  (verify-install) with their suites; the live gate validation rides it. The
  lockstep pairs named above never split.

### Acceptance Criteria

- [ ] Both gate branches validated live (block message verbatim; allow after
  init) — transcript excerpts in the report (attended-step protocol applies —
  Execution context; simulated evidence is a verifier FAIL).
- [ ] Wrong-key regression case passes (old sentinel does not unlock).
- [ ] verify-install anti-hollow demonstrated: each named broken-install
  fixture FAILs it; a healthy init-era fixture passes; the A6 hard-gate case
  (failing verify-install blocks the init-done write) passes.
- [ ] `bash tests/run-all.sh` passes — state the command and per-suite results
  with pass counts.

### Dependencies

Phase 6a (init-state.sh, the init flow, and the A8 suite all exist; the gate
and verify-install key on its markers).

---

## Phase 7 — Deletions: materialiser, lane-switch complex, sentinels

### Goal

Delete the machinery the previous phases replaced — materialiser, switch
complex, D27 probe, D20 sentinels, W6.2 marker — with every hard-fail-on-delete
lockstep pair inside the deleting commit, and the subtractive
`detect-install-state.sh` simplification. May be 2–3 commits (materialiser /
switch complex / sentinel sweep), each independently green.

### Work Items

**Commit 1 — materialiser:**

- [ ] `git rm hooks/session-start-materialise.sh`. SAME COMMIT, all of:
  - `hooks/hooks.json`: remove the SessionStart materialiser entry. Replace
    with the slim **greeting hook** `hooks/session-start-greeting.sh`
    (read-only, zero writes): when `init-done` absent AND legacy mirror absent
    (source `init-state.sh` + the detect mirror-evidence), emit the
    `systemMessage` greeting pointing at `/zs:update-zskills` (USER channel —
    #1088/#1089); silent otherwise. Sources the D16 shim (Gap 2). On branch
    R-b, fold the greeting into Phase 4's `session-rules-context.sh` instead of
    a second hook — ONE SessionStart entry total — but ONLY if Claim 3's
    combined-envelope sub-probe showed one envelope delivers BOTH
    `additionalContext` and `systemMessage`; if not, keep two SessionStart
    entries. Pick per the landed R branch + that sub-probe and say which in
    the report. W6.3 lesson: the greeting fires every
    pre-init session by design (it's curable, not a nag-loop); it goes silent
    permanently after init.
  - `test-plugin-hooks-integrity.sh` Gap 1 (hooks.json entry enumeration) +
    Gap 2/3 updates — including dropping `session-start-materialise.sh` from
    `SHIM_EXCLUDE` (≈L108; the greeting/rules hook sources the shim, so it is
    NOT excluded).
  - **The two suites that EXECUTE the materialiser unconditionally (run-all
    ≈L121, ≈L378 — they hard-fail the moment the file is gone, so their rework
    rides THIS commit, not commit 3):**
    `tests/test-synthetic-consumer-install.sh` ≈L444 (`MAT=` + its
    materialiser arms — prune/retarget onto the init-era flow) and
    `tests/test-broken-python3-stub-e2e.sh` ≈L156 (flow (a) runs the
    materialiser — retarget onto the surviving python consumers:
    greeting/rules hook or init). The broken-python3 suite arrives in its
    Phase-3-edited 4-artifact form (the 5→4 lockstep);
    `test-synthetic-consumer-install.sh` was NOT edited by Phase 3 (its
    ≈L444 block greps the materialiser's dual-install WARN sites — no
    artifact-count assertion, but the grep hard-fails on the deleted file).
    This commit owns both suites' materialiser-DELETION rework.
  - `tests/test-zskills-paths.sh` ≈L51: comment references the materialiser —
    sweep the reference (comment-only edit).
  - Conformance presence list ≈L240–252: remove the materialiser + its
    artifacts' entries (verify which of ≈L240–252 name materialised artifacts
    vs plugin-tree files — only the former die).
  - Conformance seed-dict extraction ≈L2364–2420: DELETE the
    materialiser-extraction side, and with it the Phase 5 congruence net's
    arm (ii) (seed-dict ≡ `zskills-defaults.json` — subject-removal rationale
    in the commit message). Arm (i) (bash family-1/2 defaults ≡
    `zskills-defaults.json`) survives untouched; the interview seed reads the
    JSON directly and never needed an arm.
  - `tests/test-hook-helper-drift.sh` ≈L125,135: remove the materialiser entry
    from `RESOLVE_PYTHON_CONSUMERS` (the sed hard-fails on a missing file).
  - Tests: `git rm tests/test-sessionstart-materialise.sh` (assertions ported
    in Phase 6a A8 — verify the port list in that phase's report BEFORE
    deleting; any unported assertion gets ported NOW into
    `test-update-zskills-init.sh`),
    `tests/test-sessionstart-materialise-overwrite-guard.sh`,
    `tests/test-sessionstart-dual-install-detect.sh` (D27 — subject-removal).
    REWORK `tests/test-sessionstart-greeting.sh` (170 lines) onto the slim
    greeting hook (greeting survives — retarget, don't delete). run-all.sh
    registrations + suite-registry SAME COMMIT (triplets).
  - `tests/test-inject-bash-timeout-parity.sh`: delete the sentinel-half
    (materialised-copy comparison — subject-removal); keep any
    source↔`.claude/hooks` mirror half.
  - mirror-parity exclusion lists (`tests/test-hooks-mirror-parity.sh`
    `EXCLUDE_BASENAMES` ≈L41 + the test-hooks sub-suite analogue): drop the
    materialiser basename; ADD `session-start-greeting.sh` (plugin-lane-only,
    no `.claude/hooks/` mirror — only if the greeting lands as its own hook,
    i.e. not folded on R-b).

**Commit 2 — switch complex:**

- [ ] `git rm scripts/switch-install-path.sh scripts/migrate-strip-settings.py docs/guides/switching-install-lanes.md tests/test-switch-install-path.sh`.
  SAME COMMIT:
  - `scripts/build-catalog.sh` ≈L114 hard-codes
    `docs/guides/switching-install-lanes.md` in `SECTION_ORDER` (rank-only,
    runtime-harmless — but it is a named reference to a deleted file): remove
    the entry, THEN `bash scripts/build-catalog.sh` + commit the regenerated
    `docs/DocsRegistry.js` (the guide page leaves the catalog;
    `test-doc-viewer-catalog.sh` byte-diffs committed vs fresh).
  - run-all.sh registration + suite-registry for the deleted suite.
  - **D16 shim MESSAGE edit (this commit's ONLY shim change — see the narrowed
    Do-NOT-touch below):** `hooks/_lib/plugin-hook-skip-if-mirrored.sh` ≈L160's
    skew-defer message tells the consumer to run
    `bash scripts/switch-install-path.sh --to-plugin` (deleted THIS commit)
    or `/update-zskills install` (refused on a plugin consumer). The commit-2
    sweep pattern does not match `switch-install-path`, but the Phase 7 AC /
    Overview item-3 grep DOES — without this edit the AC is unsatisfiable.
    Rewrite the recommendation tail to the new model (e.g. "…deferring to
    settings.json copy. Update your zskills install (uninstall one lane,
    reinstall the other — see the install guide).") — the phrase `deferring
    to settings.json copy` MUST survive verbatim (the only test pin:
    `test-plugin-hook-skip-on-double-register.sh` ≈L134). Bump the shim's
    line-2 `# zskills-hook-version:` stamp; refresh any mirror twin per the
    parity suites, same commit.
  - **verify-install dual-lane message (same lockstep family as the shim
    edit):** `skills/update-zskills/verifiers/verify-install-lib.sh` ≈L664 —
    the `lane.dual-unsupported` FAIL message also recommends
    `scripts/switch-install-path.sh` (deleted THIS commit). It sits OUTSIDE
    the plugin section Phase 6b's C reworked (whose ≈L525 sibling mention died
    there), so it survives to here — rewrite its recommendation to the
    uninstall-one-install-the-other prose, mirror via
    `bash scripts/mirror-skill.sh update-zskills`, and fold into this commit's
    update-zskills version bump (the SKILL.md preset-arm deletion below
    already requires one).
  - `tests/test-hook-helper-drift.sh`: remove the switch-script
    `RESOLVE_PYTHON_CONSUMERS` entry.
  - `skills/update-zskills/SKILL.md`: delete the
    `--switch-install-path` preset arm (≈L1065–1084) and the W6.1
    switch-in-progress carve-out (≈L1060–1063) — the refuse arm becomes
    unconditional (its surviving prose ≈L989–1015/-region updated). Version
    bump + mirror.
  - `tests/test-update-zskills-lane-aware.sh`: the switch-related ~60% dies
    (subject-removal); the refuse cases SURVIVE and now assert the
    carve-out-less behavior (a present `.zskills/switch-in-progress` file no
    longer bypasses the refuse — add that as a regression case).
  - Sweep `.zskills/switch-in-progress` and `.claude/zskills-install-lane`
    references: `grep -rn 'switch-in-progress\|zskills-install-lane' --exclude-dir=docs skills/ .claude/skills/ hooks/ .claude/hooks/ scripts/ tests/ CLAUDE.md CLAUDE_TEMPLATE.md` → fix every hit
    this commit (docs hits belong to Phase 9) — EXCEPT
    `hooks/_lib/detect-install-state.sh` ≈L67 (the `zskills-install-lane`
    lock-evidence rule): that edit is owned by COMMIT 3's detect rework, not
    this sweep; leave it and note the deferral in this commit's message
    (single owner — no double-assignment).
  - `scripts/migrate-paths.sh` interplay: Step 0.1 migrate-paths is UNAFFECTED
    (settled) — verify it has no switch references; leave it alone.

**Commit 3 — sentinels + detect simplification:**

- [ ] D20 sentinel retirement: remove the `zskills-materialised:` convention —
  `grep -rn 'zskills-materialised' --exclude-dir=docs .` and fix every live
  hit EXCEPT the deliberate survivors: `init-state.sh`'s frozen legacy-residue
  constants (+ mirror twin). The A1.5 cleanup fences and fixtures are
  SOURCERS/READERS of those constants — per Phase 6a A0's literal-string
  discipline they carry no literal of their own and thus never appear in this
  grep; if one DOES appear, that is a discipline violation to fix (replace the
  re-typed literal with the constant), not a survivor to whitelist. The
  cleanup must recognize residue from pre-redesign releases forever
  (end-state item 3 carve-out). All other hits die:
  `detect-install-state.sh` sentinel evidence rules,
  `.claude/agents/*.md` / root `agents/*.md` stamped lines if any checked-in
  copy carries one (strip the line; agents parity test updated same commit),
  remaining test fixtures, AND the renderer's sentinel machinery:
  `scripts/render-managed-rules.py` `SENTINEL_PREFIX` (≈L36–39) + the
  `--sentinel` flag (≈L77–78) die, with
  `tests/test-render-managed-rules-correctness.sh`'s sentinel arm (fixture 4,
  ≈L101–106) deleted in the same commit (subject-removal) — re-derive its
  legacy callers (`grep -rn 'sentinel' skills/update-zskills/ scripts/`) and
  drop the `--sentinel` argument from every surviving render call site.
- [ ] `detect-install-state.sh` (`hooks/_lib/`, 204 lines) subtractive rework:
  evidence = legacy mirror (23-name anchor ≈L111) + settings.json hooks (keep)
  + CLAUDE_PLUGIN_ROOT env context (added in Phase 6b); lock-file (≈L67 —
  deferred here from commit 2's sweep, single owner) and sentinel rules
  DELETED. Surviving callers (gate, verify-install, init refuse arm)
  re-smoked.
- [ ] `.zskills/config-seeded-notice`: the WRITER died with the materialiser —
  sweep stale readers (`grep -rn 'config-seeded-notice' .`) EXCEPT the Phase 6a
  A1.5 seeded-config cure: the literal lives ONLY in `init-state.sh`'s
  constant (+ mirror twin); the cleanup fence and A8 fixtures are
  sourcers/readers of that constant and reference it referentially. That
  reader chain IS the cure for residue on upgraded consumers and
  survives by design (end-state item 3 carve-out). Only readers that predate
  A1.5 and serve no cure purpose are removed.
- [ ] `tests/test-plugin-live-load.sh` ≈L183–227, ≈L422–461: rework the
  materialiser-era expectations (artifact-write observables) into init-era ones
  (zero writes at session start; greeting envelope shape). KEEP the suite's
  harness layers — they are Phase 1/9's tooling.
- [ ] (`tests/test-broken-python3-stub-e2e.sh` and
  `tests/test-synthetic-consumer-install.sh` rework moved to COMMIT 1 — they
  execute the materialiser unconditionally and would fail any commit that
  deletes it without them.) Here: `tests/canary-verifier-*.sh`: confirm
  Phase 2's retargets still hold with the materialiser gone.

### Design & Constraints

- EVERY deletion commit must be independently green (Invariant 5) — the
  lockstep lists above are the minimum same-commit sets; if a run surfaces
  another hard dependency, it JOINS the commit (and the report lists it), the
  deletion never splits from its dependents.
- BD-plan interplay: `scripts/switch-install-path.sh` was edited by the BD
  plan's Phase 3 (`is_shipped_skill`); deleting it now is strictly fine.
- Do NOT delete or restructure the D16 shim MECHANISM or its Gap-2 machinery
  (12+ hooks still source it; the skip/skew logic is load-bearing for dogfood
  dual-load) — commit 2's message-TEXT edit is the only permitted shim change.
  Also do not touch: legacy `.claude/agents` frontmatter; `migrate-paths.sh`;
  historical surfaces; CLAUDE.md/README prose (Phase 9 — EXCEPT where a
  deleted file is named in a LIVE instruction that would now error; defer
  prose to Phase 9 and list such hits in the report).

### Acceptance Criteria

- [ ] `test ! -e hooks/session-start-materialise.sh && test ! -e scripts/switch-install-path.sh && test ! -e scripts/migrate-strip-settings.py && test ! -e docs/guides/switching-install-lanes.md` hold.
- [ ] The Overview item-3 machinery grep, scoped to non-doc surfaces
  (`skills/ .claude/ hooks/ scripts/ tests/ agents/ .claude-plugin/`), returns
  0 files beyond item 3's named survivors (the `init-state.sh` legacy-residue
  constants + their sourcing fixtures; root docs cleaned in Phase 9).
- [ ] Greeting: scratch plugin install pre-init shows the systemMessage; after
  init, silent (live, attended — ride the Phase 9 DEV-QUAL if scheduling
  demands, but say so).
- [ ] `bash scripts/build-catalog.sh` → zero registry drift after the commit.
- [ ] Legacy lane suites green and unchanged in behavior.
- [ ] `bash tests/run-all.sh` passes — state the command and per-suite results
  with pass counts.

### Dependencies

Phases 2–6b (every replaced function live before its provider is deleted).

---

## Phase 8 — Root-turd consolidation into .zskills/

### Goal

Move the three root state files into `.zskills/` — `.landed` →
`.zskills/landed`, `.worktreepurpose` → `.zskills/worktreepurpose`,
`.zskills-tracked` → `.zskills/tracked` — writers flag-day (this phase), readers
dual-read (new path, then old), with the documented hazard items specced.
Counts below are inventory-era — **re-derive every touch list by grep before
editing** (`grep -rln '\.landed\b' .`, etc.).

### Work Items

**A. Writers (flag-day — all in this phase, new paths only):**

- [ ] `skills/commit/scripts/write-landed.sh` ≈L43–44 — THE sole `.landed`
  writer (one edit covers all pipelines): target `.zskills/landed`; `mkdir -p`
  the dir first.
- [ ] `skills/create-worktree/scripts/create-worktree.sh` ≈L354
  (`.zskills-tracked`) + ≈L361 (`.worktreepurpose`) → `.zskills/tracked`,
  `.zskills/worktreepurpose`.
- [ ] Orchestrator heredocs/writes: `CLAUDE_TEMPLATE.md` ≈L223–233 (Worktree
  Rules `.landed` heredoc + its safety check — re-render `managed.md` SAME
  commit; note this heredoc was already touched by Phase 4's TIMEZONE token),
  `skills/do/modes/pr.md` ≈L230,308, `skills/run-plan/modes/cherry-pick.md`
  ≈L151, `skills/run-plan/modes/execute-phase.md` ≈L200,252 (also the
  `.zskills-tracked` write ≈L252 and `rm` ≈L1792),
  `skills/fix-issues/modes/cherry-pick.md` ≈L75,
  `skills/fix-issues/modes/direct.md` ≈L151.
- [ ] **One-shot main-root migrate at init:** add to Phase 6a's init sequence
  (between A2 and A7; before the lock): if `$CLAUDE_PROJECT_DIR/.zskills-tracked`
  exists at the MAIN repo root, `mv` it to `.zskills/tracked` — main root ONLY;
  NEVER walk or mutate sibling worktrees from init. (.landed/.worktreepurpose
  live in worktrees, which init never touches — dual-read covers them for
  their lifetime.)

**B. Readers (dual-read: try new path, fall back to old; every touched reader
gets a dual-path test case):**

- [ ] `skills/commit/scripts/land-phase.sh` (verified home — the `commit`
  skill bundles the landing script; canary pin pairing below is correct):
  the hard gate ≈L28–34 + the marker handling ≈L91–122, AND the
  `EPHEMERAL_FILES` array ≈L61 — **pinned VERBATIM by
  `tests/test-canary-failures.sh` ≈L203–210: array edit and canary pin in ONE
  commit** (add the new basenames; KEEP the old ones during the window).
- [ ] **Worktree-removal hazard (must land with the writer flag-day):**
  untracked files block `git worktree remove`, and after the move the
  worktree's `.zskills/` DIR holds the markers; agent-typed
  `rm -rf <wt>/.zskills` is BLOCKED by the recursive-rm fence
  (`block-unsafe-PROJECT.sh` ≈L600–606 — note: PROJECT, not generic; CLAUDE.md
  misattributes, fixed in Phase 9). Resolution: `land-phase.sh` owns the
  worktree `.zskills/` directory cleanup internally (script internals are
  invisible to the command-token hook). Add an explicit cleanup step + test.
- [ ] `skills/run-plan/scripts/post-run-invariants.sh` ≈L175–178;
  `skills/briefing/scripts/briefing.py`
  (**27 hits**, not ~12 — add a `_marker_path(root, name)` helper that probes
  new-then-old, ONE definition); dashboard `collect.py` ≈L1073 + `app.js`;
  `hooks/block-unsafe-project.sh` ≈L885, 1000, 1064 (Tier-1 pipeline reads ×3)
  **+ regenerate its D4 `.template` sibling SAME commit** (stamp bump + mirror);
  `skills/verify-changes/SKILL.md` ×4 fences; `skills/fix-report/SKILL.md`
  ≈L160,272,354–419; `skills/session-report/SKILL.md` ≈L76;
  `skills/run-plan/SKILL.md` ≈L908.
- [ ] **Inventory completion (round-1 review: the grep returns ~42 live files —
  every one below was MISSING from the lists above; re-derive and adjudicate
  each, dual-read for readers / prose-update for prose):**
  `skills/land-pr/SKILL.md` (≈L184–187, ≈L1003–1040 + its status table) + its
  `references/caller-loop-pattern.md` and `references/failure-modes.md`;
  `skills/commit/modes/land.md` + `modes/pr.md`; `skills/do/SKILL.md` +
  `modes/worktree.md`; `skills/fix-issues/modes/pr.md` + `modes/sprint.md`;
  `skills/run-plan/modes/direct.md` + `modes/pr.md` +
  `references/failure-protocol.md` + `references/finish-mode.md` +
  `subcommands/stop-next-status.md`; `skills/create-worktree/SKILL.md` +
  `scripts/sanitize-pipeline-id.sh`; `skills/briefing/SKILL.md`;
  `skills/update-zskills/SKILL.md` + `stubs/post-create-worktree.sh` (a
  CONSUMER stub — installed copies never auto-update; note the dual-read
  window explicitly in the stub comment); `scripts/land-pr-bypass-message.sh`;
  `hooks/_lib/resolve-effective-worktree-root.sh` (stamp bump + mirror).
- [ ] `hooks/block-main-edits.sh` ≈L198–201 allowlist: new paths are ALREADY
  covered by the `.zskills/*` arm (verify, don't assume); KEEP the old arms
  during the window; message ≈L217–219 updated. Stamp bump + mirror.
- [ ] **Fence-calculus check (`tests/test-hooks-misc.sh` ≈L52–66):** the
  current assertion that `rm -f .zskills-tracked` is ALLOWED (because the old
  path is NOT under `.zskills/`) inverts in spirit after the move. VERIFY the
  fence's actual predicate first (research: it blocks RECURSIVE deletion of
  `.zskills` subtrees; a plain `rm -f .zskills/tracked` carries no recursive
  flag and passes) — then rewrite the case to assert the NEW truth:
  `rm -f .zskills/tracked` allowed, `rm -rf .zskills` blocked, old-path
  `rm -f .zskills-tracked` still allowed during the window. If verification
  contradicts the research (plain rm under `.zskills/` IS blocked), STOP and
  surface — the consolidation design needs a fence carve-out decision, which is
  a plan amendment, not an implementer call.
- [ ] `tests/zskills-tracked-allowlist.txt`: rename ripple — re-derive its
  consumers (`grep -rln 'zskills-tracked-allowlist' tests/`) and update
  name/content coherently.
- [ ] Test fixtures: ~26 files' mechanical updates (re-derive:
  `grep -rln '\.zskills-tracked\|\.worktreepurpose\|\.landed' tests/`) +
  `tests/lib/hooks-harness.sh` fixtures; per-reader dual-path cases (new-path
  hit; old-path fallback hit; new wins when both exist).
- [ ] `.gitignore` (dev repo): add/verify the umbrella `.zskills/` entry; KEEP
  the 3 root-turd lines during the window (file a follow-up issue to retire
  dual-read + the old gitignore lines + the old allowlist arms after 2–3
  releases — note the issue number in the report; retirement is OUT of this
  plan).
- [ ] Skill version bumps for every touched skill (re-derive the set; expect at
  least: `commit`, `create-worktree`, `do`, `run-plan`, `fix-issues`,
  `verify-changes`, `fix-report`, `session-report`, `briefing`, `land-pr`,
  `update-zskills`, `zskills-dashboard`) + hook stamp bumps + mirrors +
  managed.md re-render.

### Design & Constraints

- **Writers new-only, readers dual-read** — never the reverse (a dual-WRITE
  would double the turds; an old-only reader would miss new markers).
- Correction baked from research: `cleanup-merged` does NOT read `.landed` —
  do not "fix" it. The recursive-rm fence matches any `.zskills` substring →
  new paths are auto-protected with ZERO fence edits.
- `.landed` semantics in CLAUDE.md/worktree rules ("does `<wt>/.landed`
  exist") are PROSE updated in Phase 9; the heredoc fences here are the LIVE
  writers and move now.
- Do NOT touch: tracking-marker paths under `.zskills/tracking/` (already
  consolidated, different subsystem); `block-unsafe-generic.sh` (the fence
  lives in -project); the dual-read retirement (follow-up issue).

### Acceptance Criteria

- [ ] A full worktree pipeline round-trip in the test harness (create →
  tracked/worktreepurpose under `.zskills/` → land → `.zskills/landed` written
  → worktree removable with land-phase's internal cleanup) passes.
- [ ] Dual-read proven: a fixture worktree with OLD-path markers only is still
  read correctly by land-phase gate, briefing, and block-unsafe-project (one
  case each).
- [ ] `grep -rn 'EPHEMERAL_FILES' tests/test-canary-failures.sh` pin matches
  the edited array verbatim.
- [ ] Writers' grep: `grep -rn '> *"?\$?[A-Za-z_/{}".]*\.landed\b' skills/ scripts/ CLAUDE_TEMPLATE.md`
  (and the `-tracked`/`worktreepurpose` analogues — craft the actual patterns
  against the real fences) shows no remaining old-path WRITERS; readers may
  still name old paths (dual-read arms).
- [ ] Fence-calculus case asserts the verified truth (or the phase STOPPED and
  surfaced — see work item).
- [ ] `bash tests/run-all.sh` passes — state the command and per-suite results
  with pass counts.

### Dependencies

Phase 6a (init exists for the one-shot migrate step). Independent of Phase 7 in
content; ordered after so deletion commits stay reviewable.

---

## Phase 9 — Docs, release/dogfood, DEV-QUAL, final sweep

### Goal

Rewrite every doc that describes the old install model, fix the known dangling
references, add the superseded-note, rebuild the catalog, run the mirror-less
DEV-QUAL against a built release tree, and sweep the whole tree against the
Overview's falsifiable end state.

### Work Items

**A. Root agent docs:**

- [ ] **`CLAUDE.md`:** rewrite the Architecture bullets (materialiser, lane
  files) and the three lane paragraphs (≈L20/22/24 — "plugin-lane mental
  model", "Two install lanes", "Dual-path dogfooding"): the new model is —
  plugin lane = zero-write sessions + explicit `/zs:update-zskills` init +
  plugin-native agents/hooks/rules per the landed branches; legacy lane
  unchanged; dogfooding = permanent dual-load via D16 shim, `--plugin-dir`
  iteration loop unchanged; lane SWITCHING section replaced by
  "uninstall one, install the other" prose. Rewrite the Verifier-cannot-run
  Layer-0 mechanism paragraph to the landed T branch; rewrite the
  Skill-versioning frontmatter-compose paragraph per the landed agents branch
  (on 1A, plugin-lane verifier commits are gated by hooks.json project hooks,
  not frontmatter-composition — describe what is true); update the
  Verifier-cannot-run section's **Layer-3 path literal**
  (`.claude/hooks/verify-response-validate.sh` ≈L123 → the relocated
  skills-script form — Phase 3's AC grep deliberately excluded CLAUDE.md;
  THIS item is the literal's named owner); fix the Tracking-markers
  fence ATTRIBUTION (the recursive-rm fence lives in `block-unsafe-project.sh`,
  not generic — research correction); update the `.landed` prose (≈L107 region
  + Worktree Rules references) to `.zskills/landed` with a dual-read-window
  note.
- [ ] **`RELEASING.md`:** rewrite the release-flow section for the new tree
  (agents/ staging on 1A; no switch scripts); **FIX the dangling "Dogfooding
  lanes" cross-ref** — CLAUDE.md ≈L22 cites a RELEASING.md section that does
  not exist; re-home a real "Dogfooding lanes" section (the `--plugin-dir`
  loop, the D16 dual-load reality, the mirror-less validation recipe) and
  point the CLAUDE.md citation at it.
- [ ] **`CLAUDE_TEMPLATE.md`:** residual prose only (tokens died in Phase 4,
  heredoc moved in Phase 8) — Tracking Enforcement prose updated to
  `.zskills/tracked`; re-render + managed-md test.

**B. User docs (rebuild catalog after — `bash scripts/build-catalog.sh`, commit
the registry):**

- [ ] `docs/guides/installing-zskills.md` ≈L19–68, 127–142, 158–181, 199–203:
  plugin install = marketplace add + install + run `/zs:update-zskills` once;
  the zero-write default; what init creates; the optional config; **recommend
  PROJECT-scoped plugin enablement** and state the user-scope trade per the
  Claim-3 enablement-scope Findings row (Phase 4 scope acceptance — under a
  user-scope install the rules context + greeting fire in every project).
- [ ] `docs/guides/zskills-config.md` ≈L47, 298, 325 + NEW cascade section
  (project > user > built-ins, per-key; the family-3 safety carve-out AND the
  family-5 inline-reader carve-out — state plainly that **`execution.*` keys
  are project-tier-only and never cascade from the user tier**;
  `~/.claude/zskills-config.json` examples).
- [ ] `docs/guides/README.md` ≈L17 (drop the switching-guide entry — the file
  died in Phase 7; verify the catalog already reflects it), `README.md`
  ≈L47–91, 157–158 (install story).
- [ ] `docs/skills/update-zskills.md`: references `switch-install-path`
  (deleted in Phase 7) — rewrite to the uninstall-one-install-the-other prose.
- [ ] **Docs sweep for the OLD root-turd paths (Phase 8 moved the writers; the
  docs still teach the old paths):** `docs/tracking/TRACKING_NAMING.md` (the
  AUTHORITATIVE naming doc — must teach `.zskills/tracked` with a dual-read
  window note), `docs/skills/create-worktree.md`,
  `docs/evals/REBASE_CONFLICT_CANARY.md` — re-derive the full set with
  `grep -rln '\.zskills-tracked\|\.worktreepurpose\|\.landed\b' docs/ README.md`
  and adjudicate every hit (historical surfaces per Invariant 11 stay).
- [ ] `DEV-QUAL.md`: rework the 17 switch-scenario hits into the new scenario
  set — fresh mirror-less install; init; gate block/allow; legacy lane
  regression; (1B/T-C) artifact-write checks.
- [ ] `docs/plans/PLUGIN_DISTRIBUTION.md`: add the superseded-framing NOTE
  (precedent: its line-12 W6.4 note) naming this plan; do NOT rewrite the body
  (Invariant 11).

**C. Release + DEV-QUAL (attended — the attended-step protocol from the
Execution context applies to every item here: under `/run-plan` dispatch the
implementer STOPs with the ATTENDED-PENDING list; simulated DEV-QUAL evidence
is a verifier FAIL):**

- [ ] Build the prod-stripped tree (`bash scripts/build-prod.sh` to a temp
  target) and the plugin release tree; verify agents/ staging (1A) and the
  absence of every deleted file in BOTH outputs (`test ! -e` each).
- [ ] **Mirror-less DEV-QUAL (Invariant 8):** `claude plugin marketplace add`
  the built tree as a path in a sandbox config; install into a fresh scratch
  repo; run the end-state item-1 zero-write session check (including a
  verifier dispatch with a >120s Bash call — Layer-0 live, Invariant 7); run
  `/zs:update-zskills`; verify the exact item-2 footprint (**this is THE
  exact-footprint demonstration** — deferred here from Phase 6a, whose AC was
  delta-scoped because the materialiser was still live there); gate block→allow;
  greeting appears→goes silent; rules visible to the model (R-branch
  landmark). Record every observable in the phase report.
- [ ] **Upgraded-consumer DEV-QUAL (the residue path — a fresh scratch repo can
  NEVER exercise it):** fabricate a materialiser-era consumer fixture (the 5
  sentinelled artifacts + seeded config + schema +
  `.zskills/config-seeded-notice` — derive the sentinel/paths from
  `init-state.sh`'s legacy-residue constants, or produce them by running the
  pre-Phase-7 materialiser from a historical checkout), install the NEW built
  release over it, run `/zs:update-zskills`, and verify: every sentinelled
  artifact removed (A1.5), the seeded-config offer fired with the documented
  semantics, the notice consumed, and the post-init footprint equals the
  item-2 exact set. Record observables in the phase report.
- [ ] Legacy-lane DEV-QUAL: `/update-zskills` in a scratch consumer still
  installs/updates identically (spot-check: mirror, hooks, agents with
  frontmatter, managed.md render, gitignore umbrella append on update).

**D. Final sweep:**

- [ ] Run the Overview item-3 grep verbatim — EMPTY (quote the command + output).
- [ ] Judgment sweep for the CONCEPTS:
  `git ls-files -z | xargs -0 grep -nirE 'materialis|dual.install|lane.switch|install.lane' -- 2>/dev/null | grep -vE '^(docs/plans/|docs/reports/|docs/issues/|CHANGELOG\.md:|\.pre-paths-migration)'`
  — adjudicate EVERY hit individually (expected legitimate survivors: D16 shim
  comments describing dual-LOAD dogfooding; init refuse-arm prose about
  mirrored consumers; `init-state.sh`'s frozen legacy-residue constants and
  their legacy-residue-detection-only comments (+ mirror twin);
  `skills/update-zskills/SKILL.md`'s A1.5 cleanup prose, which necessarily
  describes materialiser-era residue by concept (+ mirror twin); this plan's
  own exclusion set). Anything else gets fixed
  with full bump/mirror discipline.
- [ ] Stale-behavior sweep: `grep -rn 'session start' docs/ README.md CLAUDE.md`
  -class claims that still describe materialise-at-session-start; adjudicate.
- [ ] Tracker completion: all phases ✅ with commit hashes + one-line notes.
- [ ] Final report: deletions (by tree), branch selections recap, files edited
  by category, skills bumped, hooks stamped, the follow-up issues filed
  (dual-read retirement; any deferred residue), and the historical surfaces
  deliberately untouched.

### Design & Constraints

- DocsRegistry is build output — never hand-edit; byte-diff gate applies.
- Docs phases do not bump skill versions UNLESS a sweep hit lands inside a
  skill dir — then full Invariant-1 discipline, no "it's just one word".
- The DEV-QUAL is the plan's last line of defense against the dogfood-mask —
  it runs against the BUILT tree via marketplace install, never `--plugin-dir`,
  never this repo.

### Acceptance Criteria

- [ ] Overview end-state items 1–4 each demonstrated with quoted command output
  (zero-write session; exact footprint; machinery grep empty; legacy
  spot-check) — §C demonstrations recorded per the attended-step protocol
  (real attended transcripts, never simulated).
- [ ] Both built trees verified (agents present per branch; deleted files absent).
- [ ] Catalog: `bash scripts/build-catalog.sh` → zero drift post-commit.
- [ ] `bash tests/run-all.sh` passes — state the command and EVERY suite's
  result with pass counts; name any skipped suite and why.

### Dependencies

All prior phases.

---

## Plan Quality

Drafted via /draft-plan: consolidated research → draft → adversarial review
rounds (senior reviewer + devil's advocate per round, findings deduped via an
overlap map) → refiner pass per round.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1 | R1–R12 | F1–F14 | 22 unique post-dedup (26 raw − 4 overlaps); 22/22 resolved |
| 2 | REV-1–REV-6 | DA-F1–DA-F14 | 19 unique post-dedup (20 raw − 1 overlap); 19/19 resolved |
| 3 | REV-1–REV-6 | DA-F1–DA-F8 | 12 unique post-dedup (14 raw − 2 overlaps); 12/12 resolved |

(Round-1/2 counts re-verified against the round files in the final pass: the
round-1 file's header said "20" but enumerates 22 unique findings — C1, M1–M9,
m1–m12; the round-2 file's header said "16" but enumerates 19 — C1–C2, M1–M8,
m1–m9. The enumerations, all resolved, are authoritative.)

Convergence: **Converged at round 3 (max budget): rounds 1–2 resolved 41
unique findings incl. 3 CRITICAL; round-3 findings (12) were spec-tightenings
with no structural rework beyond the Phase 6 → 6a/6b sizing split, all
applied. Remaining concerns: none open.**
