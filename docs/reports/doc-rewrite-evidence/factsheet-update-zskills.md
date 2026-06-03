# Factsheet — docs/skills/update-zskills.md

Every factual claim in the rewritten doc, paired with a verbatim quote from
`skills/update-zskills/SKILL.md` (R1). Line numbers are against that file at
the HEAD this rewrite was derived from.

Companion-skill claims are additionally cross-checked against
`docs/reports/doc-rewrite-evidence/COMPANIONS.md` (R6, canonical companion
graph); those rows cite COMPANIONS.md as well.

---

## Summary (### What it does)

**Doc:** "Install or update the Z Skills supporting infrastructure: the CLAUDE.md agent rules, safety hooks, helper scripts, and skill dependencies the other skills rely on."
- `skills/update-zskills/SKILL.md:11-13`: `"Install or update the supporting infrastructure that Z Skills depend / on: CLAUDE.md agent rules, safety hooks, helper scripts, and skill / dependencies."`

**Doc:** "the agent rules file (`.claude/rules/zskills/managed.md`, which Claude Code loads automatically each session)"
- `skills/update-zskills/SKILL.md:1219-1221`: `"Claude Code / auto-loads everything under \`.claude/rules/\` recursively at session / start, so no \`@\`-import from root \`./CLAUDE.md\` is needed."`
- `skills/update-zskills/SKILL.md:1218`: `"**Target path:** \`.claude/rules/zskills/managed.md\` in the project."`

**Doc:** "the safety hooks under `.claude/hooks/`"
- `skills/update-zskills/SKILL.md:820`: `"Look in \`.claude/hooks/\` for these 2 files:"`

**Doc:** "the helper scripts under `scripts/`"
- `skills/update-zskills/SKILL.md:827`: `"Look in \`scripts/\` for these files (all required by installed skills):"`

**Doc:** "and the skill files themselves."
- `skills/update-zskills/SKILL.md:756`: `"List all \`.claude/skills/*/SKILL.md\` files. For each skill:"`

**Doc:** "Run with no arguments, it figures out which case you're in. If nothing is installed yet, it does a full first-time install. If Z Skills are already present, it pulls the latest versions, updates any skills that changed, and fills in anything new that's missing."
- `skills/update-zskills/SKILL.md:23-26`: `"Default mode (no argument): **smart detection** — if nothing is installed / yet, do a full install; if already installed, pull latest, update changed / skills, and fill new gaps."`
- `skills/update-zskills/SKILL.md:1200-1204`: `"- If no \`.claude/skills/\` directory exists, or it contains zero skills / -> treat as first-time install ... / - If skills are already installed -> treat as update"`

**Doc:** "it starts by auditing what's currently on disk and prints a report of what it found before changing anything — so you always see the gap analysis first. The audit itself never modifies files."
- `skills/update-zskills/SKILL.md:26-27`: `"Always begins with an audit and reports what / was found and what was done about it."`
- `skills/update-zskills/SKILL.md:750`: `"**The audit itself never modifies any files.**"`
- `skills/update-zskills/SKILL.md:961-962`: `"The audit report is always shown first / so the user sees what was found before any modifications."`

**Doc:** "On a first install it asks one question: how you want changes to land — directly to `main`, via cherry-pick from a worktree, or as pull requests on a protected `main`."
- `skills/update-zskills/SKILL.md:709-710`: `"**Run this only when** \`.claude/zskills-config.json\` does NOT exist AND / \`$PRESET_ARG\` is empty."`
- `skills/update-zskills/SKILL.md:718-722`: `"How should /run-plan land changes? / (1) cherry-pick — each phase squash-lands directly to main ... / (2) locked-main-pr — plans become feature branches + PRs ... / (3) direct — work on main, no worktree isolation"`

**Doc:** "Your answer is saved to `.claude/zskills-config.json` and drives the landing behavior of the execution skills from then on."
- `skills/update-zskills/SKILL.md:88-90`: `"Presets are **config-only**: they set \`execution.landing\` and / \`execution.main_protected\` in \`.claude/zskills-config.json\`."`
- `skills/update-zskills/SKILL.md:117`: `"chosen preset and write the config (as part of the install/update pass)."`

**Doc:** "On later runs it respects the config that's already there and does not re-ask."
- `skills/update-zskills/SKILL.md:118-120`: `"\`/update-zskills\` **and existing config, no preset arg** — / respect the / existing config; do NOT re-ask."`

