#!/bin/bash
# Parse, compute, and apply numeric "acceptance-band drift" corrections
# emitted by /run-plan implementation and verification agents.
#
# Pure bash — no jq, no eval, no $(( )) over user-controlled input.
# Stated-form parsing uses awk + case + integer arithmetic only. Same
# pattern as scripts/compute-cron-fire.sh: keep parse/compute/edit logic
# in a testable script rather than skill-prose.
#
# Token format (single-line, space-delimited key=value):
#
#   PLAN-TEXT-DRIFT: phase=<N> bullet=<M> field=<str> plan=<stated> actual=<measured>
#
# - phase=<N>      1-indexed phase number (e.g., phase=1, phase=4A)
# - bullet=<M>     1-indexed ordinal within `### Acceptance Criteria`
# - field=<str>    short identifier, free-form but MUST NOT contain ':'
#                  or '=' (forbids parse ambiguity)
# - plan=<stated>  exact literal from the acceptance criterion
# - actual=<int>   measured value (integer; leading sign + digits)
#
# Modes:
#   --parse <report-file>
#     Reads file, extracts every PLAN-TEXT-DRIFT: token. For each token,
#     emits one line on stdout: <phase>|<bullet>|<field>|<stated>|<actual>
#     Exit 0 on success; 1 if any malformed token (stderr explains).
#
#   --drift <stated> <actual>
#     Computes drift-percent (integer, rounded UP) for the given stated
#     form and integer actual. Supported stated forms:
#       N-M / N–M       range, drift = |actual - midpoint| / midpoint * 100
#       <=N / ≤N / "at most N"
#                       0 if actual ≤ N, else (actual - N)/N * 100
#       >=N / ≥N / "at least N"
#                       0 if actual ≥ N, else (N - actual)/N * 100
#       ~N / "approximately N" / "expected N" / literal N
#                       drift = |actual - N| / N * 100
#       exactly N       0 if actual == N, else 999
#     Any other form: exit 2 with stderr 'unsupported stated form: ...'.
#
#   --correct <plan-file> <phase> <bullet> <new-band> [--audit "original band"]
#     Edits <plan-file>: locates the <phase> ### Acceptance Criteria
#     section, finds the <bullet>th numeric-bearing bullet, replaces its
#     stated band with <new-band>, and appends an audit comment of the
#     form `<!-- Auto-corrected YYYY-MM-DD: was X, arithmetic says Y -->`.
#     Exit 0 on success; 1 if the target bullet can't be uniquely located.
#
#   --eval <expr>
#     Pre-dispatch arithmetic gate (Phase 1 step 6 sub-check b). Evaluates
#     an integer-only expression `N [+-] N [+-] N …` (whitespace-tolerant,
#     integer-only, no variables, no parentheses, no multiplication or
#     division). Implementation is a hand-rolled token-walking parser —
#     NO `eval`, NO shell `$(( ))` over user input, NO awk-script string
#     interpolation. Untrusted strings never reach a shell or arithmetic
#     interpreter.
#       - Emits the computed integer to stdout. Exit 0.
#       - Rejects unsupported operators (`*`, `/`, `(`, `)`, variables,
#         non-digit non-sign chars) with exit 2 and stderr message.
#
# Exits:
#   0  success
#   1  malformed token (parse) / unlocatable bullet (correct)
#   2  unsupported stated form (drift) / usage error / unknown mode

set -eu

usage() {
  sed -n '/^# Token format/,/^#   2 /p' "$0" | sed 's/^# \?//'
}

# ---------- helpers ----------

# Print an error to stderr.
err() { printf '%s\n' "$*" >&2; }

# Validate <field> rejects ':' or '='.
field_ok() {
  case "$1" in
    *:*|*=*) return 1 ;;
  esac
  return 0
}

# Parse an integer "actual" — leading optional sign, then digits, anything
# trailing is discarded. Sets $ACTUAL_INT (positive integers only allowed
# downstream — drift-percent treats negatives as 0-band overshoot).
parse_actual_int() {
  local raw="$1" sign='' digits
  case "$raw" in
    -*) sign='-'; raw="${raw#-}" ;;
    +*) raw="${raw#+}" ;;
  esac
  # Extract leading digits via shell parameter expansion (no eval, no awk).
  digits=''
  while [ -n "$raw" ]; do
    case "$raw" in
      [0-9]*) digits="${digits}${raw:0:1}"; raw="${raw:1}" ;;
      *) break ;;
    esac
  done
  if [ -z "$digits" ]; then
    return 1
  fi
  # Strip leading zeros but keep "0".
  while [ "${#digits}" -gt 1 ] && [ "${digits:0:1}" = "0" ]; do
    digits="${digits:1}"
  done
  ACTUAL_INT="${sign}${digits}"
  return 0
}

