#!/bin/bash
# Tests for the DOC_VIEWER Phase 2a viewer shell:
#   docs/index.html, docs/docs-app.js, docs/DocsRegistry.js
#
# Two layers:
#   1. Static-grep contracts — assert the lift + strips landed cleanly
#      (Phase 2a's positive ACs + the negative ACs that pin the
#      Phase 2a / Phase 2b split).
#   2. Node-DOM sanity smoke — import docs-app.js under a minimal DOM
#      stub, mock fetch to return '# H', drive the upstream eager
#      initial-load path (which calls loadDoc on the first catalog
#      item), and assert main.innerHTML contains the rendered <h1>.
#      This gates the L101-173 replacement plus the frontmatter
#      helpers' presence — a missing renderFrontmatterStrip or
#      stripFrontmatter would produce a ReferenceError on first paint
#      and the smoke fails closed.
#
# Run from repo root: bash tests/test-doc-viewer-shell.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INDEX_HTML="$REPO_ROOT/docs/index.html"
APP_JS="$REPO_ROOT/docs/docs-app.js"
REGISTRY="$REPO_ROOT/docs/DocsRegistry.js"
RENDERER="$REPO_ROOT/docs/MarkdownRenderer.js"

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

FOURZEROFOUR="$REPO_ROOT/docs/404.html"

for f in "$INDEX_HTML" "$APP_JS" "$REGISTRY" "$RENDERER"; do
  if [ ! -f "$f" ]; then
    fail "expected file exists: $f"
    print_summary_and_exit
  fi
done
pass "docs/index.html, docs/docs-app.js, docs/DocsRegistry.js, docs/MarkdownRenderer.js all exist"

# Post-deploy fix: docs/404.html is the GitHub Pages fallback that rewrites
# /docs/<subdir>/ misses into a viewer hash route.
if [ -f "$FOURZEROFOUR" ]; then
  pass "docs/404.html exists (GH Pages subpath fallback)"
else
  fail "docs/404.html missing — needed for /docs/<subdir>/ → viewer hash redirect"
fi

# ---------------------------------------------------------------------------
# Static-grep contracts — index.html
# ---------------------------------------------------------------------------

