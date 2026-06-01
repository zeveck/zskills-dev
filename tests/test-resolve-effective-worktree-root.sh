#!/bin/bash
# tests/test-resolve-effective-worktree-root.sh — unit tests for the
# `extract_cd_target` and `resolve_effective_worktree_root` helpers in
# hooks/_lib/resolve-effective-worktree-root.sh (#401).
#
# Coverage:
#   - extract_cd_target:
#       * leading `cd /tmp/wt && ...` shapes (chain operators)
#       * JSON-wire-escaped newline (`\n` two-char) inside command
#       * quoted target path (single/double quotes stripped)
#       * non-existent target (returns empty)
#       * no leading `cd` (returns empty)
#       * env-var-prefixed `KEY=val cd ...` (recognized — #924)
#       * shell preamble before cd: `set -e; cd …`, `export X=Y; cd …`,
#         `. resolver.sh && cd …`, mixed-preamble (#924)
#       * preamble of inert statements that does NOT contain a cd → empty
#         (e.g., `set -e; git commit -m foo`)
#   - resolve_effective_worktree_root:
#       * env_override takes precedence over cd_target AND fallback
#       * cd_target takes precedence over fallback when env_override empty
#       * fallback echoed when first two tiers empty
#       * empty env_override + empty cd_target + non-empty fallback
#       * all-empty edge case (echoes empty string from fallback)
#
# Run standalone: `bash tests/test-resolve-effective-worktree-root.sh`
# exits 0 if all cases pass.

# Locate and source the source-of-truth helper.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../hooks/_lib/resolve-effective-worktree-root.sh"

PASS=0
FAIL=0

