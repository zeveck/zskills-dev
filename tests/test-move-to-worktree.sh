#!/bin/bash
# tests/test-move-to-worktree.sh — suite for
# skills/create-worktree/scripts/move-to-worktree.sh (ENFORCEMENT_V2 Phase 5).
#
# The helper creates a worktree off LOCAL HEAD (create-worktree.sh
# --no-preflight), CARRIES dirty + untracked files into it via a TWO-PATCH
# carry (staged + unstaged, split preserved) plus per-file untracked copy, and
# then performs a byte+index-verified, stash-free restore of main.
#
# Every case builds a FRESH scratch git repo (the helper mutates main state, so
# each case needs its own main). Scratch repos + their worktrees live under one
# mktemp dir removed by the EXIT trap. The worktree root defaults to /tmp via
# create-worktree.sh's WORKTREE_ROOT default; we override execution.worktree_root
# in each scratch repo's .claude/zskills-config.json so the worktree lands INSIDE
# the scratch tree (self-cleaning, never colliding with parallel runs).
#
# Cases:
#   1.  dirty-move full matrix (MM split + A staged-new + ' D' deleted +
#       untracked nested dir) → main empty, main SHA unchanged, wt mirrors dirt,
#       staged/unstaged split survives.
#   2.  staged rename R  → both paths carried; main clean after.
#   3.  staged-then-reverted (index X, worktree==HEAD) → diff HEAD empty yet X
#       SURVIVES in the worktree index (the R2-5 fixture).
#   4.  --keep-main-dirty → main untouched, dirt carried.
#   5.  verification-failure injection → main stays dirty, rc 8.
#   6.  unmerged UU refusal → rc 7, main untouched, "resolve the merge".
#   7.  clean-main no-op arm → rc 0, "main was clean".
#   8.  .zskills/ exclusion → a .zskills/tracked file is neither carried nor
#       deleted.
#   9.  gitignored file NOT carried (porcelain-based exclusion property).
#   10. untracked NESTED-dir files carry per-file (DA7).
#   11. local-main-ahead-of-origin + dirty → rc 0; wt HEAD == LOCAL main HEAD;
#       main clean after.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HELPER="$REPO_ROOT/skills/create-worktree/scripts/move-to-worktree.sh"
if [ ! -x "$HELPER" ]; then
  echo "FATAL: helper not found/executable: $HELPER" >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

SANDBOX_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mvwt-suite.XXXXXX")"
cleanup() {
  # Per-file-safe recursive cleanup: prune any registered worktrees first, then
  # rm the sandbox. The sandbox is a private mktemp dir, so a literal rm -rf on
  # the captured absolute path is safe here.
  [ -n "${SANDBOX_ROOT:-}" ] && [ -d "$SANDBOX_ROOT" ] && rm -rf "$SANDBOX_ROOT"
}
trap cleanup EXIT

# new_scratch <name> : create a fresh git repo at $SANDBOX_ROOT/<name>, echo its
# path. The worktree root is set OUTSIDE the repo ($SANDBOX_ROOT/<name>-wt) so a
# created worktree never appears as untracked dirt in main's `git status`. The
# .claude/zskills-config.json (which create-worktree.sh reads from $MAIN_ROOT)
# IS committed at init so it is not untracked either — leaving main genuinely
# clean after an init+commit.
new_scratch() {
  local name="$1"
  local repo="$SANDBOX_ROOT/$name"
  mkdir -p "$repo/.claude"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email "mvwt@test.invalid"
  git -C "$repo" config user.name "mvwt"
  mkdir -p "$SANDBOX_ROOT/$name-wt"
  printf '{\n  "execution": { "worktree_root": "%s-wt" }\n}\n' "$repo" \
    > "$repo/.claude/zskills-config.json"
  # Commit the config so it is tracked-clean, not untracked dirt.
  git -C "$repo" add .claude/zskills-config.json
  git -C "$repo" commit -qm "config"
  printf '%s\n' "$repo"
}

# The worktree path create-worktree.sh derives for a bare slug is
# ${worktree_root}/${PROJECT_NAME}-${slug}. PROJECT_NAME = basename($repo).
wt_path_for() {
  local repo="$1" slug="$2"
  printf '%s-wt/%s-%s\n' "$repo" "$(basename "$repo")" "$slug"
}

