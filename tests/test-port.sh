#!/bin/bash
# Tests for skills/update-zskills/scripts/port.sh
# Run from repo root: bash tests/test-port.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT_SCRIPT="$REPO_ROOT/skills/update-zskills/scripts/port.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  ((FAIL_COUNT++))
}

echo "=== port.sh tests ==="

# 1. Determinism: run 3 times, verify same output
run1=$(bash "$PORT_SCRIPT")
run2=$(bash "$PORT_SCRIPT")
run3=$(bash "$PORT_SCRIPT")
if [[ "$run1" == "$run2" && "$run2" == "$run3" ]]; then
  pass "deterministic output ($run1)"
else
  fail "non-deterministic: got $run1, $run2, $run3"
fi

# 2. DEV_PORT override
override=$(DEV_PORT=3000 bash "$PORT_SCRIPT")
if [[ "$override" == "3000" ]]; then
  pass "DEV_PORT override (3000)"
else
  fail "DEV_PORT override — expected 3000, got $override"
fi

# 3. Port range: output should be between 9000-60000 (unless DEV_PORT set)
port=$(bash "$PORT_SCRIPT")
if [[ "$port" -ge 9000 && "$port" -le 60000 ]]; then
  pass "port in range 9000-60000 ($port)"
else
  # Could be 8080 if MAIN_REPO matches — that's also valid
  if [[ "$port" == "8080" ]]; then
    pass "port is default 8080 (main repo match)"
  else
    fail "port out of range — got $port"
  fi
fi

# 4. Numeric output
if [[ "$port" =~ ^[0-9]+$ ]]; then
  pass "numeric output ($port)"
else
  fail "non-numeric output: $port"
fi

# ─── Consumer dev-port.sh stub-callout cases ───
# Each case sets up a fake project root with .claude/skills/update-zskills/
# scripts/zskills-stub-lib.sh sourced from the repo, optionally a
# scripts/dev-port.sh stub, then runs port.sh with that root and
# CLAUDE_PROJECT_DIR set so the callout activates.

STUB_LIB_SRC="$REPO_ROOT/skills/update-zskills/scripts/zskills-stub-lib.sh"

setup_stub_project() {
  # $1 = stub body (or empty for no stub); $2 = "exec" or "noexec"
  local body="$1"
  local mode="${2:-exec}"
  local d
  d=$(mktemp -d)
  (
    cd "$d"
    git init -q
    git config user.email "t@t" >/dev/null
    git config user.name "t" >/dev/null
    git commit -q --allow-empty -m init
  )
  mkdir -p "$d/.claude/skills/update-zskills/scripts"
  cp "$STUB_LIB_SRC" "$d/.claude/skills/update-zskills/scripts/zskills-stub-lib.sh"
  if [ -n "$body" ]; then
    mkdir -p "$d/scripts"
    printf '%s\n' "$body" > "$d/scripts/dev-port.sh"
    if [ "$mode" = "exec" ]; then
      chmod +x "$d/scripts/dev-port.sh"
    fi
  fi
  printf '%s\n' "$d"
}

# 5. stub-absent → built-in algorithm runs (worktree-hash range or 8080)
proj=$(setup_stub_project "" exec)
out=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$PORT_SCRIPT" 2>/dev/null)
if [[ "$out" =~ ^[0-9]+$ ]] && { [[ "$out" -ge 9000 && "$out" -le 60000 ]] || [[ "$out" == "8080" ]]; }; then
  pass "stub-absent → built-in algorithm runs ($out)"
else
  fail "stub-absent → expected built-in port, got '$out'"
fi
rm -rf "$proj"

