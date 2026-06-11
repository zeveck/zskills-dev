#!/bin/bash
# tests/test-plugin-manifest.sh
#
# W1.5 (D8 / D2) — validates the plugin manifest:
#   .claude-plugin/plugin.json   (the `zs` plugin)
#
# Uses Python JSONSchema-style validation (no jq — per `## Python is
# required`). Asserts:
#   - the manifest parses as JSON and carries the required top-level fields;
#   - the plugin name is exactly `zs`;
#   - `dependencies` is ABSENT (D2 / F-DA2-1 orphan-install closure);
#   - the zs `skills` field is exactly ["./skills/"] and there is NO `hooks`
#     field (the standard hooks/hooks.json is auto-loaded by Claude Code from
#     the plugin root — a manifest `hooks` reference to it causes a
#     duplicate-hooks load error); NO `agents` field (INSTALL_REDESIGN
#     Phase 1 claim-1 probe: `claude plugin validate` REJECTS the field
#     (rc=1 "agents: Invalid input") AND it breaks agent load — the root
#     agents/ dir is auto-loaded, the manifest must never name it);
#   - tree shape (1A): agents/verifier.md + agents/implementer.md exist at
#     the plugin root (the auto-loaded plugin-native agent sources).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== plugin manifest validation (zs) ==="

# Run all structural assertions in one Python pass; emit PASS/FAIL lines the
# shell tallies.
RESULT=$("$PYTHON" - <<'PY'
import json, sys

def out(ok, label, detail=""):
    tag = "PASS" if ok else "FAIL"
    print(f"{tag}\t{label}\t{detail}")

ZS = ".claude-plugin/plugin.json"

# ---- load + parse ----
def load(path):
    try:
        with open(path) as f:
            return json.load(f), None
    except Exception as e:
        return None, str(e)

zs, zs_err = load(ZS)
out(zs is not None, f"{ZS} parses as JSON", zs_err or "")

# Minimal JSONSchema-style validator (required keys + types). No external
# deps — per `## Python is required`, json stdlib only.
REQUIRED = {
    "name": str, "version": str, "description": str, "author": dict,
}
def check_required(doc, label):
    if doc is None:
        return
    for k, t in REQUIRED.items():
        present = k in doc
        out(present, f"{label}: required field '{k}' present")
        if present:
            out(isinstance(doc[k], t), f"{label}: field '{k}' is {t.__name__}")

check_required(zs, "zs")

# ---- name ----
if zs is not None:
    out(zs.get("name") == "zs", "zs: name == 'zs'", repr(zs.get("name")))

# ---- dependencies: absent ----
if zs is not None:
    out("dependencies" not in zs, "zs: dependencies ABSENT", repr(zs.get("dependencies")))

# ---- agents field absent (D11 surviving leg; Phase-1 claim-1 confirmed:
# ---- validate-rejects AND breaks agent load — auto-load dir only) ----
if zs is not None:
    out("agents" not in zs, "zs: no 'agents' field (D11 / Phase-1 claim-1)")

# ---- zs skills + hooks ----
if zs is not None:
    out(zs.get("skills") == ["./skills/"],
        "zs: skills == ['./skills/']", repr(zs.get("skills")))
    out("hooks" not in zs,
        "zs: no 'hooks' field (standard hooks/hooks.json auto-loaded)", repr(zs.get("hooks")))
PY
)

# Tally.
while IFS=$'\t' read -r tag label detail; do
  [ -z "$tag" ] && continue
  if [ "$tag" = "PASS" ]; then
    pass "$label"
  else
    fail "$label ${detail:+— $detail}"
  fi
done <<< "$RESULT"

# ---- tree shape (INSTALL_REDESIGN Phase 2, branch 1A) ----
# The plugin-native verifier/implementer agents are checked-in root agents/
# files, auto-loaded from the plugin root (companion to the no-'agents'-field
# assertion above). Missing files here mean the plugin lane cannot dispatch
# verifier/implementer mirror-lessly.
echo ""
echo "=== plugin tree shape (1A root agents/) ==="
for a in verifier implementer; do
  if [ -f "agents/$a.md" ]; then
    pass "agents/$a.md present at plugin root"
  else
    fail "agents/$a.md MISSING at plugin root (1A plugin-native agent source)"
  fi
done

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit "$FAIL_COUNT"
