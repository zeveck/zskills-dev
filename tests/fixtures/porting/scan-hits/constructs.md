# Claude-lane sample prose — scanner known-hit fixture

Every v1 construct class fires at least once in this tree
(tests/test-porting-scanner.sh asserts per-class count > 0).

Arm the schedule with CronCreate, inspect it with CronList, and clear it
with CronDelete; the fire time comes from compute-cron-fire.

Dispatch the phase with the Agent tool, pinning subagent_type: "implementer"
and isolation: "worktree" for the sandbox.

Never reach for run_in_background with Monitor, TaskOutput, or BashOutput
polling — foreground the call instead.

Dispatch /land-pr via the Skill tool with a result file.

Execute the procedure inline with $ARGUMENTS set to the trailing text.

Confirm the destructive step with AskUserQuestion before proceeding.

Resolve bundled scripts under ${CLAUDE_PLUGIN_ROOT}/skills on the plugin
lane, falling back to CLAUDE_PROJECT_DIR when the harness sets it.

Set disable-model-invocation: true and user-invocable: false in the skill
frontmatter, and keep allowed-tools tight.

Model ordinal: haiku=1 < sonnet=2 < opus=3. Never dispatch with a haiku
model.

```bash
# fence-context hits (the fence state machine scans these too)
claude -p "run it" --agents '{"model": "opus"}'
echo "$ARGUMENTS" > "${CLAUDE_PLUGIN_ROOT}/out.txt"
```
