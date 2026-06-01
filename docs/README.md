# `docs/` — Z Skills documentation

This directory holds operator/adopter documentation, design plans, issue
tracking, audit reports, and reference material for zskills. Use this index
to find the right starting point.

## Layout

| Path | What's here |
|------|-------------|
| [`guides/`](guides/) | Operator and adopter guides — start here if you're using zskills (workflows, plugin install/migration, monitoring, tracking concepts). |
| [`skills/`](skills/README.md) | Per-skill reference for the 23 user-facing skills plus the 2 internal helpers. |
| [`plans/`](plans/) | Design plans (in-flight, accepted, and completed). Source of truth for multi-phase efforts. |
| [`tracking/`](tracking/) | Authoritative naming scheme and delegation semantics for the tracking system markers under `.zskills/tracking/`. |
| [`evals/`](evals/) | Skill evaluations, scorecards, and coverage analyses. |
| [`issues/`](issues/) | Issue triage notes and per-issue working files. |
| [`reports/`](reports/) | Post-execution reports from `/run-plan` and other multi-phase work. |

## Guides — quick links

- [`guides/WORKFLOWS.md`](guides/WORKFLOWS.md) — end-to-end recipes that combine multiple skills.
- [`guides/PLUGIN_INSTALL.md`](guides/PLUGIN_INSTALL.md) — install via the plugin lane or `/update-zskills` lane, with the full side-by-side comparison.
- [`guides/PLUGIN_MIGRATION.md`](guides/PLUGIN_MIGRATION.md) — switch between install lanes, with Abort/Rollback for both directions.
- [`guides/INSPECTING_AND_MONITORING.md`](guides/INSPECTING_AND_MONITORING.md) — observe a running zskills project without reading git history by hand.
- [`guides/ZSKILLS_TRACKING_OVERVIEW.md`](guides/ZSKILLS_TRACKING_OVERVIEW.md) — the enforcement model: how tracking markers gate commits.
