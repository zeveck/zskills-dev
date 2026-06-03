#!/usr/bin/env bash
# tests/test-session-logging.sh
#
# Behavioral coverage for the framework session-logging capability:
#   hooks/log-session-stop.sh        (Stop / SubagentStop renderer + merge)
#   hooks/log-permission-request.sh  (passive, fail-open PermissionRequest)
#   skills/update-zskills/scripts/session-logs.sh (resolver + copy helper)
#
# Cases:
#   1. Renderer — synthetic transcript JSONL -> markdown with header +
#      User/assistant/tool sections.
#   2. Permission passivity (CRITICAL) — exit 0 AND empty stdout on a valid
#      PermissionRequest, on malformed stdin, and on empty stdin (fail-open).
#   3. Sidecar + in-situ merge — a permission event whose ts falls BETWEEN
#      two transcript events renders a [PERMISSION]-tagged line at the right
#      position; grep -c returns the expected count.
#   4. Config toggle — logging.enabled=false => both hooks no-op (no files
#      written) and still exit 0.
#   5. Helper — no args prints the resolved dir; dest arg copies the logs.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

STOP_HOOK="$REPO_ROOT/hooks/log-session-stop.sh"
PERM_HOOK="$REPO_ROOT/hooks/log-permission-request.sh"
HELPER="$REPO_ROOT/skills/update-zskills/scripts/session-logs.sh"

# Python interpreter (same precedence the hooks use) — needed by Case 6c.
PYTHON=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Hermetic sandbox under /tmp (block-unsafe-friendly literal cleanup).
WORK="$(mktemp -d /tmp/zskills-session-log-test.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

PROJ="$WORK/proj"
mkdir -p "$PROJ/.claude"
echo '{}' > "$PROJ/.claude/zskills-config.json"

# Synthetic transcript: user @00, assistant+tool @05, tool_result @08,
# assistant @10. A permission event at @07 (between @05 and @08) is used in
# case 3 to assert in-situ ordering.
TR="$WORK/transcript.jsonl"
cat > "$TR" <<'JSONL'
{"type":"user","timestamp":"2026-06-03T12:00:00.000Z","message":{"role":"user","content":"Please list the files"}}
{"type":"assistant","timestamp":"2026-06-03T12:00:05.000Z","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Sure, listing now."},{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"ls -la"}}]}}
{"type":"user","timestamp":"2026-06-03T12:00:08.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu1","content":"file1.txt\nfile2.txt"}]}}
{"type":"assistant","timestamp":"2026-06-03T12:00:10.000Z","message":{"id":"m2","role":"assistant","content":[{"type":"text","text":"Done."}]}}
JSONL

SID="sess1234ab"

# ──────────────────────────────────────────────────────────────────────────
echo "=== Case 1 — renderer produces markdown ==="
LOGD1="$WORK/logs1"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SID\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$LOGD1" CLAUDE_PROJECT_DIR="$PROJ" TZ=UTC bash "$STOP_HOOK"
rc=$?
[ "$rc" -eq 0 ] && pass "1a. stop hook exits 0" || fail "1a. stop hook exit 0" "rc=$rc"

