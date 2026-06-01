# tests/lib/extract-fence.sh — shared fence-extraction primitives for the
# extract-and-run test idiom (SEAM_HARDENING_HIGH Phase 1).
#
# SOURCEABLE LIBRARY, NOT A SUITE. Do NOT register in run-all.sh as a
# `run_suite`. `tests/test-extract-fence-lib.sh` is the registered self-test
# that exercises these functions.
#
# These primitives let a test extract the REAL fenced bash block from a
# production SKILL.md and run it (extract-and-run), instead of carrying a
# re-implemented copy that silently drifts. Two extractors are provided:
#
#   extract_fence_between <file> <start-regex> <end-regex> [fence-index] [strip-indent]
#       awk-extract the Nth ```bash block whose opening fence falls BETWEEN
#       a line matching <start-regex> and a line matching <end-regex>.
#
#   extract_sentinel_block <file> <begin-regex> <end-regex>
#       Extract a slice bounded by inline comment sentinels that live INSIDE
#       a single ```bash fence (e.g. `# === BEGIN CANONICAL ... ===` /
#       `# === END ===`). Fence-index extraction would grab the whole fence
#       including pre-BEGIN lines; this slices exactly BEGIN..END (exclusive
#       of the sentinel lines themselves).
#
# ─────────────────────────────────────────────────────────────────────
# PUBLIC CONTRACT — FROZEN.
#   The function NAMES and SIGNATURES of `extract_fence_between` and
#   `extract_sentinel_block` are a frozen public contract. The sibling plan
#   SEAM_HARDENING_REST hard-depends on them. Do NOT rename or change their
#   argument order/meaning. (Adding NEW helpers here is fine.)
# ─────────────────────────────────────────────────────────────────────
#
# FRAGILITY NOTE (review M1) — fence-index + mixed indent.
#   `fence-index` counts ```bash openers in document order between the two
#   landmarks. When a section MIXES 3-space-indented fences (nested under a
#   list item) and column-0 fences, ordinal counting is error-prone: an
#   editor re-ordering or inserting a fence silently shifts the index and the
#   wrong block extracts (still "valid bash", so failures are subtle).
#   PREFER tight start/end regexes that bracket exactly one fence over relying
#   on `fence-index`. Use the index only when two near-identical fences sit
#   between the same pair of landmarks and no tighter anchor exists.
#
# INDENT NOTE — `strip-indent` (default 0).
#   commit/SKILL.md and draft-plan/SKILL.md carry 3-space-indented fences
#   (fences nested inside a markdown list). Their body lines are prefixed with
#   3 spaces. Pass strip-indent=1 to remove a single leading 3-space run from
#   each body line (`sub(/^   /, "")`) so the extracted bash is column-0 and
#   runnable. Column-0 fences need strip-indent=0 (the default).

# extract_fence_between <file> <start-regex> <end-regex> [fence-index] [strip-indent]
#   Prints the body (between the ```bash opener and the closing ```) of the
#   <fence-index>th ```bash block whose OPENER line appears at-or-after the
#   first line matching <start-regex> and strictly BEFORE the first line
#   matching <end-regex> that follows it. fence-index defaults to 1 (1-based).
#   strip-indent defaults to 0. Returns non-zero if no matching fence found.
extract_fence_between() {
  local file="$1" start_re="$2" end_re="$3"
  local fence_index="${4:-1}" strip_indent="${5:-0}"

  awk -v start_re="$start_re" -v end_re="$end_re" \
      -v want="$fence_index" -v strip="$strip_indent" '
    BEGIN { in_window = 0; seen = 0; in_fence = 0; emitted = 0 }
    # Enter the window at the start landmark.
    in_window == 0 && $0 ~ start_re { in_window = 1; next }
    # Leave the window at the end landmark (only once inside).
    in_window == 1 && in_fence == 0 && $0 ~ end_re { in_window = 0 }
    in_window == 1 {
      if (in_fence == 0) {
        # Match a ```bash fence opener, optionally indented.
        if ($0 ~ /^[[:space:]]*```bash[[:space:]]*$/) {
          seen++
          if (seen == want) { in_fence = 1; emitted = 1 }
          next
        }
      } else {
        # Inside the target fence: a closing ``` (optionally indented) ends it.
        if ($0 ~ /^[[:space:]]*```[[:space:]]*$/) { in_fence = 0; in_window = 0; next }
        line = $0
        if (strip == 1) { sub(/^   /, "", line) }
        print line
      }
    }
    END { if (emitted == 0) exit 3 }
  ' "$file"
}

# extract_sentinel_block <file> <begin-regex> <end-regex>
#   Prints the lines strictly BETWEEN the first line matching <begin-regex>
#   and the next line matching <end-regex>. The sentinel lines themselves are
#   NOT emitted. Indentation is preserved verbatim (sentinels live inside a
#   fence whose body is already at the indent the caller expects). Returns
#   non-zero if the begin sentinel is never seen.
extract_sentinel_block() {
  local file="$1" begin_re="$2" end_re="$3"

  awk -v begin_re="$begin_re" -v end_re="$end_re" '
    BEGIN { active = 0; emitted = 0 }
    active == 0 && $0 ~ begin_re { active = 1; emitted = 1; next }
    active == 1 && $0 ~ end_re { active = 0; next }
    active == 1 { print }
    END { if (emitted == 0) exit 3 }
  ' "$file"
}
