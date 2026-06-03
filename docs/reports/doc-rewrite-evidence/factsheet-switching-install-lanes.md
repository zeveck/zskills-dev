# Factsheet — `docs/guides/switching-install-lanes.md`

Every factual claim in the rewritten guide, paired with the verbatim source
line that backs it (R1). Sources: `scripts/switch-install-path.sh` (the actual
tool), the project `CLAUDE.md` (lane definitions), and
`.claude/rules/zskills/managed.md` `## Migration scripts` (the
re-runnable-after-interrupt guarantee — this section is the rendered CLAUDE.md
the script header points at; it does not appear in the top-level `CLAUDE.md`,
see "Surprises").

---

## What switching does — there are two lanes, you pick one

**Doc:** "zskills installs one of two ways — as a Claude Code plugin, or through
the `/update-zskills` command. You run on exactly one of them at a time."

- `CLAUDE.md:22`: "**Two install lanes — a consumer picks exactly ONE.** A
  client is single-lane: it installs zskills via the plugin lane OR the legacy
  `/update-zskills` lane, never both."
- `CLAUDE.md:22`: "zskills is distributed via (1) the **plugin lane** … and (2)
  the legacy **`/update-zskills` lane**"

**Doc:** "`scripts/switch-install-path.sh` moves you from whichever lane you're
on to the other one."

- `scripts/switch-install-path.sh:2`: "# switch-install-path.sh — D25
  bidirectional install-lane switcher (W5.6)."
- `scripts/switch-install-path.sh:6-7`: "#   --to-plugin           Switch FROM
  the /update-zskills lane TO the plugin / #                         lane."
- `scripts/switch-install-path.sh:14-15`: "#   --to-update-zskills   Switch FROM
  the plugin lane TO the /update-zskills / #                         lane."

---

## The command to run

**Doc:** "To move to the plugin lane: `bash scripts/switch-install-path.sh
--to-plugin`. To move to the `/update-zskills` lane: `bash
scripts/switch-install-path.sh --to-update-zskills`."

- `scripts/switch-install-path.sh:269`: "usage: switch-install-path.sh
  {--to-plugin | --to-update-zskills}"
- `scripts/switch-install-path.sh:278-281`: "case "$MODE" in /   --to-plugin)
  to_plugin ;; /   --to-update-zskills) to_update_zskills ;;"

**Doc:** "You can also run it through `/update-zskills
--switch-install-path=to-plugin` (or `=to-update-zskills`)."

- `CLAUDE.md:24`: "(also reachable as `/update-zskills
  --switch-install-path={to-plugin|to-update-zskills}`)"

---

## --to-plugin: what it does, in order

**Doc:** "It lists your current `/update-zskills` files, removes the zskills hook
entries from `.claude/settings.json`…"

- `scripts/switch-install-path.sh:121`: "log "Pre-flight inventory of
  /update-zskills artifacts:""
- `scripts/switch-install-path.sh:128`: "log "Stripping zskills hook entries
  from settings.json""
- `scripts/switch-install-path.sh:129`: ""$PYTHON"
  "$SCRIPT_DIR/migrate-strip-settings.py" "$CLAUDE_DIR/settings.json""

**Doc:** "…then prints the in-session steps for you to run: add the marketplace,
install the plugin, and restart Claude Code."

- `scripts/switch-install-path.sh:133-136`: "log "Now in your Claude session:" /
  info "  /plugin marketplace add zeveck/zskills" / info "  /plugin install
  zs@zskills" / info "  Restart Claude Code (close + reopen).""

**Doc:** "After you confirm, it removes the mirrored zskills skills, hooks, and
`managed.md` rules file."

- `scripts/switch-install-path.sh:145`: "log "Removing /update-zskills mirror
  artifacts (basename-gated to shipped tree)""
- `scripts/switch-install-path.sh:152`: "rm -rf "$d" && info "  removed mirror
  skill: $bn""
- `scripts/switch-install-path.sh:164`: "rm -f "$h" && info "  removed mirror
  hook: $bn""
- `scripts/switch-install-path.sh:171`: "rm -f "$CLAUDE_DIR/rules/zskills/managed.md" && info "  removed managed.md""

---

## --to-update-zskills: what it does, in order

**Doc:** "It lists your current plugin files, then prints the in-session steps:
uninstall the plugin, restart, and run `/update-zskills install`."

- `scripts/switch-install-path.sh:212`: "log "Pre-flight inventory of
  plugin-materialised artifacts:""
- `scripts/switch-install-path.sh:228-231`: "log "Now in your Claude session:" /
  info "  /plugin uninstall zs@zskills" / info "  Restart Claude Code." / info "
  /update-zskills install""

**Doc:** "After you confirm, it removes the leftover plugin files."

- `scripts/switch-install-path.sh:240`: "log "Removing leftover sentinelled
  plugin artifacts (sentinel-gated)""
- `scripts/switch-install-path.sh:248`: "rm -f "$mat" && info "  removed
  sentinelled leftover: ${mat#$PROJ/}""

---

## Reassurance — it won't touch files you've edited

**Doc (--to-plugin):** "Skills and hooks you wrote yourself are left in place —
only the ones zskills ships are removed."

- `scripts/switch-install-path.sh:145`: "log "Removing /update-zskills mirror
  artifacts (basename-gated to shipped tree)""
- `scripts/switch-install-path.sh:154`: "info "  kept (not zskills-owned): $bn""
  (skills branch)
- `scripts/switch-install-path.sh:166`: "info "  kept (not zskills-owned): $bn""
  (hooks branch)
- `scripts/switch-install-path.sh:9-10` (header): "#
  sentinel-/basename-gated / #                         removal of the mirrored
  .claude/skills, .claude/hooks,"

**Doc (--to-plugin, settings.json):** "Your own hook entries in
`.claude/settings.json` stay; only the zskills ones are removed."

- `scripts/switch-install-path.sh:127-129`: "if [ -f
  "$CLAUDE_DIR/settings.json" ]; then … migrate-strip-settings.py …"
- `scripts/switch-install-path.sh:8` (header): "#                         Strips
  zskills hook entries from"
- existing guide `docs/guides/switching-install-lanes.md:22` (corroborating the
  preserve behavior): "(`scripts/migrate-strip-settings.py`; non-zskills hook
  entries preserved)."

**Doc (--to-update-zskills):** "A plugin file you've already replaced with your
own copy is kept; only untouched zskills files are removed."

- `scripts/switch-install-path.sh:236-239`: "# 6. Sentinel-gated removal of the
  5 materialised files — ONLY if they STILL / #    carry a materialiser sentinel
  … Sentinel-bearing leftovers are dead plugin / #    state; sentinel-less files
  are /update-zskills-owned and preserved."
- `scripts/switch-install-path.sh:250`: "info "  kept (no sentinel —
  /update-zskills-owned): ${mat#$PROJ/}""

**Doc (both directions):** "Your zskills runtime state — claims, tracking, audit
notes under `.zskills/` — is left untouched, the same on either lane."

- `scripts/switch-install-path.sh:178`: "info "  - .zskills/ runtime state was
  preserved (lane-independent).""
- `scripts/switch-install-path.sh:253`: "info "  .zskills/ runtime state
  preserved (lane-independent).""

---

## Safe to re-run / interruption is recoverable

**Doc:** "If a switch is interrupted partway, just run the same command again —
it picks up where it left off."

- `.claude/rules/zskills/managed.md:292-294` (`## Migration scripts`):
  "**Multi-step state-mutating scripts must write the idempotency lock LAST.** …
  Earlier failures must leave the consumer in a re-runnable state."