# ════════════════════════════════════════════════════════════════════════════
# CASE 1 — dirty-move full matrix.
# ════════════════════════════════════════════════════════════════════════════
REPO="$(new_scratch case1)"
( cd "$REPO"
  printf 'orig\n' > f.txt; printf 'origd\n' > d.txt
  git add f.txt d.txt; git commit -qm init
  printf 'staged-X\n' > f.txt; git add f.txt   # index = X
  printf 'worktree-Y\n' > f.txt                 # worktree = Y → MM
  printf 'newc\n' > brandnew.txt; git add brandnew.txt   # A
  rm d.txt                                       # ' D' deleted
  mkdir -p nested/deep; printf 'a\n' > nested/deep/a.txt   # untracked nested
)
SHA_BEFORE="$(git -C "$REPO" rev-parse HEAD)"
RC=0; OUT="$(cd "$REPO" && bash "$HELPER" c1-branch 2>&1)" || RC=$?
WT="$(wt_path_for "$REPO" c1-branch)"
if [ "$RC" -eq 0 ]; then pass "case1: rc 0"; else fail "case1: rc 0 (got $RC) — $OUT"; fi
if [ -z "$(git -C "$REPO" status --porcelain --untracked-files=all)" ]; then
  pass "case1: main porcelain EMPTY after restore"
else
  fail "case1: main porcelain not empty — $(git -C "$REPO" status --porcelain --untracked-files=all)"
fi
if [ "$(git -C "$REPO" rev-parse HEAD)" = "$SHA_BEFORE" ]; then
  pass "case1: main SHA unchanged"
else
  fail "case1: main SHA changed"
fi
WT_PORC="$(git -C "$WT" status --porcelain --untracked-files=all 2>/dev/null)"
if [ -n "$WT_PORC" ]; then pass "case1: worktree diff non-empty"; else fail "case1: worktree diff empty"; fi
if [ "$(git -C "$WT" show :f.txt 2>/dev/null)" = "staged-X" ]; then
  pass "case1: staged/unstaged SPLIT preserved — wt index f.txt == X (staged-X)"
else
  fail "case1: wt index f.txt != X (got '$(git -C "$WT" show :f.txt 2>/dev/null)')"
fi
if [ "$(cat "$WT/f.txt" 2>/dev/null)" = "worktree-Y" ]; then
  pass "case1: split preserved — wt worktree f.txt == Y (worktree-Y)"
else
  fail "case1: wt worktree f.txt != Y"
fi

# ════════════════════════════════════════════════════════════════════════════
# CASE 2 — staged rename.
# ════════════════════════════════════════════════════════════════════════════
REPO="$(new_scratch case2)"
( cd "$REPO"
  printf 'content\n' > old.txt; git add old.txt; git commit -qm init
  git mv old.txt new.txt
)
RC=0; OUT="$(cd "$REPO" && bash "$HELPER" c2-branch 2>&1)" || RC=$?
WT="$(wt_path_for "$REPO" c2-branch)"
if [ "$RC" -eq 0 ]; then pass "case2: rename rc 0"; else fail "case2: rename rc 0 (got $RC) — $OUT"; fi
if [ -z "$(git -C "$REPO" status --porcelain --untracked-files=all)" ]; then
  pass "case2: main clean after rename carry"
else
  fail "case2: main not clean — $(git -C "$REPO" status --porcelain)"
fi
if git -C "$WT" status --porcelain | grep -q '^R'; then
  pass "case2: worktree shows the rename (both paths carried)"
else
  fail "case2: worktree rename absent — $(git -C "$WT" status --porcelain)"
fi

# ════════════════════════════════════════════════════════════════════════════
# CASE 3 — staged-then-reverted (R2-5 index-survival).
# ════════════════════════════════════════════════════════════════════════════
REPO="$(new_scratch case3)"
( cd "$REPO"
  printf 'HEAD\n' > f.txt; git add f.txt; git commit -qm init
  printf 'STAGED-X\n' > f.txt; git add f.txt   # index = X
  printf 'HEAD\n' > f.txt                        # worktree back to HEAD → MM
)
DIFF_HEAD_BYTES="$(git -C "$REPO" diff HEAD -- f.txt | wc -c | tr -d ' ')"
RC=0; OUT="$(cd "$REPO" && bash "$HELPER" c3-branch 2>&1)" || RC=$?
WT="$(wt_path_for "$REPO" c3-branch)"
if [ "$RC" -eq 0 ]; then pass "case3: rc 0"; else fail "case3: rc 0 (got $RC) — $OUT"; fi
if [ "$DIFF_HEAD_BYTES" = "0" ]; then
  pass "case3: precondition — git diff HEAD is empty (worktree-only carry would drop X)"
else
  fail "case3: precondition broken — diff HEAD bytes=$DIFF_HEAD_BYTES"
