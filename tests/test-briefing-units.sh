#!/bin/bash
# Phase 5a (SEAM_HARDENING_REST) — direct hermetic unit tests for four pure
# briefing.py functions that were previously exercised only indirectly via
# the summary/report smoke paths.
#
# Pattern mirrors tests/test-briefing-dogfooding.sh: shell out to python3,
# importlib-load skills/briefing/scripts/briefing.py, call the function
# under test against a hermetic fixture, print a result, and assert in bash.
#
# Functions covered:
#   - parse_period            ('1h'→'1 hour ago', '2d'→'2 days ago',
#                               'bogus'→'24 hours ago')
#   - scan_checkboxes_in_files (one [ ] + one [x] under a heading → only the
#                               unchecked one is returned, with heading;
#                               checkboxes inside fenced code blocks ignored)
#   - check_staleness         (no-briefing-file → warning; 7-day-stale
#                               done-needs-review worktree → stale warning)
#   - preserve_checkboxes     (same-day checked-state carries forward; empty
#                               audit_dir is identity)
#
# Hermetic: all fixtures live under a single mktemp -d sandbox (trap cleanup).
# No network, no real gh, no live-repo writes, no writes outside the sandbox.
#
# Run from repo root: bash tests/test-briefing-units.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BRIEFING="$REPO_ROOT/skills/briefing/scripts/briefing.py"
PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT+1)); }

echo "=== briefing pure-function unit tests (Phase 5a) ==="

PY=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
if [ -z "$PY" ]; then
  skip "python3 not available"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
  exit 0
fi

if [ ! -f "$BRIEFING" ]; then
  fail "briefing.py present" "missing $BRIEFING"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
  exit 1
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# parse_period
# ---------------------------------------------------------------------------

