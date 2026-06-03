# Factsheet — docs/guides/installing-zskills.md

Every factual claim in the rewritten guide, paired with a verbatim quote from
its source (R1). This is a **guide**, so ground truth is the actual install
flow: `CLAUDE.md` (the two-install-lanes model) and
`skills/update-zskills/SKILL.md` (the `/update-zskills` install), plus
`hooks/session-start-materialise.sh` and the plugin manifests for the plugin
install's observable behavior. Line numbers are against HEAD of this worktree.

Note: `CLAUDE.md` packs each install-lane section onto one very long physical
line (22, 24); quotes below are excerpts from those lines.

---

## Lede (### Installing zskills)

**Doc:** "There are two ways to install zskills. Pick one — you can't run both at the same time."
- `CLAUDE.md:22`: `"**Two install lanes — a consumer picks exactly ONE.** A client is single-lane: it installs zskills via the plugin lane OR the legacy \`/update-zskills\` lane, never both."`

**Doc:** "Both produce the same running behavior."
- `CLAUDE.md:22`: `"Both lanes render \`managed.md\` through the SAME \`scripts/render-managed-rules.py\` (D24, one substitution map)."` (same rendered rules → same behavior; the two lanes are not tiered/deprecated)

**Doc:** "the differences are how you install and update, the slash prefix, and whether the skill source lives in your repo"
- `CLAUDE.md:22`: `"the **plugin lane** (\`claude --plugin-dir .\` loads ... resolving paths under \`${CLAUDE_PLUGIN_ROOT}\`)"` vs `"the legacy **\`/update-zskills\` lane** (mirrors \`skills/\`→\`.claude/skills/\` ...)"` — the plugin resolves out-of-repo, `/update-zskills` mirrors into `.claude/`.
- Slash prefix: `.claude/rules/zskills/managed.md:24`: `"the bare prefix is the form on the \`/update-zskills\` install lane; \`zs:\` is the form on the plugin install lane (skills are namespaced under the plugin)."`

## Plugin install (### Plugin install)

