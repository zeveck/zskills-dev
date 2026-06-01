#!/bin/bash
# test-fix-issues-skip-effective-reason.sh — cross-path agreement coverage
# for issue #862 (split-brain between the dashboard skip chip and the
# /fix-issues drop-decision).
#
# Root cause (#862): the dashboard skip-reason chip was sourced ONLY from
# the committed `Action now:` blurb (collect.py:_parse_action_now), while
# `monitor-state.json:issues.skipped[N]` was read ONLY by the filter
# (filter-unresearched-candidates.sh). An orchestrator that re-triaged an
# issue and recorded a new classification moved the FILTER but not the
# CHIP — so the chip showed a stale `skip:plan-scale` while the issue had
# actually been re-classified to needs-decision.
#
# Fix: ONE precedence, mirrored in both languages (they can't share a
# function): the live `issues.skipped[N]` override WINS over the
# blurb-derived reason; absent an override, the blurb applies. This test
# LOCKS the agreement — for the same monitor-state + tracker input, the
# Python chip path and the bash filter path must resolve the SAME
# effective skip-code. If a future edit drifts one side's precedence, the
# split-brain returns and this test fails.
#
# Cases:
#   (a) override beats a stale blurb: tracker says plan-scale, monitor-state
#       says needs-decision -> BOTH resolve needs-decision.
#   (b) record-skip.sh-persisted free-text reason flows to the chip label.
#   (c) no override: chip + filter both fall back to the blurb code.
#   (d) record-skip.sh writes the {code, reason} dict shape when a reason
#       arg is supplied (and bare-string when omitted).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILTER="$REPO_ROOT/skills/fix-issues/scripts/filter-unresearched-candidates.sh"
RECORD="$REPO_ROOT/skills/fix-issues/scripts/record-skip.sh"
PKG_PARENT="$REPO_ROOT/skills/zskills-dashboard/scripts"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not available — skipping"
  exit 0
fi

SCRATCH="$(mktemp -d)"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT INT TERM

echo "=== /fix-issues skip effective-reason cross-path agreement (#862) ==="

make_main_root() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && git commit --allow-empty -q -m init ) >/dev/null
}

# Resolve the bash filter's effective skip-code for issue N (the code in
# the `N:<code>` SKIP_TAGGED token, or empty).
filter_effective_code() {
  local issues_dir="$1" main_root="$2" n="$3"
  local out tagged
  out=$(ZSKILLS_ISSUES_DIR="$issues_dir" ZSKILLS_MAIN_ROOT="$main_root" bash "$FILTER" "$n")
  tagged=$(echo "$out" | grep '^SKIP_TAGGED=' | sed -e 's/^SKIP_TAGGED=//' -e 's/^"//' -e 's/"$//')
  # Extract the code for this issue from `N:code` tokens.
  for tok in $tagged; do
    case "$tok" in
      "$n":*) echo "${tok#*:}"; return ;;
    esac
  done
  echo ""
}

# Resolve the Python chip's effective skip-code for issue N, given a
# monitor-state file + tracker dir. Prints `code|label` (code empty when
# None).
chip_effective() {
  local state_file="$1" tracker_path="$2" n="$3"
  PYTHONPATH="$PKG_PARENT" python3 - "$state_file" "$tracker_path" "$n" <<'PY'
import json, sys, pathlib
from zskills_monitor.collect import (
    _read_monitor_skipped,
    _build_skip_reason_index,
    _resolve_effective_skip_reason,
)
state_file, tracker_path, n_s = sys.argv[1], sys.argv[2], sys.argv[3]
n = int(n_s)
try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    state = {}
monitor = _read_monitor_skipped(state)
blurb = _build_skip_reason_index(pathlib.Path(tracker_path), [n])
eff = _resolve_effective_skip_reason(n, monitor, blurb)
if eff is None:
    print("|")
else:
    print(f"{eff.get('code','')}|{eff.get('label','')}")
PY
}

