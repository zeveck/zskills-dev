/**
 * Standalone docs page app logic.
 * Imports MarkdownRenderer and DocsRegistry from sibling modules.
 *
 * Phase 2b — hash-routing layer:
 *   All navigation flows through `location.hash` → `hashchange` →
 *   `routeFromHash` → `loadDoc`. Sidebar clicks and in-page internal
 *   links both set the hash; the single-ingress invariant means no
 *   direct `loadDoc(...)` call escapes that path.
 */

import { renderMarkdown, escapeHtml } from './MarkdownRenderer.js';
import { DOCS_CATALOG } from './DocsRegistry.js';

const nav = document.getElementById('zl-docs-nav');
const main = document.getElementById('zl-docs-main');

const cache = {};
let activeNavItem = null;

// Dedupe routing: `hashchange` may fire spuriously and `DOMContentLoaded`
// also drives the same path, so we remember the last raw hash we handled
// and bail early when it hasn't changed. Initialized to `null` (NOT to
// `location.hash.slice(1)`) so the first call from `DOMContentLoaded`
// always loads. Do not pre-set this from the sidebar handler — browser
// no-ops same-value hash assignment, which prevents double-fire there.
let lastHandledHash = null;

// Build sidebar navigation. The outer loop (sections + section headers)
// is preserved verbatim from upstream; the inner item loop is rewritten
// to emit `<a data-path>` anchors that route via `location.hash` rather
// than calling `loadDoc` directly.
for (const section of DOCS_CATALOG) {
  const header = document.createElement('div');
  header.className = 'zl-docs-section-header';
  header.textContent = section.section;
  nav.appendChild(header);

  for (const item of section.items) {
    const link = document.createElement('a');
    link.className = 'zl-docs-nav-item';
    link.textContent = item.name;
    link.href = '#' + item.path;        // anchor semantics + URL preview
    link.setAttribute('data-path', item.path);
    link.addEventListener('click', (e) => {
      e.preventDefault();
      location.hash = '#' + item.path;
      // hashchange fires → routeFromHash → loadDoc (single ingress).
      // Browser no-ops same-value hash assignment, so a second click on
      // the same entry won't double-load.
    });
    nav.appendChild(link);
  }
}

// ---------------------------------------------------------------------------
// Frontmatter source-strip helpers (DOC_VIEWER Phase 2a).
//
// stripFrontmatter: remove a leading YAML `---\n…\n---\n` block before the
// markdown is fed to renderMarkdown. Without this, the renderer's HR rule
// (^---+$) treats the frontmatter opener AND closer as horizontal rules and
// renders the metadata lines as plain paragraphs between them. Handles the
// empty-frontmatter shape (`---\n---\n`) explicitly because the offset-4
// `indexOf('\n---\n', 4)` search would otherwise miss the closer.
//
// renderFrontmatterStrip: placeholder body returning '' in Phase 2a. Phase 4
// swaps this for a parsed-fields `<div class="zs-frontmatter">…</div>`
// emitter. The function MUST exist in Phase 2a so the renderer call site
// (in loadDoc below) parses without ReferenceError on first paint.
// ---------------------------------------------------------------------------
function stripFrontmatter(md) {
  if (!md.startsWith('---\n')) return md;
  if (md.startsWith('---\n---\n')) return md.slice(8);
  const close = md.indexOf('\n---\n', 4);
  if (close === -1) return md;
  return md.slice(close + 5);
}

function renderFrontmatterStrip(md) {
  return '';
}

// ---------------------------------------------------------------------------
// Hash-routing helpers (DOC_VIEWER Phase 2b).
//
// findCatalogItem / findNavEl / scrollToAnchor / currentHashPath /
// resolveLink / renderErrorPane are all net-new. `routeFromHash` is the
// single ingress.
// ---------------------------------------------------------------------------
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
  // `anchor` is the URL fragment AFTER the second `#` (e.g. `section-name`).
  // Headings emit id=slugify(text) per the Phase 1 renderer; anchor authors
  // must use slug form (lowercase, hyphenated, ASCII alnum only). A literal
  // `#Section Name` will NOT match — must be `#section-name`.
  if (!anchor) return;
  const el = document.getElementById(anchor);
  if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function currentHashPath() {
  const raw = location.hash.slice(1);
  const hashIdx = raw.indexOf('#');
  return hashIdx < 0 ? raw : raw.slice(0, hashIdx);
}

