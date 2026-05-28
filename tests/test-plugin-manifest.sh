#!/bin/bash
# tests/test-plugin-manifest.sh
#
# W1.5 (D8 / D2) — validates the two plugin manifests:
#   .claude-plugin/plugin.json                 (the `zs` plugin)
#   block-diagram/.claude-plugin/plugin.json   (the `zsbd` addon plugin)
#
# Uses Python JSONSchema-style validation (no jq — per `## Python is
# required`). Asserts:
#   - both manifests parse as JSON and carry the required top-level fields;
#   - plugin names are exactly `zs` / `zsbd`;
#   - `dependencies` is PRESENT on zsbd (declares {name: zs}) and ABSENT on
#     zs (D2 / F-DA2-1 orphan-install closure);
#   - the zsbd `skills` field is `["./"]` and the zsbd skill roster on disk
#     enumerates exactly the 4 SKILL.md-bearing block-diagram dirs
#     (RE-DERIVED at run time via find — NOT a frozen list, per D2);
#   - the zs `skills` field references both ./skills/ and ./block-diagram/
#     and `hooks` points at ./hooks/hooks.json; NO `agents` field on either.

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

echo "=== plugin manifest validation (zs + zsbd) ==="

# Re-derive the expected zsbd skill roster from disk (D2: not a frozen list).
EXPECTED_BD_SKILLS=$(find block-diagram -mindepth 2 -name SKILL.md -printf '%h\n' | sed 's#^block-diagram/##' | sort | tr '\n' ',' )

# Run all structural assertions in one Python pass; emit PASS/FAIL lines the
# shell tallies.
RESULT=$(EXPECTED_BD_SKILLS="$EXPECTED_BD_SKILLS" "$PYTHON" - <<'PY'
import json, os, sys

def out(ok, label, detail=""):
    tag = "PASS" if ok else "FAIL"
    print(f"{tag}\t{label}\t{detail}")

ZS = ".claude-plugin/plugin.json"
ZSBD = "block-diagram/.claude-plugin/plugin.json"

# ---- load + parse ----
def load(path):
    try:
        with open(path) as f:
            return json.load(f), None
    except Exception as e:
        return None, str(e)

zs, zs_err = load(ZS)
out(zs is not None, f"{ZS} parses as JSON", zs_err or "")
zsbd, zsbd_err = load(ZSBD)
out(zsbd is not None, f"{ZSBD} parses as JSON", zsbd_err or "")

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
check_required(zsbd, "zsbd")

# ---- names ----
if zs is not None:
    out(zs.get("name") == "zs", "zs: name == 'zs'", repr(zs.get("name")))
if zsbd is not None:
    out(zsbd.get("name") == "zsbd", "zsbd: name == 'zsbd'", repr(zsbd.get("name")))

# ---- dependencies: present on zsbd, absent on zs ----
if zsbd is not None:
    deps = zsbd.get("dependencies")
    ok = isinstance(deps, list) and any(
        isinstance(d, dict) and d.get("name") == "zs" for d in deps
    )
    out(ok, "zsbd: dependencies present and declares {name: zs}", repr(deps))
if zs is not None:
    out("dependencies" not in zs, "zs: dependencies ABSENT", repr(zs.get("dependencies")))

# ---- agents field absent on both (D11) ----
if zs is not None:
    out("agents" not in zs, "zs: no 'agents' field (D11)")
if zsbd is not None:
    out("agents" not in zsbd, "zsbd: no 'agents' field (D11)")

# ---- zs skills + hooks ----
if zs is not None:
    skills = zs.get("skills")
    out(isinstance(skills, list) and "./skills/" in skills and "./block-diagram/" in skills,
        "zs: skills references ./skills/ and ./block-diagram/", repr(skills))
    out(zs.get("hooks") == "./hooks/hooks.json",
        "zs: hooks points at ./hooks/hooks.json", repr(zs.get("hooks")))

# ---- zsbd skills field + roster re-derivation ----
if zsbd is not None:
    out(zsbd.get("skills") == ["./"], "zsbd: skills == ['./']", repr(zsbd.get("skills")))
    out("hooks" not in zsbd, "zsbd: no 'hooks' field (rides with zs)", repr(zsbd.get("hooks")))

# zsbd roster: re-derived list passed in via env must be exactly the 4
# block-diagram SKILL.md-bearing dirs.
expected = [s for s in os.environ.get("EXPECTED_BD_SKILLS", "").split(",") if s]
expected_set = set(expected)
canonical = {"add-block", "add-example", "model-design", "review-feedback"}
out(expected_set == canonical,
    "zsbd roster: disk has exactly add-block/add-example/model-design/review-feedback",
    repr(sorted(expected_set)))
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

echo ""
echo "=== hooks.json registered-script existence (#765) ==="

# #765: assert every script registered in hooks/hooks.json is backed by a real
# source-tree file. The dangling SessionStart -> session-start-materialise.sh
# forward-reference (a Phase-2 artifact) shipped green because the only check
# that would have caught it (`claude plugin validate --strict`) is SKIPPED when
# the `claude` CLI is off PATH. This assertion runs unconditionally (Python
# stdlib only) so the gap is closed regardless of CLI availability.
#
# Backing-file rule: a registered `hooks/X.sh` is satisfied by EITHER
# `hooks/X.sh` directly OR its `hooks/X.sh.template` sibling. The latter covers
# the D4 `.template` hooks (`block-agents.sh`, `block-unsafe-project.sh`): the
# suffixless plugin-tree copy is generated at release time by
# build-plugin-release.sh, so in the source tree only the `.template` form
# exists. `session-start-materialise.sh` has NEITHER form, so it is still
# caught.
HOOKS_RESULT=$("$PYTHON" - <<'PY'
import json, os, re

def out(ok, label, detail=""):
    print(f"{'PASS' if ok else 'FAIL'}\t{label}\t{detail}")

HOOKS = "hooks/hooks.json"
try:
    with open(HOOKS) as f:
        doc = json.load(f)
    out(True, f"{HOOKS} parses as JSON")
except Exception as e:
    out(False, f"{HOOKS} parses as JSON", str(e))
    raise SystemExit(0)

# Walk every command string and extract the ${CLAUDE_PLUGIN_ROOT}-relative
# script path: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh"` -> `hooks/foo.sh`.
pat = re.compile(r'\$\{CLAUDE_PLUGIN_ROOT\}/(\S+?\.sh)')
paths = []
for event, entries in doc.get("hooks", {}).items():
    for entry in entries:
        for h in entry.get("hooks", []):
            cmd = h.get("command", "")
            for m in pat.finditer(cmd):
                paths.append((event, m.group(1)))

out(len(paths) > 0, "hooks.json registers at least one script command",
    f"{len(paths)} command(s)")

for event, rel in paths:
    backed = os.path.isfile(rel) or os.path.isfile(rel + ".template")
    out(backed, f"registered script is backed by source-tree file: {rel} ({event})",
        "" if backed else "no .sh and no .sh.template sibling")
PY
)

while IFS=$'\t' read -r tag label detail; do
  [ -z "$tag" ] && continue
  if [ "$tag" = "PASS" ]; then
    pass "$label"
  else
    fail "$label ${detail:+— $detail}"
  fi
done <<< "$HOOKS_RESULT"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit "$FAIL_COUNT"
