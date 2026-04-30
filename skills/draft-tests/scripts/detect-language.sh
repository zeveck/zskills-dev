#!/bin/bash
# detect-language.sh -- Phase 2 language detection, test-file discovery,
# calibration-signal extraction, and config-first resolution for /draft-tests.
#
# Usage:
#   bash detect-language.sh <project-root> <state-out>
#
# Arguments:
#   <project-root>  Absolute path to the consumer project's root directory
#                   (the directory that contains package.json / pyproject.toml /
#                   etc.). For zskills source-tree tests this is $REPO_ROOT;
#                   for shipped invocations this is the consumer repo root.
#   <state-out>     Path to write the detection-state file
#                   (e.g. /tmp/draft-tests-detect-<slug>.md).
#
# The detection-state file is a stable line-based format consumed by Phase 3
# (drafter calibration) and Phase 5 (backfill gap detection / test-file map).
# It is additive to (independent of) Phase 1's parsed-state file -- nothing
# in Phase 1's schema is removed or altered.
#
# Format (every key on its own line; lists indented two spaces):
#
#   project_root: <path>
#   languages:
#     <lang-name>
#     ...
#   recommendations:
#     <lang-name>: <runner>
#     ...
#   test_files:
#     <lang-name>:<path>
#     ...
#   calibration_signal_file: <path-or-empty>
#   no_test_setup: <0|1>
#   recommendation_text: <verbatim text or empty>
#   detection_status: <ok|undetectable|error>
#   config_full_cmd: <verbatim or empty>
#   config_unit_cmd: <verbatim or empty>
#   case: <1|2|3>          # config-first three-case from /verify-changes
#   advisories:
#     <line>
#     ...
#
# Three-case decision tree (mirrors /verify-changes):
#   case=1  -> .claude/zskills-config.json testing.full_cmd OR testing.unit_cmd
#             is set -> pass verbatim to drafter; detection downgraded to
#             informational (recommendation_text empty unless useful).
#   case=2  -> tests exist in repo + no config command -> detection provides
#             framework recommendation; drafter told to match existing style.
#   case=3  -> no test infra + no config -> emit recommendation; skip
#             test-style calibration.
#
# Calibration signal:
#   Per language, read at most 3 candidate test files (preferring most
#   imports, ties broken by largest file). Extract framework markers,
#   naming convention, fixture style, assertion library. Emit at most 20
#   lines per language to a separate "calibration signal" file. The
#   signal-file path is written to detection-state via
#   `calibration_signal_file:`.
#
# Bash-only; no jq. JSON parsing via BASH_REMATCH idioms.

# Note: this script intentionally does NOT use `set -u`. Bash 4 has
# a long-standing bug where empty arrays trip "unbound variable" under
# `set -u` even with the standard `${ARR[@]:-}` guard. The script uses
# `set -e` plus explicit defaulting via `${VAR:-}` everywhere instead.
set -e

PROJECT_ROOT="${1:-}"
STATE_OUT="${2:-}"

if [ -z "$PROJECT_ROOT" ] || [ -z "$STATE_OUT" ]; then
  echo "Usage: $0 <project-root> <state-out>" >&2
  exit 2
fi

if [ ! -d "$PROJECT_ROOT" ]; then
  echo "Error: project root '$PROJECT_ROOT' is not a directory." >&2
  exit 3
fi

# Always ensure the state file is created fresh.
: > "$STATE_OUT"

# Calibration-signal file path (sibling to the state file).
SIG_OUT="${STATE_OUT%.md}.signal.md"
: > "$SIG_OUT"

declare -a LANGUAGES
declare -A RECOMMENDATIONS  # lang -> runner
declare -A TEST_FILES_BY_LANG  # lang -> newline-separated paths
declare -a ADVISORIES
DETECTION_STATUS="ok"
NO_TEST_SETUP=0
RECOMMENDATION_TEXT=""
CONFIG_FULL_CMD=""
CONFIG_UNIT_CMD=""
CASE_NUM=3

