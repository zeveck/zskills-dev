#!/usr/bin/env bash
# verify-response-validate.sh — validates a verifier subagent's response
# for signs of skipped work, hung-and-recovered, or other failure patterns.
#
# Layer 3 of the VERIFIER_AGENT_FIX D'' architecture. Universal failure-
# protocol primitive applied at all 5 verifier-dispatch sites (/run-plan,
# /commit, /fix-issues, /do, /verify-changes).
#
# Reads the verifier's response text on stdin. Exit 0 = PASS. Exit 1 =
# FAIL with a one-line reason on stderr naming the matched pattern (or
# the threshold violated).
#
# Pattern arrays are designed for easy extension — append a new array
# (e.g., PATTERNS_BACKEND_ERROR) and a new check block, no call-site
# changes needed.
#
# Pure bash. No JSON construction (just stdin pattern matching).

set -u

INPUT=$(cat)
INPUT_LEN="${#INPUT}"
MIN_BYTES=200

# Stalled-string patterns (case-insensitive substring match, anchored to
# the LAST 10 LINES of the response — NOT anywhere). The last-10-lines
# anchor prevents contamination from the verifier quoting documentation
# or earlier prose that happens to mention the trigger phrase.
PATTERNS_STALLED=(
  "let me wait for the monitor"
  "tests are running. let me wait"
  "monitor will signal"
  "monitor to signal"
  "still searching. let me wait"
  "waiting on bashoutput"
  "polling bashoutput"
)

# Future extension example (kept commented as documentation):
#   PATTERNS_BACKEND_ERROR=(
#     "rate limit exceeded"
#     "anthropic backend error"
#     "internal server error"
#   )
# Then add a second loop after the stalled check.

# Min-byte threshold check. A real verification report is at minimum a
# sentence or two of explanation, well over 200 bytes. Shorter responses
# are either empty (agent ended its turn before producing meaningful
# output) or stubs that do not constitute attestation.
if [ "$INPUT_LEN" -lt "$MIN_BYTES" ]; then
  echo "FAIL: verifier response too short (${INPUT_LEN} bytes < ${MIN_BYTES} threshold) — empty or stub" >&2
  exit 1
fi

# Stalled-string check: lowercase the last 10 lines and substring-match
# each pattern. The last-N anchor is load-bearing (prevents false-positive
# on verifier prose that quotes the warning text from PR #148 or this plan).
LAST_LINES=$(printf '%s' "$INPUT" | tail -n 10 | tr '[:upper:]' '[:lower:]')
for pattern in "${PATTERNS_STALLED[@]}"; do
  if [[ "$LAST_LINES" == *"$pattern"* ]]; then
    echo "FAIL: stalled-string pattern detected: '${pattern}' in last 10 lines of verifier response" >&2
    exit 1
  fi
done

exit 0
