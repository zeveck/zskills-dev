#!/bin/bash
# pr-push-and-create.sh — Push the branch and create-or-detect a PR.
#
# Owner: /land-pr (skills/land-pr).
# Spec:  plans/PR_LANDING_UNIFICATION.md WI 1.4.
#
# Behavior:
#   1. Detect existing PR via `gh pr list --head <branch> --base <base> --json`.
#      Parse with bash regex (no jq binary).
#   2. Push (-u origin <branch>; or `git push` if upstream is set).
#   3. If a PR already exists: emit PR_EXISTING=true and the URL/number,
#      exit 0. Body update is the CALLER's responsibility, not /land-pr's
#      (HTML-comment-marker splice preservation).
#   4. Otherwise: `gh pr create` with --base/--head/--title/--body-file.
#      Race with parallel /land-pr: gh enforces one open PR per head.
#      Loser exits 13.
#   5. Extract PR_NUMBER via `${URL##*/}` (per fix 175e4aa). Validate
#      digits-only via bash regex.
#
# Args (all required):
#   --branch    <name>
#   --base      <name>
#   --title     <title>
#   --body-file <path>
#
# Stdout: PR_EXISTING=<bool> PR_URL=<url> PR_NUMBER=<num> CALL_ERROR_FILE=<path-on-failure>
# Stderr: human-readable error text.
#
# Exits:
#   0  — push + create-or-detect succeeded
#   12 — git push failed
#   13 — gh pr create failed (CALL_ERROR_FILE points to captured stderr)
#   14 — created PR URL did not yield a numeric PR number
#   2  — usage error

set -u

BRANCH=""
BASE=""
TITLE=""
BODY_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --branch)    shift; BRANCH="${1:-}" ;;
    --base)      shift; BASE="${1:-}" ;;
    --title)     shift; TITLE="${1:-}" ;;
    --body-file) shift; BODY_FILE="${1:-}" ;;
    *) echo "ERROR: pr-push-and-create.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift || true
done

for v in BRANCH BASE TITLE BODY_FILE; do
  if [ -z "${!v}" ]; then
    echo "ERROR: pr-push-and-create.sh: --${v,,} is required" >&2
    exit 2
  fi
done

if [ ! -f "$BODY_FILE" ]; then
  echo "ERROR: pr-push-and-create.sh: body-file not found: $BODY_FILE" >&2
  exit 2
fi

# Branch names commonly contain `/` — sanitize for sidecar filenames.
BRANCH_SLUG="${BRANCH//\//-}"
STDERR_LOG="/tmp/land-pr-push-create-stderr-$BRANCH_SLUG-$$.log"

# Step 1 — Detect existing PR via bash regex on `gh pr list --json`.
PR_LIST_JSON=""
if ! PR_LIST_JSON=$(gh pr list --head "$BRANCH" --base "$BASE" --json number,url 2>"$STDERR_LOG"); then
  ERR_FILE="/tmp/land-pr-pr-list-error-$BRANCH_SLUG-$$.txt"
  cp "$STDERR_LOG" "$ERR_FILE"
  echo "ERROR: pr-push-and-create.sh: gh pr list failed — see $ERR_FILE" >&2
  cat "$STDERR_LOG" >&2
  echo "CALL_ERROR_FILE=$ERR_FILE"
  exit 13
fi

PR_EXISTING=false
PR_NUMBER=""
PR_URL=""

# Bash regex on JSON. First match wins; warn if multiple PRs are open from
# the same head branch (force-push artifact).
if [[ "$PR_LIST_JSON" =~ \"number\":[[:space:]]*([0-9]+) ]]; then
  PR_NUMBER="${BASH_REMATCH[1]}"
  if [[ "$PR_LIST_JSON" =~ \"url\":[[:space:]]*\"([^\"]+)\" ]]; then
    PR_URL="${BASH_REMATCH[1]}"
  fi
  PR_EXISTING=true

  # Detect multiple-PR situation: count occurrences of "number":.
  NUMBER_COUNT=$(grep -o '"number":' <<<"$PR_LIST_JSON" | wc -l)
  if [ "$NUMBER_COUNT" -gt 1 ]; then
    echo "WARN: pr-push-and-create.sh: $NUMBER_COUNT open PRs from branch '$BRANCH' — using first match (PR #$PR_NUMBER)" >&2
  fi
fi

# Step 2 — Push the branch. Use -u origin if no upstream is configured;
# otherwise plain `git push` (preserves any user-configured remote name).
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>"$STDERR_LOG"; then
  if ! git push >"$STDERR_LOG" 2>&1; then
    ERR_FILE="/tmp/land-pr-push-error-$BRANCH_SLUG-$$.txt"
    cp "$STDERR_LOG" "$ERR_FILE"
    echo "ERROR: pr-push-and-create.sh: git push failed — see $ERR_FILE" >&2
    cat "$STDERR_LOG" >&2
    echo "CALL_ERROR_FILE=$ERR_FILE"
    exit 12
  fi
else
  if ! git push -u origin "$BRANCH" >"$STDERR_LOG" 2>&1; then
    ERR_FILE="/tmp/land-pr-push-error-$BRANCH_SLUG-$$.txt"
    cp "$STDERR_LOG" "$ERR_FILE"
    echo "ERROR: pr-push-and-create.sh: git push -u origin $BRANCH failed — see $ERR_FILE" >&2
    cat "$STDERR_LOG" >&2
    echo "CALL_ERROR_FILE=$ERR_FILE"
    exit 12
  fi
fi

# Step 3 — Existing PR detected? Emit and exit. Caller owns body update.
if [ "$PR_EXISTING" = "true" ]; then
  echo "PR_EXISTING=true"
  echo "PR_URL=$PR_URL"
  echo "PR_NUMBER=$PR_NUMBER"
  exit 0
fi

# Step 4 — No existing PR. Create one. Race-condition note: if a parallel
# /land-pr just created a PR, gh rejects with "already exists" and we exit 13.
CREATE_OUT=""
if ! CREATE_OUT=$(gh pr create --base "$BASE" --head "$BRANCH" --title "$TITLE" --body-file "$BODY_FILE" 2>"$STDERR_LOG"); then
  ERR_FILE="/tmp/land-pr-create-error-$BRANCH_SLUG-$$.txt"
  cp "$STDERR_LOG" "$ERR_FILE"
  echo "ERROR: pr-push-and-create.sh: gh pr create failed — see $ERR_FILE" >&2
  cat "$STDERR_LOG" >&2
  echo "CALL_ERROR_FILE=$ERR_FILE"
  exit 13
fi

# `gh pr create` prints the new PR URL on its last line (typically the only
# output line). Extract the last line and validate it looks like a URL.
PR_URL=$(printf '%s\n' "$CREATE_OUT" | tail -n 1)

if [ -z "$PR_URL" ]; then
  echo "ERROR: pr-push-and-create.sh: gh pr create produced no URL on stdout" >&2
  exit 14
fi

# Step 5 — Extract PR_NUMBER via parameter expansion (per fix 175e4aa —
# never via second `gh pr view` call). Validate digits-only.
PR_NUMBER="${PR_URL##*/}"
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: pr-push-and-create.sh: extracted PR_NUMBER='$PR_NUMBER' from URL '$PR_URL' is not numeric" >&2
  exit 14
fi

# Step 6 — Emit and exit.
echo "PR_EXISTING=false"
echo "PR_URL=$PR_URL"
echo "PR_NUMBER=$PR_NUMBER"
exit 0
