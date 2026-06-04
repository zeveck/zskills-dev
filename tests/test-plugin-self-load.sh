#!/bin/bash
# tests/test-plugin-self-load.sh
#
# W1.6 (D9) — plugin self-load is a real load test, not bash-lint. Three
# parts, covering BOTH plugins (zs + zsbd):
#
#   (a) `claude plugin validate --strict` if the CLI is available, else
#       SKIP-with-reason. Validates the marketplace manifest (which covers
#       both plugin entries) AND the zsbd plugin manifest directly.
#   (b) Python json validation of both plugin.json files (zs + zsbd):
#       parse + required top-level fields.
#   (c) `bash -n` on every hook + helper script under hooks/, with an
#       explicit case-branch exclusion for hooks/canary*-bad.sh (the
#       deliberately-broken syntax fixtures).
#
# No jq — Python json per `## Python is required`.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT+1)); }

echo "=== plugin self-load (zs + zsbd) ==="

# ── (a) claude plugin validate --strict ──────────────────────────────────
if command -v claude >/dev/null 2>&1; then
  # Marketplace manifest (now lists a single entry: zs).
  if claude plugin validate "$REPO_ROOT" --strict 2>&1 | grep -q 'Validation passed'; then
    pass "(a) claude plugin validate --strict: marketplace manifest passes"
  else
    fail "(a) claude plugin validate --strict: marketplace manifest"
    claude plugin validate "$REPO_ROOT" --strict 2>&1 | sed 's/^/      /'
  fi
  # zsbd plugin manifest directly.
  if claude plugin validate "$REPO_ROOT/block-diagram" --strict 2>&1 | grep -q 'Validation passed'; then
    pass "(a) claude plugin validate --strict: zsbd plugin manifest passes"
  else
    fail "(a) claude plugin validate --strict: zsbd plugin manifest"
    claude plugin validate "$REPO_ROOT/block-diagram" --strict 2>&1 | sed 's/^/      /'
  fi
else
  skip "(a) claude plugin validate --strict — claude CLI not on PATH"
fi

# ── (b) Python json validation of both plugin.json ───────────────────────
for MANIFEST in ".claude-plugin/plugin.json" "block-diagram/.claude-plugin/plugin.json"; do
  if "$PYTHON" - "$MANIFEST" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    doc = json.load(f)
required = ["name", "version", "description", "author"]
missing = [k for k in required if k not in doc]
if missing:
    print(f"missing required fields: {missing}", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
  then
    pass "(b) python json: $MANIFEST parses + required fields present"
  else
    fail "(b) python json: $MANIFEST"
  fi
done

# ── (c) bash -n on every hook + helper, excluding canary*-bad.sh ─────────
shopt -s nullglob
LINT_TARGETS=( hooks/*.sh hooks/*.sh.template hooks/_lib/*.sh )
shopt -u nullglob
for f in "${LINT_TARGETS[@]}"; do
  bn="$(basename "$f")"
  # Literal case-branch exclusion for the deliberately-broken canary
  # fixtures (D9): hooks/canary*-bad.sh.
  case "$bn" in
    canary*-bad.sh)
      skip "(c) bash -n: $f (canary syntax-error fixture, excluded)"
      continue
      ;;
  esac
  if bash -n "$f" 2>/dev/null; then
    pass "(c) bash -n: $f"
  else
    fail "(c) bash -n: $f"
    bash -n "$f" 2>&1 | sed 's/^/      /'
  fi
done

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped (of $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT)))"
exit "$FAIL_COUNT"
