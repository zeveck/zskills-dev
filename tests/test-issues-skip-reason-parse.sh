#!/bin/bash
# Tests for zskills_monitor.collect._parse_action_now (issue #445, #721).
#
# Drives the parser against synthetic + real tracker fixtures to assert
# the 6 derivation outcomes (5 skip codes + actionable null):
#   - needs-decision  (Action now: none + "author decision" or "decide")
#   - deferred        (Action now: none + anything else)
#   - plan-scale      (Action now: /draft-plan or /run-plan)
#   - bug-unclear-cause (Action now: /investigate OR Verdict: UNCLEAR)
#   - unresearched    (Verdict: NOT YET RESEARCHED OR missing blurb)
#   - null            (everything else — /do pr, /quickfix, etc.)
#
# Also asserts:
#   - mid-line ** ** mentions of /draft-plan in qualified-actionable
#     blurbs do NOT match plan-scale (prefix-only matching);
#   - chip labels are truncated to <=60 chars + sentence-boundary cut;
#   - _build_skip_reason_index returns an entry per requested issue.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PKG_PARENT="$REPO_ROOT/skills/zskills-dashboard/scripts"
TRACKER_REAL="$REPO_ROOT/docs/issues/ISSUES_PLAN.md"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not available — skipping"
  exit 0
fi

# Single Python driver block. We pass it a synthetic tracker and assert
# every branch of the rule. Real tracker assertions are additive — they
# guard against future divergence between the fixture and live blurbs.
RESULT=$(PYTHONPATH="$PKG_PARENT" REPO_ROOT="$REPO_ROOT" python3 <<'PYEOF'
import json, os, sys, pathlib

from zskills_monitor.collect import (
    _parse_action_now,
    _build_skip_reason_index,
    _short_label,
)

repo_root = pathlib.Path(os.environ["REPO_ROOT"])

# --- Synthetic tracker covering all 5 outcomes plus negative cases ----
SYNTHETIC = """
### #100 — needs-decision: none + author decision

**Verdict:** NOT FIXED — author-deferred

**Complexity:** L. **Action now:** none — author decision needed on which option.

---

### #101 — plan-scale: /draft-plan

**Complexity:** M. **Action now:** /draft-plan.

---

### #102 — plan-scale: /run-plan

**Action now:** /run-plan to execute existing plan.

---

### #103 — bug-unclear-cause: /investigate

**Action now:** /investigate the cause.

---

### #104 — bug-unclear-cause: Verdict UNCLEAR fallback

**Verdict:** UNCLEAR — needs more info
**Action now:** look into it more.

---

### #105 — unresearched: NOT YET RESEARCHED

**Verdict:** NOT YET RESEARCHED.

---

### #106 — actionable: /do pr

**Action now:** /do pr.

---

### #107 — actionable: /quickfix

**Action now:** /quickfix prose-only.

---

### #108 — actionable: fix-agent in sprint

**Action now:** include in next sprint (fix-agent).

---

### #109 — qualified-actionable mentions /draft-plan mid-text (must NOT match plan-scale)

**Action now:** Fix #1 prose roll-in (combined /quickfix S). Fix #2 deferred to /draft-plan when prioritized.

---

### #110 — needs-decision with long trailing branches (label must be short)

**Complexity:** M. **Action now:** none — author decision needed on which option (or defer entirely). If author picks option 1 or 3, escalate to `/draft-plan`. If option 2, single `/do pr`.

---

### #111 — deferred: none + leave open as architectural memo

**Complexity:** L. **Action now:** none — leave open as architectural memo.

---

### #112 — deferred: none + waiting on prerequisite plans

**Action now:** none — waiting on prerequisite plans to land first.

---

### #113 — needs-decision: none + decide between options

**Action now:** none — decide between option A and option B before proceeding.

"""

expected = {
    100: ("needs-decision", "author decision needed on which option"),
    101: ("plan-scale", "plan-scale"),
    102: ("plan-scale", "plan-scale"),
    103: ("bug-unclear-cause", "unclear cause"),
    104: ("bug-unclear-cause", "unclear cause"),
    105: ("unresearched", "not yet researched"),
    106: None,  # actionable
    107: None,
    108: None,
    109: None,  # mid-text mention must not match
    110: ("needs-decision", None),  # label content varies, but <=60 chars
    111: ("deferred", "leave open as architectural memo"),
    112: ("deferred", "waiting on prerequisite plans to land first"),
    113: ("needs-decision", None),  # "decide between" triggers needs-decision
    999: ("unresearched", "not yet researched"),  # missing section
}

failures = []
for num, want in expected.items():
    got = _parse_action_now(num, SYNTHETIC)
    if want is None:
        if got is not None:
            failures.append(f"#{num}: expected actionable (None), got {got!r}")
        continue
    if got is None:
        failures.append(f"#{num}: expected skip {want!r}, got None")
        continue
    want_code, want_label = want
    if got["code"] != want_code:
        failures.append(
            f"#{num}: expected code={want_code!r}, got code={got['code']!r} (full={got!r})"
        )
        continue
    if want_label is not None and got["label"] != want_label:
        failures.append(
            f"#{num}: expected label={want_label!r}, got label={got['label']!r}"
        )
        continue
    if len(got["label"]) > 60:
        failures.append(f"#{num}: label too long ({len(got['label'])} chars): {got['label']!r}")

# Build-index smoke: assert every requested issue gets an entry.
tracker_path = repo_root / "docs" / "issues" / "ISSUES_PLAN.md"
if tracker_path.is_file():
    idx = _build_skip_reason_index(tracker_path, [67, 432, 429, 999999])
    for n in [67, 432, 429, 999999]:
        if n not in idx:
            failures.append(f"_build_skip_reason_index: missing entry for #{n}")
    # Real-tracker spot-check (regression guards):
    if idx.get(67) is None or idx[67].get("code") != "deferred":
        failures.append(f"real-tracker #67 expected deferred, got {idx.get(67)!r}")
    if idx.get(432) is None or idx[432].get("code") != "needs-decision":
        failures.append(f"real-tracker #432 expected needs-decision, got {idx.get(432)!r}")
    if idx.get(429) is not None:
        failures.append(f"real-tracker #429 (Action now: /do pr) expected None, got {idx[429]!r}")
    if idx.get(999999) is None or idx[999999].get("code") != "unresearched":
        failures.append(f"missing-section #999999 expected unresearched, got {idx.get(999999)!r}")

# Missing-file path: _build_skip_reason_index against a nonexistent file
# returns unresearched for every number.
import tempfile
missing = pathlib.Path(tempfile.gettempdir()) / "zskills-nonexistent-tracker-issue445.md"
if missing.exists():
    missing.unlink()
idx_missing = _build_skip_reason_index(missing, [1, 2, 3])
for n in [1, 2, 3]:
    e = idx_missing.get(n)
    if e is None or e.get("code") != "unresearched":
        failures.append(f"missing-file #{n} expected unresearched, got {e!r}")

# _short_label sanity
sl = _short_label("none — author decision needed", default="author decision needed")
if sl != "author decision needed":
    failures.append(f"_short_label simple em-dash: got {sl!r}")
sl2 = _short_label("none", default="author decision needed")
if sl2 != "author decision needed":
    failures.append(f"_short_label no em-dash falls back to default: got {sl2!r}")
long_in = "none — " + ("x" * 200)
sl3 = _short_label(long_in, default="author decision needed")
if len(sl3) > 60:
    failures.append(f"_short_label truncation: len {len(sl3)} > 60: {sl3!r}")

print(json.dumps({"failures": failures}))
PYEOF
)

