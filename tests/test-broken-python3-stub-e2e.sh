#!/usr/bin/env bash
# tests/test-broken-python3-stub-e2e.sh — END-TO-END regression guard for the
# Microsoft-Store `python3` App-Execution-Alias stub class (issue #1086).
#
# ── WHY THIS EXISTS ───────────────────────────────────────────────────────
# The Windows install broke in many places (#1075/#1079/#1080/#1083) because
# the MS Store `python3` stub is FIRST on PATH: it prints "Python was not
# found…" and exits 9009 when actually run, while the user's real interpreter
# is `python` (no `3`). The dogfood/CI environment HAS a working python3, so
# the stub bug could NEVER surface here — it slipped through unit tests + a
# clean CI all the way to the user's real Windows box (bare `python3` in 11
# skill bodies, #1083).
#
# `tests/test-resolve-python.sh` already fakes a stub at the RESOLVER-FUNCTION
# level (unit). This harness closes the integration gap: it puts a BROKEN
# `python3` first on PATH (real `python` behind it) and runs the ACTUAL flows
# end-to-end — (a) the SessionStart materialiser and (b) a representative
# skill-body fence (/briefing) — asserting both resolve via `$PYTHON`, succeed,
# and that NOTHING ever invoked the stub (a sentinel marker proves it).
#
# ── THE LIMIT (do NOT mistake this for a full Windows qual) ───────────────
# This harness catches the PYTHON-RESOLUTION class only — roughly 90% of the
# observed Windows breakage. It runs on Linux/CI with a fake stub; it does
# NOT catch true Windows-isms:
#   * `C:\`-style / drive-letter paths
#   * Git Bash vs cmd.exe vs PowerShell shell semantics
#   * CRLF line endings
# Those still require a real Windows run. Passing this test means the
# python-on-Windows resolution class is guarded — NOT that the install is
# Windows-clean.
#
# Hermetic: a unique temp dir per run holds the fake stub, a real-python
# wrapper, a fixture consumer project, and the stub's hit-marker; PATH is
# synthesized for each flow and the host PATH is never mutated; everything is
# cleaned up on EXIT.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Locate a real python3/python on the host to back the "real" interpreter that
# lives BEHIND the stub on the synthesized PATH. Without one, the resolver
# would have nothing to fall through to and the test would be meaningless.
REAL_PY="$(command -v python3 || command -v python || true)"
if [ -z "$REAL_PY" ]; then
  echo "SKIP: no host python3/python available to back the real-interpreter fixture" >&2
  echo "Results: 0 passed, 0 failed (of 0)"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── Build the fake MS-Store python3 stub (FIRST on PATH) ──────────────────
# Behavior mirrors the real App-Execution-Alias: prints the store message to
# stderr and exits 9009. CRUCIALLY it also APPENDS a line to $STUB_MARKER on
# every invocation that is NOT the resolver's harmless version-probe — that
# marker is our sentinel. The resolver is EXPECTED to probe-run the stub (that is
# how it detects the stub is broken). What must NEVER happen is the stub being
# used as `$PYTHON` to run actual work (briefing.py, the materialiser's JSON
# round-trips, etc.). We distinguish by argv: a `-c 'import sys; sys.exit…'`
# version-probe is the resolver doing its job; ANYTHING else (a .py script
# path, a `-c` that is not the version probe) means the stub leaked through as
# the chosen interpreter. We log only the latter to $STUB_MARKER.
BIN_STUB="$TMP/bin-stub"      # holds the stub `python3` (FIRST on PATH)
BIN_REAL="$TMP/bin-real"      # holds the real `python` (BEHIND the stub)
mkdir -p "$BIN_STUB" "$BIN_REAL"
STUB_MARKER="$TMP/stub-hits.log"
: > "$STUB_MARKER"            # start empty

cat > "$BIN_STUB/python3" <<STUB
#!/bin/sh
# Fake Microsoft-Store python3 App-Execution-Alias stub (issue #1086 harness).
# Record any NON-version-probe invocation as a stub leak, then emit the store
# message and exit 9009 (the real alias's "command not found" behavior).
case "\$*" in
  "-c import sys; sys.exit(0 if sys.version_info[0]==3 else 1)")
    # Resolver version-probe — expected; the resolver runs this to DETECT that
    # we are broken. Do NOT record it as a leak. Still exit non-zero (broken).
    : ;;
  *)
    # Any other invocation means the stub was chosen as \$PYTHON to do real
    # work — that is the bug. Record the full argv as a leak.
    printf 'STUB LEAK argv: %s\n' "\$*" >> "$STUB_MARKER" ;;