PP_OUT="$TMP/parse_period.txt"
"$PY" - "$BRIEFING" > "$PP_OUT" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("briefing", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(repr(m.parse_period('1h')))
print(repr(m.parse_period('2d')))
print(repr(m.parse_period('bogus')))
PYEOF

PP_1H=$(sed -n '1p' "$PP_OUT")
PP_2D=$(sed -n '2p' "$PP_OUT")
PP_BOGUS=$(sed -n '3p' "$PP_OUT")

[ "$PP_1H" = "'1 hour ago'" ] \
  && pass "parse_period('1h') → '1 hour ago'" \
  || fail "parse_period('1h')" "expected '1 hour ago' got $PP_1H"
[ "$PP_2D" = "'2 days ago'" ] \
  && pass "parse_period('2d') → '2 days ago'" \
  || fail "parse_period('2d')" "expected '2 days ago' got $PP_2D"
[ "$PP_BOGUS" = "'24 hours ago'" ] \
  && pass "parse_period('bogus') → '24 hours ago' (fallback)" \
  || fail "parse_period('bogus')" "expected '24 hours ago' got $PP_BOGUS"

# ---------------------------------------------------------------------------
# scan_checkboxes_in_files
# ---------------------------------------------------------------------------
# Fixture: one unchecked [ ] and one checked [x] under a heading, plus a
# fenced code block whose [ ] checkbox must be IGNORED. The function returns
# ONLY unchecked items, so we expect exactly one result, attributed to the
# heading, and NOT the fenced one.

CB_FIX="$TMP/report.md"
cat > "$CB_FIX" <<'MDEOF'
# Notes

## Sign-off Items

- [ ] real unchecked item
- [x] already checked item

```bash
- [ ] fenced checkbox that must be ignored
```
MDEOF

CB_OUT="$TMP/checkboxes.json"
"$PY" - "$BRIEFING" "$CB_FIX" > "$CB_OUT" <<'PYEOF'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("briefing", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
res = m.scan_checkboxes_in_files([sys.argv[2]])
print(json.dumps(res))
PYEOF

read_json() { # $1=json-file  $2=python-expr over loaded 'd'
  "$PY" - "$1" "$2" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
print(eval(sys.argv[2]))
PYEOF
}

CB_LEN=$(read_json "$CB_OUT" "len(d)")
[ "$CB_LEN" = "1" ] \
  && pass "scan_checkboxes_in_files: exactly 1 unchecked item ([x] and fenced [ ] excluded)" \
  || fail "scan_checkboxes_in_files count" "expected 1 got $CB_LEN"

CB_TEXT=$(read_json "$CB_OUT" "d[0]['text'] if d else ''")
[ "$CB_TEXT" = "real unchecked item" ] \
  && pass "scan_checkboxes_in_files: returns the unchecked item text" \
  || fail "scan_checkboxes_in_files text" "expected 'real unchecked item' got '$CB_TEXT'"

CB_HEADING=$(read_json "$CB_OUT" "d[0]['heading'] if d else ''")
[ "$CB_HEADING" = "Sign-off Items" ] \
  && pass "scan_checkboxes_in_files: nearest heading tracked (Sign-off Items)" \
  || fail "scan_checkboxes_in_files heading" "expected 'Sign-off Items' got '$CB_HEADING'"

# Belt-and-suspenders: prove the fenced checkbox text never appears in output.
CB_HAS_FENCED=$(read_json "$CB_OUT" "any('fenced' in c['text'] for c in d)")
[ "$CB_HAS_FENCED" = "False" ] \
  && pass "scan_checkboxes_in_files: fenced-code-block checkbox ignored" \
  || fail "scan_checkboxes_in_files fenced" "fenced checkbox leaked into results"

# ---------------------------------------------------------------------------
# check_staleness
# ---------------------------------------------------------------------------
# Case 1: a sandbox repoRoot with NO .zskills/audit dir → "No briefing report
#         exists yet" warning.
# Case 2: a done-needs-review worktree whose mtime is 8 days before a fixed
#         `now` → a "Stale: ... needs review" warning.
# Both use opts.repoRoot (sandbox) + opts.now (fixed epoch ms) so the test is
# deterministic and never reads the real repo or wall clock.

ST_ROOT="$TMP/staleness-root"
mkdir -p "$ST_ROOT"   # exists, but NO .zskills/audit beneath it

ST_OUT="$TMP/staleness.json"
"$PY" - "$BRIEFING" "$ST_ROOT" > "$ST_OUT" <<'PYEOF'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("briefing", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
repo_root = sys.argv[2]
NOW = 1_700_000_000_000  # fixed epoch ms
DAY = 24 * 60 * 60 * 1000

# Case 1: no briefing report.
no_brief = m.check_staleness([], opts={'repoRoot': repo_root, 'now': NOW})

# Case 2: a 8-day-stale done-needs-review worktree (> 7-day threshold).
stale_wt = {
    'name': 'agent-deadbeef',
    'category': 'done-needs-review',
    'ahead': 2,
    'branch': 'feat/x',
    'mtime': NOW - 8 * DAY,
}
stale = m.check_staleness([stale_wt], opts={'repoRoot': repo_root, 'now': NOW})

print(json.dumps({'no_brief': no_brief, 'stale': stale}))
PYEOF

ST_NOBRIEF=$(read_json "$ST_OUT" "any('No briefing report exists yet' == w for w in d['no_brief'])")
[ "$ST_NOBRIEF" = "True" ] \
  && pass "check_staleness: no briefing file → 'No briefing report exists yet'" \
  || fail "check_staleness no-briefing" "warning missing; got $(read_json "$ST_OUT" "d['no_brief']")"

ST_STALE=$(read_json "$ST_OUT" "any(w.startswith('Stale: agent-deadbeef needs review') for w in d['stale'])")
[ "$ST_STALE" = "True" ] \
  && pass "check_staleness: 7-day-stale worktree → stale review warning" \
  || fail "check_staleness stale-worktree" "warning missing; got $(read_json "$ST_OUT" "d['stale']")"

# ---------------------------------------------------------------------------
# preserve_checkboxes
# ---------------------------------------------------------------------------
# Case A (identity): a NONEXISTENT audit_dir → input returned unchanged.
# Case B (carry-forward): a previous same-day briefing-{today}.md marks an
#         item checked; a fresh report with the same item unchecked should
#         pick up the [x]. We pin `date` explicitly and derive `today` from
#         the module's own format_local so the fixture filename matches the
#         function's same-day lookup regardless of TIMEZONE.

PC_AUDIT="$TMP/pc-audit"   # created below for case B; absent for case A first
PC_OUT="$TMP/preserve.json"
"$PY" - "$BRIEFING" "$PC_AUDIT" > "$PC_OUT" <<'PYEOF'
import importlib.util, json, os, re, sys
spec = importlib.util.spec_from_file_location("briefing", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
audit_dir = sys.argv[2]

# Case A — identity: audit_dir does not exist yet.
new_report = (
    "# Briefing Report\n"
    "\n"
    "### [ ] Review: agent-feedface (2 commits)\n"
    "- [ ] some sign-off item\n"
)
identity = m.preserve_checkboxes(new_report, audit_dir)
identity_unchanged = (identity == new_report)

# Case B — same-day carry-forward.
import datetime as _dt
pinned = _dt.datetime(2026, 5, 28, 12, 0, 0)
et_str = m.format_local(pinned)
today = re.search(r'(\d{4}-\d{2}-\d{2})', et_str).group(1)

os.makedirs(audit_dir, exist_ok=True)
previous = (
    "# Briefing Report\n"
    "\n"
    "### [x] Review: agent-feedface (2 commits)\n"
    "- [x] some sign-off item\n"
)
with open(os.path.join(audit_dir, f'briefing-{today}.md'), 'w') as f:
    f.write(previous)

carried = m.preserve_checkboxes(new_report, audit_dir, date=pinned)
heading_carried = '### [x] Review: agent-feedface' in carried
item_carried = '- [x] some sign-off item' in carried

print(json.dumps({
    'identity_unchanged': identity_unchanged,
    'heading_carried': heading_carried,
    'item_carried': item_carried,
}))
PYEOF

PC_IDENTITY=$(read_json "$PC_OUT" "d['identity_unchanged']")
[ "$PC_IDENTITY" = "True" ] \
  && pass "preserve_checkboxes: empty/absent audit_dir is identity (input unchanged)" \
  || fail "preserve_checkboxes identity" "input was modified despite absent audit_dir"

PC_HEADING=$(read_json "$PC_OUT" "d['heading_carried']")
[ "$PC_HEADING" = "True" ] \
  && pass "preserve_checkboxes: same-day checked heading carries forward" \
  || fail "preserve_checkboxes heading" "heading [x] not carried forward"

PC_ITEM=$(read_json "$PC_OUT" "d['item_carried']")
[ "$PC_ITEM" = "True" ] \
  && pass "preserve_checkboxes: same-day checked item carries forward" \
  || fail "preserve_checkboxes item" "item [x] not carried forward"

# ---------------------------------------------------------------------------
# load_zskills_config + read_zskills_paths — Phase 5 config cascade
# (project > user > built-in defaults; HOME sandboxed inside the fixture)
# ---------------------------------------------------------------------------

CC_OUT="$TMP/cascade.json"
mkdir -p "$TMP/cc-home/.claude" "$TMP/cc-proj/.claude"
cat > "$TMP/cc-home/.claude/zskills-config.json" <<'UCFG'
{ "timezone": "Asia/Tokyo", "output": { "plans_dir": "user-plans" } }
UCFG
cat > "$TMP/cc-proj/.claude/zskills-config.json" <<'PCFG'
{ "timezone": "Europe/London" }
PCFG
HOME="$TMP/cc-home" "$PY" - "$BRIEFING" "$TMP/cc-proj" > "$CC_OUT" <<'PYEOF'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('briefing', sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
proj = sys.argv[2]
cfg = m.load_zskills_config(proj)
paths = m.read_zskills_paths(proj)
print(json.dumps({
    'tz': cfg.get('timezone'),    # project wins over user
    'plans': paths['plans_dir'],  # user fills project-absent output block
}))
PYEOF
CC_TZ=$(read_json "$CC_OUT" "d['tz']")
[ "$CC_TZ" = "Europe/London" ] \
  && pass "load_zskills_config: project tier wins over user tier per key" \
  || fail "load_zskills_config precedence" "got '$CC_TZ', expected 'Europe/London'"
CC_PLANS=$(read_json "$CC_OUT" "d['plans']")
[ "$CC_PLANS" = "$TMP/cc-proj/user-plans" ] \
  && pass "read_zskills_paths: user-tier output.plans_dir fills project-absent key" \
  || fail "read_zskills_paths user-fill" "got '$CC_PLANS', expected '$TMP/cc-proj/user-plans'"

# Defaults arm: EMPTY home + no project config → built-in defaults from
# the canonical zskills-defaults.json (docs/ layout).
CC2_OUT="$TMP/cascade2.json"
mkdir -p "$TMP/cc-home-empty" "$TMP/cc-empty"
HOME="$TMP/cc-home-empty" "$PY" - "$BRIEFING" "$TMP/cc-empty" > "$CC2_OUT" <<'PYEOF'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('briefing', sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
paths = m.read_zskills_paths(sys.argv[2])
print(json.dumps({'plans': paths['plans_dir'], 'reports': paths['reports_dir']}))
PYEOF
CC2_PLANS=$(read_json "$CC2_OUT" "d['plans']")
CC2_REPORTS=$(read_json "$CC2_OUT" "d['reports']")
if [ "$CC2_PLANS" = "$TMP/cc-empty/docs/plans" ] && [ "$CC2_REPORTS" = "$TMP/cc-empty/docs/reports" ]; then
  pass "read_zskills_paths: no config at either tier → docs/ built-in defaults (zskills-defaults.json)"
else
  fail "read_zskills_paths defaults" "plans='$CC2_PLANS' reports='$CC2_REPORTS'"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
