#!/bin/bash
# Parity check: docs/guides/inspecting-and-monitoring.html vs the rendered
# docs/guides/INSPECTING_AND_MONITORING.md (DOC_VIEWER Phase 5).
#
# This is the falsifiable gate that justifies deleting the hand-built .html.
# Two-step procedure:
#
#   1. Extract visible body text from both (via Python stdlib html.parser).
#   2. Tokenize each to a multiset of lowercased alpha-words, drop stopwords
#      and short tokens, and assert: every distinctive HTML word also
#      appears in the rendered MD.
#
# Why tokens not lines: the HTML's hero paragraph and the MD's blockquote
# "Audience:" carry the same information in different wording, so a
# line-level diff cannot distinguish "rewording" from "loss." Token
# overlap CAN — if the .html mentions a concept the .md never names,
# at least one distinctive token will be HTML-only.
#
# The whitelist (HTML_ONLY_OK_TOKENS) names tokens that are decorative
# chrome legitimately absent from the .md: pill labels, draft badge text,
# the figure alt-text, hero tag pill. Each entry is documented inline.
#
# If unexpected HTML-only tokens remain, the test FAILS — the .html
# deletion is unsafe to proceed and the orchestrator must HOLD the delete
# and file a follow-up issue.
#
# Emits the canonical `Results: N passed, M failed` line consumed by
# tests/run-all.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HTML_SRC="$REPO_ROOT/docs/guides/inspecting-and-monitoring.html"
MD_SRC="$REPO_ROOT/docs/guides/INSPECTING_AND_MONITORING.md"
RENDERER="$REPO_ROOT/docs/MarkdownRenderer.js"
EXTRACT="$REPO_ROOT/scripts/extract-html-text.py"

# Resolve Python interpreter (per CLAUDE.md convention).
PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [[ -z "$PYTHON" ]]; then
  echo "ERROR: Python 3 not found (set ZSKILLS_PYTHON)"
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

pass=0
fail=0
check() {
  local name="$1" cond="$2" msg="${3:-}"
  if [[ "$cond" == "1" ]]; then
    echo "PASS  $name"
    ((pass++))
  else
    echo "FAIL  $name  $msg"
    ((fail++))
  fi
}

# ── Existence gate ───────────────────────────────────────────────────────
# If the .html has been deleted (post-Phase-5 landing), the parity gate
# is vacuously satisfied — the .md is the only source of truth. Skip
# without failing.
if [[ ! -f "$HTML_SRC" ]]; then
  echo "PASS  parity.html-deleted (vacuous: IAM.html already removed)"
  echo "Results: 1 passed, 0 failed"
  exit 0
fi

check "parity.md-exists" "$([[ -f "$MD_SRC" ]] && echo 1 || echo 0)" \
  "$MD_SRC not found"
check "parity.renderer-exists" "$([[ -f "$RENDERER" ]] && echo 1 || echo 0)" \
  "$RENDERER not found"
check "parity.extract-script-exists" "$([[ -f "$EXTRACT" ]] && echo 1 || echo 0)" \
  "$EXTRACT not found"

if (( fail > 0 )); then
  echo "Results: $pass passed, $fail failed"
  exit 1
fi

# ── Extract text from both sides ─────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

HTML_TXT="$TMP_DIR/iam-html.txt"
MD_TXT="$TMP_DIR/iam-md.txt"
MD_HTML="$TMP_DIR/iam-md.html"

"$PYTHON" "$EXTRACT" "$HTML_SRC" > "$HTML_TXT" 2>"$TMP_DIR/html.err"
rc=$?
check "parity.html-extract-ran" "$([[ $rc -eq 0 ]] && echo 1 || echo 0)" \
  "extract-html-text.py failed on $HTML_SRC: $(cat "$TMP_DIR/html.err")"

RENDERER="$RENDERER" MD_SRC="$MD_SRC" MD_HTML="$MD_HTML" \
  node --input-type=module > "$TMP_DIR/node.out" 2>"$TMP_DIR/node.err" <<'NODE_EOF'
import { readFileSync, writeFileSync } from 'node:fs';
const { renderMarkdown } = await import(process.env.RENDERER);
const md = readFileSync(process.env.MD_SRC, 'utf8');
// IAM.md has no YAML frontmatter (head -2 → starts with `# `), so
// renderMarkdown is the full viewer-equivalent render path.
const html = renderMarkdown(md);
writeFileSync(process.env.MD_HTML, '<!DOCTYPE html><html><body>\n' + html + '\n</body></html>');
console.log('OK');
NODE_EOF
rc=$?
check "parity.md-render-ran" "$([[ $rc -eq 0 ]] && echo 1 || echo 0)" \
  "Node renderer failed: $(cat "$TMP_DIR/node.err")"

