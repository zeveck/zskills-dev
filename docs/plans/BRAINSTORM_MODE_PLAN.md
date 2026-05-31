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
  modify the parent skills, and the gate is simply `BRAINSTORM_FLAG=1`.
- **Accepted, deferred residual risk (round-2 finding):** an earlier draft added a
  `ZSKILLS_PIPELINE_ID`-empty check as "insurance" against a delegated sub-problem description
  that literally contains the word "brainstorm". That check is **inert** — verified that NO
  skill anywhere `export`s `ZSKILLS_PIPELINE_ID` (`grep -rn 'export ZSKILLS_PIPELINE_ID'
  skills/` → zero; `/research-and-go` only `echo`s it to the transcript for the tracking hook),
  so it reads empty in both top-level AND delegated runs and would protect nothing. It is
  therefore NOT included. The only residual edge — a delegated run whose description contains
  the standalone word "brainstorm" entering a dialogue with no user — is **explicitly accepted
  and deferred** per the user's "don't worry about that yet." If hardening is later needed, the
  mechanism is a parent-passed delegation marker (a forwarded `delegated` token or an actually-
  exported env var) that draft-plan checks — adventure for a future plan, not invented here.
- **Demos default toward the live browser companion** (superpowers' common case), with the
  static screenshot as the lighter "sometimes" path — per the user's steer.
- **Dialogue uses plain conversation text, never `AskUserQuestion`** (settled framework
  prohibition, `skills/update-zskills/SKILL.md:701`: "Do NOT use AskUserQuestion. Ask in
  plain conversation text").

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Author references/brainstorm.md | ✅ Done | `aa6d16b` | 338-line brainstorm.md; version 2026.05.31+874a6f + mirror; issue-606 allowlist; 6575/6575 |
| 2 — Wire brainstorm into SKILL.md | ✅ Done | `0a296c1` | BRAINSTORM_FLAG + conditional-load/resume + feed-forward + checkpoint-skip + argument-hint; version 1d4478 + mirror; 6575/6575 |
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

**Slug pinning (load-bearing for feed-forward).** The brainstorm notes + demo paths derive
their slug from the deterministic `$TRACKING_ID` the SKILL.md preamble computes at
`skills/draft-plan/SKILL.md:85` (`basename "$OUTPUT_FILE" .md | tr A-Z a-z | tr _ -`) — use it
verbatim, in scope at the gate (set before the brainstorm stage), do NOT recompute from the
description:
- notes: `/tmp/draft-plan-brainstorm-$TRACKING_ID.md`
- demos: `/tmp/draft-plan-demo-$TRACKING_ID/`

**Do NOT assume the existing research file shares this slug (round-2 finding).** The research
file's `<slug>` is loose, orchestrator-chosen prose (`SKILL.md:222-226` derives it from the
output filename "if one was provided," else from the description), so it is NOT guaranteed to
equal `$TRACKING_ID` (e.g. this very pipeline's research file is
`/tmp/draft-plan-research-BRAINSTORM_MODE.md` while `$TRACKING_ID` = `brainstorm-mode-plan`).
The feed-forward therefore does NOT re-derive a path — it passes the **literal**
`/tmp/draft-plan-brainstorm-$TRACKING_ID.md` string into the research-agent prompts (Phase 2),
so it never depends on slug parity.

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
8. **On confirm:** finalize the notes file as a structured design summary, flip its header to
   `status: ready` (the terminal marker that authorizes the transition), then return control to
   SKILL.md (Phase 2 wires the return + the redundant-checkpoint skip).

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
  DEMO_DIR="/tmp/draft-plan-demo-$TRACKING_ID"; mkdir -p "$DEMO_DIR"
  # Serve on an OS-assigned free port; the python prints its URL to .serve.url.
  "$PYTHON" - "$DEMO_DIR" > "$DEMO_DIR/.serve.url" 2>&1 <<'PY' &
  import http.server, socketserver, os, sys, functools
  os.chdir(sys.argv[1])
  h = functools.partial(http.server.SimpleHTTPRequestHandler)
  with socketserver.TCPServer(("127.0.0.1", 0), h) as s:
      print(f"http://127.0.0.1:{s.server_address[1]}/", flush=True)
      s.serve_forever()
  PY
  echo "$!" > "$DEMO_DIR/.serve.pid"          # NO trailing space — ps -p chokes on it
  # The server needs ~1-3s to bind + flush the URL; wait for it WITHOUT a foreground `sleep`
  # (harness-blocked per CLAUDE.md). A timeout-bounded busy-wait is sleep-free:
  timeout 8 bash -c 'until [ -s "$1/.serve.url" ]; do :; done' _ "$DEMO_DIR" || true
  ```
  Give the user the URL (read from `$DEMO_DIR/.serve.url` AFTER the wait above; an immediate read
  returns empty — round-2 finding). Iterate the HTML in place and tell them to refresh.
- **Stopping the server (NEVER `kill -9`/`killall`/`pkill`/`fuser -k`; never
  `lsof -ti | xargs kill`).** Read the PID from `$DEMO_DIR/.serve.pid` and `kill "$PID"`
  (SIGTERM that specific PID only) at brainstorm exit, or leave it for the user to stop.
  Because demos live in `/tmp`, a stranded server does not dirty the worktree and cannot
  block `/land-pr`; still, stop it on a clean exit for tidiness.

- **Static screenshot (the "sometimes" lighter case).** `playwright-cli screenshot` takes NO
  URL and requires the browser to be open first (round-2 finding: a bare
  `playwright-cli screenshot file://…` errors "browser 'default' is not open"). The verified
  sequence is: `playwright-cli open "file://$DEMO_DIR/<demo>.html"` → `playwright-cli screenshot`
  (NO `--filename`, NO url) → `playwright-cli close`. Omitting `--filename` saves into the
  configured, gitignored `.playwright/output/` dir (which is invisible to git — `.gitignore:20`
  ignores `.playwright/*`; verified the screenshot lands there headless in this environment).
  **Do NOT move or rename the screenshot into the tracked worktree** (that is the actual
  pollution hazard — it is safe only while it stays in the gitignored dir). Show the user the
  image from `.playwright/output/`. If playwright-cli errors on environment, check
  `.devcontainer/setup.sh` first (`feedback_check_devcontainer_before_bailing`).

- **Default toward the live companion** when the user benefits from interaction; use the
  screenshot for fast static conceptual shots. State this preference explicitly in the file.
- **Authoring-effort honesty note (round-2 finding):** the inline-built HTML companion is a
  THROWAWAY visualization, not production UI. Keep mockups minimal — enough to make the idea
  concrete, not polished. The file must say this so the orchestrator doesn't sink
  disproportionate effort into demo HTML mid-dialogue.
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
- **The notes file IS a resumable state machine (round-2 finding).** The dialogue is multi-turn
  and WILL sometimes span a context compaction; after compaction the in-context dialogue state
  and `BRAINSTORM_FLAG` shell var are gone, and nothing would otherwise re-trigger the loop —
  the orchestrator could jump to Phase 1 with a half-finished seed. Defend structurally: the
  notes file carries a header `status: in-progress`, flipped to a terminal `status: ready` line
  ONLY at step 8 (user confirm). The brainstorm-mode entry in SKILL.md (Phase 2) must, on
  (re)entry when the flag is set, check for the notes file: if it exists with
  `status: in-progress`, RESUME the dialogue from the captured state rather than restarting or
  skipping to Phase 1; only a `status: ready` notes file authorizes the transition. This makes
  the dialogue crash/compaction-safe.
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
      OS-assigned free port, PID written to a pidfile with `echo "$!"` (NO trailing space —
      round-2 bug), a sleep-free `timeout … until [ -s .serve.url ]` wait before reading the
      URL (no foreground `sleep`), stopped via `kill "$PID"` (no `kill -9`/`pkill`/`lsof|xargs kill`).
- [ ] The screenshot idiom uses `playwright-cli open <file://url>` → `screenshot` (no url, no
      `--filename`) → `close` (round-2: `screenshot` needs the browser open first), lands in
      gitignored `.playwright/output/`, and the file forbids moving/renaming it into the tracked
      worktree.
- [ ] The notes file is a resumable state machine: `status: in-progress` until step 8 flips it
      to `status: ready`; the file documents resume-on-reentry semantics.
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
- [ ] Add `brainstorm` to the recognized-flag **prose** list in the description-extraction
      section (`SKILL.md:143-147`, mirroring the `auto` bullet). NO preamble-loop edit — the
      `for tok in $ARGUMENTS` loop (`SKILL.md:75-80`) only extracts `.md` tokens for
      `OUTPUT_FILE` and strips nothing (round-2 finding: there is no `auto)` arm to mirror).
- [ ] Add the **conditional-load + resume** prose (new "Brainstorm mode" stage between Pre-check
      and Phase 1), gated on `BRAINSTORM_FLAG=1`.
- [ ] Wire the **feed-forward** (inject the literal notes-file path into research-agent prompts)
      and the **post-research checkpoint skip** in brainstorm mode.
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
`brainstorms`, and won't collide with `output`/`rounds`/`.md`/`auto`. Add `brainstorm` only to
the recognized-flag PROSE list (`SKILL.md:143-147`) so the orchestrator excludes it from the
description — there is nothing to change in the `.md`-only preamble token loop.

**Gate (simplified per the user — no parent-skill changes, no inert env check).** The gate is
simply `BRAINSTORM_FLAG=1`. The parents (`/research-and-plan`, `/research-and-go`) will not pass
a `brainstorm` token (the load-bearing guarantee), so the automated/headless path never sets the
flag. An earlier draft added a `[ -z "${ZSKILLS_PIPELINE_ID:-}" ]` "insurance" check; round 2
verified it is **inert** (no skill `export`s `ZSKILLS_PIPELINE_ID` — `grep -rn 'export
ZSKILLS_PIPELINE_ID' skills/` → zero; `/research-and-go` only `echo`s it for the transcript
hook), so it reads empty in both top-level and delegated runs and protects nothing. It is
therefore NOT included — a dead check dressed as insurance is worse than none. The one residual
edge (a delegated description literally containing the standalone word "brainstorm" — the regex
does fire on it) is **explicitly accepted/deferred** per the user; if hardening is later wanted,
add a real parent-passed delegation marker and check it here. Result: at top level, `brainstorm`
(with or without `auto`) enters the dialogue; delegated runs simply never have the flag set.

**Conditional-load + resume prose** (follow `/session-report handoff`,
`session-report/SKILL.md:28-35`). A new section immediately after Pre-check (`SKILL.md:174`),
before Phase 1:
> ## Brainstorm mode (only when the `brainstorm` flag is present)
> If `BRAINSTORM_FLAG=1`, **Read [references/brainstorm.md](references/brainstorm.md)** via the
> Read tool and execute its dialogue loop now, before Phase 1 — UNLESS the notes file
> `/tmp/draft-plan-brainstorm-$TRACKING_ID.md` already exists with `status: ready` (a prior,
> completed dialogue — proceed straight to Phase 1 using it as the seed). If the notes file
> exists with `status: in-progress` (a dialogue interrupted by compaction/crash), RESUME it from
> its captured state rather than restarting. If `BRAINSTORM_FLAG=0`, **ignore the reference file
> entirely** and proceed straight to Phase 1.

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
- [ ] `brainstorm` is added to the recognized-flag PROSE list (`SKILL.md:143-147`); the
      `.md`-only preamble token loop is NOT touched.
- [ ] SKILL.md Reads `references/brainstorm.md` ONLY when `BRAINSTORM_FLAG=1`; absent flag → not
      loaded. The gate contains no inert `ZSKILLS_PIPELINE_ID` check.
- [ ] The "Brainstorm mode" prose implements resume-on-reentry: `status: ready` notes file →
      skip dialogue, use as seed; `status: in-progress` → resume; absent → run dialogue.
- [ ] In brainstorm mode the research-agent prompts include the literal notes-file path and the
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
  `BRAINSTORM_FLAG` (file not unconditionally loaded). Also assert the gate does NOT reference
  `ZSKILLS_PIPELINE_ID` (regression guard against re-adding the inert check).
- **Resume-contract grep:** assert the "Brainstorm mode" prose references `status: ready` /
  `status: in-progress` (the resume state machine is wired).
- **Feed-forward grep:** assert SKILL.md's brainstorm-mode research dispatch references
  `/tmp/draft-plan-brainstorm-` (the notes-file path injected into agent prompts) — the testable
  anchor for "research consumes the seed."
- **Checkpoint-skip grep:** assert the post-research checkpoint is gated on `BRAINSTORM_FLAG`.
- **brainstorm.md idiom greps:** assert `references/brainstorm.md` uses `playwright-cli open`
  before `screenshot`, writes the pidfile with no trailing space (`echo "$!" >`), and uses no
  bare foreground `sleep` in the serve-wait (regression guards for the round-2 idiom bugs).
- `references/brainstorm.md` is automatically in scope for `test-skill-conformance.sh`
  (forbidden-literals, fence-local config sourcing, per-skill version, mirror parity) — no new
  conformance test needed, but the suite must pass with it.

**Test-file conventions:** capture output to `/tmp/zskills-tests/...`, never pipe. `tests/**/*.sh`
are not skill files, so the skill forbidden-literals deny-list does not apply to fixtures.

**No new draft-plan source edit expected here** → no further draft-plan bump unless a test-driven
fix touches a skill dir, in which case bump + mirror as in Phases 1–2.

### Acceptance Criteria
- [ ] `tests/test-draft-plan-args-smoke.sh` includes BRAINSTORM_FLAG extract-and-run (positives +
      negatives), conditional-load parity (+ no-`ZSKILLS_PIPELINE_ID` regression guard),
      resume-contract, feed-forward, checkpoint-skip, and the brainstorm.md idiom greps
      (`playwright-cli open`, pidfile no-trailing-space, no bare `sleep`); the test passes.
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

Both rounds' risks were resolved into concrete design above. Residual items for the implementer:

1. **Demo server stranding.** The pidfile-based `kill "$PID"` stop is best-effort; a stranded
   `/tmp` server on an ephemeral port is harmless to the worktree and `/land-pr` (it's not on a
   tracked path and not on the dev-server port). Acceptable; just stop on clean exit.
2. **brainstorm runs AFTER the Preflight.** Confirmed the Preflight (`SKILL.md:25-40`) STOPs
   only when there's no `Agent` tool; the brainstorm stage runs after it, dispatches no agents,
   and never executes in a context the Preflight already rejected.
3. **Accepted/deferred (per the user, 2026-05-31):** the headless edge where a delegated
   sub-problem description literally contains the standalone word "brainstorm" would enter a
   dialogue with no user. No mitigation ships now (the inert `ZSKILLS_PIPELINE_ID` check was
   removed in round 2). If hardening is wanted later, add a real parent-passed delegation marker
   and check it in the gate. Letting parents explicitly REQUEST brainstorm is likewise deferred.

## Plan Quality

**Drafting process:** /draft-plan with 2 rounds of adversarial review (reviewer +
devil's-advocate + refiner), top-level orchestration.
**Convergence:** Converged at round 2 — every round-1 and round-2 finding was independently
re-verified against the actual codebase by the orchestrator-refiner and either fixed or
confirmed a non-issue; round 2 found two broken-on-arrival demo idioms (pidfile trailing space;
missing `playwright-cli open`) and proved the round-1 `ZSKILLS_PIPELINE_ID` gate was inert — all
fixed. 0 substantive issues remain.
**Remaining concerns:** None blocking. Two verification items + one explicitly-accepted deferred
risk are itemized under Open Questions / Risks; none gate execution.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 12 (3 must-fix, rest confirmations/minor) | 9 (4 critical, 3 major, 2 minor) | All verified; fixed or confirmed-non-issue. Key fixes: feed-forward injected into agent prompts (research file is post-dispatch); screenshot stays in gitignored `.playwright/output/`; ephemeral-port + pidfile demo server; slug pinned to `$TRACKING_ID`; corrected AskUserQuestion quote. |
| (user steer) | — | — | Parents won't pass `brainstorm` → dropped the parent-side strip + the 3-skill scope; gate simplified, version-bump scope reduced to 1 skill. |
| 2     | 2 major + 1 minor (rest confirmed-correct) | 3 critical + 2 major + 3 minor | All verified against the codebase. Fixes: removed the **inert** `ZSKILLS_PIPELINE_ID` gate (no skill exports it — verified) and documented the accepted residual; pidfile `echo "$!"` (no trailing space); sleep-free serve-URL wait (foreground `sleep` is harness-blocked); `playwright-cli open`→`screenshot`→`close` (screenshot needs browser open, takes no URL); feed-forward passes the LITERAL notes path (research-file slug ≠ `$TRACKING_ID`); dropped the bogus preamble-token-loop edit (loop is `.md`-only); notes file is a resumable `status:` state machine (compaction-safe); fixed stale tracker row; authoring-effort honesty note. |
