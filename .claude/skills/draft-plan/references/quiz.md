# /draft-plan — Quiz mode

> Loaded by `SKILL.md` **only when the `quiz` token is present** (progressive
> disclosure). This file is the complete, self-contained interaction protocol the
> orchestrator follows when quiz mode is active: the interview loop state machine,
> the purely-conversational research model, the question-style discipline, the
> running understanding summary, incremental persistence + recovery-read, the
> readiness/termination contract, and the transcript-capture distillation. SKILL.md
> Reads this file and runs its interview loop INLINE — the quiz dispatches no
> sub-agents.

Quiz mode inserts a collaborative, multi-turn **requirements interview** at the
very front of `/draft-plan`, *before* any research runs. Its purpose is to let the
agent extract the user's actual intent — goal, scope, priorities, preferences —
through conversation, instead of guessing from a one-line description and then
discovering the wrong assumptions late in the adversarial pipeline. The
conversational interview runs first; when the user signals readiness with a
whole-message go-word (`draft` / `go` / `ready` / `proceed`), the existing Phase-1
research fan-out runs — now *seeded with the durable interview file as priors* —
and then Phase 2 drafts the plan. Quiz mode does **no research of its own**: it is
pure conversation against the agent's existing knowledge, and every codebase
uncertainty is deferred to the fan-out as an open question rather than interrogated
out of the user.

---

## Slug pinning — the durable interview file

The quiz writes its durable state to a `/tmp` file whose slug is the deterministic
`$TRACKING_ID` the SKILL.md preamble computes (`basename "$OUTPUT_FILE" .md | tr A-Z
a-z | tr _ -`, at `skills/draft-plan/SKILL.md:85`). `$TRACKING_ID` is already in
scope when this stage runs. **Use it verbatim** — do NOT recompute a slug from the
description.

- **interview file:** `/tmp/draft-plan-quiz-$TRACKING_ID.md`

This mirrors how the existing skill persists its research to
`/tmp/draft-plan-research-<slug>.md` (`SKILL.md:259-265`) and how brainstorm mode
persists to `/tmp/draft-plan-brainstorm-$TRACKING_ID.md`. As with the research
file, do NOT assume slug parity with the research file — the research `<slug>` is
loose orchestrator-chosen prose; the quiz file uses `$TRACKING_ID` and the
feed-forward passes the **literal** `/tmp/draft-plan-quiz-$TRACKING_ID.md` string
into the fan-out prompts, never a re-derived path.

---

## Interview loop — state machine

Quiz mode is a two-state machine:

```text
        ┌──────────────┐
        │ INTERVIEWING │◀──────── (any non-go-signal reply: steer, answer,
        └──────┬───────┘            clarify) loops back to INTERVIEWING
               │
               │  user reply normalizes to a whole-message go-word
               │  (draft / go / ready / proceed)
               ▼
         ┌────────────┐
         │  DRAFTING  │  → hand off to the existing Phase-1 fan-out (seeded
         └────────────┘     with the interview file), then Phase 2 drafts.
```

- **INTERVIEWING** is the start state. Each round the agent (1) re-reads the
  durable interview file if its own state is not in context (recovery-read, below),
  (2) restates the running understanding summary, (3) surfaces any new assumption as
  a question, (4) asks ONE question (or one tight cluster of genuinely-independent
  questions), (5) persists the updated understanding to the durable file, and (6)
  offers the readiness exit.
- The **only** transition edge out of INTERVIEWING is an explicit go-signal token
  (see the termination contract). Any other reply — an answer, a clarification, a
  course-correction, even an enthusiastic "this is great" — keeps the machine in
  INTERVIEWING.
- **DRAFTING** is terminal for the quiz: control returns to SKILL.md, which runs
  the existing research fan-out and then drafts. The quiz does not re-enter
  INTERVIEWING once it has transitioned.

---

## Research model — purely conversational, all research deferred

Quiz mode does **no research during the interview.** The agent conducts the whole
conversation from its own knowledge plus whatever is already in context. There is
NO upfront research agent and NO inline Explore dispatch mid-loop. (Because there is
no in-loop dispatch at all, there is nothing to bound, double-count, or cap — the
quiz is latency-free conversation.)

### The ask-vs-defer rule

This is the load-bearing distinction that tells the agent where every uncertainty
goes:

- **Ask the USER** about anything only the user knows: **intent, scope, priorities,
  preferences, success criteria, constraints they care about.** These are the
  questions the interview exists to answer. Examples: "what's actually in scope?",
  "what does done look like?", "is backward-compat a requirement or can we break
  the old format?", "which of these two behaviors do you want as the default?"
- **DEFER as an open question** any *codebase fact* the agent is unsure of — the
  shape of an existing function, whether a helper already exists, how a current hook
  behaves, where a literal lives. Do NOT interrogate the user about code: asking the
  user to recall the codebase is the opposite annoyance and produces unreliable
  answers. Instead, note it in the durable file's open-questions list, phrased as a
  research task, to be resolved by the post-`draft` fan-out.

