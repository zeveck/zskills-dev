#!/bin/bash
# tests/test-resolve-python.sh — unit tests for hooks/_lib/resolve-python.sh's
# zskills_resolve_python() (issue #1075).
#
# The function must PROBE-RUN each candidate, not merely check existence. The
# Windows failure mode it guards against: `command -v python3` finds the MS
# Store App-Execution-Alias stub `python3.exe`, which prints "Python was not
# found…" and exits non-zero when actually run. A plain existence check would
# latch that stub and never reach the user's real `python`.
#
# Hermetic: every case runs with a synthesized PATH (a temp dir holding fake
# interpreters) so the test is independent of the host's real Python layout.
# pass/fail inline (mirrors tests/test-hook-helper-drift.sh:22-25).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/hooks/_lib/resolve-python.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Locate a real python3 on the host to back the "real" fakes with.
REAL_PY="$(command -v python3 || command -v python || true)"
if [ -z "$REAL_PY" ]; then
  echo "SKIP: no host python3/python available to back the test fixtures" >&2
  echo "Results: 0 passed, 0 failed (of 0)"
  exit 0
fi

# Make a wrapper executable named $1 in dir $2 that execs the real python3.
make_real_py() {
  local name="$1" dir="$2"
  cat > "$dir/$name" <<EOF
#!/bin/sh
exec "$REAL_PY" "\$@"
EOF
  chmod +x "$dir/$name"
}

# Make a fake MS-Store-style stub named $1 in dir $2: prints the store message
# (to stderr by default, or stdout if \$3 == stdout) and exits non-zero (9009,
# the Windows "command not found" code the alias uses).
make_stub() {
  local name="$1" dir="$2" where="${3:-stderr}"
  if [ "$where" = "stdout" ]; then
    cat > "$dir/$name" <<'EOF'
#!/bin/sh
echo "Python was not found; run without arguments to install from the Microsoft Store, or disable this shortcut from Settings > Apps > Advanced app settings > App execution aliases."
exit 9009
EOF
  else
    cat > "$dir/$name" <<'EOF'
#!/bin/sh
echo "Python was not found; run without arguments to install from the Microsoft Store, or disable this shortcut from Settings > Apps > Advanced app settings > App execution aliases." >&2
exit 9009
EOF
  fi
  chmod +x "$dir/$name"
}

# Make a fake python2 named $1 in dir $2 (reports major version 2).
make_py2() {
  local name="$1" dir="$2"
  cat > "$dir/$name" <<'EOF'
#!/bin/sh
# Emulate a python2: any `-c` probe that asks for version_info[0]==3 exits 1.
case "$*" in
  *version_info*)
    # python2-style: report major 2 → the resolver's `==3` probe exits 1.
    exit 1 ;;
  --version) echo "Python 2.7.18" >&2; exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$dir/$name"
}

# The resolver subshell only needs `bash` to start (everything else it uses —
# `command`, the candidate interpreters — is either a builtin or the fakes we
# place). We must NOT leak the host's real python3 (in /bin & /usr/bin) onto the
# subshell PATH, or cases (d)/(e') would wrongly resolve. So build a minimal
# tools dir holding ONLY a bash symlink and append THAT (not /usr/bin).
BASH_BIN="$(command -v bash)"
TOOLS_DIR="$(mktemp -d)"
ln -s "$BASH_BIN" "$TOOLS_DIR/bash"

# Run zskills_resolve_python in a clean subshell with a controlled PATH and
# env. Echoes the resolved path on stdout; subshell exit code is the rc.
# $path holds the test's fake-interpreter dirs (highest precedence); $TOOLS_DIR
# (bash only, no python) is appended so the shell can start without leaking a
# real interpreter.
run_resolver() {
  local path="$1" zpy="$2"
  if [ -n "$zpy" ]; then
    env -i PATH="$path:$TOOLS_DIR" ZSKILLS_PYTHON="$zpy" "$BASH_BIN" -c ". '$HELPER'; zskills_resolve_python"
  else
    env -i PATH="$path:$TOOLS_DIR" "$BASH_BIN" -c ". '$HELPER'; zskills_resolve_python"
  fi
}

echo "=== zskills_resolve_python ==="

# (a) Picks a real python3 when present.
A_DIR="$(mktemp -d)"
make_real_py python3 "$A_DIR"
OUT="$(run_resolver "$A_DIR" "")"; RC=$?
if [ "$RC" -eq 0 ] && [ "$OUT" = "$A_DIR/python3" ]; then
  pass "(a) picks real python3 on PATH"
else
  fail "(a) expected $A_DIR/python3 rc=0, got '$OUT' rc=$RC"
fi

