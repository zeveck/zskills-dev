# Canonical Config-Prelude Reference

This is a reference doc for skill authors working in the zskills repo. It is
**not** installed downstream. It documents the canonical pattern for
sourcing the zskills config-resolution helper from skill bash fences,
mode files, and subagent-dispatch prompts.

The helper lives at:

```
.claude/skills/update-zskills/scripts/zskills-resolve-config.sh
```

It resolves the following six shell vars by reading
`.claude/zskills-config.json` from `$CLAUDE_PROJECT_DIR`:

```
$UNIT_TEST_CMD       — testing.unit_cmd
$FULL_TEST_CMD       — testing.full_cmd
$TIMEZONE            — timezone
$DEV_SERVER_CMD      — dev_server.cmd
$TEST_OUTPUT_FILE    — testing.output_file
$COMMIT_CO_AUTHOR    — commit.co_author
```

The helper is purely declarative bash. No `jq`, no opinionated defaults,
no aborts on malformed input — empty config or unparseable JSON yields
empty vars.

## 1. Sourcing pattern

Drop this **single line** at the top of any skill bash fence that needs
config values. It must be the first non-comment line:

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
# vars now set: $UNIT_TEST_CMD $FULL_TEST_CMD $TIMEZONE $DEV_SERVER_CMD $TEST_OUTPUT_FILE $COMMIT_CO_AUTHOR
```

`$CLAUDE_PROJECT_DIR` is set by the Claude Code harness to the running
session's project root and resolves correctly per worktree (each worktree
has its own checked-out `.claude/zskills-config.json` since the file is
git-tracked). The helper internally reads `$CLAUDE_PROJECT_DIR` and fails
loudly via `${CLAUDE_PROJECT_DIR:?...}` if it's unset, rather than
silently expanding to an empty path.

## 2. Fallback semantics

The helper produces empty values when the field is absent, the config is
empty, or the JSON is malformed. The helper itself never substitutes a
default. Consumers decide what empty means.

There are two consumer patterns:

### Critical-path consumers

Test-gates, deploy-gates, anything where running with the wrong command is
a correctness violation. Empty value = "stop and tell the user to
configure this":

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
if [ -z "$FULL_TEST_CMD" ]; then
  echo "ERROR: testing.full_cmd not configured. Run /update-zskills." >&2
  exit 1
fi
$FULL_TEST_CMD
```

### Informational consumers

Timestamp formatters, log decorations, anything where a sensible static
fallback is acceptable. Use the `${VAR:-default}` pattern:

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
TZ="${TIMEZONE:-UTC}" date -Iseconds
```

The fallback constant lives **inline at the consumer site**, not inside
the helper. This keeps the helper simple and makes consumer-specific
fallback policy auditable from the consumer's own file.

## 3. Mode files source the helper too

Mode files (e.g. `skills/run-plan/modes/pr.md`,
`skills/run-plan/modes/cherry-pick.md`) **also** source the helper at the
top of any fence that needs config. They do **not** inherit `$VAR`
bindings from a parent skill's preflight fence.

Why: agents may experience context compaction between the orchestrator
sourcing the helper and the mode fence executing. State in the
orchestrator turn is not guaranteed to survive into the mode-file turn —
and even within a single turn, separate Bash tool invocations are separate
shell processes. Always re-source.

See `skills/run-plan/modes/pr.md` for a worked example.

## 4. Subagent dispatch prompts use resolved literals

When an orchestrator dispatches a subagent and needs to pass a config
value into the subagent's prompt, the orchestrator sources the helper
**once**, in its own preflight fence, and substitutes the **resolved
literal value** into the prompt text — not a `$VAR` reference.

Reason: the subagent runs in its own session with its own bash processes;
`$VAR` from the orchestrator's shell is not visible. Even if the subagent
also sources the helper, the orchestrator must commit to the value at
dispatch time so both sides see the same string (the worktree's config
file may be edited between dispatch and execution).

Pattern (paraphrased from `skills/run-plan/SKILL.md`):

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
# Build the prompt with the literal value spliced in:
PROMPT="Run \`$FULL_TEST_CMD\` and report failures."
# Dispatch with $PROMPT as the agent input.
```

