---
name: migrate-crons
user-invocable: true
disable-model-invocation: false
argument-hint: "[apply]"
description: >-
  OPTIONAL: when switching install lanes, normalize cron prompts between the
  bare-prefix (`Run /<skill>`) and plugin (`Run /zs:<skill>`) forms. Preview by
  default; `apply` to rewrite. Not required — both prefixes work permanently.
metadata:
  version: "2026.05.29+ab8712"
---

# migrate-crons — optional cron prefix normalisation

## When (and whether) to use this

`/migrate-crons` is a **purely optional convenience**. You almost never need
it.

zskills ships two first-class, permanent install lanes — the `/update-zskills`
lane (bare slash prefix, e.g. `Run /fix-issues ...`) and the plugin lane
(namespaced prefix, e.g. `Run /zs:fix-issues ...`). The cron-fire recognition
rule (in the auto-loaded `managed.md` / `CLAUDE_TEMPLATE.md` `## Cron-fired
prompts` section) recognizes **BOTH prefixes PERMANENTLY**, with no sunset
date (decisions D12 and D23). So a cron registered under one prefix keeps
firing correctly even after you switch lanes — nothing breaks.

The only reason to run this skill is **cosmetic consistency**: if you have
switched install lanes and want your registered cron prompts to *read* in the
form that matches your current lane (e.g. you migrated from `/update-zskills`
to the plugin and want `Run /fix-issues ...` rewritten to `Run /zs:fix-issues
...`), this skill rewrites the prefix in-place. It changes nothing about
whether the crons fire — only how their prompt text reads.

If you are not switching lanes, or you do not care about the prompt-text
prefix, **do not run this skill.**

## Mechanism — session tools, not a shell script

This skill operates entirely through Claude Code's session-side cron tools
(`CronList`, `CronDelete`, `CronCreate`). It does NOT shell out to a script —
cron registrations live in the session/runtime, not in a file a script could
edit. The procedure is:

1. **Enumerate.** Call `CronList` to list every registered cron and its
   prompt text.

2. **Determine the target prefix.** Inspect the environment to decide which
   lane is active:
   - If `${CLAUDE_PLUGIN_ROOT}` is set (plugin lane), the target prefix is
     `Run /zs:<skill> ...`.
   - Otherwise (the `/update-zskills` lane), the target prefix is the bare
     `Run /<skill> ...`.

3. **Classify each cron.** For each cron whose prompt starts with
   `Run /<skill> ` or `Run /zs:<skill> `, check whether its prefix already
   matches the target form.
   - Already-matching crons are left untouched (idempotent — re-running this
     skill is a no-op).
   - Non-cron prompts (anything not starting with `Run /<skill> ` or
     `Run /zs:<skill> `) are NOT cron-fire prompts under the recognition rule
     and are skipped.

4. **Preview (default) or apply.**
   - **Preview** (no `apply` argument): print a table — for each cron that
     would change, show its id, current prompt, and the rewritten prompt.
     Make NO changes. End by telling the user to re-run with
     `/migrate-crons apply` to execute.
   - **Apply** (`$ARGUMENTS` is `apply`): for each cron needing a rewrite,
     compute the new prompt by swapping the prefix between
     `Run /<skill> ...` and `Run /zs:<skill> ...` (preserving the `<skill>`
     name and the entire `$ARGUMENTS` tail verbatim), then re-register it:
     `CronDelete` the old cron, then `CronCreate` a new cron with the SAME
     schedule and the rewritten prompt. Verify with a follow-up `CronList`
     that the new cron exists and the old one is gone.

## Prefix-swap rule

The only transformation is the prefix segment between `Run /` and the first
space:

- Bare → plugin: `Run /fix-issues 2 auto every 30m` →
  `Run /zs:fix-issues 2 auto every 30m`
- Plugin → bare: `Run /zs:run-plan plans/X.md finish auto` →
  `Run /run-plan plans/X.md finish auto`

The skill name and the `$ARGUMENTS` tail (everything after the first space)
are preserved byte-for-byte. Only the `zs:` namespace token is added or
removed.

## Safety

- **Idempotent.** Crons already in the target form are skipped. Running
  `/migrate-crons apply` twice produces no further changes on the second run.
- **Schedule-preserving.** `CronDelete` + `CronCreate` re-registers with the
  identical schedule string read from `CronList`. Never change the cadence.
- **Never deletes a cron you cannot rebuild.** If `CronList` returns a cron
  whose schedule or prompt you cannot parse confidently, leave it untouched
  and report it — per the CLAUDE.md rule, never `CronDelete` on the strength
  of a confused read.
- **Preview-first.** The default (no `apply`) makes zero changes. The user
  reviews the proposed rewrites before any `CronDelete`/`CronCreate` runs.
