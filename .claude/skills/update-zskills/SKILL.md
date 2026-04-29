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
- `--rerender` — regenerate `.claude/rules/zskills/managed.md` against
  the current `.claude/zskills-config.json`. Simple full-file rewrite
  of the zskills-owned rules file; root `./CLAUDE.md` is never touched.
  No audit, no preset, no hooks/scripts touched. See
  `### Step D — --rerender` for the algorithm.

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
   update paths). Step F runs `.claude/skills/update-zskills/scripts/apply-preset.sh` which handles
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
       "default_port": 8080,
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
    - `node`: enables `.claude/skills/briefing/scripts/briefing.cjs` (preferred for /briefing)
    - `python3`: enables `.claude/skills/briefing/scripts/briefing.py` (fallback for /briefing)
  - Hook references (`block-unsafe`) — check if the hook file
    exists in `.claude/hooks/`.
  - Script references (`.claude/skills/update-zskills/scripts/port.sh`, `scripts/test-all.sh`) — check if
    the script file exists.

### Step 2 — Check zskills rules file for 13 generic rules

Read `.claude/rules/zskills/managed.md` (the zskills-owned rules
file); if absent, fall back to reading root `./CLAUDE.md` (pre-Phase-4
installs rendered rules there). For each of the 13 generic rules,
search for a distinctive key phrase that identifies the rule
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

Search the zskills rules file (`.claude/rules/zskills/managed.md`,
falling back to root `./CLAUDE.md`) for these documentation-presence
signals. Mark each present/missing based on **case-insensitive
substring match**:

| Check | Key phrase(s) to search in zskills rules file |
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

If `/briefing` is installed, check for `[ -f .claude/skills/briefing/scripts/briefing.cjs ]`
or `[ -f .claude/skills/briefing/scripts/briefing.py ]` (the artifact half catches
partial skill-mirror installs). If neither is found, add a note: "The /briefing
skill requires `.claude/skills/briefing/scripts/briefing.cjs` (or `briefing.py`)
— see /briefing skill documentation."

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

Agent Rules: M/13 present (K missing)
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
  - /briefing: requires `.claude/skills/briefing/scripts/briefing.cjs` or `briefing.py` (not found)
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

#### Step B — Render zskills-managed rules file

**Target path:** `.claude/rules/zskills/managed.md` in the project.
Create the `.claude/rules/zskills/` subdirectory if absent. Claude Code
auto-loads everything under `.claude/rules/` recursively at session
start, so no `@`-import from root `./CLAUDE.md` is needed.

**Ownership rule:** zskills owns `.claude/rules/zskills/` in full. The
user's root `./CLAUDE.md` is theirs exclusively. No cross-writes:
Step B never reads or modifies root `./CLAUDE.md` content (the
migration sub-step below is the sole, deterministic exception, and it
only removes zskills-rendered lines — never user content).

**Render algorithm (every install, first-run and subsequent — idempotent):**

1. **Scan project files for auto-detected placeholder defaults** (only
   used when the corresponding config field is empty):
   - `package.json` — `name`, `scripts.start`, `scripts.dev`, `scripts.test`,
     `scripts["test:all"]`, `scripts["test:ci"]`
   - `Cargo.toml` — `[package] name`
   - `pyproject.toml` / `setup.py` / `setup.cfg` — project name, test config
   - `Makefile` — `test`, `serve`, `dev` targets
   - `manage.py` — Django project (dev server: `python manage.py runserver`)
   - `.github/workflows/` / `.gitlab-ci.yml` — CI test commands
   - `pytest.ini` / `jest.config.*` / `.mocharc.*` — test framework detection
   - Git remote URL or directory name — fallback for project name

2. **Substitute placeholders** in `$PORTABLE/CLAUDE_TEMPLATE.md` using
   current `.claude/zskills-config.json` values (fall back to
   auto-detected defaults for empty fields; for truly unknown values,
   comment out with a TODO marker `<!-- TODO: fill in when known -->`).
   Placeholder mapping is documented in Step 0.5.

3. **Write the rendered content** to
   `.claude/rules/zskills/managed.md`. Full overwrite is safe by
   ownership rule — zskills owns this file in full; no user content
   ever lives here. The file is regenerated from template + config on
   every install and every `--rerender`. Never leaves broken
   `{{PLACEHOLDER}}` strings.

4. **Run the root-CLAUDE.md migration sub-step** (below) to detect and
   relocate any pre-Phase-4 zskills content from root `./CLAUDE.md`.

