#!/bin/bash
# Tests for hooks (sub-suite, Test Suite Parallelization Phase 1b).
# Class-pinned negative/positive matrices (project + generic) and Hook-bypass property enumeration (#513) — PROJECT hook. Uses setup_project_test_on_main per case. Locks the #556/#565 axes (conformance A/B/C grep this file too).
# This file is a MOVE of sections out of the former tests/test-hooks.sh
# monolith — every assertion is preserved verbatim. Run from repo root or
# any cwd: bash tests/test-hooks-bypass-project.sh
#
# SOURCES tests/lib/hooks-harness.sh for all shared helpers and the
# absolutized hook-path globals (HOOK / PROJECT_HOOK / AGENTS_HOOK /
# WARN_HOOK), pass/fail counters, expect_* helpers, the project-hook
# fixture helpers, and setup_project_test_on_main. Emits exactly ONE
# canonical Results: line. Registered in run-all.sh as a run_suite; it
# carries no self-registration assertion (matches the former monolith).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-unsafe-generic.sh"

# shellcheck source=tests/lib/hooks-harness.sh
. "$SCRIPT_DIR/lib/hooks-harness.sh"

echo "=== Class-pinned negative matrix: project hook (144 cases) ==="

# 12 read-only commands × 3 git-verbs × 4 quote-shapes = 144 negative cases.
# Each shape contains `git $VERB` with literal space — exercises the bare-
# substring bug class directly. Path-substring and flag-value adjacent
# classes are exercised separately below (24 cases).
for CMD in grep sed awk cat echo printf head tail less more file wc; do
  for VERB in commit cherry-pick push; do
    for SHAPE in single double unquoted-with-space flag-with-space; do
      case "$SHAPE" in
        single)              ARG="'git $VERB foo'" ;;
        double)              ARG="\"git $VERB foo\"" ;;
        unquoted-with-space) ARG="git $VERB foo bar" ;;
        flag-with-space)     ARG="--pattern \"git $VERB\"" ;;
      esac
      FULL="$CMD $ARG /tmp/notes.md"
      setup_project_test_on_main
      expect_project_allow "matrix-$CMD-$VERB-$SHAPE" "$FULL"
      teardown_project_test
    done
  done
done

# Round-2 DA2-H-4 invariant assertion (defense-in-depth): all per-iteration
# teardowns must have removed temp state. If anything leaks, fail loudly so
# a teardown bug or hook side-effect doesn't hide cross-case contamination.
LEAKED=$(find /tmp -maxdepth 2 -type d -name 'tmp.*' -newer "$REPO_ROOT/CHANGELOG.md" 2>/dev/null | wc -l)
if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
  fail "matrix-invariant: TEST_TMPDIR=$TEST_TMPDIR still exists after teardown loop"
else
  pass "matrix-invariant: per-iteration teardown left TEST_TMPDIR clean"
fi

echo "=== Class-pinned negative matrix: generic hook (192 cases) ==="

# 8 read-only commands × 6 verbs × 4 quote-shapes = 192 negative cases.
# Verb set excludes the unmigrated subset (rm -rf / find -delete / rsync /
# xargs / fuser) per round-1 DA-C-2: bare regex on those still fires on
# `grep "rm -rf foo"` and a matrix entry would correctly FAIL. CHANGELOG
# bullet 4 documents that as out-of-scope for this plan.
for CMD in grep sed awk cat echo printf head tail; do
  for VERB in "git restore" "git clean -f" "git reset --hard" "git add -A" "git commit --no-verify" "kill -9"; do
    for SHAPE in single double unquoted-with-space flag-with-space; do
      case "$SHAPE" in
        single)              ARG="'$VERB foo'" ;;
        double)              ARG="\"$VERB foo\"" ;;
        unquoted-with-space) ARG="$VERB foo bar" ;;
        flag-with-space)     ARG="--pattern \"$VERB\"" ;;
      esac
      FULL="$CMD $ARG /tmp/notes.md"
      SAFE_VERB="$(echo "$VERB" | tr ' /-' '___')"
      expect_allow "matrix-$CMD-$SAFE_VERB-$SHAPE" "$FULL"
    done
  done
done

echo "=== Adjacent-class coverage (24 cases) ==="

# Path-substring (`grep git-commit-notes.md`) and flag-value
# (`grep --pattern=git-commit`) — these do NOT exercise the bare-regex bug
# class (no literal space between `git` and verb), but they DO exercise the
# adjacent classes. Round-1 R-H-4 split out for honest coverage labeling.
# Bare top-level helpers (no main_protected dependency).
for CMD in grep sed awk cat echo printf head tail; do
  for VERB in commit cherry-pick push; do
    expect_project_allow "adjacent-class-pathsub-$CMD-$VERB" "$CMD git-$VERB-notes.md"
    expect_project_allow "adjacent-class-flagval-$CMD-$VERB"  "$CMD --pattern=git-$VERB /tmp/notes.md"
  done
