---
name: update-zskills
argument-hint: "[install | --rerender] [cherry-pick | locked-main-pr | direct] [--with-addons | --with-block-diagram-addons]"
description: Install or update Z Skills supporting infrastructure (CLAUDE.md rules, hooks, scripts)
---

# Update Z Skills Infrastructure

Install or update the supporting infrastructure that Z Skills depend
on: CLAUDE.md agent rules, safety hooks, helper scripts, and skill
dependencies.

**Invocation:**

```
/update-zskills [install | --rerender] [cherry-pick | locked-main-pr | direct]
                [--with-addons | --with-block-diagram-addons]
```

Default mode (no argument): **smart detection** — if nothing is installed
yet, do a full install; if already installed, pull latest, update changed
skills, and fill new gaps. Always begins with an audit and reports what
was found and what was done about it.

**Explicit mode:**
- `install` — force a full first-time setup (same as what the default
  mode does when nothing is installed, but skips the detection step)
- `--rerender` — regenerate the template-managed portion of `CLAUDE.md`
  against the current `.claude/zskills-config.json`. Preserves every
  line below `## Agent Rules`. No audit, no preset, no hooks/scripts
  touched. See `### Step D — --rerender` for the full algorithm.

**Preset keywords (bare word, anywhere in the args):**

Presets control three things at once: `execution.landing`,
`execution.main_protected`, and the `BLOCK_MAIN_PUSH` line in
`.claude/hooks/block-unsafe-generic.sh`. Everything else in
`zskills-config.json` is preserved.

| Preset | `execution.landing` | `execution.main_protected` | `BLOCK_MAIN_PUSH` |
|---|---|---|---|
| `cherry-pick` (default) | `cherry-pick` | `false` | `0` |
| `locked-main-pr` | `pr` | `true` | `1` |
| `direct` | `direct` | `false` | `0` |

Behavior by invocation:
- `/update-zskills <preset>` — apply that preset; no greenfield prompt.
  If the config already exists, overwrite ONLY the three preset-owned
  fields above; every other field (branch_prefix, tests, CI, dev_server,
  UI patterns, timezone, min_model) is preserved.
- `/update-zskills` **and no existing `.claude/zskills-config.json`** —
  ask the user the greenfield prompt (see Step 0.6), then apply the
  chosen preset and write the config.
- `/update-zskills` **and existing config, no preset arg** — respect the
  existing config; do NOT re-ask. This is the idempotent re-install /
  update path.

**Add-on flags:**
- `--with-addons` — install/update core skills + ALL available add-on packs
- `--with-block-diagram-addons` — install/update core skills + block-diagram
  add-on (3 skills: `/add-block`, `/add-example`, `/model-design`)

Without an add-on flag, only the 20 core skills are installed/updated.
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

## Step 0.25 — Parse Preset Arg