# (b) SKIPS a fake python3 stub (stderr variant) earlier on PATH and lands on a
#     real `python` later.
B1_DIR="$(mktemp -d)"   # holds the stub python3 (earlier on PATH)
B2_DIR="$(mktemp -d)"   # holds the real python (later on PATH)
make_stub python3 "$B1_DIR" stderr
make_real_py python "$B2_DIR"
OUT="$(run_resolver "$B1_DIR:$B2_DIR" "")"; RC=$?
if [ "$RC" -eq 0 ] && [ "$OUT" = "$B2_DIR/python" ]; then
  pass "(b) skips stderr-stub python3, lands on real python"
else
  fail "(b) expected $B2_DIR/python rc=0, got '$OUT' rc=$RC"
fi

# (b') Same but the stub prints to STDOUT instead of stderr.
B3_DIR="$(mktemp -d)"
B4_DIR="$(mktemp -d)"
make_stub python3 "$B3_DIR" stdout
make_real_py python "$B4_DIR"
OUT="$(run_resolver "$B3_DIR:$B4_DIR" "")"; RC=$?
if [ "$RC" -eq 0 ] && [ "$OUT" = "$B4_DIR/python" ]; then
  pass "(b') skips stdout-stub python3, lands on real python"
else
  fail "(b') expected $B4_DIR/python rc=0, got '$OUT' rc=$RC"
fi

# (c) Honors ZSKILLS_PYTHON (a real interpreter at an explicit path).
C_DIR="$(mktemp -d)"
make_real_py mypy3 "$C_DIR"
# Empty PATH dir so the only way to resolve is via ZSKILLS_PYTHON's abs path.
C_EMPTY="$(mktemp -d)"
OUT="$(run_resolver "$C_EMPTY" "$C_DIR/mypy3")"; RC=$?
if [ "$RC" -eq 0 ] && [ "$OUT" = "$C_DIR/mypy3" ]; then
  pass "(c) honors ZSKILLS_PYTHON override"
else
  fail "(c) expected $C_DIR/mypy3 rc=0, got '$OUT' rc=$RC"
fi

# (c') ZSKILLS_PYTHON pointing at a stub is rejected; falls through to PATH.
C2_STUB="$(mktemp -d)"
make_stub badpy "$C2_STUB" stderr
C2_REAL="$(mktemp -d)"
make_real_py python3 "$C2_REAL"
OUT="$(run_resolver "$C2_REAL" "$C2_STUB/badpy")"; RC=$?
if [ "$RC" -eq 0 ] && [ "$OUT" = "$C2_REAL/python3" ]; then
  pass "(c') ZSKILLS_PYTHON stub rejected → falls through to real python3 on PATH"
else
  fail "(c') expected $C2_REAL/python3 rc=0, got '$OUT' rc=$RC"
fi

# (d) Returns empty / non-zero when none work (only a stub on PATH).
D_DIR="$(mktemp -d)"
make_stub python3 "$D_DIR" stderr
OUT="$(run_resolver "$D_DIR" "")"; RC=$?
if [ "$RC" -ne 0 ] && [ -z "$OUT" ]; then
  pass "(d) only-stub PATH → empty output + non-zero rc"
else
  fail "(d) expected empty/non-zero, got '$OUT' rc=$RC"
fi

# (d') Truly empty PATH (no python at all) → empty + non-zero.
D2_DIR="$(mktemp -d)"
OUT="$(run_resolver "$D2_DIR" "")"; RC=$?
if [ "$RC" -ne 0 ] && [ -z "$OUT" ]; then
  pass "(d') no interpreter anywhere → empty output + non-zero rc"
else
  fail "(d') expected empty/non-zero, got '$OUT' rc=$RC"
fi

# (e) Rejects a fake python2 (version_info[0]==2) and lands on a real python3.
E_PY2="$(mktemp -d)"
make_py2 python3 "$E_PY2"       # a python2 masquerading as python3 first on PATH
E_REAL="$(mktemp -d)"
make_real_py python "$E_REAL"
OUT="$(run_resolver "$E_PY2:$E_REAL" "")"; RC=$?
if [ "$RC" -eq 0 ] && [ "$OUT" = "$E_REAL/python" ]; then
  pass "(e) rejects python2, lands on real python3"
else
  fail "(e) expected $E_REAL/python rc=0, got '$OUT' rc=$RC"
fi

# (e') python2-only PATH → empty + non-zero (no python3 to fall back to).
E2_DIR="$(mktemp -d)"
make_py2 python "$E2_DIR"
OUT="$(run_resolver "$E2_DIR" "")"; RC=$?
if [ "$RC" -ne 0 ] && [ -z "$OUT" ]; then
  pass "(e') python2-only PATH → empty output + non-zero rc"
else
  fail "(e') expected empty/non-zero, got '$OUT' rc=$RC"
fi

# Cleanup temp dirs.
rm -rf "$A_DIR" "$B1_DIR" "$B2_DIR" "$B3_DIR" "$B4_DIR" "$C_DIR" "$C_EMPTY" \
       "$C2_STUB" "$C2_REAL" "$D_DIR" "$D2_DIR" "$E_PY2" "$E_REAL" "$E2_DIR" \
       "$TOOLS_DIR"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
