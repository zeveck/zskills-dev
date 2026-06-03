#!/bin/bash
# Tests for skills/zskills-dashboard/SKILL.md.
#
# EXTRACT-AND-RUN (SEAM_HARDENING_REST Phase 4):
#   This file no longer hand-transcribes the start/stop/status/marker bash
#   as `$1=MAIN_ROOT`-parameterised functions (the old form carried a
#   spurious `cd "$MAIN_ROOT"` workaround and called the identity helper
#   with a 2-arg signature that does NOT exist in production). Instead it
#   EXTRACTS the REAL production fences from
#   skills/zskills-dashboard/SKILL.md via tests/lib/extract-fence.sh and
#   RUNS them against tmpdir-scoped fixtures. A logic change BETWEEN the
#   lines of any extracted fence now fails these tests.
#
#   CONCATENATE-INTO-ONE-EVAL (the load-bearing fix):
#     The start/stop/status mode fences read GLOBALS (`PID_FILE`,
#     `LOG_FILE`, `PORT_SCRIPT`, `SANITIZE_SCRIPT`, `PKG_PARENT`,
#     `MAIN_ROOT`) set in the **Step-0 fence**, and CALL
#     `verify_monitor_identity "$pid"` (1-arg, reading global `$MAIN_ROOT`)
#     + `write_tracking_marker`. A mode fence extracted alone aborts under
#     `set -u` on the first unset global. So each mode is run as ONE eval'd
#     subshell that concatenates, in dependency order:
#         Step-0  +  verify_monitor_identity  +  write_tracking_marker
#                 +  the target mode fence
#     with `MAIN_ROOT` exported AND the subshell `cd`-ed into `$MAIN_ROOT`
#     — replicating production's Step-0 `cd "$MAIN_ROOT"` invocation
#     contract (the user invokes the skill from inside the repo, so cwd
#     already equals MAIN_ROOT; port.sh's `git rev-parse --show-toplevel`
#     and the launch's `cd "$MAIN_ROOT"` both anchor here). This removes
#     the old test's spurious in-fence `cd "$MAIN_ROOT"` workaround.
#
#   VERIFIED FENCE RANGES (skills/zskills-dashboard/SKILL.md):
#     - Step-0 (MAIN_ROOT / PID_FILE / LOG_FILE / PKG_PARENT / PORT_SCRIPT /
#       SANITIZE_SCRIPT setup):            fence opener L79, body L80-105
#     - verify_monitor_identity (1-arg):   fence opener L126, body L127-171
#     - write_tracking_marker (1-arg mode + resolve-config prelude):
#                                          fence opener L181, body L182-205
#     - start (launch detached + health):  fence opener L255, body L256-358
#     - stop  (SIGTERM + cleanup):         fence opener L381, body L382-462
#     - status (read-only report):         fence opener L480, body L481-541
#
#   SHIMS:
#     - `git`  — none; the fixture is a REAL git repo (Step-0 resolves
#       MAIN_ROOT via `git rev-parse --git-common-dir`, port.sh via
#       `git rev-parse --show-toplevel`).
#     - `port.sh` + `sanitize-pipeline-id.sh` + the zskills-dashboard
#       `scripts/` package + `zskills-resolve-config.sh` — source-resolved
#       into the fixture under `$MAIN_ROOT/skills/...` (the exact paths
#       Step-0's source-tree fallback and write_tracking_marker's prelude
#       expect) so the REAL scripts run, no behavioral mock.
#     - `python3 -m zskills_monitor.server` — LIVE (kept). This is the
#       live-server suite; the start fence really boots the server.
#
#   BOOT-RACE HARDENING (review F3):
#     The old transcription's post-start `/api/health` re-checks and the
#     fresh-shell survival probe were single-shot `curl` calls — a known
#     CI flake on a port-contended box (the server may have JUST bound when
#     the test polls). They are now BOUNDED RETRY-POLLS via `poll_health`
#     (up to ~3s in 0.25s steps, exit-on-ready), NOT a single sleep+curl.
#     The start fence's OWN internal 40×0.25s health loop is unchanged
#     (production) — this hardens the TEST's secondary probes around it.
#
#   PORT HYGIENE:
#     Each fixture uses a process-unique base port (derived from $$) so
#     concurrent suites on the same box don't collide. Teardown SIGTERMs
#     tracked PIDs (the stop fence already does this for the lifecycle
#     server) — NEVER kill -9 / pkill / killall (project rule). The
#     scratch tree is removed in an EXIT trap.
#
#   Run from repo root: bash tests/test_zskills_dashboard_skill.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$REPO_ROOT/skills/zskills-dashboard"
SKILL_MD="$SKILL_DIR/SKILL.md"
MIRROR_DIR="$REPO_ROOT/.claude/skills/zskills-dashboard"
PKG_PARENT_SRC="$SKILL_DIR/scripts"
SERVER_PY="$PKG_PARENT_SRC/zskills_monitor/server.py"
PORT_SCRIPT_SRC="$REPO_ROOT/skills/update-zskills/scripts/port.sh"
SANITIZE_SCRIPT_SRC="$REPO_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
RESOLVE_CONFIG_SRC="$REPO_ROOT/skills/update-zskills/scripts/zskills-resolve-config.sh"
PATHS_SRC="$REPO_ROOT/skills/update-zskills/scripts/zskills-paths.sh"

# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT+1)); }

print_summary_and_exit() {
  echo ""
  echo "---"
  local total=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
  if [ "$FAIL_COUNT" -eq 0 ]; then
    printf '\033[32mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
      "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$total"
    exit 0
  else
    printf '\033[31mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
      "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$total"
    exit 1
  fi
}

# Per-process scratch root.
TMP_ROOT="/tmp/zskills-dashboard-skill-test.$$"
mkdir -p "$TMP_ROOT"

TRACKED_PIDS=""
cleanup() {
  for p in $TRACKED_PIDS; do
    if kill -0 "$p" 2>/dev/null; then
      kill -TERM "$p" 2>/dev/null || true
      sleep 0.5
    fi
    # SIGTERM-only cleanup — no SIGKILL escalation, even on test teardown
    # (project rule). The test process itself exits regardless; any
    # stragglers are reaped by init.
  done
  case "$TMP_ROOT" in
    /tmp/zskills-dashboard-skill-test.*)
      rm -rf -- "$TMP_ROOT"
      ;;
  esac
}
trap cleanup EXIT INT TERM

###############################################################################
# AC-1/3/4/15/16: static-grep contract against the REAL SKILL.md.
###############################################################################

echo ""
echo "=== Phase 8 AC: static-grep contract ==="

if [ ! -f "$SKILL_MD" ]; then
  fail "AC-1: SKILL.md exists at $SKILL_MD"
  print_summary_and_exit
fi
pass "AC-1: SKILL.md exists at $SKILL_MD"

if grep -q '^name: zskills-dashboard$' "$SKILL_MD"; then
  pass "AC-1: frontmatter name: zskills-dashboard"
else
  fail "AC-1: frontmatter name field missing or wrong"
fi
if grep -q '^disable-model-invocation: true$' "$SKILL_MD"; then
  pass "AC-1: frontmatter disable-model-invocation: true"
else
  fail "AC-1: frontmatter disable-model-invocation flag missing"
fi
if grep -q '^argument-hint:.*\[start|stop|status|restart\]' "$SKILL_MD"; then
  pass "AC-1: frontmatter argument-hint covers [start|stop|status|restart]"
else
  fail "AC-1: frontmatter argument-hint missing or wrong"
fi

if grep -nE '\bjq\b' "$SKILL_MD" >/dev/null; then
  fail "AC-3: forbidden \\bjq\\b token in SKILL.md"
else
  pass "AC-3: no \\bjq\\b in SKILL.md"
fi

if grep -nE 'kill\s+-9|killall|pkill|fuser\s+-k' "$SKILL_MD" >/dev/null; then
  fail "AC-4: forbidden SIGKILL/killall family in SKILL.md"
else
  pass "AC-4: no SIGKILL / killall / pkill / fuser -k in SKILL.md"
fi

if grep -nE 'PYTHONPATH=.*skills/zskills-dashboard/scripts' "$SKILL_MD" >/dev/null; then
  pass "AC-15: PYTHONPATH=...skills/zskills-dashboard/scripts present"
else
  fail "AC-15: PYTHONPATH discipline missing"
fi

if grep -nE 'mirror-skill\.sh' "$SKILL_MD" >/dev/null; then
  pass "AC-16: mirror-skill.sh referenced in SKILL.md"
else
  fail "AC-16: mirror-skill.sh not referenced"
fi
if grep -nE 'rm\s+-rf\s+\.claude/skills' "$SKILL_MD" >/dev/null; then
  fail "AC-16: forbidden rm -rf .claude/skills in SKILL.md"
else
  pass "AC-16: no rm -rf .claude/skills in SKILL.md"
fi

###############################################################################
# AC-2: whole-tree mirror clean.
###############################################################################

if [ ! -d "$MIRROR_DIR" ]; then
  fail "AC-2: mirror dir exists at $MIRROR_DIR"
else
  DIFF_OUT=$(diff -rq "$SKILL_DIR/" "$MIRROR_DIR/" 2>&1 | grep -v __pycache__ || true)
  if [ -z "$DIFF_OUT" ]; then
    pass "AC-2: diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/ is clean"
  else
    fail "AC-2: mirror diverges from source: $DIFF_OUT"
  fi
fi

