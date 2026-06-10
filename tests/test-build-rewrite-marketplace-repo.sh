#!/usr/bin/env bash
# tests/test-build-rewrite-marketplace-repo.sh
#
# Unit test for the SHARED rewrite_marketplace_repo helper in
# scripts/_lib/finalize-prod-tree.sh. The dev repo's marketplace.json
# self-references the dev repo (zeveck/zskills-dev) so pre-publish plugin qual
# uses the genuine consumer flow; the publish path must translate the `zs`
# plugin's source.repo back to the prod slug (zeveck/zskills). This sources the
# lib, calls the function on fixture marketplace.json files, and asserts:
#
#   - dev slug (zeveck/zskills-dev) → prod slug (zeveck/zskills)
#   - `ref: "main"` is left untouched
#   - a non-zs entry's (`other-addon`) `./other-addon` relative-path source is left untouched
#   - top-level name / version / $schema survive the round-trip
#   - idempotent: a second call is a no-op
#   - a fixture that is ALREADY prod-pointing is left unchanged
#
# Mirrors the pass/fail/exit-$FAIL_COUNT harness of
# tests/test-build-rewrite-dev-urls.sh.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Source the shared finalizer so rewrite_marketplace_repo is in scope.
# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/_lib/finalize-prod-tree.sh"

if ! declare -F rewrite_marketplace_repo >/dev/null; then
  fail "0. rewrite_marketplace_repo not defined after sourcing finalize-prod-tree.sh"
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" 1
  exit 1
fi
pass "0. rewrite_marketplace_repo is defined after sourcing the finalizer"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# field <file> <python-expr-on-mp> — read a field out of a marketplace.json via
# Python json so assertions are structural, not substring-based.
field() {
  "$PYTHON" - "$1" "$2" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    mp = json.load(f)
by = {p.get("name"): p for p in mp.get("plugins", []) if isinstance(p, dict)}
print(eval(sys.argv[2], {"mp": mp, "by": by}))
PY
}

# write_dev_fixture <path> — the dev-pointing manifest (self-reference form).
write_dev_fixture() {
  cat > "$1" <<'JSON'
{
  "$schema": "https://anthropic.com/schemas/claude-plugin-marketplace.json",
  "name": "zskills",
  "owner": { "name": "Rich Conlan", "url": "https://github.com/zeveck" },
  "description": "Z Skills — agent-discipline skill framework",
  "version": "1",
  "plugins": [
    { "name": "zs", "source": { "source": "github", "repo": "zeveck/zskills-dev", "ref": "main" } },
    { "name": "other-addon", "source": "./other-addon" }
  ]
}
JSON
}

# write_prod_fixture <path> — the already-prod-pointing manifest.
write_prod_fixture() {
  cat > "$1" <<'JSON'
{
  "$schema": "https://anthropic.com/schemas/claude-plugin-marketplace.json",
  "name": "zskills",
  "owner": { "name": "Rich Conlan", "url": "https://github.com/zeveck" },
  "description": "Z Skills — agent-discipline skill framework",
  "version": "1",
  "plugins": [
    { "name": "zs", "source": { "source": "github", "repo": "zeveck/zskills", "ref": "main" } },
    { "name": "other-addon", "source": "./other-addon" }
  ]
}
JSON
}

# ── 1. dev slug → prod slug, ref + other-addon + top-level fields untouched ──
MP="$TMP/dev.json"
write_dev_fixture "$MP"
rewrite_marketplace_repo "$MP"

if [ "$(field "$MP" 'by["zs"]["source"]["repo"]')" = "zeveck/zskills" ]; then
  pass "1a. zs source.repo rewritten dev → prod (zeveck/zskills)"
else
  fail "1a. zs source.repo not rewritten to zeveck/zskills"
fi
if ! grep -q 'zskills-dev' "$MP"; then
  pass "1b. no 'zskills-dev' bare-slug residue after rewrite"
else
  fail "1b. 'zskills-dev' still present after rewrite"
fi
if [ "$(field "$MP" 'by["zs"]["source"]["ref"]')" = "main" ]; then
  pass "1c. zs source.ref left untouched (main)"
else
  fail "1c. zs source.ref changed (must stay 'main')"
fi
if [ "$(field "$MP" 'by["zs"]["source"]["source"]')" = "github" ]; then
  pass "1d. zs source.source left untouched (github)"
else
  fail "1d. zs source.source changed (must stay 'github')"
fi
if [ "$(field "$MP" 'by["other-addon"]["source"]')" = "./other-addon" ]; then
  pass "1e. other-addon source './other-addon' relative path untouched"
else
  fail "1e. other-addon source changed (must stay './other-addon')"
fi
if [ "$(field "$MP" 'mp["name"]')" = "zskills" ] \
   && [ "$(field "$MP" 'mp["version"]')" = "1" ] \
   && [ "$(field "$MP" 'mp["$schema"]')" = "https://anthropic.com/schemas/claude-plugin-marketplace.json" ]; then
  pass "1f. top-level name / version / \$schema survive the round-trip"
else
  fail "1f. top-level name / version / \$schema mangled by the round-trip"
fi

# ── 2. Idempotent: second call is a no-op ────────────────────────────────────
AFTER_FIRST="$(cat "$MP")"
rewrite_marketplace_repo "$MP"
if [ "$(cat "$MP")" = "$AFTER_FIRST" ]; then
  pass "2. idempotent: second call is a no-op"
else
  fail "2. idempotent: second call changed the file"
fi

# ── 3. Already-prod fixture is left unchanged ────────────────────────────────
PRODMP="$TMP/prod.json"
write_prod_fixture "$PRODMP"
PROD_BEFORE="$(cat "$PRODMP")"
rewrite_marketplace_repo "$PRODMP"
if [ "$(cat "$PRODMP")" = "$PROD_BEFORE" ]; then
  pass "3a. already-prod fixture: left byte-identical (no spurious rewrite)"
else
  fail "3a. already-prod fixture: was modified despite being prod-pointing"
fi
if [ "$(field "$PRODMP" 'by["zs"]["source"]["repo"]')" = "zeveck/zskills" ]; then
  pass "3b. already-prod fixture: zs source.repo remains zeveck/zskills"
else
  fail "3b. already-prod fixture: zs source.repo no longer zeveck/zskills"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
