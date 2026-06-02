#!/usr/bin/env bash
# tests/lib/attended-gate.sh
#
# Capability-gate + throttle decision for the live (attended) plugin runtime
# checks in tests/test-plugin-live-load.sh §B.
#
# This is a SOURCEABLE library, NOT a suite — it exposes the pure decision
# function `attended_gate_should_run` so a deterministic unit test
# (tests/test-attended-gate.sh) can exercise every branch WITHOUT a live
# `claude` CLI. tests/run-all.sh sources it right before it runs the
# test-plugin-live-load.sh suite and uses the decision to (only then) export
# ZSKILLS_LIVE_ATTENDED=1 for that one suite.
#
# Rationale (#991): the §B checks (hookfire, dual-install, (A2)-runtime) are
# real and passing but only ran when a human set ZSKILLS_LIVE_ATTENDED=1 —
# nobody does, so they rotted. We instead gate on machine CAPABILITY (claude +
# credentials present) and a throttle window, so they auto-run in an authed
# devcontainer and SKIP cleanly on CI (no `claude`) — byte-for-byte unchanged
# there.
#
# No jq — Python json per `## Python is required` (not needed here).

# Default capability probes. Both are overridable: a caller (or the
# deterministic test) may redefine these functions BEFORE calling
# attended_gate_should_run to simulate presence/absence without a real CLI or
# credential file. The env overrides ZSKILLS_GATE_FORCE_CLAUDE /
# ZSKILLS_GATE_FORCE_CREDS (values "1"=present, "0"=absent) take precedence,
# so the test can drive the decision purely through the environment too.

_attended_gate_have_claude() {
  case "${ZSKILLS_GATE_FORCE_CLAUDE:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  command -v claude >/dev/null 2>&1
}

_attended_gate_have_creds() {
  case "${ZSKILLS_GATE_FORCE_CREDS:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  [ -f "${HOME:-/nonexistent}/.claude/.credentials.json" ]
}

# attended_gate_should_run <marker_path> <now_epoch> <throttle_seconds>
#
# Returns 0 (gate PASSES — run §B, caller should export the flag and refresh
# the marker) iff ALL hold:
#   1. a `claude` CLI is available    (_attended_gate_have_claude)
#   2. credentials are present        (_attended_gate_have_creds)
#   3. the throttle window has elapsed: the marker is absent, unreadable, or
#      its stored epoch is more than <throttle_seconds> before <now_epoch>.
#
# Returns 1 (gate FAILS — leave the flag unset so §B SKIPs as today) otherwise.
attended_gate_should_run() {
  local marker_path="$1" now_epoch="$2" throttle_seconds="$3"

  # 1 + 2: capability.
  _attended_gate_have_claude || return 1
  _attended_gate_have_creds  || return 1

  # 3: throttle. Never run / unreadable marker => stale => run.
  if [ ! -f "$marker_path" ]; then
    return 0
  fi
  local last
  last="$(cat "$marker_path" 2>/dev/null)"
  # A non-numeric / empty marker is treated as stale (re-run, then refresh).
  case "$last" in
    ''|*[!0-9]*) return 0 ;;
  esac
  if [ "$((now_epoch - last))" -gt "$throttle_seconds" ]; then
    return 0
  fi
  return 1
}

# attended_gate_refresh_marker <marker_path> <now_epoch>
#
# Write the throttle timestamp atomically. Creates the parent dir (e.g.
# ~/.zskills) if needed. Best-effort: a failure to write must not break the
# test run (the worst case is the throttle simply doesn't take and §B runs
# again next time).
attended_gate_refresh_marker() {
  local marker_path="$1" now_epoch="$2" dir
  dir="$(dirname "$marker_path")"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\n' "$now_epoch" > "$marker_path" 2>/dev/null || return 0
}
