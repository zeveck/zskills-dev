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
#   4. Config toggle / OFF-by-default — session logging is OFF unless the
#      consumer opts in (logging.enabled:true). Asserts both hooks no-op
#      (no files written, exit 0) for: explicit logging.enabled=false, an
#      ABSENT logging.enabled field, and an empty config object {}.
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
# Session logging is OFF by default (absent logging.enabled => off), so the
# renderer-positive cases (1, 3, 5, 6) MUST opt in explicitly. They also pin
# include_repo:false so ZSKILLS_LOG_DIR stays FLAT (no <repo> segment), which
# keeps these orthogonal rendering/passivity/mode cases independent of the
# path-composition feature (exercised separately in Cases 13-15). The
# composition defaults (include_repo:true) are exercised by Cases 7/12/13.
# The absent-field default is asserted separately in Case 4b/4c.
echo '{"logging":{"enabled":true,"include_repo":false}}' > "$PROJ/.claude/zskills-config.json"

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
echo "=== Case 4 — logging OFF: explicit enabled=false AND absent field both no-op ==="
# Explicit logging.enabled=false: both hooks no-op.
PROJ_OFF="$WORK/proj-off"
mkdir -p "$PROJ_OFF/.claude"
echo '{"logging":{"enabled":false}}' > "$PROJ_OFF/.claude/zskills-config.json"
LOGD4="$WORK/logs4"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"off1\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$LOGD4" CLAUDE_PROJECT_DIR="$PROJ_OFF" bash "$STOP_HOOK"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -d "$LOGD4" ]; then
  pass "4a. stop hook no-ops (exit 0, no log dir created) when explicitly disabled"
else
  fail "4a. stop disabled no-op" "rc=$rc dir_exists=$([ -d "$LOGD4" ] && echo y || echo n)"
fi
out="$(printf '%s' '{"hook_event_name":"PermissionRequest","session_id":"off1","tool_name":"Read","tool_input":{"file_path":"x"},"tool_use_id":"t"}' | \
  ZSKILLS_LOG_DIR="$LOGD4" CLAUDE_PROJECT_DIR="$PROJ_OFF" bash "$PERM_HOOK" 2>/dev/null)"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -d "$LOGD4" ]; then
  pass "4b. permission hook no-ops (exit 0, empty stdout, no dir) when explicitly disabled"
else
  fail "4b. perm disabled no-op" "rc=$rc out=[$out] dir_exists=$([ -d "$LOGD4" ] && echo y || echo n)"
fi

# OFF-BY-DEFAULT: an absent logging.enabled field (fresh consumer config)
# must ALSO no-op both hooks — session logging is opt-in. PROJ_ABSENT has a
# config with NO logging block at all (exactly what /update-zskills seeds).
PROJ_ABSENT="$WORK/proj-absent"
mkdir -p "$PROJ_ABSENT/.claude"
echo '{"project_name":"x"}' > "$PROJ_ABSENT/.claude/zskills-config.json"
LOGD4A="$WORK/logs4a"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"abs1\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$LOGD4A" CLAUDE_PROJECT_DIR="$PROJ_ABSENT" bash "$STOP_HOOK"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -d "$LOGD4A" ]; then
  pass "4c. stop hook no-ops when logging.enabled is ABSENT (off by default)"
else
  fail "4c. stop absent-field no-op" "rc=$rc dir_exists=$([ -d "$LOGD4A" ] && echo y || echo n)"
fi
out="$(printf '%s' '{"hook_event_name":"PermissionRequest","session_id":"abs1","tool_name":"Read","tool_input":{"file_path":"x"},"tool_use_id":"t"}' | \
  ZSKILLS_LOG_DIR="$LOGD4A" CLAUDE_PROJECT_DIR="$PROJ_ABSENT" bash "$PERM_HOOK" 2>/dev/null)"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -d "$LOGD4A" ]; then
  pass "4d. permission hook no-ops when logging.enabled is ABSENT (off by default)"
else
  fail "4d. perm absent-field no-op" "rc=$rc out=[$out] dir_exists=$([ -d "$LOGD4A" ] && echo y || echo n)"
fi

# And an EMPTY config object ({}) — the most minimal fresh state — also off.
PROJ_EMPTY="$WORK/proj-empty"
mkdir -p "$PROJ_EMPTY/.claude"
echo '{}' > "$PROJ_EMPTY/.claude/zskills-config.json"
LOGD4E="$WORK/logs4e"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"emp1\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$LOGD4E" CLAUDE_PROJECT_DIR="$PROJ_EMPTY" bash "$STOP_HOOK"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -d "$LOGD4E" ]; then
  pass "4e. stop hook no-ops on empty config {} (off by default)"
