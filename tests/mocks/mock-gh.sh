#!/bin/bash
# mock-gh.sh — minimal stateful mock for the `gh` CLI.
#
# Owner: tests/test-land-pr-scripts.sh (WI 1B.2 of PR_LANDING_UNIFICATION).
#
# State directory:  $MOCK_GH_STATE_DIR (default /tmp/mock-gh-state-$$)
# Per-call counter: $MOCK_GH_STATE_DIR/<key>.count
# Per-call canned response files (read on call N, where N is the counter
# AFTER the increment):
#   $MOCK_GH_STATE_DIR/<key>.<N>.stdout   (printed to stdout if present)
#   $MOCK_GH_STATE_DIR/<key>.<N>.stderr   (printed to stderr if present)
#   $MOCK_GH_STATE_DIR/<key>.<N>.exit     (exit code if present, else 0)
#
# <key> is the first two args joined by `_` (e.g. `pr_list`, `pr_create`,
# `auth_status`, `run_view`). For single-arg subcommands (e.g.
# `gh --version`) the key collapses to the first arg only.
#
# FAIL-FAST design: if the script-under-test calls a subcommand more
# times than the test prepared canned responses for, we exit 99 with a
# loud stderr message (not exit 0 with empty stdout — that would
# silently produce false test confidence).
#
# CONCURRENCY: the per-call counter file is NOT locked. All tests using
# this mock MUST invoke `gh` sequentially within a single test process.

set -u

STATE_DIR="${MOCK_GH_STATE_DIR:-/tmp/mock-gh-state-$$}"
mkdir -p "$STATE_DIR"

# Build the key from the first 1-2 args (subcommand + sub-subcommand).
# Drop flags from the key so e.g. `gh pr list --head x` and `gh pr list
# --base y` share the same counter.
ARG1="${1:-}"
ARG2="${2:-}"
if [ -z "$ARG1" ]; then
  echo "mock-gh: invoked with no arguments" >&2
  exit 99
fi

# Strip leading dashes — `gh --version` becomes key `version`.
case "$ARG1" in
  --*|-*) KEY="${ARG1#--}"; KEY="${KEY#-}" ;;
  *)
    if [ -n "$ARG2" ] && [[ "$ARG2" != -* ]]; then
      KEY="${ARG1}_${ARG2}"
    else
      KEY="$ARG1"
    fi
    ;;
esac

COUNT_FILE="$STATE_DIR/$KEY.count"
PREV_COUNT=0
if [ -f "$COUNT_FILE" ]; then
  PREV_COUNT=$(cat "$COUNT_FILE")
fi
COUNT=$((PREV_COUNT + 1))
printf '%s' "$COUNT" > "$COUNT_FILE"

# Also keep a flat invocation log for tests that want to assert on the
# full sequence of calls (e.g. "was `gh pr edit` called at all?").
INVOCATION_LOG="$STATE_DIR/_invocations.log"
printf '%s\n' "$KEY $*" >> "$INVOCATION_LOG"

STDOUT_FILE="$STATE_DIR/$KEY.$COUNT.stdout"
STDERR_FILE="$STATE_DIR/$KEY.$COUNT.stderr"
EXIT_FILE="$STATE_DIR/$KEY.$COUNT.exit"

if [ ! -f "$STDOUT_FILE" ] && [ ! -f "$STDERR_FILE" ] && [ ! -f "$EXIT_FILE" ]; then
  echo "mock-gh: no canned response prepared for key='$KEY' call #$COUNT (args: $*)" >&2
  echo "mock-gh: STATE_DIR=$STATE_DIR" >&2
  exit 99
fi

if [ -f "$STDOUT_FILE" ]; then
  cat "$STDOUT_FILE"
fi
if [ -f "$STDERR_FILE" ]; then
  cat "$STDERR_FILE" >&2
fi
if [ -f "$EXIT_FILE" ]; then
  exit "$(cat "$EXIT_FILE")"
fi
exit 0
