#!/usr/bin/env bash
# tests/test-prod-tree-no-dev-urls.sh
#
# Coverage contract (#1002): the BUILT prod tree must carry NO dev-only URLs.
#
# Both publishers (build-prod.sh, build-plugin-release.sh) call the SHARED
# finalizer (scripts/_lib/finalize-prod-tree.sh), whose rewrite_dev_urls
# tree-walk swaps every dev URL to its prod equivalent AFTER all strip steps:
#
#   zeveck.github.io/zskills-dev   → zskills.synapticnoise.com   (dev Pages site)
#   github.com/zeveck/zskills-dev  → github.com/zeveck/zskills   (dev GitHub repo)
#
# Before #1002 each builder ran rewrite_dev_urls on README.md ALONE, so 21
# source files (a live dashboard href, skill issue-filing prose, a demo URL,
# and a long tail of docs) shipped to prod still pointing at the dev Pages site
# / dev repo. This test stages BOTH builders' output and asserts 0 dev-URL hits
# (modulo an allow-list marker for genuinely-prose-only contexts), plus the 3
# CRITICAL/HIGH regression instances are the PROD URL in the staged tree.
#
# Allow-list mechanism: a file that intentionally NAMES a dev URL in a prose-
# only context (e.g. CHANGELOG.md narrating the rewrite, the dogfood-install
# script defaulting to the dev repo) carries a `zskills-dev-url-allow` marker.
# rewrite_dev_urls honors the marker (leaves the file untouched) and this test
# excuses any marked file from the 0-hit assertion — so the contract is "every
# dev URL is rewritten UNLESS its file is explicitly allow-listed."

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Precise dev-URL pattern (the contract). The broad manual-acceptance grep
# (`zskills-dev|github.io/zskills`) over-matches bare repo-name prose and
# backslash-escaped grep-command examples in plan docs; this is the form
# rewrite_dev_urls actually rewrites and the form that 404s in prod.
DEV_URL_RE='zeveck\.github\.io/zskills-dev|github\.com/zeveck/zskills-dev'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# snapshot_worktree_repo <dest>
# Materialise a fresh git repo at <dest> that mirrors the CURRENT working tree
# (tracked files + any uncommitted modifications), then commit it so the build
# scripts' internal `git archive HEAD` sees the live on-disk content. This makes
# the test pass against the working-tree fix WHETHER OR NOT it has been
# committed yet — a plain `git clone` would only carry HEAD and silently test
# stale committed scripts. Excludes the build artifacts dir + .git itself.
snapshot_worktree_repo() {
  local dest="$1"
  mkdir -p "$dest"
  # Copy every tracked-or-untracked-but-not-ignored path from the worktree.
  # `git ls-files -co --exclude-standard` lists exactly the files git would
  # consider (tracked + untracked-not-ignored), reflecting uncommitted edits.
  ( cd "$REPO_ROOT" && git ls-files -co --exclude-standard -z ) \
    | ( cd "$REPO_ROOT" && tar --null -T - -cf - ) \
    | tar -x -C "$dest"
  git -C "$dest" init --quiet
  git -C "$dest" config user.email "no-dev-urls-test@zskills.invalid"
  git -C "$dest" config user.name  "zskills no-dev-urls test"
  git -C "$dest" add -A
  git -C "$dest" commit --quiet -m "snapshot for #1002 build test" >/dev/null 2>&1
}

# assert_tree_clean <label> <tree-dir>
# Grep the tree for the precise dev-URL pattern, drop hits in files carrying
# the allow-list marker, assert 0 survivors.
assert_tree_clean() {
  local label="$1" tree="$2"
  local hits survivors
  hits="$(grep -rlE "$DEV_URL_RE" "$tree" 2>/dev/null || true)"
  survivors=""
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -q 'zskills-dev-url-allow' "$f"; then
      continue   # allow-listed prose context — excused
    fi
    survivors+="$f"$'\n'
  done <<<"$hits"
  survivors="$(printf '%s' "$survivors" | sed '/^$/d')"
  if [ -z "$survivors" ]; then
    pass "$label: 0 non-allow-listed dev-URL hits in built tree"
  else
    fail "$label: dev URLs survived in the built tree (non-allow-listed):"
    printf '%s\n' "$survivors" | sed "s|^$tree/||; s/^/        /"
  fi
}

