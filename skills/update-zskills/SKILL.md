---
name: update-zskills
description: Install or update Z Skills supporting infrastructure (CLAUDE.md rules, hooks, scripts)
---

# Update Z Skills Infrastructure

Install or update the supporting infrastructure that Z Skills depend
on: CLAUDE.md agent rules, safety hooks, helper scripts, and skill
dependencies.

**Invocation:**

```
/update-zskills [install] [--with-addons | --with-block-diagram-addons]
```

Default mode (no argument): **smart detection** — if nothing is installed
yet, do a full install; if already installed, pull latest, update changed
skills, and fill new gaps. Always begins with an audit and reports what
was found and what was done about it.

**Explicit mode:**
- `install` — force a full first-time setup (same as what the default
  mode does when nothing is installed, but skips the detection step)

**Add-on flags:**
- `--with-addons` — install/update core skills + ALL available add-on packs
- `--with-block-diagram-addons` — install/update core skills + block-diagram
  add-on (3 skills: `/add-block`, `/add-example`, `/model-design`)

Without an add-on flag, only the 17 core skills are installed/updated.
If core is already installed, adding an add-on flag just copies the
add-on skills (the audit detects core is satisfied and skips it).

---

## Step 0 — Locate Portable Assets

**This step runs before any mode.** The portable assets (hooks, scripts,
CLAUDE_TEMPLATE.md, skills) can come from two sources: the `zskills-portable/`
vendored directory (inside projects like yours), or the Z Skills repo
root (which has the same structure). To find them:

1. Check if `zskills-portable/` exists in the current working directory. If
   yes, use it as `$PORTABLE`.
2. Check if `zskills/` exists in the current directory and contains
   `CLAUDE_TEMPLATE.md`. If yes, it's a repo clone — use `zskills/` as
   both `$PORTABLE` and `$ZSKILLS_PATH`.
3. Check if `/tmp/zskills` exists and contains `CLAUDE_TEMPLATE.md`. If
   yes, use it.
4. **Auto-clone fallback:** Clone the repo:
   ```bash
   git clone https://github.com/zeveck/zskills.git /tmp/zskills
   ```
   If `/tmp/zskills` already exists, pull instead:
   ```bash
   git -C /tmp/zskills pull
   ```
   If the clone/pull fails (network, permissions), report the error clearly
   and stop — do not silently continue without portable assets.
   Tell the user:
   > Using Z Skills repo at /tmp/zskills for portable assets.

**Portable asset detection:** A valid portable source contains
`CLAUDE_TEMPLATE.md`, `hooks/`, `scripts/`, and `skills/`. The Z Skills
repo root has these at the top level (no `zskills-portable/` subdirectory).

**If the audit finds no gaps** (all hooks, scripts, and CLAUDE.md rules
already present — e.g., because the LLM already copied everything), the
portable assets are not needed and Step 0 can return early.

Store the resolved path as `$PORTABLE` for use in install/update modes.
If the source is a git repo, also store it as `$ZSKILLS_PATH` for use
in update mode.

---

## Step 0.5 — Read Config

Check if `.claude/zskills-config.json` exists in the target project root (`$PROJECT_ROOT`).

