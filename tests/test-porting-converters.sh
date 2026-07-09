#!/bin/bash
# tests/test-porting-converters.sh — suite for the Phase 3 converters
# (CODEX_PORT_PLAN WIs 3.3/3.4/3.5/3.6): agents-to-toml.py against the REAL
# agents/verifier.md, hooks-translate.py against the REAL hooks/hooks.json
# (both plugin-root styles), and the render-agents-md.sh wrapper (success +
# oversize dual-delivery failure).
#
# pass/fail inline (mirrors tests/test-porting-probe-kit.sh).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
A2T="$REPO_ROOT/scripts/porting/agents-to-toml.py"
HTX="$REPO_ROOT/scripts/porting/hooks-translate.py"
RAM="$REPO_ROOT/scripts/porting/render-agents-md.sh"
FIX="$REPO_ROOT/tests/fixtures/porting"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

PYTHON="$(command -v python3 || command -v python || true)"
if [ -z "$PYTHON" ]; then
  echo "SKIP: no python3/python available (required by the converters)" >&2
  echo "Results: 0 passed, 0 failed (of 0)"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zskills-codex-conv-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

for f in "$A2T" "$HTX" "$RAM"; do
  if [ ! -f "$f" ]; then
    fail "required script not found at $f"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
    exit 1
  fi
done

HAS_TOMLLIB=0
"$PYTHON" -c 'import tomllib' >/dev/null 2>&1 && HAS_TOMLLIB=1

# ── 1. agents-to-toml against the REAL agents/verifier.md ───────────────────
VT="$WORK/verifier.toml"
"$PYTHON" "$A2T" "$REPO_ROOT/agents/verifier.md" --out "$VT" > "$WORK/a2t.stdout" 2>"$WORK/a2t.stderr"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "agents-to-toml converts agents/verifier.md (rc=0)"
else
  fail "agents-to-toml exited $rc: $(sed -n '1,2p' "$WORK/a2t.stderr")"
fi
if [ -f "$VT" ]; then
  pass "agents-to-toml wrote the output TOML"
else
  fail "agents-to-toml wrote nothing at $VT"
fi

if [ "$HAS_TOMLLIB" -eq 1 ]; then
  TOML_CHECK="$("$PYTHON" -c '
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
missing = [k for k in ("name", "description", "developer_instructions") if not d.get(k)]
if missing:
    print("EMPTY:" + ",".join(missing)); sys.exit(1)
if "model" in d:
    print("MODEL-PRESENT:" + repr(d["model"])); sys.exit(1)
if d["name"] != "verifier":
    print("BAD-NAME:" + repr(d["name"])); sys.exit(1)
print("OK bodylen=%d" % len(d["developer_instructions"]))
' "$VT" 2>&1)"
  if [ $? -eq 0 ]; then
    pass "output is tomllib-parseable; name/description/developer_instructions non-empty ($TOML_CHECK)"
  else
    fail "tomllib validation failed: $TOML_CHECK"
  fi
  BODY_OK="$("$PYTHON" -c '
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
src = open(sys.argv[2], encoding="utf-8").read()
body = src.split("---", 2)[2].lstrip("\n")
sys.exit(0 if d["developer_instructions"] == body else 1)
' "$VT" "$REPO_ROOT/agents/verifier.md" && echo yes || echo no)"
  if [ "$BODY_OK" = "yes" ]; then
    pass "developer_instructions is the verbatim agent body (full body, never a wrapper)"
  else
    fail "developer_instructions differs from the agent body"
  fi
else
  echo "  (tomllib unavailable — Python < 3.11; parse assertions skipped)" >&2
fi

if grep -q 'DEGRADATIONS' "$WORK/a2t.stdout" && grep -q 'tools:' "$WORK/a2t.stdout"; then
  pass "degradations report names the untranslatable tools: allowlist"
else
  fail "degradations report missing or does not name tools:"
fi
# `model: inherit` → omitted from the TOML (Codex default is inheriting)
if grep -Eq '^model *=' "$VT"; then
  fail "model key present in TOML despite 'model: inherit' in the frontmatter"
else
  pass "model: inherit is omitted from the TOML"
fi

# ── 2. hooks-translate against the REAL hooks/hooks.json — native style ─────
HN="$WORK/hooks-native.json"
"$PYTHON" "$HTX" "$REPO_ROOT/hooks/hooks.json" --plugin-root-style native --out "$HN" > "$WORK/htx-native.stdout" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "hooks-translate (native) exits 0"
else
  fail "hooks-translate (native) exited $rc: $(tail -2 "$WORK/htx-native.stdout" | tr '\n' ' ')"
fi
if "$PYTHON" -c 'import json,sys; json.load(open(sys.argv[1]))' "$HN" 2>/dev/null; then
  pass "native output is json.load-parseable"
else
  fail "native output is not valid JSON"