# assert_prod_url <label> <file> <grep-anchor>
# The CRITICAL/HIGH regression instances must carry the PROD URL (and NOT the
# dev URL) in the staged tree.
assert_prod_url() {
  local label="$1" file="$2"
  if [ ! -f "$file" ]; then
    fail "$label: expected file missing from built tree: $file"
    return
  fi
  if grep -qE "$DEV_URL_RE" "$file"; then
    fail "$label: still carries a dev URL in the built tree"
  else
    pass "$label: no dev URL in the built tree"
  fi
}

# ── A. build-plugin-release.sh → its own STAGE (git ls-tree on the prod ref) ──
echo "=== A. build-plugin-release.sh staged tree carries no dev URLs ==="
PR_STAGE="$TMP/plugin-stage"
mkdir -p "$PR_STAGE"

# build-plugin-release.sh creates LOCAL prod/main + prod/<version> refs. Run it
# in an isolated CLONE so those refs never touch the live repo, then extract the
# prod/main tree.
PR_CLONE="$TMP/plugin-clone"
if snapshot_worktree_repo "$PR_CLONE"; then
  if ( cd "$PR_CLONE" && bash scripts/build-plugin-release.sh ) > "$TMP/pr-build.out" 2>&1; then
    pass "0a. build-plugin-release.sh ran in isolated clone (rc=0)"
    git -C "$PR_CLONE" archive refs/heads/prod/main | tar -x -C "$PR_STAGE"
    assert_tree_clean "A.plugin-release" "$PR_STAGE"
    assert_prod_url "A.dashboard index.html" \
      "$PR_STAGE/skills/zskills-dashboard/scripts/zskills_monitor/static/index.html"
    assert_prod_url "A.run-plan SKILL.md issue-filing prose" \
      "$PR_STAGE/skills/run-plan/SKILL.md"
    assert_prod_url "A.inspecting-and-monitoring.md demo URL" \
      "$PR_STAGE/docs/guides/inspecting-and-monitoring.md"
  else
    fail "0a. build-plugin-release.sh FAILED in isolated clone — output below:"
    sed 's/^/      /' "$TMP/pr-build.out"
  fi
else
  fail "0a. worktree snapshot failed (plugin-release stage)"
fi

# ── B. build-prod.sh → IN-PLACE on a git-archive-extracted tree ──────────────
# build-prod.sh modifies its working tree in place and DELETES itself (build-*.sh
# strip). Run it inside a throwaway clone, then inspect the clone's on-disk tree.
echo ""
echo "=== B. build-prod.sh in-place tree carries no dev URLs ==="
BP_CLONE="$TMP/prod-clone"
if snapshot_worktree_repo "$BP_CLONE"; then
  if ( cd "$BP_CLONE" && bash scripts/build-prod.sh ) > "$TMP/bp-build.out" 2>&1; then
    pass "0b. build-prod.sh ran in isolated clone (rc=0)"
    assert_tree_clean "B.build-prod" "$BP_CLONE"
    assert_prod_url "B.dashboard index.html" \
      "$BP_CLONE/skills/zskills-dashboard/scripts/zskills_monitor/static/index.html"
    assert_prod_url "B.run-plan SKILL.md issue-filing prose" \
      "$BP_CLONE/skills/run-plan/SKILL.md"
    assert_prod_url "B.inspecting-and-monitoring.md demo URL" \
      "$BP_CLONE/docs/guides/inspecting-and-monitoring.md"
  else
    fail "0b. build-prod.sh FAILED in isolated clone — output below:"
    sed 's/^/      /' "$TMP/bp-build.out"
  fi
else
  fail "0b. worktree snapshot failed (build-prod stage)"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
