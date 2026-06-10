#!/bin/bash
# DOC_VIEWER Phase 4 — catalog generator regression gate.
#
# Confirms that:
#   - scripts/build-catalog.sh exists, is invokable via bash
#   - BUILD_CATALOG_OUT env var is honored (script feature, not test trick)
#   - Two consecutive runs produce byte-identical output (determinism gate)
#   - The committed docs/DocsRegistry.js byte-matches a fresh run (drift gate)
#   - Per-section item ordering is path-ascending (sort stability)
#   - Excluded dirs (docs/plans, docs/reports, docs/evals, docs/issues, docs/tracking) emit zero entries
#   - Catalog scope: Guides + Skills + Internal (user-facing onboarding; ~35 entries)
#   - Internal section holds the user-invocable:false skills (land-pr,
#     manual-testing today), absent from the user-facing Skills section
#   - inspecting-and-monitoring.md is present (Phase 5 dependency)
#   - tests/run-all.sh registers this file
#
# Run from repo root: bash tests/test-doc-viewer-catalog.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILDER="$REPO_ROOT/scripts/build-catalog.sh"
REGISTRY="$REPO_ROOT/docs/DocsRegistry.js"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '  PASS  %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

print_summary_and_exit() {
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  if [ "$FAIL_COUNT" -gt 0 ]; then exit 1; fi
  exit 0
}

# Existence + executability.
if [ -f "$BUILDER" ]; then pass "scripts/build-catalog.sh exists"
else fail "scripts/build-catalog.sh missing"; print_summary_and_exit; fi

if [ -x "$BUILDER" ]; then pass "scripts/build-catalog.sh is executable"
else fail "scripts/build-catalog.sh not executable (chmod +x missing)"; fi

if [ -f "$REGISTRY" ]; then pass "docs/DocsRegistry.js exists"
else fail "docs/DocsRegistry.js missing"; print_summary_and_exit; fi

# Static-grep guards against accidental jq / node-CLI dependencies.
if grep -qE '(^|\s)jq(\s|$)' "$BUILDER"; then
  fail "build-catalog.sh references jq (forbidden — Python stdlib only)"
else
  pass "build-catalog.sh has no jq dependency"
fi

# BUILD_CATALOG_OUT honored — two runs to two tmp paths.
TMP1=$(mktemp -t cat-out-1-XXXX.js)
TMP2=$(mktemp -t cat-out-2-XXXX.js)
trap 'rm -f "$TMP1" "$TMP2"' EXIT

REG_SHA_BEFORE=$(sha256sum "$REGISTRY" | awk '{print $1}')

BUILD_CATALOG_OUT="$TMP1" bash "$BUILDER" >/dev/null 2>&1 \
  && pass "build-catalog.sh succeeds with BUILD_CATALOG_OUT=tmp1" \
  || fail "build-catalog.sh exit non-zero with BUILD_CATALOG_OUT=tmp1"

BUILD_CATALOG_OUT="$TMP2" bash "$BUILDER" >/dev/null 2>&1 \
  && pass "build-catalog.sh succeeds with BUILD_CATALOG_OUT=tmp2" \
  || fail "build-catalog.sh exit non-zero with BUILD_CATALOG_OUT=tmp2"

REG_SHA_AFTER=$(sha256sum "$REGISTRY" | awk '{print $1}')

if [ "$REG_SHA_BEFORE" = "$REG_SHA_AFTER" ]; then
  pass "BUILD_CATALOG_OUT leaves docs/DocsRegistry.js untouched"
else
  fail "BUILD_CATALOG_OUT=<tmp> mutated docs/DocsRegistry.js (env-var override broken)"
fi

# Byte-determinism: TMP1 == TMP2.
if diff -q "$TMP1" "$TMP2" >/dev/null 2>&1; then
  pass "two consecutive runs produce byte-identical output (determinism)"
else
  fail "two consecutive runs DIFFER (catalog is non-deterministic)"
  diff -u "$TMP1" "$TMP2" | head -40
fi

# Drift gate: committed catalog == fresh regenerated catalog.
if diff -q "$TMP1" "$REGISTRY" >/dev/null 2>&1; then
  pass "committed docs/DocsRegistry.js matches fresh re-run (no drift)"
else
  fail "committed docs/DocsRegistry.js has drifted — run: bash scripts/build-catalog.sh"
  echo "  --- diff (first 80 lines) ---"
  diff -u "$REGISTRY" "$TMP1" | head -80
fi

# Section ordering — Start here, Guides, the Skills index, the 8 skill
# categories (importance order, mirrors docs/skills/README.md + the nav),
# then Internal last.
EXPECTED_ORDER='Start here Guides Skills Execution Planning & Design Quality Assurance Automation Reporting Utilities Internal'
ACTUAL_ORDER=$(grep -oE 'section: "[^"]+"' "$REGISTRY" | sed 's/section: "\(.*\)"/\1/' | tr '\n' ' ' | sed 's/ $//')
if [ "$ACTUAL_ORDER" = "$EXPECTED_ORDER" ]; then
  pass "10 sections present in fixed order"
else
  fail "section order mismatch — expected '$EXPECTED_ORDER', got '$ACTUAL_ORDER'"
fi

# Entry count: ~33 (1 Start here + ~6 Guides + ~26 Skills).
ENTRY_COUNT=$(grep -cE '^\s+\{ name: ' "$REGISTRY")
if [ "$ENTRY_COUNT" -ge 25 ] && [ "$ENTRY_COUNT" -le 50 ]; then
  pass "catalog has $ENTRY_COUNT entries (in expected 25..50 range)"
else
  fail "catalog has $ENTRY_COUNT entries, expected 25..50 (Start here + Guides + Skills only)"
fi

