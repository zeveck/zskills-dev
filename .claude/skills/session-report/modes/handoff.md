# /session-report handoff — durable end-of-session hand-off

You reach this file ONLY when `/session-report handoff` was invoked. The
default `/session-report` is deliberately retrospective ("audit what THIS
session said it would do vs. what shipped"; "Do not invent next actions").
**`handoff` inverts that posture: it is forward-looking by design.** It
captures in-flight concerns, pending work, and the context needed to
resume — then persists that to memory and hands you a ready-to-act
message. Run this near full context, at the end of a long session, before
`/clear` or `/compact`.

The procedure has two phases — a **retrospective phase** (Part 1) that
reuses the default audit verbatim, and a **forward phase** (Parts 2–4)
that is unique to this mode.

## Part 1 — Retrospective (reuse the default audit)

Run **Steps 1–3 of `SKILL.md`** exactly as written:

1. **Step 1** — Enumerate session intent (every concrete deliverable the
   session said would happen).
2. **Step 2** — Verify each intent item against ground truth (git, PRs,
   plans, worktrees, tracking markers — minimal verification per item).
3. **Step 3** — Reconcile each into a status bucket (Done & shipped, Done
   locally not shipped, In flight, Blocked, Not started).

This produces the **"work done"** summary. Do NOT run Step 4 (its
retrospective report format is not what `handoff` emits). Keep the
per-item status buckets; you reuse them in the ready-message below.

## Part 2 — Forward capture

Now switch posture: look forward, not back. Capture what a fresh session
would need to continue. From the conversation and the verified state, list:

- **In-flight concerns** — work started but not finished, decisions left
  open, anything load-bearing that lives only in conversation context (not
  yet in git, a PR, an issue, or memory).
- **Pending fixes / plans** — known follow-ups, deferred edits, plan phases
  not yet executed. If a pending item is a real feature or bug, it belongs
  in a **GitHub issue**, not buried in the hand-off — file it (or note it
  must be filed). Memory is for resume-context, not a substitute for the
  issue tracker.
- **Open questions** — anything awaiting a user decision or external input.
- **Resume-context** — the specific paths, branch names, PR numbers, plan
  files, commands, and gotchas the next session needs to pick up cleanly.
  Be concrete: name files and branches, not "the work from before."

## Part 3 — Persist to memory

Write the hand-off so it survives `/clear`, following CLAUDE.md's Memory
section pattern:

1. **Write a `project_*` memory file** under the session's memory dir
   (`~/.claude/projects/<slug>/memory/project_<topic>_handoff.md` or
   similar). Put the full forward capture (Part 2) plus a one-line summary
   of the retrospective status buckets (Part 1) in it. Keep it skimmable —
   headers and bullets, not prose walls.

   The memory file MUST end with a dedicated `## Resume protocol` section
   in the following exact shape:

   ```markdown
   ## Resume protocol

   **Next step:** <one sentence — the next thing the resuming agent should do, framed as a step, not a committed goal>

   **Rule:** If the next step above is an action (anything that changes state — push, rebase, file, run, delete, edit, merge, cherry-pick, etc., as opposed to reads or asks), confirm with me in a brief plain message before executing — do not use the Ask tool (per user preference; plain conversational confirm matches the discussion-handoff posture).

   **Resume context:**
   - <branch / worktree path>
   - <PR # / plan file path / issue #>
   - <key file(s) or command(s) the next session needs>
   - <gotcha(s) — anything subtle that would trip a fresh agent>
   ```

   The `**Next step:**` framing (NOT `Goal:` / `Immediate goal:`) is
   deliberate — `Next step` is descriptive of what comes next, while
   `Goal` reads as a committed-to-do tone that biases a fresh agent
   toward executing without confirmation. An unanswered question of the
   current agent (e.g. "Want me to file the issue?") goes in **Open
   questions** in Part 2, NOT in `Next step` — promoting a question to
   `Next step` is the exact failure mode this redesign closes.

   The `**Rule:**` is principle-first: the gate is *anything that
   changes state*; the enumeration is illustrative, not exhaustive. The
   Ask-tool prohibition is intentional — confirmation here is a brief
   plain conversational message, not a tool invocation.

2. **Add a one-line `MEMORY.md` index pointer** linking the new file
   (`[<topic> hand-off](project_<topic>_handoff.md) — <one-line gist>`).
   Keep the index entry under ~200 chars (MEMORY.md has a size limit;
   detail lives in the topic file, not the index).

Persisting to memory — not just printing — is what makes the hand-off
*durable*: it is recoverable after `/clear` wipes the conversation.

## Part 4 — Ready-message

Emit a single message with two parts:

1. **Work summary** — the Part-1 status buckets, terse (one bullet per
   intent item, anomalies first — same brevity discipline as the default
   report).

2. **Copy-paste kickoff prompt** — a literal-`―――`-bracketed block the
   user can paste into a fresh post-`/clear` session. It points at the
   memory file by path and previews the next step in one line — nothing
   else. The memory file's `## Resume protocol` section carries the
   binding rule and resume context; the prompt MUST NOT duplicate them.

   **Block delimitation.** The kickoff block is bracketed by literal
   Unicode horizontal bars (`―――`, three U+2015 characters) above and
   below — NOT markdown thematic-break syntax (`---`, `***`, `___`).
   All three thematic-break markers render as the same `<hr>` element, a
   block-level divider that does not provide tight visual bracketing.
   Literal `―――` is plain text, never parsed, and hugs the content the
   way the spec requires. **No code fence around the prompt** — the bars
   ARE the delimiter; nesting a triple-backtick fence is redundant and
   styles the prompt as monospace, which isn't wanted.

   The bars are tight against the content inside (the label
   `Paste below into a fresh session after /clear:` hugs the opening
   bar with no blank line between them; the last prompt line hugs the
   closing bar). The only blank lines are OUTSIDE the bars — one above
   the opening bar (separating it from any closing prose above), one
   below the closing bar (separating it from any continuing agent
   message below), and one inside between the label and the prompt
   content.

   Concretely the emitted block looks like:

   ```
   [closing agent prose, if any]

   ―――
   Paste below into a fresh session after /clear:

   Read <memory-file-path> for the hand-off. The `## Resume protocol`
   section is binding instructions, not background.

   Next step: <one-line preview matching the memory file's Next step>.
   ―――

   [agent's continuing message, if any]
   ```

   The `binding instructions, not background` sentence is load-bearing
   — without it a fresh agent might treat the protocol section as
   backstory rather than enforceable rules. The blank line + `Next
   step:` on its own line is so the user can verify the goal at a
   glance before pasting.

## Rules for handoff mode

- **Forward-looking is intentional here** — unlike the default audit, you
  DO capture pending work, open questions, and a kickoff prompt. This
  posture lives entirely in this file; it never bleeds into the default.
- **Verify, don't recall** still applies to Part 1 — every status bucket
  traces to a command's output, not conversation memory.
- **Memory is resume-context, not the issue tracker** — a real
  feature/bug becomes a GitHub issue; the hand-off file points at it.
- **Persist before you print** — write the memory file and MEMORY.md
  pointer FIRST, so the kickoff prompt can reference a path that exists.