# --- (a) override beats stale blurb (BOTH paths agree) -------------------
test_override_beats_blurb_agreement() {
  local issues_dir="$SCRATCH/a/issues" main_root="$SCRATCH/a/main"
  mkdir -p "$issues_dir"; make_main_root "$main_root"
  # Tracker blurb says plan-scale...
  cat > "$issues_dir/ISSUES_PLAN.md" <<'EOF'
### #832 — stale blurb
**Action now:** /draft-plan — plan-scale design surface.
EOF
  # ...but the orchestrator re-triaged to needs-decision (with a reason).
  ZSKILLS_MAIN_ROOT="$main_root" bash "$RECORD" 832 needs-decision "needs author A/B/C scope decision" >/dev/null 2>&1

  local fcode chip ccode
  fcode=$(filter_effective_code "$issues_dir" "$main_root" 832)
  chip=$(chip_effective "$main_root/.zskills/monitor-state.json" "$issues_dir/ISSUES_PLAN.md" 832)
  ccode="${chip%%|*}"

  if [ "$fcode" = "needs-decision" ] && [ "$ccode" = "needs-decision" ]; then
    pass "override beats stale blurb AND chip+filter agree (both needs-decision)"
  else
    fail "override beats stale blurb / agreement" "filter=[$fcode] chip=[$ccode]"
  fi
}

# --- (b) persisted reason flows to the chip label ------------------------
test_reason_flows_to_chip_label() {
  local issues_dir="$SCRATCH/b/issues" main_root="$SCRATCH/b/main"
  mkdir -p "$issues_dir"; make_main_root "$main_root"
  : > "$issues_dir/ISSUES_PLAN.md"
  ZSKILLS_MAIN_ROOT="$main_root" bash "$RECORD" 900 needs-decision "needs author A/B/C scope decision" >/dev/null 2>&1
  local chip label
  chip=$(chip_effective "$main_root/.zskills/monitor-state.json" "$issues_dir/ISSUES_PLAN.md" 900)
  label="${chip#*|}"
  if [ "$label" = "needs author A/B/C scope decision" ]; then
    pass "record-skip.sh-persisted reason flows through to chip label"
  else
    fail "reason flows to chip label" "got label [$label] (full=[$chip])"
  fi
}

# --- (c) no override: both paths fall back to blurb code -----------------
test_no_override_blurb_fallback_agreement() {
  local issues_dir="$SCRATCH/c/issues" main_root="$SCRATCH/c/main"
  mkdir -p "$issues_dir"; make_main_root "$main_root"
  cat > "$issues_dir/ISSUES_PLAN.md" <<'EOF'
### #701 — plan-scale rowed
**Action now:** /draft-plan — needs design review.
EOF
  # No record-skip — monitor-state has no entry.
  printf '{}\n' > "$main_root/.zskills/monitor-state.json" 2>/dev/null || {
    mkdir -p "$main_root/.zskills"; printf '{}\n' > "$main_root/.zskills/monitor-state.json"; }
  local fcode chip ccode
  fcode=$(filter_effective_code "$issues_dir" "$main_root" 701)
  chip=$(chip_effective "$main_root/.zskills/monitor-state.json" "$issues_dir/ISSUES_PLAN.md" 701)
  ccode="${chip%%|*}"
  if [ "$fcode" = "plan-scale" ] && [ "$ccode" = "plan-scale" ]; then
    pass "no override: chip+filter both fall back to blurb code (plan-scale)"
  else
    fail "no-override blurb fallback agreement" "filter=[$fcode] chip=[$ccode]"
  fi
}

# --- (d) record-skip writes dict shape with reason, bare without ---------
test_record_skip_dict_shape() {
  local main_root="$SCRATCH/d/main"
  make_main_root "$main_root"
  ZSKILLS_MAIN_ROOT="$main_root" bash "$RECORD" 11 needs-decision "scope decision" >/dev/null 2>&1
  ZSKILLS_MAIN_ROOT="$main_root" bash "$RECORD" 12 plan-scale >/dev/null 2>&1
  local shapes
  shapes=$(python3 - "$main_root/.zskills/monitor-state.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
sk = data.get('issues', {}).get('skipped', {})
e11 = sk.get('11'); e12 = sk.get('12')
ok11 = isinstance(e11, dict) and e11.get('code') == 'needs-decision' and e11.get('reason') == 'scope decision'
ok12 = (e12 == 'plan-scale')  # bare string when no reason
print('ok' if (ok11 and ok12) else f'BAD e11={e11!r} e12={e12!r}')
PY
)
  if [ "$shapes" = "ok" ]; then
    pass "record-skip writes {code,reason} dict with reason, bare string without"
  else
    fail "record-skip dict/bare shape" "$shapes"
  fi
}

test_override_beats_blurb_agreement
test_reason_flows_to_chip_label
test_no_override_blurb_fallback_agreement
test_record_skip_dict_shape

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"
  exit 1
fi
