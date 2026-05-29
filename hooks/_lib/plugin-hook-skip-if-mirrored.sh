#!/usr/bin/env bash
# plugin-hook-skip-if-mirrored.sh — D16(a) conditional-skip shim.
#
# Sourced as the FIRST executable line of every plugin-registered hook
# script (those listed in hooks/hooks.json). Prevents hook double-fire when
# a consumer has BOTH install lanes active at once: the plugin lane
# (hooks.json registers ${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh) AND the
# /update-zskills lane (settings.json registers
# $CLAUDE_PROJECT_DIR/.claude/hooks/<name>.sh). Plugin hooks.json and the
# consumer's settings.json compose ADDITIVELY at the harness level
# (research §13), so without this shim both copies of the same hook fire on
# every matching tool call.
#
# Mechanism (D16(a), 7 steps — see docs/plans/PLUGIN_DISTRIBUTION.md):
#   1. Plugin hook sources this shim as its first executable line.
#   2. Shim computes MY_BASENAME from ${BASH_SOURCE[0]} — when sourced,
#      [0] is the SOURCING hook's path (empirically confirmed under
#      claude 2.1.149; NOT the shim's own path).
#   3. Shim reads $CLAUDE_PROJECT_DIR/.claude/settings.json via Python and
#      iterates hooks.<event>[].hooks[] entries.
#   4. For each entry's command, extracts the last whitespace-separated
#      token (the script path), strips quoting, basename-matches against
#      MY_BASENAME. settings.json stores $CLAUDE_PROJECT_DIR / ${...} as a
#      LITERAL string; basename works on the literal, but any disk
#      existence-check / read substitutes the env var first.
#   5. On basename match: version-skew compare via the line-2
#      `# zskills-hook-version:` stamp on both copies. Plugin STRICTLY
#      NEWER → one-time-per-session WARN to stderr + defer (exit 0).
#   6. Plugin EQUAL/OLDER, or either stamp absent → silent defer (exit 0).
#   7. No basename match → return (do not exit); calling hook continues.
#
# KNOWN COST: two legitimately-distinct hooks sharing a basename across
# lanes would be conflated. zskills owns all its hook basenames (the source
# tree is the single point of basename assignment), so this is safe in
# practice. Env-sentinel races are explicitly out-of-scope; the
# basename + version-stamp check is deterministic and stateless across
# invocations.
#
# This shim must be sourced (not exec'd). When sourced and it decides to
# defer, it calls `exit 0` which terminates the SOURCING hook — the
# intended behaviour. When it decides "continue", it `return`s so the
# sourcing hook resumes.

# Resolve Python (per `## Python is required`).
_PHSIM_PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"

# If we cannot resolve Python or settings.json, fail-open: the calling hook
# continues normally (no skip). A missing settings.json means the consumer
# is plugin-only (no /update-zskills lane) → no double-fire risk.
_phsim_main() {
  local my_path my_basename settings consumer_script plugin_ver consumer_ver marker

  # Step 2: basename of the sourcing hook. The sourcing hook is the
  # OUTERMOST entry of the BASH_SOURCE stack (the script the harness invoked
  # with `bash <hook>`), regardless of how many sourced/function frames sit
  # between it and this shim. The empirical 2026-05-26 note claimed
  # ${BASH_SOURCE[0]} == the sourcing hook under claude 2.1.149 (call depth
  # 1, so [0] == outermost). Under a plain `bash <hook>` invocation that
  # source-includes this shim, the shim's own path is [0] and the hook is the
  # LAST index. Using the outermost (last) entry resolves to the sourcing
  # hook in BOTH environments — portable and correct. (Past fragility: the
  # hardcoded [0] silently no-op'd under plain bash, defeating the
  # double-fire guard everywhere except the exact claude build it was tuned
  # for; W5.7 testbed surfaced it.)
  my_path="${BASH_SOURCE[${#BASH_SOURCE[@]}-1]}"
  my_basename="$(basename "$my_path")"

  # Need CLAUDE_PROJECT_DIR to find the consumer settings.json.
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] || return 0
  settings="${CLAUDE_PROJECT_DIR}/.claude/settings.json"
  [ -f "$settings" ] || return 0
  [ -n "$_PHSIM_PYTHON" ] || return 0

  # Steps 3-4: find a settings.json hook entry whose command path-token
  # has the same basename as MY_BASENAME. Emit the RAW (unsubstituted)
  # path-token so the shell can substitute env vars before any disk read.
  consumer_script="$(
    MY_BASENAME="$my_basename" "$_PHSIM_PYTHON" - "$settings" <<'PY'
