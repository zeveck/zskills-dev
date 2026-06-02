#!/bin/bash
# Tests for the DOC_VIEWER Phase 3 styling layer:
#   docs/docs.css, docs/index.html (FOUC + toggle), docs/docs-app.js (toggle wiring).
#
# Static-grep contracts only at this layer. The FOUC inline-script lives in
# index.html (not a standalone .js), so a Node-DOM extract-and-exec is
# deferred to v2 — the static asserts catch the realistic regression surface
# (someone deleting one of the load-bearing operations).
#
# Run from repo root: bash tests/test-doc-viewer-styling.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INDEX_HTML="$REPO_ROOT/docs/index.html"
APP_JS="$REPO_ROOT/docs/docs-app.js"
CSS="$REPO_ROOT/docs/docs.css"
NOJEKYLL="$REPO_ROOT/.nojekyll"

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

# ---------------------------------------------------------------------------
# Required-file presence
# ---------------------------------------------------------------------------
for f in "$CSS" "$INDEX_HTML" "$APP_JS"; do
  if [ ! -f "$f" ]; then
    fail "expected file exists: $f"
    print_summary_and_exit
  fi
done
pass "docs/docs.css, docs/index.html, docs/docs-app.js all exist"

if [ -f "$NOJEKYLL" ]; then
  pass ".nojekyll exists at repo root"
else
  fail ".nojekyll missing at repo root (required for GitHub Pages to serve docs/)"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_grep_count() {
  local pattern="$1" file="$2"
  local n
  n=$(grep -c -- "$pattern" "$file" 2>/dev/null)
  if [ -z "$n" ]; then n=0; fi
  printf '%s' "$n"
}

_grep_count_re() {
  local pattern="$1" file="$2"
  local n
  n=$(grep -cE -- "$pattern" "$file" 2>/dev/null)
  if [ -z "$n" ]; then n=0; fi
  printf '%s' "$n"
}

assert_count_eq() {
  local label="$1" file="$2" pattern="$3" expected="$4"
  local got
  got=$(_grep_count "$pattern" "$file")
  if [ "$got" = "$expected" ]; then
    pass "$label (grep -c '$pattern' = $expected)"
  else
    fail "$label (expected $expected, got $got for pattern '$pattern' in $file)"
  fi
}

assert_count_ge() {
  local label="$1" file="$2" pattern="$3" expected="$4"
  local got
  got=$(_grep_count "$pattern" "$file")
  if [ "$got" -ge "$expected" ]; then
    pass "$label (grep -c '$pattern' = $got, expected >= $expected)"
  else
    fail "$label (expected >= $expected, got $got for pattern '$pattern' in $file)"
  fi
}

# ---------------------------------------------------------------------------
# docs.css — dual-palette structure
# ---------------------------------------------------------------------------
# Exactly one :root block + one [data-theme="light"] block.
got_root=$(_grep_count_re '^:root \{' "$CSS")
if [ "$got_root" -ge "1" ]; then
  pass "docs.css: :root block present ($got_root match)"
else
  fail "docs.css: missing :root block"
fi

got_light=$(_grep_count_re '^\[data-theme="light"\] \{' "$CSS")
if [ "$got_light" -ge "1" ]; then
  pass "docs.css: [data-theme=\"light\"] overlay present ($got_light match)"
else
  fail "docs.css: missing [data-theme=\"light\"] overlay"
fi

# The 9 viewer-relevant variables must appear in BOTH palette blocks.
# Each variable should appear at least twice (once per palette).
for var in --bg --panel --panel2 --ink --muted --line --accent --accent2 --code; do
  got=$(_grep_count_re "^\s*${var}: *#" "$CSS")
  if [ "$got" -ge "2" ]; then
    pass "docs.css: $var defined in BOTH palettes (count=$got)"
  else
    fail "docs.css: $var must be defined in both :root and [data-theme=\"light\"] (count=$got, expected >= 2)"
  fi
done

# Upstream variable names must be fully rewritten — no --color-* remnants.
got_color=$(_grep_count_re -- '--color-[a-z-]+' "$CSS")
if [ "$got_color" = "0" ]; then
  pass "docs.css: no stale --color-* variable references"
else
  fail "docs.css: stale --color-* references present (count=$got_color)"
fi

# Newsletter block fully stripped.
assert_count_eq "docs.css: no zl-docs-newsletter-header rule" "$CSS" \
  "zl-docs-newsletter-header" 0
assert_count_eq "docs.css: no zl-docs-toc rule" "$CSS" \
  "zl-docs-toc" 0

# Responsive @media block PRESERVED from upstream.
got_media=$(_grep_count_re '@media \(max-width: 768px\)' "$CSS")
if [ "$got_media" -ge "1" ]; then
  pass "docs.css: responsive @media block preserved"
