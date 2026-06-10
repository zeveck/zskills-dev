#!/usr/bin/env bash
# Asserts total `description:` bytes across all source SKILL.md files
# (skills/*/SKILL.md).
# Two-tier budget: hard-fail above 7500, soft-warn between 7000 and 7500.
# Per-skill breakdown emitted for diagnosis.
#
# Units note: the script runs under LC_ALL=C and uses bash `${#var}`,
# which counts BYTES (not characters) in the C locale. Multibyte UTF-8
# code points (e.g. em-dash U+2014 = 3 bytes) therefore contribute more
# than one to the total. We report and budget in bytes — both because
# bytes are what bash measures cheaply without an awk/python detour and
# because byte-count is the right proxy for token-context cost on the
# wire. A future trimmer chasing a budget overage should think in bytes,
# not characters. See issue #339.
#
# Background: ~7500 bytes ≈ 1875 tokens ≈ <1% of 200k context. The
# project's design target chosen to honor the published Anthropic
# skill-development guidance of ~100 words/skill, scaled to ~30 skills,
# leaving headroom in the 200k context budget for descriptions. This is
# a project-internal target, not an Anthropic-enforced cap. See
# `references/skill-description-budget.md` for derivation.
set -euo pipefail
LC_ALL=C; export LC_ALL
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
cd "$ROOT"

# Two-tier budget (D14): a future agent that expands to 7900 should not
# silently pass a single 8000-cap test. Hard-fail at 7500; soft-warn
# anywhere between WARN_AT and CAP (printed but exit 0).
CAP=7500
WARN_AT=7000

extract_description() {
  # Read SKILL.md, extract `description:` value as a single line.
  # Handles BOTH scalar forms found in this repo:
  #   * Block scalar: `description: >-` followed by indented continuation
  #     lines (joined with single spaces, YAML folded form).
  #   * Single-line: `description: <text on the same line>` (e.g.
  #     land-pr, update-zskills).
  # Pure awk; no jq, no python.
  local file="$1"
  awk '
    BEGIN { in_fm=0; in_desc=0; out=""; ind="" }
    /^---$/ {
      if (!in_fm) { in_fm=1; next }
      else { in_fm=0; exit }   # END block prints; do not double-print here
    }
    # Single-line form: `description: <value>` where <value> is non-empty
    # and not a block-scalar indicator (`>-`, `>`, `|`, `|-`).
    in_fm && /^description: / {
      rest = substr($0, length("description: ") + 1)
      # Detect block-scalar indicator (optional trim/keep flag).
      if (rest ~ /^>-?[+-]?[[:space:]]*$/ || rest ~ /^\|-?[+-]?[[:space:]]*$/) {
        in_desc = 1
        next
      }
      # Otherwise treat as single-line scalar — strip optional surrounding
      # quotes and emit immediately.
      gsub(/^"/, "", rest); gsub(/"$/, "", rest)
      gsub(/^'\''/, "", rest); gsub(/'\''$/, "", rest)
      out = rest
      next
    }
    in_fm && in_desc {
      # Block-scalar continuation lines are indented; first such line
      # sets the indent. Stop on next top-level key (no leading space).
      if (ind=="" && match($0, /^[ ]+/)) { ind=substr($0, 1, RLENGTH) }
      if (ind!="" && index($0, ind)==1) {
        line=substr($0, length(ind)+1)
        if (out=="") out=line; else out=out " " line
        next
      } else if (/^[A-Za-z]/) {
        in_desc=0
      }
    }
    in_fm && /^[A-Za-z]/ && in_desc==0 { next }
    END { if (out!="") print out }
  ' "$file"
}

TOTAL=0
declare -A PER_SKILL
for f in $(find skills -mindepth 2 -maxdepth 2 -name SKILL.md | sort); do
  desc=$(extract_description "$f")
  n=${#desc}
  name=$(echo "$f" | awk -F/ '{print $2}')
  PER_SKILL["$name"]=$n
  TOTAL=$((TOTAL + n))
done

# Emit per-skill breakdown sorted by bytes desc.
echo "# skill-description-budget per-skill breakdown (bytes)"
for name in "${!PER_SKILL[@]}"; do
  printf '%5d  %s\n' "${PER_SKILL[$name]}" "$name"
done | sort -nr

echo "----"
echo "TOTAL: $TOTAL bytes (warn_at: $WARN_AT, hard_cap: $CAP)"

if (( TOTAL > CAP )); then
  echo "FAIL: total description bytes $TOTAL exceeds hard cap $CAP" >&2
  exit 1
fi
if (( TOTAL > WARN_AT )); then
  echo "WARN: total description bytes $TOTAL is between warn-at $WARN_AT and hard cap $CAP — trim before next addition" >&2
fi
echo "PASS"