A reader of this file (or a reader of the durable interview file) can always tell
which bucket a given uncertainty landed in: user-facing intent questions are asked
in the conversation; codebase facts are written down as deferred open questions.

### All codebase research is the existing fan-out, seeded

When the user says `draft`, control returns to SKILL.md and the **existing Phase-1
research fan-out runs unchanged** (`SKILL.md:226-265`), with one small additive
behavior: each fan-out agent is **seeded with the durable interview file as priors**
— "here is what the interview established with the user; validate and extend it,
do not re-derive it." This is the same seeding shape brainstorm mode already uses
(`SKILL.md:231-240`, injecting the brainstorm notes path into each research prompt)
and that `/research-and-plan` uses when it hands a research file to its dispatch
(`SKILL.md:134-135`). The fan-out is also handed the deferred open-questions list so
the Codebase / Prior-art agents specifically resolve them.

### Post-`go` surprise handling

Deferring all research to after the go-signal has one real trade-off: the fan-out
may surface a codebase fact that **contradicts a requirement the user confirmed**
during the interview. Handle it by severity, and **only on a genuine conflict** (not
once per finding — most findings simply extend the plan):

- **Minor contradiction** (the confirmed requirement is still achievable with a
  small adjustment, or the conflict is a detail): record it in the research summary
  as a flagged note. It is caught and surfaced by the existing Phase-3 adversarial
  review, and the user reviews the finished plan regardless (Phase 6).
- **Hard contradiction** (a user-confirmed requirement is infeasible or directly
  conflicts with a discovered fact): pause and ask the user a single one-line
  question — "the research found X, which conflicts with your requirement Y; adjust
  or proceed?" — then continue.

This handling fires **only on genuine conflict with a confirmed requirement**, never
as a per-finding interruption.

---

## Question-style discipline

The interview is **prose-dominant.** Open questions — the ones that draw out intent
and scope — are asked as plain conversation text, because plain text is what lets
the agent also mirror its running understanding back to the user in the same turn (a
structured prompt has no room to restate the evolving spec). Examples of prose
questions: "What's actually in scope here — just the happy path, or do you want the
error cases covered too?" / "What does 'done' look like to you?" / "Which of these
matters more: speed of landing, or test coverage?"

Use **AskUserQuestion only for genuinely closed forks** — a small, known set of
mutually-exclusive options where structure genuinely helps. Example: "Landing mode —
cherry-pick, PR, or direct?" Do NOT wrap an open intent question in a structured
prompt.

Ask **one question per turn**, or at most one tight cluster of genuinely-independent
questions. Never present a 12-question wall — it overwhelms the user and defeats the
conversational design.

### HARD RULE — a free-text escape is always present

Any AskUserQuestion the quiz issues MUST leave the user a free-text path and MUST
NOT force a choice among pre-baked options. A closed prompt with no escape can
anchor or rubber-stamp the user toward the agent's framing — the exact failure mode
that motivated quiz mode. The guarantee has two layers, and **the load-bearing one
is layer (b):**

- **(b) MANDATORY — the agent authors an explicit invite-free-text cue in every
  structured prompt.** Phrase one option, or the prompt text itself, to explicitly
  invite a free-text answer — e.g. add a final option worded "Something else — let
  me describe it" or end the prompt with "…or just tell me in your own words." This
  is self-sufficient: it works regardless of any harness behavior, and the rule
  rests entirely on it. Do NOT skip this on the assumption that the tool provides an
  escape for you.
- **(a) BONUS — the AskUserQuestion tool contract may also surface an "Other"
  free-text option.** This is documented in the *tool's own schema* and is NOT
  anchored anywhere in this repo, so treat it as a convenience that *may* exist —
  never as the guarantee. Layer (b) is what you rely on.

---

## Running understanding summary

After each answer, the agent restates the evolving spec back to the user before
asking the next question. This is the single most valuable element of the interview
— it surfaces misunderstandings immediately and is the reason the style is
prose-dominant. The summary takes a compact, consistent shape, for example:

```text
So far —
  Goal: <one line>
  In scope: <A>, <B>
  Out of scope: <C>
  Confirmed assumptions: <…>
  Open (for research): <D>, <E>
```

Restate it **every turn**, updated with the latest answer, so the user always sees
the current state of the agreed-upon spec and can correct drift in one reply.

---

## Incremental persistence + recovery-read

### Persist after every answer (do NOT defer to exit)

After each answer, the agent **appends/rewrites** the durable interview file
`/tmp/draft-plan-quiz-$TRACKING_ID.md` with:

- the current running understanding summary (goal / in-scope / out-of-scope),
- the assumptions surfaced and confirmed so far,
- the open questions noted for the post-`draft` fan-out.

This mirrors how the existing skill writes its research to
`/tmp/draft-plan-research-<slug>.md` after each phase (`SKILL.md:259-265`). The file
carries a `status:` field — `in-progress` while INTERVIEWING, flipped to `complete`
at the go-signal — so a resume can tell whether the interview finished.

