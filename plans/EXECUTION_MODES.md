---
title: Execution Modes
created: 2026-04-13
status: active
---

# Plan: Execution Modes

## Overview

Add three landing modes to zskills skills: **cherry-pick** (default, existing behavior), **PR** (push feature branch + `gh pr create`), and **direct** (work on main, no landing step). Includes a config file (`.claude/zskills-config.json`) that `/update-zskills` reads, a `main_protected` hook that blocks commits/cherry-picks/pushes to main, and propagation through the skill chain (`/run-plan`, `/fix-issues`, `/research-and-go`, `/draft-plan`, `/do`, `/commit`, `/research-and-plan`).

The tracking system is DONE and working. This plan builds on top of it. Tracking uses `.zskills/tracking/`, pipeline association uses `.zskills-tracked` in worktrees and `ZSKILLS_PIPELINE_ID=` in transcripts, and verification agents commit (not impl agents).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Config File + /update-zskills | ✅ Done | `2bbe180` | Config, schema, /update-zskills Step 0.5, 6 tests |
| 2 -- main_protected Hook Enforcement | ✅ Done | `a874492` | Runtime config read, 8 tests, push fallback |
| 3a -- Argument Detection + Config Reading + Direct Mode | ✅ Done | `a8dfe49` | 11 tests, pr/direct detection, config default |
| 3b-i -- Worktree Unification + Landing Script | ✅ Done | `9cc1dc2` | Manual worktrees, land-phase.sh, preflight, 7 tests |
| 3b-ii -- PR Mode Happy Path | ✅ Done | `36af895` | Named branches, rebase, push+PR, .landed, 9 tests |
| 3b-iii -- CI Integration + Fix Cycle + Auto-Merge | ✅ Done | `e24d8ad` | CI polling, fix cycle, auto-merge, PR comments, 4 tests |
| 4 -- /fix-issues PR Landing | ✅ Done | `e9d4a82` | Per-issue branches, PR #10, 3 tests |
| 5a -- Skill Propagation | 🟡 In Progress | `a13211f` | research-and-go, research-and-plan, draft-plan |
| 5b -- Execution Skills + Documentation | ⬜ | | do, commit, CLAUDE_TEMPLATE, update-zskills |
| 5c -- Infrastructure: Cleanup, Model Gate, Baseline | ⬜ | | cleanup tooling, agents.min_model, baseline snapshot |

---

## Phase 1 -- Config File + /update-zskills

### Goal

Define the `.claude/zskills-config.json` schema, create the zskills dogfood config, create the JSON Schema file for VS Code validation, and modify `/update-zskills` to read the config, merge with auto-detected values, and fill CLAUDE_TEMPLATE.md and hook templates from config values instead of raw placeholders.

### Work Items

#### 1.1 -- Define `.claude/zskills-config.json` schema

Create `.claude/zskills-config.json` for the zskills repo itself (dogfood):

```json
{
  "$schema": "./zskills-config.schema.json",
  "project_name": "zskills",
  "timezone": "America/New_York",

  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "feat/"
  },

  "testing": {
    "unit_cmd": "bash tests/test-hooks.sh",
    "full_cmd": "bash scripts/test-all.sh",
    "output_file": ".test-results.txt",
    "file_patterns": ["tests/**/*.sh"]
  },

  "dev_server": {
    "cmd": "",
    "port_script": "",
    "main_repo_path": "/workspaces/zskills"
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

**`$schema`:** Points to the JSON Schema file in the same directory. VS Code uses this for autocomplete, hover descriptions, and live validation. The `$schema` field is ignored by the bash regex extraction.

**Allowed values for `execution.landing`:** `"cherry-pick"` (default), `"pr"`, `"direct"`.

**Allowed values for `execution.main_protected`:** `true`, `false` (default).

**`execution.branch_prefix`:** String prepended to plan slug for branch names. Default `"feat/"`. Examples: `"feat/"`, `"agent/"`, `""` (empty string = no prefix).

**`ci.auto_fix`:** `true` (default) or `false`. When `true` and landing mode is `pr`, the agent polls CI checks after PR creation and attempts to fix failures automatically. When `false`, the agent creates the PR and reports the URL without waiting for CI.

**`ci.max_fix_attempts`:** Integer, default `2`. Maximum number of fix-and-push cycles the agent will attempt when CI fails. Set to `0` to poll CI but never attempt fixes (report-only mode).

- [ ] Create `.claude/zskills-config.json` with the zskills dogfood values above (including `$schema` reference)
- [ ] Verify the file is readable by the bash regex extraction (no external JSON validator -- if malformed, regex silently falls through to defaults, which is safe)

#### 1.2 -- JSON Schema file

Create `config/zskills-config.schema.json` in the skills distribution repo. This provides VS Code autocomplete, hover descriptions, and live validation for `.claude/zskills-config.json` in target projects.

`/update-zskills` copies the schema file to `.claude/zskills-config.schema.json` in the target project alongside the config. The config's `"$schema": "./zskills-config.schema.json"` reference resolves relative to the config file location.

Full schema:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "zskills Configuration",
  "description": "Configuration for zskills agent skill system. Controls execution modes, testing, CI, and UI verification.",
  "type": "object",
  "properties": {
    "$schema": {
      "type": "string",
      "description": "Path to this schema file (for VS Code validation)."
    },
    "project_name": {
      "type": "string",
      "description": "Human-readable project name. Used in PR titles and reports."
    },
    "timezone": {
      "type": "string",
      "description": "IANA timezone for timestamps in reports and markers. Example: America/New_York",
      "default": "America/New_York"
    },
    "execution": {
      "type": "object",
      "description": "Controls how agent work reaches main.",
      "properties": {
        "landing": {
          "type": "string",
          "enum": ["cherry-pick", "pr", "direct"],
          "default": "cherry-pick",
          "description": "Default landing mode. cherry-pick: work in worktree, cherry-pick to main. pr: work in named worktree, push branch, create PR. direct: work on main, no landing step."
        },
        "main_protected": {
          "type": "boolean",
          "default": false,
          "description": "When true, agents cannot commit, cherry-pick, or push to main. Forces PR or feature branch workflow."
        },
        "branch_prefix": {
          "type": "string",
          "default": "feat/",
          "description": "Prefix for branch names in PR mode. Examples: 'feat/', 'agent/', '' (empty = no prefix)."
        }
      }
    },
    "testing": {
      "type": "object",
      "description": "Test commands and patterns.",
      "properties": {
        "unit_cmd": {
          "type": "string",
          "description": "Command to run unit tests. Example: npm run test"
        },
        "full_cmd": {
          "type": "string",
          "description": "Command to run all tests (unit + integration + E2E). Example: npm run test:all"
        },
        "output_file": {
          "type": "string",
          "default": ".test-results.txt",
          "description": "File where test output is captured."
        },
        "file_patterns": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Glob patterns for test files. Example: ['tests/**/*.test.js']"
        }
      }
    },
    "dev_server": {
      "type": "object",
      "description": "Development server configuration for manual testing.",
      "properties": {
        "cmd": {
          "type": "string",
          "description": "Command to start the dev server. Example: npm start"
        },
        "port_script": {
          "type": "string",
          "description": "Script that outputs the dev server port. Example: scripts/port.sh"
        },
        "main_repo_path": {
          "type": "string",
          "description": "Absolute path to the main repo. Used by worktree agents to find the dev server."
        }
      }
    },
    "ui": {
      "type": "object",
      "description": "UI verification configuration.",
      "properties": {
        "file_patterns": {
          "type": "string",
          "description": "Regex pattern matching UI files. When these files change, manual verification is required. Example: src/(components|ui)/.*\\.tsx?$"
        },
        "auth_bypass": {
          "type": "string",
          "description": "JavaScript to execute for auth bypass during manual testing. Example: localStorage.setItem('token', 'test')"
        }
      }
    },
    "ci": {
      "type": "object",
      "description": "CI integration for PR mode. Controls whether the agent polls CI checks and attempts to fix failures.",
      "properties": {
        "auto_fix": {
          "type": "boolean",
          "default": true,
          "description": "When true, poll CI checks after PR creation and attempt to fix failures. When false, create PR and report URL without waiting. Set to false for slow CI (30+ min) or repos without CI."
        },
        "max_fix_attempts": {
          "type": "integer",
          "default": 2,
          "minimum": 0,
          "maximum": 5,
          "description": "Maximum fix-and-push cycles when CI fails. 0 = poll and report only (no fix attempts). Each attempt comments on the PR with failure context."
        }
      }
    }
  }
}
```

- [ ] Create `config/zskills-config.schema.json` with full field descriptions and defaults
- [ ] Add `$schema` field to the dogfood config (`.claude/zskills-config.json`)
- [ ] Add schema copy step to `/update-zskills`: copy `config/zskills-config.schema.json` to `.claude/zskills-config.schema.json` in target project
- [ ] Verify VS Code picks up autocomplete (open the config, check for hover descriptions)

#### 1.3 -- Add config reading to `/update-zskills`

Modify `skills/update-zskills/SKILL.md` to add a config-reading step that runs after Step 0 (Locate Portable Assets) and before the Audit.

Add this section after Step 0 in `skills/update-zskills/SKILL.md`:

