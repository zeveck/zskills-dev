#!/bin/bash
# DOC_VIEWER Phase 4 — catalog generator.
#
# Walks the repo's docs/ tree and emits a deterministic JS catalog module
# consumed by the standalone doc viewer (docs/index.html → docs/docs-app.js).
#
# Output destination:
#   - BUILD_CATALOG_OUT (env var) — explicit override
#   - else docs/DocsRegistry.js relative to repo root
#
# Discovery:
#   - docs/README.md            → "Start here" (position 0, single entry)
#   - docs/guides/*.md          → "Guides"
#   - docs/skills/*.md          → "Skills"
#   - docs/skills/block-diagram/*.md → "Skills > Block diagram"
#   - docs/plans/*.md           → "Plans" (flat, ~77 entries)
#   - docs/plans/archive/canaries/*.md → "Archived plans"
#   - docs/reports/*.md         → "Reports"
#   - docs/evals/*.md           → "Evals"
#
# Deliberately excluded for v1 (agent-only artifacts, not user docs):
#   - docs/issues/  (issue plans)
#   - docs/tracking/ (pipeline tracking dumps)
#
# Per-section items sorted by `path` ascending (NOT by `name`, since name
# derives from H1 which changes on title rewordings — sorting by name would
# make the byte-diff regression gate produce spurious churn).
#
# Output format: 2-space indent, LF newlines, trailing newline, key order
# (name, path), no trailing comma. The regression test in
# tests/test-doc-viewer-catalog.sh byte-diffs the regenerated output
# against the committed file.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_PATH="${BUILD_CATALOG_OUT:-$REPO_ROOT/docs/DocsRegistry.js}"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python || true)}"
if [ -z "$PYTHON" ]; then
  echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2
  exit 1
fi

cd "$REPO_ROOT"

"$PYTHON" - "$OUT_PATH" <<'PY'
import os
import re
import sys

OUT_PATH = sys.argv[1]
REPO_ROOT = os.getcwd()
DOCS_DIR = os.path.join(REPO_ROOT, 'docs')

# (section_label, scan_dir, recursive_predicate_or_None)
# scan_dir is repo-root-relative; we list only its DIRECT children for the
# fixed-shape sections, except where the predicate explicitly defines a
# nested path (e.g., archive canaries).
SECTIONS = [
    ('Start here',            None),  # special: single README entry
    ('Guides',                'docs/guides'),
    ('Skills',                'docs/skills'),
    ('Skills > Block diagram','docs/skills/block-diagram'),
    ('Plans',                 'docs/plans'),
    ('Archived plans',        'docs/plans/archive/canaries'),
    ('Reports',               'docs/reports'),
    ('Evals',                 'docs/evals'),
]

FRONTMATTER_RE = re.compile(r'^---\n.*?\n---\n', re.DOTALL)
H1_RE          = re.compile(r'^# (.+)$', re.MULTILINE)


def list_md_direct(rel_dir):
    """Return repo-relative paths of *.md FILES directly in rel_dir
    (non-recursive). Sorted ascending."""
    abs_dir = os.path.join(REPO_ROOT, rel_dir)
    if not os.path.isdir(abs_dir):
        return []
    out = []
    for name in os.listdir(abs_dir):
        if not name.endswith('.md'):
            continue
        full = os.path.join(abs_dir, name)
        if not os.path.isfile(full):
            continue
        out.append(rel_dir + '/' + name)
    out.sort()
    return out


def derive_name(rel_path):
    abs_path = os.path.join(REPO_ROOT, rel_path)
    try:
        with open(abs_path, 'r', encoding='utf-8') as f:
            text = f.read()
    except OSError:
        text = ''
    body = FRONTMATTER_RE.sub('', text, count=1)
    m = H1_RE.search(body)
    if m:
        return m.group(1).strip()
    # Fallback: filename → title-cased with underscores/dashes → spaces.
    base = os.path.splitext(os.path.basename(rel_path))[0]
    base = base.replace('_', ' ').replace('-', ' ')
    # Preserve all-caps acronyms; otherwise title-case word by word.
    words = []
    for w in base.split(' '):
        if not w:
            continue
        if w.isupper() and len(w) > 1:
            words.append(w)
        else:
            words.append(w[:1].upper() + w[1:].lower())
    return ' '.join(words) if words else base


def gather_section(label, rel_dir):
    if label == 'Start here':
        items = [('Z Skills Docs', 'docs/README.md')] if os.path.isfile(
            os.path.join(REPO_ROOT, 'docs/README.md')
        ) else []
        return items
    paths = list_md_direct(rel_dir)
    return [(derive_name(p), p) for p in paths]


def js_string(s):
    # JSON string literal is a valid JS string literal. Use ensure_ascii=False
    # so non-ASCII names round-trip literally; control characters still get
    # escaped by json.dumps.
    import json
    return json.dumps(s, ensure_ascii=False)


# Build the catalog.
sections_out = []
for label, rel_dir in SECTIONS:
    items = gather_section(label, rel_dir)
    if not items:
        continue
    # Sort by path ascending (the second field of the tuple).
    items.sort(key=lambda t: t[1])
    sections_out.append((label, items))


# Emit. Stable indent (2 spaces), LF line endings, trailing newline, key
# order (name, path), no trailing comma after the final item.
lines = []
lines.append('/**')
lines.append(' * Z Skills docs catalog.')
lines.append(' *')
lines.append(' * Generated by scripts/build-catalog.sh — DO NOT EDIT BY HAND.')
lines.append(' * Re-run the generator after adding or renaming docs:')
lines.append(' *   bash scripts/build-catalog.sh')
lines.append(' * The catalog regression test (tests/test-doc-viewer-catalog.sh)')
lines.append(' * fails when this file drifts from a fresh re-run.')
lines.append(' *')
lines.append(' * Shape: array of { section: string, items: [{ name, path }] }')
lines.append(' * Paths are repo-root-relative; the viewer (served at /docs/) prepends')
lines.append(" * '../' before fetching.")
lines.append(' */')
lines.append('export const DOCS_CATALOG = [')

for si, (label, items) in enumerate(sections_out):
    lines.append('  {')
    lines.append('    section: ' + js_string(label) + ',')
    lines.append('    items: [')
    for ii, (name, path) in enumerate(items):
        comma = ',' if ii < len(items) - 1 else ''
        lines.append(
            '      { name: ' + js_string(name)
            + ', path: ' + js_string(path) + ' }' + comma
        )
    lines.append('    ]')
    tail = ',' if si < len(sections_out) - 1 else ''
    lines.append('  }' + tail)

lines.append('];')

# Write atomically with explicit LF line endings + trailing newline.
out_dir = os.path.dirname(os.path.abspath(OUT_PATH))
if out_dir and not os.path.isdir(out_dir):
    os.makedirs(out_dir, exist_ok=True)

with open(OUT_PATH, 'wb') as f:
    f.write(('\n'.join(lines) + '\n').encode('utf-8'))

# Emit a one-line status to stderr so a CI dispatch shows progress.
total_items = sum(len(items) for _, items in sections_out)
print(
    'wrote {} ({} sections, {} items)'.format(
        OUT_PATH, len(sections_out), total_items
    ),
    file=sys.stderr,
)
PY
