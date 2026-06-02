#!/bin/bash
# Tests for docs/MarkdownRenderer.js (DOC_VIEWER Phase 1).
#
# Node-DOM extract-and-exec harness. The renderer is an ES module that
# returns HTML strings (no DOM), so we import its `renderMarkdown` and
# `escapeHtml` exports directly via `node --input-type=module` and assert
# on substrings/regexes. Mirrors the style of
# tests/test-tab-dot-render-dom.sh — fixture-driven, no test framework,
# emits the canonical `Results: N passed, M failed` line consumed by
# tests/run-all.sh.
#
# Concerns covered (every Markdown feature the zskills corpus uses):
#   T1   ATX headings + slug anchor IDs
#   T2   GFM tables (fragment from docs/plans/PLUGIN_LANE_VERIFICATION.md)
#   T3   Fenced code with language class
#   T4   Inline code
#   T5   GFM task list (checked + unchecked)
#   T6   Recursive blockquotes with nested formatting
#   T7   Nested mixed lists
#   T8   Internal .md link gets zl-docs-internal-link class
#   T9   External https link gets target="_blank" rel="noopener"
#   T10  HTML comment stripped (real one from docs/plans/SKILL_FILE_DRIFT_FIX.md)
#   T11  Image with relative-path resolution (from inspecting-and-monitoring.md)
#   T12  Em/en dashes preserved
#   T13  HR `---` not adjacent to YAML field
#   T14  Security strip: <script>alert(1)</script> — both tokens absent
#   T15  Security strip: <div onclick=alert(2)> — both tokens absent
#   T16  Inline-HTML escaping: <kbd>X</kbd> mid-paragraph renders escaped
#   T17  Security: raw <a href="javascript:..."> neutralized (#983)
#   T18  Security: raw <img onerror=...> handler stripped (#983 supplement)
#   T19  Security: markdown [x](javascript:...) drops link, keeps text (#983)
#   T20  Security: markdown ![alt](data:text/html,...) drops image (#983)
#   T21  Security: markdown [x](//evil.com) protocol-relative dropped (#983)
#   T22  Security: HTML-entity-encoded scheme &#x6A;avascript: neutralized (#983)
#
# Run from repo root: bash tests/test-doc-viewer-renderer.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDERER="$REPO_ROOT/docs/MarkdownRenderer.js"