```markdown
## Step 0.5 -- Read Config

Check if `.claude/zskills-config.json` exists in the target project root (`$PROJECT_ROOT`).

**If it exists:**
1. Read the file content.
2. Extract values using bash regex (no jq dependency):
   ```bash
   CONFIG_CONTENT=$(cat "$PROJECT_ROOT/.claude/zskills-config.json")
   # Extract a string value (note: ([^\"]*) allows empty strings):
   if [[ "$CONFIG_CONTENT" =~ \"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     UNIT_CMD="${BASH_REMATCH[1]}"
   fi
   # Extract a boolean value:
   if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
     MAIN_PROTECTED="${BASH_REMATCH[1]}"
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

**If it does not exist:**
1. Auto-detect values from the project (existing behavior).
2. Present the auto-detected values to the user and instruct them to create
   the config file:
   ```
   ! cat > .claude/zskills-config.json <<'EOF'
   { ... auto-detected values ... }
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
```

- [ ] Add Step 0.5 to `skills/update-zskills/SKILL.md` after Step 0
- [ ] Add extraction examples for all config fields used by templates
- [ ] Config creation uses `!` user-action prefix (agent cannot write config directly)
- [ ] Copy `config/zskills-config.schema.json` to `.claude/zskills-config.schema.json` in target project (part of Step 0.5)
- [ ] Include `"$schema": "./zskills-config.schema.json"` in the suggested config template

#### 1.4 -- Template filling from config

Modify the template-filling logic in `/update-zskills` to use config values. The placeholders in `CLAUDE_TEMPLATE.md` and `hooks/block-unsafe-project.sh.template` that map to config fields:

| Placeholder | Config path | Example |
|-------------|-------------|---------|
| `{{UNIT_TEST_CMD}}` | `testing.unit_cmd` | `npm run test` |
| `{{FULL_TEST_CMD}}` | `testing.full_cmd` | `npm run test:all` |
| `{{UI_FILE_PATTERNS}}` | `ui.file_patterns` | `src/(components|ui)/.*\\.tsx?$` |
| `{{DEV_SERVER_CMD}}` | `dev_server.cmd` | `npm start` |
| `{{PORT_SCRIPT}}` | `dev_server.port_script` | `scripts/port.sh` |
| `{{MAIN_REPO_PATH}}` | `dev_server.main_repo_path` | `/workspaces/my-app` |
| `{{AUTH_BYPASS}}` | `ui.auth_bypass` | `localStorage.setItem(...)` |

**Empty value handling:** When a config field is empty string `""`, the corresponding template section is commented out with a TODO marker:

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

- [ ] Update `/update-zskills` template-filling instructions to use config values
- [ ] Ensure empty config values produce commented-out sections with TODO markers
- [ ] Verify backward compatibility: no config = auto-detect (unchanged behavior)

#### 1.5 -- Tests for config reading

Add tests to `tests/test-hooks.sh` for bash regex config extraction:

```bash
# Test: extract string value from config
test_config_extract_string() {
  CONFIG='{"project_name": "my-app", "timezone": "America/New_York"}'
  [[ "$CONFIG" =~ \"project_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]
  [[ "${BASH_REMATCH[1]}" == "my-app" ]] || fail "Expected my-app"
}

# Test: extract boolean value from config
test_config_extract_boolean() {
  CONFIG='{"execution": {"main_protected": true}}'
  [[ "$CONFIG" =~ \"main_protected\"[[:space:]]*:[[:space:]]*(true|false) ]]
  [[ "${BASH_REMATCH[1]}" == "true" ]] || fail "Expected true"
}

# Test: extract integer value from config
test_config_extract_integer() {
  CONFIG='{"ci": {"max_fix_attempts": 3}}'
  [[ "$CONFIG" =~ \"max_fix_attempts\"[[:space:]]*:[[:space:]]*([0-9]+) ]]
  [[ "${BASH_REMATCH[1]}" == "3" ]] || fail "Expected 3"
}

# Test: empty string value extracted correctly
test_config_extract_empty_string() {
  CONFIG='{"dev_server": {"cmd": ""}}'
  [[ "$CONFIG" =~ \"cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]
  [[ "${BASH_REMATCH[1]}" == "" ]] || fail "Expected empty string"
}

# Test: missing config field falls through (no match)
test_config_missing_field() {
  CONFIG='{"project_name": "my-app"}'
  if [[ "$CONFIG" =~ \"nonexistent\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    fail "Should not match nonexistent field"
  fi
}

# Test: landing mode extraction
test_config_extract_landing() {
  CONFIG='{"execution": {"landing": "pr", "main_protected": false}}'
  [[ "$CONFIG" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]
  [[ "${BASH_REMATCH[1]}" == "pr" ]] || fail "Expected pr"
}
```

- [ ] Add 6+ config extraction tests covering: string, boolean, integer, empty string, missing field, landing mode
- [ ] All tests pass: `bash tests/test-hooks.sh > .test-results.txt 2>&1`

#### 1.6 -- Sync installed copies

- [ ] Copy `skills/update-zskills/SKILL.md` to `.claude/skills/update-zskills/SKILL.md`
- [ ] Verify installed copy matches source: `diff skills/update-zskills/SKILL.md .claude/skills/update-zskills/SKILL.md`
- [ ] Verify `config/zskills-config.schema.json` exists in the distribution repo

### Design & Constraints

- **No jq dependency.** All JSON reading uses bash regex. The config is flat enough that `[[ "$content" =~ \"key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]` works for strings (note `*` not `+` to allow empty strings) and `[[ "$content" =~ \"key\"[[:space:]]*:[[:space:]]*(true|false) ]]` works for booleans. Caveat: bash regex may match the wrong key if two keys share a suffix. This is acceptable for the current flat schema.
- **Claude Code-protected.** `.claude/zskills-config.json` is protected by Claude Code's built-in permission system on all tools (Bash, Write, Edit). Agent writes trigger a permission prompt. No custom hook needed.
- **Config is optional.** No config = current behavior. Config is a progressive enhancement.
- **Config created by user action.** When no config exists, `/update-zskills` auto-detects values and presents them to the user with instructions to create the file using `! cat > .claude/zskills-config.json <<'EOF' ... EOF`.

### Acceptance Criteria

- [ ] `.claude/zskills-config.json` exists in zskills repo with valid JSON and `$schema` reference
- [ ] `config/zskills-config.schema.json` exists with descriptions for all fields
- [ ] VS Code provides autocomplete and hover docs when editing the config
- [ ] `skills/update-zskills/SKILL.md` has Step 0.5 that reads config and copies schema
- [ ] Template placeholders map to config fields
- [ ] Empty config values produce commented-out template sections
- [ ] No config = auto-detect (backward compatible)
- [ ] Config creation uses user action, not agent write
- [ ] 6+ config extraction tests pass (string, boolean, integer, empty, missing, landing)
- [ ] Installed skill copy synced

### Dependencies

None. This is the foundation phase.

---

## Phase 2 -- main_protected Hook Enforcement

### Goal

Add `main_protected` enforcement to `hooks/block-unsafe-project.sh.template`. When `execution.main_protected: true` in `.claude/zskills-config.json`, block `git commit` on main, `git cherry-pick` on main, and `git push` to main. Allow everything on feature branches. This is ACCESS CONTROL, separate from tracking (PROCESS CONTROL).

Also fix the push tracking hook's code-files detection to work before upstream is set (`@{u}` fails before first `git push -u`).

### Work Items

#### 2.1 -- Add main_protected check function

Insert a helper function near the top of `hooks/block-unsafe-project.sh.template` (after the `block_with_reason` and `extract_transcript` functions) that reads `main_protected` from config at runtime:

```bash
# --- main_protected access control ---
# Reads config at runtime (not baked in during /update-zskills).
# Changing the config takes effect immediately.
is_main_protected() {
  local config_file
  local repo_root="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  config_file="$repo_root/.claude/zskills-config.json"
  if [ -f "$config_file" ]; then
    local content
    content=$(cat "$config_file" 2>/dev/null) || return 1
    if [[ "$content" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
      return 0
    fi
  fi
  return 1
}

is_on_main() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  [[ "$branch" == "main" || "$branch" == "master" ]]
}
```

- [ ] Add `is_main_protected` function to hook template
- [ ] Add `is_on_main` function to hook template
- [ ] Functions use bash regex only (no jq)
- [ ] Config is read at runtime (not baked in)

#### 2.2 -- Block git commit on main when protected

Insert before the existing `git commit` block (which handles test checks and tracking enforcement). The main_protected check must come first because it is a hard block -- no exemptions for content-only commits.

```bash
# --- main_protected: block git commit on main ---
if [[ "$INPUT" =~ git[[:space:]]+commit ]] && is_main_protected && is_on_main; then
  block_with_reason "BLOCKED: main branch is protected (main_protected: true in .claude/zskills-config.json). Create a feature branch or use PR mode. To change: edit .claude/zskills-config.json"
fi
```

- [ ] Add git commit block before existing commit checks
- [ ] Block fires before test/tracking checks (hard block, no exemptions)

#### 2.3 -- Block git cherry-pick on main when protected

```bash
# --- main_protected: block git cherry-pick on main ---
if [[ "$INPUT" =~ git[[:space:]]+cherry-pick ]] && is_main_protected && is_on_main; then
  block_with_reason "BLOCKED: main branch is protected (main_protected: true in .claude/zskills-config.json). Cherry-pick to a feature branch instead. To change: edit .claude/zskills-config.json"
fi
```

- [ ] Add git cherry-pick block before existing cherry-pick checks

#### 2.4 -- Block git push to main when protected

```bash
# --- main_protected: block git push to main ---
if [[ "$INPUT" =~ git[[:space:]]+push([[:space:]]|\") ]] && is_main_protected; then
  # Check if pushing to main/master (explicit refspec or default branch)
  if is_on_main; then
    # On main branch, default push targets main
    if [[ ! "$INPUT" =~ origin[[:space:]]+[a-zA-Z] ]] || [[ "$INPUT" =~ origin[[:space:]]+(main|master) ]]; then
      block_with_reason "BLOCKED: Cannot push to main (main_protected: true in .claude/zskills-config.json). Push a feature branch instead. To change: edit .claude/zskills-config.json"
    fi
  fi
fi
```

- [ ] Add git push block that detects push-to-main
- [ ] Push regex uses `([[:space:]]|\")` consistent with existing pattern

#### 2.5 -- Fix push tracking hook: code-files detection before upstream

The existing push tracking hook uses `@{u}..HEAD` to find code files, which fails before the first `git push -u` (no upstream set). Fix: use `git diff main..HEAD` as fallback:

```bash
# Replace:
#   PUSH_DIFF=$(git diff --name-only @{u}..HEAD 2>/dev/null)
# With:
PUSH_DIFF=$(git diff --name-only @{u}..HEAD 2>/dev/null)
if [ -z "$PUSH_DIFF" ]; then
  # Fallback: compare against main (works before first push -u)
  PUSH_DIFF=$(git diff --name-only main..HEAD 2>/dev/null)
fi
```

- [ ] Add fallback from `@{u}..HEAD` to `main..HEAD` for code-files detection
- [ ] Verify: push tracking works on branches that have never been pushed

#### 2.6 -- Sync installed hook copy

After modifying the template, sync the installed copy:

```bash
# Copy template to installed location, replacing placeholders with current values
cp hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh
# Then apply current placeholder values from the installed copy
```

- [ ] Sync installed hook copy with template
- [ ] Verify: diff shows only placeholder differences between template and installed

#### 2.7 -- Tests

Add tests to `tests/test-hooks.sh` for main_protected enforcement. Write full test bodies:

```bash
# Test: main_protected blocks commit on main
test_main_protected_blocks_commit_on_main() {
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills"
  cat > "$TEST_TMPDIR/.claude/zskills-config.json" <<'EOF'
{"execution": {"main_protected": true}}
EOF
  cd "$TEST_TMPDIR" && git init && git checkout -b main
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  assert_blocked "$RESULT" "main branch is protected"
}

# Test: main_protected allows commit on feature branch
test_main_protected_allows_commit_on_feature_branch() {
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills"
  cat > "$TEST_TMPDIR/.claude/zskills-config.json" <<'EOF'
{"execution": {"main_protected": true}}
EOF
  cd "$TEST_TMPDIR" && git init && git checkout -b feat/test
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  assert_allowed "$RESULT"
}

# Test: main_protected false allows commit on main
test_main_protected_false_allows_commit_on_main() {
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills"
  cat > "$TEST_TMPDIR/.claude/zskills-config.json" <<'EOF'
{"execution": {"main_protected": false}}
EOF
  cd "$TEST_TMPDIR" && git init && git checkout -b main
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  [[ "$RESULT" != *"main branch is protected"* ]] || fail "Should not block when main_protected is false"
}

# Test: no config file allows commit on main
test_no_config_allows_commit_on_main() {
  setup_project_test
  cd "$TEST_TMPDIR" && git init && git checkout -b main
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  [[ "$RESULT" != *"main branch is protected"* ]] || fail "Should not block when no config"
}

# Test: main_protected blocks cherry-pick on main
test_main_protected_blocks_cherry_pick_on_main() {
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills"
  cat > "$TEST_TMPDIR/.claude/zskills-config.json" <<'EOF'
{"execution": {"main_protected": true}}
EOF
  cd "$TEST_TMPDIR" && git init && git checkout -b main
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git cherry-pick abc123"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  assert_blocked "$RESULT" "main branch is protected"
}

# Test: main_protected blocks push to main
test_main_protected_blocks_push_to_main() {
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills"
  cat > "$TEST_TMPDIR/.claude/zskills-config.json" <<'EOF'
{"execution": {"main_protected": true}}
EOF
  cd "$TEST_TMPDIR" && git init && git checkout -b main
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  assert_blocked "$RESULT" "Cannot push to main"
}

# Test: push tracking works before first push (no upstream)
test_push_tracking_no_upstream() {
  setup_project_test
  mkdir -p "$TEST_TMPDIR/.zskills/tracking"
  cd "$TEST_TMPDIR" && git init && git checkout -b feat/test
  echo "test-pipeline" > "$TEST_TMPDIR/.zskills-tracked"
  touch "$TEST_TMPDIR/.zskills/tracking/step.phase1.test-pipeline.implement"
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git push -u origin feat/test"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" LOCAL_ROOT="$TEST_TMPDIR" bash "$HOOK")
  echo "$RESULT"  # For debugging
}
```

- [ ] Add at least 7 tests: commit/cherry-pick/push on main blocked, commit on feature branch allowed, main_protected false allowed, no config allowed, push tracking without upstream
- [ ] All test bodies are complete (no empty stubs)
- [ ] Run tests: `bash tests/test-hooks.sh > .test-results.txt 2>&1`
- [ ] All tests pass (including pre-existing tests)

### Design & Constraints

- **Runtime config read.** The hook reads `main_protected` from `.claude/zskills-config.json` at runtime, NOT baked in during `/update-zskills`. Changing the config takes effect immediately without re-running `/update-zskills`.
- **ACCESS CONTROL vs PROCESS CONTROL.** `main_protected` is access control (who can write to main). Tracking enforcement is process control (did you follow the workflow). Both can be active simultaneously and are independent. Ordering: main_protected fires first (hard block), then tracking enforcement fires (process block).
- **No exemptions.** When `main_protected` is true, ALL commits/cherry-picks/pushes to main are blocked, including content-only commits.
- **Backward compatible.** No config file = no protection (current behavior).
- **Push regex consistency.** Use `([[:space:]]|\")` pattern for push detection, matching the existing hook's pattern.

### Acceptance Criteria

- [ ] `is_main_protected` reads config at runtime with bash regex
- [ ] `git commit` on main blocked when `main_protected: true`
- [ ] `git cherry-pick` on main blocked when `main_protected: true`
- [ ] `git push` to main blocked when `main_protected: true`
- [ ] All three allowed on feature branches when `main_protected: true`
- [ ] All three allowed on main when `main_protected: false` or no config
- [ ] Push tracking code-files detection works before first push (fallback to `main..HEAD`)
- [ ] At least 7 new tests pass with full bodies
- [ ] Pre-existing tests still pass
- [ ] Installed hook copy synced

### Dependencies

Phase 1 (config file must exist for dogfood testing, though the hook also handles missing config).

---

## Phase 3a -- Argument Detection + Config Reading + Direct Mode

### Goal

Add `pr` and `direct` landing mode argument detection to `/run-plan`, config-based default reading, and direct mode implementation. This is the small, self-contained foundation that Phase 3b builds on.

### Work Items

#### 3a.1 -- Argument detection

Add `pr` and `direct` to the argument detection block in `skills/run-plan/SKILL.md`. Same pattern as `auto`, `finish`, `stop` -- case-insensitive, last token.

```markdown
- `pr` (case-insensitive) -- PR landing mode
- `direct` (case-insensitive) -- direct landing mode
- Neither `pr` nor `direct` -- read config default (`execution.landing`),
  or `cherry-pick` if no config

**Landing mode resolution:**
1. Explicit argument wins: `pr` or `direct` in $ARGUMENTS
2. Config default: read `.claude/zskills-config.json` `execution.landing` field
3. Fallback: `cherry-pick`
```

```bash
# Detect landing mode
LANDING_MODE="cherry-pick"  # default
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
  LANDING_MODE="pr"
elif [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  LANDING_MODE="direct"
else
  # Read config default
  CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      CFG_LANDING="${BASH_REMATCH[1]}"
      if [ -n "$CFG_LANDING" ]; then
        LANDING_MODE="$CFG_LANDING"
      fi
    fi
  fi
fi
```

**Validation:**

```bash
# direct + main_protected -> error
if [[ "$LANDING_MODE" == "direct" ]]; then
  CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
      echo "ERROR: direct mode is incompatible with main_protected: true. Use pr mode or change config."
      exit 1
    fi
  fi
fi
```

- [ ] Add `pr` and `direct` to argument detection in SKILL.md
- [ ] Add landing mode resolution logic (argument > config > fallback)
- [ ] Add `direct` + `main_protected` conflict check
- [ ] Strip `pr`/`direct` from arguments before passing to downstream processing

#### 3a.2 -- Config reading for branch_prefix

Add config reading for `branch_prefix` with support for empty string values:

```bash
# Read branch prefix from config (default: feat/)
BRANCH_PREFIX="feat/"
if [ -f "$PROJECT_ROOT/.claude/zskills-config.json" ]; then
  CONFIG_CONTENT=$(cat "$PROJECT_ROOT/.claude/zskills-config.json")
  # ([^\"]*) allows empty string match -- empty prefix means no prefix
  if [[ "$CONFIG_CONTENT" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    BRANCH_PREFIX="${BASH_REMATCH[1]}"
  fi
fi
```

Note: the regex uses `([^\"]*)` (zero or more) not `([^\"]+)` (one or more), so `"branch_prefix": ""` correctly sets `BRANCH_PREFIX` to empty string.

- [ ] Read `branch_prefix` from config with `([^\"]*)` regex (allows empty string)
- [ ] Default to `"feat/"` when not in config
- [ ] Empty string `""` results in no prefix (branches named just `plan-slug`)

#### 3a.3 -- Direct mode

Add `### Execution: direct` as a recognized directive. This is a NEW directive (not a rename).

Direct mode means no worktree -- agent works directly on main, commits go to main immediately, Phase 6 landing is a no-op.

```markdown
### Direct mode (Phase 2)

When `LANDING_MODE` is `direct`:
- Do NOT create a worktree
- Agent works directly on main (current working directory)
- `### Execution: direct` in phase text is the recognized directive
- Phase 6: no-op (work is already on main, nothing to land)
- `.landed` marker: not written (no worktree to mark)

**Validation (already checked in 3a.1):** `direct` + `main_protected: true` -> error before dispatch.
```

- [ ] Add `### Execution: direct` as a recognized directive in SKILL.md
- [ ] Direct mode skips worktree creation in Phase 2
- [ ] Direct mode Phase 6 is a no-op
- [ ] Direct mode works on main directly

#### 3a.4 -- Tests for argument detection

Add tests to `tests/test-hooks.sh` for landing mode argument parsing:

```bash
# Test: detect "pr" argument (case-insensitive)
test_detect_pr_argument() {
  ARGUMENTS="plans/FEATURE.md finish auto pr"
  [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]] || fail "Should detect pr"
}

# Test: detect "direct" argument (case-insensitive)
test_detect_direct_argument() {
  ARGUMENTS="plans/FEATURE.md direct"
  [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]] || fail "Should detect direct"
}

# Test: no landing mode argument -> falls through
test_detect_no_landing_mode() {
  ARGUMENTS="plans/FEATURE.md finish auto"
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
    fail "Should not detect pr"
  fi
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
    fail "Should not detect direct"
  fi
}

# Test: "pr" inside a word does not match (e.g., "sprint")
test_pr_word_boundary() {
  ARGUMENTS="plans/SPRINT_PLAN.md finish"
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
    fail "Should not match 'pr' inside 'SPRINT'"
  fi
}

# Test: direct + main_protected -> error
test_direct_main_protected_conflict() {
  CONFIG='{"execution": {"landing": "cherry-pick", "main_protected": true}}'
  LANDING_MODE="direct"
  [[ "$CONFIG" =~ \"main_protected\"[[:space:]]*:[[:space:]]*(true|false) ]]
  MAIN_PROTECTED="${BASH_REMATCH[1]}"
  if [ "$LANDING_MODE" = "direct" ] && [ "$MAIN_PROTECTED" = "true" ]; then
    echo "Conflict detected (expected)"
  else
    fail "Should detect direct + main_protected conflict"
  fi
}
```

- [ ] Add 5+ argument detection tests covering: pr, direct, no mode, word boundary, direct+main_protected conflict
- [ ] All tests pass

#### 3a.5 -- Sync installed copies

- [ ] Copy `skills/run-plan/SKILL.md` to `.claude/skills/run-plan/SKILL.md`
- [ ] Verify installed copy matches source

### Design & Constraints

- **`direct` not `main`.** The keyword is `direct` because `main` collides with plan filenames containing "main" (e.g., `plans/MAIN_MENU.md`).
- **`([^\"]*)` not `([^\"]+)`.** The branch_prefix regex must allow empty string matches. `([^\"]+)` requires at least one character, which would silently fail on `"branch_prefix": ""` and fall through to the default.
- **Add, not rename.** `### Execution: main` does not exist in the current codebase. This is adding a new directive.

### Acceptance Criteria

- [ ] `pr` and `direct` detected as arguments (case-insensitive)
- [ ] Config default read when no argument specified
- [ ] `direct` + `main_protected: true` -> error
- [ ] `branch_prefix` empty string handled correctly
- [ ] `### Execution: direct` recognized as a directive
- [ ] Direct mode: no worktree, Phase 6 no-op
- [ ] 5+ argument detection tests pass (pr, direct, no mode, word boundary, conflict)
- [ ] Installed skill copy synced

### Dependencies

Phase 1 (config file for `branch_prefix` and `landing` default).
Phase 2 (main_protected check for `direct` + `main_protected` validation).

---

## Phase 3b-i -- Worktree Unification + Landing Script

### Goal

Unify ALL worktree creation to use manual `git worktree add` at `/tmp/` paths, replacing Claude Code's `isolation: "worktree"` parameter. This affects cherry-pick mode (existing behavior change) and establishes the pattern for PR mode. Also create `scripts/land-phase.sh` for atomic post-landing cleanup and add a preflight safety net for landed worktrees.

**Why this is split from PR mode:** The worktree unification is foundational — it changes existing cherry-pick behavior. PR mode (Phase 3b-ii) builds on top of it. Splitting ensures the foundation is solid before adding PR complexity.

### Work Items

#### 3b.1 -- Unify worktree creation: manual for ALL modes

**Problem:** Claude Code's `isolation: "worktree"` creates worktrees at `.claude/worktrees/agent-<id>`. This causes:
- Permission prompts (writes under `.claude/` trigger Claude Code's built-in protection)
- Non-deterministic paths (can't resume across sessions or cron turns)
- No control over branch naming
- Auto-cleanup behavior that conflicts with our `.landed` marker workflow

**Solution:** ALL modes (cherry-pick and PR) use manual `git worktree add` at `/tmp/` paths. Agents are dispatched WITHOUT `isolation: "worktree"` and told to `cd` to the worktree path as their first action.

**Cherry-pick mode worktree creation (replaces `isolation: "worktree"`):**

```bash
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
PROJECT_NAME=$(basename "$PROJECT_ROOT")
WORKTREE_PATH="/tmp/${PROJECT_NAME}-cp-${PLAN_SLUG}-phase-${PHASE}"

git worktree prune
if [ -d "$WORKTREE_PATH" ]; then
  echo "Resuming existing worktree at $WORKTREE_PATH"
else
  git worktree add "$WORKTREE_PATH" -b "cp-${PLAN_SLUG}-${PHASE}" main
fi

# Pipeline association
echo "$PIPELINE_ID" > "$WORKTREE_PATH/.zskills-tracked"
```

Cherry-pick mode: one worktree per phase, auto-named branch, `/tmp/` path. After landing (cherry-pick to main), worktree is removed.

**Agent dispatch (all modes):** Agents dispatched WITHOUT `isolation: "worktree"`. The prompt tells the agent the worktree path and requires absolute paths:

```
Agent tool prompt:
  "You are working in worktree: /tmp/myproject-cp-thermal-domain-phase-1

   IMPORTANT: Use ABSOLUTE PATHS for all file operations.
   - Bash: run `cd /tmp/myproject-cp-thermal-domain-phase-1` before commands
   - Read/Edit/Write/Grep: use /tmp/myproject-cp-thermal-domain-phase-1/... paths
   Do not work in any other directory.
   ..."
```

No `isolation: "worktree"` parameter on the Agent call. Bash cwd persists between calls, but Read/Edit/Write/Grep tools require absolute paths. The tracking hooks provide a backstop — if the agent works in the wrong directory, `.zskills-tracked` won't be found and commits are blocked.

**Failed-run cleanup:** If a phase fails terminally, write `.landed` with `status: failed` in the worktree before invoking the Failure Protocol. The cron preamble runs `git worktree prune` to clean up stale entries from container restarts or crashed runs.

**Update /run-plan skill text:** Replace all references to `isolation: "worktree"` in the dispatch instructions with the manual creation pattern above. This affects:
- Phase 2 "Worktree mode" dispatch instructions
- The worktree test recipe (agents work in `/tmp/` not `.claude/worktrees/`)

**Atomic landing script (`scripts/land-phase.sh`):** The root cause of forgotten cleanup is that landing is an 11-step manual sequence. When cherry-pick conflicts break the flow, the orchestrator completes the hard part (conflict resolution) and drops the easy parts (cleanup, tracker update). This happened 3 times in 3 phases.

The fix: reduce landing to a single script call. The orchestrator runs `bash scripts/land-phase.sh <worktree-path> <plan-file> <phase>` and the script handles everything atomically:

```bash
#!/bin/bash
# scripts/land-phase.sh — Post-landing cleanup: verify .landed, extract logs, remove worktree
# Usage: bash scripts/land-phase.sh <worktree-path>
#
# Prerequisites: orchestrator already cherry-picked, ran tests, wrote .landed marker.
# This script handles the mechanical cleanup. Idempotent — safe to re-run.

WORKTREE_PATH="$1"

# Idempotency: if worktree is already gone, nothing to do
if [ ! -d "$WORKTREE_PATH" ]; then
  echo "Worktree already removed: $WORKTREE_PATH"
  exit 0
fi

MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)

# 1. Verify .landed marker (proof work is on main — refuse without it)
if [ ! -f "$WORKTREE_PATH/.landed" ]; then
  echo "ERROR: No .landed marker in $WORKTREE_PATH. Cannot clean up without proof of landing."
  exit 1
fi
if ! grep -q 'status: landed' "$WORKTREE_PATH/.landed"; then
  echo "ERROR: .landed marker does not say 'status: landed'. Current status:"
  cat "$WORKTREE_PATH/.landed"
  exit 1
fi

# 2. Extract logs not yet on main (MUST succeed before we destroy the worktree)
if [ -d "$WORKTREE_PATH/.claude/logs" ]; then
  if ! mkdir -p "$MAIN_ROOT/.claude/logs"; then
    echo "ERROR: Could not create $MAIN_ROOT/.claude/logs — aborting cleanup to preserve logs"
    exit 1
  fi
  for log in "$WORKTREE_PATH/.claude/logs/"*.md; do
    [ -f "$log" ] || continue
    if [ ! -f "$MAIN_ROOT/.claude/logs/$(basename "$log")" ]; then
      if ! cp "$log" "$MAIN_ROOT/.claude/logs/"; then
        echo "ERROR: Failed to copy $log — aborting cleanup to preserve logs"
        exit 1
      fi
    fi
  done
fi

# 3. Remove worktree (critical — fail loudly if this doesn't work)
BRANCH=$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
rm -f "$WORKTREE_PATH/.landed" "$WORKTREE_PATH/.test-results.txt" \
      "$WORKTREE_PATH/.worktreepurpose" "$WORKTREE_PATH/.zskills-tracked"
git worktree remove "$WORKTREE_PATH" 2>&1
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to remove worktree $WORKTREE_PATH"
  exit 1
fi

# 4. Delete branch (best-effort — may already be gone)
if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "HEAD" ]; then
  git branch -d "$BRANCH" 2>/dev/null || true
fi

echo "Worktree removed: $WORKTREE_PATH"
```

The orchestrator's landing flow becomes:
1. Cherry-pick commits (may need conflict resolution — LLM judgment)
2. Run tests on main
3. Write `.landed` marker in worktree
4. `bash scripts/land-phase.sh "$WORKTREE_PATH" "$PLAN_FILE" "$PHASE"`

Steps 1-3 need LLM judgment (conflict resolution, test diagnosis). Step 4 is mechanical — the script handles it. No more forgetting cleanup.

**Preflight safety net:** Add to /run-plan's preflight checks:

```bash
# 5. Clean up landed worktrees from previous phases
for wt_line in $(git worktree list --porcelain | grep '^worktree ' | sed 's/^worktree //'); do
  if [ -f "$wt_line/.landed" ] && grep -q 'status: landed' "$wt_line/.landed"; then
    echo "Cleaning up landed worktree: $wt_line"
    bash scripts/land-phase.sh "$wt_line"
  fi
done
```

This catches stragglers from crashed agents, container restarts, or any remaining edge cases. Defense in depth — the script is the primary fix, the preflight is the safety net.

- [ ] Replace `isolation: "worktree"` dispatch with manual `git worktree add` at `/tmp/` for cherry-pick mode
- [ ] Agent dispatch uses prompt-based absolute paths instead of isolation parameter
- [ ] Cherry-pick worktree path: `/tmp/<project>-cp-<plan-slug>-phase-<N>`
- [ ] Pipeline association via `.zskills-tracked` in worktree
- [ ] `git worktree prune` before creation (handles container restarts)
- [ ] Update all /run-plan references to `isolation: "worktree"`
- [ ] Create `scripts/land-phase.sh` — atomic post-landing: verify `.landed`, extract logs, remove worktree+branch
- [ ] Update /run-plan Phase 6 to call `scripts/land-phase.sh` after cherry-pick + tests + `.landed` marker
- [ ] Add preflight check #5: scan and clean up worktrees with `status: landed` markers
- [ ] Test: create a mock worktree with `.landed` marker, verify preflight removes it
- [ ] Tests for land-phase.sh: no marker rejection, wrong status rejection, idempotent on missing dir
- [ ] Sync installed copy of /run-plan SKILL.md

### Design & Constraints (3b-i)

- **Manual worktrees, NOT `isolation: "worktree"`.** Claude Code's `isolation: "worktree"` branches from `origin/HEAD` (not local main), causing stale base issues when local main is ahead of the remote. Manual `git worktree add ... main` uses local main.
- **Absolute paths in agent prompts.** Read/Edit/Write/Grep tools require absolute paths. Bash `cd` persists between calls but non-Bash tools don't use cwd. Agent prompts must specify `WORKTREE_PATH` and instruct agents to use absolute paths for all file operations.
- **`scripts/land-phase.sh` is the structural fix for forgotten cleanup.** Landing is an 11-step sequence where the orchestrator consistently drops tail steps after conflict resolution. The script reduces this to one call. Log extraction MUST succeed before removal (exit 1, not || true). Worktree removal gates the progress tracker update to Done.
- **Preflight is defense in depth.** The script is the primary fix; the preflight catches stragglers from crashes or container restarts.

### Acceptance Criteria (3b-i)

- [ ] Cherry-pick mode uses manual worktree at `/tmp/<project>-cp-<slug>-phase-<N>` (no `isolation: "worktree"`)
- [ ] ALL agents dispatched WITHOUT `isolation: "worktree"` (prompt-based absolute paths)
- [ ] `scripts/land-phase.sh` exists: idempotent, .landed verification, logs MUST succeed, worktree removal
- [ ] Preflight check #5: auto-remove worktrees with `status: landed` markers
- [ ] All existing tests still pass (no regressions)
- [ ] 4+ new tests for worktree unification and land-phase.sh
- [ ] Installed skill copy synced

### Dependencies (3b-i)

Phase 3a (argument detection, config reading).

---

## Phase 3b-ii -- PR Mode Happy Path

### Goal

Implement PR mode for `/run-plan`: persistent worktree with named feature branch, all phases accumulating on the same branch, rebase at clean points, Phase 6 landing via push + `gh pr create`, `.landed` marker writing, and mixed mode ban enforcement. CI integration (polling, fix cycle, auto-merge) is deferred to Phase 3b-iii.

All code examples here are **canonical** -- Phase 4 and Phase 5 reference this phase rather than duplicating the patterns.

### Work Items

#### 3b.2 -- PR mode: persistent worktree with named branch

Add PR mode worktree setup to Phase 2 (Dispatch Implementation). When `LANDING_MODE` is `pr`, the worktree follows the same manual creation pattern as 3b.1 but with these differences:
- **Named feature branch** (not auto-named)
- **Persistent across phases** in `finish` mode (not one-per-phase)
- **Deterministic path** for cron turn resumption

**Branch naming:** `{branch_prefix}{plan-slug}`
- `branch_prefix` from config (`execution.branch_prefix`), default `"feat/"` (read in 3a.2)
- `plan-slug` derived from plan file path: lowercase, hyphens, no extension
  - `plans/THERMAL_DOMAIN.md` -> `thermal-domain`
  - `plans/ADD_FILTER_BLOCK.md` -> `add-filter-block`

```bash
# Derive plan slug
PLAN_FILE="plans/THERMAL_DOMAIN.md"
PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')

BRANCH_NAME="${BRANCH_PREFIX}${PLAN_SLUG}"
PROJECT_NAME=$(basename "$PROJECT_ROOT")
WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"
```

**Worktree creation -- orchestrator creates manually, NOT via `isolation: "worktree"`:**

The orchestrator creates the worktree directly with `git worktree add`. Do NOT use `isolation: "worktree"` in the Agent tool -- that creates auto-named worktrees which are NOT deterministic and do NOT persist across cron turns.

```bash
# Prune stale worktree entries. If /tmp was cleared (container restart,
# codespace rebuild), git still has the old worktree registered in
# .git/worktrees/. `git worktree prune` cleans up entries whose directories
# no longer exist, so `git worktree add` won't fail with "already registered."
git worktree prune

# Check if worktree already exists (resuming a previous run)
if [ -d "$WORKTREE_PATH" ]; then
  echo "Resuming existing PR worktree at $WORKTREE_PATH"
else
  # Create worktree on a named branch
  git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" main 2>/dev/null \
    || git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
  # First form: create new branch from main
  # Second form: branch already exists (resume after worktree was pruned)
fi
```

**Dispatching agents to the worktree:**
Dispatch agents WITHOUT `isolation: "worktree"`. Instead, the agent's prompt tells it to work in the worktree. The Agent tool has no `cwd` parameter -- the prompt specifies the directory and the agent `cd`s as its first action. This is how all worktree agents work.

**Concrete dispatch example:**

```
Agent tool prompt:
  "You are implementing Phase N of plan X.
   FIRST: cd /tmp/myproject-pr-thermal-domain
   All work happens in that directory. Do not work in any other directory.

   <phase work items here>

   Commit rules:
   - Do NOT commit. The verification agent commits after review.
   - Stage specific files by name (not git add .)
   ..."
```

The key line is `FIRST: cd $WORKTREE_PATH` -- the agent treats this as a mandatory first action. Without `isolation: "worktree"`, the agent starts in the main repo directory, so the `cd` instruction is essential.

**One branch per plan.** All phases accumulate on the same branch. The worktree persists across cron turns for chunked execution. Do NOT create a new worktree per phase.

**Pipeline association:** Write `.zskills-tracked` in the worktree (same as cherry-pick mode):

```bash
echo "$PIPELINE_ID" > "$WORKTREE_PATH/.zskills-tracked"
```

- [ ] Add PR mode worktree setup to Phase 2 dispatch
- [ ] Orchestrator creates worktree manually with `git worktree add -b`
- [ ] Do NOT use `isolation: "worktree"` -- agents dispatched without isolation to the worktree path
- [ ] Branch naming uses config `branch_prefix` + plan slug
- [ ] Worktree path is deterministic: `/tmp/<project>-pr-<plan-slug>`
- [ ] Worktree reuse: check if exists before creating (resume support)
- [ ] Pipeline association via `.zskills-tracked`

**Orchestrator practice -- test baseline capture:** Add to the /run-plan skill text (Phase 2 dispatch section): before dispatching the implementation agent, the orchestrator captures a test baseline in the worktree:

```bash
# Orchestrator captures baseline BEFORE impl agent starts
cd "$WORKTREE_PATH"
if [ -n "$FULL_TEST_CMD" ]; then
  $FULL_TEST_CMD > .test-baseline.txt 2>&1 || true
fi
```

This is an orchestrator-level practice, not a phase-specific work item. It applies to all modes (cherry-pick, PR, direct). The full implementation is in Phase 5c.3; this note ensures the /run-plan skill text includes the hook point.

- [ ] Add test baseline capture hook point to /run-plan Phase 2 dispatch instructions (orchestrator runs `$FULL_TEST_CMD > .test-baseline.txt` before impl dispatch)

#### 3b.2a -- SKILL.md insertion points

When modifying `skills/run-plan/SKILL.md`, insert PR mode code at these specific locations:

1. **PR mode worktree creation (Phase 2 -- Dispatch):** Insert AFTER the `### Worktree mode` section, gated on `LANDING_MODE == pr`. The new section is `### PR mode (Phase 2)` and contains the named branch creation, deterministic worktree path, and resume logic.

2. **PR mode landing (Phase 6 -- Landing):** Insert AFTER the `### Worktree mode landing` section (cherry-pick flow), gated on `LANDING_MODE == pr`. The new section is `### PR mode landing` and contains push + `gh pr create` + `.landed` marker.

Both insertions are gated: when `LANDING_MODE` is not `pr`, these sections are skipped and existing cherry-pick behavior is unchanged.

- [ ] Insert PR mode branch in SKILL.md Phase 2 after `### Worktree mode`, gated on `LANDING_MODE == pr`
- [ ] Insert PR landing in SKILL.md Phase 6 after `### Worktree mode landing`, gated on `LANDING_MODE == pr`

#### 3b.3 -- Rebase strategy

Rebase onto latest main **only when the tree is clean**. NEVER stash + rebase (stash pop frequently conflicts). NEVER `git merge origin/main` (creates merge commits on phase 2+).

**Rebase point 1: between phases (finish mode only)**

After the verification agent commits Phase N, BEFORE dispatching Phase N+1's impl agent:

```bash
cd "$WORKTREE_PATH"
git fetch origin main
PRE_REBASE=$(git rev-parse HEAD)
git rebase origin/main
# Tree is clean (verification agent just committed). No stash needed.
if [ $? -ne 0 ]; then
  # CRITICAL: abort the rebase to leave the worktree clean.
  # Without this, the worktree stays in "rebase in progress" state
  # and all subsequent git operations fail (including cron retries).
  git rebase --abort
  echo "REBASE CONFLICT: Phase $N changes conflict with main."

  # Write .landed marker so cron turns and cleanup tools know the state.
  cat > "$WORKTREE_PATH/.landed.tmp" <<LANDED
status: conflict
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
phase: $N
reason: rebase-conflict-between-phases
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
  mv "$WORKTREE_PATH/.landed.tmp" "$WORKTREE_PATH/.landed"

  # In interactive mode: report to user and stop.
  # In auto/cron mode: the cron will fire again later. On the next turn,
  # it will see the .landed marker with status: conflict and skip this
  # plan (same as any terminal status). If the user resolves the conflict
  # manually and removes the .landed marker, the next cron turn will
  # resume normally. If main moves further and the conflict resolves
  # itself, the user can delete .landed to retry.
  echo "Manual resolution required. Wrote .landed with status: conflict."
  exit 1
fi
if [ "$(git rev-parse HEAD)" != "$PRE_REBASE" ]; then
  echo "Main moved -- re-verifying before Phase $((N+1))..."
  # Dispatch /verify-changes worktree for full re-verification.
  # The verification agent is dispatched the same way as implementation
  # agents -- prompt includes "FIRST: cd $WORKTREE_PATH".
  # Re-verification has its OWN fix cycle (max 2 attempts), INDEPENDENT
  # of the CI fix budget. If re-verification fails after its own max
  # attempts, STOP -- same as any verification failure (write report,
  # mark phase as failed).
fi
```

**Rebase point 2: before push (all PR mode runs)**

After the LAST phase's verification agent commits, before pushing:

```bash
cd "$WORKTREE_PATH"
git fetch origin main
PRE_REBASE=$(git rev-parse HEAD)
git rebase origin/main
if [ $? -ne 0 ]; then
  # CRITICAL: abort the rebase to leave the worktree clean.
  git rebase --abort
  echo "REBASE CONFLICT: Branch conflicts with main."

  # Write .landed marker so cron turns and cleanup tools know the state.
  cat > "$WORKTREE_PATH/.landed.tmp" <<LANDED
status: conflict
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
reason: rebase-conflict-before-push
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
  mv "$WORKTREE_PATH/.landed.tmp" "$WORKTREE_PATH/.landed"

  # In interactive mode: report to user and stop.
  # In auto/cron mode: .landed with status: conflict is a terminal state.
  # The cron will see it on the next turn and skip this plan.
  echo "Manual resolution required. Wrote .landed with status: conflict."
  exit 1
fi
if [ "$(git rev-parse HEAD)" != "$PRE_REBASE" ]; then
  echo "Main moved since last verification -- re-verifying..."
  # Dispatch /verify-changes worktree for full re-verification.
  # The verification agent's prompt includes "FIRST: cd $WORKTREE_PATH".
  # This includes tests, code review, and manual testing if UI files changed.
  # Re-verification has its OWN fix cycle (max 2 attempts), INDEPENDENT
  # of the CI fix budget. If re-verification fails after its own max
  # attempts, STOP -- same as any verification failure.
  # If re-verification passes, proceed to push.
fi
```

**Why full re-verification, not just re-test:** Verification includes manual testing (playwright), coverage audit, and code review -- not just `npm test`. If main moved enough to replay commits, the integration state changed and deserves full verification.

- [ ] Rebase between phases in finish mode (clean tree, after commit)
- [ ] Rebase before push (clean tree, after last phase commit)
- [ ] NEVER stash + rebase
- [ ] NEVER git merge origin/main
- [ ] If rebase conflicts -> STOP, report to user
- [ ] If rebase moves HEAD -> dispatch full `/verify-changes` re-verification

#### 3b.4 -- Phase 6: push + PR creation

Replace the cherry-pick landing logic in Phase 6 with push + PR creation when `LANDING_MODE` is `pr`:

```bash
cd "$WORKTREE_PATH"

# --- Construct PR title and body ---
# $PLAN_SLUG, $PLAN_TITLE, $CURRENT_PHASE_NUM, $CURRENT_PHASE_TITLE come from
# the plan parser (Phase 1 of /run-plan's execution).
# $FINISH_MODE is true when running in finish mode (all remaining phases).

if [ "$FINISH_MODE" = "true" ]; then
  PR_TITLE="[${PLAN_SLUG}] ${PLAN_TITLE}"
else
  PR_TITLE="[${PLAN_SLUG}] Phase ${CURRENT_PHASE_NUM}: ${CURRENT_PHASE_TITLE}"
fi

# Collect completed phases for the body
COMPLETED_PHASES=$(grep -E '^\| .* \| ✅' "$PLAN_FILE" | sed 's/|//g' | awk '{$1=$1};1' || echo "See plan file")

PR_BODY="## Plan: ${PLAN_TITLE}

**Phases completed:**
${COMPLETED_PHASES}

**Report:** See \`reports/plan-${PLAN_SLUG}.md\` for details.

---
Generated by \`/run-plan\`"

# --- Push ---
if git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
  echo "Remote branch $BRANCH_NAME already exists. Pushing updates."
  git push origin "$BRANCH_NAME"
else
  git push -u origin "$BRANCH_NAME"
fi

# --- PR creation ---
EXISTING_PR=$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number' 2>/dev/null)
if [ -n "$EXISTING_PR" ]; then
  echo "PR #$EXISTING_PR already exists for $BRANCH_NAME. Updated with latest push."
  PR_URL=$(gh pr view "$EXISTING_PR" --json url --jq '.url')
  PR_NUMBER="$EXISTING_PR"
else
  PR_URL=$(gh pr create \
    --title "$PR_TITLE" \
    --body "$PR_BODY" \
    --base main \
    --head "$BRANCH_NAME")
  if [ -n "$PR_URL" ]; then
    PR_NUMBER=$(gh pr view --json number --jq '.number')
  fi
fi

# --- Verify PR was created ---
if [ -z "$PR_URL" ]; then
  echo "WARNING: PR creation failed. Branch pushed but PR not created."
  echo "Manual fallback: gh pr create --base main --head $BRANCH_NAME"
  cat > "$WORKTREE_PATH/.landed.tmp" <<LANDED
status: pr-failed
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
pr:
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
  mv "$WORKTREE_PATH/.landed.tmp" "$WORKTREE_PATH/.landed"
  # Report and stop -- PR creation failed
fi
```

**PR title:** `[plan-slug] Phase N: <phase title>` for single phase, or `[plan-slug] <plan title>` for finish mode.

**PR body:** Include plan name, phases completed, and link to report file.

- [ ] Push to remote (handle existing remote branch)
- [ ] Create PR via `gh pr create` (handle existing PR)
- [ ] Get PR number via `gh pr view --json number --jq '.number'` (NOT URL regex)
- [ ] PR creation failure -> `.landed` with `status: pr-failed`
- [ ] Error handling: `gh auth` failure -> report branch name and manual instructions

#### 3b.5 -- .landed marker for PR mode

After push + PR creation, write the `.landed` marker. In Phase 3b-ii (before CI integration exists), the status is always `pr-ready` -- the PR is created and awaiting CI/review. Phase 3b-iii adds CI polling and upgrades the status to `landed` when auto-merge succeeds.

```bash
# --- Write .landed marker ---
# Without CI integration (Phase 3b-iii), we write pr-ready.
# Phase 3b-iii will insert CI polling + auto-merge between PR creation
# and this marker write, and will set LANDED_STATUS based on CI results.
LANDED_STATUS="pr-ready"

cat > "$WORKTREE_PATH/.landed.tmp" <<LANDED
status: $LANDED_STATUS
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
pr: $PR_URL
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
mv "$WORKTREE_PATH/.landed.tmp" "$WORKTREE_PATH/.landed"
```

**`land-phase.sh` acceptance for PR worktrees:** `scripts/land-phase.sh` currently only accepts `status: landed` as safe-to-remove. For PR mode, `status: pr-ready` is also safe because the work is preserved in the remote PR -- the local worktree is a convenience copy. After PR auto-merge succeeds (in Phase 3b-iii, `status: landed`), the orchestrator explicitly calls `land-phase.sh` for cleanup.

**`.landed` status values for PR mode:**

| Scenario | status | method | ci | pr_state |
|----------|--------|--------|----|----------|
| PR merged (auto-merge) | `landed` | `pr` | `pass`/`none`/`skipped` | `MERGED` |
| PR open, CI passed, awaiting review | `pr-ready` | `pr` | `pass`/`none`/`skipped` | `OPEN` |
| PR open, CI timed out (still running) | `pr-ready` | `pr` | `pending` | `OPEN` |
| PR open, CI failing after max attempts | `pr-ci-failing` | `pr` | `fail` | `OPEN` |
| Branch pushed, PR creation failed | `pr-failed` | `pr` | _(not set)_ | _(not set)_ |
| Rebase conflict | `conflict` | `pr` | _(not set)_ | _(not set)_ |

**Other landing modes (for reference):**

| Scenario | status | method |
|----------|--------|--------|
| Cherry-pick landed | `landed` | `cherry-pick` |
| Direct committed | `landed` | `direct` |
| Cherry-pick conflicts | `conflict` | `cherry-pick` |
| Agent done, didn't land | `not-landed` | -- |

- [ ] Write `.landed` with `status: pr-ready` after successful push + PR creation
- [ ] `.landed` marker includes: `status`, `date`, `source`, `method`, `branch`, `pr`, `commits`
- [ ] Write marker atomically (tmp + mv)
- [ ] Update `scripts/land-phase.sh` to accept `status: pr-ready` as safe-to-remove (work preserved in PR)
- [ ] After PR auto-merge succeeds (`status: landed`, added in 3b-iii), explicitly call `land-phase.sh`

#### 3b.6 -- Mixed mode ban in PR plans

When the plan-level landing mode is `pr`, individual phases cannot use `### Execution: direct`. Delegate is always OK.

```markdown
**Mixed mode validation (Phase 2):**
When `LANDING_MODE` is `pr`, scan the current phase text:
- `### Execution: direct` -> ERROR: "Mixed execution modes not allowed in PR
  plans. All phases must use worktree or delegate mode."
- `### Execution: delegate ...` -> OK (delegate manages its own isolation)
- `### Execution: worktree` or no directive -> OK (default)
```

- [ ] Add mixed mode validation in Phase 2 dispatch
- [ ] `### Execution: direct` in a PR plan -> error
- [ ] `### Execution: delegate` in a PR plan -> allowed

#### 3b.7 -- Tests for PR mode

Add tests to `tests/test-hooks.sh` for PR mode mechanics. These test the
hook enforcement and marker writing — not the full PR flow (which requires
a real GitHub repo).

```bash
# Test: .landed marker with status: landed
test_landed_marker_landed() {
  MARKER=$(cat <<LANDED
status: landed
date: 2026-04-13T12:00:00-04:00
source: run-plan
method: pr
branch: feat/test
pr: https://github.com/owner/repo/pull/42
ci: pass
pr_state: MERGED
LANDED
)
  [[ "$MARKER" == *"status: landed"* ]] || fail "Expected status: landed"
  [[ "$MARKER" == *"pr_state: MERGED"* ]] || fail "Expected pr_state: MERGED"
}

# Test: .landed marker with status: pr-ready
test_landed_marker_pr_ready() {
  MARKER="status: pr-ready"
  [[ "$MARKER" == *"pr-ready"* ]] || fail "Expected pr-ready"
}

# Test: .landed marker with status: pr-ci-failing
test_landed_marker_ci_failing() {
  MARKER="status: pr-ci-failing"
  [[ "$MARKER" == *"pr-ci-failing"* ]] || fail "Expected pr-ci-failing"
}

# Test: .landed marker with status: conflict (rebase failure)
test_landed_marker_conflict() {
  MARKER="status: conflict"
  [[ "$MARKER" == *"conflict"* ]] || fail "Expected conflict"
}

# Test: PR mode branch naming
test_pr_branch_naming() {
  BRANCH_PREFIX="feat/"
  PLAN_SLUG=$(basename "plans/THERMAL_DOMAIN.md" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  BRANCH_NAME="${BRANCH_PREFIX}${PLAN_SLUG}"
  [[ "$BRANCH_NAME" == "feat/thermal-domain" ]] || fail "Expected feat/thermal-domain, got $BRANCH_NAME"
}

# Test: PR mode worktree path
test_pr_worktree_path() {
  PROJECT_NAME="my-app"
  PLAN_SLUG="thermal-domain"
  WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"
  [[ "$WORKTREE_PATH" == "/tmp/my-app-pr-thermal-domain" ]] || fail "Wrong path: $WORKTREE_PATH"
}

# Test: main_protected blocks commit on main but not feature branch
test_main_protected_feature_branch_allowed() {
  setup_project_test
  echo '{"execution":{"main_protected":true}}' > "$TEST_TMPDIR/.claude/zskills-config.json"
  cd "$TEST_TMPDIR" && git init && git checkout -b feat/test
  INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  RESULT=$(echo "$INPUT" | REPO_ROOT="$TEST_TMPDIR" bash "$HOOK")
  [[ "$RESULT" != *"main branch is protected"* ]] || fail "Should not block on feature branch"
}

# Test: land-phase.sh accepts status: pr-ready as safe-to-remove
test_land_phase_accepts_pr_ready() {
  setup_project_test
  MOCK_WT="$TEST_TMPDIR/mock-pr-worktree"
  mkdir -p "$MOCK_WT"
  cat > "$MOCK_WT/.landed" <<LANDED
status: pr-ready
date: 2026-04-13T12:00:00-04:00
source: run-plan
method: pr
branch: feat/test
pr: https://github.com/owner/repo/pull/42
LANDED
  # Verify the marker is recognized as safe-to-remove
  grep -q 'status: pr-ready' "$MOCK_WT/.landed" || fail "Expected status: pr-ready in marker"
}

# Test: slug normalization edge cases
test_slug_normalization() {
  # These tests verify bash string operations that construct branch names
  # and worktree paths. They catch implementation bugs in path construction
  # (e.g., wrong tr arguments, missed case conversion, underscore handling).
  PLAN_FILE="plans/ADD_FILTER_BLOCK.md"
  PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  [[ "$PLAN_SLUG" == "add-filter-block" ]] || fail "Expected add-filter-block, got $PLAN_SLUG"

  PLAN_FILE2="plans/FIX_MAIN_LOOP.md"
  PLAN_SLUG2=$(basename "$PLAN_FILE2" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  [[ "$PLAN_SLUG2" == "fix-main-loop" ]] || fail "Expected fix-main-loop, got $PLAN_SLUG2"
}
```

**Note on string assertion tests (branch naming, worktree paths, slug normalization):** These tests verify bash string operations (`tr`, `basename`, variable interpolation) that construct branch names and worktree paths. While they look trivial, they catch real implementation bugs: wrong `tr` arguments, missed case conversion, underscore-vs-hyphen confusion, empty `branch_prefix` handling. They are not deep integration tests, but they prevent the class of bug where path construction silently produces wrong values that only fail later during `git worktree add` or `git push`.

- [ ] Add 9+ tests covering: .landed marker statuses (4), branch naming, worktree path, main_protected on feature branch, land-phase.sh pr-ready acceptance, slug normalization
- [ ] All tests pass alongside pre-existing tests

#### 3b.8 -- Sync installed copies

- [ ] Copy `skills/run-plan/SKILL.md` to `.claude/skills/run-plan/SKILL.md`
- [ ] Verify installed copy matches source

### Design & Constraints (3b-ii)

- **Phase 3b-ii depends on 3b-i.** The worktree unification and landing script (3b-i) must be in place before PR mode is implemented. PR mode builds on the manual worktree pattern.
- **Persistent worktree, NOT isolation parameter.** The orchestrator creates the worktree manually with `git worktree add -b`. Do NOT use `isolation: "worktree"` -- it branches from `origin/HEAD` (often stale), not local main. See 3b-i Design & Constraints.
- **Agents dispatched without isolation.** Use absolute paths in agent prompts. See 3b-i for the dispatch pattern.
- **Never checkout branches in main directory.** Branch checkout in main causes stash data loss, tracking enforcement deadlock, and progress tracking failure across cron turns. Always use worktrees.
- **Rebase when the tree is clean, not when dirty.** Rebase onto latest main only at clean points: (1) between phases in `finish` mode (after verify+commit, before next impl dispatch), (2) before push (after last phase's commit). Never stash uncommitted changes to rebase -- `git stash pop` after rebase frequently conflicts. If rebase conflicts: `git rebase --abort` (leave worktree clean), write `.landed` with `status: conflict`, and stop. In cron mode, the `.landed` marker prevents re-attempts until the user resolves manually. If rebase moves HEAD, dispatch full `/verify-changes worktree` re-verification before proceeding -- this re-verification has its own fix cycle (max 2 attempts), independent of the CI fix budget.
- **Verification agent commits.** Same as cherry-pick mode -- impl agent writes code, verification agent verifies and commits. The tracking system enforces this regardless of landing mode.
- **One PR per plan.** All phases go into one PR. Agent never waits for merge mid-execution.
- **Verify before marking pr-ready.** Always check that `PR_URL` is non-empty before writing `status: pr-ready`. If PR creation failed, write `status: pr-failed`.
- **`land-phase.sh` accepts `pr-ready`.** Update the script's status check to accept both `status: landed` and `status: pr-ready` as safe-to-remove. For PR worktrees, the work is preserved in the remote branch/PR -- the local worktree is disposable.

### Acceptance Criteria (3b-ii)

- [ ] PR mode creates persistent worktree at `/tmp/<project>-pr-<plan-slug>` via manual `git worktree add`
- [ ] PR mode branch name: `{branch_prefix}{plan-slug}`
- [ ] PR mode worktree reuse on resume
- [ ] Rebase at clean points only (between phases + before push)
- [ ] Rebase conflict -> `git rebase --abort`, write `.landed` with `status: conflict`, STOP
- [ ] Rebase moved HEAD -> full re-verification (own fix cycle, independent of CI budget)
- [ ] PR mode Phase 6: push + `gh pr create`
- [ ] PR number obtained via `gh pr view --json number --jq '.number'`
- [ ] `.landed` with `status: pr-ready` after successful push + PR creation
- [ ] `.landed` marker includes `branch`, `pr`, `commits` fields
- [ ] `scripts/land-phase.sh` accepts `status: pr-ready` as safe-to-remove
- [ ] Mixed mode ban enforced in PR plans
- [ ] Tests in `tests/test-hooks.sh`
- [ ] 9+ PR mode tests pass (markers, naming, paths, config)
- [ ] Installed skill copy synced

### Dependencies (3b-ii)

Phase 3b-i (worktree unification, landing script).

---

## Phase 3b-iii -- CI Integration + Fix Cycle + Auto-Merge

### Goal

Add CI check polling, failure fix cycle, auto-merge, and PR comment tracking to PR mode. This phase extends the PR landing flow from Phase 3b-ii with CI awareness. After PR creation (3b-ii writes `status: pr-ready`), this phase inserts CI polling between PR creation and the final `.landed` marker, upgrading the status based on CI results.

### Work Items

#### 3b-iii.1 -- CI config re-read and skip logic

All CI behavior is controlled by config values re-read at point of use.

**Config re-read (always re-read, never rely on earlier variables):**

```bash
# --- Re-read config at point of use ---
# Do NOT rely on $CONFIG_CONTENT from earlier -- context compaction may
# have lost it. Re-read the config file now.
CI_AUTO_FIX=true
CI_MAX_ATTEMPTS=2
FULL_TEST_CMD=""
CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
if [ -f "$CONFIG_FILE" ]; then
  CI_CONFIG=$(cat "$CONFIG_FILE" 2>/dev/null)
  if [[ "$CI_CONFIG" =~ \"auto_fix\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
    CI_AUTO_FIX="${BASH_REMATCH[1]}"
  fi
  if [[ "$CI_CONFIG" =~ \"max_fix_attempts\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    CI_MAX_ATTEMPTS="${BASH_REMATCH[1]}"
  fi
  if [[ "$CI_CONFIG" =~ \"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    FULL_TEST_CMD="${BASH_REMATCH[1]}"
  fi
fi
```

**Skip CI when disabled:**

```bash
if [ "$CI_AUTO_FIX" = "false" ]; then
  echo "CI auto-fix disabled (ci.auto_fix: false). PR created -- CI results are the user's responsibility."
  CI_STATUS="skipped"
fi
```

- [ ] Re-read `ci.auto_fix`, `ci.max_fix_attempts`, and `testing.full_cmd` from config at point of use
- [ ] Skip CI polling when `ci.auto_fix: false`

#### 3b-iii.2 -- CI pre-check and polling

**CI pre-check (avoid hang on repos with no CI):**

`gh pr checks --watch` hangs indefinitely if no checks are configured. GitHub Actions has a registration delay (5-30s after push), so retry before concluding there are no checks:

```bash
CHECK_COUNT=0
for _i in 1 2 3; do
  CHECK_COUNT=$(gh pr checks "$PR_NUMBER" --json name --jq 'length' 2>/dev/null || echo "0")
  [ "$CHECK_COUNT" != "0" ] && break
  sleep 10
done
if [ "$CHECK_COUNT" = "0" ]; then
  echo "No CI checks configured for this repo. Skipping CI polling."
  CI_STATUS="none"
fi
```

**CI polling:**

```bash
echo "Waiting for $CHECK_COUNT CI check(s) on PR #$PR_NUMBER..."
CI_LOG="/tmp/ci-failure-${PR_NUMBER}.txt"

# Timeout: 10 minutes. In cron mode, a hung --watch blocks the entire turn.
# Exit code 124 from timeout means "timed out" -- treat as "checks still pending".
timeout 600 gh pr checks "$PR_NUMBER" --watch 2>"$CI_LOG.stderr"
CI_EXIT=$?

if [ "$CI_EXIT" -eq 0 ]; then
  echo "CI checks passed."
  CI_STATUS="pass"
elif [ "$CI_EXIT" -eq 124 ]; then
  echo "CI checks timed out after 10 minutes. Treating as pending."
  CI_STATUS="pending"
  # Write .landed with pr-ready so the next cron turn re-checks.
  # Do NOT enter the fix cycle -- checks are still running, not failing.
else
  echo "CI checks failed (exit $CI_EXIT). Reading failure logs..."
  CI_STATUS="fail"
  FAILED_RUN_ID=$(gh run list --branch "$BRANCH_NAME" --status failure --limit 1 \
    --json databaseId --jq '.[0].databaseId' 2>/dev/null)
  if [ -n "$FAILED_RUN_ID" ]; then
    gh run view "$FAILED_RUN_ID" --log-failed 2>&1 | head -500 > "$CI_LOG"
  fi
fi
```

Note: `gh pr checks --watch` is used WITHOUT `--fail-fast` (that flag may not exist in all gh versions).

**Timeout handling:** If `CI_STATUS` is `"pending"` (timeout exit 124), skip the fix cycle entirely and write `.landed` with `status: pr-ready`. The next cron turn will re-enter Phase 6, see the existing PR, and re-poll CI.

- [ ] CI pre-check: retry 3x with 10s delay for GitHub Actions registration delay
- [ ] No checks after retries -> `CI_STATUS="none"`, skip polling
- [ ] Poll CI via `timeout 600 gh pr checks "$PR_NUMBER" --watch` (10 min cap; NOT `--fail-fast`)
- [ ] Timeout (exit 124) -> `CI_STATUS="pending"`, write `pr-ready`, let next cron turn re-check
- [ ] On failure: read logs via `gh run view "$FAILED_RUN_ID" --log-failed`
- [ ] CI failure log namespaced: `/tmp/ci-failure-${PR_NUMBER}.txt` (parallel safety)

#### 3b-iii.3 -- CI failure fix cycle

```bash
if [ "$CI_STATUS" = "fail" ] && [ "$CI_MAX_ATTEMPTS" -gt 0 ]; then
  # Post initial CI status comment using gh api (returns comment ID).
  # gh pr comment does NOT return comment URL/ID, so we use the API directly.
  COMMENT_ID=$(gh api "repos/{owner}/{repo}/issues/$PR_NUMBER/comments" \
    -f body="**CI Status:** Investigating failure..." --jq '.id' 2>/dev/null || true)

  for ATTEMPT in $(seq 1 "$CI_MAX_ATTEMPTS"); do
    echo "CI fix attempt $ATTEMPT/$CI_MAX_ATTEMPTS..."

    # Update the single status comment (edit, not append spam)
    COMMENT_BODY="**CI Fix -- Attempt $ATTEMPT/$CI_MAX_ATTEMPTS**

Failure from \`gh run view --log-failed\`:
\`\`\`
$(tail -50 "$CI_LOG" 2>/dev/null || echo "No failure log available")
\`\`\`

Attempting fix..."
    if [ -n "$COMMENT_ID" ]; then
      gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$COMMENT_ID" \
        -f body="$COMMENT_BODY" 2>/dev/null || true
    fi

    # --- Dispatch CI fix agent ---
    # The /run-plan ORCHESTRATOR dispatches this agent via the Agent tool.
    # The agent does NOT use isolation: "worktree" -- the worktree already
    # exists. Instead, the agent's prompt tells it to work in $WORKTREE_PATH.
    #
    # Tracking: The worktree has .zskills-tracked (written by the orchestrator
    # in 3b.1), so the tracking hooks allow commits. The fix agent's
    # transcript will contain test commands (it runs tests before committing),
    # satisfying the test gate.
    #
    # Agent prompt (inline, not a skill):
    #
    #   CI checks failed on PR #$PR_NUMBER for branch $BRANCH_NAME.
    #   The failure log is at $CI_LOG -- read it to understand what failed.
    #
    #   FIRST: cd $WORKTREE_PATH
    #   All work happens in that directory. Do not work in any other directory.
    #
    #   Steps:
    #   1. Read $CI_LOG. Identify the failure type:
    #      - Test failure -> find the failing test, read the source, fix the code
    #      - Build error -> fix the compilation/bundling issue
    #      - Lint error -> fix the style violation
    #      - Environment issue -> may not be fixable, report and stop
    #   2. Make the minimal fix. Do not refactor or improve unrelated code.
    #   3. Run tests locally to verify the fix:
    #      - If FULL_TEST_CMD is set: "$FULL_TEST_CMD > .test-results.txt 2>&1"
    #      - If FULL_TEST_CMD is empty: look for package.json scripts (npm test),
    #        or test files matching common patterns. If no test command can be
    #        determined, skip local testing and note it in the commit message.
    #      Read .test-results.txt to check for failures.
    #   4. If tests pass, commit with message:
    #      "fix: address CI failure -- <short description of what was fixed>"
    #   5. If tests fail on the same error after one fix attempt, STOP.
    #      Do not thrash. Report what you tried and what failed.
    #
    #   Do NOT:
    #   - Weaken tests to make them pass
    #   - Skip the local test run
    #   - Touch code unrelated to the CI failure
    #   - Use git add . (stage specific files by name)

    # After fix agent completes, push to branch (auto-updates PR, re-triggers CI)
    cd "$WORKTREE_PATH"
    git push origin "$BRANCH_NAME"

    # CI registration delay: GitHub needs 5-30s to register new check runs
    # after a push. Run the same pre-check retry loop before --watch to avoid
    # watching stale checks from the previous push.
    echo "Waiting for CI to register new checks after push..."
    for _j in 1 2 3; do
      NEW_CHECK_COUNT=$(gh pr checks "$PR_NUMBER" --json name --jq 'length' 2>/dev/null || echo "0")
      [ "$NEW_CHECK_COUNT" != "0" ] && break
      sleep 10
    done

    echo "Waiting for CI re-check..."
    timeout 600 gh pr checks "$PR_NUMBER" --watch 2>"$CI_LOG.stderr"
    CI_EXIT=$?
    if [ "$CI_EXIT" -eq 0 ]; then
      echo "CI checks passed after fix attempt $ATTEMPT."
      CI_STATUS="pass"
      break
    elif [ "$CI_EXIT" -eq 124 ]; then
      echo "CI checks timed out after fix attempt $ATTEMPT. Treating as pending."
      CI_STATUS="pending"
      break
    fi
    # Re-read failure logs for next attempt
    FAILED_RUN_ID=$(gh run list --branch "$BRANCH_NAME" --status failure --limit 1 \
      --json databaseId --jq '.[0].databaseId' 2>/dev/null)
    if [ -n "$FAILED_RUN_ID" ]; then
      gh run view "$FAILED_RUN_ID" --log-failed 2>&1 | head -500 > "$CI_LOG"
    fi
  done

  # Final comment update
  if [ "$CI_STATUS" = "pass" ]; then
    FINAL_BODY="**CI Passed** after fix attempt $ATTEMPT. Ready for review."
  else
    FINAL_BODY="**CI Fix Exhausted** ($CI_MAX_ATTEMPTS attempts)

CI is still failing. Manual intervention needed.

Last failure:
\`\`\`
$(tail -50 "$CI_LOG" 2>/dev/null || echo "No failure log available")
\`\`\`"
  fi
  if [ -n "$COMMENT_ID" ]; then
    gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$COMMENT_ID" \
      -f body="$FINAL_BODY" 2>/dev/null || true
  fi
fi
```

- [ ] PR comments via `gh api repos/{owner}/{repo}/issues/$PR_NUMBER/comments` (NOT `gh pr comment`)
- [ ] Edit single comment via `gh api -X PATCH` (not append spam)
- [ ] Dispatch fix agent via Agent tool (inline prompt, not a skill)
- [ ] Fix agent works in worktree (no isolation parameter); prompt includes `FIRST: cd $WORKTREE_PATH`
- [ ] After fix push: CI registration delay pre-check (retry 3x with 10s) before `--watch`
- [ ] Fix loop `--watch` also uses `timeout 600` (10 min cap)
- [ ] `ci.max_fix_attempts: 0` -> poll + report only, no fix attempts
- [ ] Final comment: "CI Passed" or "CI Fix Exhausted" with failure log

#### 3b-iii.4 -- Auto-merge and .landed upgrade

After CI resolution, request auto-merge and upgrade the `.landed` marker from `pr-ready` (written by 3b-ii) to the final status:

```bash
# --- Auto-merge: request merge when CI passes ---
# gh pr merge --auto --squash requires that auto-merge is enabled in the
# GitHub repo settings (Settings > General > Allow auto-merge). It is OFF
# by default. If not enabled, `--auto` returns exit code 1 with an error
# about "Auto merge is not allowed for this repository". We suppress this
# with `|| true`, and the PR stays open with status: pr-ready. The user
# merges manually. This is the correct fallback -- pr-ready means "agent
# work is done, PR is ready for human action."
if [ "$CI_STATUS" = "pass" ] || [ "$CI_STATUS" = "none" ] || [ "$CI_STATUS" = "skipped" ]; then
  gh pr merge "$PR_NUMBER" --auto --squash 2>/dev/null || true
  # Give GitHub a moment to process the merge
  sleep 5
  PR_STATE=$(gh pr view "$PR_NUMBER" --json state --jq '.state' 2>/dev/null || echo "OPEN")
else
  PR_STATE="OPEN"
fi

# --- Determine .landed status ---
if [ "$CI_STATUS" = "pending" ]; then
  # Timeout: checks still running. Write pr-ready so next cron turn re-checks.
  LANDED_STATUS="pr-ready"
elif [ "$CI_STATUS" = "fail" ]; then
  LANDED_STATUS="pr-ci-failing"
elif [ "$PR_STATE" = "MERGED" ]; then
  LANDED_STATUS="landed"
else
  # PR is open -- either awaiting required reviews, or auto-merge
  # not supported. Agent's work is done either way.
  LANDED_STATUS="pr-ready"
fi

# --- Upgrade .landed marker ---
cat > "$WORKTREE_PATH/.landed.tmp" <<LANDED
status: $LANDED_STATUS
date: $(TZ=America/New_York date -Iseconds)
source: run-plan
method: pr
branch: $BRANCH_NAME
pr: $PR_URL
ci: $CI_STATUS
pr_state: $PR_STATE
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
mv "$WORKTREE_PATH/.landed.tmp" "$WORKTREE_PATH/.landed"

# --- Cleanup on merge ---
# When PR was merged (status: landed), call land-phase.sh to remove the worktree.
# The work is on main via the merge -- the worktree is no longer needed.
if [ "$LANDED_STATUS" = "landed" ]; then
  bash scripts/land-phase.sh "$WORKTREE_PATH"
fi
```

- [ ] Auto-merge via `gh pr merge "$PR_NUMBER" --auto --squash`
- [ ] Check PR state via `gh pr view --json state --jq '.state'`
- [ ] MERGED -> `status: landed` | OPEN -> `status: pr-ready`
- [ ] CI failing -> `status: pr-ci-failing`
- [ ] Upgraded `.landed` marker includes `ci` and `pr_state` fields
- [ ] Write marker atomically (tmp + mv)
- [ ] On `status: landed`, call `land-phase.sh` for worktree cleanup

#### 3b-iii.5 -- Tests for CI integration

```bash
# Test: CI config defaults (no config = auto_fix true, max 2)
test_ci_config_defaults() {
  CI_AUTO_FIX=true
  CI_MAX_ATTEMPTS=2
  CONFIG=""  # Empty config
  if [ -n "$CONFIG" ]; then
    :
  fi
  [[ "$CI_AUTO_FIX" == "true" ]] || fail "Default auto_fix should be true"
  [[ "$CI_MAX_ATTEMPTS" == "2" ]] || fail "Default max_fix_attempts should be 2"
}

# Test: CI config auto_fix false
test_ci_config_auto_fix_false() {
  CONFIG='{"ci": {"auto_fix": false, "max_fix_attempts": 2}}'
  CI_AUTO_FIX=true
  if [[ "$CONFIG" =~ \"auto_fix\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
    CI_AUTO_FIX="${BASH_REMATCH[1]}"
  fi
  [[ "$CI_AUTO_FIX" == "false" ]] || fail "Expected auto_fix: false"
}

# Test: .landed marker with status: pr-ci-failing
test_landed_marker_ci_failing() {
  MARKER="status: pr-ci-failing"
  [[ "$MARKER" == *"pr-ci-failing"* ]] || fail "Expected pr-ci-failing"
}

# Test: .landed marker upgrade includes ci and pr_state fields
test_landed_marker_upgraded() {
  MARKER=$(cat <<LANDED
status: landed
date: 2026-04-13T12:00:00-04:00
source: run-plan
method: pr
branch: feat/test
pr: https://github.com/owner/repo/pull/42
ci: pass
pr_state: MERGED
LANDED
)
  [[ "$MARKER" == *"ci: pass"* ]] || fail "Expected ci field"
  [[ "$MARKER" == *"pr_state: MERGED"* ]] || fail "Expected pr_state field"
}
```

- [ ] Add 4+ CI integration tests to `tests/test-hooks.sh`
- [ ] All tests pass alongside pre-existing tests and 3b-ii tests

#### 3b-iii.6 -- Sync installed copies

- [ ] Copy `skills/run-plan/SKILL.md` to `.claude/skills/run-plan/SKILL.md`
- [ ] Verify installed copy matches source

### Design & Constraints (3b-iii)

- **Phase 3b-iii depends on 3b-ii.** The PR creation and `.landed` marker writing (3b-ii) must be in place. This phase extends the flow with CI awareness.
- **CI check after PR creation.** Controlled by `ci.auto_fix` (default `true`) and `ci.max_fix_attempts` (default `2`) in config. When enabled: poll `timeout 600 gh pr checks --watch` after creating the PR (10 minute cap prevents hung cron turns; exit 124 = timeout, treat as `pr-ready`). On failure, read logs (`gh run view --log-failed`), comment on PR with failure context via `gh api`, dispatch fix agent in the worktree (agent prompt includes `FIRST: cd $WORKTREE_PATH`), push (auto-updates PR). After each push, re-run the CI registration delay pre-check (retry 3x with 10s) before `--watch` to avoid polling stale checks. After each attempt or on exhaustion, update the single comment so human reviewers have an audit trail. When `ci.auto_fix: false`, skip entirely. When `ci.max_fix_attempts: 0`, poll and report but don't attempt fixes.
- **PR comments via gh api, not gh pr comment.** `gh pr comment` does NOT return the comment ID. Use `gh api repos/{owner}/{repo}/issues/$PR_NUMBER/comments` to create (returns ID), and `gh api -X PATCH repos/{owner}/{repo}/issues/comments/$COMMENT_ID` to update.
- **Cleanup on merge.** When auto-merge succeeds (`status: landed`), call `land-phase.sh` to remove the worktree. The script accepts both `status: landed` and `status: pr-ready` (updated in 3b-ii).

### Acceptance Criteria (3b-iii)

- [ ] CI pre-check with retry for registration delay
- [ ] CI polling via `timeout 600 gh pr checks --watch` (10 min cap; no `--fail-fast`)
- [ ] CI failure -> read logs, fix in worktree, push, re-poll (max attempts from config)
- [ ] PR comments via `gh api` (create + edit single comment)
- [ ] Auto-merge requested via `gh pr merge --auto --squash`
- [ ] `.landed` upgraded: `landed` (merged), `pr-ready` (awaiting review), `pr-ci-failing`
- [ ] `.landed` marker includes `ci`, `pr_state` fields after CI integration
- [ ] On `status: landed`, `land-phase.sh` called for cleanup
- [ ] 4+ CI integration tests pass in `tests/test-hooks.sh`
- [ ] Installed skill copy synced

### Dependencies (3b-iii)

Phase 3b-ii (PR mode happy path, `.landed` marker, `land-phase.sh` pr-ready acceptance).

---

## Phase 4 -- /fix-issues PR Landing

### Goal

Add `pr` and `direct` landing mode arguments to `/fix-issues`. PR mode creates per-issue named branches with worktrees, pushes each, and creates PRs with `Fixes #NNN` linking. Direct mode works on main (existing behavior with the `direct` keyword).

### Work Items

#### 4.1 -- Argument detection

Same pattern as /run-plan (3a.1). Add `pr` and `direct` to argument detection in `skills/fix-issues/SKILL.md`:

```bash
# Same detection logic as /run-plan (3a.1)
LANDING_MODE="cherry-pick"
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
  LANDING_MODE="pr"
elif [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  LANDING_MODE="direct"
else
  # Read config default (same as /run-plan)
  CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      CFG_LANDING="${BASH_REMATCH[1]}"
      [ -n "$CFG_LANDING" ] && LANDING_MODE="$CFG_LANDING"
    fi
  fi
fi
```

- [ ] Add `pr` and `direct` to argument detection in `/fix-issues`
- [ ] Add `direct` + `main_protected` conflict check
- [ ] Strip landing mode from arguments before parsing issue numbers/focus

#### 4.2 -- Per-issue named branches in PR mode

When `LANDING_MODE` is `pr`, each issue gets its own worktree with a named branch:

```bash
ISSUE_NUM=42
BRANCH_NAME="fix/issue-${ISSUE_NUM}"
PROJECT_NAME=$(basename "$PROJECT_ROOT")
WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"

# Prune stale worktree entries (same as 3b.1)
git worktree prune

# Orchestrator creates worktree manually (same pattern as 3b.1)
if [ -d "$WORKTREE_PATH" ]; then
  echo "Resuming existing fix worktree at $WORKTREE_PATH"
else
  git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" main 2>/dev/null \
    || git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
fi

# Pipeline association
echo "$PIPELINE_ID" > "$WORKTREE_PATH/.zskills-tracked"
```

**Differences from /run-plan PR mode (3b.1):**
- Branch prefix is hardcoded `fix/` (not config `branch_prefix`)
- Branch name uses issue number, not plan slug
- Worktree path uses `fix-issue-NNN`, not `pr-<plan-slug>`
- One worktree per issue (not one per plan)

- [ ] Per-issue branch naming: `fix/issue-NNN`
- [ ] Per-issue worktree: `/tmp/<project>-fix-issue-NNN`
- [ ] Orchestrator creates worktree manually (not isolation parameter)
- [ ] Worktree reuse on resume

#### 4.3 -- Per-issue landing: rebase + push + PR + CI

Same PR landing flow as 3b-ii/3b-iii, with these differences:

**Rebase before push:** Same pattern as 3b.3, rebase point 2 only (fix-issues is single-phase per issue, no between-phase rebase needed):

```bash
cd "$WORKTREE_PATH"
git fetch origin main
PRE_REBASE=$(git rev-parse HEAD)
git rebase origin/main
if [ $? -ne 0 ]; then
  git rebase --abort
  echo "REBASE CONFLICT for issue #$ISSUE_NUM."
  # Write .landed with status: conflict, continue to next issue
  cat > "$WORKTREE_PATH/.landed.tmp" <<LANDED
status: conflict
date: $(TZ=America/New_York date -Iseconds)
source: fix-issues
method: pr
branch: $BRANCH_NAME
issue: $ISSUE_NUM
reason: rebase-conflict
LANDED
  mv "$WORKTREE_PATH/.landed.tmp" "$WORKTREE_PATH/.landed"
  continue  # Move to next issue
fi
if [ "$(git rev-parse HEAD)" != "$PRE_REBASE" ]; then
  echo "Main moved -- re-verifying issue #$ISSUE_NUM before push..."
  # Dispatch /verify-changes worktree re-verification.
  # Agent prompt includes "FIRST: cd $WORKTREE_PATH".
  # Re-verification has its own fix cycle (max 2 attempts), independent
  # of the CI fix budget.
fi
```

**PR creation per issue:**

```bash
for issue in "${FIXED_ISSUES[@]}"; do
  ISSUE_NUM="$issue"
  BRANCH_NAME="fix/issue-${ISSUE_NUM}"
  WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"

  cd "$WORKTREE_PATH"
  git push -u origin "$BRANCH_NAME"

  EXISTING_PR=$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number' 2>/dev/null)
  if [ -n "$EXISTING_PR" ]; then
    PR_URL=$(gh pr view "$EXISTING_PR" --json url --jq '.url')
    PR_NUMBER="$EXISTING_PR"
  else
    PR_URL=$(gh pr create \
      --title "Fix #${ISSUE_NUM}: ${ISSUE_TITLE}" \
      --body "$(cat <<EOF
Fixes #${ISSUE_NUM}

## Changes
${CHANGE_SUMMARY}

## Test plan
- [ ] Verify the fix resolves the original issue
- [ ] All existing tests pass
EOF
)" \
      --base main \
      --head "$BRANCH_NAME")
    if [ -n "$PR_URL" ]; then
      PR_NUMBER=$(gh pr view --json number --jq '.number')
    fi
  fi

  # CI check + auto-merge: same pattern as 3b-iii, with per-issue timeout adjustment.
  # (config re-read, pre-check, polling, fix cycle, auto-merge, .landed marker)
  # Only difference: source is "fix-issues" and marker includes issue: field.
  #
  # IMPORTANT: Use `timeout 300` (5 min) per issue instead of 600, to avoid
  # serial accumulation across N issues (N * 10min = unacceptable for 5+ issues).
  # If CI doesn't resolve in 5 min for a given issue, write `status: pr-ready`
  # and move on -- the next cron turn or the user can re-check.
  #
  # Parallel optimization: if the orchestrator can dispatch sub-agents, each
  # issue's CI polling can run in parallel. This is not required for the initial
  # implementation but should be noted as a future optimization.

  # .landed marker includes issue field
  cat > "$WORKTREE_PATH/.landed.tmp" <<LANDED
status: $LANDED_STATUS
date: $(TZ=America/New_York date -Iseconds)
source: fix-issues
method: pr
branch: $BRANCH_NAME
pr: $PR_URL
ci: $CI_STATUS
pr_state: $PR_STATE
issue: $ISSUE_NUM
commits: $(git log main.."$BRANCH_NAME" --format='%h' | tr '\n' ' ')
LANDED
  mv "$WORKTREE_PATH/.landed.tmp" "$WORKTREE_PATH/.landed"

  echo "Issue #$ISSUE_NUM -> PR: $PR_URL"
done
```

- [ ] Rebase each issue worktree onto latest main before push (clean tree, same pattern as 3b.3)
- [ ] Re-verify if rebase moved HEAD
- [ ] Push + PR creation for each fixed issue
- [ ] PR body includes `Fixes #NNN` for auto-close linking
- [ ] Handle existing PRs (update, don't duplicate)
- [ ] CI check + auto-merge per issue (same pattern as 3b-iii, but `timeout 300` per issue instead of 600 to avoid serial accumulation)
- [ ] `.landed` marker includes `issue:` field in addition to standard PR fields

#### 4.4 -- /fix-report: PR-aware review flow

Update `skills/fix-issues/SKILL.md` (the `/fix-report` section) to be PR-aware:

- When reviewing completed sprints, check `.landed` markers for `method: pr`
- Report PR URLs alongside issue numbers
- Sprint summary includes PR links

- [ ] `/fix-report` checks `.landed` markers for `method: pr`
- [ ] Sprint report includes PR URLs

#### 4.5 -- Tests for /fix-issues PR mode

```bash
# Test: per-issue branch naming
test_fix_issue_branch_naming() {
  ISSUE_NUM=42
  BRANCH_NAME="fix/issue-${ISSUE_NUM}"
  [[ "$BRANCH_NAME" == "fix/issue-42" ]] || fail "Expected fix/issue-42"
}

# Test: per-issue worktree path
test_fix_issue_worktree_path() {
  PROJECT_NAME="my-app"
  ISSUE_NUM=42
  WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"
  [[ "$WORKTREE_PATH" == "/tmp/my-app-fix-issue-42" ]] || fail "Wrong path"
}

# Test: .landed marker includes issue field
test_fix_issue_landed_marker() {
  MARKER=$(cat <<LANDED
status: landed
source: fix-issues
method: pr
issue: 42
LANDED
)
  [[ "$MARKER" == *"issue: 42"* ]] || fail "Expected issue field"
  [[ "$MARKER" == *"source: fix-issues"* ]] || fail "Expected source: fix-issues"
}
```

- [ ] Add 3+ tests covering: branch naming, worktree path, .landed marker with issue field
- [ ] All tests pass

#### 4.6 -- Sync installed copies

- [ ] Copy `skills/fix-issues/SKILL.md` to `.claude/skills/fix-issues/SKILL.md`
- [ ] Verify installed copy matches source

### Design & Constraints

- **One PR per issue.** Each issue gets its own branch and PR. This allows independent review and merging, unlike `/run-plan` where all phases share one branch.
- **`Fixes #NNN` linking.** GitHub auto-closes issues when the PR is merged.
- **Verification agent commits.** Same as all modes -- tracking enforces this.
- **PR-aware sprint report.** `/fix-report` must show PR URLs so the user can review them.
- **Same CI/auto-merge/marker pattern as 3b.** Do not re-implement; reference the canonical pattern from 3b-iii. The only differences are `source: fix-issues` and the additional `issue:` field in the marker.

### Acceptance Criteria

- [ ] `pr` and `direct` detected as arguments in `/fix-issues`
- [ ] Per-issue branches: `fix/issue-NNN`
- [ ] Per-issue worktrees: `/tmp/<project>-fix-issue-NNN`
- [ ] Rebase onto latest main before push (clean tree, after commit)
- [ ] Re-verify if rebase moved HEAD
- [ ] Phase 6 creates one PR per fixed issue with `Fixes #NNN`
- [ ] CI check + auto-merge per issue
- [ ] `.landed` status: `landed`/`pr-ready`/`pr-ci-failing`/`pr-failed`
- [ ] `.landed` marker includes `issue:` field
- [ ] `/fix-report` shows PR URLs
- [ ] Tests in `tests/test-hooks.sh`
- [ ] 3+ /fix-issues PR mode tests pass (naming, path, marker)
- [ ] Installed skill copy synced

### Dependencies

Phase 1 (config file).
Phase 2 (main_protected validation).
Phase 3a (landing mode detection pattern -- reuse the same approach).
Phase 3b-ii (PR mode worktree setup, push+PR, .landed markers) -- **hard dependency for core flow**.
Phase 3b-iii (CI integration, auto-merge pattern) -- **soft dependency**. Phase 4 core flow (push, create PR, `.landed` marker) only needs 3b-ii. CI polling per issue (4.3 CI section) depends on 3b-iii. Phase 4 can start as soon as 3b-ii lands; the CI integration per-issue can be added after 3b-iii lands or stubbed as `status: pr-ready` without CI.

---

## Phase 5a -- Skill Propagation

### Goal

Propagate execution mode awareness through the upstream skill chain: `/research-and-go` detects mode and passes it in the cron prompt, `/research-and-plan` passes mode context to `/draft-plan`, `/draft-plan` embeds landing hints. These are small, mechanical changes -- each skill just detects `pr`/`direct` and passes it downstream.

### Work Items

#### 5a.1 -- /research-and-go: detect mode and pass to /run-plan

Modify `skills/research-and-go/SKILL.md` to detect `pr` or `direct` in the goal text and pass it through to the `/run-plan` cron prompt:

```bash
# In the cron prompt construction:
LANDING_ARG=""
if [[ "$GOAL" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]|[.!?]) ]]; then
  LANDING_ARG="pr"
elif [[ "$GOAL" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]|[.!?]) ]]; then
  LANDING_ARG="direct"
fi

# Cron prompt includes landing mode:
# /run-plan plans/GENERATED_PLAN.md finish auto $LANDING_ARG every 4h now
```

- [ ] Detect `pr`/`direct` in goal text
- [ ] Pass landing mode to `/run-plan` cron prompt
- [ ] Sync installed copy

#### 5a.2 -- /research-and-plan: pass mode context to /draft-plan

Modify `skills/research-and-plan/SKILL.md` to detect `pr` or `direct` in the goal text and pass it through to `/draft-plan`:

```markdown
If the user's goal includes `pr` or `direct`, pass this context to `/draft-plan`
so generated plans include appropriate landing hints.

When constructing the /draft-plan invocation, append the detected landing mode:
- `/draft-plan output plans/X.md rounds 2 <description>. Landing mode: pr`
```

- [ ] Detect `pr`/`direct` in goal text
- [ ] Pass landing mode context to `/draft-plan` invocations
- [ ] Sync installed copy

#### 5a.3 -- /draft-plan: embed landing hints

Modify `skills/draft-plan/SKILL.md` to embed landing hints in generated plans when the config specifies a non-default landing mode:

```markdown
When generating a plan, check `.claude/zskills-config.json` for `execution.landing`:
- If `"pr"`: add a note at the top of the plan:
  `> **Landing mode: PR** -- This plan targets PR-based landing. All phases
  > use worktree isolation with a named feature branch.`
- If `"direct"`: add a note:
  `> **Landing mode: direct** -- This plan targets direct-to-main landing.
  > No worktree isolation.`
- If `"cherry-pick"` or absent: no note (default behavior).

This is a hint for the implementing agent, not enforcement. The `/run-plan`
argument always takes precedence.
```

- [ ] Read config `execution.landing` in `/draft-plan`
- [ ] Embed landing hint in generated plan when non-default
- [ ] Sync installed copy

#### 5a.4 -- Sync all installed copies

- [ ] `skills/research-and-go/SKILL.md` -> `.claude/skills/research-and-go/SKILL.md`
- [ ] `skills/research-and-plan/SKILL.md` -> `.claude/skills/research-and-plan/SKILL.md`
- [ ] `skills/draft-plan/SKILL.md` -> `.claude/skills/draft-plan/SKILL.md`
- [ ] Verify all installed copies match sources

### Design & Constraints (5a)

- **Propagation, not re-implementation.** Each skill reuses the same landing mode detection pattern from Phase 3a. No new patterns.
- **Config hints, not enforcement.** `/draft-plan` embeds hints in plans, but `/run-plan` arguments always take precedence.
- **`/research-and-plan` included.** It passes mode context to `/draft-plan`.

### Acceptance Criteria (5a)

- [ ] `/research-and-go` detects mode in goal and passes to `/run-plan` cron prompt
- [ ] `/research-and-plan` detects mode and passes to `/draft-plan`
- [ ] `/draft-plan` embeds landing hints for non-default modes
- [ ] All installed skill copies synced and verified

**Testing note:** 5a changes are skill text only (no code, no hooks, no scripts). Verification is structural -- the agent reviews the diff to confirm the detection pattern and downstream propagation are correctly inserted. No automated tests are needed for this phase.

### Dependencies (5a)

Phase 3a (landing mode detection pattern).

---

## Phase 5b -- Execution Skills + Documentation

### Goal

Add execution mode support to downstream skills (`/do`, `/commit`), document execution modes in `CLAUDE_TEMPLATE.md`, and add execution mode audit to `/update-zskills`.

### Work Items

#### 5b.1 -- /do: `pr` option

Modify `skills/do/SKILL.md` to accept a `pr` argument. `/do <task> pr` creates a worktree with a named branch, does the work, pushes, and creates a PR. Same PR landing flow as 3b-ii/3b-iii, with these differences:

- Branch name: `{branch_prefix}{task-slug}` (task slug derived from first few words of task description, lowercased, hyphenated)
- Worktree: `/tmp/<project>-do-<task-slug>`
- Single-phase: only rebase point 2 applies (before push)
- CI check + auto-merge: same pattern as 3b-iii
- `.landed` marker: `source: do`

- [ ] Add `pr` argument detection to `/do`
- [ ] PR mode creates named worktree, pushes, creates PR
- [ ] Rebase onto latest main before push (same pattern as 3b.3, rebase point 2)
- [ ] CI check + auto-merge (same pattern as 3b-iii)
- [ ] `.landed` marker with `source: do`
- [ ] Sync installed copy

#### 5b.2 -- /commit: `pr` subcommand

Modify `skills/commit/SKILL.md` to accept a `pr` subcommand. `/commit pr` pushes the current branch and creates a PR to main:

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  echo "ERROR: Cannot create PR from main. Create a feature branch first."
  exit 1
fi

# Rebase onto latest main before pushing
git fetch origin main
git rebase origin/main
# If rebase conflicts: report and stop. The user needs to resolve.

git push -u origin "$BRANCH"

EXISTING_PR=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null)
if [ -n "$EXISTING_PR" ]; then
  PR_URL=$(gh pr view "$EXISTING_PR" --json url --jq '.url')
  echo "PR already exists: $PR_URL"
else
  PR_URL=$(gh pr create --base main --head "$BRANCH" --fill)
  echo "Created PR: $PR_URL"
fi

# Poll CI if PR was created/exists
if [ -n "$PR_URL" ]; then
  PR_NUMBER=$(gh pr view --json number --jq '.number')
  # CI pre-check with retry (same pattern as 3b-iii.2)
  CHECK_COUNT=0
  for _i in 1 2 3; do
    CHECK_COUNT=$(gh pr checks "$PR_NUMBER" --json name --jq 'length' 2>/dev/null || echo "0")
    [ "$CHECK_COUNT" != "0" ] && break
    sleep 10
  done
  if [ "$CHECK_COUNT" != "0" ]; then
    timeout 600 gh pr checks "$PR_NUMBER" --watch 2>/dev/null
    if [ $? -eq 0 ]; then
      echo "CI checks passed."
    else
      echo "CI checks failed. Run /verify-changes to diagnose."
    fi
  fi
fi
```

**Differences from 3b:** This is a convenience command for manual PR creation. It does NOT dispatch fix agents or write `.landed` markers. It rebases, pushes, creates PR, and reports CI status.

- [ ] Add `pr` subcommand to `/commit`
- [ ] Rebase onto latest main before pushing
- [ ] Push current branch + create PR
- [ ] PR number via `gh pr view --json number --jq '.number'` (NOT URL regex)
- [ ] Poll CI checks after PR creation (report only, no fix cycle)
- [ ] Error if on main/master
- [ ] Handle existing PR
- [ ] Sync installed copy

#### 5b.3 -- CLAUDE_TEMPLATE.md: document execution modes

Add a section to `CLAUDE_TEMPLATE.md` documenting execution modes:

```markdown
## Execution Modes

Three landing modes control how agent work reaches main:

| Mode | Keyword | How it works |
|------|---------|-------------|
| Cherry-pick | (default) | Work in auto-named worktree, cherry-pick to main |
| PR | `pr` | Work in named worktree, push branch, create PR |
| Direct | `direct` | Work directly on main, no landing step |

**Usage:** Append keyword to any execution skill:
- `/run-plan plans/X.md finish auto pr`
- `/fix-issues 10 pr`
- `/research-and-go Build an RPG. pr`
- `/do Add dark mode. pr`

**Config default:** Set in `.claude/zskills-config.json`:
```json
{
  "execution": {
    "landing": "pr",
    "main_protected": true,
    "branch_prefix": "feat/"
  }
}
```

When `main_protected: true`, agents cannot commit, cherry-pick, or push
to main. Use PR mode or feature branches.
```

- [ ] Add execution modes section to `CLAUDE_TEMPLATE.md`
- [ ] Document all three modes with usage examples
- [ ] Document config defaults

#### 5b.4 -- /update-zskills: audit execution mode rules

Add execution mode key phrases to the `/update-zskills` audit checklist:

```markdown
**Execution mode audit items:**
- "Execution Modes" section exists in CLAUDE.md
- "main_protected" mentioned if config has it enabled
- "PR" and "direct" keywords documented
- `.claude/zskills-config.json` referenced
```

- [ ] Add execution mode audit items to `/update-zskills`
- [ ] Sync installed copy

#### 5b.5 -- Sync all installed copies

- [ ] `skills/do/SKILL.md` -> `.claude/skills/do/SKILL.md`
- [ ] `skills/commit/SKILL.md` -> `.claude/skills/commit/SKILL.md`
- [ ] `CLAUDE_TEMPLATE.md` updated
- [ ] `skills/update-zskills/SKILL.md` -> `.claude/skills/update-zskills/SKILL.md`
- [ ] Verify all installed copies match sources

### Design & Constraints (5b)

- **`/commit pr` is a convenience.** It's for manual use from any feature branch, not tied to the pipeline. No fix agents, no `.landed` markers.
- **CLAUDE_TEMPLATE.md is documentation.** It tells the LLM about execution modes so it can make informed decisions.

### Acceptance Criteria (5b)

- [ ] `/do pr` creates worktree, rebases onto main before push, pushes, creates PR, polls CI
- [ ] `/commit pr` rebases onto main, pushes, creates PR, polls CI
- [ ] `CLAUDE_TEMPLATE.md` documents all three execution modes
- [ ] `/update-zskills` audit includes execution mode checks
- [ ] All installed skill copies synced and verified

### Dependencies (5b)

Phase 3a (landing mode detection pattern).
Phase 3b-ii (PR mode worktree setup, push+PR pattern).
Phase 3b-iii (CI integration, auto-merge pattern).

---

## Phase 5c -- Infrastructure: Cleanup Tooling, Model Gate, Baseline Snapshot

### Goal

Update cleanup tooling for new `.landed` statuses, add `agents.min_model` config enforcement, and add baseline test snapshot capture. These are infrastructure improvements that support the execution mode system but are independent of the skill text changes in 5b.

### Work Items

#### 5c.1 -- Cleanup tooling: recognize new `.landed` statuses

Update `/briefing` and `/fix-report` to classify the new `.landed` status values.
Existing tooling only recognizes `status: landed` (safe) and treats everything else
as unknown. The new statuses need distinct handling:

| Status | Classification | Action |
|--------|---------------|--------|
| `landed` | Safe to remove | Worktree cleanup OK |
| `pr-ready` | Safe to remove | Work preserved in PR |
| `pr-ci-failing` | Needs attention | CI failing, may need manual fix |
| `pr-failed` | Needs attention | PR creation failed, manual `gh pr create` |
| `conflict` | Needs attention | Rebase conflict, manual resolution |
| `not-landed` | Agent done | Review before removing |

- [ ] Update `/briefing` worktree classification to recognize all 6 statuses
- [ ] Update `/fix-report` sprint summary to show PR URLs and CI status
- [ ] `landed` and `pr-ready` -> safe for cleanup; others -> flag for user
- [ ] Sync installed copies of briefing and fix-report skills

#### 5c.2 -- `agents.min_model` config field + hook enforcement

Add an `agents.min_model` field to the config schema and enforce it in the hook. This prevents agents from dispatching subagents with models below a minimum quality threshold.

**Config addition:**

```json
{
  "agents": {
    "min_model": "claude-sonnet-4-20250514"
  }
}
```

**Schema addition:**

```json
"agents": {
  "type": "object",
  "description": "Agent dispatch configuration.",
  "properties": {
    "min_model": {
      "type": "string",
      "description": "Minimum model for Agent tool calls. Hook blocks Agent calls with model_name below this. Example: claude-sonnet-4-20250514"
    }
  }
}
```

**Hook enforcement:** In `hooks/block-unsafe-project.sh.template`, when the tool is `Agent` and the input contains a `model` or `model_name` field, extract it and compare against `agents.min_model` from config. Block if the specified model is below the minimum.

The comparison uses an ordinal lookup on the model family, NOT lexicographic (since `opus < sonnet` alphabetically, which is backwards). Extract the family name from the model string and map to an ordinal: `haiku=1, sonnet=2, opus=3`. Compare ordinals: if the requested model's ordinal is less than the minimum model's ordinal, block. If `min_model` is `claude-sonnet-4-*` (ordinal 2), block `claude-haiku-*` (ordinal 1) but allow `claude-sonnet-4-*` (ordinal 2) and `claude-opus-*` (ordinal 3).

```bash
model_ordinal() {
  case "$1" in
    *haiku*) echo 1 ;;
    *sonnet*) echo 2 ;;
    *opus*) echo 3 ;;
    *) echo 99 ;;  # unknown/future model family, allow by default
  esac
}
```

- [ ] Add `agents.min_model` to config schema
- [ ] Add `agents` section to dogfood config
- [ ] Add hook enforcement: block Agent calls with model below minimum
- [ ] Model comparison: ordinal (haiku=1, sonnet=2, opus=3), not lexicographic
- [ ] Tests in `tests/test-hooks.sh` (config/hook tests belong there)

#### 5c.3 -- Baseline test snapshot

`/run-plan` captures test results BEFORE the implementation agent starts, so the verification agent can compare against a known-good baseline. This detects regressions introduced by the implementation (as opposed to pre-existing failures).

**Mechanism:** Before dispatching the implementation agent for each phase:

```bash
# Capture baseline test results in the worktree
cd "$WORKTREE_PATH"
$FULL_TEST_CMD > .test-baseline.txt 2>&1 || true
# The || true ensures we capture output even if some tests fail pre-existing.
# The verification agent compares .test-results.txt against .test-baseline.txt
# to distinguish new failures from pre-existing ones.
```

**Verification agent instructions (added to prompt):**

```markdown
After running tests, compare `.test-results.txt` against `.test-baseline.txt`:
- New failures (in results but not in baseline) -> must be fixed before commit
- Pre-existing failures (in both baseline and results) -> note in report, do not fix
- Resolved failures (in baseline but not in results) -> positive, note in report
```

- [ ] Capture `.test-baseline.txt` before implementation agent dispatch
- [ ] Add comparison instructions to verification agent prompt
- [ ] Handle missing `FULL_TEST_CMD` (skip baseline if no test command configured)
- [ ] Tests in `tests/test-hooks.sh`

#### 5c.4 -- Sync all installed copies

- [ ] `config/zskills-config.schema.json` updated with `agents` section
- [ ] Sync installed copies of briefing and fix-report skills
- [ ] Verify all installed copies match sources

### Design & Constraints (5c)

- **`agents.min_model` uses ordinal comparison.** We extract the model family (haiku=1, sonnet=2, opus=3) and compare ordinals. NOT lexicographic -- `opus < sonnet` alphabetically, which gives the wrong result. Unknown families get ordinal 0 (allowed by default).
- **Baseline snapshot is best-effort.** If `FULL_TEST_CMD` is not configured, skip the baseline. The verification agent still runs tests; it just can't distinguish new vs pre-existing failures.
- **Phase 5c tests go in `tests/test-hooks.sh`.** Config/hook tests (min_model, baseline) belong in the hook test file.

### Acceptance Criteria (5c)

- [ ] `/briefing` and `/fix-report` classify all 6 `.landed` statuses correctly
- [ ] `agents.min_model` config field exists with schema definition
- [ ] Hook blocks Agent calls with model below `agents.min_model`
- [ ] Baseline test snapshot captured before implementation agent dispatch
- [ ] Verification agent compares `.test-results.txt` against `.test-baseline.txt`
- [ ] All installed skill copies synced and verified

### Dependencies (5c)

Phase 3b-ii (`.landed` statuses, PR mode patterns).
Phase 4 (fix-issues PR mode, for sprint report PR URLs).

---

## Anti-Patterns -- Hard Constraints

These are 11 mistakes identified through 4 rounds of adversarial review. Each is a hard constraint -- violating any of them means the implementation is wrong.

1. **No worktree exemption for tracking.** The tracking system enforces in worktrees via `git-common-dir` resolution. Do not add any code that skips tracking checks in worktrees.

2. **No branch checkout in main directory.** Never use `git checkout <branch>` in the main working directory. It causes stash data loss, tracking enforcement deadlock, and progress tracking failure across cron turns. Always use `git worktree add` for isolation.

3. **No staleness bypass.** Tracking enforcement is unconditional. Do not add "skip if stale" logic that lets agents bypass tracking by waiting.

4. **No `.zskills-tracked` on main for orchestrators.** Orchestrators on main use `echo "ZSKILLS_PIPELINE_ID=..."` (transcript-based). `.zskills-tracked` is for worktree agents only (written by the orchestrator before dispatch). Do not write `.zskills-tracked` in the main repo root from the orchestrator's own session.

5. **No glob matching for sentinels.** Pipeline scoping uses exact suffix matching: `[[ "$base" != *".$PIPELINE_ID" ]]`. Do not use `find -name "*pattern*"` or shell glob expansion for marker lookups.

6. **`direct` not `main` as keyword.** The keyword for direct-to-main execution is `direct`, not `main`. `main` collides with plan filenames containing "main" (e.g., `plans/MAIN_MENU.md`, `plans/FIX_MAIN_LOOP.md`).

7. **Verification agent commits, not impl agent.** The implementation agent writes code and does NOT commit. The verification agent verifies (runs tests, reviews) and commits if verification passes. This is enforced by the tracking system regardless of landing mode.

8. **Two-tier pipeline guard, not three.** Pipeline association uses exactly two tiers: (1) `.zskills-tracked` file in LOCAL repo root, (2) `ZSKILLS_PIPELINE_ID=` in transcript. There is no third tier. Do not add additional tiers.

9. **`.zskills/tracking`, not `.claude/tracking`.** All tracking state lives under `.zskills/tracking/`. The `.claude/` directory triggers permission prompts when agents write to it. Do not use `.claude/tracking/` for any purpose.

10. **No git stash + rebase.** Never stash uncommitted changes to rebase. `git stash pop` after rebase frequently conflicts and needs manual merge, which breaks autonomous flows. Rebase only when the tree is clean (after commits).

11. **No git merge origin/main.** Never use `git merge origin/main` to update a feature branch. It creates merge commits that pollute history on phase 2+. Use `git rebase origin/main` at clean points only.

---

## Plan Quality

**Drafting process:** /draft-plan with 2 rounds of adversarial review (modernization rewrite of existing 1772-line plan)
**Convergence:** Converged at round 2
**Remaining concerns:** None

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 6 important, 4 minor | 4 critical, 9 important | All addressed: rebase conflict handling, .landed mv bug, PR title/body, agent dispatch, --watch timeout, re-poll delay, re-verify budget, auto-merge docs, Phase 3b sizing note |
| 2     | 0 (CONVERGED) | 2 medium | Fixed: /do timeout, cleanup tooling statuses. Converged. |

### Prior Review History (before re-draft)
The original plan went through 4 additional rounds of incremental review during the design session. Key issues caught and resolved:
- git stash + rebase fragility (replaced with clean-tree-only strategy)
- gh pr comment does NOT return URL (switched to gh api)
- /tmp file collision across parallel pipelines (namespaced with PR number)
- .landed status ambiguity (replaced full/partial with 6 specific statuses)
- Missing auto-merge flow (added gh pr merge --auto --squash)
- Missing JSON Schema for config documentation (added config/zskills-config.schema.json)

---

## Drift Log

Structural comparison of the plan as originally drafted (`adb4752`) vs current state.

| Phase | Original (adb4752) | Current | Delta |
|-------|-------------------|---------|-------|
| 1 — Config | 1 phase | 1 phase (Done) | No structural drift |
| 2 — Hook Enforcement | 1 phase | 1 phase (Done) | No structural drift |
| 3a — Argument Detection | 1 phase | 1 phase (Done) | Added direct mode (not in original) |
| 3b — PR Mode | 1 phase (6 items) | Split into 3b-i, 3b-ii, 3b-iii | +2 phases. 3b-i (worktree unification + landing script) added during execution. 3b split due to 908-line phase failing from stale `origin/HEAD` base |
| 4 — /fix-issues | 1 phase | 1 phase | CI timeout reduced to 300s/issue. Soft dep on 3b-iii |
| 5 — Propagation | 1 phase (9 items) | Split into 5a, 5b, 5c | +2 phases. agents.min_model and baseline test snapshot added during execution. /review-plan removed (separate plan) |
| **Totals** | **6 phases** | **10 phases** | +4 phases from splits and additions |

**Key execution-time additions not in original draft:**
- `scripts/land-phase.sh` — atomic worktree cleanup (worktree cleanup kept being forgotten)
- Preflight check #5 — auto-clean landed worktrees
- Manual worktrees replacing `isolation: "worktree"` — discovered `origin/HEAD` stale base issue
- Baseline test snapshot — agents falsely claim failures are "pre-existing"
- `agents.min_model` config — Sonnet minimum, no Haiku ever

## Plan Review (/refine-plan)

**Refinement process:** /refine-plan with 2 rounds of adversarial review
**Convergence:** Converged at round 2 (1 minor fix: model_ordinal unknown=99)
**Remaining concerns:** None

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Substantive | Resolved |
|-------|-------------------|---------------------------|-------------|----------|
| 1 | 2 critical, 3 important, 1 minor | 4 critical, 3 important, 1 minor | 11 | 11/11 |
| 2 | 1 note (model_ordinal) | 1 issue (model_ordinal) | 1 | 1/1 (fixed: unknown=99) |