fi
if grep -q 'CLAUDE_PLUGIN_ROOT' "$HN"; then
  fail "native output carries CLAUDE_PLUGIN_ROOT residue"
else
  pass "native output has zero CLAUDE_PLUGIN_ROOT residue"
fi
if grep -q 'PLUGIN_ROOT' "$HN"; then
  pass "native output rewrote paths to \${PLUGIN_ROOT}"
else
  fail "native output carries no PLUGIN_ROOT paths at all"
fi
if grep -q 'DROPPED' "$WORK/htx-native.stdout" && grep -q 'CronCreate' "$WORK/htx-native.stdout"; then
  pass "dropped-entry listing present and names the CronCreate entry"
else
  fail "dropped-entry listing missing or does not name CronCreate"
fi
if grep -qi 'trust-review' "$WORK/htx-native.stdout"; then
  pass "trust-review note emitted (non-managed hooks are dead until trusted)"
else
  fail "trust-review note missing from stdout"
fi
# structural: no-substrate events are gone; live events survive
STRUCT="$("$PYTHON" -c '
import json, sys
d = json.load(open(sys.argv[1]))
ev = d.get("hooks", {})
bad = [e for e in ("UserPromptExpansion", "PermissionRequest") if e in ev]
if bad:
    print("KEPT-DEAD-EVENT:" + ",".join(bad)); sys.exit(1)
if "PreToolUse" not in ev or "SessionStart" not in ev:
    print("LOST-LIVE-EVENT"); sys.exit(1)
matchers = [e.get("matcher", "") for e in ev["PreToolUse"]]
if any("CronCreate" in m for m in matchers):
    print("KEPT-CRON-MATCHER"); sys.exit(1)
if "Bash" not in matchers:
    print("LOST-BASH-MATCHER"); sys.exit(1)
print("OK events=%d" % len(ev))
' "$HN" 2>&1)"
if [ $? -eq 0 ]; then
  pass "event structure: dead events/matchers dropped, live ones kept ($STRUCT)"
else
  fail "event structure wrong: $STRUCT"
fi

# ── 3. hooks-translate — alias style keeps the compat alias ─────────────────
HA="$WORK/hooks-alias.json"
"$PYTHON" "$HTX" "$REPO_ROOT/hooks/hooks.json" --plugin-root-style alias --out "$HA" > "$WORK/htx-alias.stdout" 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "hooks-translate (alias) exits 0"
else
  fail "hooks-translate (alias) exited $rc"
fi
if "$PYTHON" -c 'import json,sys; json.load(open(sys.argv[1]))' "$HA" 2>/dev/null; then
  pass "alias output is json.load-parseable"
else
  fail "alias output is not valid JSON"
fi
ALIAS_N="$(grep -c 'CLAUDE_PLUGIN_ROOT' "$HA" || true)"
if [ "$ALIAS_N" -gt 0 ]; then
  pass "alias output keeps CLAUDE_PLUGIN_ROOT ($ALIAS_N line(s) — valid only when the probe confirmed the alias)"
else
  fail "alias output lost CLAUDE_PLUGIN_ROOT (alias style must keep it)"
fi

# ── 4. render-agents-md — success on a small fixture template ───────────────
SMALL_OUT="$WORK/AGENTS-small.md"
if bash "$RAM" --template "$FIX/render-small-template.md" --out "$SMALL_OUT" > "$WORK/ram-small.out" 2>&1; then
  pass "render-agents-md renders the small fixture (rc=0)"
else
  fail "render-agents-md failed on the small fixture: $(tail -2 "$WORK/ram-small.out" | tr '\n' ' ')"
fi
if [ -f "$SMALL_OUT" ] && cmp -s "$FIX/render-small-template.md" "$SMALL_OUT"; then
  pass "wrapper does not transform content (token-free template renders byte-identical)"
else
  fail "rendered output missing or differs from the token-free template"
fi

# ── 5. render-agents-md — oversize template fails with dual-delivery ────────
if bash "$RAM" --template "$FIX/oversize-template.md" --out "$WORK/AGENTS-big.md" > "$WORK/ram-big.out" 2>&1; then
  fail "render-agents-md exited 0 on the oversize template (must fail the 32 KiB cap)"
else
  pass "render-agents-md exits non-zero on the oversize template"
fi
if grep -q 'project_doc_max_bytes' "$WORK/ram-big.out"; then
  pass "oversize failure names project_doc_max_bytes"
else
  fail "oversize failure does not name project_doc_max_bytes"
fi
if grep -q 'additionalContext' "$WORK/ram-big.out" && grep -qi 'short AGENTS.md' "$WORK/ram-big.out"; then
  pass "oversize failure carries the dual-delivery instruction (short AGENTS.md + SessionStart additionalContext)"
else
  fail "oversize failure missing the dual-delivery instruction"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
