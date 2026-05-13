#!/usr/bin/env bash
# tests/canary-ensure-worktree.sh
#
# Phase 5 canary — PREAMBLE_WORKTREE_GATE plan.
#
# SCOPE: pure-shell integration assertion that the shared
# `ensure-worktree.sh` preamble (loaded from
# `.claude/skills/create-worktree/scripts/ensure-worktree.sh`)
# implements the 10 gate sub-cases A-J that all 6 adopter skills rely
# on. Six consumer skills (draft-plan, refine-plan, draft-tests,
# block-diagram/add-block, block-diagram/add-example, fix-issues) front-
# run this helper to honour --worktree-override, no-op when already
# inside a worktree, no-op when main_protected is not true, otherwise
# create a fresh worktree via the peer create-worktree.sh.
#
# WHAT THIS CANARY IS:
#   * End-to-end fixture-based assertion of ensure-worktree.sh's exit
#     code + stdout contract across the 10 sub-cases enumerated in
#     `docs/plans/PREAMBLE_WORKTREE_GATE.md` Phase 5.
#   * Uses a bare-repo origin so create-worktree's pre-flight fetch
#     (`git fetch --prune origin`) succeeds — without `origin.git`,
#     create-worktree.sh fails before reaching the gate logic we want
#     to exercise. The bare origin is the load-bearing fixture detail.
#
# WHAT THIS CANARY IS NOT:
#   * A test of create-worktree.sh internals (covered by
#     tests/test-create-worktree.sh).
#   * A test of the zskills-paths.sh helper (covered by
#     tests/test-update-zskills-paths-migration.sh) — sub-case J pins
#     ONE specific contract that ensure-worktree.sh's dataflow depends
#     on (ZSKILLS_PATHS_ROOT override precedence). If that contract
#     regresses, all 6 adopter skills produce WT-rooted paths that
#     silently land in main/'s .zskills/ tree.
#
# Sub-case index:
#   A: in-main + main_protected=true → creates worktree, exit 0
#   B: cd into worktree from A → empty stdout, exit 0
#   C: main_protected=false config → empty stdout, exit 0
#   D: missing config file → empty stdout, exit 0 (defaults non-protected)
#   E: in-main + valid --worktree-override → stdout=override, exit 0
#   F: override non-existent dir → exit 2
#   G: override belongs to different repo → exit 2
#   H: missing --pipeline-id → exit 5
#   I: in-worktree + --worktree-override <other-worktree> → override wins
#   J: ZSKILLS_PATHS_ROOT override precedence — derived paths reroot to WT

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HELPER="$REPO_ROOT/.claude/skills/create-worktree/scripts/ensure-worktree.sh"
PATHS_HELPER="$REPO_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Install-integrity check upfront — a missing helper is a hard fail,
# not a per-sub-case skip.
if [ ! -x "$HELPER" ]; then
  fail "install-integrity" "ensure-worktree.sh missing or not executable at $HELPER"
  printf '\n\033[31mResults: 0 passed, 1 failed (of 1)\033[0m\n'
  exit 1
fi
if [ ! -f "$PATHS_HELPER" ]; then
  fail "install-integrity" "zskills-paths.sh missing at $PATHS_HELPER"
  printf '\n\033[31mResults: 0 passed, 1 failed (of 1)\033[0m\n'
  exit 1
fi

# ──────────────────────────────────────────────────────────────────
# Fixture setup. Bare-origin satisfies create-worktree.sh's pre-flight
# `git fetch --prune origin` (R-F11). $WORK/main is the "main repo"
# the canary cd's into for in-main sub-cases; $WORK/other is a
# DIFFERENT repo used by sub-case G.
# ──────────────────────────────────────────────────────────────────
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Build main repo with one commit on `main`, then clone --bare into
# origin.git, then wire main's remote `origin` to that bare. Avoids any
# subprocess `git push` (so harness-level Bash hooks scanning for
# `git push origin main` against a protected project don't interfere
# with the fixture).
git init -q -b main "$WORK/main"
(
  cd "$WORK/main"
  git -c user.email=canary@x -c user.name=canary commit --allow-empty -q -m init
)
git clone --bare -q "$WORK/main" "$WORK/origin.git"
(
  cd "$WORK/main"
  git remote add origin "$WORK/origin.git"
  git branch --set-upstream-to=origin/main main 2>/dev/null || true
)
git init -q -b main "$WORK/other"
(
  cd "$WORK/other"
  git -c user.email=canary@x -c user.name=canary commit --allow-empty -q -m init
)