fi
if [ "$(git -C "$WT" show :f.txt 2>/dev/null)" = "STAGED-X" ]; then
  pass "case3: index X SURVIVES in worktree — git show :f.txt == STAGED-X"
else
  fail "case3: index X lost (got '$(git -C "$WT" show :f.txt 2>/dev/null)')"
fi
if [ -z "$(git -C "$REPO" status --porcelain)" ]; then
  pass "case3: main clean after restore"
else
  fail "case3: main not clean"
fi

# ════════════════════════════════════════════════════════════════════════════
# CASE 4 — --keep-main-dirty.
# ════════════════════════════════════════════════════════════════════════════
REPO="$(new_scratch case4)"
( cd "$REPO"
  printf 'x\n' > f.txt; git add f.txt; git commit -qm init
  printf 'dirty\n' > f.txt
)
RC=0; OUT="$(cd "$REPO" && bash "$HELPER" c4-branch --keep-main-dirty 2>&1)" || RC=$?
WT="$(wt_path_for "$REPO" c4-branch)"
if [ "$RC" -eq 0 ]; then pass "case4: --keep-main-dirty rc 0"; else fail "case4: rc 0 (got $RC) — $OUT"; fi
if [ "$(git -C "$REPO" status --porcelain)" = " M f.txt" ]; then
  pass "case4: main STILL dirty (untouched)"
else
  fail "case4: main not preserved — '$(git -C "$REPO" status --porcelain)'"
fi
if [ "$(cat "$WT/f.txt" 2>/dev/null)" = "dirty" ]; then
  pass "case4: worktree has the dirt"
else
  fail "case4: worktree missing dirt"
fi

# ════════════════════════════════════════════════════════════════════════════
# CASE 5 — verification-failure injection → main stays dirty (NOT restored),
# rc 8. Deterministic injection: a SHIM create-worktree.sh that delegates to the
# real one and then, right after the worktree is created (step 2), DELETES the
# to-be-carried untracked file from MAIN. The helper's step-5 copy then skips it
# (source gone), so the worktree never gets it; step-6 verify finds it
# worktree-ABSENT → mismatch → rc 8, with main left UNTOUCHED (the remaining
# tracked dirt is NOT restored — destruction never runs on a verify failure).
# Running a COPY of the helper from the shim dir makes its sibling
# create-worktree.sh resolve to the shim (the helper uses SCRIPT_DIR-relative
# sibling resolution).
# ════════════════════════════════════════════════════════════════════════════
REPO="$(new_scratch case5)"
SHIM_DIR="$SANDBOX_ROOT/shim5"
mkdir -p "$SHIM_DIR"
cat > "$SHIM_DIR/create-worktree.sh" <<SHIM
#!/bin/bash
set -eu
REAL="$REPO_ROOT/skills/create-worktree/scripts/create-worktree.sh"
OUT=\$(bash "\$REAL" "\$@")
RC=\$?
# Delete the to-be-carried untracked file from MAIN after worktree creation so
# the helper's copy skips it and its verify finds it worktree-absent → rc 8.
MROOT=\$(cd "\$(git rev-parse --git-common-dir)/.." && pwd)
rm -f "\$MROOT/untr.txt" 2>/dev/null || true
printf '%s\n' "\$OUT"
exit \$RC
SHIM
chmod +x "$SHIM_DIR/create-worktree.sh"
# The helper resolves create-worktree.sh via its own SCRIPT_DIR (sibling). To
# inject the shim we run a COPY of the helper from the shim dir so its sibling
# create-worktree.sh is the shim.
cp "$HELPER" "$SHIM_DIR/move-to-worktree.sh"
chmod +x "$SHIM_DIR/move-to-worktree.sh"
( cd "$REPO"
  printf 'base\n' > f.txt; git add f.txt; git commit -qm init
  printf 'tracked-dirty\n' > f.txt              # tracked dirt (carryable)
  printf 'orig-untracked\n' > untr.txt          # untracked → will be corrupted
)
RC=0; OUT="$(cd "$REPO" && bash "$SHIM_DIR/move-to-worktree.sh" c5-branch 2>&1)" || RC=$?
if [ "$RC" -eq 8 ]; then pass "case5: verification mismatch → rc 8"; else fail "case5: expected rc 8, got $RC — $OUT"; fi
# Main must still be dirty (NOT restored): both the tracked edit and the
# (corrupted) untracked file remain.
if [ -n "$(git -C "$REPO" status --porcelain --untracked-files=all)" ]; then
  pass "case5: main left dirty (no destructive restore on verify failure)"
else
  fail "case5: main was wrongly restored despite verify failure"
fi