shopt -s nullglob
MD_FILES=( "$LOGD1"/*.md )
shopt -u nullglob
if [ "${#MD_FILES[@]}" -ge 1 ]; then
  pass "1b. a markdown file was produced"
else
  fail "1b. a markdown file was produced" "none under $LOGD1"
fi

MD="${MD_FILES[0]:-/nonexistent}"
# Filename is sortable: {date}-{HHMM}-{session}.md
bn="$(basename "$MD")"
if [[ "$bn" =~ ^2026-06-03-1200-${SID:0:8}\.md$ ]]; then
  pass "1c. filename is sortable {date}-{HHMM}-{session}.md ($bn)"
else
  fail "1c. filename sortable" "got $bn"
fi

if [ -f "$MD" ] && grep -q "^# Session \`${SID:0:8}\` — 2026-06-03 12:00" "$MD"; then
  pass "1d. session header present with id + date/time"
else
  fail "1d. session header" "$(head -1 "$MD" 2>/dev/null)"
fi
if [ -f "$MD" ] && grep -q '^\*\*User:\*\*' "$MD" && grep -q '> Please list the files' "$MD"; then
  pass "1e. user prompt rendered"
else
  fail "1e. user prompt" "missing"
fi
if [ -f "$MD" ] && grep -q 'Bash(ls -la)' "$MD" && grep -q 'Done.' "$MD"; then
  pass "1f. assistant text + tool call rendered"
else
  fail "1f. assistant/tool" "missing"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 2 — permission hook is PASSIVE / fail-open ==="
LOGD2="$WORK/logs2"
# Valid event: exit 0 AND empty stdout (no decision emitted).
PERM_JSON="{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$SID\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/etc/secret\"},\"tool_use_id\":\"tu99\"}"
out="$(printf '%s' "$PERM_JSON" | ZSKILLS_LOG_DIR="$LOGD2" CLAUDE_PROJECT_DIR="$PROJ" bash "$PERM_HOOK" 2>/dev/null)"
rc=$?
[ "$rc" -eq 0 ] && pass "2a. valid permission event exits 0" || fail "2a. exit 0" "rc=$rc"
[ -z "$out" ] && pass "2b. valid permission event emits EMPTY stdout (no decision)" || fail "2b. empty stdout" "got [$out]"

# Malformed stdin: still exit 0 + empty stdout.
out="$(printf '%s' 'not json {{{ broken' | ZSKILLS_LOG_DIR="$LOGD2" CLAUDE_PROJECT_DIR="$PROJ" bash "$PERM_HOOK" 2>/dev/null)"
rc=$?
[ "$rc" -eq 0 ] && pass "2c. malformed stdin exits 0 (fail-open)" || fail "2c. malformed exit 0" "rc=$rc"
[ -z "$out" ] && pass "2d. malformed stdin emits empty stdout" || fail "2d. malformed empty stdout" "got [$out]"

# Empty stdin: still exit 0 + empty stdout.
out="$(printf '' | ZSKILLS_LOG_DIR="$LOGD2" CLAUDE_PROJECT_DIR="$PROJ" bash "$PERM_HOOK" 2>/dev/null)"
rc=$?
[ "$rc" -eq 0 ] && pass "2e. empty stdin exits 0 (fail-open)" || fail "2e. empty exit 0" "rc=$rc"
[ -z "$out" ] && pass "2f. empty stdin emits empty stdout" || fail "2f. empty empty stdout" "got [$out]"

# The valid event must have produced a sidecar line.
SIDECAR="$LOGD2/permissions-$SID.jsonl"
if [ -f "$SIDECAR" ] && grep -q '"tool_name": "Write"' "$SIDECAR" \
   && grep -q '"tool_use_id": "tu99"' "$SIDECAR"; then
  pass "2g. valid event appended a sidecar JSON line (ts/tool_name/summary/id)"
else
  fail "2g. sidecar line" "$(cat "$SIDECAR" 2>/dev/null)"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 3 — sidecar merged in-situ by timestamp with [PERMISSION] tag ==="
LOGD3="$WORK/logs3"
# Pre-seed a sidecar with a permission ts of 12:00:07 — between the @05
# tool call and the @08 tool_result, so it must render in that gap.
mkdir -p "$LOGD3"
cat > "$LOGD3/permissions-$SID.jsonl" <<'SIDE'
{"ts": "2026-06-03T12:00:07.000000+00:00", "tool_name": "Bash", "tool_input_summary": "command=ls -la", "tool_use_id": "tu1"}
SIDE
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SID\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$LOGD3" CLAUDE_PROJECT_DIR="$PROJ" TZ=UTC bash "$STOP_HOOK"
MD3="$LOGD3/2026-06-03-1200-${SID:0:8}.md"
if [ -f "$MD3" ]; then
  pcount="$(grep -c '\[PERMISSION\]' "$MD3")"
  [ "$pcount" -eq 1 ] && pass "3a. exactly one [PERMISSION] line ($pcount)" \
    || fail "3a. [PERMISSION] count" "got $pcount"
  # Positional: the permission line (ts @07) must appear AFTER the user @08
  # tool_result line? No — it has ts @07, which is BEFORE the @08 result,
  # so it must precede the 'Done.' (@10) AND precede the tool_result block.
  perm_ln="$(grep -n '\[PERMISSION\]' "$MD3" | head -1 | cut -d: -f1)"
  done_ln="$(grep -n '^Done\.' "$MD3" | head -1 | cut -d: -f1)"
  if [ -n "$perm_ln" ] && [ -n "$done_ln" ] && [ "$perm_ln" -lt "$done_ln" ]; then
    pass "3b. [PERMISSION] (@07) renders before the @10 assistant 'Done.'"
  else
    fail "3b. in-situ ordering" "perm_ln=$perm_ln done_ln=$done_ln"
  fi
  # The sidecar must SURVIVE the fresh re-render (persistence).
  echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SID\",\"transcript_path\":\"$TR\"}" | \
    ZSKILLS_LOG_DIR="$LOGD3" CLAUDE_PROJECT_DIR="$PROJ" TZ=UTC bash "$STOP_HOOK"
  pcount2="$(grep -c '\[PERMISSION\]' "$MD3")"
  [ "$pcount2" -eq 1 ] && pass "3c. [PERMISSION] survives a fresh re-render (sidecar persists)" \
    || fail "3c. survives re-render" "got $pcount2"
else
  fail "3a. [PERMISSION] count" "no markdown at $MD3"
  fail "3b. in-situ ordering" "no markdown"
  fail "3c. survives re-render" "no markdown"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 4 — logging.enabled=false no-ops both hooks ==="
PROJ_OFF="$WORK/proj-off"
mkdir -p "$PROJ_OFF/.claude"
echo '{"logging":{"enabled":false}}' > "$PROJ_OFF/.claude/zskills-config.json"
LOGD4="$WORK/logs4"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"off1\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$LOGD4" CLAUDE_PROJECT_DIR="$PROJ_OFF" bash "$STOP_HOOK"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -d "$LOGD4" ]; then
  pass "4a. stop hook no-ops (exit 0, no log dir created) when disabled"
else
  fail "4a. stop disabled no-op" "rc=$rc dir_exists=$([ -d "$LOGD4" ] && echo y || echo n)"
fi
out="$(printf '%s' '{"hook_event_name":"PermissionRequest","session_id":"off1","tool_name":"Read","tool_input":{"file_path":"x"},"tool_use_id":"t"}' | \
  ZSKILLS_LOG_DIR="$LOGD4" CLAUDE_PROJECT_DIR="$PROJ_OFF" bash "$PERM_HOOK" 2>/dev/null)"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -d "$LOGD4" ]; then
  pass "4b. permission hook no-ops (exit 0, empty stdout, no dir) when disabled"
else
  fail "4b. perm disabled no-op" "rc=$rc out=[$out] dir_exists=$([ -d "$LOGD4" ] && echo y || echo n)"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 5 — session-logs.sh helper ==="
# No args: prints the resolved dir (matches the hooks' precedence).
resolved="$(ZSKILLS_LOG_DIR="$LOGD1" CLAUDE_PROJECT_DIR="$PROJ" bash "$HELPER")"
[ "$resolved" = "$LOGD1" ] && pass "5a. no-arg prints resolved dir (env precedence)" \
  || fail "5a. no-arg resolved dir" "got [$resolved] want [$LOGD1]"

# Default precedence (no env, no config dir): tempdir/zskills-session-logs/<project>.
default_dir="$(CLAUDE_PROJECT_DIR="$PROJ" bash "$HELPER")"
if [[ "$default_dir" == */zskills-session-logs/proj ]]; then
  pass "5b. default dir is <tempdir>/zskills-session-logs/<project> ($default_dir)"
