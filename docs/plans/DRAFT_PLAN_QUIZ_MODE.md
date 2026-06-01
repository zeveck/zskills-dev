---
title: /draft-plan quiz mode — interactive requirements-elicitation before drafting
created: 2026-05-31
status: active
---

# Plan: /draft-plan quiz mode

## Overview

Add an opt-in **`quiz`** mode to `/draft-plan`. When the user types
`/draft-plan … quiz`, the skill conducts a Socratic "quiz me" interview —
asking the user clarifying questions, reflecting a running understanding
summary, and surfacing assumptions — looping until the user explicitly
signals readiness, at which point it proceeds into the existing draft →
adversarial review → refine pipeline unchanged.

The interaction protocol lives in a new, **conditionally-loaded**
`references/quiz.md` that the SKILL.md instructs the agent to read **only
when the `quiz` token is present** (progressive disclosure — the flag is
usually absent, so the main body stays lean).

**Why this matters.** `/draft-plan` already states "the plan is the spec —
if it's not in the plan, it doesn't exist," and "open questions /
uncertainties" is a required research output. Today those open questions
become agent *guesses* that the devil's-advocate later flags as "wrong
assumptions" / "specification gaps." A front-loaded interview converts the
**intent/scope** subset of those guesses into user-confirmed facts before a
single review round burns; the **codebase-fact** subset becomes explicit open
questions the seeded post-`draft` fan-out resolves (v2 ask-vs-defer rule) —
either way, strictly higher-quality input to the same adversarial machinery.

**Design is locked** (captured via an interactive quiz with the user — see
the Requirements appendix). Key decisions:

- **Trigger:** `quiz` recognized as a **leading flag token only** (in the
  flag cluster before the description begins, like `output`/`rounds`) — NOT
  match-anywhere like `auto`. This is a deliberate divergence from `auto`:
  matching anywhere would let a description word "quiz" trip the flag in an
  autonomous run (see the leak decision below). `auto`'s own match-anywhere
  false-positive is pre-existing and out of scope here. **Note (R2):** this
  is a prose-driven parse following an explicit tokenization rule, not a
  verifiable regex — the plan must give the implementer a concrete
  tokenization (Phase 2), not just the phrase "leading cluster." **Ergonomic
  limitation (R2-F1b):** a *trailing* `quiz` (`/draft-plan add dark mode quiz`)
  is therefore description text, not the flag — unlike `auto`, which users may
  trail. This is accepted by design (it is the price of closing the leak) and
  is called out in an AC so it's not a surprise.
- **Research model — purely conversational quiz, all research deferred
  (simplified v2; supersedes the earlier "interleave" design).** The quiz is a
  pure conversation: the agent asks from its own knowledge + whatever is
  already in context, with NO upfront research agent and NO inline Explore
  dispatches during the loop. All codebase research is the **existing,
  unchanged Phase-1 fan-out**, which runs once, *after* the user says `draft`,
  seeded with the interview file as priors. **Rationale:** the interleave
  design made the user wait through research rounds on every quiz turn — a
  guaranteed friction cost; deferring all research trades it for an
  occasional, recoverable "research surfaces something after `go`" case (see
  the post-`go` surprise handling below). The ask-vs-defer rule simplifies to:
  ask the user about *intent / scope / preference*; for *codebase facts* the
  agent is unsure of, do NOT interrogate the user — note them as open
  questions for the post-`draft` fan-out to resolve.
- **Post-`go` research surprise handling (the simplified design's one real
  trade-off).** Because research runs entirely after `draft`, the fan-out may
  surface a fact relevant to what the user confirmed. Handling, graduated by
  severity: a routine finding just informs the draft; a finding that
  *contradicts a user-confirmed requirement* is **surfaced, not silently
  drafted around** — minor conflicts go in the research summary and are caught
  by the Phase-3 adversarial review; a **hard** contradiction ("you asked for
  X, but X isn't feasible because Y") pauses for a one-line "adjust or
  proceed?". The user reviews the finished plan regardless (existing Phase-6
  "open it and tell me what to change"), so nothing surprising ships silently.
  This fires only on genuine conflict — it does not reintroduce per-finding
  interruption. **Does NOT hang a `quiz auto` run (F4):** `quiz` is
  interactive-only (leading-flag, never set by autonomous callers — see the
  leak decision), so a human is always present; and `auto` governs only the
  Phase-6 `/land-pr` landing, which is *after* the fan-out where the pause
  fires. The hard-contradiction pause therefore asks a human who is already in
  the loop; `auto` just auto-lands the resulting PR. (Honors
  [[feedback_auto_means_dont_ask]] — the pause is not an unattended-run gate.)
- **Question style:** prose-dominant; AskUserQuestion only for closed forks —
  and **every structured prompt MUST always leave a free-text escape** (the
  user is never caged in pre-baked options). AskUserQuestion's "Other"
  free-text option is documented as always available in the tool contract;
  the protocol relies on it AND additionally frames prompts to invite free
  text (belt-and-suspenders).
- **Termination:** explicit `draft`/`go`/`ready` keyword as a **whole-message**
  signal (not a substring); the agent *proposes* readiness each round and
  exits only on that explicit signal — never on a mid-stream "looks good," and
  never on a go-word embedded inside a longer steering message.
- **`quiz` + `auto` compose for an interactive human** (they are independent):
  `quiz` = interactive interview before drafting; `auto` = Phase-6 `/land-pr`
  auto-land after the worktree commit. A human typing `/draft-plan quiz auto …`
  gets "interview me, then auto-land the plan PR." **Not contradictory** — no
  suppression of one by the other.
