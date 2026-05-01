#!/bin/bash
# Tests for /update-zskills Step D.5 — Migrate stale Tier-1 scripts.
#
# /update-zskills is an agent-executed command. We cannot literally invoke
# the skill from a shell test. Instead, we encode the algorithm documented
# in `skills/update-zskills/SKILL.md` "Step D.5" as a bash function below
# (`run_step_d5`) and run it against fixture directories. The function is
# an executable oracle — if SKILL.md's spec changes meaning, the oracle
# must be updated in lockstep.
#
# Coverage (matches Phase 4 WI 4.8 exactly):
#   1.  Consumer scripts/create-worktree.sh hashes match a known
#       zskills version (LF endings) → MIGRATED; after `y`, file removed.
#   2.  Consumer scripts/create-worktree.sh modified by user → KEPT;
#       file preserved.
#   2b. Cross-platform CRLF fixture (D25 fix) — same shipped content as
#       case 1 but with CRLF endings on disk; migration's
#       `tr -d '\r' | git hash-object --stdin` MUST produce LF-equivalent
#       hash and classify the fixture as MIGRATED.
#   2c. New Tier-1 scripts (port.sh, clear-tracking.sh, statusline.sh,
#       plan-drift-correct.sh) hash-matched → MIGRATED.
#   2d. New Tier-1 scripts (same set as 2c) user-modified → KEPT.
#   2e. Git-missing pre-flight (DA-8 fix) — Step D.5 in a shell where
#       `git` is not on PATH; pre-flight guard must skip with the
#       exact stderr message and return 0.
#   3.  Consumer scripts/foo.sh not in STALE_LIST → ignored (does not
#       appear in either list).
#   4.  $KNOWN_HASHES file missing → every existing Tier-1 file is KEPT
#       (defensive default — never remove without verification).
#   5.  User answers `n` to the prompt → file preserved; report says
#       "Kept. To migrate later, re-run /update-zskills."
#   6.  STALE_LIST drift + hash-file format + commit-cohabitation:
#         6a. Parse Tier-1 names from script-ownership.md AND the
#             STALE_LIST array in SKILL.md; sort and diff.
#         6b. Every line in tier1-shipped-hashes.txt is a 40-char
#             lowercase hex sha; no blanks.
#         6c. Commit-cohabitation — when a Tier-1 script changes, the
#             hash file must change in the same commit (or later).
#             Owner-literal pathspec from script-ownership.md column 4
#             (DA-10 fix). Skip with warning on shallow clones.
#
# Per CLAUDE.md test-output idiom, this script writes scratch fixtures
# to /tmp/zskills-tests/$(basename "$REPO_ROOT")/migration-fixture-* so
# they never appear in `git status` of the worktree.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")"
mkdir -p "$TEST_OUT"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT+1)); }

