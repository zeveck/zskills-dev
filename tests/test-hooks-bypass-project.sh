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

# ════════════════════════════════════════════════════════════════════════════
# ENFORCEMENT_V2_PLAN Phase 3 (#1159) — project-hook bypass-parity (15 of 18) +
# watched-silent + opt-in-warn + SPOOF + stale-pipeline tracking-gate fixture.
# All 15 demotable project sites: requires_unfulfilled (×2 sites, 1 key),
# step_unverified, step_unreported, logs_add_all, test_pipe, full_cmd_unset,
# commit_on_main, tests_not_run (commit + cherry-pick), ui_unverified,
# cherry_pick_on_main, push_to_main (×3 forms). Critical invariant 4: each still
# DENIES under bypassPermissions (autonomous protection unchanged). The 2 hard
# sites (zskills_tree_delete, clear_tracking_agent) are covered above + by
# test-hooks-misc (absent-pm → enforce → deny).
# ─────────────────────────────────────────────────────────────────────────────
echo "=== ENFORCEMENT_V2 Phase 3: project-hook demotable parity (#1159) ==="

# Flexible project-hook fixture runner. Builds a temp repo with a rendered
# project hook + config, controllable branch / permission_mode / hooks-toggle /
# markers, then runs the hook and asserts deny|silent|warn.
#   $1=label $2=branch $3=permission_mode("" → absent) $4=cmd $5=expect
#   Named-array-style trailing opts via env-ish positionals:
#     $6 = hooks-config-JSON (value of top-level "hooks"; "" → none)
#     $7 = "tracked" to write .zskills/tracked (→ live pipeline)
#     $8 = setup spec: comma list of {requires,fulfilled,stepimpl,stepverify,
#          stagecode,uifile,no-full-cmd}
PROJ_HOOK_FILE="$REPO_ROOT/hooks/block-unsafe-project.sh.template"
enf_proj_case() {
  local label="$1" branch="$2" pm="$3" cmd="$4" expect="$5"
  local hooks_cfg="${6:-}" tracked="${7:-}" setup="${8:-}"
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude/hooks" "$d/.zskills/tracking/run-plan.test-plan"
  cp "$PROJ_HOOK_FILE" "$d/.claude/hooks/block-unsafe-project.sh"
  # Config: testing/ui defaults + main_protected:true + optional hooks toggle.
  local full_cmd='"full_cmd": "npm run test:all"'
  [[ "$setup" == *no-full-cmd* ]] && full_cmd='"full_cmd": ""'
  {
    printf '{\n  "testing": { "unit_cmd": "npm test", %s },\n' "$full_cmd"
    printf '  "ui": { "file_patterns": "src/ui/" },\n'
    printf '  "execution": { "main_protected": true }'
    [ -n "$hooks_cfg" ] && printf ',\n  "hooks": %s' "$hooks_cfg"
    printf '\n}\n'
  } > "$d/.claude/zskills-config.json"
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$d/package.json"
  # Transcript: declare the pipeline so tracking association fires; include the
  # full test command UNLESS we are testing tests_not_run (then omit it).
  if [[ "$setup" == *ui-no-playwright* ]]; then
    # Test command PRESENT (tests_not_run gate satisfied) but playwright-cli
    # ABSENT, so the UI gate is the one that fires.
    printf 'ZSKILLS_PIPELINE_ID=run-plan.test-plan\nnpm run test:all\n' > "$d/.transcript"
  elif [[ "$setup" == *no-test-in-transcript* ]]; then
    printf 'ZSKILLS_PIPELINE_ID=run-plan.test-plan\n' > "$d/.transcript"
  else
    printf 'ZSKILLS_PIPELINE_ID=run-plan.test-plan\nnpm run test:all\nplaywright-cli\n' > "$d/.transcript"
  fi
  ( cd "$d" && git init -q && git checkout -q -b "$branch" 2>/dev/null && git add -A && git commit -q -m init 2>/dev/null )
  # push-code: simulate a feature branch carrying un-landed code so the push
  # tracking gate's CODE_FILES (merge-base origin/main..HEAD) is non-empty.
  # Build origin/main from the init commit, then add a code commit on $branch.
  if [[ "$setup" == *push-code* ]]; then
    ( cd "$d" \
      && git branch -q main 2>/dev/null \
      && bare=$(mktemp -d) && git clone -q --bare "$d" "$bare" 2>/dev/null \
      && git remote add origin "$bare" 2>/dev/null && git fetch -q origin 2>/dev/null \
      && echo "var y=2;" > feat.js && git add feat.js && git commit -q -m feat 2>/dev/null )
  fi
  # Markers / staged files.
  local sub="$d/.zskills/tracking/run-plan.test-plan"
  [[ "$setup" == *requires* ]]   && touch "$sub/requires.verify-changes.test-plan"
  [[ "$setup" == *fulfilled* ]]  && touch "$sub/fulfilled.verify-changes.test-plan"
  [[ "$setup" == *stepimpl* ]]   && touch "$sub/step.phase1.implement"
  [[ "$setup" == *stepverify* ]] && touch "$sub/step.phase1.verify"
  [ "$tracked" = "tracked" ] && printf 'run-plan.test-plan\n' > "$d/.zskills/tracked"
  if [[ "$setup" == *stagecode* ]]; then ( cd "$d" && echo "var x=1;" > app.js && git add app.js ); fi
  if [[ "$setup" == *uifile* ]]; then mkdir -p "$d/src/ui" && ( cd "$d" && echo ".a{}" > src/ui/a.css && git add src/ui/a.css ); fi
  local pmf=""
  [ -n "$pm" ] && pmf=",\"permission_mode\":\"$pm\""
  local json="{\"tool_name\":\"Bash\",\"transcript_path\":\"$d/.transcript\"$pmf,\"tool_input\":{\"command\":\"$cmd\"}}"
  local out
  out=$(printf '%s' "$json" | REPO_ROOT="$d" TRACKING_ROOT="$d" LOCAL_ROOT="$d" ZSKILLS_ENF_CONFIG_ROOT="$d" \
    bash -c "cd '$d' && bash '$d/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)
  rm -rf "$d"
  case "$expect" in
    deny)   if [[ "$out" == *'"permissionDecision"'*'deny'* ]]; then pass "enf-proj: $label → deny"; else fail "enf-proj: $label → expected deny, got: ${out:0:90}"; fi ;;
    silent) if [[ -z "$out" ]]; then pass "enf-proj: $label → silent (empty)"; else fail "enf-proj: $label → expected silent, got: ${out:0:90}"; fi ;;
    warn)   if [[ "$out" == *'"systemMessage"'* ]] && [[ "$out" != *'permissionDecision'* ]]; then pass "enf-proj: $label → warn"; else fail "enf-proj: $label → expected warn, got: ${out:0:90}"; fi ;;
  esac
}

