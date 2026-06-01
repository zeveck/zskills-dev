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
2. **Add a one-line `MEMORY.md` index pointer** linking the new file
   (`[<topic> hand-off](project_<topic>_handoff.md) — <one-line gist>`).
   Keep the index entry under ~200 chars (MEMORY.md has a size limit;
   detail lives in the topic file, not the index).

Persisting to memory — not just printing — is what makes the hand-off
*durable*: it is recoverable after `/clear` wipes the conversation.

## Part 4 — Ready-message

Emit a single message with three parts:

1. **Work summary** — the Part-1 status buckets, terse (one bullet per
   intent item, anomalies first — same brevity discipline as the default
   report).

2. **`/clear` vs. `/compact` recommendation** — apply the heuristic:
   - Recommend **`/clear`** when everything important is *durably captured*
     — in git, PRs, GitHub issues, or the memory file you just wrote.
     Nothing load-bearing is context-only. `/clear` is the clean reset.
   - Recommend **`/compact`** when something important still lives only in
     conversation context and could not be fully externalized (e.g. a
     subtle in-progress debugging thread, an un-externalizable judgment).
   State which one and why in one line.

3. **Copy-paste kickoff prompt** — a fenced block the user can paste into a
   fresh post-`/clear` session. It MUST: point at the memory file by path,
   state the immediate next goal in one sentence, and name the key
   resume-context (branch/PR/plan/files). Keep it self-contained — assume
   the reader has zero conversation context.

   ````markdown
   ```
   Read <memory-file-path> for the hand-off. Immediate goal: <one sentence>.
   Resume context: branch <X>, PR #<N>, plan <path>. Start by <first step>.
   ```
   ````

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