mkdir -p "$WORK/main/.claude" "$WORK/wt"

# create-worktree.sh's post-create stub dispatcher references
# $CLAUDE_PROJECT_DIR under `set -u`; without it set, the script aborts
# late (after the worktree is materialized) on "unbound variable". In
# production, the harness always sets this. Mirror that for fixture
# runs by pointing it at $WORK/main (the fixture's "project root").
export CLAUDE_PROJECT_DIR="$WORK/main"
# Set worktree_root inside $WORK so create-worktree's default `/tmp/<name>`
# scheme doesn't collide across canary runs and the fixture is fully self-
# contained (and torn down by the EXIT trap).
cat > "$WORK/main/.claude/zskills-config.json" <<JSON
{ "execution": { "landing": "pr", "main_protected": true, "branch_prefix": "feat/", "worktree_root": "$WORK/wt" } }
JSON

# Shared invocation args for sub-cases that use the standard set.
# Tests always pass --pipeline-id (except sub-case H, which deliberately omits it).
COMMON_ARGS=(--prefix canary --pipeline-id canary.ensure-worktree)

# ──────────────────────────────────────────────────────────────────
# Sub-case A: in-main + main_protected=true → creates worktree.
# Asserts exit 0 AND non-empty stdout pointing at an existing dir.
# ──────────────────────────────────────────────────────────────────
A_OUT=$(cd "$WORK/main" && bash "$HELPER" "${COMMON_ARGS[@]}" sub-a 2>/tmp/canary-a.err) || A_RC=$?
A_RC=${A_RC:-0}
if [ "$A_RC" -eq 0 ] && [ -n "$A_OUT" ] && [ -d "$A_OUT" ]; then
  pass "A: in-main + protected → creates worktree at $A_OUT"
  WT_PATH_A="$A_OUT"
else
  fail "A: in-main + protected → creates worktree" "exit=$A_RC stdout='$A_OUT'"
  WT_PATH_A=""
fi

# ──────────────────────────────────────────────────────────────────
# Sub-case B: cd into worktree from A → empty stdout, exit 0 (no-op).
# ──────────────────────────────────────────────────────────────────
if [ -n "$WT_PATH_A" ] && [ -d "$WT_PATH_A" ]; then
  B_OUT=$(cd "$WT_PATH_A" && bash "$HELPER" "${COMMON_ARGS[@]}" sub-b 2>/dev/null) || B_RC=$?
  B_RC=${B_RC:-0}
  # Stdout contract: helper prints a single newline as the "no-op" marker
  # (printf '\n') so a trailing-newline-stripping $(...) yields the empty
  # string. Test for empty after the strip.
  if [ "$B_RC" -eq 0 ] && [ -z "$B_OUT" ]; then
    pass "B: in-worktree → no-op (empty stdout, exit 0)"
  else
    fail "B: in-worktree → no-op" "exit=$B_RC stdout='$B_OUT'"
  fi
else
  fail "B: in-worktree → no-op" "skipped — sub-case A failed to produce a worktree"
fi

# ──────────────────────────────────────────────────────────────────
# Sub-case C: main_protected=false → empty stdout, exit 0 (no-op).
# Toggle the config, run, then restore.
# ──────────────────────────────────────────────────────────────────
cat > "$WORK/main/.claude/zskills-config.json" <<JSON
{ "execution": { "landing": "pr", "main_protected": false, "branch_prefix": "feat/", "worktree_root": "$WORK/wt" } }
JSON
C_OUT=$(cd "$WORK/main" && bash "$HELPER" "${COMMON_ARGS[@]}" sub-c 2>/dev/null) || C_RC=$?
C_RC=${C_RC:-0}
if [ "$C_RC" -eq 0 ] && [ -z "$C_OUT" ]; then
  pass "C: main_protected=false → no-op"
else
  fail "C: main_protected=false → no-op" "exit=$C_RC stdout='$C_OUT'"
fi
# Restore protected config for subsequent sub-cases.
cat > "$WORK/main/.claude/zskills-config.json" <<JSON
{ "execution": { "landing": "pr", "main_protected": true, "branch_prefix": "feat/", "worktree_root": "$WORK/wt" } }
JSON

