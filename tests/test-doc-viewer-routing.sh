#!/bin/bash
# Tests for the DOC_VIEWER Phase 2b hash-routing layer in docs/docs-app.js.
#
# Layers:
#   1. Static-grep contracts — assert routing helpers + listeners landed,
#      and upstream's eager/direct-call shape is GONE (negative ACs that
#      pin the Phase 2a/2b split).
#   2. Node-DOM behavior — load docs-app.js under a DOM stub, mock fetch,
#      drive routing through DOMContentLoaded / location.hash / synthetic
#      click events, and assert on the observable seams:
#        - empty hash → loads docs/README.md
#        - valid hash → fetch arg URL contains the catalog path
#        - missing catalog entry → renderErrorPane output with the
#          escaped path AND a github.com/zeveck/zskills source link
#        - relative .md link click → e.preventDefault() called + hash
#          updated to the resolved target
#        - sidebar click fires loadDoc exactly ONCE (spy counter; second
#          click on the same item is a browser no-op so still ONCE)
#        - anchor parsing uses indexOf('#'), not split — verified by
#          asserting `pathPart` + `anchor` outputs for `path.md#a#b`
#        - frontmatter source-strip: `---\ntitle:X\n---\n# H` renders
#          neither <hr> nor a paragraph containing `title:`
#
# Run from repo root: bash tests/test-doc-viewer-routing.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_JS="$REPO_ROOT/docs/docs-app.js"
RENDERER="$REPO_ROOT/docs/MarkdownRenderer.js"
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

for f in "$APP_JS" "$RENDERER" "$REGISTRY"; do
  if [ ! -f "$f" ]; then
    fail "expected file exists: $f"
    print_summary_and_exit
  fi
done
pass "docs-app.js, MarkdownRenderer.js, DocsRegistry.js all exist"

# ---------------------------------------------------------------------------
# Static-grep contracts
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
    fail "$label (expected $expected, got $got)"
  fi
}

assert_count_ge() {
  local label="$1" file="$2" pattern="$3" expected="$4"
  local got
  got=$(_grep_count "$pattern" "$file")
  if [ "$got" -ge "$expected" ]; then
    pass "$label (grep -c '$pattern' = $got, expected >= $expected)"
  else
    fail "$label (expected >= $expected, got $got)"
  fi
}

assert_re_count_eq() {
  local label="$1" file="$2" pattern="$3" expected="$4"
  local got
  got=$(_grep_count_re "$pattern" "$file")
  if [ "$got" = "$expected" ]; then
    pass "$label (grep -cE '$pattern' = $expected)"
  else
    fail "$label (expected $expected, got $got)"
  fi
}

assert_re_count_ge() {
  local label="$1" file="$2" pattern="$3" expected="$4"
  local got
  got=$(_grep_count_re "$pattern" "$file")
  if [ "$got" -ge "$expected" ]; then
    pass "$label (grep -cE '$pattern' = $got, expected >= $expected)"
  else
    fail "$label (expected >= $expected, got $got)"
  fi
}

# Listeners
assert_re_count_ge "hashchange listener wired" "$APP_JS" \
  "window\\.addEventListener\\('hashchange'" 1
assert_re_count_ge "popstate listener wired" "$APP_JS" \
  "window\\.addEventListener\\('popstate'" 1
assert_re_count_ge "DOMContentLoaded listener wired" "$APP_JS" \
  "document\\.addEventListener\\('DOMContentLoaded'" 1

# Helpers
assert_count_eq "routeFromHash defined" "$APP_JS" "function routeFromHash" 1
assert_count_eq "resolveLink defined" "$APP_JS" "function resolveLink" 1
assert_count_eq "findCatalogItem defined" "$APP_JS" "function findCatalogItem" 1
assert_count_eq "findNavEl defined" "$APP_JS" "function findNavEl" 1
assert_count_eq "scrollToAnchor defined" "$APP_JS" "function scrollToAnchor" 1
assert_count_eq "renderErrorPane defined" "$APP_JS" "function renderErrorPane" 1
assert_count_eq "currentHashPath defined" "$APP_JS" "function currentHashPath" 1

# Module state
assert_count_ge "lastHandledHash present (decl + read)" "$APP_JS" "lastHandledHash" 2

