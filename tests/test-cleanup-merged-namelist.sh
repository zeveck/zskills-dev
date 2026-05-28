#!/bin/bash
# Tests for the /cleanup-merged branch-name-list + `local` token + `force`
# interface (pick-and-choose branch cleanup from the dashboard Branches tab).
#
# Coverage:
#   Static (skill-source + docs assertions):
#     - argument-hint advertises local / force / <branch>
#     - WI 1.2 parser accepts `local`, `force`, and collects branch names
#     - is_named() narrowing helper present
#     - protected-skip is evaluated before any force logic (ordering)
#     - docs reflect the new interface (local token, force, names)
#
#   Behavioral (extract the REAL parser + Phase 5 loop, run against a
#   throwaway git repo with stubbed gh — exercises the decision logic, not
#   a paraphrase):
#     - name-list parsing: preview vs apply
#     - names NARROW the candidate set (un-named branches untouched)
#     - safety still applies to named branches (unmerged un-forced => skip)
#     - local vs remote routing (the section keys map to scope)
#     - THE LOAD-BEARING INVARIANT: a config-protected branch named WITH
#       `force` is NOT deleted — it survives and a refusal notice is emitted.
#
# Run from repo root: bash tests/test-cleanup-merged-namelist.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/cleanup-merged/SKILL.md"
DOC="$REPO_ROOT/docs/skills/cleanup-merged.md"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== cleanup-merged branch-name-list + force interface ==="

# ── Static: skill source ────────────────────────────────────────────

# argument-hint advertises the new tokens.
if grep -qE '^argument-hint:.*local.*remote.*all.*force.*branch' "$SKILL"; then
  pass "argument-hint advertises local | remote | all, force, <branch>"
else
  fail "argument-hint missing new tokens"
fi

# WI 1.2 parser accepts `local` and `force` as positional tokens.
if grep -q 'local)  SCOPE="local"' "$SKILL" \
   && grep -q 'force)  FORCE=1' "$SKILL"; then
  pass "WI 1.2: local + force positional tokens accepted"
else
  fail "WI 1.2: local/force token parsing incomplete"
fi

# Non-keyword positionals collected as branch names.
if grep -q 'NAMED_BRANCHES+=("$arg")' "$SKILL"; then
  pass "WI 1.2: non-keyword positionals collected as branch names"
else
  fail "WI 1.2: branch-name collection missing"
fi

# is_named narrowing helper present.
if grep -q 'is_named()' "$SKILL"; then
  pass "is_named() narrowing helper present"
else
  fail "is_named() helper missing"
fi

