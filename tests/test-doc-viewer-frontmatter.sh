#!/bin/bash
# DOC_VIEWER Phase 4 — visible frontmatter strip behavior tests.
#
# Asserts on the `renderFrontmatterStrip(md)` body in docs/docs-app.js after
# Phase 4 swap:
#
#   1. Plan MD with frontmatter (status/completed/created) renders the
#      <div class="zs-frontmatter"> strip with all three values.
#   2. Non-frontmatter MD renders no strip.
#   3. Empty frontmatter (---\n---\n with no fields) renders no strip.
#   4. Malformed frontmatter (no closing ---) renders no strip and the
#      body still appears (silent passthrough, no crash).
#   5. Field rendering order: status before completed before created
#      regardless of source order.
#   6. XSS regression: title: <img src=x onerror=alert(1)> renders as
#      escaped &lt;img — NOT a raw <img> tag.
#   7. Static-grep: escapeHtml() call sites in docs-app.js >= 2 (one in
#      renderErrorPane + ≥1 in renderFrontmatterStrip).
#   8. Registered in tests/run-all.sh.
#
# Run from repo root: bash tests/test-doc-viewer-frontmatter.sh

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
# Static-grep: escapeHtml call-sites >= 2 (one in renderErrorPane, one+ in
# renderFrontmatterStrip). This pins the XSS discipline.
# ---------------------------------------------------------------------------
EH_COUNT=$(grep -cE 'escapeHtml\(' "$APP_JS")
if [ "$EH_COUNT" -ge 2 ]; then
  pass "escapeHtml( call sites in docs-app.js = $EH_COUNT (>= 2)"
else
  fail "expected >= 2 escapeHtml() call sites, got $EH_COUNT"
fi

# Confirm the placeholder body is gone — `function renderFrontmatterStrip(md) {\n  return '';` should NOT appear.
if grep -Pzq "function renderFrontmatterStrip\(md\) \{\n  return '';" "$APP_JS" 2>/dev/null; then
  fail "Phase 2a placeholder body still present in renderFrontmatterStrip"
else
  pass "Phase 2a placeholder renderFrontmatterStrip body replaced"
fi

# ---------------------------------------------------------------------------
# Node-DOM behavior tests
# ---------------------------------------------------------------------------

if ! command -v node >/dev/null 2>&1; then
  fail "node not available — DOM tests skipped"
  print_summary_and_exit
fi

HARNESS=$(cat <<'JS'
function makeEl(tag) {
  const el = {
    tagName: (tag || 'div').toUpperCase(),
    className: '', textContent: '', innerHTML: '', href: '',
    children: [], _attrs: {}, _listeners: {},
    appendChild(c) { c.parentEl = this; this.children.push(c); return c; },
    removeChild(c) { this.children = this.children.filter(x => x !== c); return c; },
    addEventListener(ev, fn) { (this._listeners[ev] = this._listeners[ev] || []).push(fn); },
    removeEventListener() {},
    setAttribute(k, v) { this._attrs[k] = String(v); },
    getAttribute(k) { return k === 'href' ? (this.href || null) : (this._attrs[k] == null ? null : this._attrs[k]); },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    classList: { _classes: new Set(), add(c){this._classes.add(c);}, remove(c){this._classes.delete(c);}, contains(c){return this._classes.has(c);} },
    scrollIntoView() {},
    closest() { return null; },
  };
  return el;
}
const nav = makeEl('nav');
const main = makeEl('main');
const elements = { 'zl-docs-nav': nav, 'zl-docs-main': main };
const docListeners = {}; const winListeners = {};
global.document = {
  getElementById(id) { return elements[id] || null; },
  createElement(tag) { return makeEl(tag); },
  querySelector() { return null; },
  addEventListener(ev, fn) { (docListeners[ev] = docListeners[ev] || []).push(fn); },
  documentElement: { setAttribute() {}, getAttribute() { return null; } },
};
global.window = {
  addEventListener(ev, fn) { (winListeners[ev] = winListeners[ev] || []).push(fn); },
  matchMedia: () => ({ matches: false, addEventListener() {}, removeEventListener() {} }),
};
global.location = { hash: '' };
global.history = { replaceState() {} };

function fireDOMContentLoaded() {
  for (const fn of (docListeners.DOMContentLoaded || [])) fn();
}
async function flushTicks(n) {
  for (let i = 0; i < (n || 4); i++) { await new Promise(r => setImmediate(r)); }
}
JS
)

run_node_scenario() {
  local code="$1"
  APP_JS="$APP_JS" RENDERER="$RENDERER" REGISTRY="$REGISTRY" \
    node --input-type=module -e "$code" 2>&1 || true
}