esac
echo "Python was not found; run without arguments to install from the Microsoft Store, or disable this shortcut from Settings > Apps > Advanced app settings > App execution aliases." >&2
exit 9009
STUB
chmod +x "$BIN_STUB/python3"

# Real `python` (no `3`) BEHIND the stub — what the resolver must fall through
# to. Exec the host's real interpreter.
cat > "$BIN_REAL/python" <<REAL
#!/bin/sh
exec "$REAL_PY" "\$@"
REAL
chmod +x "$BIN_REAL/python"

# A minimal tools dir holding the non-python utilities the flows need (git,
# bash, coreutils, etc.). We must NOT leak the host's real python3 (in
# /usr/bin) onto the synthesized PATH, or the resolver would latch it instead
# of exercising the stub→real-python fallthrough. So we expose a curated set of
# tool dirs that are unlikely to contain a python3, plus explicit symlinks for
# the essentials. Simplest robust approach: put $BIN_STUB and $BIN_REAL first,
# then append the host PATH but with any dir that holds a real python3 still
# behind our fakes (the stub's `python3` shadows them by precedence anyway).
#
# Precedence is what matters: $BIN_STUB first means `command -v python3`
# resolves to the stub; $BIN_REAL before the host means `python` resolves to
# our wrapper. The host PATH tail supplies git/coreutils. A host python3 in the
# tail is harmless — it can never win against $BIN_STUB/python3.
STUB_PATH="$BIN_STUB:$BIN_REAL:$PATH"

# Sanity: confirm the synthesized PATH actually puts the stub first and the
# stub is genuinely broken (non-zero exit), so the rest of the test is
# meaningful. NOTE: the stub `exit 9009`, but POSIX shells truncate exit status
# to 8 bits, so the observed rc is 9009 % 256 = 49 (still non-zero, which is all
# the resolver's probe cares about). This sanity probe is NOT one of the real
# flows, so we run it FIRST and then RESET $STUB_MARKER below — otherwise this
# deliberate `print("hi")` invocation would (correctly) register as a leak and
# pollute the cross-cutting sentinel assertion (test 7).
PROBE_OUT="$(PATH="$STUB_PATH" python3 -c 'print("hi")' 2>&1)"; PROBE_RC=$?
RESOLVED_PY3="$(PATH="$STUB_PATH" command -v python3)"
if [ "$RESOLVED_PY3" = "$BIN_STUB/python3" ] && [ "$PROBE_RC" -ne 0 ]; then
  pass "0. fixture: stub python3 is FIRST on PATH and broken (non-zero rc=$PROBE_RC)"
else
  fail "0. fixture sanity: resolved python3='$RESOLVED_PY3' rc=$PROBE_RC (expected stub + non-zero rc)"
fi

# Reset the leak marker now that the fixture sanity probe (which intentionally
# ran the stub) is done. From here on, ANY content in $STUB_MARKER is a real
# leak from flow (a) or (b).
: > "$STUB_MARKER"

# ──────────────────────────────────────────────────────────────────────────
# Flow (a): SessionStart materialiser end-to-end under the broken-stub PATH.
# ──────────────────────────────────────────────────────────────────────────
# Build a FRESH fixture consumer project (lane=fresh): a config + root
# CLAUDE_TEMPLATE.md so the materialiser can render managed.md. CLAUDE_PLUGIN_ROOT
# points at the repo (dogfood source-tree layout), matching
# tests/test-sessionstart-materialise.sh.
PROJ="$TMP/proj"
mkdir -p "$PROJ/.claude"
cp "$REPO_ROOT/.claude/zskills-config.json" "$PROJ/.claude/"
cp "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$PROJ/"

MAT_OUT="$TMP/materialise.out"
PATH="$STUB_PATH" env CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
  bash "$REPO_ROOT/hooks/session-start-materialise.sh" > "$MAT_OUT" 2>&1
MAT_RC=$?

V="$PROJ/.claude/agents/verifier.md"
I="$PROJ/.claude/agents/implementer.md"
H1="$PROJ/.claude/hooks/inject-bash-timeout.sh"
H2="$PROJ/.claude/hooks/verify-response-validate.sh"
M="$PROJ/.claude/rules/zskills/managed.md"

# 1. Materialiser must complete cleanly (exit 0) — it must NOT abort on the
#    stub (the #1075/#1079 failure mode where it bailed "no working Python 3").
if [ "$MAT_RC" -eq 0 ]; then
  pass "1. materialiser exits 0 under broken-stub PATH"
else
  fail "1. materialiser rc=$MAT_RC (expected 0); output: $(cat "$MAT_OUT")"
