#!/bin/bash
# tests/test-tmpdir-hardcode-guard.sh
#
# STANDING CONFORMANCE GUARD for issue #1102 — the "false-pass-on-stale-/tmp"
# test-integrity hole.
#
# THE BUG CLASS (fixed once in #1100):
#   A producing script honors $TMPDIR — it writes its artifacts under a base
#   like `BASE="${TMPDIR:-/tmp}"; ... "$BASE/<artifact>"`. A test that *checks*
#   for that artifact at a HARDCODED `/tmp/<artifact>` then diverges from where
#   the artifact actually lands the moment $TMPDIR != /tmp. Under the parallel
#   runner each suite gets its own `TMPDIR=$(mktemp -d)`, so:
#     • clean box (CI): the test looks in /tmp, finds nothing → FAILS, or
#     • dev box with stale /tmp artifacts from prior serial runs: the broken
#       test FALSE-PASSES — green while structurally broken (silent integrity
#       hole). CI (clean /tmp) is what caught the one live instance
#       (test-draft-tests-phase4/5 vs review-loop.sh's `${TMPDIR:-/tmp}` base).
#
# THE GUARD (this file):
#   1. PRODUCER SCAN — find every `skills/**/scripts/*` and `hooks/*` script
#      that defines a TMPDIR-honoring BASE var (a var assigned `${TMPDIR:-/tmp}`,
#      `${TMPDIR}` or `$TMPDIR`). For each such base var, collect the literal
#      leading filename segment of every artifact path written under it
#      (`"$BASE/<literal>..."`) — the run of [A-Za-z0-9._-] after the slash, up
#      to the first shell expansion. That literal is a "producer token".
#   2. TEST SCAN — for every `tests/*.sh`, flag any HARDCODED `/tmp/<token>`
#      literal whose `<token>` STARTS WITH a producer token. The match keys on
#      the DIVERGENCE: a test hardcoding /tmp for a name a $TMPDIR-honoring
#      script produces. `${TMPDIR:-/tmp}/<token>` and `${TMPDIR}/<token>` are
#      NOT hardcoded (they honor TMPDIR) and are NOT flagged.
#
# WHY THIS IS PRECISE (no false positives):
#   • The correlation is the artifact NAME. A test's `/tmp/zskills-port-fixture`
#     (test-port.sh) is NOT flagged because `port.sh` does NOT honor TMPDIR —
#     `zskills-port-fixture` is not a producer token. That fixed-/tmp use is a
#     test-local fixture, NOT this bug.
#   • mktemp-based producers (e.g. draft-orchestrator.sh's `mktemp -d`) create
#     unguessable per-run names — there is no stable artifact token a test could
#     hardcode, so they produce no tokens and can't be matched.
#   • A producer token must be reasonably specific (length >= 6 AND contain a
#     `-`) so short/common literals (`out`, `log`) can't over-match.
#
# EXEMPTION (inspectable): put a marker comment naming the token on the flagged
# line or the line immediately above it:
#     # allow-tmpdir-hardcode: <token> reason: <why this fixed /tmp is correct>
#   Use ONLY when the hardcoded /tmp is genuinely correct (never to silence a
#   real instance). The marker is greppable and review-visible.
#
# This guard MUST currently PASS — the one live instance was fixed in #1100.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${REPO_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Resolve Python (project convention: no jq; Python json/stdlib is the parser).
PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$PYTHON" ]; then
  fail "Python 3 required (install python3 or set ZSKILLS_PYTHON)"
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT+FAIL_COUNT))"
  exit 1
fi

# The detector lives in Python (correlation logic is brittle in bash-regex).
# It prints, to stdout, one line per OFFENDING test occurrence:
#     <test-file>:<lineno>: hardcoded /tmp/<token> for $TMPDIR-honoring producer <producer>:<token>
# and exits 0 (clean) or 1 (offenders found). All diagnostics go to stdout so
# the suite output captures them.
DETECT_OUT="$("$PYTHON" - "$REPO_ROOT" <<'PY'
import os, re, sys

repo = sys.argv[1]

# ── Phase 1: PRODUCER SCAN ────────────────────────────────────────────────
# A TMPDIR-honoring base var is `VAR=${TMPDIR:-/tmp}` / `VAR=${TMPDIR}` /
# `VAR=$TMPDIR` (optionally quoted). We capture VAR, then find every artifact
# path written under "$VAR/" and extract the leading literal filename segment.

BASE_ASSIGN = re.compile(
    r'^\s*([A-Za-z_][A-Za-z0-9_]*)='
    r'"?\$\{?TMPDIR(?::-/tmp)?\}?"?\s*$'
)

def producer_files():
    roots = []
    skills_root = os.path.join(repo, "skills")
    for base in (skills_root,):
        if not os.path.isdir(base):
            continue
        for dirpath, _dirs, files in os.walk(base):
            # only scripts/ subtrees
            if os.path.basename(dirpath) != "scripts":
                continue
            for f in files:
                roots.append(os.path.join(dirpath, f))
    hooks_root = os.path.join(repo, "hooks")
    if os.path.isdir(hooks_root):
        for f in os.listdir(hooks_root):
            p = os.path.join(hooks_root, f)
            if os.path.isfile(p):
                roots.append(p)
    return roots

def leading_literal(after_slash):
    # Run of literal filename chars after "$BASE/", up to the first shell
    # expansion ($ or `) or whitespace/quote. e.g. 'draft-tests-candidate-'
    m = re.match(r'([A-Za-z0-9][A-Za-z0-9._-]*)', after_slash)
    return m.group(1) if m else ""