# Integer absolute value into stdout.
abs_int() {
  local n="$1"
  case "$n" in
    -*) printf '%s\n' "${n#-}" ;;
    *)  printf '%s\n' "$n" ;;
  esac
}

# Ceiling division of |num| by denom (denom > 0). Both must be integers.
ceil_div_abs() {
  local n d a
  n="$1"; d="$2"
  a=$(abs_int "$n")
  # ceil(a/d) = (a + d - 1) / d for non-negative a, positive d
  printf '%s\n' "$(( (a + d - 1) / d ))"
}

# Compute |actual - target| / target * 100, rounded up. target must be > 0.
drift_relative() {
  local target="$1" actual="$2" diff
  if [ "$target" -le 0 ]; then
    err "drift_relative: target must be positive (got $target)"
    return 2
  fi
  diff=$(( actual - target ))
  diff=$(abs_int "$diff")
  # ceil(diff*100/target)
  printf '%s\n' "$(( (diff * 100 + target - 1) / target ))"
}

# Normalise a stated form for case-matching: strip surrounding whitespace,
# replace en-dash with hyphen, replace ≤/≥ with <=/>=.
normalise_stated() {
  local s="$1"
  # Trim leading/trailing whitespace.
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  # En-dash → hyphen.
  s="${s//–/-}"
  # ≤ → <= , ≥ → >= (multibyte-safe via bash string ops).
  s="${s//≤/<=}"
  s="${s//≥/>=}"
  printf '%s' "$s"
}

# ---------- mode: --parse ----------

mode_parse() {
  local file="$1"
  if [ ! -f "$file" ]; then
    err "plan-drift-correct --parse: file not found: $file"
    return 2
  fi

  local rc=0 line_no=0 line
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$(( line_no + 1 ))
    case "$line" in
      *PLAN-TEXT-DRIFT:*) ;;
      *) continue ;;
    esac

    # Extract the substring starting at the token marker.
    local rest="${line#*PLAN-TEXT-DRIFT:}"
    # Strip leading spaces.
    rest="${rest#"${rest%%[![:space:]]*}"}"

    # Token must be exactly 5 space-delimited key=value pairs.
    # Grammar: phase=<v> bullet=<v> field=<v> plan=<v> actual=<v>
    # We cannot use shell word-split because <stated> may contain spaces
    # (e.g. "at most 50"). Anchor on the literal keys instead.
    local phase bullet field plan_v actual_v

    # Each value runs up to the next ' KEY=' boundary or EOL.
    if ! [[ "$rest" =~ ^phase=([^[:space:]]+)[[:space:]]+bullet=([^[:space:]]+)[[:space:]]+field=([^[:space:]]+)[[:space:]]+plan=(.+)[[:space:]]+actual=(.+)$ ]]; then
      err "plan-drift-correct --parse: malformed token at line $line_no: $line"
      err "  expected: PLAN-TEXT-DRIFT: phase=<N> bullet=<M> field=<str> plan=<stated> actual=<measured>"
      rc=1
      continue
    fi
    phase="${BASH_REMATCH[1]}"
    bullet="${BASH_REMATCH[2]}"
    field="${BASH_REMATCH[3]}"
    plan_v="${BASH_REMATCH[4]}"
    actual_v="${BASH_REMATCH[5]}"

    # Validate field has no ':' or '='.
    if ! field_ok "$field"; then
      err "plan-drift-correct --parse: field contains ':' or '=' at line $line_no: $field"
      rc=1
      continue
    fi

    # phase must be alphanumeric (digits + optional trailing letter, e.g. 4A).
    if ! [[ "$phase" =~ ^[0-9]+[A-Za-z]?$ ]]; then
      err "plan-drift-correct --parse: invalid phase '$phase' at line $line_no"
      rc=1
      continue
    fi

    # bullet must be a positive integer.
    if ! [[ "$bullet" =~ ^[1-9][0-9]*$ ]]; then
      err "plan-drift-correct --parse: invalid bullet '$bullet' at line $line_no (must be positive integer)"
      rc=1
      continue
    fi

    # plan_v must not be empty (already guaranteed by regex .+).
    # actual_v must contain leading digits (with optional sign).
    if ! parse_actual_int "$actual_v"; then
      err "plan-drift-correct --parse: actual='$actual_v' has no leading integer at line $line_no"
      rc=1
      continue
    fi

    printf '%s|%s|%s|%s|%s\n' "$phase" "$bullet" "$field" "$plan_v" "$ACTUAL_INT"
  done < "$file"

  return $rc
}