# ════════════════════════════════════════════════════════════════════════════
# CASE 6 — unmerged UU refusal → rc 7, main untouched.
# ════════════════════════════════════════════════════════════════════════════
REPO="$(new_scratch case6)"
( cd "$REPO"
  printf 'base\n' > f.txt; git add f.txt; git commit -qm base
  git checkout -q -b feature
  printf 'feature\n' > f.txt; git add f.txt; git commit -qm feat
  git checkout -q main
  printf 'mainline\n' > f.txt; git add f.txt; git commit -qm mainc
  git merge feature -q >/dev/null 2>&1 || true
)
SHA_BEFORE="$(git -C "$REPO" rev-parse HEAD)"
PORC_BEFORE="$(git -C "$REPO" status --porcelain)"
RC=0; OUT="$(cd "$REPO" && bash "$HELPER" c6-branch 2>&1)" || RC=$?
if [ "$RC" -eq 7 ]; then pass "case6: unmerged → rc 7"; else fail "case6: expected rc 7, got $RC — $OUT"; fi
if printf '%s' "$OUT" | grep -qi 'resolve the merge'; then
  pass "case6: message says resolve the merge first"
else
  fail "case6: message missing 'resolve the merge' — $OUT"
fi
if [ "$(git -C "$REPO" status --porcelain)" = "$PORC_BEFORE" ] && \
   [ "$(git -C "$REPO" rev-parse HEAD)" = "$SHA_BEFORE" ]; then
  pass "case6: main untouched (porcelain + SHA)"
else
  fail "case6: main changed"
fi
( cd "$REPO" && git merge --abort >/dev/null 2>&1 || true )

# ════════════════════════════════════════════════════════════════════════════
# CASE 7 — clean-main no-op.
# ════════════════════════════════════════════════════════════════════════════
REPO="$(new_scratch case7)"
( cd "$REPO"; printf 'x\n' > f.txt; git add f.txt; git commit -qm init )
RC=0; OUT="$(cd "$REPO" && bash "$HELPER" c7-branch 2>&1)" || RC=$?
if [ "$RC" -eq 0 ]; then pass "case7: clean-main rc 0"; else fail "case7: rc 0 (got $RC) — $OUT"; fi
if printf '%s' "$OUT" | grep -qi 'main was clean'; then
  pass "case7: notes 'main was clean'"
else
  fail "case7: missing clean note — $OUT"
fi

# ════════════════════════════════════════════════════════════════════════════
# CASE 8 — .zskills/ exclusion (a .zskills/tracked file is neither carried nor
# deleted).
# ════════════════════════════════════════════════════════════════════════════
REPO="$(new_scratch case8)"
( cd "$REPO"
  printf 'x\n' > f.txt; git add f.txt; git commit -qm init
  mkdir -p .zskills; printf 'pipe.id\n' > .zskills/tracked
  printf 'realdirt\n' > real.txt   # untracked, carryable
)
RC=0; OUT="$(cd "$REPO" && bash "$HELPER" c8-branch 2>&1)" || RC=$?
WT="$(wt_path_for "$REPO" c8-branch)"
if [ "$RC" -eq 0 ]; then pass "case8: rc 0"; else fail "case8: rc 0 (got $RC) — $OUT"; fi
if [ -f "$REPO/.zskills/tracked" ]; then
  pass "case8: main .zskills/tracked NOT deleted"
else
  fail "case8: main .zskills/tracked was wrongly removed"
fi
if [ ! -f "$WT/.zskills/tracked" ] || \
   [ "$(cat "$WT/.zskills/tracked")" != "pipe.id" ]; then
  # The worktree's own create-worktree write puts a DIFFERENT pipeline id here;
  # the point is main's .zskills/tracked content was NOT carried over.
  pass "case8: main's .zskills/tracked content not carried into worktree"
else
  fail "case8: main .zskills/tracked was carried (excluded path leaked)"
fi
if [ ! -f "$REPO/real.txt" ] && [ -f "$WT/real.txt" ]; then
  pass "case8: real untracked file carried (sanity — exclusion is selective)"
else
  fail "case8: real.txt not carried correctly"
fi

# ════════════════════════════════════════════════════════════════════════════
# CASE 9 — gitignored file NOT carried.
# ════════════════════════════════════════════════════════════════════════════
REPO="$(new_scratch case9)"
( cd "$REPO"
  printf 'node_modules/\n' > .gitignore; git add .gitignore; git commit -qm init
  mkdir -p node_modules; printf 'junk\n' > node_modules/x.js   # gitignored
  printf 'kept\n' > kept.txt                                   # untracked carryable
)
RC=0; OUT="$(cd "$REPO" && bash "$HELPER" c9-branch 2>&1)" || RC=$?
WT="$(wt_path_for "$REPO" c9-branch)"
if [ "$RC" -eq 0 ]; then pass "case9: rc 0"; else fail "case9: rc 0 (got $RC) — $OUT"; fi
if [ -f "$REPO/node_modules/x.js" ]; then
  pass "case9: gitignored file still on main (not deleted)"
