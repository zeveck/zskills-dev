## Reconsider (if `reconsider` is present)

Flag a previously-skipped issue for re-evaluation on the next sprint. This
is an early-exit subcommand that adds the issue number to the
`issues.reconsider` list in `.zskills/monitor-state.json` and exits — it
does NOT proceed to Phase 0/1/2.

**Syntax:** `reconsider <N>`
- `<N>` — positive integer (GitHub issue number). REQUIRED.

**Behavior:**
- Adds `<N>` to the `issues.reconsider` array in `.zskills/monitor-state.json`.
- Creates the `issues.reconsider` key if absent; deduplicates.
- Idempotent: if the number is already in the list, exit 0 with a note.
- Atomic write via Python tempfile + `os.replace`.

The reconsider list is a one-shot signal. On the next `/fix-issues` fire,
`filter-unresearched-candidates.sh` reads the list and suppresses
skip-code emission for listed issues, allowing Phase 2 to re-triage them
independently. After the sprint processes the issue, the filter script
removes it from the list (one-shot: flag once, re-evaluate once, clear).

```bash
if [ "$RECONSIDER_MODE" = "1" ]; then
  ISSUE_NUM="$RECONSIDER_ISSUE_NUM"

  MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
  STATE_FILE="$MAIN_ROOT/.zskills/monitor-state.json"
  if [ ! -f "$STATE_FILE" ]; then
    echo "ERROR: $STATE_FILE does not exist. Run /fix-issues sync first." >&2
    exit 1
  fi

  python3 - "$STATE_FILE" "$ISSUE_NUM" <<'PY'
import sys, os, json, tempfile

path, num_s = sys.argv[1], sys.argv[2]
num = int(num_s)

with open(path, 'r') as f:
    data = json.load(f)

issues = data.setdefault("issues", {})
reconsider = issues.get("reconsider", [])

if num in reconsider:
    print(f"/fix-issues: #{num_s} already in reconsider list (no-op).", file=sys.stderr)
    sys.exit(0)

reconsider.append(num)
issues["reconsider"] = reconsider

tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.monitor-state.', suffix='.tmp')
json.dump(data, tmp, indent=2)
tmp.write('\n')
tmp.close()
os.replace(tmp.name, path)
print(f"/fix-issues: #{num_s} flagged for reconsideration on next sprint.")
PY

  exit 0
fi
```
