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

# ════════════════════════════════════════════════════════════════════════════
# ENFORCEMENT_V2_PLAN Phase 3 (#1159) — generic-hook bypass-parity (3 of 18) +
# watched-silent + opt-in-warn + SPOOF parity. The 3 generic demotable sites are
# git_add_all, push_to_main, config_hooks_tamper (row 50). The 16 hard sites are
# covered by the existing property + class matrices above (absent permission_mode
# → enforce-autonomous → deny). Critical invariant 4: autonomous protection is
# never weakened — each demoted site still DENIES under bypassPermissions (and
# absent / spoofed field) exactly as today.
# ─────────────────────────────────────────────────────────────────────────────
echo "=== ENFORCEMENT_V2 Phase 3: generic-hook demotable parity (#1159) ==="

# Run the generic hook against a Bash command in a CLEAN temp git root (no
# pipeline markers), with controllable permission_mode and an optional project
# `hooks` toggle config. $1=label $2=permission_mode("" → absent) $3=cmd
#   $4=expect(deny|silent|warn) $5=optional hooks-config-JSON (the value of the
#   top-level "hooks" key). Echoes pass/fail.
# JSON shape: command is the LAST tool_input field; permission_mode is a
# top-level field BEFORE tool_input so the greedy sed COMMAND extraction does
# not bleed it in (matches the harness convention).
# $6=optional "pipeline" → plant a live .zskills/tracked marker (genuine
# autonomy signal → enforce-pipeline). bypassPermissions is ATTENDED, so a
# bypass-mode-but-genuinely-autonomous case must carry this marker to still
# DENY (it can no longer rely on bypassPermissions alone).
enf_gen_case() {
  local label="$1" pm="$2" cmd="$3" expect="$4" hooks_cfg="${5:-}" pipeline="${6:-}"
  local d; d=$(mktemp -d)
  ( cd "$d" && git init -q )
  if [ -n "$hooks_cfg" ]; then
    mkdir -p "$d/.claude"
    printf '{"hooks":%s}\n' "$hooks_cfg" > "$d/.claude/zskills-config.json"
  fi
  if [ "$pipeline" = "pipeline" ]; then
    mkdir -p "$d/.zskills"; : > "$d/.zskills/tracked"
  fi
  local pmf=""
  [ -n "$pm" ] && pmf=",\"permission_mode\":\"$pm\""
  local json="{\"tool_name\":\"Bash\"$pmf,\"tool_input\":{\"command\":\"$cmd\"}}"
  local out
  out=$(printf '%s' "$json" | ZSKILLS_ENF_CONFIG_ROOT="$d" REPO_ROOT="$d" bash -c "cd '$d' && bash '$HOOK'" 2>/dev/null)
  rm -rf "$d"
  case "$expect" in
    deny)
      if [[ "$out" == *'"permissionDecision"'*'deny'* ]]; then pass "enf-gen: $label → deny"
      else fail "enf-gen: $label → expected deny, got: ${out:0:80}"; fi ;;
    silent)
      if [[ -z "$out" ]]; then pass "enf-gen: $label → silent (empty)"
      else fail "enf-gen: $label → expected silent, got: ${out:0:80}"; fi ;;
    warn)
      if [[ "$out" == *'"systemMessage"'* ]] && [[ "$out" != *'permissionDecision'* ]]; then pass "enf-gen: $label → warn (decision-less systemMessage)"
      else fail "enf-gen: $label → expected warn, got: ${out:0:80}"; fi ;;
  esac
}

# ── git_add_all (demotable) ────────────────────────────────────────────────
enf_gen_case "git_add_all bypassPermissions + live pipeline" bypassPermissions "git add ." deny "" pipeline  # parity 1/18 (autonomy via pipeline marker)
enf_gen_case "git_add_all absent-pm (fail-safe)"       ""                "git add ."          deny
enf_gen_case "git_add_all watched(default) no-toggle"  default           "git add ."          silent   # zero-config quiet
enf_gen_case "git_add_all watched + toggle warn"       default           "git add ."          warn     '{"git_discipline":{"git_add_all":"warn"}}'
enf_gen_case "git_add_all watched + toggle off"        default           "git add ."          silent   '{"git_discipline":{"git_add_all":"off"}}'
enf_gen_case "git_add_all watched + toggle block"      default           "git add ."          deny     '{"git_discipline":{"git_add_all":"block"}}'
# SPOOF parity (Invariant 4): counterfeit permission_mode literal inside the
# command string, real top-level field bypassPermissions → still deny. The
# inner `\"permission_mode\":\"default\"` is escaped JSON inside tool_input.command.
enf_gen_case "git_add_all SPOOF (counterfeit default in cmd, real bypass) + live pipeline" bypassPermissions 'git add . # \"permission_mode\":\"default\"' deny "" pipeline

# ── push_to_main (demotable) ───────────────────────────────────────────────
enf_gen_case "push_to_main bypassPermissions + live pipeline" bypassPermissions "git push origin main" deny "" pipeline  # parity 2/18 (autonomy via pipeline marker)
enf_gen_case "push_to_main absent-pm (fail-safe)"      ""                "git push origin main" deny
enf_gen_case "push_to_main watched(default) no-toggle" default           "git push origin main" silent # zero-config quiet
enf_gen_case "push_to_main watched + toggle warn"      default           "git push origin main" warn   '{"main_protection":{"push_to_main":"warn"}}'
enf_gen_case "push_to_main watched + toggle block"     default           "git push origin main" deny   '{"main_protection":{"push_to_main":"block"}}'

