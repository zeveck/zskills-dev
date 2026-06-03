---
name: update-zskills
argument-hint: "[install] [cherry-pick|locked-main-pr|direct]"
description: Install or update Z Skills supporting infrastructure (CLAUDE.md rules, hooks, scripts)
metadata:
  version: "2026.06.03+a0528a"
---

# Update Z Skills Infrastructure

Install or update the supporting infrastructure that Z Skills depend
on: CLAUDE.md agent rules, safety hooks, helper scripts, and skill
dependencies.

**Invocation:**

```
/update-zskills [install | --rerender | --migrate-paths | --switch-install-path={to-plugin|to-update-zskills}]
                [cherry-pick | locked-main-pr | direct]
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
- `--switch-install-path={to-plugin|to-update-zskills}` — the supported
  entry point for switching a consumer between the two install lanes
  (the plugin lane and the legacy `/update-zskills` lane). This sub-mode
  is a thin delegation: it runs
  `bash scripts/switch-install-path.sh --to-plugin` (or
  `--to-update-zskills`) and reports its output. (The lane-switch script
  is a repo-root `scripts/` tool, not a skill-owned `$ZSK/scripts/` one —
  it operates on the consumer's `.claude/` and is shared across both
  lanes.) The script is
  bidirectional and writes the lock file
  `.claude/zskills-install-lane` LAST in BOTH directions (config/state
  writes first, lock claim last — per CLAUDE.md `## Migration scripts`),
  so an interrupted switch leaves the consumer re-runnable.
    - `=to-plugin` — switch FROM the `/update-zskills` lane TO the plugin
      lane: strips zskills hook entries from `.claude/settings.json` (via
      `scripts/migrate-strip-settings.py`), basename-gated removal of the
      mirrored `.claude/skills/<zskills>/`, `.claude/hooks/<zskills>.sh`,
      and `.claude/rules/zskills/managed.md` (consumer-authored skills/
      hooks are preserved), then writes `plugin` to the lock. The script
      prints the `/plugin marketplace add` + `/plugin install zs@zskills`
      steps the user runs in their Claude session.
    - `=to-update-zskills` — switch FROM the plugin lane TO the
      `/update-zskills` lane: sentinel-gated removal of the 5
      plugin-materialised artifacts (only the ones STILL carrying a
      `zskills-materialised:` sentinel — sentinel-less / re-installed
      files are preserved), then writes `update-zskills` to the lock.
    - Idempotent: invoking a direction whose lock already matches is a
      no-op-with-INFO. Neither direction touches `.zskills/` runtime
      state (claim markers etc. are lane-independent). See
      `docs/plans/PLUGIN_DISTRIBUTION.md` (D25) and `docs/guides/switching-install-lanes.md`
      for the Abort/Rollback path.

**Preset keywords (bare word, anywhere in the args):**

Presets are **config-only**: they set `execution.landing` and
`execution.main_protected` in `.claude/zskills-config.json`. The
main-push gate in `block-unsafe-generic.sh` is no longer set by the preset
— the hook reads `execution.main_protected` from config at runtime
(fail-closed). Everything else in `zskills-config.json` is preserved.

| Preset | `execution.landing` | `execution.main_protected` | push gate (derived at runtime) |
|---|---|---|---|
| `cherry-pick` (default) | `cherry-pick` | `false` | allow |
| `locked-main-pr` | `pr` | `true` | block |
| `direct` | `direct` | `false` | allow |

Behavior by invocation:
- `/update-zskills <preset>` (a **bare** preset — a preset keyword with NO
  `install` mode token) — **config-only**. Overwrite ONLY the two
  preset-owned fields above (`execution.landing`,
  `execution.main_protected`) in `.claude/zskills-config.json`; every
  other field (branch_prefix, tests, CI, dev_server, UI patterns,
  timezone, min_model) is preserved. **Do NOT audit, pull, or update
  skills** — a bare preset is a pure landing-mode switch, not a refresh.
  No greenfield prompt. After writing, print a config-only confirmation
  (see "Config-only confirmation + version nudge" below) that makes clear
  nothing was pulled, plus a best-effort version-availability nudge. See
  the dedicated **`### Bare-preset config-only short-circuit`** step for
  the algorithm.
- `/update-zskills install <preset>` (a preset composed with the explicit
  `install` mode token) — install AND set config: run the full install
  (audit + fill all gaps) AND apply the preset via Step F. Unchanged.
- `/update-zskills` **and no existing `.claude/zskills-config.json`** —
  ask the user the greenfield prompt (see Step 0.6), then apply the
  chosen preset and write the config (as part of the install/update pass).
- `/update-zskills` **and existing config, no preset arg** — respect the
  existing config; do NOT re-ask. This is the idempotent re-install /
  update path (smart detection — audit + pull + update). Unchanged.

**Add-on flags:**
- `--with-addons` — install/update core skills + ALL available add-on packs
- `--with-block-diagram-addons` — install/update core skills + block-diagram
  add-on (3 skills: `/add-block`, `/add-example`, `/model-design`)

Without an add-on flag, only the 25 core skills are installed/updated.
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

| `$PRESET_ARG` | `execution.landing` | `execution.main_protected` |
|---|---|---|
| `cherry-pick` | `"cherry-pick"` | `false` |
| `locked-main-pr` | `"pr"` | `true` |
| `direct` | `"direct"` | `false` |