**Doc:** "After it finishes, it reports what it installed or updated and a one-line version summary comparing your installed version against the latest available, including how many skills changed."
- `skills/update-zskills/SKILL.md:899-902`: `"append a one-line **Versions** summary / showing the installed \`zskills_version\` (consumer-side) vs the source / clone's latest tag (authoritative), plus how many skills have a different / \`metadata.version\` upstream."`
- `skills/update-zskills/SKILL.md:938`: `"Versions: zskills <installed_zskills_ver>→<current_zskills_ver>; <n_changed> skills changed"`

**Doc:** "The config file and the installed skills are the artifacts; there's no separate report file to read."
- (R3 raise-altitude restatement of) `skills/update-zskills/SKILL.md:896`: `"Overall: X/Y dependencies satisfied."` and `skills/update-zskills/SKILL.md:1265-1276` (the inline rendered report) — the skill prints its report inline and writes config + skills; no persisted report-file step exists in the body. Mirrors the equivalent statement validated in the landed `docs/skills/do.md:13`.

---

## Usage block

**Doc:** the `/update-zskills [install | --rerender | --migrate-paths | --switch-install-path=...] [cherry-pick | locked-main-pr | direct] [--with-addons | --with-block-diagram-addons]` block
- `skills/update-zskills/SKILL.md:18-21`: `"/update-zskills [install | --rerender | --migrate-paths | --switch-install-path={to-plugin|to-update-zskills}] / [cherry-pick | locked-main-pr | direct] / [--with-addons | --with-block-diagram-addons]"`

---

## Typical usage

**Doc:** "`/update-zskills install` to set a project up from scratch"
- `skills/update-zskills/SKILL.md:29-30`: `"\`install\` — force a full first-time setup (same as what the default / mode does when nothing is installed, but skips the detection step)"`

**Doc:** "a bare `/update-zskills` to pull the latest and refresh an existing install"
- `skills/update-zskills/SKILL.md:23-26`: `"Default mode (no argument): **smart detection** ... if already installed, pull latest, update changed / skills, and fill new gaps."`

**Doc:** "After you hand-edit `.claude/zskills-config.json`, run `/update-zskills --rerender` to regenerate the rules file from the new config."
- `skills/update-zskills/SKILL.md:31-33`: `"\`--rerender\` — regenerate \`.claude/rules/zskills/managed.md\` against / the current \`.claude/zskills-config.json\`."`

**Doc:** "To change only how changes land — without pulling or updating anything — pass a bare landing keyword like `/update-zskills locked-main-pr`."
- `skills/update-zskills/SKILL.md:100-106`: `"\`/update-zskills <preset>\` (a **bare** preset ...) — **config-only**. ... **Do NOT audit, pull, or update / skills** — a bare preset is a pure landing-mode switch, not a refresh."`

---

## Companion skills (R6 — cross-checked against COMPANIONS.md)

**Doc:** "`/update-zskills` is the setup skill that configures and is referenced by nearly every other skill"
- `COMPANIONS.md:96`: `"\`update-zskills\` | ... | The install/config skill; configures and is referenced by nearly every skill."`

**Doc:** "`/commit`, `/do`, `/quickfix`, `/fix-issues`, `/run-plan` — the execution skills whose landing behavior is governed by the `execution.landing` and `execution.main_protected` config fields that `/update-zskills` writes."
- `COMPANIONS.md:96`: companions list includes `commit`, `do`, `quickfix`, `fix-issues`, `run-plan`.
- `skills/update-zskills/SKILL.md:88-90`: `"they set \`execution.landing\` and / \`execution.main_protected\` in \`.claude/zskills-config.json\`."`

**Doc:** "`/create-worktree` — the shared worktree-setup helper installed and kept current as part of the infrastructure these skills call."
- `COMPANIONS.md:96`: companions list includes `create-worktree`.
- `COMPANIONS.md:78`: `"\`create-worktree\` | do, fix-issues, run-plan, commit, update-zskills | The shared worktree-setup primitive every isolation-using skill calls."`

**Doc:** "`/briefing`, `/plans`, `/zskills-dashboard` — status and catalog skills that depend on the Python helpers and config `/update-zskills` puts in place."
- `COMPANIONS.md:96`: companions list includes `briefing`, `plans`, `zskills-dashboard`.
- `skills/update-zskills/SKILL.md:769-770`: `"Python 3 is / required (per CLAUDE.md \"Python is required\"). Powers \`/briefing\`, / \`/plans rebuild\`, the dashboard, and other Python-only helpers."`