# ── commit_on_main (demotable) — parity 4/18 ───────────────────────────────
enf_proj_case "commit_on_main bypassPermissions + live pipeline" main bypassPermissions "git commit -m x" deny "" "tracked" "stagecode"
enf_proj_case "commit_on_main absent-pm (fail-safe)"      main ""                "git commit -m x" deny "" "" "stagecode"
enf_proj_case "commit_on_main watched(default) → SILENT"  main default           "git commit -m x" silent "" "" "stagecode"
enf_proj_case "commit_on_main watched + toggle warn"      main default           "git commit -m x" warn '{"main_protection":{"commit_on_main":"warn"}}' "" "stagecode"
enf_proj_case "commit_on_main watched + toggle block"     main default           "git commit -m x" deny '{"main_protection":{"commit_on_main":"block"}}' "" "stagecode"

# ── cherry_pick_on_main (demotable) — parity 5/18 ──────────────────────────
enf_proj_case "cherry_pick_on_main bypassPermissions + live pipeline" main bypassPermissions "git cherry-pick abc123" deny "" "tracked"
enf_proj_case "cherry_pick_on_main watched(default) → SILENT" main default       "git cherry-pick abc123" silent

# ── push_to_main (demotable, 3 forms share the key) — parity 6/18 ──────────
enf_proj_case "push_to_main form-a (origin main) bypass + live pipeline" feat/test bypassPermissions "git push origin main" deny "" "tracked"
enf_proj_case "push_to_main form-a watched(default) → SILENT" feat/test default     "git push origin main" silent
enf_proj_case "push_to_main form-b (feat:main) bypass + live pipeline" feat/test bypassPermissions "git push origin feat:main" deny "" "tracked"
enf_proj_case "push_to_main form-c (naked on main) bypass + live pipeline" main bypassPermissions "git push" deny "" "tracked"

