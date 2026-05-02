---
name: session-report
argument-hint: ""
description: >-
  Audit what THIS session said it would do vs. what's actually shipped, and
  report gaps. Verifies session-mentioned items against ground truth (git,
  PRs, plans, worktrees) — not conversation memory — because the user may
  have completed some of them in another session.
metadata:
  version: "2026.05.02+a208dd"
---

# /session-report — Session Intent vs. Actual State

Have we planned or fixed everything **we talked about doing in this
session**? Verify against the filesystem and git, then report tersely.

**Scope:** items the user and assistant discussed in THIS conversation —
written, planned, fixed, or said they'd do. NOT a repo-wide audit. If the
session never mentioned a plan/PR/worktree, it's out of scope, full stop.

**Why verify, not recall:** the user may have completed a session-mentioned
item in a different session, or it may have been reverted, never
committed, or stuck in a worktree. Conversation memory is unreliable
(compaction, parallel sessions, background agents). The report's only
value is its accuracy.

## Step 1 — Enumerate session intent

From the current conversation, list every concrete deliverable the user or
assistant said would happen:

- "Let's add X" / "build X" / "fix X" / "I'll do X next"
- A plan drafted, refined, or referenced for execution
- A PR opened, fixed, merged, or referenced for landing
- A skill, script, or hook to write or modify
- A bug to investigate or close
- A queued action ("we'll run /quickfix later")

Do NOT include:
- Items only mentioned in passing as background or context
- Items the user explicitly deferred ("not now")
- Repo state observed but not acted on
- Other open PRs, recent merges, or backlog plans the session never touched

If the session intended exactly one thing, the list has one entry. That's
fine — most sessions are small.

If you genuinely cannot identify session intent (e.g., the conversation is
empty or only contains `/session-report` itself), say so plainly:
"No identifiable session intent — nothing to verify." Stop there.

## Step 2 — Verify each intent item against ground truth

For EACH item from Step 1, run only the checks that could affect its
status. Do not pre-scan the whole repo. Choose the smallest verification
that resolves the item:

| Intent item type | Minimal verification |
|---|---|
| File written/edited (skill, script, hook, plan, doc) | `git status -s <path>`; if path has a mirror (e.g. `skills/X/` ↔ `.claude/skills/X/`), `diff -q` both. Untracked = uncommitted; modified = uncommitted edit. |
| Plan drafted | `git status -s plans/<name>.md` + `Read` the file (count `[ ]` vs `[x]`, note Phase status lines). |
| Plan executed (some/all phases) | `Read` the plan's Phase status; `git log --oneline main` for matching commits; if `/run-plan` was used, check `.zskills/tracking/fulfilled.run-plan.<slug>` and `requires.*`. |
| PR opened | `gh pr view <N> --json state,mergeable,reviewDecision,statusCheckRollup` + `gh pr checks <N>`. |
| PR merged | `gh pr view <N> --json state,mergeCommit` — confirm `MERGED` and the merge commit is on main. |
| Bug fixed | `git log --oneline -10 -- <file>` for the fix commit; if a regression test was promised, grep for it. |
| Worktree-based work | `cat <worktree>/.landed`; if missing, `git -C <worktree> log main..HEAD --oneline` and `git -C <worktree> status -s`. |
| Queued action ("we'll run X later") | Did it get run this session? Check the most recent commits / PRs for evidence. If still queued, note it. |

**Cross-session verification:** if conversation context says "we wrote X"
but the user might have done it in another session, the verification above
already handles it — `git status` / `gh pr view` is ground truth regardless
of which session produced the change.

**Do NOT** run any of these unless they map to a specific intent item:
- Bulk `gh pr list` of all open/merged PRs
- `ls plans/*.md` enumeration
- `git worktree list` walks of every worktree
- Full `.zskills/tracking/` directory listings

If a check is needed for an intent item, run it. Otherwise, don't.

## Step 3 — Reconcile

For each intent item, classify:
- **Done & shipped** — committed + (if applicable) on main / PR merged + CI green
- **Done locally, not shipped** — file written/edited but uncommitted, OR committed but not pushed/PR'd
- **In flight** — PR open with CI pending/passing, or worktree with commits awaiting land
- **Blocked** — CI red, conflict, missing dependency
- **Not started** — talked about but no evidence of action

Note any divergence between conversation memory and ground truth (e.g.
"I thought we committed X but it's untracked").

## Step 4 — Report

**Lead with the headline. Anomalies first.** The single most important
finding goes at the top, in plain language. If a session deliverable is
uncommitted, on a stale branch, blocked by CI, or otherwise not where the
user expects — that's the headline. Don't bury it.

**Strict structure:**

```markdown
## Session Report — <date> <time> ET

**Headline:** <1-2 sentences. State of session deliverables; surprising/
actionable finding first. If everything is fine, say so plainly.>

**Intent → status:** (one bullet per intent item from Step 1)
- <intent item> — <classification>, <evidence>, <gap if any>

**Memory vs. reality:** <one line per divergence, or omit if matched>

**Next action:** <one line, concrete; only if the evidence calls for one>
```

That's the whole format. Sections not listed above (e.g. "Recently
merged," "Broader open work," "In flight," "Other checks") do not exist
and must not be added.

If the session intended one item, the report is ~5 lines. If it intended
five, ~10. There is never a table. There is never a recap of activity the
session didn't touch.

## Rules

- **Scope = what THIS session discussed.** Adjacent repo state is out of
  scope unless it materially blocks a session intent item (e.g. "this
  skill ships in PR #66, which has red CI"). Do not pad.
- **Verify, don't recall.** Every classification must trace to a specific
  command's output. If you can't cite evidence, mark it `(unverified)`.
- **Name commits/PRs by subject, not bare hash or number alone.**
- **CI is ground truth for "shipped."** A merged PR with no main commit, or
  an open PR with red checks, is not shipped.
- **If two sources disagree, trust filesystem/git/gh over conversation
  memory.** Surface the divergence.
- **Do not invent next actions.** Recommend only what the evidence demands
  (uncommitted file → "commit and PR"; red CI → "investigate failing
  check"). If everything is in good shape, no next action is needed.
- **Do not run bulk repo scans.** No `gh pr list --limit 30`, no
  `git log --since="2 days ago"`, no walking `plans/*.md`. Each check is
  scoped to a specific intent item.