# 6. stub-returns-numeric → output is the stub's port
proj=$(setup_stub_project "#!/bin/bash
echo 12345
exit 0" exec)
out=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$PORT_SCRIPT" 2>/dev/null)
if [[ "$out" == "12345" ]]; then
  pass "stub-returns-numeric → 12345"
else
  fail "stub-returns-numeric — expected 12345, got '$out'"
fi
rm -rf "$proj"

# 7. stub-returns-empty → falls through to built-in
proj=$(setup_stub_project "#!/bin/bash
exit 0" exec)
out=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$PORT_SCRIPT" 2>/dev/null)
if [[ "$out" =~ ^[0-9]+$ ]] && { [[ "$out" -ge 9000 && "$out" -le 60000 ]] || [[ "$out" == "8080" ]]; }; then
  pass "stub-returns-empty → built-in ($out)"
else
  fail "stub-returns-empty — expected built-in port, got '$out'"
fi
rm -rf "$proj"

# 8. stub-returns-non-numeric → built-in, stderr matches
proj=$(setup_stub_project "#!/bin/bash
echo notaport
exit 0" exec)
err_file=$(mktemp)
out=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$PORT_SCRIPT" 2>"$err_file")
err=$(cat "$err_file")
rm -f "$err_file"
if [[ "$out" =~ ^[0-9]+$ ]] && { [[ "$out" -ge 9000 && "$out" -le 60000 ]] || [[ "$out" == "8080" ]]; }; then
  if [[ "$err" == *"non-numeric"* ]]; then
    pass "stub-returns-non-numeric → built-in + stderr warning"
  else
    fail "stub-returns-non-numeric — port ok ($out) but stderr missing 'non-numeric': $err"
  fi
else
  fail "stub-returns-non-numeric — expected built-in port, got '$out'"
fi
rm -rf "$proj"

# 9. stub-non-executable → built-in, stderr matches "present but not executable"
proj=$(setup_stub_project "#!/bin/bash
echo 7777" noexec)
err_file=$(mktemp)
out=$(cd "$proj" && CLAUDE_PROJECT_DIR="$proj" bash "$PORT_SCRIPT" 2>"$err_file")
err=$(cat "$err_file")
rm -f "$err_file"
if [[ "$out" =~ ^[0-9]+$ ]] && { [[ "$out" -ge 9000 && "$out" -le 60000 ]] || [[ "$out" == "8080" ]]; }; then
  if [[ "$err" == *"present but not executable"* ]]; then
    pass "stub-non-executable → built-in + stderr warning"
  else
    fail "stub-non-executable — port ok ($out) but stderr missing 'present but not executable': $err"
  fi
else
  fail "stub-non-executable — expected built-in port, got '$out'"
fi
rm -rf "$proj"

# 10. DEV_PORT env var still wins when stub also present (sanity).
proj=$(setup_stub_project "#!/bin/bash
echo 12345
exit 0" exec)
out=$(cd "$proj" && DEV_PORT=4242 CLAUDE_PROJECT_DIR="$proj" bash "$PORT_SCRIPT" 2>/dev/null)
if [[ "$out" == "4242" ]]; then
  pass "DEV_PORT wins over stub (4242)"
else
  fail "DEV_PORT vs stub — expected 4242, got '$out'"
fi
rm -rf "$proj"

# ─── Fixture-based runtime-config-read cases ───
# Verify PROJECT_ROOT env override + tightened regex + fail-loud guard.

# 11. Fixture with default_port: 7777 — verifies PROJECT_ROOT override + configured value
FIXTURE=/tmp/zskills-port-fixture
rm -rf "$FIXTURE" && mkdir -p "$FIXTURE/.claude"
cat > "$FIXTURE/.claude/zskills-config.json" <<JSON
{"dev_server": {"main_repo_path": "$FIXTURE", "default_port": 7777}}
JSON
out=$(REPO_ROOT="$FIXTURE" PROJECT_ROOT="$FIXTURE" bash "$PORT_SCRIPT")
if [[ "$out" == "7777" ]]; then
  pass "fixture default_port → 7777"
else
  fail "fixture default_port — expected 7777, got $out"
fi
rm -rf "$FIXTURE"

# 12. Fixture WITHOUT default_port field — verifies fail-loud
FIXTURE=/tmp/zskills-port-fixture-absent
rm -rf "$FIXTURE" && mkdir -p "$FIXTURE/.claude"
cat > "$FIXTURE/.claude/zskills-config.json" <<JSON
{"dev_server": {"main_repo_path": "$FIXTURE"}}
JSON
err=$(REPO_ROOT="$FIXTURE" PROJECT_ROOT="$FIXTURE" bash "$PORT_SCRIPT" 2>&1 >/dev/null)
rc=$?
if [[ $rc -ne 0 ]] && [[ "$err" == *"default_port"* ]] && [[ "$err" == *"$FIXTURE/.claude/zskills-config.json"* ]]; then
  pass "fail-loud when default_port absent"
else
  fail "fail-loud expected non-zero exit + stderr with 'default_port' + absolute config path; rc=$rc err=$err"
fi
rm -rf "$FIXTURE"

# 13. Fixture with default_port nested inside a sub-object — verifies tightened regex refuses traversal
# NOTE: main_repo_path is placed BEFORE the nested "limits" object so the (still-loose) main_repo_path
# regex matches; default_port appears only inside "limits", so the tight [^{}]* regex must NOT match,
# leaving DEFAULT_PORT="" and triggering fail-loud in the main-repo branch.
FIXTURE=/tmp/zskills-port-fixture-nested
rm -rf "$FIXTURE" && mkdir -p "$FIXTURE/.claude"
cat > "$FIXTURE/.claude/zskills-config.json" <<JSON
{"dev_server": {"main_repo_path": "$FIXTURE", "limits": {"default_port": 9999}}}
JSON
# default_port appears only inside nested "limits" object → tight regex must NOT match
err=$(REPO_ROOT="$FIXTURE" PROJECT_ROOT="$FIXTURE" bash "$PORT_SCRIPT" 2>&1 >/dev/null)
rc=$?
if [[ $rc -ne 0 ]]; then
  pass "tight-regex refuses nested-only default_port (fail-loud fired)"
else
  fail "tight-regex test expected fail-loud (nested-only default_port should NOT match); rc=$rc"
fi
rm -rf "$FIXTURE"

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