if (( fail > 0 )); then
  echo "Results: $pass passed, $fail failed"
  exit 1
fi

"$PYTHON" "$EXTRACT" "$MD_HTML" > "$MD_TXT" 2>"$TMP_DIR/md.err"
rc=$?
check "parity.md-extract-ran" "$([[ $rc -eq 0 ]] && echo 1 || echo 0)" \
  "extract-html-text.py failed on rendered MD: $(cat "$TMP_DIR/md.err")"

if (( fail > 0 )); then
  echo "Results: $pass passed, $fail failed"
  exit 1
fi

# ── Token-level parity ───────────────────────────────────────────────────
# Tokenize each side: lowercase, split on non-alpha, drop stopwords and
# tokens shorter than 4 chars. The remainder is the substantive vocabulary
# of each document. Any word in HTML's vocab but NOT in MD's vocab is
# either expected chrome (whitelist) or a real prose gap.

"$PYTHON" - "$HTML_TXT" "$MD_TXT" "$TMP_DIR/html-only-tokens.txt" <<'PY_EOF'
import re, sys
html_path, md_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

STOPWORDS = set("""
the and that this with from have will been which were what when where
your into about they them then than there here some this that those
just only also even more most much many such other than then those
these will would could should might must been being were have has had
shall does doesn isn aren wasn weren didn don can cant cannot dont
about above after again against because before below between both
during each ever every from further itself ourselves themselves through
under until upon while whose your yours yourself this their theirs
""".split())

def tokens(path):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read().lower()
    out = set()
    for tok in re.findall(r"[a-z]+", text):
        if len(tok) < 4: continue
        if tok in STOPWORDS: continue
        out.add(tok)
    return out

h = tokens(html_path)
m = tokens(md_path)
diff = sorted(h - m)
with open(out_path, 'w', encoding='utf-8') as f:
    for t in diff:
        f.write(t + '\n')
print(f"html-tokens={len(h)} md-tokens={len(m)} html-only={len(diff)}")
PY_EOF

# ── Whitelist: HTML-only tokens that are expected (decorative chrome) ────
# Each line below names ONE distinctive token that legitimately appears in
# the .html chrome but not in the .md prose. Add a comment line on the same
# block describing where it comes from.
HTML_ONLY_OK_TOKENS=(
  # Pill labels in the LIVE/DURABLE grid cards (chrome, not prose)
  "live"
  "durable"
  # Draft badge text
  "draft"
  # Hero tag pill: "zskills · operator guide"
  "operator"
  # Figure alt-text and caption: the .html has BOTH an <img alt=...> and
  # a separate <figcaption> with phrases like "The dashboard's Plans
  # board — columns, per-plan status chips + phase progress … the
  # /work-on-plans copy-and-run line." The .md carries the same wording
  # in its image alt-attribute, which html.parser does NOT emit as text
  # data (alt is an HTML attribute, not element content). So these tokens
  # appear in HTML body text but are present-yet-invisible in the MD
  # extract — same prose, attribute-vs-element-text artifact only.
  "board"
  "columns"
  "copy"
  "line"
  # Verb-form mismatch: HTML "before trusting a session's own summary",
  # MD "before you trust a session's own summary" — same sentence,
  # different conjugation; tokenizer treats them as distinct.
  "trusting"
)

# Filter html-only-tokens against the whitelist.
UNEXPLAINED="$TMP_DIR/unexplained-tokens.txt"
{
  for tok in "${HTML_ONLY_OK_TOKENS[@]}"; do echo "$tok"; done
} | sort -u > "$TMP_DIR/whitelist.txt"

comm -23 <(sort -u "$TMP_DIR/html-only-tokens.txt") "$TMP_DIR/whitelist.txt" \
  > "$UNEXPLAINED"

GAP_COUNT=$(wc -l < "$UNEXPLAINED" | tr -d ' ')

if [[ "$GAP_COUNT" -gt 0 ]]; then
  echo ""
  echo "── HTML-only tokens NOT in whitelist (potential prose gap) ──"
  cat "$UNEXPLAINED"
  echo "── end ──"
  echo ""
fi

check "parity.no-unexplained-html-only-tokens" \
  "$([[ "$GAP_COUNT" -eq 0 ]] && echo 1 || echo 0)" \
  "$GAP_COUNT unexplained HTML-only token(s); inspect output above"

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
