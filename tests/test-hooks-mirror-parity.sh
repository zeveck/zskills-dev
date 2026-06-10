#!/bin/bash
# tests/test-hooks-mirror-parity.sh
#
# Asserts byte-equality between every hook source under `hooks/` and its
# installed mirror under `.claude/hooks/`. Closes the "mirror-bypassed-tests"
# class of bug (issue #390): every test in `tests/test-skill-version-*` and
# friends targets the source `hooks/*.sh`, but `.claude/settings.json` wires
# the mirror under `.claude/hooks/*.sh`. When the source is updated without
# refreshing the mirror, CI stays green while production is silently inert.
#
# Mapping rules (per skills/update-zskills/SKILL.md "Copy missing hooks"):
#   hooks/<X>.sh                      -> .claude/hooks/<X>.sh           (byte-equal)
#   hooks/<X>.sh.template             -> .claude/hooks/<X>.sh           (byte-equal,
#                                                                       no install-time
#                                                                       placeholder fill)
# Exclusions:
#   hooks/_lib/*       — source-of-truth helpers inlined into hooks, never installed.
#   hooks/canary3-bad.sh — deliberately-broken syntax-error fixture for canary tests;
#                          not a real hook, not installed.
#   hooks/session-start-materialise.sh — PLUGIN-LANE-ONLY hook (registered in
#                          hooks/hooks.json under SessionStart, never in
#                          .claude/settings.json). It is the plugin equivalent
#                          of /update-zskills's install-time writes (plugins
#                          cannot write at install time — research §10); the
#                          /update-zskills lane performs those writes directly
#                          and has no SessionStart materialiser, so there is no
#                          mirror to byte-compare. (Phase 2, W2.1, D11.)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Excluded basenames (not real hooks / not installed).
EXCLUDE_BASENAMES=(
  "canary3-bad.sh"
  "session-start-materialise.sh"
  # block-unmaterialised-skill.sh (#1128) — PLUGIN-LANE-ONLY UserPromptExpansion
  # gate (registered in hooks/hooks.json, never in .claude/settings.json). The
  # half-installed state it closes is plugin-lane-only, so there is no
  # /update-zskills mirror to byte-compare.
  "block-unmaterialised-skill.sh"
  # session-rules-context.sh (INSTALL_REDESIGN Phase 4, R-b) — PLUGIN-LANE-ONLY
  # SessionStart rules delivery via additionalContext (registered in
  # hooks/hooks.json, never in .claude/settings.json). The legacy lane delivers
  # the managed rules from disk (.claude/rules/zskills/managed.md), so there is
  # no /update-zskills mirror to byte-compare — do NOT create one.
  "session-rules-context.sh"
)

is_excluded() {
  local bn="$1"
  for x in "${EXCLUDE_BASENAMES[@]}"; do
    [[ "$bn" == "$x" ]] && return 0
  done
  return 1
}

# Collect candidate source hooks: top-level `hooks/*.sh` and `hooks/*.sh.template`.
# (Subdirectories like `hooks/_lib/` are intentionally not globbed.)
shopt -s nullglob
SOURCES=( hooks/*.sh hooks/*.sh.template )
shopt -u nullglob

if [[ ${#SOURCES[@]} -eq 0 ]]; then
  fail "no hook sources matched hooks/*.sh{,.template} — glob likely broken"
fi

for SRC in "${SOURCES[@]}"; do
  bn="$(basename "$SRC")"
  if is_excluded "$bn"; then
    pass "skip (excluded fixture): $SRC"
    continue
  fi

  # Map source basename to expected mirror basename:
  #   <name>.sh.template -> <name>.sh
  #   <name>.sh          -> <name>.sh
  if [[ "$bn" == *.sh.template ]]; then
    mirror_bn="${bn%.template}"
  else
    mirror_bn="$bn"
  fi
  MIRROR=".claude/hooks/$mirror_bn"

  if [[ ! -f "$MIRROR" ]]; then
    fail "mirror missing: $SRC has no mirror at $MIRROR"
    continue
  fi

  if cmp -s "$SRC" "$MIRROR"; then
    pass "mirror parity: $SRC == $MIRROR"
  else
    fail "mirror drift: $SRC and $MIRROR differ (run: cp '$SRC' '$MIRROR')"
  fi
done

# Reverse check: every `.claude/hooks/*.sh` must have a source under `hooks/`
# (either same name, or with a `.template` suffix). This catches the case
# where a mirror exists but no source — implying a stale install that would
# never be regenerated.
shopt -s nullglob
MIRRORS=( .claude/hooks/*.sh )
shopt -u nullglob

for MIR in "${MIRRORS[@]}"; do
  bn="$(basename "$MIR")"
  if [[ -f "hooks/$bn" || -f "hooks/${bn}.template" ]]; then
    pass "reverse: mirror $MIR has a source under hooks/"
  else
    fail "reverse: mirror $MIR has no corresponding source under hooks/"
  fi
done

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit $FAIL_COUNT