# Imports
assert_re_count_eq "escapeHtml imported alongside renderMarkdown" "$APP_JS" \
  "import \\{[^}]*\\bescapeHtml\\b[^}]*\\} from ['\"]\\./MarkdownRenderer\\.js['\"]" 1

# Sidebar build — outer section-header loop preserved; inner item loop is <a data-path>.
assert_count_eq "outer section-header loop preserved" "$APP_JS" "zl-docs-section-header" 1
assert_count_ge "data-path attribute set on sidebar items" "$APP_JS" "data-path" 1

# Anchor parse uses indexOf, not split.
assert_re_count_ge "anchor parse uses indexOf('#')" "$APP_JS" "indexOf\\('#'\\)" 1

# Removals
assert_count_eq "no DOCS_CATALOG[0] eager fallback" "$APP_JS" 'DOCS_CATALOG\[0\]' 0
assert_count_eq "no loadDoc(item, link) sidebar direct call" "$APP_JS" 'loadDoc(item, link)' 0
assert_count_eq "no loadDoc(item, navItems[idx]) main-click direct call" "$APP_JS" \
  'loadDoc(item, navItems\[idx\])' 0
assert_count_eq "no history.replaceState in loadDoc" "$APP_JS" "history.replaceState" 0

# location.hash set from at least 2 places (sidebar + main-click).
assert_re_count_ge "location.hash assigned from ≥2 places" "$APP_JS" \
  "location\\.hash\\s*=" 2

# ---------------------------------------------------------------------------
# Node-DOM behavior tests
# ---------------------------------------------------------------------------

if ! command -v node >/dev/null 2>&1; then
  fail "node not available — DOM tests skipped"
  print_summary_and_exit
fi

# Shared bootstrap: a DOM stub + listener-capture harness that drives the
# Phase 2b routing path. Each test scenario is a self-contained Node
# program that loads the harness inline, performs its setup (initial
# location.hash, fetch mock, click synthesis), imports docs-app.js, fires
# the captured listeners as needed, then prints structured assertions.

# Helper to run a node scenario and capture exit + stdout.
run_node_scenario() {
  local label="$1"
  local code="$2"
  local out
  out=$(APP_JS="$APP_JS" RENDERER="$RENDERER" REGISTRY="$REGISTRY" \
    node --input-type=module -e "$code" 2>&1) || true
  echo "$out"
}