# ---------------------------------------------------------------------------
# Test 1: status + completed + created → strip rendered with all three.
# ---------------------------------------------------------------------------
SCEN1=$(cat <<JS
${HARNESS}
const md = '---\nstatus: complete\ncompleted: 2026-06-01\ncreated: 2026-05-29\ntitle: Plugin Lane\n---\n# Plan';
global.fetch = async () => ({ ok: true, status: 200, text: async () => md });
global.location.hash = '#docs/guides/workflows.md';
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();
process.stdout.write('HTML_START\n' + (main.innerHTML || '') + '\nHTML_END\n');
JS
)
OUT1=$(run_node_scenario "$SCEN1")
HTML1=$(echo "$OUT1" | awk '/^HTML_START$/{f=1; next} /^HTML_END$/{f=0} f')
if echo "$HTML1" | grep -q 'class="zs-frontmatter"'; then
  pass "test1: zs-frontmatter strip rendered for plan with frontmatter"
else
  fail "test1: expected zs-frontmatter strip — got: $HTML1"
fi
for f in status completed created; do
  if echo "$HTML1" | grep -q "$f"; then
    pass "test1: $f field present in strip"
  else
    fail "test1: $f field missing — got: $HTML1"
  fi
done

# ---------------------------------------------------------------------------
# Test 2: Field rendering order — status BEFORE completed BEFORE created.
# Frontmatter source order is reversed (created → completed → status); the
# rendered strip MUST still be status → completed → created.
# ---------------------------------------------------------------------------
SCEN2=$(cat <<JS
${HARNESS}
const md = '---\ncreated: 2026-05-29\ncompleted: 2026-06-01\nstatus: complete\n---\n# H';
global.fetch = async () => ({ ok: true, status: 200, text: async () => md });
global.location.hash = '#docs/guides/workflows.md';
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();
process.stdout.write('HTML_START\n' + (main.innerHTML || '') + '\nHTML_END\n');
JS
)
OUT2=$(run_node_scenario "$SCEN2")
HTML2=$(echo "$OUT2" | awk '/^HTML_START$/{f=1; next} /^HTML_END$/{f=0} f')
# Extract just the zs-frontmatter div content & check ordering positions.
POS_STATUS=$(echo "$HTML2" | grep -bo 'status' | head -1 | cut -d: -f1)
POS_COMPLETED=$(echo "$HTML2" | grep -bo 'completed' | head -1 | cut -d: -f1)
POS_CREATED=$(echo "$HTML2" | grep -bo 'created' | head -1 | cut -d: -f1)
if [ -n "$POS_STATUS" ] && [ -n "$POS_COMPLETED" ] && [ -n "$POS_CREATED" ] \
  && [ "$POS_STATUS" -lt "$POS_COMPLETED" ] \
  && [ "$POS_COMPLETED" -lt "$POS_CREATED" ]; then
  pass "test2: render order status → completed → created (independent of source order)"
else
  fail "test2: render order broken — status@$POS_STATUS, completed@$POS_COMPLETED, created@$POS_CREATED"
fi

# ---------------------------------------------------------------------------
# Test 3: Non-frontmatter MD renders no strip.
# ---------------------------------------------------------------------------
SCEN3=$(cat <<JS
${HARNESS}
const md = '# Plain Header\n\nNo frontmatter here.';
global.fetch = async () => ({ ok: true, status: 200, text: async () => md });
global.location.hash = '#docs/guides/workflows.md';
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();
process.stdout.write('HTML_START\n' + (main.innerHTML || '') + '\nHTML_END\n');
JS
)
OUT3=$(run_node_scenario "$SCEN3")
HTML3=$(echo "$OUT3" | awk '/^HTML_START$/{f=1; next} /^HTML_END$/{f=0} f')
if echo "$HTML3" | grep -q 'class="zs-frontmatter"'; then
  fail "test3: non-frontmatter MD rendered a zs-frontmatter strip (unexpected): $HTML3"
else
  pass "test3: non-frontmatter MD renders no zs-frontmatter strip"
fi
if echo "$HTML3" | grep -q '<h1[^>]*>Plain Header</h1>'; then
  pass "test3: body H1 still rendered"
else
  fail "test3: expected <h1>Plain Header</h1> — got: $HTML3"
fi

# ---------------------------------------------------------------------------
# Test 4: Empty frontmatter (---\n---\n with no fields) renders no strip.
# ---------------------------------------------------------------------------
SCEN4=$(cat <<JS
${HARNESS}
const md = '---\n---\n# H';
global.fetch = async () => ({ ok: true, status: 200, text: async () => md });
global.location.hash = '#docs/guides/workflows.md';
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();
process.stdout.write('HTML_START\n' + (main.innerHTML || '') + '\nHTML_END\n');
JS
)
OUT4=$(run_node_scenario "$SCEN4")
HTML4=$(echo "$OUT4" | awk '/^HTML_START$/{f=1; next} /^HTML_END$/{f=0} f')
if echo "$HTML4" | grep -q 'class="zs-frontmatter"'; then
  fail "test4: empty frontmatter rendered a strip: $HTML4"