These two config fields are **preset-owned**. (The main-push gate in
`block-unsafe-generic.sh` derives from `main_protected` at runtime — it is
not a value the preset writes.) When `$PRESET_ARG` is
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
   update paths). Step F runs `.claude/skills/update-zskills/scripts/apply-preset.sh` which is
   **config-only** — it sets the two preset-owned config fields
   (`execution.landing`, `execution.main_protected`) atomically,
   including idempotency, JSON formatting variance, and a missing
   `execution` key. It does NOT touch the hook; `block-unsafe-generic.sh`
   reads `main_protected` from config at runtime. Don't attempt a manual
   `Edit` here — the script is the single source of truth.

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
     }
   }
   ```
   Substitute the three preset-owned placeholders (`<preset.landing>`,
   `<preset.main_protected>`) using the Step 0.25 mapping table. Fields
   left empty by auto-detection stay as empty strings — the install
   summary's test-setup blurb tells the user what to fill in later.

4. **No hook edit needed.** The config's `execution.landing`
   and `execution.main_protected` placeholders above are substituted
   in at write time, and `block-unsafe-generic.sh` reads
   `main_protected` from config at runtime to decide whether to block
   a push to `main`/`master` (fail-closed). **Step F — Apply Preset** is
   config-only and does not touch the hook. Nothing to do here.

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
questions — the two-field config mapping (landing + main_protected) in
Step 0.25 is final. In particular, we do **not** ask "do you want the
main-push block on?" for `locked-main-pr`: `main_protected=true` is the
single source of truth — `block-unsafe-project.sh` blocks agent commits,
cherry-picks, and pushes on main, and `block-unsafe-generic.sh` derives
its push gate from the same `main_protected` value at runtime, so the
push block is not a separate user-facing choice.

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
- `apply-preset.sh` — required by the preset UX (Step F); **config-only** — updates `execution.landing`/`execution.main_protected` in config (the hook reads `main_protected` at runtime; apply-preset does not touch it)
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
  - /briefing: requires `.claude/skills/briefing/scripts/briefing.py` (not found)
  ...

Overall: X/Y dependencies satisfied.
```