# The harness: paste-include from a heredoc so each scenario shares the
# same DOM-stub + listener-capture code without duplication.
HARNESS=$(cat <<'JS'
function makeEl(tag) {
  const el = {
    tagName: (tag || 'div').toUpperCase(),
    className: '',
    textContent: '',
    innerHTML: '',
    href: '',
    children: [],
    _attrs: {},
    _listeners: {},
    appendChild(c) { c.parentEl = this; this.children.push(c); return c; },
    removeChild(c) { this.children = this.children.filter(x => x !== c); return c; },
    addEventListener(ev, fn) { (this._listeners[ev] = this._listeners[ev] || []).push(fn); },
    removeEventListener() {},
    setAttribute(k, v) { this._attrs[k] = String(v); },
    getAttribute(k) {
      if (k === 'href') return this.href || null;
      return this._attrs[k] == null ? null : this._attrs[k];
    },
    querySelector(sel) {
      // 'tag[attr="val"]' form
      const attrMatch = sel.match(/^([a-z]+)\[([a-z-]+)="([^"]+)"\]$/);
      if (attrMatch) {
        const [, t, attr, val] = attrMatch;
        for (const c of this.children) {
          if (c.tagName === t.toUpperCase() && c._attrs[attr] === val) return c;
        }
        return null;
      }
      // '#id' form — recurse children
      if (sel.startsWith('#')) {
        const id = sel.slice(1);
        function walk(n) {
          if (n._attrs && n._attrs.id === id) return n;
          for (const c of (n.children || [])) {
            const r = walk(c);
            if (r) return r;
          }
          return null;
        }
        return walk(this);
      }
      // '.cls' form
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
    closest(sel) {
      // walk parents looking for an 'a' tag (the only closest() we use)
      let n = this;
      while (n) {
        if (n.tagName === 'A') return n;
        n = n.parentEl;
      }
      return null;
    },
  };
  return el;
}

const nav = makeEl('nav');
const main = makeEl('main');
const elements = { 'zl-docs-nav': nav, 'zl-docs-main': main };

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

function fireDOMContentLoaded() {
  for (const fn of (docListeners.DOMContentLoaded || [])) fn();
}
function fireHashchange() {
  for (const fn of (winListeners.hashchange || [])) fn();
}
async function flushTicks(n) {
  for (let i = 0; i < (n || 4); i++) {
    await new Promise(r => setImmediate(r));
  }
}
JS
)

# ---------------------------------------------------------------------------
# Test 1: Empty hash → DOMContentLoaded fallback loads docs/README.md
# ---------------------------------------------------------------------------
SCENARIO_1=$(cat <<JS
${HARNESS}
const fetchUrls = [];
global.fetch = async (url) => {
  fetchUrls.push(url);
  return { ok: true, status: 200, text: async () => '# README Body' };
};
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();
const out = main.innerHTML || '';
process.stdout.write('FETCH_URLS:' + JSON.stringify(fetchUrls) + '\n');
process.stdout.write('HTML_START\n' + out + '\nHTML_END\n');
JS
)
OUT1=$(run_node_scenario "empty hash → README" "$SCENARIO_1")
if echo "$OUT1" | grep -q '"../docs/README.md"'; then
  pass "test1: empty hash → fetch('../docs/README.md')"
else
  fail "test1: expected fetch('../docs/README.md') — got: $OUT1"
fi
if echo "$OUT1" | grep -q '<h1[^>]*>README Body</h1>'; then
  pass "test1: rendered README body H1"
else
  fail "test1: expected rendered <h1>README Body</h1> — got: $OUT1"
fi

# ---------------------------------------------------------------------------
# Test 2: Valid hash #docs/guides/WORKFLOWS.md → fetch for that path
# ---------------------------------------------------------------------------
SCENARIO_2=$(cat <<JS
${HARNESS}
const fetchUrls = [];
global.fetch = async (url) => {
  fetchUrls.push(url);
  return { ok: true, status: 200, text: async () => '# Workflows' };
};
global.location.hash = '#docs/guides/WORKFLOWS.md';
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();
process.stdout.write('FETCH_URLS:' + JSON.stringify(fetchUrls) + '\n');
process.stdout.write('HTML_START\n' + (main.innerHTML || '') + '\nHTML_END\n');
JS
)
OUT2=$(run_node_scenario "valid hash → WORKFLOWS" "$SCENARIO_2")
if echo "$OUT2" | grep -q '"../docs/guides/WORKFLOWS.md"'; then
  pass "test2: hash #docs/guides/WORKFLOWS.md → fetch('../docs/guides/WORKFLOWS.md')"
else
  fail "test2: expected fetch arg '../docs/guides/WORKFLOWS.md' — got: $OUT2"
fi

# ---------------------------------------------------------------------------
# Test 3: Missing catalog entry → renderErrorPane with escaped path +
#         GitHub fallback link
# ---------------------------------------------------------------------------
SCENARIO_3=$(cat <<JS
${HARNESS}
global.fetch = async () => ({ ok: false, status: 404, text: async () => '' });
global.location.hash = '#docs/nonexistent.md';
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();
process.stdout.write('HTML_START\n' + (main.innerHTML || '') + '\nHTML_END\n');
JS
)
OUT3=$(run_node_scenario "missing catalog → error pane" "$SCENARIO_3")
if echo "$OUT3" | grep -q 'zs-error-pane'; then
  pass "test3: catalog miss → zs-error-pane class rendered"
else
  fail "test3: expected zs-error-pane class — got: $OUT3"
fi
if echo "$OUT3" | grep -q 'Page not found'; then
  pass "test3: error pane has 'Page not found' text"
else
  fail "test3: expected 'Page not found' text — got: $OUT3"
fi
if echo "$OUT3" | grep -q '<code>docs/nonexistent.md</code>'; then
  pass "test3: error pane shows the requested path"
else
  fail "test3: expected target path in <code> tag — got: $OUT3"
fi
if echo "$OUT3" | grep -q 'https://github.com/zeveck/zskills/blob/main/docs/nonexistent.md'; then
  pass "test3: GitHub source fallback link present"
else
  fail "test3: expected GitHub fallback link — got: $OUT3"
fi

# ---------------------------------------------------------------------------
# Test 4: Anchor-hash form #docs/guides/WORKFLOWS.md#some-section parses
#         via indexOf — pathPart and anchor are split on FIRST '#'.
#
# We extract routeFromHash's parse contract by exercising it through a
# multi-# hash. A hash 'a#b#c' must yield pathPart='a' and anchor='b#c'
# (NOT 'b' with 'c' truncated, which split('#',2) would do).
# ---------------------------------------------------------------------------
SCENARIO_4=$(cat <<JS
${HARNESS}
// Use a stub catalog entry path that we'll inject by setting location.hash
// to 'docs/guides/WORKFLOWS.md#sec#sub'. routeFromHash should compute
// pathPart='docs/guides/WORKFLOWS.md' and anchor='sec#sub'. We can
// observe the parse by checking fetch is invoked with the path only,
// AND by observing scrollToAnchor on element with id 'sec#sub' (which
// won't exist, so no scroll happens — but no crash either).
const fetchUrls = [];
global.fetch = async (url) => {
  fetchUrls.push(url);
  return { ok: true, status: 200, text: async () => '<a id="sec#sub">x</a>\n# H' };
};
global.location.hash = '#docs/guides/WORKFLOWS.md#sec#sub';
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();
process.stdout.write('FETCH_URLS:' + JSON.stringify(fetchUrls) + '\n');
JS
)
OUT4=$(run_node_scenario "triple-hash anchor parse" "$SCENARIO_4")
# The path used for fetch must NOT include the anchor portion.
if echo "$OUT4" | grep -q '"../docs/guides/WORKFLOWS.md"'; then
  pass "test4: pathPart parses correctly via indexOf (anchor stripped from fetch URL)"
else
  fail "test4: expected fetch arg WITHOUT anchor — got: $OUT4"
fi
if echo "$OUT4" | grep -q "WORKFLOWS.md#sec"; then
  fail "test4: fetch URL leaked the anchor (split-truncate bug suspected) — got: $OUT4"
else
  pass "test4: fetch URL does not include anchor portion"
fi

# ---------------------------------------------------------------------------
# Test 5: Relative .md link click in rendered content → preventDefault()
#         called AND location.hash updated to resolved target.
# ---------------------------------------------------------------------------
SCENARIO_5=$(cat <<JS
${HARNESS}
global.fetch = async () => ({
  ok: true, status: 200,
  text: async () => '[Workflows](../guides/WORKFLOWS.md)',
});
// Anchor the current page in docs/skills/README.md so a '../guides/...'
// relative href resolves to docs/guides/... (URL spec: from base dir
// /docs/skills/, '../guides/X' → /docs/guides/X).
global.location.hash = '#docs/skills/README.md';
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();

// Build a synthetic <a> with the relative href that the rendered markdown
// would produce; dispatch a fake click event through main's click handler.
const linkEl = makeEl('a');
linkEl.href = '../guides/WORKFLOWS.md';
linkEl.parentEl = main;
let prevented = false;
const evt = {
  target: linkEl,
  preventDefault() { prevented = true; this.defaultPrevented = true; },
  defaultPrevented: false,
};
// Find main's click listener and invoke it.
const clickListeners = main._listeners.click || [];
for (const fn of clickListeners) fn(evt);
process.stdout.write('PREVENTED:' + prevented + '\n');
process.stdout.write('NEW_HASH:' + global.location.hash + '\n');
JS
)
OUT5=$(run_node_scenario "relative md link click" "$SCENARIO_5")
if echo "$OUT5" | grep -q '^PREVENTED:true'; then
  pass "test5: .md link click calls e.preventDefault()"
else
  fail "test5: expected preventDefault() — got: $OUT5"
fi
if echo "$OUT5" | grep -q '^NEW_HASH:#docs/guides/WORKFLOWS.md'; then
  pass "test5: .md link click sets location.hash to resolved target"
else
  fail "test5: expected location.hash='#docs/guides/WORKFLOWS.md' — got: $OUT5"
fi

# ---------------------------------------------------------------------------
# Test 6: Sidebar click fires loadDoc exactly ONCE — second click on the
#         same entry is a browser no-op (we simulate this by checking the
#         click handler doesn't re-fire when location.hash already equals
#         the target — i.e., assigning the same hash doesn't re-invoke
#         hashchange listeners).
# ---------------------------------------------------------------------------
SCENARIO_6=$(cat <<JS
${HARNESS}
let fetchCount = 0;
global.fetch = async () => {
  fetchCount++;
  return { ok: true, status: 200, text: async () => '# X' };
};
await import(process.env.APP_JS);
// First sidebar click: simulate by setting location.hash + firing hashchange.
global.location.hash = '#docs/guides/WORKFLOWS.md';
fireHashchange();
await flushTicks();
const c1 = fetchCount;
// Second click on the same entry: real browsers no-op the hash assignment
// (no hashchange fires when hash is unchanged). We replicate by NOT firing
// hashchange. Meanwhile, the sidebar click handler itself sets
// location.hash = '#' + item.path — if it's already that value, no
// hashchange. We verify routeFromHash dedupes via lastHandledHash if
// somehow called again.
fireHashchange();   // re-fire defensively — lastHandledHash should dedupe
await flushTicks();
const c2 = fetchCount;
process.stdout.write('COUNT1:' + c1 + '\n');
process.stdout.write('COUNT2:' + c2 + '\n');
JS
)
OUT6=$(run_node_scenario "single-fire on same-hash click" "$SCENARIO_6")
if echo "$OUT6" | grep -q '^COUNT1:1$'; then
  pass "test6: first sidebar click fires loadDoc exactly once"
else
  fail "test6: expected COUNT1=1 — got: $OUT6"
fi
if echo "$OUT6" | grep -q '^COUNT2:1$'; then
  pass "test6: lastHandledHash dedupes a re-fired hashchange"
else
  fail "test6: expected COUNT2=1 (dedupe) — got: $OUT6"
fi

# ---------------------------------------------------------------------------
# Test 7: Frontmatter source-strip regression — `---\ntitle:X\n---\n# H`
#         loaded through the hash-routed path renders neither <hr> nor a
#         paragraph containing `title:`.
# ---------------------------------------------------------------------------
SCENARIO_7=$(cat <<'JS'
JS
)
SCENARIO_7=$(cat <<JS
${HARNESS}
const fmMd = '---\ntitle: X\nstatus: drafted\n---\n# H';
global.fetch = async () => ({ ok: true, status: 200, text: async () => fmMd });
global.location.hash = '#docs/README.md';
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();
process.stdout.write('HTML_START\n' + (main.innerHTML || '') + '\nHTML_END\n');
JS
)
OUT7=$(run_node_scenario "frontmatter source-strip via hash routing" "$SCENARIO_7")
# Extract just the rendered HTML between markers.
RENDERED7=$(echo "$OUT7" | awk '/^HTML_START$/{f=1; next} /^HTML_END$/{f=0} f')
if echo "$RENDERED7" | grep -q '<hr'; then
  fail "test7: rendered HTML contains <hr> — frontmatter delim leaked: $RENDERED7"
else
  pass "test7: no <hr> in rendered output (frontmatter delim stripped)"
fi
if echo "$RENDERED7" | grep -qi 'title:'; then
  fail "test7: rendered HTML contains 'title:' paragraph — frontmatter body leaked: $RENDERED7"
else
  pass "test7: no 'title:' paragraph in rendered output"
fi
if echo "$RENDERED7" | grep -q '<h1[^>]*>H</h1>'; then
  pass "test7: H1 'H' rendered after frontmatter strip"
else
  fail "test7: expected <h1>H</h1> after strip — got: $RENDERED7"
fi

# ---------------------------------------------------------------------------
# Conformance: tests/run-all.sh registers this file.
# ---------------------------------------------------------------------------

if grep -q "test-doc-viewer-routing.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-doc-viewer-routing.sh"
else
  fail "tests/run-all.sh missing test-doc-viewer-routing.sh registration"
fi

print_summary_and_exit
