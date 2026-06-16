#!/usr/bin/env bash
# tests/test-fix-issues-sprint-land-pr.sh
#
# Issue #337 — behavioral coverage for the two sprint-level `/land-pr`
# dispatch blocks in `skills/fix-issues/SKILL.md`:
#
#   Block A — `### Sprint-level SPRINT_REPORT.md landing` (Phase 6
#             post-loop ship of SPRINT_REPORT.md; added by PR #329 at
#             ~7211fcf).
#   Block B — `### If no actionable issues found` SHIP branch
#             (added by PR #343 as a sibling dispatch for the
#             no-actionable + dirty-tracker path).
#
# Sister to tests/test-fix-issues-sprint-worktree-gate.sh (schema-only).
# That test pins shape; this one drives the actual extracted code paths
# against fixtures so realpath, marker-sequencing, LP_SPRINT result-file
# parsing, and the `--auto` conditional cannot regress silently.
#
# Strategy mirrors tests/test-fix-issues-dashboard.sh (#334 → PR #345):
# extract-from-source via awk, run the extracted bash against a
# sandboxed fixture (mock `git`, mock `realpath` to drive the bash
# fallback, mock LP_SPRINT result-file shapes). The test stays coupled
# to the real code path — any future drift surfaces as a fail here.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/fix-issues/modes/sprint.md"

PASS=0
FAIL=0

pass() { printf '  PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL: %s — %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# ─────────────────────────────────────────────────────────────────────
# Extract Block A — sprint-level SPRINT_REPORT.md landing
# Bounded by the heading `### Sprint-level SPRINT_REPORT.md landing`
# (find the NEXT ```bash fence, capture through the matching ```).
# ─────────────────────────────────────────────────────────────────────
BLOCK_A="$TMP_ROOT/block_a.sh"
awk '
  /^### Sprint-level SPRINT_REPORT\.md landing/ { found=1; next }
  found && /^```bash$/ { in_fence=1; next }
  found && in_fence && /^```$/ { exit }
  found && in_fence { print }
' "$SKILL" > "$BLOCK_A"

if [ ! -s "$BLOCK_A" ]; then
  fail "extract Block A (sprint-level SPRINT_REPORT.md landing)" "extraction produced empty file"
else
  pass "extract Block A (sprint-level SPRINT_REPORT.md landing — $(wc -l < "$BLOCK_A") lines)"
fi

# ─────────────────────────────────────────────────────────────────────
# Extract Block B — `### If no actionable issues found` SHIP branch.
# This heading wraps a numbered list whose step-2 contains the bash
# fence we want. Bounded by the heading and the next `^### ` heading.
# ─────────────────────────────────────────────────────────────────────
BLOCK_B="$TMP_ROOT/block_b.sh"
awk '
  /^### If no actionable issues found/ { found=1; next }
  found && /^### / { exit }
  found && /^   ```bash$/ { in_fence=1; next }
  found && in_fence && /^   ```$/ { exit }
  found && in_fence { sub(/^   /, ""); print }
' "$SKILL" > "$BLOCK_B"

if [ ! -s "$BLOCK_B" ]; then
  fail "extract Block B (no-actionable SHIP branch)" "extraction produced empty file"
else
  pass "extract Block B (no-actionable SHIP branch — $(wc -l < "$BLOCK_B") lines)"
fi

# ─────────────────────────────────────────────────────────────────────
# Helpers — build a sandbox per case with:
#   - $WT_PATH (worktree top), a git fake repo
#   - $MAIN_ROOT separate dir (so requires/fulfilled markers land here)
#   - a `git` shim on PATH that fakes the operations the block needs
#     (rev-parse --show-toplevel / --git-common-dir, add, commit,
#      diff --cached --name-only, rev-parse --abbrev-ref HEAD,
#      status --porcelain, worktree remove)
#   - a `realpath` shim toggleable to "GNU" or "fallback" via env
#   - a $RESULT_FILE with a chosen LP_SPRINT result shape
#   - a faux `$ZSKILLS_AUDIT_DIR` containing SPRINT_REPORT.md so the
#     realpath path-normalize has something real to look at
#
# Each case prepares the sandbox, exports the env the block reads,
# then sources the block in a subshell. The block contains a
# `# Skill: { skill: "land-pr", args: ... }` comment line (NOT
# executable) where the real /land-pr would run — to simulate the
# dispatch, we drop our prepared $RESULT_FILE BEFORE sourcing, so the
# block's post-dispatch parser reads from it. We also have to neuter
# the `. "$CLAUDE_PROJECT_DIR/.claude/skills/..." ` source lines so
# the block doesn't try to source the real zskills-paths.sh /
# zskills-resolve-config.sh (we set ZSKILLS_AUDIT_DIR directly).
# ─────────────────────────────────────────────────────────────────────

# Build the env shim once — used by both block runners.
mkshim() {
  local dir="$1" wt="$2" main="$3" status_dirty="$4" realpath_mode="$5" branch="$6"
  mkdir -p "$dir/bin"

  # git shim — minimal subset.
  cat > "$dir/bin/git" <<EOF
#!/usr/bin/env bash
set -u
WT_PATH_FIX="$wt"
MAIN_ROOT_FIX="$main"
STATUS_DIRTY="$status_dirty"
BRANCH_FIX="$branch"

# Strip a leading "-C <dir>" pair so the rest looks like a normal git invocation.
if [ "\${1:-}" = "-C" ]; then shift 2; fi

case "\$1" in
  rev-parse)
    case "\${2:-}" in
      --show-toplevel) echo "\$WT_PATH_FIX" ;;
      --git-common-dir) echo "\$MAIN_ROOT_FIX/.git" ;;
      --abbrev-ref)
        if [ "\${3:-}" = "HEAD" ]; then echo "\$BRANCH_FIX"; fi
        ;;
      *) exit 0 ;;
    esac
    ;;
  add)
    # add <pathspec> | add -A
    # Pretend it always succeeds; track staged via a sentinel file.
    if [ "\${2:-}" = "-A" ]; then
      if [ "\$STATUS_DIRTY" = "1" ]; then
        echo "tracker_change.txt" > "\$WT_PATH_FIX/.staged"
      fi
    else
      # add <file>
      if [ -n "\${2:-}" ]; then echo "\$2" > "\$WT_PATH_FIX/.staged"; fi
    fi
    ;;
  diff)
    # diff --cached --name-only
    if [ "\${2:-}" = "--cached" ] && [ "\${3:-}" = "--name-only" ]; then
      if [ -f "\$WT_PATH_FIX/.staged" ]; then cat "\$WT_PATH_FIX/.staged"; fi
    fi
    ;;
  commit)
    # Pretend commit succeeded. Clear staged sentinel.
    rm -f "\$WT_PATH_FIX/.staged"
    echo "[fake-commit] ok" >&2
    ;;
  status)
    # status --porcelain
    if [ "\$STATUS_DIRTY" = "1" ]; then
      echo " M tracker_change.txt"
    fi
    ;;
  worktree)
    # worktree remove --force <path>
    if [ "\${2:-}" = "remove" ]; then
      echo "[fake-worktree-remove] \${4:-}" >&2
    fi
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$dir/bin/git"

  # realpath shim — either echoes a GNU-style rel path or exits 1
  # (forcing the bash-fallback `case "\$ABS_FILE_CANON"` branch).
  cat > "$dir/bin/realpath" <<EOF