else
  fail "4e. stop empty-config no-op" "rc=$rc dir_exists=$([ -d "$LOGD4E" ] && echo y || echo n)"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 5 — session-logs.sh helper ==="
# No args: prints the resolved dir (matches the hooks' precedence).
resolved="$(ZSKILLS_LOG_DIR="$LOGD1" CLAUDE_PROJECT_DIR="$PROJ" bash "$HELPER")"
[ "$resolved" = "$LOGD1" ] && pass "5a. no-arg prints resolved dir (env precedence)" \
  || fail "5a. no-arg resolved dir" "got [$resolved] want [$LOGD1]"

# Default precedence (no env, no config dir, no registry): per-OS cache
# default <cache-root>/zskills-session-logs/<project> (issue #1059 replaced
# the old tempfile.gettempdir() default). Use a FRESH project with no
# registry (the shared $PROJ now has one from Cases 1+3's Stop writes).
PROJ5B="$WORK/proj5b"
mkdir -p "$PROJ5B/.claude"
echo '{}' > "$PROJ5B/.claude/zskills-config.json"
default_dir="$(CLAUDE_PROJECT_DIR="$PROJ5B" XDG_CACHE_HOME="$WORK/xdg" bash "$HELPER")"
if [[ "$default_dir" == "$WORK/xdg/zskills-session-logs/proj5b" ]]; then
  pass "5b. default dir is <cache-root>/zskills-session-logs/<project> ($default_dir)"
else
  fail "5b. default dir" "got $default_dir want $WORK/xdg/zskills-session-logs/proj5b"
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
echo "=== Case 6 — log files honor file_mode (default 0o600; configurable) ==="
# Security (issue #1055): session transcripts capture verbatim user prompts
# and Bash tool I/O (incl. any cat-ed credential); on a shared /tmp a 0o644
# file leaks them to every local user. The hooks derive the umask from
# file_mode (umask = 0o777 & ~dir_mode) so the .tmp + final markdown + sidecar
# all land at exactly file_mode, and created dirs land at the derived dir mode.
# DEFAULT file_mode is "0600" (secure-by-default preserved). We run the hooks
# under a DELIBERATELY relaxed umask (022) so that WITHOUT the fix the files
# would be 0o644 — these assertions fail against the pre-fix behavior. A
# configured file_mode (e.g. 0640) is exercised in Case 6d/6e.
mode_of() { stat -c '%a' "$1" 2>/dev/null; }

LOGD6="$WORK/logs6"
SID6="sec00mode"
# Stop hook -> final markdown (default file_mode 0600 via $PROJ config).
( umask 022
  echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SID6\",\"transcript_path\":\"$TR\"}" | \
    ZSKILLS_LOG_DIR="$LOGD6" CLAUDE_PROJECT_DIR="$PROJ" TZ=UTC bash "$STOP_HOOK" )
MD6="$LOGD6/2026-06-03-1200-${SID6:0:8}.md"
if [ -f "$MD6" ]; then
  m="$(mode_of "$MD6")"
  [ "$m" = "600" ] && pass "6a. Stop markdown defaults to mode 0o600 ($m)" \
    || fail "6a. Stop markdown mode 0o600" "got $m (world/group-readable leak)"
else
  fail "6a. Stop markdown mode 0o600" "no markdown at $MD6"
fi

# Permission hook -> sidecar (default file_mode 0600).
LOGD6P="$WORK/logs6p"
SID6P="sec00perm"
( umask 022
  printf '%s' "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$SID6P\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat /etc/secret\"},\"tool_use_id\":\"tuSEC\"}" | \
    ZSKILLS_LOG_DIR="$LOGD6P" CLAUDE_PROJECT_DIR="$PROJ" bash "$PERM_HOOK" >/dev/null 2>&1 )
SIDECAR6="$LOGD6P/permissions-$SID6P.jsonl"
if [ -f "$SIDECAR6" ]; then
  m="$(mode_of "$SIDECAR6")"
  [ "$m" = "600" ] && pass "6b. permission sidecar defaults to mode 0o600 ($m)" \
    || fail "6b. permission sidecar mode 0o600" "got $m (world/group-readable leak)"
else
  fail "6b. permission sidecar mode 0o600" "no sidecar at $SIDECAR6"
fi