done

echo "=== Class-pinned positive matrix (24 cases — must DENY) ==="

# 6 destructive-verb invocations × 4 invocation-shape variants = 24 positive
# cases that MUST DENY. Asserts the migration doesn't weaken the positive
# surface AT THE CLASS LEVEL (complementing per-verb regressions in 3.4/4.5).
#
# 6 verbs spread across project + generic hooks:
#   project-hook: git commit, git cherry-pick, git push (require on-main setup)
#   generic-hook: git restore, git clean -f, kill -9 (no main_protected setup)
# 4 shapes:
#   bare         — naked invocation
#   leading-ws   — leading whitespace before the verb
#   env-prefix   — env-var assignment prefix (FOO=bar verb …)
#   subdir-cd    — `cd /tmp/wt && verb …` (chain wrapper exercise)

# Project-hook positives.
for VERB_PAYLOAD in "git commit -m foo" "git cherry-pick abc123" "git push"; do
  VERB_LABEL="$(echo "$VERB_PAYLOAD" | tr ' /-' '___' | tr -s '_')"
  for SHAPE in bare leading-ws env-prefix subdir-cd; do
    case "$SHAPE" in
      bare)        FULL="$VERB_PAYLOAD" ;;
      leading-ws)  FULL="    $VERB_PAYLOAD" ;;
      env-prefix)  FULL="GIT_TRACE=1 $VERB_PAYLOAD" ;;
      subdir-cd)   FULL="cd /tmp/wt && $VERB_PAYLOAD" ;;
    esac
    setup_project_test_on_main
    expect_project_deny "positive-matrix-$VERB_LABEL-$SHAPE" "$FULL"
    teardown_project_test
  done
done

# Generic-hook positives.
for VERB_PAYLOAD in "git restore ." "git clean -f" "kill -9 1234"; do
  VERB_LABEL="$(echo "$VERB_PAYLOAD" | tr ' /.-' '____' | tr -s '_')"
  for SHAPE in bare leading-ws env-prefix subdir-cd; do
    case "$SHAPE" in
      bare)        FULL="$VERB_PAYLOAD" ;;
      leading-ws)  FULL="    $VERB_PAYLOAD" ;;
      env-prefix)  FULL="GIT_TRACE=1 $VERB_PAYLOAD" ;;
      subdir-cd)   FULL="cd /tmp/wt && $VERB_PAYLOAD" ;;
    esac
    expect_deny "positive-matrix-$VERB_LABEL-$SHAPE" "$FULL"
  done
done



echo "=== Hook-bypass property enumeration: project hook (#513) ==="

# Same matrix replayed against the rendered project hook with
# main_protected: true. Uses setup_project_test_on_main per case (matches
# the existing "Class-pinned negative matrix: project hook" pattern at
# tests/test-hooks.sh:2070). Proves the project-hook regex form
# `[+:]?(refs/heads/)?(main|master)` plus the post-colon rule handle the
# same combinatorial space. Adds the project hook to the closure cycle
# this test prevents.
#
# Note: this section uses an inline assertion (run_main_protected_test
# returns the hook output; we check for "deny" substring) rather than the
# expect_project_* helpers because those source from $TEST_TMPDIR which
# requires explicit setup. Inline matches the existing PR1-PR11 pattern
# at line 1933+ that also calls run_main_protected_test directly.

PROJ_PROP_DENY=0
PROJ_PROP_ALLOW=0
PROJ_PROP_CASES=0