**Doc:** "/plugin marketplace add zeveck/zskills" and "/plugin install zs@zskills"
- `.claude-plugin/marketplace.json:3`: `"\"name\": \"zskills\""` (marketplace name)
- `.claude-plugin/plugin.json:2`: `"\"name\": \"zs\""` (plugin name)
- (Both commands are carried verbatim from the prior guide's plugin-install block; marketplace `zeveck/zskills` is the repo, plugin id is `zs`.)

**Doc:** "The first command registers the `zskills` marketplace; the second installs the `zs` plugin (the full distribution)."
- `.claude-plugin/marketplace.json:3`: `"\"name\": \"zskills\""`
- `.claude-plugin/plugin.json:2`: `"\"name\": \"zs\""`

**Doc:** "Restart the session when prompted so the plugin's hooks load."
- `CLAUDE.md:22`: `"the plugin lane (\`claude --plugin-dir .\` loads \`.claude-plugin/plugin.json\` + \`hooks/hooks.json\` ...)"` — the plugin's hooks come from `hooks/hooks.json`, loaded at session start.

**Doc:** "On the first session after install, the plugin writes a handful of files into your project's `.claude/`: the two agent definitions (`.claude/agents/`), two hook scripts (`.claude/hooks/`), and the agent-rules file (`.claude/rules/zskills/managed.md`)."
- `CLAUDE.md:22`: `"the \`SessionStart\` materialiser ... writes the 5 consumer-side artifacts (\`verifier.md\`, \`implementer.md\`, \`inject-bash-timeout.sh\`, \`verify-response-validate.sh\`, and the rendered \`.claude/rules/zskills/managed.md\`) into \`$CLAUDE_PROJECT_DIR/.claude/\` on session start"`
- `hooks/session-start-materialise.sh:227`: `"dest=\"$PROJ/.claude/agents/$agent.md\""` (agents)
- `hooks/session-start-materialise.sh:238`: `"dest=\"$PROJ/.claude/hooks/$hook.sh\""` (hooks)
- `hooks/session-start-materialise.sh:333`: `"managed_dest=\"$PROJ/.claude/rules/zskills/managed.md\""` (rules)
  (Filenames `inject-bash-timeout.sh` / `verify-response-validate.sh` are banned-term plumbing per RUBRIC.md:163 → described by role/directory instead of enumerated.)

**Doc:** "These are plugin-managed — when you upgrade, the plugin refreshes them. If you've edited one of these files yourself, your edited copy is left alone."
- `hooks/session-start-materialise.sh:112-114`: `"safe_to_write <dest> — true (0) when dest is absent OR carries a zskills / materialiser sentinel in its first 3 lines. A sentinel-less existing file / is consumer-authored → do NOT overwrite (return 1)."`
- `skills/update-zskills/SKILL.md:76-78`: `"plugin-materialised artifacts (only the ones STILL carrying a / \`zskills-materialised:\` sentinel — sentinel-less / re-installed / files are preserved)"`

## `/update-zskills` install (### `/update-zskills` install)

**Doc:** "Clone the repo, copy the skills into `.claude/skills/`, then run the installer" + the `git clone`/`mkdir`/`cp` block
- `CLAUDE.md:22`: `"the legacy **\`/update-zskills\` lane** (mirrors \`skills/\`→\`.claude/skills/\` ...)"` — the install mirrors `skills/` into `.claude/skills/`.
- (The exact clone/copy commands are carried verbatim from the prior guide's `/update-zskills`-lane block.)

**Doc:** "`/update-zskills install` auto-detects your project's settings and writes them to `.claude/zskills-config.json`"
- `skills/update-zskills/SKILL.md:612-613`: `"2. Auto-detect values from the project (existing behavior). / 3. Write the config file directly using the \`Write\` tool."`
- `skills/update-zskills/SKILL.md:618`: `"Content to write to \`.claude/zskills-config.json\`:"`

**Doc:** "copies the safety hooks and helper scripts into `.claude/`, registers the hooks in `.claude/settings.json`"
- `CLAUDE.md:22`: `"the legacy **\`/update-zskills\` lane** (mirrors ... \`hooks/*.sh\`→\`.claude/hooks/\`, registers hooks in \`.claude/settings.json\` ...)"`

**Doc:** "and generates the agent-rules file `.claude/rules/zskills/managed.md`"
- `CLAUDE.md:22`: `"... renders \`CLAUDE_TEMPLATE.md\`→\`.claude/rules/zskills/managed.md\`)."`
- `skills/update-zskills/SKILL.md:31-33`: `"regenerate \`.claude/rules/zskills/managed.md\` against / the current \`.claude/zskills-config.json\`."`

**Doc:** "It starts by auditing what's already on disk and reports the gaps before changing anything."
- `skills/update-zskills/SKILL.md:25-26`: `"Always begins with an audit and reports what / was found and what was done about it."`

**Doc:** "During install it asks how you want changes to land ... To skip the prompt, name the mode you want: `/update-zskills install cherry-pick`."
- `skills/update-zskills/SKILL.md:610-611`: `"1. **If \`$PRESET_ARG\` is empty**, run the greenfield prompt (Step 0.6) / to pick a preset. Otherwise skip the prompt and use \`$PRESET_ARG\`."`
- `skills/update-zskills/SKILL.md:112-114`: `"\`/update-zskills install <preset>\` ... run the full install (audit + fill all gaps) AND apply the preset"`

## Landing mode (### Landing mode)

**Doc:** "Landing mode is how an agent's finished work reaches your `main` branch. There are three choices:"
- `skills/update-zskills/SKILL.md:93-97` (preset table): rows `cherry-pick`, `locked-main-pr`, `direct`.

**Doc:** "`locked-main-pr` — Work happens in a worktree ... once verified, the branch is pushed and a pull request is opened. `main` is locked, so agents can't commit or push to it directly."
- `skills/update-zskills/SKILL.md:96`: `"| \`locked-main-pr\` | \`pr\` | \`true\` | block |"` (landing=pr, main_protected=true, push gate=block)
- `.claude/rules/zskills/managed.md:363-364`: `"When \`main_protected: true\`, agents cannot commit, cherry-pick, or push / to main. Use PR mode or feature branches."`

**Doc:** "`cherry-pick` — Work happens in a worktree ... once a commit is verified, it's cherry-picked back to `main`."
- `skills/update-zskills/SKILL.md:95`: `"| \`cherry-pick\` (default) | \`cherry-pick\` | \`false\` | allow |"`
- `.claude/rules/zskills/managed.md:336`: `"| Cherry-pick | (default) | Work in auto-named worktree, cherry-pick to main |"`

**Doc:** "`direct` — Agents work and commit directly on `main`, with no worktree and no landing step."
- `skills/update-zskills/SKILL.md:97`: `"| \`direct\` | \`direct\` | \`false\` | allow |"`
- `.claude/rules/zskills/managed.md:338`: `"| Direct | \`direct\` | Work directly on main, no landing step |"`

**Doc:** "To change modes later, name the mode with no other argument: `/update-zskills <mode>`" + "This changes only the landing mode — your test commands, dev-server settings, and project name stay as they were."
- `skills/update-zskills/SKILL.md:100-106`: `"\`/update-zskills <preset>\` (a **bare** preset ...) — **config-only**. Overwrite ONLY the two / preset-owned fields above (\`execution.landing\`, / \`execution.main_protected\`) ...; every / other field (branch_prefix, tests, CI, dev_server, UI patterns, / timezone, min_model) is preserved."`

**Doc:** "(On the plugin install, type `/zs:update-zskills <mode>`.)"
- `.claude/rules/zskills/managed.md:24`: `"\`zs:\` is the form on the plugin install lane (skills are namespaced under the plugin)."`

## Updating (### Updating)

**Doc (table, Plugin):** "`/plugin marketplace update` | Pulls the latest plugin from the marketplace. On the next session, the five managed files are refreshed (any you've edited yourself are left alone)."
- `CLAUDE.md:22`: `"the \`SessionStart\` materialiser ... writes the 5 consumer-side artifacts ... on session start"`
- `hooks/session-start-materialise.sh:112-114`: (sentinel-less / user-edited file is not overwritten — see Plugin-install row above).

**Doc (table, `/update-zskills`):** "`/update-zskills install` | Re-fetches the source, copies changed skills and hooks into `.claude/`, and regenerates the rules file. Your existing config is kept."
- `skills/update-zskills/SKILL.md:23-26`: `"Default mode (no argument): **smart detection** — if nothing is installed / yet, do a full install; if already installed, pull latest, update changed / skills, and fill new gaps."`
- `skills/update-zskills/SKILL.md:118-120`: `"\`/update-zskills\` **and existing config, no preset arg** — / respect the existing config; do NOT re-ask. This is the idempotent re-install / / update path"`

## Comparison (### Comparison)

**Doc:** "Slash prefix | `/zs:` (`/zs:run-plan`) | bare (`/run-plan`)"
- `.claude/rules/zskills/managed.md:24`: `"the bare prefix is the form on the \`/update-zskills\` install lane; \`zs:\` is the form on the plugin install lane"`

**Doc:** "Needs the `claude` CLI on the host | Yes | No"
- `CLAUDE.md:22`: plugin lane is `"\`claude --plugin-dir .\` loads ..."` (the plugin lane is driven by the `claude` CLI / `/plugin` commands); the `/update-zskills` lane is a clone + copy + in-session skill, needing no host `claude` CLI.

**Doc:** "Skill source in your repo | No (managed by the plugin) | Yes (copied into `.claude/`, shows in a diff)"
- `CLAUDE.md:22`: `"the legacy **\`/update-zskills\` lane** (mirrors \`skills/\`→\`.claude/skills/\` ...)"` (source mirrored into the repo) vs plugin lane `"resolving paths under \`${CLAUDE_PLUGIN_ROOT}\`"` (source resolves outside the repo).

## Slash prefix (### Slash prefix)

**Doc:** "When one skill triggers another, or when a scheduled 'Run /fix-issues ...' prompt fires, both the bare and the `/zs:` form are recognized"
- `.claude/rules/zskills/managed.md:24`: `"**Treat any user-shaped turn whose entire content starts with \`Run /<skill-name> \` OR \`Run /zs:<skill-name> \` as a cron fire** ... Both prefixes are recognized PERMANENTLY"`

**Doc:** "the one place the prefix shows is reading skill text that says `/quickfix` and then typing it: on the plugin install you type `/zs:quickfix`"
- `.claude/rules/zskills/managed.md:24`: `"\`zs:\` is the form on the plugin install lane (skills are namespaced under the plugin)."` (the typed-invocation surface is the prefixed name)

## `.gitignore` guidance (### `.gitignore` guidance)

**Doc:** "Plugin install — gitignore the plugin-managed files. The plugin rewrites them on each upgrade, so tracking them only produces churn."
- `CLAUDE.md:22`: `"the \`SessionStart\` materialiser ... writes the 5 consumer-side artifacts ... on session start"` (re-written each upgrade)

**Doc:** "`/update-zskills` install — keep them tracked. Under this install those files (and the rest of the `.claude/` copy) *are* your install state."
- `CLAUDE.md:22`: `"the \`/update-zskills\` lane, mirrored = the other supported single-lane state, where the \`.claude/skills/\` mirror IS the install."`
- `skills/update-zskills/SKILL.md:975`: `"\`.claude/skills/\` mirror, the audit would see every skill/hook as \"missing\""` (the mirror is the tracked install state).

## Pinning to a release (### Pinning to a release)

**Doc:** "Releases are tagged with a bare `<version>` of the form `YYYY.MM.N` (for example `2026.06.0`), so set `source.ref` to that version tag" + the `{ "name": "zs", ... "ref": "2026.06.0" }` example.
- `.github/workflows/ship-to-prod.yml:12`: `"# Tag format: YYYY.MM.N (zero-padded month, no prefix)."` (the publish workflow tags each release with a bare `YYYY.MM.N` version)
- `.github/workflows/ship-to-prod.yml:113`: `"git push prod \"${PROD_SHA}:refs/tags/${TAG}\""` where `TAG="${YEAR}.${MONTH}.${COUNT}"` (`:75`) — pushed to bare `refs/tags/<version>`, NOT `prod/<version>`.
- `.claude-plugin/plugin.json:4`: `"\"version\": \"2026.06.0\","` (the current release version — the example tag is a real published value).
- `.claude-plugin/marketplace.json` zs `source.ref` defaults to bare `main`; pinning overrides it to the bare version tag (matching what the workflow pushes). Asserted by `tests/test-plugin-ref-consistency.sh` assertion 3 (docs must document the bare `<version>` pin idiom and must NOT show the obsolete `prod/<version>` form).
- (Restored content: the prior guide carried this version-pin section; the Phase-7 rewrite dropped it, which the ref-consistency conformance test caught. Re-added as plain user-facing prose, bare-tag form only.)

## Switching installs (### Switching installs)

**Doc:** "See `switching-install-lanes.md`, which walks through the supported switch in both directions, including how to back out."
- `skills/update-zskills/SKILL.md:53-65`: `"\`--switch-install-path={to-plugin|to-update-zskills}\` — the supported / entry point for switching a consumer between the two install lanes ... The script is / bidirectional"`
- `skills/update-zskills/SKILL.md:82-83`: `"See ... \`docs/guides/switching-install-lanes.md\` / for the Abort/Rollback path."`