5. **Report:**
   <!-- allow-hardcoded: npm start reason: report-template example showing the auto-detected dev_server.cmd value; not an executable command -->
   ```
   .claude/rules/zskills/managed.md rendered. Values filled:
     Project name: my-app (from package.json)
     Dev server: npm start (detected)
     Test command: npm test (detected)
     Full test: commented out (no test:all script found — update when ready)

   Review .claude/rules/zskills/managed.md and adjust config values if needed
   (edit .claude/zskills-config.json, then rerun /update-zskills --rerender).
   ```

**Migration sub-step — relocate pre-Phase-4 zskills content from root `./CLAUDE.md`:**

Earlier zskills installs rendered into root `./CLAUDE.md`; Phase 4
moved the target to `.claude/rules/zskills/managed.md`. On every
install (first-run and subsequent), detect any zskills-rendered lines
still sitting in root `./CLAUDE.md` and remove them — carefully, so
user-authored content that merely mentions a zskills value is
preserved. Idempotent: on a clean install or after a previous
migration, nothing matches and nothing changes.

Algorithm:

1. If root `./CLAUDE.md` does not exist, the migration is a no-op.
   Skip and continue.

2. **Render the current template against current config** (same
   substitution used in Step B step 2 above) to produce a
   `$RENDERED_TEMPLATE` string. This is the set of lines zskills would
   write today.

3. For each placeholder `P` in `CLAUDE_TEMPLATE.md` whose current
   rendered value `V` is non-empty, identify the set of lines in
   `$RENDERED_TEMPLATE` that contain `V`. For each such "template
   line," record its ±2-line neighbourhood in the template (2 lines
   before, 2 lines after). The neighbourhood is the **context
   signature** for that template line.