PYRC=$?
if [ "$PYRC" -ne 0 ]; then
  fail "python driver" "python3 exited $PYRC; output: $RESULT"
else
  FAIL_LINES=$(printf '%s\n' "$RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for line in data['failures']:
    print(line)
")
  if [ -z "$FAIL_LINES" ]; then
    # Each expected case = 1 pass for granular counting.
    for desc in \
      "synthetic #100 needs-decision (none + author decision)" \
      "synthetic #101 plan-scale (/draft-plan prefix)" \
      "synthetic #102 plan-scale (/run-plan prefix)" \
      "synthetic #103 bug-unclear-cause (/investigate prefix)" \
      "synthetic #104 bug-unclear-cause (Verdict UNCLEAR fallback)" \
      "synthetic #105 unresearched (NOT YET RESEARCHED)" \
      "synthetic #106-108 actionable null (/do pr, /quickfix, sprint)" \
      "synthetic #109 mid-text /draft-plan in qualified action -> null" \
      "synthetic #110 long-label truncates to <=60 chars" \
      "synthetic #111 deferred (none + leave open)" \
      "synthetic #112 deferred (none + waiting)" \
      "synthetic #113 needs-decision (none + decide between)" \
      "synthetic #999 missing section -> unresearched" \
      "real-tracker spot-check (67/432/429/999999)" \
      "_build_skip_reason_index missing-file fallback" \
      "_short_label truncation + fallback"
    do
      pass "$desc"
    done
  else
    fail "_parse_action_now derivation" "$FAIL_LINES"
  fi
fi

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