# ---------- mode: --drift ----------

mode_drift() {
  local stated_raw="$1" actual_raw="$2"

  if ! parse_actual_int "$actual_raw"; then
    err "plan-drift-correct --drift: actual must be an integer, got '$actual_raw'"
    return 2
  fi
  local actual="$ACTUAL_INT"

  local stated
  stated=$(normalise_stated "$stated_raw")

  # Try each supported form in turn. Order matters: more specific patterns
  # (range "N-M") before bare-N forms.

  # exactly N
  if [[ "$stated" =~ ^exactly[[:space:]]+([+-]?[0-9]+)$ ]]; then
    local n="${BASH_REMATCH[1]}"
    if [ "$actual" -eq "$n" ]; then
      printf '0\n'
    else
      printf '999\n'
    fi
    return 0
  fi

  # range: N-M (after en-dash normalisation; allow leading sign on first num)
  if [[ "$stated" =~ ^([+-]?[0-9]+)-([+-]?[0-9]+)$ ]]; then
    local lo="${BASH_REMATCH[1]}" hi="${BASH_REMATCH[2]}"
    if [ "$lo" -gt "$hi" ]; then
      err "plan-drift-correct --drift: range lo > hi in '$stated_raw'"
      return 2
    fi
    # midpoint (integer; truncating toward zero is fine — drift is small either way)
    local mid=$(( (lo + hi) / 2 ))
    if [ "$mid" -le 0 ]; then
      err "plan-drift-correct --drift: range midpoint must be positive in '$stated_raw'"
      return 2
    fi
    drift_relative "$mid" "$actual"
    return 0
  fi

  # ≤N / <=N / "at most N"
  if [[ "$stated" =~ ^(\<=|at[[:space:]]+most[[:space:]]+)([+-]?[0-9]+)$ ]]; then
    local n="${BASH_REMATCH[2]}"
    if [ "$n" -le 0 ]; then
      err "plan-drift-correct --drift: bound must be positive in '$stated_raw'"
      return 2
    fi
    if [ "$actual" -le "$n" ]; then
      printf '0\n'
    else
      local diff=$(( actual - n ))
      printf '%s\n' "$(( (diff * 100 + n - 1) / n ))"
    fi
    return 0
  fi

  # ≥N / >=N / "at least N"
  if [[ "$stated" =~ ^(\>=|at[[:space:]]+least[[:space:]]+)([+-]?[0-9]+)$ ]]; then
    local n="${BASH_REMATCH[2]}"
    if [ "$n" -le 0 ]; then
      err "plan-drift-correct --drift: bound must be positive in '$stated_raw'"
      return 2
    fi
    if [ "$actual" -ge "$n" ]; then
      printf '0\n'
    else
      local diff=$(( n - actual ))
      printf '%s\n' "$(( (diff * 100 + n - 1) / n ))"
    fi
    return 0
  fi

  # ~N / approximately N / expected N / literal N
  if [[ "$stated" =~ ^(~|approximately[[:space:]]+|expected[[:space:]]+)?([+-]?[0-9]+)$ ]]; then
    local n="${BASH_REMATCH[2]}"
    if [ "$n" -le 0 ]; then
      err "plan-drift-correct --drift: target must be positive in '$stated_raw'"
      return 2
    fi
    drift_relative "$n" "$actual"
    return 0
  fi

  err "unsupported stated form: $stated_raw"
  return 2
}

# ---------- mode: --correct ----------