# ── requires_unfulfilled (demotable, 2 sites: commit + push) — parity 7/18 ─
enf_proj_case "requires_unfulfilled (commit) bypass"      feat/test bypassPermissions "git commit -m x" deny "" "tracked" "requires,stagecode"
enf_proj_case "requires_unfulfilled (push) bypass"        feat/test bypassPermissions "git push origin feat/test" deny "" "tracked" "requires,push-code"
enf_proj_case "requires_unfulfilled (commit) watched + tracked → DENY (live pipeline)" feat/test default "git commit -m x" deny "" "tracked" "requires,stagecode"
# Stale-pipeline fixture (DA2): markers present, NO tracked file, watched, no
# toggle → SILENT (the bare tracking/ subdir is deliberately not a signal).
enf_proj_case "requires_unfulfilled STALE (markers, no tracked, watched) → SILENT" feat/test default "git commit -m x" silent "" "" "requires,stagecode"
enf_proj_case "requires_unfulfilled STALE watched + toggle warn → WARN"  feat/test default "git commit -m x" warn '{"tracking":{"requires_unfulfilled":"warn"}}' "" "requires,stagecode"

# ── step_unverified (demotable) — parity 8/18 ──────────────────────────────
enf_proj_case "step_unverified (impl, no verify) bypass"  feat/test bypassPermissions "git commit -m x" deny "" "tracked" "stepimpl,stagecode"
# ── step_unreported (demotable) — parity 9/18 ──────────────────────────────
enf_proj_case "step_unreported (verify, no report) bypass" feat/test bypassPermissions "git commit -m x" deny "" "tracked" "stepverify,stagecode"

# ── logs_add_all (demotable) — parity 10/18 ────────────────────────────────
enf_proj_case "logs_add_all bypassPermissions + live pipeline" feat/test bypassPermissions "git add .claude/logs/" deny "" "tracked"
enf_proj_case "logs_add_all watched(default) → SILENT"    feat/test default           "git add .claude/logs/" silent

# ── test_pipe (demotable) — parity 11/18 ───────────────────────────────────
enf_proj_case "test_pipe bypassPermissions + live pipeline" feat/test bypassPermissions "npm test | tail" deny "" "tracked"
enf_proj_case "test_pipe watched(default) → SILENT"       feat/test default           "npm test | tail" silent

# ── full_cmd_unset (demotable) — parity 12/18 ──────────────────────────────
enf_proj_case "full_cmd_unset bypassPermissions + live pipeline" feat/test bypassPermissions "npm test | tail" deny "" "tracked" "no-full-cmd"
enf_proj_case "full_cmd_unset watched(default) → SILENT"  feat/test default           "npm test | tail" silent "" "" "no-full-cmd"