After printing `Overall: ...`, append a one-line **Versions** summary
showing the installed `zskills_version` (consumer-side) vs the source
clone's latest tag (authoritative), plus how many skills have a different
`metadata.version` upstream. Compute it like this:

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# Repo-level version: latest YYYY.MM.N tag in the source clone.
current_zskills_ver=$(bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/resolve-repo-version.sh" "$ZSKILLS_PATH")

# Installed version: top-level `zskills_version` field in
# .claude/zskills-config.json. Read with inline BASH_REMATCH (NOT
# frontmatter-get.sh — that helper is YAML-only and exits 2 on JSON;
# silencing that with `2>/dev/null` would be the anti-CLAUDE.md
# "swallow failures" pattern. Same JSON-parsing idiom as
# zskills-resolve-config.sh — single source of truth.)
installed_zskills_ver=""
if [ -f "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json" ]; then
  cfg=$(cat "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json")
  if [[ "$cfg" =~ \"zskills_version\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    installed_zskills_ver="${BASH_REMATCH[1]}"
  fi
fi

# Per-skill delta: count rows whose `metadata.version` differs upstream.
delta_tsv=$(bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/skill-version-delta.sh" "$ZSKILLS_PATH")
n_changed=$(printf '%s\n' "$delta_tsv" | awk -F'\t' '$5 == "bumped" || $5 == "new"' | wc -l)
```

Render (print the lines verbatim, substituting the three values; if
`current_zskills_ver` is empty, print the literal `(unversioned) — source
clone has no tags`; if `installed_zskills_ver` is empty, print `(none)`):

```text
Repo version: <installed_zskills_ver> → <current_zskills_ver>
Versions: zskills <installed_zskills_ver>→<current_zskills_ver>; <n_changed> skills changed
```

The `Repo version:` line uses the same label as the install/update
final reports (Step G / Pull Latest step 6) for cross-report
consistency; the `Versions:` line is the audit-specific one-liner that
also includes the per-skill delta count. Both surface the same
underlying data.

If the source clone has no tags (repo is unversioned): both lines
still print, just with the `(unversioned)` placeholder. This surfaces
the state instead of hiding it (CLAUDE.md surface-bugs rule). Same
applies to a pre-Phase-5 install with no `zskills_version` field —
print `(none)`; the install/Pull-Latest path will write the field on
its next run via the mirror-the-tag step (see Step F.5 / Pull Latest
step 5.7).

If everything is satisfied, end with:
```
Overall: Y/Y dependencies satisfied. Nothing to install.
```

If there are gaps and the skill is running in default or install mode,
proceed to fill them (see below). The audit report is always shown first
so the user sees what was found before any modifications.

---

## Step 0.7 — Lane check (plugin-lane short-circuit)

This branch runs after the arg parser (Step 0.25), config read (Step 0.5),
and the greenfield prompt (Step 0.6), and **at/above** the Default-Mode
Smart-Detection fork below. Explicit `--migrate-paths` already
short-circuited at Step 0.1; `--rerender` and `--switch-install-path` are a
user *forcing* a config/lane action and are **not** intercepted by the
hard-refuse below. The destructive case this branch prevents is the *silent*
flip of a pure-plugin consumer on a **bare** `/update-zskills` call: with no
`.claude/skills/` mirror, the audit would see every skill/hook as "missing"
and the gap-fill would copy them all in, flipping the consumer onto the
legacy lane.

**Policy reversal (W6.1) — explicit `install` / `--with-addons` is now
HARD-REFUSED on the plugin lane.** Earlier this branch let explicit `install`
through as an "opt-in" mirror action. That carve-out is removed: a client is
**single-lane**, so running `/update-zskills install` on a `detect ==
plugin` consumer is never the right move — it would re-create the legacy
mirror alongside the plugin and put the consumer into the dual state the rest
of the system actively pushes to consolidate. The refuse points the user at
`scripts/switch-install-path.sh` (the supported lane-switch path) and exits
non-zero. **Keyed on `detect_install_state == plugin`, NOT
`$CLAUDE_PLUGIN_ROOT`** — so the dev repo (which keeps its legacy mirror and
classifies `update-zskills`) is never blocked, and dogfooding both lanes from
this repo via `/update-zskills install` still works. The one carve-out: the
refuse is **SKIPPED while a lane switch is in progress** (see the
`switch-in-progress` marker below), so `switch-install-path.sh
--to-update-zskills` — which mandates `/plugin uninstall` → restart →
`/update-zskills install` — does not deadlock against its own
not-yet-completed switch.

**Signal = `detect_install_state == plugin`**, NOT `$CLAUDE_PLUGIN_ROOT`.
`lane == plugin` means "plugin-materialised artifacts present AND no legacy
`.claude/skills` mirror" — the exact flip-risk. `$CLAUDE_PLUGIN_ROOT` is
rejected: it is set in any `claude --plugin-dir .` session (including the
dev repo's legacy-lane dogfooding), so keying on it would make
`/update-zskills install` wrongly hit this branch and refuse to install.
`detect_install_state` answers "what's installed on disk", not "how was I
invoked." The dev repo has its legacy mirror present, so it classifies as
`update-zskills` and this branch **never fires** there.

**Resolve the lane (dual-locate + fail-soft).** `detect-install-state.sh`
is NOT mirrored into `.claude/hooks/_lib/` on the legacy lane, so locate it
under `$CLAUDE_PLUGIN_ROOT` or `$PORTABLE`; if it is unreachable, default
`LANE=update-zskills` (legacy behavior — safe, because the only unreachable
case is a pure-legacy session, which *should* proceed with legacy behavior
anyway; a pure-plugin consumer always has `$CLAUDE_PLUGIN_ROOT` set):

```bash
MAIN_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
DIS=""
if [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/detect-install-state.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  DIS="${CLAUDE_PLUGIN_ROOT}/hooks/_lib/detect-install-state.sh"
elif [ -n "${PORTABLE:-}" ] && [ -f "${PORTABLE}/hooks/_lib/detect-install-state.sh" ]; then
  DIS="${PORTABLE}/hooks/_lib/detect-install-state.sh"
fi
LANE="update-zskills"   # fail-soft default = legacy behavior (safe)
if [ -n "$DIS" ]; then . "$DIS"; LANE="$(detect_install_state "$MAIN_ROOT")"; fi
```

**If `LANE == plugin`:** do NOT run Step 0 asset-locate, the audit's
gap-fill (Steps A–G below), or any `.claude/`-mirroring step.

- **W6.1 hard-refuse — explicit `install` / `--with-addons` on the plugin
  lane.** If an explicit install arg was parsed (`$MODE == "install"` OR
  `$ADDON_FLAG` non-empty) AND no lane switch is in progress, REFUSE and exit
  non-zero. The `switch-in-progress` carve-out (W6.2) lets
  `scripts/switch-install-path.sh --to-update-zskills` run its mandated
  `/update-zskills install` step without tripping this refuse:

  ```bash
  if { [ "$MODE" = install ] || [ -n "$ADDON_FLAG" ]; } \
     && [ ! -f "${CLAUDE_PROJECT_DIR:-$PWD}/.zskills/switch-in-progress" ]; then
    echo "ERROR: refusing 'install' / '--with-addons' on the plugin lane." >&2
    echo "A client is single-lane. Running it here would re-create the legacy" >&2
    echo ".claude/skills mirror alongside the plugin (the dual state the system" >&2
    echo "actively pushes to consolidate). To switch lanes, run:" >&2
    echo "    bash scripts/switch-install-path.sh --to-update-zskills" >&2
    echo "  (or /update-zskills --switch-install-path=to-update-zskills)" >&2
    exit 1
  fi
  ```

  (The `switch-install-path.sh --to-update-zskills` flow writes
  `.zskills/switch-in-progress` at its START and removes it only after the
  lane-lock is written LAST, so this skip is active exactly for the duration
  of an in-flight switch and not in steady state.)

- **If a preset arg was parsed (`$PRESET_ARG` non-empty):** apply it
  **config-only** via the existing **Step F — Apply Preset** call (it is
  lane-portable — it edits only `.claude/zskills-config.json`, never the
  mirror):

  ```bash
  if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
  else
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  fi
  bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/apply-preset.sh" "$PRESET_ARG"
  ```

  Report the result verbatim per Step F's exit-code table (0 applied / 1
  no-change / 2 usage / 3 missing config / 4 malformed config), then print
  the config-only confirmation + best-effort version nudge from
  **`### Bare-preset config-only short-circuit`** below, and exit with the
  script's exit code. Do not proceed to the audit or any fill step.

- **Else (bare call, no preset):** FIRST run the bundled verifier's cheap
  structural tier, THEN print the plugin-lane explanation and exit 0.

  This is the plugin-lane analog of **`#### Step G.5 — Post-install
  verification`**: a read-only, NON-FATAL health check ("verify at install
  completion" equivalent) for the most-common single-lane install state. A
  bare `/update-zskills` on the plugin lane does no install work (the plugin
  manager owns skills/hooks/rules), but the consumer-side install can still
  be subtly broken (a registered hook resolving to nothing, an un-rendered
  `managed.md` carrying raw `{{TOKEN}}` placeholders, a dropped
  artifact/sentinel, an accidental dual-install). Running the verifier here
  surfaces that breakage even though there is no install/update path to wire
  Step G.5 into on this lane. It is **read-only and NON-FATAL** — it reports
  PASS/WARN/FAIL but never aborts and **cannot re-create the legacy
  `.claude/skills` mirror** (the verifier only inspects state). Run ONLY the
  cheap structural tier here — never `--deep` (the heavy live-`claude` probe
  is opt-in and must not run on a bare informational call). Resolve the
  verifier path lane-awarely, exactly as Step G.5 does:

  ```bash
  if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/verifiers/verify-install.sh" ]; then
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    VERIFY_INSTALL="${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/verifiers/verify-install.sh"
  else
    VERIFY_INSTALL="$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/verifiers/verify-install.sh"
  fi
  if [ -f "$VERIFY_INSTALL" ]; then
    # Cheap tier only (no --deep). Non-fatal: report, never abort.
    bash "$VERIFY_INSTALL" --project-dir "$CLAUDE_PROJECT_DIR" || \
      echo "(post-install verification reported a FAIL above — review and fix your environment)"
  else
    echo "(post-install verifier not found at $VERIFY_INSTALL — skipping verification)"
  fi
  ```

  THEN print the plugin-lane explanation and exit 0:

  ```
  You're on the plugin lane. Skills, hooks, and rules are plugin-managed —
  update them with `/plugin marketplace update`, not `/update-zskills`. To
  change landing mode here, run
  `/zs:update-zskills <cherry-pick|locked-main-pr|direct>` or edit
  `.claude/zskills-config.json` directly (config is the single source of
  truth for mode). To switch install lanes, use
  `scripts/switch-install-path.sh` (or
  `/update-zskills --switch-install-path=...`).
  ```

**Else** (`LANE` is `update-zskills`, `dual`, or `fresh`, OR detection was
unreachable): proceed to the existing behavior. **First** check for a bare
preset: if `$PRESET_ARG` is non-empty AND `$MODE` is NOT `install`, jump to
**`## Bare-preset config-only short-circuit`** (config-only — no audit, no
pull, no fill) and exit there. Otherwise (no preset, or `install <preset>`)
proceed to **Default Mode — Smart Detection** / Fill-All-Gaps **unchanged**.
The `dual` case is intentionally NOT given its own arm — the mirror already
exists, so gap-fill is a non-destructive update, and the materialiser +
`switch-install-path` already own dual detection/warning/recovery;
`/update-zskills` must not add its own dual handling.

`managed.md` is not touched by this branch — because the plugin arm skips
the entire gap-fill (including Step B's render), the sentinel-clobber
landmine (a sentinel-less re-render shifting `detect_install_state`) cannot
occur on this path.

---

## Bare-preset config-only short-circuit

**Runs on the legacy lane** (i.e. when Step 0.7's `Else` arm was taken —
`LANE` is `update-zskills`, `dual`, or `fresh`, OR detection was
unreachable) **when a bare preset was parsed**: `$PRESET_ARG` is non-empty
AND `$MODE` is NOT `install`. (On the plugin lane the equivalent
config-only apply already happened in Step 0.7's preset arm, which then
prints the same confirmation + nudge documented here.)

A bare preset is a **pure landing-mode switch** — write the two
preset-owned config fields and STOP. Do **NOT** run the audit, do **NOT**
pull the source clone for skill updates, do **NOT** render/fill any gap.
The full smart-detect update is reserved for `/update-zskills` (no preset)
and `/update-zskills install <preset>`.

**Step 1 — Apply the preset (config-only).** Run the same
`apply-preset.sh` invocation as Step F (it edits ONLY
`.claude/zskills-config.json` — `execution.landing` +
`execution.main_protected` — preserving every other field; it never
touches the hook or the mirror):

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/apply-preset.sh" "$PRESET_ARG"
```

Capture the exit code per Step F's table (0 applied / 1 no-change /
2 usage / 3 missing config / 4 malformed config).

**Step 2 — Config-only confirmation + version nudge.** Print a
confirmation that is EXPLICIT that nothing was pulled or updated, pointing
the user at the bare no-arg command for a real update:

```
Applied preset <name> (config only — no skills pulled or updated).
```

(For exit 1 / no-change, say `Preset <name> already applied — config
unchanged (no skills pulled or updated).` instead.)

**Version nudge (best-effort, offline-safe — reuse the existing
machinery, do NOT invent new comparison logic).** Reuse the SAME
resolve-repo-version + installed-`zskills_version` comparison the audit's
"Versions:" line uses (see `### Step 6 — Produce the gap report`). The
ONLY addition for this path is a best-effort `git fetch --tags` on the
source clone FIRST, so the comparison sees newly-published tags that the
local clone has not yet fetched:

```bash
# Best-effort tag refresh on the source clone (offline-safe). The source
# clone is $ZSKILLS_PATH when Step 0 resolved a git clone; if it is unset,
# not a git repo, or the fetch fails (no network / no remote), SKIP the
# nudge entirely — NEVER fail or abort the config write because of it.
if [ -n "${ZSKILLS_PATH:-}" ] && [ -d "$ZSKILLS_PATH/.git" ]; then
  git -C "$ZSKILLS_PATH" fetch --tags --quiet || true
fi
# Reuse the audit's resolve+read (single source of truth — same scripts):
current_zskills_ver=""
installed_zskills_ver=""
if [ -n "${ZSKILLS_PATH:-}" ]; then
  current_zskills_ver=$(bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/resolve-repo-version.sh" "$ZSKILLS_PATH")
fi
if [ -f "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json" ]; then
  cfg=$(cat "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json")
  if [[ "$cfg" =~ \"zskills_version\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    installed_zskills_ver="${BASH_REMATCH[1]}"
  fi
fi
```

Print the nudge line **ONLY when the installed version is strictly behind
the latest available tag** (both versions present AND
`installed_zskills_ver` sorts before `current_zskills_ver` under `sort
-V`). When the fetch fails, there is no source clone, there are no tags,
the installed version is unknown, or installed ≥ current — **silently skip
the nudge** (print nothing extra; the config write already succeeded):

```
zskills <installed_zskills_ver> → <current_zskills_ver> available. Run /update-zskills (no args) to pull + update.
```

**Step 3 — Exit.** Exit with `apply-preset.sh`'s exit code. Do NOT proceed
to the audit, Default Mode — Smart Detection, or any fill/update step.

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

2. **Render the template** via the canonical renderer (D24 — one
   substitution map, three callers; no LLM-prose substitution). Run:
   `python3 "$PORTABLE/scripts/render-managed-rules.py" --config .claude/zskills-config.json --template "$PORTABLE/CLAUDE_TEMPLATE.md" --out .claude/rules/zskills/managed.md`.
   The renderer imports `scripts/managed_rules_substitution.py` (the single
   source-of-truth `build_substitutions` + `apply` map), substitutes every
   `{{PLACEHOLDER}}` from current `.claude/zskills-config.json` values
   (empty `dev_server.cmd` / `ui.auth_bypass` / `testing.file_patterns`
   render the documented TODO fallbacks), and exits non-zero rather than
   ship a broken `{{...}}` token. This step both substitutes AND writes the
   rendered content (step 3's write is performed by the renderer's
   atomic-rename `--out`).

3. **The renderer's `--out` writes** `.claude/rules/zskills/managed.md`
   atomically (step 2 performs the write). Full overwrite is safe by
   ownership rule — zskills owns this file in full; no user content
   ever lives here. The file is regenerated from template + config on
   every install and every `--rerender`. The renderer never leaves broken
   `{{PLACEHOLDER}}` strings (it exits non-zero instead).

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

#### Step C — Fill hook + agent gaps

Copy missing hooks from `$PORTABLE/hooks/` to `.claude/hooks/`.

<!-- hooks/_lib/git-tokenwalk.sh is the source-of-truth for hooks/block-unsafe-*.sh* helpers. Inlined into each hook; DO NOT install separately. -->


- For `block-unsafe-project.sh.template`: copy to
  `.claude/hooks/block-unsafe-project.sh`. No install-time placeholder
  fill needed — the hook reads `testing.unit_cmd`, `testing.full_cmd`,
  and `ui.file_patterns` from `.claude/zskills-config.json` at runtime
  via bash regex (same idiom as `is_main_protected()`). Just copy the
  source template.
- For `block-unsafe-generic.sh`, `block-agents.sh.template`,
  `warn-config-drift.sh`: copy as-is. Wired into `settings.json` per
  the canonical zskills-owned triples table below.
- For `inject-bash-timeout.sh`: copy to
  `.claude/hooks/inject-bash-timeout.sh`. **No `settings.json` entry**
  — this hook is loaded via the `.claude/agents/verifier.md`
  frontmatter `hooks.PreToolUse` declaration (Layer 0 timeout-injection
  for verifier subagent Bash calls). Auto-discovered when the agent
  definition is loaded at session start.
- For `verify-response-validate.sh`: copy to
  `.claude/hooks/verify-response-validate.sh`. **No `settings.json`
  entry** — this hook is invoked directly from dispatcher SKILL.md
  files (Layer 3 universal verifier-response failure-protocol
  primitive). Standard executable shell script, called as
  `bash .claude/hooks/verify-response-validate.sh ...` from skill
  prose.
- For `block-stale-skill-version.sh`: copy as-is from `$PORTABLE/hooks/` to `.claude/hooks/`.
- For `block-bad-cron.sh`: copy as-is from `$PORTABLE/hooks/` to
  `.claude/hooks/`. Wired into `settings.json` as PreToolUse on the
  `CronCreate` matcher (see canonical-triples table below). Rejects
  one-shot crons whose next-fire is in the past or > 7 days out
  (closes a TZ-confusion class of "the cron never fired" bugs; PR #456).
- For `block-main-edits.sh`: copy as-is from `$PORTABLE/hooks/` to
  `.claude/hooks/`. Wired into `settings.json` as PreToolUse on the
  `Edit|Write` matcher (see canonical-triples table below).
  Honors `execution.main_protected` from `.claude/zskills-config.json` —
  denies edits to files inside the main repo working tree when
  `main_protected: true`, with narrow allowlists for `.zskills/` and
  gitignored worktree-state markers (issue #308).
- For `block-fix-issue-unclaimed.sh`: copy as-is from `$PORTABLE/hooks/`
  to `.claude/hooks/`. Wired into `settings.json` as PreToolUse on the
  `Bash` matcher (see canonical-triples table below). Backstops the
  `/fix-issues` inline-acquire prose — denies any Bash invocation of
  `create-worktree.sh` / `ensure-worktree.sh` whose resolved branch
  matches `fix-issue-NNN` or `fix/issue-NNN` and lacks a matching
  `.zskills/claims/issue-NNN/` claim directory
  (plans/fix-issues-claims.md Phase 2, W2.2c).
- For `block-run-plan-unclaimed.sh`: copy as-is from `$PORTABLE/hooks/`
  to `.claude/hooks/`. Wired into `settings.json` as PreToolUse on the
  `Bash` matcher (see canonical-triples table below). Backstops the
  `/run-plan` inline plan-claim-acquire prose — denies any Bash
  invocation of `create-worktree.sh` / `ensure-worktree.sh` whose
  resolved branch matches one of the three `/run-plan` shapes
  (`cp-<slug>`, `cp-<slug>-phase-<N>`, or `${BRANCH_PREFIX}<slug>` for
  PR mode) and lacks a matching `.zskills/plan-claims/<slug>/` claim
  directory (plans/plans-claim-chip-parity.md Phase 2; PR #544).
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

The `inject-bash-timeout.sh` and `verify-response-validate.sh` hooks
have NO entries in the canonical zskills-owned triples table below
(they are not registered via `settings.json`). They are loaded via the
`.claude/agents/verifier.md` frontmatter PreToolUse declaration AND
via direct skill invocation in dispatcher SKILL.md files. Copy them to
`.claude/hooks/` only — do not register them.

**Custom subagent definitions.** After hook copy, copy missing or
changed agent definitions from `$PORTABLE/.claude/agents/*.md` to
`$PROJECT_DIR/.claude/agents/`. `cp -a` preserves mode bits + mtime.
The agent frontmatter references
`$CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh` — that path
is fixed, so the hook-copy step (above) is a hard prerequisite.

```bash
if [ -d "$PORTABLE/.claude/agents" ]; then
  mkdir -p .claude/agents
  for src in "$PORTABLE/.claude/agents"/*.md; do
    [ -e "$src" ] || continue
    name=$(basename "$src")
    dst=".claude/agents/$name"
    if [ ! -f "$dst" ]; then
      cp -a "$src" "$dst" && echo "Installed agent: $name"
    elif ! cmp -s "$src" "$dst"; then
      cp -a "$src" "$dst" && echo "Updated agent: $name"
    fi
  done
  echo "WARN: agent definitions auto-discover at session start. Restart Claude Code (or open a new session) before invoking verifier-using skills (/run-plan, /commit, /fix-issues, /do, /verify-changes). There is no in-session reload command."
fi
```

**No settings.json wiring needed for agents.** Auto-discovered.
**Bash regex parse only — no `jq`.** (Hook scripts may use Python;
`inject-bash-timeout.sh` does, per zskills convention exemption for
JSON round-trip.)

**Consumer-customization handling:** if a consumer edits
`.claude/agents/verifier.md`, the next install OVERWRITES with source
(idempotent `cmp -s` gate ensures only changed files are touched).
Document this expectation: agent definitions are framework-owned, not
consumer-owned. Consumers wanting to customize verification behavior
should compose around the agent (wrap dispatch in their own skill),
not edit the agent definition file in place.

Note: hooks and helper scripts read `testing.*`, `ui.file_patterns`,
and `dev_server.main_repo_path` from `.claude/zskills-config.json` at
runtime. No install-time fill needed. Only copy the source template.

**Explain what each hook does** so the user understands what's being added:

> Installing 3 PreToolUse Bash safety hooks (commit-time + pre-tool-execution gates):
> - **block-unsafe-generic.sh** — blocks destructive commands (`git reset --hard`, `rm -rf`, `kill -9`, `git checkout --`, `--no-verify`, etc.) and discipline violations (`git add .`).
> - **block-unsafe-project.sh** — project-specific guards: prevents piping test output (must capture to file), verifies tests ran before commit, optionally checks for UI verification before committing UI changes, enforces tracking discipline.
> - **block-stale-skill-version.sh** — denies `git commit` when staged skill files have a stale `metadata.version` hash; reuses `scripts/skill-version-stage-check.sh`.
>
> See the canonical table below for the full hook set (additionally: PreToolUse `Agent` matcher → `block-agents.sh`; PostToolUse `Edit`/`Write` matchers → `warn-config-drift.sh`).

**Main-push block (config-derived):** `block-unsafe-generic.sh`
blocks `git push` to `main`/`master` when `BLOCK_MAIN_PUSH=1` — a value the
hook **derives at runtime** from `execution.main_protected` in
`.claude/zskills-config.json` (fail-closed: defaults to `1`/block when the
config is absent or unreadable). The preset sets `main_protected` in config
(Step F is config-only); the hook reads it. No hook edit here in Step C.
Effective mapping: `cherry-pick`/`direct` → `main_protected:false` → allow
push; `locked-main-pr` → `main_protected:true` → block push.

**Note on tracking enforcement:** The tracking enforcement section in
`block-unsafe-project.sh` (protecting `.zskills/tracking/`, blocking
`clear-tracking.sh` execution, and enforcing delegation/step verification)
has no placeholders — it works out of the box. No configuration needed.

**Add tracking directory to `.gitignore`:** During installation, add
`.zskills/tracking/` to the project's `.gitignore` if not already present.
Tracking files are ephemeral session state and should never be committed.

**Add `.zskills/dev-server.pid` and `.zskills/dev-server.log` to
`.gitignore`:** Also add these lines if not already present.
`scripts/stop-dev.sh` reads PIDs from `.zskills/dev-server.pid` (written
by the project's dev server launcher); PID files are per-worktree runtime
state and must never be committed.

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
| PreToolUse   | Bash    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-stale-skill-version.sh"`      |
| PreToolUse   | Bash    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-bypassed-land-pr.sh"`         |
| PreToolUse   | Bash    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-fix-issue-unclaimed.sh"`      |
| PreToolUse   | Bash    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-run-plan-unclaimed.sh"`       |
| PreToolUse   | Agent   | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-agents.sh"`                   |
| PreToolUse   | CronCreate | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-bad-cron.sh"`              |
| PreToolUse   | Edit\|Write | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-main-edits.sh"` |
| PostToolUse  | Edit    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/warn-config-drift.sh"`              |
| PostToolUse  | Write   | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/warn-config-drift.sh"`              |

All 11 rows carry `"type": "command"` and `"timeout": 5`. The
`warn-config-drift.sh` hook lands in Phase 3 of
`plans/DRIFT_ARCH_FIX.md`; the two PostToolUse rows become live once
that hook is installed.

**Session-init-only `settings.json` load (#460).** `.claude/settings.json`
is loaded ONCE at session start. The in-memory hook table is fixed at
session-init time; mid-session edits to `settings.json` — including
this install/update step landing a new hook registration — are NOT
re-read by the running session. Consequence: any newly registered hook
will not fire in the current session, even though the registration is
correctly on disk. Past failure: PR #456 landed `block-bad-cron.sh` at
06:18 UTC 2026-05-20; the orchestrator session whose lifetime predated
the merge made a bad `CronCreate` call at 07:16 UTC and the hook did
not fire (issue #460). Issue author confirmed via post-restart
live-fire that the hook DOES fire on built-in `CronCreate` calls once
the session sees the registration. After this Step C completes,
**always report the session-restart instruction to the user**:

> WARN: settings.json is loaded at session start. Hook registrations
> added by this step will not take effect until you `/clear` (or
> restart Claude Code). To verify a newly registered PreToolUse hook,
> restart your session and re-trigger the gated tool call; the deny
> envelope (if any) confirms the hook is wired.

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

   Then append the agent + non-settings-wired hook install summary:

   > Installed agents:
   > - verifier (from .claude/agents/verifier.md, Layer 0 timeout-injection hook)
   >
   > Installed hook scripts (D'' structural defense):
   > - .claude/hooks/inject-bash-timeout.sh (Layer 0 — auto-extends Bash timeout to 600000 ms for verifier subagent)
   > - .claude/hooks/verify-response-validate.sh (Layer 3 — universal verifier-response failure-protocol primitive)
   >
   > Drift check: each .md is byte-equivalent to source.
   > Drift check: each hook script is byte-equivalent to source.

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
  replaces (contract: read PIDs from `.zskills/dev-server.pid`,
  SIGTERM each). Pair: `start-dev.sh`.
- Copy `test-all.sh` if missing — invoked by `/run-plan`,
  `/verify-changes`, etc. when `testing.full_cmd` is
  `bash scripts/test-all.sh`. Initial install is a failing
  stub the user replaces.
- Copy `start-dev.sh` if missing — sanctioned way to start a
  dev server. Initial install is a failing stub the user
  replaces with their start command (and a write to
  `.zskills/dev-server.pid`).
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
- Install the 4 skill-version helpers required by
  `block-stale-skill-version.sh` (the PreToolUse hook installed in
  **Step C** above) by invoking the shared driver:

  ```bash
  bash "$PORTABLE/scripts/install-helpers-into.sh" "$CONSUMER_ROOT"
  ```

  Step A (`Locate portable assets`, SKILL.md line 685) provides
  `$PORTABLE` pointing at the zskills source clone —
  `$PORTABLE/scripts/install-helpers-into.sh` resolves correctly because
  the driver lives in the source repo's `scripts/` (not under any
  skill's `scripts/`). The driver is invoked SOURCE-SIDE from
  `$PORTABLE`; no consumer-local copy of the driver itself is needed
  (avoids the chicken-and-egg of a self-copying installer).

  These four helpers (`skill-version-stage-check.sh`,
  `skill-content-hash.sh`, `frontmatter-get.sh`, `frontmatter-set.sh`)
  are dependencies of `block-stale-skill-version.sh` (the PreToolUse
  hook installed in **Step C** above). Without them, the hook
  fails-open on every commit, defeating the lock-step skill-version
  enforcement chain. The `install-helpers-into.sh` driver is the same
  one exercised by `tests/test-block-stale-skill-version-sandbox.sh`,
  so the install path and the test path share code. Collision policy:
  existing identical helpers are skipped; existing different helpers
  are overwritten; logged either way.

  The driver's per-file `SKIP:` / `COPY:` log feeds the count in the
  `Report: "Installed N scripts: [list]"` output below — list each
  helper that was COPYed (a SKIP is a no-op and does not increment
  N).

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
  append-backfill-phase.sh
  append-tests-section.sh
  apply-preset.sh
  briefing.py
  clear-tracking.sh
  compute-cron-fire.sh
  convergence-check.sh
  coverage-floor-precheck.sh
  create-worktree.sh
  defer-backoff-decide.sh
  detect-language.sh
  draft-orchestrator.sh
  flip-frontmatter-status.sh
  gap-detect.sh
  insert-prerequisites.sh
  insert-test-spec-revisions.sh
  land-phase.sh
  migrate-paths.sh
  parse-plan.sh
  plan-drift-correct.sh
  port.sh
  post-run-invariants.sh
  re-invocation-detect.sh
  review-loop.sh
  sanitize-pipeline-id.sh
  statusline.sh
  sync-pr-body-progress.sh
  verify-completed-checksums.sh
  worktree-add-safe.sh
  write-landed.sh
  zskills-paths.sh
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
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/apply-preset.sh" "$PRESET_ARG"
```

Capture stdout and the exit code. Report to the user verbatim:
- Exit 0: "Applied preset '<name>':" followed by the list of changes
  the script reported.
- Exit 1: "Preset '<name>' already applied — no changes needed."
- Exit 2/3/4: print the script's error message and halt; these only
  fire when an unknown preset was somehow passed (2), the config file is
  missing (3), or the config JSON is malformed (4). apply-preset is
  config-only — it does not read or edit the hook. In that case, advise
  the user and do not continue.

**Why a script and not a series of `Edit` calls in the SKILL.md?**
The script is deterministic, idempotent, and unit-tested
(`tests/test-apply-preset.sh` covers missing `execution` keys, compact
JSON, idempotency, error paths, and asserts the hook is left untouched).
A prompt-side sequence of `Edit` calls is fragile against JSON
formatting variance. Delegate to the script.

#### Step F.5 — Mirror the source-repo tag into config

Now that all skills, hooks, scripts, and add-ons have been installed
from the current source clone, mirror the clone's latest tag into
`.claude/zskills-config.json` as the consumer-side `zskills_version`.
This is what the audit gap report (Step 6) and `/briefing` "Z Skills
Update Check" read to detect drift on subsequent invocations:

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
new_repo_ver=$(bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/resolve-repo-version.sh" "$ZSKILLS_PATH")
if [ -n "$new_repo_ver" ]; then
  bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/json-set-string-field.sh" \
    "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json" zskills_version "$new_repo_ver"
fi
```

If the source clone has no tags (`new_repo_ver` empty), skip silently —
nothing authoritative to mirror. The audit will print `(unversioned)`
on the next invocation, which surfaces the state without falsely
recording a stale tag.

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
- /briefing: requires `.claude/skills/briefing/scripts/briefing.py` (see /briefing skill docs)

Repo version: <new_zskills_ver>

Per-skill versions:
  <name>          <metadata.version>  (new)
  <name>          <metadata.version>  (new)
  ...

Run /update-zskills to check for updates later.
```

The **Per-skill versions** sub-section is generated by piping
`skill-version-delta.sh` output through awk. For an install, every
row's status is `new` (the prior installed state was empty). Only show
`addon`-kind rows when `--with-block-diagram-addons` (or
`--with-addons`) was passed OR when at least one block-diagram skill
is already present under `.claude/skills/`; otherwise filter them out.
Same renderer logic as the update-path table (see Pull Latest step 6).

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
delta_tsv=$(bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/skill-version-delta.sh" "$ZSKILLS_PATH")
show_addons=0
case "$ARGS" in *--with-addons*|*--with-block-diagram-addons*) show_addons=1 ;; esac
[ "$show_addons" = 0 ] && [ -d "$ZSKILLS_SKILLS_ROOT/add-block" ] && show_addons=1
printf '%s\n' "$delta_tsv" | awk -F'\t' -v show_addons="$show_addons" '
  $2 == "addon" && show_addons == 0 { next }
  { printf "  %-20s %s  (%s)\n", $1, $3, $5 }
'
```

`Repo version: <new_zskills_ver>` reflects the freshly mirrored
`zskills_version` from Step F.5 (or `(unversioned)` if the source clone
had no tags).

#### Step G.5 — Post-install verification (#999, cheap tier, NON-FATAL)

After the final report, run the bundled consumer post-install verifier's
**cheap structural tier** and append its result to the success output. This
catches the consumer-side of the dogfood-mask (#799/#831): environment-specific
install breakage that dev-repo tests structurally cannot see (a registered hook
that resolves to nothing, an un-rendered `managed.md` carrying raw `{{TOKEN}}`
template placeholders, a dropped artifact/sentinel, an accidental dual-install).
Per the zero-false-positive bar (#1004) it NEVER flags the renderer's designed
`<!-- TODO -->` comments for unset OPTIONAL config, nor a missing
`zskills_version` (an untagged source clone legitimately lacks one) — a FAIL
always means the install is genuinely broken, never that an optional setting is
unconfigured.

**NON-FATAL — informative only.** The install already succeeded; this
verification reports PASS/WARN/FAIL but **does NOT undo or fail the install**.
A FAIL is surfaced to the user (so they can fix their environment) but the
install stands. Run ONLY the cheap tier here — never `--deep` (the heavy
live-`claude` probe is opt-in and must not run on the success path).

Resolve the verifier path lane-awarely (it ships at
`.claude/skills/update-zskills/verifiers/` on the legacy lane,
`${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/verifiers/` on the plugin lane):

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/verifiers/verify-install.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  VERIFY_INSTALL="${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/verifiers/verify-install.sh"
else
  VERIFY_INSTALL="$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/verifiers/verify-install.sh"
fi
if [ -f "$VERIFY_INSTALL" ]; then
  # Cheap tier only (no --deep). Non-fatal: capture and report, never abort.
  bash "$VERIFY_INSTALL" --project-dir "$CLAUDE_PROJECT_DIR" || \
    echo "(post-install verification reported a FAIL above — the install still succeeded; review and fix your environment, then re-run /update-zskills to re-verify)"
else
  echo "(post-install verifier not found at $VERIFY_INSTALL — skipping verification)"
fi
```

Report the verifier's per-check output and overall result as a final block of
the success message. On WARN-only, note it's informative; on FAIL, tell the
user the install succeeded but verification flagged an environment issue.

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
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/apply-preset.sh" "$PRESET_ARG"
   ```

   Capture stdout and exit code; report verbatim to the user. This is
   the single place where preset values land into config and hook —
   regardless of install/update path.

5.7. **Mirror the source-repo tag into config.** Same step as install
   path Step F.5: capture the source clone's latest tag and write it
   into `.claude/zskills-config.json` as `zskills_version`. This is the
   value the audit report (Step 6) and `/briefing` "Z Skills Update
   Check" read on the next invocation:

   ```bash
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   new_repo_ver=$(bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/resolve-repo-version.sh" "$ZSKILLS_PATH")
   if [ -n "$new_repo_ver" ]; then
     bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/json-set-string-field.sh" \
       "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json" zskills_version "$new_repo_ver"
   fi
   ```

   Skip silently if the source clone has no tags.

6. **Report.** Replace the prior single-line `Updated: N skills (list)`
   summary with a structured table generated from
   `skill-version-delta.sh` (the same data source as `/briefing`'s
   update check). Each row shows `<name> <old metadata.version> →
   <new metadata.version>` for changed skills, and `<name>
   <metadata.version> (unchanged)` for the rest. Example shape (the
   shown date+hash literals are illustrative — the actual values come
   from `skill-version-delta.sh` against the source/install pair):

   ```text
   Z Skills updated.

   Repo version: <old_zskills_ver> → <new_zskills_ver>

   Updated: N skills
     run-plan          <old-ver>         → <new-ver>
     briefing          <old-ver>         → <new-ver>
     commit            <ver>             (unchanged)
     ...
   New: M items installed (list)

   Source: $ZSKILLS_PATH (pulled from origin)
   ```

   `<old_zskills_ver>` is the value of `zskills_version` BEFORE Step
   5.7's mirror — capture it at the start of the Pull Latest path
   using the same inline `BASH_REMATCH` JSON-read idiom as Step 6 (the
   audit gap report) so the table can show the delta. `<new_zskills_ver>`
   is what Step 5.7 just wrote.

   Generation pseudocode (pure bash + awk):

   ```bash
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   delta_tsv=$(bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/skill-version-delta.sh" "$ZSKILLS_PATH")
   show_addons=0
   case "$ARGS" in *--with-addons*|*--with-block-diagram-addons*) show_addons=1 ;; esac
   [ "$show_addons" = 0 ] && [ -d "$ZSKILLS_SKILLS_ROOT/add-block" ] && show_addons=1
   # Updated section (status=bumped: old → new), then unchanged:
   printf '%s\n' "$delta_tsv" | awk -F'\t' -v show_addons="$show_addons" '
     $2 == "addon" && show_addons == 0 { next }
     $5 == "bumped"   { printf "  %-20s %s → %s\n", $1, $4, $3 }
     $5 == "unchanged"{ printf "  %-20s %s (unchanged)\n", $1, $3 }
   '
   # New section (status=new):
   printf '%s\n' "$delta_tsv" | awk -F'\t' -v show_addons="$show_addons" '
     $2 == "addon" && show_addons == 0 { next }
     $5 == "new" { printf "  %s\n", $1 }
   '
   ```

   `(unversioned)` placeholder applies to either side of the `Repo
   version:` arrow if the corresponding tag is missing.

7. **Post-install verification (#999, cheap tier, NON-FATAL).** Same as
   install-path **Step G.5**: run the bundled consumer verifier's cheap
   structural tier and append its result. NON-FATAL — the update already
   succeeded; a verifier FAIL is reported (so the consumer can fix their
   environment) but never undoes the update. Cheap tier only (no `--deep`).

   ```bash
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/verifiers/verify-install.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     VERIFY_INSTALL="${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/verifiers/verify-install.sh"
   else
     VERIFY_INSTALL="$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/verifiers/verify-install.sh"
   fi
   if [ -f "$VERIFY_INSTALL" ]; then
     bash "$VERIFY_INSTALL" --project-dir "$CLAUDE_PROJECT_DIR" || \
       echo "(post-install verification reported a FAIL above — the update still succeeded; review and fix your environment, then re-run /update-zskills to re-verify)"
   fi
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
2. Render the template against current config via the canonical
   renderer (the SAME `render-managed-rules.py` invocation as Step B
   step 2 — D24, one substitution map, three callers): run
   `python3 "$PORTABLE/scripts/render-managed-rules.py" --config .claude/zskills-config.json --template "$PORTABLE/CLAUDE_TEMPLATE.md" --out .claude/rules/zskills/managed.md`.
   The renderer creates `.claude/rules/zskills/` if absent and writes the
   rendered content to `.claude/rules/zskills/managed.md` atomically (full
   overwrite — the file is zskills-owned, no user content lives here).
3. **Exit 0.** If the renderer exits non-zero (missing template, invalid
   config, or an unsubstituted placeholder), **exit 1** with its error.

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
   exists, skip it. The user may have customized it. (Presets do not edit
   any hook: `apply-preset.sh` is config-only, and
   `block-unsafe-generic.sh` derives its main-push gate from
   `execution.main_protected` at runtime.)
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