# Protected-skip must appear BEFORE any FORCE-gated deletion in Phase 5.
PHASE5_SLICE=$(awk '
  /^## Phase 5 — Local branch scan/{capture=1}
  /^## Phase 6 —/{exit}
  capture {print}
' "$SKILL")

PROT_LINE=$(echo "$PHASE5_SLICE" | grep -n 'if is_protected "\$branch"; then' | head -1 | cut -d: -f1)
FORCE_LINE=$(echo "$PHASE5_SLICE" | grep -n 'NAMED_FORCE=1' | head -1 | cut -d: -f1)
if [ -n "$PROT_LINE" ] && [ -n "$FORCE_LINE" ] && [ "$PROT_LINE" -lt "$FORCE_LINE" ]; then
  pass "Phase 5: protected-skip precedes any force logic (prot=$PROT_LINE, force=$FORCE_LINE)"
else
  fail "Phase 5: protected-skip ordering wrong (prot=$PROT_LINE, force=$FORCE_LINE)"
fi

# The refusal notice exists.
if echo "$PHASE5_SLICE" | grep -q 'refusing to delete even with force'; then
  pass "Phase 5: 'refusing to delete even with force' notice present"
else
  fail "Phase 5: force-refusal notice missing"
fi

# ── Static: docs ────────────────────────────────────────────────────
if grep -q 'local apply' "$DOC" \
   && grep -qi 'force' "$DOC" \
   && grep -qi 'narrow' "$DOC"; then
  pass "docs/skills/cleanup-merged.md reflects local token + force + narrowing"
else
  fail "docs/skills/cleanup-merged.md interface description stale"
fi

if grep -q 'never override\|can never\|can NEVER\|sacrosanct\|never overrides' "$DOC"; then
  pass "docs: force-cannot-delete-protected invariant documented"
else
  fail "docs: protected-under-force invariant not documented"
fi

# ── Behavioral: extract the parser + Phase 5 loop and run them ──────
# Extract the WI 1.2 parse block (from `for arg in "$@"` through the
# is_named helper + FORCE-without-names guard) and the Phase 5 loop body.

# Extract from the `APPLY=0` initializer through the `FORCE=0` reset at the
# end of the parse work-item (the closing `fi` of the force-without-names
# guard). The prose paragraph after the fence is excluded by stopping at fi.
PARSE_BLOCK=$(awk '
  /^APPLY=0$/{capture=1}
  capture {print}
  capture && /^  FORCE=0$/{print_close=1}
  print_close && /^fi$/{exit}
' "$SKILL")

PHASE5_BODY=$(echo "$PHASE5_SLICE" | awk '
  /^CURRENT=\$\(git rev-parse --abbrev-ref HEAD\)$/{capture=1}
  capture {print}
  capture && /done < <\(git for-each-ref --format=.%\(refname:short\). refs\/heads\/\)/{print_close=1}
  print_close && /^fi$/{exit}
')

if [ -z "$PARSE_BLOCK" ]; then
  fail "could not extract WI 1.2 parse block for behavioral test"
elif [ -z "$PHASE5_BODY" ]; then
  fail "could not extract Phase 5 loop body for behavioral test"
else
  pass "extracted parse block + Phase 5 body for behavioral test"

  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  STUBDIR="$TMP/stub"
  mkdir -p "$STUBDIR"

  # ── Build a throwaway repo with several local branches ────────────
  (
    cd "$TMP" || exit 1
    git init -q -b main .
    git config user.email t@t.t; git config user.name t
    git commit -q --allow-empty -m base

    # merged: an ancestor of main (clean fast-forward merge) — deletable.
    git branch merged main

    # protected: also an ancestor of main, but config-protected. MUST
    # survive even when named WITH force.
    git branch protected main

    # unmerged: a branch with a unique commit NOT on main — not merged,
    # has "unpushed" commits (no remotes configured). Without force it
    # must be SKIP'd; with force (+name) it is deletable.
    git checkout -q -b unmerged
    git commit -q --allow-empty -m "unmerged work"
    git checkout -q main

    # untouched: another merged ancestor used to prove narrowing — when
    # names are given, this branch must NOT be considered.
    git branch untouched main

    # Stub gh: `merged` and `untouched` report MERGED (genuine auto-
    # candidates, both ancestors of main); `unmerged`/`unmerged2`/
    # `protected` report empty (not merged). For headRefOid we echo the
    # branch's own tip so the #516/#755 post-merge gate sees tip == PR head
    # (the safe squash case) and falls through.
    cat > "$STUBDIR/gh" <<'STUB'
#!/bin/bash
# gh pr view <branch> --json <fields> -q <jq>
#   $1=pr  $2=view  $3=<branch>  rest=--json ... -q ...
branch="$3"
want_head=0
for a in "$@"; do [ "$a" = "headRefOid" ] && want_head=1; done
case "$branch" in
  merged|untouched)
    if [ "$want_head" -eq 1 ]; then
      git rev-parse "$branch" 2>/dev/null
    else
      echo "MERGED"
    fi
    ;;
  *)
    echo ""  # not merged / unknown
    ;;
esac
STUB
    chmod +x "$STUBDIR/gh"
  )

  run_scan_with_args() {
    # Helper to pass args cleanly through eval-based parser.
    local out
    out=$(
      cd "$TMP" || exit 1
      export PATH="$STUBDIR:$PATH"
      MAIN_ROOT="$TMP"
      MAIN_BRANCH=main
      HAVE_GH=1
      is_protected() { [ "$1" = "protected" ]; }
      set -- "$@"
      eval "$PARSE_BLOCK"
      eval "$PHASE5_BODY"
      echo "LOCAL_DELETED=$LOCAL_DELETED"
      echo "LOCAL_PROTECTED=$LOCAL_PROTECTED"
      echo "LOCAL_SKIPPED=$LOCAL_SKIPPED"
    )
    printf '%s\n' "$out"
  }

  branch_exists() { git -C "$TMP" show-ref --verify --quiet "refs/heads/$1"; }

  # ── Scenario A: preview (no apply), name a merged branch ──────────
  # Names without apply => preview only; nothing deleted.
  A=$(run_scan_with_args merged)
  if echo "$A" | grep -q 'WOULD-DELETE merged' \
     || echo "$A" | grep -q 'LOCAL_DELETED=1'; then
    : # candidate detection is fine in preview; but it must not delete
  fi
  if branch_exists merged; then
    pass "Scenario A (preview): named branch NOT deleted without apply"
  else
    fail "Scenario A (preview): branch 'merged' was deleted in preview mode"
  fi

  # ── Scenario B: narrowing — apply force on 'unmerged' only ────────
  # Names narrow the set: 'untouched' (a merged ancestor) must survive
  # because it was not named.
  B=$(run_scan_with_args apply force unmerged)
  if ! branch_exists unmerged; then
    pass "Scenario B (narrow+force): named unmerged branch deleted"
  else
    fail "Scenario B: 'unmerged' not deleted despite apply+force+name ($B)"
  fi
  if branch_exists untouched; then
    pass "Scenario B (narrow): un-named branch 'untouched' survives"
  else
    fail "Scenario B: un-named 'untouched' was wrongly deleted ($B)"
  fi

  # ── Scenario C: safety still applies to a named branch (no force) ──
  # Create an unmerged branch and name it WITHOUT force: PR_STATE is empty
  # (stub) and no upstream-gone, so it is not merged => must NOT delete.
  ( cd "$TMP" && git checkout -q -b unmerged2 main && git commit -q --allow-empty -m "u2 work" && git checkout -q main )
  C=$(run_scan_with_args apply unmerged2)
  if branch_exists unmerged2; then
    pass "Scenario C (safety): named-but-not-merged branch SKIP'd without force"
  else
    fail "Scenario C: 'unmerged2' deleted without force despite not being merged ($C)"
  fi

  # ── Scenario D (THE INVARIANT): protected + named + force => SURVIVES
  D=$(run_scan_with_args apply force protected)
  if branch_exists protected; then
    pass "INVARIANT: config-protected branch named WITH force is NOT deleted (it survives)"
  else
    fail "INVARIANT VIOLATED: protected branch was deleted under force+name!! ($D)"
  fi
  if echo "$D" | grep -q 'refusing to delete even with force'; then
    pass "INVARIANT: loud refusal notice emitted for protected+force"
  else
    fail "INVARIANT: no refusal notice for protected+force ($D)"
  fi
  if echo "$D" | grep -q 'LOCAL_PROTECTED=1'; then
    pass "INVARIANT: protected counter incremented (not deleted)"
  else
    fail "INVARIANT: protected counter not incremented ($D)"
  fi
fi

# ── Mirror sync ──────────────────────────────────────────────────────
MIRROR="$REPO_ROOT/.claude/skills/cleanup-merged/SKILL.md"
if [ -f "$MIRROR" ]; then
  if diff -q "$SKILL" "$MIRROR" >/dev/null; then
    pass "mirror sync: source SKILL.md == .claude/skills/cleanup-merged/SKILL.md"
  else
    fail "mirror drift: skills/ vs .claude/skills/ cleanup-merged SKILL.md differ"
  fi
else
  fail ".claude/skills/cleanup-merged/SKILL.md missing"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
