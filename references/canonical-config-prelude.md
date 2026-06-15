# Canonical Config-Prelude Reference

This is a reference doc for skill authors working in the zskills repo. It is
**not** installed downstream. It documents the canonical pattern for
sourcing the zskills config-resolution helper from skill bash fences,
mode files, and subagent-dispatch prompts.

The helper lives at one of two locations depending on the install lane:

```
${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh          # plugin lane
$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh   # /update-zskills lane
```

Both install lanes are first-class and PERMANENT (decision D23) — neither is
deprecated. New code should source the helper via the lane-portable
**bare-token `-f` fence** documented in §1 so it works under either lane.

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

### Preferred: lane-portable bare-token `-f` fence

Drop this block at the top of any skill bash fence that needs config values.
It is the PREFERRED form for all new code because it selects the install lane
**correctly on a mirror-less plugin consumer** (the normal plugin install),
which the older `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]`-guarded form did NOT:

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# vars now set: $UNIT_TEST_CMD $FULL_TEST_CMD $TIMEZONE $DEV_SERVER_CMD $TEST_OUTPUT_FILE $COMMIT_CO_AUTHOR
#               + $ZSKILLS_SKILLS_ROOT (sourced transitively via zskills-paths.sh)
```

**Why the bare token, NOT a `"${X:-}"` guard.** The Claude Code harness
substitutes the **bare** `${CLAUDE_PLUGIN_ROOT}` token in plugin-skill
**markdown** with the plugin's absolute root path; it does **NOT** substitute
the `${CLAUDE_PLUGIN_ROOT:-}` form, and the variable is **absent from the env**
of any script a skill launches or sources. The old "preferred" form opened with
`[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] &&` — that first conjunct is the never-
substituted form, so it is **always empty/false on the plugin lane**, which
short-circuited away the (working, bare-token) `-f` test and dropped every
mirror-less plugin consumer onto the absent legacy `.claude/skills` path. The
new fence uses ONLY the bare-token `-f` test: it substitutes to a real path on
the plugin lane (true → plugin branch) and to a missing path on the legacy lane
(false → else branch). The `export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"`
line (bare RHS) propagates the substituted value to any child the plugin branch
launches.

**`set -u`-unsafe by necessity.** Because the bare `${CLAUDE_PLUGIN_ROOT}` token
is genuinely unbound on the legacy lane, this fence MUST NOT run under `set -u`
(`set -euo pipefail`) — substitution and `:-`-safety are mutually exclusive for
this token. Skill `.md` fences do not run under `set -u`, so this is safe; do
NOT add `set -u`/`set -euo` above a resolution fence.