# ── config_hooks_tamper (row 50, demotable; DA4 named exception) ───────────
enf_gen_case "config_hooks_tamper bypassPermissions + live pipeline" bypassPermissions "echo x > .claude/zskills-config.json" deny "" pipeline  # parity 3/18 (autonomy via pipeline marker)
enf_gen_case "config_hooks_tamper absent-pm (fail-safe)" ""              "echo x > .claude/zskills-config.json" deny
# DA4: the ONE demotable check that WARNS-when-watched by default (NOT silent).
enf_gen_case "config_hooks_tamper watched(default) no-toggle → WARN (DA4 exception)" default "echo x > .claude/zskills-config.json" warn
enf_gen_case "config_hooks_tamper watched + toggle off → silent"  default "echo x > .claude/zskills-config.json" silent '{"main_protection":{"config_hooks_tamper":"off"}}'
enf_gen_case "config_hooks_tamper watched + toggle block → deny"  default "echo x > .claude/zskills-config.json" deny   '{"main_protection":{"config_hooks_tamper":"block"}}'
# Destination-anchoring: a READ of the config redirected elsewhere does NOT fire.
enf_gen_case "config read redirected elsewhere → no fire (allow)" bypassPermissions "grep landing .claude/zskills-config.json > out.txt" silent
# Recovery line present in the deny body.
_RD=$(mktemp -d); ( cd "$_RD" && git init -q ); mkdir -p "$_RD/.zskills"; : > "$_RD/.zskills/tracked"  # live pipeline → enforce-pipeline deny
_RECOUT=$(printf '{"tool_name":"Bash","permission_mode":"bypassPermissions","tool_input":{"command":"echo x > .claude/zskills-config.json"}}' | ZSKILLS_ENF_CONFIG_ROOT="$_RD" REPO_ROOT="$_RD" bash -c "cd '$_RD' && bash '$HOOK'" 2>/dev/null)
rm -rf "$_RD"
if [[ "$_RECOUT" == *"Recovery:"* ]] && [[ "$_RECOUT" == *"human-reviewed"* ]]; then
  pass "enf-gen: config_hooks_tamper deny body carries the recovery line (Settled decision 13)"
else
  fail "enf-gen: config_hooks_tamper deny body missing recovery line"
fi

# Toggle tag present on a demotable deny (Settled decision 14).
_TD=$(mktemp -d); ( cd "$_TD" && git init -q ); mkdir -p "$_TD/.zskills"; : > "$_TD/.zskills/tracked"  # live pipeline → enforce-pipeline deny
_TAGOUT=$(printf '{"tool_name":"Bash","permission_mode":"bypassPermissions","tool_input":{"command":"git add ."}}' | ZSKILLS_ENF_CONFIG_ROOT="$_TD" REPO_ROOT="$_TD" bash -c "cd '$_TD' && bash '$HOOK'" 2>/dev/null)
rm -rf "$_TD"
if [[ "$_TAGOUT" == *"[hooks.git_discipline.git_add_all — block|warn|off in .claude/zskills-config.json"* ]]; then
  pass "enf-gen: demotable deny carries its toggle tag"
else
  fail "enf-gen: demotable deny missing toggle tag — got: ${_TAGOUT:0:120}"
fi

# ── Inline-JSON bypass-parity (Invariant 4, AC parity-coverage floor) ───────
# Each line carries the literal `"permission_mode":"bypassPermissions"` so the
# Phase-3 AC grep (`grep -rE '"permission_mode"' tests/ | grep -c
# bypassPermissions` ≥ 23) counts genuine bypass-mode parity fixtures. Each
# asserts the demotable generic site STILL DENIES under bypassPermissions WHEN
# a zskills pipeline is genuinely live — autonomous protection unchanged.
# bypassPermissions is now ATTENDED (a permission-convenience flag), so the
# genuine-autonomy signal is the live .zskills/tracked marker planted below;
# the bypass JSON is preserved for the AC parity grep.
bypass_deny_gen() {
  local label="$1" json="$2"
  local d; d=$(mktemp -d); ( cd "$d" && git init -q )
  mkdir -p "$d/.zskills"; : > "$d/.zskills/tracked"  # live pipeline → enforce-pipeline deny
  local out; out=$(printf '%s' "$json" | ZSKILLS_ENF_CONFIG_ROOT="$d" REPO_ROOT="$d" bash -c "cd '$d' && bash '$HOOK'" 2>/dev/null)
  rm -rf "$d"
  if [[ "$out" == *'"permissionDecision"'*'deny'* ]]; then pass "bypass-parity-gen: $label"; else fail "bypass-parity-gen: $label — expected deny, got: ${out:0:80}"; fi
}
bypass_deny_gen "git_add_all"        '{"tool_name":"Bash","permission_mode":"bypassPermissions","tool_input":{"command":"git add ."}}'
bypass_deny_gen "push_to_main"       '{"tool_name":"Bash","permission_mode":"bypassPermissions","tool_input":{"command":"git push origin main"}}'
bypass_deny_gen "config_hooks_tamper" '{"tool_name":"Bash","permission_mode":"bypassPermissions","tool_input":{"command":"echo x > .claude/zskills-config.json"}}'
# SPOOF (inline-literal): real top-level "permission_mode":"bypassPermissions" +
# a counterfeit default literal smuggled INSIDE tool_input.command → still deny.
bypass_deny_gen "git_add_all SPOOF inline" '{"tool_name":"Bash","permission_mode":"bypassPermissions","tool_input":{"command":"git add . # \"permission_mode\":\"default\""}}'

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