# token -> set of producer files
producers = {}
for path in producer_files():
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        continue
    if "TMPDIR" not in text:
        continue
    basevars = set()
    for line in text.splitlines():
        m = BASE_ASSIGN.match(line)
        if m:
            basevars.add(m.group(1))
    if not basevars:
        continue
    rel = os.path.relpath(path, repo)
    for var in basevars:
        # Match `$VAR/<literal>` and `${VAR}/<literal>` anywhere on a line.
        pat = re.compile(r'\$\{?' + re.escape(var) + r'\}?/([^"\s`]*)')
        for m in pat.finditer(text):
            tok = leading_literal(m.group(1))
            # Specificity floor: avoid short/common tokens over-matching.
            if len(tok) >= 6 and "-" in tok:
                producers.setdefault(tok, set()).add(rel)

# ── Phase 2: TEST SCAN ────────────────────────────────────────────────────
# Flag a hardcoded `/tmp/<token>` in tests/*.sh whose <token> starts with a
# producer token. A `/tmp/` immediately preceded by `-` (the `:-/tmp` default
# of ${TMPDIR:-/tmp}) or by another path char is NOT a hardcoded literal — the
# negative-lookbehind `(?<![-\w./])` excludes those.
HARDCODE = re.compile(r'(?<![-\w./])/tmp/([A-Za-z0-9][A-Za-z0-9._-]*)')
ALLOW = re.compile(r'allow-tmpdir-hardcode:\s*([A-Za-z0-9._-]+)')

tests_dir = os.path.join(repo, "tests")
offenders = []
if producers and os.path.isdir(tests_dir):
    for f in sorted(os.listdir(tests_dir)):
        if not f.endswith(".sh"):
            continue
        path = os.path.join(tests_dir, f)
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        for i, line in enumerate(lines):
            for m in HARDCODE.finditer(line):
                tok = m.group(1)
                # Find a producer token that this hardcoded name starts with.
                hit = None
                for ptok in producers:
                    if tok == ptok or tok.startswith(ptok):
                        hit = ptok
                        break
                if hit is None:
                    continue
                # Exemption: marker on this line or the line immediately above,
                # naming the producer token (or the full hardcoded token).
                exempt = False
                for probe in (line, lines[i-1] if i > 0 else ""):
                    am = ALLOW.search(probe)
                    if am and (am.group(1) == hit or am.group(1) == tok
                               or tok.startswith(am.group(1))):
                        exempt = True
                        break
                if exempt:
                    continue
                prod = ", ".join(sorted(producers[hit]))
                offenders.append(
                    "tests/%s:%d: hardcoded /tmp/%s for $TMPDIR-honoring "
                    "producer %s (token '%s')" % (f, i + 1, tok, prod, hit)
                )

for o in offenders:
    print(o)
sys.exit(1 if offenders else 0)
PY
)"
DETECT_RC=$?

# Visibility: report how many producer tokens were discovered (a 0 here would
# mean the producer scan silently went blind — the guard would vacuously pass).
PRODUCER_TOKENS="$("$PYTHON" - "$REPO_ROOT" <<'PY'
import os, re, sys
repo = sys.argv[1]
BASE_ASSIGN = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)="?\$\{?TMPDIR(?::-/tmp)?\}?"?\s*$')
def files():
    out=[]
    for base in (os.path.join(repo,"skills"),):
        if not os.path.isdir(base): continue
        for dp,_d,fs in os.walk(base):
            if os.path.basename(dp)!="scripts": continue
            out += [os.path.join(dp,f) for f in fs]
    h=os.path.join(repo,"hooks")
    if os.path.isdir(h):
        out += [os.path.join(h,f) for f in os.listdir(h) if os.path.isfile(os.path.join(h,f))]
    return out
def lead(s):
    m=re.match(r'([A-Za-z0-9][A-Za-z0-9._-]*)', s); return m.group(1) if m else ""
toks=set()
for p in files():
    try: t=open(p,encoding="utf-8",errors="replace").read()
    except OSError: continue
    if "TMPDIR" not in t: continue
    bvs={m.group(1) for m in (BASE_ASSIGN.match(l) for l in t.splitlines()) if m}
    for v in bvs:
        for m in re.finditer(r'\$\{?'+re.escape(v)+r'\}?/([^"\s`]*)', t):
            tk=lead(m.group(1))
            if len(tk)>=6 and "-" in tk: toks.add(tk)
print(len(toks))
PY
)"

if [ "${PRODUCER_TOKENS:-0}" -ge 1 ] 2>/dev/null; then
  pass "producer scan found $PRODUCER_TOKENS \$TMPDIR-honoring artifact token(s) — guard is live"
else
  fail "producer scan found 0 \$TMPDIR-honoring artifact tokens — guard would vacuously pass (scan likely broke)"
fi

if [ "$DETECT_RC" -eq 0 ]; then
  pass "no tests/*.sh hardcodes /tmp/<artifact> for a \$TMPDIR-honoring producer (issue #1102 class)"
else
  echo "$DETECT_OUT"
  fail "tests/*.sh hardcode(s) /tmp/<artifact> for a \$TMPDIR-honoring producer (issue #1102 class) — see lines above; fix the path to \${TMPDIR:-/tmp}/<artifact> or add an inspectable '# allow-tmpdir-hardcode: <token> reason: ...' marker"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [[ "$FAIL_COUNT" -eq 0 ]]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
fi
exit "$FAIL_COUNT"