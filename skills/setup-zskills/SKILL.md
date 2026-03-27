---
name: setup-zskills
description: Install, audit, or update Z Skills supporting infrastructure (CLAUDE.md rules, hooks, scripts)
disable-model-invocation: true
---

# Setup Z Skills Infrastructure

Install, audit, or update the supporting infrastructure that Z Skills depend
on: CLAUDE.md agent rules, safety hooks, helper scripts, and skill
dependencies.

**Invocation:**

```
/setup-zskills [install | audit | update] [--with-addons | --with-block-diagram-addons]
```

Default mode (no argument): `audit`.

**Add-on flags (install mode only):**
- `--with-addons` — install core skills + ALL available add-on packs
- `--with-block-diagram-addons` — install core skills + block-diagram add-on
  (3 skills: `/add-block`, `/add-example`, `/model-design`)

Without an add-on flag, `install` only installs the 17 core skills. If core
is already installed, adding an add-on flag just copies the add-on skills
(the audit detects core is satisfied and skips it).

---

## Step 0 — Locate Portable Assets

**This step runs before any mode.** The portable assets live in
`zskills-portable/` in the Z Skills source repo. To find them:

1. Check if `zskills-portable/` exists in the current working directory. If
   yes, use it.
2. If not, check if any installed skill file (`.claude/skills/*/SKILL.md`)
   contains a `# Source:` header line pointing to the Z Skills repo path. If
   found, look for `zskills-portable/` relative to that path.
3. If still not found, ask the user: "Where is the Z Skills source repo? I
   need the path to `zskills-portable/`."

Store the resolved path as `$PORTABLE` for use in install/update modes.

---

## `audit` Mode — Read-Only Gap Analysis

The audit scans the project for all Z Skills dependencies and reports what
is missing. **It NEVER modifies any files.**

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
  - Tool references (`playwright-cli`, `gh `) — check if the tool is
    available via `which`.
  - Hook references (`block-unsafe`, `stop-log`) — check if the hook file
    exists in `.claude/hooks/`.
  - Script references (`scripts/port.js`, `scripts/test-all.js`) — check if
    the script file exists.

### Step 2 — Check CLAUDE.md for 13 generic rules

Read the project's `CLAUDE.md` (if it exists). For each of the 13 generic
rules, search for a distinctive key phrase that identifies the rule. Mark
the rule as present if the key phrase is found, missing otherwise.

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

### Step 3 — Check hooks

Look in `.claude/hooks/` for these 4 files:

- `block-unsafe-generic.sh` (or `block-unsafe.sh` — either name counts)
- `stop-log.cjs`
- `subagent-stop-log.cjs`
- `log-converter.cjs`

### Step 4 — Check scripts

Look in `scripts/` for these 3 files:

- `port.js`
- `test-all.js`
- `briefing.cjs`

### Step 5 — Check skills with additional requirements

If `/briefing` is installed, check for `briefing.cjs` in `scripts/` or
`.claude/hooks/`. If missing, add a note: "The /briefing skill requires a
project-specific briefing.cjs script — see /briefing skill documentation."

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

Hooks: M/4 installed (K missing)
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
  - /briefing: requires project-specific briefing.cjs (not found)
  ...

Overall: X/Y dependencies satisfied.
Run /setup-zskills install to fix gaps.
```

If everything is satisfied, end with:
```
Overall: Y/Y dependencies satisfied. Nothing to install.
```

---

## `install` Mode — Fill All Gaps

Runs the full audit first, then installs everything that is missing.

### Step 1 — Locate portable assets

Run Step 0 (locate portable assets). If the path cannot be resolved, stop
with an error: "Cannot locate zskills-portable/ directory. Please provide
the path to the Z Skills source repo."

### Step 2 — Run audit

Run audit steps 1-6 above. Display the gap report.

### Step 3 — Check for gaps

If no gaps found: report "All Z Skills dependencies are satisfied. Nothing
to install." and stop.

### Step 4 — Fill CLAUDE.md gaps

**If CLAUDE.md does NOT exist:**

Copy `$PORTABLE/CLAUDE_TEMPLATE.md` to `CLAUDE.md`. Then **auto-detect
placeholder values** from project files before prompting:

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

2. **Present detected values for confirmation:**
   ```
   CLAUDE.md created from template. Detected values (confirm or override):

     {{PROJECT_NAME}}: my-app (from package.json)
     {{DEV_SERVER_CMD}}: npm start (from package.json scripts.start)
     {{UNIT_TEST_CMD}}: npm test (from package.json scripts.test)
     {{FULL_TEST_CMD}}: npm run test:all (from package.json scripts["test:all"])

   Could not detect:
     {{SOURCE_PATHS}}: [please provide, e.g., src/, lib/]
   ```

3. **Only prompt for values that couldn't be detected.** For detected values,
   the user confirms or overrides. This means install on an established
   project requires minimal input — most values are discoverable.

After confirmation, do find-and-replace for each placeholder.

**If CLAUDE.md EXISTS but is missing rules:**

Show the user which rules are missing, show the exact text that will be
appended, and ASK before modifying. Append to a `## Agent Rules` section at
the end of the existing CLAUDE.md. If `## Agent Rules` already exists in
CLAUDE.md, append the missing rules to the existing section — do NOT create
a duplicate section header.

