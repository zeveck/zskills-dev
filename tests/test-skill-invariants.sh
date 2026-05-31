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
  'grep -rq "Idempotent re-entry check (chunked finish auto only)" skills/run-plan/'
check "chunked finish auto Phase 5c" \
  'grep -rq "Phase 5c — Chunked finish auto transition" skills/run-plan/'

# Phase B: cross-branch final verify
check "final-verify marker in research-and-go" \
  'grep -q "requires.verify-changes.final" skills/research-and-go/SKILL.md'
check "final-verify fulfillment ref" \
  'grep -q "fulfilled.verify-changes.final" skills/research-and-go/SKILL.md'
check "research-and-go pre-decides meta-plan path" \
  'grep -q "META_PLAN_PATH=" skills/research-and-go/SKILL.md'
check "research-and-go drops every 4h" \
  '! grep -q "every 4h now" skills/research-and-go/SKILL.md'

# Issue #601: /fix-issues PR-mode pr.md heredoc reads ${CHANGE_SUMMARY};
# the variable must be assigned in the same file before the heredoc.
# Sibling of #579 (META_PLAN_PATH), #582 ($GOAL), #592/#596
# (TRACKING_ID + PLAN_FILE). Read-before-assignment shipped empty
# "## Changes" sections in every PR-mode PR body.
check "fix-issues pr.md assigns CHANGE_SUMMARY before heredoc read" \
  'grep -qE "^[[:space:]]*CHANGE_SUMMARY=" skills/fix-issues/modes/pr.md'
check "fix-issues pr.md mirror assigns CHANGE_SUMMARY before heredoc read" \
  'grep -qE "^[[:space:]]*CHANGE_SUMMARY=" .claude/skills/fix-issues/modes/pr.md'

# Issue #606: variable-read-before-assignment family — close remaining
# 4 siblings (post-#603 closure-verification sweep). Each entry below
# names a (file, var) where the file's fenced bash blocks read $VAR but
# previously had zero assignment sites — causing failed-closed
# standalone invocations. Each pair is regression-pinned: an assignment
# (bare `VAR=`, case-branch `) VAR=`, `${VAR:=...}`, `${VAR:-...}`,
# `read VAR`, or `for VAR in`) must exist in the same file.
#
# Sibling of #601 above, but covers 4 vars across 3 source skills.
# Source + mirror both checked so drift catches early.
#
# Helper: emit 0 iff $1 file has an assignment-like construct for $2 var.
has_assign() {
  local f="$1" v="$2"
  grep -qE "(^|[^A-Za-z0-9_])${v}=" "$f" && return 0
  grep -qE "(^|[[:space:]])read[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*${v}([[:space:]]|$)" "$f" && return 0
  grep -qE "(^|[[:space:]])for[[:space:]]+${v}[[:space:]]+in[[:space:]]" "$f" && return 0
  grep -qE "\\\$\{${v}:=" "$f" && return 0
  grep -qE "\\\$\{${v}:-" "$f" && return 0
  return 1
}

# (file, var) pairs covering #606's 4 siblings, plus #629's 2 additional
# siblings (/quickfix $ZSKILLS_PIPELINE_ID, /draft-tests $ROUND_N and
# $PREV_INPUT) that were added via comments on #606 but missed by PR #626.
# Issue #629 chose targeted pairs over extending FAMILY_VARS_RE so that
# legitimate env-inherited reads of these var names in OTHER skills
# (e.g., a skill called by /fix-issues that reads ZSKILLS_PIPELINE_ID
# from the env) aren't surfaced as defects.
ISSUE_606_PAIRS=(
  "skills/draft-plan/SKILL.md|TRACKING_ID"
  "skills/draft-plan/SKILL.md|OUTPUT_FILE"
  "skills/draft-plan/SKILL.md|ROUND"
  "skills/fix-issues/modes/sync.md|TRACKING_ID"
  "skills/run-plan/subcommands/stop-next-status.md|PLAN_FILE"
  "skills/quickfix/SKILL.md|ZSKILLS_PIPELINE_ID"
  "skills/draft-tests/SKILL.md|ROUND_N"
  "skills/draft-tests/SKILL.md|PREV_INPUT"
)
for pair in "${ISSUE_606_PAIRS[@]}"; do
  f="${pair%%|*}"; v="${pair##*|}"
  if has_assign "$f" "$v"; then
    check "issue #606: $f assigns \$$v before any read" 'true'
  else
    check "issue #606: $f assigns \$$v before any read" 'false'
  fi
  # Mirror under .claude/ must match (drift catch).
  mf=".claude/$f"
  if [ -f "$mf" ]; then
    if has_assign "$mf" "$v"; then
      check "issue #606: mirror $mf assigns \$$v before any read" 'true'
    else
      check "issue #606: mirror $mf assigns \$$v before any read" 'false'
    fi
  fi
