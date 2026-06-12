#!/bin/bash
# tests/test-fix-issues-claim-script.sh — unit tests for the
# claim-issue.sh primitive (skills/fix-issues/scripts/claim-issue.sh).
#
# Covers W1.5 acceptance cases for plans/fix-issues-claims.md Phase 1:
#   - acquire on fresh slot succeeds (exit 0)
#   - second acquire on held slot exits 10 (EEXIST), preserves first
#     claim's claim.json byte-for-byte
#   - release on matching pipeline_id exits 0
#   - release on mismatched pipeline_id exits 12, leaves claim intact
#   - release on absent claim exits 0 (idempotent)
#   - is-stale: absent -> 2; live claim -> 1 (never stale by age; the
#     TTL-aging branch was removed in #739)
#   - is-stale: dir w/o claim.json mtime > 30s -> 0; mtime < 5s -> 1
#   - list output is parseable TSV (N, pipeline_id, age_seconds)
#   - concurrency: two parallel acquires for same N -> exactly one wins
#   - non-EEXIST -> exit 11 (EACCES via chmod 0500 on parent)
#   - atomic-write crash window: mkdir-success-then-write-failure ->
#     non-zero AND claim dir is rmdir'd (no stub leak)
#   - MAIN_ROOT resolution: cd'd to worktree -> claim lands in main root,
#     not in worktree. cd /tmp (no git) -> error, no /tmp/.zskills/ write.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/fix-issues/scripts/claim-issue.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Per-test scratch root. Cleaned up on exit unless TEST_KEEP_SCRATCH is set.
SCRATCH_ROOT="/tmp/test-fix-issues-claim-script-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
    echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT for inspection" >&2
    return
  fi
  if [ -d "$SCRATCH_ROOT" ]; then
    # Re-allow any chmod 0500 dirs we created during EACCES test.
    find "$SCRATCH_ROOT" -type d -exec chmod 0755 {} + 2>/dev/null || true
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

# Create a fresh fixture git repo and cd into it. Returns absolute path.
make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (cd "$repo" && git init -q && git config user.email "t@t" && git config user.name "t" \
    && git commit --allow-empty -q -m "init") || return 1
}

# Sanity: CLAIM_SH exists and is readable.
if [ ! -f "$CLAIM_SH" ]; then
  echo "FATAL: claim-issue.sh missing at $CLAIM_SH" >&2
  exit 1
fi

echo "=== claim-issue.sh unit tests ==="

