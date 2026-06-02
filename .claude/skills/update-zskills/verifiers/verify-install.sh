#!/usr/bin/env bash
# verify-install.sh — thin entry for the consumer post-install verifier.
#
# Issue #999. Detects the install lane and runs the CHEAP structural tier of
# checks (fast file/config checks — no live `claude`), printing explicit
# per-check PASS/WARN/FAIL lines and an overall result. Auto-run by
# /update-zskills at the end of a successful install/update (NON-FATAL: a
# FAIL here is reported but does not undo the install — verification is
# informative).
#
# Usage:
#   verify-install.sh [--project-dir <dir>] [--deep]
#
#   --project-dir <dir>   Consumer project root to verify. Defaults to
#                         $CLAUDE_PROJECT_DIR, else the current directory.
#   --deep                ALSO run the heavy live-probe tier (opt-in only —
#                         NEVER passed on the /update-zskills success path).
#
# Exit codes:
#   0  no FAILs (all PASS, possibly with WARNs)
#   1  at least one FAIL
#   2  usage error
#
# The library (verify-install-lib.sh) holds the assertion logic and is the
# single source of truth; this entry only parses args, sources the lib, and
# renders. It ships alongside the lib on both lanes
# (.claude/skills/update-zskills/verifiers/ legacy,
# ${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/verifiers/ plugin).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verify-install-lib.sh
. "$SCRIPT_DIR/verify-install-lib.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
RUN_DEEP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      PROJECT_DIR="${2:-}"
      [ -n "$PROJECT_DIR" ] || { echo "ERROR: --project-dir requires a value" >&2; exit 2; }
      shift 2
      ;;
    --deep)
      RUN_DEEP=1
      shift
      ;;
    -h|--help)
      sed -n '2,30p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ ! -d "$PROJECT_DIR" ]; then
  echo "ERROR: project dir not found: $PROJECT_DIR" >&2
  exit 2
fi

echo "zskills install verification — project: $PROJECT_DIR"
echo "------------------------------------------------------------"

# vi_emit increments VI_PASS/WARN/FAIL, but vi_run_cheap runs inside a process
# substitution (a subshell), so those counters do NOT propagate back here.
# Re-tally from the rendered record stream in THIS shell so the Result line and
# exit code reflect reality.
P_PASS=0; P_WARN=0; P_FAIL=0

render_stream() {
  # $1 = records-producing function; remaining args = its args.
  local fn="$1"; shift
  while IFS=$'\t' read -r status id detail; do
    [ -n "$status" ] || continue
    case "$status" in
      PASS) P_PASS=$((P_PASS + 1)); marker="PASS" ;;
      WARN) P_WARN=$((P_WARN + 1)); marker="WARN" ;;
      FAIL) P_FAIL=$((P_FAIL + 1)); marker="FAIL" ;;
      *)    marker="????" ;;
    esac
    printf '  %-4s  %-32s %s\n' "$marker" "$id" "$detail"
  done < <("$fn" "$@")
}

vi_reset
# Run the cheap tier and render each record as it arrives.
render_stream vi_run_cheap "$PROJECT_DIR"

if [ "$RUN_DEEP" -eq 1 ]; then
  echo "--- heavy tier (--deep, opt-in) ---"
  render_stream vi_run_heavy "$PROJECT_DIR"
fi

echo "------------------------------------------------------------"
printf 'Result: %d PASS, %d WARN, %d FAIL\n' "$P_PASS" "$P_WARN" "$P_FAIL"

if [ "$P_FAIL" -gt 0 ]; then
  echo "Overall: FAIL"
  exit 1
elif [ "$P_WARN" -gt 0 ]; then
  echo "Overall: PASS (with warnings)"
  exit 0
else
  echo "Overall: PASS"
  exit 0
fi
