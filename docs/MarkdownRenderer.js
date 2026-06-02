// MarkdownRenderer — shared markdown→HTML renderer.
// Source: zeveck/zimulink:src/ui/MarkdownRenderer.js (lifted 2026-06-02).
// License posture: single-author lift; both repos share the same author.
// Design intent: zero-deps hand-rolled MD→HTML — small, inspectable, no
// supply-chain surface. Lift is verbatim; the only addition is
// `stripUnsafeHtml` wired into `renderMarkdown` to remove script/iframe/
// handler/comment surfaces before parsing. Supports: headings, bold,
// italic, inline code, code blocks, lists, links, images, hr, paragraphs,
// tables, and blockquotes. Used by WhatsNewDialog and DocsDialog.

/** Strip script/iframe/object/embed, inline handlers, and HTML comments. */
function stripUnsafeHtml(s) {
  return s
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<\/?(?:iframe|object|embed)\b[^>]*>/gi, '')
    // Scheme-strip from href= / src= attribute values. Neutralize
    // javascript:/vbscript:/data:text/html (and HTML-entity-encoded variants
    // that decode to those schemes at render time) by replacing the scheme
    // with about:blank#blocked-scheme-<original>. Apply BEFORE on*= stripping
    // so the on*= regex's quote handling isn't disturbed by our edit.
    //
    // Defense covers: javascript:, vbscript:, data:text/html (case-insensitive,
    // leading whitespace tolerated). Also catches HTML-entity-encoded forms
    // like &#x6A;avascript: by neutralizing any href=/src= attribute value
    // starting with &# (HTML numeric entities have no legitimate use in URL
    // schemes — real URLs use percent-encoding for non-ASCII). Issue #983.
    .replace(
      /(\s(?:href|src)\s*=\s*["']?)[\s]*(javascript|vbscript|data:text\/html)/gi,
      '$1about:blank#blocked-scheme-$2'
    )
    .replace(
      /(\s(?:href|src)\s*=\s*["']?)[\s]*&#/gi,
      '$1about:blank#blocked-entity-encoded&#'
    )
    .replace(/\s+on\w+\s*=\s*"[^"]*"/gi, '')
    .replace(/\s+on\w+\s*=\s*'[^']*'/gi, '')
    .replace(/\s+on\w+\s*=\s*[^\s>]+/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '');
}

/** Render markdown text to HTML. options: { baseUrl?: string } */
export function renderMarkdown(md, options) {
  md = stripUnsafeHtml(md);
  const baseUrl = (options && options.baseUrl) || 'getting-started/';
  const lines = md.split('\n');
  const out = [];
  let i = 0;
  let inList = false;
  let listTag = '';

  function closeList() {
    if (inList) {
      out.push(`</${listTag}>`);
      inList = false;
    }
  }

  while (i < lines.length) {
    const line = lines[i];

    // HTML block passthrough — self-closing and inline tags (br, hr, iframe)
    if (/^<(br|hr)\s*\/?\s*>/.test(line.trim()) || /^<(iframe|h[1-6]|a)[\s>]/.test(line.trim())) {
      closeList();
      out.push(line);
      i++;
      continue;
    }

    // HTML block passthrough — container elements (details, div, section, etc.)
    if (/^<(details|div|section|figure|aside)[\s>]/.test(line.trim())) {
      closeList();
      const tagMatch = line.trim().match(/^<(\w+)/);
      const tag = tagMatch[1];
      const htmlLines = [lines[i]];
      i++;
      let depth = 1;
      while (i < lines.length && depth > 0) {
        const l = lines[i];
        if (new RegExp(`<${tag}[\\s>]`).test(l)) depth++;
        if (new RegExp(`</${tag}>`).test(l)) depth--;
        htmlLines.push(l);
        i++;
      }
      const openTag = htmlLines[0];
      const closeTag = htmlLines[htmlLines.length - 1];
      const innerLines = htmlLines.slice(1, -1);
      const innerHtml = innerLines.length > 0
        ? renderMarkdown(innerLines.join('\n'), options)
        : '';
      out.push(openTag + '\n' + innerHtml + '\n' + closeTag);
      continue;
    }

    // HTML block passthrough — summary tag
    if (/^<\/?(summary)[\s>]/.test(line.trim())) {
      closeList();
      out.push(line);
      i++;
      continue;
    }

    // Fenced code block
    if (line.startsWith('```')) {
      closeList();
      const lang = line.slice(3).trim();
      i++;
      const codeLines = [];
      while (i < lines.length && !lines[i].startsWith('```')) {
        codeLines.push(escapeHtml(lines[i]));
        i++;
      }
      i++; // skip closing ```
      out.push(`<pre><code${lang ? ` class="language-${lang}"` : ''}>${codeLines.join('\n')}</code></pre>`);
      continue;
    }

    // Horizontal rule
    if (/^---+$/.test(line.trim())) {
      closeList();
      out.push('<hr>');
      i++;
      continue;
    }

    // Table: detect lines starting with |
    if (line.trimStart().startsWith('|')) {
      closeList();
      const tableLines = [];
      while (i < lines.length && lines[i].trimStart().startsWith('|')) {
        tableLines.push(lines[i]);
        i++;
      }
      out.push(renderTable(tableLines, baseUrl));
      continue;
    }

    // Headings
    const headingMatch = line.match(/^(#{1,6})\s+(.*)/);
    if (headingMatch) {
      closeList();
      const level = headingMatch[1].length;
      const rawText = headingMatch[2];
      const id = slugify(rawText);
      out.push(`<h${level} id="${id}">${inlineMarkdown(rawText, baseUrl)}</h${level}>`);
      i++;
      continue;
    }

    // Unordered list item
    if (/^[-*]\s+/.test(line)) {
      if (!inList || listTag !== 'ul') {
        closeList();
        out.push('<ul>');
        inList = true;
        listTag = 'ul';
      }
      let itemText = line.replace(/^[-*]\s+/, '');
      i++;
      // Lazy-continuation: lines indented with whitespace (and not themselves
      // starting a new list item) belong to the current item.
      while (i < lines.length && /^\s+\S/.test(lines[i]) &&
             !/^\s*[-*]\s+/.test(lines[i]) &&
             !/^\s*\d+\.\s+/.test(lines[i])) {
        itemText += ' ' + lines[i].trim();
        i++;
      }
      // GFM task list checkbox
      const taskMatch = itemText.match(/^\[([ xX])\]\s+(.*)/);
      if (taskMatch) {
        const checked = taskMatch[1].toLowerCase() === 'x' ? ' checked' : '';
        out.push(`<li class="task-list-item"><input type="checkbox"${checked} class="zl-task-checkbox"> ${inlineMarkdown(taskMatch[2], baseUrl)}</li>`);
      } else {
        out.push(`<li>${inlineMarkdown(itemText, baseUrl)}</li>`);
      }
      continue;
    }

    // Ordered list item
    if (/^\d+\.\s+/.test(line)) {
      if (!inList || listTag !== 'ol') {
        closeList();
        out.push('<ol>');
        inList = true;
        listTag = 'ol';
      }
      let itemText = line.replace(/^\d+\.\s+/, '');
      i++;
      while (i < lines.length && /^\s+\S/.test(lines[i]) &&
             !/^\s*[-*]\s+/.test(lines[i]) &&
             !/^\s*\d+\.\s+/.test(lines[i])) {
        itemText += ' ' + lines[i].trim();
        i++;
      }
      out.push(`<li>${inlineMarkdown(itemText, baseUrl)}</li>`);
      continue;
    }

    // Close list if we're no longer in one
    closeList();

    // Blockquote — collect consecutive > lines, strip prefix, render recursively
    if (/^>\s?/.test(line)) {
      const bqLines = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) {
        bqLines.push(lines[i].replace(/^>\s?/, ''));
        i++;
      }
      out.push(`<blockquote>${renderMarkdown(bqLines.join('\n'), options)}</blockquote>`);
      continue;
    }

    // Blank line
    if (line.trim() === '') {
      i++;
      continue;
    }

    // Paragraph — collect consecutive non-special lines
    const paraLines = [];
    while (i < lines.length && lines[i].trim() !== '' &&
           !lines[i].startsWith('#') && !lines[i].startsWith('```') &&
           !/^---+$/.test(lines[i].trim()) && !/^[-*]\s+/.test(lines[i]) &&
           !/^\d+\.\s+/.test(lines[i]) && !lines[i].trimStart().startsWith('|') &&
           !/^>\s?/.test(lines[i])) {
      paraLines.push(lines[i]);
      i++;
    }
    if (paraLines.length > 0) {
      out.push(`<p>${inlineMarkdown(paraLines.join(' '), baseUrl)}</p>`);
    }
  }

  closeList();
  return out.join('\n');
}

/**
 * Render a set of pipe-delimited table lines to an HTML table.
 * @param {string[]} tableLines
 * @param {string} baseUrl
 * @returns {string}
 */
function renderTable(tableLines, baseUrl) {
  // Parse rows: split by | and trim, drop empty first/last cells from leading/trailing pipes
  const rows = [];
  for (const line of tableLines) {
    const cells = line.split('|').map(c => c.trim());
    // Remove empty leading/trailing entries from leading/trailing pipes
    if (cells[0] === '') cells.shift();
    if (cells.length > 0 && cells[cells.length - 1] === '') cells.pop();
    rows.push(cells);
  }

  if (rows.length === 0) return '';

  // Check if second row is a separator (all cells match ---+ pattern)
  let headerRow = null;
  let bodyStart = 0;
  if (rows.length > 1 && rows[1].every(c => /^[-:]+$/.test(c))) {
    headerRow = rows[0];
    bodyStart = 2;
  }

  let html = '<table class="zl-docs-table">';

  if (headerRow) {
    html += '<thead><tr>';
    for (const cell of headerRow) {
      html += `<th>${inlineMarkdown(cell, baseUrl)}</th>`;
    }
    html += '</tr></thead>';
  }

  html += '<tbody>';
  for (let r = bodyStart; r < rows.length; r++) {
    html += '<tr>';
    for (const cell of rows[r]) {
      html += `<td>${inlineMarkdown(cell, baseUrl)}</td>`;
    }
    html += '</tr>';
  }
  html += '</tbody></table>';

  return html;
}

/** Convert heading text to a URL-friendly slug for anchor IDs. */
export function slugify(text) {
  return text
    .replace(/\*\*([^*]+)\*\*/g, '$1')   // strip bold markers
    .replace(/\*([^*]+)\*/g, '$1')        // strip italic markers
    .replace(/`([^`]+)`/g, '$1')          // strip inline code
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1') // strip link markup
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')         // remove non-alnum
    .replace(/\s+/g, '-')                 // spaces → hyphens
    .replace(/-+/g, '-')                  // collapse hyphens
    .replace(/^-|-$/g, '');               // trim leading/trailing hyphens
}

export function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function inlineMarkdown(s, baseUrl) {
  s = escapeHtml(s);
  // Helper: reject dangerous URLs. Checks the raw and resolved forms because
  // baseUrl prefixing can mask a `javascript:` scheme behind the prefix. #983.
  function isDangerousUrl(raw, resolved) {
    return (
      /^\s*(javascript|vbscript|data:text\/html)/i.test(raw) ||
      /^\s*(javascript|vbscript|data:text\/html)/i.test(resolved) ||
      /^\s*&#/.test(raw) ||
      /^\s*&#/.test(resolved) ||
      /^\s*\/\//.test(raw) ||
      /^\s*\/\//.test(resolved)
    );
  }
  // Images: ![alt](url) — resolve relative paths against baseUrl
  s = s.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (_, alt, src) => {
    const resolved = src.startsWith('http') || src.startsWith('/') ? src : normalizePath(baseUrl + src);
    // Reject dangerous schemes/protocol-relative on image src — emit alt only. #983.
    if (isDangerousUrl(src, resolved)) {
      return alt;
    }
    return `<img src="${resolved}" alt="${alt}" class="zl-whatsnew-img">`;
  });
  // Links: [text](url) — anchor links and .md links stay internal, others open in new tab
  s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, text, href) => {
    if (href.startsWith('#')) {
      return `<a href="${href}" class="zl-docs-internal-link">${text}</a>`;
    }
    // Internal .md doc links: pass through the RAW (un-baseUrl-resolved)
    // href. The hash router in docs-app.js (rewriteInternalLinksToHash)
    // resolves these against the current doc's location and converts them
    // to `#docs/.../X.md` form. Applying baseUrl here pre-concatenates
    // `../docs/<dir>/`, which then double-resolves against `docs/<dir>/`
    // and produces `docs/docs/...` (the double-prefix bug fixed by this
    // change). Only images (`![alt](src)` above) and non-.md links need
    // baseUrl resolution at render time, because those are real fetch URLs
    // anchored at the viewer's location, not hash-router inputs.
    const isInternalMd = (href.endsWith('.md') || href.includes('.md#'))
      && !href.startsWith('http') && !href.startsWith('/');
    if (isInternalMd) {
      return `<a href="${href}" class="zl-docs-internal-link">${text}</a>`;
    }
    // Resolve relative paths against baseUrl (skip absolute URLs and root-relative paths)
    const resolved = href.startsWith('http') || href.startsWith('/') ? href : normalizePath(baseUrl + href);
    // Reject dangerous schemes / entity-encoded / protocol-relative — emit text only. #983.
    if (isDangerousUrl(href, resolved)) {
      return text;
    }
    // Absolute or root-relative .md (rare): internal, no target="_blank"
    if (resolved.endsWith('.md') || resolved.includes('.md#')) {
      return `<a href="${resolved}" class="zl-docs-internal-link">${text}</a>`;
    }
    return `<a href="${resolved}" target="_blank" rel="noopener">${text}</a>`;
  });
  // GFM task list checkboxes — prevent false matches on array[x], obj[ ] (word char before [)
  s = s.replace(/(?<!\w)\[x\]/gi, '<input type="checkbox" checked class="zl-task-checkbox">');
  s = s.replace(/(?<!\w)\[ \]/g, '<input type="checkbox" class="zl-task-checkbox">');
  // Inline code
  s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
  // Bold
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  // Italic
  s = s.replace(/\*([^*]+)\*/g, '<em>$1</em>');
  return s;
}

/** Normalize a path by resolving '..' and '.' segments.
 *  Preserves a leading '/' for root-relative paths. */
function normalizePath(p) {
  const isAbsolute = p.startsWith('/');
  const parts = p.split('/');
  const out = [];
  for (const s of parts) {
    if (s === '..') {
      if (out.length > 0 && out[out.length - 1] !== '..') out.pop();
      else out.push(s);
    } else if (s !== '.' && s !== '') {
      out.push(s);
    }
  }
  return (isAbsolute ? '/' : '') + out.join('/');
}