- `scripts/switch-install-path.sh:21-23` (header): "# FINAL step in BOTH
  directions. An earlier failure leaves the consumer in a / # re-runnable state
  — the lock is the claim that the switch completed."

**Doc:** "Running a switch toward the lane you're already on does nothing — it
just tells you you're already there."

- `scripts/switch-install-path.sh:110-115`: "local prior; prior="$(read_lock)"
  / if [ "$prior" = plugin ]; then / log "Already on the plugin lane
  (lock=plugin)." / info "No-op. Nothing to switch.""
- `scripts/switch-install-path.sh:187-192`: "if [ "$prior" = update-zskills ];
  then / log "Already on the /update-zskills lane (lock=update-zskills)." / info
  "No-op. Nothing to switch.""

---

## Reverting a switch

**Doc:** "Changed your mind? Run the opposite direction. From the plugin lane
back to `/update-zskills`: `bash scripts/switch-install-path.sh
--to-update-zskills`, then `/update-zskills install`."

- `scripts/switch-install-path.sh:14-15`: "#   --to-update-zskills   Switch FROM
  the plugin lane TO the /update-zskills"
- `scripts/switch-install-path.sh:231`: "info "  /update-zskills install""
- existing guide `docs/guides/switching-install-lanes.md:64-66` (corroborating
  the revert sequence): "run / `scripts/switch-install-path.sh --to-plugin`,
  then / `/plugin install zs@zskills`."

---

## Surprises / drift

- **`## Migration scripts` is NOT in the top-level `CLAUDE.md`.** It lives only
  in the rendered `.claude/rules/zskills/managed.md:290`. The script header
  (`scripts/switch-install-path.sh:19`) refers to it as "CLAUDE.md `##
  Migration scripts`" — that reference resolves to the *rendered* CLAUDE.md
  (managed.md), not the source `CLAUDE.md`. The guide's re-runnable-after-
  interrupt claim is cited to `managed.md:292` plus the script header
  (lines 21-23) so it stands on the script's own ground truth regardless.
- **No `PLAN-TEXT-DRIFT:`** — the plan's described command invocations
  (`--to-plugin` / `--to-update-zskills` / `/update-zskills
  --switch-install-path=...`) all match source exactly.
- The marketplace add target is `zeveck/zskills` and the plugin id is
  `zs@zskills` (`scripts/switch-install-path.sh:134-135`, `229`) — used verbatim
  in the guide's step lists.
