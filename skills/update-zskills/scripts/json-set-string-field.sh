#!/bin/bash
# json-set-string-field.sh <json-file> <key> <value>
# Updates a top-level string field in a JSON file in-place.
# Inserts the field if absent. No jq, no sed (awk is metacharacter-clean).
#
# v1 contract (Phase 5a.6, see plans/SKILL_VERSIONING.md):
#   * Top-level string fields only.
#   * Value MUST NOT contain `"` characters. The awk regex `[^"]*` stops at
#     the first inner quote; values containing `\"` (JSON-escaped) are not
#     supported. Out of scope per Non-Goals (refine-plan F-DA-R2-3).
#     `.claude/zskills-config.json`'s actual usage (a date+hash version
#     string) does not need them.
#   * Insert path requires the closing brace on its own line (matches
#     `apply-preset.sh:99-115`'s assumption). One-line `{}` is out of scope.
#
# Sibling rationale (Phase 5a.6 pre-condition): apply-preset.sh inlines its
# own awk for inserting an `execution` block and uses a generic `sed_inplace`
# for value updates — no reusable JSON-write helper to source. This file is
# the canonical helper going forward.
#
# Why awk (not sed): awk's match()/substr() is metacharacter-clean. sed's
# replacement side treats `&` as the matched-text backreference and `\N` as
# capture-group references; if `${VALUE}` contained either, sed would
# silently corrupt the output. (refine-plan F-DA-8.)
set -u
FILE="${1:?json-file required}"
KEY="${2:?key required}"
VALUE="${3:?value required}"

# v1 contract guard: reject values containing `"`. The awk replacement
# regex `[^"]*` cannot represent JSON-escaped quotes — passing one through
# would silently emit invalid JSON. Per Non-Goals (refine-plan F-DA-R2-3),
# embedded quotes are out of scope; surface as a non-zero exit so callers
# don't silently corrupt their config. (Phase 5a.7 Case 7b enforces.)
case "$VALUE" in
  *\"*)
    echo "json-set-string-field: value contains \" character; not supported in v1 (Non-Goals)." >&2
    exit 3
    ;;
esac

TMP="$(mktemp)"
# Preserve original file mode — `mktemp` defaults to 0600 which would lock
# other readers (e.g., the dashboard server) out of the JSON file. Match
# the original perms before mv. (refine-plan F-DA-8.)
# `chmod --reference` is GNU coreutils; BSD/macOS lacks it. Probe-and-fall
# back via `stat`. The probe pattern uses `2>/dev/null` defensibly (probe-
# then-detect-failure-via-exit-code), not to silence a fallible op whose
# success matters. (refine-plan F-R2-8.)
if ! chmod --reference="$FILE" "$TMP" 2>/dev/null; then
  perms=$(stat -c '%a' "$FILE" 2>/dev/null || stat -f '%Lp' "$FILE")
  chmod "$perms" "$TMP"
