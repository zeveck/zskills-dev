# tests/lib/suite-result-valid.sh — provenance-result validator for a
# tests/run-all.sh output file (SUITE_PROVENANCE Phase 1, #1166).
#
# SOURCEABLE LIBRARY, NOT A SUITE. Do NOT register in run-all.sh as a
# `run_suite`. `tests/test-suite-result-valid.sh` is the registered self-test
# that exercises this function.
#
# Answers ONLY "is this result still TRUE for the current tree?" — NOT "did it
# pass?". The pass signal (every suite passed) is the bottom
# `Overall: N/M passed, F failed` line, checked SEPARATELY by the verifier; a
# result can be VALID (right tree, fresh) and FAILING. Keep the two concerns
# distinct.
#
# suite_result_valid <file>
#   exit 0 (valid) IFF ALL clauses hold; exit 1 otherwise:
#     0. Fields present + non-empty (fail closed). <file> exists, its first
#        non-blank line is `zskills-suite-provenance: v1`, and it carries
#        NON-EMPTY tree=/fingerprint=/timestamp=/epoch= header lines. Empty is
#        MALFORMED, not a wildcard — checked BEFORE any live comparison so an
#        empty recorded value can never `""==""`-match an empty live value when
#        git is unavailable.
#     1. git available + HEAD resolvable. `git -C "$REPO_ROOT" rev-parse HEAD`
#        succeeds (non-empty, exit 0). Absent git / not a repo / unborn HEAD →
#        exit 1 (cannot prove "same tree").
#     2. tree + fingerprint match the CURRENT tree. Recorded `tree` == live
#        HEAD AND recorded `fingerprint` == the live content-sensitive
#        fingerprint (the EXACT formula run-all.sh emits — same `git diff HEAD`
#        + untracked roll-up).
#     3. Age < 30 minutes. (now_epoch - recorded_epoch) < 1800, where
#        now_epoch=$(date -u +%s) and recorded_epoch is read DIRECTLY from the
#        header (a plain integer — NO ISO re-parse, portable across GNU/BSD
#        date). A negative/future delta → invalid (defensive).
#
# Pure bash + git/date math — NO jq, NO Python (the fields are simple
# grep-able lines).
#
# REPO_ROOT: if the caller has already exported it (run-all.sh does), it is
# used; otherwise self-locate from this lib's path. zsh leaves
# ${BASH_SOURCE[0]} unset, so fall back to $0 (#1149 idiom). All live git
# calls use `git -C "$REPO_ROOT" …` — the validator must NOT assume the
# caller's cwd is the repo root.
if [ -z "${REPO_ROOT:-}" ]; then
  _srv_self="${BASH_SOURCE[0]:-$0}"
  _srv_dir="$(cd "$(dirname "$_srv_self")" && pwd)"
  REPO_ROOT="$(cd "$_srv_dir/../.." && pwd)"
fi

# Recompute the live content-sensitive fingerprint. MUST be byte-identical to
# the formula tests/run-all.sh emits (any divergence makes a freshly-captured
# header fail its own validator).
_suite_result_live_fingerprint() {
  {
    git -C "$REPO_ROOT" rev-parse HEAD
    git -C "$REPO_ROOT" diff HEAD
    git -C "$REPO_ROOT" ls-files --others --exclude-standard -z \
      | while IFS= read -r -d '' f; do
          printf '%s\0' "$f"
          git -C "$REPO_ROOT" hash-object "$REPO_ROOT/$f"
        done
  } 2>/dev/null | git -C "$REPO_ROOT" hash-object --stdin 2>/dev/null
}

# Extract a `key=value` header field's VALUE from the first ~10 lines.
# Echoes the raw value (may be empty). Returns the value verbatim after the
# first `=`.
_suite_result_field() {
  local file="$1" key="$2"
  head -n 10 "$file" | grep -m1 -E "^${key}=" | sed -E "s/^${key}=//"
}

suite_result_valid() {
  local file="$1"

  # ── Clause 0: file exists, marker present, fields present + non-empty ──────
  [ -n "$file" ] || return 1
  [ -f "$file" ] || return 1

  # First NON-BLANK line must be the format-version marker.
  local first_nonblank
  first_nonblank="$(grep -m1 -E '[^[:space:]]' "$file")"
  [ "$first_nonblank" = "zskills-suite-provenance: v1" ] || return 1

  local rec_tree rec_fp rec_ts rec_epoch
  rec_tree="$(_suite_result_field "$file" tree)"
  rec_fp="$(_suite_result_field "$file" fingerprint)"
  rec_ts="$(_suite_result_field "$file" timestamp)"
  rec_epoch="$(_suite_result_field "$file" epoch)"

  # Missing OR empty field → malformed → fail closed (BEFORE any live compare).
  [ -n "$rec_tree" ]  || return 1
  [ -n "$rec_fp" ]    || return 1
  [ -n "$rec_ts" ]    || return 1
  [ -n "$rec_epoch" ] || return 1

  # epoch must be a plain integer (a non-integer would break clause 3 math).
  case "$rec_epoch" in
    ''|*[!0-9]*) return 1 ;;
  esac

  # ── Clause 1: git available + HEAD resolvable ─────────────────────────────
  local live_tree
  live_tree="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)" || return 1
  [ -n "$live_tree" ] || return 1

  # ── Clause 2: tree + fingerprint match the CURRENT tree ───────────────────
  [ "$rec_tree" = "$live_tree" ] || return 1
  local live_fp
  live_fp="$(_suite_result_live_fingerprint)"
  [ -n "$live_fp" ] || return 1
  [ "$rec_fp" = "$live_fp" ] || return 1

  # ── Clause 3: age < 30 minutes (epoch integer subtraction; defensive on
  # negative/future delta) ──────────────────────────────────────────────────
  local now_epoch delta
  now_epoch="$(date -u +%s)"
  delta=$(( now_epoch - rec_epoch ))
  [ "$delta" -ge 0 ] || return 1      # future/negative → invalid (defensive)
  [ "$delta" -lt 1800 ] || return 1   # >= 30 min → stale

  return 0
}

# Runnable directly: `bash tests/lib/suite-result-valid.sh <file>` → exit 0/1.
# (The self-test invokes it both ways; when sourced, only the function is
# defined.) Guard on BASH_SOURCE vs $0 so a `bash <lib> <file>` invocation
# runs the predicate while a `. <lib>` source does not.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  suite_result_valid "$1"
  exit $?
fi