else
  fail "docs.css: upstream @media (max-width: 768px) block missing"
fi

# Split remap (R#4): nav-item hover/active uses --panel2; <code>/<pre> uses --code.
# Coarse check: both --panel2 and --code are referenced via var(...) in the rules.
got_panel2_use=$(_grep_count_re 'var\(--panel2\)' "$CSS")
if [ "$got_panel2_use" -ge "2" ]; then
  pass "docs.css: var(--panel2) used >= 2 times (nav hover + active)"
else
  fail "docs.css: expected >= 2 var(--panel2) uses (nav hover/active); got $got_panel2_use"
fi
got_code_use=$(_grep_count_re 'var\(--code\)' "$CSS")
if [ "$got_code_use" -ge "2" ]; then
  pass "docs.css: var(--code) used >= 2 times (inline code + pre block)"
else
  fail "docs.css: expected >= 2 var(--code) uses (inline + pre); got $got_code_use"
fi

# ---------------------------------------------------------------------------
# index.html — FOUC inline script BEFORE <link rel="stylesheet">
# ---------------------------------------------------------------------------
inline_line=$(grep -n 'setAttribute.*data-theme\|data-theme.*setAttribute' "$INDEX_HTML" | head -1 | cut -d: -f1)
# Match the actual <link …rel="stylesheet"…> element — NOT the prose mention
# inside the HTML comment that documents the FOUC-ordering contract above it.
link_line=$(grep -nE '^[[:space:]]*<link[^>]*rel="stylesheet"' "$INDEX_HTML" | head -1 | cut -d: -f1)

if [ -z "$inline_line" ]; then
  fail "index.html: FOUC inline script not found (no setAttribute('data-theme', ...) line)"
elif [ -z "$link_line" ]; then
  fail "index.html: <link rel=\"stylesheet\"> not found"
elif [ "$inline_line" -lt "$link_line" ]; then
  pass "index.html: FOUC inline script (line $inline_line) appears before <link rel=\"stylesheet\"> (line $link_line)"
else
  fail "index.html: FOUC ordering violated — inline script line $inline_line, stylesheet line $link_line"
fi

# Inline-script semantic operations (3 grep assertions per plan v1):
#   (i)   reads localStorage key 'zskills-docs-theme'
#   (ii)  writes data-theme via document.documentElement.setAttribute
#   (iii) queries prefers-color-scheme via window.matchMedia
assert_count_ge "index.html: inline reads localStorage zskills-docs-theme" \
  "$INDEX_HTML" "localStorage.getItem('zskills-docs-theme')" 1
assert_count_ge "index.html: inline sets data-theme via documentElement.setAttribute" \
  "$INDEX_HTML" "document.documentElement.setAttribute" 1
assert_count_ge "index.html: inline queries prefers-color-scheme via matchMedia" \
  "$INDEX_HTML" "window.matchMedia('(prefers-color-scheme: dark)')" 1

# Toggle button: id + aria-label.
assert_count_ge "index.html: toggle button #zl-docs-theme-toggle present" \
  "$INDEX_HTML" 'id="zl-docs-theme-toggle"' 1
assert_count_ge "index.html: toggle button carries aria-label" \
  "$INDEX_HTML" 'aria-label="Theme:' 1

# ---------------------------------------------------------------------------
# docs-app.js — theme wiring
# ---------------------------------------------------------------------------
assert_count_ge "docs-app.js: reads localStorage key zskills-docs-theme" \
  "$APP_JS" "zskills-docs-theme" 1
assert_count_ge "docs-app.js: defines applyTheme" \
  "$APP_JS" "function applyTheme" 1
assert_count_ge "docs-app.js: defines cycleTheme (3-state cycle)" \
  "$APP_JS" "function cycleTheme" 1

# 3-state ordering literal — light → dark → system.
got_states=$(_grep_count_re "'light', 'dark', 'system'" "$APP_JS")
if [ "$got_states" -ge "1" ]; then
  pass "docs-app.js: THEME_STATES literal ['light','dark','system'] present"
else
  fail "docs-app.js: expected ['light','dark','system'] state literal"
fi

# matchMedia change listener for system-mode tracking.
assert_count_ge "docs-app.js: matchMedia change listener wired" \
  "$APP_JS" "addEventListener('change', applyTheme)" 1

# ---------------------------------------------------------------------------
# Conformance: tests/run-all.sh registers this file.
# ---------------------------------------------------------------------------
if grep -q "test-doc-viewer-styling.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-doc-viewer-styling.sh"
else
  fail "tests/run-all.sh missing test-doc-viewer-styling.sh registration"
fi

print_summary_and_exit
