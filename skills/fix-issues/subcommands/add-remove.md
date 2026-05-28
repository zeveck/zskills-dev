## Add (if `add` is present)

Add an issue to a dashboard queue column. This is an early-exit subcommand
that mutates `.zskills/monitor-state.json` and exits — it does NOT proceed
to Phase 0/1/2.

**Syntax:** `add <N> [column] [pos]`
- `<N>` — positive integer (GitHub issue number). REQUIRED.
- `[column]` — one of `triage`, `ready`, `backlog`. Default: `ready`.
- `[pos]` — 1-based insertion position. Default: append.

**Validation:**
- `<N>` must match `^[0-9]+$` — exit 2 on non-digit.
- `[column]` must be in `{triage, ready, backlog}` — exit 2 on invalid.
  `completed` is read-only (per `_validate_queue_body`).
- Idempotent: if `<N>` already in the target column, exit 0 with stderr note.

**Parse `[column]` and `[pos]` from remaining tokens** after the issue
number. The regex captured the issue number in `ADD_ISSUE_NUM`; now scan
the rest of `$ARGUMENTS` for optional column and position:

```bash
if [ "$ADD_MODE" = "1" ]; then
  ISSUE_NUM="$ADD_ISSUE_NUM"

  # Parse optional [column] — default 'ready'
  COLUMN="ready"
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[tT][rR][iI][aA][gG][eE]($|[[:space:]]) ]]; then
    COLUMN="triage"
  elif [[ "$ARGUMENTS" =~ (^|[[:space:]])[bB][aA][cC][kK][lL][oO][gG]($|[[:space:]]) ]]; then
    COLUMN="backlog"
  fi

  # Parse optional [pos] — digits following the column or issue number.
  # Look for a bare integer that isn't the issue number itself. The pos
  # token is the SECOND integer in the arguments (the first is the issue
  # number captured by ADD_ISSUE_NUM).
  POS=""
  REMAINING="$ARGUMENTS"
  # Strip the 'add' keyword and issue number to isolate trailing tokens
  REMAINING=$(printf '%s' "$REMAINING" \
    | sed -E 's/(^|[[:space:]])[aA][dD][dD][[:space:]]+[0-9]+/ /' \
    | sed -E 's/(^|[[:space:]])(triage|ready|backlog)($|[[:space:]])/ /i' \
    | sed -E 's/^[[:space:]]+//' | sed -E 's/[[:space:]]+$//')
  if [[ "$REMAINING" =~ ^[0-9]+$ ]]; then
    POS="$REMAINING"
  fi

  # Resolve MAIN_ROOT and MONITOR_STATE
  MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
  MONITOR_STATE="$MAIN_ROOT/.zskills/monitor-state.json"
  if [ ! -f "$MONITOR_STATE" ]; then
    echo "ERROR: $MONITOR_STATE does not exist. Start the dashboard first." >&2
    exit 1
  fi

  python3 - "$MONITOR_STATE" "$ISSUE_NUM" "$COLUMN" "${POS:-}" <<'PY'
import json, os, sys, tempfile, datetime
path, num_s, col = sys.argv[1], sys.argv[2], sys.argv[3]
pos_s = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else ""
num = int(num_s)
doc = json.load(open(path))
issues = doc.setdefault("issues", {})
arr = issues.setdefault(col, [])
if num in arr:
    print(f"/fix-issues: #{num} already in {col} (no-op).", file=sys.stderr)
    sys.exit(0)
if pos_s:
    try:
        pos = int(pos_s)
    except ValueError:
        print(f"/fix-issues: invalid pos '{pos_s}'.", file=sys.stderr)
        sys.exit(2)
    if pos < 1: pos = 1
    if pos > len(arr) + 1: pos = len(arr) + 1
    arr.insert(pos - 1, num)
else:
    arr.append(num)
issues[col] = arr
doc["updated_at"] = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.monitor-state.', suffix='.tmp')
json.dump(doc, tmp, indent=2); tmp.write('\n'); tmp.close()
os.replace(tmp.name, path)
print(f"/fix-issues: added #{num} to {col}.")
PY

  exit 0
fi
```

## Remove (if `remove` is present)

Remove an issue from a dashboard queue column. This is an early-exit
subcommand that mutates `.zskills/monitor-state.json` and exits — it
does NOT proceed to Phase 0/1/2.

**Syntax:** `remove <N> [column]`
- `<N>` — positive integer (GitHub issue number). REQUIRED.
- `[column]` — one of `triage`, `ready`, `backlog`. Default: `ready`.

**Validation:**
- `<N>` must match `^[0-9]+$` — exit 2 on non-digit.
- `[column]` must be in `{triage, ready, backlog}` — exit 2 on invalid.
- Idempotent: if `<N>` not in the target column, exit 0 with stderr note.

```bash
if [ "$REMOVE_MODE" = "1" ]; then
  ISSUE_NUM="$REMOVE_ISSUE_NUM"

  # Parse optional [column] — default 'ready'
  COLUMN="ready"
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[tT][rR][iI][aA][gG][eE]($|[[:space:]]) ]]; then
    COLUMN="triage"
  elif [[ "$ARGUMENTS" =~ (^|[[:space:]])[bB][aA][cC][kK][lL][oO][gG]($|[[:space:]]) ]]; then
    COLUMN="backlog"
  fi

  # Resolve MAIN_ROOT and MONITOR_STATE
  MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
  MONITOR_STATE="$MAIN_ROOT/.zskills/monitor-state.json"
  if [ ! -f "$MONITOR_STATE" ]; then
    echo "ERROR: $MONITOR_STATE does not exist. Start the dashboard first." >&2
    exit 1
  fi

  python3 - "$MONITOR_STATE" "$ISSUE_NUM" "$COLUMN" <<'PY'
import json, os, sys, tempfile, datetime
path, num_s, col = sys.argv[1], sys.argv[2], sys.argv[3]
num = int(num_s)
doc = json.load(open(path))
issues = doc.setdefault("issues", {})
arr = issues.get(col, [])
if num not in arr:
    print(f"/fix-issues: #{num} not in {col} (no-op).", file=sys.stderr)
    sys.exit(0)
arr.remove(num)
issues[col] = arr
doc["updated_at"] = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.monitor-state.', suffix='.tmp')
json.dump(doc, tmp, indent=2); tmp.write('\n'); tmp.close()
os.replace(tmp.name, path)
print(f"/fix-issues: removed #{num} from {col}.")
PY

  exit 0
fi
```