###############################################################################
# Live-server preconditions. Skip the behavioral suite (not the file) when
# python3 / curl / the server source / the source-resolved scripts are
# unavailable — defensive; should not happen in CI.
###############################################################################

if ! command -v python3 >/dev/null 2>&1; then
  skip "live tests: python3 not available"
  print_summary_and_exit
fi
if ! command -v curl >/dev/null 2>&1; then
  skip "live tests: curl not available"
  print_summary_and_exit
fi
if [ ! -f "$SERVER_PY" ]; then
  skip "live tests: server.py missing at $SERVER_PY"
  print_summary_and_exit
fi
if [ ! -x "$PORT_SCRIPT_SRC" ]; then
  skip "live tests: port.sh missing or non-executable at $PORT_SCRIPT_SRC"
  print_summary_and_exit
fi
if [ ! -x "$SANITIZE_SCRIPT_SRC" ]; then
  skip "live tests: sanitize-pipeline-id.sh missing or non-executable at $SANITIZE_SCRIPT_SRC"
  print_summary_and_exit
fi
if [ ! -f "$RESOLVE_CONFIG_SRC" ]; then
  skip "live tests: zskills-resolve-config.sh missing at $RESOLVE_CONFIG_SRC"
  print_summary_and_exit
fi

###############################################################################
# Extract the SIX real production fences from SKILL.md.
###############################################################################

# Step-0 — the FIRST ```bash fence after the "## Step 0 — Common setup"
# header. Tight anchors bracket exactly that fence.
STEP0_FENCE=$(extract_fence_between "$SKILL_MD" \
  '^## Step 0 — Common setup' '^### Process-identity check' 1 0) \
  || { echo "FATAL: could not extract Step-0 fence from $SKILL_MD" >&2; exit 2; }

VERIFY_FENCE=$(extract_fence_between "$SKILL_MD" \
  '^### Process-identity check' '^### Tracking marker helper' 1 0) \
  || { echo "FATAL: could not extract verify_monitor_identity fence" >&2; exit 2; }

MARKER_FENCE=$(extract_fence_between "$SKILL_MD" \
  '^### Tracking marker helper' '^## Mode dispatch' 1 0) \
  || { echo "FATAL: could not extract write_tracking_marker fence" >&2; exit 2; }

START_FENCE=$(extract_fence_between "$SKILL_MD" \
  '^## start — launch detached server' '^## stop — SIGTERM' 1 0) \
  || { echo "FATAL: could not extract start fence" >&2; exit 2; }

STOP_FENCE=$(extract_fence_between "$SKILL_MD" \
  '^## stop — SIGTERM and clean up' '^## status — read-only' 1 0) \
  || { echo "FATAL: could not extract stop fence" >&2; exit 2; }

STATUS_FENCE=$(extract_fence_between "$SKILL_MD" \
  '^## status — read-only health report' '^## restart — stop then start' 1 0) \
  || { echo "FATAL: could not extract status fence" >&2; exit 2; }

# Sanity: each fence is non-empty and carries its signature line. Catches a
# silent mis-extraction (empty body / wrong fence) before any test runs.
sanity_fences() {
  local ok=1
  printf '%s' "$STEP0_FENCE"  | grep -qF 'PID_FILE="$MAIN_ROOT/.zskills/dashboard-server.pid"' || { echo "FATAL: Step-0 fence missing PID_FILE assignment" >&2; ok=0; }
  printf '%s' "$VERIFY_FENCE" | grep -qF 'verify_monitor_identity() {'                          || { echo "FATAL: verify fence missing function def" >&2; ok=0; }
  # Production identity helper is 1-arg (reads global $MAIN_ROOT). Guard
  # against a 2-arg transcription creeping back in.
  printf '%s' "$VERIFY_FENCE" | grep -qF 'local pid="$1"'                                       || { echo "FATAL: verify fence not 1-arg (production signature)" >&2; ok=0; }
  printf '%s' "$VERIFY_FENCE" | grep -qF 'main_root="$2"'                                       && { echo "FATAL: verify fence has a 2-arg signature (transcription artifact)" >&2; ok=0; }
  printf '%s' "$MARKER_FENCE" | grep -qF 'write_tracking_marker() {'                            || { echo "FATAL: marker fence missing function def" >&2; ok=0; }
  printf '%s' "$START_FENCE"  | grep -qF 'nohup python3 -m zskills_monitor.server'              || { echo "FATAL: start fence missing launch" >&2; ok=0; }
  printf '%s' "$STOP_FENCE"   | grep -qF 'kill -TERM "$STOP_PID"'                               || { echo "FATAL: stop fence missing SIGTERM" >&2; ok=0; }
  printf '%s' "$STATUS_FENCE" | grep -qF 'Dashboard running at http://127.0.0.1:$ST_PORT/'      || { echo "FATAL: status fence missing report" >&2; ok=0; }
  [ "$ok" -eq 1 ] || exit 2
}
sanity_fences

