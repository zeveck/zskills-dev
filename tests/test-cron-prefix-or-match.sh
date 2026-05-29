#!/bin/bash
# tests/test-cron-prefix-or-match.sh
#
# Phase 3 (PLUGIN_DISTRIBUTION) — decision D12: the cron-fire recognition
# rule must recognize BOTH prefix forms PERMANENTLY:
#   - bare prefix  `Run /<skill-name> `   (/update-zskills install lane)
#   - plugin prefix `Run /zs:<skill-name> ` (plugin install lane)
# with NO sunset / expiry date.
#
# Asserts against the rendered `.claude/rules/zskills/managed.md` (the
# auto-loaded rules file) so we catch any drift between CLAUDE_TEMPLATE.md
# and its rendered output. `test-managed-md-up-to-date.sh` separately gates
# that managed.md is a faithful render; this test gates the CONTENT of the
# cron-fire recognition rule.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MANAGED=".claude/rules/zskills/managed.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

if [ ! -f "$MANAGED" ]; then
  fail "rendered managed.md present at $MANAGED"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
  exit $FAIL_COUNT
fi

# Isolate the cron-fire recognition section so date / prefix assertions are
# scoped to that rule, not the whole file. Section runs from the
# "## Cron-fired prompts" heading to the next "## " heading.
SECTION="$(awk '
  /^## Cron-fired prompts[[:space:]]*$/ { grab=1; next }
  grab && /^## / { exit }
  grab { print }
' "$MANAGED")"

if [ -z "$SECTION" ]; then
  fail "managed.md contains a '## Cron-fired prompts' section"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
  exit $FAIL_COUNT
else
  pass "managed.md contains a '## Cron-fired prompts' section"
fi

# 1. Bare-prefix recognition pattern present.
if grep -qF 'Run /<skill-name> ' <<<"$SECTION"; then
  pass "cron-fire rule recognizes bare prefix 'Run /<skill-name> '"
else
  fail "cron-fire rule must recognize bare prefix 'Run /<skill-name> '"
fi

# 2. Plugin-prefix recognition pattern present.
if grep -qF 'Run /zs:<skill-name> ' <<<"$SECTION"; then
  pass "cron-fire rule recognizes plugin prefix 'Run /zs:<skill-name> '"
else
  fail "cron-fire rule must recognize plugin prefix 'Run /zs:<skill-name> '"
fi

# 3. The OR-match is stated permanently — NO sunset/expiry date.
#    The round-3 plan specced a 2026-07-21 sunset that D12 explicitly
#    dropped. We must NOT flag legitimate historical-incident date
#    citations elsewhere in the section (e.g. "Past failure 2026-05-18"),
#    so the assertion is twofold and scoped:
#      (3a) the RECOGNITION-RULE paragraph (the line stating the OR-match,
#           identified by containing the 'Run /zs:<skill-name> ' pattern)
#           must contain no YYYY-MM-DD date at all; and
#      (3b) nowhere in the section may a sunset/expiry/deprecat* keyword
#           appear on the same line as a YYYY-MM-DD date.
RULE_LINE="$(grep -F 'Run /zs:<skill-name> ' <<<"$SECTION" | head -1)"
date_in_rule=0
if grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' <<<"$RULE_LINE"; then
  date_in_rule=1
fi
sunset_line="$(grep -iE '(sunset|expir|deprecat)' <<<"$SECTION" | grep -E '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
if [ "$date_in_rule" -eq 0 ] && [ -z "$sunset_line" ]; then
  pass "cron-fire rule states a permanent OR-match with no sunset/expiry date"
else
  if [ "$date_in_rule" -eq 1 ]; then
    fail "cron-fire recognition-rule line must NOT contain a date (found one in: ${RULE_LINE:0:80}...)"
  fi
  if [ -n "$sunset_line" ]; then
    fail "cron-fire section must NOT pair a sunset/expiry/deprecation keyword with a date (found: ${sunset_line:0:80}...)"
  fi
fi

# 4. Permanence is affirmatively stated.
if grep -qiE 'permanent' <<<"$SECTION"; then
  pass "cron-fire rule affirmatively states the OR-match is permanent"
else
  fail "cron-fire rule should state the OR-match is permanent"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit $FAIL_COUNT