**Doc:** "`/verify-changes` — the change-soundness gate that, like the others, relies on the rules and test config this skill installs."
- `COMPANIONS.md:96`: companions list includes `verify-changes`.
- `skills/update-zskills/SKILL.md:1704-1706`: `"Copy \`test-all.sh\` if missing — invoked by \`/run-plan\`, / \`/verify-changes\`, etc. when \`testing.full_cmd\` is"` (verify-changes depends on installed test config).

---

## Arguments

**Doc (`install`):** "Force a full first-time setup, skipping the detect-what's-installed step"
- `skills/update-zskills/SKILL.md:29-30`: `"\`install\` — force a full first-time setup (same as what the default / mode does when nothing is installed, but skips the detection step)"`

**Doc (`--rerender`):** "Regenerate `.claude/rules/zskills/managed.md` from the current config only — no audit, no pull, no hook or script changes; never touches your root `./CLAUDE.md`"
- `skills/update-zskills/SKILL.md:31-35`: `"\`--rerender\` — regenerate \`.claude/rules/zskills/managed.md\` against / the current \`.claude/zskills-config.json\`. Simple full-file rewrite / of the zskills-owned rules file; root \`./CLAUDE.md\` is never touched. / No audit, no preset, no hooks/scripts touched."`

**Doc (`--migrate-paths`):** "One-time move of legacy artifacts into the standard layout (plan files under `docs/plans/`, issue trackers under `docs/issues/`, reports under `.zskills/audit/`); runs once and refuses to repeat"
- `skills/update-zskills/SKILL.md:36-43`: `"\`--migrate-paths\` — one-shot deterministic relocation of legacy / artifacts into the path-config layout (\`docs/plans/\` for plan files, / \`.zskills/audit/\` for forensic + narrative reports, \`docs/issues/\` / for issue trackers ... Idempotent — refuses to re-run if / \`.pre-paths-migration\` already exists."`

**Doc (`--switch-install-path=...`):** "Move a project between the two ways of consuming Z Skills, preserving its config and trackers; runs once per direction and is a no-op if already there"
- `skills/update-zskills/SKILL.md:53-56`: `"\`--switch-install-path={to-plugin|to-update-zskills}\` — the supported / entry point for switching a consumer between the two install lanes / (the plugin lane and the legacy \`/update-zskills\` lane)."`
- `skills/update-zskills/SKILL.md:79-81`: `"Idempotent: invoking a direction whose lock already matches is a / no-op-with-INFO. Neither direction touches \`.zskills/\` runtime / state (claim markers etc. are lane-independent)."`

**Doc (`cherry-pick`):** "Set landing to cherry-pick from a worktree onto an unprotected `main`"
- `skills/update-zskills/SKILL.md:95`: `"| \`cherry-pick\` (default) | \`cherry-pick\` | \`false\` | allow |"`

**Doc (`locked-main-pr`):** "Set landing to pull requests on a protected `main`"
- `skills/update-zskills/SKILL.md:96`: `"| \`locked-main-pr\` | \`pr\` | \`true\` | block |"`

**Doc (`direct`):** "Set landing to direct commits on an unprotected `main`"
- `skills/update-zskills/SKILL.md:97`: `"| \`direct\` | \`direct\` | \`false\` | allow |"`

**Doc (`--with-addons`):** "Also install/update the available add-on skill packs, not just the core skills"
- `skills/update-zskills/SKILL.md:123`: `"\`--with-addons\` — install/update core skills + ALL available add-on packs"`

**Doc (`--with-block-diagram-addons`):** "Like `--with-addons`, but limited to the block-diagram add-on pack"
- `skills/update-zskills/SKILL.md:124-126`: `"\`--with-block-diagram-addons\` — install/update core skills + block-diagram / add-on (3 skills: \`/add-block\`, \`/add-example\`, \`/model-design\`)"`

**Doc:** "a mode token, a landing keyword, and an add-on flag are independent and may appear together"
- `skills/update-zskills/SKILL.md:416-417`: `"Parser pseudocode (classify each token; presets, mode, and add-on flags / are orthogonal and can coexist):"`
- `skills/update-zskills/SKILL.md:435-438`: `"\`install\` + a preset keyword are compatible and combine ... \`--with-addons\` / \`--with-block-diagram-addons\` / are independent of the preset."`