The agent receives the literal command string, not a variable name.

## 5. Shell-state scope

- **Within ONE bash fence (one Bash tool invocation):** the shell process
  persists for the duration of the fence. Sourcing once at the top makes
  `$VAR` available to every subsequent line.
- **Across fences:** each fence is a fresh bash process. State does not
  carry over. Re-source the helper at the top of each fence that needs
  config.

This is why the one-line preamble is required per-fence — it is cheap
(one file read + ~6 regex matches) and avoids the entire class of
"I sourced it earlier in another fence, why is `$TIMEZONE` empty here"
bugs.

## 6. Heredoc-form interaction

When you embed a heredoc inside a fence that has sourced the helper:

- **Unquoted heredoc** (`<<TAG`): variables expand inside the body.
  ```bash
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  cat <<NOTE
  Running tests with: $FULL_TEST_CMD
  NOTE
  ```
  The note will contain the resolved command string.

- **Quoted heredoc** (`<<'TAG'` or `<<"TAG"`): variables do **not**
  expand. The body is treated as a literal blob. To inject a config value
  into a quoted-heredoc body, capture it into a variable first and
  interpolate with `sed`/`awk` after, or rewrite to use an unquoted
  heredoc if expansion is desired:
  ```bash
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  CO_AUTHOR_LITERAL="$COMMIT_CO_AUTHOR"
  # Now $CO_AUTHOR_LITERAL is in scope for unquoted heredocs in this fence.
  ```

Migration plans should enumerate quoted heredocs in the migration set
(Phase 2.1 enumeration) before assuming the simple-substitution pattern
is sufficient.

## 7. Allowlist marker format

The Phase 4 deny-list test scans every skill `.md` file for hardcoded
literals (e.g. `npm run test:all`, `npm start`, `America/New_York`,
`.test-results.txt`, the canonical co-author trailer) that should be
sourced from the helper instead. Genuine exceptions — places where the
hardcoded literal is correct on purpose — are exempted via a marker on
the line **immediately above** a fence-opener:

```
<!-- allow-hardcoded: <literal> reason: <one-line explanation> -->
```

### Format rules

- **Case-sensitive lowercase** prefix: `<!-- allow-hardcoded:`.
- `<literal>` is the forbidden string **verbatim**, no escaping.
  Multi-token literals like `npm run test:all` and `npm start` are
  supported because the capture is delimited by ` reason:`, not by
  whitespace.
- The capture rule: "everything between `allow-hardcoded: ` (one space)
  and ` reason:` (one space, then `reason:`), trimmed."
- `<reason>` may contain any characters except the substring `-->` and
  the substring `reason:`. Reasons containing either MUST be rephrased.

### Marker scope

- Markers live in **markdown prose**, on the line **immediately above**
  a fence-opener (` ```bash `, ` ```sh `, or ` ```shell `).
- Such a marker exempts hits of **exactly `<literal>`** (verbatim string
  match, not regex) inside the immediately-following fence.
- For a fence with multiple distinct allowed literals, place **multiple
  markers on consecutive lines** above the fence-opener (one per
  literal). The deny-list test reads upward from the fence-opener until
  it hits a non-marker line.
- Markers **inside** fences (as bash comments) are **not** supported.
- Markers further than the contiguous-marker-block above the fence-opener
  are **not** supported.

### Example

```markdown
<!-- allow-hardcoded: npm run test:all reason: documenting the default
  consumer command for first-time users in onboarding prose -->
\`\`\`bash
echo "By default we use 'npm run test:all'; configure via testing.full_cmd."
\`\`\`
```

The Phase 4 deny-list test exempts the `npm run test:all` hit inside the
fence above; any other hit of the same literal in another fence without
its own marker still fails.