else
  fail "case9: gitignored file wrongly removed from main"
fi
if [ ! -f "$WT/node_modules/x.js" ]; then
  pass "case9: gitignored file NOT carried into worktree (porcelain exclusion)"
else
  fail "case9: gitignored file leaked into worktree"
fi

# ════════════════════════════════════════════════════════════════════════════
# CASE 10 — untracked NESTED-dir files carry per-file (DA7).
# ════════════════════════════════════════════════════════════════════════════
REPO="$(new_scratch case10)"
( cd "$REPO"
  printf 'x\n' > f.txt; git add f.txt; git commit -qm init
  mkdir -p newdir; printf 'A\n' > newdir/a.txt; printf 'B\n' > newdir/b.txt
)
RC=0; OUT="$(cd "$REPO" && bash "$HELPER" c10-branch 2>&1)" || RC=$?
WT="$(wt_path_for "$REPO" c10-branch)"
if [ "$RC" -eq 0 ]; then pass "case10: rc 0"; else fail "case10: rc 0 (got $RC) — $OUT"; fi
if [ -f "$WT/newdir/a.txt" ] && [ -f "$WT/newdir/b.txt" ] && \
   [ "$(cat "$WT/newdir/a.txt")" = "A" ] && [ "$(cat "$WT/newdir/b.txt")" = "B" ]; then
  pass "case10: both nested untracked files carried per-file"
else
  fail "case10: nested dir not carried per-file"
fi
if [ ! -f "$REPO/newdir/a.txt" ] && [ ! -f "$REPO/newdir/b.txt" ]; then
  pass "case10: nested untracked files removed from main"
else
  fail "case10: nested files left on main"
fi

# ════════════════════════════════════════════════════════════════════════════
# CASE 11 — local-main-ahead-of-origin + dirty → rc 0; wt HEAD == LOCAL main
# HEAD; main clean after.
# ════════════════════════════════════════════════════════════════════════════
SEED="$SANDBOX_ROOT/seed11"
mkdir -p "$SEED"
git -C "$SEED" init -q -b main
git -C "$SEED" config user.email "mvwt@test.invalid"
git -C "$SEED" config user.name "mvwt"
( cd "$SEED"; printf 'v1\n' > f.txt; git add f.txt; git commit -qm c1 )
REPO="$SANDBOX_ROOT/case11"
git clone -q "$SEED" "$REPO"
git -C "$REPO" config user.email "mvwt@test.invalid"
git -C "$REPO" config user.name "mvwt"
mkdir -p "$REPO/.claude" "$SANDBOX_ROOT/case11-wt"
printf '{\n  "execution": { "worktree_root": "%s-wt" }\n}\n' "$REPO" \
  > "$REPO/.claude/zskills-config.json"
( cd "$REPO"
  git add .claude/zskills-config.json; git commit -qm config
  printf 'v2\n' > f.txt; git add f.txt; git commit -qm c2   # 1 ahead of origin/main (over the seed)
  printf 'dirty\n' > f.txt
)
AHEAD="$(git -C "$REPO" rev-list --count origin/main..main)"
LOCAL_HEAD="$(git -C "$REPO" rev-parse HEAD)"
RC=0; OUT="$(cd "$REPO" && bash "$HELPER" c11-branch 2>&1)" || RC=$?
WT="$(wt_path_for "$REPO" c11-branch)"
if [ "$AHEAD" -ge 1 ]; then pass "case11: precondition — local main ahead of origin ($AHEAD)"; else fail "case11: ahead=$AHEAD"; fi
if [ "$RC" -eq 0 ]; then pass "case11: ahead+dirty rc 0 (no preflight to trip)"; else fail "case11: rc 0 (got $RC) — $OUT"; fi
if [ "$(git -C "$WT" rev-parse HEAD)" = "$LOCAL_HEAD" ]; then
  pass "case11: worktree HEAD == LOCAL main HEAD"
else
  fail "case11: worktree HEAD != local main HEAD"
fi
if [ -z "$(git -C "$REPO" status --porcelain)" ]; then
  pass "case11: main clean after restore"
else
  fail "case11: main not clean — $(git -C "$REPO" status --porcelain)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