# ---------------------------------------------------------------------------
# Step 1 -- config-first. Read .claude/zskills-config.json if present.
# Bash regex parse only; no jq. WI 2.6.
# ---------------------------------------------------------------------------
CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
if [ -f "$CONFIG_FILE" ]; then
  CONFIG_RAW="$(cat "$CONFIG_FILE")"
  if [[ "$CONFIG_RAW" =~ \"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    CONFIG_FULL_CMD="${BASH_REMATCH[1]}"
  fi
  if [[ "$CONFIG_RAW" =~ \"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    CONFIG_UNIT_CMD="${BASH_REMATCH[1]}"
  fi
fi

# ---------------------------------------------------------------------------
# Step 2 -- language detection from manifest files (WI 2.1). Detection
# failures (malformed manifest) emit an advisory to stderr and degrade to
# "language undetectable" without aborting (WI 2.7).
# ---------------------------------------------------------------------------

detect_javascript() {
  local pj="$PROJECT_ROOT/package.json"
  [ -f "$pj" ] || return 1
  # Validate JSON shape minimally: must contain at least one key:value pair
  # within an object. A malformed manifest -> advisory, undetectable.
  local pj_raw
  pj_raw="$(cat "$pj" 2>/dev/null || true)"
  # Heuristic: file must contain `{` and `}` and at least one `"<key>"`.
  if [[ ! "$pj_raw" =~ \{ ]] || [[ ! "$pj_raw" =~ \} ]] \
     || [[ ! "$pj_raw" =~ \"[a-zA-Z_][a-zA-Z0-9_-]*\"[[:space:]]*: ]]; then
    ADVISORIES+=("Malformed package.json at '$pj' -- treated as language undetectable.")
    echo "/draft-tests detect-language: malformed package.json at '$pj' -- treating as undetectable." >&2
    DETECTION_STATUS="undetectable"
    return 1
  fi
  LANGUAGES+=("javascript")
  # If jest is referenced as a key/value in package.json (the spec says
  # "scripts or devDependencies"), recommend jest; else vitest. We bind
  # jest to a quoted JSON token form to avoid false positives like the
  # word "jest" appearing in "description" / "no jest reference".
  if [[ "$pj_raw" =~ \"jest\"[[:space:]]*: ]] \
     || [[ "$pj_raw" =~ \"jest\"[[:space:]]*\, ]] \
     || [[ "$pj_raw" =~ \"jest\"[[:space:]]*\} ]] \
     || [[ "$pj_raw" =~ :[[:space:]]*\"jest\" ]] \
     || [[ "$pj_raw" =~ jest[[:space:]]+--config ]]; then
    RECOMMENDATIONS["javascript"]="jest"
  else
    RECOMMENDATIONS["javascript"]="vitest"
  fi
  return 0
}

detect_python() {
  if [ -f "$PROJECT_ROOT/pyproject.toml" ] \
     || [ -f "$PROJECT_ROOT/setup.py" ] \
     || ls "$PROJECT_ROOT"/requirements*.txt >/dev/null 2>&1; then
    LANGUAGES+=("python")
    RECOMMENDATIONS["python"]="pytest"
    return 0
  fi
  return 1
}

detect_go() {
  if [ -f "$PROJECT_ROOT/go.mod" ]; then
    LANGUAGES+=("go")
    RECOMMENDATIONS["go"]="go test"
    return 0
  fi
  return 1
}

detect_rust() {
  if [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
    LANGUAGES+=("rust")
    RECOMMENDATIONS["rust"]="cargo test"
    return 0
  fi
  return 1
}

detect_bash() {
  # Heavy *.sh content at repo root or scripts/, AND no other manifest.
  local sh_count=0
  if [ -d "$PROJECT_ROOT/scripts" ]; then
    sh_count=$(find "$PROJECT_ROOT/scripts" -maxdepth 2 -name '*.sh' -type f 2>/dev/null | wc -l)
  fi
  local root_sh
  root_sh=$(find "$PROJECT_ROOT" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | wc -l)
  sh_count=$((sh_count + root_sh))
  if [ "$sh_count" -ge 3 ]; then
    LANGUAGES+=("bash")
    RECOMMENDATIONS["bash"]="bats"
    return 0
  fi
  return 1
}

detect_javascript || true
detect_python || true
detect_go || true
detect_rust || true
# Only consider bash if no other manifest matched (the "no other manifest" condition).
if [ "${#LANGUAGES[@]}" -eq 0 ]; then
  detect_bash || true
fi

# Polyglot is implicit in LANGUAGES having >1 entry.

# ---------------------------------------------------------------------------
# Step 3 -- test-file discovery (WI 2.2). Per-language heuristics. Find
# emits no errors when directories are missing. find runs are bounded by
# project root (`-not -path '*/node_modules/*'` etc.) to avoid noise.
# ---------------------------------------------------------------------------

# Common ignores: node_modules, .git, .venv, target, dist, build.
FIND_PRUNE=(
  -path "$PROJECT_ROOT/node_modules" -prune -o
  -path "$PROJECT_ROOT/.git"          -prune -o
  -path "$PROJECT_ROOT/.venv"         -prune -o
  -path "$PROJECT_ROOT/venv"          -prune -o
  -path "$PROJECT_ROOT/target"        -prune -o
  -path "$PROJECT_ROOT/dist"          -prune -o
  -path "$PROJECT_ROOT/build"         -prune -o
  -path "$PROJECT_ROOT/__pycache__"   -prune -o
)

find_js_tests() {
  find "$PROJECT_ROOT" "${FIND_PRUNE[@]}" \
    \( -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' -o -name '*.test.jsx' \
       -o -name '*.spec.ts' -o -name '*.spec.tsx' -o -name '*.spec.js' -o -name '*.spec.jsx' \
       -o -path '*/__tests__/*.ts' -o -path '*/__tests__/*.tsx' \
       -o -path '*/__tests__/*.js' -o -path '*/__tests__/*.jsx' \) \
    -type f -print 2>/dev/null
}

find_py_tests() {
  find "$PROJECT_ROOT" "${FIND_PRUNE[@]}" \
    \( -name 'test_*.py' -o -name '*_test.py' \) \
    -type f -print 2>/dev/null
}

find_go_tests() {
  find "$PROJECT_ROOT" "${FIND_PRUNE[@]}" \
    -name '*_test.go' -type f -print 2>/dev/null
}

find_rust_tests() {
  # Files under tests/ subtrees + grep for #[cfg(test)] blocks.
  find "$PROJECT_ROOT" "${FIND_PRUNE[@]}" \
    \( -path '*/tests/*.rs' \) -type f -print 2>/dev/null
  # Grep #[cfg(test)] anywhere outside the prune list.
  grep -rl --include='*.rs' \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=target \
    --exclude-dir=dist --exclude-dir=build \
    '#\[cfg(test)\]' "$PROJECT_ROOT" 2>/dev/null
}

find_bash_tests() {
  find "$PROJECT_ROOT" "${FIND_PRUNE[@]}" \
    \( -path '*/tests/test-*.sh' -o -path '*/tests/*_test.sh' \) \
    -type f -print 2>/dev/null
}

for lang in "${LANGUAGES[@]:-}"; do
  [ -z "$lang" ] && continue
  case "$lang" in
    javascript) files="$(find_js_tests | sort -u)" ;;
    python)     files="$(find_py_tests | sort -u)" ;;
    go)         files="$(find_go_tests | sort -u)" ;;
    rust)       files="$(find_rust_tests | sort -u)" ;;
    bash)       files="$(find_bash_tests | sort -u)" ;;
    *)          files="" ;;
  esac
  TEST_FILES_BY_LANG["$lang"]="$files"
done

# ---------------------------------------------------------------------------
# Step 4 -- calibration signal (WI 2.3). Per language, read at most 3 test
# files preferring (i) most imports, (ii) largest file as tiebreak. Extract
# a small regex panel and emit <=20 lines per language to SIG_OUT.
# ---------------------------------------------------------------------------

count_imports() {
  local f="$1"
  # JS/TS: count `import ` + `require(`. Python: `import ` + `from `. Generic
  # fallback: count `import` lines in first 10 lines.
  head -n 50 "$f" 2>/dev/null | grep -cE '^[[:space:]]*(import|from|require\()' 2>/dev/null
}

# Choose top-3 calibration files for a language, write a structured summary.
emit_signal_for() {
  local lang="$1"
  local files_str="${TEST_FILES_BY_LANG[$lang]:-}"
  [ -z "$files_str" ] && return 0
  # Build a (imports lines, size, path) array.
  local picks=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    local imp size
    imp=$(count_imports "$f")
    size=$(wc -c < "$f" 2>/dev/null || echo 0)
    # Strip newline whitespace.
    imp="${imp//[[:space:]]/}"
    size="${size//[[:space:]]/}"
    picks+="$imp $size $f"$'\n'
  done <<< "$files_str"
  # Sort: imports desc, size desc.
  local top3
  top3=$(printf '%s' "$picks" | sort -k1,1nr -k2,2nr | head -n 3)

  # Choose a representative test-file path: the first of the top-3.
  local rep_file
  rep_file=$(printf '%s' "$top3" | head -n 1 | awk '{print $3}')

  # Slice up to 20 lines max for the per-language summary.
  {
    printf '## %s\n' "$lang"
    printf 'framework: %s\n' "${RECOMMENDATIONS[$lang]:-unknown}"
    if [ -n "$rep_file" ]; then
      printf 'representative_file: %s\n' "$rep_file"
    fi
    # Convention markers across the top-3.
    local naming="" assert_lib="" fixture="" describe_seen=0 it_seen=0 test_seen=0
    while IFS= read -r row; do
      [ -z "$row" ] && continue
      local f
      f=$(echo "$row" | awk '{print $3}')
      [ -z "$f" ] && continue
      [ -f "$f" ] || continue
      if grep -qE '\<describe\(' "$f" 2>/dev/null; then describe_seen=1; fi
      if grep -qE '\<it\(' "$f" 2>/dev/null; then it_seen=1; fi
      if grep -qE '(\<test\()|(^def[[:space:]]+test_)|(_test\b)' "$f" 2>/dev/null; then test_seen=1; fi
      if grep -qE '\b(assertEqual|expect\(|assert\.|should)' "$f" 2>/dev/null; then
        if [ -z "$assert_lib" ]; then
          if grep -qE '\bexpect\(' "$f" 2>/dev/null; then assert_lib="expect"; fi
          if grep -qE 'assertEqual' "$f" 2>/dev/null; then assert_lib="assertEqual"; fi
          if grep -qE 'assert\.' "$f" 2>/dev/null; then assert_lib="${assert_lib:-assert.}"; fi
          if grep -qE '\bshould\b' "$f" 2>/dev/null; then assert_lib="${assert_lib:-should}"; fi
        fi
      fi
      if grep -qE '\b(beforeEach|fixture|setup|setUp)\b' "$f" 2>/dev/null; then
        fixture="present"
      fi
    done <<< "$top3"
    if [ $describe_seen -eq 1 ] && [ $it_seen -eq 1 ]; then
      naming="describe/it"
    elif [ $test_seen -eq 1 ]; then
      naming="test_/_test"
    else
      naming="unknown"
    fi
    printf 'naming_convention: %s\n' "$naming"
    printf 'assertion_library: %s\n' "${assert_lib:-unknown}"
    printf 'fixture_style: %s\n' "${fixture:-none}"
    # Imports excerpt (top 10 lines of representative file, prefixed with `> `
    # so the signal is visually distinct from outer prose). Bound size: max 10
    # lines, max 80 cols each.
    if [ -n "$rep_file" ] && [ -f "$rep_file" ]; then
      printf 'imports_excerpt:\n'
      head -n 10 "$rep_file" | head -c 800 | awk '{ if (length($0) > 80) print "  " substr($0, 1, 80); else print "  " $0 }'
    fi
  } >> "$SIG_OUT"
  # Truncate this language's section to 20 lines max. We do this by
  # rewriting the whole signal file, keeping only the most-recent
  # language section trimmed to 20 lines. Simpler: append a 20-line cap
  # using awk that knows section boundaries.
}

# Cap each `## <lang>` section to 20 lines (header inclusive). Run as a
# pass over SIG_OUT after all languages have been appended.
cap_signal_sections_to_20() {
  local tmp
  tmp=$(mktemp)
  awk '
    BEGIN { count = 0; in_section = 0 }
    /^## / {
      in_section = 1
      count = 0
      print
      count++
      next
    }
    in_section && count >= 20 { next }
    {
      print
      if (in_section) count++
    }
  ' "$SIG_OUT" > "$tmp"
  mv "$tmp" "$SIG_OUT"
}

# Phase 4 (Step 4). Emit signal for each detected language IF candidate
# files exist (case 2). In case 1 (config set) we DOWNGRADE to informational
# only -- still record framework recommendation but skip extracting style.
# In case 3 (no infra + no config) we skip entirely (handled below).
for lang in "${LANGUAGES[@]:-}"; do
  [ -z "$lang" ] && continue
  files_for_lang="${TEST_FILES_BY_LANG[$lang]:-}"
  if [ -n "$files_for_lang" ]; then
    emit_signal_for "$lang"
  fi
done
cap_signal_sections_to_20 || true

# ---------------------------------------------------------------------------
# Step 5 -- Three-case decision tree (WI 2.6).
# ---------------------------------------------------------------------------
# Compute "tests exist anywhere" by union over per-language test-file lists.
total_test_files=0
for lang in "${LANGUAGES[@]:-}"; do
  [ -z "$lang" ] && continue
  files_for_lang="${TEST_FILES_BY_LANG[$lang]:-}"
  if [ -n "$files_for_lang" ]; then
    n=$(printf '%s\n' "$files_for_lang" | grep -c .)
    total_test_files=$((total_test_files + n))
  fi
done

if [ -n "$CONFIG_FULL_CMD$CONFIG_UNIT_CMD" ]; then
  CASE_NUM=1
  RECOMMENDATION_TEXT=""
elif [ "$total_test_files" -gt 0 ]; then
  CASE_NUM=2
  RECOMMENDATION_TEXT=""
else
  CASE_NUM=3
fi

# ---------------------------------------------------------------------------
# Step 6 -- No-test-setup recommendation text (WI 2.4). Only when CASE=3.
# ---------------------------------------------------------------------------
if [ "$CASE_NUM" -eq 3 ]; then
  NO_TEST_SETUP=1
  if [ "${#LANGUAGES[@]}" -eq 0 ]; then
    DETECTION_STATUS="undetectable"
    RECOMMENDATION_TEXT=""
  else
    # Per-language one-liner. Polyglot: emit a multiline list.
    REC_LINES=""
    for lang in "${LANGUAGES[@]}"; do
      runner="${RECOMMENDATIONS[$lang]:-unknown}"
      manifest_hint=""
      case "$lang" in
        javascript) manifest_hint="JavaScript/TypeScript detected from package.json" ;;
        python)     manifest_hint="Python detected from pyproject.toml/setup.py/requirements*.txt" ;;
        go)         manifest_hint="Go detected from go.mod" ;;
        rust)       manifest_hint="Rust detected from Cargo.toml" ;;
        bash)       manifest_hint="Bash detected from heavy *.sh content" ;;
      esac
      REC_LINES+="> Recommended: \`$runner\` ($manifest_hint)."$'\n'
    done
    RECOMMENDATION_TEXT="## Prerequisites

> **Test-runner recommendation:** this project has no configured test runner.
${REC_LINES}> Add appropriate test infra (configuration + tests/ directory) before running the first test-bearing phase."
  fi
fi

# When language is undetectable but CASE_NUM == 3, also surface the literal
# "no configured test runner" wording so AC-2.4 holds even when the manifest
# was missing entirely. Keep the literal phrase on a single line so
# downstream `grep -F` checks match.
if [ "$CASE_NUM" -eq 3 ] && [ "${#LANGUAGES[@]}" -eq 0 ]; then
  RECOMMENDATION_TEXT="## Prerequisites

> **Test-runner recommendation:** this project has no configured test runner. Language could not be detected from a manifest file. Add a manifest (package.json, pyproject.toml, go.mod, Cargo.toml, etc.) and appropriate test infra before running the first test-bearing phase."
fi

# ---------------------------------------------------------------------------
# Step 7 -- write detection-state file. Bash regex-friendly line format,
# additive to Phase 1 parsed-state schema.
# ---------------------------------------------------------------------------
{
  printf 'project_root: %s\n' "$PROJECT_ROOT"
  printf 'languages:\n'
  for lang in "${LANGUAGES[@]:-}"; do
    [ -z "$lang" ] && continue
    printf '  %s\n' "$lang"
  done
  printf 'recommendations:\n'
  for lang in "${LANGUAGES[@]:-}"; do
    [ -z "$lang" ] && continue
    printf '  %s: %s\n' "$lang" "${RECOMMENDATIONS[$lang]:-}"
  done
  printf 'test_files:\n'
  for lang in "${LANGUAGES[@]:-}"; do
    [ -z "$lang" ] && continue
    files_for_lang="${TEST_FILES_BY_LANG[$lang]:-}"
    [ -z "$files_for_lang" ] && continue
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      printf '  %s:%s\n' "$lang" "$f"
    done <<< "$files_for_lang"
  done
  printf 'calibration_signal_file: %s\n' "$SIG_OUT"
  printf 'no_test_setup: %s\n' "$NO_TEST_SETUP"
  printf 'detection_status: %s\n' "$DETECTION_STATUS"
  printf 'config_full_cmd: %s\n' "$CONFIG_FULL_CMD"
  printf 'config_unit_cmd: %s\n' "$CONFIG_UNIT_CMD"
  printf 'case: %s\n' "$CASE_NUM"
  printf 'advisories:\n'
  for adv in "${ADVISORIES[@]:-}"; do
    [ -z "$adv" ] && continue
    printf '  %s\n' "$adv"
  done
  # recommendation_text is multiline; write at the END as a heredoc-style
  # block separated by a sentinel line. Consumers parse: anything after the
  # `recommendation_text_begin` marker until `recommendation_text_end` is
  # the verbatim block.
  printf 'recommendation_text_begin\n'
  printf '%s\n' "$RECOMMENDATION_TEXT"
  printf 'recommendation_text_end\n'
} > "$STATE_OUT"

# Echo advisories to stderr so the orchestrator can surface them.
for adv in "${ADVISORIES[@]:-}"; do
  [ -z "$adv" ] && continue
  printf '%s\n' "$adv" >&2
done

exit 0
