---
title: Docs Viewer — JS-based Markdown viewer at /docs/
created: 2026-06-02
status: drafted
---

# Plan: Docs Viewer — JS-based Markdown viewer at /docs/

## Overview

zskills currently has no `/docs/` landing — `docs/` is a tree of ~178 Markdown
files (`guides/`, `skills/`, `plans/`, `reports/`, `evals/`, `issues/`,
`tracking/`) plus one hand-built `docs/guides/inspecting-and-monitoring.html`
that sits outside any framework. GitHub Pages serves the repo with
`.nojekyll` (PR #47), so a Jekyll-based viewer is off the table.

This plan lifts a private zero-dependency JS Markdown viewer from
`zeveck/zimulink` (verified via `gh api`: 5 files, 971 LOC total) and adapts
it to zskills' content shape: hash routing, sidebar catalog, a `URL`-based
internal-link resolver, recursive-blockquote rendering, GFM tables (the
highest-signal element in plan progress trackers), YAML-frontmatter
metadata strip, and a dark-default theme anchored on the
`docs/guides/inspecting-and-monitoring.html` palette with a 3-state
(light/dark/system) toggle. Implementation is plain ES2020+ — no
transpiler, no bundler, no jq. Tests follow the dashboard precedent
(`tests/test-tab-dot-render-dom.sh` et al.): Node-DOM extract-and-exec
behavioral suites + static-grep contracts.

The work decomposes into 5 phases: (1) lift the renderer + tests + add
defense-in-depth strips for `<script>` blocks, HTML comments, and unquoted
event-handler attributes, (2) lift the shell, write net-new hash-routing
listeners (the upstream uses `history.replaceState` only — no
`hashchange`/`popstate`/`DOMContentLoaded` listeners exist; see Phase 2
Work Items), write the inline catalog-miss error pane and off-catalog
GitHub fallback as net-new UX, and lift the YAML-frontmatter SOURCE-STRIP
into the render pipeline so plan files do not ship visibly broken before
Phase 4 lands, (3) restyle + add dark-default + theme toggle with FOUC
prevention, (4) replace the stub with a scripted catalog generator + the
VISIBLE frontmatter `.zs-frontmatter` strip rendering, (5) delete the
redundant hand-built `.html` once viewer parity is verified and add the
`.nojekyll` regression gate.

**Lift-vs-net-new audit.** Several elements were initially framed as "lift"
but a Round-1 source re-check showed they are net-new work the plan must
explicitly specify, not preserve. Routed to the phases noted: hash-routing
listeners (Phase 2), inline error pane (Phase 2), GitHub fallback (Phase 2),
HTML-comment strip (Phase 1), script-block delete (Phase 1), unquoted `on*=`
strip (Phase 1), dark-mode CSS + theme toggle (Phase 3 — already framed as
new), frontmatter source-strip (Phase 2 — MOVED from Phase 4 so plan files
do not render `---` as `<hr>` and the YAML keys as literal text between
Phases 2 and 4).

## Progress Tracker
| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — MarkdownRenderer lift + tests | ✅ Done | `fd79c2c` | 27/27 renderer tests; full suite 7185/7185 |
| 2a — Viewer shell + stub catalog + frontmatter helpers + sanity smoke | ✅ Done | `474aed5` | 33/33 shell tests; full suite 7228/7228 |
| 2b — Hash routing + helpers + handler rewrites + error pane + routing test | ✅ Done | `ea81d88` | 38/38 routing tests; doc-viewer suites 98/98 |
| 3 — Styling + dark-default + theme toggle | ✅ Done | `101b4a9` | 31/31 styling tests; full suite 7297/7297 |
| 4 — Catalog generator + frontmatter metadata strip | ✅ Done | `942c0cd` | 36 new tests (catalog+frontmatter); 176-item catalog; full suite 7333/7333 |
| 5 — Inspecting-and-monitoring.html disposition + URL plumbing | ✅ Done | `05e46fe` | parity verified (0 unexplained HTML-only tokens); IAM.html deleted; .nojekyll gate added; build-prod.sh no-op confirmed; full suite 7336/7336 |

## Conventions all phases follow

- All viewer files live under `docs/`. Markdown source files anywhere in
  the repo are NEVER modified by this plan — they are canonical.
- `.nojekyll` MUST stay at repo root (PR #47, commit `a7f4bcb`). A
  static-grep test asserts its presence as the final regression gate
  (Phase 5).
- **Pre-flight before Phase 1 starts:** (1) `gh auth status` succeeds
  against `zeveck/zimulink` (PRIVATE repo, raw URLs return 404);
  (2) `gh api repos/zeveck/zimulink/contents/docs/index.html` returns 200;
  (3) `bash tests/run-all.sh` baseline passes on the working tree.
  Lift sources are already cached at `/tmp/zimulink-lift/` — the plan
  references them directly so no re-fetch is required during execution.
- **CSS class prefix `zl-*` from zimulink is KEPT verbatim.** The prefix
  appears in `MarkdownRenderer.js` (`zl-docs-internal-link`,
  `zl-whatsnew-img`, `zl-task-checkbox`, `zl-docs-table`) and the
  matching CSS rules. Renaming touches 4 of 5 lifted files and provides
  zero functional value — the prefix is unique enough to never collide
  with future zskills CSS. This decision is documented in Phase 1 as well.
- Each phase must run `bash tests/run-all.sh` clean before commit.
  Capture output per the canonical idiom:
  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
  ```
- Each phase emits a unit test file `tests/test-doc-viewer-<phase-slug>.sh`
  registered in `tests/run-all.sh`, emitting the canonical
  `Results: N passed, M failed` line (load-bearing — `run-all.sh:36`
  greps it) and exiting non-zero on any failure.
- Test pattern: Node-DOM extract-and-exec mirror of the dashboard tests
  (`tests/test-tab-dot-render-dom.sh` is the exemplar). NO playwright in
  CI; `playwright-cli` is only used for attended manual smokes.
- Commit prefix: `feat(docs-viewer):` for new viewer files (mirroring
  `feat(dashboard):` precedent); `docs(viewer):` for prose-only phases.
- All viewer code targets ES2020+ (native `URL`, `fetch`, `Promise`,
  `Map`, optional chaining, `matchMedia`); no transpilation, no bundler.
- Catalog paths are repo-root-relative (e.g., `docs/guides/WORKFLOWS.md`);
  the viewer at `/docs/index.html` fetches with `'../' + item.path`.
- HTML passthrough security strip: entire `<script>...</script>` blocks
  are DELETED (multiline non-greedy regex — not just the tags); `<iframe>`,
  `<object>`, `<embed>` opening/closing tags are stripped; `on*=`
  attributes are stripped in three forms — double-quoted, single-quoted,
  and unquoted (`onclick=alert(1)`). HTML comments `<!-- ... -->` are
  also stripped before render. Total ~8 LOC defense-in-depth, single
  owner content, no DOMPurify.
- Skill-file hardcode discipline scopes to `skills/**/*.md` — viewer
  files under `docs/` are FREE of `zskills-resolve-config.sh` sourcing.
  Do NOT over-apply the rule.
- **Search is OUT OF SCOPE for v1.** Catalog browse + per-page TOC +
  browser Ctrl-F is the v1 affordance. v2 decision points: client-side
  index (lunr/MiniSearch), Algolia DocSearch, or none.

## Phase 1 — MarkdownRenderer lift + tests

### Goal
Lift `/tmp/zimulink-lift/src__ui__MarkdownRenderer.js` verbatim to
`docs/MarkdownRenderer.js` (100% lift), add a ~5-LOC security strip pass
to its HTML passthrough, and add Node-DOM extract-and-exec tests covering
every Markdown feature the zskills corpus actually uses.

### Work Items
- [ ] Copy `/tmp/zimulink-lift/src__ui__MarkdownRenderer.js` →
  `docs/MarkdownRenderer.js` (310 LOC, zero changes to MD render logic).
- [ ] Add a top-of-file comment header noting source
  (`zeveck/zimulink:src/ui/MarkdownRenderer.js`, lifted 2026-06-02),
  license posture (single-author lift, both repos same author), and
  the design intent (zero-deps hand-rolled MD→HTML).
- [ ] Add the HTML passthrough strip pass — a single helper applied
  BEFORE the renderer's existing passthrough. The helper MUST:
  (a) delete entire `<script>...</script>` blocks (not just the tags —
  the inner JS text must go too); (b) strip opening/closing tags for
  `<iframe>`, `<object>`, `<embed>`; (c) strip `on*=` attributes in all
  three quote forms (double-quoted, single-quoted, unquoted); (d) strip
  HTML comments `<!-- ... -->` (the renderer has no native comment
  handling — see verified Round-1 finding DA #7):
  ```js
  function stripUnsafeHtml(s) {
    return s
      .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
      .replace(/<\/?(?:iframe|object|embed)\b[^>]*>/gi, '')
      .replace(/\s+on\w+\s*=\s*"[^"]*"/gi, '')
      .replace(/\s+on\w+\s*=\s*'[^']*'/gi, '')
      .replace(/\s+on\w+\s*=\s*[^\s>]+/gi, '')
      .replace(/<!--[\s\S]*?-->/g, '');
  }
  ```
  Document the threat model inline (single-owner content; this is
  defense-in-depth, not a real sandbox).
- [ ] **Wire `stripUnsafeHtml` into the render pipeline.** Defining the
  helper without a call site means the strip pass never runs (verified
  Round-2 finding DA #1: round-1 plan defined the helper but never
  invoked it). Modify the body of `renderMarkdown(md, options)` —
  insert `md = stripUnsafeHtml(md);` as the FIRST executable line of
  the function, BEFORE the existing `const baseUrl = …` /
  `md.split('\n')` setup. Concretely, the upstream function opens at
  `MarkdownRenderer.js:16` as:
  ```js
  export function renderMarkdown(md, options) {
    const baseUrl = (options && options.baseUrl) || 'getting-started/';
    const lines = md.split('\n');
    …
  ```
  After the edit it must read:
  ```js
  export function renderMarkdown(md, options) {
    md = stripUnsafeHtml(md);
    const baseUrl = (options && options.baseUrl) || 'getting-started/';
    const lines = md.split('\n');
    …
  ```
- [ ] Keep the existing `zl-*` CSS classes the renderer emits unchanged
  (`zl-docs-internal-link`, `zl-whatsnew-img`, `zl-task-checkbox`,
  `zl-docs-table`). Renaming would cascade into 4 of the 5 lifted files
  for zero functional gain — document this in the file header.
- [ ] Add `tests/test-doc-viewer-renderer.sh` (Node-DOM extract-and-exec)
  covering, with real-corpus fragments where possible:
  - ATX headings 1-6 with slugified `id` attributes. Slug algorithm
    matches the LIFTED source (do not invent unicode preservation or
    dedupe). The verified zimulink slugify (see
    `/tmp/zimulink-lift/src__ui__MarkdownRenderer.js:246-257`):
    (1) strip `**bold**`, `*italic*`, `` `code` ``, `[text](url)` link
    markup; (2) lowercase; (3) `replace(/[^a-z0-9\s-]/g, '')` —
    REMOVE all non-ASCII alnum (no unicode preservation); (4)
    `replace(/\s+/g, '-')`; (5) `replace(/-+/g, '-')` (collapse
    hyphen runs); (6) trim leading/trailing hyphens. NO duplicate
    suffix logic — two identical headings emit identical `id`s
    (acceptable for v1; documented limitation).
  - GFM pipe tables with alignment row (`:---:`, `:---`, `---:`).
    Test fragment lifted from `docs/plans/PLUGIN_LANE_VERIFICATION.md`'s
    Progress Tracker — this is the highest-signal visual element.
  - Fenced code blocks with language class (`bash`, `json`, `yaml`,
    `markdown`, `python`).
  - Inline code (very high density in plans).
  - Task lists `- [ ]` and `- [x]`.
  - Blockquote with recursive nested rendering (a `> **bold**` inside
    `> outer` must emit `<strong>` inside the inner blockquote — the
    lifted renderer calls itself on inner content; see
    `MarkdownRenderer.js:166`).
  - Nested unordered + ordered lists, mixed depths.
  - Internal `.md` link rendered with class `zl-docs-internal-link`.
  - External `https://` link with `target="_blank" rel="noopener"`.
  - HTML comments `<!-- … -->` stripped silently. Use a real HTML
    comment as the test fixture — pick a verified one via
    `grep -nE '^<!--' docs/**/*.md | head` and cite the line in the test
    comment. (Round-1 finding DA #17 flagged that
    `docs/plans/SKILL_VERSIONING.md:141` is NOT itself an HTML comment;
    do not rely on that anchor.)
  - Image with relative-path resolution. Use the image in
    `docs/guides/INSPECTING_AND_MONITORING.md` — locate it at test-write
    time via `grep -nE '!\[' docs/guides/INSPECTING_AND_MONITORING.md`
    and cite the resolved line in the test comment.
  - Em/en dashes preserved literally.
  - HR (`---` on its own line BUT NOT immediately followed by `^[a-z]+:`
    YAML field — that pattern is frontmatter and is stripped upstream in
    Phase 2 before this renderer ever sees it).
  - Security strip: a `<script>alert(1)</script>` injected fragment is
    fully removed before render emits HTML (output contains neither
    `<script` nor `alert(1)` — achievable because the regex now deletes
    the entire `<script>...</script>` block, not just the tags).
  - Security strip: a `<div onclick=alert(2)>x</div>` unquoted handler
    is stripped (output contains neither `onclick` nor `alert(2)`).
  - **Inline-HTML escaping reality.** The lifted renderer's HTML
    passthrough is BLOCK-LEVEL ONLY (br, hr, iframe, h1-h6, a, details,
    div, section, figure, aside, summary; see
    `MarkdownRenderer.js:35,43,68`). Inline tags `<sub>`, `<sup>`,
    `<kbd>`, `<span>`, `<details>` mid-line are escaped by
    `escapeHtml` inside `inlineMarkdown` and render as VISIBLE
    `&lt;kbd&gt;...` text. The test must assert this fact (one fragment
    with a mid-paragraph `<kbd>X</kbd>` whose output contains `&lt;kbd&gt;`),
    so future readers do not assume inline HTML works. This is a
    documented limitation, not a regression to fix in v1.
- [ ] Each test asserts on output HTML via substring or regex match;
  emit final `Results: N passed, M failed` line; exit non-zero on
  any failure.
- [ ] Register `test-doc-viewer-renderer.sh` in `tests/run-all.sh`
  (add a `run_suite` line near the other doc-/render-DOM tests).
- [ ] Run `bash tests/run-all.sh` to confirm baseline + new suite green.

### Design & Constraints
- **Source:** `/tmp/zimulink-lift/src__ui__MarkdownRenderer.js`
  (310 LOC, confirmed via `gh api`). Lift VERBATIM except for the
  security strip pass.
- **Exports the renderer provides:** `renderMarkdown(md, opts)`,
  `slugify(s)`, `escapeHtml(s)`. Phase 2's `docs-app.js` imports
  `renderMarkdown` directly.
- **Internal helper (non-exported) preserved verbatim:** `normalizePath(p)`
  at `MarkdownRenderer.js:297-310` — collapses `..` / `.` segments while
  preserving a leading `/`. Called by image and link relative-path
  resolution in `inlineMarkdown`. Do not delete or rename it during the
  lift.
- **Markdown features confirmed in corpus** (research file §"Markdown
  features the corpus actually uses"). CRITICAL set (used on essentially
  every page): ATX headings, nested lists, GFM tables, fenced code with
  langs, inline code, bold/italic, blockquotes (recursive), internal +
  external links, HTML comments (must strip), em/en dashes, HR.
  MODERATE: task lists, sparse inline HTML (`<sub>`, `<kbd>`, rare
  `<details>`/`<summary>`/`<br>`).
- **Recursive blockquote rendering:** the lifted renderer invokes itself
  on inner blockquote content. Test must verify nested formatting.
- **Security threat model:** zskills' `docs/` is single-owner content
  written by one human; the strip-list is defense-in-depth against a
  hypothetical compromised editor, not a sandbox. DOMPurify (~20KB) is
  rejected as overkill.
- **HTML passthrough — actual reality (verified against
  `MarkdownRenderer.js:35,43,68`).** BLOCK-LEVEL tags whose opener
  starts a line pass through verbatim: `<br>`, `<hr>`, `<iframe>` (now
  stripped by Phase 1's helper), `<h1>`-`<h6>`, `<a>`, `<details>`,
  `<div>`, `<section>`, `<figure>`, `<aside>`, `<summary>`. Everything
  ELSE — including inline `<sub>`, `<sup>`, `<kbd>`, `<span>` mid-paragraph
  — is escaped by `escapeHtml` inside `inlineMarkdown` and renders as
  visible `&lt;kbd&gt;…`. The Phase 1 test asserts this so the
  limitation is locked in (extending inline-HTML passthrough is a v2
  decision).
- **Test harness:** Node + jsdom-style stub already established in
  `tests/test-tab-dot-render-dom.sh` — copy that scaffolding pattern
  (extract the JS file, eval inside a stubbed DOM, assert on
  `document.body.innerHTML`).
- **Test sample inputs** MUST come from real zskills MD files. Pick
  2-3 sample fragments from `docs/guides/INSPECTING_AND_MONITORING.md`,
  `docs/plans/PLUGIN_LANE_VERIFICATION.md`, `docs/skills/README.md`,
  and `docs/plans/SKILL_VERSIONING.md`.
- **No SKILL.md edits** in this phase → no `metadata.version` bump
  required.

### Acceptance Criteria
- [ ] `docs/MarkdownRenderer.js` exists, between 305 and 320 LOC
  (310 lift ± strip helper), zero external imports, no `require()`
  / `import` other than its own exports.
- [ ] `grep -c "function stripUnsafeHtml" docs/MarkdownRenderer.js`
  returns 1.
- [ ] `stripUnsafeHtml` is INVOKED inside `renderMarkdown` as its first
  executable line:
  `grep -nE "^\s*md\s*=\s*stripUnsafeHtml\(md\)\s*;?\s*$" docs/MarkdownRenderer.js`
  returns exactly 1 hit at a line number ≤ 25 (i.e., immediately
  inside the `renderMarkdown` body, before the parser setup).
- [ ] `tests/test-doc-viewer-renderer.sh` runs under Node-DOM stub,
  asserts every CRITICAL feature listed in Work Items, emits
  `Results: N passed, M failed`, exits 0 on success, registered in
  `tests/run-all.sh` (grep for the suite name returns ≥1 hit).
- [ ] `bash tests/run-all.sh` exits 0.
- [ ] `<script>alert(1)</script>` injected into a test MD fragment is
  stripped before the renderer emits HTML (verified by a dedicated
  test case that asserts the output string contains neither `<script`
  nor `alert(1)` — achievable because the regex deletes the entire
  block, not just the tags).
- [ ] `<div onclick=alert(2)>x</div>` unquoted-handler form is stripped
  (test asserts output contains neither `onclick` nor `alert(2)`).
- [ ] HTML comments `<!-- agent-facing note -->` are stripped silently
  (test asserts output contains no `<!--`).
- [ ] Inline `<kbd>X</kbd>` mid-paragraph renders as escaped text
  (`&lt;kbd&gt;X&lt;/kbd&gt;`) — locks in the documented
  inline-HTML limitation.
- [ ] Renderer file contains EACH of the four `zl-*` class names verbatim:
  `grep -c 'zl-docs-internal-link' docs/MarkdownRenderer.js` ≥1,
  `grep -c 'zl-whatsnew-img' docs/MarkdownRenderer.js` ≥1,
  `grep -c 'zl-task-checkbox' docs/MarkdownRenderer.js` ≥1,
  `grep -c 'zl-docs-table' docs/MarkdownRenderer.js` ≥1
  (the bare `grep -c "zl-"` count is brittle — it counts LINES not
  classes; this per-class check pins each one).
- [ ] `normalizePath` helper is preserved in the lift
  (`grep -c "function normalizePath" docs/MarkdownRenderer.js` returns 1).

### Dependencies
None — foundation phase. Pre-flight gates (above) must pass.

## Phase 2a — Viewer shell + stub catalog + frontmatter helpers + sanity smoke

### Goal
Lift the index.html shell + docs-app.js verbatim minus the strips
(password gate, newsletter logic, examples/ folder branch); KEEP upstream's
eager initial-load block AND upstream's direct-`loadDoc` sidebar + main
click handlers in place; rewrite ONLY the renderer call site to use the
new frontmatter helpers; add the `stripFrontmatter` + `renderFrontmatterStrip`
placeholder helpers (load-bearing for the renderer call site — without
them the file throws `ReferenceError` on first paint); write the 5-item
stub catalog; and add a static-grep + Node-DOM sanity-smoke test. The
result is an unstyled, upstream-routing-shape viewer that renders one
catalog doc end-to-end. **Phase 2a is intentionally unstyled — Phase 3
ships the CSS palette. Verifiers should NOT flag the unstyled look as a
regression.** Phase 2b layers hash-routing + helpers + handler rewrites +
error pane on top.

### Work Items
- [ ] Copy `/tmp/zimulink-lift/docs__index.html` → `docs/index.html`.
  STRIP (verified against the lift source, not approximated):
  - Line 6: `<meta name="robots" content="noindex, nofollow">`.
  - Line 8: `<link rel="icon" type="image/svg+xml" href="/favicon.svg">`.
    REMOVE entirely. No `favicon.svg` file exists in zskills at repo
    root or under `docs/` (`ls favicon.svg docs/favicon.svg` → both
    ENOENT, verified 2026-06-02). Leaving the tag in causes a console
    404 on every page load. If a favicon is wanted later, file a v2
    follow-up.
  - Line 9: `<link rel="stylesheet" href="/docs/docs.css">`. REPLACE
    with `<link rel="stylesheet" href="./docs.css">`. The absolute
    `/docs/docs.css` form breaks under `python3 -m http.server`
    served from repo root (the local server has no rewrite rule to
    serve `/docs/` from `./docs/`) AND breaks any deployment served
    from a non-root path. Sibling relative is dev/prod safe.
  - Lines 10-62: the gate `<style>` block (verified — block opens at
    line 10 `<style>` and closes at line 62 `</style>`; the plan's
    original `10-72` overshot the `</style>` boundary).
  - Lines 66-72: the `<div id="zl-gate">…</div>` markup (gate input
    + button form).
  - Lines 73-120: the gate `<script>...</script>` block (the
    password-unlock async module loader).
  - `class="zl-locked"` on `<body>` (line 64) → remove the class
    attribute (or replace with the bare `<body>`).
  - Line 65: `<!-- Password gate -->` orphan HTML comment that
    introduces the (now-deleted) gate `<div>`. STRIP entirely; leaving
    a "Password gate" comment in a viewer that has no gate is
    confusing for future readers.
  KEEP: `<head>` meta + viewport + (rewritten) stylesheet link; the
  `<div id="zl-docs-app">` shell with `<header>`, `<nav>`, `<main>`
  (lines 122-133); the closing tags.
- [ ] Replace zimulink-specific branding: header logo text "Zimulink"
  (line 124) → "Z Skills Docs" with the zskills accent palette
  (`--accent:#5db0ff` from
  `docs/guides/inspecting-and-monitoring.html:10`). Keep any gradient
  / shimmer animation if Phase 3's restyle keeps it; do not invent one.
- [ ] Change script entry to a direct
  `<script type="module" src="./docs-app.js"></script>` injected just
  before `</body>` — loaded after parse, no async unlock.
- [ ] Copy `/tmp/zimulink-lift/docs__docs-app.js` → `docs/docs-app.js`.
  STRIPS in Phase 2a (correct boundaries — the original `101-170` strip
  range is a syntax-error trap because the surrounding `if/else`
  straddles 101-173; see Round-1 finding DA #1):
  - Line 11: `const headerTitle = document.querySelector('.zl-docs-header-title');`
    — the header title is set statically in Phase 3 styling; no JS
    mutation needed.
  - Line 15: `const isNewsletter = (item) => item.path.endsWith('NEWSLETTER.md');`.
  - Lines 68-71: the newsletter `headerTitle` mutation block
    (`if (headerTitle) { headerTitle.textContent = isNewsletter(item) ? '' : item.name; }`).
  - **Lines 101-173 ENTIRE `if (isNewsletter(item)) { … } else {
    main.innerHTML = renderMarkdown(md, { baseUrl }); }` block.**
    REPLACE the whole block with the single line:
    ```js
    main.innerHTML = renderFrontmatterStrip(md) + renderMarkdown(stripFrontmatter(md), { baseUrl });
    ```
    where `renderFrontmatterStrip` and `stripFrontmatter` are the
    helpers added in this phase (see "Frontmatter source-strip helpers"
    work item below). **Both helpers MUST land in 2a** — the upstream
    eager block (lines 34-55, preserved verbatim per the next bullet)
    calls `loadDoc` on first paint, which calls this line; if the
    helpers are deferred to 2b the file throws a `ReferenceError`
    immediately at module load and the shell can't be smoke-tested in
    isolation (verified Round-1 finding DA #1). The syntax-error trap:
    stripping 101-170 alone leaves a dangling `} else { ... }` because
    the upstream `if` opens at line 101 and the matching `} else { ... }`
    closes at 171-173. The strip MUST run 101-173 with the single-line
    replacement.
  - Lines 224-233: the upstream click-handler's `examples/<name>/`
    folder branch. zskills has no `examples/` directory (verified —
    `ls /workspaces/zskills/examples 2>&1` → ENOENT). REMOVE this
    entire branch; do not adapt it. This is a pure deletion and fits
    the "lift + strip" shape of Phase 2a (the surrounding click
    handler's catalog-scan inner body at L193-221 is rewritten in
    Phase 2b, not here).
- [ ] **Preserve upstream's routing shape verbatim in Phase 2a.** The
  following upstream sections are KEPT BYTE-FOR-BYTE — they are
  rewritten in Phase 2b, not here, so that Phase 2a's shell has a
  working render path the moment it lands and can be smoke-tested in
  isolation:
  - Sidebar build (upstream lines 17-31, including the L28
    `link.addEventListener('click', () => loadDoc(item, link));`
    direct-call). Phase 2b rewrites the inner item loop (lines 24-29)
    to emit `<a data-path=...>` and route via `location.hash`.
  - The eager initial-load top-level block (upstream lines 34-55, bare
    top-level code — NOT an IIFE). Phase 2b REMOVES it and replaces
    with a `DOMContentLoaded` listener calling `routeFromHash`. AC for
    2a (positive presence): `grep -c 'DOCS_CATALOG\[0\]' docs/docs-app.js`
    returns ≥1 (the eager fallback at L51 references
    `DOCS_CATALOG[0]?.items[0]`).
  - `loadDoc` body, including the upstream `history.replaceState` call
    at line 66 (Phase 2b removes the replaceState call when it adds
    listener-based routing).
  - The main click handler's catalog-scan inner body (upstream lines
    193-221), which calls `loadDoc(item, navItems[idx])` directly.
    Phase 2b replaces this entire block with `resolveLink` +
    `location.hash`. (The `examples/` branch at lines 224-233 is
    already stripped in 2a per the previous bullet.)
- [ ] Rewrite the imports at the top of `docs-app.js` to the sibling-relative
  form. Phase 2a imports ONLY `renderMarkdown` — `escapeHtml` is added in
  Phase 2b alongside `renderErrorPane` (which is the only caller):
  - Line 6 `import { renderMarkdown } from '../src/ui/MarkdownRenderer.js';`
    → `import { renderMarkdown } from './MarkdownRenderer.js';`
  - Line 7 `import { DOCS_CATALOG } from '../src/ui/DocsRegistry.js';`
    → `import { DOCS_CATALOG } from './DocsRegistry.js';`
- [ ] Write `docs/DocsRegistry.js` with a 5-item STUB catalog (the
  full generated catalog comes in Phase 4):
  ```js
  export const DOCS_CATALOG = [
    { section: 'Start here', items: [
        { name: 'Z Skills Docs',           path: 'docs/README.md' },
        { name: 'Workflows',               path: 'docs/guides/WORKFLOWS.md' },
        { name: 'Plugin install',          path: 'docs/guides/PLUGIN_INSTALL.md' },
        { name: 'All skills',              path: 'docs/skills/README.md' },
        { name: 'Inspecting & monitoring', path: 'docs/guides/INSPECTING_AND_MONITORING.md' },
    ] },
  ];
  ```
  Verified 2026-06-02: `head -8` on each of the 5 files returns no
  YAML frontmatter — every file opens at its `# H1`. So 2a's render
  path (which calls `renderFrontmatterStrip` → returns `''` placeholder,
  then `renderMarkdown(stripFrontmatter(md), ...)` → `stripFrontmatter`
  returns the input unchanged because the leading 4 bytes are not
  `---\n`) is a pure pass-through for the stub catalog. The helpers
  are still load-bearing as references — the call site won't parse
  without them — and they unlock plan-file rendering once Phase 4
  generates the broader catalog.
- [ ] **Frontmatter source-strip helpers** (MOVED from the original
  monolithic Phase 2; the visible `.zs-frontmatter` strip rendering
  stays in Phase 4 but the SOURCE strip + the placeholder MUST land
  in 2a because the renderer call site references both names — see
  the L101-173 replacement bullet above). The renderer's HR rule
  (`MarkdownRenderer.js:91 /^---+$/`) matches the frontmatter opener
  AND closer, so without source-strip every plan file (once Phase 4
  exposes them) renders a stray `<hr>` followed by paragraphs of
  `title: Foo`, `status: drafted`, etc., followed by another `<hr>`.
  Implementation in `docs/docs-app.js`:
  ```js
  function stripFrontmatter(md) {
    if (!md.startsWith('---\n')) return md;
    // Empty-frontmatter precheck: `---\n---\n` — closing `\n---\n`
    // starts at offset 3, so the offset-4 search misses it and we'd
    // return unstripped. Handle the empty case explicitly. (Round-2
    // finding DA #6.)
    if (md.startsWith('---\n---\n')) return md.slice(8);
    const close = md.indexOf('\n---\n', 4);
    if (close === -1) return md;        // unterminated → pass through
    return md.slice(close + 5);
  }
  function renderFrontmatterStrip(md) {
    // Phase 2a: emit nothing (placeholder). Phase 4 replaces this body
    // with the parsed-fields strip emitter.
    return '';
  }
  ```
  Phase 4 swaps `renderFrontmatterStrip`'s body for the full parsed
  `<div class="zs-frontmatter">` emitter. `stripFrontmatter` stays as
  written across Phases 2a/2b/4.
- [ ] Add `tests/test-doc-viewer-shell.sh` (static-grep contracts +
  Node-DOM sanity smoke). The shell test asserts the file lifts +
  strips landed cleanly and that the shell renders ONE doc end-to-end
  using upstream's eager block — no hash routing involved. Cases:
  - **Static greps (the strip + lift contracts):** see the matching
    Phase 2a ACs below; each is a 1-line shell assertion.
  - **Node-DOM `import DOCS_CATALOG` assertion:** spawn
    `node --input-type=module -e "import('./docs/DocsRegistry.js').then(m => process.stdout.write(JSON.stringify(m.DOCS_CATALOG)))"`
    and assert the JSON has exactly 1 section with 5 items at the
    expected paths.
  - **Node-DOM sanity smoke (~20 LOC):** import `docs-app.js` under a
    minimal DOM stub (mirror `tests/test-tab-dot-render-dom.sh`'s
    harness), mock `fetch` to return `# H` for the first catalog
    item's URL, drive `loadDoc(DOCS_CATALOG[0].items[0], null)`
    directly, and assert `document.querySelector('main').innerHTML`
    contains `<h1` and the slugified id (`id="h"` per Phase 1 slugify
    spec) and `>H</h1>`. This gates the L101-173 replacement plus the
    frontmatter helpers' presence — a missing `renderFrontmatterStrip`
    or `stripFrontmatter` produces a `ReferenceError` on `loadDoc`
    invocation and the test fails closed. The smoke does NOT exercise
    `hashchange`, sidebar clicks, or `location.hash` — those are 2b's
    domain.
- [ ] Register `test-doc-viewer-shell.sh` in `tests/run-all.sh`.
- [ ] Run `bash tests/run-all.sh` to confirm green (Phase 1 + new shell
  suite + pre-existing).

### Design & Constraints
- **Lift sources:** `/tmp/zimulink-lift/docs__index.html` (135 LOC),
  `/tmp/zimulink-lift/docs__docs-app.js` (234 LOC),
  `/tmp/zimulink-lift/src__ui__DocsRegistry.js` (99 LOC — shape only,
  all content replaced).
- **Lift-vs-net-new split (Phase 2a).** LIFTED verbatim: sidebar build
  loop (upstream lines 17-31, including the direct-call click handler);
  eager initial-load block (upstream lines 34-55); `loadDoc` body
  including `history.replaceState`; `renderDoc` baseUrl computation
  (upstream lines 93-99 minus the `main.innerHTML = ''` clear, which
  the L101-173 replacement makes redundant); main click handler outer
  shell (upstream lines 179-234 minus the L101-173 inner body's
  newsletter branch — already stripped — and minus the L224-233
  examples/ branch). NET-NEW in 2a: ONLY the frontmatter helpers
  (`stripFrontmatter`, `renderFrontmatterStrip` placeholder) and the
  one-line renderer call site at L101-173. All hash routing,
  listeners, helper functions, `renderErrorPane`, `resolveLink`,
  handler rewrites, and `escapeHtml` import are deferred to Phase 2b.
- **Catalog shape:** array of `{section: string, items: [{name, path}]}`.
  Paths are repo-root-relative.
- **Fetch prefix:** viewer at `/docs/index.html` fetches with
  `'../' + item.path` (so `item.path = 'docs/guides/X.md'` becomes
  fetch URL `'../docs/guides/X.md'`). The browser resolves this against
  the page URL `/docs/`, yielding the final URL `/docs/guides/X.md`
  served by GitHub Pages (i.e., the on-disk file at repo root
  `docs/guides/X.md`). Equivalent under `python3 -m http.server`
  served from repo root.
- **`.nojekyll` interaction.** Because Pages serves the repo verbatim
  (PR #47), MD files at `docs/*.md` are served as `text/markdown` /
  `text/plain` and `fetch().text()` returns the raw source — exactly
  what the renderer wants. No build step.
- **Intentionally unstyled.** Phase 2a does NOT touch `docs/docs.css`;
  the page will look broken (no flex layout, no width split between
  sidebar and main) when served. Phase 3 ships the palette. Verifiers
  must NOT flag the unstyled look as a regression.
- **No SKILL.md edits** in this phase → no `metadata.version` bump
  required.
- **No DOMPurify import** — security strip lives in `MarkdownRenderer.js`
  (Phase 1).
- **`stripFrontmatter` heuristic + corpus risk.** The strip rule is
  "any document whose first 4 bytes are `---\n` and which contains a
  later `\n---\n` (or the empty-FM `---\n---\n` shape) has its prefix
  through the closer stripped." A document whose ACTUAL first content
  line is an HR `---` followed somewhere later by another `---` line
  would be mis-stripped — the renderer would lose its first
  paragraph. Verified against the current zskills corpus (2026-06-02):
  no `docs/**/*.md` file opens with `---\n` as a content HR (every
  hit is genuine YAML frontmatter). Future regression would surface
  as "first paragraph missing in viewer" — discoverable by readers.
  v2 may tighten by requiring line 2 to match
  `^[a-zA-Z_][\w-]*:\s` (a YAML key) before committing to strip,
  but the heuristic stays as-is for v1 to match the lifted renderer's
  simplicity.

### Acceptance Criteria
- [ ] `docs/index.html`, `docs/docs-app.js`, `docs/DocsRegistry.js`
  exist with strips applied and the 5-item stub catalog.
- [ ] `grep -c "zl-gate" docs/index.html` returns 0
  (gate fully removed).
- [ ] `grep -c 'Password gate' docs/index.html` returns 0
  (orphan comment also removed).
- [ ] `grep -c "isNewsletter" docs/docs-app.js` returns 0
  (newsletter branch fully removed).
- [ ] `grep -c 'name="robots"' docs/index.html` returns 0
  (noindex meta removed).
- [ ] `grep -c 'favicon.svg' docs/index.html` returns 0 (broken
  reference removed).
- [ ] `grep -c 'href="/docs/docs.css"' docs/index.html` returns 0
  (absolute path replaced); `grep -c 'href="./docs.css"' docs/index.html`
  returns 1.
- [ ] `grep -c "type=\"module\"" docs/index.html` returns 1 (the
  `<script type="module" src="./docs-app.js">` tag is present; no
  async unlock loader).
- [ ] `grep -c "function stripFrontmatter" docs/docs-app.js` returns 1
  AND `grep -c "function renderFrontmatterStrip" docs/docs-app.js`
  returns 1 (both helpers present in 2a so the L101-173 renderer
  call site parses).
- [ ] **Upstream eager initial-load block is PRESERVED in 2a:**
  `grep -c 'DOCS_CATALOG\[0\]' docs/docs-app.js` returns ≥1 (the
  upstream L51 `DOCS_CATALOG[0]?.items[0]` fallback is still in the
  file). Phase 2b's parallel AC asserts this drops to 0 once the
  eager block is replaced by the `DOMContentLoaded` listener.
- [ ] **Upstream sidebar handler is PRESERVED in 2a:**
  `grep -c 'loadDoc(item, link)' docs/docs-app.js` returns ≥1 (the
  upstream L28 direct-call form is still in the file). Phase 2b
  rewrites it.
- [ ] **Upstream main-click catalog-scan + direct `loadDoc(item,
  navItems[idx])` IS still present in 2a:**
  `grep -c "loadDoc(item, navItems\\[idx\\])" docs/docs-app.js`
  returns ≥1 (this is the upstream L207 inner-body line, kept
  verbatim in 2a). Phase 2b's parallel AC asserts this drops to 0.
- [ ] **The DocsRegistry import works:** the Node-DOM `import
  DOCS_CATALOG` assertion in `tests/test-doc-viewer-shell.sh` passes
  — `DOCS_CATALOG` is a 1-section, 5-item array at the expected paths.
- [ ] **The shell renders one doc end-to-end:** the Node-DOM sanity
  smoke in `tests/test-doc-viewer-shell.sh` mocks `fetch` to return
  `# H`, invokes `loadDoc` on the first catalog item, and asserts
  `main.innerHTML` contains `<h1` + the slug id + `>H</h1>`. No
  `ReferenceError` (which is what a missing frontmatter helper would
  produce on the L101-173 call site).
- [ ] **Hash-routing additions are NOT yet in 2a (negative ACs that
  pin the split):**
  - `grep -nE "hashchange|popstate|DOMContentLoaded" docs/docs-app.js`
    returns 0 (no listener wires in 2a — Phase 2b adds them).
  - `grep -c "function routeFromHash" docs/docs-app.js` returns 0.
  - `grep -c "function renderErrorPane" docs/docs-app.js` returns 0.
  - `grep -c "function resolveLink" docs/docs-app.js` returns 0.
  - `grep -cE "import \\{[^}]*\\bescapeHtml\\b[^}]*\\}" docs/docs-app.js`
    returns 0 (escapeHtml is NOT imported in 2a — Phase 2b adds it).
- [ ] `tests/test-doc-viewer-shell.sh` exits 0; emits
  `Results: N passed, M failed`; registered in `run-all.sh`.
- [ ] `bash tests/run-all.sh` exits 0 (Phase 1's renderer test +
  Phase 2a's shell test + the full pre-existing suite).
- [ ] Manual smoke (attended, optional but recommended for the
  implementing agent): serve repo root via
  `python3 -m http.server 8000`, open
  `http://localhost:8000/docs/`, verify the first catalog item
  (`docs/README.md`) renders via upstream's eager initial-load path
  (no hash). Other 4 items are reachable only via sidebar clicks
  using upstream's direct-`loadDoc` form (no URL sync yet — that's
  Phase 2b). The unstyled look is expected; do not flag it.

### Dependencies
Phase 1 (MarkdownRenderer must exist and be importable).

## Phase 2b — Hash routing + helpers + handler rewrites + error pane + routing test

### Goal
Layer hash-routing on top of Phase 2a's working shell: remove upstream's
eager initial-load block; rewrite the sidebar build's inner item loop +
the main click handler's catalog-scan inner body to route via
`location.hash`; add `routeFromHash` + its referenced helpers
(`findCatalogItem`, `findNavEl`, `scrollToAnchor`); add `resolveLink` +
`currentHashPath` for relative `.md` link resolution; add `renderErrorPane`
for catalog misses (with GitHub off-catalog fallback link); add the
3 routing listeners (`hashchange`, `popstate`, `DOMContentLoaded`); add
`escapeHtml` to the imports (needed by `renderErrorPane`); and add the
routing test suite. The result is a fully deep-linkable viewer with
single-ingress (hash) routing.

### Work Items
- [ ] **Extend the imports** — add `escapeHtml` alongside the existing
  `renderMarkdown`:
  - Phase 2a's `import { renderMarkdown } from './MarkdownRenderer.js';`
    → `import { renderMarkdown, escapeHtml } from './MarkdownRenderer.js';`
  - `escapeHtml` is used by `renderErrorPane` to HTML-escape the
    user-supplied path before string-interpolating it into the error
    pane's GitHub link. Without this import the first off-catalog hash
    produces a `ReferenceError`. (Verified Round-2 finding DA #2.)
- [ ] **Rewrite the sidebar build's INNER item loop (upstream lines
  24-29) to emit `data-path` attributes and route via `location.hash`,**
  so `findNavEl` (added below) can locate nav elements after hashchange
  and so a single ingress (`hashchange` → `routeFromHash` → `loadDoc`)
  handles all navigation. **Preserve the outer loop and section header
  build (upstream lines 18-22): `for (const section of DOCS_CATALOG)` +
  the `<div class="zl-docs-section-header">` block are NOT modified.**
  AC: `grep -c 'zl-docs-section-header' docs/docs-app.js` returns 1.
  Replace the inner element-creation lines with:
  ```js
  for (const item of section.items) {
    const link = document.createElement('a');
    link.className = 'zl-docs-nav-item';
    link.textContent = item.name;
    link.href = '#' + item.path;        // anchor semantics for free
    link.setAttribute('data-path', item.path);
    link.addEventListener('click', (e) => {
      e.preventDefault();
      location.hash = '#' + item.path;
      // hashchange fires → routeFromHash → loadDoc (single ingress)
    });
    nav.appendChild(link);
  }
  ```
  Switching from `<div>` to `<a>` is a minor a11y win (keyboard +
  screen-reader semantics) and lets the browser's URL preview show the
  destination on hover; the `e.preventDefault()` + manual
  `location.hash` assignment is still required because we want a
  single `hashchange`-driven ingress.
  **Double-load-prevention reasoning (load-bearing, do NOT pre-set
  `lastHandledHash`):** `lastHandledHash` (defined alongside
  `routeFromHash` below) starts as `null`. On the first sidebar click,
  `location.hash = '#docs/...'` fires `hashchange` → `routeFromHash`
  sees `raw='docs/...'` ≠ `null` → loads the doc → sets
  `lastHandledHash='docs/...'`. On a SECOND click of the SAME sidebar
  entry, assigning `location.hash` to its current value is a browser
  no-op (no `hashchange` fires per the HTML spec) — no double load.
  Pre-setting `lastHandledHash = item.path` BEFORE assigning the hash
  would cause `routeFromHash` to bail and the doc would never load on
  first click — that is the bug, do not write it that way.
- [ ] **Rewrite the upstream main-click handler's catalog-scan block
  (lines 193-221) to set `location.hash` instead of calling
  `loadDoc` directly.** Upstream walks DOCS_CATALOG, finds a matching
  item by path, and invokes `loadDoc(item, navItems[idx])` directly —
  same anti-pattern as the sidebar handler, and same URL-sync break.
  REPLACE the entire `if (href.endsWith('.md') || …)` branch's inner
  body with:
  ```js
  if (href.endsWith('.md') || href.includes('.md#')) {
    e.preventDefault();
    const resolved = resolveLink(href, currentHashPath());
    location.hash = '#' + resolved;
    // hashchange → routeFromHash → loadDoc; section anchor (if any)
    // rides along inside `resolved` and is parsed out by routeFromHash.
    return;
  }
  ```
  This block REPLACES upstream lines 193-221 entirely — the catalog
  scan and the "Not in catalog — load directly" off-catalog branch
  are both subsumed by `routeFromHash`'s catalog-miss → `renderErrorPane`
  path (which carries the GitHub fallback link). Do not preserve the
  off-catalog `loadDoc` direct call.
- [ ] **Remove the upstream eager initial-load block** (lines 34-55 of
  upstream `docs__docs-app.js`, preserved verbatim in Phase 2a). The
  `DOMContentLoaded` listener added below supersedes it — keeping
  both would race (eager block loads first item, then hashchange-on-load
  fires and re-renders). AC: `grep -c 'DOCS_CATALOG\[0\]' docs/docs-app.js`
  returns 0 (the L51 fallback reference is gone).
- [ ] **Remove the upstream `history.replaceState` call at line 66**
  inside `loadDoc` — superseded by setting `location.hash` directly
  (which fires `hashchange` for free).
- [ ] **Write net-new hash-routing listeners.** The upstream source
  does NOT have these — verified via
  `grep -nE "hashchange|popstate|DOMContentLoaded|lastHandledHash"
  /tmp/zimulink-lift/docs__docs-app.js` → 0 hits. Upstream only uses
  `history.replaceState` to mirror the path into the URL after a
  sidebar click (line 66). We are adding listener-based routing for
  zskills because the use cases here (browser back/forward through
  deep links, URL-bar editing) demand it. Algorithm:
  ```js
  let lastHandledHash = null;
  function routeFromHash() {
    const raw = location.hash.slice(1);          // strip leading '#'
    if (raw === lastHandledHash) return;          // dedupe: re-renders
    lastHandledHash = raw;
    // Split on the FIRST '#' (path part vs. section anchor). We use
    // indexOf+slice instead of `raw.split('#', 2)` because JS's
    // `.split(sep, limit)` truncates to N substrings and DISCARDS any
    // remainder — a hash like `docs/X.md#sec#sub` would drop `#sub`.
    // The slugify spec strips `#` from heading text, so triple-hash
    // anchors are not generated by the renderer today (corpus-safe),
    // but indexOf+slice future-proofs the parse with no extra cost.
    const hashIdx = raw.indexOf('#');
    const pathPart = hashIdx < 0 ? raw : raw.slice(0, hashIdx);
    const anchor   = hashIdx < 0 ? ''  : raw.slice(hashIdx + 1);
    const targetPath = pathPart || 'docs/README.md';
    // Find catalog entry; if missing, render the inline error pane
    // (Page not found + GitHub fallback link) — see helper below.
    const item = findCatalogItem(targetPath);
    if (item) {
      loadDoc(item, findNavEl(item)).then(() => scrollToAnchor(anchor));
    } else {
      renderErrorPane(targetPath);
    }
  }
  window.addEventListener('hashchange', routeFromHash);
  window.addEventListener('popstate', routeFromHash);
  window.addEventListener('DOMContentLoaded', routeFromHash);
  ```
  Where `findCatalogItem`, `findNavEl`, `scrollToAnchor`,
  `renderErrorPane` are the helpers added below.
- [ ] **Specify the three referenced helpers** (`findCatalogItem`,
  `findNavEl`, `scrollToAnchor`) used by `routeFromHash`. Write them
  alongside `routeFromHash` in `docs/docs-app.js`:
  ```js
  function findCatalogItem(path) {
    for (const section of DOCS_CATALOG) {
      for (const item of section.items) {
        if (item.path === path) return item;
      }
    }
    return null;
  }

  function findNavEl(item) {
    // Sidebar build (rewritten above) adds `data-path` on each <a>.
    return nav.querySelector(`a[data-path="${item.path}"]`);
  }

  function scrollToAnchor(anchor) {
    // anchor is the URL fragment AFTER the second `#`. Headings emit
    // id=slugify(text) per the lifted renderer, so anchor authors
    // must use slug form (lowercase, hyphenated, ASCII alnum only —
    // see Phase 1 slugify spec).
    if (!anchor) return;
    const el = document.getElementById(anchor);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
  ```
  Document the slug-form requirement so future anchor authors don't
  expect `#Section Name` to work (it won't — must be `#section-name`).
- [ ] **Add the `currentHashPath` 1-liner helper** used by the main
  click-handler rewrite to compute the base for relative `.md` link
  resolution:
  ```js
  function currentHashPath() {
    const raw = location.hash.slice(1);
    const hashIdx = raw.indexOf('#');
    return hashIdx < 0 ? raw : raw.slice(0, hashIdx);
  }
  ```
- [ ] **Implement internal-link resolver using the `URL` constructor.**
  This is also net-new — upstream's click handler (lines 193-221)
  did a simpler `rawPath.replace(/^(\.\.\/)+/, '')` plus a catalog
  scan; zskills needs richer resolution for relative paths like
  `../guides/X.md` inside `docs/skills/Y.md`:
  ```js
  function resolveLink(href, currentHashPath) {
    // currentHashPath is the path part of location.hash (no leading '#')
    const base = new URL('https://x/' + currentHashPath, 'https://x/');
    const u = new URL(href, base);
    return u.pathname.slice(1) + u.hash;
  }
  ```
  The math: `currentHashPath = 'docs/skills/Y.md'` becomes base
  `https://x/docs/skills/Y.md`; `href = '../guides/X.md'` resolves to
  `https://x/docs/guides/X.md`; `.pathname.slice(1)` strips the leading
  `/` → `docs/guides/X.md`. Section anchor (the SECOND `#` in
  `Y.md#section`) is preserved via `u.hash`. The click handler sets
  `location.hash = '#' + resolveLink(href, current)` — `hashchange`
  fires, `routeFromHash` does the rest. No `pushState` to a different
  pathname, no full reload.
- [ ] **Write the inline catalog-miss error pane.** This is NEW UX, not
  in the upstream (the upstream's only error path is line 89
  `main.innerHTML = '<p style="color:#f44336">Could not load document.</p>'`
  on `fetch` failure). Net-new helper:
  ```js
  function renderErrorPane(targetPath) {
    const safe = escapeHtml(targetPath);
    main.innerHTML = `
      <div class="zs-error-pane">
        <h2>Page not found</h2>
        <p>No catalog entry for <code>${safe}</code>.</p>
        <p><a href="#docs/README.md" class="zl-docs-internal-link">Back to docs home</a></p>
        <p>Or view raw source on
          <a href="https://github.com/zeveck/zskills/blob/main/${safe}"
             target="_blank" rel="noopener">GitHub</a>.</p>
      </div>`;
  }
  ```
  (`escapeHtml` is imported from `MarkdownRenderer.js` per the Phase 2b
  import-extend Work Item.) The GitHub link is the off-catalog fallback —
  it works even when the catalog is stale or the user typed a path
  that exists in the repo but not in the sidebar.
- [ ] Add `tests/test-doc-viewer-routing.sh` (Node-DOM extract-and-exec)
  covering:
  - Empty hash → `routeFromHash` sets `lastHandledHash = ''` and
    invokes `loadDoc` with the `docs/README.md` catalog entry.
  - Valid hash `#docs/guides/WORKFLOWS.md` → `loadDoc` calls
    `fetch('../docs/guides/WORKFLOWS.md')` (use a fetch spy; assert on
    the URL arg).
  - Hash `#docs/nonexistent.md` not in catalog → error pane rendered;
    `main.innerHTML` contains "Page not found" AND a GitHub fallback
    `<a href="https://github.com/zeveck/zskills/blob/main/docs/nonexistent.md"`.
  - Anchor-hash form `#docs/guides/WORKFLOWS.md#some-section` parses
    into `pathPart='docs/guides/WORKFLOWS.md'` and `anchor='some-section'`
    (assert directly on the helpers — not on observed scroll, which
    Node-DOM can't observe).
  - Internal `.md` link click → the click handler calls
    `event.preventDefault()` (assert the spy's `defaultPrevented` is
    `true`) AND sets `location.hash` to the resolved target. (The
    "no full page reload" assertion is structurally hard in Node-DOM
    — `preventDefault` being called is the actionable surrogate; see
    Round-1 finding R #10.)
  - Sidebar click fires the load EXACTLY ONCE (not twice from the
    click + hashchange double path) — implemented with a `loadDoc`
    spy that counts invocations: after a synthetic sidebar click on
    `docs/guides/WORKFLOWS.md`, `spy.callCount === 1` AND a SECOND
    click on the SAME entry yields `spy.callCount === 1` still
    (browser no-op on same-value hash assignment).
  - Frontmatter source-strip (regression — the helpers landed in 2a
    but the routing path is what feeds them in the deep-link case):
    an MD string starting with `---\ntitle: X\nstatus: drafted\n---\n# H`
    renders neither `<hr>` nor a paragraph containing `title: X` or
    `status: drafted`.
- [ ] Register `test-doc-viewer-routing.sh` in `tests/run-all.sh`.
- [ ] Run `bash tests/run-all.sh` to confirm green (Phase 1 + 2a + 2b +
  pre-existing).

### Design & Constraints
- **Lift-vs-net-new split (Phase 2b).** NET-NEW (all written here):
  the 3 routing listeners, `lastHandledHash` dedupe, `routeFromHash`,
  `findCatalogItem`, `findNavEl`, `scrollToAnchor`, `currentHashPath`,
  `resolveLink`, `renderErrorPane`, the `escapeHtml` import addition.
  REWRITES (replacing 2a's preserved-upstream sections): sidebar inner
  item loop (upstream L24-29 → `<a data-path=...>` + `location.hash`);
  main click handler inner body (upstream L193-221 → `resolveLink` +
  `location.hash`); REMOVALS: upstream eager block L34-55, upstream
  `history.replaceState` at L66.
- **Single-ingress invariant.** All loads after Phase 2b go through
  `hashchange` → `routeFromHash` → `loadDoc`. No direct `loadDoc` call
  remains in the sidebar or main-click handlers. The single-fire
  routing-test assertion gates this.
- **No SKILL.md edits** in this phase → no `metadata.version` bump
  required.

### Acceptance Criteria
- [ ] `grep -nE "hashchange|popstate|DOMContentLoaded" docs/docs-app.js`
  returns ≥3 (the 3 listeners are wired).
- [ ] `grep -c "function routeFromHash" docs/docs-app.js` returns 1.
- [ ] All three routing helpers are defined:
  `grep -c "function findCatalogItem" docs/docs-app.js` returns 1,
  `grep -c "function findNavEl" docs/docs-app.js` returns 1,
  `grep -c "function scrollToAnchor" docs/docs-app.js` returns 1.
- [ ] `grep -c "function currentHashPath" docs/docs-app.js` returns 1.
- [ ] `grep -c "function resolveLink" docs/docs-app.js` returns 1.
- [ ] `grep -c "function renderErrorPane" docs/docs-app.js` returns 1.
- [ ] `grep -cE "import \\{[^}]*\\bescapeHtml\\b[^}]*\\} from ['\"]\\./MarkdownRenderer\\.js['\"]" docs/docs-app.js`
  returns 1 (escapeHtml is imported alongside `renderMarkdown` so
  `renderErrorPane` can call it).
- [ ] **Upstream eager initial-load block is REMOVED in 2b:**
  `grep -c 'DOCS_CATALOG\[0\]' docs/docs-app.js` returns 0
  (parallel to Phase 2a's positive presence AC).
- [ ] **Upstream sidebar `loadDoc(item, link)` direct-call form is
  REMOVED in 2b:** `grep -c 'loadDoc(item, link)' docs/docs-app.js`
  returns 0 (the rewrite replaces the entire inner item loop).
- [ ] **Upstream main-click direct `loadDoc(item, navItems[idx])` call
  is GONE:** `grep -c "loadDoc(item, navItems\\[idx\\])" docs/docs-app.js`
  returns 0.
- [ ] Sidebar AND main-click handlers both route via `location.hash`:
  `grep -cE "location\\.hash\\s*=" docs/docs-app.js` returns ≥ 2 (the
  sidebar handler + the internal-link handler each set it).
- [ ] Sidebar `<a>` elements carry `data-path` attributes (so
  `findNavEl` can locate them):
  `grep -c "setAttribute('data-path'" docs/docs-app.js` returns 1.
- [ ] Loading `docs/index.html` with no hash invokes `loadDoc` on
  `docs/README.md` (verified by routing test via `DOMContentLoaded`
  → `routeFromHash` → empty-raw → `docs/README.md` fallback).
- [ ] Loading `docs/index.html#docs/guides/WORKFLOWS.md` renders
  WORKFLOWS (verified by routing test).
- [ ] Loading `docs/index.html#docs/nonexistent.md` renders the inline
  error pane with "Page not found" text AND a GitHub fallback link
  (verified by routing test).
- [ ] An internal `[Workflows](../guides/WORKFLOWS.md)` link click from
  `docs/README.md` calls `event.preventDefault()` (asserted via
  `evt.defaultPrevented === true`) and sets `window.location.hash`
  to the resolved target (verified by routing test).
- [ ] Routing test asserts a sidebar click fires the load EXACTLY ONCE
  (not twice from the click + hashchange double path).
- [ ] Frontmatter source-strip regression: a plan-style MD `---\ntitle:
  X\nstatus: drafted\n---\n# H` renders neither `<hr>` nor a paragraph
  containing `title: X` (verified by routing test against the 2a
  helpers, exercised through the hash-routed load path).
- [ ] `tests/test-doc-viewer-routing.sh` exits 0; emits
  `Results: N passed, M failed`; registered in `run-all.sh`.
- [ ] `bash tests/run-all.sh` exits 0 (Phase 1 + 2a shell + 2b routing
  + pre-existing).
- [ ] Manual smoke (attended, optional but recommended for the
  implementing agent): serve repo root via
  `python3 -m http.server 8000`, open
  `http://localhost:8000/docs/`, verify all 5 catalog items load via
  sidebar click AND deep-linking by editing the URL hash works AND
  browser back/forward navigates correctly. A plan file with
  frontmatter (once Phase 4's catalog exposes one) renders cleanly
  (no stray `---`, no `title:` paragraph above the H1).

### Dependencies
Phase 2a (the viewer shell, frontmatter helpers, and stub catalog
must exist for the routing-layer additions and handler rewrites to
have something to attach to).

## Phase 3 — Styling + dark-default + theme toggle

### Goal
Lift the CSS structurally, replace the palette with zskills dark-default
colors anchored on `docs/guides/inspecting-and-monitoring.html`, and add
a 3-state (light/dark/system) theme toggle with FOUC prevention.

### Work Items
- [ ] Copy `/tmp/zimulink-lift/docs__docs.css` → `docs/docs.css`.
  STRIP the newsletter CSS block at lines 139-182 (~44 LOC — the
  comment `/* Newsletter header + TOC pills */` at line 139 belongs to
  the stripped block). KEEP lines 184-193 (the `@media (max-width:
  768px)` responsive block — sidebar narrows on mobile).
- [ ] Restructure the 7 light-theme CSS variables into a dual-palette
  setup, using the EXACT variable names from
  `docs/guides/inspecting-and-monitoring.html:9-11` (verified
  2026-06-02; the names there are `--bg`, `--panel`, `--panel2`,
  `--ink`, `--muted`, `--line`, `--accent`, `--accent2`, `--warn`,
  `--code`, plus four `--pill-*` vars). For the doc viewer we use the
  9 vars that map to viewer concerns:
  - `:root { /* dark defaults */ --bg:#0f1115; --panel:#161a22;
    --panel2:#1b2030; --ink:#e6e9ef; --muted:#9aa4b2; --line:#2a3142;
    --accent:#5db0ff; --accent2:#7ee2b8; --code:#0b0d12; }`
    (lifted verbatim from inspecting-and-monitoring.html:9-10).
  - `[data-theme="light"] { /* light overlay */ --bg:#f6f8fb;
    --panel:#ffffff; --panel2:#f0f3f8; --ink:#1b2430; --muted:#5b6776;
    --line:#dde3ec; --accent:#1668c7; --accent2:#0f8a5f;
    --code:#0e1116; }`
    (lifted verbatim from inspecting-and-monitoring.html:15-16).
  - Rewrite the zimulink CSS rules to reference the new names:
    `var(--color-bg)` → `var(--bg)`, `var(--color-surface)` →
    `var(--panel)`, `var(--color-border)` → `var(--line)`,
    `var(--color-text)` → `var(--ink)`, `var(--color-text-muted)` →
    `var(--muted)`, `var(--color-primary)` → `var(--accent)`.
    Verify all `--color-*` references are gone post-rewrite.
  - **Split `--color-primary-light` remap by call site** (Round-2
    finding R #4 — a single-target remap loses the code-fence accent
    tint). The upstream uses `--color-primary-light` for two
    semantically distinct concerns: (a) nav-item hover/active
    background tint (lines 78, 81 of zimulink `docs__docs.css`), and
    (b) inline `<code>` + fenced `<pre>` background (lines 103, 109).
    Remap (a) → `var(--panel2)` (slightly-elevated panel tint that
    reads as a subtle hover/active state in both themes), and remap
    (b) → `var(--code)` (the dedicated code-block background defined
    in both `:root` and `[data-theme="light"]` palettes — gives a
    visibly distinct background for code that doesn't compete with
    nav-item tinting). Also check lines 163, 179, 180 of zimulink
    `docs__docs.css` for further `--color-primary-light` uses (TOC
    pills / newsletter chrome — but most of those are inside the
    stripped 139-182 newsletter block, so verify post-strip that
    only the 4 nav + code occurrences remain).
- [ ] Add FOUC-prevention inline `<script>` in `docs/index.html`
  `<head>`, BEFORE the `<link rel="stylesheet" href="docs.css">`:
  ```html
  <script>
  (function() {
    var s = localStorage.getItem('zskills-docs-theme') || 'system';
    var dark = s === 'dark' || (s === 'system' &&
      window.matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
  })();
  </script>
  ```
- [ ] Add toggle UI to `docs/index.html` header: a small icon button
  (`☀` / `🌙` / `⚙` for light / dark / system) cycling
  `light → dark → system → light`. Persist to
  `localStorage['zskills-docs-theme']`. Include `aria-label` reflecting
  the current state.
- [ ] Add a theme-toggle module to `docs/docs-app.js` (or a small
  `theme.js` if preferred — sibling file):
  ```js
  function applyTheme() {
    const s = localStorage.getItem('zskills-docs-theme') || 'system';
    const dark = s === 'dark' || (s === 'system' &&
      window.matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
  }
  // On `system` mode, listen for OS-level theme changes:
  window.matchMedia('(prefers-color-scheme: dark)')
    .addEventListener('change', applyTheme);
  ```
- [ ] Add `tests/test-doc-viewer-styling.sh` static-grep contracts:
  - `.nojekyll` exists at repo root.
  - `:root` block exists in `docs/docs.css` with the 9 dark vars
    (`--bg --panel --panel2 --ink --muted --line --accent --accent2
    --code`).
  - `[data-theme="light"]` block exists in `docs/docs.css` with the
    same 9 vars (parallel definitions).
  - FOUC inline `<script>` appears BEFORE
    `<link rel="stylesheet" href="./docs.css">` in `docs/index.html`.
    Implementation: derive `inline_line=$(grep -n
    "data-theme.*setAttribute\|setAttribute.*data-theme"
    docs/index.html | head -1 | cut -d: -f1)` and
    `link_line=$(grep -n 'rel="stylesheet"' docs/index.html | head -1
    | cut -d: -f1)`; assert `[ "$inline_line" -lt "$link_line" ]`.
    Fail with a diagnostic that prints both line numbers if violated.
  - **FOUC inline-script semantics check (v1: static-grep only).**
    The inline `<script>` lives in `index.html`, not a standalone
    `.js` file — the existing Node-DOM extract-and-exec pattern
    cannot `node -e` it directly. For v1 this is treated as a
    static-grep contract: assert (i) the inline script body contains
    `localStorage.getItem('zskills-docs-theme')`, (ii) it sets
    `data-theme` via `document.documentElement.setAttribute`, and
    (iii) it queries `prefers-color-scheme: dark` via
    `window.matchMedia`. Document that a true semantic test
    (extract via `sed -n '/<script>$/,/<\/script>$/p' docs/index.html`
    + eval under a DOM stub) is deferred to v2 — the 3 static-grep
    assertions catch the realistic regression surface (someone
    deleting one of the load-bearing operations), and a
    semantic-extract-and-eval test for an inline HTML script adds
    test-harness complexity disproportionate to the risk.
  - `localStorage` key string `'zskills-docs-theme'` appears in
    `docs/index.html` (inline script) AND `docs/docs-app.js`
    (toggle module).
  - Toggle-button element with `aria-label` exists in
    `docs/index.html`.
- [ ] Register `test-doc-viewer-styling.sh` in `tests/run-all.sh`.
- [ ] Run `bash tests/run-all.sh` to confirm green.

### Design & Constraints
- **Source:** `/tmp/zimulink-lift/docs__docs.css` (193 LOC, light-only).
  Dark mode + toggle is NEW work, not lifted.
- **Default theme:** dark (matches PRESENTATION.html which readers
  already pattern-match).
- **localStorage key:** `zskills-docs-theme`. **States:** `light`,
  `dark`, `system`.
- **FOUC-safe `<head>` ordering** is load-bearing:
  1. `<script>` inline (sets `data-theme` on `<html>`).
  2. `<link rel="stylesheet" href="docs.css">`.
  3. `<script type="module" src="./docs-app.js">` (loaded after parse;
     attaches `matchMedia` listener; binds toggle click handler).
- **CSS selector strategy:** `[data-theme="dark"]` and
  `[data-theme="light"]` on `<html>` (NOT `<body>`) — so the pre-CSS
  inline script can set it before `<body>` parses.
- **Toggle UI:** minimal icon button in the header; emoji glyphs or
  inline SVG, no external icon font.
- **Palette derivation** is anchored on
  `docs/guides/inspecting-and-monitoring.html` for site coherence —
  the hand-off named that file as the visual reference.
- **No SKILL.md edits** in this phase → no `metadata.version` bump
  required.

### Acceptance Criteria
- [ ] `docs/docs.css` has both `:root` (dark) and `[data-theme="light"]`
  blocks with parallel `--bg / --panel / --panel2 / --ink / --muted /
  --line / --accent / --accent2 / --code` definitions (`grep -c "^:root"
  docs/docs.css` returns ≥1; `grep -c '\[data-theme="light"\]'
  docs/docs.css` returns ≥1; both blocks contain all 9 variable names).
- [ ] `docs/index.html` `<head>` has the FOUC inline `<script>` BEFORE
  `<link rel="stylesheet" href="docs.css">` (verified by line-number
  comparison in styling test).
- [ ] First-paint with no localStorage value defaults to `system` mode
  and matches `prefers-color-scheme` (verified by a Node-DOM test that
  stubs `matchMedia` and asserts on `data-theme`).
- [ ] Toggle button cycles `light → dark → system → light`;
  localStorage updates after each click; `data-theme` on
  `<html>` updates immediately (verified by extract-and-exec test that
  simulates clicks).
- [ ] System-mode page responds to OS theme change via
  `matchMedia('(prefers-color-scheme: dark)').addEventListener('change', …)`
  (verified by test that fires a synthetic change event and asserts
  `data-theme` updates).
- [ ] `tests/test-doc-viewer-styling.sh` exits 0; emits
  `Results: N passed, M failed`; registered in `run-all.sh`.
- [ ] Manual smoke (attended): dark + light both look intentional; no
  FOUC visible on hard reload of `docs/index.html`.

### Dependencies
Phase 2a (shell HTML must exist to attach styles + toggle to). Phase 3
does NOT need hash routing — styling layers on the shell, and the
toggle button + theme-state machine are independent of the routing
ingress added in Phase 2b.

## Phase 4 — Catalog generator + visible frontmatter strip

### Goal
Replace the 5-item stub catalog with a scripted, repo-walking generator
(`scripts/build-catalog.sh`) and add the visible
`<div class="zs-frontmatter">` strip ABOVE the H1 of plan files (the
SOURCE strip already landed in Phase 2 — this phase swaps the
`renderFrontmatterStrip` placeholder body for the parsed-fields emitter
and adds its CSS).

### Work Items
- [ ] Write `scripts/build-catalog.sh`. Bash + Python (Python stdlib
  `json` for any structured output — per CLAUDE.md "Python is
  required"). NO jq. NO node CLI.
  - **Output destination is parameterised.** The script writes to the
    path in env var `BUILD_CATALOG_OUT` if set, else to
    `docs/DocsRegistry.js`. This is a SCRIPT feature, not a test-side
    invention — the test in this phase exercises it.
  - Walks `docs/`, groups MD files by directory.
  - Sections derived from subdirs:
    - `docs/README.md` → "Start here" (position 0; single item).
    - `docs/guides/` → "Guides".
    - `docs/skills/` → "Skills" (with `docs/skills/block-diagram/`
      nested as a "Skills > Block diagram" sub-section).
    - `docs/plans/` → "Plans" (single section listing the ~77 active
      entries; v1 keeps it flat — sidebar is long but searchable via
      browser Ctrl-F; subdividing-by-status is deferred to v2).
    - `docs/plans/archive/canaries/` → "Archived plans" (separate
      section, so historical canaries are discoverable without
      bloating the main "Plans" listing).
    - `docs/reports/` → "Reports".
    - `docs/evals/` → "Evals".
  - **Deliberate exclusions for v1.** The following are NOT exposed as
    sidebar sections — they are agent-facing internal artifacts and
    would clutter a user-facing sidebar:
    - `docs/issues/` (issue tracking notes; surfaced via GitHub Issues).
    - `docs/tracking/` (pipeline tracking dumps; agent-only).
    The script MUST skip these directories entirely (no scan, no
    silent inclusion). If a future v2 wants them exposed, add the
    sections explicitly.
  - Sections emitted in this fixed order:
    `Start here, Guides, Skills, Skills > Block diagram, Plans,
    Archived plans, Reports, Evals`.
  - **Items within each section sorted alphabetically by `path`, NOT by
    `name`.** Sorting by name is non-deterministic if an H1 changes
    (a doc rename or rewording shuffles position even though the file
    didn't move); sorting by path is stable across rewordings. Display
    order in the sidebar follows the sorted-by-path order.
  - Item `name` derived from the MD file's H1 if present, else from
    filename (title-cased, underscores/dashes → spaces).
  - Output format MUST be byte-deterministic: stable 2-space indent;
    trailing newline; LF line endings (no CRLF); keys in fixed order
    `name`, `path`; no trailing comma after the final item in any
    array. The test in this phase diffs the regenerated output against
    the committed file; any byte drift fails.
- [ ] Run `BUILD_CATALOG_OUT=docs/DocsRegistry.js
  bash scripts/build-catalog.sh` once and commit the result.
- [ ] Add `tests/test-doc-viewer-catalog.sh`: runs
  `BUILD_CATALOG_OUT=<tmpfile> bash scripts/build-catalog.sh`, then
  `diff -u <tmpfile> docs/DocsRegistry.js`. Fails on any drift —
  this is the regression gate against "you edited a doc but didn't
  re-run the catalog build."
- [ ] **Swap the Phase 2 frontmatter placeholder.** Replace the body of
  `renderFrontmatterStrip(md)` in `docs/docs-app.js` with the parsed-
  fields emitter: detect `^---\n…\n---\n`, parse each line with regex
  `^(\w+):\s*(.+)$` (strip surrounding `'` or `"` quotes from value),
  and return a `<div class="zs-frontmatter">…</div>` string with
  recognized fields rendered in this order: `status`, `completed`,
  `created`, `title`, `issue`. Unknown fields rendered with their
  literal key in muted text. Empty frontmatter (`---\n---\n` with no
  fields) returns the empty string (no strip). The Phase 2
  `stripFrontmatter` helper (which removes the YAML block from the MD
  source before render) is UNCHANGED — only the visible emitter swaps.
  **XSS discipline (mandatory):** every parsed YAML value AND every
  unknown-field key MUST be wrapped in `escapeHtml(...)` before string
  interpolation into the returned HTML. `renderFrontmatterStrip` runs
  OUTSIDE `renderMarkdown`, so `stripUnsafeHtml` (which runs inside the
  renderer on the post-strip body) never touches frontmatter values — a
  malicious value like `title: <img src=x onerror=alert(1)>` would land
  raw in `main.innerHTML` without this wrap. `escapeHtml` is already
  imported by Phase 2 (`renderErrorPane` uses it); this phase reuses
  the same import. AC: `grep -cE "escapeHtml\(" docs/docs-app.js`
  returns ≥ 2 (one call site in `renderErrorPane`, one or more in
  `renderFrontmatterStrip`).
- [ ] Add the matching CSS for `.zs-frontmatter` in `docs/docs.css` —
  a subtle muted strip with small font, separator between fields
  (`·`), no heavy decoration. Both dark and light palettes covered.
- [ ] Add `tests/test-doc-viewer-frontmatter.sh` covering:
  - Plan MD with frontmatter (e.g.,
    `docs/plans/PLUGIN_LANE_VERIFICATION.md`'s fixture) renders the
    `<div class="zs-frontmatter">` strip with `status`, `completed`,
    `created` values.
  - Non-frontmatter MD (e.g., a fragment with no `^---`) renders no
    strip (`<div class="zs-frontmatter">` absent from output).
  - Malformed frontmatter (no closing `---`) silently passes through;
    body still renders.
  - Field rendering order: `status` before `completed` before
    `created` regardless of source order.
- [ ] Register `test-doc-viewer-catalog.sh` and
  `test-doc-viewer-frontmatter.sh` in `tests/run-all.sh`.
- [ ] Run `bash tests/run-all.sh` to confirm green.

### Design & Constraints
- **Catalog regeneration model:** the catalog is regenerated by hand
  (`bash scripts/build-catalog.sh`) when docs are added or renamed; the
  regression test fails if the committed catalog drifts from a fresh
  re-run. This makes the catalog deterministic, reviewable in PR diffs,
  and not coupled to an at-page-load filesystem walk (which would
  require a server).
- **Catalog size reality (verified 2026-06-02 via `find docs -name
  "*.md" | wc -l`):** 178 MD files total. Per-dir breakdown:
  `docs/README.md` = 1, `docs/guides/` = 5, `docs/skills/` = 29,
  `docs/plans/` = 77, `docs/reports/` = 59, `docs/evals/` = 4, plus
  `docs/issues/` = 2 and `docs/tracking/` = 1 which are deliberately
  excluded (see Work Items). Exposed catalog total: 178 − 2 − 1 = 175
  entries. The AC count target accounts for this exclusion.
- **Why sort by `path` not `name`:** path is the file-identity key and
  is stable across rewordings; name is derived from the H1, which
  changes when an agent rewrites a title. Stability matters because
  the byte-diff test (above) is the regression gate — a re-run that
  re-orders by name on every H1 edit would produce spurious diffs.
- **Frontmatter strip recognized fields** (rendered in fixed order):
  `status`, `completed`, `created`, `title`, `issue`. Unknown fields
  rendered with their literal key in muted text (e.g.,
  `customField: value` → `customField: value`).
- **Frontmatter render output order in viewer:**
  1. Optional `<div class="zs-frontmatter">` strip.
  2. Rendered body (with the frontmatter block removed).
  Frontmatter is NEVER rendered inside the body as a code fence or
  visible `---`.
- **Empty-frontmatter case:** `^---\n---\n` (no fields) renders no
  strip; treated as if absent.
- **Top-of-file H1 detection** for catalog `name` derivation: first
  line matching `^# (.+)$` AFTER frontmatter strip; fallback to
  filename if absent.
- **No SKILL.md edits** in this phase → no `metadata.version` bump
  required.

### Acceptance Criteria
- [ ] `scripts/build-catalog.sh` exists, runnable via
  `bash scripts/build-catalog.sh`; uses bash + Python stdlib `json`
  only; no jq, no node.
- [ ] The script honours `BUILD_CATALOG_OUT=<path>` env var:
  `BUILD_CATALOG_OUT=/tmp/cat-out.js bash scripts/build-catalog.sh`
  writes to `/tmp/cat-out.js` and leaves `docs/DocsRegistry.js`
  untouched (asserted in the catalog test).
- [ ] Running `bash scripts/build-catalog.sh` (without
  `BUILD_CATALOG_OUT`) writes to `docs/DocsRegistry.js` containing the
  section ordering listed in Work Items: Start here → Guides → Skills
  → Skills > Block diagram → Plans → Archived plans → Reports → Evals
  (eight sections; `docs/issues/` and `docs/tracking/` deliberately
  excluded).
- [ ] `docs/DocsRegistry.js` has ≥170 entries (178 total MD count
  minus the 3 in `docs/issues/` + `docs/tracking/`; some additional
  exclusions like build-catalog generator artifacts are acceptable).
- [ ] Items within each section sorted by `path` ascending (verified
  by a sort-check assertion in the catalog test; given the byte-diff
  is the regression gate, a deliberate re-order in the committed file
  would fail on re-run).
- [ ] `tests/test-doc-viewer-catalog.sh` passes (no byte drift between
  committed `docs/DocsRegistry.js` and a fresh
  `BUILD_CATALOG_OUT=<tmp> bash scripts/build-catalog.sh` re-run).
- [ ] Plan files with frontmatter (e.g.,
  `docs/plans/PLUGIN_LANE_VERIFICATION.md`) render with a
  `Status · Completed · Created` strip above the H1 (verified by
  frontmatter test asserting on output HTML).
- [ ] Non-frontmatter files (e.g., `docs/guides/WORKFLOWS.md`) render
  with no frontmatter strip (test asserts
  `class="zs-frontmatter"` absent).
- [ ] Malformed frontmatter (no closing `---`) renders the body
  unchanged with no strip and no error (test).
- [ ] `tests/test-doc-viewer-frontmatter.sh` exits 0; emits
  `Results: N passed, M failed`; registered in `run-all.sh`.
- [ ] Catalog miss continues to render the existing inline error pane
  (regression — Phase 2 routing test still passes).
- [ ] `bash tests/run-all.sh` exits 0 on the full suite.

### Dependencies
Phase 2b (catalog wiring + routing in place — the catalog-miss
regression gate at the bottom of this phase requires `routeFromHash`,
which lands in 2b); Phase 1 (renderer in place); Phase 3 (CSS palette
+ `.zs-frontmatter` styling target).

## Phase 5 — Inspecting-and-monitoring.html disposition + URL plumbing

### Goal
Delete the redundant hand-built `docs/guides/inspecting-and-monitoring.html`
(after content-parity verification), rewire any internal references to
the `.md` viewer hash, extend `scripts/build-prod.sh:rewrite_dev_urls()`
for any new viewer file that embeds dev URLs, and add the `.nojekyll`
regression gate.

### Work Items
- [ ] **Parity verification (gate before deletion) — automated text
  extract + diff, not eyeball.** A `/run-plan` verifier cannot judge
  visual parity, so the gate must be a falsifiable text comparison
  (Round-1 finding DA #12). Procedure:
  1. Extract visible text from
     `docs/guides/inspecting-and-monitoring.html` via Python's
     `html.parser` (stdlib): walk the parse tree, emit `data` from
     every node except `<script>` and `<style>`, collapse whitespace.
     Save as `/tmp/im-html-text.txt`.
  2. Render `docs/guides/INSPECTING_AND_MONITORING.md` to HTML by
     invoking `docs/MarkdownRenderer.js` under Node (extract-and-exec,
     same harness pattern as the test suites), then run the same
     `html.parser` text extraction. Save as `/tmp/im-md-text.txt`.
  3. Run `diff -u /tmp/im-html-text.txt /tmp/im-md-text.txt` and
     attach the diff to the PR description.
  4. The acceptable-diff set is itemised in
     `docs/guides/INSPECTING_AND_MONITORING.md`'s top-of-file
     `<!-- doc-viewer-parity: ack -->` allow-list block (added in
     this phase if absent) — e.g., "hero card text", "pill labels",
     "draft badge". Each ack line names a text fragment found in HTML
     but absent from MD that the implementing agent confirms is
     decorative.
  5. ALSO capture side-by-side screenshots via `playwright-cli` (one
     for `inspecting-and-monitoring.html` direct, one for
     `#docs/guides/INSPECTING_AND_MONITORING.md` via the viewer) for
     the PR description — visual chrome confirmation is supplementary
     to the text-diff gate, not a replacement.
- [ ] **Branch on parity result:**
  - **If parity holds:** proceed with deletion.
  - **If `.html` has prose the `.md` lacks:** HOLD the deletion; file
    a follow-up GitHub issue titled "Backport
    inspecting-and-monitoring.html unique prose to MD" with the
    extracted diff; this phase ships WITHOUT the delete; mark this
    sub-step in the Progress Tracker; the plan completes.
- [ ] `git rm docs/guides/inspecting-and-monitoring.html` (only if
  parity held).
- [ ] `grep -rn "inspecting-and-monitoring.html" .` (excluding `.git/`
  and `docs/reports/` historical files) — find any internal
  references; rewrite each to
  `docs/guides/INSPECTING_AND_MONITORING.md` (filesystem path) or
  `#docs/guides/INSPECTING_AND_MONITORING.md` (viewer hash) as
  appropriate per call site.
- [ ] **`build-prod.sh` extension check (likely no-op).** The viewer
  files added by this plan (`docs/index.html`, `docs/docs-app.js`,
  `docs/MarkdownRenderer.js`, `docs/DocsRegistry.js`, `docs/docs.css`)
  do NOT embed dev-URL strings by construction — paths are
  repo-root-relative or sibling-relative; the GitHub fallback uses
  `https://github.com/zeveck/zskills/blob/main/...` (not the dev
  Pages URL). Run `grep -rn 'zeveck\.github\.io/zskills-dev' docs/` as
  a falsification check: if it returns 0 hits, leave
  `scripts/build-prod.sh` unchanged and record the grep output in the
  PR description as evidence. If it returns ≥1 hit, add one
  `rewrite_dev_urls <relpath>` line per file to
  `scripts/build-prod.sh` after the existing `rewrite_dev_urls
  README.md` call (verify line number at edit time — the existing
  comment cited line 72 may have shifted; locate via
  `grep -n 'rewrite_dev_urls README.md' scripts/build-prod.sh`).
  Convert this step to a "note, not work" entry in the implementing
  agent's report when the check is clean.
- [ ] Add `tests/test-doc-viewer-nojekyll.sh`: asserts `.nojekyll`
  exists at repo root and is byte-empty (or at least exists). This is
  the regression gate against accidental deletion — `.nojekyll` is
  load-bearing because it blocks Jekyll's `{{...}}` evaluation across
  ~700 MD files; without it the prod build silently breaks.
- [ ] Register `test-doc-viewer-nojekyll.sh` in `tests/run-all.sh`.
- [ ] **Final attended smoke** (PR-blocker for human review):
  - All 5 catalog sections (or 10 in the full Phase 4 catalog)
    expand correctly in the sidebar.
  - Theme toggle cycles `light → dark → system → light`; localStorage
    persists across reload.
  - Deep-link hash (`#docs/plans/PLUGIN_LANE_VERIFICATION.md`)
    renders with the frontmatter `Status · Completed · Created` strip.
  - Browser back/forward navigates the hash history correctly.
  - Internal `.md` link click updates the hash and re-renders without
    full page reload.
  - Off-catalog hash renders the inline error pane.
  - Dev URL `https://zeveck.github.io/zskills-dev/docs/` (or local
    `python3 -m http.server` equivalent) renders the docs home.
- [ ] Run `bash tests/run-all.sh` to confirm full suite green
  (including all 5 phases' tests).

### Design & Constraints
- **Deletion gate is parity, not assumption.** The codebase research
  asserts content parity (HTML 342 LOC, MD 340 LOC, "content parity"),
  but the implementing agent MUST verify, not trust. If the verification
  finds a prose gap, the deletion is held and a follow-up issue is
  filed — the plan completes without the delete.
- **`rewrite_dev_urls` extension is at most additive 1-liner.** The
  existing call site is `scripts/build-prod.sh:72`
  (`rewrite_dev_urls README.md`). Adding lines like
  `rewrite_dev_urls docs/index.html` is a 1-LOC change per file.
- **`.nojekyll` regression test is mandatory** — this single empty file
  blocks Jekyll's `{{...}}` evaluation across all ~700 MD files. Its
  accidental deletion would silently break the prod build.
- **Internal references to `inspecting-and-monitoring.html`** likely
  exist in `docs/guides/WORKFLOWS.md`, `README.md`, or
  `PRESENTATION.html`. The `grep -rn` work item enumerates them; the
  rewrite is mechanical.
- **No SKILL.md edits** in this phase → no `metadata.version` bump
  required.

### Acceptance Criteria
- [ ] Parity verification recorded in the PR description with
  side-by-side screenshots (manual gate; PR-blocker).
- [ ] If parity held: `docs/guides/inspecting-and-monitoring.html`
  removed from the repo (`test -e` returns false; `git log -- <path>`
  shows the `git rm` commit).
- [ ] If parity gap: follow-up issue exists (`gh issue list --search
  "Backport inspecting-and-monitoring.html unique prose"` returns ≥1
  hit); deletion held; this state recorded in the plan's Progress
  Tracker.
- [ ] No remaining references to `inspecting-and-monitoring.html` in
  the codebase (excluding `.git/` and `docs/reports/` historical
  files): `grep -rn "inspecting-and-monitoring.html" . --exclude-dir=.git --exclude-dir=docs/reports`
  returns no hits.
- [ ] `scripts/build-prod.sh` either unchanged (no new dev URLs in
  viewer files; verified by grep) OR extended with the necessary
  `rewrite_dev_urls` calls.
- [ ] `tests/test-doc-viewer-nojekyll.sh` exists, asserts `.nojekyll`
  at repo root, exits 0, emits `Results: N passed, M failed`,
  registered in `run-all.sh`.
- [ ] `bash tests/run-all.sh` exits 0 across all phases' tests + the
  full pre-existing suite.
- [ ] Final attended smoke confirms theme toggle, deep-link hash,
  frontmatter strip, back/forward, internal link click, off-catalog
  error pane, and dev-URL landing — all working (recorded in PR
  description).

### Dependencies
Phases 1-4 all complete. In particular, the parity-verification step
above requires `docs/DocsRegistry.js` to contain the
`docs/guides/INSPECTING_AND_MONITORING.md` entry (Phase 4 catalog must
have run) so the viewer can resolve the `#docs/guides/INSPECTING_AND_MONITORING.md`
hash without falling into the error pane. The catalog generator's
inclusion rule for `docs/guides/` already covers this; the gate is the
catalog being run, not a special-case entry.

## Round 2 disposition

| # | Source | Severity | Phase | Evidence | Disposition |
|---|--------|----------|-------|----------|-------------|
| 1 | DA #1 | critical | 1 | Verified — `grep -n stripUnsafeHtml` showed only the def (L139) + 1 AC (L269); zero call sites in the render pipeline | Fixed — added explicit Work Item modifying `renderMarkdown` body to insert `md = stripUnsafeHtml(md);` as the first executable line; added AC asserting `grep -nE` matches exactly 1 hit at line ≤ 25 |
| 2 | DA #2 | critical | 2 | Verified — pre-fix `grep -n escapeHtml` showed it used by `renderErrorPane` (L438) but the import-rewrite bullet listed only `renderMarkdown`; first off-catalog hash would ReferenceError | Fixed — import-rewrite now reads `import { renderMarkdown, escapeHtml } from './MarkdownRenderer.js';`; added AC `grep -cE "import \{[^}]*\bescapeHtml\b[^}]*\}"` returns 1 |
| 3 | R #1 + DA #3 | major | 2 | Verified against upstream `docs__docs-app.js`: L28 `link.addEventListener('click', () => loadDoc(item, link))` (sidebar) and L193-221 (main click) both call `loadDoc` directly; removing `history.replaceState` from `loadDoc` (per the plan) breaks URL sync without handler rewrites | Fixed — added two Work Items: (1) sidebar handler now sets `location.hash` and lets hashchange drive a single load (with explicit reasoning that pre-setting `lastHandledHash` would BAIL on first load and is the trap); sidebar build now emits `<a data-path=...>` for `findNavEl`. (2) main click L193-221 replaced with `resolveLink` + `location.hash` set; off-catalog branch subsumed by `renderErrorPane`. Added 4 ACs (no `loadDoc(item, navItems[idx])`, ≥2 `location.hash =` writes, `data-path` attribute, single-fire spy assertion) |
| 4 | DA #4 | major | 2 | Verified — `findCatalogItem`, `findNavEl`, `scrollToAnchor` were referenced inside `routeFromHash` but no bodies anywhere in the plan | Fixed — added Work Item with explicit bodies (DOCS_CATALOG flatten + path match; `nav.querySelector('a[data-path="..."]')`; `getElementById` + `scrollIntoView`). Added 3 grep ACs. Slug-form requirement for anchor authors documented inline |
| 5 | R #2 | minor | 2 | Verified — `sed -n '60,75p'` of upstream `docs__index.html` shows L65 `<!-- Password gate -->` as the orphan comment directly above the now-deleted `<div id="zl-gate">` | Fixed — added explicit strip bullet for L65; AC `grep -c 'Password gate' docs/index.html` returns 0 |
| 6 | R #3 | minor | 2 | Verified — current corpus has no `docs/**/*.md` opening with content-HR `---\n`; risk is real but corpus-clean | Fixed — added Design note describing the heuristic, the corpus check date, the regression-surface symptom ("first paragraph missing"), and the v2 tightening option (require line 2 match `^[a-zA-Z_][\w-]*:\s`) |
| 7 | R #4 | minor | 3 | Verified — `grep -n 'color-primary-light' /tmp/zimulink-lift/docs__docs.css`: L78/81 (nav hover/active) and L103/109 (code/pre); collapsing both onto `--panel2` loses the code-block accent | Fixed — split remap in Phase 3 Work Items: nav uses → `var(--panel2)`, code/pre → `var(--code)`; cited specific zimulink line numbers; flagged L163/179/180 fall inside the stripped newsletter block |
| 8 | DA #5 | minor | 3 | Verified — the FOUC inline `<script>` lives in `index.html`, not a `.js` file, so the existing extract-and-exec pattern cannot directly `node -e` it | Fixed — Phase 3 styling test now explicitly scoped to static-grep contracts on the inline body (localStorage key, `setAttribute('data-theme', ...)`, `matchMedia` query); semantic eval-under-DOM-stub deferred to v2 with reasoning |
| 9 | DA #6 | minor | 2/4 | Verified — `indexOf("\n---\n", 4)` on input `---\n---\n# H` returns -1 because the closing `\n---\n` starts at offset 3; round-1 implementation would mis-handle the empty-FM case | Fixed — added `if (md.startsWith('---\n---\n')) return md.slice(8);` precheck inside `stripFrontmatter`; added Phase 2 routing-test fixture asserting empty-FM input renders only `<h1>H</h1>` (no `<hr>`) |
| 10 | R #5 | nit | 2 | Verified — upstream's initial-load block at L34-55 is bare top-level code, not a `(function(){...})()` IIFE | Fixed — reworded the one occurrence in Phase 2 to "top-level eager block ... NOT an IIFE" with timing note. The Phase 3 FOUC inline script remains correctly labeled as an IIFE (it actually is one) |
| 11 | R #6 | nit | 2 | Verified — `'docs/X.md#sec#sub'.split('#', 2)` yields `['docs/X.md', 'sec']` and DROPS `#sub`; slugify strips `#` from heading text so corpus-safe today, but cheap to fix | Fixed — replaced `raw.split('#', 2)` in `routeFromHash` with `indexOf` + slice; inline comment explains the JS `.split(sep, limit)` truncation gotcha and corpus-safety today |

> Round 2 refinement complete: addressed 11/11 findings (11 Fixed, 0 Justified). Updated plan is 1333 lines.

## Plan Quality

**Drafting process:** `/draft-plan` with 3 rounds of adversarial review (reviewer + devil's-advocate in parallel each round; refiner verify-before-fix in between).

**Convergence:** Reviewer round 3 returned CONVERGED (0 findings); devil's advocate round 3 returned NEAR-CONVERGED (2 findings — 1 major XSS gap in `renderFrontmatterStrip`, 1 minor sidebar-range ambiguity). Both round-3 findings were landed in-place by the orchestrator (the major adds an explicit `escapeHtml(...)` wrap + matching AC to Phase 4's frontmatter emitter; the minor tightens Phase 2's sidebar-rewrite scope to the inner item loop with an outer-loop-preserved AC).

**Remaining concerns:** None blocking execution. v2 watchlist documented inline: `<sub>`/`<kbd>`/`<span>` inline-HTML escape (intentional v1 limitation; locked via positive AC), `stripFrontmatter` heuristic false-positive risk (corpus-clean today; future regression would surface as "first paragraph missing"), FOUC inline-script semantic eval-under-DOM-stub (deferred — static-grep contracts cover the realistic regression surface), search (out of scope; v2 decision among lunr/MiniSearch, Algolia DocSearch, or none).

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 14                | 18 (5 critical, 10 major, 3 minor) | 29/29 (with overlap; 0 deferred) |
| 2     | 6 (0 critical, 1 major, 3 minor, 2 nit) | 6 (2 critical, 2 major, 2 minor) | 11/11 (0 deferred) |
| 3     | 0 (CONVERGED)     | 2 (1 major, 1 minor)      | 2/2 (in-place by orchestrator) |
| Refine 1 (post-PR-#975) | 5 (2 major, 3 minor) | 4 (2 critical, 2 major) | 9/9 (0 deferred) |

### Refinement round (post-PR-#975)

A single `/refine-plan` round (1 reviewer + 1 devil's advocate dispatched in
parallel; refiner verify-before-fix). Scope was the user-requested Phase 2
→ Phase 2a/Phase 2b structural split: 2a lifts the shell + stub catalog +
frontmatter helpers + sanity smoke (intentionally unstyled — Phase 3 ships
the palette); 2b layers hash routing + helpers + handler rewrites + error
pane + the routing-test suite on top. Phases 1, 3, 4, 5 were NOT renumbered;
Phase 3 dep updated to "Phase 2a", Phase 4 dep updated to "Phase 2b". The
critical empirical re-check was that the L101-173 renderer call site
references `renderFrontmatterStrip` + `stripFrontmatter` directly, so both
helpers MUST land in 2a (deferring them to 2b would `ReferenceError` on
module load). Upstream's eager initial-load block (lines 34-55) is preserved
verbatim in 2a (positive presence AC `grep -c 'DOCS_CATALOG\[0\]'` ≥ 1) and
removed in 2b (parallel negative AC `grep -c 'DOCS_CATALOG\[0\]'` = 0).
The 5 stub-catalog files have no YAML frontmatter (verified via `head -8`
on each), so 2a's render path is pure pass-through for the stub catalog —
the frontmatter helpers are still load-bearing as references but exercise
nothing until plan files are in the catalog (Phase 4).

### Drift Log

No completed phases — all phases were reviewed as remaining at refinement
time. Refinement applied a Phase 2 → 2a/2b structural split per round-1
DA + reviewer + user direction; Phase 3/4 dependency lines updated;
Phase 1 + Phase 5 internals preserved byte-for-byte; the Plan Quality
round-history rows 1-3 preserved byte-for-byte; the Pre-flight section
preserved byte-for-byte. Only additive edits to Plan Quality: a new
"Refine 1" row in the Round History table and this Refinement-round
subsection.

### Pre-flight requirements (must hold before Phase 1 begins)

1. `gh auth status` succeeds and the authenticated identity has read access to the **private** `zeveck/zimulink` repo. Verify with `gh api repos/zeveck/zimulink/contents/docs/index.html` returning HTTP 200.
2. Lift sources at `/tmp/zimulink-lift/` are populated (cached during research; re-fetch with `gh api repos/zeveck/zimulink/contents/<path>` if missing).
3. `bash tests/run-all.sh` baseline passes on `main` before any phase starts.
4. `.nojekyll` at repo root exists and is empty (0 bytes). `cat .nojekyll | wc -c` returns 0.

