#!/bin/bash
# Regression invariants for features deleted by faab84b.
#
# Asserts every restored feature's load-bearing anchor text exists.
# Catches faab84b-class silent deletions in CI before they escape
# to a release. If any check fails, the offending feature is
# silently gone — fix the skill, not this test.
#
# Output format follows tests/run-all.sh convention:
#   "Results: N passed, M failed"
# so run-all.sh aggregates counts.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASS=0
FAIL=0

check() {
  local desc="$1"
  local cmd="$2"
  if eval "$cmd"; then
    PASS=$((PASS+1))
  else
    echo "FAIL: $desc" >&2
    FAIL=$((FAIL+1))
  fi
}

# Phase A: chunked finish auto
check "chunked finish auto Step 0" \
  'grep -q "Idempotent re-entry check (chunked finish auto only)" skills/run-plan/SKILL.md'
check "chunked finish auto Phase 5c" \
  'grep -q "Phase 5c — Chunked finish auto transition" skills/run-plan/SKILL.md'

# Phase B: cross-branch final verify
check "final-verify marker in research-and-go" \
  'grep -q "requires.verify-changes.final" skills/research-and-go/SKILL.md'
check "final-verify fulfillment ref" \
  'grep -q "fulfilled.verify-changes.final" skills/research-and-go/SKILL.md'
check "research-and-go pre-decides meta-plan path" \
  'grep -q "META_PLAN_PATH=" skills/research-and-go/SKILL.md'
check "research-and-go drops every 4h" \
  '! grep -q "every 4h now" skills/research-and-go/SKILL.md'

# Phase C: tool-list-aware dispatch (4 skills)
for f in skills/run-plan/SKILL.md skills/fix-issues/SKILL.md \
         skills/verify-changes/SKILL.md \
         block-diagram/add-block/SKILL.md; do
  check "tool-list-aware dispatch in $f" \
    "grep -q 'Check your tool list' '$f'"
done

# Phase D: prohibition explanation (anchor phrases)
check "prohibition: subagents cannot dispatch" \
  'grep -q "Subagents in Claude Code cannot dispatch further subagents" skills/research-and-plan/SKILL.md'
check "prohibition: skill tool recursion mechanism" \
  'grep -q "Skill tool is the recursion mechanism" skills/research-and-plan/SKILL.md'
check "prohibition: docs URL" \
  'grep -q "code.claude.com/docs/en/sub-agents" skills/research-and-plan/SKILL.md'

# Phase E: early requires-lockdown
# The marker creation must appear in Phase 1 (before Phase 2).
# Heuristic: the first occurrence of `requires.verify-changes.$TRACKING_ID`
# in skills/run-plan/SKILL.md must appear on a line BEFORE the first
# `## Phase 2` heading. If the anchor is missing entirely, fail.
LOCKDOWN_LINE=$(grep -n 'requires.verify-changes.\$TRACKING_ID' skills/run-plan/SKILL.md | head -1 | cut -d: -f1)
PHASE2_LINE=$(grep -n '^## Phase 2' skills/run-plan/SKILL.md | head -1 | cut -d: -f1)
if [ -n "$LOCKDOWN_LINE" ] && [ -n "$PHASE2_LINE" ] && [ "$LOCKDOWN_LINE" -lt "$PHASE2_LINE" ]; then
  check "early requires-lockdown (Phase 1)" 'true'
else
  check "early requires-lockdown (Phase 1)" 'false'
fi

# Phase H: scope-vs-plan judgment in /verify-changes
check "verify-changes: scope assessment in review prompt" \
  'grep -q "Scope vs plan" skills/verify-changes/SKILL.md'
check "verify-changes: scope assessment in report format" \
  'grep -q "Scope Assessment" skills/verify-changes/SKILL.md'
check "verify-changes: argument parser" \
  'grep -q "Parsing \$ARGUMENTS" skills/verify-changes/SKILL.md'
