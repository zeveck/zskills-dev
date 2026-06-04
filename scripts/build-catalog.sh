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
# Scope (user-facing onboarding only):
#   - docs/README.md            → "Start here" (position 0, single entry)
#   - docs/guides/*.md          → "Guides"
#   - docs/skills/*.md          → "Skills" (user-facing skills)
#   - docs/skills/<name>.md     → "Internal" when the source skill
#                                 skills/<name>/SKILL.md carries
#                                 `user-invocable: false` in frontmatter.
#                                 Classification is by reading frontmatter,
#                                 NOT a hand-curated name list. (docs/skills/
#                                 README.md is the section index and always
#                                 stays under "Skills".)
#
# Deliberately excluded (agent/dev artifacts OR optional add-ons, not docs a new user needs):
#   - docs/skills/block-diagram/ (optional block-diagram add-on; users who need it visit the addon repo separately)
#   - docs/plans/    (in-flight + completed design plans — for maintainers)
#   - docs/reports/  (post-execution reports — auto-generated)
#   - docs/evals/    (skill evaluations / coverage analyses)
#   - docs/issues/   (issue triage notes)
#   - docs/tracking/ (pipeline tracking system internals)
#
# Per-section items sorted by `path` ascending by default (NOT by `name`,
# since name derives from H1 which changes on title rewordings — sorting
# by name would make the byte-diff regression gate produce spurious churn).
#
# Curated ordering: sections listed in SECTION_ORDER use the curated
# sequence; items not in the curated list fall back to alphabetical-by-path
# AFTER the curated entries. Display names can be overridden via
# DISPLAY_NAME_OVERRIDES (e.g., docs/guides/README.md → "Overview") so the
# H1-derived default doesn't fight the curated intent.
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
    ('Start here',                      None),  # special: single README entry
    ('Guides',                         'docs/guides'),
    ('Skills',                         'docs/skills'),  # the README section index only
    # docs/skills user-facing skills, split into importance-ordered categories
    # by SKILL_CATEGORY below (mirrors docs/skills/README.md "## Categories"
    # and the viewer nav). Order here = nav order.
    ('Execution',          'docs/skills'),
    ('Planning & Design',  'docs/skills'),
    ('Quality Assurance',  'docs/skills'),
    ('Automation',         'docs/skills'),
    ('Reporting',          'docs/skills'),
    ('Utilities',          'docs/skills'),
    ('Internal',           'docs/skills'),  # user-invocable:false, split by frontmatter
]

# Curated per-section item order. Paths listed appear first (in this order);
# any other items in the section fall back to alphabetical-by-path AFTER
# the curated entries. Sections not listed here use pure alphabetical order.
SECTION_ORDER = {
    'Guides': [
        'docs/guides/README.md',
        'docs/guides/installing-zskills.md',
        'docs/guides/workflows.md',
        'docs/guides/inspecting-and-monitoring.md',
        'docs/guides/zskills-config.md',
        'docs/guides/switching-install-lanes.md',
        'docs/guides/tracking-overview.md',
    ],
    # Skill categories — curated importance order within each (NOT alphabetical).
    'Execution': [
        'docs/skills/do.md',
        'docs/skills/run-plan.md',
        'docs/skills/investigate.md',
    ],
    'Planning & Design': [
        'docs/skills/draft-plan.md',
        'docs/skills/refine-plan.md',
        'docs/skills/draft-tests.md',
        'docs/skills/research-and-plan.md',
        'docs/skills/plans.md',
    ],
    'Quality Assurance': [
        'docs/skills/verify-changes.md',
        'docs/skills/qe-audit.md',
    ],
    'Automation': [
        'docs/skills/fix-issues.md',
        'docs/skills/work-on-plans.md',
        'docs/skills/zskills-dashboard.md',
        'docs/skills/research-and-go.md',
    ],
    'Reporting': [
        'docs/skills/session-report.md',
        'docs/skills/briefing.md',
        'docs/skills/fix-report.md',
    ],
    'Utilities': [
        'docs/skills/commit.md',
        'docs/skills/cleanup-merged.md',
        'docs/skills/update-zskills.md',
        'docs/skills/create-worktree.md',
    ],
}