pass() { echo "PASS $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }

# ─── extract_cd_target tests ───
# extract_cd_target reads $INPUT (the hook's captured stdin JSON envelope).
# We construct $INPUT inline for each case.

# Create a real directory we can use as a valid cd target (helpers check
# [ -d "$target" ] before echoing).
TMPDIR_REAL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_REAL"' EXIT

# CE1 — bare cd to existing dir.
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $TMPDIR_REAL && git commit -m foo\"}}"
got=$(extract_cd_target)
if [ "$got" = "$TMPDIR_REAL" ]; then
  pass "CE1 cd <existing-dir> && git commit → echoes target"
else
  fail "CE1 expected [$TMPDIR_REAL] got [$got]"
fi

# CE2 — cd with extra spaces.
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd   $TMPDIR_REAL && ls\"}}"
got=$(extract_cd_target)
if [ "$got" = "$TMPDIR_REAL" ]; then
  pass "CE2 cd with multi-space → echoes target"
else
  fail "CE2 expected [$TMPDIR_REAL] got [$got]"
fi

# CE3 — JSON-wire-escaped newline (cd /tmp/x\ngit commit).
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $TMPDIR_REAL\\ngit commit\"}}"
got=$(extract_cd_target)
if [ "$got" = "$TMPDIR_REAL" ]; then
  pass "CE3 cd <dir>\\n (JSON-wire newline) → decoded, target echoed"
else
  fail "CE3 expected [$TMPDIR_REAL] got [$got]"
fi

# CE4 — non-existent target → empty.
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd /nonexistent/path/zzz && ls\"}}"
got=$(extract_cd_target)
if [ -z "$got" ]; then
  pass "CE4 cd <non-existent> → empty"
else
  fail "CE4 expected empty, got [$got]"
fi

# CE5 — no leading cd → empty.
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m foo\"}}"
got=$(extract_cd_target)
if [ -z "$got" ]; then
  pass "CE5 no leading cd → empty"
else
  fail "CE5 expected empty, got [$got]"
fi

# CE6 — env-var prefix BEFORE cd is recognized (#924: orchestrator-side
# `VAR=val cd /tmp/wt && git commit` is a real shape we see in practice).
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"FOO=bar cd $TMPDIR_REAL && git commit\"}}"
got=$(extract_cd_target)
if [ "$got" = "$TMPDIR_REAL" ]; then
  pass "CE6 env-var-prefixed cd (#924) → echoes target"
else
  fail "CE6 expected [$TMPDIR_REAL] got [$got]"
fi

# CE7 — semicolon separator (cd /tmp/x; git commit).
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $TMPDIR_REAL; git commit\"}}"
got=$(extract_cd_target)
if [ "$got" = "$TMPDIR_REAL" ]; then
  pass "CE7 cd <dir>; <cmd> (semicolon separator) → echoes target"
else
  fail "CE7 expected [$TMPDIR_REAL] got [$got]"
fi

# ─── #924 preamble shapes ───
# Orchestrator-side worktree bookkeeping commits routinely emit commands
# with a shell preamble before the cd: `set -e`, `export FOO=bar`,
# `source <resolver>` / `. <resolver>`, `VAR=val cd …`. Pre-#924 the
# extract regex required `^cd …`, falling back to the ambient main-repo
# cwd and triggering false-positive "main is protected" blocks.

# CE8 — `set -e` preamble.
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"set -e; cd $TMPDIR_REAL && git commit -m foo\"}}"
got=$(extract_cd_target)
if [ "$got" = "$TMPDIR_REAL" ]; then
  pass "CE8 #924: set -e; cd <dir> → echoes target"
else
  fail "CE8 expected [$TMPDIR_REAL] got [$got]"
fi

# CE9 — `export VAR=val` preamble.
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"export FOO=bar; cd $TMPDIR_REAL && git commit\"}}"
got=$(extract_cd_target)
if [ "$got" = "$TMPDIR_REAL" ]; then
  pass "CE9 #924: export VAR=val; cd <dir> → echoes target"
else
  fail "CE9 expected [$TMPDIR_REAL] got [$got]"
fi

# CE10 — `. <file>` (source) preamble joined with &&.
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\". /tmp/resolver.sh && cd $TMPDIR_REAL && git commit\"}}"
got=$(extract_cd_target)
if [ "$got" = "$TMPDIR_REAL" ]; then
  pass "CE10 #924: . <file> && cd <dir> → echoes target"
else
  fail "CE10 expected [$TMPDIR_REAL] got [$got]"
fi

# CE11 — `source <file>` preamble joined with &&.
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"source /tmp/resolver.sh && cd $TMPDIR_REAL && git commit\"}}"
got=$(extract_cd_target)
if [ "$got" = "$TMPDIR_REAL" ]; then
  pass "CE11 #924: source <file> && cd <dir> → echoes target"
else
  fail "CE11 expected [$TMPDIR_REAL] got [$got]"
fi

# CE12 — mixed preamble (set -e + export + cd).
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"set -e; export FOO=bar; cd $TMPDIR_REAL && git commit -m foo\"}}"
got=$(extract_cd_target)
if [ "$got" = "$TMPDIR_REAL" ]; then
  pass "CE12 #924: set -e; export X=Y; cd <dir> → echoes target"
else
  fail "CE12 expected [$TMPDIR_REAL] got [$got]"
fi

# CE13 — preamble that does NOT lead to a cd → empty (no false-positive
# extraction from an inert-statement prefix).
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"set -e; export FOO=bar; git commit -m foo\"}}"
got=$(extract_cd_target)
if [ -z "$got" ]; then
  pass "CE13 #924: preamble without cd → empty"
else
  fail "CE13 expected empty, got [$got]"
fi

# CE14 — newline-separated preamble (multi-line bash command).
# Wire-format double-escape: agent JSON encodes a real newline as `\n`,
# and we already test `\n` decoding in CE3. Here use the same wire form.
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"set -e\\nexport FOO=bar\\ncd $TMPDIR_REAL\\ngit commit\"}}"
got=$(extract_cd_target)
if [ "$got" = "$TMPDIR_REAL" ]; then
  pass "CE14 #924: multi-line preamble + cd → echoes target"
else
  fail "CE14 expected [$TMPDIR_REAL] got [$got]"
fi

# CE15 — non-preamble first statement (e.g., `git status`) before a cd
# should NOT silently extract the later cd. Pre-#924 the regex would not
# have matched either; post-#924 we explicitly stop at the first non-inert
# statement to preserve "first effective cwd" semantics.
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git status; cd $TMPDIR_REAL && git commit\"}}"
got=$(extract_cd_target)
if [ -z "$got" ]; then
  pass "CE15 #924: non-inert prefix before cd → empty (stop on first real statement)"
else
  fail "CE15 expected empty, got [$got]"
fi

# ─── resolve_effective_worktree_root tests ───

# RE1 — env_override non-empty → wins over cd_target + fallback.
got=$(resolve_effective_worktree_root "/env" "/cd" "/fallback")
if [ "$got" = "/env" ]; then
  pass "RE1 env_override set → echoes env_override"
else
  fail "RE1 expected [/env] got [$got]"
fi

# RE2 — env_override empty, cd_target non-empty → cd_target wins over fallback.
got=$(resolve_effective_worktree_root "" "/cd" "/fallback")
if [ "$got" = "/cd" ]; then
  pass "RE2 env_override empty, cd_target set → echoes cd_target"
else
  fail "RE2 expected [/cd] got [$got]"
fi

# RE3 — env_override + cd_target both empty → fallback.
got=$(resolve_effective_worktree_root "" "" "/fallback")
if [ "$got" = "/fallback" ]; then
  pass "RE3 env_override + cd_target empty → echoes fallback"
else
  fail "RE3 expected [/fallback] got [$got]"
fi

# RE4 — env_override empty, cd_target empty, fallback empty → empty.
got=$(resolve_effective_worktree_root "" "" "")
if [ -z "$got" ]; then
  pass "RE4 all-empty → echoes empty"
else
  fail "RE4 expected empty, got [$got]"
fi

# RE5 — env_override non-empty, others empty → env_override wins.
got=$(resolve_effective_worktree_root "/env" "" "")
if [ "$got" = "/env" ]; then
  pass "RE5 env_override non-empty, cd_target/fallback empty → env_override"
else
  fail "RE5 expected [/env] got [$got]"
fi

# RE6 — paths with spaces preserve correctly.
got=$(resolve_effective_worktree_root "" "/tmp/path with spaces" "/fallback")
if [ "$got" = "/tmp/path with spaces" ]; then
  pass "RE6 cd_target with spaces → preserved"
else
  fail "RE6 expected [/tmp/path with spaces] got [$got]"
fi

# ─── Integration: extract_cd_target + resolve_effective_worktree_root ───
# Mirror the call shape that lives in hooks/block-stale-skill-version.sh
# and the 3 sites in hooks/block-unsafe-project.sh.template.

# RI1 — template-style call: env-override empty, cd_target from $INPUT, git-rev-parse fallback.
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $TMPDIR_REAL && git commit\"}}"
got=$(resolve_effective_worktree_root "${LOCAL_ROOT:-}" "$(extract_cd_target)" "/fallback")
if [ "$got" = "$TMPDIR_REAL" ]; then
  pass "RI1 template-call shape: cd target picked up via extract_cd_target"
else
  fail "RI1 expected [$TMPDIR_REAL] got [$got]"
fi

# RI2 — template-style call with LOCAL_ROOT env override set.
LOCAL_ROOT="/override"
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $TMPDIR_REAL && git commit\"}}"
got=$(resolve_effective_worktree_root "${LOCAL_ROOT:-}" "$(extract_cd_target)" "/fallback")
if [ "$got" = "/override" ]; then
  pass "RI2 template-call with LOCAL_ROOT env override → override wins over cd_target"
else
  fail "RI2 expected [/override] got [$got]"
fi
unset LOCAL_ROOT

# RI3 — stale-skill-version-style call: no env override, CLAUDE_PROJECT_DIR fallback.
INPUT="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m foo\"}}"
got=$(resolve_effective_worktree_root "" "$(extract_cd_target)" "${CLAUDE_PROJECT_DIR:-/pwd-fallback}")
if [ "$got" = "${CLAUDE_PROJECT_DIR:-/pwd-fallback}" ]; then
  pass "RI3 stale-call shape: no cd, no env → fallback (CLAUDE_PROJECT_DIR)"
else
  fail "RI3 expected [${CLAUDE_PROJECT_DIR:-/pwd-fallback}] got [$got]"
fi

# ─── Summary ───
echo ""
echo "Total: PASS=$PASS FAIL=$FAIL"
echo "Results: $PASS passed, $FAIL failed (of $((PASS + FAIL)))"

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