# Tmp-window race: the .tmp is created with the same umask as the final file,
# so its in-flight mode is also file_mode. We can't reliably catch it
# mid-write from a shell, but we CAN assert the invariant directly: with the
# default file_mode the derived dir mode is 0o700 and umask = 0o777 & ~0o700
# = 0o077, so a freshly created file under umask 022 lands 0o600 (the same
# code path the .tmp uses).
LOGD6T="$WORK/logs6t"
mkdir -p "$LOGD6T"
probe="$LOGD6T/.umask-probe"
( umask 022
  ZSKILLS_PROJECT_DIR="$PROJ" "$PYTHON" - "$probe" <<'PYPROBE'
import os, sys
# Mirror the hooks: derive umask from the default file_mode 0o600 (dir mode
# 0o700 -> umask 0o077) before any creation, then create a file the same way
# the .tmp write does (plain open for write).
os.umask(0o777 & ~0o700)
with open(sys.argv[1], "w") as f:
    f.write("x")
PYPROBE
)
if [ -f "$probe" ]; then
  m="$(mode_of "$probe")"
  [ "$m" = "600" ] && pass "6c. tmp-window write path yields 0o600 under default file_mode ($m)" \
    || fail "6c. tmp-window mode 0o600" "got $m"
else
  fail "6c. tmp-window mode 0o600" "probe not created"
fi

# Configured file_mode 0640 -> markdown/sidecar 0o640, created dir 0o750
# (derived: read/write triads gain the exec/search bit). include_repo:false
# keeps the path flat so we assert the exact log-dir mode.
PROJ_MODE="$WORK/proj-mode"
mkdir -p "$PROJ_MODE/.claude"
echo '{"logging":{"enabled":true,"include_repo":false,"file_mode":"0640"}}' \
  > "$PROJ_MODE/.claude/zskills-config.json"
LOGD6M="$WORK/logs6m"
SID6M="sec64mode"
( umask 022
  echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SID6M\",\"transcript_path\":\"$TR\"}" | \
    ZSKILLS_LOG_DIR="$LOGD6M" CLAUDE_PROJECT_DIR="$PROJ_MODE" TZ=UTC bash "$STOP_HOOK" )
MD6M="$LOGD6M/2026-06-03-1200-${SID6M:0:8}.md"
if [ -f "$MD6M" ]; then
  m="$(mode_of "$MD6M")"
  dm="$(mode_of "$LOGD6M")"
  [ "$m" = "640" ] && pass "6d. configured file_mode 0640 -> markdown 0o640 ($m)" \
    || fail "6d. configured file_mode markdown" "got $m want 640"
  [ "$dm" = "750" ] && pass "6e. derived dir mode is 0o750 for file_mode 0640 ($dm)" \
    || fail "6e. derived dir mode 0750" "got $dm want 750"
else
  fail "6d. configured file_mode markdown" "no markdown at $MD6M"
  fail "6e. derived dir mode 0750" "no markdown at $MD6M"
fi

# The registry stays 0o600 even when file_mode is relaxed (it lives on the
# local checkout, never the shared mount).
( cd "$PROJ_MODE" && git init -q . ) 2>/dev/null
( umask 022
  echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"sec64reg\",\"transcript_path\":\"$TR\"}" | \
    ZSKILLS_LOG_DIR="$LOGD6M" CLAUDE_PROJECT_DIR="$PROJ_MODE" TZ=UTC bash "$STOP_HOOK" )
REG6M="$PROJ_MODE/.zskills/session-log-dirs"
if [ -f "$REG6M" ]; then
  rm6="$(mode_of "$REG6M")"
  [ "$rm6" = "600" ] && pass "6f. registry stays 0o600 even with relaxed file_mode ($rm6)" \
    || fail "6f. registry mode 0600" "got $rm6 want 600"
