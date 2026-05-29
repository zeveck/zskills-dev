#!/bin/bash
# Layer-2 dogfooding measurement test (SKILL_VERIFICATION_SMOKES Phase 4).
#
# Runs briefing.py's dogfooding aggregation against synthesized `.landed`
# fixtures in a tmpdir. Asserts:
#   - per-skill SUCCESSFUL-land counts (status landed/full, or pr_state
#     MERGED / ci pass) — and that ATTEMPTS (pr-failed, conflict, etc.) are
#     NOT counted.
#   - source canonicalization (fix-issues / fix-issues-sprint /
#     fix-issues-pr-mode-NNN → fix-issues).
#   - last_seen reflects the newest successful land per skill.
#   - the gh-merged-PR backfill is hermetic: with gh disabled the
#     aggregation never touches the network.
#
# No network; no real gh; deterministic. There is deliberately NO
# hard-assert "skill X ran >=N times" usage-floor (the plan forbids it —
# it false-fails on quiet periods).
#
# Run from repo root: bash tests/test-briefing-dogfooding.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BRIEFING="$REPO_ROOT/skills/briefing/scripts/briefing.py"
PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT+1)); }

echo "=== briefing dogfooding aggregation (Phase 4) ==="

PY=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
if [ -z "$PY" ]; then
  skip "python3 not available"
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
  exit 0
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Synthesize .landed fixtures, each in its own worktree-shaped dir.
mk_landed() { # $1=dirname  $2...=lines
  local d="$TMP/$1"; shift
  mkdir -p "$d"
  printf '%s\n' "$@" > "$d/.landed"
}

# fix-issues family — three SUCCESSFUL lands across canonicalized variants.
mk_landed wt-fi-1 "status: full"   "source: fix-issues"            "date: 2026-05-20T10:00:00+00:00"
mk_landed wt-fi-2 "status: landed" "source: fix-issues-sprint"     "date: 2026-05-22T10:00:00+00:00"
mk_landed wt-fi-3 "status: landed" "source: fix-issues-pr-mode-481" "pr_state: MERGED" "date: 2026-05-25T10:00:00+00:00"
# fix-issues ATTEMPT — must NOT count (pr-failed, no merge/ci-pass).
mk_landed wt-fi-fail "status: pr-failed" "source: fix-issues" "date: 2026-05-26T10:00:00+00:00"

# run-plan — one success via ci: pass (pr_state OPEN).
mk_landed wt-rp-1 "status: pr-ready" "source: run-plan" "ci: pass" "pr_state: OPEN" "date: 2026-05-24T10:00:00+00:00"
# run-plan ATTEMPT — pr-ci-failing, ci fail → not counted.
mk_landed wt-rp-fail "status: pr-ci-failing" "source: run-plan" "ci: fail" "date: 2026-05-27T10:00:00+00:00"

# do — one full land.
mk_landed wt-do-1 "status: full" "source: do" "date: 2026-05-23T10:00:00+00:00"

# A marker with NO source: — successful but unattributable; must not crash
# and must not inflate any named skill.
mk_landed wt-nosrc "status: full" "date: 2026-05-21T10:00:00+00:00"

# Run the aggregation via the module (hermetic; gh backfill disabled).
OUT_JSON="$TMP/result.json"
"$PY" - "$BRIEFING" "$TMP" > "$OUT_JSON" <<'PYEOF'
import importlib.util, json, os, sys
mod_path, scan_root = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("briefing", mod_path)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
# Enumerate fixture dirs as explicit search_roots (no git, no network).
roots = [os.path.join(scan_root, d) for d in os.listdir(scan_root)
         if os.path.isdir(os.path.join(scan_root, d))]
data = m.gather_dogfooding(since='30d', search_roots=roots,
                           enable_gh_backfill=False)
