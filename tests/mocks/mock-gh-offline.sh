#!/bin/bash
# mock-gh-offline.sh — stateless, deterministic offline stub for `gh`.
#
# Purpose: make the dashboard-monitor test suite (collect.py / server.py /
# dashboard UI) HERMETIC to the live GitHub API. collect.py fires
# `gh issue list` from SUBPROCESSES it spawns (the server, or the
# `--repo-root` CLI), which bypasses the in-process `_runner` / `issue_runner`
# dependency-injection seam — an in-process runner cannot reach a child
# process. A PATH-prefixed mock `gh` IS inherited by the child, so this stub
# intercepts every `gh` invocation in those subprocesses.
#
# Why NOT tests/mocks/mock-gh.sh: that mock is STATEFUL (per-call counter,
# exit 99 on an unprepared call). collect.py's gh-call COUNT is
# non-deterministic across a run — the 60s TTL cache, multiple /api/state
# polls, and open-vs-closed fetches all vary — so a counter-keyed mock would
# spuriously exhaust its canned responses and exit 99. This stub is the
# stateless complement: it answers ANY `gh issue list` (open or closed) with
# a deterministic empty JSON array and exits 0, and is a successful no-op for
# any other subcommand. The live tests it serves assert plan-set parity,
# snapshot key/shape contracts, repo_root, byte-identity, and HTTP codes —
# NONE depend on live issue content, so an empty list is correct and keeps
# the suite deterministic (no live issue state leaking into pass counts).
#
# Optional invocation logging: if MOCK_GH_LOG is set, each invocation's
# argv is appended (one line) for tests that want to assert gh was/ wasn't
# called.

set -u

if [ -n "${MOCK_GH_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$MOCK_GH_LOG"
fi

ARG1="${1:-}"
ARG2="${2:-}"

# `gh issue list ...` (open or closed) → deterministic empty JSON array.
# collect.py json.loads() the stdout and iterates; [] yields zero issues,
# which every live-firing assertion tolerates.
if [ "$ARG1" = "issue" ] && [ "$ARG2" = "list" ]; then
  printf '[]\n'
  exit 0
fi

# `gh --version` and any other subcommand: succeed quietly. collect.py only
# ever shells `gh issue list`; this branch exists so an unexpected probe
# never errors the suite.
exit 0