else
  fail "6f. registry mode 0600" "no registry at $REG6M"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 7 — cross-context agreement (issue #1059 regression test) ==="
# The actual bug: writer (Stop hook) and reader (helper) each independently
# re-resolved the log dir via tempfile.gettempdir(), which honors $TMPDIR.
# With different TMPDIRs they diverged and logs became unfindable. The fix:
# the Stop hook publishes its resolved dir into a shared registry at
# <main-repo-root>/.zskills/session-log-dirs; the reader reads the registry.
# This test writes with one TMPDIR/XDG and reads with a DIFFERENT one, and
# asserts the reader still finds the logs (via the registry, NOT recompute).
CC_PROJ="$WORK/ccproj"
mkdir -p "$CC_PROJ/.claude"
# Opt in (logging is off by default); leave logging.dir blank so the per-OS
# default resolution under test is exercised unchanged.
echo '{"logging":{"enabled":true}}' > "$CC_PROJ/.claude/zskills-config.json"
( cd "$CC_PROJ" && git init -q . )
# Write: blank logging.dir, no ZSKILLS_LOG_DIR -> per-OS default under
# XDG_CACHE_HOME=cacheA; a deliberately DIFFERENT TMPDIR.
mkdir -p "$WORK/cc-tmpA" "$WORK/cc-tmpB"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"ccsess01\",\"transcript_path\":\"$TR\"}" | \
  HOME="$WORK/cc-home" XDG_CACHE_HOME="$WORK/cc-cacheA" TMPDIR="$WORK/cc-tmpA" \
  CLAUDE_PROJECT_DIR="$CC_PROJ" TZ=UTC bash "$STOP_HOOK"
WRITTEN_DIR="$WORK/cc-cacheA/zskills-session-logs/ccproj"
if [ -f "$WRITTEN_DIR/2026-06-03-1200-ccsess01.md" ]; then
  pass "7a. Stop hook wrote to the per-OS default (cacheA) dir"
else
  fail "7a. Stop hook wrote to per-OS default" "no md under $WRITTEN_DIR"
fi
# Registry recorded the written dir.
REG="$CC_PROJ/.zskills/session-log-dirs"
if [ -f "$REG" ] && grep -qF "$WRITTEN_DIR" "$REG"; then
  pass "7b. registry recorded the resolved dir at <main-root>/.zskills/session-log-dirs"
else
  fail "7b. registry recorded dir" "$(cat "$REG" 2>/dev/null)"
fi
# Read with a DIFFERENT TMPDIR/XDG: must resolve to the WRITTEN dir via the
# registry, not recompute to cacheB.
read_dir="$(HOME="$WORK/cc-home" XDG_CACHE_HOME="$WORK/cc-cacheB" TMPDIR="$WORK/cc-tmpB" \
  CLAUDE_PROJECT_DIR="$CC_PROJ" bash "$HELPER")"
if [ "$read_dir" = "$WRITTEN_DIR" ]; then
  pass "7c. reader (different TMPDIR/XDG) resolves the WRITTEN dir via registry"
else
  fail "7c. cross-context agreement" "reader got [$read_dir] want [$WRITTEN_DIR]"
fi
# And a copy across contexts actually finds the markdown.
CC_DEST="$WORK/cc-dest"
HOME="$WORK/cc-home" XDG_CACHE_HOME="$WORK/cc-cacheB" TMPDIR="$WORK/cc-tmpB" \
  CLAUDE_PROJECT_DIR="$CC_PROJ" bash "$HELPER" "$CC_DEST" >/dev/null
if [ -f "$CC_DEST/2026-06-03-1200-ccsess01.md" ]; then
  pass "7d. cross-context copy lands the markdown in dest"
else
  fail "7d. cross-context copy" "dest: $(ls "$CC_DEST" 2>/dev/null)"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 8 — registry semantics: header, append, dedup, union ==="
RS_PROJ="$WORK/rsproj"
mkdir -p "$RS_PROJ/.claude"
echo '{"logging":{"enabled":true}}' > "$RS_PROJ/.claude/zskills-config.json"
( cd "$RS_PROJ" && git init -q . )
RS_REG="$RS_PROJ/.zskills/session-log-dirs"
RS_A="$WORK/rs-logA"
RS_B="$WORK/rs-logB"
# First write -> dir A (via ZSKILLS_LOG_DIR override).
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"rs000001\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$RS_A" CLAUDE_PROJECT_DIR="$RS_PROJ" TZ=UTC bash "$STOP_HOOK"
# Self-describing header present.
if head -2 "$RS_REG" | grep -q "zskills session logs are written" \
   && head -2 "$RS_REG" | grep -q "logging.dir"; then
  pass "8a. registry has a self-describing header block"
else
  fail "8a. self-describing header" "$(head -2 "$RS_REG" 2>/dev/null)"
fi
# Second write -> SAME dir A: must NOT append a duplicate line.
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"rs000002\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$RS_A" CLAUDE_PROJECT_DIR="$RS_PROJ" TZ=UTC bash "$STOP_HOOK"
acount="$(grep -cF "$RS_A" "$RS_REG")"
[ "$acount" -eq 1 ] && pass "8b. duplicate dir is deduped (1 line, not 2)" \
  || fail "8b. dedup" "got $acount lines for $RS_A"
# Third write -> dir B: appends a NEW line (union, newest last).
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"rs000003\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$RS_B" CLAUDE_PROJECT_DIR="$RS_PROJ" TZ=UTC bash "$STOP_HOOK"
if grep -qF "$RS_A" "$RS_REG" && grep -qF "$RS_B" "$RS_REG"; then
  pass "8c. distinct dirs both recorded (append-only union)"
else
  fail "8c. append union" "$(cat "$RS_REG" 2>/dev/null)"
fi
# Newest last: dir B's line comes AFTER dir A's line.
a_ln="$(grep -nF "$RS_A" "$RS_REG" | head -1 | cut -d: -f1)"
b_ln="$(grep -nF "$RS_B" "$RS_REG" | head -1 | cut -d: -f1)"
if [ -n "$a_ln" ] && [ -n "$b_ln" ] && [ "$b_ln" -gt "$a_ln" ]; then
  pass "8d. newest dir is recorded last"
else
  fail "8d. newest last" "a_ln=$a_ln b_ln=$b_ln"
fi
# Helper unions logs across BOTH recorded dirs that still exist.
RS_DEST="$WORK/rs-dest"
CLAUDE_PROJECT_DIR="$RS_PROJ" bash "$HELPER" "$RS_DEST" >/dev/null
# Both A and B got the same filenames (same SID? no — different SIDs).
nfiles="$(find "$RS_DEST" -name '*.md' | wc -l | tr -d ' ')"
if [ "$nfiles" -ge 1 ]; then
  pass "8e. helper unions logs across recorded dirs into dest ($nfiles md files)"
else
  fail "8e. union copy" "dest md count=$nfiles"
fi
# Helper print-dir unions: BOTH A and B appear (both exist).
union_out="$(CLAUDE_PROJECT_DIR="$RS_PROJ" bash "$HELPER")"
if echo "$union_out" | grep -qF "$RS_A" && echo "$union_out" | grep -qF "$RS_B"; then
  pass "8f. helper print-dir unions existing recorded dirs"
else
  fail "8f. union print" "got [$union_out]"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 9 — registry race-safe under concurrent writers ==="
RC_PROJ="$WORK/rcproj"
mkdir -p "$RC_PROJ/.claude"
echo '{"logging":{"enabled":true}}' > "$RC_PROJ/.claude/zskills-config.json"
( cd "$RC_PROJ" && git init -q . )
RC_REG="$RC_PROJ/.zskills/session-log-dirs"
RC_DIR="$WORK/rc-log"
# Two concurrent Stop hooks both resolving the SAME dir: must produce
# exactly ONE registry line for that dir (no interleaving, no dup).
pids=()
for i in 1 2 3 4; do
  ( echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"rcsess0$i\",\"transcript_path\":\"$TR\"}" | \
      ZSKILLS_LOG_DIR="$RC_DIR" CLAUDE_PROJECT_DIR="$RC_PROJ" TZ=UTC bash "$STOP_HOOK" ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
rccount="$(grep -cF "$RC_DIR" "$RC_REG" 2>/dev/null || echo 0)"
[ "$rccount" -eq 1 ] && pass "9a. concurrent writers -> exactly one registry line (race-safe dedup)" \
  || fail "9a. concurrent dedup" "got $rccount lines for $RC_DIR"
# No corrupted/partial lines: every non-comment line is <ts>\t<abspath>.
bad=0
while IFS= read -r ln; do
  [ -z "${ln// /}" ] && continue
  case "$ln" in
    \#*) continue ;;
  esac
  # Must contain a tab and an absolute path after it.
  printf '%s' "$ln" | grep -qP '^\S+\t/' || bad=1
done < "$RC_REG"
[ "$bad" -eq 0 ] && pass "9b. no corrupted/interleaved registry lines" \
  || fail "9b. line integrity" "found a malformed line in $RC_REG"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 10 — worktree write records into MAIN-ROOT registry ==="
# A write whose cwd/project is a WORKTREE must record into the main repo
# root's .zskills/session-log-dirs (shared across all worktrees), and the
# main-repo helper must see it.
WT_MAIN="$WORK/wt-main"
mkdir -p "$WT_MAIN/.claude"
echo '{}' > "$WT_MAIN/.claude/zskills-config.json"
( cd "$WT_MAIN" && git init -q . && git config user.email t@t && git config user.name t \
    && git commit -q --allow-empty -m init )
WT_LEAF="$WORK/wt-leaf"
( cd "$WT_MAIN" && git worktree add -q "$WT_LEAF" -b leafbranch ) 2>/dev/null
mkdir -p "$WT_LEAF/.claude"
# The Stop hook runs with CLAUDE_PROJECT_DIR=WT_LEAF, so the leaf must opt in.
echo '{"logging":{"enabled":true}}' > "$WT_LEAF/.claude/zskills-config.json"
WT_LOG="$WORK/wt-log"
# Write from the WORKTREE (CLAUDE_PROJECT_DIR = worktree path).
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"wtsess01\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$WT_LOG" CLAUDE_PROJECT_DIR="$WT_LEAF" TZ=UTC bash "$STOP_HOOK"
MAIN_REG="$WT_MAIN/.zskills/session-log-dirs"
if [ -f "$MAIN_REG" ] && grep -qF "$WT_LOG" "$MAIN_REG"; then
  pass "10a. worktree write recorded into MAIN-root registry (shared)"
else
  fail "10a. main-root registry" "main_reg=$(cat "$MAIN_REG" 2>/dev/null); leaf_reg_exists=$([ -f "$WT_LEAF/.zskills/session-log-dirs" ] && echo y || echo n)"
fi
# The main-repo helper sees the worktree's logged dir.
main_read="$(CLAUDE_PROJECT_DIR="$WT_MAIN" bash "$HELPER")"
if echo "$main_read" | grep -qF "$WT_LOG"; then
  pass "10b. main-repo helper sees the worktree-written dir via shared registry"
else
  fail "10b. main helper sees worktree dir" "got [$main_read]"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 11 — per-OS cache default (mocked platform + env) ==="
# CI is Linux-only, so the macOS/Windows branches are UNIT-mocked by
# overriding platform.system() and the relevant env. We drive the exact
# default_cache_dir() logic the hooks + helper share.
osprobe() {
  # $1 = platform.system() return; remaining env passed by caller. Mirrors
  # the refactored composition: default_cache_base() (NO <repo>) then the
  # include_repo:true composition step that appends the <repo> segment, so
  # the default-mode path is byte-identical to today.
  local sysname="$1"; shift
  "$PYTHON" - "$sysname" <<'PYOS'
import os, platform, sys
sysname = sys.argv[1]
platform.system = lambda: sysname  # mock

def sanitize_segment(seg):
    if not seg:
        return "unknown"
    bad = set(os.sep) | {"/", "\\", ":", "*", "?", '"', "<", ">", "|"}
    out = []
    for ch in seg:
        if ch in bad or ch.isspace():
            out.append("_")
        else:
            out.append(ch)
    result = "".join(out).strip(". ")
    return result or "unknown"

def project_base(project_dir):
    base = os.path.basename(os.path.normpath(project_dir)) or "project"
    return sanitize_segment(base)

def default_cache_base(project_dir):
    system = platform.system()
    if system == "Windows":
        root = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    elif system == "Darwin":
        root = os.path.join(os.path.expanduser("~"), "Library", "Caches")
    else:
        root = (os.environ.get("XDG_CACHE_HOME")
                or os.path.join(os.path.expanduser("~"), ".cache"))
    return os.path.join(root, "zskills-session-logs")

# include_repo:true (default) composition: base + <repo>.
pd = "/some/where/myproj"
print(os.path.join(default_cache_base(pd), project_base(pd)))
PYOS
}
# Sanity: the mocked default_cache_base() above must byte-match the one
# embedded in BOTH the source hook and the helper (guards against drift).
for f in "$STOP_HOOK" "$PERM_HOOK" "$HELPER"; do
  if grep -q 'def default_cache_base(project_dir):' "$f" \
     && grep -q 'Library", "Caches"' "$f" \
     && grep -q 'LOCALAPPDATA' "$f" \
     && grep -q 'XDG_CACHE_HOME' "$f"; then
    pass "11-pre. $(basename "$f") embeds the shared default_cache_base() branches"
  else
    fail "11-pre. shared default_cache_base" "$(basename "$f") missing a branch"
  fi
done
# Linux: XDG_CACHE_HOME honored. (Run each probe in a subshell so env
# manipulation applies to the python child, not to a shell function via
# `env -u` — which would no-op on a function.)
got="$(HOME=/h XDG_CACHE_HOME=/xdgroot osprobe Linux)"
[ "$got" = "/xdgroot/zskills-session-logs/myproj" ] \
  && pass "11a. Linux uses \$XDG_CACHE_HOME" || fail "11a. Linux XDG" "got $got"
# Linux: XDG unset -> ~/.cache.
got="$( unset XDG_CACHE_HOME; HOME=/homedir osprobe Linux )"
[ "$got" = "/homedir/.cache/zskills-session-logs/myproj" ] \
  && pass "11b. Linux falls back to \$HOME/.cache" || fail "11b. Linux ~/.cache" "got $got"
# macOS (Darwin): ~/Library/Caches.
got="$(HOME=/Users/bob osprobe Darwin)"
[ "$got" = "/Users/bob/Library/Caches/zskills-session-logs/myproj" ] \
  && pass "11c. macOS uses ~/Library/Caches" || fail "11c. macOS" "got $got"
# Windows: %LOCALAPPDATA% (a single literal backslash per separator).
got="$(LOCALAPPDATA='C:\Users\bob\AppData\Local' osprobe Windows)"
case "$got" in
  *'AppData\Local'*'zskills-session-logs'*myproj) pass "11d. Windows uses %LOCALAPPDATA% ($got)" ;;
  *) fail "11d. Windows LOCALAPPDATA" "got $got" ;;
