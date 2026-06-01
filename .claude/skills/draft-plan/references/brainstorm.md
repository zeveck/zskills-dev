# /draft-plan — Brainstorm mode

> Loaded by `SKILL.md` **only when the `brainstorm` flag is present** (progressive
> disclosure). This file is the complete, self-contained dialogue protocol the
> orchestrator follows when brainstorm mode is active, including the throwaway-demo
> lifecycle, the durable notes-file state machine, the feed-forward into Phase 1
> research, and the reconciliations with zskills framework rules. SKILL.md Reads this
> file and executes its loop INLINE — the dialogue dispatches no sub-agents.

Brainstorm mode is adapted from the [superpowers](https://github.com/obra/superpowers)
`brainstorming` skill, re-grounded for zskills. superpowers writes a committed design
doc and hands off to `writing-plans`; here the terminal artifact is the `/draft-plan`
plan file, so the brainstorm produces a `/tmp` **notes seed** that feeds Phase 1
research instead of a committed spec. The dialogue runs a collaborative, multi-turn
conversation to flesh out a rough idea *before* the existing adversarial pipeline runs:
one focused question at a time, 2–3 approaches with trade-offs, ruthless YAGNI, and
optional throwaway demos. It proceeds until the user explicitly confirms they're ready.

---

## Slug pinning — load-bearing for the notes + demo paths

The brainstorm notes file and the demo directory derive their slug from the
deterministic `$TRACKING_ID` the SKILL.md preamble computes (`basename "$OUTPUT_FILE"
.md | tr A-Z a-z | tr _ -`, at `skills/draft-plan/SKILL.md:85`). `$TRACKING_ID` is
already in scope at the brainstorm stage (it is set before this stage runs). **Use it
verbatim** — do NOT recompute a slug from the description:

- **notes file:** `/tmp/draft-plan-brainstorm-$TRACKING_ID.md`
- **demo directory:** `/tmp/draft-plan-demo-$TRACKING_ID/`

**Do NOT assume the existing research file shares this slug.** The research file's
`<slug>` is loose, orchestrator-chosen prose (`SKILL.md:222-226` derives it from the
output filename "if one was provided," else from the description), so it is NOT
guaranteed to equal `$TRACKING_ID`. (Example: a pipeline's research file may be
`/tmp/draft-plan-research-BRAINSTORM_MODE.md` while `$TRACKING_ID` = `brainstorm-mode-plan`.)
The feed-forward therefore does NOT re-derive a path — it passes the **literal**
`/tmp/draft-plan-brainstorm-$TRACKING_ID.md` string into the research-agent prompts (see
[Feed-forward](#feed-forward-into-phase-1-research)), so it never depends on slug parity.

**All `/tmp` paths are ABSOLUTE.** This is required because the brainstorm stage runs
*after* the worktree preamble, so the current working directory is the worktree. A
relative demo/notes path would write *into* the worktree and dirty the tree.

---

## The 8-step dialogue protocol

Execute these steps inline as the orchestrator. The loop is conversational and
multi-turn; there is no fixed number of turns — it ends only when the user affirmatively
confirms at step 7/8.

1. **Open: restate + light context.** Reflect the user's seed idea back in 1–2
   sentences so they can confirm or correct your understanding. The worktree,
   `$OUTPUT_FILE`, and `$TRACKING_ID` are already resolved by the preamble, so defer
   heavy repo exploration to Phase 1 research — read only what's needed to ask good
   questions, not to pre-solve the design.

2. **Offer a visual companion as its OWN standalone message** (superpowers pattern) —
   but **only** when the upcoming exploration involves visual content (UI, layout,
   diagrams, flows). The message contains nothing but the offer plus a one-line
   description of what would be shown, and requests consent before building anything.
   **Skip this step entirely for non-visual ideas** (most plans). See
   [Quick-demo lifecycle](#quick-demo-lifecycle--exact-idioms) for how to build one once
   the user consents.

3. **Ask clarifying questions ONE per message.** Most-fundamental first (problem / user
   / success criteria), then mechanics and naming. When a question has natural choices,
   **offer them in plain prose** — e.g. "Option A: …; Option B: …; I lean toward A
   because …" — and **never** the `AskUserQuestion` tool (see
   [Reconciliations](#reconciliations-with-zskills-rules)).

4. **Propose 2–3 approaches with trade-offs + an explicit recommendation** at each real
   fork in the design. Don't enumerate options neutrally — say which one you'd pick and
   why, so the user has a concrete position to push against.

5. **Apply ruthless YAGNI / gentle pushback.** Surface hidden costs and simpler
   alternatives as questions ("Do we actually need X, or would the simpler Y cover the
   real case?"). This is the soft, in-dialogue cousin of the Phase-3 adversarial review
   — it does **not** replace it. The full review still runs after the transition.

6. **Capture decisions as they're made** into the notes file (see
   [Durable notes file](#durable-notes-file--resumable-state-machine)) — each decision
   with its rationale, plus the rejected alternatives and any open questions. Update the
   notes file after each decision, not in one batch at the end, so the state survives a
   compaction.

7. **Offer the transition checkpoint** when the open questions are exhausted:
   > "I think we've got enough to draft a plan — start the adversarial design review, or
   > keep exploring?"

   Require an **affirmative confirm**. If the reply is ambiguous, **ask once more** — do
   not infer readiness. **Never keyword-auto-detect "ready"**: a stray mention of the
   word "ready" (or "done", "go", etc.) in the user's prose is NOT a confirmation. Only
   an explicit, unambiguous affirmative to *this* checkpoint authorizes the transition.

8. **On confirm:** finalize the notes file as a structured design summary, flip its
   header to `status: ready` (the terminal marker that authorizes the transition — see
   below), then return control to SKILL.md, which proceeds to Phase 1 research using the
   notes file as the seed. (Phase 2 of the brainstorm plan wires the SKILL.md-side return
   and the redundant-checkpoint skip.)

---

## Quick-demo lifecycle — EXACT idioms

These are the worktree-safety + process-lifecycle load-bearing rules. They are specified
literally because casual versions are factually wrong about screenshot paths and ports.

**All demo files live under `/tmp/draft-plan-demo-$TRACKING_ID/`, NEVER inside the
worktree.** Phase 6 finalize stages ONLY the plan `.md` via a `FILE_REL` guard and
`exit 1`s if any other file is staged (`skills/draft-plan/SKILL.md:640-645`); a
worktree-resident demo would dirty the tree and confuse `/land-pr`. Keeping demos in
`/tmp` is what makes them safe.

### Live browser visual companion (the common / default case)

Write a self-contained HTML file (inline CSS/JS, no external assets) under
`/tmp/draft-plan-demo-$TRACKING_ID/`, then serve that directory on an **OS-assigned free
port**. Do NOT use `port.sh` — that returns the same per-worktree-deterministic port the
dev server uses, so reusing it would collide with a running dev server; an ephemeral port
(`port 0`) avoids all collisions. Use Python's stdlib http server (Python is a hard
zskills dependency; this avoids any consumer-specific serve literal and the uncustomized
`start-dev.sh` stub).

Capture the chosen port AND the PID to a **pidfile**: the Bash tool does not persist
shell state across calls, so an in-memory `$!` is lost on the next Bash invocation — a
pidfile is mandatory so a later call can find and stop the server. Spec the idiom
literally:

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

Give the user the URL by reading it from `$DEMO_DIR/.serve.url` **AFTER** the
`timeout … until [ -s … ]` wait above — an immediate read returns empty because the
server has not yet bound the port and flushed its URL. Iterate the HTML in place and tell
the user to refresh the page to see changes.

**Authoring-effort honesty note.** The inline-built HTML companion is a THROWAWAY
visualization, not production UI. Keep mockups minimal — enough to make the idea concrete,
not polished. Do NOT sink disproportionate effort into demo HTML mid-dialogue; the goal
is to unblock the conversation, not to ship a pixel-perfect mockup.

### Stopping the server

**NEVER use `kill -9`, `killall`, `pkill`, or `fuser -k`; never `lsof -ti | xargs kill`.**
Read the PID from `$DEMO_DIR/.serve.pid` and SIGTERM that specific PID only:

```bash
DEMO_DIR="/tmp/draft-plan-demo-$TRACKING_ID"
PID=$(cat "$DEMO_DIR/.serve.pid")
kill "$PID"   # SIGTERM to the one server PID — never kill -9/pkill/killall/fuser -k/lsof|xargs kill
```

Stop the server at brainstorm exit, or leave it for the user to stop. Because demos live
in `/tmp` on an ephemeral port, a stranded server does not dirty the worktree and cannot
block `/land-pr` (it is not on a tracked path and not on the dev-server port); still, stop
it on a clean exit for tidiness.

### Static screenshot (the "sometimes" lighter case)

`playwright-cli screenshot` takes **NO URL** and requires the browser to be open first (a
bare `playwright-cli screenshot file://…` errors "browser 'default' is not open"). The
verified sequence is:

```bash
DEMO_DIR="/tmp/draft-plan-demo-$TRACKING_ID"
playwright-cli open "file://$DEMO_DIR/<demo>.html"
playwright-cli screenshot   # NO --filename, NO url
playwright-cli close
```

Omitting `--filename` saves the image into the configured, gitignored `.playwright/output/`
directory (which is invisible to git — `.gitignore:20` ignores `.playwright/*`; the
screenshot lands there headless in this environment). **Do NOT move or rename the
screenshot into the tracked worktree** — that is the actual pollution hazard; the image is
safe only while it stays in the gitignored `.playwright/output/` dir. Show the user the
image from `.playwright/output/`. If `playwright-cli` errors on the environment, check
`.devcontainer/setup.sh` first before concluding the container can't do it
(`feedback_check_devcontainer_before_bailing`).

### Which demo to use

**Default toward the live companion** when the user benefits from interaction (clicking,
hovering, refreshing as the idea evolves). Use the static screenshot for fast, static
conceptual shots where interaction adds nothing. Demos are throwaway and never committed;
optionally clean up on brainstorm exit:

```bash
rm -rf "/tmp/draft-plan-demo-$TRACKING_ID"
```

---

## Durable notes file — resumable state machine

Maintain `/tmp/draft-plan-brainstorm-$TRACKING_ID.md`, updated after each decision (step
6). This mirrors the skill's existing `/tmp/draft-plan-research-$TRACKING_ID.md`
compaction-survival pattern (`SKILL.md:222-228`). Accumulate, as the dialogue progresses:

- the refined problem statement,
- decisions + rationale,
- rejected alternatives,
- open questions,
- pointers to demo screenshots / URLs.

**The notes file IS a resumable state machine.** The dialogue is multi-turn and WILL
sometimes span a context compaction. After compaction, the in-context dialogue state and
the `STEERING_MODE` shell variable are gone, and nothing would otherwise re-trigger the
loop — the orchestrator could wrongly jump to Phase 1 with a half-finished seed. Defend
this structurally with a header status line:

- The notes file carries a header `status: in-progress` from creation.
- It is flipped to the terminal `status: ready` line **ONLY at step 8** (user confirm).

The notes file therefore looks like this from the start of the dialogue:

```
---
status: in-progress
tracking_id: <$TRACKING_ID>
---

# Brainstorm notes: <restated idea>

## Refined problem statement
...

## Decisions
- <decision> — <rationale>

## Rejected alternatives
- <alternative> — <why rejected>

## Open questions
- <question>

## Demo pointers
- <URL or .playwright/output/ screenshot path>
```

**Resume-on-reentry semantics.** When SKILL.md (re)enters with `STEERING_MODE = brainstorm`, it
checks for the notes file (Phase 2 wires the SKILL.md side):

- **Notes file exists with `status: ready`** → a prior dialogue already completed.
  Proceed straight to Phase 1, using the notes file as the seed. Do NOT re-run the
  dialogue, and do NOT re-offer the transition checkpoint.
- **Notes file exists with `status: in-progress`** → a dialogue was interrupted by
  compaction or crash. **RESUME** the dialogue from its captured state (re-read the notes
  file to reconstruct decisions / open questions), rather than restarting from step 1 or
  skipping to Phase 1.
- **Notes file absent** → run the dialogue from step 1.

Only a `status: ready` notes file authorizes the transition to Phase 1. This makes the
dialogue crash/compaction-safe.

---

## Feed-forward into Phase 1 research

At the transition (after `status: ready`), the notes-file path is injected into **EACH**
Phase 1 research agent's **PROMPT**, with an instruction to read it as the primary design
seed. (Phase 2 of the brainstorm plan wires the SKILL.md-side dispatch.)

**The feed-forward is "inject the notes-file path into each research agent's prompt," NOT
"append to the research file before dispatch."** The research file
(`/tmp/draft-plan-research-$TRACKING_ID.md` per the loose slug) is the *post-dispatch
CONSOLIDATION*, written AFTER the agents are dispatched (`skills/draft-plan/SKILL.md:202`),
so notes cannot be "added to the research file" before agents read it — the file does not
exist yet at dispatch time. The path injected into the prompts is the **literal**
`/tmp/draft-plan-brainstorm-$TRACKING_ID.md` string (it does not depend on research-file
slug parity — see [Slug pinning](#slug-pinning--load-bearing-for-the-notes--demo-paths)).

The post-dispatch consolidation then incorporates both the agents' findings and the
brainstorm notes. **This is hybrid — the brainstorm does NOT skip research:**

- The **Codebase / Patterns / Prior-art** agents STILL run to ground the design against
  the actual repo.
- The **Domain** agent's "what to build" work is largely pre-answered by the brainstorm
  and may be reduced to verification.

---

## Reconciliations with zskills rules

Stated here so future editors don't re-litigate them.

- **No `AskUserQuestion`.** Per `skills/update-zskills/SKILL.md:701`: "Do NOT use
  AskUserQuestion. Ask in plain conversation text." superpowers "prefers multiple choice"
  → here, options are offered in plain prose ("Option A: …; Option B: …; I lean toward
  A because …").

- **No sub-agent dispatch in the dialogue.** The loop and demo-building are INLINE
  orchestrator work; the dialogue dispatches no agents, so it adds no `Agent`-tool
  requirement beyond the existing Preflight and needs no `subagent_type` pin. (Forward
  constraint: if a future revision dispatches an agent to build a demo, it MUST pin
  `subagent_type: "implementer"` and never Haiku.)

- **No forbidden literals in this file.** This IS a skill file (it lives under `skills/`),
  so it is in the forbidden-literals deny-list scope. No `TZ=America/New_York` (use
  `${TIMEZONE:-UTC}` via `zskills-resolve-config.sh` if a timestamp is ever needed), no
  `npm run test:all`, `npm start`, `$TEST_OUT/.test-results.txt`, or the skill-version
  regex inside exec fences without an `<!-- allow-hardcoded: … reason: … -->` marker. The
  Python-http-server + ephemeral-port + `file://`-screenshot design deliberately
  references none of the six config-resolution variables, so no positive-side fence-local
  config-sourcing is triggered; if a future fence references one, source the helper
  in/above it.

- **Never `kill -9` / `killall` / `pkill` / `fuser -k` / `lsof -ti | xargs kill`** to stop
  the demo server — SIGTERM the one pidfile PID (see
  [Stopping the server](#stopping-the-server)).

- **No foreground `sleep`** in the serve-URL wait — the harness blocks it; the
  `timeout … until [ -s … ]` busy-wait is the sleep-free substitute.

**Authoring constraint — script-source references use the two-lane dual-path form.** Try
`${CLAUDE_PLUGIN_ROOT}/skills/...` first, fall back to
`$CLAUDE_PROJECT_DIR/.claude/skills/...`. For example, when sourcing the config-resolution
helper:

```bash
. "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_PROJECT_DIR/.claude}/skills/update-zskills/scripts/zskills-resolve-config.sh"
```
