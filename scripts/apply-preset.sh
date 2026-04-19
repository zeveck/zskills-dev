#!/bin/bash
# Apply a zskills preset to .claude/zskills-config.json and
# .claude/hooks/block-unsafe-generic.sh.
#
# Usage: bash scripts/apply-preset.sh <cherry-pick|locked-main-pr|direct>
# Env:   PROJECT_ROOT — override root (default: $(pwd))
# Exits: 0 = applied (at least one field changed)
#        1 = no changes (preset already applied)
#        2 = usage error (unknown/missing preset)
#        3 = missing file (config or hook not found)
#        4 = malformed config JSON
#
# Preset → field mapping:
#   cherry-pick    landing=cherry-pick  main_protected=false  BLOCK_MAIN_PUSH=0
#   locked-main-pr landing=pr           main_protected=true   BLOCK_MAIN_PUSH=1
#   direct         landing=direct       main_protected=false  BLOCK_MAIN_PUSH=0
#
# The script is idempotent: repeat invocations with the same preset exit
# with code 1 and no writes. It preserves every config field not owned
# by the preset (branch_prefix, testing.*, dev_server.*, ui.*, ci.*,
# timezone, agents.min_model, $schema, project_name).
#
# Hook behavior:
#   - If the BLOCK_MAIN_PUSH= line is missing (legacy hook), splice
#     BLOCK_MAIN_PUSH=<target> before the first non-comment, non-blank
#     line of code. This is a non-destructive fill — equivalent to the
#     "missing value gets default" upgrade pattern.
#   - If the line exists with a different value, sed-flip it in place.
#   - Otherwise no-op.

set -e

PRESET="${1:-}"
case "$PRESET" in
  cherry-pick)    LANDING=cherry-pick; MAIN_PROTECTED=false; BLOCK_MAIN_PUSH=0 ;;
  locked-main-pr) LANDING=pr;          MAIN_PROTECTED=true;  BLOCK_MAIN_PUSH=1 ;;
  direct)         LANDING=direct;      MAIN_PROTECTED=false; BLOCK_MAIN_PUSH=0 ;;
  "")  echo "usage: apply-preset.sh <cherry-pick|locked-main-pr|direct>" >&2; exit 2 ;;
  *)   echo "apply-preset: unknown preset '$PRESET' (valid: cherry-pick, locked-main-pr, direct)" >&2; exit 2 ;;
esac

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CONFIG="$PROJECT_ROOT/.claude/zskills-config.json"
HOOK="$PROJECT_ROOT/.claude/hooks/block-unsafe-generic.sh"

if [ ! -f "$CONFIG" ]; then
  echo "apply-preset: $CONFIG not found. Run /update-zskills first to create the config." >&2
  exit 3
fi
if [ ! -f "$HOOK" ]; then
  echo "apply-preset: $HOOK not found. Install hooks via /update-zskills install first." >&2
  exit 3
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "apply-preset: python3 required (for JSON config manipulation)." >&2
  exit 3
fi

CHANGED=()

# ─── Config: execution.landing + execution.main_protected ───────────
CONFIG_DIFF=$(python3 - "$CONFIG" "$LANDING" "$MAIN_PROTECTED" <<'PY'
import json, sys
path, landing, main_protected_str = sys.argv[1], sys.argv[2], sys.argv[3]
main_protected = main_protected_str == 'true'
with open(path) as f:
    raw = f.read()
try:
    cfg = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"error: {path} is not valid JSON: {e}", file=sys.stderr)
    sys.exit(4)
changed = []
if 'execution' not in cfg or not isinstance(cfg.get('execution'), dict):
    cfg['execution'] = {
        'landing': landing,
        'main_protected': main_protected,
        'branch_prefix': 'feat/',
    }
    changed.append('execution (inserted)')
else:
    ex = cfg['execution']
    if ex.get('landing') != landing:
        ex['landing'] = landing
        changed.append(f'execution.landing={landing}')
    if ex.get('main_protected') != main_protected:
        ex['main_protected'] = main_protected
        changed.append(f'execution.main_protected={main_protected_str}')
if changed:
    with open(path, 'w') as f:
        json.dump(cfg, f, indent=2)
        f.write('\n')
print('|'.join(changed))
PY
)
RC=$?
if [ $RC -ne 0 ]; then
  exit $RC
fi
if [ -n "$CONFIG_DIFF" ]; then
  IFS='|' read -ra parts <<<"$CONFIG_DIFF"
  for p in "${parts[@]}"; do CHANGED+=("$p"); done
fi

# ─── Hook: ensure BLOCK_MAIN_PUSH= exists and matches target ────────
CURRENT_LINE=$(grep -m1 '^BLOCK_MAIN_PUSH=' "$HOOK" || true)

if [ -z "$CURRENT_LINE" ]; then
  # Legacy hook — no BLOCK_MAIN_PUSH line. Splice default before the
  # first non-comment non-blank code line.
  TMP=$(mktemp)
  awk -v val="$BLOCK_MAIN_PUSH" '
    BEGIN { inserted=0 }
    !inserted && NR>1 && !/^#/ && !/^[[:space:]]*$/ {
      print "# Preset toggle — set by scripts/apply-preset.sh. Do not edit manually."
      print "BLOCK_MAIN_PUSH=" val
      print ""
      inserted=1
    }
    { print }
    END {
      # Safety net: if the file had no code lines at all, append.
      if (!inserted) {
        print "# Preset toggle — set by scripts/apply-preset.sh. Do not edit manually."
        print "BLOCK_MAIN_PUSH=" val
      }
    }
  ' "$HOOK" > "$TMP"
  # Preserve the hook's execute bit (matches original) — mv strips some attrs; use cp+rm.
  cat "$TMP" > "$HOOK"
  rm -f "$TMP"
  CHANGED+=("BLOCK_MAIN_PUSH=$BLOCK_MAIN_PUSH (spliced into legacy hook)")
else
  CURRENT_VAL="${CURRENT_LINE#BLOCK_MAIN_PUSH=}"
  # Strip any trailing comment/whitespace (e.g., "BLOCK_MAIN_PUSH=1  # comment")
  CURRENT_VAL="${CURRENT_VAL%%[[:space:]#]*}"
  if [ "$CURRENT_VAL" != "$BLOCK_MAIN_PUSH" ]; then
    # Match exactly "BLOCK_MAIN_PUSH=<digit>" at line start; preserve trailing content
    sed -i -E "s/^BLOCK_MAIN_PUSH=[01]/BLOCK_MAIN_PUSH=$BLOCK_MAIN_PUSH/" "$HOOK"
    CHANGED+=("BLOCK_MAIN_PUSH: $CURRENT_VAL → $BLOCK_MAIN_PUSH")
  fi
fi

# ─── Report ─────────────────────────────────────────────────────────
if [ ${#CHANGED[@]} -eq 0 ]; then
  echo "Preset '$PRESET' already applied — no changes needed."
  exit 1
fi

echo "Applied preset '$PRESET':"
for c in "${CHANGED[@]}"; do echo "  - $c"; done
exit 0
