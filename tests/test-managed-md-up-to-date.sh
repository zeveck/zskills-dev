#!/bin/bash
# tests/test-managed-md-up-to-date.sh
#
# Asserts that `.claude/rules/zskills/managed.md` matches the live render of
# `CLAUDE_TEMPLATE.md` against `.claude/zskills-config.json`.
#
# Companion of `/update-zskills --rerender` (Step D in
# `.claude/skills/update-zskills/SKILL.md`). If this test fails, the tracked
# rendered file has drifted from its inputs (someone edited CLAUDE_TEMPLATE.md
# or .claude/zskills-config.json but forgot to rerender). Remediation:
#   /update-zskills --rerender
#   git add .claude/rules/zskills/managed.md
#   git commit
#
# The substitution map below MUST stay in lock-step with /update-zskills
# Step B / Step D --rerender. If you add a placeholder to CLAUDE_TEMPLATE.md,
# add it here AND in the skill's substitution logic.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0

result=$(python3 <<'PY'
import json, re, sys, difflib

with open("CLAUDE_TEMPLATE.md") as f:
    template = f.read()
with open(".claude/zskills-config.json") as f:
    cfg = json.load(f)
with open(".claude/rules/zskills/managed.md") as f:
    expected = f.read()

def empty_or(value, fallback):
    if value is None or value == "":
        return fallback
    return value

ds = cfg.get("dev_server", {})
testing = cfg.get("testing", {})
ui = cfg.get("ui", {})
patterns = testing.get("file_patterns", [])
patterns_md = "\n".join(f"- `{p}`" for p in patterns) if patterns else "<!-- TODO: testing.file_patterns is empty -->"

subs = {
    "PROJECT_NAME": cfg.get("project_name", ""),
    "TIMEZONE": cfg.get("timezone", ""),
    "DEFAULT_PORT": str(ds.get("default_port", "")),
    "MAIN_REPO_PATH": ds.get("main_repo_path", ""),
    "UNIT_TEST_CMD": testing.get("unit_cmd", ""),
    "FULL_TEST_CMD": testing.get("full_cmd", ""),
    "TEST_FILE_PATTERNS": patterns_md,
    "DEV_SERVER_CMD": empty_or(ds.get("cmd", ""), "<!-- TODO: dev_server.cmd not set in .claude/zskills-config.json -->"),
    "AUTH_BYPASS": empty_or(ui.get("auth_bypass", ""), "<!-- TODO: ui.auth_bypass not set in .claude/zskills-config.json -->"),
    "SOURCE_LAYOUT": "<!-- TODO: SOURCE_LAYOUT has no config field; fill in project's architecture summary -->",
}

rendered = template
for k, v in subs.items():
    rendered = rendered.replace("{{" + k + "}}", v)

leftover = re.findall(r"\{\{[A-Z_]+\}\}", rendered)
if leftover:
    print(f"ERROR: render left unsubstituted placeholders: {leftover}")
    sys.exit(2)

if rendered == expected:
    sys.exit(0)

diff = "".join(difflib.unified_diff(
    expected.splitlines(keepends=True),
    rendered.splitlines(keepends=True),
    fromfile=".claude/rules/zskills/managed.md (tracked)",
    tofile="render(CLAUDE_TEMPLATE.md, .claude/zskills-config.json) (live)",
    n=3,
))
diff_lines = diff.splitlines()
cap = 200
if len(diff_lines) > cap:
    print("\n".join(diff_lines[:cap]))
    print(f"... (diff truncated; {len(diff_lines)} total lines)")
else:
    print(diff)
sys.exit(1)
PY
)
rc=$?

if [ "$rc" -eq 0 ]; then
  PASS=$((PASS + 1))
  echo "PASS: managed.md matches live render of CLAUDE_TEMPLATE.md + .claude/zskills-config.json"
elif [ "$rc" -eq 2 ]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: render produced unsubstituted placeholders (template/script out of sync)"
  echo ""
  echo "$result"
else
  FAIL=$((FAIL + 1))
  echo "FAIL: .claude/rules/zskills/managed.md is stale relative to CLAUDE_TEMPLATE.md / .claude/zskills-config.json"
  echo ""
  echo "$result"
  echo ""
  echo "Remediation: run \`/update-zskills --rerender\` and commit the result."
fi

echo ""
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 1
fi