**If it exists:**
1. Read the file content.
2. Extract values using bash regex (no jq dependency):
   ```bash
   CONFIG_CONTENT=$(cat "$PROJECT_ROOT/.claude/zskills-config.json")
   # Extract a string value (note: ([^\"]*) allows empty strings):
   if [[ "$CONFIG_CONTENT" =~ \"project_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     PROJECT_NAME="${BASH_REMATCH[1]}"
   fi
   if [[ "$CONFIG_CONTENT" =~ \"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     UNIT_CMD="${BASH_REMATCH[1]}"
   fi
   if [[ "$CONFIG_CONTENT" =~ \"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     FULL_CMD="${BASH_REMATCH[1]}"
   fi
   if [[ "$CONFIG_CONTENT" =~ \"output_file\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     OUTPUT_FILE="${BASH_REMATCH[1]}"
   fi
   if [[ "$CONFIG_CONTENT" =~ \"cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     DEV_SERVER_CMD="${BASH_REMATCH[1]}"
   fi
   if [[ "$CONFIG_CONTENT" =~ \"port_script\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     PORT_SCRIPT="${BASH_REMATCH[1]}"
   fi
   if [[ "$CONFIG_CONTENT" =~ \"main_repo_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     MAIN_REPO_PATH="${BASH_REMATCH[1]}"
   fi
   if [[ "$CONFIG_CONTENT" =~ \"file_patterns\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     UI_FILE_PATTERNS="${BASH_REMATCH[1]}"
   fi
   if [[ "$CONFIG_CONTENT" =~ \"auth_bypass\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     AUTH_BYPASS="${BASH_REMATCH[1]}"
   fi
   if [[ "$CONFIG_CONTENT" =~ \"timezone\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     TIMEZONE="${BASH_REMATCH[1]}"
   fi
   # Extract a boolean value:
   if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
     MAIN_PROTECTED="${BASH_REMATCH[1]}"
   fi
   # Extract landing mode:
   if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     LANDING_MODE="${BASH_REMATCH[1]}"
   fi
   # Extract branch prefix:
   if [[ "$CONFIG_CONTENT" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     BRANCH_PREFIX="${BASH_REMATCH[1]}"
   fi
   # Extract CI config:
   if [[ "$CONFIG_CONTENT" =~ \"auto_fix\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
     CI_AUTO_FIX="${BASH_REMATCH[1]}"
   fi
   if [[ "$CONFIG_CONTENT" =~ \"max_fix_attempts\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
     CI_MAX_ATTEMPTS="${BASH_REMATCH[1]}"
   fi
   ```
3. For each template placeholder, use the config value if non-empty.
4. Copy `config/zskills-config.schema.json` from `$PORTABLE` to
   `.claude/zskills-config.schema.json` in the target project (so the
   `$schema` reference in the config resolves correctly).

**If it does not exist:**
1. Auto-detect values from the project (existing behavior).
2. Present the auto-detected values to the user and instruct them to create
   the config file:
   ```
   ! cat > .claude/zskills-config.json <<'EOF'
   {
     "$schema": "./zskills-config.schema.json",
     "project_name": "<detected>",
     "timezone": "America/New_York",
     "execution": {
       "landing": "cherry-pick",
       "main_protected": false,
       "branch_prefix": "feat/"
     },
     "testing": {
       "unit_cmd": "<detected>",
       "full_cmd": "<detected>",
       "output_file": ".test-results.txt",
       "file_patterns": ["<detected>"]
     },
     "dev_server": {
       "cmd": "<detected>",
       "port_script": "",
       "main_repo_path": "<detected>"
     },
     "ui": {
       "file_patterns": "",
       "auth_bypass": ""
     },
     "ci": {
       "auto_fix": true,
       "max_fix_attempts": 2
     }
   }
   EOF
   ```
   **Important:** `.claude/zskills-config.json` is protected by Claude Code's
   built-in permission system -- agent writes trigger a prompt. The agent presents
   the values and instructs the user to create the file using the `!` prefix
   (user action).

**Merge algorithm pseudocode:**
```
for each field F in schema:
  if config[F] is non-empty string (or true/false for booleans):
    use config[F]
  else if auto_detect[F] is non-empty:
    use auto_detect[F]
  else:
    mark as empty -> template section gets commented out
```

**Template placeholder mapping:**

| Placeholder | Config path | Example |
|-------------|-------------|---------|
| `{{UNIT_TEST_CMD}}` | `testing.unit_cmd` | `npm run test` |
| `{{FULL_TEST_CMD}}` | `testing.full_cmd` | `npm run test:all` |
| `{{UI_FILE_PATTERNS}}` | `ui.file_patterns` | `src/(components\|ui)/.*\\.tsx?$` |
| `{{DEV_SERVER_CMD}}` | `dev_server.cmd` | `npm start` |
| `{{PORT_SCRIPT}}` | `dev_server.port_script` | `scripts/port.sh` |
| `{{MAIN_REPO_PATH}}` | `dev_server.main_repo_path` | `/workspaces/my-app` |
| `{{AUTH_BYPASS}}` | `ui.auth_bypass` | `localStorage.setItem(...)` |