# Internal section membership — the user-invocable:false docs live
# here, NOT in the user-facing Skills section. Today that set is exactly
# land-pr + manual-testing (classification is by source-skill frontmatter,
# enumerated by the generator — this asserts the live result).
INTERNAL_BLOCK=$(awk '
  /section: "Internal"/ { in_sec=1; next }
  in_sec && /^    \]/          { exit }
  in_sec                       { print }
' "$REGISTRY")
SKILLS_BLOCK=$(awk '
  /section: "Skills"/          { in_sec=1; next }
  in_sec && /^    \]/          { exit }
  in_sec                       { print }
' "$REGISTRY")
for doc in land-pr manual-testing; do
  if printf '%s\n' "$INTERNAL_BLOCK" | grep -q "\"docs/skills/$doc.md\""; then
    pass "Internal section contains docs/skills/$doc.md"
  else
    fail "Internal section missing docs/skills/$doc.md"
  fi
  if printf '%s\n' "$SKILLS_BLOCK" | grep -q "\"docs/skills/$doc.md\""; then
    fail "docs/skills/$doc.md still in user-facing Skills section (should be Internal)"
  else
    pass "docs/skills/$doc.md absent from user-facing Skills section"
  fi
done
# README is the section index — it stays under Skills, never Internal.
if printf '%s\n' "$SKILLS_BLOCK" | grep -q '"docs/skills/README.md"'; then
  pass "docs/skills/README.md remains in Skills section (section index)"
else
  fail "docs/skills/README.md missing from Skills section"
fi
if printf '%s\n' "$INTERNAL_BLOCK" | grep -q '"docs/skills/README.md"'; then
  fail "docs/skills/README.md wrongly classified into Internal"
else
  pass "docs/skills/README.md not classified as Internal"
fi

# Internal/optional dirs must be excluded — this is an onboarding viewer.
for dir in plans reports evals issues tracking; do
  if grep -q "\"docs/$dir/" "$REGISTRY"; then
    fail "catalog includes docs/$dir/ entries (must be excluded — internal artifacts)"
  else
    pass "catalog excludes docs/$dir/"
  fi
done

# Phase 5 dependency.
if grep -q '"docs/guides/inspecting-and-monitoring.md"' "$REGISTRY"; then
  pass "catalog includes docs/guides/inspecting-and-monitoring.md (Phase 5 dep)"
else
  fail "catalog missing docs/guides/inspecting-and-monitoring.md"
fi

# Per-section path-ordering check: within each section block, the
# extracted paths must be ascending — EXCEPT sections listed in
# SECTION_ORDER (scripts/build-catalog.sh), which use a curated order.
# Curated sections instead assert a verbatim sequence.
SORT_CHECK_OUT=$(awk '
  /section: "(Guides|Execution|Planning & Design|Quality Assurance|Automation|Reporting|Utilities)"/ { skip_sec=1; in_sec=1; n=0; next }
  /section: "/         { skip_sec=0; in_sec=1; n=0; next }
  in_sec && /^    \]/ {
    if (!skip_sec) {
      sorted=1
      for (i=2; i<=n; i++) {
        if (paths[i-1] > paths[i]) { sorted=0; bad=paths[i-1]" > "paths[i]; break }
      }
      if (!sorted) { print "UNSORTED: "bad; exit 1 }
    }
    in_sec=0; n=0; next
  }
  in_sec && /path: "/  {
    match($0, /path: "[^"]+"/); s=substr($0, RSTART+7, RLENGTH-8); n++; paths[n]=s
  }
' "$REGISTRY")
if [ -z "$SORT_CHECK_OUT" ]; then
  pass "all non-curated sections sorted by path ascending"
else
  fail "section path-order broken: $SORT_CHECK_OUT"
fi

# Curated Guides order — assert verbatim sequence matches the canonical
# importance order (Overview first, then the install / workflow / ops
# triad, then the niche references).
EXPECTED_GUIDES_PATHS='docs/guides/README.md
docs/guides/installing-zskills.md
docs/guides/workflows.md
docs/guides/inspecting-and-monitoring.md
docs/guides/zskills-config.md
docs/guides/switching-install-lanes.md
docs/guides/tracking-overview.md'
ACTUAL_GUIDES_PATHS=$(awk '
  /section: "Guides"/  { in_sec=1; next }
  in_sec && /^    \]/  { exit }
  in_sec && /path: "/  {
    match($0, /path: "[^"]+"/); print substr($0, RSTART+7, RLENGTH-8)
  }
' "$REGISTRY")
if [ "$ACTUAL_GUIDES_PATHS" = "$EXPECTED_GUIDES_PATHS" ]; then
  pass "Guides section follows curated importance order"
else
  fail "Guides curated order drift: expected
$EXPECTED_GUIDES_PATHS
got
$ACTUAL_GUIDES_PATHS"
fi

# Guides README is renamed to "Overview" (curated display-name override).
if grep -qE '\{ name: "Overview", path: "docs/guides/README.md" \}' "$REGISTRY"; then
  pass 'docs/guides/README.md displays as "Overview" (curated rename)'
else
  fail 'expected curated display-name override for docs/guides/README.md → "Overview"'
fi

# Trailing newline + no CRLF.
if [ "$(tail -c1 "$REGISTRY" | od -An -c | tr -d ' ')" = "\\n" ]; then
  pass "trailing newline at EOF"
else
  fail "missing trailing newline at EOF"
fi
if grep -q $'\r' "$REGISTRY"; then
  fail "CRLF line endings detected (must be LF)"
else
  pass "LF line endings only (no CRLF)"
fi

# Registered in run-all.sh.
if grep -q "test-doc-viewer-catalog.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-doc-viewer-catalog.sh"
else
  fail "tests/run-all.sh missing test-doc-viewer-catalog.sh registration"
fi

print_summary_and_exit