### Recovery-read on resume / post-compaction (the write is not enough)

A file written every turn but never re-read leaves the agent resuming **blind** after
context compaction. So quiz.md REQUIRES: on resuming an in-progress quiz — after a
context compaction, or any re-entry where the running understanding is no longer in
context — the agent **re-reads `/tmp/draft-plan-quiz-$TRACKING_ID.md` to reconstruct
state BEFORE issuing the next question.** Only then does it restate the summary and
continue. This is what makes the persistence operational: it is the same pattern by
which the research file "persists through all phases" precisely because later phases
re-read it (`SKILL.md:265`). Write-only persistence is explicitly NOT sufficient.

---

## Assumption-surfacing

Whenever the agent would otherwise silently guess at a requirement, it instead
**states the assumption as a question** and waits for confirmation — "I'm assuming we
only need to support the JSON format, not the legacy CSV — is that right?" rather than
quietly baking the guess into the eventual plan. Confirmed assumptions move into the
running summary's "Confirmed assumptions" line and into the durable file. This
directly pre-empts the "wrong assumptions" findings the devil's-advocate would
otherwise raise late in the pipeline.

---

## Readiness / termination contract — propose, don't self-declare

The agent **proposes** readiness; it never silently decides the interview is over.

### Offer the exit each round

End each round with an explicit readiness offer, for example: "I think I have enough
to draft. Reply `draft` (or `go` / `ready`) to start the adversarial review, or keep
steering." The offer names the exact go-words so the user knows the magic tokens.

### Terminate ONLY on a normalized whole-message go-signal

Before testing any reply as a go-signal, **normalize it**:

1. Trim leading/trailing whitespace.
2. Strip a single trailing `.` / `!` / `?`.
3. Case-fold.

THEN test **whole-message equality** against the go-word set `draft` / `go` /
`ready` / `proceed`.

- Replies that **exit** (each normalizes to a bare go-word): `draft`, `go`,
  `ready`, `proceed`, `draft.`, `Go!`, ` ready ` (surrounding whitespace),
  `proceed?`.
- Replies that do **NOT** exit: a go-word plus substantive additional words. A
  go-word embedded inside a longer steering message is **steering, not exit** —
  e.g. "use the **go** SDK", "the **ready** state should reset the counter",
  "**proceed** with Postgres but I still need to discuss auth." These keep the
  machine in INTERVIEWING.
- If a reply is **genuinely ambiguous** as to whether it's an exit, the agent
  **re-poses the readiness offer** rather than guessing.

### Bare affirmations only answer a just-posed readiness question

A bare affirmation ("yes", "yep", "looks good", "sounds good") counts as the
go-signal **only when it directly answers the agent's just-posed readiness offer**.
A mid-stream "looks good" — said while the agent asked something else, or
unprompted — is steering/acknowledgement, NOT an exit. Never exit on a mid-stream
"looks good."

### Honor an unprompted go-signal

If the user types a whole-message `draft` / `go` / `ready` / `proceed` (after
normalization) at any point — even when the agent did not just offer the exit —
honor it as an immediate early exit.

### No silent timeout, no auto-proceed cap

There is **no silent timeout and no round cap that auto-proceeds.** In interactive
mode the user owns the exit; the interview continues until the user gives an explicit
go-signal.

---

## Transcript capture — distill, don't dump

At exit (the go-signal), the agent flips the durable file's `status:` to `complete`
and produces a **"Requirements captured via quiz"** distillation — decisions plus
their rationale, NOT a raw chat transcript. The durable interview file is the source
of truth; this step distills it so it informs without bloating the plan. The
distillation is used in two places:

- **(a) Merged into the Phase-1 research summary file** as confirmed requirements,
  so each research agent treats the interview-established intent as a given to
  validate and extend (the seeding described in the research model above).
- **(b) Appended to the final plan's "Plan Quality" section** as a short record —
  a few lines noting the requirements were elicited through a quiz interview and the
  key decisions/assumptions confirmed. This documents *how* the plan's requirements
  were grounded without reproducing the conversation.

Keep both to a distillation. The incremental durable file and this distilled capture
are **not redundant**: the former is the live, every-turn state of truth; the latter
is the compact, durable record that feeds research and the plan.

---

## What quiz mode does NOT do

- It dispatches **no sub-agents** (all research is the existing post-`draft`
  fan-out). If a future edit ever adds a dispatch here, it must use
  `subagent_type: "general-purpose"` and never a bare `Explore` (which is
  Haiku-pinned per `.claude/rules/zskills/managed.md`).
- It defines **no hooks and no scripts.** quiz.md is pure consulted protocol prose;
  it does not continue any persistent shell (that is what `modes/` files are for —
  this is correctly a `references/` file).
- It requires **no new frontmatter** — reference files carry none; only SKILL.md
  carries `metadata.version`.
