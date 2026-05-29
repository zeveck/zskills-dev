# Switching install lanes (`scripts/switch-install-path.sh`)

zskills ships via two permanent install lanes — the **plugin lane** and the
legacy **`/update-zskills` lane**. `scripts/switch-install-path.sh` is the
bidirectional consolidation tool (D25) for moving a consumer between them.
It is also reachable as
`/update-zskills --switch-install-path={to-plugin|to-update-zskills}`.

Both directions follow the **lock-LAST** contract (CLAUDE.md
`## Migration scripts`): all config/state writes happen first, and the lock
file `.claude/zskills-install-lane` (bare value `plugin\n` or
`update-zskills\n`, written atomically via tmpfile + rename) is the FINAL
step. An interrupted switch therefore leaves the consumer in a re-runnable
state — re-running the same direction resumes cleanly. Neither direction
touches `.zskills/` runtime state (claim markers, tracking, audit) — that
state is lane-independent and preserved across switches.

## `--to-plugin` (from `/update-zskills` → plugin)

1. Pre-flight inventory of `/update-zskills` artifacts.
2. Strip zskills hook entries from `.claude/settings.json`
   (`scripts/migrate-strip-settings.py`; non-zskills hook entries preserved).
3. Prints the in-session steps: `/plugin marketplace add zeveck/zskills`,
   `/plugin install zs@zskills`, restart.
4. Blocks on confirmation (`ZSKILLS_SWITCH_NONINTERACTIVE=1` skips the block
   for tests/CI).
5. Basename-gated removal of the mirrored `.claude/skills/<zskills>/`,
   `.claude/hooks/<zskills>.sh`, and `.claude/rules/zskills/managed.md` —
   gated against the shipped source-tree basenames, so consumer-authored
   skills/hooks are NEVER removed.
6. Writes `plugin` to the lock LAST.

### Abort / Rollback (`--to-plugin`)

- **Before the lock is written** (script interrupted at any earlier step):
  nothing is committed. Re-run `--to-plugin` to resume, OR restore the
  legacy lane by running `/update-zskills install` (re-mirrors skills/hooks
  and re-registers settings.json hooks) — the mirror removal in step 5 is
  reversible by a fresh install.
- **After the lock is written but you want to revert:** run
  `scripts/switch-install-path.sh --to-update-zskills` (the reverse
  direction), then `/update-zskills install` to re-materialise the legacy
  mirror. Uninstall the plugin with `/plugin uninstall zs@zskills` if you do
  not want both lanes co-present.

## `--to-update-zskills` (from plugin → `/update-zskills`)

1. Pre-flight inventory of the 5 plugin-materialised artifacts.
2. Prints the in-session steps: `/plugin uninstall zs@zskills`, restart,
   `/update-zskills install`.
3. Blocks on confirmation (skipped under `ZSKILLS_SWITCH_NONINTERACTIVE=1`).
4. Sentinel-gated removal of the 5 materialised files — ONLY the ones STILL
   carrying a `zskills-materialised:` sentinel. A file that
   `/update-zskills install` already overwrote (sentinel-less) is
   `/update-zskills`-owned and is preserved.
5. Writes `update-zskills` to the lock LAST.

### Abort / Rollback (`--to-update-zskills`)

- **Before the lock is written:** nothing is committed. Re-run
  `--to-update-zskills` to resume, OR re-enable the plugin lane with
  `/plugin install zs@zskills` (the SessionStart materialiser re-writes the
  5 artifacts on next session start).
- **After the lock is written but you want to revert:** run
  `scripts/switch-install-path.sh --to-plugin`, then
  `/plugin install zs@zskills`.

## No-op behaviour

Invoking a direction whose lock already matches the requested lane is a
no-op-with-INFO (the script reads the pre-existing lock at START and reports
"Already on the … lane"). This makes the tool idempotent and safe to re-run.
