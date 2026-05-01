#!/bin/bash
# mock-git.sh — minimal stateful mock for `git`.
#
# Owner: tests/test-land-pr-scripts.sh (WI 1B.2 of PR_LANDING_UNIFICATION).
#
# Pattern parallels mock-gh.sh:
#   $MOCK_GIT_STATE_DIR (default /tmp/mock-git-state-$$)
#   $MOCK_GIT_STATE_DIR/<key>.count            — per-call counter
#   $MOCK_GIT_STATE_DIR/<key>.<N>.stdout       — canned stdout
#   $MOCK_GIT_STATE_DIR/<key>.<N>.stderr       — canned stderr
#   $MOCK_GIT_STATE_DIR/<key>.<N>.exit         — exit code
#
# <key> derivation: first arg, plus the second if it's a subcommand
# (no leading dash). E.g. `git rev-parse --is-inside-work-tree` →
# key `rev-parse`; `git rebase --abort` → key `rebase`; `git push -u
# origin foo` → key `push`. We deliberately strip flags so that all
# `git rebase` invocations share one counter — finer-grained
# discrimination (e.g. distinguishing `git rebase X` from `git rebase
# --abort`) is the test's responsibility via per-call canned files
# (response 1 vs response 2).
#
# CONCURRENCY: same caveat as mock-gh — sequential test calls only.
#
# OPTIONAL "real-git" passthrough: if $MOCK_GIT_PASSTHROUGH=1 is set,
# we call the real `git` for the current invocation. Useful for tests
# that want to mock SOME subcommands and run others against a real
# fixture repo. Per-test you can selectively enable this by setting
# $MOCK_GIT_PASSTHROUGH BEFORE the call you want passed through, then
# unsetting it after.

set -u

STATE_DIR="${MOCK_GIT_STATE_DIR:-/tmp/mock-git-state-$$}"
mkdir -p "$STATE_DIR"

if [ "${MOCK_GIT_PASSTHROUGH:-0}" = "1" ]; then
  # Find the real git via the system PATH minus our mocks dir. The
  # caller arranged for this script to be earlier in PATH; for
  # passthrough we shell out to a path-resolved real git.
  REAL_GIT=""
  for candidate in /usr/bin/git /usr/local/bin/git /bin/git; do
    if [ -x "$candidate" ]; then REAL_GIT="$candidate"; break; fi
  done
  if [ -z "$REAL_GIT" ]; then
    echo "mock-git: passthrough requested but no real git found" >&2
    exit 127
  fi
  exec "$REAL_GIT" "$@"
fi

ARG1="${1:-}"
ARG2="${2:-}"
if [ -z "$ARG1" ]; then
  echo "mock-git: invoked with no arguments" >&2
  exit 99
fi

case "$ARG1" in
  --*|-*) KEY="${ARG1#--}"; KEY="${KEY#-}" ;;
  *) KEY="$ARG1" ;;
esac

# Special-case: `git diff` with `--name-only --diff-filter=U` is the
# conflict-file enumeration call. We give it its own key so tests can
# distinguish it from generic `git diff` calls.
if [ "$ARG1" = "diff" ]; then
  for arg in "$@"; do
    if [ "$arg" = "--diff-filter=U" ]; then
      KEY="diff_unmerged"
      break
    fi
  done
fi

# Special-case: `git rebase --abort` vs `git rebase X`. The abort path
# is the failure-mode #2 trigger; tests want to count aborts separately.
if [ "$ARG1" = "rebase" ] && [ "$ARG2" = "--abort" ]; then
  KEY="rebase_abort"
fi

COUNT_FILE="$STATE_DIR/$KEY.count"
PREV_COUNT=0
if [ -f "$COUNT_FILE" ]; then
  PREV_COUNT=$(cat "$COUNT_FILE")
fi
COUNT=$((PREV_COUNT + 1))
printf '%s' "$COUNT" > "$COUNT_FILE"

INVOCATION_LOG="$STATE_DIR/_invocations.log"
printf '%s\n' "$KEY $*" >> "$INVOCATION_LOG"

STDOUT_FILE="$STATE_DIR/$KEY.$COUNT.stdout"
STDERR_FILE="$STATE_DIR/$KEY.$COUNT.stderr"
EXIT_FILE="$STATE_DIR/$KEY.$COUNT.exit"

if [ ! -f "$STDOUT_FILE" ] && [ ! -f "$STDERR_FILE" ] && [ ! -f "$EXIT_FILE" ]; then
  echo "mock-git: no canned response prepared for key='$KEY' call #$COUNT (args: $*)" >&2
  echo "mock-git: STATE_DIR=$STATE_DIR" >&2
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
