#!/usr/bin/env bash
# switch-install-path.sh — D25 bidirectional install-lane switcher (W5.6).
#
# Replaces the round-3 one-way migrate-to-plugin.sh. Two modes:
#
#   --to-plugin           Switch FROM the /update-zskills lane TO the plugin
#                         lane. Strips zskills hook entries from
#                         .claude/settings.json, sentinel-/basename-gated
#                         removal of the mirrored .claude/skills, .claude/hooks,
#                         and managed.md, then writes the `plugin` lock LAST.
#
#   --to-update-zskills   Switch FROM the plugin lane TO the /update-zskills
#                         lane. Sentinel-gated removal of the 5 plugin-
#                         materialised artifacts (only if they STILL carry a
#                         materialiser sentinel — i.e. /update-zskills install
#                         did not already overwrite them), then writes the
#                         `update-zskills` lock LAST.
#
# LOCK-LAST CONTRACT (CLAUDE.md `## Migration scripts`): config/state writes
# happen FIRST; the lock file `.claude/zskills-install-lane` (bare value
# `plugin\n` / `update-zskills\n`, written atomically tmpfile+rename) is the
# FINAL step in BOTH directions. An earlier failure leaves the consumer in a
# re-runnable state — the lock is the claim that the switch completed.
#
# Reads any pre-existing lock at START to validate the transition:
#   - --to-plugin on an already-`plugin` lane → no-op-with-INFO.
#   - --to-update-zskills on an already-`update-zskills` lane → no-op-with-INFO.
#
# The interactive "run /plugin ... then type done" steps block on `read`.
# For non-interactive use (fixture tests, CI), set
# ZSKILLS_SWITCH_NONINTERACTIVE=1 to skip the read-block (the user-facing
# instruction is still printed). Per `## Python is required` — Python stdlib
# json via migrate-strip-settings.py, no jq.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

# Project root: explicit env override (used by tests on fixtures) else the
# repo this script lives in.
PROJ="${ZSKILLS_SWITCH_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$REPO_ROOT}}"
CLAUDE_DIR="$PROJ/.claude"
LOCK="$CLAUDE_DIR/zskills-install-lane"

# Source the detection probe. Prefer the plugin-root copy (runtime), else the
# source-tree copy. Resolve from REPO_ROOT since this script ships in scripts/.
DETECT_SRC=""
for cand in "$REPO_ROOT/hooks/_lib/detect-install-state.sh" \
            "${CLAUDE_PLUGIN_ROOT:-}/hooks/_lib/detect-install-state.sh"; do
  if [ -n "$cand" ] && [ -f "$cand" ]; then DETECT_SRC="$cand"; break; fi
done
[ -n "$DETECT_SRC" ] || { echo "ERROR: cannot locate hooks/_lib/detect-install-state.sh" >&2; exit 1; }
# shellcheck source=/dev/null
. "$DETECT_SRC"

log()  { printf '\033[1m▸\033[0m %s\n' "$1"; }
info() { printf '   %s\n' "$1"; }
done_() { printf '\033[32m✓\033[0m %s\n' "$1"; }

read_lock() {
  [ -f "$LOCK" ] && cat "$LOCK" 2>/dev/null || true
}

# Write the lock LAST, atomically. $1 = bare value (plugin | update-zskills).
write_lock_last() {
  local value="$1" tmp
  mkdir -p "$CLAUDE_DIR"
  tmp="$LOCK.tmp.$$"
  printf '%s\n' "$value" > "$tmp"
  mv "$tmp" "$LOCK"
  done_ "lock written LAST: .claude/zskills-install-lane = $value"
}

# Block on user confirmation unless non-interactive.
confirm_block() {
  if [ "${ZSKILLS_SWITCH_NONINTERACTIVE:-0}" = "1" ]; then
    info "(non-interactive: skipping the 'type done' block)"
    return 0
  fi
  local reply
  read -r -p "When finished, type 'done' and press Enter: " reply
  while [ "$reply" != "done" ]; do
    read -r -p "Type 'done' when finished (or Ctrl-C to abort): " reply
  done
}