- **The non-interactive leak IS closed by the leading-flag parse rule.** The
  autonomous callers that dispatch `/draft-plan` with a verbatim user
  description are: `/research-and-plan` → `/draft-plan output <path>
  <description>$AUTO_ARG` (`research-and-plan/SKILL.md:136`);
  `/research-and-go` → delegates through `/research-and-plan` (no direct
  dispatch, `research-and-go/SKILL.md:374`); and `/run-plan` delegate phases →
  `/draft-plan plans/FOO.md <description> auto` (`execute-phase.md:49`). In
  every case the description is positionally **after the output-file token**
  (whether spelled `output <path>` OR a bare leading `*.md`), so a "quiz" in
  the description is never in the leading cluster and never sets the flag.
  **Why the existing subagent-skip can't be relied on here (R2-F1a/DA2-F1a):**
  those callers load `/draft-plan` via the **Skill tool into their own
  top-level context** (`research-and-plan/SKILL.md:105-110`) — the executing
  agent still HAS the Agent tool, so the skip at `draft-plan/SKILL.md:310-313`
  is a *prose judgment about caller identity*, not a tool-list gate, and
  arg-parse (where the flag is set) happens *before* the checkpoint/skip is
  ever evaluated. The skip therefore cannot protect against a match-anywhere
  flag. The leading-flag parse is the **sole** guard, and it works by
  preventing the flag from being set at all. (Not "structural by construction"
  — it is correct *if the implementer follows the tokenization rule in Phase
  2*; that rule is the load-bearing artifact.)
- **Transcript capture:** the interview is recorded into the plan as a
  "Requirements captured via quiz" appendix (feeding the research summary and
  Plan Quality section) — a record, never the spec body. The running
  understanding summary is persisted **incrementally** to a file (not only at
  exit) so the interview survives context compaction (see Phase 1).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Author references/quiz.md (interaction protocol) | ✅ Done | `520aaab` | 331-line quiz.md; version 2026.06.01+ab6deb + mirror; 6773/6773 |
| 2 — Wire SKILL.md (flag, conditional load, seam, transcript) | ✅ Done | `ff1a562` | leading-flag QUIZ_FLAG + conditional-load seam + transcript wiring + gated step.*.quiz; version 2026.06.01+82b352 + mirror; conformance sanitize-count 4→5; 6773/6773 |
| 3 — Mirror, version reconcile, conformance + tests | ✅ Done | `e9cb987` | required co-occurrence wiring tripwire (references/quiz.md + QUIZ_FLAG=1, fails-closed); version 82b352 + mirror parity final; 6774/6774 |

---

## Phase 1 — Author references/quiz.md (interaction protocol)

### Goal
Create the conditionally-loaded `skills/draft-plan/references/quiz.md` that
fully specifies how the agent conducts the quiz interview, so the SKILL.md
seam (Phase 2) only needs a one-line "read this file and follow it."

### Work Items
- [ ] Create `skills/draft-plan/references/quiz.md` (the skill's first
  reference file — no `references/` dir exists today).
- [ ] Specify the **interview loop state machine**: `INTERVIEWING → (user types
  draft/go/ready) → DRAFTING`. The only transition edge out of `INTERVIEWING`
  is an explicit go-signal token.
- [ ] Specify the **research model — purely conversational, all research
  deferred** (v2 — supersedes the dropped "interleave" design; the simpler
  shape removes per-turn research latency):
  1. **No research during the quiz.** The agent conducts the interview from
     its own knowledge + whatever is already in context. NO upfront research
     agent, NO inline Explore dispatches mid-loop. (This also moots the earlier
     double-research / dispatch-cap concerns — there is no in-loop dispatch to
     bound.)
  2. **The ask-vs-defer rule:** ask the **user** about *intent, scope,
     priorities, preference* — anything only the user knows. For a *codebase
     fact* the agent is unsure of, do NOT interrogate the user (asking the user
     to recall code is the opposite annoyance); note it as an **open question**
     to be resolved by the post-`draft` fan-out.
  3. **All codebase research is the existing Phase-1 fan-out, unchanged**,
     running once *after* the user says `draft` — seeded with the durable
     interview file as priors (each fan-out agent: "here's what the interview
     established — validate and extend, don't re-derive"). This is a small
     additive seeding behavior on `/draft-plan`'s own fan-out (today it just
     hands each agent the description, `SKILL.md:200-228`; precedented by
     `/research-and-plan` handing a research file to its dispatch, `:134-135`).
  4. **Post-`go` surprise handling** (the one real trade-off of deferring all
     research): if the fan-out surfaces a fact that **contradicts a
     user-confirmed requirement**, surface it — minor conflicts into the
     research summary (caught by Phase-3 review); a hard contradiction pauses
     for a one-line "adjust or proceed?". Fires only on genuine conflict, not
     per-finding. The user reviews the finished plan regardless (Phase-6).
