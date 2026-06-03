# Canonical Companion-Skill Graph

> The single source of truth for every doc's "companion skills" section (R6).
> Every doc draws its companion relationships from here so the catalog
> cross-references itself consistently. Do not invent companion relationships
> per doc — read them off this graph.
>
> **How this was built.** For each of the 25 skills under `skills/`, the
> "companions" column lists the OTHER real skills that the skill's own
> `skills/<name>/SKILL.md` references (mechanically: a `/<skill>` or `/zs:<skill>`
> token matching a real skill name, then hand-curated down to genuine
> companion relationships — not every passing mention). Counts and the raw
> reference set are reproducible with the command at the bottom.
>
> **Reconciliation.** The "which skill for which input" mapping below is taken
> from **`/workspaces/zskills/CLAUDE.md` "## Which skill for which input"**
> (the decision table + "Common confusions"). Nothing here contradicts that
> table; where this file adds detail (companion edges from source), it
> supplements, never overrides, CLAUDE.md. CLAUDE.md is authoritative on
> routing; this file is authoritative on companion edges.

---

## "Which skill for which input" — mirror of the CLAUDE.md decision table

Cited from `/workspaces/zskills/CLAUDE.md` "## Which skill for which input".
Reproduced so phase docs can route the reader without re-deriving it. If
CLAUDE.md changes, re-sync this section.

| You have | Run |
|---|---|
| One-commit PR — edit in-place on main, no worktree (only valid when `main_protected: false`) | `/quickfix` |
| Several small bugs / issues in a backlog | `/fix-issues N` |
| Bug, but root cause is unclear | `/investigate` |
| One-commit PR — needs worktree isolation (required when `main_protected: true`) | `/do` |
| Plan file already drafted, ready to execute | `/run-plan <path>` |
| Plan-scale design surface — needs adversarial review before execution | `/draft-plan` |
| Broad goal that decomposes into multiple sub-plans | `/research-and-plan` |
| Same as above, but execute all sub-plans autonomously after drafting | `/research-and-go` |
| Plan is mid-execution and reality has drifted from the spec | `/refine-plan` |
| Want to confirm recent changes really work (diffs + tests + manual UI) | `/verify-changes` |
| Staged work in main, ready to commit (and optionally push/land/PR) | `/commit` |
| Just merged a PR, want local clone caught up | `/cleanup-merged` |
| Want to file bug/test-gap issues from a QE pass over recent work | `/qe-audit` |

**Common confusions (from CLAUDE.md — load-bearing for companion framing):**

- **`/quickfix` vs `/do` are PEERS, not tiers.** Same lifecycle; same `/land-pr`
  dispatch; same one-commit-PR shape. The difference is *where the work tree
  lives* — `/quickfix` does `git checkout -b` on main; `/do` uses a worktree.
  Pick by **project policy**: `main_protected: true` → `/do`; otherwise either.
  (In THIS repo, `main_protected: true`, so `/do`, never `/quickfix`.)
- **`/draft-plan` → `/run-plan`** are sequential, not alternatives:
  `/draft-plan` produces a plan file, `/run-plan` executes one.
- **`/research-and-plan` vs `/research-and-go`**: same drafting machinery;
  `-and-plan` stops after the meta-plan is ready, `-and-go` continues into
  execution.
- **`/investigate` vs `/quickfix`**: `/quickfix` assumes the fix is known;
  `/investigate` proves the root cause first, then its fix may dispatch
  `/quickfix` or `/do`.
- **`/verify-changes` vs `/qe-audit`**: `/verify-changes` checks YOUR recent
  changes (gates a commit); `/qe-audit` hunts repo-wide for gaps and files
  issues (generates work).

---

## Per-skill companion graph (source-cited)

Each row: the skill, its typical companion skills (drawn from cross-references
in its own `skills/<name>/SKILL.md`), and a one-line note on the relationship.
"Companion" = used before/after/alongside, or the documented redirect target.