fi
if grep -q "\"$KEY\"" "$FILE"; then
  # Update existing field. awk uses match()/substr() (no gsub) so the
  # replacement value `v` is treated as a literal string — no metacharacter
  # expansion. Whatever follows the closing quote (trailing comma, newline,
  # `}`, etc.) is preserved byte-for-byte. (refine-plan F-R2-3 / F-DA-R2-2:
  # earlier awk arithmetic dropped the opening quote AND the trailing
  # comma on middle fields. The form below uses match() once on the full
  # `"key" : "..."` pattern and slices the line into pre/head/post.)
  #
  # Pass VALUE via ENVIRON, NOT `-v v=...`: awk's `-v` flag processes
  # backslash-escape sequences (so `\1` would become `\001` or be eaten
  # entirely depending on the awk implementation). ENVIRON is byte-clean.
  # (Plan-text drift from plan lines 1135 / 1172 caught by Phase 5a.7
  # Case 6 — the original `-v v="$VALUE"` form failed the round-trip.)
  k="$KEY" v="$VALUE" awk '
    BEGIN { k = ENVIRON["k"]; v = ENVIRON["v"] }
    {
      # Build the pattern: "<key>"<ws>:<ws>"<anything-without-quote>"
      # `[^"]*` is awk-regex (NOT shell glob); the inner pattern matches
      # the existing quoted value with NO embedded quotes. Embedded quotes
      # are out of scope for v1 (see Non-Goals; refine-plan F-DA-R2-3).
      pat = "\"" k "\"" "[[:space:]]*:[[:space:]]*\"[^\"]*\""
      if (match($0, pat)) {
        pre  = substr($0, 1, RSTART - 1)              # before "key"
        head = substr($0, RSTART, RLENGTH)            # "key": "old"
        post = substr($0, RSTART + RLENGTH)           # everything after closing "
        # Replace just the trailing quoted value inside `head`. Anchor to
        # end-of-string so we only touch the value, not the key. The
        # replacement uses sub() with v interpolated as a literal awk
        # string, so `&`/`\1`/etc. in v are NOT awk-regex metacharacters
        # in the REPLACEMENT side — but sub() DOES treat `&` and `\&` as
        # specials in the replacement. To stay metacharacter-clean,
        # construct the new head by string concatenation:
        if (match(head, /"[^"]*"$/)) {
          head_pre = substr(head, 1, RSTART - 1)      # "key": (trailing space then opening ")
          # head_pre ends just before the OPENING quote of the value.
          new_head = head_pre "\"" v "\""
          print pre new_head post
          next
        }
      }
      print
    }
  ' "$FILE" > "$TMP"
else
  # Insert before the outer closing brace, comma-aware (matches
  # apply-preset.sh:99-115). For an empty object `{ }` the inserted
  # field is the only entry — no leading comma needed AND no trailing
  # comma. For a non-empty object, the previous last field needs a
  # trailing comma added (if absent), and the inserted field gets
  # NO trailing comma. (refine-plan F-R2-6: the prior insert path
  # always wrote a trailing comma → invalid JSON.)
  k="$KEY" v="$VALUE" awk '
    BEGIN { k = ENVIRON["k"]; v = ENVIRON["v"] }
    { buf[NR] = $0 }
    END {
      # Find the last standalone closing brace.
      last_close = 0
      for (i = NR; i >= 1; i--) {
        if (buf[i] ~ /^[[:space:]]*\}[[:space:]]*$/) { last_close = i; break }
      }
      if (last_close == 0) {
        # Malformed JSON — leave file untouched and exit non-zero.
        for (i = 1; i <= NR; i++) print buf[i]
        exit 2
      }
      # Find the last non-blank line before the closing brace.
      preceding = 0
      for (i = last_close - 1; i >= 1; i--) {
        if (buf[i] !~ /^[[:space:]]*$/) { preceding = i; break }
      }
      for (i = 1; i < preceding; i++) print buf[i]
      if (preceding > 0) {
        # `preceding` is either the opening `{` (empty object) or the
        # last existing field. If it ends in `{`, no comma needed.
        # If it ends in `,`, no extra comma needed. Otherwise add one.
        if (buf[preceding] ~ /\{[[:space:]]*$/) {
          print buf[preceding]
        } else if (buf[preceding] ~ /,[[:space:]]*$/) {
          print buf[preceding]
        } else {
          line = buf[preceding]
          sub(/[[:space:]]*$/, "", line)
          print line ","
        }
      }
      # Inject the new field WITHOUT trailing comma (it lands as the
      # last field before `}`).
      print "  \"" k "\": \"" v "\""
      # Preserve any blank lines between preceding and last_close.
      for (i = preceding + 1; i < last_close; i++) print buf[i]
      for (i = last_close; i <= NR; i++) print buf[i]
    }
  ' "$FILE" > "$TMP" || {
    rm -f "$TMP"
    echo "json-set-string-field: malformed JSON in $FILE (no outer closing brace)" >&2
    exit 2
  }
fi
mv "$TMP" "$FILE"