# Also exercise canonicalize_source directly for the variant assertions.
data['_canon'] = {
    'fix-issues': m.canonicalize_source('fix-issues'),
    'fix-issues-sprint': m.canonicalize_source('fix-issues-sprint'),
    'fix-issues-pr-mode-481': m.canonicalize_source('fix-issues-pr-mode-481'),
    'run-plan.MY_PLAN': m.canonicalize_source('run-plan.MY_PLAN'),
}
print(json.dumps(data))
PYEOF

if [ ! -s "$OUT_JSON" ]; then
  fail "aggregation produced no output" "empty $OUT_JSON"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
  exit 1
fi

jq_get() { # $1=python-expr returning a value from the loaded JSON 'd'
  "$PY" - "$OUT_JSON" "$1" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
expr = sys.argv[2]
print(eval(expr))
PYEOF
}

# --- canonicalization assertions ---
[ "$(jq_get "d['_canon']['fix-issues']")" = "fix-issues" ] \
  && pass "canon: fix-issues → fix-issues" \
  || fail "canon: fix-issues" "got $(jq_get "d['_canon']['fix-issues']")"
[ "$(jq_get "d['_canon']['fix-issues-sprint']")" = "fix-issues" ] \
  && pass "canon: fix-issues-sprint → fix-issues" \
  || fail "canon: fix-issues-sprint" "got $(jq_get "d['_canon']['fix-issues-sprint']")"
[ "$(jq_get "d['_canon']['fix-issues-pr-mode-481']")" = "fix-issues" ] \
  && pass "canon: fix-issues-pr-mode-481 → fix-issues" \
  || fail "canon: fix-issues-pr-mode-481" "got $(jq_get "d['_canon']['fix-issues-pr-mode-481']")"
[ "$(jq_get "d['_canon']['run-plan.MY_PLAN']")" = "run-plan" ] \
  && pass "canon: run-plan.MY_PLAN → run-plan" \
  || fail "canon: run-plan.MY_PLAN" "got $(jq_get "d['_canon']['run-plan.MY_PLAN']")"

# --- per-skill counts ---
FI_COUNT=$(jq_get "d['skills'].get('fix-issues',{}).get('landed_count',0)")
[ "$FI_COUNT" = "3" ] \
  && pass "count: fix-issues = 3 successful lands (variants merged, attempt excluded)" \
  || fail "count: fix-issues" "expected 3 got $FI_COUNT"

RP_COUNT=$(jq_get "d['skills'].get('run-plan',{}).get('landed_count',0)")
[ "$RP_COUNT" = "1" ] \
  && pass "count: run-plan = 1 (ci: pass counts; ci: fail attempt excluded)" \
  || fail "count: run-plan" "expected 1 got $RP_COUNT"

DO_COUNT=$(jq_get "d['skills'].get('do',{}).get('landed_count',0)")
[ "$DO_COUNT" = "1" ] \
  && pass "count: do = 1" \
  || fail "count: do" "expected 1 got $DO_COUNT"

# --- last_seen reflects the NEWEST successful land for fix-issues ---
FI_LAST=$(jq_get "d['skills'].get('fix-issues',{}).get('last_seen','')")
[ "$FI_LAST" = "2026-05-25T10:00:00+00:00" ] \
  && pass "last_seen: fix-issues = newest successful land (2026-05-25)" \
  || fail "last_seen: fix-issues" "expected 2026-05-25 got $FI_LAST"

# --- gh backfill disabled is reported as such (hermetic) ---
BACKFILL=$(jq_get "d['gh_backfill']")
[ "$BACKFILL" = "disabled" ] \
  && pass "gh_backfill: disabled (hermetic, no network)" \
  || fail "gh_backfill" "expected disabled got $BACKFILL"

# --- the un-sourced successful marker must NOT inflate a named skill ---
# (it canonicalizes to None and is dropped). Total named-skill landed
# counts should be exactly 3 (fix-issues) + 1 (run-plan) + 1 (do) = 5.
TOTAL=$(jq_get "sum(s['landed_count'] for s in d['skills'].values())")
[ "$TOTAL" = "5" ] \
  && pass "no-source marker dropped (total named landed_count = 5)" \
  || fail "no-source handling" "expected total 5 got $TOTAL"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
