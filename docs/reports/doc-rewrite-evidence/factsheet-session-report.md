# Factsheet — docs/skills/session-report.md

Every factual claim in the rewritten doc, paired with the verbatim source
line that backs it. Source = `skills/session-report/SKILL.md` and
`skills/session-report/modes/handoff.md` (handoff mode), companion edges from
`docs/reports/doc-rewrite-evidence/COMPANIONS.md`.

Citation format: `<file>:LINE: "<verbatim quote>"`.

---

## Blockquote / summary

**Doc:** "Audit what THIS session said it would do versus what is actually shipped. Verifies session-mentioned items against ground truth — git, PRs, plans, worktrees — not conversation memory."

- `skills/session-report/SKILL.md:5: "Audit what THIS session said it would do vs. what's actually shipped."`
- `skills/session-report/SKILL.md:6-8: "Verifies session-mentioned items against ground truth (git, PRs, plans, / worktrees), not conversation memory — items may have been completed in / another session."`

**Doc:** "`handoff` turns it into a durable, forward-looking end-of-session hand-off."

- `skills/session-report/SKILL.md:3: argument-hint: "[handoff]"` (the argument exists)
- `skills/session-report/modes/handoff.md:1: "# /session-report handoff — durable end-of-session hand-off"`
- `skills/session-report/modes/handoff.md:8-10: "handoff inverts that posture: it is forward-looking by design."`

---

## What it does

**Doc:** "have we actually shipped everything we talked about doing in this conversation?"

- `skills/session-report/SKILL.md:15-16: "Have we planned or fixed everything **we talked about doing in this / session**?"`

**Doc:** "It lists the concrete deliverables the session discussed, checks each one against the filesystem and git, and reports tersely."

- `skills/session-report/SKILL.md:16-17: "Verify against the filesystem and git, then report tersely."`
- `skills/session-report/SKILL.md:38-39: "From the current conversation, list every concrete deliverable the / user or assistant said would happen:"`

**Doc:** "it verifies rather than recalls."

- `skills/session-report/SKILL.md:22: "**Why verify, not recall:**"`
- `skills/session-report/SKILL.md:140: "**Verify, don't recall.** Every classification must trace to a specific / command's output."`

**Doc:** "Conversation memory is unreliable — context gets compacted, parallel sessions and background agents change things underneath you, and a file you 'remember committing' may be sitting untracked."

- `skills/session-report/SKILL.md:24-26: "Conversation memory is unreliable / (compaction, parallel sessions, background agents)."`
- `skills/session-report/SKILL.md:22-24: "the user may have completed a session-mentioned / item in a different session, or it may have been reverted, never / committed, or stuck in a worktree."`

**Doc:** "for each item the session said it would do, `/session-report` runs the smallest ground-truth check that resolves it: `git status` for a file, `gh pr view` for a pull request, the plan file's own phase markers for an executed plan."

- `skills/session-report/SKILL.md:62-65: "For EACH item from Step 1, run only the checks that could affect its / status. Do not pre-scan the whole repo. Choose the smallest verification / that resolves the item:"`
- `skills/session-report/SKILL.md:70: "File written/edited ... | `git status -s <path>`"`
- `skills/session-report/SKILL.md:73: "PR opened | `gh pr view <N> --json state,mergeable,reviewDecision,statusCheckRollup`"`
- `skills/session-report/SKILL.md:72: "Plan executed (some/all phases) | `Read` the plan's Phase status; `git log --oneline main` for matching commits"`

**Doc:** "A change made in a different session still shows as done, because git is the source of truth no matter which session produced it."

- `skills/session-report/SKILL.md:79-82: "if conversation context says \"we wrote X\" / but the user might have done it in another session ... `git status` / `gh pr view` is ground truth regardless / of which session produced the change."`

**Doc:** "It looks only at items the user and assistant discussed in this conversation — written, planned, fixed, or said they would do."

- `skills/session-report/SKILL.md:19-21: "**Scope:** items the user and assistant discussed in THIS conversation — / written, planned, fixed, or said they'd do."`

**Doc:** "It is not a repo-wide audit ... and it does not run bulk scans like `gh pr list` or a full plan-directory enumeration."

