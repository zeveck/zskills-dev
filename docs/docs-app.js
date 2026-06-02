/**
 * Standalone docs page app logic.
 * Imports MarkdownRenderer and DocsRegistry from sibling modules.
 */

import { renderMarkdown } from './MarkdownRenderer.js';
import { DOCS_CATALOG } from './DocsRegistry.js';

const nav = document.getElementById('zl-docs-nav');
const main = document.getElementById('zl-docs-main');

const cache = {};
let activeNavItem = null;

// Build sidebar navigation
for (const section of DOCS_CATALOG) {
  const header = document.createElement('div');
  header.className = 'zl-docs-section-header';
  header.textContent = section.section;
  nav.appendChild(header);

  for (const item of section.items) {
    const link = document.createElement('div');
    link.className = 'zl-docs-nav-item';
    link.textContent = item.name;
    link.addEventListener('click', () => loadDoc(item, link));
    nav.appendChild(link);
  }
}

// Load from URL hash or fall back to first doc
let loaded = false;
if (location.hash) {
  const target = location.hash.slice(1);
  const navItems = nav.querySelectorAll('.zl-docs-nav-item');
  let idx = 0;
  for (const section of DOCS_CATALOG) {
    for (const item of section.items) {
      if (item.path === target || item.name.toLowerCase().replace(/\s+/g, '-') === target) {
        loadDoc(item, navItems[idx]);
        loaded = true;
      }
      idx++;
    }
  }
}
if (!loaded) {
  const firstItem = DOCS_CATALOG[0]?.items[0];
  if (firstItem) {
    const firstNav = nav.querySelector('.zl-docs-nav-item');
    loadDoc(firstItem, firstNav);
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

async function loadDoc(item, navEl) {
  // Update active state
  if (activeNavItem) activeNavItem.classList.remove('active');
  if (navEl) {
    navEl.classList.add('active');
    activeNavItem = navEl;
  }

  // Update URL hash for deep-linking (so copying the URL shares the current page)
  history.replaceState(null, '', '#' + item.path);

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
    main.innerHTML = '<p style="color:#f44336">Could not load document.</p>';
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

// Intercept internal anchor links and doc-to-doc links
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

  // Internal doc link (e.g., ../guides/X.md#anchor)
  if (href.endsWith('.md') || href.includes('.md#')) {
    e.preventDefault();
    const [rawPath, hash] = href.split('#');
    // Resolve path: strip leading ../ since our catalog paths are repo-relative
    const path = rawPath.replace(/^(\.\.\/)+/, '');
    // Find matching nav item
    const navItems = nav.querySelectorAll('.zl-docs-nav-item');
    let idx = 0;
    for (const section of DOCS_CATALOG) {
      for (const item of section.items) {
        if (item.path === path) {
          loadDoc(item, navItems[idx]).then(() => {
            if (hash) {
              const target = main.querySelector('#' + CSS.escape(hash));
              if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }
          });
          return;
        }
        idx++;
      }
    }

    // Not in catalog — load directly
    const name = path.split('/').filter(Boolean).slice(-2, -1)[0] || 'Document';
    const displayName = name.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
    loadDoc({ path, name: displayName }, null);
    return;
  }
});