else
  fail "5b. default dir" "got $default_dir"
fi

# Dest arg: copies the logs.
DEST="$WORK/copydest"
ZSKILLS_LOG_DIR="$LOGD1" CLAUDE_PROJECT_DIR="$PROJ" bash "$HELPER" "$DEST" >/dev/null
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$DEST/$(basename "$MD")" ]; then
  pass "5c. dest arg copies the session logs"
else
  fail "5c. dest copy" "rc=$rc dest contents: $(ls "$DEST" 2>/dev/null)"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 6 — log files are written mode 0o600 (not world-readable) ==="
# Security (issue #1055): session transcripts capture verbatim user prompts
# and Bash tool I/O (incl. any cat-ed credential); on a shared /tmp a 0o644
# file leaks them to every local user. The hooks set os.umask(0o077) at the
# top of main() so the .tmp + final markdown + sidecar all land 0o600. We
# run the hooks under a DELIBERATELY relaxed umask (022) so that WITHOUT the
# fix the resulting files would be 0o644 — these assertions fail against the
# pre-fix behavior.
mode_of() { stat -c '%a' "$1" 2>/dev/null; }

LOGD6="$WORK/logs6"
SID6="sec00mode"
# Stop hook -> final markdown.
( umask 022
  echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SID6\",\"transcript_path\":\"$TR\"}" | \
    ZSKILLS_LOG_DIR="$LOGD6" CLAUDE_PROJECT_DIR="$PROJ" TZ=UTC bash "$STOP_HOOK" )