function resolveLink(href, basePath) {
  // basePath is the path part of location.hash (no leading '#').
  // We use a synthetic origin so the URL constructor resolves relative
  // paths (`../guides/X.md`) against the current doc's directory.
  const base = new URL('https://x/' + basePath, 'https://x/');
  const u = new URL(href, base);
  return u.pathname.slice(1) + u.hash;
}

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

function routeFromHash() {
  const raw = location.hash.slice(1);          // strip leading '#'
  if (raw === lastHandledHash) return;          // dedupe re-renders
  lastHandledHash = raw;

  // Split on the FIRST '#' (path part vs. section anchor). We use
  // indexOf+slice instead of `raw.split('#', 2)` because JS's
  // `.split(sep, limit)` truncates to N substrings and DISCARDS any
  // remainder — a hash like `docs/X.md#sec#sub` would drop `#sub`.
  const hashIdx = raw.indexOf('#');
  const pathPart = hashIdx < 0 ? raw : raw.slice(0, hashIdx);
  const anchor   = hashIdx < 0 ? ''  : raw.slice(hashIdx + 1);
  const targetPath = pathPart || 'docs/README.md';

  const item = findCatalogItem(targetPath);
  if (item) {
    loadDoc(item, findNavEl(item)).then(() => scrollToAnchor(anchor));
  } else {
    renderErrorPane(targetPath);
  }
}

async function loadDoc(item, navEl) {
  // Update active state
  if (activeNavItem) activeNavItem.classList.remove('active');
  if (navEl) {
    navEl.classList.add('active');
    activeNavItem = navEl;
  }

  // Check cache
  if (cache[item.path]) {
    renderDoc(item, cache[item.path]);
    return;
  }

  main.innerHTML = '<p style="color:#888">Loading&hellip;</p>';

  try {
    // Paths are relative to repo root; from /docs/ we need to go up one level
    const res = await fetch('../' + item.path);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const md = await res.text();
    cache[item.path] = md;
    renderDoc(item, md);
  } catch {
    // Off-catalog fallback: render the inline error pane with a GitHub
    // source link. The pane works equally well for catalog-miss (routed
    // here from routeFromHash) and for fetch-404 (which lands here via
    // the throw above).
    renderErrorPane(item.path);
  }
}

function renderDoc(item, md) {
  // Determine base URL for resolving relative paths
  const pathParts = item.path.split('/');
  pathParts.pop();
  const baseUrl = pathParts.length > 0 ? '../' + pathParts.join('/') + '/' : '../';

  main.innerHTML = renderFrontmatterStrip(md) + renderMarkdown(stripFrontmatter(md), { baseUrl });

  main.scrollTop = 0;
}

// Intercept internal anchor links and doc-to-doc links. Doc-to-doc links
// now route via `location.hash` (single-ingress); in-page `#section`
// anchors are still handled inline.
main.addEventListener('click', (e) => {
  const link = e.target.closest('a');
  if (!link) return;
  const href = link.getAttribute('href');
  if (!href) return;

  // Anchor link within current page
  if (href.startsWith('#')) {
    e.preventDefault();
    const target = main.querySelector(href);
    if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    return;
  }

  // Internal doc link (e.g., ../guides/X.md#anchor). Route via
  // location.hash so hashchange → routeFromHash → loadDoc is the single
  // ingress; the section anchor (if any) is carried inside the resolved
  // path and parsed back out by routeFromHash.
  if (href.endsWith('.md') || href.includes('.md#')) {
    e.preventDefault();
    const resolved = resolveLink(href, currentHashPath());
    location.hash = '#' + resolved;
    return;
  }
});

// ---------------------------------------------------------------------------
// Routing listeners (DOC_VIEWER Phase 2b).
// `hashchange` covers sidebar clicks + manual URL-bar edits + internal
// link clicks. `popstate` covers browser back/forward. `DOMContentLoaded`
// covers initial page load (including deep-links typed into a fresh tab).
// ---------------------------------------------------------------------------
window.addEventListener('hashchange', routeFromHash);
window.addEventListener('popstate', routeFromHash);
document.addEventListener('DOMContentLoaded', routeFromHash);