done

# Structural family scan — broad sweep across skills/**/*.md and
# block-diagram/**/*.md for the family-pattern variables (TRACKING_ID,
# PLAN_FILE, OUTPUT_FILE, META_PLAN_PATH, GOAL, CHANGE_SUMMARY, SPRINT_ID,
# ROUND). Each occurrence inside a ```bash...``` fence MUST be backed by
# an assignment in the same file. This catches the next person editing
# a skill body who copies the failed-closed read pattern without copying
# the resolver.
#
# Allow-list: files where the family-pattern variable is known to be
# inherited from a parent skill via ZSKILLS_PIPELINE_ID and is read in
# a mode/reference file that DOCUMENTS but does not own the resolver.
# Each entry SHOULD be replaced over time by an in-file resolver — the
# allow-list is the "known acceptable tail" of the closure, NOT a
# license to add more. Format: file<TAB>VAR. Add with a comment naming
# the upstream owner.
ISSUE_606_ALLOWLIST=(
  # /refine-plan's $ROUND is the per-round orchestrator counter mirrored
  # from /draft-plan; both files use the same shape. Same allow as
  # /draft-plan's ROUND (which the targeted pair above now resolves via
  # ${ROUND:-1} default). Filed: separate issue (post-#606 follow-up).
  "skills/refine-plan/SKILL.md	ROUND"
  # /research-and-plan's $GOAL is set by /research-and-go upstream; the
  # in-file resolver was added by #603 for /research-and-go's own GOAL
  # read but /research-and-plan reads it from env. Filed: separate
  # issue (post-#606 follow-up).
  "skills/research-and-plan/SKILL.md	GOAL"
  # PR-mode reference files inherit $PLAN_FILE and $TRACKING_ID from the
  # main SKILL.md's worktree preamble; these files are not entrypoints
  # so they don't need their own resolver. Filed: separate issue
  # (post-#606 follow-up) if the family-pattern test fails on them.
  "skills/run-plan/references/failure-protocol.md	PLAN_FILE"
  # After #725 extraction, PLAN_FILE is assigned in subcommands/stop-next-status.md
  # (Status mode's resolver) and modes/execute-phase.md (Phase 2 example); the
  # router SKILL.md reads it from the orchestrator's parsed $ARGUMENTS context.
  "skills/run-plan/SKILL.md	PLAN_FILE"
  "skills/run-plan/modes/execute-phase.md	PLAN_FILE"
  "skills/run-plan/modes/execute-phase.md	TRACKING_ID"
  "skills/run-plan/modes/pr.md	PLAN_FILE"
  "skills/run-plan/modes/pr.md	TRACKING_ID"
  "skills/commit/modes/pr.md	TRACKING_ID"
  "skills/fix-issues/modes/pr.md	SPRINT_ID"
)
FAMILY_VARS_RE='^(TRACKING_ID|PLAN_FILE|OUTPUT_FILE|META_PLAN_PATH|GOAL|CHANGE_SUMMARY|SPRINT_ID|ROUND)$'
FAMILY_FAIL=""
while IFS= read -r f; do
  # Inline awk: emit one var-name per bash-fence read of $VAR / ${VAR}.
  fence_vars=$(awk '
    /^```bash/ { in_b=1; next }
    /^```[^`]*$/ { in_b=0; next }
    !in_b { next }
    {
      s=$0
      while (match(s, /\$\{[A-Za-z_][A-Za-z0-9_]*|\$[A-Za-z_][A-Za-z0-9_]*/)) {
        tok=substr(s, RSTART, RLENGTH)
        s=substr(s, RSTART+RLENGTH)
        sub(/^\$\{?/, "", tok)
        print tok
      }
    }
  ' "$f" | sort -u)
  while IFS= read -r v; do
    [ -z "$v" ] && continue
    printf '%s\n' "$v" | grep -qE "$FAMILY_VARS_RE" || continue
    has_assign "$f" "$v" && continue
    # Check allow-list.
    allowed=0
    for entry in "${ISSUE_606_ALLOWLIST[@]}"; do
      if [ "$entry" = "$(printf '%s\t%s' "$f" "$v")" ]; then
        allowed=1; break
      fi
    done
    [ "$allowed" -eq 1 ] && continue
    FAMILY_FAIL+="$(printf '%s\t%s\n' "$f" "$v")"$'\n'
  done <<< "$fence_vars"
done < <(find skills block-diagram -name '*.md' -type f 2>/dev/null)
if [ -z "$FAMILY_FAIL" ]; then
  check 'issue #606: family-pattern vars (TRACKING_ID/PLAN_FILE/OUTPUT_FILE/META_PLAN_PATH/GOAL/CHANGE_SUMMARY/SPRINT_ID/ROUND) all have same-file assignments' 'true'
else
  printf '%s\n' "$FAMILY_FAIL" >&2
  check 'issue #606: family-pattern vars (TRACKING_ID/PLAN_FILE/OUTPUT_FILE/META_PLAN_PATH/GOAL/CHANGE_SUMMARY/SPRINT_ID/ROUND) all have same-file assignments' 'false'
fi

# Phase C: tool-list-aware dispatch (4 skills)
for f in skills/run-plan/modes/execute-phase.md skills/fix-issues/modes/sprint.md \
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

# Issue #577: Step 2 must not contradict the Skill-tool MUST clause with
# parallel-Agent-dispatch prose. The MUST clause makes /draft-plan
# dispatch intrinsically serial; any "concurrent" / "at most N"
# parallelism wording is unrealizable and is the documented past-failure
# trigger. Source AND mirror must both be clean.
for f in skills/research-and-plan/SKILL.md .claude/skills/research-and-plan/SKILL.md; do
  check "issue #577: no parallel-draft-plan contradiction in $f (no 'at most 3')" \
    "! grep -q 'at most 3' '$f'"
  check "issue #577: no parallel-draft-plan contradiction in $f (no 'concurrently')" \
    "! grep -q 'concurrently' '$f'"
  check "issue #577: canonical serial-dispatch prose present in $f" \
    "grep -q 'intrinsically serial' '$f'"
done

# Phase E: early requires-lockdown
# The marker creation must appear in Phase 1 (before Phase 2).
# Heuristic: the first occurrence of `requires.verify-changes.$TRACKING_ID`
# in skills/run-plan/SKILL.md must appear on a line BEFORE the first
# `## Phase 2` heading. If the anchor is missing entirely, fail.
LOCKDOWN_LINE=$(grep -n 'requires.verify-changes.\$TRACKING_ID' skills/run-plan/SKILL.md | head -1 | cut -d: -f1)
PHASE2_LINE=$(grep -n '^## Phases 2-6' skills/run-plan/SKILL.md | head -1 | cut -d: -f1)
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
  'grep -rq "Final-verify gate" skills/run-plan/'
check "Phase 5b: idempotent early-exit present" \
  'grep -rq "frontmatter is already.*status: complete" skills/run-plan/'

# Issue #110: adaptive cron backoff anchors (Mode A)
check "issue #110: in-progress-defers counter" \
  'grep -q "in-progress-defers" skills/run-plan/SKILL.md'
check "issue #110: cron-recovery-needed sentinel" \
  'grep -q "cron-recovery-needed" skills/run-plan/SKILL.md'
check "issue #110: cron-replace-failed WARN" \
  'grep -q "WARN cron-replace-failed" skills/run-plan/SKILL.md'
check "issue #110: backoff documented in finish-mode" \
  'grep -q "in-progress-defers" skills/run-plan/references/finish-mode.md'

# post-run-invariants.sh still invoked by /run-plan
check "post-run-invariants.sh invoked by /run-plan" \
  'grep -rq "post-run-invariants.sh" skills/run-plan/'

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
check "cleanup-merged: #816 -d → -D escalation block" \
  "grep -q 'escalated -d → -D after upstream-divergence refusal' '$CM_SRC'"
# Mirror the source too, so drift is caught immediately.
if [ -d ".claude/skills/cleanup-merged" ]; then
  check "mirror sync: cleanup-merged" \
    "diff -q 'skills/cleanup-merged/SKILL.md' '.claude/skills/cleanup-merged/SKILL.md' >/dev/null"
fi

# Tier-1 drift invariant (Phase E of 2026-05-01 recovery): every Tier-1
# script's CURRENT blob hash must be in
# `skills/update-zskills/references/tier1-shipped-hashes.txt`. Trivial
# check, can't be skipped, runs in shallow clones, catches drift at PR
# time. Complementary to test-update-zskills-migration.sh case 6c
# (which uses git history) — this one only needs the current tree.
#
# Past failure: 10 Tier-1 scripts drifted across PRs #128-#142 because
# case 6c (the only existing check) silently skipped on shallow clones
# in CI, and authors had no easy way to know they needed to update the
# hash file. This invariant is unconditional.
#
# Issue #380 fix: This block reads `git ls-tree HEAD`, which reflects the
# committed blob hash, NOT the working-tree content. Pre-commit, an agent
# may have modified a Tier-1 script in the working tree but the HEAD blob
# is still the OLD (registered) hash, producing a silent false-PASS. To
# force loud failure, we first check each Tier-1 script for uncommitted
# changes via `git diff --quiet HEAD -- <path>` and ERROR if any are dirty.
TIER1_DIRTY_OUT=$(
  awk -F'|' 'NR>1 && $3 ~ /^[[:space:]]*1[[:space:]]*$/ {
    gsub(/[[:space:]`]/, "", $2);
    owner=$4;
    sub(/^[[:space:]`]+/, "", owner);
    sub(/[[:space:]`(].*$/, "", owner);
    if (length($2) > 0) print $2 "\t" owner
  }' skills/update-zskills/references/script-ownership.md \
  | while IFS=$'\t' read -r name owner; do
      src="skills/$owner/scripts/$name"
      if [ ! -f "$src" ]; then
        src="block-diagram/$owner/scripts/$name"
        [ -f "$src" ] || continue
      fi
      if ! git diff --quiet HEAD -- "$src" 2>/dev/null; then
        echo "DIRTY: $src has uncommitted changes (working tree differs from HEAD); this test only checks committed state. Commit first, then re-run."
      fi
    done
)
if [ -z "$TIER1_DIRTY_OUT" ]; then
  check 'Tier-1 drift: pre-flight working-tree-vs-HEAD clean (committed-state check is meaningful)' 'true'
else
  echo "$TIER1_DIRTY_OUT" >&2
  check 'Tier-1 drift: pre-flight working-tree-vs-HEAD clean (committed-state check is meaningful)' 'false'
fi

TIER1_DRIFT_OUT=$(
  awk -F'|' 'NR>1 && $3 ~ /^[[:space:]]*1[[:space:]]*$/ {
    gsub(/[[:space:]`]/, "", $2);
    owner=$4;
    sub(/^[[:space:]`]+/, "", owner);
    sub(/[[:space:]`(].*$/, "", owner);
    if (length($2) > 0) print $2 "\t" owner
  }' skills/update-zskills/references/script-ownership.md \
  | while IFS=$'\t' read -r name owner; do
      src="skills/$owner/scripts/$name"
      if [ ! -f "$src" ]; then
        src="block-diagram/$owner/scripts/$name"
        [ -f "$src" ] || continue
      fi
      current_hash=$(git ls-tree HEAD "$src" 2>/dev/null | awk '{print $3}')
      [ -z "$current_hash" ] && continue
      if ! grep -qF "$current_hash" skills/update-zskills/references/tier1-shipped-hashes.txt; then
        echo "DRIFT: $name -> $current_hash ($src)"
      fi
    done
)
if [ -z "$TIER1_DRIFT_OUT" ]; then
  check 'Tier-1 drift: every current Tier-1 blob hash is in tier1-shipped-hashes.txt' 'true'
else
  echo "$TIER1_DRIFT_OUT" >&2
  check 'Tier-1 drift: every current Tier-1 blob hash is in tier1-shipped-hashes.txt' 'false'
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

# Issue #621: /briefing renderer paths must enumerate every canonical
# worktree category. PR #532 (#516 fix) added
# `landed-pr-merged-but-diverged` at the producer; readers
# (summary pill list, report "Needs Attention", worktrees-mode) silently
# dropped it. Sibling of #602 (BASH surface) and #618 (JS surface). The
# loose `grep -qF "'$status'"` check mirrors #602's pattern: assert each
# canonical category is at least referenced somewhere in the reader file,
# so a future category addition can't ship with a vocabulary-drift hole.
for _briefing_status in landed-full landed-pr-ready landed-pr-needs-attention \
                       landed-pr-merged landed-pr-abandoned landed-partial \
                       landed-pr-merged-but-diverged empty named orphaned; do
  check "briefing.py references canonical category '$_briefing_status' (source)" \
    "grep -qF \"'$_briefing_status'\" skills/briefing/scripts/briefing.py"
  check "briefing.py references canonical category '$_briefing_status' (mirror)" \
    "grep -qF \"'$_briefing_status'\" .claude/skills/briefing/scripts/briefing.py"
done

# Issue #618: zskills-dashboard app.js landedPillClass() must enumerate every
# canonical .landed status value. PR #532's analog on briefing.py (#621) and
# fix-report/SKILL.md (#602) closed the prose/Python reader-side; this closes
# the JS reader-side. Canonical 11-value vocabulary is locked by
# tests/test-landed-status-vocabulary.sh; this pin asserts each value appears
# as a quoted literal in landedPillClass.
for _landed_status in full landed partial pr-ready pr-ci-failing pr-failed \
                      conflict pr-state-unknown failed direct-push-failed \
                      direct-verify-failed; do
  check "app.js landedPillClass references canonical status '$_landed_status' (source)" \
    "grep -qF '\"$_landed_status\"' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js"
  check "app.js landedPillClass references canonical status '$_landed_status' (mirror)" \
    "grep -qF '\"$_landed_status\"' .claude/skills/zskills-dashboard/scripts/zskills_monitor/static/app.js"
done

# Issue #649: CLAUDE.md Architecture section's skill counts must match
# `ls -d skills/*/` and `ls -d block-diagram/*/` (minus screenshots).
# Stale counts ship outdated framing to every consumer reading CLAUDE.md.
# These are two intentionally single-domain checks — one probes skills/,
# the sibling check probes block-diagram/ — so the framework-wide
# meta-lint's "must also reference block-diagram/" rule doesn't apply.
# The opt-out below must sit IMMEDIATELY before the first `check` line
# (no intervening non-marker lines) because the meta-lint resets the
# skip flag on any non-marker line.
# block-diagram-exempt: CLAUDE.md count check; sibling assertion below covers block-diagram/
check "CLAUDE.md skills/ count matches ls -d skills/*/" \
  "test \"\$(grep -oE '\\([0-9]+ core\\)' CLAUDE.md | head -1 | grep -oE '[0-9]+')\" = \"\$(ls -d skills/*/ | wc -l)\""
check "CLAUDE.md block-diagram/ count matches ls -d block-diagram/*/ (minus screenshots)" \
  "test \"\$(grep -oE 'add-on skills \\([0-9]+\\)' CLAUDE.md | head -1 | grep -oE '[0-9]+')\" = \"\$(ls -d block-diagram/*/ | grep -v screenshots | wc -l)\""

# Emit format expected by tests/run-all.sh
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