The same bare-token `-f` test applies to the sibling helper
`zskills-stub-lib.sh`. Note that `zskills-resolve-config.sh` itself sources
`zskills-paths.sh` — but it does so via env-independent **`BASH_SOURCE`-relative
self-location** (a launched/sourced script's env has no `${CLAUDE_PLUGIN_ROOT}`),
and `zskills-paths.sh` derives `$ZSKILLS_SKILLS_ROOT` the same way — so sourcing
the config helper transitively exports `$ZSKILLS_SKILLS_ROOT`, the lane-portable
absolute path to the installed skills tree (`${CLAUDE_PLUGIN_ROOT}/skills` under
the plugin lane, `$CLAUDE_PROJECT_DIR/.claude/skills` under the `/update-zskills`
lane).

### Family 2: bundled-script invocations use `$ZSKILLS_SKILLS_ROOT`

`bash`/`python3` invocations of other bundled scripts (`port.sh`,
`apply-preset.sh`, etc.) — anything you would call rather than source — run
through the resolved skills root. After the fence has sourced
`zskills-resolve-config.sh` (which exports `$ZSKILLS_SKILLS_ROOT`), invoke a
bundled script via:

```bash
bash "$ZSKILLS_SKILLS_ROOT/<owner>/scripts/<x>"
```

For example, `bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/port.sh"`.
This resolves correctly under both lanes because `$ZSKILLS_SKILLS_ROOT` already
encodes the lane-correct prefix. The `python3`, `VAR=$(…)`, and
command-substitution variants all use the same `$ZSKILLS_SKILLS_ROOT/<owner>/scripts/<x>`
path form.

### Legacy: single-line `/update-zskills`-lane form (NOT deprecated)

The original single-line source form remains **valid forever** on the
`/update-zskills` lane (decision D23 / F-DA2-4). It is NOT deprecated and
carries NO migration deadline — under the permanent dual-path commitment the
legacy path always exists on that lane, so a deadline-warn would be a
no-op-with-noise. `tests/test-skill-conformance.sh`'s per-fence
sourcing-discipline check accepts EITHER form permanently. New code should
still prefer the dual-path form above for lane portability, but pre-existing
single-line sources need no mechanical migration:

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

### Inline-prose `resolve via` references must use the lane-portable form (#832/#833)

The "permanently valid" status above applies **only inside `` ```fenced``
bash blocks** — where the single-line form is the legacy `/update-zskills`-lane
source, and where it ALSO appears as the `else` fallback branch of the
dual-lane prelude in §1. It does **not** extend to **inline prose**.

An inline-prose reference is the single-backtick code-span form that shows up
in a parenthetical, e.g.

> Run `$FULL_TEST_CMD` (resolve via `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"` if you don't already have it).

That wording instructs the agent to source a **single-lane** path. A
mirror-less plugin install (the primary plugin consumer — no
`.claude/skills/` mirror) following it runs a path that does not exist and
fails. Inline-prose `resolve via` references MUST therefore use the
lane-portable form, pointing at the dual-lane prelude in §1 rather than
pasting the single-line literal:

> Run `$FULL_TEST_CMD` (resolve via the dual-lane prelude in references/canonical-config-prelude.md §1 if you don't already have it in your environment).

This is the distinction the conformance gate `=== Inline-prose resolve-via
uses lane-portable wording (#832/#833) ===` in `tests/test-skill-conformance.sh`
enforces: it is fence-aware and flags the single-lane literal **only** when it
appears in an inline code-span on a non-fenced line, leaving the fence form
(both the legacy source and the dual-prelude fallback) untouched per
decision D23 / finding F-DA2-4.

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

## 8. zsh fence-portability marker (`allow-zsh-unwrapped`)

Skill-file bash fences execute under the consumer's snapshot shell, which is
**zsh** on stock macOS/dev setups, not bash. The zsh fence-portability
tripwire in `tests/test-skill-conformance.sh` (`=== zsh fence-portability
tripwire (#1155) ===`) flags executed fences containing zsh-divergent
constructs that are not remediated. A fence the scanner flags must be
**wrapped** (Track W), **guarded** (Track G), **rewritten** (Track R), or —
for the rare fence that is genuinely never executed (display-only
illustration, prohibition-by-name) — carry an inspectable marker on the line
**immediately above** the fence-opener:

```
<!-- allow-zsh-unwrapped: <construct> reason: <why this fence is exempt> -->
```

### Format rules

- **Case-sensitive lowercase** prefix: `<!-- allow-zsh-unwrapped:`.
- `<construct>` names the flagged construct token **verbatim as the scanner
  reports it** — e.g. `BASH_REMATCH`, `mapfile`, `read-a`, `for-in-scalar`,
  `quoted-subscript`. The capture is delimited by ` reason:`, so multi-token
  construct names work.
- `<reason>` may contain any characters except the substrings `-->` and
  `reason:`.

### Marker scope

- Markers live in **markdown prose**, on the line **immediately above** a
  fence-opener (` ```bash `, ` ```sh `, ` ```shell `, or a bare ` ``` `).
- A marker exempts the named construct inside the immediately-following
  fence only.
- Markers **stack**: place multiple consecutive marker lines above one
  fence-opener to exempt several distinct constructs. The scanner reads
  upward from the opener until it hits a non-blank, non-marker line, which
  resets the block.
- Markers **inside** fences (as bash comments) are **not** supported (HTML
  comments are not bash-valid inside a fence).

### Worked examples

Display-only illustration fence (never executed — a docs example of an
idiom):

```markdown
<!-- allow-zsh-unwrapped: BASH_REMATCH reason: display-only idiom illustration, never executed -->
\`\`\`bash
[[ "$s" =~ ^([0-9]+) ]] && echo "${BASH_REMATCH[1]}"
\`\`\`
```

Prohibition-by-name fence (the fence documents an antipattern verbatim):

```markdown
<!-- allow-zsh-unwrapped: mapfile reason: prohibition-by-name — the fence shows the construct authors must NOT use -->
\`\`\`bash
# WRONG under zsh — mapfile is a bash builtin absent in zsh:
mapfile -t ARR < <(cmd)
\`\`\`
```

### Writing portable fences (authoring note)

When you write a new executed bash fence in a skill file, make it portable
so the first reader on macOS does not learn the policy from red CI:

- **Default remedy = the v2 guard** as the first executable line (handles
  `[[ =~ ]]`/`BASH_REMATCH`, 0-based indexed arrays, and `for tok in
  $SCALAR` word-split):
  `if [ -n "${ZSH_VERSION:-}" ]; then setopt KSH_ARRAYS BASH_REMATCH SH_WORD_SPLIT 2>/dev/null || true; fi`
- **setopt-UNFIXABLE constructs** (`mapfile`/`readarray`, `read -a`,
  `${!var}`, `${var,,}`/`${var^^}`, `compgen`) have no guard — use the
  Track-R replacement idioms (see `docs/plans/ZSH_FENCE_WRAP_PLAN.md` §Track R
  and the matching sections of `tests/test-zsh-fence-semantics.sh`).
- **Associative-array subscripts** must be **consistent-unquoted**
  (`LP[$KEY]` / `${LP[STATUS]}`, never `LP["$KEY"]`) — zsh addresses quoted
  and unquoted keys as different keys; see
  `skills/land-pr/references/caller-loop-pattern.md`.
- **Display-only / prohibition fences** get the `allow-zsh-unwrapped` marker
  above.
- **Wrap (`bash <<'ZSKILLS_BASH_FENCE'` … `ZSKILLS_BASH_FENCE`) only a
  PROVEN self-contained fence** — one that neither reads nor writes any
  cross-fence shell variable or function; the child inherits only exported
  env. Most fences are not self-contained — default to the guard.
- **Named residuals the guard does NOT fix** — glob-in-variable expansion
  (`v="*.md"; ls $v`; no `GLOB_SUBST`) and argument-position word-split
  (`cmd $FLAGS`): do not rely on them.