if [[ ! -f "$RENDERER" ]]; then
  echo "ERROR: $RENDERER not found"
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# Drive the renderer from Node. Each case prints `PASS|FAIL\t<name>\t<msg>`
# on stdout. We then count and re-emit the canonical Results line in bash.
NODE_OUT=$(RENDERER="$RENDERER" node --input-type=module <<'NODE_EOF' 2>&1
const { renderMarkdown, escapeHtml, slugify } = await import(process.env.RENDERER);

let pass = 0, fail = 0;
function check(name, cond, msg) {
  if (cond) { console.log('PASS\t' + name); pass++; }
  else      { console.log('FAIL\t' + name + '\t' + msg); fail++; }
}

// T1: ATX headings + slug anchor IDs
{
  const h = renderMarkdown('# Hello World\n## Sub-Section');
  check('T1.heading-h1-with-slug-id',
    /<h1 id="hello-world">Hello World<\/h1>/.test(h),
    'expected <h1 id="hello-world">; got: ' + h);
  check('T1.heading-h2-with-slug-id',
    /<h2 id="sub-section">Sub-Section<\/h2>/.test(h),
    'expected <h2 id="sub-section">; got: ' + h);
}

// T2: GFM tables (fragment from PLUGIN_LANE_VERIFICATION.md)
{
  const md = [
    '| Phase | Status | Notes |',
    '|-------|--------|-------|',
    '| 1 | Done | smokes |',
    '| 2 | Done | live |',
  ].join('\n');
  const h = renderMarkdown(md);
  check('T2.table-has-zl-docs-table-class',
    /<table class="zl-docs-table">/.test(h),
    'expected zl-docs-table class; got: ' + h);
  check('T2.table-thead-th',
    /<thead><tr><th>Phase<\/th><th>Status<\/th><th>Notes<\/th><\/tr><\/thead>/.test(h),
    'expected thead row; got: ' + h);
  check('T2.table-tbody-row',
    /<tbody>[\s\S]*<td>1<\/td><td>Done<\/td><td>smokes<\/td>/.test(h),
    'expected tbody row; got: ' + h);
}

// T3: Fenced code with language class
{
  const h = renderMarkdown('```bash\necho hi\n```');
  check('T3.fenced-code-lang-class',
    /<pre><code class="language-bash">echo hi<\/code><\/pre>/.test(h),
    'expected language-bash class; got: ' + h);
}
{
  const h = renderMarkdown('```\nplain\n```');
  check('T3.fenced-code-no-lang',
    /<pre><code>plain<\/code><\/pre>/.test(h),
    'expected bare <code>; got: ' + h);
}

// T4: Inline code
{
  const h = renderMarkdown('Use `scripts/port.sh` to check.');
  check('T4.inline-code',
    /<code>scripts\/port\.sh<\/code>/.test(h),
    'expected inline <code>; got: ' + h);
}

// T5: GFM task list (checked + unchecked) via list items
{
  const md = '- [x] done thing\n- [ ] todo thing';
  const h = renderMarkdown(md);
  check('T5.task-checked',
    /<li class="task-list-item"><input type="checkbox" checked class="zl-task-checkbox"> done thing<\/li>/.test(h),
    'expected checked task li; got: ' + h);
  check('T5.task-unchecked',
    /<li class="task-list-item"><input type="checkbox" class="zl-task-checkbox"> todo thing<\/li>/.test(h),
    'expected unchecked task li; got: ' + h);
}

// T6: Recursive blockquotes with nested formatting
{
  const md = '> A quote with **bold** and `code`.';
  const h = renderMarkdown(md);
  check('T6.blockquote-wraps-paragraph',
    /<blockquote>[\s\S]*<\/blockquote>/.test(h),
    'expected <blockquote>; got: ' + h);
  check('T6.blockquote-nested-bold',
    /<strong>bold<\/strong>/.test(h),
    'expected <strong> inside blockquote; got: ' + h);
  check('T6.blockquote-nested-code',
    /<code>code<\/code>/.test(h),
    'expected <code> inside blockquote; got: ' + h);
}

// T7: Nested mixed lists (this renderer is line-based, so we assert it
// produces both list types in order without crashing — the corpus doesn't
// rely on indent-driven nesting visually nested under one another).
{
  const md = '- bullet one\n- bullet two\n\n1. ordered one\n2. ordered two';
  const h = renderMarkdown(md);
  check('T7.list-ul',
    /<ul>[\s\S]*<li>bullet one<\/li>[\s\S]*<li>bullet two<\/li>[\s\S]*<\/ul>/.test(h),
    'expected <ul> with two items; got: ' + h);
  check('T7.list-ol',
    /<ol>[\s\S]*<li>ordered one<\/li>[\s\S]*<li>ordered two<\/li>[\s\S]*<\/ol>/.test(h),
    'expected <ol> with two items; got: ' + h);
}

// T8: Internal .md link gets zl-docs-internal-link class AND its raw
//     (un-baseUrl-resolved) href so the hash-router in docs-app.js
//     (rewriteInternalLinksToHash) can resolve it against the current
//     doc's location. Applying baseUrl here would double-resolve and
//     produce `docs/docs/...` (see the doc-viewer post-deploy fixup).
{
  const h = renderMarkdown('See [the guide](guides/INSPECTING.md).');
  check('T8.md-link-internal-class',
    /<a href="guides\/INSPECTING\.md" class="zl-docs-internal-link">the guide<\/a>/.test(h),
    'expected zl-docs-internal-link with RAW href (no baseUrl prefix); got: ' + h);
}

// T9: External https link gets target="_blank" rel="noopener"
{
  const h = renderMarkdown('See [Anthropic](https://anthropic.com).');
  check('T9.external-link-target-blank',
    /<a href="https:\/\/anthropic\.com" target="_blank" rel="noopener">Anthropic<\/a>/.test(h),
    'expected external link with target=_blank rel=noopener; got: ' + h);
}

// T10: HTML comment stripped (shape from docs/plans/SKILL_FILE_DRIFT_FIX.md)
{
  const md = '<!-- co_author was deferred here in earlier rounds. -->\n\nVisible text.';
  const h = renderMarkdown(md);
  check('T10.html-comment-stripped',
    !/<!--/.test(h) && !/co_author/.test(h) && /Visible text/.test(h),
    'expected comment + body gone, visible kept; got: ' + h);
}

// T11: Image with relative-path resolution (mirrors inspecting-and-monitoring.md)
{
  const md = '![Dashboard screenshot](assets/zskills-dashboard.png)';
  const h = renderMarkdown(md, { baseUrl: 'guides/' });
  check('T11.image-relative-path-resolved',
    /<img src="guides\/assets\/zskills-dashboard\.png" alt="Dashboard screenshot" class="zl-whatsnew-img">/.test(h),
    'expected resolved <img> with zl-whatsnew-img; got: ' + h);
}

// T12: Em/en dashes preserved (the renderer doesn't touch them)
{
  const h = renderMarkdown('A sentence — with em dash and 2026–2027 en dash.');
  check('T12.em-dash-preserved',
    h.includes('—'),
    'expected em dash preserved; got: ' + h);
  check('T12.en-dash-preserved',
    h.includes('–'),
    'expected en dash preserved; got: ' + h);
}

// T13: HR `---` not adjacent to YAML field
{
  const md = 'Para before.\n\n---\n\nPara after.';
  const h = renderMarkdown(md);
  check('T13.hr-emitted',
    /<hr>/.test(h),
    'expected <hr>; got: ' + h);
}

// T14: Security strip: <script>alert(1)</script>
{
  const h = renderMarkdown('Hello\n\n<script>alert(1)</script>\n\nWorld');
  check('T14.script-tag-stripped',
    !/<script/i.test(h),
    'expected no <script in output; got: ' + h);
  check('T14.script-body-stripped',
    !/alert\(1\)/.test(h),
    'expected no alert(1) in output; got: ' + h);
}

// T15: Security strip: <div onclick=alert(2)>
{
  const h = renderMarkdown('<div onclick=alert(2)>\nhi\n</div>');
  check('T15.onclick-handler-stripped',
    !/onclick/i.test(h),
    'expected no onclick in output; got: ' + h);
  check('T15.onclick-body-stripped',
    !/alert\(2\)/.test(h),
    'expected no alert(2) in output; got: ' + h);
}

// T16: Inline-HTML escaping reality — <kbd>X</kbd> mid-paragraph
{
  const h = renderMarkdown('Press <kbd>X</kbd> to continue.');
  check('T16.inline-html-escaped',
    h.includes('&lt;kbd&gt;') && h.includes('&lt;/kbd&gt;'),
    'expected &lt;kbd&gt;...&lt;/kbd&gt; (escaped); got: ' + h);
}

// T17: Raw HTML <a href="javascript:..."> is neutralized (issue #983).
// The href= scheme-strip should rewrite the scheme to about:blank#blocked-scheme-
// so that no live `javascript:` URL reaches main.innerHTML.
{
  const h = renderMarkdown('<a href="javascript:alert(1)">x</a>');
  // After scheme rewrite, the literal substring 'href="javascript' (a live
  // scheme in attribute position) must be absent. The string 'javascript'
  // may still appear inside the about:blank#blocked-scheme-javascript:...
  // fragment but that is not interpreted as a URL scheme.
  check('T17.raw-anchor-javascript-no-live-href',
    !/href\s*=\s*["']?\s*javascript:/i.test(h),
    'expected no live href=javascript:; got: ' + h);
  check('T17.raw-anchor-javascript-neutralized',
    /about:blank#blocked-scheme/.test(h),
    'expected about:blank#blocked-scheme- replacement; got: ' + h);
}

// T18: Raw HTML <img src="x" onerror="alert(1)"> — onerror stripped.
// Supplements T15 (which covers onclick) with onerror, a common image-XSS handler.
{
  const h = renderMarkdown('<img src="x" onerror="alert(1)">');
  check('T18.raw-img-onerror-stripped',
    !/onerror/i.test(h),
    'expected no onerror in output; got: ' + h);
  check('T18.raw-img-onerror-body-stripped',
    !/alert\(1\)/.test(h),
    'expected no alert(1) in output; got: ' + h);
}

// T19: Markdown [x](javascript:...) produces text only — no <a href.
// Markdown link parser stops at the first ')' so the regex captures
// `href = "javascript:alert(1"`; the scheme check on the raw href must still
// fire and drop the link entirely.
{
  const h = renderMarkdown('[click](javascript:alert(1))');
  check('T19.md-link-javascript-no-scheme',
    !/javascript:/i.test(h),
    'expected no live javascript: in output; got: ' + h);
  check('T19.md-link-javascript-no-href',
    !/<a\s+href/i.test(h),
    'expected no <a href in output; got: ' + h);
  check('T19.md-link-javascript-text-preserved',
    /click/.test(h),
    'expected bracket-text preserved; got: ' + h);
}

// T20: Markdown ![alt](data:text/html,...) produces alt-text only.
// data:text/html, even on an <img>, is an XSS surface (browsers may render).
{
  const h = renderMarkdown('![alt-text](data:text/html,<script>alert(1)</script>)');
  check('T20.md-image-data-text-html-no-scheme',
    !/data:text\/html/i.test(h),
    'expected no data:text/html in output; got: ' + h);
  check('T20.md-image-data-text-html-no-script',
    !/<script/i.test(h),
    'expected no <script tag in output; got: ' + h);
  check('T20.md-image-data-text-html-alt-preserved',
    /alt-text/.test(h),
    'expected alt-text preserved; got: ' + h);
}

// T21: Markdown [x](//evil.com) — protocol-relative is open-redirect surface.
// Should be dropped to text-only.
{
  const h = renderMarkdown('[click](//evil.com)');
  check('T21.md-link-protocol-relative-no-href',
    !/href\s*=\s*["']?\/\/evil\.com/.test(h),
    'expected no protocol-relative href; got: ' + h);
  check('T21.md-link-protocol-relative-text-preserved',
    /click/.test(h),
    'expected bracket-text preserved; got: ' + h);
}

// T22: HTML-entity-encoded scheme <a href="&#x6A;avascript:..."> is neutralized.
// `&#x6A;` is the HTML numeric entity for `j`; when the browser decodes the
// attribute value at render time, the result is `javascript:alert(1)` — a
// live XSS scheme. The stripUnsafeHtml entity-encoded-href neutralizer must
// rewrite this to about:blank#blocked-entity-encoded so the decoded form is
// no longer a scheme.
{
  const h = renderMarkdown('<a href="&#x6A;avascript:alert(1)">x</a>');
  // The href must NOT decode to a live javascript: scheme. The literal
  // `&#x6A;avascript:` as the START of the href value is the dangerous form;
  // after rewrite it lives inside `about:blank#blocked-entity-encoded&#x6A;...`
  // which decodes harmlessly.
  check('T22.entity-encoded-scheme-not-live-href',
    !/href\s*=\s*["']\s*&#/.test(h),
    'expected no href starting with &#; got: ' + h);
  check('T22.entity-encoded-scheme-neutralized',
    /about:blank#blocked-entity-encoded/.test(h),
    'expected about:blank#blocked-entity-encoded replacement; got: ' + h);
}

console.log('__COUNTS__\t' + pass + '\t' + fail);
NODE_EOF
)
NODE_RC=$?

# Print the per-case lines (without the marker line)
echo "$NODE_OUT" | grep -v '^__COUNTS__'

# Extract counts
COUNTS_LINE=$(echo "$NODE_OUT" | grep '^__COUNTS__' | tail -1)
if [[ -z "$COUNTS_LINE" ]]; then
  echo ""
  echo "ERROR: node harness did not emit __COUNTS__ marker (exit $NODE_RC)"
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

PASS=$(echo "$COUNTS_LINE" | awk -F'\t' '{print $2}')
FAIL=$(echo "$COUNTS_LINE" | awk -F'\t' '{print $3}')

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]] || [[ $NODE_RC -ne 0 ]]; then
  exit 1
fi
exit 0
