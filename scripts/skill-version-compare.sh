#!/bin/bash
# skill-version-compare.sh — Compare two `metadata.version` strings of
# the form `YYYY.MM.DD+HHHHHH` and decide whether `<new>` is a valid
# bump from `<old>`.
#
# Usage:
#   bash scripts/skill-version-compare.sh <old-version> <new-version>
#
# A valid bump is defined per references/skill-versioning.md §1.3:
#
#   date(new) >= date(old)  AND  ( date(new) > date(old) OR hash(new) != hash(old) )
#
# Equivalently: the new version is at least as new in date, AND is not
# byte-identical to the old version (either the date moved forward, or
# the content hash changed). This closes the "same-day re-edit" gap that
# pure lexical `>` comparison misses (issue #178). See Appendix D in
# references/skill-versioning.md for the comparator definition and
# rationale.
#
# Exit codes:
#   0  <new> is a valid bump from <old>
#   1  <new> is NOT a valid bump (same content / regression)
#   2  malformed input (bad regex, missing arg)
#
# Errors / diagnostics go to stderr. Stdout is silent on success.
#
# Pure bash. No jq, no external compare tools.

set -euo pipefail
export LC_ALL=C

VERSION_RE='^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$'

die_malformed() {
  echo "ERROR: $1" >&2
  exit 2
}

if [ "$#" -ne 2 ]; then
  die_malformed "usage: $(basename "$0") <old-version> <new-version> (got $# arg(s))"
fi

OLD="$1"
NEW="$2"

if [ -z "$OLD" ]; then
  die_malformed "<old-version> is empty"
fi
if [ -z "$NEW" ]; then
  die_malformed "<new-version> is empty"
fi
if ! [[ "$OLD" =~ $VERSION_RE ]]; then
  die_malformed "<old-version> '$OLD' does not match $VERSION_RE"
fi
if ! [[ "$NEW" =~ $VERSION_RE ]]; then
  die_malformed "<new-version> '$NEW' does not match $VERSION_RE"
fi

OLD_DATE="${OLD%%+*}"   # YYYY.MM.DD
OLD_HASH="${OLD##*+}"   # HHHHHH
NEW_DATE="${NEW%%+*}"
NEW_HASH="${NEW##*+}"

# Lexical comparison of YYYY.MM.DD with zero-padded fields is equivalent
# to chronological comparison.
if [[ "$NEW_DATE" < "$OLD_DATE" ]]; then
  echo "NOT A BUMP: new date $NEW_DATE is older than old date $OLD_DATE" >&2
  exit 1
fi

if [[ "$NEW_DATE" == "$OLD_DATE" ]] && [[ "$NEW_HASH" == "$OLD_HASH" ]]; then
  echo "NOT A BUMP: new version $NEW is byte-identical to old $OLD (same date AND same hash)" >&2
  exit 1
fi

# Either NEW_DATE > OLD_DATE (any hash valid, including a lexically smaller one
# — date wins per §1.3), or NEW_DATE == OLD_DATE AND NEW_HASH != OLD_HASH
# (same-day re-edit: hash must differ).
exit 0
