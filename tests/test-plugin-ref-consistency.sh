#!/bin/bash
# tests/test-plugin-ref-consistency.sh
#
# Pre-launch guard (fail-closed). Statically asserts that the refs
# scripts/build-plugin-release.sh PUSHES on `--push` are CONSISTENT with what
# consumers RESOLVE:
#
#   - .claude-plugin/marketplace.json's `zs` source.ref (the moving window
#     unpinned consumers track) — must equal the BRANCH the build pushes.
#   - docs/guides/PLUGIN_INSTALL.md's pin-by-version idiom (`prod/<version>`)
#     — must match the TAG namespace the build pushes (with $VERSION).
#
# Why this exists: a prior cut of build-plugin-release.sh pushed to bare
# `main` / bare `<version>` while marketplace.json declared `prod/main` and
# the docs documented `prod/<version>`. Those refs never existed on prod →
# the first `/plugin install zs@zskills` could not resolve the ref. This test
# FAILS-RED if anyone reverts the build to push to bare refs.
#
# Uses Python stdlib json (no jq — per `## Python is required`).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

BUILD="scripts/build-plugin-release.sh"
MP=".claude-plugin/marketplace.json"
DOC="docs/guides/PLUGIN_INSTALL.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== plugin ref consistency (build push targets ↔ consumer resolution) ==="

# Pre-flight: the files we parse must exist.
for f in "$BUILD" "$MP" "$DOC"; do
  if [ ! -f "$f" ]; then
    fail "required file present: $f"
  else
    pass "required file present: $f"
  fi
done

# ── Parse the two `git push prod ...` refspec lines out of the build ────────
# Heads refspec: `git push prod "refs/heads/<src>:refs/heads/<dest-branch>"`
# Tags  refspec: `git push prod "refs/tags/<src>:refs/tags/<dest-tag>"`
HEADS_LINE="$(grep -E 'git push prod .*refs/heads/' "$BUILD" | head -1)"
TAGS_LINE="$(grep -E 'git push prod .*refs/tags/' "$BUILD" | head -1)"

if [ -n "$HEADS_LINE" ]; then
  pass "build has a heads-refspec push line"
else
  fail "build has a heads-refspec push line"
fi
if [ -n "$TAGS_LINE" ]; then
  pass "build has a tags-refspec push line"
else
  fail "build has a tags-refspec push line"
fi

# Extract the DEST of each refspec (the part after the colon).
# Heads dest: refs/heads/<DEST_BRANCH>
PUSHED_BRANCH="$(printf '%s\n' "$HEADS_LINE" | sed -nE 's@.*refs/heads/[^:]*:refs/heads/([^"]*)".*@\1@p')"
# Tags dest: refs/tags/<DEST_TAG> (contains $VERSION)
PUSHED_TAG_DEST="$(printf '%s\n' "$TAGS_LINE" | sed -nE 's@.*refs/tags/[^:]*:(refs/tags/[^"]*)".*@\1@p')"

# ── marketplace.json: zs source.ref (read via Python stdlib json) ──────────
MP_REF="$("$PYTHON" - "$MP" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    mp = json.load(f)
ref = ""
for p in mp.get("plugins", []):
    if isinstance(p, dict) and p.get("name") == "zs":
        src = p.get("source")
        if isinstance(src, dict):
            ref = src.get("ref", "") or ""
print(ref)
PY
)"

# ── Assertion 1: pushed BRANCH == marketplace zs source.ref ────────────────
if [ -n "$PUSHED_BRANCH" ] && [ "$PUSHED_BRANCH" = "$MP_REF" ]; then
  pass "pushed branch '$PUSHED_BRANCH' == marketplace zs source.ref '$MP_REF'"
else
  fail "pushed branch '$PUSHED_BRANCH' must equal marketplace zs source.ref '$MP_REF' (both should be 'prod/main')"
fi

# Belt-and-braces: both should be the literal 'prod/main'.
if [ "$MP_REF" = "prod/main" ]; then
  pass "marketplace zs source.ref is 'prod/main'"
else
  fail "marketplace zs source.ref is 'prod/main' (got '$MP_REF')"
fi
if [ "$PUSHED_BRANCH" = "prod/main" ]; then
  pass "build pushes to branch 'prod/main' (not bare 'main')"
else
  fail "build pushes to branch 'prod/main' (not bare 'main') — got '$PUSHED_BRANCH'"
fi

# ── Assertion 2: pushed TAG namespace matches the doc pin idiom ────────────
# The build's tag dest should be refs/tags/prod/$VERSION (i.e. the prod/
# namespace), matching the documented `prod/<version>` pin idiom.
if [ "$PUSHED_TAG_DEST" = 'refs/tags/prod/$VERSION' ]; then
  pass "build pushes tag to 'refs/tags/prod/\$VERSION' (prod/<version> namespace)"
else
  fail "build pushes tag to 'refs/tags/prod/\$VERSION' — got '$PUSHED_TAG_DEST' (must NOT be bare 'refs/tags/\$VERSION')"
fi

# The docs must document the `prod/<version>` pin idiom.
if grep -q 'prod/<version>' "$DOC"; then
  pass "docs document the 'prod/<version>' pin idiom"
else
  fail "docs document the 'prod/<version>' pin idiom (PLUGIN_INSTALL.md)"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit "$FAIL_COUNT"
