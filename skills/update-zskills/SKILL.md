---
name: update-zskills
argument-hint: "[install | --rerender | --migrate-paths] [cherry-pick | locked-main-pr | direct] [--with-addons | --with-block-diagram-addons]"
description: Install or update Z Skills supporting infrastructure (CLAUDE.md rules, hooks, scripts)
metadata:
  version: "2026.05.20+45bef1"
---

# Update Z Skills Infrastructure

Install or update the supporting infrastructure that Z Skills depend
on: CLAUDE.md agent rules, safety hooks, helper scripts, and skill
dependencies.

**Invocation:**

```
/update-zskills [install | --rerender | --migrate-paths] [cherry-pick | locked-main-pr | direct]
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
- `--migrate-paths` — one-shot deterministic relocation of legacy
  artifacts into the path-config layout (`docs/plans/` for plan files,
  `.zskills/audit/` for forensic + narrative reports, `docs/issues/`
  for issue trackers, `.zskills/dev-server.{pid,log}` for runtime
  state). Dispatches to
  `bash $ZSK/scripts/migrate-paths.sh "$MAIN_ROOT"` (where `$ZSK` is
  `.claude/skills/update-zskills` shipped, or `skills/update-zskills`
  in zskills source tree). Writes a `.pre-paths-migration` manifest
  (write-once), updates `.gitignore`, and writes `output.plans_dir`
  + `output.issues_dir` + `output.reports_dir` LAST (atomic
  both-or-all-or-neither — 3-tuple). The script
  triggers `--rerender` AS THE FIRST FILE-SYSTEM CHANGE so the
  broadened recursive-delete hook regex protects the migration's own
  filesystem actions. Idempotent — refuses to re-run if
  `.pre-paths-migration` already exists. The agent-runnable
  follow-up (path-config-upgrade prompt) handles `start-dev.sh` /
  `stop-dev.sh` rewrites and any cross-references in plan content.

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
4. **Extended probe — common downstream clone locations.** If none of
   the above matched, check the following paths IN ORDER (first valid
   wins). A path is valid iff the directory exists and contains all
   four of `CLAUDE_TEMPLATE.md`, `hooks/`, `scripts/`, and `skills/` —
   the same validity test as the existing tiers. If the path is a git
   clone, also store it as `$ZSKILLS_PATH`.
   1. `$PWD/../zskills` (project's sibling)
   2. `$PWD/../../zskills` (grandparent-sibling)
   3. `~/src/zskills`
   4. `~/code/zskills`
   5. `~/projects/zskills`
   6. `~/zskills`

   Track each location you checked (matched and unmatched) for the
   stop-and-ask prompt below.
5. **Stop-and-ask fallback.** If no path above matched, do NOT silently
   auto-clone. Instead, print the full list of locations that were
   checked (tiers 1-3 plus the six extended-probe paths from tier 4),
   then ask the user in plain conversation text (NOT
   `AskUserQuestion`, per Key Rule 7):

   > Couldn't locate zskills source. Checked:
   >   - ./zskills-portable/
   >   - ./zskills/
   >   - /tmp/zskills
   >   - $PWD/../zskills
   >   - $PWD/../../zskills
   >   - ~/src/zskills
   >   - ~/code/zskills
   >   - ~/projects/zskills
   >   - ~/zskills
   >
   > Options:
   >   (a) paste a path to your clone
   >   (b) type `clone` to clone fresh to /tmp/zskills
   >   (c) type `abort` to cancel

   Wait for the user's reply. Then:
   - **Pasted path:** Validate it with the same directory-contains
     check (`CLAUDE_TEMPLATE.md` + `hooks/` + `scripts/` + `skills/`).
     If valid, use it as `$PORTABLE` (and `$ZSKILLS_PATH` if it's a
     git clone). If invalid, report what's missing and re-ask the same
     options once; on a second invalid reply, treat as `abort`.
   - **`clone`:** Fall through to the auto-clone behavior below.
   - **`abort`:** Print "Aborted — no zskills source resolved." and
     exit cleanly. Do not modify the project.
   - **Anything else:** Treat as `abort`.

6. **Auto-clone fallback (only when the user typed `clone` above).**
   Clone the repo:
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

## Step 0.1 — `--migrate-paths` short-circuit (Phase 5a)

If the invocation arguments contain the bare flag `--migrate-paths`, this
takes precedence over every other mode (preset, install, --rerender). Run
the deterministic mover and exit; do not run the audit or any install/
update path.

**Per-fence allow-hardcoded markers.** The four fenced code blocks in this
section contain forbidden literals (`plans/`, `reports/`, `SPRINT_REPORT.md`,
etc.) that the conformance hook flags. The marker on the line preceding
each fence whitelists the block. Phase 5a ships 4 such markers; Phase 5b
adds 4 more in a separate section (total 8).

**Dispatcher:**

<!-- allow-hardcoded: re:plans/ re:reports/ re:SPRINT_REPORT\.md reason: Phase 5a migrate-paths dispatcher names the legacy paths the mover relocates -->
```bash
# $ZSK = .claude/skills/update-zskills (shipped) or skills/update-zskills
# (zskills source tree).
ZSK=".claude/skills/update-zskills"
[ -d "skills/update-zskills" ] && ZSK="skills/update-zskills"
MAIN_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
bash "$ZSK/scripts/migrate-paths.sh" "$MAIN_ROOT"
```

**What the script moves (summary):**

<!-- allow-hardcoded: re:plans/ re:reports/ re:SPRINT_REPORT\.md re:FIX_REPORT\.md re:PLAN_REPORT\.md re:VERIFICATION_REPORT\.md re:NEW_BLOCKS_REPORT\.md reason: Phase 5a migrate-paths summary lists legacy filenames the mover relocates -->
```text
Forensic + narrative reports (Tier 2 — regenerable):
  SPRINT_REPORT.md, FIX_REPORT.md, PLAN_REPORT.md,
  VERIFICATION_REPORT.md, NEW_BLOCKS_REPORT.md
  reports/**
  plans/PLAN_INDEX.md
    → .zskills/audit/

Plans (Tier 1 — durable):
  plans/*_PLAN.md, plans/CANARY*.md, plans/blocks/**
    → docs/plans/  (or $output.plans_dir if user-set)

Issue trackers:
  plans/{ISSUES_PLAN,BUILD_ISSUES,DOC_ISSUES,QE_ISSUES}.md
    → docs/issues/  (or $output.issues_dir if user-set)

Work-trail reports (Tier 1.5 — durable narrative artifacts):
  /run-plan plan-{slug}.md, /verify-changes verify-{name}.md,
  /fix-issues SPRINT_REPORT.md
    → docs/reports/  (or $output.reports_dir if user-set;
                      legacy fallback `.zskills/audit`)

Runtime files:
  legacy var/dev.{pid,log}
    → .zskills/dev-server.pid, .zskills/dev-server.log
```

**Algorithm ordering (Phase 5a Locked Decisions):**

The script executes 11 steps in a deterministic order. Hook-rerender is
HOISTED to step 2.5 (BEFORE any file moves) so the broadened recursive-
delete hook regex protects the migration's own filesystem actions. The
config-key write (step 10) is LAST so a mid-failure leaves the consumer
recovering via the helper's legacy-`plans/` fallback.

<!-- allow-hardcoded: re:plans/ re:.zskills/audit re:.zskills/issues reason: Phase 5a migrate-paths algorithm shows the per-step file-move targets -->
```text
1.  Detection — refuse re-run if .pre-paths-migration already exists.
2.  Resolve target dirs in memory only (no config write yet).
2.5 Trigger --rerender BEFORE any file moves (hook strengthens FIRST).
3.  Move forensic + narrative reports → .zskills/audit/.
4.  Move plans → $TARGET_PLANS (default docs/plans/).
4b. Move plans/PLAN_INDEX.md → .zskills/audit/.
5.  Move issue trackers → $TARGET_ISSUES (default docs/issues/).
6.  Move var/ runtime files → .zskills/dev-server.{pid,log}.
7.  Update .gitignore (idempotent) + verify via git check-ignore -v.
8.  (reserved — was --rerender step before round-2 plan hoisted to 2.5).
9.  Write .pre-paths-migration manifest (write-once).
10. Write config keys (BOTH or NEITHER — atomic) LAST.
11. Print summary.
```

**Stub-script handling (DEFER).** `tier1-shipped-hashes.txt` does NOT
cover `start-dev.sh` / `stop-dev.sh`. The migration script does NOT
attempt auto-edit of these scripts; it prints a deferral notice naming
both files when the legacy `var/dev.{pid,log}` are moved. The agent-
runnable upgrade prompt (Phase 5b, `references/path-config-upgrade.md`)
handles them.

**Recovery.** If the mover aborts mid-way (a `git mv` fails, a `git
check-ignore -v` returns negative, etc.) it exits non-zero and leaves
the partial state. Because the config write is LAST, the helper falls
back to legacy `plans/` for any un-moved files — partial-but-functional
state, not broken. The user can re-run after fixing the underlying
cause; the idempotent guard (manifest existence) prevents double-moves.

**Idempotent re-run.** If `.pre-paths-migration` already exists, the
script prints "already migrated" and exits 0 without making any
changes. To force a fresh migration after a prior aborted run, the
user removes `.pre-paths-migration` AND restores files from the
manifest's `from`-column paths.

**Example output:**

<!-- allow-hardcoded: re:SPRINT_REPORT\.md re:plans/ re:.zskills/audit reason: Phase 5a migrate-paths sample output names the legacy → migrated paths -->
```text
moved: SPRINT_REPORT.md → .zskills/audit/SPRINT_REPORT.md
moved: plans/FOO_PLAN.md → docs/plans/FOO_PLAN.md
...
Wrote .pre-paths-migration with N entries.
Re-rendered hooks (broadened recursive-delete fence — applied EARLY).
Wrote output.plans_dir = "docs/plans", output.issues_dir = "docs/issues", and output.reports_dir = "docs/reports".
For start-dev.sh / stop-dev.sh customizations, see
.claude/skills/update-zskills/references/path-config-upgrade.md.
```

After dispatch, `/update-zskills --migrate-paths` exits with the script's
exit code. Do NOT proceed to Step 0.25 / 0.5 / audit.

### Cross-reference rewrite (Phase 5b)

`migrate-paths.sh` runs a structural-reference rewriter immediately after
gitignore update (step 7) and before the manifest write (step 9). The
rewriter scans every `.md` under `<TARGET_PLANS>` and rewrites legacy
`plans/X.md` and `reports/Y.md` tokens to the migrated paths, gated by
the YAML frontmatter `status:` field.

**Frontmatter decision tree:**

<!-- allow-hardcoded: re:plans/ re:reports/ reason: Phase 5b cross-ref-rewrite decision tree names the legacy path tokens the rewriter substitutes inside plan content -->
```text
status: active     → REWRITE (all 4 enclosure types)
status: proposal   → REWRITE
(no frontmatter)   → REWRITE
status: complete + filename CANARY*.md   → REWRITE (slash-command lines
                                            naturally limited by rule 4)
status: complete + non-canary filename   → PRESERVE (frozen) + scan/warn
status: deferred / paused / other        → PRESERVE + scan/warn
```

**Four enclosure types** triggering rewrite — token must appear inside ONE:

<!-- allow-hardcoded: re:plans/ re:reports/ re:run-plan reason: Phase 5b cross-ref-rewrite enumerates the four structural enclosures that promote a path token from naked-prose to rewritable -->
```text
1. Markdown link:   [...](plans/X.md)  or  [...](reports/Y.md)
2. Backtick span:   `plans/X.md`       or  `reports/Y.md`
3. Shell line:      inside ```bash/```sh/```shell/``` fence,
                    OR line starts with "$ ",
                    OR line ends with shell metachar | > < ;
4. Slash-command:   /run-plan plans/X.md  (also draft-plan, refine-plan,
                    draft-tests, work-on-plans, research-and-plan,
                    research-and-go)
```

**Substitution targets:**

<!-- allow-hardcoded: re:plans/ re:reports/ re:.zskills/audit reason: Phase 5b cross-ref-rewrite substitution rules name the legacy → migrated path mappings -->
```text
plans/X.md           → <TARGET_PLANS>/X.md   (e.g., docs/plans/X.md)
reports/<slug>-Y.md  → .zskills/audit/<slug>-Y.md
                       (slug ∈ {plan, verify, briefing, new-blocks})
```

**Warning emission contract.** For PRESERVED plans containing legacy
tokens, the rewriter emits a stderr `WARN` line per hit AND appends the
same line to `.pre-paths-migration-warnings` at the repo root:

<!-- allow-hardcoded: re:plans/ re:reports/ reason: Phase 5b cross-ref-rewrite warning format documents the WARN line emitted to stderr + .pre-paths-migration-warnings for legacy tokens preserved in frozen plans -->
```text
WARN docs/plans/OLD_FEATURE.md:42: legacy token 'plans/OTHER.md' preserved (frozen plan; see path-config-upgrade.md)
```

**`--rewrite-only` flag.** For mid-version-skip recovery (when an older
5a-only `migrate-paths.sh` ran without cross-ref rewrite), the agent-
runnable upgrade prompt at `references/path-config-upgrade.md` invokes
`migrate-paths.sh --rewrite-only "$MAIN_ROOT"`. This skips steps 1–7,
resolves `<TARGET_PLANS>` from the existing config, runs ONLY the cross-
ref rewrite, and appends a `rewrite-only:	<ts>	<count>` trailer to the
existing manifest. Config keys are not re-written. Idempotent.

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
2. Extract values using bash regex (pure bash, no external JSON tool).

   **IMPORTANT — parent-object scoping is mandatory for any field
   that lives inside a parent block.** An unscoped regex like
   `\"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"` matches the
   FIRST occurrence of the field anywhere in the JSON, so a future
   sibling block declaring its own same-named field will silently
   shadow the intended one. The fix class addressed by issues #395
   (`zskills-resolve-config.sh`) and #400 (`apply-preset.sh`) and
   reproductively-broad issue #428 (this prose recipe) is the SAME
   bug class: every field that lives inside `"<parent>": { ... }`
   must scope its extraction under the parent. The canonical form
   for a scoped string-value extraction is:

   ```text
   \"<parent>\"[[:space:]]*:[[:space:]]*\{[^}]*\"<field>\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"
   ```

   Top-level fields (`project_name`, `timezone`) have no parent
   block and may be extracted directly. The mapping below annotates
   every parent-scoped field with `# parent: <name>` next to its
   regex.

   ```bash
   CONFIG_CONTENT=$(cat "$PROJECT_ROOT/.claude/zskills-config.json")
   # Top-level string (no parent — direct extraction is safe):
   if [[ "$CONFIG_CONTENT" =~ \"project_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     PROJECT_NAME="${BASH_REMATCH[1]}"
   fi
   # parent: testing  (sibling-shadow risk if unscoped — see #395)
   if [[ "$CONFIG_CONTENT" =~ \"testing\"[[:space:]]*:[[:space:]]*\{[^}]*\"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     UNIT_CMD="${BASH_REMATCH[1]}"
   fi
   # parent: testing
   if [[ "$CONFIG_CONTENT" =~ \"testing\"[[:space:]]*:[[:space:]]*\{[^}]*\"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     FULL_CMD="${BASH_REMATCH[1]}"
   fi
   # parent: testing
   if [[ "$CONFIG_CONTENT" =~ \"testing\"[[:space:]]*:[[:space:]]*\{[^}]*\"output_file\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     OUTPUT_FILE="${BASH_REMATCH[1]}"
   fi
   # parent: dev_server
   if [[ "$CONFIG_CONTENT" =~ \"dev_server\"[[:space:]]*:[[:space:]]*\{[^}]*\"cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     DEV_SERVER_CMD="${BASH_REMATCH[1]}"
   fi
   # parent: dev_server
   if [[ "$CONFIG_CONTENT" =~ \"dev_server\"[[:space:]]*:[[:space:]]*\{[^}]*\"main_repo_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     MAIN_REPO_PATH="${BASH_REMATCH[1]}"
   fi
   # parent: ui  (note: `file_patterns` also exists under `testing` as
   # an array — scoping under `ui` disambiguates)
   if [[ "$CONFIG_CONTENT" =~ \"ui\"[[:space:]]*:[[:space:]]*\{[^}]*\"file_patterns\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     UI_FILE_PATTERNS="${BASH_REMATCH[1]}"
   fi
   # parent: ui
   if [[ "$CONFIG_CONTENT" =~ \"ui\"[[:space:]]*:[[:space:]]*\{[^}]*\"auth_bypass\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     AUTH_BYPASS="${BASH_REMATCH[1]}"
   fi
   # Top-level string (no parent):
   if [[ "$CONFIG_CONTENT" =~ \"timezone\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     TIMEZONE="${BASH_REMATCH[1]}"
   fi
   # parent: execution  (boolean — sibling-shadow risk if unscoped, see #400)
   if [[ "$CONFIG_CONTENT" =~ \"execution\"[[:space:]]*:[[:space:]]*\{[^}]*\"main_protected\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
     MAIN_PROTECTED="${BASH_REMATCH[1]}"
   fi
   # parent: execution  (landing mode)
   if [[ "$CONFIG_CONTENT" =~ \"execution\"[[:space:]]*:[[:space:]]*\{[^}]*\"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     LANDING_MODE="${BASH_REMATCH[1]}"
   fi
   # parent: execution  (branch prefix)
   if [[ "$CONFIG_CONTENT" =~ \"execution\"[[:space:]]*:[[:space:]]*\{[^}]*\"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     BRANCH_PREFIX="${BASH_REMATCH[1]}"
   fi
   # parent: ci  (boolean)
   if [[ "$CONFIG_CONTENT" =~ \"ci\"[[:space:]]*:[[:space:]]*\{[^}]*\"auto_fix\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
     CI_AUTO_FIX="${BASH_REMATCH[1]}"
   fi
   # parent: ci  (integer)
   if [[ "$CONFIG_CONTENT" =~ \"ci\"[[:space:]]*:[[:space:]]*\{[^}]*\"max_fix_attempts\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
     CI_MAX_ATTEMPTS="${BASH_REMATCH[1]}"
   fi
   # parent: commit  (optional — backfilled below if missing)
   if [[ "$CONFIG_CONTENT" =~ \"commit\"[[:space:]]*:[[:space:]]*\{[^}]*\"co_author\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
     CO_AUTHOR="${BASH_REMATCH[1]}"
   fi
   ```

   The `[^}]*` between the parent key and the field key is what
   constrains the match to inside that block. Do NOT replace it with
   `.*` (which would match across blocks) and do NOT drop the parent
   prefix to "simplify" the regex — that re-introduces the bug class.
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
3.6. **Backfill `dashboard.work_on_plans_trigger` if absent.** If the
   existing config does not contain a `"dashboard"` block with a
   `"work_on_plans_trigger"` field (e.g. configs written before the
   `/zskills-dashboard` skill was introduced), splice in an empty
   default so the dashboard server can read the field unconditionally.
   Default value: `""` (empty string — disables the Run button until
   the consumer wires a trigger script). The server is **read-only** on
   `.claude/zskills-config.json` — adding the field here is the sole
   migration point. Matches the same style as 3.5: targeted `Edit` or
   small `sed`-based rewrite that preserves every other field
   unchanged. If the `dashboard` key is absent, add the whole block; if
   the `dashboard` block exists but lacks `work_on_plans_trigger`, add
   only that field. Idempotent: re-running on an already-backfilled
   config is a no-op. Detection regex (bash): test against
   `\"dashboard\"[[:space:]]*:[[:space:]]*\{[^}]*\"work_on_plans_trigger\"`
   — if it does NOT match, the backfill applies.

   <!-- allow-hardcoded: re:^plans/ reason: forward-protection comment quoting pre-migration plan path -->
   ```markdown
   > **Path-config keys are EXEMPT from auto-backfill.** `output.plans_dir`,
   > `output.issues_dir`, and `output.reports_dir` MUST NOT be inserted into
   > `.claude/zskills-config.json` during install or `--rerender`. Their
   > absence is meaningful — the helper falls back to legacy `plans/`,
   > preserving consumer-current behavior. Only `/update-zskills
   > --migrate-paths` writes these keys (and writes BOTH or NEITHER).
   > See plan `docs/plans/ZSKILLS_PATH_CONFIG.md` (or
   > `plans/ZSKILLS_PATH_CONFIG.md` pre-migration).
   ```

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
       "main_repo_path": "<detected>"
     },
     "ui": {
       "file_patterns": "",
       "auth_bypass": ""
     },
     "ci": {
       "auto_fix": true,
       "max_fix_attempts": 2
     },
     "dashboard": {
       "work_on_plans_trigger": ""
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
| `{{DEFAULT_PORT}}` | `dev_server.default_port` | `8080` |
| `{{MAIN_REPO_PATH}}` | `dev_server.main_repo_path` | `/path/to/repo` |

Runtime-read fields (read by hooks and helper scripts at every invocation, NOT install-filled): `testing.unit_cmd`, `testing.full_cmd`, `ui.file_patterns`. The field `dev_server.main_repo_path` is read at runtime by `port.sh` AND install-substituted into managed.md as `{{MAIN_REPO_PATH}}` (the rendered value reflects the config at install/--rerender time; warn-config-drift signals re-render-needed when the config is edited via Claude Code's Edit/Write tool — see Phase 3 Design & Constraints for coverage limits). Similarly, `dev_server.default_port` is runtime-read by `port.sh` AND install-substituted as `{{DEFAULT_PORT}}`. See Phase 1 of `plans/DRIFT_ARCH_FIX.md` for the canonical bash-regex read pattern.

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
  - Required tool reference (`python3`) — check via `which`. Python 3 is
    required (per CLAUDE.md "Python is required"). Powers `/briefing`,
    `/plans rebuild`, the dashboard, and other Python-only helpers.
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
- `briefing.py`
- `clear-tracking.sh`
- `land-phase.sh` — referenced by `/run-plan`, `/fix-issues`, `/do` for atomic post-landing cleanup
- `post-run-invariants.sh` — referenced by `/run-plan` as mandatory end-of-run gate (7 invariants)
- `write-landed.sh` — referenced by `/run-plan`, `/fix-issues`, `/commit` for rc-checked atomic `.landed` marker writes
- `worktree-add-safe.sh` — referenced by `/run-plan`, `/fix-issues`, `/do` for safe worktree creation (discriminates fresh vs poisoned stale branches)
- `create-worktree.sh` — referenced by `/run-plan`, `/fix-issues`, `/do` for unified worktree creation
- `sanitize-pipeline-id.sh` — shared PIPELINE_ID sanitizer (used by `/run-plan`, `/fix-issues`, `/do`, `/quickfix` before persisting ID)
- `apply-preset.sh` — required by the preset UX (Step F); splices/flips the `BLOCK_MAIN_PUSH` line in `block-unsafe-generic.sh` and updates `execution.landing`/`execution.main_protected` in config
- `compute-cron-fire.sh` — required by `/run-plan` (Phase 5c chunked finish-auto, verify-pending retry, re-entry) for computing one-shot cron expressions with correct minute/hour/day/month/year rollover
- `stop-dev.sh` — sanctioned SIGTERM-only dev-server stopper (reads `.zskills/dev-server.pid`). The approved way for agents to stop a dev server without reaching for `kill -9` / `fuser -k` / `lsof -ti | xargs kill`
- `statusline.sh` — session statusline helper (optional but should be installed if the user has it)

### Step 5 — Check skills with additional requirements

If `/briefing` is installed, check for `[ -f .claude/skills/briefing/scripts/briefing.py ]`
(the artifact half catches partial skill-mirror installs). If not found, add a
note: "The /briefing skill requires `.claude/skills/briefing/scripts/briefing.py`
— see /briefing skill documentation."

### Step 6 — Produce the gap report

Output the report in this exact format:

```
Z Skills Audit Report