# ───────────────────────────────────────────────────────────────────────
# Test 1: acquire on fresh slot succeeds.
# ───────────────────────────────────────────────────────────────────────
t1_root="$SCRATCH_ROOT/t1"
make_repo "$t1_root"
(
  cd "$t1_root" || exit 1
  out=$(bash "$CLAIM_SH" acquire 42 --pipeline-id pipe-A --sprint-id sprint-A 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL_REASON acquire returned $rc, out: $out"
    exit 1
  fi
  if [ ! -f "$t1_root/.zskills/claims/issue-42/claim.json" ]; then
    echo "FAIL_REASON claim.json not created"
    exit 1
  fi
  # Validate JSON schema.
  python3 -c "
import json, sys
b = json.load(open('$t1_root/.zskills/claims/issue-42/claim.json'))
assert b['schema_version'] == 1, b
assert b['pipeline_id'] == 'pipe-A', b
assert b['sprint_id'] == 'sprint-A', b
assert b['issue'] == 42, b
assert 'started_at' in b, b
assert 'worktree_path' not in b, b
assert 'host_pid' not in b, b
" || { echo "FAIL_REASON schema mismatch"; exit 1; }
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "acquire on fresh slot succeeds and writes correct claim.json schema"
else
  fail "acquire on fresh slot succeeds" "see FAIL_REASON above"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 2: second acquire on same slot exits 10, preserves first claim
# byte-for-byte.
# ───────────────────────────────────────────────────────────────────────
t2_root="$SCRATCH_ROOT/t2"
make_repo "$t2_root"
(
  cd "$t2_root" || exit 1
  bash "$CLAIM_SH" acquire 7 --pipeline-id pipe-A --sprint-id sprint-A >/dev/null
  first_hash=$(sha256sum "$t2_root/.zskills/claims/issue-7/claim.json" | awk '{print $1}')
  out=$(bash "$CLAIM_SH" acquire 7 --pipeline-id pipe-B --sprint-id sprint-B 2>&1)
  rc=$?
  if [ "$rc" -ne 10 ]; then
    echo "FAIL_REASON second acquire returned $rc, expected 10; out: $out"
    exit 1
  fi
  second_hash=$(sha256sum "$t2_root/.zskills/claims/issue-7/claim.json" | awk '{print $1}')
  if [ "$first_hash" != "$second_hash" ]; then
    echo "FAIL_REASON claim.json mutated by failed second acquire"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "second acquire on held slot exits 10, preserves claim.json byte-for-byte"
else
  fail "second acquire returns 10" "see FAIL_REASON above"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 3: release on matching pipeline_id exits 0.
# ───────────────────────────────────────────────────────────────────────
t3_root="$SCRATCH_ROOT/t3"
make_repo "$t3_root"
(
  cd "$t3_root" || exit 1
  bash "$CLAIM_SH" acquire 11 --pipeline-id pipe-A --sprint-id sprint-A >/dev/null
  out=$(bash "$CLAIM_SH" release 11 --require-pipeline pipe-A 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL_REASON release matched pipeline returned $rc, out: $out"
    exit 1
  fi
  if [ -d "$t3_root/.zskills/claims/issue-11" ]; then
    echo "FAIL_REASON claim dir still present after release"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "release on matching pipeline_id exits 0, removes claim"
else
  fail "release matching pipeline" "see FAIL_REASON above"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 4: release on mismatched pipeline_id exits 12, leaves claim intact.
# ───────────────────────────────────────────────────────────────────────
t4_root="$SCRATCH_ROOT/t4"
make_repo "$t4_root"
(
  cd "$t4_root" || exit 1
  bash "$CLAIM_SH" acquire 22 --pipeline-id pipe-A --sprint-id sprint-A >/dev/null
  before_hash=$(sha256sum "$t4_root/.zskills/claims/issue-22/claim.json" | awk '{print $1}')
  out=$(bash "$CLAIM_SH" release 22 --require-pipeline pipe-B 2>&1)
  rc=$?
  if [ "$rc" -ne 12 ]; then
    echo "FAIL_REASON release mismatched returned $rc, expected 12; out: $out"
    exit 1
  fi
  after_hash=$(sha256sum "$t4_root/.zskills/claims/issue-22/claim.json" 2>/dev/null | awk '{print $1}')
  if [ "$before_hash" != "$after_hash" ]; then
    echo "FAIL_REASON claim.json mutated/removed by refused release"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "release on mismatched pipeline_id exits 12, leaves claim intact"
else
  fail "release mismatched pipeline" "see FAIL_REASON above"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 5: release on absent claim is idempotent (exit 0).
# ───────────────────────────────────────────────────────────────────────
t5_root="$SCRATCH_ROOT/t5"
make_repo "$t5_root"
(
  cd "$t5_root" || exit 1
  out=$(bash "$CLAIM_SH" release 999 --require-pipeline pipe-A 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL_REASON release absent returned $rc, expected 0; out: $out"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "release on absent claim exits 0 (idempotent)"
else
  fail "release absent claim idempotent" "see FAIL_REASON above"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 6: is-stale — absent -> 2; a LIVE claim (claim.json present) is
# NEVER stale -> 1, regardless of age. The TTL-age branch was removed
# (#739, same precedent as #684 for plan claims); claims are released at
# land-or-abandon, not aged out. The crash-window (dir-without-json)
# branch is exercised by Test 7.
# ───────────────────────────────────────────────────────────────────────
t6_root="$SCRATCH_ROOT/t6"
make_repo "$t6_root"
(
  cd "$t6_root" || exit 1
  # Absent -> 2
  bash "$CLAIM_SH" is-stale 100
  rc=$?
  if [ "$rc" -ne 2 ]; then
    echo "FAIL_REASON absent is-stale returned $rc, expected 2"
    exit 1
  fi
  # Live claim, just acquired -> 1 (fresh)
  bash "$CLAIM_SH" acquire 100 --pipeline-id pipe-A --sprint-id sprint-A >/dev/null
  bash "$CLAIM_SH" is-stale 100
  rc=$?
  if [ "$rc" -ne 1 ]; then
    echo "FAIL_REASON fresh live claim is-stale returned $rc, expected 1"
    exit 1
  fi
  # Live claim aged 3h -> STILL 1 (no TTL aging — a live claim is never stale)
  python3 -c "
import json, datetime
p = '$t6_root/.zskills/claims/issue-100/claim.json'
with open(p) as f: b = json.load(f)
b['started_at'] = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=3)).isoformat(timespec='seconds')
with open(p, 'w') as f: json.dump(b, f, sort_keys=True)
"
  bash "$CLAIM_SH" is-stale 100
  rc=$?
  if [ "$rc" -ne 1 ]; then
    echo "FAIL_REASON aged-3h live claim is-stale returned $rc, expected 1 (TTL aging removed)"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "is-stale: absent -> 2, live claim -> 1 (never stale by age; TTL branch removed #739)"
else
  fail "is-stale semantics (no TTL)" "see FAIL_REASON above"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 7: is-stale crash window — dir exists, claim.json missing.
# mtime > 30s ago -> 0 (stale); mtime < 5s ago -> 1 (in-flight write).
# ───────────────────────────────────────────────────────────────────────
t7_root="$SCRATCH_ROOT/t7"
make_repo "$t7_root"
(
  cd "$t7_root" || exit 1
  # Fresh dir, no claim.json -> in-flight window -> 1
  mkdir -p "$t7_root/.zskills/claims/issue-101"
  bash "$CLAIM_SH" is-stale 101
  rc=$?
  if [ "$rc" -ne 1 ]; then
    echo "FAIL_REASON in-flight dir is-stale returned $rc, expected 1"
    exit 1
  fi
  # Now set mtime to 60s ago — should be stale.
  touch -d "60 seconds ago" "$t7_root/.zskills/claims/issue-101"
  bash "$CLAIM_SH" is-stale 101
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL_REASON aged stub dir is-stale returned $rc, expected 0"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "is-stale crash-window: <5s old stub dir = fresh; >30s old stub dir = stale"
else
  fail "is-stale crash-window" "see FAIL_REASON above"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 9: list output is parseable TSV.
# ───────────────────────────────────────────────────────────────────────
t9_root="$SCRATCH_ROOT/t9"
make_repo "$t9_root"
(
  cd "$t9_root" || exit 1
  bash "$CLAIM_SH" acquire 301 --pipeline-id pipe-A --sprint-id sprint-A >/dev/null
  bash "$CLAIM_SH" acquire 302 --pipeline-id pipe-B --sprint-id sprint-B >/dev/null
  out=$(bash "$CLAIM_SH" list 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL_REASON list returned $rc, out: $out"
    exit 1
  fi
  line_count=$(printf '%s\n' "$out" | grep -c '^[0-9]')
  if [ "$line_count" -ne 2 ]; then
    echo "FAIL_REASON list emitted $line_count lines, expected 2; out: $out"
    exit 1
  fi
  # Each line: <N>\t<pipeline_id>\t<age>. 3 tab-separated fields.
  while IFS=$'\t' read -r n pid age; do
    case "$n" in
      ''|*[!0-9]*) echo "FAIL_REASON list field N malformed: '$n'"; exit 1 ;;
    esac
    case "$age" in
      ''|*[!0-9]*) echo "FAIL_REASON list field age malformed: '$age'"; exit 1 ;;
    esac
    if [ -z "$pid" ]; then
      echo "FAIL_REASON list field pipeline_id empty"; exit 1
    fi
    # No 4th column (no worktree_path per DA8).
    extra_fields=$(printf '%s\n' "$out" | head -1 | awk -F'\t' '{print NF}')
    if [ "$extra_fields" -ne 3 ]; then
      echo "FAIL_REASON list emitted $extra_fields columns, expected 3"; exit 1
    fi
  done <<< "$out"
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "list emits parseable TSV: <N>\\t<pipeline_id>\\t<age_seconds>, 3 columns, no worktree column"
else
  fail "list TSV format" "see FAIL_REASON above"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 10: concurrency — two parallel acquires for same N. Exactly one
# exits 0, the other exits 10. Winner's pipeline persists in claim.json.
# ───────────────────────────────────────────────────────────────────────
t10_root="$SCRATCH_ROOT/t10"
make_repo "$t10_root"
(
  cd "$t10_root" || exit 1
  # Fire two acquires in background. Capture exit codes to files.
  ec_a="$SCRATCH_ROOT/t10-ec-A"
  ec_b="$SCRATCH_ROOT/t10-ec-B"
  ( bash "$CLAIM_SH" acquire 500 --pipeline-id pipe-A --sprint-id sprint-A >/dev/null 2>&1; echo $? > "$ec_a" ) &
  ( bash "$CLAIM_SH" acquire 500 --pipeline-id pipe-B --sprint-id sprint-B >/dev/null 2>&1; echo $? > "$ec_b" ) &
  wait

  rc_a=$(cat "$ec_a")
  rc_b=$(cat "$ec_b")
  # Exactly one is 0 and the other is 10.
  if ! { { [ "$rc_a" = "0" ] && [ "$rc_b" = "10" ]; } || { [ "$rc_a" = "10" ] && [ "$rc_b" = "0" ]; }; }; then
    echo "FAIL_REASON concurrent acquires: rc_a=$rc_a rc_b=$rc_b (expected one 0 + one 10)"
    exit 1
  fi
  # Winner's pipeline persists.
  if [ "$rc_a" = "0" ]; then winner="pipe-A"; else winner="pipe-B"; fi
  actual=$(python3 -c "import json; print(json.load(open('$t10_root/.zskills/claims/issue-500/claim.json')).get('pipeline_id',''))")
  if [ "$actual" != "$winner" ]; then
    echo "FAIL_REASON winner pipeline mismatch: expected=$winner actual=$actual"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "concurrent acquires: exactly one wins (exit 0), other gets exit 10, winner's metadata persists"
else
  fail "concurrency" "see FAIL_REASON above"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 11: non-EEXIST mkdir failure (EACCES) -> exit 11, NOT 10.
# Force EACCES by chmod 0500 on parent .zskills/claims/ AFTER its creation.
# ───────────────────────────────────────────────────────────────────────
t11_root="$SCRATCH_ROOT/t11"
make_repo "$t11_root"
(
  cd "$t11_root" || exit 1
  # Run as non-root only (root bypasses chmod 0500).
  if [ "$(id -u)" -eq 0 ]; then
    echo "SKIP_REASON running as root — chmod 0500 has no effect"
    exit 0
  fi
  mkdir -p "$t11_root/.zskills/claims"
  chmod 0500 "$t11_root/.zskills/claims"
  out=$(bash "$CLAIM_SH" acquire 600 --pipeline-id pipe-X --sprint-id sprint-X 2>&1)
  rc=$?
  chmod 0755 "$t11_root/.zskills/claims"  # restore for cleanup
  if [ "$rc" -ne 11 ]; then
    echo "FAIL_REASON EACCES acquire returned $rc, expected 11; out: $out"
    exit 1
  fi
  if [ -d "$t11_root/.zskills/claims/issue-600" ]; then
    echo "FAIL_REASON claim dir created despite EACCES"
    exit 1
  fi
  exit 0
)
case "$?" in
  0)
    pass "non-EEXIST mkdir failure (EACCES) returns exit 11, not 10"
    ;;
  *)
    fail "EACCES -> exit 11" "see FAIL_REASON above"
    ;;
esac

# ───────────────────────────────────────────────────────────────────────
# Test 12: atomic-write crash window. Simulate mkdir-success-then-write-
# failure by chmod 0500 on the issue subdir after mkdir. Acquire returns
# non-zero AND the claim dir is rmdir'd (no stub leak).
#
# We use a wrapper-mkdir shim on PATH: it does the real mkdir, then if
# the dir name matches issue-700, chmods it to 0500 before returning.
# This is more reliable than racing the script.
# ───────────────────────────────────────────────────────────────────────
t12_root="$SCRATCH_ROOT/t12"
make_repo "$t12_root"
(
  cd "$t12_root" || exit 1
  if [ "$(id -u)" -eq 0 ]; then
    echo "SKIP_REASON running as root — chmod 0500 has no effect"
    exit 0
  fi

  # Shim dir with a custom 'mkdir' that triggers the crash window.
  shim_dir="$SCRATCH_ROOT/t12-shim"
  mkdir -p "$shim_dir"
  cat > "$shim_dir/mkdir" <<'SHIM'
#!/bin/bash
# Pass-through wrapper around real mkdir. After creating the target,
# if any argument matches issue-700 (i.e. the claim dir), chmod it to
# 0500 to force the subsequent claim.json write to fail.
real_mkdir=$(command -v mkdir | grep -v "$0" | head -1)
"$real_mkdir" "$@"
rc=$?
for a in "$@"; do
  case "$a" in
    *issue-700) "${real_mkdir%/mkdir}/chmod" 0500 "$a" 2>/dev/null ;;
  esac
done
exit $rc
SHIM
  # The wrapper needs real mkdir lookup. Use /usr/bin/mkdir directly to
  # keep this robust; replace the shim content.
  cat > "$shim_dir/mkdir" <<SHIM
#!/bin/bash
/usr/bin/mkdir "\$@"
rc=\$?
for a in "\$@"; do
  case "\$a" in
    *issue-700) /usr/bin/chmod 0500 "\$a" 2>/dev/null ;;
  esac
done
exit \$rc
SHIM
  chmod +x "$shim_dir/mkdir"

  out=$(PATH="$shim_dir:$PATH" bash "$CLAIM_SH" acquire 700 --pipeline-id pipe-X --sprint-id sprint-X 2>&1)
  rc=$?
  # The dir is now 0500; restore for cleanup checks.
  [ -d "$t12_root/.zskills/claims/issue-700" ] && chmod 0755 "$t12_root/.zskills/claims/issue-700" 2>/dev/null

  if [ "$rc" -eq 0 ]; then
    echo "FAIL_REASON crash-window acquire returned 0, expected non-zero; out: $out"
    exit 1
  fi
  # Stub leak check: claim dir should be rmdir'd.
  if [ -d "$t12_root/.zskills/claims/issue-700" ]; then
    echo "FAIL_REASON stub leak: claim dir not rmdir'd after atomic-write failure"
    exit 1
  fi
  exit 0
)
case "$?" in
  0)
    pass "atomic-write crash window: mkdir succeeds but write fails -> non-zero exit + no stub leak"
    ;;
  *)
    fail "atomic-write crash window" "see FAIL_REASON above"
    ;;
esac

# ───────────────────────────────────────────────────────────────────────
# Test 13: MAIN_ROOT resolution (DA4.1 — round 4b).
# (a) cd into a sprint worktree; claim lands in MAIN_ROOT/.zskills/claims/
#     NOT in the worktree's .zskills/claims/.
# (b) cd into a non-git dir (/tmp via empty SCRATCH dir); script errors,
#     does NOT write under cwd.
# ───────────────────────────────────────────────────────────────────────
t13_root="$SCRATCH_ROOT/t13-main"
make_repo "$t13_root"
t13_wt="$SCRATCH_ROOT/t13-sprint-wt"
(
  cd "$t13_root" && git worktree add -q "$t13_wt" -b "feat/fixture-sprint" 2>/dev/null
)
if [ ! -d "$t13_wt" ]; then
  fail "MAIN_ROOT resolution: worktree fixture setup failed"
else
(
  cd "$t13_wt" || exit 1
  out=$(bash "$CLAIM_SH" acquire 42 --pipeline-id pipe-A --sprint-id sprint-A 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL_REASON acquire from worktree returned $rc, out: $out"
    exit 1
  fi
  # Claim must land in main root, not worktree.
  if [ ! -d "$t13_root/.zskills/claims/issue-42" ]; then
    echo "FAIL_REASON claim not in main root: $t13_root/.zskills/claims/issue-42"
    exit 1
  fi
  if [ -d "$t13_wt/.zskills/claims/issue-42" ]; then
    echo "FAIL_REASON claim wrongly placed in worktree: $t13_wt/.zskills/claims/issue-42"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "MAIN_ROOT resolution: cd'd into worktree -> claim lands in main root, not in worktree"
else
  fail "MAIN_ROOT resolution from worktree" "see FAIL_REASON above"
fi

# Cleanup worktree before scratch dir teardown.
(cd "$t13_root" && git worktree remove --force "$t13_wt" 2>/dev/null)
fi

# (b) Non-git directory -> error, no silent /tmp/.zskills/ write.
t13_nogit="$SCRATCH_ROOT/t13-nogit"
mkdir -p "$t13_nogit"
(
  cd "$t13_nogit" || exit 1
  out=$(bash "$CLAIM_SH" acquire 42 --pipeline-id pipe-X --sprint-id sprint-X 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "FAIL_REASON acquire from non-git dir returned 0, expected non-zero; out: $out"
    exit 1
  fi
  if ! echo "$out" | grep -q "cannot resolve MAIN_ROOT"; then
    echo "FAIL_REASON missing 'cannot resolve MAIN_ROOT' stderr; got: $out"
    exit 1
  fi
  if [ -d "$t13_nogit/.zskills/claims" ]; then
    echo "FAIL_REASON silent fallback wrote .zskills/claims/ in non-git cwd"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "MAIN_ROOT resolution: non-git cwd -> error stderr, no silent \$PWD/.zskills/ fallback"
else
  fail "MAIN_ROOT resolution from non-git dir" "see FAIL_REASON above"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 14: Arg-spelling alias (#1164) — --pipeline-id and
# --require-pipeline are interchangeable on BOTH acquire AND release.
#   14a. acquire accepts --require-pipeline (the release spelling).
#   14b. release accepts --pipeline-id (the acquire spelling) and matches.
#   14c. mismatched value via the alias spelling is still refused (12).
# ───────────────────────────────────────────────────────────────────────
t14_root="$SCRATCH_ROOT/t14"
make_repo "$t14_root"
(
  cd "$t14_root" || exit 1
  # 14a: acquire with --require-pipeline alias.
  out=$(bash "$CLAIM_SH" acquire 800 --require-pipeline pipe-A --sprint-id sprint-A 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL_REASON acquire --require-pipeline alias returned $rc, out: $out"
    exit 1
  fi
  cf="$t14_root/.zskills/claims/issue-800/claim.json"
  if [ ! -f "$cf" ]; then
    echo "FAIL_REASON claim.json not written after --require-pipeline acquire"
    exit 1
  fi
  pipe=$("${ZSKILLS_PYTHON:-python3}" -c "import json; print(json.load(open('$cf'))['pipeline_id'])")
  if [ "$pipe" != "pipe-A" ]; then
    echo "FAIL_REASON pipeline_id=$pipe, expected pipe-A"
    exit 1
  fi
  # 14b: release with --pipeline-id alias, matching value -> rc 0, removed.
  out=$(bash "$CLAIM_SH" release 800 --pipeline-id pipe-A 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || [ -d "$t14_root/.zskills/claims/issue-800" ]; then
    echo "FAIL_REASON release --pipeline-id alias rc=$rc, dir still present? $([ -d "$t14_root/.zskills/claims/issue-800" ] && echo yes || echo no); out: $out"
    exit 1
  fi
  # 14c: mismatched value via alias spelling -> still refused (12), intact.
  bash "$CLAIM_SH" acquire 801 --pipeline-id pipe-A --sprint-id sprint-A >/dev/null
  out=$(bash "$CLAIM_SH" release 801 --pipeline-id pipe-WRONG 2>&1)
  rc=$?
  if [ "$rc" -ne 12 ] || [ ! -d "$t14_root/.zskills/claims/issue-801" ]; then
    echo "FAIL_REASON mismatch via alias rc=$rc (expected 12), dir present? $([ -d "$t14_root/.zskills/claims/issue-801" ] && echo yes || echo no); out: $out"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "arg-spelling alias: --pipeline-id/--require-pipeline interchangeable on acquire+release; mismatch still refused (#1164)"
else
  fail "arg-spelling alias (#1164)" "see FAIL_REASON above"
fi

# ───────────────────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