check "verify-changes: branch-scope marker stem" \
  'grep -q "verify-changes.final" skills/verify-changes/SKILL.md'
check "/run-plan halts on scope-violation flag" \
  'grep -qr "Scope Assessment" skills/run-plan/'

# Phase A: Phase 5b idempotency + final-verify gate
check "Phase 5b: final-verify gate present" \
  'grep -q "Final-verify gate" skills/run-plan/SKILL.md'
check "Phase 5b: idempotent early-exit present" \
  'grep -q "frontmatter is already.*status: complete" skills/run-plan/SKILL.md'

# post-run-invariants.sh still invoked by /run-plan
check "post-run-invariants.sh invoked by /run-plan" \
  'grep -q "post-run-invariants.sh" skills/run-plan/SKILL.md'

# Mirror sync (catches restores that forget to mirror)
for f in run-plan research-and-go fix-issues verify-changes research-and-plan; do
  if [ -d ".claude/skills/$f" ]; then
    check "mirror sync: $f" \
      "diff -q 'skills/$f/SKILL.md' '.claude/skills/$f/SKILL.md' >/dev/null"
  fi
done

# /cleanup-merged worktree handling — each anchor must be present in the
# skill source. A missing anchor means the worktree-aware branch-delete
# path silently regressed to plain `git branch -D` (which fails on
# worktree-held branches). If any check fails, the desc names the
# missing piece.
CM_SRC="skills/cleanup-merged/SKILL.md"
check "cleanup-merged: worktree detection (git worktree list --porcelain)" \
  "grep -q 'git worktree list --porcelain' '$CM_SRC'"
check "cleanup-merged: worktree removal action (git worktree remove)" \
  "grep -q 'git worktree remove' '$CM_SRC'"
check "cleanup-merged: orphan cleanup (git worktree prune)" \
  "grep -q 'git worktree prune' '$CM_SRC'"
check "cleanup-merged: dirty-skip warning phrase" \
  "grep -q 'uncommitted changes — inspect and remove manually' '$CM_SRC'"
check "cleanup-merged: MAIN_ROOT comparison guard" \
  "grep -q 'MAIN_ROOT' '$CM_SRC'"
# Mirror the source too, so drift is caught immediately.
if [ -d ".claude/skills/cleanup-merged" ]; then
  check "mirror sync: cleanup-merged" \
    "diff -q 'skills/cleanup-merged/SKILL.md' '.claude/skills/cleanup-merged/SKILL.md' >/dev/null"
fi

# Cross-skill invariant: no skill statically prescribes `isolation: "worktree"`.
# All worktree work must go through skills/create-worktree/scripts/create-worktree.sh
# (manual creation) per plans/EXECUTION_MODES.md. Word-boundary on "with"
# distinguishes prescriptions ("Dispatch ... with `isolation: "worktree"`") from
# negative warnings ("WITHOUT `isolation: "worktree"`"), so existing migrated skills
# don't false-positive.
check 'no skill prescribes isolation: worktree (use skills/create-worktree/scripts/create-worktree.sh)' \
  '! grep -rEn '"'"'\bwith[[:space:]]+`?isolation: *"worktree"'"'"' skills/ block-diagram/ 2>/dev/null'

# Cross-skill invariant: no skill writes flat-layout tracking markers.
# Post-UNIFY_TRACKING_NAMES Phase 6, only $PIPELINE_ID-subdir writes
# are visible to the hook. Pattern matches `> "…/.zskills/tracking/<basename>"`
# where <basename> starts with a letter (rules out `$PIPELINE_ID/...`
# which begins with `$`). Pinned to the writer shape `> "…"` so prose
# and comment hits in skills/{quickfix,research-and-go,session-report,
# verify-changes,run-plan}/SKILL.md don't false-positive. See
# plans/BLOCK_DIAGRAM_TRACKING_CATCHUP.md for baseline-zero proof.
check 'no skill writes flat-layout tracking markers (post-UNIFY_TRACKING_NAMES)' \
  '! grep -rEn '"'"'> "[^"]*\.zskills/tracking/[a-zA-Z]'"'"' skills/ block-diagram/ 2>/dev/null'