#!/usr/bin/env bash
# Mode: $realpath_mode (gnu|fallback)
if [ "$realpath_mode" = "fallback" ]; then
  exit 1
fi
# GNU-style: --relative-to=BASE PATH
BASE=""
FILE=""
while [ "\${1:-}" != "" ]; do
  case "\$1" in
    --relative-to=*) BASE="\${1#--relative-to=}"; shift ;;
    --relative-to) BASE="\$2"; shift 2 ;;
    -*) shift ;;
    *) FILE="\$1"; shift ;;
  esac
done
# Canonicalize file (drop double-slashes) and strip BASE prefix if matching.
F="\$FILE"
B="\$BASE"
case "\$F" in
  "\$B"/*) echo "\${F#\$B/}" ;;
  *) echo "\$F" ;;
esac
EOF
  chmod +x "$dir/bin/realpath"
}

# Build a $RESULT_FILE with arbitrary key=value lines.
mk_result_file() {
  local path="$1"; shift
  : > "$path"
  for kv in "$@"; do printf '%s\n' "$kv" >> "$path"; done
}

# Patch a copy of $BLOCK to: (a) drop the `. <zskills-paths>` sources;
# (b) replace the `# Skill: { skill: "land-pr", ... }` comment with an
# inline "fake-/land-pr" that writes our pre-staged result-file contents
# into $RESULT_FILE (we stage them ahead of sourcing).
#
# The block reads ZSKILLS_REPORTS_DIR for $ABS_FILE (post-#217) — we set
# it via env. ZSKILLS_AUDIT_DIR is also exported for any non-SPRINT_REPORT
# audit-side reads the block may hit.
# The block reads PIPELINE_ID, SPRINT_ID, COMMIT_CO_AUTHOR — env too.
# The block sets RESULT_FILE=$(mktemp). We can't intercept that mktemp,
# so we patch the literal `RESULT_FILE=$(mktemp)` to `RESULT_FILE="$PREPARED_RESULT_FILE"`.
patch_block() {
  local src="$1" out="$2"
  # 1. Replace `. "$CLAUDE_PROJECT_DIR/.../zskills-{paths,resolve-config}.sh"`
  #    lines with `: # patched-out source` — env-vars are pre-set by the
  #    test harness instead.
  # 2. Replace `RESULT_FILE=$(mktemp)` with our pre-staged path so the
  #    parser block reads our synthesized result-file.
  # 3. Same for `BODY_FILE=$(mktemp)` (avoid spurious tmpfile noise).
  awk '
    /^[[:space:]]*\.[[:space:]]+"\$CLAUDE_PROJECT_DIR\/\.claude\/skills\/update-zskills\/scripts\/zskills-(paths|resolve-config)\.sh"/ {
      print ": # patched-out source: " $0
      next
    }
    {
      sub(/RESULT_FILE=\$\(mktemp\)/, "RESULT_FILE=\"$PREPARED_RESULT_FILE\"")
      sub(/BODY_FILE=\$\(mktemp\)/,   "BODY_FILE=\"$PREPARED_BODY_FILE\"")
      print
    }
  ' "$src" > "$out"
}

# Run a patched block in a subshell with controlled env + PATH.
# Stores rc in $LAST_RC and captures stderr to $TMP_ROOT/<tag>.err.
run_block() {
  local tag="$1" patched="$2" shim_bin="$3"
  LAST_TAG="$tag"
  (
    set +e
    set -u
    export PATH="$shim_bin:$PATH"
    # Legacy-lane faithful under `set -u`: the patched block retains the new
    # resolution idiom's `if [ -f "${CLAUDE_PLUGIN_ROOT}/…" ]` wrapper (only the
    # else-branch `. "$CLAUDE_PROJECT_DIR/…"` source line is patched out). In
    # production that fence runs WITHOUT `set -u`; the bare ${CLAUDE_PLUGIN_ROOT}
    # token expands empty → the `-f` test is false → else (patched-out) →
    # env-pre-set vars win. Bind the token EMPTY (not a real path) so that same
    # legacy else path is taken without an unbound-variable abort.
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
    # shellcheck disable=SC1090
    source "$patched"
  ) >"$TMP_ROOT/$tag.out" 2>"$TMP_ROOT/$tag.err"
  LAST_RC=$?
}

# ─────────────────────────────────────────────────────────────────────
# Test cases — Block A (Sprint-level SPRINT_REPORT.md landing)
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "=== Block A — Sprint-level SPRINT_REPORT.md landing ==="

# Each case sets up a fresh sandbox. Writes the case dir into the
# global $CASE_DIR (NOT via stdout, because command-substitution would
# strand the export-side-effects in a subshell).
setup_case_a() {
  local case_id="$1" realpath_mode="$2"
  CASE_DIR="$TMP_ROOT/A-$case_id"
  mkdir -p "$CASE_DIR"
  local wt="$CASE_DIR/wt"
  local main="$CASE_DIR/main"
  local audit="$wt/.zskills/audit"
  mkdir -p "$wt" "$main/.zskills/tracking" "$main/.git" "$audit"
  echo "# sprint report" > "$audit/SPRINT_REPORT.md"

  mkshim "$CASE_DIR" "$wt" "$main" "0" "$realpath_mode" "feature/x"

  export WT_PATH="$wt"
  export ZSKILLS_AUDIT_DIR="$audit"
  # Post-#217: SPRINT_REPORT.md moved to $ZSKILLS_REPORTS_DIR (legacy default
  # = audit dir until reports_dir is configured separately in Phase 3).
  export ZSKILLS_REPORTS_DIR="$audit"
  export CLAUDE_PROJECT_DIR="$REPO_ROOT"
  export PIPELINE_ID="test-pipeline-A-$case_id"
  export SPRINT_ID="sprintA$case_id"
  export COMMIT_CO_AUTHOR=""
}

run_block_a() {
  local case_dir="$1" auto_value="$2"
  shift 2
  local -a result_file_args
  if [ $# -gt 0 ]; then result_file_args=("$@"); else result_file_args=(); fi
  local patched="$case_dir/block.sh"
  patch_block "$BLOCK_A" "$patched"

  export PREPARED_RESULT_FILE="$case_dir/result.txt"
  export PREPARED_BODY_FILE="$case_dir/body.txt"
  if [ "${#result_file_args[@]}" -gt 0 ]; then
    mk_result_file "$PREPARED_RESULT_FILE" "${result_file_args[@]}"
  else
    : > "$PREPARED_RESULT_FILE"
  fi

  if [ "$auto_value" = "unset" ]; then unset AUTO || true
  else export AUTO="$auto_value"
  fi

  run_block "A-$(basename "$case_dir")" "$patched" "$case_dir/bin"
}

# Case A1: STATUS=merged, AUTO=true, GNU realpath
#   → expect requires.land-pr.<id> AND fulfilled.land-pr.<id> markers,
#     LAND_ARGS contains --auto.
test_A1_merged_auto_gnu() {
  setup_case_a "1" "gnu"
  run_block_a "$CASE_DIR" "true" "STATUS=merged" "PR_URL=https://pr/1" "PR_NUMBER=1"
  local req="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/requires.land-pr.fix-issues.sprint.$SPRINT_ID"
  local ful="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.fix-issues.sprint.$SPRINT_ID"
  if [ "$LAST_RC" -eq 0 ] && [ -s "$req" ] && [ -s "$ful" ]; then
    pass "A1: STATUS=merged + AUTO=true + GNU realpath → both markers present"
  else
    fail "A1: STATUS=merged + AUTO=true + GNU realpath" "rc=$LAST_RC req=$([ -e "$req" ] && echo Y || echo N) ful=$([ -e "$ful" ] && echo Y || echo N) stderr=$(head -5 "$TMP_ROOT/$LAST_TAG.err" 2>/dev/null)"
  fi
  unset AUTO WT_PATH ZSKILLS_AUDIT_DIR ZSKILLS_REPORTS_DIR PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
}

# Case A2: STATUS=merged, fallback realpath (mask `realpath` to exit 1)
#   → block's bash-fallback case "$ABS_FILE_CANON" branch must take over
#     and produce the same outcome.
test_A2_merged_fallback_realpath() {
  setup_case_a "2" "fallback"
  run_block_a "$CASE_DIR" "true" "STATUS=merged" "PR_URL=https://pr/2"
  local req="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/requires.land-pr.fix-issues.sprint.$SPRINT_ID"
  local ful="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.fix-issues.sprint.$SPRINT_ID"
  if [ "$LAST_RC" -eq 0 ] && [ -s "$req" ] && [ -s "$ful" ]; then
    pass "A2: STATUS=merged + realpath fallback path → both markers present"
  else
    fail "A2: STATUS=merged + realpath fallback path" "rc=$LAST_RC req=$([ -e "$req" ] && echo Y || echo N) ful=$([ -e "$ful" ] && echo Y || echo N) stderr=$(head -5 "$TMP_ROOT/$LAST_TAG.err" 2>/dev/null)"
  fi
  unset AUTO WT_PATH ZSKILLS_AUDIT_DIR ZSKILLS_REPORTS_DIR PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
}

# Case A3: STATUS=created (not merged) → requires.* present, fulfilled.* ABSENT
test_A3_created_no_fulfilled() {
  setup_case_a "3" "gnu"
  run_block_a "$CASE_DIR" "true" "STATUS=created" "PR_URL=https://pr/3" "PR_NUMBER=3"
  local req="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/requires.land-pr.fix-issues.sprint.$SPRINT_ID"
  local ful="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.fix-issues.sprint.$SPRINT_ID"
  if [ "$LAST_RC" -eq 0 ] && [ -s "$req" ] && [ ! -e "$ful" ]; then
    pass "A3: STATUS=created → requires.* present, fulfilled.* ABSENT (left open)"
  else
    fail "A3: STATUS=created" "rc=$LAST_RC req=$([ -e "$req" ] && echo Y || echo N) ful=$([ -e "$ful" ] && echo Y || echo N)"
  fi
  unset AUTO WT_PATH ZSKILLS_AUDIT_DIR ZSKILLS_REPORTS_DIR PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
}

# Case A4: STATUS variants that are non-merged → fulfilled.* ABSENT for each.
#   monitored, push-failed, rebase-conflict, create-failed, monitor-failed, merge-failed
test_A4_other_statuses_no_fulfilled() {
  local statuses=("monitored" "push-failed" "rebase-conflict" "create-failed" "monitor-failed" "merge-failed")
  local ok=1
  local i=0
  for st in "${statuses[@]}"; do
    i=$((i + 1))
    setup_case_a "4-$i" "gnu"
    run_block_a "$CASE_DIR" "true" "STATUS=$st"
    local ful="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.fix-issues.sprint.$SPRINT_ID"
    if [ "$LAST_RC" -ne 0 ] || [ -e "$ful" ]; then
      ok=0
      echo "    sub-case STATUS=$st failed (rc=$LAST_RC fulfilled-exists=$([ -e "$ful" ] && echo Y || echo N))" >&2
    fi
    unset AUTO WT_PATH ZSKILLS_AUDIT_DIR ZSKILLS_REPORTS_DIR PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
  done
  if [ "$ok" -eq 1 ]; then
    pass "A4: 6 non-merged STATUS variants → fulfilled.* never written"
  else
    fail "A4: 6 non-merged STATUS variants" "at least one wrote fulfilled.* (see stderr above)"
  fi
}

# Case A5: --auto conditional ON (AUTO=true) — LAND_ARGS contains --auto.
#  Trace via a wrapper that captures LAND_ARGS into a file. We patch the
#  block to additionally `printf '%s' "$LAND_ARGS" > $TMP_ROOT/A5.land_args`
#  right after the `LAND_ARGS=...` assignment.
# Helper: patch a block with an extra capture line that writes the
# final $LAND_ARGS value to a file after the AUTO-conditional fires.
patch_block_capturing_land_args() {
  local src="$1" out="$2" capture_file="$3"
  patch_block "$src" "$out"
  awk -v out="$capture_file" '
    /\[ "\$\{AUTO_FLAG:-0\}" = "1" \] && LAND_ARGS=/ {
      print
      print "printf \"%s\" \"$LAND_ARGS\" > " out
      next
    }
    /\[ "\$\{AUTOMERGE_FLAG:-0\}" = "1" \] && LAND_ARGS=/ {
      print
      print "printf \"%s\" \"$LAND_ARGS\" > " out
      next
    }
    { print }
  ' "$out" > "$out.new" && mv "$out.new" "$out"
}

test_A5_auto_true_emits_flag() {
  setup_case_a "5" "gnu"
  local patched="$CASE_DIR/block.sh"
  local cap="$TMP_ROOT/A5.land_args"
  patch_block_capturing_land_args "$BLOCK_A" "$patched" "$cap"

  export PREPARED_RESULT_FILE="$CASE_DIR/result.txt"
  export PREPARED_BODY_FILE="$CASE_DIR/body.txt"
  mk_result_file "$PREPARED_RESULT_FILE" "STATUS=merged"
  export AUTO_FLAG="1"
  run_block "A-5cap" "$patched" "$CASE_DIR/bin"
  if [ -f "$cap" ] && grep -q -- '--auto' "$cap"; then
    pass "A5: AUTO=true → LAND_ARGS contains --auto"
  else
    fail "A5: AUTO=true → LAND_ARGS contains --auto" "rc=$LAST_RC captured=$(cat "$cap" 2>/dev/null || echo missing) stderr=$(head -5 "$TMP_ROOT/A-5cap.err" 2>/dev/null)"
  fi
  unset AUTO_FLAG AUTOMERGE_FLAG WT_PATH ZSKILLS_AUDIT_DIR ZSKILLS_REPORTS_DIR PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
}

# Case A6: AUTO_FLAG=0 — LAND_ARGS must NOT contain --auto.
test_A6_auto_false_no_flag() {
  setup_case_a "6" "gnu"
  local patched="$CASE_DIR/block.sh"
  local cap="$TMP_ROOT/A6.land_args"
  patch_block_capturing_land_args "$BLOCK_A" "$patched" "$cap"

  export PREPARED_RESULT_FILE="$CASE_DIR/result.txt"
  export PREPARED_BODY_FILE="$CASE_DIR/body.txt"
  mk_result_file "$PREPARED_RESULT_FILE" "STATUS=merged"
  export AUTO_FLAG="0"
  run_block "A-6cap" "$patched" "$CASE_DIR/bin"
  if [ -f "$cap" ] && ! grep -q -- '--auto' "$cap"; then
    pass "A6: AUTO=false → LAND_ARGS does NOT contain --auto"
  else
    fail "A6: AUTO=false → LAND_ARGS does NOT contain --auto" "captured=$(cat "$cap" 2>/dev/null || echo missing)"
  fi
  unset AUTO_FLAG AUTOMERGE_FLAG WT_PATH ZSKILLS_AUDIT_DIR ZSKILLS_REPORTS_DIR PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
}

# Case A7: AUTO_FLAG unset + `set -u` — block must NOT crash, LAND_ARGS no --auto.
#   This pins the fix from issue #337 secondary: `[ "${AUTO_FLAG:-0}" = ... ]`
#   defaults under set -u; the prior `[ "$AUTO" = "true" ]` would have
#   triggered `unbound variable`.
test_A7_auto_unset_no_crash() {
  setup_case_a "7" "gnu"
  local patched="$CASE_DIR/block.sh"
  local cap="$TMP_ROOT/A7.land_args"
  patch_block_capturing_land_args "$BLOCK_A" "$patched" "$cap"

  export PREPARED_RESULT_FILE="$CASE_DIR/result.txt"
  export PREPARED_BODY_FILE="$CASE_DIR/body.txt"
  mk_result_file "$PREPARED_RESULT_FILE" "STATUS=merged"
  unset AUTO_FLAG AUTOMERGE_FLAG || true
  run_block "A-7cap" "$patched" "$CASE_DIR/bin"
  local err; err=$(cat "$TMP_ROOT/A-7cap.err" 2>/dev/null || echo "")
  if [ "$LAST_RC" -eq 0 ] && ! echo "$err" | grep -qi 'unbound variable' \
     && [ -f "$cap" ] && ! grep -q -- '--auto' "$cap"; then
    pass "A7: AUTO unset + set -u → no 'unbound variable', LAND_ARGS without --auto"
  else
    fail "A7: AUTO unset + set -u → no crash" "rc=$LAST_RC err=$err captured=$(cat "$cap" 2>/dev/null || echo missing)"
  fi
  unset WT_PATH ZSKILLS_AUDIT_DIR ZSKILLS_REPORTS_DIR PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
}

# Case A8: LP_SPRINT parser — well-formed (all allow-list keys present)
#   plus an UNKNOWN key. Block should WARN to stderr on unknown but
#   complete the dispatch normally (STATUS=merged → fulfilled.* written).
test_A8_unknown_key_warns_but_proceeds() {
  setup_case_a "8" "gnu"
  run_block_a "$CASE_DIR" "true" \
    "STATUS=merged" \
    "PR_URL=https://pr/8" \
    "PR_NUMBER=8" \
    "CI_STATUS=SUCCESS" \
    "MERGE_REQUESTED=true" \
    "MERGE_REASON=automerge" \
    "PR_STATE=MERGED" \
    "UNKNOWN_FUTURE_KEY=mystery"
  local ful="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.fix-issues.sprint.$SPRINT_ID"
  local err; err=$(cat "$TMP_ROOT/$LAST_TAG.err" 2>/dev/null || echo "")
  if [ "$LAST_RC" -eq 0 ] && [ -s "$ful" ] && echo "$err" | grep -q 'WARN.*unknown key.*UNKNOWN_FUTURE_KEY'; then
    pass "A8: unknown key → WARN to stderr + dispatch proceeds (fulfilled.* still written)"
  else
    fail "A8: unknown key → WARN to stderr + proceed" "rc=$LAST_RC fulfilled=$([ -e "$ful" ] && echo Y || echo N) stderr=$err"
  fi
  unset AUTO WT_PATH ZSKILLS_AUDIT_DIR ZSKILLS_REPORTS_DIR PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
}

# Case A9: missing STATUS key → block reaches the *) arm of the case
#   statement, logs "STATUS=unknown — sprint report PR left open" to
#   stderr, does NOT write fulfilled.*.
test_A9_missing_status_logs_left_open() {
  setup_case_a "9" "gnu"
  run_block_a "$CASE_DIR" "true" "PR_URL=https://pr/9"
  local ful="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.fix-issues.sprint.$SPRINT_ID"
  local err; err=$(cat "$TMP_ROOT/$LAST_TAG.err" 2>/dev/null || echo "")
  if [ "$LAST_RC" -eq 0 ] && [ ! -e "$ful" ] && echo "$err" | grep -q 'STATUS=unknown'; then
    pass "A9: missing STATUS → 'left open' diagnostic + no fulfilled.*"
  else
    fail "A9: missing STATUS" "rc=$LAST_RC fulfilled-exists=$([ -e "$ful" ] && echo Y || echo N) stderr=$err"
  fi
  unset AUTO WT_PATH ZSKILLS_AUDIT_DIR ZSKILLS_REPORTS_DIR PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
}

# ─────────────────────────────────────────────────────────────────────
# Block B — `### If no actionable issues found` SHIP branch
# Same shape as Block A but with the dirty-tracker outer condition,
# different SPRINT_LAND_ID namespace (fix-issues.sync.*), and a CLEANUP
# branch we also exercise.
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "=== Block B — no-actionable SHIP / CLEANUP branches ==="

setup_case_b() {
  local case_id="$1" status_dirty="$2"
  CASE_DIR="$TMP_ROOT/B-$case_id"
  mkdir -p "$CASE_DIR"
  local wt="$CASE_DIR/wt"
  local main="$CASE_DIR/main"
  mkdir -p "$wt" "$main/.zskills/tracking" "$main/.git"

  mkshim "$CASE_DIR" "$wt" "$main" "$status_dirty" "gnu" "feature/sync"

  export WT_PATH="$wt"
  export CLAUDE_PROJECT_DIR="$REPO_ROOT"
  export PIPELINE_ID="test-pipeline-B-$case_id"
  export SPRINT_ID="sprintB$case_id"
  export COMMIT_CO_AUTHOR=""
  export OPEN_COUNT="0"
}

run_block_b() {
  local case_dir="$1" auto_value="$2"; shift 2
  local -a result_args
  if [ $# -gt 0 ]; then result_args=("$@"); else result_args=(); fi
  local patched="$case_dir/block.sh"
  patch_block "$BLOCK_B" "$patched"

  export PREPARED_RESULT_FILE="$case_dir/result.txt"
  export PREPARED_BODY_FILE="$case_dir/body.txt"
  if [ "${#result_args[@]}" -gt 0 ]; then
    mk_result_file "$PREPARED_RESULT_FILE" "${result_args[@]}"
  else
    : > "$PREPARED_RESULT_FILE"
  fi

  if [ "$auto_value" = "unset" ]; then unset AUTO || true
  else export AUTO="$auto_value"
  fi
  run_block "B-$(basename "$case_dir")" "$patched" "$case_dir/bin"
}

# Case B1: SHIP branch — dirty tree, STATUS=merged, AUTO=true.
#   Expect requires.land-pr.fix-issues.sync.<id> AND fulfilled.* present.
test_B1_ship_merged_auto() {
  setup_case_b "1" "1"
  run_block_b "$CASE_DIR" "true" "STATUS=merged" "PR_URL=https://pr/B1"
  local req="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/requires.land-pr.fix-issues.sync.$SPRINT_ID"
  local ful="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.fix-issues.sync.$SPRINT_ID"
  if [ "$LAST_RC" -eq 0 ] && [ -s "$req" ] && [ -s "$ful" ]; then
    pass "B1: SHIP + STATUS=merged + AUTO=true → both markers (sync.* namespace)"
  else
    fail "B1: SHIP + STATUS=merged" "rc=$LAST_RC req=$([ -e "$req" ] && echo Y || echo N) ful=$([ -e "$ful" ] && echo Y || echo N) stderr=$(head "$TMP_ROOT/$LAST_TAG.err" 2>/dev/null)"
  fi
  unset AUTO WT_PATH PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR OPEN_COUNT PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
}

# Case B2: SHIP branch — STATUS=push-failed → fulfilled.* ABSENT,
#   stderr contains "sync PR left open" diagnostic.
test_B2_ship_push_failed_left_open() {
  setup_case_b "2" "1"
  run_block_b "$CASE_DIR" "true" "STATUS=push-failed"
  local ful="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.fix-issues.sync.$SPRINT_ID"
  local err; err=$(cat "$TMP_ROOT/$LAST_TAG.err" 2>/dev/null || echo "")
  if [ "$LAST_RC" -eq 0 ] && [ ! -e "$ful" ] && echo "$err" | grep -q 'sync PR left open'; then
    pass "B2: SHIP + STATUS=push-failed → no fulfilled.*, 'left open' diagnostic"
  else
    fail "B2: SHIP + STATUS=push-failed" "rc=$LAST_RC ful=$([ -e "$ful" ] && echo Y || echo N) err=$err"
  fi
  unset AUTO WT_PATH PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR OPEN_COUNT PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
}

# Case B3: AUTO unset + set -u (the actual secondary fix from #337).
#   Verifies the block does not crash with unbound-variable.
test_B3_ship_auto_unset_no_crash() {
  setup_case_b "3" "1"
  run_block_b "$CASE_DIR" "unset" "STATUS=merged"
  local err; err=$(cat "$TMP_ROOT/$LAST_TAG.err" 2>/dev/null || echo "")
  if [ "$LAST_RC" -eq 0 ] && ! echo "$err" | grep -qi 'unbound variable'; then
    pass "B3: SHIP + AUTO unset + set -u → no 'unbound variable' crash"
  else
    fail "B3: SHIP + AUTO unset + set -u" "rc=$LAST_RC err=$err"
  fi
  unset WT_PATH PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR OPEN_COUNT PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
}

# Case B4: CLEANUP branch — clean tree → no markers, git worktree
#   remove called. We assert by absence of markers AND presence of the
#   shim's '[fake-worktree-remove]' diagnostic in stderr.
test_B4_cleanup_clean_tree() {
  setup_case_b "4" "0" # status_dirty=0 → CLEANUP
  run_block_b "$CASE_DIR" "true"
  local req="$CASE_DIR/main/.zskills/tracking/$PIPELINE_ID/requires.land-pr.fix-issues.sync.$SPRINT_ID"
  local err; err=$(cat "$TMP_ROOT/$LAST_TAG.err" 2>/dev/null || echo "")
  if [ "$LAST_RC" -eq 0 ] && [ ! -e "$req" ] && echo "$err" | grep -q 'fake-worktree-remove'; then
    pass "B4: CLEANUP (clean tree) → no requires.* marker, git worktree remove invoked"
  else
    fail "B4: CLEANUP (clean tree)" "rc=$LAST_RC req=$([ -e "$req" ] && echo Y || echo N) err=$err"
  fi
  unset AUTO WT_PATH PIPELINE_ID SPRINT_ID COMMIT_CO_AUTHOR OPEN_COUNT PREPARED_RESULT_FILE PREPARED_BODY_FILE || true
}

# Case B5: marker write SEQUENCING. requires.* must exist BEFORE the
#   dispatch comment; fulfilled.* must NOT exist before the parser
#   block. We simulate by inspecting the patched block's line order
#   (since we can't time-stamp serially within the same script run
#   reliably from a fixture, we pin the *static* sequencing: the awk
#   line-number of `requires.land-pr` must precede `# Skill:` which
#   must precede `fulfilled.land-pr`). Static sequencing IS the
#   contract — runtime order follows directly from top-down bash.
test_B5_marker_sequencing_static() {
  local req_line ship_line ful_line
  req_line=$(grep -n 'requires.land-pr' "$BLOCK_B" | head -1 | cut -d: -f1)
  ship_line=$(grep -n '# Skill:.*land-pr' "$BLOCK_B" | head -1 | cut -d: -f1)
  ful_line=$(grep -n 'fulfilled.land-pr' "$BLOCK_B" | head -1 | cut -d: -f1)
  if [ -n "$req_line" ] && [ -n "$ship_line" ] && [ -n "$ful_line" ] \
     && [ "$req_line" -lt "$ship_line" ] && [ "$ship_line" -lt "$ful_line" ]; then
    pass "B5: static sequencing requires.* (L$req_line) < dispatch (L$ship_line) < fulfilled.* (L$ful_line)"
  else
    fail "B5: marker sequencing" "req=$req_line ship=$ship_line ful=$ful_line"
  fi
}

# Same static sequencing for Block A.
test_A_sequencing_static() {
  local req_line ship_line ful_line
  req_line=$(grep -n 'requires.land-pr' "$BLOCK_A" | head -1 | cut -d: -f1)
  ship_line=$(grep -n '# Skill:.*land-pr' "$BLOCK_A" | head -1 | cut -d: -f1)
  ful_line=$(grep -n 'fulfilled.land-pr' "$BLOCK_A" | head -1 | cut -d: -f1)
  if [ -n "$req_line" ] && [ -n "$ship_line" ] && [ -n "$ful_line" ] \
     && [ "$req_line" -lt "$ship_line" ] && [ "$ship_line" -lt "$ful_line" ]; then
    pass "A: static sequencing requires.* (L$req_line) < dispatch (L$ship_line) < fulfilled.* (L$ful_line)"
  else
    fail "A: marker sequencing" "req=$req_line ship=$ship_line ful=$ful_line"
  fi
}

# ─────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────
test_A_sequencing_static
test_A1_merged_auto_gnu
test_A2_merged_fallback_realpath
test_A3_created_no_fulfilled
test_A4_other_statuses_no_fulfilled
test_A5_auto_true_emits_flag
test_A6_auto_false_no_flag
test_A7_auto_unset_no_crash
test_A8_unknown_key_warns_but_proceeds
test_A9_missing_status_logs_left_open

test_B5_marker_sequencing_static
test_B1_ship_merged_auto
test_B2_ship_push_failed_left_open
test_B3_ship_auto_unset_no_crash
test_B4_cleanup_clean_tree

echo ""
echo "---"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
