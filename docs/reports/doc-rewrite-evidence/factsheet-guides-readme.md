# Factsheet — `docs/guides/README.md` (guides index / "Overview")

This file is the **guides index**. Its job is to orient the reader and link the
guides that actually exist. Every description claim below is sourced to the
guide file it summarizes — for an index, the filename plus the guide's own
stated topic is sufficient (R1: claims about what each guide covers are
accurate to that guide's topic).

## Guides linked (all exist in `docs/guides/`)

Confirmed present via `ls docs/guides/*.md`:
`installing-zskills.md`, `workflows.md`, `inspecting-and-monitoring.md`,
`tracking-overview.md`, `switching-install-lanes.md`.

## Per-link description claims

| Link text / description | Source guide | Why the description is accurate |
|---|---|---|
| "Install zskills — the two ways to install zskills and how to choose between them." | `installing-zskills.md` | Guide opens: "zskills ships via two permanent, first-class install lanes… Pick one and stick with it" and provides a tradeoff matrix for choosing (`installing-zskills.md:3-19`). |
| "Workflows — end-to-end recipes that chain skills together (draft a plan, review it, run it, land it)." | `workflows.md` | Guide self-describes as "a **recipes / playbook** doc: it shows how to chain Z Skills into real end-to-end workflows" (`workflows.md:3-5`); examples include draft → review → run → land. |
| "Inspecting & monitoring — see what a running zskills project is doing: where its state lives, what files to read, and how to open the dashboard in your browser." | `inspecting-and-monitoring.md` | Audience line: answer "what is the system doing, what has it done, and what's stuck?"; body covers where state lives, reading plain-text state files, and `/zskills-dashboard` serving "a normal web UI in your browser" (`inspecting-and-monitoring.md:3-26`). |
| "Tracking system overview — how zskills keeps an agent from skipping verification: the checks that gate commits and pushes, and how to clear them if they get stuck." | `tracking-overview.md` | Purpose section: tracking exists "because agents bypass verification"; hooks "run on every commit" and block commits unless verification occurred (`tracking-overview.md:5-9`). Stale-state clearing is covered later in the same guide. |
| "Switching install lanes — move an existing install from one lane to the other, in either direction, with a clean way to back out." | `switching-install-lanes.md` | Guide describes `switch-install-path.sh` as "the bidirectional consolidation tool… for moving a consumer between" lanes, and notes an interrupted switch "leaves the consumer in a re-runnable state" (the back-out / rollback property) (`switching-install-lanes.md:3-16`). |

## "See also" claim

| Claim | Source | Verification |
|---|---|---|
| "Skills reference — per-skill details for the 23 user-facing slash commands." | `docs/skills/README.md` | That file's own heading reads "Per-skill reference for the **23 user-facing Z Skills**" (`docs/skills/README.md:3`). Count of 23 is the doc's own published figure, kept consistent here. |

## Rubric notes

- **R1 (accurate):** every description matches the linked guide's own stated
  topic; descriptions reference stable filenames + topic, not the sibling
  guides' changing prose (those are being rewritten in parallel).
- **R3 (plain):** one short orienting line at the top; each link is a single
  plain sentence; no internals vocabulary.
- **R5 (no banned terms):**
  `grep -nEf docs/reports/doc-rewrite-evidence/banned-terms.txt docs/guides/README.md`
  returns no hits.

## H1 / catalog note

H1 left as `# Guides` (unchanged). The catalog shows this file under a
display-name override ("Overview"); the H1 was not touched, so no catalog
regeneration is required on that account.
</content>