mode_correct() {
  local plan_file="$1" target_phase="$2" target_bullet="$3" new_band="$4"
  local audit_was=""

  shift 4
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --audit)
        shift
        audit_was="${1:-}"
        if [ -z "$audit_was" ]; then
          err "plan-drift-correct --correct: --audit requires a value"
          return 2
        fi
        shift
        ;;
      *)
        err "plan-drift-correct --correct: unknown arg '$1'"
        return 2
        ;;
    esac
  done

  if [ ! -f "$plan_file" ]; then
    err "plan-drift-correct --correct: plan file not found: $plan_file"
    return 2
  fi
  if ! [[ "$target_phase" =~ ^[0-9]+[A-Za-z]?$ ]]; then
    err "plan-drift-correct --correct: invalid phase '$target_phase'"
    return 2
  fi
  if ! [[ "$target_bullet" =~ ^[1-9][0-9]*$ ]]; then
    err "plan-drift-correct --correct: invalid bullet '$target_bullet'"
    return 2
  fi

  # Locate the phase header. We anchor on '## Phase <N>' (allowing trailing
  # text such as "— Foo"). Use grep -nE with anchored pattern; the awk
  # walk that follows uses NR comparisons, not unanchored substring greps.
  local phase_re='^## Phase '"$target_phase"'( |\b|—|-|$)'
  local start_line
  start_line=$(grep -nE "$phase_re" "$plan_file" | head -1 | cut -d: -f1 || true)
  if [ -z "$start_line" ]; then
    err "plan-drift-correct --correct: phase '$target_phase' header not found in $plan_file"
    return 1
  fi

  # Find the next phase header (any) after start_line, to bound the search.
  local end_line
  end_line=$(awk -v s="$start_line" 'NR > s && /^## Phase / { print NR; exit }' "$plan_file")
  if [ -z "$end_line" ]; then
    end_line=$(wc -l < "$plan_file")
    end_line=$(( end_line + 1 ))
  fi

  # Within [start_line, end_line), find '### Acceptance Criteria'.
  local accept_line
  accept_line=$(awk -v s="$start_line" -v e="$end_line" \
    'NR >= s && NR < e && /^### Acceptance Criteria[[:space:]]*$/ { print NR; exit }' \
    "$plan_file")
  if [ -z "$accept_line" ]; then
    err "plan-drift-correct --correct: phase '$target_phase' has no '### Acceptance Criteria' section"
    return 1
  fi

  # Find end of acceptance section: next '### ' or '## ' header.
  local accept_end
  accept_end=$(awk -v s="$accept_line" 'NR > s && /^(##|###) / { print NR; exit }' "$plan_file")
  if [ -z "$accept_end" ]; then
    accept_end=$(wc -l < "$plan_file")
    accept_end=$(( accept_end + 1 ))
  fi

  # Walk bullets in (accept_line, accept_end). A bullet starts with '- [ ]'
  # or '- [x]' optionally indented, OR '- ' (no checkbox). Numeric-bearing
  # bullets are those that contain at least one digit. We index 1-based.
  # Multi-line bullets (continuation indented further) belong to the
  # previous bullet.
  local target_bullet_line=""
  local idx=0
  local current_line=""
  local i=$(( accept_line + 1 ))
  while [ "$i" -lt "$accept_end" ]; do
    local row
    row=$(sed -n "${i}p" "$plan_file")
    # Detect new bullet (top-level '- ' with no leading non-empty spaces > 2).
    if [[ "$row" =~ ^-[[:space:]] ]] || [[ "$row" =~ ^[[:space:]]{0,3}-[[:space:]] ]]; then
      # New bullet: count it if it contains a digit.
      if [[ "$row" =~ [0-9] ]]; then
        idx=$(( idx + 1 ))
        if [ "$idx" -eq "$target_bullet" ]; then
          target_bullet_line="$i"
          break
        fi
      fi
    fi
    i=$(( i + 1 ))
  done

  if [ -z "$target_bullet_line" ]; then
    err "plan-drift-correct --correct: phase '$target_phase' has fewer than $target_bullet numeric-bearing acceptance bullets"
    return 1
  fi

  # Apply the rewrite.
  local original
  original=$(sed -n "${target_bullet_line}p" "$plan_file")

  # Locate the band literal to replace. We prefer the user-supplied
  # `--audit "<original band>"` because it's the explicit, unambiguous
  # match. Without --audit, we fall back to a heuristic: replace the FIRST
  # parenthesised or backticked numeric-looking token. To stay safe we
  # require --audit unless the line contains exactly one numeric token.
  local rewritten
  if [ -n "$audit_was" ]; then
    # Literal substring replacement, first occurrence only.
    if [[ "$original" != *"$audit_was"* ]]; then
      err "plan-drift-correct --correct: --audit literal '$audit_was' not found on bullet line $target_bullet_line"
      return 1
    fi
    rewritten="${original/"$audit_was"/$new_band}"
  else
    err "plan-drift-correct --correct: --audit \"<original band>\" is required (heuristic substitution refused)"
    return 1
  fi

  # Append audit comment.
  local today
  today=$(date -u +%Y-%m-%d)
  rewritten="${rewritten} <!-- Auto-corrected ${today}: was ${audit_was}, arithmetic says ${new_band} -->"

  # In-place replacement of just that one line. We re-emit the file via
  # awk to avoid sed's escaping pitfalls with `&`, `/`, etc.
  local tmp
  tmp=$(mktemp)
  awk -v ln="$target_bullet_line" -v new="$rewritten" '
    NR == ln { print new; next }
    { print }
  ' "$plan_file" > "$tmp"
  mv "$tmp" "$plan_file"
  return 0
}