for target in main master feat/test; do
  if [ "$target" = "feat/test" ]; then
    expected="allow"
  else
    expected="deny"
  fi
  for force in "" "+"; do
    for refp in "" "refs/heads/"; do
      dest="${force}${refp}${target}"
      for spec_kind in bare feat HEAD del localref; do
        case "$spec_kind" in
          bare)     refspec="$dest" ;;
          feat)     refspec="feat:${dest}" ;;
          HEAD)     refspec="HEAD:${dest}" ;;
          del)      refspec=":${dest}" ;;
          localref) refspec="localref:${dest}" ;;
        esac
        for wrapper_kind in bare bash-c sh-c eval; do
          if [ "$wrapper_kind" = "bare" ]; then
            quote_styles="none"
          else
            quote_styles="single double"
          fi
          for q in $quote_styles; do
            case "$q" in
              none)   inner_q="" ;;
              single) inner_q="'" ;;
              double) inner_q="\"" ;;
            esac
            inner="git push origin $refspec"
            case "$wrapper_kind" in
              bare)   cmd="$inner" ;;
              bash-c) cmd="bash -c ${inner_q}${inner}${inner_q}" ;;
              sh-c)   cmd="sh -c ${inner_q}${inner}${inner_q}" ;;
              eval)   cmd="eval ${inner_q}${inner}${inner_q}" ;;
            esac
            label="proj-prop/$wrapper_kind/$q/${spec_kind}/${force:-noforce}${refp:+/refsheads}/${target}"
            PROJ_PROP_CASES=$((PROJ_PROP_CASES + 1))
            # run_main_protected_test on a feat/test branch with main_protected:true.
            # The branch parameter to run_main_protected_test sets the
            # CURRENT branch of the test repo (used by rule (c) — naked
            # push on main); for refspec-bearing pushes (rules a + b) the
            # current branch is irrelevant because the destination is
            # parsed from the args. Using feat/test as the current branch
            # isolates the bypass-matrix to rules a + b — exactly the
            # surface this test exercises.
            RESULT=$(run_main_protected_test "feat/test" '{"execution": {"main_protected": true}}' "$cmd")
            if [ "$expected" = "deny" ]; then
              if [[ "$RESULT" == *"permissionDecision"*"deny"* ]]; then
                pass "deny: $label"
                PROJ_PROP_DENY=$((PROJ_PROP_DENY + 1))
              else
                fail "deny: $label — expected deny, got: $RESULT"
              fi
            else
              if [[ "$RESULT" != *"permissionDecision"*"deny"* ]]; then
                pass "allow: $label"
                PROJ_PROP_ALLOW=$((PROJ_PROP_ALLOW + 1))
              else
                fail "allow: $label — expected allow, got: $RESULT"
              fi
            fi
          done
        done
      done
    done
  done
done

echo "  (#513 project-hook enumeration: $PROJ_PROP_CASES cases — $PROJ_PROP_DENY deny, $PROJ_PROP_ALLOW allow)"

# --- #556 extension: target=HEAD × branch axis (project hook) ---
# Same matrix as the generic-hook HEAD extension above, but exercised
# against the rendered project hook with main_protected:true. The project
# hook resolves HEAD via the token rewrite at block-unsafe-project.sh.
# template:1057-1071 — `git branch --show-current` against the test repo,
# then PUSH_ARGS substitution before rules (a)/(b) match. Branch is set
# via run_main_protected_test's first arg (which `git checkout -b`s the
# fixture repo onto that branch).
for branch in main feat/test; do
  if [ "$branch" = "main" ]; then
    expected="deny"
  else
    expected="allow"
  fi
  for force in "" "+"; do
    for refp in "" "refs/heads/"; do
      dest="${force}${refp}HEAD"
      for spec_kind in bare feat HEAD del localref; do
        case "$spec_kind" in
          bare)     refspec="$dest" ;;
          feat)     refspec="feat:${dest}" ;;
          HEAD)     refspec="HEAD:${dest}" ;;
          del)      refspec=":${dest}" ;;
          localref) refspec="localref:${dest}" ;;
        esac
        for wrapper_kind in bare bash-c sh-c eval; do
          if [ "$wrapper_kind" = "bare" ]; then
            quote_styles="none"
          else
            quote_styles="single double"
          fi
          for q in $quote_styles; do
            case "$q" in
              none)   inner_q="" ;;
              single) inner_q="'" ;;
              double) inner_q="\"" ;;
            esac
            inner="git push origin $refspec"
            case "$wrapper_kind" in
              bare)   cmd="$inner" ;;
              bash-c) cmd="bash -c ${inner_q}${inner}${inner_q}" ;;
              sh-c)   cmd="sh -c ${inner_q}${inner}${inner_q}" ;;
              eval)   cmd="eval ${inner_q}${inner}${inner_q}" ;;
            esac
            label="proj-prop/$wrapper_kind/$q/${spec_kind}/${force:-noforce}${refp:+/refsheads}/HEAD/branch=${branch}"
            PROJ_PROP_CASES=$((PROJ_PROP_CASES + 1))
            RESULT=$(run_main_protected_test "$branch" '{"execution": {"main_protected": true}}' "$cmd")
            if [ "$expected" = "deny" ]; then
              if [[ "$RESULT" == *"permissionDecision"*"deny"* ]]; then
                pass "deny: $label"
                PROJ_PROP_DENY=$((PROJ_PROP_DENY + 1))
              else
                fail "deny: $label — expected deny, got: $RESULT"
              fi
            else
              if [[ "$RESULT" != *"permissionDecision"*"deny"* ]]; then
                pass "allow: $label"
                PROJ_PROP_ALLOW=$((PROJ_PROP_ALLOW + 1))
              else
                fail "allow: $label — expected allow, got: $RESULT"
              fi
            fi
          done
        done
      done
    done
  done
done

echo "  (#556 project-hook HEAD-extension: total now $PROJ_PROP_CASES cases — $PROJ_PROP_DENY deny, $PROJ_PROP_ALLOW allow)"




echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
