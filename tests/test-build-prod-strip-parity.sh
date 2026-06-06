#!/usr/bin/env bash
# tests/test-build-prod-strip-parity.sh
#
# Strip / rewrite parity (#1002): the two publishers must produce the SAME prod
# tree (modulo intrinsic, documented differences). Both call the shared
# finalizer (scripts/_lib/finalize-prod-tree.sh) for the dev-only strip set,
# the recursive CANARY strip, and the dev→prod URL rewrite — but before #1002
# they each carried their OWN copy of rewrite_dev_urls (README-only) and their
# CANARY strips diverged (build-prod stripped only top-level CANARY_*.md while
# build-plugin-release used a recursive find, so docs/plans/archive/canaries/*.md
# shipped via one but not the other). This test stages both builders and
# `diff -r`s the trees, asserting they are STRUCTURALLY identical.
#
# Documented, allow-listed differences (NOT parity violations):
#   - .git                       — build-prod runs in a working clone (has .git);
#                                  the archive-extracted comparison tree does not.
#   - **/.claude-plugin/plugin.json — build-plugin-release RE-SERIALIZES both
#                                  plugin.json files (Python json.dump, indent=2,
#                                  unicode-escaped) during its version-bump step;
#                                  build-prod never touches them. The difference
#                                  is whitespace/version/unicode-escaping only —
#                                  not a strip/rewrite divergence — so both
#                                  plugin.json files are excluded from the diff.
#                                  (build-prod is NOT the version-setter; the
#                                  ship-to-prod workflow bumps versions upstream.)
#   - scripts/build-*.sh         — both finalizers strip these. build-prod
#                                  strips its OWN running script too; on an
#                                  archive-extracted run both trees lose all of
#                                  them, so this is normally a no-op exclusion,
#                                  kept for documentation + robustness.
#
# Method: extract HEAD via `git archive` into TWO sibling trees, run each
# builder against its own tree (build-prod IN-PLACE via a clone whose working
# tree IS the archive; build-plugin-release into its own STAGE), then diff.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# snapshot_worktree_repo <dest>
# Materialise a git repo at <dest> mirroring the CURRENT working tree (tracked +
# uncommitted edits), committed so the build scripts' internal `git archive
# HEAD` sees live on-disk content. A plain `git clone` would carry only HEAD and
# silently test stale committed scripts (this fix may not be committed yet).
snapshot_worktree_repo() {
  local dest="$1"
  mkdir -p "$dest"
  ( cd "$REPO_ROOT" && git ls-files -co --exclude-standard -z ) \
    | ( cd "$REPO_ROOT" && tar --null -T - -cf - ) \
    | tar -x -C "$dest"
  git -C "$dest" init --quiet
  git -C "$dest" config user.email "parity-test@zskills.invalid"
  git -C "$dest" config user.name  "zskills parity test"
  git -C "$dest" add -A
  git -C "$dest" commit --quiet -m "snapshot for #1002 parity test" >/dev/null 2>&1
}

echo "=== strip / rewrite parity: build-prod.sh vs build-plugin-release.sh ==="

# ── build-prod.sh tree: run IN-PLACE inside an isolated worktree snapshot ────
# build-prod.sh mutates its working tree and self-deletes build-*.sh. Run it in
# a throwaway snapshot so the live repo is untouched; the snapshot's post-build
# working tree IS the prod tree.
# Apples-to-apples normalization: build-prod runs IN-PLACE on a filesystem
# working tree, while build-plugin-release produces its tree via `git archive`
# (which drops empty dirs left behind by file strips, and never carries
# force-added-but-gitignored fixtures like tests/fixtures/**/.zskills). To
# compare only strip/rewrite CONTENT — not in-place-vs-archive materialization
# artifacts — we run build-prod in a snapshot, then re-extract its result via
# `git archive` exactly as build-plugin-release does for its tree.
BP_SNAP="$TMP/build-prod-snap"
BP_TREE="$TMP/build-prod"
mkdir -p "$BP_TREE"
if ! snapshot_worktree_repo "$BP_SNAP"; then
  fail "0. worktree snapshot for build-prod failed"
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" 1
  exit 1