###############################################################################
# Fence runner — concatenate Step-0 + helpers + the target mode fence into
# ONE eval'd subshell, faithful to how Claude executes the SKILL.md top to
# bottom for a single mode invocation.
#
#   $1 = MAIN_ROOT (fixture)         exported + cd'd into (Step-0 contract)
#   $2 = SUB       (start|stop|status)
#   stdin/stdout/stderr flow to the caller's redirection.
#
# Concatenation order is load-bearing: Step-0 sets globals the helpers and
# the mode fence read; verify_monitor_identity + write_tracking_marker must
# be DEFINED before the mode fence CALLS them.
###############################################################################
run_mode() {
  local main_root="$1" sub="$2" mode_fence
  case "$sub" in
    start)  mode_fence="$START_FENCE"  ;;
    stop)   mode_fence="$STOP_FENCE"   ;;
    status) mode_fence="$STATUS_FENCE" ;;
    *) echo "run_mode: unknown sub '$sub'" >&2; return 99 ;;
  esac
  (
    # Replicate production's invocation context: cwd == MAIN_ROOT (so
    # port.sh's `git rev-parse --show-toplevel` and the launch's
    # `cd "$MAIN_ROOT"` anchor to the fixture), and ARGUMENTS == the mode.
    cd "$main_root" || return 98
    export MAIN_ROOT="$main_root"
    # Neutralise host env that would bend port.sh / config resolution:
    #   - DEV_PORT would override port.sh's config-driven port.
    #   - REPO_ROOT would make port.sh read the WRONG repo's config
    #     (it honours ${REPO_ROOT:-$PROJECT_ROOT} for the config path).
    unset DEV_PORT REPO_ROOT ZSKILLS_DASHBOARD_ROOT
    # The mode fences guard on $SUB (set by the Mode-dispatch fence from
    # $ARGUMENTS in production). We feed both: $ARGUMENTS is the raw token,
    # and $SUB is the lowercased/trimmed result the dispatch fence would
    # produce for a clean single-mode token — the minimal faithful bridge
    # so we run exactly ONE mode body, as a single skill invocation does.
    ARGUMENTS="$sub"
    SUB="$sub"
    # Legacy-lane faithful under the file-level `set -u`: production fences run
    # WITHOUT `set -u`, so the new resolution idiom's bare ${CLAUDE_PLUGIN_ROOT}
    # token expands empty → else/legacy branch. Bind it EMPTY (not a real path)
    # so the same legacy else-branch is exercised without an unbound-variable
    # abort under the inherited `set -u`.
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
    eval "$STEP0_FENCE"
    eval "$VERIFY_FENCE"
    eval "$MARKER_FENCE"
    eval "$mode_fence"
  )
}