# ── tests_not_run (commit, demotable) — parity 13/18 ───────────────────────
enf_proj_case "tests_not_run (commit) bypassPermissions + live pipeline" feat/test bypassPermissions "git commit -m x" deny "" "tracked" "stagecode,no-test-in-transcript"
enf_proj_case "tests_not_run (commit) watched(default) → SILENT" feat/test default     "git commit -m x" silent "" "" "stagecode,no-test-in-transcript"
# ── tests_not_run (cherry-pick, demotable) — parity 14/18 ──────────────────
enf_proj_case "tests_not_run (cherry-pick) bypassPermissions + live pipeline" feat/test bypassPermissions "git cherry-pick abc123" deny "" "tracked" "no-test-in-transcript"

# ── ui_unverified (demotable) — parity 15/18 ───────────────────────────────
# UI file staged, transcript lacks playwright-cli AND lacks the test cmd so the
# commit transcript gate is the UI one (use no-test-in-transcript to skip the
# tests_not_run gate ordering; UI gate fires on the missing playwright-cli).
enf_proj_case "ui_unverified bypassPermissions + live pipeline" feat/test bypassPermissions "git commit -m x" deny "" "tracked" "uifile,ui-no-playwright"

# SPOOF parity (Invariant 4): counterfeit permission_mode:"default" inside the
# command string, real top-level field bypassPermissions → parser takes the real
# field (attended); a live pipeline marker keeps the deny path exercised.
enf_proj_case "commit_on_main SPOOF (counterfeit default in cmd, real bypass) + live pipeline" main bypassPermissions 'git commit -m \"x permission_mode default\"' deny "" "tracked" "stagecode"