**NEVER overwrite or modify existing CLAUDE.md content.**

### Step 5 — Fill hook gaps

Copy missing hooks from `$PORTABLE/hooks/` to `.claude/hooks/`.

- For `block-unsafe-project.sh.template`: copy to
  `.claude/hooks/block-unsafe-project.sh`, then prompt user for the
  `# CONFIGURE:` values and replace them.
- For hooks with timezone placeholders (`stop-log.cjs`,
  `subagent-stop-log.cjs`): prompt user for timezone and replace.

Then read `.claude/settings.json`. Show the user the hook registration
entries that will be added. ASK before modifying. The format for hook
registration in `settings.json` is:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$(git rev-parse --show-toplevel)/.claude/hooks/block-unsafe-generic.sh\"",
            "timeout": 5
          },
          {
            "type": "command",
            "command": "bash \"$(git rev-parse --show-toplevel)/.claude/hooks/block-unsafe-project.sh\"",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"$(git rev-parse --show-toplevel)/.claude/hooks/stop-log.cjs\""
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"$(git rev-parse --show-toplevel)/.claude/hooks/subagent-stop-log.cjs\""
          }
        ]
      }
    ]
  }
}
```

Note: only the `Bash` matcher is used for PreToolUse hooks. The hook scripts
themselves only process Bash tool inputs (they exit early for other tools).

Report: "Installed N hooks: [list]"

### Step 6 — Fill script gaps

Copy missing scripts from `$PORTABLE/scripts/` to `scripts/`.

- For scripts with placeholders: prompt user for values and replace.

Report: "Installed N scripts: [list]"

### Step 7 — Install add-ons (if `--with-addons` or `--with-block-diagram-addons`)

Skip this step if no add-on flag was provided.

1. **Determine which add-on packs to install:**
   - `--with-addons` → all packs in `$PORTABLE/../block-diagram/` (and any
     future add-on directories)
   - `--with-block-diagram-addons` → only `$PORTABLE/../block-diagram/`

2. **For each add-on skill** (e.g., `add-block`, `add-example`, `model-design`):
   - If `.claude/skills/<name>/SKILL.md` already exists, skip (never overwrite)
   - Otherwise, copy from the add-on source directory to `.claude/skills/<name>/`

3. **Report:** "Installed N add-on skills: [list]" or "Add-on skills already
   installed — skipped."

### Step 8 — Final report

```
Installation complete.

Installed:
- CLAUDE.md: [created | N rules appended | already complete]
- Hooks: N hooks installed
- Scripts: N scripts installed
- Add-ons: N add-on skills installed (omit this line if no add-on flag was used)

Skills with additional requirements:
- /briefing: requires project-specific briefing.cjs (see /briefing skill docs)

Run /setup-zskills audit to verify.
```

---

## `update` Mode — Pull Latest and Fill Gaps

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
   the new version to `.claude/skills/`. Show the user what changed before
   overwriting.

4. **Update installed add-ons.** Check if any block-diagram add-on skills
   are installed (e.g., `.claude/skills/add-block/SKILL.md` exists). If so,
   update them from `$ZSKILLS_PATH/block-diagram/` the same way.

5. **Fill new gaps.** Run the audit. For any NEW items (skills, hooks,
   scripts, CLAUDE.md rules) that don't exist yet, install them using
   the same steps as install mode.

6. **Report:**
   ```
   Z Skills updated.

   Updated: N skills (list)
   Add-ons updated: N (list)
   New: N items installed (list)
   Unchanged: N skills

   Source: $ZSKILLS_PATH (pulled from origin)
   ```

---

## Key Rules

These rules are inviolable. They apply to all three modes:

1. **NEVER overwrite existing CLAUDE.md content** — append only. New rules
   go into `## Agent Rules` at the end. Never modify or delete existing
   sections.
2. **NEVER overwrite existing hooks or scripts** — if a file already exists,
   skip it. The user may have customized it.
3. **ALWAYS ask before modifying `.claude/settings.json`** — show the exact
   JSON that will be added and wait for confirmation.
4. **Show the user what will be installed BEFORE doing it** — no silent
   modifications. List every file that will be created or modified.
5. **The `audit` mode is strictly read-only** — it never modifies anything.
   It only reads files and produces a report.
6. **The source of truth is `zskills-portable/`** — Step 0 describes how to
   locate it. Never hardcode paths or guess where assets live.