###############################################################################
# poll_health — BOUNDED retry-poll of /api/health (boot-race hardening, F3).
# Up to ~3s in 0.25s steps; exit 0 the instant `"status": "ok"` appears.
# Replaces the old single-shot `curl` probes that flaked under port
# contention when the server had only just bound.
###############################################################################
poll_health() {
  local port="$1" _i body
  for _i in $(seq 1 12); do
    body=$(curl -sf -m 1 "http://127.0.0.1:$port/api/health" 2>/dev/null || true)
    if printf '%s' "$body" | grep -qE '"status":[[:space:]]*"ok"'; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

###############################################################################
# Fixture builder — minimal REAL git repo whose source-tree layout matches
# what Step-0 / port.sh / write_tracking_marker expect, with the REAL helper
# scripts + the dashboard package source-resolved in (symlinked from the
# zskills tree — no behavioral mock).
###############################################################################
make_fixture() {
  local label="$1" port="$2"
  local f="$TMP_ROOT/$label"
  mkdir -p "$f/.claude/skills/update-zskills" \
           "$f/.zskills" \
           "$f/skills/zskills-dashboard" \
           "$f/skills/update-zskills" \
           "$f/skills/create-worktree"
  ( cd "$f" && git init -q && git config user.email "t@e.com" && git config user.name "t" && \
    git commit --allow-empty -q -m init )

  # zskills-config.json — port.sh's main-repo branch keys off
  # dev_server.main_repo_path == PROJECT_ROOT, then returns default_port.
  cat > "$f/.claude/zskills-config.json" <<EOF
{
  "dev_server": { "default_port": $port, "main_repo_path": "$f" },
  "execution": { "landing": "pr" }
}
EOF

  # Source-resolve the REAL script DIRECTORIES onto the EXACT paths Step-0's
  # source-tree fallback ($MAIN_ROOT/skills/...) and write_tracking_marker's
  # prelude ($CLAUDE_PROJECT_DIR/.claude/skills/.../) expect. Whole-directory
  # symlinks keep the REAL behavior (no mock) AND carry the sibling helpers
  # each script transitively needs:
  #   - port.sh's BASH_SOURCE-relative zskills-stub-lib.sh lookup,
  #   - zskills-resolve-config.sh's sibling zskills-paths.sh source,
  #   - the zskills_monitor package under .../zskills-dashboard/scripts/.
  ln -s "$(dirname "$PORT_SCRIPT_SRC")"     "$f/skills/update-zskills/scripts"
  ln -s "$(dirname "$SANITIZE_SCRIPT_SRC")" "$f/skills/create-worktree/scripts"
  ln -s "$PKG_PARENT_SRC"                   "$f/skills/zskills-dashboard/scripts"
  # write_tracking_marker's resolve-config prelude sources from
  # $CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/. We point
  # $CLAUDE_PROJECT_DIR at the fixture (set per-run below) so this dir is
  # what gets sourced; resolve-config sets $TIMEZONE only (no dashboard-global
  # clobber) and pulls in its sibling zskills-paths.sh from the same dir.
  ln -s "$(dirname "$RESOLVE_CONFIG_SRC")"  "$f/.claude/skills/update-zskills/scripts"

  echo "$f"
}

# Process-unique, well-spaced base ports so concurrent suites don't collide.
BASE_A=$(( 19800 + ($$ % 100) ))
BASE_B=$(( BASE_A + 100 ))
BASE_C=$(( BASE_A + 200 ))

# write_tracking_marker's prelude reads
# $CLAUDE_PROJECT_DIR/.claude/skills/.../zskills-resolve-config.sh. Point it
# at each fixture per-run via the exported var (overridden inside run_mode's
# subshell is not possible — the prelude reads it at source time — so export
# it here and reassign before each run_mode that writes a marker).
export CLAUDE_PROJECT_DIR

###############################################################################
# AC-5: start writes a PID file and /api/health returns ok; status after
#       start prints `^Dashboard running`.
# AC-6: PID-file shape (pid=<int>, port=<int>, started_at=ISO).
###############################################################################

echo ""
echo "=== Phase 8 AC: live start/stop/status (lifecycle) ==="

FX_A=$(make_fixture A "$BASE_A")
CLAUDE_PROJECT_DIR="$FX_A"

if run_mode "$FX_A" start >"$TMP_ROOT/A.start.out" 2>&1; then
  if grep -qE '^Dashboard running at http://127\.0\.0\.1:' "$TMP_ROOT/A.start.out"; then
    pass "AC-5: start prints 'Dashboard running at http://127.0.0.1:...'"
  else
    fail "AC-5: start output missing expected line: $(cat "$TMP_ROOT/A.start.out")"
  fi
  if [ -f "$FX_A/.zskills/dashboard-server.pid" ]; then
    pass "AC-5: PID file written at .zskills/dashboard-server.pid"
  else
    fail "AC-5: PID file NOT written"
  fi

  # Track the launched server's PID for SIGTERM teardown.
  A_PID=$(grep -oE '^pid=[0-9]+' "$FX_A/.zskills/dashboard-server.pid" 2>/dev/null | cut -d= -f2)
  [ -n "${A_PID:-}" ] && TRACKED_PIDS="$TRACKED_PIDS $A_PID"

  # /api/health smoke — BOUNDED poll (boot-race hardening).
  if poll_health "$BASE_A"; then
    pass "AC-5: /api/health returns ok (bounded poll)"
  else
    fail "AC-5: /api/health did not return ok within ~3s"
  fi

  # AC-6: PID-file shape.
  PID_FILE_A="$FX_A/.zskills/dashboard-server.pid"
  if grep -qE '^pid=[0-9]+$' "$PID_FILE_A"; then
    pass "AC-6: PID file has pid=<int>"
  else
    fail "AC-6: PID file pid= line malformed: $(cat "$PID_FILE_A")"
  fi
  if grep -qE '^port=[0-9]+$' "$PID_FILE_A"; then
    pass "AC-6: PID file has port=<int>"
  else
    fail "AC-6: PID file port= line malformed: $(cat "$PID_FILE_A")"
  fi
  if grep -qE '^started_at=[0-9T:+-]+$' "$PID_FILE_A"; then
    pass "AC-6: PID file has started_at=<ISO-token-shape>"
  else
    fail "AC-6: PID file started_at= line malformed: $(cat "$PID_FILE_A")"
  fi

  # AC-5 (status side): status after start prints `^Dashboard running`.
  if run_mode "$FX_A" status >"$TMP_ROOT/A.status.out" 2>&1; then
    if grep -qE '^Dashboard running' "$TMP_ROOT/A.status.out"; then
      pass "AC-5: status after start prints '^Dashboard running'"
    else
      fail "AC-5: status output missing 'Dashboard running': $(cat "$TMP_ROOT/A.status.out")"
    fi
  else
    fail "AC-5: status returned non-zero after start: $(cat "$TMP_ROOT/A.status.out")"
  fi
else
  fail "AC-5: start returned non-zero: $(cat "$TMP_ROOT/A.start.out")"
fi

###############################################################################
# AC-8: start twice → second run detects live PID + matching command +
#       matching cwd and prints the URL without launching a duplicate.
###############################################################################

if run_mode "$FX_A" start >"$TMP_ROOT/A.start2.out" 2>&1; then
  if grep -qE 'already running at http://127\.0\.0\.1:' "$TMP_ROOT/A.start2.out"; then
    pass "AC-8: start twice — second prints 'already running' (no duplicate)"
  else
    fail "AC-8: start twice — unexpected output: $(cat "$TMP_ROOT/A.start2.out")"
  fi
else
  fail "AC-8: start twice returned non-zero (expected 0 when already running): $(cat "$TMP_ROOT/A.start2.out")"
fi

###############################################################################
# AC-12: tracking markers exist after start; status writes none.
###############################################################################

COUNT_AFTER_TWO_STARTS=$(find "$FX_A/.zskills/tracking" -maxdepth 1 -type d -name 'zskills-dashboard.*' 2>/dev/null | wc -l | tr -d ' ')
if [ "${COUNT_AFTER_TWO_STARTS:-0}" -ge 1 ]; then
  pass "AC-12: tracking subdir(s) exist after start ($COUNT_AFTER_TWO_STARTS)"
else
  fail "AC-12: expected ≥1 tracking subdir after start, got $COUNT_AFTER_TWO_STARTS"
fi

MARKER_FILE=$(find "$FX_A/.zskills/tracking" -name 'fulfilled.zskills-dashboard.*' -type f 2>/dev/null | head -1)
if [ -n "$MARKER_FILE" ]; then
  if grep -q '^skill: zskills-dashboard$' "$MARKER_FILE" \
     && grep -q '^id: ' "$MARKER_FILE" \
     && grep -q '^status: ' "$MARKER_FILE" \
     && grep -q '^date: ' "$MARKER_FILE"; then
    pass "AC-12: marker has skill: / id: / status: / date: fields"
  else
    fail "AC-12: marker missing fields: $(cat "$MARKER_FILE")"
  fi
else
  fail "AC-12: no fulfilled.zskills-dashboard.* marker found"
fi

# status must NOT add a new subdir (read-only).
STATUS_BEFORE=$(find "$FX_A/.zskills/tracking" -maxdepth 1 -type d -name 'zskills-dashboard.*' 2>/dev/null | wc -l | tr -d ' ')
run_mode "$FX_A" status >/dev/null 2>&1 || true
STATUS_AFTER=$(find "$FX_A/.zskills/tracking" -maxdepth 1 -type d -name 'zskills-dashboard.*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$STATUS_BEFORE" = "$STATUS_AFTER" ]; then
  pass "AC-12: status does NOT add a new tracking subdir (read-only)"
else
  fail "AC-12: status added a tracking subdir (was $STATUS_BEFORE, now $STATUS_AFTER)"
fi

###############################################################################
# AC-13: detachment survival in a fresh shell (BOUNDED health poll).
###############################################################################

# The start fence ran `nohup … & disown`, so the server is reparented away
# from this process's job table. Read its PID/port and probe from a fresh
# `bash -c` (the AC's "new shell"), using a BOUNDED retry-poll on
# /api/health rather than a single-shot curl (boot-race hardening).
FRESH_SHELL_OUT=$(bash -c '
  PIDF="'"$FX_A"'/.zskills/dashboard-server.pid"
  PID=$(grep -oE "^pid=[0-9]+" "$PIDF" 2>/dev/null | cut -d= -f2)
  PORT=$(grep -oE "^port=[0-9]+" "$PIDF" 2>/dev/null | cut -d= -f2)
  if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then echo "DEAD"; exit 0; fi
  for _ in $(seq 1 12); do
    if curl -sf -m 1 "http://127.0.0.1:$PORT/api/health" 2>/dev/null | grep -q "\"status\""; then
      echo "ALIVE"; exit 0
    fi
    sleep 0.25
  done
  echo "DEAD"
')
if [ "$FRESH_SHELL_OUT" = "ALIVE" ]; then
  pass "AC-13: detachment survival — kill -0 + /api/health succeed in fresh shell"
else
  fail "AC-13: server did not survive parent-shell exit (got: $FRESH_SHELL_OUT)"
fi

###############################################################################
# AC-14: PID-reuse defense — a PID file pointing at a non-dashboard process
#        is treated as stale; start does NOT print "already running" and does
#        NOT signal the decoy.
###############################################################################

FX_REUSE=$(make_fixture reuse "$BASE_C")
sleep 30 &
DECOY_PID=$!
TRACKED_PIDS="$TRACKED_PIDS $DECOY_PID"
cat > "$FX_REUSE/.zskills/dashboard-server.pid" <<EOF
pid=$DECOY_PID
port=$BASE_C
started_at=$(date -Iseconds)
EOF
CLAUDE_PROJECT_DIR="$FX_REUSE"
run_mode "$FX_REUSE" start >"$TMP_ROOT/reuse.start.out" 2>&1 || true
if grep -qE 'already running' "$TMP_ROOT/reuse.start.out"; then
  fail "AC-14: PID-reuse defense — start incorrectly said 'already running' against decoy"
else
  pass "AC-14: PID-reuse defense — start did NOT say 'already running' against decoy"
fi
if kill -0 "$DECOY_PID" 2>/dev/null; then
  pass "AC-14: PID-reuse defense — decoy process untouched (no kill sent)"
else
  fail "AC-14: PID-reuse defense — decoy process was killed (should be untouched)"
fi
# Track whatever start launched (so teardown SIGTERMs it).
REUSE_PID=$(grep -oE '^pid=[0-9]+' "$FX_REUSE/.zskills/dashboard-server.pid" 2>/dev/null | cut -d= -f2)
[ -n "${REUSE_PID:-}" ] && TRACKED_PIDS="$TRACKED_PIDS $REUSE_PID"
kill -TERM "$DECOY_PID" 2>/dev/null || true

###############################################################################
# AC-10: stop PID-mismatch defense (command-name). PID file points at an
#        unrelated process; stop prints the mismatch diagnostic, does NOT
#        kill it, and exits 1.
###############################################################################

FX_CMD=$(make_fixture cmdmiss "$BASE_C")
sleep 30 &
DECOY2_PID=$!
TRACKED_PIDS="$TRACKED_PIDS $DECOY2_PID"
cat > "$FX_CMD/.zskills/dashboard-server.pid" <<EOF
pid=$DECOY2_PID
port=$BASE_C
started_at=$(date -Iseconds)
EOF
CLAUDE_PROJECT_DIR="$FX_CMD"
if run_mode "$FX_CMD" stop >"$TMP_ROOT/cmdmiss.stop.out" 2>&1; then
  CMDMISS_RC=0
else
  CMDMISS_RC=$?
fi
if [ "$CMDMISS_RC" -eq 1 ]; then
  pass "AC-10: stop PID-mismatch (command-name) — exit 1"
else
  fail "AC-10: stop PID-mismatch (command-name) — exit was $CMDMISS_RC, expected 1"
fi
if grep -q 'does not appear to be zskills-dashboard' "$TMP_ROOT/cmdmiss.stop.out"; then
  pass "AC-10: stop PID-mismatch (command-name) — diagnostic printed"
else
  fail "AC-10: stop PID-mismatch (command-name) — diagnostic missing: $(cat "$TMP_ROOT/cmdmiss.stop.out")"
fi
if kill -0 "$DECOY2_PID" 2>/dev/null; then
  pass "AC-10: stop PID-mismatch (command-name) — decoy untouched"
else
  fail "AC-10: stop PID-mismatch (command-name) — decoy was killed"
fi
kill -TERM "$DECOY2_PID" 2>/dev/null || true

###############################################################################
# AC-11: stop PID-mismatch defense (cwd). A second dashboard runs in FX_B;
#        FX_A's PID file is cross-written to FX_B's PID. The cwd check must
#        fail and FX_B's dashboard must NOT be killed.
###############################################################################

FX_B=$(make_fixture B "$BASE_B")
CLAUDE_PROJECT_DIR="$FX_B"
run_mode "$FX_B" start >"$TMP_ROOT/B.start.out" 2>&1 || true
B_PID=""
if [ -f "$FX_B/.zskills/dashboard-server.pid" ]; then
  B_PID=$(grep -oE '^pid=[0-9]+' "$FX_B/.zskills/dashboard-server.pid" | cut -d= -f2)
fi
[ -n "${B_PID:-}" ] && TRACKED_PIDS="$TRACKED_PIDS $B_PID"
if [ -n "$B_PID" ] && kill -0 "$B_PID" 2>/dev/null; then
  pass "AC-11: pre-condition — second dashboard running in FX_B (pid $B_PID)"

  cat > "$FX_A/.zskills/dashboard-server.pid" <<EOF
pid=$B_PID
port=$BASE_B
started_at=$(date -Iseconds)
EOF
  CLAUDE_PROJECT_DIR="$FX_A"
  if run_mode "$FX_A" stop >"$TMP_ROOT/cwdmiss.stop.out" 2>&1; then
    CWDMISS_RC=0
  else
    CWDMISS_RC=$?
  fi
  if [ "$CWDMISS_RC" -eq 1 ]; then
    pass "AC-11: stop PID-mismatch (cwd) — exit 1"
  else
    fail "AC-11: stop PID-mismatch (cwd) — exit was $CWDMISS_RC, expected 1"
  fi
  if grep -q 'does not appear to be zskills-dashboard for this repo' "$TMP_ROOT/cwdmiss.stop.out"; then
    pass "AC-11: stop PID-mismatch (cwd) — diagnostic printed"
  else
    fail "AC-11: stop PID-mismatch (cwd) — diagnostic missing: $(cat "$TMP_ROOT/cwdmiss.stop.out")"
  fi
  if kill -0 "$B_PID" 2>/dev/null; then
    pass "AC-11: stop PID-mismatch (cwd) — FX_B's dashboard untouched"
  else
    fail "AC-11: stop PID-mismatch (cwd) — FX_B's dashboard was killed!"
  fi

  # Stop FX_B cleanly. FX_A's PID file currently points at FX_B's PID;
  # rewrite it to FX_A's OWN running dashboard PID so AC-7 has a real
  # target. Find FX_A's dashboard among live servers by cwd == FX_A.
  CLAUDE_PROJECT_DIR="$FX_B"
  run_mode "$FX_B" stop >/dev/null 2>&1 || true
  rm -f "$FX_A/.zskills/dashboard-server.pid"
  for cand in $(pgrep -f 'python3.*zskills_monitor.server' 2>/dev/null); do
    cand_cwd=$(readlink "/proc/$cand/cwd" 2>/dev/null || echo "")
    if [ "$cand_cwd" = "$FX_A" ]; then
      A_HEALTH=$(curl -sf -m 1 "http://127.0.0.1:$BASE_A/api/health" 2>/dev/null || true)
      if printf '%s' "$A_HEALTH" | grep -qE '"status":[[:space:]]*"ok"'; then
        cat > "$FX_A/.zskills/dashboard-server.pid" <<EOF
pid=$cand
port=$BASE_A
started_at=$(date -Iseconds)
EOF
      fi
      break
    fi
  done
else
  fail "AC-11: pre-condition — second dashboard in FX_B did not start (skipping cwd-mismatch test): $(cat "$TMP_ROOT/B.start.out")"
fi

###############################################################################
# AC-7: stop removes the PID file and frees the port within 5s.
# AC-9: stop twice → second prints no-PID-file message, exits 0.
###############################################################################

if [ -f "$FX_A/.zskills/dashboard-server.pid" ]; then
  STOP_PORT_AC7=$(grep -oE '^port=[0-9]+' "$FX_A/.zskills/dashboard-server.pid" | cut -d= -f2)
  STOP_START_TS=$(date +%s)
  CLAUDE_PROJECT_DIR="$FX_A"
  if run_mode "$FX_A" stop >"$TMP_ROOT/A.stop.out" 2>&1; then
    STOP_END_TS=$(date +%s)
    STOP_ELAPSED=$((STOP_END_TS - STOP_START_TS))
    if [ "$STOP_ELAPSED" -le 5 ]; then
      pass "AC-7: stop completed within 5s (took ${STOP_ELAPSED}s)"
    else
      fail "AC-7: stop took ${STOP_ELAPSED}s (>5s)"
    fi
    if [ ! -f "$FX_A/.zskills/dashboard-server.pid" ]; then
      pass "AC-7: stop removed the PID file"
    else
      fail "AC-7: stop did NOT remove the PID file"
    fi
    if [ -n "$STOP_PORT_AC7" ]; then
      if lsof -iTCP:"$STOP_PORT_AC7" -sTCP:LISTEN >/dev/null 2>&1; then
        fail "AC-7: port $STOP_PORT_AC7 still has a listener after stop"
      else
        pass "AC-7: port $STOP_PORT_AC7 is free after stop"
      fi
    fi
  else
    fail "AC-7: stop returned non-zero: $(cat "$TMP_ROOT/A.stop.out")"
  fi

  # AC-9: stop twice → second is no-op, exit 0.
  if run_mode "$FX_A" stop >"$TMP_ROOT/A.stop2.out" 2>&1; then
    if grep -q 'No running dashboard' "$TMP_ROOT/A.stop2.out"; then
      pass "AC-9: stop twice — second prints 'No running dashboard' (idempotent)"
    else
      fail "AC-9: stop twice — unexpected output: $(cat "$TMP_ROOT/A.stop2.out")"
    fi
  else
    fail "AC-9: stop twice — second invocation returned non-zero"
  fi
else
  fail "AC-7 / AC-9: FX_A has no PID file to stop (cleanup branch failed)"
fi

print_summary_and_exit