- [ ] Specify the **question style discipline**:
  - Prose-dominant: open questions ("what's actually in scope?", "what does
    done look like?") are asked as plain conversation text.
  - Structured (AskUserQuestion) **only** for genuinely closed forks with a
    small known option set (e.g. "landing mode: cherry-pick / PR / direct?").
  - **HARD RULE — free-text escape always present:** any AskUserQuestion the
    quiz issues MUST leave the user a free-text path and never force a choice
    among pre-baked options. The **load-bearing guarantee is layer (b)**, which
    is self-sufficient (DA round-2 #5 — do NOT rest the rule on an unanchored
    affordance): **(b, mandatory)** the agent authors an explicit invite-free-
    text cue in every structured prompt (e.g. "…or just tell me in your own
    words"), so the escape works regardless of harness behavior. **(a, bonus)**
    the AskUserQuestion tool contract also surfaces an "Other" free-text option
    — documented in the *tool's own schema*, NOT anchored anywhere in this
    repo, so treat it as a convenience that may exist, never as the guarantee.
    Rationale: a closed prompt can otherwise anchor/rubber-stamp the user
    toward the agent's framing — the exact failure the user reported that
    motivated quiz mode.
  - One question (or one tight cluster of genuinely-independent questions) per
    turn — never a 12-question wall.
- [ ] Specify the **running understanding summary**: after each answer, the
  agent restates the evolving spec ("So far — goal: X; in-scope: A, B;
  out-of-scope: C; open: D"). This is the single most valuable element and is
  why the style is prose-dominant (structured prompts have no room to mirror).
- [ ] **Persist interview state incrementally** (DA round-1 #3 — do NOT defer
  all persistence to exit): after each answer, the agent appends/rewrites the
  running understanding summary, surfaced-and-confirmed assumptions, and any
  open questions noted for the post-`draft` fan-out, to a durable file
  (`/tmp/draft-plan-quiz-<slug>.md`), mirroring how the existing skill writes
  its research to `/tmp/draft-plan-research-<slug>.md` (SKILL.md:294,299).
- [ ] **Specify the recovery-read path** (DA round-2 #3 — the write alone does
  NOT survive compaction): quiz.md MUST instruct that on resuming an
  in-progress quiz (after context compaction or any re-entry where the running
  understanding is no longer in context), the agent re-reads
  `/tmp/draft-plan-quiz-<slug>.md` to reconstruct state **before** issuing the
  next question. A file written every turn but never re-read leaves the agent
  resuming blind — the recovery read is what makes the persistence operational
  (compare `SKILL.md:226-228`, where the research file "persists through all
  phases" precisely because later phases re-read it).
- [ ] Specify **assumption-surfacing**: when the agent would otherwise guess,
  it states the assumption as a question ("I'm assuming X — correct?") rather
  than silently baking it in. This directly pre-empts the devil's-advocate
  "wrong assumptions" findings later.
- [ ] Specify the **readiness/termination contract** (propose, don't
  self-declare):
  - The agent ends each round by *offering* to stop, with an explicit
    instruction: "I think I have enough to draft. Reply `draft` (or `go` /
    `ready`) to start the adversarial review, or keep steering."
  - Terminate **only** on an explicit go-signal: **normalize the reply first**
    (DA round-2 #4 — don't trap a user whose signal has trivial punctuation):
    trim leading/trailing whitespace, strip a single trailing `.`/`!`/`?`,
    and case-fold; THEN test whole-message equality against the go-word set
    `draft` / `go` / `ready` / `proceed`. So `draft.`, `Go!`, ` ready `,
    `proceed?` all exit; a go-word plus *substantive* additional words does
    not. A go-word embedded inside a longer steering message ("use the **go**
    SDK", "the **ready** state should…", "**proceed** with Postgres but I still
    need to discuss auth") is **steering, not exit** (DA round-1 #4). If
    genuinely ambiguous, the agent re-poses the readiness offer rather than
    guessing.
  - A bare affirmation ("yes", "looks good") counts as the go-signal **only
    when it directly answers the agent's just-posed readiness question** —
    never mid-stream.
  - Honor an **unprompted** whole-message `draft` / `go` / `ready` at any point
    as an immediate early exit.
  - **No silent timeout, no round cap that auto-proceeds.** The user owns the
    exit in interactive mode.
- [ ] Specify **transcript capture**: at exit, the agent distills the durable
  interview-state file into a "Requirements captured via quiz" block that is
  (a) merged into the Phase-1 research summary file as confirmed requirements,
  and (b) appended to the final plan's Plan Quality section as a short record.
  Keep it a *distillation* (decisions + rationale), not a raw chat dump, so it
  informs without bloating the plan. (The incremental file above is the source
  of truth; this step distills it — the two are not redundant.)
- [ ] Add a one-paragraph header to quiz.md naming its trigger ("loaded only
  when the `quiz` token is present") and its place in the flow (the
  conversational interview runs *before* any research; on `draft` the existing
  Phase-1 fan-out runs, then Phase 2 drafts).
- [ ] **Bump `metadata.version` and stage SKILL.md in this phase's commit**
  (R2-F2 — feasibility, not cosmetic): `skill-version-stage-check.sh:59-63`
  gathers the affected skill from **any** staged file under
  `skills/draft-plan/`, so committing the new `references/quiz.md` while
  `SKILL.md`'s version still reads the old value trips the asymmetric
  "content changed, version unchanged" branch (`:135+`) and
  `block-stale-skill-version.sh` **rejects the commit**. So Phase 1's commit
  MUST also bump `skills/draft-plan/SKILL.md metadata.version` (canonical
  recipe in Phase 2 Design) and stage SKILL.md alongside quiz.md. (Each of the
  three phase commits touches the skill dir and therefore re-bumps; the final
  value is reconciled in Phase 3.)

### Design & Constraints
- **Authoring hazard — deny-list:** the conformance scanner
  (`tests/test-skill-conformance.sh:2144`) globs **all** `skills/**/*.md`,
  including this file, but only scans **exec-shaped** fences (bash/sh/no-lang)
  and code-span prose for forbidden literals. **Keep all example agent prose
  in narrative text or ` ```text ` fences** to sidestep the scanner entirely.
  If a real bash incantation is unavoidable and references a config var
  (`$TIMEZONE`, `$FULL_TEST_CMD`, etc.), source `zskills-resolve-config.sh`
  in/above the fence per the fence-local positive-side check.
- **No new frontmatter required** on reference files (only SKILL.md requires
  `metadata.version`).
- **Model rule:** quiz.md itself dispatches NO agents (research is deferred to
  the existing SKILL.md fan-out), so there is no agent-dispatch prose to
  constrain here. The fan-out's own model discipline is unchanged in SKILL.md.
  If a future edit ever adds a dispatch to quiz.md, it must use
  `subagent_type: "general-purpose"` and never bare `Explore` (Haiku-pinned per
  `.claude/rules/zskills/managed.md`).
- **No hooks, no scripts.** quiz.md is pure consulted protocol prose — it does
  not continue the persistent shell (that's what `modes/` files are for; this
  is correctly a `references/` file).

### Acceptance Criteria
- [ ] `skills/draft-plan/references/quiz.md` exists and contains all Work-Item
  specs above (state machine, conversational research model + ask-vs-defer
  rule + post-`go` surprise handling, question style + free-text-escape hard
  rule, understanding summary, incremental persistence, assumption-surfacing,
  termination contract, transcript capture, header).
- [ ] The file contains no forbidden literals in exec-shaped fences:
  `bash tests/test-skill-conformance.sh` passes its deny-list section with the
  new file present (verify after Phase 2 wires it, but the file must be clean
  on its own).
- [ ] **Conversational research model is specified (no in-loop research):**
  quiz.md states that the interview dispatches NO agents, gives the
  ask-vs-defer rule (intent→user; codebase facts→defer as open questions), and
  defers ALL research to the existing post-`draft` fan-out seeded with the
  interview file. A reader can tell whether a given question goes to the user
  or becomes a deferred open question.
- [ ] **Post-`go` surprise handling is specified:** quiz.md states that a
  fan-out finding contradicting a user-confirmed requirement is surfaced
  (minor → research summary + Phase-3 review; hard → one-line "adjust or
  proceed?"), and that this fires only on genuine conflict, not per-finding.
- [ ] **Incremental persistence AND recovery-read are specified:** quiz.md
  requires writing the running understanding to a durable file after each
  answer AND re-reading that file on resume/post-compaction before the next
  question — not a write-only path. (DA r1 #3 + r2 #3)
- [ ] The termination contract specifies a **normalized whole-message** go-
  signal match (trim/strip-trailing-punct/case-fold then equality), explicitly
  forbids exiting on a mid-stream "looks good" OR a go-word embedded in
  steering, accepts `draft.`/`Go!`/` ready `, and handles an unprompted
  go-signal. (DA r1 #4 + r2 #4)
- [ ] The free-text-escape rule makes **layer (b)** (agent-authored invite-
  free-text cue) the mandatory, self-sufficient guarantee; layer (a)
  (tool-contract "Other") is named as an unanchored convenience, not relied
  upon. (DA r1 #5 + r2 #5)
- [ ] If Phase 1 is committed independently, its commit bumps
  `metadata.version` + stages SKILL.md (R2-F2) and passes
  `bash scripts/skill-version-stage-check.sh`.

### Dependencies
None for authoring the spec — this is the leaf content. (Phase 2 reads it.)
NOTE: Phase 1's *commit* still touches `skills/draft-plan/` (adds quiz.md), so
it carries the version-bump obligation above.

---

## Phase 2 — Wire SKILL.md (flag, conditional load, seam, transcript)

### Goal
Plumb the `quiz` token through argument parsing, conditionally load
`references/quiz.md`, and insert the quiz loop at the correct seam in Phase 1
— without disturbing any downstream phase or the existing checkpoint's
subagent-skip.

### Work Items
- [ ] **Argument-hint frontmatter** (`SKILL.md:4`): add `[quiz]` to the
  `argument-hint` string.
- [ ] **Usage synopsis** (`:116`): add `[quiz]` to the
  `/draft-plan [output FILE] [rounds N] [auto] <description...>` line.
- [ ] **Recognized-pattern list** (after `:144`): add a bullet describing the
  `quiz` token — recognized **only as a leading flag token** (in the flag
  cluster before the description begins, like `output`/`rounds`), case-
  insensitive, sets `QUIZ_FLAG=1`; "conducts an interactive requirements
  interview before drafting; loads `references/quiz.md`. A `quiz` appearing
  within the description text is part of the description, not the flag."
- [ ] **Flag detection** (DA r1 #1 — leading-flag only, NOT match-anywhere
  like `auto`): the authoritative parse is the orchestrator's prose-driven
  leading-token scan (same pass that recognizes `output`/`rounds`/`auto`):
  `QUIZ_FLAG=1` iff `quiz` appears in the leading flag cluster, before the
  first description token. **Concrete tokenization the implementer MUST follow**
  (DA r2 #1b/#1c — "leading cluster" needs a definition, and the output token
  has TWO spellings): consume, in any order, the **output-file token** —
  either the literal `output <path>` OR a bare leading `*.md` token
  (`SKILL.md:135`) — plus `rounds N` (**consume the numeric value token after
  `rounds`**, else the bare `N` would be mis-read as the first description
  token), `auto`, and `quiz`; the **first token matching none of these**
  begins the description, and everything from there (including any later
  `quiz`) is description, not flags. Do **not** clone
  `auto`'s `(^|[[:space:]])quiz($|[[:space:]])` match-anywhere regex: a
  description word "quiz" (passed verbatim by `/research-and-plan`
  `:136`, or by `/run-plan` delegate `execute-phase.md:49` as
  `/draft-plan plans/FOO.md <desc> auto`) would otherwise set the flag in an
  autonomous run with no human to answer. If a bash fence is used for
  convenience, it MUST operate on the leading cluster (strip the description
  first), never raw `$ARGUMENTS`.
- [ ] **Conditional load + seam insertion** in Phase 1's "### Post-research
  tracking" region (the existing single-shot checkpoint at `:297-313`):
  - Replace the single-shot "Anything to add, correct, or steer?" checkpoint
    with a branch:
    - **When `QUIZ_FLAG=1` and running interactively** (not a subagent — same
      predicate as the existing `:310-313` skip): a conditional-load
      directive — `**Read [references/quiz.md](references/quiz.md) in full and
      follow its procedure end-to-end. Do not proceed until you have read that
      file.**` — then conduct the quiz loop per that file, exiting to Phase 2
      only on the explicit go-signal.
    - **When `QUIZ_FLAG=0`** (default): the existing single-shot checkpoint,
      verbatim and unchanged.
    - **When running as a subagent** (no `Agent` tool): the existing skip —
      proceed directly to Phase 2. (Quiz never reaches this branch in practice
      since the research-and-* callers don't pass `quiz`, but the guard is the
      same predicate and must remain.)
  - The branch sits **after** the scope-check decomposition branch
    (`:241-278`, which can `exit` to `/research-and-plan`) and **before**
    Phase 2 (`:315`). Confirm ordering is preserved.
- [ ] **Research-sequencing wiring:** specify in the SKILL.md that when
  `QUIZ_FLAG=1`, the conversational quiz runs FIRST (no research during it),
  and on `draft` the **existing Phase-1 fan-out runs unchanged**, seeded with
  the durable interview file as priors ("validate and extend, don't
  re-derive"), then Phase 2 drafts. (The interview mechanics live in quiz.md;
  SKILL.md just orders quiz-before-fan-out and passes the interview file in.)
  When `QUIZ_FLAG=0`, research runs exactly as today (full fan-out, then
  single-shot checkpoint). Note this is a strictly smaller SKILL.md change than
  the dropped interleave design — no research is split or moved, only gated
  behind the quiz and seeded.
- [ ] **Transcript capture wiring:** after the quiz exits, the agent merges
  the captured requirements into `/tmp/draft-plan-research-<slug>.md` (the
  existing research summary file) and the Plan Quality section gains a
  "Requirements captured via quiz" subsection (Phase 6). Reference the
  quiz.md transcript-capture spec; do not duplicate it.
- [ ] **Optional `step.*.quiz` tracking marker** (for convention symmetry with
  research/review/finalize markers): when `QUIZ_FLAG=1`, write
  `step.draft-plan.$TRACKING_ID.quiz` at quiz exit by cloning the **full**
  research-marker fence at `SKILL.md:284-294` — including the `MAIN_ROOT` +
  `PIPELINE_ID` derivation and the `sanitize-pipeline-id.sh` call (R2-F4 — NOT
  just the `:293-294` `printf` lines; copying the printf alone risks an empty
  `PIPELINE_ID` flat-marker write, the exact #852 bug surfaced this session).
  Informational only (not hook-gated). Gate behind `QUIZ_FLAG=1` so a normal
  run never emits it.
- [ ] **Version bump** (`metadata.version`, `:10` — currently
  `2026.05.31+c60020`): bump after edits via the canonical recipe (see
  Design). NOTE: a final reconcile happens in Phase 3 after the mirror; this
  per-phase bump satisfies the commit-time gate for Phase 2's commit.

### Design & Constraints
- **Token false-positive — deliberately NOT inherited from `auto`.** `auto`
  uses a match-anywhere regex, so a description word "auto" trips `AUTO_FLAG`;
  that exposure is pre-existing and out of scope here. `quiz` does **not**
  copy it (DA finding #1, confirmed via `research-and-plan/SKILL.md:136`
  passing the user description verbatim to `/draft-plan` at top-level
  `:105-110`): a stray "quiz" in an autonomously-dispatched description would
  hang the pipeline on an interactive prompt. Leading-flag recognition is the
  fix — quiz only fires when it leads, and those callers' descriptions are
  positionally after `output <path>`. (If `auto`'s own false-positive is ever
  worth fixing, that is a separate change.)
- **Version-bump recipe** (mandatory on any skill-dir edit; canonical
  projection covers SKILL.md + every file under the skill dir):
  ```bash
  TODAY=$(TZ=America/New_York date +%Y.%m.%d)
  HASH=$(bash scripts/skill-content-hash.sh skills/draft-plan)
  bash scripts/frontmatter-set.sh skills/draft-plan/SKILL.md metadata.version "$TODAY+$HASH"
  ```
- **Do not touch downstream phases.** No phase after Phase 1 reads checkpoint
  state; the change is structurally contained to the `:297-313` region plus
  the arg-parse additions.
- **Preserve the subagent-skip** at `:310-313` exactly — it is load-bearing
  for the research-and-* callers.

### Acceptance Criteria
- [ ] `QUIZ_FLAG` is set by **leading-flag** detection (not `auto`'s
  match-anywhere regex); `argument-hint`, synopsis, and recognized-pattern
  list all name `quiz` and state it is a leading flag. A description word
  "quiz" does NOT set the flag — add an explicit negative example to the
  Examples block (e.g. `/draft-plan output p.md build a quiz app` → flag NOT
  set), alongside the existing `README.md` precedent. (DA r1 #1, r2 #1b)
- [ ] The Examples/argument-hint explicitly note that a **trailing** `quiz`
  (`/draft-plan add dark mode quiz`) is description text, not the flag —
  the accepted ergonomic limitation of leading-only parsing. (R2-F1b)
- [ ] With `quiz` absent, `/draft-plan` behaves **identically to today** —
  full Phase-1 fan-out then the single-shot checkpoint; quiz.md is never read;
  no `step.*.quiz` marker is written. (Verify by reading the QUIZ_FLAG=0
  branch — it must be the unmodified original checkpoint prose.)
- [ ] With `quiz` present (interactive), the SKILL.md instructs the agent to
  read `references/quiz.md` and run the loop, deferring the full research
  fan-out until after the go-signal.
- [ ] The quiz branch sits after the scope-check decomposition `exit` and
  before Phase 2; the subagent-skip is intact.
- [ ] **Transcript-capture wiring is present** (R5): SKILL.md instructs the
  agent, after the quiz exits, to merge the captured requirements into
  `/tmp/draft-plan-research-<slug>.md` and to add a "Requirements captured via
  quiz" subsection in the Phase-6 Plan Quality section (referencing quiz.md's
  capture spec, not duplicating it).
- [ ] The optional `step.*.quiz` marker, if wired, is gated behind
  `QUIZ_FLAG=1` so a normal (non-quiz) run never emits it.
- [ ] `metadata.version` is bumped (date = today America/New_York, hash
  recomputed) and the stage-check passes:
  `bash scripts/skill-version-stage-check.sh` (or `/commit` step 2.5) does not
  STOP on the draft-plan commit.

### Dependencies
Phase 1 (the conditional load targets `references/quiz.md`, which must exist).

---

## Phase 3 — Mirror, version reconcile, conformance + tests

### Goal
Finalize the source version, propagate source edits byte-for-byte to the
installed legacy-lane mirror, add the wiring tripwire, and prove the change
passes all conformance gates and the test suite.

### Work Items
- [ ] **Finalize the SOURCE version FIRST** (R2 — correcting a false premise:
  mirroring cannot stale the source hash; `skill-content-hash.sh` hashes the
  source dir only via `find "$SKILL_DIR"` and redacts `metadata.version`
  before hashing, `scripts/skill-content-hash.sh:198-202,254`). Once **all**
  source edits to `skills/draft-plan/` (SKILL.md + `references/quiz.md`) are
  final, bump the source `metadata.version` once (date = today ET, hash =
  fresh `skill-content-hash.sh skills/draft-plan`). After this, the source
  hash is final — nothing downstream restales it.
- [ ] **Mirror byte-for-byte** `skills/draft-plan/` → `.claude/skills/draft-plan/`
  via a **batch copy** (not per-file Edit — per-Edit mirror writes trigger
  permission storms; see memory `feedback_claude_skills_permissions`),
  including the new `references/quiz.md` AND the finalized SKILL.md. The mirror
  SKILL.md's `metadata.version` must be **identical** to the source's (R3 —
  mirror-parity at `tests/test-skill-conformance.sh:2764-2771` compares the
  mirror's stored hash-suffix against the source's fresh projection, so the
  version strings must match exactly; "modulo the version field" is wrong).
  Simplest correct procedure: bump source first (above), then copy source over
  the mirror verbatim.
- [ ] **Run the suite** capturing output out-of-tree:
  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"; mkdir -p "$TEST_OUT"
  bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
  ```
  Read the results file; the suite must pass with the same suite list as a
  clean baseline (report each suite + result, not "all pass").
- [ ] **Targeted conformance:** confirm `tests/test-skill-conformance.sh`
  passes — specifically (a) the deny-list section with `references/quiz.md`
  present, (b) the skill-version stale-hash check
  (`:2722-2728`) for `skills/draft-plan`, (c) the mirror-parity check
  (source vs `.claude/skills` copy identical).
- [ ] **Conformance tripwire (required, R9):** add a targeted assertion to
  `tests/test-skill-conformance.sh` that the `quiz` wiring is present. It MUST
  check **co-occurrence** (R2-F5 — a bare substring grep for `references/quiz.md`
  would still pass if the conditional were degraded to an unconditional read,
  or if the string survived only in a comment): assert that
  `skills/draft-plan/SKILL.md` contains BOTH a `references/quiz.md` reference
  AND a `QUIZ_FLAG`-conditional token, in the same region. There is no
  orphan-reference gate today, so without this the conditional load is
  unprotected. Keep it one targeted assertion, not a generic sweep. (This is
  the only automated check that exercises the new wiring; the Phase-1 prose
  ACs are reviewer-checked, not regression-gated — R2-F3.)
- [ ] **No CHANGELOG / README update (R10):** this is a skill-internal change;
  zskills ships skill edits via PR without per-change CHANGELOG entries. Stated
  explicitly so the implementer does not guess that one is required.

### Design & Constraints
- **Mirror parity is gated by CI** — source and `.claude/skills` copy must be
  byte-identical **including the `metadata.version` field** (R3). The
  mirror-parity check (`tests/test-skill-conformance.sh:2764-2771`) compares
  the mirror's stored version hash-suffix against the source's *freshly
  computed* projection, and the source's own stale-hash check
  (`:2723-2725`) forces the source version to equal its fresh hash — so all
  three must agree. There is **no** "reconcile after mirror" step: bump the
  source version once, after all source edits are final (the hash redacts the
  version field and ignores the mirror dir, so it cannot restale), then copy
  source → mirror verbatim. (DA r2 #6: CI only compares the version *hash
  suffix*, not the date portion; "byte-identical including version" is a
  stronger-than-required but simpler-to-execute rule — adopt it.)
- **Capture test output to a file, never pipe** (CLAUDE.md). Compute
  `$TEST_OUT` from `$(pwd)` after `cd`-ing to the worktree root.
- **Do not weaken any test** to make it pass. If conformance fails, fix the
  source (most likely a forbidden literal in an exec fence in quiz.md → move
  it to a `text` fence, or a stale version hash → re-bump).

### Acceptance Criteria
- [ ] `.claude/skills/draft-plan/` mirrors `skills/draft-plan/` exactly,
  including `references/quiz.md`; mirror-parity conformance passes.
- [ ] `metadata.version` (source and mirror) matches a freshly recomputed
  `scripts/skill-content-hash.sh skills/draft-plan`; the stale-hash CI check
  passes.
- [ ] `bash tests/run-all.sh` passes — every suite reported by name with its
  result; no suite skipped without a stated reason.
- [ ] `tests/test-skill-conformance.sh` passes in full (deny-list, version,
  mirror parity).
- [ ] The wiring tripwire (now required) passes and would fail if the
  `references/quiz.md` conditional load were removed (sanity-check by
  reasoning, not by actually breaking it).

### Dependencies
Phases 1 and 2 (mirror copies their output; the source version hash is
finalized here after both phases' edits land).

---

## Plan Quality

**Drafting process:** /draft-plan in interactive `quiz`-style mode (the
feature dogfooded itself — the design was elicited through a live user
interview), followed by multiple rounds of adversarial review (reviewer +
devil's-advocate + refiner).
**Convergence:** Converged at round 4. Rounds 1-3 hardened the original
(interleave) design; after round 3 the research model was redesigned to
purely-conversational (simpler, removes per-turn research latency) and round 4
re-attacked the redesign (1 defect + 3 cleanups, all fixed). Round 1 was
initially — and wrongly — declared converged;
the user challenged that (criticals fixed via substantive rewrites still need
a verifying pass), and round 2 then found 5 substantive issues the round-1
fixes had missed or introduced (Phase-1 commit version-bump feasibility bug,
double-research cost, missing recovery-read path, punctuation exit-trap, a
false-"verified" disposition). Round 2 fixed all five; round 3 verified them
sound with no new substantive issues (2 non-gating nits applied). **Process
lesson:** declaring convergence in the same round that fixes a CRITICAL via
rewrite is unsafe — the rewrite needs its own adversarial pass.
**Remaining concerns:** None substantive. The leading-flag parse is
agent-judgment-following-prose (not a verifiable regex); the Phase-2
tokenization spec is the load-bearing artifact and must be followed exactly.

### Requirements captured via quiz (transcript distillation)

The design above was settled through an interactive interview with the user.
Decisions and their rationale:

1. **`quiz` + `auto` compose for an interactive human.** Initial research
   conflated `/research-and-go`'s `auto` (skip checkpoints) with
   `/draft-plan`'s `auto` (Phase-6 auto-land). The user corrected this: in
   `/draft-plan`, `auto` only governs landing, so a human typing
   `/draft-plan quiz auto …` gets "interview me, then auto-land the PR." → The
   two flags do not suppress each other.
2. **The non-interactive leak is closed by leading-flag parsing, not by a
   runtime guard.** The user's intent was "quiz is human-opt-in only." The
   adversarial review (DA #1) then proved that the *original* design (match-
   anywhere regex like `auto`) would leak: `/research-and-plan` passes the user
   description verbatim to `/draft-plan` (`research-and-plan/SKILL.md:136`) at
   top-level with the Agent tool (`:105-110`), so a description word "quiz"
   would set the flag in an autonomous `auto` run and hang on a prompt no human
   will answer — and the subagent-skip predicate does not fire there. **Fix:**
   recognize `quiz` only as a *leading flag token* (those callers' descriptions
   are positionally after `output <path>`), making "human-opt-in only" true by
   construction with no suppression machinery — exactly the user's intent,
   achieved structurally.
3. **Free-text escape is mandatory on every structured prompt.** The user
   reported being forced to leave a structured question because no free-text
   option was apparent. → Hard rule in quiz.md (two layers per DA #5): rely on
   the tool-contract "Other" option AND author an explicit invite-free-text
   cue in every structured prompt. AskUserQuestion is an optional accelerator
   on closed forks, never a cage.
4. **Research model — purely conversational, all research deferred (v2).**
   Originally the user selected an "interleave" model (light upfront research +
   inline dispatches). After the plan converged, the orchestrator flagged
   interleave as the riskiest / most likely over-engineered piece (per-turn
   research latency, ask-vs-dispatch misfire risk), and the user agreed to
   switch: the quiz is now a pure conversation, with ALL codebase research
   deferred to the existing post-`draft` fan-out (seeded with the interview
   file). Accepted trade-off (raised by the user): research can surface
   something after `go` — handled by the post-`go` surprise rule (surface
   genuine contradictions, don't silently draft around them). This is the
   [[feedback_dont_overengineer_edge_cases]] instinct applied: ship the simple
   default, earn complexity later.
5. **Termination** (user-approved): explicit `draft`/`go`/`ready` as a
   whole-message signal; agent proposes readiness each round; never exits on a
   mid-stream "looks good" or a go-word embedded in steering (DA #4).
6. **Transcript capture** (user-approved): record the interview as a
   distillation in the plan (research summary + this Plan Quality subsection),
   not a raw dump. Refined (DA #3) to persist interview state to a durable file
   *incrementally* so it survives context compaction, not only at exit.

A tracking robustness bug surfaced during this session (silent flat-marker
write on empty `PIPELINE_ID`) was filed separately as **#852** rather than
folded into this plan.

### Round History

| Round | Reviewer | Devil's Advocate | Resolved |
|-------|----------|------------------|----------|
| 1 | 6 (2 CRITICAL hash/mirror, 1 AC gap, 1 test gap, 2 minor; line-cites clean) | 7 (1 CRITICAL leak, 3 MAJOR spec gaps, 1 escape-affordance, 1 thin-AC, 1 clean) | 13/13 |
| 2 (verify r1 fixes) | 5 (1 MAJOR commit-order feasibility, 1 wrong-rationale ×3, 1 trailing-flag ergonomics, 2 nits) | 7 (3 MAJOR: double-research, missing recovery-read, punctuation trap; 1 MAJOR false-"verified"; 3 rationale/def nits) | 12/12 |
| 3 (verify r2 fixes) | combined pass: 0 substantive, 2 nits (applied) | — | converged (then redesigned) |
| 4 (verify v2 redesign) | combined pass on the interleave→conversational switch: 1 defect (stale "inline-Explore" ref), 3 cleanups (motivation over-claim, quiz+auto/pause reconcile, disposition annotation) — all applied | — | CONVERGED |

**Disposition (all empirical claims reproduced by the refiner before acting):**

| # | Finding | Evidence | Disposition |
|---|---------|----------|-------------|
| R1 | SKILL.md line-cites correct | Verified (read SKILL.md:4,10,116,148-153,241-278,297-313,315) | Justified — no change |
| R2 | version-reconcile rationale false (mirror can't stale source hash; version redacted) | Verified (`skill-content-hash.sh:198-202,254`) | Fixed — Phase 3 rewritten: bump source last, no reconcile |
| R3 | "modulo version field" wrong; mirror version must match | Verified (`test-skill-conformance.sh:2764-2771,2723-2725`) | Fixed — Phase 3 mirror = byte-identical incl. version |
| R5 | missing Phase-2 AC for transcript + step.quiz | Cross-read | Fixed — ACs added |
| R9 | no test exercises quiz token | Verified (grep, feature is new) | Fixed — tripwire promoted to required |
| R10 | CHANGELOG status unstated | Judgment | Fixed — explicit "none needed" WI |
| DA1 | match-anywhere leaks into autonomous research-and-* run | Verified (`research-and-plan/SKILL.md:136,105-110`) | Fixed — leading-flag recognition |
| DA2 | interleave terms under-specified | Judgment | Fixed in r1 (decision rule + dispatch cap + bounded upfront) — **superseded by v2**, which removes in-loop research entirely |
| DA3 | state persistence at-exit loses on compaction | Verified (`SKILL.md:294,299`) | Fixed — incremental durable persistence |
| DA4 | termination go-word-as-content hole | Judgment | Fixed — whole-message match |
| DA5 | free-text escape relies on unverified affordance | Partially reproduced — "Other" IS documented in tool contract | Justified + Fixed — two-layer (Other + explicit cue) |
| DA6 | Phase-1 ACs too thin | Cross-read | Fixed — quality ACs added (DA2/3 testable) |
| DA7 | no constraint violations | Verified (Haiku/jq/main/tests scan clean) | Justified — no change |

**Round-2 disposition (verifying the round-1 fixes):**

| # | Finding | Evidence | Disposition |
|---|---------|----------|-------------|
| R2-F2 | Phase-1 commit (adds quiz.md, no bump) rejected by stage-check | Verified (`skill-version-stage-check.sh:59-63,135+`) | Fixed — Phase-1 WI now bumps version + stages SKILL.md |
| R2-F1a/DA2-F1a | "subagent-skip doesn't fire" rationale conflates skip-predicate with tool-list | Verified (`research-and-plan/SKILL.md:105-110`) | Fixed — rationale corrected (skip is prose caller-identity, can't gate arg-parse) |
| R2-F1b/DA2-F1b | trailing `quiz` broken (unacknowledged); 2nd caller `/run-plan` delegate uses bare `.md` | Verified (`execute-phase.md:49`) | Fixed — tokenization covers both output forms; trailing-limit AC added |
| DA2-F1c | "structural by construction" overstates a prose-judgment parse | Judgment | Fixed — reframed; concrete tokenization required |
| DA2-F2 | double-research cost (up to 8 dispatches), no dedup | Verified (`SKILL.md:200-228`) | Fixed — fan-out seeded with interview priors |
| DA2-F3 | recovery-READ path missing (write-only ≠ compaction-safe) | Verified (`SKILL.md:226-228`) | Fixed — recovery-read WI + AC added |
| DA2-F4 | whole-message match traps `draft.`/`Go!`/` ready ` | Judgment | Fixed — normalize (trim/strip-punct/case-fold) then match |
| DA2-F5 | layer-(a) "Other" marked verified but unanchored in-repo | Verified (repo grep: 0 hits) | Fixed — layer-(b) is the guarantee; (a) demoted to convenience |
| R2-F4 | step.quiz WI under-references fence → #852 risk | Verified (`SKILL.md:284-294`) | Fixed — clone FULL fence incl. derivation+sanitize |
| R2-F5 | tripwire substring grep under-protects | Judgment | Fixed — co-occurrence assertion required |
| R3 nits | `rounds N` value-consume implicit; dedup citation over-reads | Verified | Fixed — both applied |
