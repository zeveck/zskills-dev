#!/usr/bin/env bash
# tests/test-build-rewrite-dev-urls.sh
#
# Unit test for the SHARED rewrite_dev_urls helper (#1002) in
# scripts/_lib/finalize-prod-tree.sh. Sources the lib, calls the function on
# fixture files, and asserts:
#
#   - Dev Pages URL (zeveck.github.io/zskills-dev)  → zskills.synapticnoise.com
#   - Dev repo URL  (github.com/zeveck/zskills-dev) → github.com/zeveck/zskills
#   - Both forms in one file are rewritten in a single call.
#   - Works across .md / .html / .js / .json fixtures.
#   - A file WITHOUT any dev URL is left BYTE-IDENTICAL (no spurious sed -i
#     write — verified by mtime preservation + content equality).
#   - A file carrying the `zskills-dev-url-allow` marker is left untouched even
#     when it contains a dev URL.
#   - Idempotent: re-running on an already-rewritten file is a no-op.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Source the shared finalizer so rewrite_dev_urls is in scope.
# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/_lib/finalize-prod-tree.sh"

if ! declare -F rewrite_dev_urls >/dev/null; then
  fail "0. rewrite_dev_urls not defined after sourcing finalize-prod-tree.sh"
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" 1
  exit 1
fi
pass "0. rewrite_dev_urls is defined after sourcing the finalizer"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# assert_contains <label> <file> <needle>
assert_contains() {
  if grep -qF "$3" "$2"; then pass "$1"; else fail "$1 (missing: $3)"; fi
}
# assert_absent <label> <file> <needle>
assert_absent() {
  if grep -qF "$3" "$2"; then fail "$1 (still present: $3)"; else pass "$1"; fi
}

# ── 1. Markdown: Pages URL rewritten ─────────────────────────────────────────
MD="$TMP/page.md"
printf 'See <https://zeveck.github.io/zskills-dev/demo/> for the demo.\n' > "$MD"
rewrite_dev_urls "$MD"
assert_contains "1a. .md: Pages host rewritten to prod" "$MD" "zskills.synapticnoise.com/demo/"
assert_absent   "1b. .md: dev Pages host gone"          "$MD" "zeveck.github.io/zskills-dev"

# ── 2. HTML: href Pages URL rewritten ────────────────────────────────────────
HTML="$TMP/index.html"
printf '<a href="https://zeveck.github.io/zskills-dev/docs/">Dashboard</a>\n' > "$HTML"
rewrite_dev_urls "$HTML"
assert_contains "2a. .html: href rewritten to prod" "$HTML" "https://zskills.synapticnoise.com/docs/"
assert_absent   "2b. .html: dev href gone"          "$HTML" "zeveck.github.io/zskills-dev"

# ── 3. JS: repo URL rewritten ────────────────────────────────────────────────
JS="$TMP/widget.js"
printf 'const REPO = "https://github.com/zeveck/zskills-dev/issues/new";\n' > "$JS"
rewrite_dev_urls "$JS"
assert_contains "3a. .js: repo URL rewritten to prod repo" "$JS" "https://github.com/zeveck/zskills/issues/new"
assert_absent   "3b. .js: dev repo URL gone"               "$JS" "github.com/zeveck/zskills-dev"

# ── 4. Both forms in one file rewritten in a single call ─────────────────────
BOTH="$TMP/both.md"
printf 'Site: zeveck.github.io/zskills-dev — Repo: github.com/zeveck/zskills-dev/issues\n' > "$BOTH"
rewrite_dev_urls "$BOTH"
assert_contains "4a. both: Pages → prod host"          "$BOTH" "zskills.synapticnoise.com"
assert_contains "4b. both: repo → prod repo"           "$BOTH" "github.com/zeveck/zskills/issues"
assert_absent   "4c. both: no dev Pages host survives" "$BOTH" "zeveck.github.io/zskills-dev"
assert_absent   "4d. both: no dev repo URL survives"   "$BOTH" "github.com/zeveck/zskills-dev"

# ── 5. File WITHOUT a dev URL is left byte-identical (no spurious write) ──────
CLEAN="$TMP/clean.md"
printf 'Nothing to see here. Visit zskills.synapticnoise.com.\n' > "$CLEAN"
CLEAN_BEFORE="$(cat "$CLEAN")"
# Capture mtime BEFORE, sleep past filesystem mtime granularity, call, compare.
MTIME_BEFORE="$(stat -c %Y "$CLEAN" 2>/dev/null || stat -f %m "$CLEAN")"
sleep 1
rewrite_dev_urls "$CLEAN"
MTIME_AFTER="$(stat -c %Y "$CLEAN" 2>/dev/null || stat -f %m "$CLEAN")"
if [ "$(cat "$CLEAN")" = "$CLEAN_BEFORE" ]; then
  pass "5a. clean file: content unchanged"
else
  fail "5a. clean file: content was modified"
fi
if [ "$MTIME_BEFORE" = "$MTIME_AFTER" ]; then
  pass "5b. clean file: NOT rewritten (mtime unchanged — no spurious sed -i)"
else
  fail "5b. clean file: mtime changed — sed -i fired on a file with no dev URL"
fi

# ── 6. Allow-listed file is left untouched even WITH a dev URL ────────────────
ALLOW="$TMP/changelog.md"
printf '<!-- zskills-dev-url-allow -->\nRewrites zeveck.github.io/zskills-dev → prod.\n' > "$ALLOW"
ALLOW_BEFORE="$(cat "$ALLOW")"
rewrite_dev_urls "$ALLOW"
if [ "$(cat "$ALLOW")" = "$ALLOW_BEFORE" ]; then
  pass "6. allow-listed file: dev URL preserved (marker honored)"
else
  fail "6. allow-listed file: dev URL was rewritten despite the marker"
fi

# ── 7. Idempotent: re-running on an already-rewritten file is a no-op ─────────
AFTER_FIRST="$(cat "$BOTH")"
rewrite_dev_urls "$BOTH"
if [ "$(cat "$BOTH")" = "$AFTER_FIRST" ]; then
  pass "7. idempotent: second call is a no-op"
else
  fail "7. idempotent: second call changed the file"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