# Meta-lint: every framework-wide cross-skill check must cover
# block-diagram/. Two prior framework migrations (isolation:worktree,
# UNIFY_TRACKING_NAMES) silently skipped block-diagram/ because the
# check enumerated skills/ alone.
#
# Detection rule: a `check` line references `skills/` as a
# framework-wide enumeration (matches the regex `[^A-Za-z]skills/`
# followed by whitespace, a quote, or end-of-line — NOT followed by
# a skill-name segment like `skills/run-plan/SKILL.md`). Such a
# check must also contain ` block-diagram/` (with whitespace
# boundary) somewhere in the same logical check invocation.
#
# CRITICAL — line-continuation handling: real `check` invocations
# span TWO physical lines via trailing `\` continuation, e.g.:
#   check '<desc>' \                  ← head: matches `^check`, lacks `skills/`
#     '! grep -rE ... skills/ ...'    ← body: has `skills/`, lacks `^check`
# A naive per-physical-line regex never finds the `^check && skills/`
# conjunction and the meta-lint passes vacuously. The pre-process
# step below joins `\\n` continuations so each logical check
# invocation collapses to one line BEFORE the regex runs.
#
# Opt-out: prefix the check with the comment
#   # block-diagram-exempt: <reason>
# on the immediately preceding line. Use sparingly — exemptions
# are by definition the surface that grows to bite us next time.
SCRIPT="$REPO_ROOT/tests/test-skill-invariants.sh"
_meta_skipped=0
_meta_failed=0
# Collapse `\\n` continuations into single logical lines.
# awk: when a line ends with `\`, drop the `\` and buffer; on the
# next line, prepend the buffer and emit. Comment lines pass
# through unchanged so the `# block-diagram-exempt:` opt-out
# still works on the preceding-line basis.
joined=$(awk '
  /\\$/ { sub(/\\$/,""); buf = buf $0; next }
  buf   { print buf $0; buf = ""; next }
        { print }
' "$SCRIPT")
while IFS= read -r line; do
  case "$line" in
    *"# block-diagram-exempt:"*) _meta_skipped=1; continue ;;
  esac
  # Match logical-check lines that enumerate skills/ as a path.
  # Regex: skills/ preceded by non-alpha, followed by space,
  # single-quote, double-quote, or end-of-line (i.e., a path arg
  # at a directory boundary) — NOT skills/<name>/ (alpha after
  # slash, single-skill probe) NOR skills/$f/... (variable
  # interpolation, also single-skill probe by convention). The
  # post-slash class must be path-terminator-shaped, not just
  # non-alpha — `$` is non-alpha, but `skills/$f/SKILL.md` is the
  # mirror-sync per-skill loop body at
  # `tests/test-skill-invariants.sh:101-102`, which is single-skill
  # by intent. After the awk-join above, both predicates evaluate
  # against the same logical line.
  if printf '%s' "$line" | grep -qE '^[[:space:]]*check ' \
     && printf '%s' "$line" | grep -qE '[^A-Za-z]skills/([[:space:]'\''"]|$)'; then
    if [ "$_meta_skipped" -eq 1 ]; then
      _meta_skipped=0
      continue
    fi
    if ! printf '%s' "$line" | grep -qE '[^A-Za-z]block-diagram/'; then
      echo "META-LINT FAIL: framework-wide check missing block-diagram/ coverage: $line" >&2
      _meta_failed=1
    fi
  else
    _meta_skipped=0
  fi
done <<<"$joined"
if [ "$_meta_failed" -eq 0 ]; then
  check 'meta: framework-wide checks cover block-diagram/' 'true'
else
  check 'meta: framework-wide checks cover block-diagram/' 'false'
fi

# Emit format expected by tests/run-all.sh
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
