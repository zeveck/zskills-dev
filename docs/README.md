# Z Skills documentation

Z Skills turns Claude Code into a disciplined engineering team — 21 user-facing slash commands that plan, build, test, fix, and ship with verification at every step.

It's **built for Claude Code** — that's where the skills, hooks, and slash commands are designed to run — though some pieces work with other agents too. It's also built around **git**: branches, worktrees, commits, and pull requests are how work gets planned, verified, and landed, so a git-based project is assumed.

For the high-level tour, see the **[Z Skills presentation](https://zeveck.github.io/zskills-dev/PRESENTATION.html)**.

These docs are organised in two halves:

- **[Guides](guides/README.md)** — install instructions, end-to-end workflows, and operational concepts. **Start here if you're new to zskills.**
- **[Skills reference](skills/README.md)** — per-skill detail pages for the 21 user-facing slash commands plus 2 internal helpers. Reach for this when you need to know exactly what a single skill does, its arguments, and its modes.

## New here? Read in this order

1. **[Install zskills](guides/installing-zskills.md)** — pick the plugin lane or the `/update-zskills` lane.
2. **[Workflows](guides/workflows.md)** — see the canonical recipes (draft → review → execute → land).
3. **[Inspecting & monitoring](guides/inspecting-and-monitoring.md)** — observe a running project without reading git history.

## Guides — quick links

- [Workflows](guides/workflows.md) — end-to-end recipes that combine multiple skills.
- [Installing zskills](guides/installing-zskills.md) — install via the plugin lane or `/update-zskills` lane, with the full side-by-side comparison.
- [Switching install lanes](guides/switching-install-lanes.md) — move between the plugin and `/update-zskills` lanes, with Abort/Rollback for both directions.
- [Inspecting & monitoring](guides/inspecting-and-monitoring.md) — observe a running zskills project without reading git history by hand.
- [Tracking system overview](guides/tracking-overview.md) — the enforcement model: how tracking markers gate commits.
