#!/bin/bash
# tests/test-suite-registration-complete.sh — registration-completeness gate
# (#1186).
#
# THE GAP: tests/run-all.sh registers suites via literal
# `run_suite "<name>" "tests/<name>"` lines. A test file can land on disk,
# pass standalone, and yet NEVER be run by the suite or CI if no one adds its
# registration line. Six files (test-block-fix-issue-unclaimed-ownership.sh,
# test-do-multi-issue-fanout.sh, test-do-pr-claim-release.sh,
# test-hooks-helpers.sh, test-inflight-reentry-guard.sh,
# test-mark-plan-complete.sh) sat orphaned this way until #1186.
#
# THE GATE: enumerate every top-level tests/test-*.sh on disk and FAIL if any
# is neither referenced ANYWHERE in run-all.sh (a run_suite line, a sourced
# reference, OR a conditional/gated reference — we grep the basename, not only
# run_suite lines) NOR on the explicit in-file ALLOWLIST (each entry carries an
# inline `# reason:` so a deliberate exclusion is inspectable).
#
# Coverage is intentionally LENIENT on the "referenced" side (grep-the-basename
# anywhere) so a file sourced by a parent suite, or gated behind a `if
# RUN_X; then run_suite ...` block, counts as covered. It is STRICT on the
# allowlist side (every entry needs a reason). After #1186 registered the six
# orphans the allowlist is EMPTY — every on-disk test-*.sh is referenced.
#
# This suite does NOT execute run-all.sh — static grep only.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNALL="$REPO_ROOT/tests/run-all.sh"

PASS=0
FAIL=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# ── ALLOWLIST ─────────────────────────────────────────────────────────────
# Files that legitimately must NOT be registered in run-all.sh. Each entry is
# a basename followed by an inline `# reason: ...` comment. Keep EMPTY unless a
# file is a genuine standalone/manual artifact — never allowlist a real suite
# just to make the gate pass.
ALLOWLIST=(
  # (none — after #1186 every on-disk test-*.sh is referenced in run-all.sh)
)

# Strip an inline `# reason: ...` comment to recover the bare basename.
allowlist_basename() {
  # echo "$1" with everything from the first '#' removed, then trimmed.
  local raw="${1%%#*}"
  # trim leading/trailing whitespace
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  printf '%s' "$raw"
}

# is_allowlisted <basename> — true iff $1 matches an allowlist entry that ALSO
# carries a `# reason:` comment (a reason-less entry does NOT count).
is_allowlisted() {
  local target="$1" entry bn
  for entry in "${ALLOWLIST[@]}"; do
    case "$entry" in
      *"# reason:"*) ;;            # must carry a reason
      *) continue ;;
    esac
    bn="$(allowlist_basename "$entry")"
    [ "$bn" = "$target" ] && return 0
  done
  return 1
}

# is_referenced <basename> <runall-file> — true iff the basename appears
# ANYWHERE in the run-all.sh file (run_suite line, sourced ref, conditional
# ref). Fixed-string grep so dots in the name aren't regex-significant.
is_referenced() {
  local bn="$1" file="$2"
  grep -qF "$bn" "$file"
}

# core_uncovered <runall-file> <test-file...> — echo (one per line) each
# supplied test file basename that is NEITHER referenced in the run-all file
# NOR allowlisted. This is the reusable gate kernel exercised by BOTH the real
# run (below) and the negative-path self-test.
core_uncovered() {
  local file="$1"; shift
  local path bn
  for path in "$@"; do
    bn="$(basename "$path")"
    if is_referenced "$bn" "$file"; then
      continue
    fi
    if is_allowlisted "$bn"; then
      continue
    fi
    printf '%s\n' "$bn"
  done
}

# ── 1. REAL RUN — every on-disk tests/test-*.sh must be covered ───────────
# Top-level only: a plain glob of tests/test-*.sh never descends into
# tests/lib, tests/manual, tests/fixtures, tests/e2e.
shopt -s nullglob
ON_DISK=( "$REPO_ROOT"/tests/test-*.sh )
shopt -u nullglob