fi

# 2. It must NOT have emitted the "no working Python 3" abort message.
if grep -q "no working Python 3 found" "$MAT_OUT"; then
  fail "2. materialiser reported 'no working Python 3' — resolver did not fall through to real python"
else
  pass "2. materialiser did NOT report 'no working Python 3'"
fi

# 3. All five artifacts materialised (proves the python-driven render/inject
#    steps actually ran via the real interpreter).
if [ -f "$V" ] && [ -f "$I" ] && [ -f "$H1" ] && [ -f "$H2" ] && [ -f "$M" ]; then
  pass "3. all 5 artifacts materialised end-to-end under the stub"
else
  fail "3. missing artifact(s): V=$([ -f "$V" ]&&echo y||echo n) I=$([ -f "$I" ]&&echo y||echo n) H1=$([ -f "$H1" ]&&echo y||echo n) H2=$([ -f "$H2" ]&&echo y||echo n) M=$([ -f "$M" ]&&echo y||echo n)"
fi

# 4. The rendered managed.md must carry the substitution from the config
#    (project name) — proves render-managed-rules.py ran via the real python,
#    not a no-op.
PROJECT_NAME="$("$REAL_PY" -c 'import json;print(json.load(open("'"$PROJ"'/.claude/zskills-config.json")).get("project_name",""))')"
if [ -n "$PROJECT_NAME" ] && [ -f "$M" ] && grep -qF "$PROJECT_NAME" "$M"; then
  pass "4. managed.md rendered with project_name '$PROJECT_NAME' (python render ran via real interpreter)"
else
  fail "4. managed.md missing rendered project_name '$PROJECT_NAME'"
fi

# ──────────────────────────────────────────────────────────────────────────
# Flow (b): a representative SKILL-BODY fence (/briefing) end-to-end.
# ──────────────────────────────────────────────────────────────────────────
# /briefing's fences source zskills-resolve-config.sh (which exports $PYTHON
# via the same probe-run resolver) then invoke `"$PYTHON" briefing.py <sub>`.
# We reproduce that fence shape EXACTLY against the real prelude + real script,
# under the broken-stub PATH. The `worktrees` subcommand emits a clean JSON
# array (deterministic, no side effects) we can assert on.
#
# The fence runs against the REAL repo (CLAUDE_PROJECT_DIR=$REPO_ROOT) so the
# prelude + briefing.py operate on a real git worktree, exactly as in a live
# /briefing invocation.
BRIEF_OUT="$TMP/briefing.out"
PATH="$STUB_PATH" CLAUDE_PROJECT_DIR="$REPO_ROOT" bash -c '
  set -u
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  if [ -z "${PYTHON:-}" ]; then
    echo "FENCE-ERROR: \$PYTHON empty after sourcing prelude" >&2
    exit 3
  fi
  "$PYTHON" "$ZSKILLS_SKILLS_ROOT/briefing/scripts/briefing.py" worktrees
' > "$BRIEF_OUT" 2>"$TMP/briefing.err"
BRIEF_RC=$?

# 5. The skill-body fence succeeds (exit 0).
if [ "$BRIEF_RC" -eq 0 ]; then
  pass "5. /briefing skill-body fence exits 0 under broken-stub PATH"
else
  fail "5. /briefing fence rc=$BRIEF_RC; stderr: $(cat "$TMP/briefing.err")"
fi

# 6. The fence produced correct output — valid JSON array from briefing.py
#    (proves it ran via the real interpreter, not a stub that exits 9009 with
#    no stdout).
if [ -s "$BRIEF_OUT" ] && "$REAL_PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d,list) else 1)' "$BRIEF_OUT"; then
  pass "6. /briefing fence produced valid JSON array (real python ran the script)"
else
  fail "6. /briefing fence output is not a valid JSON array; head: $(head -c 200 "$BRIEF_OUT")"
fi

# ──────────────────────────────────────────────────────────────────────────
# Cross-cutting sentinel: NOTHING used the stub as the chosen interpreter.
# ──────────────────────────────────────────────────────────────────────────
# The stub records a "STUB LEAK" line for any invocation that is NOT the
# resolver's harmless version-probe. An empty marker proves both flows resolved
# to the real `python` and never ran real work through the broken `python3`.
if [ ! -s "$STUB_MARKER" ]; then
  pass "7. stub-hit marker is EMPTY — no flow ran real work through the broken python3"
else
  fail "7. stub was used as the interpreter for real work:"
  while IFS= read -r line; do printf '       %s\n' "$line"; done < "$STUB_MARKER"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