**Empty value handling:** When a config field is empty string `""`, the
corresponding template section is commented out with a TODO marker:

```bash
# Example: if UI_FILE_PATTERNS is empty, comment out the UI verification section
# in block-unsafe-project.sh:
#
# Before:
#   UI_FILE_PATTERNS="src/components/.*\.tsx?$"
#
# After (empty):
#   # TODO: Configure UI file patterns in .claude/zskills-config.json
#   # UI_FILE_PATTERNS=""
```

---

## Audit — Gap Analysis (runs as part of every invocation)

The audit scans the project for all Z Skills dependencies and reports what
is present and what is missing. **The audit itself never modifies any files.**
Its output is always displayed so the user can see exactly what was found
before any changes are made.

### Step 1 — Scan installed skills and check dependency graph

List all `.claude/skills/*/SKILL.md` files. For each skill:

- Read its YAML frontmatter. If it has a `requires:` field (list of skill
  names), check that each required skill is also installed. Collect all
  missing dependencies.
- Extract infrastructure dependencies by searching the skill file body for:
  - References to CLAUDE.md rules (e.g., "never weaken tests", "capture
    output") — map each to a specific rule from the 13 generic rules below.
  - Test command references (`npm test`, `npm run test:all`,
    `{{FULL_TEST_CMD}}`) — check if test commands are configured.
  - Tool references (`playwright-cli`, `gh`) — check if the tool is
    available via `which`.
  - Optional tool references (`node`, `python3`) — check via `which`.
    These are not required but enable features:
    - `node`: enables `scripts/briefing.cjs` (preferred for /briefing)
    - `python3`: enables `scripts/briefing.py` (fallback for /briefing)
  - Hook references (`block-unsafe`) — check if the hook file
    exists in `.claude/hooks/`.
  - Script references (`scripts/port.sh`, `scripts/test-all.sh`) — check if
    the script file exists.

### Step 2 — Check CLAUDE.md for 13 generic rules

Read the project's `CLAUDE.md` (if it exists). For each of the 13 generic
rules, search for a distinctive key phrase that identifies the rule
(**case-insensitive**). Mark the rule as present if the key phrase is
found, missing otherwise.

| # | Rule Name | Key Phrase(s) to Search |
|---|-----------|------------------------|
| 1 | Never weaken tests | `"loosen tolerances"` or `"widen thresholds"` |
| 2 | Capture test output | `"capture"` AND `"output"` AND `"never pipe"` |
| 3 | Max 2 fix attempts | `"two attempts.*maximum"` or `"NEVER thrash"` |
| 4 | Pre-existing failures | `"pre-existing"` AND `"it.skip"` |
| 5 | Never discard others' changes | `"discard"` AND `"changes"` AND `"didn't make"` |
| 6 | Protect untracked files | `"protect untracked"` or `"git stash -u"` |
| 7 | Feature-complete commits | `"feature-complete"` AND `"trace"` AND `"imports"` |
| 8 | Landed marker check | `".landed"` AND `"status: full"` |
| 9 | Worktree verify before remove | `"worktree"` AND `"batch-remove"` |
| 10 | Never defer hard parts | `"defer"` AND `"hard parts"` AND `"future phases"` |
| 11 | Correctness over speed | `"correctness over speed"` or `"correctness, not speed"` |
| 12 | Enumerate before guessing | `"enumerate before guessing"` |
| 13 | Never skip hooks | `"never.*--no-verify"` or `"skip.*pre-commit hooks"` |

### Step 2.5 — Documentation presence audit (execution modes)

Search the project's `CLAUDE.md` for these documentation-presence signals.
Mark each present/missing based on **case-insensitive substring match**:

| Check | Key phrase(s) to search in CLAUDE.md |
|-------|--------------------------------------|
| Execution Modes section | `## Execution Modes` (heading) |
| Landing mode keywords documented | `cherry-pick` AND `pr` AND `direct` |
| Direct mode description present | `Work directly on main` |

Report in the same pass/fail format as Step 2. Missing items are
**recommendations, not errors** — this is a documentation-only gap with
no enforcement consequence.

### Step 3 — Check hooks

Look in `.claude/hooks/` for these 2 files:

- `block-unsafe-generic.sh` (or `block-unsafe.sh` — either name counts)
- `block-unsafe-project.sh`

### Step 4 — Check scripts

Look in `scripts/` for these 4 files:

- `port.sh`
- `test-all.sh`
- `briefing.cjs` OR `briefing.py` (either counts — Node or Python version)
- `clear-tracking.sh`

### Step 5 — Check skills with additional requirements

If `/briefing` is installed, check for `briefing.cjs` or `briefing.py` in `scripts/`.
If neither is found, add a note: "The /briefing skill requires briefing.cjs
or briefing.py in scripts/ — see /briefing skill documentation."

### Step 6 — Produce the gap report

Output the report in this exact format:

```
Z Skills Audit Report
=====================

Skills installed: N
  [list of skill names]

Skill Dependencies: all satisfied | K missing
  Missing:
  - /run-plan requires /verify-changes — NOT INSTALLED
  ...

CLAUDE.md Rules: M/13 present (K missing)
  Missing:
  - [rule name]: [key phrase not found]
  ...

Execution Mode Docs: M/3 present (K missing/recommended)
  Missing (recommendation only):
  - [check name]: [key phrase not found]
  ...

Hooks: M/2 installed (K missing)
  Missing:
  - [filename]
  ...

Scripts: M/3 installed (K missing)
  Missing:
  - [filename]
  ...

Tools: M/N available (K missing)
  Missing:
  - [tool name]: not found in PATH
  ...

Skills with additional requirements:
  - /briefing: requires briefing.cjs or briefing.py in scripts/ (not found)
  ...

Overall: X/Y dependencies satisfied.
```

If everything is satisfied, end with:
```
Overall: Y/Y dependencies satisfied. Nothing to install.
```

If there are gaps and the skill is running in default or install mode,
proceed to fill them (see below). The audit report is always shown first
so the user sees what was found before any modifications.

---

## Default Mode — Smart Detection

1. **Run the audit** (Steps 1-6 above). Display the gap report.

2. **Detect installation state:**
   - If no `.claude/skills/` directory exists, or it contains zero skills
     -> treat as first-time install (proceed to "Fill All Gaps" below).
   - If skills are already installed -> treat as update (proceed to
     "Pull Latest and Update" below).

### Fill All Gaps (first-time install path)

This is also the path taken by the explicit `install` mode.

#### Step A — Locate portable assets

Run Step 0 (locate portable assets). If the path cannot be resolved, stop
with an error: "Cannot locate zskills-portable/ directory. Please provide
the path to the Z Skills source repo."

#### Step B — Fill CLAUDE.md gaps

**If CLAUDE.md does NOT exist:**

Copy `$PORTABLE/CLAUDE_TEMPLATE.md` to `CLAUDE.md`. Then **auto-detect
placeholder values** and fill them in — do not prompt or block:

1. **Scan project files** for detection signals:
   - `package.json` — `name`, `scripts.start`, `scripts.dev`, `scripts.test`,
     `scripts["test:all"]`, `scripts["test:ci"]`
   - `Cargo.toml` — `[package] name`
   - `pyproject.toml` / `setup.py` / `setup.cfg` — project name, test config
   - `Makefile` — `test`, `serve`, `dev` targets
   - `manage.py` — Django project (dev server: `python manage.py runserver`)
   - `.github/workflows/` / `.gitlab-ci.yml` — CI test commands
   - `pytest.ini` / `jest.config.*` / `.mocharc.*` — test framework detection
   - Git remote URL or directory name — fallback for project name

2. **Fill in values automatically.** Do not prompt. Do not block.
   - **Detected values** -> replace the placeholder directly
   - **Undetectable values** -> use sensible defaults:
     - `{{PROJECT_NAME}}` -> directory name (always available)
     - `{{DEV_SERVER_CMD}}` -> `npm start` if package.json exists,
       otherwise comment out the section
     - `{{UNIT_TEST_CMD}}` -> `npm test` if package.json exists,
       otherwise comment out
     - `{{FULL_TEST_CMD}}` -> same as unit test command, or comment out
   - **Truly unknown values** -> comment out with a TODO marker:
     `<!-- TODO: fill in when known -->`

3. **Report what was filled and what needs review:**
   ```
   CLAUDE.md created. Values filled:
     Project name: my-app (from package.json)
     Dev server: npm start (detected)
     Test command: npm test (detected)
     Full test: commented out (no test:all script found — update when ready)

   Review CLAUDE.md and adjust any values that need changing.
   ```

The CLAUDE.md should be functional immediately — the 13 agent rules
work regardless of project-specific values. Unfilled placeholders should
never leave broken `{{PLACEHOLDER}}` strings in the file.

**If CLAUDE.md EXISTS but is missing rules:**

Show the user which rules are missing, show the exact text that will be
appended, and ASK before modifying. Append to a `## Agent Rules` section at
the end of the existing CLAUDE.md. If `## Agent Rules` already exists in
CLAUDE.md, append the missing rules to the existing section — do NOT create
a duplicate section header.

**NEVER overwrite or modify existing CLAUDE.md content.**

#### Step C — Fill hook gaps

Copy missing hooks from `$PORTABLE/hooks/` to `.claude/hooks/`.

- For `block-unsafe-project.sh.template`: copy to
  `.claude/hooks/block-unsafe-project.sh`, then fill in the
  `# CONFIGURE:` values from project detection (test commands, UI file
  patterns). Use placeholders/fallbacks for anything undetectable.

**Explain what each hook does** so the user understands what's being added:

> Installing 2 safety hooks:
> - **block-unsafe-generic.sh** — blocks destructive commands (git reset
>   --hard, rm -rf, kill -9, git checkout --, etc.) and discipline
>   violations (git add ., --no-verify)
> - **block-unsafe-project.sh** — project-specific guards: prevents piping
>   test output (must capture to file), verifies tests ran before commit,
>   and optionally checks for UI verification before committing UI changes

**Ask about git push blocking:**

> block-unsafe-generic.sh has an optional git push block. When enabled,
> agents cannot push to remote — you push when ready (using `! git push`).
> This prevents accidental pushes of incomplete work.
>
> Enable git push blocking? (recommended for shared repos)

If the user says yes (or in `auto` mode — default to enabled), uncomment
the push blocking section in `.claude/hooks/block-unsafe-generic.sh`:
```bash
if [[ "$INPUT" =~ git[[:space:]]+push ]]; then
  block_with_reason "BLOCKED: Agents must not push. The user decides when to push — they can run: ! git push"
fi
```
If the user says no, leave it commented out.

**Note on tracking enforcement:** The tracking enforcement section in
`block-unsafe-project.sh` (protecting `.zskills/tracking/`, blocking
`clear-tracking.sh` execution, and enforcing delegation/step verification)
has no placeholders — it works out of the box. No configuration needed.

**Add tracking directory to `.gitignore`:** During installation, add
`.zskills/tracking/` to the project's `.gitignore` if not already present.
Tracking files are ephemeral session state and should never be committed.

Then register the hooks in `.claude/settings.json`. The format is:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-generic.sh\"",
            "timeout": 5
          },
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-project.sh\"",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-agents.sh\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Note: both `Bash` and `Agent` matchers are used for PreToolUse hooks. The `Bash`
matcher hooks enforce command safety and tracking. The `Agent` matcher hook
enforces `agents.min_model` — blocking subagent dispatches that specify a model
below the configured minimum (haiku=1 < sonnet=2 < opus=3).