if [ "${#ON_DISK[@]}" -eq 0 ]; then
  fail "[enumerate] on-disk tests" "found ZERO tests/test-*.sh — glob likely broke"
else
  pass "[enumerate] found ${#ON_DISK[@]} top-level tests/test-*.sh on disk"
fi

UNCOVERED="$(core_uncovered "$RUNALL" "${ON_DISK[@]}")"
if [ -z "$UNCOVERED" ]; then
  pass "[coverage] every on-disk tests/test-*.sh is referenced in run-all.sh (or allowlisted)"
else
  COUNT_UNCOVERED="$(printf '%s\n' "$UNCOVERED" | grep -c .)"
  # List each offender on its own line so the failure is actionable.
  while IFS= read -r off; do
    [ -n "$off" ] && fail "[coverage] UNREGISTERED" "tests/$off is on disk but NOT referenced in run-all.sh and NOT allowlisted — add a run_suite line"
  done <<< "$UNCOVERED"
  fail "[coverage] summary" "$COUNT_UNCOVERED on-disk test file(s) are neither registered nor allowlisted"
fi

# ── 2. NEGATIVE-PATH SELF-TEST — prove the gate actually FAILS on an orphan ─
# Create a real temp probe file under tests/ that is guaranteed NOT referenced
# in run-all.sh, run the gate kernel against it, and assert it is reported as
# uncovered. A trap removes the probe even if an assertion below aborts, so it
# is never left in the tree.
PROBE="$REPO_ROOT/tests/test-__gate_probe_DELETEME.sh"
cleanup_probe() { rm -f "$PROBE"; }
trap cleanup_probe EXIT INT TERM
printf '#!/bin/bash\n# synthetic orphan probe for #1186 gate negative-path test\nexit 0\n' > "$PROBE"

# Sanity: the probe basename must NOT already appear in run-all.sh.
if is_referenced "$(basename "$PROBE")" "$RUNALL"; then
  fail "[negative] probe is unreferenced" "probe basename unexpectedly found in run-all.sh"
else
  PROBE_RESULT="$(core_uncovered "$RUNALL" "$PROBE")"
  if [ "$PROBE_RESULT" = "$(basename "$PROBE")" ]; then
    pass "[negative] gate reports a synthetic unregistered probe as uncovered"
  else
    fail "[negative] gate detects orphan" "expected '$(basename "$PROBE")' uncovered, got: '$PROBE_RESULT'"
  fi
fi

# And the inverse: were the probe referenced (simulate via a temp runall copy
# that DOES reference it), the gate must report it as COVERED.
TMP_RUNALL="$(mktemp)"
cp "$RUNALL" "$TMP_RUNALL"
printf 'run_suite "%s" "tests/%s"\n' "$(basename "$PROBE")" "$(basename "$PROBE")" >> "$TMP_RUNALL"
PROBE_COVERED="$(core_uncovered "$TMP_RUNALL" "$PROBE")"
rm -f "$TMP_RUNALL"
if [ -z "$PROBE_COVERED" ]; then
  pass "[negative] gate reports the probe as COVERED once a run_suite line references it"
else
  fail "[negative] referenced probe covered" "expected probe covered, still uncovered: '$PROBE_COVERED'"
fi

cleanup_probe
trap - EXIT INT TERM

# ── 3. ALLOWLIST hygiene — every entry must carry a reason ────────────────
ALLOWLIST_OK=1
for entry in "${ALLOWLIST[@]}"; do
  case "$entry" in
    *"# reason:"*) ;;
    *) ALLOWLIST_OK=0; fail "[allowlist] reasonless entry" "allowlist entry lacks an inline '# reason:' comment: '$entry'" ;;
  esac
done
if [ "$ALLOWLIST_OK" -eq 1 ]; then
  pass "[allowlist] every allowlist entry (if any) carries an inline '# reason:'"
fi

echo ""
echo "---"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 1
fi
