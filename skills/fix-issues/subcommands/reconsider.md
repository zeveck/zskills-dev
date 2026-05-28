## Reconsider (if `reconsider` is present)

Flag a previously-skipped issue for re-evaluation on the next sprint. This
is an early-exit subcommand that annotates the issue's section in
`$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md` and exits — it does NOT proceed to
Phase 0/1/2.

**Syntax:** `reconsider <N>`
- `<N>` — positive integer (GitHub issue number). REQUIRED.

**Behavior:**
- Finds the `### #<N> ` section in `$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md`.
- Appends `**Reconsidered:** user flagged prior classification as incorrect — re-evaluate independently.` after the `**Action now:**` line.
- Idempotent: if the section already contains `**Reconsidered:**`, exit 0 with a note.
- If `### #<N> ` is not found in ISSUES_PLAN.md, exit 1 with an error.

The annotation does NOT delete the existing blurb (keeps original research
for context). On the next `/fix-issues` fire, `filter-unresearched-candidates.sh`
sees the `**Reconsidered:**` marker and suppresses skip-code emission for
that issue, allowing Phase 2 to re-triage it independently.

<!-- allow-hardcoded: (^|[^A-Za-z0-9_])ISSUES_PLAN\.md reason: filename basename suffixed onto $ZSKILLS_ISSUES_DIR (resolved via zskills-paths.sh); the basename token remains literal so the regex still flags the /ISSUES_PLAN.md tail -->
```bash
if [ "$RECONSIDER_MODE" = "1" ]; then
  ISSUE_NUM="$RECONSIDER_ISSUE_NUM"

  # Resolve paths
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  PLAN_FILE="$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
  if [ ! -f "$PLAN_FILE" ]; then
    echo "ERROR: $PLAN_FILE does not exist. Run /fix-issues sync first." >&2
    exit 1
  fi

  python3 - "$PLAN_FILE" "$ISSUE_NUM" <<'PY'
import sys, os, tempfile

path, num_s = sys.argv[1], sys.argv[2]
header = f"### #{num_s} "
reconsidered_marker = "**Reconsidered:**"
action_now_marker = "**Action now:**"
annotation = f"{reconsidered_marker} user flagged prior classification as incorrect — re-evaluate independently."

with open(path, 'r') as f:
    lines = f.readlines()

# Find the section for this issue
in_sec = False
sec_start = -1
action_line = -1
already_annotated = False

for i, line in enumerate(lines):
    if line.startswith(header):
        in_sec = True
        sec_start = i
        continue
    if in_sec and line.startswith("### "):
        break
    if in_sec:
        if reconsidered_marker in line:
            already_annotated = True
            break
        if action_now_marker in line:
            action_line = i

if sec_start == -1:
    print(f"ERROR: section '{header.strip()}' not found in {path}", file=sys.stderr)
    sys.exit(1)

if already_annotated:
    print(f"/fix-issues: #{num_s} already has Reconsidered annotation (no-op).", file=sys.stderr)
    sys.exit(0)

if action_line == -1:
    # No Action-now line — issue was never classified as skip; append after header
    insert_at = sec_start + 1
else:
    insert_at = action_line + 1

lines.insert(insert_at, f"{annotation}\n")

tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.ISSUES_PLAN.', suffix='.tmp')
tmp.writelines(lines)
tmp.close()
os.replace(tmp.name, path)
print(f"/fix-issues: #{num_s} flagged for reconsideration on next sprint.")
PY

  exit 0
fi
```