Report: "Installed N hooks: [list]"

#### Step C.5 — Statusline (optional)

If `.claude/settings.json` already has a `"statusLine"` key, skip.

Otherwise, offer to install: "Add zskills statusline? Shows context window,
5-hour, and 7-day rate limits as colored bars."

If yes: copy `$PORTABLE/scripts/statusline.sh` to `~/.claude/statusline-command.sh`
and add `"statusLine": {"type":"command","command":"bash ~/.claude/statusline-command.sh"}`
to `.claude/settings.json`. Users can customize further with `/statusline`.

#### Step D — Fill script gaps

Copy missing scripts from `$PORTABLE/scripts/` to `scripts/`.

- For scripts with placeholders: prompt user for values and replace.
- Copy `clear-tracking.sh` from `$PORTABLE/scripts/` to `scripts/` if missing.
  This script lets the user manually clear stale tracking state. Agents are
  blocked from running it by the project hook.

Report: "Installed N scripts: [list]"

#### Step E — Install add-ons (if `--with-addons` or `--with-block-diagram-addons`)

Skip this step if no add-on flag was provided.

1. **Determine which add-on packs to install:**
   - `--with-addons` -> all packs in `$PORTABLE/../block-diagram/` (and any
     future add-on directories)
   - `--with-block-diagram-addons` -> only `$PORTABLE/../block-diagram/`

