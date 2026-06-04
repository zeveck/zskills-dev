# /session-report

> Audit what THIS session said it would do versus what is actually shipped. Verifies session-mentioned items against ground truth — git, PRs, plans, worktrees — not conversation memory. `handoff` turns it into a durable, forward-looking end-of-session hand-off.

## What it does

`/session-report` answers one question: have we actually shipped everything **we talked about doing in this conversation**? It lists the concrete deliverables the session discussed, checks each one against the filesystem and git, and reports tersely what is done, what is not, and where reality diverges from what you remember.

The key idea is that it **verifies rather than recalls.** Conversation memory is unreliable — context gets compacted, parallel sessions and background agents change things underneath you, and a file you "remember committing" may be sitting untracked. So for each item the session said it would do, `/session-report` runs the smallest ground-truth check that resolves it: `git status` for a file, `gh pr view` for a pull request, the plan file's own phase markers for an executed plan. A change made in a *different* session still shows as done, because git is the source of truth no matter which session produced it.

Its scope is deliberately narrow. It looks only at items the user and assistant discussed in this conversation — written, planned, fixed, or said they would do. It is **not** a repo-wide audit: it does not list other open PRs, recent merges, or backlog plans the session never touched, and it does not run bulk scans like `gh pr list` or a full plan-directory enumeration. If the session never mentioned something, it is out of scope.

The report leads with the headline — the single most important, most surprising, or most actionable finding first. If a deliverable is uncommitted, stuck on a stale branch, or blocked by red CI, that goes at the top. Each intent item then gets one line classifying it (done and shipped, done locally but not shipped, in flight, blocked, or not started) with the evidence that backs the classification. The report is short by design: roughly five lines for a one-item session, ten for a five-item one. There is no table and no recap of work the session did not touch.

With the `handoff` argument the skill flips posture. Instead of a backward-looking audit, it becomes a forward-looking, durable end-of-session hand-off: it still runs the same intent-versus-reality verification, then captures the in-flight concerns, pending work, open questions, and resume-context a fresh session would need, writes all of that to a memory file so it survives a `/clear` or `/compact`, and hands you a ready-to-paste kickoff prompt for the next session. Run this near the end of a long session, before you reset the conversation.

## Usage

```
/session-report
/session-report handoff
```

## Typical usage

Most of the time you run it bare, at the end of a working session, to confirm everything you discussed actually landed:

```
/session-report
```

This is especially useful after a long session — particularly one where context was compacted — because that is exactly when a deliverable can quietly slip from "I committed that" to "actually untracked."

When you are about to wrap up and clear the conversation, run the hand-off form so the next session can resume cleanly:

```
/session-report handoff
```

## Companion skills

- **`/briefing`** — the cross-session, multi-pipeline status companion. `/session-report` is scoped to the one conversation you are in; `/briefing` reports on the activity of long-running orchestration work across sessions. Reach for `/briefing` when you want the wider picture, `/session-report` when you want to close out the session in front of you.
- **`/run-plan`** and **`/do`** — examples of the landing skills whose output `/session-report` verifies. When the session executed a plan or shipped an ad-hoc change, the report checks the resulting commits, PR state, and plan phase markers against ground truth rather than taking your word for it.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `handoff` | No | Run the forward-looking, durable end-of-session hand-off instead of the default retrospective audit |

`/session-report` takes a single optional token, `handoff`.

- **No argument** runs the **default audit**: enumerate session intent, verify each item against git/PRs/plans/worktrees, reconcile into status buckets, and emit the short retrospective report described above.
- **`handoff`** runs the **hand-off mode**: it reuses the same audit to summarize the work done, then adds a forward capture (in-flight concerns, pending fixes, open questions, resume-context), persists it to a memory file plus a one-line index pointer, and emits a ready-message that includes a `/clear`-versus-`/compact` recommendation and a copy-paste kickoff prompt for the next session. Real features or bugs surfaced during the capture are meant to be filed as GitHub issues, not buried in the hand-off — the memory file is for resume-context, not a substitute for the issue tracker.

## Examples

```
/session-report
/session-report handoff
```

## Common Patterns

- **End-of-session audit:** `/session-report` — confirm everything the conversation discussed was actually shipped.
- **After a long or compacted session:** `/session-report` — catch deliverables that slipped from "committed" to "untracked" while context churned.
- **Before `/clear` or `/compact`:** `/session-report handoff` — capture and persist resume-context so the next session can pick up cleanly.

## Tips & Gotchas

- Scope is limited to THIS conversation — it is not a repo-wide audit, and it deliberately avoids bulk scans of all PRs or plans.
- It verifies against the filesystem and git, not conversation memory, so an item completed in a *different* session still shows as done, and an item you "remember committing" that is actually untracked shows as not shipped.
- The report leads with the headline (anomalies first) and stays short — about five lines for a one-item session. There is no table.
- The default audit does not invent next actions; it recommends one only when the evidence demands it (an uncommitted file, a red CI check).
- `handoff` writes a memory file and a `MEMORY.md` index pointer *before* it prints, so the kickoff prompt it gives you references a path that already exists and survives `/clear`.
