#!/bin/bash
# test-all.sh -- Runs all test suites: unit, e2e, and build/codegen.
#
# - Unit tests: always run
# - E2E tests: run if dev server is up on the derived port, skipped with warning otherwise
# - Build/codegen tests: run if prerequisites are met, skipped with warning otherwise
#
# CONFIGURE: Replace the {{PLACEHOLDER}} values below with your project's commands.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Runtime config read (eliminates install-time drift) ───
# Read testing.unit_cmd from the checked-out .claude/zskills-config.json.
_ZSK_REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || cd "$SCRIPT_DIR/.." && pwd)}"
_ZSK_CFG="$_ZSK_REPO_ROOT/.claude/zskills-config.json"
UNIT_TEST_CMD=""
if [ -f "$_ZSK_CFG" ]; then
  _ZSK_CFG_BODY=$(cat "$_ZSK_CFG" 2>/dev/null) || _ZSK_CFG_BODY=""
  if [[ "$_ZSK_CFG_BODY" =~ \"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    UNIT_TEST_CMD="${BASH_REMATCH[1]}"
  fi
  unset _ZSK_CFG_BODY
fi
unset _ZSK_REPO_ROOT _ZSK_CFG

# ─── CONFIGURE ──────────────────────────────────────────────────────
# E2E_TEST_CMD / BUILD_TEST_CMD have no config source; install-filled by
# /update-zskills. See plan DRIFT_ARCH_FIX.md Out-of-Scope.
E2E_TEST_CMD='{{E2E_TEST_CMD}}'
BUILD_TEST_CMD='{{BUILD_TEST_CMD}}'
# ────────────────────────────────────────────────────────────────────

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

# Track results: name:status pairs (status: pass, fail, skip)
declare -a RESULT_NAMES=()
declare -a RESULT_STATUSES=()

header() {
  printf '\n%b%s%b\n' "$BOLD" "$(printf '=%.0s' {1..60})" "$RESET"
  printf '%b  %s%b\n' "$BOLD" "$1" "$RESET"
  printf '%b%s%b\n\n' "$BOLD" "$(printf '=%.0s' {1..60})" "$RESET"
}

record() {
  RESULT_NAMES+=("$1")
  RESULT_STATUSES+=("$2")
}

get_port() {
  # Source port logic inline (same as port.sh)
  if [[ -n "$DEV_PORT" ]]; then
    echo "$DEV_PORT"
    return
  fi
  local project_root
  project_root="$(cd "$SCRIPT_DIR/.." && pwd)"
  # Runtime config read: dev_server.main_repo_path
  local _cfg_root="${REPO_ROOT:-$(git -C "$project_root" rev-parse --show-toplevel 2>/dev/null || echo "$project_root")}"
  local _cfg="$_cfg_root/.claude/zskills-config.json"
  local main_repo=""
  if [ -f "$_cfg" ]; then
    local _body
    _body=$(cat "$_cfg" 2>/dev/null) || _body=""
    if [[ "$_body" =~ \"dev_server\"[[:space:]]*:[[:space:]]*\{[^}]*\"main_repo_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      main_repo="${BASH_REMATCH[1]}"
    fi
  fi
  if [[ -n "$main_repo" ]] && [[ "$project_root" == "$main_repo" ]]; then
    echo 8080
    return
  fi
  local hash
  hash=$(printf '%s' "$project_root" | cksum | awk '{print $1}')
  echo $(( 9000 + (hash % 51000) ))
}

check_port() {
  # Check if a TCP port is open. Uses /dev/tcp (bash built-in).
  local port=$1
  (echo >/dev/tcp/127.0.0.1/"$port") 2>/dev/null
}

has_build_prerequisite() {
  # CONFIGURE: check for your build test prerequisite (e.g., cargo)
  command -v cargo &>/dev/null
}

has_changed_source_files() {
  # Check if any staged or unstaged changes touch source files that E2E tests cover
  local staged unstaged all_changed source_files
  staged=$(git diff --cached --name-only 2>/dev/null)
  unstaged=$(git diff --name-only 2>/dev/null)
  all_changed=$(printf '%s\n%s' "$staged" "$unstaged" | sort -u | grep -v '^$')

  source_files=$(echo "$all_changed" | grep -E '^(src/|tests/e2e/).*\.(js|ts|css|html)$')
  if [[ -n "$source_files" ]]; then
    echo "$source_files"
    return 0
  fi
  return 1
}

# ── 1. Unit + integration tests (always) ───────────────────────────

header "Unit + Integration Tests ($UNIT_TEST_CMD)"
if eval "$UNIT_TEST_CMD"; then
  record "Unit/integration" "pass"
else
  record "Unit/integration" "fail"
fi

# ── 2. E2E tests (if dev server is up) ─────────────────────────────

PORT=$(get_port)

if check_port "$PORT"; then
  header "E2E Tests ($E2E_TEST_CMD)"
  if eval "$E2E_TEST_CMD"; then
    record "E2E" "pass"
  else
    record "E2E" "fail"
  fi
else
  header "E2E Tests ($E2E_TEST_CMD)"
  if e2e_relevant=$(has_changed_source_files); then
    printf '%bx FAILED -- dev server not running on port %s, but source files changed:%b\n' "$RED" "$PORT" "$RESET"
    printf '  %s\n' "$e2e_relevant"
    printf '\n  E2E tests cannot be skipped when src/ files are modified.\n'
    printf '  Start the dev server and re-run tests.\n\n'
    record "E2E" "fail"
  else
    printf '%b! SKIPPED -- dev server not running on port %s (no source files changed)%b\n' "$YELLOW" "$PORT" "$RESET"
    printf '  Start the dev server to enable E2E tests.\n\n'
    record "E2E" "skip"
  fi
fi

# ── 3. Build/codegen tests (if prerequisites are met) ──────────────

if has_build_prerequisite; then
  header "Build/Codegen Tests ($BUILD_TEST_CMD)"
  if eval "$BUILD_TEST_CMD"; then
    record "Build/codegen" "pass"
  else
    record "Build/codegen" "fail"
  fi
else
  header "Build/Codegen Tests ($BUILD_TEST_CMD)"
  printf '%b! SKIPPED -- build prerequisite not available%b\n\n' "$YELLOW" "$RESET"
  record "Build/codegen" "skip"
fi

# ── Summary ─────────────────────────────────────────────────────────

header "Summary"

all_passed=true
skip_count=0

for i in "${!RESULT_NAMES[@]}"; do
  name="${RESULT_NAMES[$i]}"
  status="${RESULT_STATUSES[$i]}"
  case "$status" in
    pass) printf '  %bv %s: PASSED%b\n' "$GREEN" "$name" "$RESET" ;;
    fail) printf '  %bx %s: FAILED%b\n' "$RED" "$name" "$RESET"; all_passed=false ;;
    skip) printf '  %b! %s: SKIPPED%b\n' "$YELLOW" "$name" "$RESET"; ((skip_count++)) ;;
  esac
done

if (( skip_count > 0 )); then
  printf '\n%b  %d suite(s) skipped -- see above for how to enable them.%b\n' "$YELLOW" "$skip_count" "$RESET"
fi

echo ''

if $all_passed; then
  exit 0
else
  exit 1
fi