fi
if ( cd "$BP_SNAP" && bash scripts/build-prod.sh ) > "$TMP/bp.out" 2>&1; then
  pass "0a. build-prod.sh ran (rc=0)"
  # Commit the post-build in-place tree, then archive it (empty-dir-free,
  # gitignored-fixture-free) so the diff sees the SAME materialization as PR_TREE.
  git -C "$BP_SNAP" add -A
  git -C "$BP_SNAP" commit --quiet -m "post-build-prod snapshot" >/dev/null 2>&1
  git -C "$BP_SNAP" archive HEAD | tar -x -C "$BP_TREE"
else
  fail "0a. build-prod.sh FAILED — output below:"
  sed 's/^/      /' "$TMP/bp.out"
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT+FAIL_COUNT))"
  exit "$FAIL_COUNT"
fi

# ── build-plugin-release.sh tree: run in another clone, extract prod/main ────
PR_CLONE="$TMP/plugin-clone"
PR_TREE="$TMP/build-plugin"
mkdir -p "$PR_TREE"
if ! snapshot_worktree_repo "$PR_CLONE"; then
  fail "0. worktree snapshot for build-plugin-release failed"
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT+FAIL_COUNT))"
  exit "$FAIL_COUNT"
fi
if ( cd "$PR_CLONE" && bash scripts/build-plugin-release.sh ) > "$TMP/pr.out" 2>&1; then
  pass "0b. build-plugin-release.sh ran (rc=0)"
  git -C "$PR_CLONE" archive refs/heads/prod/main | tar -x -C "$PR_TREE"
else
  fail "0b. build-plugin-release.sh FAILED — output below:"
  sed 's/^/      /' "$TMP/pr.out"
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT+FAIL_COUNT))"
  exit "$FAIL_COUNT"
fi

# ── diff -r the two trees (exclude the documented intrinsic-difference files) ─
# Both trees are now git-archive-materialized (no .git, no empty dirs, no
# gitignored fixtures), so the only remaining intrinsic differences are the
# re-serialized plugin.json files and build-*.sh self-deletion artifacts.
DIFF_OUT="$TMP/diff.out"
if diff -r \
     --exclude='build-*.sh' \
     --exclude='plugin.json' \
     "$BP_TREE" "$PR_TREE" > "$DIFF_OUT" 2>&1; then
  pass "1. build-prod.sh and build-plugin-release.sh produce structurally identical trees"
else
  fail "1. trees DIFFER (strip/rewrite parity broken) — diff below:"
  sed 's/^/      /' "$DIFF_OUT"
fi

# ── Targeted parity assertion: archive canaries stripped from BOTH ───────────
# The specific #1002 strip-parity regression: docs/plans/archive/canaries/*.md
# shipped via build-prod (top-level-only glob) but were stripped by
# build-plugin-release (recursive find). Both must now strip them.
for tree_label in "BP:$BP_TREE" "PR:$PR_TREE"; do
  label="${tree_label%%:*}"; tree="${tree_label#*:}"
  if [ -d "$tree/docs/plans/archive/canaries" ] && \
     [ -n "$(find "$tree/docs/plans/archive/canaries" -name '*CANARY*' 2>/dev/null)" ]; then
    fail "2.$label: archive canary files survived the strip"
  else
    pass "2.$label: archive canaries stripped (no *CANARY* under docs/plans/archive/canaries)"
  fi
done

# ── Targeted strip assertion: dev-only .github/ stripped from BOTH ────────────
# The prod tree must not ship .github/ (dev-only CI workflows + the dev→prod
# ship-to-prod button). Stripping it also fixes the ship-to-prod push, which the
# prod PAT rejects for touching workflow files (it lacks the `workflow` scope).
for tree_label in "BP:$BP_TREE" "PR:$PR_TREE"; do
  label="${tree_label%%:*}"; tree="${tree_label#*:}"
  if [ -e "$tree/.github" ]; then
    fail "3.$label: dev-only .github/ survived the strip (must be absent in prod tree)"
  else
    pass "3.$label: .github/ stripped from prod tree"
  fi
done

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
