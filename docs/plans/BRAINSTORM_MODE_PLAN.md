---
title: Brainstorm mode for /draft-plan
created: 2026-05-31
status: active
---

# Plan: Brainstorm mode for /draft-plan

## Overview

Add an opt-in **`brainstorm`** mode to `/draft-plan`. Inspired by the
[superpowers](https://github.com/obra/superpowers) `brainstorming` skill, it runs a
collaborative, multi-turn dialogue with the user to flesh out a rough idea *before* the
existing adversarial pipeline runs — asking one focused question at a time, proposing 2–3
approaches with trade-offs, applying ruthless YAGNI, and **offering to build quick
throwaway demos** (a live browser "visual companion", or a static screenshot) to visualize
ideas and progress. The dialogue proceeds until the user confirms they're ready, at which
point the brainstorm output becomes a rich design seed that flows into the existing
Phase 1 research → Phase 6 finalize pipeline.

The behavior lives in a new `skills/draft-plan/references/brainstorm.md` that the skill
**Reads only when the `brainstorm` flag is present** — progressive disclosure, since most
`/draft-plan` invocations won't use it and shouldn't pay its context cost. This is
`/draft-plan`'s first `references/` split (it is currently a single 809-line `SKILL.md`),
following the `/session-report handoff` (#848) and `/quickfix` (#849) context-window
pattern. It does NOT split `/draft-plan` into sub-skills — single entry point preserved.

**Why this needs a plan (not a thin wrapper):** brainstorm adds a genuinely new interactive
dialogue loop, a throwaway-demo lifecycle with worktree-pollution and process-lifecycle
hazards, an interactive-only gate, and a feed-forward into the research phase — multiple
integration points and hook interactions. Per `feedback_draftplan_for_new_skills`, exactly the
design surface that warrants adversarial review up front.

### Settled semantics (decided with the user, do not re-litigate)

- **Flag form:** a positional `brainstorm` token (modes are positional per the CLAUDE.md
  flag convention; dashed `--flags` are reserved for safety-gate overrides).
- **`brainstorm` + `auto` = "brainstorm then auto-land."** At an interactive top-level
  invocation, the dialogue runs first; after the user confirms, the existing `AUTO_FLAG`
  path carries Phase 6 through `/land-pr` auto-merge. `auto` does NOT suppress the dialogue
  at top level. (This intentionally supersedes the research summary's earlier
  "auto disables brainstorm" recommendation — the user chose interactive-then-land.)
- **Brainstorm is a top-level-only interactive feature; no parent-skill changes are needed.**
  Per the user (2026-05-31), `/research-and-plan` and `/research-and-go` will NOT pass a
  `brainstorm` token when they delegate `/draft-plan`, so the automated/headless path simply
  never sets the flag — there is nothing to defend against at the parent. We therefore do NOT
  modify the parent skills. As cheap, non-load-bearing insurance against the one edge case
  where a delegated sub-problem description happens to contain the standalone word
  "brainstorm", draft-plan additionally requires `ZSKILLS_PIPELINE_ID` to be empty before
  entering the dialogue (a one-line inline check, draft-plan-only). If a future need arises to
  let parents request brainstorm explicitly, the parent-side plumbing can be added then.
- **Demos default toward the live browser companion** (superpowers' common case), with the
  static screenshot as the lighter "sometimes" path — per the user's steer.
- **Dialogue uses plain conversation text, never `AskUserQuestion`** (settled framework
  prohibition, `skills/update-zskills/SKILL.md:701`: "Do NOT use AskUserQuestion. Ask in
  plain conversation text").

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Author references/brainstorm.md | ⬚ | | |
| 2 — Wire brainstorm into SKILL.md + parent-skill guards | ⬚ | | |
| 3 — Tests, version bumps, mirrors, conformance | ⬚ | | |

---

## Phase 1 — Author references/brainstorm.md

### Goal
Create `skills/draft-plan/references/brainstorm.md` — the complete, self-contained dialogue
protocol the orchestrator follows when brainstorm mode is active, including a fully-specified
demo lifecycle and the durable notes/feed-forward contract.

### Work Items
- [ ] Create `skills/draft-plan/references/brainstorm.md` (source tree).
- [ ] Document the **8-step dialogue protocol** (below).
- [ ] Document the **visual-companion / quick-demo lifecycle** with the EXACT serve idiom,
      pidfile-based lifecycle, and screenshot idiom (below) — no hand-waving.
- [ ] Document the **durable notes file** (`/tmp/draft-plan-brainstorm-$TRACKING_ID.md`) and
      the **feed-forward** (inject into research-agent prompts).
- [ ] Document the **transition signal** (agent-offered checkpoint + explicit confirm).
- [ ] Document the **reconciliations** (no `AskUserQuestion`; options in prose; no sub-agent
      dispatch in the dialogue; no `TZ=America/New_York` literal — use `${TIMEZONE:-UTC}`).
- [ ] Bump `skills/draft-plan/SKILL.md` `metadata.version` and re-mirror to
      `.claude/skills/draft-plan/` (creating this file changes the skill-content hash).

### Design & Constraints

**Slug pinning (load-bearing for feed-forward).** All three `/tmp` artifacts derive the slug
from the SAME `$TRACKING_ID` the SKILL.md preamble computes at `skills/draft-plan/SKILL.md:85`
(`basename "$OUTPUT_FILE" .md | tr A-Z a-z | tr _ -`). Use it verbatim — do NOT recompute a
slug from the description, or the feed-forward silently misses:
- notes: `/tmp/draft-plan-brainstorm-$TRACKING_ID.md`
- demos: `/tmp/draft-plan-demo-$TRACKING_ID/`
- research (existing): `/tmp/draft-plan-research-$TRACKING_ID.md`

All `/tmp` paths are ABSOLUTE — required because the brainstorm stage runs after the worktree
preamble, so cwd is the worktree; a relative demo/notes path would write into the worktree.

**Dialogue protocol** (adapted from superpowers' 9-step `brainstorming` flow, re-grounded for
zskills — superpowers writes a committed design doc and hands off to `writing-plans`; here the
terminal artifact is the `/draft-plan` plan file, so the brainstorm produces a `/tmp` notes
seed that feeds Phase 1 research instead of a committed spec):

1. **Open: restate + light context.** Reflect the user's seed idea back in 1–2 sentences.
   Worktree + `$OUTPUT_FILE`/`$TRACKING_ID` are already resolved by the preamble, so defer
   heavy repo exploration to Phase 1 research; read only what's needed to ask good questions.
2. **Offer a visual companion as its OWN standalone message** (superpowers pattern) — only
   when upcoming exploration involves visual content (UI, layout, diagrams, flows). The
   message contains nothing but the offer + a one-line description of what would be shown,
   and requests consent. Skip entirely for non-visual ideas.
3. **Ask clarifying questions ONE per message.** Most-fundamental first (problem / user /
   success), then mechanics and naming. When a question has natural choices, **offer them in
   plain prose** ("Option A: …; Option B: …; I lean toward A because …") — never the
   `AskUserQuestion` tool.
4. **Propose 2–3 approaches with trade-offs + an explicit recommendation** at each real fork.
5. **Apply ruthless YAGNI / gentle pushback.** Surface hidden costs and simpler alternatives
   as questions. This is the soft in-dialogue cousin of the Phase-3 review — it does not
   replace it.
6. **Capture decisions as they're made** into the notes file — each with rationale, plus
   rejected alternatives and open questions.
7. **Offer the transition checkpoint** when open questions are exhausted: "I think we've got
   enough to draft a plan — start the adversarial design review, or keep exploring?" Require
   an **affirmative confirm**. Ambiguous → ask once more. **Never keyword-auto-detect "ready"**.
8. **On confirm:** finalize the notes file as a structured design summary, then return control
   to SKILL.md (Phase 2 wires the return + the redundant-checkpoint skip).

**Quick-demo lifecycle — EXACT idioms (the worktree-safety + process-lifecycle load-bearing
rules; the round-1 review found the previous version under-specified and factually wrong about
screenshot paths and ports):**

- **All demo files live under `/tmp/draft-plan-demo-$TRACKING_ID/`, NEVER inside the
  worktree.** Phase 6 finalize stages ONLY the plan `.md` via a `FILE_REL` guard and `exit 1`s
  if any other file is staged (`skills/draft-plan/SKILL.md:640-645`); a worktree-resident demo
  would dirty the tree and confuse `/land-pr`.

- **Live browser visual companion (the common/default case).** Write a self-contained HTML
  file (inline CSS/JS, no external assets) under `/tmp/draft-plan-demo-$TRACKING_ID/`, then
  serve that dir on an **OS-assigned free port** (NOT `port.sh` — that returns the same
  per-worktree-deterministic port the dev server uses, so reusing it would collide with a
  running dev server; an ephemeral port avoids all collisions). Use Python's stdlib http
  server (Python is a hard zskills dependency; this avoids any consumer-specific serve literal
  and the uncustomized `start-dev.sh` stub). Capture the chosen port AND the PID to a **pidfile**
  (the Bash tool does not persist shell state across calls, so an in-memory `$!` is lost — a
  pidfile is mandatory). Spec the idiom literally in the file, e.g.:
  ```bash
  PYTHON=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
  DEMO_DIR="/tmp/draft-plan-demo-$TRACKING_ID"
  # Serve on an OS-assigned free port; write "PID PORT" to a pidfile for later clean stop.
  "$PYTHON" - "$DEMO_DIR" > "$DEMO_DIR/.serve.url" 2>&1 <<'PY' &
  import http.server, socketserver, os, sys, functools
  os.chdir(sys.argv[1])
  h = functools.partial(http.server.SimpleHTTPRequestHandler)
  with socketserver.TCPServer(("127.0.0.1", 0), h) as s:
      print(f"http://127.0.0.1:{s.server_address[1]}/", flush=True)
      s.serve_forever()
  PY
  echo "$! " > "$DEMO_DIR/.serve.pid"
  ```
  Give the user the URL (read from `$DEMO_DIR/.serve.url`) to open and interact with; iterate
  the HTML in place and tell them to refresh.
- **Stopping the server (NEVER `kill -9`/`killall`/`pkill`/`fuser -k`; never
  `lsof -ti | xargs kill`).** Read the PID from `$DEMO_DIR/.serve.pid` and `kill "$PID"`
  (SIGTERM that specific PID only) at brainstorm exit, or leave it for the user to stop.
  Because demos live in `/tmp`, a stranded server does not dirty the worktree and cannot
  block `/land-pr`; still, stop it on a clean exit for tidiness.

- **Static screenshot (the "sometimes" lighter case).** Use `playwright-cli screenshot` on a
  `file://` URL pointing at the demo HTML, **without `--filename`** (per the managed-rule:
  this saves into the configured, gitignored `.playwright/output/` dir, which is invisible to
  git — `.gitignore:20` ignores `.playwright/*`). **Do NOT move or rename the screenshot into
  the tracked worktree** (that is the actual pollution hazard — the file is safe only while it
  stays in the gitignored dir). Show the user the image from `.playwright/output/`. If
  playwright-cli errors on environment, check `.devcontainer/setup.sh` first
  (`feedback_check_devcontainer_before_bailing`).

- **Default toward the live companion** when the user benefits from interaction; use the
  screenshot for fast static conceptual shots. State this preference explicitly in the file.
- Demos are throwaway and never committed; optionally `rm -rf "/tmp/draft-plan-demo-$TRACKING_ID"`
  on brainstorm exit.

**Durable notes file + feed-forward (the round-1 review found the seam was wrong — the research
file is the post-dispatch CONSOLIDATION, written AFTER the agents are dispatched at
`skills/draft-plan/SKILL.md:202`, so notes cannot be "added to the research file" before
agents read it):**

- Maintain `/tmp/draft-plan-brainstorm-$TRACKING_ID.md`, updated after each decision — mirrors
  the skill's existing `/tmp/draft-plan-research-$TRACKING_ID.md` compaction-survival pattern
  (`SKILL.md:222-228`). Accumulate: refined problem statement, decisions + rationale, rejected
  alternatives, open questions, pointers to demo screenshots/URLs.
- **Feed-forward mechanism (pinned):** at transition, the notes file path is injected into
  EACH Phase 1 research agent's PROMPT, with an instruction to read it as the primary design
  seed (Phase 2 of this plan wires the SKILL.md side). The post-dispatch consolidation then
  incorporates both the agents' findings and the brainstorm notes. This is hybrid — the
  Codebase / Patterns / Prior-art agents STILL run to ground the design against the actual
  repo; the Domain agent's "what to build" work is largely pre-answered and may be reduced to
  verification. The brainstorm does NOT skip research.

**Reconciliations with zskills rules (state them in the file so future editors don't
re-litigate):**
- **No `AskUserQuestion`** (`skills/update-zskills/SKILL.md:701`: "Do NOT use AskUserQuestion.
  Ask in plain conversation text"). superpowers "prefers multiple choice" → here, options
  offered in plain prose.
- **No sub-agent dispatch in the dialogue.** The loop and demo-building are INLINE orchestrator
  work; the dialogue dispatches no agents, so it adds no `Agent`-tool requirement beyond the
  existing Preflight and needs no `subagent_type` pin. (Forward constraint: if a future
  revision dispatches an agent to build a demo, it MUST pin `subagent_type: "implementer"` and
  never Haiku.)
- **No forbidden literals in this file** (it IS a skill file, in deny-list scope): no
  `TZ=America/New_York` (use `${TIMEZONE:-UTC}` via `zskills-resolve-config.sh` if a timestamp
  is needed), no `npm run test:all`, `npm start`, `$TEST_OUT/.test-results.txt`, or the
  skill-version regex inside exec fences without an `<!-- allow-hardcoded: … reason: … -->`
  marker. The Python-http-server + ephemeral-port + `file://`-screenshot design deliberately
  references none of the six config-resolution variables, so no positive-side fence-local
  config-sourcing is triggered; if a future fence references one, source the helper in/above it.

**Authoring constraint:** script-source references use the two-lane dual-path form (try
`${CLAUDE_PLUGIN_ROOT}/skills/...` first, fall back to `$CLAUDE_PROJECT_DIR/.claude/skills/...`).

**Version bump + mirror (per-phase, mandatory).** `/run-plan` commits each phase and the
PreToolUse `block-stale-skill-version.sh` hook fires on every `git commit`; creating
`references/brainstorm.md` changes the skill-content hash, so this phase's commit MUST carry a
bumped `metadata.version`. The implementer runs (in their own shell — NOT copied into any
skill file; `docs/plans/` is out of the forbidden-literals deny-list scope, verified at
`tests/test-skill-conformance.sh:2144`, so this `TZ=` is safe here):
```bash
TODAY=$(TZ=America/New_York date +%Y.%m.%d)
HASH=$(bash scripts/skill-content-hash.sh skills/draft-plan)
bash scripts/frontmatter-set.sh skills/draft-plan/SKILL.md metadata.version "$TODAY+$HASH"
bash scripts/mirror-skill.sh draft-plan
```
Verify mirror parity before committing.

### Acceptance Criteria
- [ ] `skills/draft-plan/references/brainstorm.md` exists and documents all 8 dialogue steps,
      both demo paths, the notes-file contract, the transition signal, and the reconciliations.
- [ ] Demo HTML + notes use absolute `/tmp/...$TRACKING_ID...` paths; the file states demos
      live ONLY in `/tmp` and are never committed, with the `FILE_REL`-guard rationale.
- [ ] The live-companion serve idiom is written literally: Python stdlib server on an
      OS-assigned free port, PID+URL captured to a pidfile under the demo dir, stopped via
      `kill "$PID"` (no `kill -9`/`pkill`/`lsof|xargs kill`).
- [ ] The screenshot idiom omits `--filename` (lands in gitignored `.playwright/output/`) and
      the file explicitly forbids moving/renaming the screenshot into the tracked worktree.
- [ ] The file forbids `AskUserQuestion`, forbids keyword-auto-detecting "ready", and forbids
      `TZ=America/New_York` (and the other forbidden literals).
- [ ] The feed-forward is specified as "inject the notes-file path into each research agent's
      prompt," NOT "append to the research file before dispatch."
- [ ] No bash fence in the file trips the forbidden-literals deny-list or the positive-side
      fence-local config-sourcing check.
- [ ] `bash scripts/skill-content-hash.sh skills/draft-plan` equals the committed
      `metadata.version` hash; `.claude/skills/draft-plan/` mirror parity holds.

### Dependencies
None — foundational content. SKILL.md does not yet load it; an inert reference file is a
harmless intermediate commit state.

---

## Phase 2 — Wire brainstorm into SKILL.md

### Goal
Make `skills/draft-plan/SKILL.md` detect the `brainstorm` flag, gate it to interactive
top-level runs, conditionally Read `references/brainstorm.md`, inject the brainstorm seed into
Phase 1 research-agent prompts, skip the now-redundant post-research checkpoint, and advertise
the flag. No parent-skill changes (per the user: `/research-and-plan` / `/research-and-go` will
not pass `brainstorm`).

### Work Items
- [ ] Add a dedicated `BRAINSTORM_FLAG` detection fence (separate from `AUTO_FLAG`).
- [ ] Add `brainstorm` to the recognized-flag set in the description-extraction prose
      (`SKILL.md:133-147`) and the worktree-preamble token loop (`SKILL.md:69-85`) so the word
      is stripped from the description.
- [ ] Add the **conditional-load** prose (new "Brainstorm mode" stage between Pre-check and
      Phase 1), gated on `BRAINSTORM_FLAG=1` plus the cheap `ZSKILLS_PIPELINE_ID`-empty check.
- [ ] Wire the **feed-forward** (inject notes-file path into research-agent prompts) and the
      **post-research checkpoint skip** in brainstorm mode.
- [ ] Update `argument-hint` (`SKILL.md:4`) to include `[brainstorm]`.
- [ ] Bump `skills/draft-plan/SKILL.md` `metadata.version` + re-mirror.

### Design & Constraints

**Flag detection** (a SEPARATE fence beside `AUTO_FLAG`, `SKILL.md:148-153`, so it cannot
perturb the `AUTO_FLAG=0 … fi` awk extraction the args-smoke test relies on):
```bash
BRAINSTORM_FLAG=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[bB][rR][aA][iI][nN][sS][tT][oO][rR][mM]($|[[:space:]]) ]]; then
  BRAINSTORM_FLAG=1
fi
```
Whitespace-anchored + case-insensitive → does NOT match `brainstorming`/`brainstormed`/
`brainstorms`, and won't collide with `output`/`rounds`/`.md`/`auto`. Add `brainstorm` to the
preamble token strip and the recognized-flag list so it is removed from the description string.

**Delegation gate (simplified per the user — no parent-skill changes).** The parents
(`/research-and-plan`, `/research-and-go`) will not pass a `brainstorm` token, so the automated
path never sets the flag and there is nothing to strip at the parent. The only residual edge is
a delegated sub-problem description that happens to contain the standalone word "brainstorm"
(`/research-and-plan` composes `/draft-plan output <path> <sub-problem description>$AUTO_ARG`,
`research-and-plan/SKILL.md:136`). To keep brainstorm strictly interactive-top-level and make a
headless dialogue-hang structurally impossible at near-zero cost, the gate is:

> Brainstorm runs iff `BRAINSTORM_FLAG=1` **AND** `[ -z "${ZSKILLS_PIPELINE_ID:-}" ]`, the
> latter read INLINE in the gate fence (the same inline-read pattern the skill already relies
> on at `SKILL.md:192`; a delegated run has `ZSKILLS_PIPELINE_ID` set by the parent).

This is a one-line, draft-plan-only check — cheap insurance, not load-bearing (the load-bearing
fact is "parents don't pass brainstorm"). No verification of env-propagation reliability is
required to ship: if `ZSKILLS_PIPELINE_ID` is reliably set when delegated, the check is exact;
if it isn't, the worst case is the already-accepted "parents don't pass brainstorm" guarantee,
unchanged. Result: at an interactive top-level run, `brainstorm` (with or without `auto`) enters
the dialogue; delegated runs proceed normally without it.

**Conditional-load prose** (follow `/session-report handoff`, `session-report/SKILL.md:28-35`).
A new section immediately after Pre-check (`SKILL.md:174`), before Phase 1:
> ## Brainstorm mode (only when the `brainstorm` flag is present)
> If `BRAINSTORM_FLAG=1` AND `ZSKILLS_PIPELINE_ID` is empty (interactive top-level run, not a
> `/research-and-plan`/`/research-and-go` delegation), **Read
> [references/brainstorm.md](references/brainstorm.md)** via the Read tool and execute its
> dialogue loop now, before Phase 1. Otherwise (`BRAINSTORM_FLAG=0`, or the run is
> delegated/headless), **ignore the reference file entirely** and proceed straight to Phase 1.

Shared vars (`$OUTPUT_FILE`, `$TRACKING_ID`, `$AUTO_FLAG`, the slug) are already set and survive
into the loaded reference via the persistent orchestrator context.

**Feed-forward + checkpoint skip:**
- In brainstorm mode, the Phase 1 research dispatch (`SKILL.md:200-220`) includes the path
  `/tmp/draft-plan-brainstorm-$TRACKING_ID.md` in EACH research agent's prompt with an
  instruction to read it as the primary design seed. (Inject into the prompt — NOT into the
  research consolidation file, which doesn't exist until after dispatch.)
- The post-research steering checkpoint (`SKILL.md:297-308`) is **skipped when
  `BRAINSTORM_FLAG=1`** (the user already steered, in depth, during the dialogue). The existing
  "if subagent, skip checkpoint" branch is unchanged; the new condition is additive.

**Must-not-break (conformance + per-skill test pins, verified at the cited lines):**
- `auto` token detection, `AUTO_FLAG=0` init, `/land-pr` dispatch, `${AUTO_FLAG:-0}` gate,
  `Skill: { skill: "land-pr"`, `--auto`, and `argument-hint:.*\[auto\]` MUST all survive
  (`tests/test-skill-conformance.sh:677-692`).
- `test-draft-plan-args-smoke.sh` parity fingerprints (`for tok in $ARGUMENTS; do`, the two
  `OUTPUT_FILE` case arms, the `TRACKING_ID` kebab derive) MUST still `grep -qF`-match, and the
  `AUTO_FLAG=0 … fi` extract-and-run fence MUST stay awk-extractable (separate `BRAINSTORM_FLAG`
  fence guarantees this — confirmed the extractor keys on `/^AUTO_FLAG=0$/.../^fi$/`).

**Version bump + mirror (one skill).** This phase edits only `skills/draft-plan/SKILL.md`, so
bump its `metadata.version` (date + recomputed hash via `scripts/skill-content-hash.sh
skills/draft-plan`) and `scripts/mirror-skill.sh draft-plan` before the per-phase commit, or
`block-stale-skill-version.sh` will deny the commit.

### Acceptance Criteria
- [ ] `BRAINSTORM_FLAG` is set by a dedicated fence; `brainstorming`/`brainstormed`/
      `brainstorms` do NOT match.
- [ ] `brainstorm` is stripped from the description (preamble loop + extraction prose updated).
- [ ] SKILL.md Reads `references/brainstorm.md` ONLY when `BRAINSTORM_FLAG=1` AND
      `ZSKILLS_PIPELINE_ID` is empty; absent flag or delegated → not loaded.
- [ ] In brainstorm mode the research-agent prompts include the notes-file path and the
      post-research checkpoint is skipped; non-brainstorm mode is unchanged.
- [ ] `argument-hint` includes `[brainstorm]`; `[auto]` retained.
- [ ] `tests/test-skill-conformance.sh` draft-plan per-skill pins still pass; existing `auto`
      behaviors intact.
- [ ] `tests/test-draft-plan-args-smoke.sh` still passes.
- [ ] `metadata.version` bumped + mirror parity holds for draft-plan (no parent-skill edits).

### Dependencies
Phase 1 (the conditional-load prose Reads `references/brainstorm.md`).

---

## Phase 3 — Tests, version bumps, mirrors, conformance

### Goal
Add brainstorm-specific coverage, then run the full suite + conformance and verify green.

### Work Items
- [ ] Extend `tests/test-draft-plan-args-smoke.sh` with brainstorm cases.
- [ ] Run `bash tests/run-all.sh` and `bash tests/test-skill-conformance.sh`; fix failures at
      root cause.
- [ ] Confirm no residual version/mirror drift for draft-plan.

### Design & Constraints

**New test cases** (mirror the file's existing two-pattern style — extract-and-run for
self-contained fences, `grep -qF` parity for externally-sourced fences):
- **BRAINSTORM_FLAG extract-and-run:** awk-extract the `BRAINSTORM_FLAG=0 … fi` fence and run
  it verbatim against fixtures — positives: `brainstorm Add dark mode`, `Add dark mode
  brainstorm`, `output X.md brainstorm rounds 3 …` (mid), `BRAINSTORM …` (case); negatives:
  `brainstorming the design`, `brainstormed yesterday`, `brainstorms` → flag stays `0`.
- **Conditional-load parity grep:** assert SKILL.md gates the `references/brainstorm.md` Read on
  `BRAINSTORM_FLAG` AND `ZSKILLS_PIPELINE_ID` emptiness (file not unconditionally loaded).
- **Feed-forward grep:** assert SKILL.md's brainstorm-mode research dispatch references
  `/tmp/draft-plan-brainstorm-` (the notes-file path injected into agent prompts) — the testable
  anchor for "research consumes the seed."
- **Checkpoint-skip grep:** assert the post-research checkpoint is gated on `BRAINSTORM_FLAG`.
- `references/brainstorm.md` is automatically in scope for `test-skill-conformance.sh`
  (forbidden-literals, fence-local config sourcing, per-skill version, mirror parity) — no new
  conformance test needed, but the suite must pass with it.

**Test-file conventions:** capture output to `/tmp/zskills-tests/...`, never pipe. `tests/**/*.sh`
are not skill files, so the skill forbidden-literals deny-list does not apply to fixtures.

**No new draft-plan source edit expected here** → no further draft-plan bump unless a test-driven
fix touches a skill dir, in which case bump + mirror as in Phases 1–2.

### Acceptance Criteria
- [ ] `tests/test-draft-plan-args-smoke.sh` includes BRAINSTORM_FLAG extract-and-run (positives +
      negatives), conditional-load parity, feed-forward, and checkpoint-skip assertions; the
      test passes.
- [ ] `bash tests/run-all.sh` passes — report each suite + result + the exact command (no
      "all tests pass" without enumeration).
- [ ] `bash tests/test-skill-conformance.sh` passes, including per-skill version + mirror parity
      for draft-plan, and forbidden-literals + fence-local config-sourcing for
      `references/brainstorm.md`.
- [ ] No version/mirror drift remains for draft-plan.

### Dependencies
Phases 1 and 2.

---

## Open Questions / Risks

Most round-1 risks were resolved into concrete design above. Residual items for the implementer:

1. **Demo server stranding.** The pidfile-based `kill "$PID"` stop is best-effort; a stranded
   `/tmp` server on an ephemeral port is harmless to the worktree and `/land-pr` (it's not on a
   tracked path and not on the dev-server port). Acceptable; just stop on clean exit.
2. **brainstorm runs AFTER the Preflight.** Confirmed the Preflight (`SKILL.md:25-40`) STOPs
   only when there's no `Agent` tool; the brainstorm stage runs after it, dispatches no agents,
   and never executes in a context the Preflight already rejected.

Deferred by design (per the user, 2026-05-31): letting `/research-and-plan` /
`/research-and-go` explicitly request brainstorm. Out of scope now; add parent-side plumbing
if the need arises.

## Plan Quality

**Drafting process:** /draft-plan with 1 round of adversarial review (reviewer +
devil's-advocate + refiner), top-level orchestration.
**Convergence:** Converged at round 1 — all reviewer (12) and devil's-advocate (9) findings
were verified against the actual codebase and either fixed or confirmed non-issues; 0
substantive issues remain.
**Remaining concerns:** None blocking. Three implementer-verification items are itemized under
Open Questions / Risks (ZSKILLS_PIPELINE_ID propagation probe, demo-server stranding tolerance,
Preflight ordering) — all have a defined, robust fallback and do not gate execution.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 12 (3 must-fix, rest confirmations/minor) | 9 (4 critical, 3 major, 2 minor) | All verified; fixed or confirmed-non-issue. Key fixes: feed-forward injected into agent prompts (research file is post-dispatch); screenshot stays in gitignored `.playwright/output/` (no `/tmp` claim, no move-into-tree); ephemeral-port + pidfile demo server (no `port.sh` collision, compliant stop); slug pinned to `$TRACKING_ID`; corrected AskUserQuestion quote. |
| post  | — | — | User steer (2026-05-31): parents won't pass `brainstorm`, so the delegation gate was simplified from a dual-mechanism (draft-plan check + parent-side strip across 3 skills) to a single one-line `ZSKILLS_PIPELINE_ID`-empty insurance check in draft-plan alone. No parent-skill edits; version-bump scope reduced to 1 skill. |