2. **For each add-on skill** (e.g., `add-block`, `add-example`, `model-design`):
   - If `.claude/skills/<name>/SKILL.md` already exists, skip (never overwrite)
   - Otherwise, copy from the add-on source directory to `.claude/skills/<name>/`

3. **Report:** "Installed N add-on skills: [list]" or "Add-on skills already
   installed — skipped."

#### Step F — Final report

```
Installation complete.

Installed:
- CLAUDE.md: [created | N rules appended | already complete]
- Hooks: N hooks installed
- Scripts: N scripts installed
- Add-ons: N add-on skills installed (omit this line if no add-on flag was used)

Skills with additional requirements:
- /briefing: requires briefing.cjs or briefing.py in scripts/ (see /briefing skill docs)

Run /update-zskills to check for updates later.
```

### Pull Latest and Update (already-installed path)

1. **Pull latest from upstream.** Find the `zskills/` clone (Step 0) and
   update it:
   ```bash
   git -C "$ZSKILLS_PATH" pull
   ```
   If the pull fails (no remote, not a git repo), warn and continue with
   the local copy as-is.

2. **Diff against installed skills.** For each skill in the source
   `$ZSKILLS_PATH/skills/`, compare against the installed version in
   `.claude/skills/`. Report which skills have upstream changes.