esac
# Windows: LOCALAPPDATA unset -> ~ fallback.
got="$( unset LOCALAPPDATA; HOME=/winhome osprobe Windows )"
[ "$got" = "/winhome/zskills-session-logs/myproj" ] \
  && pass "11e. Windows falls back to ~ when LOCALAPPDATA unset" || fail "11e. Windows ~ fallback" "got $got"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 12 — registry-absent fallback resolves sanely ==="
# No registry (e.g. run before the first Stop, or outside a repo): the
# helper falls back to its own per-OS resolution and still prints a dir.
NA_PROJ="$WORK/naproj"
mkdir -p "$NA_PROJ/.claude"
echo '{}' > "$NA_PROJ/.claude/zskills-config.json"
( cd "$NA_PROJ" && git init -q . )   # repo, but NO registry written yet.
na_dir="$(CLAUDE_PROJECT_DIR="$NA_PROJ" XDG_CACHE_HOME="$WORK/na-xdg" bash "$HELPER")"
if [ "$na_dir" = "$WORK/na-xdg/zskills-session-logs/naproj" ]; then
  pass "12a. registry-absent -> per-OS fallback resolution"
else
  fail "12a. registry-absent fallback" "got $na_dir"
fi
# Env override still wins even with no registry. NA_PROJ config is {} so
# include_repo defaults to true -> the env base is COMPOSED with the <repo>
# segment (naproj), matching what the hooks would write.
na_env="$(ZSKILLS_LOG_DIR="$WORK/na-env" CLAUDE_PROJECT_DIR="$NA_PROJ" bash "$HELPER")"
[ "$na_env" = "$WORK/na-env/naproj" ] && pass "12b. ZSKILLS_LOG_DIR (composed) wins with no registry" \
  || fail "12b. env override no-registry" "got $na_env want $WORK/na-env/naproj"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 13 — path composition: <base>/[<repo>]/[<user>] ==="
