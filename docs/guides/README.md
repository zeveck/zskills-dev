# Guides

Practical guides for installing, running, and operating zskills.

## Start here

- **[Install zskills](PLUGIN_INSTALL.md)** — side-by-side comparison of the two install lanes (plugin or `/update-zskills`), with worked examples for each.
- **[Workflows](WORKFLOWS.md)** — end-to-end recipes that combine multiple skills (draft → review → execute → land, etc.).

## Operations

- **[Inspecting & monitoring](INSPECTING_AND_MONITORING.md)** — observe a running zskills project without reading git history by hand. Where state lives, which markers to look for, how to use the dashboard.
- **[Tracking system overview](ZSKILLS_TRACKING_OVERVIEW.md)** — the enforcement model: how `requires.*` / `fulfilled.*` markers gate commits and pushes, when to clear stale state.

## Maintenance

- **[Switching install lanes](PLUGIN_MIGRATION.md)** — move between the plugin lane and the `/update-zskills` lane, with abort/rollback for both directions.

## See also

- **[Skills reference](../skills/README.md)** — per-skill details for the 23 user-facing slash commands.