4. Walk root `./CLAUDE.md` line by line. A root line is a **migration
   candidate** iff:
   - it contains at least one placeholder's current rendered value `V`, AND
   - its ±2-line neighbourhood in root `./CLAUDE.md` matches the
     corresponding template line's context signature (line-for-line,
     ignoring trailing whitespace).

   The context match restricts removal to lines that were genuinely
   rendered by zskills. Prose that merely mentions a zskills value in
   non-template context (e.g., "I remember we used to have
   `bash tests/run-all.sh`…") fails the context check and is preserved.

5. **If zero candidates**, migration is a no-op. Do not create a
   backup, do not emit a NOTICE. Stop.

6. **Otherwise**: back up root `./CLAUDE.md` to
   `./CLAUDE.md.pre-zskills-migration` — **only if that backup does
   NOT already exist.** Never overwrite a prior backup. This preserves
   the user's pre-migration state across repeated `/update-zskills`
   invocations.

7. Remove the matched candidate lines from root `./CLAUDE.md`.
   Everything else is left byte-identical. If the result is an empty
   file, leave it as an empty file (do not delete) — an existing
   `./CLAUDE.md` with no content signals "user chose zskills-only
   rules and has no other project notes yet"; recreating it on next
   invocation is cheaper than guessing intent.

8. Emit to stderr:

   ```
   NOTICE: Migrated zskills content from root ./CLAUDE.md to .claude/rules/zskills/managed.md.
   Backup: ./CLAUDE.md.pre-zskills-migration.
   If your Claude Code settings exclude .claude/** from context (e.g. claudeMdExcludes),
   the new rules file will not auto-load — adjust your excludes or @-import it from root CLAUDE.md.
   ```

**NEVER modify user-authored content in root `./CLAUDE.md`** — the
migration removes only lines matching both value AND ±2-line template
context. Anything the user added (their own sections, notes,
references) is untouched.

#### Step C — Fill hook gaps

Copy missing hooks from `$PORTABLE/hooks/` to `.claude/hooks/`.

- For `block-unsafe-project.sh.template`: copy to
  `.claude/hooks/block-unsafe-project.sh`. No install-time placeholder
  fill needed — the hook reads `testing.unit_cmd`, `testing.full_cmd`,
  and `ui.file_patterns` from `.claude/zskills-config.json` at runtime
  via bash regex (same idiom as `is_main_protected()`). Just copy the
  source template.
- For `scripts/test-all.sh`: copy as-is from
  `$PORTABLE/scripts/`. Reads `testing.unit_cmd` from
  `.claude/zskills-config.json` at runtime — no
  install-time fill. (Tier-2 placeholder; consumer
  customizes.)
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
backfill (Step 0.5 step 3.5), and `.claude/skills/update-zskills/scripts/apply-preset.sh`'s line
splice — all surgical, all agent-driven, all preserve-by-default. Step
C aligns with the house style.

**Matcher semantics:** `PreToolUse`+`Bash` enforces command safety and
tracking. `PreToolUse`+`Agent` enforces `agents.min_model` — blocking
subagent dispatches that specify a model below the configured minimum
(haiku=1 < sonnet=2 < opus=3). `PostToolUse`+`Edit`/`Write` (Phase 3)
surfaces `/update-zskills --rerender` guidance after edits to
`.claude/zskills-config.json`.

**Install-integrity check (applies to every row).** Before writing a
settings.json entry for a triple, verify the referenced hook file is
present in `$PORTABLE/hooks/` (source) — and therefore copyable to
`.claude/hooks/`. If the source file is missing (e.g. a zskills release
cut before the hook landed), warn the user and **skip that row's
wiring**; do not write a settings.json entry pointing at a script that
won't exist on disk. Report as `skip: <basename> — source missing` in
the Step 6 preview. Same pattern as the other hook copies in Step C:
"Copy missing hooks from `$PORTABLE/hooks/`" already fails soft if the
source file isn't there; this just extends that convention into the
settings.json merge.

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

If yes: copy `$PORTABLE/.claude/skills/update-zskills/scripts/statusline.sh` to `~/.claude/statusline-command.sh`
and add `"statusLine": {"type":"command","command":"bash ~/.claude/statusline-command.sh"}`
to `.claude/settings.json`. Users can customize further with `/statusline`.

#### Step D — Fill script gaps

> Copy missing scripts from `$PORTABLE/scripts/` and from
> `$PORTABLE/skills/update-zskills/stubs/` to `scripts/`
> (verify executable bit is preserved). The `stubs/` dir
> holds NEW consumer-customizable failing-stub / no-op
> templates (post-create-worktree.sh, dev-port.sh,
> start-dev.sh); `scripts/` holds the existing zskills-managed
> Tier-2 templates (stop-dev.sh, test-all.sh — kept at
> `scripts/` for continuity with prior installs; their
> bodies become failing stubs in Phase 5 but their source
> location does not move).

If `$PORTABLE/skills/update-zskills/stubs/` does not exist
(older zskills snapshot), skip the second source silently —
do not error.

- For scripts with placeholders: prompt user for values and replace.
- Copy `stop-dev.sh` if missing — sanctioned way to stop a
  dev server. Initial install is a failing stub the user
  replaces (contract: read PIDs from `var/dev.pid`, SIGTERM
  each). Pair: `start-dev.sh`.
- Copy `test-all.sh` if missing — invoked by `/run-plan`,
  `/verify-changes`, etc. when `testing.full_cmd` is
  `bash scripts/test-all.sh`. Initial install is a failing
  stub the user replaces.
- Copy `start-dev.sh` if missing — sanctioned way to start a
  dev server. Initial install is a failing stub the user
  replaces with their start command (and a write to
  `var/dev.pid`).
- Copy `post-create-worktree.sh` if missing — invoked by the
  `/create-worktree` skill's worktree-creation script after a
  successful create. Stub is a documented no-op; consumer
  replaces with setup steps (cp `.env.local`, `npm install`,
  etc.). See `.claude/skills/update-zskills/references/stub-callouts.md`.
- Copy `dev-port.sh` if missing — invoked by `port.sh`
  (lives in the `update-zskills` skill) after the
  `DEV_PORT` env override; if non-empty numeric stdout is
  returned, that value is used as the port. See
  `.claude/skills/update-zskills/references/stub-callouts.md`.
- Copy any consumer-stub templates from
  `$PORTABLE/skills/update-zskills/stubs/` (e.g.
  `post-create-worktree.sh`, `dev-port.sh`, `start-dev.sh`) if missing.
  See `references/stub-callouts.md` for the contract and inventory.

> Tier-1 scripts (skill machinery) ship via the skill mirror at
> `.claude/skills/<owner>/scripts/`. They are NOT copied to `scripts/`.
> See `references/script-ownership.md` for the full table.

Report: "Installed N scripts: [list]"

#### Step D.5 — Migrate stale Tier-1 scripts

Earlier zskills versions copied skill-machinery scripts to the
consumer's `scripts/`. Detect any leftover copies and offer to remove
them after verifying they match a known zskills version (so a
user-modified script is preserved with a warning).

```bash
# Pre-flight: git is required for hash-object normalization (DA-8 fix
# — explicit guard at the top of Step D.5). On git-missing systems,
# skip the migration with a one-line stderr note; do not abort
# /update-zskills mid-flight.
if ! command -v git >/dev/null 2>&1; then
  echo "Step D.5 requires git on PATH; skipping stale-Tier-1 migration" >&2
  return 0
fi

STALE_LIST=(
  apply-preset.sh
  briefing.cjs
  briefing.py
  clear-tracking.sh
  compute-cron-fire.sh
  create-worktree.sh
  land-phase.sh
  parse-plan.sh
  plan-drift-correct.sh
  port.sh
  post-run-invariants.sh
  sanitize-pipeline-id.sh
  statusline.sh
  worktree-add-safe.sh
  write-landed.sh
  zskills-stub-lib.sh
)
```

Note: `statusline.sh` is a defensive entry. Step C.5 copies
`statusline.sh` directly from
`$PORTABLE/.claude/skills/update-zskills/scripts/statusline.sh` to
`~/.claude/statusline-command.sh`, with no intermediate consumer-side
`scripts/statusline.sh` step. However, consumers may have a leftover
`scripts/statusline.sh` from manual copies, third-party tutorials, or
pre-refactor experiments. Defensive migration: matches → MIGRATED;
user-modified → KEPT. Expect this entry to be a no-op for most
consumers (the live install at `~/.claude/statusline-command.sh` is
separate and unaffected).

(Note: `build-prod.sh`, `mirror-skill.sh`, `stop-dev.sh`, `test-all.sh`
are NOT in `STALE_LIST` — they are Tier-2 per
`references/script-ownership.md` and stay at `scripts/`.)

```bash
KNOWN_HASHES=$PORTABLE/.claude/skills/update-zskills/references/tier1-shipped-hashes.txt
DEFER_MARKER=.zskills/tier1-migration-deferred

MIGRATED=()
KEPT=()
for name in "${STALE_LIST[@]}"; do
  target="scripts/$name"
  [ -f "$target" ] || continue

  # git is required (Phase 4 preconditions, guarded above).
  # CRLF-normalize for cross-platform consumer compat (D25 fix —
  # Windows consumers with core.autocrlf=true store files as LF in
  # the index but check out as CRLF; raw `git hash-object` would hash
  # the CRLF bytes and never match the LF-hashed release file).
  # Strip \r before hashing through stdin.
  consumer_hash=$(tr -d '\r' < "$target" | git hash-object --stdin)

  # Match against the static, version-shipped hashes file.
  if [ -f "$KNOWN_HASHES" ] && grep -qxF "$consumer_hash" "$KNOWN_HASHES"; then
    MIGRATED+=("$name")
  else
    KEPT+=("$name")
  fi
done

if [ "${#MIGRATED[@]}" -gt 0 ]; then
  echo "Found ${#MIGRATED[@]} stale Tier-1 script(s) at scripts/ that"
  echo "match a known zskills version. These now ship via skill mirrors."
  printf '  - %s\n' "${MIGRATED[@]}"
  read -r -p "Remove? [y/N] " ans
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    for name in "${MIGRATED[@]}"; do
      rm -- "scripts/$name" \
        && echo "removed scripts/$name" \
        || { echo "ERROR: rm scripts/$name failed" >&2; exit 1; }
    done
  else
    echo "Kept. To migrate later, re-run /update-zskills."
  fi
fi

# The defer marker is a NEWLINE-DELIMITED LIST of deferred filenames
# (D24 fix — boolean marker permanently muted future Tier-1 additions;
# per-file list re-prompts when a NEW Tier-1 filename appears in KEPT).
DEFERRED_NAMES=()
if [ -f "$DEFER_MARKER" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && DEFERRED_NAMES+=("$line")
  done < "$DEFER_MARKER"
fi

# Filter KEPT to only files NOT already deferred.
KEPT_NEW=()
for name in "${KEPT[@]}"; do
  skip=0
  for d in "${DEFERRED_NAMES[@]}"; do
    [ "$name" = "$d" ] && skip=1 && break
  done
  [ "$skip" -eq 0 ] && KEPT_NEW+=("$name")
done

if [ "${#KEPT_NEW[@]}" -gt 0 ]; then
  echo "WARNING: ${#KEPT_NEW[@]} Tier-1 script(s) at scripts/ do NOT match"
  echo "any known zskills version (likely user-modified). NOT removing."
  printf '  - %s\n' "${KEPT_NEW[@]}"
  echo
  echo "Review each: if your modifications are still needed, port them"
  echo "into a skill subdir (.claude/skills/<owner>/scripts/) and delete"
  echo "the scripts/ copy. If they were unintentional, delete the file."
  echo "To defer these files on subsequent /update-zskills runs:"
  echo "  mkdir -p .zskills"
  for name in "${KEPT_NEW[@]}"; do
    echo "  echo $name >> $DEFER_MARKER"
  done
  echo "(Future Tier-1 additions NOT in this list will re-prompt.)"
fi

# Strip leftover `port_script` field from the consumer's
# `.claude/zskills-config.json` (DA-7 fix). Phase 5 WI 5.5.a removes
# `port_script` from the schema; existing configs carrying that field
# would become unknown-property violations under the new schema.
CFG=.claude/zskills-config.json
if [ -f "$CFG" ] && grep -qF '"port_script"' "$CFG"; then
  TMP=$(mktemp)
  # Drop any line that contains only the port_script field plus possible
  # leading whitespace and trailing comma.
  grep -v '^\s*"port_script"\s*:' "$CFG" > "$TMP" \
    && mv "$TMP" "$CFG" \
    && echo "stripped legacy dev_server.port_script from $CFG (DA-7 fix)" \
    || { echo "ERROR: failed to strip port_script from $CFG" >&2; exit 1; }
fi
```

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
bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/apply-preset.sh" "$PRESET_ARG"
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
- .claude/rules/zskills/managed.md: [rendered | already current]
- Root ./CLAUDE.md migration: [none | N lines relocated, backup at ./CLAUDE.md.pre-zskills-migration]
- Hooks: N hooks installed
- Scripts: N scripts installed
- Add-ons: N add-on skills installed (omit this line if no add-on flag was used)

Skills with additional requirements:
- /briefing: requires `.claude/skills/briefing/scripts/briefing.cjs` or `briefing.py` (see /briefing skill docs)

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

5. **Fill new gaps.** For any NEW items (skills, hooks, scripts, zskills
   rules file) that don't exist yet, install them using the same steps as the
   install path above (Steps B-E). In particular, if
   `.claude/skills/update-zskills/scripts/apply-preset.sh` is missing from the target, copy it — Step F
   relies on it.

5.5. **Apply Preset** (if `$PRESET_ARG` is non-empty). Run the same
   procedure as **Step F** in the install path (defined above, under
   "Fill All Gaps"):

   ```bash
   bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/apply-preset.sh" "$PRESET_ARG"
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

**Scope:** full-file rewrite of `.claude/rules/zskills/managed.md`
against the current `.claude/zskills-config.json`.
Root `./CLAUDE.md` is never touched by `--rerender`.
Hooks and helper scripts are runtime-read; they
auto-reflect config changes with no action from this flag. Does not
touch `.claude/settings.json`, skills, or source templates. No audit,
no preset, no config backfill, no migration. Pure re-render.

**Algorithm:**

1. If `$PORTABLE/CLAUDE_TEMPLATE.md` is missing or unreadable, **exit
   1** with error `CLAUDE_TEMPLATE.md missing or unreadable; cannot
   rerender`.
2. Render the template against current config (same substitution
   logic as Step B step 2).
3. Create `.claude/rules/zskills/` if absent.
4. Write the rendered content to `.claude/rules/zskills/managed.md`
   (full overwrite — the file is zskills-owned, no user content lives
   here).
5. **Exit 0.**

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | Re-render complete. |
| 1 | `CLAUDE_TEMPLATE.md` missing or invalid. |

**What `--rerender` does NOT do:** re-run the audit, backfill config
fields, apply a preset, update skills, copy hooks/scripts, touch
`.claude/settings.json`, or run the root-CLAUDE.md migration. Any of
those require a full `/update-zskills` invocation.

---

## Key Rules

These rules are inviolable. They apply to all modes:

1. **zskills owns `.claude/rules/zskills/` in full; root `./CLAUDE.md`
   is the user's exclusively.** zskills renders, overwrites, and
   rerenders its own `managed.md` freely. It never writes to root
   `./CLAUDE.md` except for the one-time migration sub-step in
   Step B, which removes only lines matching both a rendered value
   AND the template's ±2-line context around that value. No other
   cross-writes.
2. **NEVER overwrite existing hooks or scripts** — if a file already
   exists, skip it. The user may have customized it.
   (Exception: `.claude/skills/update-zskills/scripts/apply-preset.sh` performs targeted in-place
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