# --- Oracle: Step D.5 migration -------------------------------------------
# Args:
#   $1 = consumer dir (contains scripts/, .claude/zskills-config.json,
#        possibly .zskills/tier1-migration-deferred)
#   $2 = path to known-hashes file (or /dev/null to simulate missing)
#   $3 = answer to interactive prompt: "y" or "n"
#
# Stdout: the human-readable report (Found ..., - <name>, removed ...,
#         Kept ..., WARNING ..., - <name>).
# Stderr: any error messages.
# Return: 0 on success, non-zero on hard error (e.g., rm fails).
#
# Encodes the SKILL.md Step D.5 algorithm verbatim. STALE_LIST mirrors
# the array in SKILL.md (kept in sync via test case 6a).
run_step_d5() {
  local dir="$1" known_hashes="$2" ans="$3"
  local target consumer_hash name d skip
  local DEFER_MARKER="$dir/.zskills/tier1-migration-deferred"

  # Pre-flight (DA-8 fix). Match the SKILL.md guard exactly.
  if ! command -v git >/dev/null 2>&1; then
    echo "Step D.5 requires git on PATH; skipping stale-Tier-1 migration" >&2
    return 0
  fi

  local STALE_LIST=(
    apply-preset.sh
    briefing.cjs
    briefing.py
    clear-tracking.sh
    compute-cron-fire.sh
    create-worktree.sh
    land-phase.sh
    plan-drift-correct.sh
    port.sh
    post-run-invariants.sh
    sanitize-pipeline-id.sh
    statusline.sh
    worktree-add-safe.sh
    write-landed.sh
  )

  local MIGRATED=() KEPT=()
  for name in "${STALE_LIST[@]}"; do
    target="$dir/scripts/$name"
    [ -f "$target" ] || continue

    consumer_hash=$(tr -d '\r' < "$target" | git hash-object --stdin)

    if [ -f "$known_hashes" ] && grep -qxF "$consumer_hash" "$known_hashes"; then
      MIGRATED+=("$name")
    else
      KEPT+=("$name")
    fi
  done

  if [ "${#MIGRATED[@]}" -gt 0 ]; then
    echo "Found ${#MIGRATED[@]} stale Tier-1 script(s) at scripts/ that"
    echo "match a known zskills version. These now ship via skill mirrors."
    printf '  - %s\n' "${MIGRATED[@]}"
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
      for name in "${MIGRATED[@]}"; do
        rm -- "$dir/scripts/$name" \
          && echo "removed scripts/$name" \
          || { echo "ERROR: rm scripts/$name failed" >&2; return 1; }
      done
    else
      echo "Kept. To migrate later, re-run /update-zskills."
    fi
  fi

  local DEFERRED_NAMES=()
  if [ -f "$DEFER_MARKER" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && DEFERRED_NAMES+=("$line")
    done < "$DEFER_MARKER"
  fi

  local KEPT_NEW=()
  for name in "${KEPT[@]}"; do
    skip=0
    for d in "${DEFERRED_NAMES[@]}"; do
      [ "$name" = "$d" ] && skip=1 && break
    done
    [ "$skip" -eq 0 ] && KEPT_NEW+=("$name")
  done

  if [ "${#KEPT_NEW[@]}" -gt 0 ]; then
    echo "WARNING: ${#KEPT_NEW[@]} Tier-1 script(s) at scripts/ do NOT match"
    echo "any known zskills version (likely user-modified). NOT removing."
    printf '  - %s\n' "${KEPT_NEW[@]}"
  fi

  return 0
}

# --- Helpers ---------------------------------------------------------------

# Build a fresh fixture dir with `scripts/` and `.claude/`.
make_fixture() {
  local label="$1"
  local fixture="$TEST_OUT/migration-fixture-$label-$$"
  rm -rf -- "$fixture"
  mkdir -p "$fixture/scripts" "$fixture/.claude" "$fixture/.zskills"
  echo "$fixture"
}

# Write a file whose `git hash-object` SHA matches the FIRST line of
# tier1-shipped-hashes.txt (a known shipped hash). The blob content
# is read from `git cat-file blob <hash>` against the source repo.
# Output: writes the blob bytes to $1.
write_known_blob() {
  local out="$1" hash="$2"
  git -C "$REPO_ROOT" cat-file blob "$hash" > "$out"
}

# --- Test cases ------------------------------------------------------------

KNOWN_HASHES="$REPO_ROOT/skills/update-zskills/references/tier1-shipped-hashes.txt"

# Pick the first known shipped hash for create-worktree.sh.
# We iterate the known-hashes file and pick one whose blob ends with the
# create-worktree.sh canonical signature (#!/bin/bash + filename).
find_blob_for() {
  local script_name="$1" hash blob
  while IFS= read -r hash; do
    blob=$(git -C "$REPO_ROOT" cat-file blob "$hash" 2>/dev/null || true)
    if echo "$blob" | head -1 | grep -qF '#!/bin/bash' \
       && echo "$blob" | grep -qF "$script_name"; then
      echo "$hash"
      return 0
    fi
  done < "$KNOWN_HASHES"
  return 1
}

# Find a blob from tier1-shipped-hashes.txt whose content references the
# given Tier-1 script name (used to populate fixtures). Falls back to
# the first hash in the file if no obvious match (last-resort).
pick_known_hash_for() {
  local name="$1" h
  h=$(find_blob_for "$name" || true)
  if [ -z "$h" ]; then
    h=$(head -1 "$KNOWN_HASHES")
  fi
  echo "$h"
}

# Case 1: create-worktree.sh matches → MIGRATED + removed on `y`.
test_case_1_match_lf() {
  local label="case1"
  local fixture; fixture=$(make_fixture "$label")
  local h; h=$(pick_known_hash_for "create-worktree.sh")
  write_known_blob "$fixture/scripts/create-worktree.sh" "$h"

  local out
  out=$(run_step_d5 "$fixture" "$KNOWN_HASHES" "y" 2>&1)

  if echo "$out" | grep -qF "  - create-worktree.sh" \
     && echo "$out" | grep -qF "removed scripts/create-worktree.sh" \
     && [ ! -f "$fixture/scripts/create-worktree.sh" ]; then
    pass "case 1: known LF blob → MIGRATED and removed"
  else
    fail "case 1: known LF blob → MIGRATED and removed" "out=$out"
  fi
  rm -rf -- "$fixture"
}

# Case 2: user-modified create-worktree.sh → KEPT.
test_case_2_user_modified() {
  local label="case2"
  local fixture; fixture=$(make_fixture "$label")
  printf '#!/bin/bash\n# user-modified create-worktree.sh\necho hello %s\n' "$$" \
    > "$fixture/scripts/create-worktree.sh"

  local out
  out=$(run_step_d5 "$fixture" "$KNOWN_HASHES" "n" 2>&1)

  if echo "$out" | grep -qF "WARNING:" \
     && echo "$out" | grep -qF "  - create-worktree.sh" \
     && [ -f "$fixture/scripts/create-worktree.sh" ]; then
    pass "case 2: user-modified → KEPT and preserved"
  else
    fail "case 2: user-modified → KEPT and preserved" "out=$out"
  fi
  rm -rf -- "$fixture"
}

# Case 2b: same shipped content as case 1, but CRLF endings on disk →
# `tr -d '\r' | git hash-object --stdin` MUST yield the LF hash → MIGRATED.
test_case_2b_crlf_normalize() {
  local label="case2b"
  local fixture; fixture=$(make_fixture "$label")
  local h; h=$(pick_known_hash_for "create-worktree.sh")
  local lf="$fixture/scripts/create-worktree.sh.lf"
  write_known_blob "$lf" "$h"
  # Convert LF → CRLF in place (use sed -E 's/$/\r/' equivalent via awk).
  awk 'BEGIN{ORS="\r\n"} {print}' "$lf" > "$fixture/scripts/create-worktree.sh"
  rm -- "$lf"

  # Sanity: file truly has CRLF.
  if ! grep -qU $'\r' "$fixture/scripts/create-worktree.sh"; then
    fail "case 2b: fixture lacks CRLF (test bug)" "no \\r in fixture"
    rm -rf -- "$fixture"
    return
  fi

  local out
  out=$(run_step_d5 "$fixture" "$KNOWN_HASHES" "y" 2>&1)

  if echo "$out" | grep -qF "  - create-worktree.sh" \
     && echo "$out" | grep -qF "removed scripts/create-worktree.sh" \
     && [ ! -f "$fixture/scripts/create-worktree.sh" ]; then
    pass "case 2b: CRLF fixture → MIGRATED (CRLF → LF normalize)"
  else
    fail "case 2b: CRLF fixture → MIGRATED" "out=$out"
  fi
  rm -rf -- "$fixture"
}

# Case 2c: four newly-Tier-1 scripts (port.sh, clear-tracking.sh,
# statusline.sh, plan-drift-correct.sh) — each populated with a known
# shipped hash → all MIGRATED + removed on `y`.
test_case_2c_new_tier1_match() {
  local label="case2c"
  local fixture; fixture=$(make_fixture "$label")
  local names=(port.sh clear-tracking.sh statusline.sh plan-drift-correct.sh)
  local n h
  for n in "${names[@]}"; do
    h=$(pick_known_hash_for "$n")
    write_known_blob "$fixture/scripts/$n" "$h"
  done

  local out
  out=$(run_step_d5 "$fixture" "$KNOWN_HASHES" "y" 2>&1)

  local all_ok=1
  for n in "${names[@]}"; do
    if ! echo "$out" | grep -qF "removed scripts/$n"; then all_ok=0; break; fi
    if [ -f "$fixture/scripts/$n" ]; then all_ok=0; break; fi
  done

  if [ "$all_ok" -eq 1 ]; then
    pass "case 2c: 4 new-Tier-1 known blobs → all MIGRATED + removed"
  else
    fail "case 2c: 4 new-Tier-1 known blobs → all MIGRATED" "out=$out"
  fi
  rm -rf -- "$fixture"
}

# Case 2d: same four new-Tier-1 names, all user-modified → all KEPT.
test_case_2d_new_tier1_kept() {
  local label="case2d"
  local fixture; fixture=$(make_fixture "$label")
  local names=(port.sh clear-tracking.sh statusline.sh plan-drift-correct.sh)
  local n
  for n in "${names[@]}"; do
    printf '#!/bin/bash\n# user-modified %s\necho %s %s\n' "$n" "$n" "$$" \
      > "$fixture/scripts/$n"
  done

  local out
  out=$(run_step_d5 "$fixture" "$KNOWN_HASHES" "n" 2>&1)

  local all_kept=1
  for n in "${names[@]}"; do
    if ! echo "$out" | grep -qF "  - $n"; then all_kept=0; break; fi
    if [ ! -f "$fixture/scripts/$n" ]; then all_kept=0; break; fi
  done

  if [ "$all_kept" -eq 1 ] && echo "$out" | grep -qF "WARNING:"; then
    pass "case 2d: 4 new-Tier-1 user-modified → all KEPT + preserved"
  else
    fail "case 2d: 4 new-Tier-1 user-modified → all KEPT" "out=$out"
  fi
  rm -rf -- "$fixture"
}

# Case 2e: git missing on PATH → pre-flight guard skips, returns 0.
test_case_2e_git_missing() {
  local label="case2e"
  local fixture; fixture=$(make_fixture "$label")

  # Run run_step_d5 in a subshell with git removed from PATH.
  # Use an empty PATH so `command -v git` fails. The outer shell-launcher
  # is invoked via absolute path (/usr/bin/bash) so the empty PATH does
  # not break the launch itself. `env -i` clears all inherited env to
  # ensure no fallback PATH leaks in.
  local out rc
  set +e
  out=$(env -i PATH=/empty-no-git /usr/bin/bash -c "
    $(declare -f run_step_d5)
    run_step_d5 '$fixture' '$KNOWN_HASHES' 'n'
  " 2>&1)
  rc=$?
  set -e

  if [ "$rc" -eq 0 ] \
     && echo "$out" | grep -qF "Step D.5 requires git on PATH; skipping stale-Tier-1 migration"; then
    pass "case 2e: git missing → pre-flight skip + rc=0"
  else
    fail "case 2e: git missing → pre-flight skip" "rc=$rc out=$out"
  fi
  rm -rf -- "$fixture"
}

# Case 3: scripts/foo.sh (not in STALE_LIST) → ignored.
test_case_3_not_in_stale_list() {
  local label="case3"
  local fixture; fixture=$(make_fixture "$label")
  printf '#!/bin/bash\necho ignore me\n' > "$fixture/scripts/foo.sh"

  local out
  out=$(run_step_d5 "$fixture" "$KNOWN_HASHES" "n" 2>&1)

  if ! echo "$out" | grep -qF "foo.sh" \
     && [ -f "$fixture/scripts/foo.sh" ]; then
    pass "case 3: non-STALE_LIST file → ignored"
  else
    fail "case 3: non-STALE_LIST file → ignored" "out=$out"
  fi
  rm -rf -- "$fixture"
}

# Case 4: missing $KNOWN_HASHES → every existing Tier-1 file KEPT.
test_case_4_missing_hashes_file() {
  local label="case4"
  local fixture; fixture=$(make_fixture "$label")
  printf '#!/bin/bash\necho any\n' > "$fixture/scripts/create-worktree.sh"

  local out
  out=$(run_step_d5 "$fixture" "/nonexistent/hashes.txt" "n" 2>&1)

  if echo "$out" | grep -qF "WARNING:" \
     && echo "$out" | grep -qF "  - create-worktree.sh" \
     && [ -f "$fixture/scripts/create-worktree.sh" ]; then
    pass "case 4: \$KNOWN_HASHES missing → defensive KEPT"
  else
    fail "case 4: \$KNOWN_HASHES missing → defensive KEPT" "out=$out"
  fi
  rm -rf -- "$fixture"
}

# Case 5: known blob, user answers `n` → file preserved, "Kept" report.
test_case_5_user_says_no() {
  local label="case5"
  local fixture; fixture=$(make_fixture "$label")
  local h; h=$(pick_known_hash_for "create-worktree.sh")
  write_known_blob "$fixture/scripts/create-worktree.sh" "$h"

  local out
  out=$(run_step_d5 "$fixture" "$KNOWN_HASHES" "n" 2>&1)

  if echo "$out" | grep -qF "Kept. To migrate later, re-run /update-zskills." \
     && [ -f "$fixture/scripts/create-worktree.sh" ]; then
    pass "case 5: user answers n → preserved + 'Kept' report"
  else
    fail "case 5: user answers n → preserved" "out=$out"
  fi
  rm -rf -- "$fixture"
}

# Case 6a: STALE_LIST drift — parse Tier-1 names from script-ownership.md
# AND from the STALE_LIST array in SKILL.md; sort and diff.
test_case_6a_stale_list_drift() {
  local doc="$REPO_ROOT/skills/update-zskills/references/script-ownership.md"
  local skill="$REPO_ROOT/skills/update-zskills/SKILL.md"

  local tier1_from_doc tier1_from_list
  tier1_from_doc=$(awk -F'|' '$3 ~ /^[[:space:]]*1[[:space:]]*$/ {
    gsub(/[[:space:]`]/, "", $2); print $2
  }' "$doc" | sort)

  tier1_from_list=$(awk '
    /^STALE_LIST=\(/ { f=1; next }
    /^\)/ { f=0 }
    f { gsub(/[[:space:]]/, ""); print }
  ' "$skill" | sort)

  if diff <(echo "$tier1_from_doc") <(echo "$tier1_from_list") >/dev/null; then
    pass "case 6a: STALE_LIST in sync with script-ownership.md"
  else
    fail "case 6a: STALE_LIST out of sync" \
      "$(diff <(echo "$tier1_from_doc") <(echo "$tier1_from_list"))"
  fi
}

# Case 6b: every line in tier1-shipped-hashes.txt is a 40-char hex sha.
test_case_6b_hash_format() {
  local f="$REPO_ROOT/skills/update-zskills/references/tier1-shipped-hashes.txt"
  if [ ! -f "$f" ]; then
    fail "case 6b: hash file present" "$f missing"
    return
  fi
  local bad
  bad=$(grep -v '^[a-f0-9]\{40\}$' "$f" || true)
  if [ -z "$bad" ]; then
    pass "case 6b: tier1-shipped-hashes.txt is all 40-char hex"
  else
    fail "case 6b: hash file format" "bad lines: $bad"
  fi
}

# Case 6c: commit-cohabitation — when a Tier-1 script changes, the hash
# file must change in the same commit (or later). Owner-literal pathspec
# from script-ownership.md column 4 (DA-10 fix). Requires full git
# history (fetch-depth: 0 in CI; non-shallow locally).
#
# Past failure (2026-04-30 → 2026-05-01): this test previously called
# `pass "shallow clone — skipped (warning)"` on shallow clones, making
# it invisible in CI and silently masking ~24h of accumulated Tier-1
# drift across PRs #128, #131, #135-#142. The skip-as-pass anti-pattern
# is corrected here: shallow now FAILs loudly.
test_case_6c_commit_cohabitation() {
  if [ "$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository)" = "true" ]; then
    fail "case 6c: shallow clone" "this test requires full git history (set fetch-depth: 0 in CI; run \`git fetch --unshallow\` locally). Previously skipped-as-PASS, masking ~24h of Tier-1 drift on main."
    return
  fi

  local hash_path="skills/update-zskills/references/tier1-shipped-hashes.txt"
  local last_hash_commit
  last_hash_commit=$(git -C "$REPO_ROOT" log -1 --pretty=format:%H -- "$hash_path")
  if [ -z "$last_hash_commit" ]; then
    # The hash file may have been generated in this very worktree but not
    # yet committed (verifier-pre-commit state). This is a legitimate
    # transient state (the post-merge CI fires after the commit lands),
    # so emit a real SKIP rather than a fake PASS.
    skip "case 6c: hash file uncommitted in this worktree (pre-commit state)"
    return
  fi

  # Parse name+owner pairs from script-ownership.md.
  # Owner column may have trailing prose; take the first token.
  local violations=()
  while IFS=$'\t' read -r name owner; do
    [ -z "$name" ] && continue
    local last_script_commit
    last_script_commit=$(git -C "$REPO_ROOT" log -1 --pretty=format:%H \
      -- "scripts/$name" "skills/$owner/scripts/$name")
    [ -z "$last_script_commit" ] && continue
    if ! git -C "$REPO_ROOT" merge-base --is-ancestor \
         "$last_script_commit" "$last_hash_commit"; then
      violations+=("$name (owner: $owner)")
    fi
  done < <(awk -F'|' '$3 ~ /^[[:space:]]*1[[:space:]]*$/ {
    gsub(/[[:space:]`]/, "", $2);
    owner=$4;
    sub(/^[[:space:]`]+/, "", owner);
    sub(/[[:space:]`(].*$/, "", owner);
    print $2 "\t" owner
  }' "$REPO_ROOT/skills/update-zskills/references/script-ownership.md")

  if [ "${#violations[@]}" -eq 0 ]; then
    pass "case 6c: commit-cohabitation — hash file regenerated after each Tier-1 change"
  else
    fail "case 6c: commit-cohabitation" "violations: ${violations[*]}"
  fi
}

# --- Run ------------------------------------------------------------------

echo "Running tests/test-update-zskills-migration.sh"
test_case_1_match_lf
test_case_2_user_modified
test_case_2b_crlf_normalize
test_case_2c_new_tier1_match
test_case_2d_new_tier1_kept
test_case_2e_git_missing
test_case_3_not_in_stale_list
test_case_4_missing_hashes_file
test_case_5_user_says_no
test_case_6a_stale_list_drift
test_case_6b_hash_format
test_case_6c_commit_cohabitation

echo
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  if [ "$SKIP_COUNT" -gt 0 ]; then
    printf '\033[32mResults: %d passed, 0 failed, %d skipped (of %d)\033[0m\n' \
      "$PASS_COUNT" "$SKIP_COUNT" "$TOTAL"
  else
    printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  fi
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"
  exit 1
fi