**Doc:** "The three landing keywords (`cherry-pick`, `locked-main-pr`, `direct`) are mutually exclusive — pass at most one."
- `skills/update-zskills/SKILL.md:413-414`: `"If more than one is present, stop with an error: \"Specify exactly / one preset: cherry-pick, locked-main-pr, or direct.\""`

**Doc:** "A bare landing keyword on its own (no `install`) only rewrites the two landing-related config fields and leaves everything else, including the rest of your config, untouched; it does not pull or update skills."
- `skills/update-zskills/SKILL.md:100-106`: `"\`/update-zskills <preset>\` (a **bare** preset — a preset keyword with NO / \`install\` mode token) — **config-only**. Overwrite ONLY the two / preset-owned fields above ... every / other field ... is preserved. **Do NOT audit, pull, or update / skills**."`

**Doc:** "Paired with `install`, it sets the landing mode as part of the full install."
- `skills/update-zskills/SKILL.md:112-114`: `"\`/update-zskills install <preset>\` ... — install AND set config: run the full install / (audit + fill all gaps) AND apply the preset via Step F."`

**Doc:** "By default only the core skills are installed or updated."
- `skills/update-zskills/SKILL.md:127`: `"Without an add-on flag, only the 25 core skills are installed/updated."`

**Doc:** "Add `--with-addons` (or the narrower `--with-block-diagram-addons`) to also bring in the add-on packs — these are extra, domain-specific skills layered on top of the core set."
- `skills/update-zskills/SKILL.md:123-126`: (the two add-on-flag bullets quoted above).
- `docs/skills/update-zskills.md` (prior landed version) Tip: `"Add-on skills (\`--with-addons\`) provide domain-specific functionality"` — corroborating; primary cite is SKILL.md:123-126.

---

## Examples / Common Patterns / Tips

**Doc examples block** — every line is a literal invocation in the SKILL invocation grammar:
- `skills/update-zskills/SKILL.md:18-21` (invocation grammar) authorizes each example.
- Specific corroboration for the add-on + landing example lines: `skills/update-zskills/SKILL.md:123` (`--with-addons`), `:97` (`direct`), `:95-96` (`cherry-pick`/`locked-main-pr`).

**Tip:** "Every run begins with an audit and prints what it found before making any change"
- `skills/update-zskills/SKILL.md:26-27` + `:961-962` (quoted above).

**Tip:** "`--rerender` only rewrites `.claude/rules/zskills/managed.md`; it never modifies your root `./CLAUDE.md`."
- `skills/update-zskills/SKILL.md:33`: `"of the zskills-owned rules file; root \`./CLAUDE.md\` is never touched."`

**Tip:** "A bare landing keyword ... is a pure landing-mode switch — it changes only the two landing fields and does not pull or update skills."
- `skills/update-zskills/SKILL.md:106`: `"a bare preset is a pure landing-mode switch, not a refresh."`

**Tip:** "`--migrate-paths` runs once. It refuses to repeat after it has migrated, so re-running it is safe and does nothing."
- `skills/update-zskills/SKILL.md:42-43`: `"Idempotent — refuses to re-run if / \`.pre-paths-migration\` already exists."`
- `skills/update-zskills/SKILL.md:317-319`: `"**Idempotent re-run.** If \`.pre-paths-migration\` already exists, the / script prints \"already migrated\" and exits 0 without making any / changes."`

**Tip:** "On a first install you'll be asked once how changes should land; on later runs it respects the config already on disk and won't re-ask."
- `skills/update-zskills/SKILL.md:709-710` (greenfield prompt only when no config) + `:118-120` (respect existing config, do NOT re-ask) — both quoted above.

---

## R5 — internals NOT carried into prose (deliberate omissions)

These source concepts were stripped per R5 (internals voice) and are
intentionally absent from the doc: the SessionStart materialiser / the 5
materialised artifacts, `sentinel`-gated removal, `${CLAUDE_PLUGIN_ROOT}`,
`render-managed-rules.py` / `migrate-paths.sh` / `apply-preset.sh` /
`switch-install-path.sh` script names, `Phase Nx` / `Step 0.x` numbers,
`D24`/`D25` design refs, `lock-LAST`, `flock`, `BASH_REMATCH` parsing,
`detect_install_state` / lane-flip mechanics, and the dual-install probe.
The block-diagram add-ons appear ONLY as the `--with-addons` /
`--with-block-diagram-addons` flag note (per the plan's scope rule), never
documented as skills in their own right.