else
  pass "test4: empty frontmatter renders no strip"
fi
if echo "$HTML4" | grep -q '<h1[^>]*>H</h1>'; then
  pass "test4: empty-frontmatter body H1 still rendered"
else
  fail "test4: expected body H1 after empty frontmatter — got: $HTML4"
fi

# ---------------------------------------------------------------------------
# Test 5: Malformed frontmatter (no closing ---) — silently strips (returns
# empty string from renderFrontmatterStrip) and the body MD passes through
# the renderer unchanged. We DO NOT assert on whether the renderer choke-
# point produces a particular HR shape — the contract is: no crash, no
# zs-frontmatter strip, no exception.
# ---------------------------------------------------------------------------
SCEN5=$(cat <<JS
${HARNESS}
const md = '---\ntitle: never closed\n\n# Body';
global.fetch = async () => ({ ok: true, status: 200, text: async () => md });
global.location.hash = '#docs/guides/workflows.md';
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();
process.stdout.write('HTML_START\n' + (main.innerHTML || '') + '\nHTML_END\n');
JS
)
OUT5=$(run_node_scenario "$SCEN5")
HTML5=$(echo "$OUT5" | awk '/^HTML_START$/{f=1; next} /^HTML_END$/{f=0} f')
if echo "$HTML5" | grep -q 'class="zs-frontmatter"'; then
  fail "test5: malformed frontmatter (no closer) rendered a strip: $HTML5"
else
  pass "test5: malformed frontmatter renders no strip"
fi
# Renderer should not have crashed — we expect some innerHTML.
if [ -n "$HTML5" ]; then
  pass "test5: renderer produced output despite malformed frontmatter"
else
  fail "test5: renderer produced empty output (likely crashed)"
fi

# ---------------------------------------------------------------------------
# Test 6: XSS regression — malicious title MUST be escaped, not landed raw.
# ---------------------------------------------------------------------------
SCEN6=$(cat <<JS
${HARNESS}
const md = '---\ntitle: <img src=x onerror=alert(1)>\nstatus: drafted\n---\n# H';
global.fetch = async () => ({ ok: true, status: 200, text: async () => md });
global.location.hash = '#docs/guides/workflows.md';
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();
process.stdout.write('HTML_START\n' + (main.innerHTML || '') + '\nHTML_END\n');
JS
)
OUT6=$(run_node_scenario "$SCEN6")
HTML6=$(echo "$OUT6" | awk '/^HTML_START$/{f=1; next} /^HTML_END$/{f=0} f')
# Inside the zs-frontmatter strip, the title value MUST be escaped — i.e.,
# contain `&lt;img` and NOT contain a raw `<img` tag.
if echo "$HTML6" | grep -q '&lt;img'; then
  pass "test6: XSS payload title escaped to &lt;img"
else
  fail "test6: expected '&lt;img' in escaped output — got: $HTML6"
fi
# Make sure no raw <img tag landed in the strip. (The renderer also runs
# stripUnsafeHtml on the body, but a raw <img> from the frontmatter would
# bypass that — so any <img>/<IMG> hit fails.)
if echo "$HTML6" | grep -qi '<img'; then
  fail "test6: raw <img tag found in output — XSS escape failed: $HTML6"
else
  pass "test6: no raw <img tag in rendered HTML"
fi

# ---------------------------------------------------------------------------
# Test 7: Unknown field rendered with literal key (escaped).
# ---------------------------------------------------------------------------
SCEN7=$(cat <<JS
${HARNESS}
const md = '---\nstatus: x\ncustomField: hello\n---\n# H';
global.fetch = async () => ({ ok: true, status: 200, text: async () => md });
global.location.hash = '#docs/guides/workflows.md';
await import(process.env.APP_JS);
fireDOMContentLoaded();
await flushTicks();
process.stdout.write('HTML_START\n' + (main.innerHTML || '') + '\nHTML_END\n');
JS
)
OUT7=$(run_node_scenario "$SCEN7")
HTML7=$(echo "$OUT7" | awk '/^HTML_START$/{f=1; next} /^HTML_END$/{f=0} f')
if echo "$HTML7" | grep -q 'customField'; then
  pass "test7: unknown field 'customField' rendered with literal key"
else
  fail "test7: expected 'customField' literal key — got: $HTML7"
fi

# ---------------------------------------------------------------------------
# Conformance: tests/run-all.sh registers this file.
# ---------------------------------------------------------------------------
if grep -q "test-doc-viewer-frontmatter.sh" "$REPO_ROOT/tests/run-all.sh"; then
  pass "tests/run-all.sh references test-doc-viewer-frontmatter.sh"
else
  fail "tests/run-all.sh missing test-doc-viewer-frontmatter.sh registration"
fi

print_summary_and_exit
