## Now (standalone — no N provided)

If `$ARGUMENTS` is just `now` (no N, no focus, no every — just the word
`now` by itself):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /fix-issues`
3. If found: extract the cron's prompt to get N, focus, auto, and schedule.
   **Run the sprint immediately** using those parameters — proceed to
   Phase 1 with the cron's N, focus, and auto settings. Do NOT ask for
   confirmation — `now` IS the confirmation. The cron itself stays active.
4. If none found: report `No active /fix-issues cron to trigger. Use
   /fix-issues N to run manually.` and **exit.**

## Next (if `next` is present)

If `$ARGUMENTS` contains `next` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /fix-issues`
3. Report:
   - If found: parse the cron expression and compute the next fire time.
     Use `date +%Z` for the timezone. Show both relative and absolute:
     > Next fix-issues sprint in ~2h 15m (~8:30 PM ET, cron XXXX).
     > Prompt: Run /fix-issues 5 auto every 4h
   - If none found: `No active /fix-issues cron in this session.`
4. Peek at the Ready queue in `.zskills/monitor-state.json`:
   - If `issues.ready` is non-empty: report the count
     (`N issues in Ready queue.`).
   - If `issues.ready` is empty (or the file does not exist): read the
     `updated_at` field (ISO 8601 timestamp written by every sync/snapshot
     cycle), compute minutes since that timestamp, and report:
     > Ready queue empty (last synced: N minutes ago). Run `/fix-issues sync` to refresh, or the next cron fire will sync automatically.
     If the file is missing or has no `updated_at`, say:
     > Ready queue empty (never synced). Run `/fix-issues sync` to populate.
5. **Exit.** Do not proceed to any phase.

## Stop (if `stop` is present)

If `$ARGUMENTS` contains `stop` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Delete ALL whose prompt starts with `Run /fix-issues` using `CronDelete`
3. Report what was cancelled:
   - If one cron found: `Fix-issues cron stopped (was job ID XXXX, every INTERVAL).`
   - If multiple found: `Stopped N fix-issues crons (IDs: XXXX, YYYY).`
   - If none found: `No active /fix-issues cron found.`
4. **Exit.** Do not proceed to any phase. The `stop` command does nothing else.

