# Z Skills documentation

Z Skills turns Claude Code into a disciplined engineering team — 23 user-facing slash commands that plan, build, test, fix, and ship with verification at every step.

These docs are organised in two halves:

- **[Guides](guides/README.md)** — install instructions, end-to-end workflows, and operational concepts. **Start here if you're new to zskills.**
- **[Skills reference](skills/README.md)** — per-skill detail pages for the 23 user-facing slash commands plus 2 internal helpers. Reach for this when you need to know exactly what a single skill does, its arguments, and its modes.

## New here? Read in this order

1. **[Install zskills](guides/PLUGIN_INSTALL.md)** — pick the plugin lane or the `/update-zskills` lane.
2. **[Workflows](guides/WORKFLOWS.md)** — see the canonical recipes (draft → review → execute → land).
3. **[Inspecting & monitoring](guides/INSPECTING_AND_MONITORING.md)** — observe a running project without reading git history.

## Guides — quick links

- [Workflows](guides/WORKFLOWS.md) — end-to-end recipes that combine multiple skills.
- [Installing zskills](guides/PLUGIN_INSTALL.md) — install via the plugin lane or `/update-zskills` lane, with the full side-by-side comparison.
- [Switching install lanes](guides/PLUGIN_MIGRATION.md) — move between the plugin and `/update-zskills` lanes, with Abort/Rollback for both directions.
- [Inspecting & monitoring](guides/INSPECTING_AND_MONITORING.md) — observe a running zskills project without reading git history by hand.
- [Tracking system overview](guides/ZSKILLS_TRACKING_OVERVIEW.md) — the enforcement model: how tracking markers gate commits.
