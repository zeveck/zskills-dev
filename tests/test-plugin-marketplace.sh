#!/bin/bash
# tests/test-plugin-marketplace.sh
#
# W1.5 (D8 / D1 / D2) — validates the marketplace manifest at
# .claude-plugin/marketplace.json.
#
# The marketplace lists EXACTLY ONE plugin (`zs`).
#
# Uses Python json (no jq — per `## Python is required`). Asserts:
#   - manifest parses + carries required top-level fields (name, owner,
#     plugins, and — strict-mode requirement — a top-level `description`);
#   - exactly one plugin entry named `zs`;
#   - the `zs` entry's source is the github object form the current
#     validator accepts: { "source": "github", "repo": ..., "ref": ... }
#     (the plan's nested-`github` example form is rejected by claude
#     2.1.153 — see W1.5 implementer note);
#   - `dependencies` is absent on the zs plugin manifest;
#   - the zs plugin manifest carries a non-empty string `version`.

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

echo "=== marketplace manifest validation ==="

RESULT=$("$PYTHON" - <<'PY'
import json, sys

def out(ok, label, detail=""):
    print(f"{'PASS' if ok else 'FAIL'}\t{label}\t{detail}")

MP = ".claude-plugin/marketplace.json"

def load(path):
    try:
        with open(path) as f:
            return json.load(f), None
    except Exception as e:
        return None, str(e)

mp, err = load(MP)
out(mp is not None, f"{MP} parses as JSON", err or "")
if mp is None:
    sys.exit(0)

# Required top-level fields. Strict mode requires a top-level `description`.
for k, t in (("name", str), ("owner", dict), ("plugins", list), ("description", str)):
    present = k in mp
    out(present, f"marketplace: required field '{k}' present")
    if present:
        out(isinstance(mp[k], t), f"marketplace: field '{k}' is {t.__name__}")

out(mp.get("name") == "zskills", "marketplace: name == 'zskills'", repr(mp.get("name")))

plugins = mp.get("plugins", [])
by_name = {p.get("name"): p for p in plugins if isinstance(p, dict)}
out(set(by_name) == {"zs"},
    "marketplace: exactly one plugin (zs)", repr(sorted(by_name)))

# zs source — github object form accepted by the current validator:
# { "source": "github", "repo": ..., "ref": ... }
# This test runs against the DEV tree, whose manifest SELF-REFERENCES the dev
# repo (zeveck/zskills-dev) so pre-publish plugin qual uses the genuine consumer
# flow. The publish path (scripts/_lib/finalize-prod-tree.sh's
# rewrite_marketplace_repo) translates this to zeveck/zskills in the prod tree;
# tests/test-prod-tree-no-dev-urls.sh asserts the BUILT tree is prod-pointing.
zs = by_name.get("zs", {})
zs_src = zs.get("source")
ok_zs = (isinstance(zs_src, dict)
         and zs_src.get("source") == "github"
         and zs_src.get("repo") == "zeveck/zskills-dev"
         and zs_src.get("ref") == "main")
out(ok_zs, "marketplace: zs source is github {source,repo,ref}", repr(zs_src))

zs_plugin, zerr = load(".claude-plugin/plugin.json")
out(zs_plugin is not None, ".claude-plugin/plugin.json parses as JSON", zerr or "")
if zs_plugin is not None:
    out("dependencies" not in zs_plugin, "zs plugin: dependencies ABSENT", repr(zs_plugin.get("dependencies")))
    # The zs plugin manifest must carry a non-empty string `version`.
    zs_ver = zs_plugin.get("version")
    out(isinstance(zs_ver, str) and len(zs_ver) > 0,
        "zs plugin: version is a non-empty string", repr(zs_ver))
PY
)

while IFS=$'\t' read -r tag label detail; do
  [ -z "$tag" ] && continue
  if [ "$tag" = "PASS" ]; then
    pass "$label"
  else
    fail "$label ${detail:+— $detail}"
  fi
done <<< "$RESULT"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
exit "$FAIL_COUNT"