- `skills/session-report/SKILL.md:20: "NOT a repo-wide audit."`
- `skills/session-report/SKILL.md:85-88: "**Do NOT** run any of these unless they map to a specific intent item: / - Bulk `gh pr list` of all open/merged PRs / - `ls \"$ZSKILLS_PLANS_DIR\"/*.md` enumeration"`
- `skills/session-report/SKILL.md:150-152: "**Do not run bulk repo scans.** No `gh pr list --limit 30` ... no walking `\"$ZSKILLS_PLANS_DIR\"/*.md`."`

**Doc:** "it does not list other open PRs, recent merges, or backlog plans the session never touched"

- `skills/session-report/SKILL.md:52-53: "- Other open PRs, recent merges, or backlog plans the session never touched"`

**Doc:** "If the session never mentioned something, it is out of scope."

- `skills/session-report/SKILL.md:20-21: "If the session never mentioned a plan/PR/worktree, it's out of scope, full stop."`

**Doc:** "The report leads with the headline — the single most important, most surprising, or most actionable finding first. If a deliverable is uncommitted, stuck on a stale branch, or blocked by red CI, that goes at the top."

- `skills/session-report/SKILL.md:106-109: "**Lead with the headline. Anomalies first.** The single most important / finding goes at the top ... If a session deliverable is / uncommitted, on a stale branch, blocked by CI ... that's the headline. Don't bury it."`

**Doc:** "Each intent item then gets one line classifying it (done and shipped, done locally but not shipped, in flight, blocked, or not started) with the evidence."

- `skills/session-report/SKILL.md:94-99: "For each intent item, classify: / - **Done & shipped** ... / - **Done locally, not shipped** ... / - **In flight** ... / - **Blocked** ... / - **Not started**"`
- `skills/session-report/SKILL.md:119-121: "**Intent → status:** (one bullet per intent item from Step 1) / - <intent item> — <classification>, <evidence>, <gap if any>"`

**Doc:** "The report is short by design: roughly five lines for a one-item session, ten for a five-item one. There is no table and no recap of work the session did not touch."

- `skills/session-report/SKILL.md:131-133: "If the session intended one item, the report is ~5 lines. If it intended / five, ~10. There is never a table. There is never a recap of activity the / session didn't touch."`

---

## Handoff mode

**Doc:** "With the `handoff` argument the skill flips posture. Instead of a backward-looking audit, it becomes a forward-looking, durable end-of-session hand-off."

- `skills/session-report/SKILL.md:30-32: "If it contains the token `handoff`, this is **not** a / retrospective audit — it is a durable end-of-session hand-off (forward / capture + persist + ready-message)."`
- `skills/session-report/modes/handoff.md:8-11: "**handoff inverts that posture: it is forward-looking by design.** It / captures in-flight concerns, pending work, and the context needed to / resume — then persists that to memory and hands you a ready-to-act / message."`

**Doc:** "it still runs the same intent-versus-reality verification"

- `skills/session-report/modes/handoff.md:16-18: "## Part 1 — Retrospective (reuse the default audit) / Run **Steps 1–3 of `SKILL.md`** exactly as written:"`

**Doc:** "then captures the in-flight concerns, pending work, open questions, and resume-context a fresh session would need"

- `skills/session-report/modes/handoff.md:32-34: "## Part 2 — Forward capture ... Capture what a fresh session / would need to continue."`
- `skills/session-report/modes/handoff.md:35: "- **In-flight concerns** ..."`
- `skills/session-report/modes/handoff.md:38: "- **Pending fixes / plans** ..."`
- `skills/session-report/modes/handoff.md:44: "- **Open questions** ..."`
- `skills/session-report/modes/handoff.md:45: "- **Resume-context** — the specific paths, branch names, PR numbers, plan / files, commands, and gotchas the next session needs to pick up cleanly."`

**Doc:** "writes all of that to a memory file so it survives a `/clear` or `/compact`"

- `skills/session-report/modes/handoff.md:50-51: "## Part 3 — Persist to memory / Write the hand-off so it survives `/clear`"`
- `skills/session-report/modes/handoff.md:54-56: "1. **Write a `project_*` memory file** under the session's memory dir"`
- `skills/session-report/modes/handoff.md:64-65: "Persisting to memory — not just printing — is what makes the hand-off / *durable*: it is recoverable after `/clear` wipes the conversation."`

**Doc:** "and hands you a ready-to-paste kickoff prompt for the next session."

- `skills/session-report/modes/handoff.md:68-69: "## Part 4 — Ready-message / Emit a single message with three parts:"`
- `skills/session-report/modes/handoff.md:84-88: "3. **Copy-paste kickoff prompt** — a fenced block the user can paste into a / fresh post-`/clear` session."`

**Doc:** "Run this near the end of a long session, before you reset the conversation."

- `skills/session-report/modes/handoff.md:10-11: "Run this near full context, at the end of a long session, before / `/clear` or `/compact`."`

**Doc (Arguments):** "then adds a forward capture ... persists it to a memory file plus a one-line index pointer, and emits a ready-message that includes a `/clear`-versus-`/compact` recommendation and a copy-paste kickoff prompt."

- `skills/session-report/modes/handoff.md:59-62: "2. **Add a one-line `MEMORY.md` index pointer** linking the new file"`
- `skills/session-report/modes/handoff.md:75-83: "2. **`/clear` vs. `/compact` recommendation** — apply the heuristic: / - Recommend **`/clear`** when everything important is *durably captured* ... / - Recommend **`/compact`** when something important still lives only in / conversation context"`

**Doc (Arguments & Tips):** "Real features or bugs surfaced during the capture are meant to be filed as GitHub issues, not buried in the hand-off — the memory file is for resume-context, not a substitute for the issue tracker."

- `skills/session-report/modes/handoff.md:38-43: "If a pending item is a real feature or bug, it belongs / in a **GitHub issue**, not buried in the hand-off — file it ... Memory is for resume-context, not a substitute for the issue tracker."`
- `skills/session-report/modes/handoff.md:103-105: "- **Memory is resume-context, not the issue tracker** — a real / feature/bug becomes a GitHub issue; the hand-off file points at it."`

**Doc (Tips):** "`handoff` writes a memory file and a `MEMORY.md` index pointer before it prints, so the kickoff prompt it gives you references a path that already exists and survives `/clear`."

- `skills/session-report/modes/handoff.md:106-107: "- **Persist before you print** — write the memory file and MEMORY.md / pointer FIRST, so the kickoff prompt can reference a path that exists."`

---

## Arguments section — the specific Phase-4 fix

**Doc:** "`/session-report` takes a single optional token, `handoff`." / "No argument runs the default audit." / "`handoff` runs the hand-off mode."

- `skills/session-report/SKILL.md:3: argument-hint: "[handoff]"` (declares the one optional token)
- `skills/session-report/SKILL.md:29-35: "## Mode dispatch / Inspect `$ARGUMENTS`. If it contains the token `handoff` ... **Read [modes/handoff.md](modes/handoff.md) / in full and follow its procedure end-to-end** ... Otherwise (plain `/session-report`, no / `handoff`), ignore the mode file entirely and run the default audit below."`

This is the corrected claim: the prior doc said "No arguments," contradicting
`argument-hint: "[handoff]"` (line 3) and the Mode dispatch block (lines
29–35). The handoff mode is now documented from `modes/handoff.md`.

---

## Companion skills (R6 — from COMPANIONS.md, not invented)

**Doc:** "`/briefing` — the cross-session, multi-pipeline status companion."

- `COMPANIONS.md:115: "**Diagnose/verify peers:** `investigate`, `qe-audit`, `verify-changes`, / `session-report`."` (peer family)
- `COMPANIONS.md:75: "| `briefing` | `fix-issues`, `run-plan`, `update-zskills` | Reports on the activity of long-running orchestration skills"` (briefing = the cross-session status reporter, the natural counterpart to session-scoped session-report)

**Doc:** "`/run-plan` and `/quickfix` — examples of the landing skills whose output `/session-report` verifies."

- `COMPANIONS.md:95: "| `session-report` | `run-plan`, `quickfix` | Summarizes a session's work; references landing skills."` (the canonical companion edges for session-report)
- `skills/session-report/SKILL.md:72: "if `/run-plan` was used, check `.zskills/tracking/$PIPELINE_ID/fulfilled.run-plan.<id>`"` (run-plan output is a verification target)
- `skills/session-report/SKILL.md:77: "Queued action (\"we'll run X later\") | Did it get run this session?"` (queued e.g. /quickfix)
