#!/bin/bash
# hooks/_lib/resolve-python.sh — source-of-truth body for the working-Python-3
# interpreter resolver shared by every hook / helper script that needs Python.
#
# The function is inlined VERBATIM into each shipped consumer (the materialised
# inject-bash-timeout.sh + every legacy-mirror hook cannot reach this _lib file,
# so the body must be pasted in); the drift gate at
# tests/test-hook-helper-drift.sh enforces byte-equality at CI time. The body is
# also inlined into the skill helper scripts under skills/**/scripts/ for the
# same uniformity (they run from worktrees / sprint roots where _lib is not on a
# reliable relative path).
#
# Maintain HERE only.

# zskills_resolve_python — print path to a working Python 3 interpreter, or
# empty if none. Probe-RUNS each candidate (existence is NOT enough: on Windows
# `command -v python3` finds the MS Store App-Execution-Alias stub, which exits
# non-zero when run). Honors ZSKILLS_PYTHON. Rejects python2.
zskills_resolve_python() {
  local cand
  for cand in "${ZSKILLS_PYTHON:-}" python3 python; do
    [ -n "$cand" ] || continue
    command -v "$cand" >/dev/null 2>&1 || continue
    if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
      command -v "$cand"; return 0
    fi
  done
  return 1
}