# ──────────────────────────────────────────────────────────────────
# Sub-case D: missing config file → empty stdout, exit 0 (defaults
# non-protected).
# ──────────────────────────────────────────────────────────────────
mv "$WORK/main/.claude/zskills-config.json" "$WORK/main/.claude/zskills-config.json.bak"
D_OUT=$(cd "$WORK/main" && bash "$HELPER" "${COMMON_ARGS[@]}" sub-d 2>/dev/null) || D_RC=$?
D_RC=${D_RC:-0}
if [ "$D_RC" -eq 0 ] && [ -z "$D_OUT" ]; then
  pass "D: missing config → no-op (defaults non-protected)"
else
  fail "D: missing config → no-op" "exit=$D_RC stdout='$D_OUT'"
fi
mv "$WORK/main/.claude/zskills-config.json.bak" "$WORK/main/.claude/zskills-config.json"

# ──────────────────────────────────────────────────────────────────
# Sub-case E: in-main + valid --worktree-override → stdout=override.
# WT_PATH_A is a valid worktree of $WORK/main and is the natural
# override target. Override wins over the protected gate.
# ──────────────────────────────────────────────────────────────────
if [ -n "$WT_PATH_A" ] && [ -d "$WT_PATH_A" ]; then
  E_OUT=$(cd "$WORK/main" && bash "$HELPER" "${COMMON_ARGS[@]}" \
    --worktree-override "$WT_PATH_A" sub-e 2>/dev/null) || E_RC=$?
  E_RC=${E_RC:-0}
  # WT_PATH_A may be a symlink-resolved path; helper symlink-resolves
  # too, so direct string equality holds.
  E_EXPECT=$(cd "$WT_PATH_A" && pwd)
  if [ "$E_RC" -eq 0 ] && [ "$E_OUT" = "$E_EXPECT" ]; then
    pass "E: --worktree-override valid → stdout=override"
  else
    fail "E: --worktree-override valid → stdout=override" "exit=$E_RC stdout='$E_OUT' expected='$E_EXPECT'"
  fi
else
  fail "E: --worktree-override valid" "skipped — sub-case A failed"
fi

# ──────────────────────────────────────────────────────────────────
# Sub-case F: override non-existent dir → exit 2.
# ──────────────────────────────────────────────────────────────────
F_OUT=$(cd "$WORK/main" && bash "$HELPER" "${COMMON_ARGS[@]}" \
  --worktree-override "$WORK/does-not-exist" sub-f 2>/dev/null) || F_RC=$?
F_RC=${F_RC:-0}
if [ "$F_RC" -eq 2 ] && [ -z "$F_OUT" ]; then
  pass "F: --worktree-override non-existent → exit 2"
else
  fail "F: --worktree-override non-existent → exit 2" "exit=$F_RC stdout='$F_OUT'"
fi

# ──────────────────────────────────────────────────────────────────
# Sub-case G: override belongs to a DIFFERENT repo → exit 2.
# $WORK/other is a separate git init (no shared common-dir with
# $WORK/main), so the override-validation 4-check should reject it.
# ──────────────────────────────────────────────────────────────────
G_OUT=$(cd "$WORK/main" && bash "$HELPER" "${COMMON_ARGS[@]}" \
  --worktree-override "$WORK/other" sub-g 2>/dev/null) || G_RC=$?
G_RC=${G_RC:-0}
if [ "$G_RC" -eq 2 ] && [ -z "$G_OUT" ]; then
  pass "G: --worktree-override different repo → exit 2"
else
  fail "G: --worktree-override different repo → exit 2" "exit=$G_RC stdout='$G_OUT'"
fi

# ──────────────────────────────────────────────────────────────────
# Sub-case H: missing --pipeline-id → exit 5 (input validation).
# Pass --prefix and slug but deliberately omit --pipeline-id.
# ──────────────────────────────────────────────────────────────────
H_OUT=$(cd "$WORK/main" && bash "$HELPER" --prefix canary sub-h 2>/dev/null) || H_RC=$?
H_RC=${H_RC:-0}
if [ "$H_RC" -eq 5 ] && [ -z "$H_OUT" ]; then
  pass "H: missing --pipeline-id → exit 5"
else
  fail "H: missing --pipeline-id → exit 5" "exit=$H_RC stdout='$H_OUT'"
fi