# ---------- mode: --eval ----------

# Pre-dispatch arithmetic gate. Token-walking parser for integer-only
# expressions of the form `N [+-] N [+-] N …`. Whitespace tolerant.
#
# Security model: untrusted input NEVER reaches `eval` or shell `$(( ))`.
# Each token is matched against strict regexes (`^[+-]?[0-9]+$` for
# operands, exact `+`/`-` for operators); the resulting list of validated
# tokens is fed to awk via `-v` (one variable per token) plus a fixed
# count, so awk only sees integers and the BEGIN block walks them with
# integer arithmetic. No string interpolation into the awk script body.
#
# Rejected with rc=2: `*`, `/`, `(`, `)`, identifiers, decimals, anything
# else.
mode_eval() {
  local expr="$1"

  # Strip leading/trailing whitespace.
  expr="${expr#"${expr%%[![:space:]]*}"}"
  expr="${expr%"${expr##*[![:space:]]}"}"

  if [ -z "$expr" ]; then
    err "plan-drift-correct --eval: empty expression"
    return 2
  fi

  # First-pass charset filter: only digits, +, -, whitespace allowed.
  # Anything else (letters, `*`, `/`, parens, `.`, `,`) → reject early
  # with a precise message.
  local i ch
  i=0
  while [ "$i" -lt "${#expr}" ]; do
    ch="${expr:$i:1}"
    case "$ch" in
      [0-9]|+|-|' '|$'\t')
        ;;
      *)
        err "plan-drift-correct --eval: unsupported character '$ch' in expression (only digits, '+', '-', whitespace allowed)"
        return 2
        ;;
    esac
    i=$(( i + 1 ))
  done

  # Token-walk: split on whitespace and on +/- boundaries. We collect a
  # list of operand-tokens and operator-tokens in alternating order,
  # starting with an operand. A leading sign on the first operand is
  # part of the operand; subsequent +/- are operators.
  #
  # Strategy:
  #   1. Compress runs of whitespace, then parse character-by-character.
  #   2. Build operand-strings until we hit an operator boundary.
  #   3. An operator is a +/- that immediately follows an operand
  #      (with optional whitespace between). A +/- that follows another
  #      operator or starts the expression is a unary sign on the next
  #      operand (only allowed once at the very beginning per operand).
  local operands=()  # validated integer literal strings
  local operators=() # '+' or '-'
  local cur=""
  local expect_operand=1   # 1 → next non-space token starts an operand
  local sign=""            # accumulating leading sign for current operand

  i=0
  while [ "$i" -lt "${#expr}" ]; do
    ch="${expr:$i:1}"
    case "$ch" in
      ' '|$'\t')
        if [ -n "$cur" ]; then
          # End of an operand.
          operands+=("${sign}${cur}")
          cur=""
          sign=""
          expect_operand=0
        fi
        ;;
      [0-9])
        cur="${cur}${ch}"
        # Once digits start, we're mid-operand; subsequent +/- are
        # operators, not signs (until the operand is flushed).
        expect_operand=0
        ;;
      '+'|'-')
        if [ "$expect_operand" = "1" ]; then
          # Sign on the next operand. Only one sign permitted, and only
          # before any digits of the operand.
          if [ -n "$cur" ] || [ -n "$sign" ]; then
            err "plan-drift-correct --eval: unexpected '$ch' (double sign or sign after digit)"
            return 2
          fi
          sign="$ch"
        else
          # End previous operand if still buffered, then record operator.
          if [ -n "$cur" ]; then
            operands+=("${sign}${cur}")
            cur=""
            sign=""
          fi
          operators+=("$ch")
          expect_operand=1
        fi
        ;;
      *)
        # Should have been caught by the charset filter above.
        err "plan-drift-correct --eval: unexpected character '$ch'"
        return 2
        ;;
    esac
    i=$(( i + 1 ))
  done

  # Flush trailing operand.
  if [ -n "$cur" ]; then
    operands+=("${sign}${cur}")
  elif [ -n "$sign" ]; then
    err "plan-drift-correct --eval: trailing sign with no operand"
    return 2
  fi

  # Validate counts: operands must equal operators+1.
  local op_n="${#operands[@]}"
  local opr_n="${#operators[@]}"
  if [ "$op_n" -eq 0 ]; then
    err "plan-drift-correct --eval: no operands parsed from '$1'"
    return 2
  fi
  if [ "$op_n" -ne $(( opr_n + 1 )) ]; then
    err "plan-drift-correct --eval: malformed expression (operands=$op_n, operators=$opr_n)"
    return 2
  fi

  # Validate each operand is a strict integer literal.
  local idx tok
  idx=0
  while [ "$idx" -lt "$op_n" ]; do
    tok="${operands[$idx]}"
    if ! [[ "$tok" =~ ^[+-]?[0-9]+$ ]]; then
      err "plan-drift-correct --eval: invalid integer token '$tok'"
      return 2
    fi
    idx=$(( idx + 1 ))
  done

  # Compute via awk -v. Tokens are now strict integer literals; awk's
  # own integer arithmetic does the math. We never interpolate strings
  # into the awk program body.
  #
  # Build a flat operand-list string and an operator-list string, both
  # space-delimited, and pass them as -v variables. awk splits and walks.
  local operand_blob operator_blob
  operand_blob="${operands[*]}"
  operator_blob="${operators[*]:-}"

  # awk script: split blobs on whitespace, then accumulate.
  # Note: split() in awk handles empty operator_blob by returning 0 fields.
  awk -v ops="$operand_blob" -v ors="$operator_blob" '
    BEGIN {
      n = split(ops, a, /[[:space:]]+/);
      m = split(ors, b, /[[:space:]]+/);
      # awk split(): if the string is empty, awk returns 0 fields.
      # If it is non-empty, leading/trailing FS is suppressed by the FS regex.
      acc = a[1] + 0;
      for (k = 2; k <= n; k++) {
        if (b[k-1] == "+") {
          acc = acc + (a[k] + 0);
        } else if (b[k-1] == "-") {
          acc = acc - (a[k] + 0);
        } else {
          # Unreachable: pre-validated.
          exit 3;
        }
      }
      printf "%d\n", acc;
    }
  '
  return 0
}

# ---------- arg dispatch ----------

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 2
fi

MODE="$1"
shift
case "$MODE" in
  --parse)
    if [ "$#" -ne 1 ]; then
      err "plan-drift-correct --parse <report-file>"
      exit 2
    fi
    mode_parse "$1"
    exit $?
    ;;
  --drift)
    if [ "$#" -ne 2 ]; then
      err "plan-drift-correct --drift <stated> <actual>"
      exit 2
    fi
    mode_drift "$1" "$2"
    exit $?
    ;;
  --correct)
    if [ "$#" -lt 4 ]; then
      err "plan-drift-correct --correct <plan-file> <phase> <bullet> <new-band> [--audit \"original\"]"
      exit 2
    fi
    mode_correct "$@"
    exit $?
    ;;
  --eval)
    if [ "$#" -ne 1 ]; then
      err "plan-drift-correct --eval <expr>"
      exit 2
    fi
    mode_eval "$1"
    exit $?
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    err "plan-drift-correct: unknown mode '$MODE'"
    err "  modes: --parse | --drift | --correct | --eval"
    exit 2
    ;;
esac