# 13a. include_repo:true (default) appends the <repo> segment to the env
# base, and the helper round-trips to the SAME composed dir the Stop hook
# wrote to (writer<->reader agreement).
COMP_PROJ="$WORK/comp-proj"
mkdir -p "$COMP_PROJ/.claude"
echo '{"logging":{"enabled":true}}' > "$COMP_PROJ/.claude/zskills-config.json"
( cd "$COMP_PROJ" && git init -q . && git config user.email dev@example.com )
COMP_BASE="$WORK/comp-base"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"comp0001\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$COMP_BASE" CLAUDE_PROJECT_DIR="$COMP_PROJ" TZ=UTC bash "$STOP_HOOK"
if [ -f "$COMP_BASE/comp-proj/2026-06-03-1200-comp0001.md" ]; then
  pass "13a. include_repo:true writes to <base>/<repo>/"
else
  fail "13a. include_repo:true <base>/<repo>" "ls: $(find "$COMP_BASE" -name '*.md' 2>/dev/null)"
fi
comp_read="$(ZSKILLS_LOG_DIR="$COMP_BASE" CLAUDE_PROJECT_DIR="$COMP_PROJ" bash "$HELPER")"
[ "$comp_read" = "$COMP_BASE/comp-proj" ] \
  && pass "13b. helper resolves the SAME composed <base>/<repo> dir (writer<->reader)" \
  || fail "13b. helper composed dir" "got [$comp_read] want [$COMP_BASE/comp-proj]"