Scan the invocation arguments for one of these bare keywords (order
doesn't matter; no `preset=` prefix; must be a whole word):

- `cherry-pick`
- `locked-main-pr`
- `direct`

Record the match as `$PRESET_ARG`. If none is present, `$PRESET_ARG` is
empty. If more than one is present, stop with an error: "Specify exactly
one preset: cherry-pick, locked-main-pr, or direct."

Parser pseudocode (classify each token; presets, mode, and add-on flags
are orthogonal and can coexist):

```
PRESET_ARG=""
MODE=""          # "install" or "" (default = smart detection)
ADDON_FLAG=""    # --with-addons | --with-block-diagram-addons | ""
for tok in $ARGUMENTS; do
  case "$tok" in
    cherry-pick|locked-main-pr|direct)
      [ -n "$PRESET_ARG" ] && fail "multiple presets"
      PRESET_ARG="$tok" ;;
    install) MODE="install" ;;
    --with-addons|--with-block-diagram-addons) ADDON_FLAG="$tok" ;;
    *) ;;  # unknown token — ignore, don't error
  esac
done
```

`install` + a preset keyword are compatible and combine (force-install
with the chosen preset). `--with-addons` / `--with-block-diagram-addons`
are independent of the preset — they control only which skills get
installed, not landing behavior.

Preset → field mapping (used wherever a preset is applied in later
steps):

| `$PRESET_ARG` | `execution.landing` | `execution.main_protected` | `BLOCK_MAIN_PUSH` |
|---|---|---|---|
| `cherry-pick` | `"cherry-pick"` | `false` | `0` |
| `locked-main-pr` | `"pr"` | `true` | `1` |
| `direct` | `"direct"` | `false` | `0` |

The three affected fields are **preset-owned**. When `$PRESET_ARG` is
non-empty, every other field in `.claude/zskills-config.json`
(`branch_prefix`, `testing.*`, `dev_server.*`, `ui.*`, `ci.*`,
`timezone`, `agents.min_model`) is preserved unchanged.

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
   # Extract commit.co_author (optional — backfilled below if missing):
   if [[ "$CONFIG_CONTENT" =~ \"co_author\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     CO_AUTHOR="${BASH_REMATCH[1]}"
   fi
   ```
3. For each template placeholder, use the config value if non-empty.
3.5. **Backfill `commit.co_author` if absent.** If the existing config
   does not contain a `"commit"` block with a `"co_author"` field (e.g.
   configs written before this field was introduced), splice in the
   default so downstream skills (`/quickfix`, `/commit`) can rely on the
   field resolving. Default value:
   `"Claude Opus 4.7 (1M context) <noreply@anthropic.com>"`. Match the
   same style used for other optional-field backfills — a targeted
   `Edit` or small `sed`-based rewrite that preserves every other field unchanged.
   If the `commit` key is absent, add the whole block; if the `commit`
   block exists but lacks `co_author`, add only that field. Idempotent:
   re-running on an already-backfilled config is a no-op.
4. Copy `config/zskills-config.schema.json` from `$PORTABLE` to
   `.claude/zskills-config.schema.json` in the target project (so the
   `$schema` reference in the config resolves correctly).
5. **If `$PRESET_ARG` was set**, defer preset application to
   **Step F — Apply Preset** (invoked at the end of both install and
   update paths). Step F runs `scripts/apply-preset.sh` which handles
   all three preset-owned fields (`execution.landing`,
   `execution.main_protected`, `BLOCK_MAIN_PUSH`) atomically,
   including idempotency, JSON formatting variance, missing
   `execution` key, and legacy hooks without the `BLOCK_MAIN_PUSH=`
   line. Don't attempt a manual `Edit` here — the script is the
   single source of truth.

**If it does not exist:**
1. **If `$PRESET_ARG` is empty**, run the greenfield prompt (Step 0.6)
   to pick a preset. Otherwise skip the prompt and use `$PRESET_ARG`.
2. Auto-detect values from the project (existing behavior).
3. Write the config file directly using the `Write` tool. Running
   `/update-zskills` is the user's consent — do not gate this on a paste-this-
   heredoc step. If the user's permission mode prompts for the write, that is
   Claude Code's normal flow and the user will approve.

   Content to write to `.claude/zskills-config.json`:
   ```json
   {
     "$schema": "./zskills-config.schema.json",
     "project_name": "<detected>",
     "timezone": "America/New_York",
     "execution": {
       "landing": "<preset.landing>",
       "main_protected": <preset.main_protected>,
       "branch_prefix": "feat/"
     },
     "commit": {
       "co_author": "Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
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
   ```
   Substitute the three preset-owned placeholders (`<preset.landing>`,
   `<preset.main_protected>`) using the Step 0.25 mapping table. Fields
   left empty by auto-detection stay as empty strings — the install
   summary's test-setup blurb tells the user what to fill in later.

4. **Hook toggle handled by Step F.** The config's `execution.landing`
   and `execution.main_protected` placeholders above are substituted
   in at write time. The `BLOCK_MAIN_PUSH` line in the hook is set by
   **Step F — Apply Preset** at the end of the install path, after
   Step C has copied the hook. Step F idempotently flips the value
   (or splices the line, on a legacy hook without it) to match the
   preset target. Nothing to do here.

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
| `{{DEV_SERVER_CMD}}` | `dev_server.cmd` | `npm start` |
| `{{PORT_SCRIPT}}` | `dev_server.port_script` | `scripts/port.sh` |
| `{{AUTH_BYPASS}}` | `ui.auth_bypass` | `localStorage.setItem(...)` |

Runtime-read fields (not install-filled): `testing.unit_cmd`, `testing.full_cmd`, `ui.file_patterns`, `dev_server.main_repo_path`. Hooks and helper scripts read these directly from `.claude/zskills-config.json` at every invocation — see Phase 1 of `plans/DRIFT_ARCH_FIX.md`.

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

## Step 0.6 — Greenfield Preset Prompt

**Run this only when** `.claude/zskills-config.json` does NOT exist AND
`$PRESET_ARG` is empty. Skip otherwise.

**Do NOT use AskUserQuestion.** Ask in plain conversation text, exactly
as shown. Wait for the user's reply before proceeding.

Ask:

```
How should /run-plan land changes?
  (1) cherry-pick — each phase squash-lands directly to main (simple, solo)
  (2) locked-main-pr — plans become feature branches + PRs, CI, auto-merge
      (locked main, shared repo)
  (3) direct — work on main, no worktree isolation (minimal, risky)

Default: (1). Pick one, or accept the default.
```

Map the reply:
- `1`, `cherry-pick`, or an empty/default-accepting reply → `cherry-pick`
- `2`, `locked-main-pr`, or `pr` → `locked-main-pr`
- `3`, `direct` → `direct`
- **Anything else** (e.g. "idk", "whatever", "the usual") → treat as
  default. Confirm once in plain text: "Going with cherry-pick (the
  default). Run `/update-zskills locked-main-pr` later to switch." —
  then proceed. Never re-ask the prompt; never invent a 4th option.

Set `$PRESET_ARG` to the chosen preset and proceed. No follow-up
questions — the three-field mapping (landing + main_protected +
BLOCK_MAIN_PUSH) in Step 0.25 is final. In particular, we do **not**
ask "do you want the main-push block on?" for `locked-main-pr`:
`main_protected=true` already makes `block-unsafe-project.sh` block
agent commits, cherry-picks, and pushes on main, so the generic hook's
`BLOCK_MAIN_PUSH=1` is belt-and-suspenders, not a user-facing choice.

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

Look in `scripts/` for these files (all required by installed skills):

- `port.sh`
- `test-all.sh`
- `briefing.cjs` OR `briefing.py` (either counts — Node or Python version)
- `clear-tracking.sh`
- `land-phase.sh` — referenced by `/run-plan`, `/fix-issues`, `/do` for atomic post-landing cleanup
- `post-run-invariants.sh` — referenced by `/run-plan` as mandatory end-of-run gate (7 invariants)
- `write-landed.sh` — referenced by `/run-plan`, `/fix-issues`, `/commit` for rc-checked atomic `.landed` marker writes
- `worktree-add-safe.sh` — referenced by `/run-plan`, `/fix-issues`, `/do` for safe worktree creation (discriminates fresh vs poisoned stale branches)
- `create-worktree.sh` — referenced by `/run-plan`, `/fix-issues`, `/do` for unified worktree creation
- `sanitize-pipeline-id.sh` — shared PIPELINE_ID sanitizer (used by `/run-plan`, `/fix-issues`, `/do`, `/quickfix` before persisting ID)
- `apply-preset.sh` — required by the preset UX (Step F); splices/flips the `BLOCK_MAIN_PUSH` line in `block-unsafe-generic.sh` and updates `execution.landing`/`execution.main_protected` in config
- `compute-cron-fire.sh` — required by `/run-plan` (Phase 5c chunked finish-auto, verify-pending retry, re-entry) for computing one-shot cron expressions with correct minute/hour/day/month/year rollover
- `stop-dev.sh` — sanctioned SIGTERM-only dev-server stopper (reads `var/dev.pid`). The approved way for agents to stop a dev server without reaching for `kill -9` / `fuser -k` / `lsof -ti | xargs kill`
- `statusline.sh` — session statusline helper (optional but should be installed if the user has it)

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
  `.claude/hooks/block-unsafe-project.sh`. No install-time placeholder
  fill needed — the hook reads `testing.unit_cmd`, `testing.full_cmd`,
  and `ui.file_patterns` from `.claude/zskills-config.json` at runtime
  via bash regex (same idiom as `is_main_protected()`). Just copy the
  source template.
- For `scripts/port.sh` and `scripts/test-all.sh`: copy as-is from
  `$PORTABLE/scripts/`. These also read `dev_server.main_repo_path` and
  `testing.unit_cmd` from `.claude/zskills-config.json` at runtime — no
  install-time fill.
- For any remaining templates that do still contain placeholders
  (`{{E2E_TEST_CMD}}`, `{{BUILD_TEST_CMD}}`): these have no config
  source, so fill from project detection or leave as a `# TODO`
  comment. Only these two placeholders — all others listed in the
  Step 0.5 mapping table go through the template-render path (Step B),
  not the hook path.

Note: hooks and helper scripts read `testing.*`, `ui.file_patterns`,
and `dev_server.main_repo_path` from `.claude/zskills-config.json` at
runtime. No install-time fill needed. Only copy the source template.

**Explain what each hook does** so the user understands what's being added:

> Installing 2 safety hooks:
> - **block-unsafe-generic.sh** — blocks destructive commands (git reset
>   --hard, rm -rf, kill -9, git checkout --, etc.) and discipline
>   violations (git add ., --no-verify)
> - **block-unsafe-project.sh** — project-specific guards: prevents piping
>   test output (must capture to file), verifies tests ran before commit,
>   and optionally checks for UI verification before committing UI changes

**Main-push block (preset-controlled):** `block-unsafe-generic.sh`
blocks `git push` to `main`/`master` when `BLOCK_MAIN_PUSH=1`, the
top-of-file variable. The preset controls this value via
**Step F — Apply Preset** at the end of the install/update path; no
action here in Step C. Preset mapping: `cherry-pick` → `0`,
`locked-main-pr` → `1`, `direct` → `0`.

**Note on tracking enforcement:** The tracking enforcement section in
`block-unsafe-project.sh` (protecting `.zskills/tracking/`, blocking
`clear-tracking.sh` execution, and enforcing delegation/step verification)
has no placeholders — it works out of the box. No configuration needed.

**Add tracking directory to `.gitignore`:** During installation, add
`.zskills/tracking/` to the project's `.gitignore` if not already present.
Tracking files are ephemeral session state and should never be committed.

**Add `var/` to `.gitignore`:** Also add `var/` if not already present.
`scripts/stop-dev.sh` reads PIDs from `var/dev.pid` (written by the
project's dev server launcher); PID files are per-worktree runtime state
and must never be committed.

Then register the hooks in `.claude/settings.json` via a **surgical
agent-driven merge** — `Read` + `Edit` only, never `Write`-from-template.
This preserves every other top-level key (`permissions`, `env`,
`statusLine`, `model`, ...) and every non-zskills-owned hook entry that
a user or another tool may have added.

**Canonical zskills-owned triples** (single source of truth — anything
not in this table is foreign and preserved untouched):

| Event        | Matcher | Command literal                                                              |
|--------------|---------|------------------------------------------------------------------------------|
| PreToolUse   | Bash    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-generic.sh"`           |
| PreToolUse   | Bash    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-project.sh"`           |
| PreToolUse   | Agent   | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-agents.sh"`                   |
| PostToolUse  | Edit    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/warn-config-drift.sh"`              |
| PostToolUse  | Write   | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/warn-config-drift.sh"`              |

All 5 rows carry `"type": "command"` and `"timeout": 5`. The
`warn-config-drift.sh` hook lands in Phase 3 of
`plans/DRIFT_ARCH_FIX.md`; the two PostToolUse rows become live once
that hook is installed.

**Step C algorithm** (never overwrite; never reorder top-level keys;
never strip whitespace from untouched regions; never re-emit the file
from a template):

1. **`Read` `.claude/settings.json`.** If the file does not exist,
   `Write` a minimal file containing only the zskills `hooks` block
   populated from the table above. Nothing to preserve on a fresh
   install — stop.
2. If the top-level `hooks` key is absent, `Edit` to insert a
   `"hooks": { "PreToolUse": [], "PostToolUse": [] }` skeleton adjacent
   to the existing top-level keys.
   Do not touch `permissions`, `env`, `statusLine`, `model`, or any other existing top-level key.
3. **Run Step C.9 renames first** (see below): for each
   `old_command → new_command` row in the migration table, search the
   entire `hooks.PreToolUse` and `hooks.PostToolUse` arrays for an
   entry whose `command` equals `old_command`. If found, `Edit` to
   replace the exact `old_command` string with `new_command` in place.
   The surrounding structure (matcher, timeout, siblings) is preserved.
   Renames first ensures later steps don't see orphan entries.
4. For each `(event, matcher, command)` triple in the canonical table:
   a. Search the ENTIRE `hooks.<event>` array (all matcher blocks) for
      an object whose `hooks[*].command` equals `command` exactly. If
      found anywhere — even under a different matcher — treat as
      "already present" and skip (do not duplicate).
   b. Otherwise, locate the matcher block whose `matcher` field equals
      the triple's matcher. If present, `Edit` to append the zskills
      hook object to that block's `hooks` array.
      Do not touch sibling hook objects (user-added customizations in the same matcher survive).
   c. If no matcher block with that matcher exists, `Edit` to append a
      new `{ "matcher": "<matcher>", "hooks": [ <zskills entry> ] }`
      object to `hooks.<event>`.
5. Never reorder top-level keys, never strip whitespace from untouched
   regions, never re-emit the file from a template, never remove
   entries not listed in the rename table (Step C.9) or already-present
   check (step 4a).
6. **Preview and confirm before any `Edit`.** Display a diff-style
   summary to the user — one line per planned action (`+ add
   block-agents.sh under Agent matcher`, `skip: block-unsafe-generic.sh
   already present`, `rename: block-unsafe-project.sh → deny-unsafe.sh`
   ) — and ASK for confirmation.
   Mirrors the Step B CLAUDE.md append convention (preview + ask).
   On confirmation, perform the Edits; on rejection, report which
   entries were missing and exit without changes.
7. **Report:** `"Step C: registered N hook entries, skipped M already
   present, renamed R, preserved F foreign entries."`

**Why agent-driven, not scripted.** Three prior adversarial reviews of
bash-splice approaches (append-if-missing, overwrite-if-stock,
partition-by-ownership) all concluded that bash + nested-JSON is
high-cost / high-risk. The `Edit` tool's exact-string match + LLM
reasoning about JSON structure makes this operation natural. Precedents
in this same skill: Step B's CLAUDE.md append, the `zskills-config.json`
backfill (Step 0.5 step 3.5), and `scripts/apply-preset.sh`'s line
splice — all surgical, all agent-driven, all preserve-by-default. Step
C aligns with the house style.

**Matcher semantics:** `PreToolUse`+`Bash` enforces command safety and
tracking. `PreToolUse`+`Agent` enforces `agents.min_model` — blocking
subagent dispatches that specify a model below the configured minimum
(haiku=1 < sonnet=2 < opus=3). `PostToolUse`+`Edit`/`Write` (Phase 3)
surfaces `/update-zskills --rerender` guidance after edits to
`.claude/zskills-config.json`.

#### Step C.9 — Hook renames

Rename migrations run BEFORE the main Step C merge loop (step 3 above),
so each row rewrites an existing entry in place. The surrounding
structure (matcher, timeout, siblings) is preserved byte-for-byte.

**When to add a row:** when a zskills release renames a hook file
(e.g. `block-unsafe.sh` → `block-unsafe-generic.sh`), the PR that
ships the rename MUST add a row here. Without a row, the old command
lingers in every downstream install's `settings.json` alongside the
new one — two copies of the same hook registered under the same
matcher.

**Format:** one row per rename, `old_command` and `new_command` as
full exact strings (same form as the canonical table's `Command
literal` column). Rows are append-only and idempotent — if
`old_command` is absent from a given install, the row is a no-op.

**Migration table** (initially empty):

```
# old_command → new_command

# (none yet)
#
# Template for future rows:
# old_command: bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<old-name>.sh"
# new_command: bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<new-name>.sh"
#
# Committed in the same PR that ships the rename. Rows accumulate; the
# table is append-only. Step C.9 runs each row against every install;
# rows are idempotent (if old_command absent, the row is a no-op).
```

When a row is added, include it in the preview displayed to the user in
Step C step 6 (`rename: <basename> → <basename>`).

#### Step C.5 — Statusline (optional)

If `.claude/settings.json` already has a `"statusLine"` key, skip.

Otherwise, offer to install: "Add zskills statusline? Shows context window,
5-hour, and 7-day rate limits as colored bars."

If yes: copy `$PORTABLE/scripts/statusline.sh` to `~/.claude/statusline-command.sh`
and add `"statusLine": {"type":"command","command":"bash ~/.claude/statusline-command.sh"}`
to `.claude/settings.json`. Users can customize further with `/statusline`.

#### Step D — Fill script gaps

Copy missing scripts from `$PORTABLE/scripts/` to `scripts/` (verify
executable bit is preserved).

- For scripts with placeholders: prompt user for values and replace.
- Copy `clear-tracking.sh` if missing — lets the user manually clear
  stale tracking state. Agents are blocked from running it by the
  project hook.
- Copy `apply-preset.sh` if missing — required by Step F (preset UX).
  Without it, `/update-zskills <preset>` will fail.
- Copy `stop-dev.sh` if missing — the sanctioned way for agents to stop
  a dev server (SIGTERM to PIDs in `var/dev.pid`). Keeps the generic
  hook's kill blocks intact while giving the agent a legitimate path.

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

#### Step F — Apply Preset (if `$PRESET_ARG` is non-empty)

This is the **single place** where preset values land into config and
hook. Called from both "Fill All Gaps" (install path) and "Pull Latest
and Update" (update path) before their final report.

If `$PRESET_ARG` is empty, skip this step entirely — nothing to do.

Otherwise:

```bash
bash scripts/apply-preset.sh "$PRESET_ARG"
```

Capture stdout and the exit code. Report to the user verbatim:
- Exit 0: "Applied preset '<name>':" followed by the list of changes
  the script reported.
- Exit 1: "Preset '<name>' already applied — no changes needed."
- Exit 2/3/4: print the script's error message and halt; these only
  fire when the config file is missing, the hook file is missing, the
  config JSON is malformed, or an unknown preset was somehow passed.
  In that case, advise the user and do not continue.

**Why a script and not a series of `Edit` calls in the SKILL.md?**
The script is deterministic, idempotent, and unit-tested
(`tests/test-apply-preset.sh`, 16 cases covering legacy hooks,
missing `execution` keys, compact JSON, idempotency, error paths).
A prompt-side sequence of `Edit` calls is fragile against JSON
formatting variance and legacy hook versions. Delegate to the script.

#### Step G — Final report

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
   install path above (Steps B-E). In particular, if
   `scripts/apply-preset.sh` is missing from the target, copy it — Step F
   relies on it.

5.5. **Apply Preset** (if `$PRESET_ARG` is non-empty). Run the same
   procedure as **Step F** in the install path (defined above, under
   "Fill All Gaps"):

   ```bash
   bash scripts/apply-preset.sh "$PRESET_ARG"
   ```

   Capture stdout and exit code; report verbatim to the user. This is
   the single place where preset values land into config and hook —
   regardless of install/update path.

6. **Report:**
   ```
   Z Skills updated.

   Updated: N skills (list)
   New: N items installed (list)
   Unchanged: N skills

   Source: $ZSKILLS_PATH (pulled from origin)
   ```

---

### Step D — --rerender

**Trigger:** user runs `/update-zskills --rerender`.

**Scope:** regenerates `CLAUDE.md` only. Hooks and helper scripts are
runtime-read; they auto-reflect config changes with no action from
this flag. Does not touch `.claude/settings.json`, skills, or source
templates. No audit, no preset, no config backfill — this is a pure
CLAUDE.md re-render against the current `.claude/zskills-config.json`.

**Use case:** after a post-install edit to
`.claude/zskills-config.json` changes a render-time-filled field
(`{{PROJECT_NAME}}`, `{{DEV_SERVER_CMD}}`, `{{PORT_SCRIPT}}`,
`{{AUTH_BYPASS}}`, `{{E2E_TEST_CMD}}`, `{{BUILD_TEST_CMD}}`,
`{{TIMEZONE}}`), the frozen `CLAUDE.md` snapshot has drifted. This
flag brings it back in sync without an audit round-trip.

**Boundary-detection algorithm:**

1. **Locate the `## Agent Rules` demarcation** in the existing
   `CLAUDE.md`:

   ```bash
   HEADING_LINE=$(grep -n '^## Agent Rules[[:space:]]*$' CLAUDE.md | head -1 | cut -d: -f1)
   ```

   Tolerant of trailing whitespace, strict on leading `##` and — by
   convention — a surrounding blank line (Step B appends with blank
   lines around the heading). If no match → **exit 2** with error:

   > `CLAUDE.md missing '## Agent Rules' demarcation; cannot rerender safely. Add the heading or re-run /update-zskills (without --rerender) for initial install.`

2. **Split the existing file** on the heading line:
   - `existing_above` = lines `1 .. heading_line - 1`
   - `existing_below` = lines `heading_line .. end` (heading itself
     stays in the below region)

3. **Render `CLAUDE_TEMPLATE.md` against current config.** For each
   placeholder (`{{PROJECT_NAME}}`, `{{DEV_SERVER_CMD}}`,
   `{{PORT_SCRIPT}}`, `{{AUTH_BYPASS}}`, `{{E2E_TEST_CMD}}`,
   `{{BUILD_TEST_CMD}}`, `{{TIMEZONE}}`), substitute the current
   config value (per Step B's existing fill logic, unchanged). Locate
   the `## Agent Rules` heading in the rendered output; extract
   `fresh_above`.

4. **Byte-compare `existing_above` to `fresh_above`.**
   Right-trim trailing whitespace on each line before comparing, to
   tolerate editor-induced churn. No "normalize by substituting prior
   values" — if they differ, the differences are either user edits OR
   config-change-since-last-render. Both cases mean the user reviews
   before overwriting.

   - **Identical:** write `fresh_above + existing_below` to
     `CLAUDE.md`. **Exit 0.** If the resulting bytes equal the
     existing `CLAUDE.md` content, skip the write entirely so the file
     mtime stays stable — ensures idempotency (second consecutive
     `--rerender` is a true no-op).
   - **Different:** write `fresh_above + existing_below` to
     `CLAUDE.md.new`. Do NOT overwrite `CLAUDE.md`. Print to stderr
     verbatim:

     ```
     CLAUDE.md differs above '## Agent Rules' (user edits, config drift, or both).
     New rendered content written to CLAUDE.md.new. Review with:
         diff CLAUDE.md CLAUDE.md.new
     To accept the new version:  mv CLAUDE.md.new CLAUDE.md
     To discard it:              rm CLAUDE.md.new
     ```

     **Exit 2.**

**Missing `CLAUDE.md`:** **exit 1** with error `no existing CLAUDE.md;
run /update-zskills (without --rerender) for initial install`. Do not
create one silently — `--rerender` is explicitly a re-render of an
existing install, not an initial install.

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | Clean re-render (or idempotent no-op). |
| 1 | No existing `CLAUDE.md` — not a valid `--rerender` target. |
| 2 | Conflict (user edits above `## Agent Rules`, or missing demarcation heading). |

**Why no interactive prompt on conflict:** `--rerender` is routinely
invoked from headless automation (e.g., the Phase 3
`warn-config-drift.sh` hook suggests it after a config edit). The
diff-command + merge-instructions on stderr keep the agent's path
deterministic while preserving user intent.

**What `--rerender` does NOT do:** re-run the audit, backfill config
fields, apply a preset, update skills, copy hooks/scripts, or touch
`.claude/settings.json`. Any of those require a full
`/update-zskills` invocation.

---

## Key Rules

These rules are inviolable. They apply to all modes:

1. **NEVER overwrite existing CLAUDE.md content** — append only. New rules
   go into `## Agent Rules` at the end. Never modify or delete existing
   sections.
2. **NEVER overwrite existing hooks or scripts** — if a file already
   exists, skip it. The user may have customized it.
   (Exception: `scripts/apply-preset.sh` performs targeted in-place
   edits to `block-unsafe-generic.sh` — splicing a missing
   `BLOCK_MAIN_PUSH=` line or flipping its value. This is a
   deterministic, non-destructive operation limited to that one line;
   the rest of the hook is preserved byte-for-byte.)
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