# Skill → category map. Distributes docs/skills/<name>.md (user-facing only;
# README + user-invocable:false excluded) into the category sections above.
# Mirrors docs/skills/README.md "## Categories". Every user-facing skill doc
# MUST appear here, or it silently drops out of the nav.
SKILL_CATEGORY = {
    'docs/skills/do.md':                'Execution',
    'docs/skills/run-plan.md':          'Execution',
    'docs/skills/investigate.md':       'Execution',
    'docs/skills/fix-issues.md':        'Automation',
    'docs/skills/work-on-plans.md':     'Automation',
    'docs/skills/zskills-dashboard.md': 'Automation',
    'docs/skills/research-and-go.md':   'Automation',
    'docs/skills/draft-plan.md':        'Planning & Design',
    'docs/skills/refine-plan.md':       'Planning & Design',
    'docs/skills/draft-tests.md':       'Planning & Design',
    'docs/skills/research-and-plan.md': 'Planning & Design',
    'docs/skills/plans.md':             'Planning & Design',
    'docs/skills/verify-changes.md':    'Quality Assurance',
    'docs/skills/qe-audit.md':          'Quality Assurance',
    'docs/skills/session-report.md':    'Reporting',
    'docs/skills/briefing.md':          'Reporting',
    'docs/skills/fix-report.md':        'Reporting',
    'docs/skills/commit.md':            'Utilities',
    'docs/skills/cleanup-merged.md':    'Utilities',
    'docs/skills/update-zskills.md':    'Utilities',
    'docs/skills/create-worktree.md':   'Utilities',
}
CATEGORY_LABELS = set(SKILL_CATEGORY.values())

# Display-name overrides for catalog items where the H1-derived name fights
# the curated intent (e.g., a section's own README would show its section
# name instead of "Overview").
DISPLAY_NAME_OVERRIDES = {
    'docs/guides/README.md': 'Overview',
}

FRONTMATTER_RE = re.compile(r'^---\n.*?\n---\n', re.DOTALL)
H1_RE          = re.compile(r'^# (.+)$', re.MULTILINE)
# Matches a frontmatter line `user-invocable: false` (any inline whitespace).
USER_INVOCABLE_FALSE_RE = re.compile(
    r'^user-invocable:\s*false\s*$', re.MULTILINE
)


def is_internal_skill(rel_path):
    """A docs/skills/<name>.md doc is 'internal' iff its source skill
    skills/<name>/SKILL.md declares `user-invocable: false` in frontmatter.

    Classification is by reading frontmatter — NOT a hand-curated name list.
    docs/skills/README.md is the section index (no matching source skill) and
    is never classified internal. Returns False when there is no matching
    source skill (e.g. README.md) or the skill is user-invocable.
    """
    base = os.path.basename(rel_path)
    if base == 'README.md':
        return False
    name = os.path.splitext(base)[0]
    skill_md = os.path.join(REPO_ROOT, 'skills', name, 'SKILL.md')
    if not os.path.isfile(skill_md):
        return False
    try:
        with open(skill_md, 'r', encoding='utf-8') as f:
            text = f.read()
    except OSError:
        return False
    m = FRONTMATTER_RE.match(text)
    if not m:
        return False
    frontmatter = m.group(0)
    return bool(USER_INVOCABLE_FALSE_RE.search(frontmatter))


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
    # docs/skills is split across many sections:
    #   - "Skills"             → ONLY the README section index
    #   - <category>           → user-facing skills mapped by SKILL_CATEGORY
    #   - "Internal"    → docs whose source skill is user-invocable:false
    if rel_dir == 'docs/skills':
        if label == 'Internal':
            paths = [p for p in paths if is_internal_skill(p)]
        elif label == 'Skills':
            paths = [p for p in paths if os.path.basename(p) == 'README.md']
        elif label in CATEGORY_LABELS:
            paths = [
                p for p in paths
                if not is_internal_skill(p)
                and os.path.basename(p) != 'README.md'
                and SKILL_CATEGORY.get(p) == label
            ]
        else:
            paths = []
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
    # Apply display-name overrides BEFORE sort so naming is canonical.
    items = [(DISPLAY_NAME_OVERRIDES.get(p, n), p) for (n, p) in items]
    curated = SECTION_ORDER.get(label)
    if curated:
        # Curated entries first (in curated order), then any remaining items
        # alphabetical-by-path. Stable: items with the same sort key keep
        # their relative insertion order.
        rank = {p: i for i, p in enumerate(curated)}
        items.sort(key=lambda t: (rank.get(t[1], len(curated)), t[1]))
    else:
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