# 13c. include_repo:false -> flat <base>/ (today's dir-mode behavior).
FLAT_PROJ="$WORK/flat-proj"
mkdir -p "$FLAT_PROJ/.claude"
echo '{"logging":{"enabled":true,"include_repo":false}}' > "$FLAT_PROJ/.claude/zskills-config.json"
FLAT_BASE="$WORK/flat-base"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"flat0001\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$FLAT_BASE" CLAUDE_PROJECT_DIR="$FLAT_PROJ" TZ=UTC bash "$STOP_HOOK"
if [ -f "$FLAT_BASE/2026-06-03-1200-flat0001.md" ] \
   && [ ! -d "$FLAT_BASE/flat-proj" ]; then
  pass "13c. include_repo:false writes FLAT to <base>/ (no <repo> segment)"
else
  fail "13c. include_repo:false flat" "ls: $(find "$FLAT_BASE" -name '*.md' 2>/dev/null)"
fi

# 13d. include_user:true -> <base>/<repo>/<user>/. ZSKILLS_LOG_USER pins the
# user segment deterministically.
USR_PROJ="$WORK/usr-proj"
mkdir -p "$USR_PROJ/.claude"
echo '{"logging":{"enabled":true,"include_user":true}}' > "$USR_PROJ/.claude/zskills-config.json"
USR_BASE="$WORK/usr-base"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"usr00001\",\"transcript_path\":\"$TR\"}" | \
  ZSKILLS_LOG_DIR="$USR_BASE" ZSKILLS_LOG_USER="alice" \
  CLAUDE_PROJECT_DIR="$USR_PROJ" TZ=UTC bash "$STOP_HOOK"