# ──────────────────────────────────────────────────────────────────
# Sub-case I: in-worktree + --worktree-override <other-valid-worktree>
# → override wins (DA-R2-19). Create a second worktree as the
# override target, then cd into WT_PATH_A and pass the second worktree
# as the override. Helper should return the second worktree's path.
# ──────────────────────────────────────────────────────────────────
if [ -n "$WT_PATH_A" ] && [ -d "$WT_PATH_A" ]; then
  # Spin up a second worktree directly via create-worktree.sh (using
  # the helper itself would loop). Use a different branch name to
  # avoid colliding with sub-a's.
  CW="$REPO_ROOT/.claude/skills/create-worktree/scripts/create-worktree.sh"
  WT_OTHER=$(cd "$WORK/main" && bash "$CW" \
    --prefix canary --pipeline-id canary.ensure-worktree.i sub-i-other 2>/dev/null) || I_SETUP_RC=$?
  I_SETUP_RC=${I_SETUP_RC:-0}
  if [ "$I_SETUP_RC" -eq 0 ] && [ -n "$WT_OTHER" ] && [ -d "$WT_OTHER" ]; then
    I_OUT=$(cd "$WT_PATH_A" && bash "$HELPER" "${COMMON_ARGS[@]}" \
      --worktree-override "$WT_OTHER" sub-i 2>/dev/null) || I_RC=$?
    I_RC=${I_RC:-0}
    I_EXPECT=$(cd "$WT_OTHER" && pwd)
    if [ "$I_RC" -eq 0 ] && [ "$I_OUT" = "$I_EXPECT" ]; then
      pass "I: in-worktree + override → override wins (stdout=other-worktree)"
    else
      fail "I: in-worktree + override → override wins" "exit=$I_RC stdout='$I_OUT' expected='$I_EXPECT'"
    fi
  else
    fail "I: in-worktree + override → override wins" "setup failed: could not create second worktree (rc=$I_SETUP_RC stdout='$WT_OTHER')"
  fi
else
  fail "I: in-worktree + override" "skipped — sub-case A failed"
fi

# ──────────────────────────────────────────────────────────────────
# Sub-case J: R3-1 verification. After ensure-worktree.sh returns
# $WT_PATH, simulate the preamble's `export ZSKILLS_PATHS_ROOT="$WT_PATH"`
# and source zskills-paths.sh. Assert $ZSKILLS_AUDIT_DIR is rooted at
# $WT_PATH (not at $WORK/main). This pins the override precedence
# contract that all 6 adopter skills depend on for WT-rooted audit/
# plan paths in PR mode.
# ──────────────────────────────────────────────────────────────────
if [ -n "$WT_PATH_A" ] && [ -d "$WT_PATH_A" ]; then
  # Run in a subshell so the sourced helper's env changes don't bleed.
  J_RESULT=$(
    set +u
    CLAUDE_PROJECT_DIR="$WORK/main"
    export CLAUDE_PROJECT_DIR
    ZSKILLS_PATHS_ROOT="$WT_PATH_A"
    export ZSKILLS_PATHS_ROOT
    # shellcheck disable=SC1090
    . "$PATHS_HELPER" >/dev/null 2>&1
    printf '%s\n' "$ZSKILLS_AUDIT_DIR"
  )
  J_EXPECT_PREFIX="$WT_PATH_A/"
  J_REJECT_PREFIX="$WORK/main/"
  case "$J_RESULT" in
    "$J_EXPECT_PREFIX"*)
      # Belt-and-suspenders: confirm it does NOT also match the reject prefix.
      case "$J_RESULT" in
        "$J_REJECT_PREFIX"*)
          fail "J: ZSKILLS_PATHS_ROOT override → WT-rooted audit dir" "audit dir matches BOTH WT and main prefixes ('$J_RESULT')"
          ;;
        *)
          pass "J: ZSKILLS_PATHS_ROOT override → WT-rooted audit dir ($J_RESULT)"
          ;;
      esac
      ;;
    *)
      fail "J: ZSKILLS_PATHS_ROOT override → WT-rooted audit dir" "audit dir '$J_RESULT' does not start with '$J_EXPECT_PREFIX'"
      ;;
  esac
else
  fail "J: ZSKILLS_PATHS_ROOT override" "skipped — sub-case A failed"
fi

# ──────────────────────────────────────────────────────────────────
# Results.
# ──────────────────────────────────────────────────────────────────
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