_grep_count() {
  # grep -c with `set -u` and a non-matching file exits non-zero; capture
  # the count cleanly without conditional `|| echo` (which doubles the
  # output when grep ALSO prints 0 to stdout).
  local pattern="$1" file="$2"
  local n
  n=$(grep -c -- "$pattern" "$file" 2>/dev/null)
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

# Password gate / newsletter / robots — all stripped. The favicon is now
# linked (Z glyph for the doc viewer) and asserted present below.
assert_count_eq "index.html: no zl-gate" "$INDEX_HTML" "zl-gate" 0
assert_count_eq "index.html: no Password gate comment" "$INDEX_HTML" "Password gate" 0
assert_count_eq "index.html: no robots meta" "$INDEX_HTML" 'name="robots"' 0
assert_count_ge "index.html: favicon.svg linked" "$INDEX_HTML" "favicon.svg" 1
assert_count_eq "index.html: favicon link tag present" "$INDEX_HTML" 'rel="icon"' 1

# CSS path: absolute /docs/docs.css replaced with sibling-relative ./docs.css.
assert_count_eq "index.html: no absolute /docs/docs.css" "$INDEX_HTML" 'href="/docs/docs.css"' 0
assert_count_eq "index.html: sibling-relative ./docs.css present" "$INDEX_HTML" 'href="./docs.css"' 1

# Direct module script (no async unlock loader).
assert_count_eq "index.html: <script type=\"module\"> present" "$INDEX_HTML" '<script type="module"' 1

# Post-deploy fix: header logo must NOT link to '/' (wrong under path-prefixed
# deploys like /zskills-dev/docs/). Route through the viewer hash instead.
assert_count_eq "index.html: header logo does NOT use href=\"/\"" \
  "$INDEX_HTML" 'class="zl-docs-logo"' 1
got_logo_root=$(_grep_count 'href="/" class="zl-docs-logo"' "$INDEX_HTML")
if [ "$got_logo_root" = "0" ]; then
  pass "index.html: header logo does not have href=\"/\" (path-prefixed-deploy safe)"
else
  fail "index.html: header logo still has href=\"/\" (breaks under path-prefixed deploy)"
fi
assert_count_ge "index.html: header logo routes through viewer hash" \
  "$INDEX_HTML" 'href="#docs/README.md"' 1

# Post-deploy fix: 404.html redirect script semantics.
assert_count_ge "docs/404.html: redirects via location.replace" \
  "$FOURZEROFOUR" "location.replace" 1
assert_count_ge "docs/404.html: builds viewer hash with '#docs/' prefix" \
  "$FOURZEROFOUR" "#docs/" 1
assert_count_ge "docs/404.html: handles trailing-slash directories via README.md" \
  "$FOURZEROFOUR" "README.md" 1

# ---------------------------------------------------------------------------
# Static-grep contracts — docs-app.js
# ---------------------------------------------------------------------------

# Newsletter logic fully stripped.
assert_count_eq "docs-app.js: no isNewsletter" "$APP_JS" "isNewsletter" 0
# examples/ folder branch stripped.
assert_count_eq "docs-app.js: no examples/" "$APP_JS" "examples/" 0

# Frontmatter helpers both present.
assert_count_eq "docs-app.js: stripFrontmatter defined" "$APP_JS" "function stripFrontmatter" 1
assert_count_eq "docs-app.js: renderFrontmatterStrip defined" "$APP_JS" "function renderFrontmatterStrip" 1
# Single-line renderer call site uses both helpers.
assert_count_eq "docs-app.js: renderer call site uses both helpers" "$APP_JS" \
  "renderFrontmatterStrip(md) + renderMarkdown(stripFrontmatter(md)" 1

# Phase 2b ACs — upstream eager/direct-call shape was REMOVED, hash routing
# was ADDED. These assertions used to be inverted (Phase 2a pinned the
# upstream-preserved shape and asserted Phase 2b territory was absent);
# Phase 2b flipped them. The Phase 2b routing test
# (test-doc-viewer-routing.sh) is the deeper coverage; we keep these as a
# fast smoke at this layer too.
_grep_count_re() {
  local pattern="$1" file="$2"
  local n
  n=$(grep -cE -- "$pattern" "$file" 2>/dev/null)
  if [ -z "$n" ]; then n=0; fi
  printf '%s' "$n"
}

assert_count_eq "docs-app.js: upstream eager fallback (DOCS_CATALOG[0]) REMOVED" "$APP_JS" \
  'DOCS_CATALOG\[0\]' 0
assert_count_eq "docs-app.js: upstream sidebar direct call (loadDoc(item, link)) REMOVED" "$APP_JS" \
  'loadDoc(item, link)' 0
assert_count_eq "docs-app.js: upstream main-click direct loadDoc REMOVED" "$APP_JS" \
  'loadDoc(item, navItems\[idx\])' 0

got=$(_grep_count_re 'hashchange|popstate|DOMContentLoaded' "$APP_JS")
if [ "$got" -ge "3" ]; then
  pass "docs-app.js: 3 routing listeners wired (hashchange/popstate/DOMContentLoaded; got $got)"
else
  fail "docs-app.js: expected ≥3 routing listener wires, got $got"
fi

assert_count_eq "docs-app.js: routeFromHash defined" "$APP_JS" "function routeFromHash" 1
assert_count_eq "docs-app.js: renderErrorPane defined" "$APP_JS" "function renderErrorPane" 1
assert_count_eq "docs-app.js: resolveLink defined" "$APP_JS" "function resolveLink" 1

got=$(_grep_count_re 'import \{[^}]*\bescapeHtml\b[^}]*\}' "$APP_JS")
if [ "$got" -ge "1" ]; then
  pass "docs-app.js: escapeHtml imported from MarkdownRenderer"
else
  fail "docs-app.js: escapeHtml import missing (got $got, expected ≥1)"
fi

# Imports are sibling-relative (no ../src/ui path).
got=$(_grep_count_re "from '\.\./src/ui/" "$APP_JS")
if [ "$got" = "0" ]; then
  pass "docs-app.js: no ../src/ui/ imports (sibling-relative form)"
else
  fail "docs-app.js: stale ../src/ui/ imports present (got $got, expected 0)"
fi

# ---------------------------------------------------------------------------
# Node: DocsRegistry import + 1-section × 5-item shape
# ---------------------------------------------------------------------------

if ! command -v node >/dev/null 2>&1; then
  fail "node not available — DOM tests skipped"
  print_summary_and_exit
fi

REGISTRY_JSON=$(REGISTRY="$REGISTRY" node --input-type=module -e "
const m = await import(process.env.REGISTRY);
process.stdout.write(JSON.stringify(m.DOCS_CATALOG));
" 2>&1) || true

if [ -z "$REGISTRY_JSON" ] || ! echo "$REGISTRY_JSON" | grep -q '"section":"Start here"'; then
  fail "DocsRegistry.js: import succeeds and exports DOCS_CATALOG with 'Start here' section"
  echo "    raw output: $REGISTRY_JSON"
else
  pass "DocsRegistry.js: import succeeds and exports DOCS_CATALOG with 'Start here' section"
fi

# Count items (crude grep on the dumped JSON).
# Phase 2a shipped a 5-item stub; Phase 4 replaced it with the generated
# catalog (~170+ items). The stub-pin migrated to a floor check; the
# byte-determinism + drift gate lives in test-doc-viewer-catalog.sh.
item_count=$(echo "$REGISTRY_JSON" | grep -o '"path":"[^"]*"' | wc -l | tr -d ' ')
if [ "$item_count" -ge 5 ]; then
  pass "DocsRegistry.js: catalog has $item_count items (>= 5 — Phase 4 generated catalog)"
else
  fail "DocsRegistry.js: expected >= 5 items, got $item_count"
fi

for path in \
  "docs/README.md" \
  "docs/guides/workflows.md" \
  "docs/guides/installing-zskills.md" \
  "docs/skills/README.md" \
  "docs/guides/inspecting-and-monitoring.md" \
; do
  if echo "$REGISTRY_JSON" | grep -q "\"path\":\"$path\""; then
    pass "DocsRegistry.js: catalog includes $path"
  else
    fail "DocsRegistry.js: catalog missing $path"
  fi
done

# ---------------------------------------------------------------------------
# Node: Sanity smoke — load docs-app.js under a DOM stub, mock fetch,
# drive the Phase 2b DOMContentLoaded → routeFromHash → loadDoc path,
# assert main.innerHTML contains <h1.
#
# Phase 2a's eager top-of-file loadDoc call was removed by Phase 2b in
# favour of a DOMContentLoaded listener. We capture listeners via stubbed
# document/window addEventListener, import the app, then synthesize the
# DOMContentLoaded fire to drive the load path.
# ---------------------------------------------------------------------------

SMOKE_OUT=$(APP_JS="$APP_JS" RENDERER="$RENDERER" REGISTRY="$REGISTRY" \
  node --input-type=module -e "
// --- minimal DOM stub ---
function makeEl(tag) {
  const el = {
    tagName: (tag || 'div').toUpperCase(),
    className: '',
    textContent: '',
    innerHTML: '',
    href: '',
    children: [],
    _attrs: {},
    appendChild(c) { this.children.push(c); return c; },
    removeChild(c) { this.children = this.children.filter(x => x !== c); return c; },
    addEventListener() {},
    removeEventListener() {},
    setAttribute(k, v) { this._attrs[k] = String(v); },
    getAttribute(k) { return this._attrs[k] == null ? null : this._attrs[k]; },
    querySelector(sel) {
      // Match either '.cls' or 'tag[attr=\"val\"]' selectors.
      const attrMatch = sel.match(/^([a-z]+)\\[([a-z-]+)=\"([^\"]+)\"\\]$/);
      if (attrMatch) {
        const [, tag, attr, val] = attrMatch;
        for (const c of this.children) {
          if (c.tagName === tag.toUpperCase() && c._attrs[attr] === val) return c;
        }
        return null;
      }
      const cls = sel.replace(/^\./, '');
      for (const c of this.children) {
        if ((c.className || '').split(/\s+/).indexOf(cls) >= 0) return c;
      }
      return null;
    },
    querySelectorAll(sel) {
      const cls = sel.replace(/^\./, '');
      const out = [];
      for (const c of this.children) {
        if ((c.className || '').split(/\s+/).indexOf(cls) >= 0) out.push(c);
      }
      return out;
    },
    classList: {
      _classes: new Set(),
      add(c) { this._classes.add(c); },
      remove(c) { this._classes.delete(c); },
      contains(c) { return this._classes.has(c); },
    },
    scrollIntoView() {},
    closest() { return null; },
  };
  return el;
}

const nav = makeEl('nav');
const main = makeEl('main');
const elements = { 'zl-docs-nav': nav, 'zl-docs-main': main };

// Capture document + window event listeners so we can fire DOMContentLoaded
// synthetically after import.
const docListeners = {};
const winListeners = {};
global.document = {
  getElementById(id) { return elements[id] || null; },
  createElement(tag) { return makeEl(tag); },
  querySelector() { return null; },
  addEventListener(ev, fn) { (docListeners[ev] = docListeners[ev] || []).push(fn); },
};
global.window = {
  addEventListener(ev, fn) { (winListeners[ev] = winListeners[ev] || []).push(fn); },
};
global.location = { hash: '' };
global.history = { replaceState() {} };

// Mock fetch — return '# H' for any URL.
global.fetch = async (url) => ({
  ok: true,
  status: 200,
  text: async () => '# H',
});

// Import the app — module top-level builds the sidebar and registers
// listeners; no eager loadDoc fires.
await import(process.env.APP_JS);

// Synthesize the DOMContentLoaded fire that drives the initial load.
for (const fn of (docListeners.DOMContentLoaded || [])) fn();

// loadDoc is async; flush microtasks so the fetch + render lands before
// we read main.innerHTML.
await new Promise(r => setImmediate(r));
await new Promise(r => setImmediate(r));
await new Promise(r => setImmediate(r));

const out = main.innerHTML || '';
process.stdout.write('SMOKE_HTML_START\n' + out + '\nSMOKE_HTML_END\n');
" 2>&1) || true

# Extract the rendered HTML between markers.
RENDERED=$(echo "$SMOKE_OUT" | awk '/^SMOKE_HTML_START$/{flag=1; next} /^SMOKE_HTML_END$/{flag=0} flag')

if echo "$SMOKE_OUT" | grep -q 'ReferenceError'; then
  fail "smoke: ReferenceError during import/render (likely missing helper) — output: $SMOKE_OUT"
elif [ -z "$RENDERED" ]; then
  fail "smoke: no rendered output between markers — full output: $SMOKE_OUT"
else
  if echo "$RENDERED" | grep -q '<h1'; then
    pass "smoke: main.innerHTML contains <h1 after eager loadDoc on first catalog item"
  else
    fail "smoke: expected <h1 in main.innerHTML; got: $RENDERED"
  fi
  # The Phase 1 renderer slugifies 'H' to 'h', so id="h".
  if echo "$RENDERED" | grep -q 'id="h"'; then
    pass "smoke: <h1> carries id=\"h\" (Phase 1 slugify spec)"
  else
    fail "smoke: expected id=\"h\" on <h1>; got: $RENDERED"
  fi
  if echo "$RENDERED" | grep -q '>H</h1>'; then
    pass "smoke: <h1> text body is 'H'"
  else
    fail "smoke: expected >H</h1>; got: $RENDERED"
  fi
fi

# ---------------------------------------------------------------------------
# Conformance: tests/run-all.sh registers this file.
# ---------------------------------------------------------------------------

if grep -q "test-doc-viewer-shell.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-doc-viewer-shell.sh"
else
  fail "tests/run-all.sh missing test-doc-viewer-shell.sh registration"
fi

print_summary_and_exit
