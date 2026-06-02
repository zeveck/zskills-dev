#!/bin/bash
# tests/test-plugin-ref-consistency.sh
#
# Pre-launch guard (fail-closed). Statically asserts that the refs the REAL
# publisher PUSHES are CONSISTENT with what consumers RESOLVE.
#
# THE publisher is the "🚀 Ship to Prod" button:
#   .github/workflows/ship-to-prod.yml → scripts/build-prod.sh
#   → push to prod's BARE `main` branch + a BARE `<version>` tag
#     (ship-to-prod.yml: `git push prod "${PROD_SHA}:refs/heads/main"` and
#      `git push prod "${PROD_SHA}:refs/tags/${TAG}"`).
#
# Consumers resolve:
#   - .claude-plugin/marketplace.json's `zs` source.ref — the moving window
#     unpinned consumers track — must equal the BRANCH the button pushes
#     (`main`).
#   - docs/guides/PLUGIN_INSTALL.md's pin-by-version idiom must be a BARE
#     `<version>` tag (e.g. `2026.06.0`), matching the TAG namespace the
#     button pushes (`refs/tags/${TAG}`, bare — NOT `prod/<version>`).
#
# Why this exists: a prior cut declared `prod/main` / `prod/<version>` in the
# marketplace + docs while the REAL publisher (the button) pushes bare `main`
# / bare `<version>`. Those `prod/...` refs never existed on prod → the first
# `/plugin install zs@zskills` could not resolve the ref. This test FAILS-RED
# if marketplace.json drifts back to `prod/main` or the docs go back to
# `prod/<version>`, or if the workflow stops pushing bare `main` / bare tag.
#
# (scripts/build-plugin-release.sh is NOT the publish path; it is a local
# dogfood builder. It pushes to the SAME bare refs on --push, but the
# CONSUMER-FACING guarantee is anchored to the workflow, which is what the
# button actually runs.)
#
# Uses Python stdlib json (no jq — per `## Python is required`).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

WF=".github/workflows/ship-to-prod.yml"
MP=".claude-plugin/marketplace.json"
DOC="docs/guides/PLUGIN_INSTALL.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== plugin ref consistency (REAL publisher push targets ↔ consumer resolution) ==="

# Pre-flight: the files we parse must exist.
for f in "$WF" "$MP" "$DOC"; do
  if [ ! -f "$f" ]; then
    fail "required file present: $f"
  else
    pass "required file present: $f"
  fi
done

# ── Parse the two `git push prod ...` refspec lines out of the WORKFLOW ─────
# Heads refspec: git push prod "${PROD_SHA}:refs/heads/main"
# Tags  refspec: git push prod "${PROD_SHA}:refs/tags/${TAG}"
HEADS_LINE="$(grep -E 'git push prod .*:refs/heads/' "$WF" | head -1)"
TAGS_LINE="$(grep -E 'git push prod .*:refs/tags/' "$WF" | head -1)"

if [ -n "$HEADS_LINE" ]; then
  pass "workflow has a heads-refspec push line"
else
  fail "workflow has a heads-refspec push line"
fi
if [ -n "$TAGS_LINE" ]; then
  pass "workflow has a tags-refspec push line"
else
  fail "workflow has a tags-refspec push line"
fi

# Extract the DEST of each refspec (the part after the colon).
# Heads dest: refs/heads/<DEST_BRANCH>
PUSHED_BRANCH="$(printf '%s\n' "$HEADS_LINE" | sed -nE 's@.*:refs/heads/([A-Za-z0-9._/-]+)".*@\1@p')"
# Tags dest: refs/tags/<DEST_TAG> (the workflow uses ${TAG}, a BARE version).
PUSHED_TAG_DEST="$(printf '%s\n' "$TAGS_LINE" | sed -nE 's@.*:(refs/tags/[^"]*)".*@\1@p')"

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

# ── Assertion 1: workflow-pushed BRANCH == marketplace zs source.ref ───────
if [ -n "$PUSHED_BRANCH" ] && [ "$PUSHED_BRANCH" = "$MP_REF" ]; then
  pass "workflow-pushed branch '$PUSHED_BRANCH' == marketplace zs source.ref '$MP_REF'"
else
  fail "workflow-pushed branch '$PUSHED_BRANCH' must equal marketplace zs source.ref '$MP_REF' (both should be 'main')"
fi

# Belt-and-braces: both should be the bare literal 'main' (NOT 'prod/main').
if [ "$MP_REF" = "main" ]; then
  pass "marketplace zs source.ref is bare 'main' (not 'prod/main')"
else
  fail "marketplace zs source.ref must be bare 'main' (got '$MP_REF')"
fi
if [ "$PUSHED_BRANCH" = "main" ]; then
  pass "workflow pushes to bare branch 'main' (not 'prod/main')"
else
  fail "workflow pushes to bare branch 'main' (not 'prod/main') — got '$PUSHED_BRANCH'"
fi

# ── Assertion 2: workflow tag dest is the BARE-version namespace ────────────
# The workflow pushes refs/tags/${TAG} where ${TAG} is the bare YYYY.MM.N
# version — NOT refs/tags/prod/<version>. Assert it is exactly the bare form.
if [ "$PUSHED_TAG_DEST" = 'refs/tags/${TAG}' ]; then
  pass "workflow pushes tag to bare 'refs/tags/\${TAG}' (bare-version namespace)"
else
  fail "workflow pushes tag to bare 'refs/tags/\${TAG}' — got '$PUSHED_TAG_DEST' (must NOT be 'refs/tags/prod/...')"
fi

# ── Assertion 3: docs pin idiom is a BARE version tag, NOT prod/<version> ───
# The docs must document a BARE `<version>` pin (e.g. 2026.06.0), matching
# what the button pushes, and must NOT document the obsolete `prod/<version>`.
if grep -Eq 'ref"?:?[^"]*"?[0-9]{4}\.[0-9]{2}\.[0-9]+' "$DOC"; then
  pass "docs document a bare '<version>' tag pin idiom (YYYY.MM.N)"
else
  fail "docs must document a bare '<version>' tag pin idiom (YYYY.MM.N) in PLUGIN_INSTALL.md"
fi
if grep -q 'prod/<version>' "$DOC"; then
  fail "docs must NOT document the obsolete 'prod/<version>' pin idiom (found in PLUGIN_INSTALL.md)"
else
  pass "docs do NOT reference the obsolete 'prod/<version>' pin idiom"
fi
if grep -q '"ref": "prod/' "$DOC"; then
  fail "docs must NOT show a 'prod/...' source.ref example (found in PLUGIN_INSTALL.md)"
else
  pass "docs do NOT show a 'prod/...' source.ref example"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit "$FAIL_COUNT"