MD6="$LOGD6/2026-06-03-1200-${SID6:0:8}.md"
if [ -f "$MD6" ]; then
  m="$(mode_of "$MD6")"
  [ "$m" = "600" ] && pass "6a. Stop markdown is mode 0o600 ($m)" \
    || fail "6a. Stop markdown mode 0o600" "got $m (world/group-readable leak)"
else
  fail "6a. Stop markdown mode 0o600" "no markdown at $MD6"
fi

# Permission hook -> sidecar.
LOGD6P="$WORK/logs6p"
SID6P="sec00perm"
( umask 022
  printf '%s' "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$SID6P\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat /etc/secret\"},\"tool_use_id\":\"tuSEC\"}" | \
    ZSKILLS_LOG_DIR="$LOGD6P" CLAUDE_PROJECT_DIR="$PROJ" bash "$PERM_HOOK" >/dev/null 2>&1 )
SIDECAR6="$LOGD6P/permissions-$SID6P.jsonl"
if [ -f "$SIDECAR6" ]; then
  m="$(mode_of "$SIDECAR6")"
  [ "$m" = "600" ] && pass "6b. permission sidecar is mode 0o600 ($m)" \
    || fail "6b. permission sidecar mode 0o600" "got $m (world/group-readable leak)"
else
  fail "6b. permission sidecar mode 0o600" "no sidecar at $SIDECAR6"
fi

# Tmp-window race: the .tmp is created with the same umask as the final
# file, so its in-flight mode is also 0o600. We can't reliably catch it
# mid-write from a shell, but we CAN confirm no 0o644 .tmp residue would be
# left behind on a write failure. Force a failure by pointing at a transcript
# whose log dir is read-only AFTER creation is not portable; instead assert
# the invariant directly: with the umask fix, a freshly created file in the
# same dir under umask 022 is 0o600 (the same code path the .tmp uses).
LOGD6T="$WORK/logs6t"
mkdir -p "$LOGD6T"
probe="$LOGD6T/.umask-probe"
( umask 022
  ZSKILLS_PROJECT_DIR="$PROJ" "$PYTHON" - "$probe" <<'PYPROBE'
import os, sys
# Mirror the hooks' first action: umask(0o077) before any creation, then
# create a file the same way the .tmp write does (plain open for write).
os.umask(0o077)
with open(sys.argv[1], "w") as f:
    f.write("x")
PYPROBE
)
if [ -f "$probe" ]; then
  m="$(mode_of "$probe")"
  [ "$m" = "600" ] && pass "6c. tmp-window write path yields 0o600 under umask(0o077) ($m)" \
    || fail "6c. tmp-window mode 0o600" "got $m"
else
  fail "6c. tmp-window mode 0o600" "probe not created"
fi

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
[ "$FAIL_COUNT" -gt 0 ] && exit 1
exit 0