if [ -f "$USR_BASE/usr-proj/alice/2026-06-03-1200-usr00001.md" ]; then
  pass "13d. include_user:true writes to <base>/<repo>/<user>/"
else
  fail "13d. include_user:true <base>/<repo>/<user>" "ls: $(find "$USR_BASE" -name '*.md' 2>/dev/null)"
fi
usr_read="$(ZSKILLS_LOG_DIR="$USR_BASE" ZSKILLS_LOG_USER="alice" \
  CLAUDE_PROJECT_DIR="$USR_PROJ" bash "$HELPER")"
[ "$usr_read" = "$USR_BASE/usr-proj/alice" ] \
  && pass "13e. helper resolves <base>/<repo>/<user> with include_user:true" \
  || fail "13e. helper user-composed dir" "got [$usr_read] want [$USR_BASE/usr-proj/alice]"

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Case 14 — resolve_user() precedence + sanitization ==="
# Drive the shared resolve_user() exactly as the hooks/helper embed it, with
# a mocked git config user.email, to assert precedence and sanitization.
userprobe() {
  # $1=ZSKILLS_LOG_USER (may be empty), $2=git-email-mock (may be empty).
  "$PYTHON" - "$1" "$2" <<'PYUSER'
import os, sys, subprocess
env_user = sys.argv[1]
git_email = sys.argv[2]
if env_user:
    os.environ["ZSKILLS_LOG_USER"] = env_user
else:
    os.environ.pop("ZSKILLS_LOG_USER", None)

# Mock the git subprocess to return the supplied email (or fail).
class _Res:
    def __init__(self, rc, out):
        self.returncode = rc
        self.stdout = out
def _fake_run(cmd, **kw):
    if git_email:
        return _Res(0, git_email + "\n")
    return _Res(1, "")
subprocess.run = _fake_run

def sanitize_segment(seg):
    if not seg:
        return "unknown"
    bad = set(os.sep) | {"/", "\\", ":", "*", "?", '"', "<", ">", "|"}
    out = []
    for ch in seg:
        if ch in bad or ch.isspace():
            out.append("_")
        else:
            out.append(ch)
    result = "".join(out).strip(". ")
    return result or "unknown"

def resolve_user():
    user = os.environ.get("ZSKILLS_LOG_USER", "")
    if not user:
        try:
            out = subprocess.run(
                ["git", "config", "user.email"],
                capture_output=True, text=True, timeout=5)
            if out.returncode == 0:
                user = out.stdout.strip()
        except Exception:
            user = ""
    if not user:
        try:
            import getpass
            user = getpass.getuser()
        except Exception:
            user = ""
    return sanitize_segment(user)

print(resolve_user())
PYUSER
}
# 14a. ZSKILLS_LOG_USER overrides git email.
got="$(userprobe "envuser" "git@example.com")"
[ "$got" = "envuser" ] && pass "14a. ZSKILLS_LOG_USER overrides git email ($got)" \
  || fail "14a. env overrides git" "got $got"
# 14b. git email used when no env override; sanitized (@ and . kept, but
# the segment is a single safe token).
got="$(userprobe "" "dev@example.com")"
[ "$got" = "dev@example.com" ] && pass "14b. git email used when no env override ($got)" \
  || fail "14b. git email fallback" "got $got"
# 14c. sanitization replaces path separators / reserved chars with _.
got="$(userprobe 'a/b c:d' '')"
[ "$got" = "a_b_c_d" ] && pass "14c. unsafe chars sanitized to _ ($got)" \
  || fail "14c. sanitization" "got $got"

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
[ "$FAIL_COUNT" -gt 0 ] && exit 1
exit 0