import json, os, sys
settings_path = sys.argv[1]
target = os.environ.get("MY_BASENAME", "")
try:
    with open(settings_path) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
hooks = data.get("hooks", {})
if not isinstance(hooks, dict):
    sys.exit(0)
for event in hooks.values():
    if not isinstance(event, list):
        continue
    for matcher in event:
        if not isinstance(matcher, dict):
            continue
        for h in matcher.get("hooks", []):
            if not isinstance(h, dict):
                continue
            cmd = h.get("command", "")
            if not isinstance(cmd, str) or not cmd.strip():
                continue
            token = cmd.split()[-1].strip('"').strip("'")
            if os.path.basename(token) == target:
                print(token)
                sys.exit(0)
sys.exit(0)
PY
  )"

  # Step 7: no basename match → continue (the calling hook runs).
  [ -n "$consumer_script" ] || return 0

  # Step 4 (substitution): settings.json stores $CLAUDE_PROJECT_DIR /
  # ${CLAUDE_PROJECT_DIR} as a LITERAL. Substitute both forms before any
  # disk read.
  consumer_script="${consumer_script//\$\{CLAUDE_PROJECT_DIR\}/$CLAUDE_PROJECT_DIR}"
  consumer_script="${consumer_script//\$CLAUDE_PROJECT_DIR/$CLAUDE_PROJECT_DIR}"

  # Steps 5-6: version-skew compare. Read line-2-ish stamp from both copies.
  plugin_ver="$(head -n 5 "$my_path" 2>/dev/null | grep -m1 'zskills-hook-version:' | sed -E 's/.*zskills-hook-version:[[:space:]]*//')"
  consumer_ver=""
  if [ -f "$consumer_script" ]; then
    consumer_ver="$(head -n 5 "$consumer_script" 2>/dev/null | grep -m1 'zskills-hook-version:' | sed -E 's/.*zskills-hook-version:[[:space:]]*//')"
  fi

  # Step 6: either stamp absent → silent defer (settings.json wins; no
  # version regression possible).
  if [ -z "$plugin_ver" ] || [ -z "$consumer_ver" ]; then
    exit 0
  fi

  # Step 5: plugin STRICTLY NEWER than consumer copy → one-time WARN + defer.
  # Comparison is string-sort safe for the YYYY.MM.N scheme (zero-padded
  # year/month; integer N). Use sort -V for robustness.
  if [ "$plugin_ver" != "$consumer_ver" ]; then
    local newer
    newer="$(printf '%s\n%s\n' "$plugin_ver" "$consumer_ver" | sort -V | tail -n1)"
    if [ "$newer" = "$plugin_ver" ]; then
      # Plugin is newer. Emit once-per-session-per-hook WARN, then defer.
      marker="${CLAUDE_PROJECT_DIR}/.zskills/hook-skew-warned-${my_basename}"
      if [ ! -f "$marker" ]; then
        mkdir -p "${CLAUDE_PROJECT_DIR}/.zskills" 2>/dev/null
        : > "$marker" 2>/dev/null
        printf 'zskills: settings.json hook %s is version %s but plugin ships %s; deferring to settings.json copy. Run /update-zskills install or bash scripts/switch-install-path.sh --to-plugin to consolidate.\n' \
          "$my_basename" "$consumer_ver" "$plugin_ver" >&2
      fi
      exit 0
    fi
  fi

  # Plugin EQUAL or OLDER than consumer copy → silent defer (settings.json
  # wins — no version regression).
  exit 0
}

_phsim_main