# Is $1 a zskills-owned skill/hook by basename against the shipped source
# tree (D25/D27 wildcard rule — no frozen KNOWN_* lists)? $1 = a basename.
is_shipped_skill() {
  [ -d "$REPO_ROOT/skills/$1" ] || [ -d "$REPO_ROOT/block-diagram/$1" ]
}
is_shipped_hook() {
  # Match against hooks/*.sh and hooks/*.sh.template basenames.
  local bn="$1"
  [ -f "$REPO_ROOT/hooks/$bn" ] || [ -f "$REPO_ROOT/hooks/$bn.template" ]
}

# Does $1 (a file) carry a materialiser sentinel in its first 3 lines?
has_materialiser_sentinel() {
  [ -f "$1" ] || return 1
  head -n 3 "$1" 2>/dev/null | grep -Eq '^(#|<!--)[[:space:]]+zskills-materialised:[[:space:]]'
}

# ── --to-plugin ────────────────────────────────────────────────────────────
to_plugin() {
  local prior; prior="$(read_lock)"
  if [ "$prior" = plugin ]; then
    log "Already on the plugin lane (lock=plugin)."
    info "No-op. Nothing to switch."
    return 0
  fi

  log "Switching to the PLUGIN lane."
  info "Detected current lane: $(detect_install_state "$PROJ")"

  # 1. Pre-flight inventory.
  log "Pre-flight inventory of /update-zskills artifacts:"
  [ -d "$CLAUDE_DIR/skills" ] && info "  mirror skills: $(ls "$CLAUDE_DIR/skills" 2>/dev/null | wc -l | tr -d ' ') dirs"
  [ -d "$CLAUDE_DIR/hooks" ] && info "  hook scripts:  $(ls "$CLAUDE_DIR/hooks"/*.sh 2>/dev/null | wc -l | tr -d ' ') files"
  [ -f "$CLAUDE_DIR/settings.json" ] && info "  settings.json: present"

  # 2. Strip zskills hook entries from settings.json (config write FIRST).
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    log "Stripping zskills hook entries from settings.json"
    "$PYTHON" "$SCRIPT_DIR/migrate-strip-settings.py" "$CLAUDE_DIR/settings.json"
  fi

  # 3. User instruction.
  log "Now in your Claude session:"
  info "  /plugin marketplace add zeveck/zskills"
  info "  /plugin install zs@zskills"
  info "  Restart Claude Code (close + reopen)."

  # 4. Block on confirmation.
  confirm_block

  # 6. Sentinel-/basename-gated removal of mirror artifacts. (Step 5 verify
  #    plugin install is interactive-environment-only — skipped in
  #    non-interactive fixture mode.) Does NOT touch consumer/third-party
  #    skills or .zskills/ runtime state.
  log "Removing /update-zskills mirror artifacts (basename-gated to shipped tree)"
  if [ -d "$CLAUDE_DIR/skills" ]; then
    local d bn
    for d in "$CLAUDE_DIR"/skills/*/; do
      [ -d "$d" ] || continue
      bn="$(basename "$d")"
      if is_shipped_skill "$bn"; then
        rm -rf "$d" && info "  removed mirror skill: $bn"
      else
        info "  kept (not zskills-owned): $bn"
      fi
    done
  fi
  if [ -d "$CLAUDE_DIR/hooks" ]; then
    local h bn
    for h in "$CLAUDE_DIR"/hooks/*.sh; do
      [ -f "$h" ] || continue
      bn="$(basename "$h")"
      if is_shipped_hook "$bn"; then
        rm -f "$h" && info "  removed mirror hook: $bn"
      else
        info "  kept (not zskills-owned): $bn"
      fi
    done
  fi
  if [ -f "$CLAUDE_DIR/rules/zskills/managed.md" ]; then
    rm -f "$CLAUDE_DIR/rules/zskills/managed.md" && info "  removed managed.md"
  fi

  # 8. .gitignore / CI guidance.
  log "Guidance:"
  info "  - Commit the stripped .claude/settings.json."
  info "  - Add the plugin lane to CI (see .github/workflows/test.yml plugin job)."
  info "  - .zskills/ runtime state was preserved (lane-independent)."

  # 7. Write the lock LAST.
  write_lock_last plugin
  done_ "Switched to the plugin lane."
}

# ── --to-update-zskills ──────────────────────────────────────────────────
to_update_zskills() {
  local prior; prior="$(read_lock)"
  if [ "$prior" = update-zskills ]; then
    log "Already on the /update-zskills lane (lock=update-zskills)."
    info "No-op. Nothing to switch."
    return 0
  fi

  log "Switching to the /update-zskills lane."
  info "Detected current lane: $(detect_install_state "$PROJ")"

  # W6.2 — switch-in-progress marker. This flow instructs the user to
  # `/plugin uninstall` → restart → `/update-zskills install` while
  # detect_install_state may still return `plugin` (the plugin is loaded until
  # the restart, and the materialiser re-arms the sentinelled artifacts on the
  # restart). The marker is the load-bearing state that survives that restart:
  # while present, BOTH (i) the SKILL.md Step 0.7 W6.1 hard-refuse skips
  # itself (so the mandated `/update-zskills install` is allowed) AND (ii)
  # session-start-materialise.sh skips re-materialise (so it does not re-arm
  # detect==plugin across the restart). Written at the START; removed only
  # AFTER the lane-lock is written LAST (preserving the lock-LAST contract).
  mkdir -p "$PROJ/.zskills"
  : > "$PROJ/.zskills/switch-in-progress"
  info "wrote .zskills/switch-in-progress (W6.2 — honored by the install refuse + materialiser until lock-write)"

  # 1. Pre-flight inventory of the 5 materialised plugin artifacts.
  log "Pre-flight inventory of plugin-materialised artifacts:"
  local mat
  for mat in \
    "$CLAUDE_DIR/agents/verifier.md" \
    "$CLAUDE_DIR/agents/implementer.md" \
    "$CLAUDE_DIR/hooks/inject-bash-timeout.sh" \
    "$CLAUDE_DIR/hooks/verify-response-validate.sh" \
    "$CLAUDE_DIR/rules/zskills/managed.md"; do
    if has_materialiser_sentinel "$mat"; then
      info "  sentinelled (plugin-materialised): ${mat#$PROJ/}"
    elif [ -f "$mat" ]; then
      info "  present, NO sentinel (consumer/update-zskills-owned): ${mat#$PROJ/}"
    fi
  done

  # 2. User instruction.
  log "Now in your Claude session:"
  info "  /plugin uninstall zs@zskills"
  info "  Restart Claude Code."
  info "  /update-zskills install"

  # 3. Block on confirmation.
  confirm_block

  # 6. Sentinel-gated removal of the 5 materialised files — ONLY if they STILL
  #    carry a materialiser sentinel (meaning /update-zskills install did NOT
  #    already overwrite them). Sentinel-bearing leftovers are dead plugin
  #    state; sentinel-less files are /update-zskills-owned and preserved.
  log "Removing leftover sentinelled plugin artifacts (sentinel-gated)"
  for mat in \
    "$CLAUDE_DIR/agents/verifier.md" \
    "$CLAUDE_DIR/agents/implementer.md" \
    "$CLAUDE_DIR/hooks/inject-bash-timeout.sh" \
    "$CLAUDE_DIR/hooks/verify-response-validate.sh" \
    "$CLAUDE_DIR/rules/zskills/managed.md"; do
    if has_materialiser_sentinel "$mat"; then
      rm -f "$mat" && info "  removed sentinelled leftover: ${mat#$PROJ/}"
    elif [ -f "$mat" ]; then
      info "  kept (no sentinel — /update-zskills-owned): ${mat#$PROJ/}"
    fi
  done
  info "  .zskills/ runtime state preserved (lane-independent)."

  # 7. Write the lock LAST.
  write_lock_last update-zskills

  # W6.2 — switch complete: remove the in-progress marker ONLY after the
  # lock has been written LAST (lock-LAST contract preserved — the marker is
  # cleared strictly after the claim). Steady-state dual handling (the
  # materialiser nag) resumes on the next session.
  rm -f "$PROJ/.zskills/switch-in-progress"
  info "removed .zskills/switch-in-progress (switch complete)"
  done_ "Switched to the /update-zskills lane."
}

usage() {
  cat >&2 <<EOF
usage: switch-install-path.sh {--to-plugin | --to-update-zskills}

Bidirectional install-lane switcher (D25). Writes the lock file LAST.
Set ZSKILLS_SWITCH_NONINTERACTIVE=1 to skip the 'type done' block.
EOF
  exit 2
}

MODE="${1:-}"
case "$MODE" in
  --to-plugin)        to_plugin ;;
  --to-update-zskills) to_update_zskills ;;
  *) usage ;;
esac