3. **Update changed skills.** For each skill with upstream changes, copy
   the new version to `.claude/skills/`. Show the user what changed (file
   names and a brief diff summary) before overwriting.

4. **Update installed add-ons.** Check if any block-diagram add-on skills
   are installed (e.g., `.claude/skills/add-block/SKILL.md` exists). If so,
   diff against `$ZSKILLS_PATH/block-diagram/` and update the same way.

5. **Fill new gaps.** For any NEW items (skills, hooks, scripts, CLAUDE.md
   rules) that don't exist yet, install them using the same steps as the
   install path above (Steps B-E).

6. **Report:**
   ```
   Z Skills updated.

   Updated: N skills (list)
   New: N items installed (list)
   Unchanged: N skills

   Source: $ZSKILLS_PATH (pulled from origin)
   ```

---

## Key Rules

These rules are inviolable. They apply to all modes:

1. **NEVER overwrite existing CLAUDE.md content** — append only. New rules
   go into `## Agent Rules` at the end. Never modify or delete existing
   sections.
2. **NEVER overwrite existing hooks or scripts** — if a file already exists,
   skip it. The user may have customized it.
3. **Explain what hooks do when installing them** — don't just list
   filenames. The user needs to understand what each hook does.
4. **Show the user what will be installed BEFORE doing it** — no silent
   modifications. List every file that will be created or modified.
5. **The audit portion is strictly read-only** — it never modifies anything.
   It only reads files and produces a report. Modifications happen in the
   install/update steps that follow.
6. **The source of truth is `zskills-portable/`** — Step 0 describes how to
   locate it. Never hardcode paths or guess where assets live.
7. **Do NOT use AskUserQuestion** — ask naturally in conversation text.
   The structured prompt tool feels robotic and the options are awkward.
   Just ask in plain English and let the user respond normally.