# ── Inline-JSON bypass-parity (Invariant 4, AC parity-coverage floor) ───────
# Each line carries the literal `"permission_mode":"bypassPermissions"` so the
# Phase-3 AC grep (`grep -rE '"permission_mode"' tests/ | grep -c
# bypassPermissions` ≥ 23) counts genuine bypass-mode parity fixtures. These
# cover the on-main + git-discipline project sites. bypassPermissions is now
# ATTENDED, so the genuine-autonomy signal is the live .zskills/tracked marker
# planted below — the bypass JSON is preserved for the AC parity grep. The
# marker-dependent tracking sites are covered by the helper-based cases above
# (also bypassPermissions). $1=label $2=branch
# $3=full-json $4=no-full-cmd? $5=no-test? — minimal fixture controls.
bypass_deny_proj() {
  local label="$1" branch="$2" json="$3" nofull="${4:-}" notest="${5:-}"
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude/hooks" "$d/.zskills/tracking"
  printf 'run-plan.test-plan\n' > "$d/.zskills/tracked"  # live pipeline → enforce-pipeline deny
  cp "$PROJ_HOOK_FILE" "$d/.claude/hooks/block-unsafe-project.sh"
  local fc='"full_cmd": "npm run test:all"'; [ "$nofull" = "nofull" ] && fc='"full_cmd": ""'
  printf '{ "testing": { "unit_cmd": "npm test", %s }, "ui": { "file_patterns": "src/ui/" }, "execution": { "main_protected": true } }\n' "$fc" > "$d/.claude/zskills-config.json"
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$d/package.json"
  if [ "$notest" = "notest" ]; then printf 'ZSKILLS_PIPELINE_ID=run-plan.test-plan\n' > "$d/.transcript"; else printf 'ZSKILLS_PIPELINE_ID=run-plan.test-plan\nnpm run test:all\nplaywright-cli\n' > "$d/.transcript"; fi
  ( cd "$d" && git init -q && git checkout -q -b "$branch" 2>/dev/null && echo "init" > README && git add -A && git commit -q -m init 2>/dev/null && echo "var x=1;" > app.js && git add app.js 2>/dev/null )
  local fulljson; fulljson=$(printf '%s' "$json" | sed "s#@T@#$d/.transcript#")
  local out; out=$(printf '%s' "$fulljson" | REPO_ROOT="$d" TRACKING_ROOT="$d" LOCAL_ROOT="$d" ZSKILLS_ENF_CONFIG_ROOT="$d" bash -c "cd '$d' && bash '$d/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)
  rm -rf "$d"
  if [[ "$out" == *'"permissionDecision"'*'deny'* ]]; then pass "bypass-parity-proj: $label"; else fail "bypass-parity-proj: $label — expected deny, got: ${out:0:80}"; fi
}
bypass_deny_proj "commit_on_main"        main      '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"git commit -m x"}}'
bypass_deny_proj "cherry_pick_on_main"   main      '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"git cherry-pick abc123"}}'
bypass_deny_proj "push_to_main form-a"   feat/test '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"git push origin main"}}'
bypass_deny_proj "push_to_main form-b"   feat/test '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"git push origin feat:main"}}'
bypass_deny_proj "push_to_main form-c"   main      '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"git push"}}'
bypass_deny_proj "logs_add_all"          feat/test '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"git add .claude/logs/"}}'
bypass_deny_proj "test_pipe"             feat/test '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"npm test | tail"}}'
bypass_deny_proj "full_cmd_unset"        feat/test '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"npm test | tail"}}' nofull
bypass_deny_proj "tests_not_run commit"  feat/test '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"git commit -m x"}}' "" notest
bypass_deny_proj "tests_not_run cherry-pick" feat/test '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"git cherry-pick abc123"}}' "" notest

# Tracking-gate inline bypass-parity (markers + live .zskills/tracked). Each line
# carries the literal "permission_mode":"bypassPermissions" for the AC grep and
# asserts the demotable tracking site still DENIES under bypass. $1=label
# $2=marker-kind(requires|stepimpl|stepverify) $3=full-json.
bypass_deny_proj_tracking() {
  local label="$1" mk="$2" json="$3"
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude/hooks" "$d/.zskills/tracking/run-plan.test-plan"
  cp "$PROJ_HOOK_FILE" "$d/.claude/hooks/block-unsafe-project.sh"
  printf '{ "testing": { "unit_cmd": "npm test", "full_cmd": "npm run test:all" }, "ui": { "file_patterns": "src/ui/" }, "execution": { "main_protected": true } }\n' > "$d/.claude/zskills-config.json"
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$d/package.json"
  printf 'ZSKILLS_PIPELINE_ID=run-plan.test-plan\nnpm run test:all\nplaywright-cli\n' > "$d/.transcript"
  ( cd "$d" && git init -q && git checkout -q -b feat/test 2>/dev/null && echo init > README && git add -A && git commit -q -m init 2>/dev/null && echo "var x=1;" > app.js && git add app.js 2>/dev/null )
  printf 'run-plan.test-plan\n' > "$d/.zskills/tracked"
  local sub="$d/.zskills/tracking/run-plan.test-plan"
  case "$mk" in
    requires)   touch "$sub/requires.verify-changes.test-plan" ;;
    stepimpl)   touch "$sub/step.phase1.implement" ;;
    stepverify) touch "$sub/step.phase1.verify" ;;
  esac
  local fulljson; fulljson=$(printf '%s' "$json" | sed "s#@T@#$d/.transcript#")
  local out; out=$(printf '%s' "$fulljson" | REPO_ROOT="$d" TRACKING_ROOT="$d" LOCAL_ROOT="$d" ZSKILLS_ENF_CONFIG_ROOT="$d" bash -c "cd '$d' && bash '$d/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)
  rm -rf "$d"
  if [[ "$out" == *'"permissionDecision"'*'deny'* ]]; then pass "bypass-parity-proj-tracking: $label"; else fail "bypass-parity-proj-tracking: $label — expected deny, got: ${out:0:80}"; fi
}
bypass_deny_proj_tracking "requires_unfulfilled" requires   '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"git commit -m x"}}'
bypass_deny_proj_tracking "step_unverified"      stepimpl   '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"git commit -m x"}}'
bypass_deny_proj_tracking "step_unreported"      stepverify '{"tool_name":"Bash","transcript_path":"@T@","permission_mode":"bypassPermissions","tool_input":{"command":"git commit -m x"}}'

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
