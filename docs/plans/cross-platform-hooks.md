# Cross-Platform Support (#1)

## Problem

zskills hooks and scripts assume bash, jq, node, and grep are available.
Claude Code guarantees bash (via Git Bash on Windows) and git, but NOT
jq or node. The reported error was `node: command not found` from a
session logging hook (since removed), and the owner noted jq was also
flagged during audit.

## Approach

Eliminate all dependencies beyond bash and git:

1. **Hooks:** Remove jq dependency using bash built-ins (`[[ =~ ]]` for
   regex, `printf` for JSON output, pattern matching on raw input for
   JSON extraction). Bash is guaranteed everywhere Claude Code runs.
2. **Scripts:** Port `port.js` and `test-all.js` to bash (simple logic).
   Port `briefing.cjs` to Python (complex, 1693 lines — Python is more
   universal than Node). Keep `.js` originals for projects that have Node.
3. **Skills:** `/briefing` tries node first, falls back to python3, fails
   with a clear explanation if neither is available. Other skills reference
   `.sh` versions by default.
4. **Audit:** `/update-zskills` checks for node and python3 availability
   and reports which optional features are unavailable.

## Dependency map (current → target)

| Component | Current deps | Target deps |
|-----------|-------------|-------------|
| block-unsafe-generic.sh | bash, jq, grep | **bash only** |
| block-unsafe-project.sh | bash, jq, grep, sed | **bash, git** |
| port.js → port.sh | node | **bash** |
| test-all.js → test-all.sh | node, sh, git | **bash, git** |
| briefing.cjs → briefing.py | node | **python3** (node as preferred) |

## Phases

### Phase 1 — Eliminate jq from hooks
**Status:** done
**Files:** `hooks/block-unsafe-generic.sh`, `hooks/block-unsafe-project.sh.template`

Rewrite both hooks to use bash built-ins only:

1. **JSON input parsing:** Instead of `jq -r '.tool_name'`, check the raw
   input with pattern matching:
   ```bash
   if [[ "$INPUT" != *'"tool_name":"Bash"'* ]] && \
      [[ "$INPUT" != *'"tool_name": "Bash"'* ]]; then
     exit 0
   fi
   ```
   For `tool_input.command`, the regex patterns are specific enough
   (e.g., `git\s+reset\s+--hard`) to match against the raw JSON input
   without extraction — they won't false-positive on other fields.

2. **Regex matching:** Replace `grep -qE` with bash `[[ =~ ]]`:
   ```bash
   if [[ "$INPUT" =~ git[[:space:]]+reset[[:space:]]+--hard ]]; then
   ```

3. **JSON output:** Replace `jq -n --arg` with `printf`:
   ```bash
   printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$reason"
   ```
   All reason strings are static (no special JSON chars to escape).

4. **Project hook specifics:**
   - Replace `grep -qP` with `[[ =~ ]]` (patterns used are JS-compatible,
     not Perl-specific)
   - Replace `sed` escaping with bash parameter expansion
   - Replace `ls` with `[[ -f ]]`
   - `git` calls stay (git is guaranteed)
   - `jq -r '.transcript_path'` for transcript extraction: use pattern
     matching on raw input

**Verify:** Test each blocked pattern by piping sample JSON to the hook.
Test allow cases too. Compare behavior with the jq versions.

### Phase 2 — Port port.js and test-all.js to bash
**Status:** done
**Files:** `scripts/port.sh` (new), `scripts/test-all.sh` (new)

- `port.sh`: Uses `cksum` for deterministic hashing, same port range logic.
  Tested: deterministic output, DEV_PORT override works.
- `test-all.sh`: Same orchestration logic — runs unit tests, checks port
  for E2E, detects changed source files, checks build prerequisites.
  Tested: syntax clean, formatted output correct, exit codes correct.

Original `.js` files kept for backward compatibility.

### Phase 3 — Port briefing.cjs to Python
**Status:** done
**Files:** `scripts/briefing.py` (new)

Port the core briefing functionality (1693 lines, 30+ functions) to Python.
Python is more universally available than Node (ships with macOS, most Linux).

**Subcommands to port:**
- `summary` — formatted terminal output (most used)
- `report` — combined JSON blob
- `verify` — verification status
- `current` — current session status
- `worktrees-status` — worktree classification
- `commits` — categorized commits
- `checkboxes` — unchecked items from reports

**Testing strategy:** Both implementations must produce identical output for
the same inputs. Create test fixtures (sample git repos, report files) and
a test harness that runs both `node scripts/briefing.cjs <cmd>` and
`python3 scripts/briefing.py <cmd>`, comparing output. Differences are bugs.

**Edge cases to test:**
- Empty repos (no commits, no worktrees)
- Repos with many worktrees in various states
- Reports with mixed checkbox states
- Period parsing (1h, 6h, 24h, 2d, 7d)
- Timezone formatting (America/New_York)

### Phase 4 — Update skills and templates
**Status:** done
**Files:** `CLAUDE_TEMPLATE.md`, `skills/update-zskills/SKILL.md`,
`skills/briefing/SKILL.md`, `skills/manual-testing/SKILL.md`,
`skills/verify-changes/SKILL.md`, `skills/fix-report/SKILL.md`

1. **CLAUDE_TEMPLATE.md:** Change `{{PORT_SCRIPT}}` default from
   `scripts/port.js` to `scripts/port.sh`. Change test command references
   from `node scripts/test-all.js` to `bash scripts/test-all.sh`.

2. **`/update-zskills` audit:** Add `node` and `python3` to the tools check.
   Report which optional features are unavailable:
   ```
   Tools: 3/4 available (1 missing)
     Missing:
     - node: not found (scripts/briefing.cjs will use python3 fallback)
   ```

3. **`/briefing` skill:** Add runtime check — try `node scripts/briefing.cjs`,
   fall back to `python3 scripts/briefing.py`, fail with clear message if
   neither available.

4. **Port-dependent skills** (`/manual-testing`, `/verify-changes`,
   `/fix-report`): Change `node scripts/port.js` references to
   `bash scripts/port.sh`.

5. **Test-dependent skills/template:** Change test command references to
   use `.sh` version.

### Phase 5 — Tests
**Status:** done
**Files:** `tests/` (new directory)

1. **Hook tests:** Sample JSON inputs for each blocked pattern. Verify deny
   output. Verify allow for safe commands. Test edge cases (patterns in
   non-command fields).

2. **port.sh tests:** Determinism, DEV_PORT override, main repo detection,
   port range bounds.

3. **test-all.sh tests:** Mocked test commands (echo true/false), port
   detection, source file detection, exit codes, skip behavior.

4. **briefing.py parity tests:** Run both Node and Python versions against
   test fixtures, diff output. Any difference is a bug.

## Risks & Open Questions

1. **Regex in raw JSON input:** Matching patterns against the full JSON
   input (instead of extracting the command field) could theoretically
   false-positive if another field contains a matching pattern. In practice,
   the patterns are specific enough (e.g., `git\s+reset\s+--hard`) that
   this won't happen — but the hook tests should verify this.

2. **briefing.py maintenance burden:** Two implementations of complex logic.
   Mitigated by parity tests. If maintenance becomes painful, consider
   dropping the Node version and going Python-only.

3. **`[[ =~ ]]` portability:** Bash regex behaves slightly differently
   across bash versions (3.x vs 4.x+ on quoting). Test on the oldest
   bash version Claude Code supports. Git Bash on Windows ships bash 5.x.

4. **`/dev/tcp` in test-all.sh:** Bash built-in TCP check. Works in bash
   but not dash/sh. Since we explicitly use `#!/bin/bash`, this is fine.
