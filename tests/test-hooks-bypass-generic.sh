#!/bin/bash
# Tests for hooks (sub-suite, Test Suite Parallelization Phase 1b).
# Hook-bypass property enumeration (#513) — GENERIC hook. Locks the #556/#565 branch-context + HEAD-destination + target axes (conformance assertions A/B/C grep this file).
# This file is a MOVE of sections out of the former tests/test-hooks.sh
# monolith — every assertion is preserved verbatim. Run from repo root or
# any cwd: bash tests/test-hooks-bypass-generic.sh
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

echo "=== Hook-bypass property enumeration (#513) ==="

# Property-style enumeration of the push-to-main bypass cartesian product.
# Closes the closure cycle from issue #513 — 11 reactive PRs over 24 days
# (#73, #87, #195, #197, #306, #413, #417, #434, #435, #465, #486) each
# patching one new bypass form into block-unsafe-{generic,project}.sh and
# adding a single hand-written positive assertion. This loop instead
# enumerates the full cartesian product of:
#
#   wrapper      ∈ {bare, bash -c, sh -c, eval}
#   refspec_form ∈ {DEST, feat:DEST, HEAD:DEST, :DEST, localref:DEST}
#   force-prefix ∈ {"", "+"}
#   ref-prefix   ∈ {"", "refs/heads/"}
#   quote-style  ∈ {none, single, double}  (only meaningful for wrappers)
#   target       ∈ {main, master}  → expect_deny
#                  {feat/test}     → expect_allow
#                  {HEAD}          → branch-context dependent (see below)
#   branch       ∈ {main, feat/test}  (only meaningful for target=HEAD;
#                  non-HEAD targets are branch-independent because the
#                  parser never consults the current branch for them).
#                  For target=HEAD the hook resolves via
#                  `git branch --show-current` against the cwd repo, so
#                  branch=main → expect_deny, branch=feat/test → expect_allow.
#                  Issue #556 / closes the property-test matrix gap left
#                  by #515's runtime HEAD-resolution fix.
#
# Proves the cumulative normalization chain in
# hooks/block-unsafe-generic.sh:612-633 (colon-RHS → quote strip → '+' strip
# → 'refs/heads/' strip → HEAD-to-current-branch) and the equivalent regex
# in hooks/block-unsafe-project.sh.template:1037-1051 ([+:]?(refs/heads/)?
# (main|master)) plus the HEAD-token rewrite at :1057-1071 both handle every
# combination in this space. Any future regression in those normalization
# sites — or any new bypass form a future agent invents — fails here at CI
# time, breaking the patch-react-ship-patch-again cycle.
#
# Generic hook only (top-level expect_deny / expect_allow harness). Project
# hook is exercised below in a separate section because it requires
# setup_project_test_on_main per case.

GEN_PROP_DENY=0
GEN_PROP_ALLOW=0
GEN_PROP_CASES=0

for target in main master feat/test; do
  if [ "$target" = "feat/test" ]; then
    expected="allow"
  else
    expected="deny"
  fi
  for force in "" "+"; do
    for refp in "" "refs/heads/"; do
      # Build the post-colon destination part (what the hook normalizes).
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
          # Quote axis: bare wrapper → only no-quote variant (shell-level
          # quoting around a single arg is uninteresting for normalization
          # since the hook sees the raw text and the quote-strip handles
          # PUSH_TARGET="main'" residue already; that path is locked by
          # the #399 cases). For wrappers, both single and double quotes
          # are meaningful — they wrap the inner shell command.
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
            label="prop/$wrapper_kind/$q/${spec_kind}/${force:-noforce}${refp:+/refsheads}/${target}"
            GEN_PROP_CASES=$((GEN_PROP_CASES + 1))
            if [ "$expected" = "deny" ]; then
              expect_deny "$label" "$cmd"
              GEN_PROP_DENY=$((GEN_PROP_DENY + 1))
            else
              expect_allow "$label" "$cmd"
              GEN_PROP_ALLOW=$((GEN_PROP_ALLOW + 1))
            fi
          done
        done
      done
    done
  done
done

echo "  (#513 generic-hook enumeration: $GEN_PROP_CASES cases — $GEN_PROP_DENY deny, $GEN_PROP_ALLOW allow)"

# --- #556 extension: target=HEAD × branch axis ---
# `git push origin HEAD` resolves to the local checkout's current branch.
# From a main/master checkout this targets remote main/master and bypasses
# the literal-string compare in pre-#515 hook logic. The #515 runtime fix
# adds `if [ "$PUSH_TARGET" = "HEAD" ]; then PUSH_TARGET=$(git branch
# --show-current); fi` at block-unsafe-generic.sh:648-650. This block
# enumerates the same cartesian product as the main loop above with
# target=HEAD and a branch-context axis (main, feat/test), proving the
# fix handles every wrapper/force/refp/spec_kind/quote combination — not
# just the 4 hand-written cases shipped with PR #553.
#
# Branch is set by cd-ing into a temp repo created on that branch and
# letting the hook run `git branch --show-current` there. One repo per
# branch keeps setup cost flat.
for branch in main feat/test; do
  HEAD_REPO=$(make_branch_repo "$branch")
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
            label="prop/$wrapper_kind/$q/${spec_kind}/${force:-noforce}${refp:+/refsheads}/HEAD/branch=${branch}"
            GEN_PROP_CASES=$((GEN_PROP_CASES + 1))
            if [ "$expected" = "deny" ]; then
              expect_deny_from_repo "$HEAD_REPO" "$label" "$cmd"
              GEN_PROP_DENY=$((GEN_PROP_DENY + 1))
            else
              expect_allow_from_repo "$HEAD_REPO" "$label" "$cmd"
              GEN_PROP_ALLOW=$((GEN_PROP_ALLOW + 1))
            fi
          done
        done
      done
    done
  done
  rm -rf "$HEAD_REPO"
done

echo "  (#556 generic-hook HEAD-extension: total now $GEN_PROP_CASES cases — $GEN_PROP_DENY deny, $GEN_PROP_ALLOW allow)"

echo ""


echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