| Skill | Typical companions | Relationship (source: `skills/<name>/SKILL.md`) |
|---|---|---|
| `briefing` | `fix-issues`, `run-plan`, `update-zskills` | Reports on the activity of long-running orchestration skills; `update-zskills` configures it. |
| `cleanup-merged` | `commit`, `do`, `fix-issues`, `quickfix`, `work-on-plans`, `land-pr` | Run AFTER any landing skill merges a PR, to catch the local clone up. |
| `commit` | `do`, `doc`, `fix-issues`, `run-plan`, `land-pr`, `update-zskills` | The staged-work landing skill; `commit pr` dispatches `/land-pr`; peers call it to land. |
| `create-worktree` | `do`, `fix-issues`, `run-plan`, `commit`, `update-zskills` | The shared worktree-setup primitive every isolation-using skill calls. |
| `do` | `quickfix` (peer), `draft-plan`, `create-worktree`, `verify-changes`, `commit`, `land-pr`, `run-plan`, `fix-issues`, `doc`, `update-zskills` | Peer of `/quickfix`; triage may redirect to `/draft-plan`/`/run-plan`; lands via `/land-pr`; runs `/verify-changes`. |
| `doc` | `manual-testing` | Content/documentation skill; references `/manual-testing` for UI doc verification. |
| `draft-plan` | `run-plan` (next step), `refine-plan`, `research-and-plan`, `research-and-go`, `do`, `quickfix`, `plans`, `create-worktree` | Produces a plan file `/run-plan` executes; `/refine-plan` adjusts it mid-flight. |
| `draft-tests` | `draft-plan`, `refine-plan`, `run-plan`, `do`, `quickfix`, `create-worktree` | Test-spec authoring sibling of the plan-authoring family. |
| `fix-issues` | `fix-report`, `draft-plan`, `run-plan`, `land-pr` | Drives an issue backlog; `fix-report` summarizes a sprint; redirects big items to `/draft-plan`/`/run-plan`. |
| `fix-report` | `fix-issues`, `commit`, `create-worktree`, `manual-testing`, `run-plan`, `update-zskills` | The reporting companion of `/fix-issues`. |
| `investigate` | `fix-issues`, `create-worktree`, `update-zskills` | Proves a root cause; its fix then routes to `/quickfix` or `/do` (per CLAUDE.md). |
| `land-pr` | `commit`, `do`, `quickfix`, `fix-issues`, `run-plan`, `draft-plan`, `refine-plan`, `research-and-plan`, `draft-tests` | **Internal** (`user-invocable: false`). Dispatched BY its callers; never typed directly. |
| `manual-testing` | `verify-changes`, `update-zskills` | UI-verification helper used by `/verify-changes`, `/do`, `/qe-audit`. (Note: #1012 makes it `user-invocable: false`.) |
| `plans` | `run-plan`, `work-on-plans`, `zskills-dashboard`, `update-zskills` | The plan-catalog index; `/work-on-plans` and `/run-plan` consume the queue it builds. |
| `qe-audit` | `draft-plan`, `fix-issues`, `manual-testing`, `create-worktree` | Files issues that `/fix-issues` then drives; big findings go to `/draft-plan`. |
| `quickfix` | `do` (peer), `draft-plan`, `cleanup-merged`, `commit`, `create-worktree`, `land-pr`, `run-plan`, `fix-issues`, `work-on-plans` | Peer of `/do`; same lifecycle; triage redirects to `/draft-plan`/`/run-plan`; lands via `/land-pr`. |
| `refine-plan` | `draft-plan`, `run-plan`, `draft-tests`, `do`, `quickfix`, `create-worktree` | Adjusts an in-flight plan; sits between `/draft-plan` and `/run-plan`. |
| `research-and-go` | `research-and-plan` (peer), `draft-plan`, `run-plan`, `fix-issues`, `verify-changes`, `commit`, `create-worktree` | Continue-into-execution twin of `/research-and-plan`; decomposes + runs sub-plans. |
| `research-and-plan` | `research-and-go` (peer), `draft-plan`, `refine-plan`, `run-plan`, `plans`, `fix-issues`, `verify-changes`, `create-worktree` | Stop-after-draft twin; decomposes a goal into sub-plans for review. |
| `run-plan` | `draft-plan` (prior step), `refine-plan`, `draft-tests`, `commit`, `land-pr`, `verify-changes`, `work-on-plans`, `create-worktree`, `fix-issues` | Executes a drafted plan; lands phases via `/land-pr`; `/refine-plan` corrects drift. |
| `session-report` | `run-plan`, `quickfix` | Summarizes a session's work; references landing skills. |
| `update-zskills` | `commit`, `do`, `quickfix`, `fix-issues`, `run-plan`, `create-worktree`, `briefing`, `plans`, `zskills-dashboard`, `verify-changes` | The install/config skill; configures and is referenced by nearly every skill. |
| `verify-changes` | `manual-testing`, `fix-report`, `run-plan`, `research-and-go`, `create-worktree` | The change-soundness gate; `/do`, `/run-plan`, `/research-and-go` call it; uses `/manual-testing` for UI. |
| `work-on-plans` | `run-plan` (executor), `fix-issues`, `create-worktree`, `update-zskills` | Drives the plan-ready queue; dispatches `/run-plan` per plan. |
| `zskills-dashboard` | `work-on-plans`, `create-worktree`, `update-zskills` | The status UI for in-flight pipelines; reads what `/work-on-plans` and others write. |

---

## Peer families (R7 — these get equal-quality docs)

Mirrors the plan's phase grouping and the CLAUDE.md "Common confusions". Within a
family, docs must read as co-equal regardless of the usage-log skew:

- **Execution peers:** `do` ↔ `quickfix` (anchor pair), with `commit`,
  `land-pr`, `cleanup-merged`.
- **Planning peers:** `draft-plan`, `run-plan`, `refine-plan`, `draft-tests`,
  `plans`.
- **Backlog/decompose peers:** `fix-issues`, `fix-report`, `work-on-plans`,
  `research-and-plan` ↔ `research-and-go`.
- **Diagnose/verify peers:** `investigate`, `qe-audit`, `verify-changes`,
  `session-report`.
- **Infra/meta peers:** `update-zskills`, `create-worktree`, `briefing`,
  `zskills-dashboard`, `doc`.
- **Internal (typed directly won't work):** `land-pr` (today);
  `manual-testing` joins once #1012 merges.

---

## Reproduce the raw reference set

```bash
SKILLS=$(ls skills/)
for s in $SKILLS; do refs=""; for t in $SKILLS; do
  [ "$t" = "$s" ] && continue
  grep -qE "/(zs:)?$t\b" "skills/$s/SKILL.md" && refs="$refs $t"
done; printf '%-20s ->%s\n' "$s" "$refs"; done
```

The hand-curated table above prunes that raw set to genuine companion edges
(dropping incidental mentions inside example blocks or prohibition notes).
