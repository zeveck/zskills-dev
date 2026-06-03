# Switching install lanes

zskills installs one of two ways, and you run on exactly one of them at a time:

- the **plugin lane** — installed as a Claude Code plugin, or
- the **`/update-zskills` lane** — installed and updated through the
  `/update-zskills` command, which copies zskills' skills and hooks into your
  project's `.claude/` directory.

`scripts/switch-install-path.sh` moves you from whichever lane you're on to the
other one. You can also run it through Claude with `/update-zskills
--switch-install-path=to-plugin` (or `=to-update-zskills`).

## The command

To move to the plugin lane:

```bash
bash scripts/switch-install-path.sh --to-plugin
```

To move to the `/update-zskills` lane:

```bash
bash scripts/switch-install-path.sh --to-update-zskills
```

Each direction prints a few in-session steps for you to run inside Claude Code,
pauses while you do them, and then cleans up the files from the lane you're
leaving.

## Moving to the plugin lane (`--to-plugin`)

The script:

1. Lists your current `/update-zskills` files so you can see what's there.
2. Removes the zskills hook entries from `.claude/settings.json`. Your own hook
   entries stay — only the zskills ones are removed.
3. Prints the steps to run in your Claude session:
   ```
   /plugin marketplace add zeveck/zskills
   /plugin install zs@zskills
   ```
   then restart Claude Code (close and reopen).
4. After you confirm you've done that, removes the zskills skills, hooks, and
   rules file that the `/update-zskills` lane had copied into `.claude/`.

**Skills and hooks you wrote yourself are left in place** — only the ones zskills
ships get removed.

## Moving to the `/update-zskills` lane (`--to-update-zskills`)

The script:

1. Lists your current plugin files.
2. Prints the steps to run in your Claude session:
   ```
   /plugin uninstall zs@zskills
   ```
   then restart Claude Code, then run `/update-zskills install`.
3. After you confirm, removes the leftover plugin files.

**A plugin file you've already replaced with your own copy is kept** — only the
untouched zskills files are removed.

## What's preserved either way

- **Your own skills, hooks, and settings entries.** Switching only removes the
  files zskills itself ships.
- **Your zskills runtime state** — claims, tracking, and audit notes under
  `.zskills/`. That state is the same on either lane, so switching leaves it
  untouched.

## Re-running and reverting

- **Safe to re-run.** If a switch is interrupted partway through, run the same
  command again — it picks up where it left off and finishes cleanly.
- **Already on that lane?** Running a switch toward the lane you're already on
  does nothing; the script just reports "Already on the … lane."
- **Changed your mind?** Run the opposite direction. For example, to go from the
  plugin lane back to `/update-zskills`, run `bash
  scripts/switch-install-path.sh --to-update-zskills` and then `/update-zskills
  install`.
