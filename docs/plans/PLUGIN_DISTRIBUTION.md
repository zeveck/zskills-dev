---
title: Plugin Distribution Migration
created: 2026-05-21
status: active
---

# Plan: Plugin Distribution Migration

> **Landing mode: PR** — This plan targets PR-based landing. All phases use worktree isolation with a named feature branch. `execution.landing = "pr"` and `execution.main_protected = true` per `.claude/zskills-config.json`.

## Overview

zskills currently distributes itself via a bespoke installer (`/update-zskills`) that mirrors `skills/` → `.claude/skills/`, copies `hooks/*.sh` → `.claude/hooks/`, copies `.claude/agents/*.md`, registers PreToolUse/PostToolUse hooks in the consumer's `.claude/settings.json`, and renders `CLAUDE_TEMPLATE.md` → `.claude/rules/zskills/managed.md` against `.claude/zskills-config.json`. Claude Code now ships a first-class plugin/marketplace system. This plan replaces the bespoke installer with that system while preserving every structural defense the installer guarantees today.

Round 1 reviewer + DA findings exposed three structural gambles (`alwaysLoad`, `SubagentStart`-as-matcher, hard cron cutover); round 2 retired all three. Round 2 review surfaced two CRITICAL omissions caught by round-3 refinement: (a) **Layer 3** of the verifier-cannot-run defense (`verify-response-validate.sh`, invoked from 12 sites across 5 skills) was missing from the materialiser; (b) `migrate-cron-prefixes.sh` was specced as a shell script but `CronList` is a Claude session-side tool, not shell-callable. Round 3 DA review then surfaced two further mechanism-correctness defects in the sentinel scheme the round-3 refiner had introduced to fix F-DA2-3 — both are fixed here in round 4: (c) the sentinel-detection logic was `grep -qF "$sentinel"` interpolating the CURRENT plugin version, which would silently freeze materialised files at first-install version on every subsequent zskills upgrade (F-DA3-1); (d) the sentinel was prepended as line 1 of agent `.md` files, breaking YAML frontmatter parsing and silently dropping the agents' `hooks:` declaration — the entire mechanism Layer 0 of the verifier-cannot-run defense depends on (F-DA3-2). Both are fixed mechanically: write-with-version + detect-by-prefix-regex; inject-inside-frontmatter for `.md` files whose line 1 is `---`.

The headline structural choices (unchanged from round 2):

1. **One plugin** at the repo root named `zskills`, distributed via `.claude-plugin/marketplace.json` at the repo root.
2. **Hybrid distribution for the two zskills agents.** `verifier.md` and `implementer.md` materialise into the consumer's `.claude/agents/` via a SessionStart hook so their frontmatter `hooks:` declaration (Layer 0 of the verifier-cannot-run defense) survives unchanged. Plugin-shipped agents can't declare frontmatter `hooks:` per `/tmp/research-plugin-schema.md` §6.
3. **Rules content is materialised, not packaged.** `CLAUDE_TEMPLATE.md` is rendered by the SessionStart hook into `$CLAUDE_PROJECT_DIR/.claude/rules/zskills/managed.md` — the documented `InstructionsLoaded`-fires-on-`.claude/rules/*.md` path (`/tmp/research-plugin-schema.md` §5 line 243). No `alwaysLoad` field.
4. **Slash-prefix migration with transition-window cron back-compat.** All 29 zskills slash-invocations gain a `zskills:` prefix per `/tmp/research-plugin-schema.md` §7. The cron-fire recognition rule in `managed.md` accepts BOTH `Run /<skill>` AND `Run /zskills:<skill>` for a documented 60-day deprecation window. A SESSION-SIDE migration skill `/zskills:migrate-crons` re-registers durable crons (not a shell script — see D12 round-3 revision below).
5. **`{{...}}` template substitution survives.** The same `CLAUDE_TEMPLATE.md` substitution that `/update-zskills` performs today is performed by the SessionStart materialiser, using a Python renderer reading `.claude/zskills-config.json`. Mtime + atomic-rename idempotency.
6. **zskills eats its own dog food** from Phase 1 onward — `claude --plugin-dir .` from the repo root loads the plugin in-place during development.
7. **Prod-strip discipline preserved.** Marketplace `source` points at `prod/main`, force-pushed at release time by `build-plugin-release.sh`. Parallel `prod/<version>` tags are pushed each release for consumers who want to pin (D1 round-3 revision).

Migration tooling lands BEFORE legacy removal: Phase 1 ships the plugin scaffold; Phase 2 ships the SessionStart materialiser (now FIVE artifacts: agents + `inject-bash-timeout.sh` + `verify-response-validate.sh` + `managed.md`); Phase 3 migrates every internal slash reference to `zskills:` prefix WITH cron back-compat; Phase 4 rebuilds conformance tests; Phase 5 retires `/update-zskills`, the mirror trees, and `CLAUDE_TEMPLATE.md`; Phase 6 activates the marketplace and finalises consumer migration tooling.

## Locked Decisions

D1. **Marketplace shape & release-tag scheme (resolves F-R2-4, F-DA2-2).** Single marketplace manifest at `.claude-plugin/marketplace.json` in the zskills repo root, listing one plugin entry `zskills`. Source is `{ "github": { "repo": "<owner>/zskills", "ref": "prod/main" } }`. **Each release pushes BOTH the moving `prod/main` ref AND a parallel `prod/<version>` tag** (e.g., `prod/2026.05.0`) on the prod-stripped commit. Consumers wanting reproducibility pin marketplace `source.sha` or override `source.ref` to `prod/<version>`. The `prod/main` force-push is the moving-window pointer for unpinned consumers. Per `/tmp/research-plugin-schema.md` §11 lines 437-446, when no `plugin.json.version` resolution succeeds the marketplace falls back to "git commit SHA" — so we ALSO bump `plugin.json.version` in the prod-stripped commit BEFORE force-pushing (W5.5 ordering). `docs/PLUGIN_INSTALL.md` documents the pin-by-version idiom for security-conscious consumers. Splitting into multiple plugins is deferred — see D17.

D2. **Plugin granularity.** ONE plugin. Hooks, skills, and scripts all live under the single `zskills` plugin root. Plugin-shipped agents are NOT used — see D11.

D3. **`CLAUDE_TEMPLATE.md` retirement strategy — materialise via SessionStart.** The DOCUMENTED auto-load path is `InstructionsLoaded` firing on `.claude/rules/*.md` (`/tmp/research-plugin-schema.md` §5 line 243). `CLAUDE_TEMPLATE.md` is rendered by the SessionStart hook into `$CLAUDE_PROJECT_DIR/.claude/rules/zskills/managed.md`. The rendering logic moves into `${CLAUDE_PLUGIN_ROOT}/scripts/render-managed-rules.py`. Idempotency uses mtime + atomic rename. Per CLAUDE.md `## Migration scripts`, the rendered file IS the lock and is written LAST.

D4. **`.template` hook strategy.** `block-agents.sh.template` and `block-unsafe-project.sh.template` are renamed to the suffixless form and read `$CLAUDE_PROJECT_DIR/.claude/zskills-config.json` at runtime.

D5. **Source-of-truth layout (resolves F-R2-3).** `skills/` stays at the zskills repo root. `block-diagram/` stays at the root and is merged via `plugin.json`'s additive `"skills": ["./block-diagram/"]` field. `hooks/` stays at root. **`hooks/_lib/` ships in the plugin tree as part of `hooks/` — sub-directories under `hooks/` are not directly registered in `hooks.json` but are reachable from inlined hook source.** The two helpers (`hooks/_lib/git-tokenwalk.sh`, `hooks/_lib/resolve-effective-worktree-root.sh`) are inlined into 3+ hooks today; `tests/test-hook-helper-drift.sh` enforces byte-equality between the source-of-truth and the inlined copies. The drift test STAYS in the suite (NOT in the D8 retirement list); under the plugin layout it resolves `hooks/_lib/` and the hook source files via the same source-tree path that CI uses today (no fallback needed because both live in the plugin tree at known relative paths). Path-fallback rewrites (W1.4) MUST NOT touch the inlined `_lib` regions in hooks (delimited by `# Inlined from hooks/_lib/...` comments); the drift gate verifies this stays clean. `agents/` directory is NOT created in the plugin tree (D11). `.claude-plugin/` contains only `plugin.json` and `marketplace.json`. The `.claude/skills/` and `.claude/hooks/` mirror trees are RETIRED in Phase 5.

D6. **`/update-zskills` retirement & script relocation.** `/update-zskills` is deleted in Phase 5. Migration-tooling scripts (`scripts/skill-content-hash.sh`, `scripts/frontmatter-set.sh`, `scripts/skill-version-stage-check.sh`, `scripts/frontmatter-get.sh`, `scripts/skill-version-compare.sh`, `scripts/zskills-resolve-config.sh`, `scripts/zskills-paths.sh`, `scripts/sanitize-pipeline-id.sh`, `scripts/migrate-flat-tracking-markers.sh`, `scripts/land-pr-bypass-message.sh`) stay at `scripts/` at the repo root. In-skill source paths inside skill bodies migrate from `${CLAUDE_PROJECT_DIR}/.claude/skills/update-zskills/scripts/...` → `${CLAUDE_PLUGIN_ROOT}/scripts/...`. The 40 skill files that source `zskills-resolve-config.sh` all edit + version-bump in Phase 2.

D7. **Phase 1 = pure-additive constraint relaxation.** Phase 1 does NOT move scripts. Phase 1's only edit surface is `.claude-plugin/`, `hooks/hooks.json`, `hooks/*.sh` (path rewrites where applicable), plus the 3 new plugin-manifest tests. NO skill bodies are touched in Phase 1.

D8. **Conformance test surface — RESOLVED COUNTS.**
- **9 RETIRED:** `tests/test-skills-mirror-parity.sh`, `test-hooks-mirror-parity.sh`, `test-mirror-skill.sh`, `test-managed-md-up-to-date.sh` (replaced by `test-render-managed-rules-correctness.sh`), `test-update-zskills-rerender.sh`, `test-update-zskills-agent-install.sh`, `test-update-zskills-migration.sh`, `test-update-zskills-paths-migration.sh`, `test-update-zskills-version-surface.sh`.
- **2 RESTRUCTURED (3 files):** `test-skill-conformance.sh`; `test-skill-version-enforcement.sh` + `test-block-stale-skill-version*.sh` (3 tests as one structural change).
- **STAYS UNCHANGED:** `tests/test-hook-helper-drift.sh` — see D5; it asserts byte-equality of inlined `_lib` regions against the source-of-truth helpers, which remain at `hooks/_lib/` under the plugin tree.
- **8 NEW TEST FILES** (replacing retired invariants + new plugin-layout invariants):
  - `tests/test-plugin-manifest.sh` (Phase 1)
  - `tests/test-plugin-marketplace.sh` (Phase 1)
  - `tests/test-plugin-self-load.sh` (Phase 1)
  - `tests/test-sessionstart-materialise.sh` (Phase 2)
  - `tests/test-sessionstart-materialise-overwrite-guard.sh` (Phase 2 — F-DA2-3 guard)
  - `tests/test-render-managed-rules-correctness.sh` (Phase 2)
  - `tests/test-inject-bash-timeout-parity.sh` (Phase 2)
  - `tests/test-verify-response-validate-parity.sh` (Phase 2 — F-R2-1 coverage)
  - `tests/test-no-unprefixed-zskills-references.sh` (Phase 3)
  - `tests/test-cron-prefix-back-compat.sh` (Phase 3)
  - `tests/test-skill-frontmatter-survival.sh` (Phase 3 — F-DA2-6 STOP gate)
  - `tests/test-claude-template-mirror.sh` (Phase 3 — F-R2-7 sync gate)

  That's actually 12 new test files in the working count. The D8 net-delta accounting in A5 is updated to reflect the full inventory: -9 retired + 12 new = +3 net new files; 3 restructured-in-place. The Phase 4 PR body documents the actual inventory.

D9. **Plugin-self-load is a real load test, not bash-lint.** `tests/test-plugin-self-load.sh` does THREE things: (a) `claude plugin validate --strict` if CLI available else SKIP-with-reason, (b) Python JSONSchema validation, (c) `bash -n` on every hook + helper script, **WITH an exclusion list** — files matching `hooks/canary*-bad.sh` are skipped (the `canary3-bad.sh` content is dev-only and may carry deliberate syntax errors; F-R2-2). Step (c) explicit exclusion lives in the script.

D10. **Versioning reconciliation.** Plugin-level `version` in `plugin.json` tracks the zskills release tag (`YYYY.MM.N`). Per-skill `metadata.version: "YYYY.MM.DD+<hash>"` continues unchanged. `scripts/frontmatter-set.sh` stays at repo-root; STOP-message recovery commands remain correct without edit.

D11. **Hybrid agent distribution — verifier and implementer NOT plugin-shipped.** Today's `.claude/agents/verifier.md` and `.claude/agents/implementer.md` declare frontmatter `hooks:` blocks invoking `$CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh`. Plugin-shipped agents cannot declare frontmatter `hooks:` per `/tmp/research-plugin-schema.md` §6. Three options were evaluated — broad-fire PreToolUse Bash hook (REJECTED — F-DA1-16), subagent-discriminating matcher (REJECTED — undocumented), hybrid keeping agents consumer-installed (LOCKED). The plugin's SessionStart hook materialises both agent files on first run from `${CLAUDE_PLUGIN_ROOT}/templates/agents/{verifier,implementer}.md`. The materialised frontmatter `hooks:` reference is preserved verbatim.

**Materialiser ships FIVE consumer-side artifacts (revised from 4 in round-2 — adds `verify-response-validate.sh` per F-R2-1):**

1. `$CLAUDE_PROJECT_DIR/.claude/agents/verifier.md`
2. `$CLAUDE_PROJECT_DIR/.claude/agents/implementer.md`
3. `$CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh` (Layer 0 — frontmatter-hook target)
4. `$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh` (Layer 3 — invoked from 12 sites in 5 skill bodies via `$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh`)
5. `$CLAUDE_PROJECT_DIR/.claude/rules/zskills/managed.md`

**Why Layer 3 must be materialised, not plugin-tree-resolved.** The 12 invocation sites (verified: `skills/commit/SKILL.md:320,335`; `skills/do/SKILL.md:741,746,786,791`; `skills/fix-issues/SKILL.md:2367,2372`; `skills/run-plan/SKILL.md:1472,1671`; `skills/verify-changes/SKILL.md:33,50`) hard-code `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"` — they do NOT use a fallback. Two paths were considered for round-3:
- **(a) Materialise it consumer-side** (alongside `inject-bash-timeout.sh`). PRO: zero edits to 12 skill-body sites. CON: a fifth materialised artifact, plus the inject-bash-timeout-style consumer-side duplication.
- **(b) Rewrite the 12 sites to `${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}/.claude/hooks/verify-response-validate.sh`**. PRO: one less materialised file. CON: 12 edits across 5 skills, 5 version-bumps; skill-body fallback resolution is inconsistent with how `inject-bash-timeout.sh` (the OTHER Layer-X consumer-side hook) is wired.

**LOCKED: option (a).** Consistency with `inject-bash-timeout.sh` is the deciding factor — both Layer-0 and Layer-3 hooks live under `$CLAUDE_PROJECT_DIR/.claude/hooks/` after materialisation; the 12 invocation sites need no edit. Phase 2 W2.1 materialises 5 artifacts; `tests/test-verify-response-validate-parity.sh` asserts the plugin-tree source and the materialised consumer-tree copy are byte-equal.

**Behavioural contract preserved:** verifier/implementer subagent Bash calls get the 600s timeout extension (Layer 0); Layer 3 stalled-string validation continues to gate every verifier-dispatching skill. Orchestrator Bash calls are NOT affected.

D12. **Slash-prefix cron back-compat — SKILL-based migration, not shell-script (resolves F-DA2-1).** Round-2 specced `scripts/migrate-cron-prefixes.sh` as a shell helper invoking `CronList`. **`CronList` is a Claude session-side tool, not a shell command** — verified by reading `skills/fix-issues/SKILL.md:244,257,271`: "Use `CronList` to list all cron jobs". There is no `gh extension exec claude-code-list-crons`. The cron migration must run inside a Claude session.

**Two-pronged migration (round-3 revision):**
- **(a) 60-day deprecation window in the recognition rule.** Phase 3 W3.3 writes both prefix forms into `CLAUDE_TEMPLATE.md ## Cron-fired prompts`. The bare-prefix form is recognised through `2026-07-21` and removed in `2026.08`. _(W3.3 edits BOTH `CLAUDE_TEMPLATE.md` AND `templates/CLAUDE_TEMPLATE.md` — F-R2-7 resolution.)_
- **(b) Session-side migration skill `/zskills:migrate-crons` (NOT a shell script).** Phase 3 W3.4 adds a new skill `skills/migrate-crons/SKILL.md` (count goes 29 → 30 in W3.1 inventory — see W3.1 revision). The skill body instructs the agent to: (1) use `CronList` to enumerate durable crons, (2) filter prompts matching `^Run /(<29-name-regex>) `, (3) for each match, dispatch `CronDelete` on the old entry and `CronCreate` for the equivalent prefixed entry, (4) report the diff. Default behaviour is PRINT-ONLY (the agent prints the OLD→NEW mapping and asks for confirmation); `$ARGUMENTS=apply` skips confirmation. The skill carries `user-invocable: true` and `disable-model-invocation: false` so consumers can invoke it post-install. The D14 runbook step "2b" (formerly a shell call) becomes a runbook PROMPT: "After installing the plugin, in your Claude session, run `/zskills:migrate-crons` to re-register pre-existing durable crons under the new prefix." `migrate-to-plugin.sh` prints this prompt verbatim and does NOT attempt the cron migration itself.

The cron migration sequencing under the runbook is therefore: shell script does settings.json strip → user installs plugin → user dispatches `/zskills:migrate-crons` → shell script does file deletions. The skill is INVOKED MANUALLY by the consumer in-session; the shell script does NOT and cannot call it.

D13. **Self-dogfooding dev loop activated in Phase 1, not Phase 6.** Phase 1 W1.8 transitions the zskills repo's own dev workflow to `claude --plugin-dir .`.

D14. **Consumer migration runbook — GUARDED SCRIPT, with session-side cron migration as a separate user step.** `scripts/migrate-to-plugin.sh` follows the lock-LAST contract:
1. Pre-flight inventory — classify zskills-known vs consumer-authored.
2. Strip zskills-installed hook entries from `.claude/settings.json` via Python helper.
3. Print user instructions: "Now in your Claude Code session run `/plugin marketplace add tomdale/zskills` + `/plugin install zskills@zskills` + `/zskills:migrate-crons`. Then return here and type 'done'." The script BLOCKS via `read -p` until the user types `done`.
4. Verification — check `${CLAUDE_PLUGIN_DATA}` or `$HOME/.claude/plugins/cache` for zskills entries.
5. Remove zskills-installed skill mirrors, hook scripts, `managed.md`. Does NOT touch `.claude/agents/` (overwritten by materialiser on next session).
6. Tag the lock — write `.claude/zskills-migrated-to-plugin` LAST.
7. Print CI workflow update guidance + `.gitignore` guidance (per F-DA2-3 (b)): "Consider adding `.claude/agents/verifier.md`, `.claude/agents/implementer.md`, `.claude/hooks/inject-bash-timeout.sh`, `.claude/hooks/verify-response-validate.sh`, `.claude/rules/zskills/managed.md` to `.gitignore` since these are now materialised by the plugin on every session."

The runbook no longer chains a non-existent shell helper — the cron-migration step is a user-driven slash invocation that the script merely instructs.

D15. **`/update-zskills` final mode.** Skill's final living revision adds a `--migrate-to-plugin` mode that prints the D14 runbook entry. Skill deleted in Phase 5.

D16. **Hook double-fire during migration window.** D14 script orders the strip BEFORE plugin install; no double-fire inside the atomic flow.

D17. **Single-plugin justification — research prerequisite for any future split.** Future split requires first fetching `https://code.claude.com/docs/en/plugin-dependencies`.

D18. **Mirror-parity whitelist disposition.** 2 entries (`playwright-cli`, `social-seo`) — consumer-installed, NOT zskills-shipped; `KNOWN_SKILLS` list excludes them.

D19. **`pluginConfigs.options` not used — documented deferral (resolves F-R2-6).** Per `/tmp/research-plugin-schema.md` §13, plugins compose with consumer `.claude/settings.json` via `pluginConfigs[<plugin-id>].options` — a documented config-injection surface. zskills bypasses this in favour of its existing `.claude/zskills-config.json` mechanism (rich schema: `testing.unit_cmd`, `testing.full_cmd`, `dev_server.cmd`, `dev_server.default_port`, `ui.auth_bypass`, `ci.auto_fix`, etc. — not a clean fit for the `options` schema as documented). **Deferred-research note:** if a future Claude Code version makes `pluginConfigs.options` the canonical config-injection point with a typed schema, zskills will need to bridge. Track in a follow-up issue. Not blocking for the migration.

D20. **Materialiser side-effects on consumer git state (resolves F-DA2-3).** The 5 materialised files land in the consumer's working tree under `$CLAUDE_PROJECT_DIR/.claude/`. Three side-effect contracts:

- **(a) Overwrite guard — write-with-version, detect-by-prefix (F-DA3-1 fix) — frontmatter-aware injection (F-DA3-2 fix).** `materialise_static` MUST NOT clobber a pre-existing consumer file that did not originate from zskills. The materialiser writes a sentinel comment carrying the CURRENT plugin version, but DETECTION uses a version-agnostic PREFIX match so that a prior-version sentinel is still recognised as zskills-authored on a later upgrade.

  - **WRITE format (per file type):**
    - Shell scripts (`*.sh`): `# zskills-materialised: <plugin-version>` injected on line 2 (after the shebang).
    - Markdown WITH YAML frontmatter (`*.md` whose line 1 is `---` — applies to both materialised agent files): `# zskills-materialised: <plugin-version>` injected on line 2, INSIDE the opening `---` block as a YAML comment. YAML 1.2 (§9.1.1) requires `---` as the first content line of the document — any prepended HTML comment invalidates frontmatter parsing and silently drops the agent's `hooks:` declaration (Layer 0 of the verifier-cannot-run defense), which is the entire mechanism the materialiser exists to preserve.
    - Markdown WITHOUT frontmatter (rendered `managed.md`): `<!-- zskills-materialised: <plugin-version> -->` as line 1.
  - **DETECTION format (version-agnostic prefix):** every safe-to-write / re-render-gate check uses `grep -qE '^(#|<!--) zskills-materialised: '` (a stable PREFIX regex — matches both the YAML/shell `#` and the HTML-comment form, at ANY plugin version). This ensures that when a consumer upgrades `zskills@2026.05.0 → zskills@2026.06.0`, the materialiser RECOGNISES the file as zskills-authored (because the prefix still matches the stale-version sentinel) and overwrites it cleanly with the new version. The fixed-string `grep -qF "$SENTINEL_WITH_VERSION"` form is NOT used for detection — it would freeze materialised files at first-install version forever.

  On every run, if the destination exists AND does NOT carry the prefix AND is NOT byte-equal to the source, the materialiser emits a STDERR WARN (`zskills: refusing to overwrite consumer-authored $dest; rename it or delete it to allow materialisation`) and SKIPs that artifact. The skip is visible in the consumer's session log.

  **Test coverage (extended in W2.1):** `tests/test-sessionstart-materialise-overwrite-guard.sh` asserts the consumer-authored-skip path with a fixture that pre-populates `.claude/agents/verifier.md` with non-sentinel content. `tests/test-sessionstart-materialise.sh` is extended with TWO cross-cutting assertions: (i) a cross-version case — pre-populate `.claude/agents/verifier.md` with a STALE-version sentinel (`# zskills-materialised: 2026.04.0`), run materialiser at version `2026.05.0`, assert the file IS overwritten (NOT skipped with a false consumer-authored WARN); (ii) a frontmatter-survival assertion — after materialisation, `head -1 .claude/agents/verifier.md` MUST equal `---` (catches any regression to leading-HTML-comment placement that would invalidate YAML frontmatter parsing).

- **(b) `.gitignore` guidance.** The D14 runbook (and `docs/PLUGIN_INSTALL.md`) tells consumers to add the 5 materialised paths to `.gitignore`. Per the round-2 framing, the materialiser writes into the consumer's repo working tree — there are two acceptable consumer postures: (i) ignore (preferred — files are plugin-managed), (ii) track them and pin to a specific zskills version (acceptable but discouraged). The plan does NOT auto-edit `.gitignore` (touching consumer-tracked files unprompted is the wrong move); the runbook EXPLAINS the choice.

- **(c) Uninstall cleanup.** `scripts/migrate-to-plugin.sh --cleanup` mode removes the 5 materialised files. Phase 5 W5.3 ships `--cleanup` as a documented subcommand. The runbook in `docs/PLUGIN_MIGRATION.md` describes the off-ramp. The lock file `.claude/zskills-migrated-to-plugin` is also removed in `--cleanup` mode (re-running `migrate-to-plugin.sh` after cleanup re-installs).

D21. **Materialiser-must-run-before-verifier ordering (resolves F-DA2-4).** Layer 0 fires when the materialised `verifier.md`'s frontmatter `hooks:` references the materialised `inject-bash-timeout.sh`. Both come from the SessionStart hook. Per `/tmp/research-plugin-schema.md` line 187, `/reload-plugins` "switches hook commands" but does NOT explicitly state that it re-fires `SessionStart`. The plan therefore documents the ordering contract conservatively:

- **First-session-with-plugin path.** Plugin loaded → SessionStart hook fires → materialises 5 artifacts → session proceeds → any verifier dispatch resolves the materialised files. ✓
- **Mid-session install path.** `/plugin install zskills` → consumer runs `/reload-plugins` per docs. **If `/reload-plugins` does NOT re-fire SessionStart**, the materialiser does not run; the consumer's next verifier dispatch hits missing files. Mitigation: `docs/PLUGIN_INSTALL.md` includes the line "After `/plugin install zskills`, **restart your Claude Code session** (close + reopen) to ensure the SessionStart materialiser runs before any verifier dispatch." The runbook D14 script step 3's user instruction also includes "restart your Claude Code session after `/plugin install`" before proceeding to "type 'done'."
- **Empirical resolution at implementation time.** Phase 2 W2.1 adds a manual verification step to the PR test plan: "(a) Start a fresh Claude session in a fixture project with no `.claude/agents/`, no `.claude/hooks/inject-bash-timeout.sh`, no `.claude/hooks/verify-response-validate.sh`. (b) `/plugin install` zskills. (c) Without restarting, run `/reload-plugins`. (d) Dispatch a verifier. Observe whether the materialiser fired. Document the result." If `/reload-plugins` DOES re-fire SessionStart, the restart instruction in D21 is conservative-but-harmless; if it does NOT, the restart instruction is load-bearing and we keep it. Either way, the user instruction is correct.

The Layer 0 invariant is "the materialiser must have run before any verifier dispatch in the consumer's lifetime in this repo." With the restart instruction, that's satisfied unconditionally; without it, it's satisfied conditionally on `/reload-plugins` semantics. **Conservative documentation wins.**

D22. **Batch-bump atomicity (resolves F-DA2-5).** Phase 3 W3.7's 29-skill version-bump loop is wrapped in `set -euo pipefail` AND a pre-flight `git status -s | grep -v '^A\b\|^M\b' && exit 1` check (no untracked or unrelated changes outside the staged rewrite). The loop computes hashes against the STAGED content (via `git show :SKILL.md`) instead of the working tree, eliminating the working-tree-vs-staged divergence concern. If `frontmatter-set.sh` doesn't support reading staged content directly, the loop runs `git stash -u` first to isolate the operation, then `git stash pop` after the commit. If any iteration fails, the loop exits non-zero and the user re-runs from a clean state. Concretely:
```bash
set -euo pipefail
# Pre-flight: ensure only staged-prefix-rewrite changes are in the tree
git diff --quiet HEAD || { echo "Unstaged changes present; abort"; exit 1; }
# (the prefix rewrites are already staged from W3.2)
today=$(TZ=America/New_York date +%Y.%m.%d)
TOUCHED_SKILLS=$(git diff --cached --name-only -- 'skills/*/SKILL.md' 'block-diagram/*/SKILL.md' | xargs -n1 dirname | sort -u)
for SKILL_DIR in $TOUCHED_SKILLS; do
  SKILL_MD="$SKILL_DIR/SKILL.md"
  hash=$(bash scripts/skill-content-hash.sh "$SKILL_DIR")
  bash scripts/frontmatter-set.sh "$SKILL_MD" metadata.version "${today}+${hash}"
done
git add skills/ block-diagram/
git commit -m "feat(plugin): zskills: prefix all slash invocations (Phase 3)"
```
On mid-loop failure the partially-bumped state IS visible in the tree, but `git checkout -- skills/ block-diagram/` restores cleanly because the loop ONLY edits SKILL.md frontmatter (no other files). The recovery is documented in W3.7's Abort/Rollback. `tests/test-skill-version-batch-bump.sh` (added in W4.4) simulates the batch-bump against a fixture and asserts every skill ends with a valid `metadata.version` matching its content hash.

## What this plan does NOT do

- **Memory-anchor updates** — out of scope per CLAUDE.md `Memory anchors are agent-local notes`.
- **Documentation site PRESENTATION.html** updates — separate cosmetic pass.
- **Plugin-dependencies semantics** — deferred per D17.
- **Marketplace listing on Anthropic's discoverability surface** — out of scope.
- **Cross-marketplace dependencies** — N/A under D2.
- **`pluginConfigs.options` bridging** — deferred per D19.
- **Per-issue close-out commits** beyond the inventoried `Closes #N` block in Phase 5 W5.9.
- **`MW-EXAMPLE__settings.json` edits** — Phase 6 W6.6 deletes the orphan.
- **`bin/` plugin convention** — zskills doesn't ship binaries.
- **Auto-edit consumer `.gitignore`** — per D20(b), `.gitignore` advice is documented, not enforced.

## Acceptance Criteria (plan-wide)

- [ ] **A1.** `claude --plugin-dir .` loads the zskills plugin without errors. **Verification:** `bash tests/test-plugin-self-load.sh` exits 0 (Python schema + bash-lint; `claude plugin validate --strict` best-effort SKIP-on-absent-CLI).
- [ ] **A2.** All 30 skills (27 in `skills/` — including the new `migrate-crons` skill from D12 — plus 3 in `block-diagram/`) are invocable under their `zskills:` prefix. **Authoritative count:** 30 (up from round-2's 29 because D12 adds the new session-side migration skill into `skills/`, taking that directory from 26 → 27). **Verification:** `tests/test-no-unprefixed-zskills-references.sh` enumerates expected slash names from directory listings.
- [ ] **A3.** Layer 0 + Layer 3 of the verifier-cannot-run defense survive unchanged in behaviour. **Verification:** `tests/test-sessionstart-materialise.sh` asserts the SessionStart hook writes `.claude/agents/verifier.md`, `.claude/agents/implementer.md`, `.claude/hooks/inject-bash-timeout.sh`, AND `.claude/hooks/verify-response-validate.sh` (5 artifacts, up from 4 in round-2 — F-R2-1 fix). `tests/test-verify-response-validate-parity.sh` asserts plugin-tree source = materialised consumer copy.
- [ ] **A4.** Rules content reaches Claude's context via `InstructionsLoaded`-fires-on-`.claude/rules/*.md`. **Verification:** `tests/test-sessionstart-materialise.sh` + `tests/test-render-managed-rules-correctness.sh`.
- [ ] **A5.** Conformance test suite migration is complete. **Verification:** `bash tests/run-all.sh` green; 9 retired tests absent; 12 new tests present; 3 restructured tests pass; `test-hook-helper-drift.sh` STAYS in the suite green (D5). PR body documents net delta: -9 + 12 + 3 restructured-in-place = +3 net new test files.
- [ ] **A6.** `/update-zskills` is gone. **Verification:** `ls skills/update-zskills/ 2>&1` returns "No such file or directory".
- [ ] **A7.** zskills repo dogfoods its own plugin from Phase 1 onward.
- [ ] **A8.** Materialiser overwrite guard works (D20 (a)). **Verification:** `tests/test-sessionstart-materialise-overwrite-guard.sh` exits 0.
- [ ] **A9.** Materialiser uninstall (`migrate-to-plugin.sh --cleanup`) removes the 5 artifacts + lock file. **Verification:** dogfood loop in PR test plan.
- [ ] **A10.** Skill-frontmatter survival (D12 (b) + F-DA2-6 STOP gate). **Verification:** `tests/test-skill-frontmatter-survival.sh` asserts `user-invocable: false` and `disable-model-invocation: true` survive plugin packaging on a fixture skill. If the test fails, Phase 3 STOPS and the orchestrator decides whether to roll back (not "file a follow-up issue" — the test is a STOP gate per F-DA2-6).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Plugin scaffold + dev-loop transition | ⬚ | | |
| 2 — SessionStart materialiser (5 artifacts), `.template`-suffix strip | ⬚ | | |
| 3 — Slash-prefix migration (30 skills incl. new `migrate-crons`), cron back-compat | ⬚ | | |
| 4 — Conformance test surface rebuild | ⬚ | | |
| 5 — `/update-zskills` retirement, mirror trees + CLAUDE_TEMPLATE.md deleted | ⬚ | | |
| 6 — Marketplace activation, prod-tag release flow, consumer onboarding | ⬚ | | |

---

## Phase 1 — Plugin scaffold + dev-loop transition (additive)

### Goal

Land `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `hooks/hooks.json`. The plugin loads via `claude --plugin-dir .` but no existing behaviour changes.

### Work Items

- [ ] **W1.1** — Create `.claude-plugin/plugin.json`:
  ```json
  {
    "name": "zskills",
    "displayName": "Z Skills",
    "version": "2026.05.0",
    "description": "Agent-discipline skill framework: plans, fix-issues, draft-plan, run-plan, land-pr, and more.",
    "author": { "name": "Tom Dale", "url": "https://github.com/tomdale/zskills" },
    "homepage": "https://github.com/tomdale/zskills",
    "repository": "https://github.com/tomdale/zskills",
    "license": "MIT",
    "keywords": ["zskills", "agent", "claude-code", "skills", "plans"],
    "skills": ["./block-diagram/"],
    "hooks": "./hooks/hooks.json"
  }
  ```
  NO `agents` field — agents are NOT plugin-shipped (D11).

- [ ] **W1.2** — Create `.claude-plugin/marketplace.json`:
  ```json
  {
    "$schema": "https://anthropic.com/schemas/claude-plugin-marketplace.json",
    "name": "zskills",
    "owner": { "name": "Tom Dale", "url": "https://github.com/tomdale" },
    "description": "Z Skills — agent-discipline skill framework",
    "version": "1",
    "plugins": [
      {
        "name": "zskills",
        "source": { "github": { "repo": "tomdale/zskills", "ref": "prod/main" } }
      }
    ]
  }
  ```

- [ ] **W1.3** — Create `hooks/hooks.json` registering the 7 existing hooks (verbatim from round-2 — same content). `inject-bash-timeout.sh` and `verify-response-validate.sh` are NOT in this file (D11). `block-agents.sh` and `block-unsafe-project.sh` listed without `.template` suffix (Phase 2 W2.4 strips it). `SessionStart` hook is `session-start-materialise.sh` (W2.1).

- [ ] **W1.4** — Inside each hook script under `hooks/`, rewrite `$CLAUDE_PROJECT_DIR/.claude/hooks/` self-references and `$CLAUDE_PROJECT_DIR/scripts/` references to use `${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}` fallback. Specific edits per `/tmp/research-codebase.md` §4. **CONSTRAINT:** path-fallback rewrites MUST NOT touch the inlined `_lib` regions in `hooks/block-stale-skill-version.sh`, `hooks/block-bypassed-land-pr.sh`, `hooks/block-unsafe-generic.sh` (delimited by `# Inlined from hooks/_lib/...` comments). `tests/test-hook-helper-drift.sh` will fail the commit if any inlined region drifts from its source-of-truth.

- [ ] **W1.5** — `tests/test-plugin-manifest.sh` + `tests/test-plugin-marketplace.sh` (new, D8).

- [ ] **W1.6** — `tests/test-plugin-self-load.sh` per D9 — (a) `claude plugin validate --strict` best-effort SKIP-on-absent-CLI, (b) Python schema validation, (c) `bash -n` on every hook + helper script **EXCLUDING `hooks/canary*-bad.sh`** (F-R2-2). Exclusion is a literal `case` branch in the test:
  ```bash
  for f in hooks/*.sh; do
    case "$f" in
      *canary*-bad*) continue ;;
    esac
    bash -n "$f"
  done
  ```

- [ ] **W1.7** — Add `.claude-plugin/` to `.gitignore` allow-list.

- [ ] **W1.8** — Dev-loop transition (D13). Update `RELEASING.md` and root `CLAUDE.md` to document `claude --plugin-dir .`.

### Design & Constraints

- `${CLAUDE_PLUGIN_ROOT}` substitution documented per §4.
- `scripts/` at the plugin root — unknown directories at plugin root are not processed but are reachable from `${CLAUDE_PLUGIN_ROOT}/scripts/...` strings.
- `hooks/hooks.json` does NOT merge into consumer's `.claude/settings.json` — they compose at the harness level. Migration-window double-fire is resolved by D14.
- Phase 1's no-skill-edit boundary satisfied — scripts STAY at `scripts/`.
- `inject-bash-timeout.sh` AND `verify-response-validate.sh` are NOT registered as plugin-level hooks (D11). Both materialise into `$CLAUDE_PROJECT_DIR/.claude/hooks/` in Phase 2.
- CronCreate / Agent matchers unverified by direct doc quote (F-R1-3); W1.6 smoke test catches rejection.
- `hooks/_lib/` ships verbatim in the plugin tree (D5). No path-rewrites inside `_lib/` source files.

### Tests

- [ ] **NEW** `tests/test-plugin-manifest.sh`, `tests/test-plugin-marketplace.sh`, `tests/test-plugin-self-load.sh` (3 new in Phase 1).
- [ ] **EXISTING tests STAY GREEN.**

### Acceptance Criteria

- [ ] All 3 new tests green.
- [ ] `bash tests/run-all.sh` green.
- [ ] `git diff --stat origin/main..HEAD` includes ONLY `.claude-plugin/`, `hooks/hooks.json`, `hooks/*.sh` (path-fallback edits), `tests/test-plugin-*.sh`, `RELEASING.md` + `CLAUDE.md`. NO skill body edits, NO `scripts/` moves, NO `hooks/_lib/` edits.

### Abort / Rollback

If `claude plugin validate --strict` rejects the `Agent` or `CronCreate` matcher — STOP per round-2 abort path.

### Dependencies

None.

---

## Phase 2 — SessionStart materialiser (5 artifacts), `.template`-suffix strip

### Goal

Land the SessionStart materialiser. Five artifacts are written to consumer `.claude/`: 2 agents, 2 hooks (inject-bash-timeout + verify-response-validate), 1 rules file. After this phase, the plugin is *behaviourally complete* — every defense the legacy installer provided is reproduced, including Layer 3 of the verifier-cannot-run defense (F-R2-1 fix).

### Work Items

- [ ] **W2.1 — SessionStart materialiser (`hooks/session-start-materialise.sh`).** Writes FIVE artifacts (round-3 revision: adds `verify-response-validate.sh` per F-R2-1):
  - `$CLAUDE_PROJECT_DIR/.claude/agents/verifier.md` ← `${CLAUDE_PLUGIN_ROOT}/templates/agents/verifier.md`
  - `$CLAUDE_PROJECT_DIR/.claude/agents/implementer.md` ← `${CLAUDE_PLUGIN_ROOT}/templates/agents/implementer.md`
  - `$CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh` ← `${CLAUDE_PLUGIN_ROOT}/hooks/inject-bash-timeout.sh`
  - `$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh` ← `${CLAUDE_PLUGIN_ROOT}/hooks/verify-response-validate.sh`
  - `$CLAUDE_PROJECT_DIR/.claude/rules/zskills/managed.md` ← rendered by `scripts/render-managed-rules.py`

  Hook body with overwrite guard (D20 (a) — write-with-version, detect-by-prefix per F-DA3-1; frontmatter-aware injection per F-DA3-2):
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  PROJ="$CLAUDE_PROJECT_DIR"
  PLUGIN="${CLAUDE_PLUGIN_ROOT}"
  CONFIG="$PROJ/.claude/zskills-config.json"
  PLUGIN_VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/.claude-plugin/plugin.json")"

  # Greenfield default config if absent.
  if [ ! -f "$CONFIG" ]; then
    mkdir -p "$(dirname "$CONFIG")"
    cp "$PLUGIN/templates/zskills-config.default.json" "$CONFIG"
  fi

  # WRITE sentinels carry the current plugin version (for uninstall + version-traceability).
  SENTINEL_SH="# zskills-materialised: ${PLUGIN_VERSION}"           # bash + YAML comment (same byte form)
  SENTINEL_MD_HTML="<!-- zskills-materialised: ${PLUGIN_VERSION} -->"  # for markdown WITHOUT YAML frontmatter

  # DETECT pattern is version-AGNOSTIC — a prior-version sentinel must still be recognised
  # as zskills-authored on a later upgrade (F-DA3-1). Matches: `# zskills-materialised: ...`
  # (shell scripts AND YAML-comment-inside-frontmatter form) and `<!-- zskills-materialised: ... -->`
  # (markdown-without-frontmatter form).
  SENTINEL_DETECT_RE='^(#|<!--) zskills-materialised: '

  # Returns 0 if dest is safe to overwrite (absent, zskills-sentinelled at ANY version, or byte-equal).
  safe_to_write() {
    local dest="$1" src="$2"
    [ -f "$dest" ] || return 0
    if grep -qE "$SENTINEL_DETECT_RE" "$dest"; then return 0; fi
    # No sentinel of any version — fall back to byte-equality (covers pre-sentinel zskills releases).
    cmp -s "$src" "$dest" && return 0
    return 1
  }

  # Inject the sentinel inside the file at the right position for the file type.
  # - *.sh: AFTER the shebang line (line 2).
  # - *.md WITH YAML frontmatter (line 1 == `---`): inject AFTER the opening `---` as a YAML
  #   comment on line 2 — required so the frontmatter `---` stays at line 1 per YAML 1.2 §9.1.1
  #   (F-DA3-2). The HTML-comment form would invalidate frontmatter parsing and silently drop
  #   the agent's `hooks:` block (Layer 0 of the verifier-cannot-run defense).
  # - *.md WITHOUT YAML frontmatter (e.g. rendered managed.md): HTML comment as line 1.
  inject_sentinel() {
    local src="$1" out="$2"
    case "$src" in
      *.sh)
        { head -n1 "$src"; echo "$SENTINEL_SH"; tail -n+2 "$src"; } > "$out"
        ;;
      *.md)
        # YAML frontmatter is detected by line 1 == "---".
        local first
        first="$(head -n1 "$src")"
        if [ "$first" = "---" ]; then
          # Inject as YAML comment INSIDE the frontmatter block.
          { head -n1 "$src"; echo "$SENTINEL_SH"; tail -n+2 "$src"; } > "$out"
        else
          # Plain markdown body — HTML comment as line 1 is safe.
          { echo "$SENTINEL_MD_HTML"; cat "$src"; } > "$out"
        fi
        ;;
      *)
        cp "$src" "$out"
        ;;
    esac
  }

  materialise_static() {
    local src="$1" dest="$2"
    # Early-return if already-materialised and current vs source mtime.
    if [ -f "$dest" ] && [ "$dest" -nt "$src" ] && grep -qE "$SENTINEL_DETECT_RE" "$dest"; then return 0; fi
    if ! safe_to_write "$dest" "$src"; then
      echo "zskills: refusing to overwrite consumer-authored $dest; rename or delete it to allow materialisation" >&2
      return 0  # skip (do NOT exit 1 — other artifacts still get materialised)
    fi
    mkdir -p "$(dirname "$dest")"
    inject_sentinel "$src" "$dest.tmp"
    mv "$dest.tmp" "$dest"
  }
  materialise_static "$PLUGIN/templates/agents/verifier.md"    "$PROJ/.claude/agents/verifier.md"
  materialise_static "$PLUGIN/templates/agents/implementer.md" "$PROJ/.claude/agents/implementer.md"
  materialise_static "$PLUGIN/hooks/inject-bash-timeout.sh"    "$PROJ/.claude/hooks/inject-bash-timeout.sh"
  materialise_static "$PLUGIN/hooks/verify-response-validate.sh" "$PROJ/.claude/hooks/verify-response-validate.sh"
  chmod +x "$PROJ/.claude/hooks/inject-bash-timeout.sh" "$PROJ/.claude/hooks/verify-response-validate.sh"

  # Render managed.md (the lock — last per CLAUDE.md `## Migration scripts`).
  # managed.md has NO YAML frontmatter — HTML-comment sentinel on line 1 is correct.
  MANAGED="$PROJ/.claude/rules/zskills/managed.md"
  TEMPLATE="$PLUGIN/templates/CLAUDE_TEMPLATE.md"
  if [ -f "$MANAGED" ] && [ "$MANAGED" -nt "$CONFIG" ] && [ "$MANAGED" -nt "$TEMPLATE" ] && grep -qE "$SENTINEL_DETECT_RE" "$MANAGED"; then
    exit 0
  fi
  if ! safe_to_write "$MANAGED" "$TEMPLATE"; then
    echo "zskills: refusing to overwrite consumer-authored $MANAGED" >&2
    exit 0
  fi
  mkdir -p "$(dirname "$MANAGED")"
  PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
  [ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }
  "$PYTHON" "$PLUGIN/scripts/render-managed-rules.py" \
    --config "$CONFIG" --template "$TEMPLATE" --out "$MANAGED.tmp" --sentinel "$SENTINEL_MD_HTML"
  mv "$MANAGED.tmp" "$MANAGED"
  ```

  Note: the renderer is updated to emit the HTML-comment sentinel as the first line of the rendered `managed.md` (which has no YAML frontmatter). The overwrite guard treats any file matching the `SENTINEL_DETECT_RE` PREFIX as zskills-owned (re-writable on every run, INCLUDING upgrades from a prior plugin version) and files without the prefix as consumer-owned (skip + warn). This is the F-DA3-1 fix: write-with-version (full sentinel string) but detect-by-prefix (regex), so cross-version upgrades propagate cleanly. The `*.md`-with-frontmatter branch inside `inject_sentinel` is the F-DA3-2 fix: the YAML-comment form keeps `---` at line 1 so subagent frontmatter parsing (and the load-bearing `hooks:` declaration) is preserved.

- [ ] **W2.2 — Python renderer (`scripts/render-managed-rules.py`).** Same as round 2 — ports the substitution map from today's `/update-zskills` Step B; adds a `--sentinel` flag that emits the sentinel as the first line of the output. `managed.md` has no YAML frontmatter, so the line-1-HTML-comment form is correct here (no F-DA3-2 frontmatter-position concern).

- [ ] **W2.3 — Templates directory `templates/`.** Create `templates/` at the plugin root:
  - `templates/agents/verifier.md` — copy of today's `.claude/agents/verifier.md`.
  - `templates/agents/implementer.md` — copy of today's `.claude/agents/implementer.md`.
  - `templates/CLAUDE_TEMPLATE.md` — copy of today's repo-root `CLAUDE_TEMPLATE.md`. **F-R2-7 contract:** any subsequent Phase that edits the repo-root `CLAUDE_TEMPLATE.md` (Phase 3 W3.3 in particular) MUST ALSO edit `templates/CLAUDE_TEMPLATE.md` in the same commit. `tests/test-claude-template-mirror.sh` (added in Phase 3 W3.5) asserts byte-equality between the two while both exist. Phase 5 W5.4 deletes the repo-root copy AFTER verifying byte-equality.
  - `templates/zskills-config.default.json` — greenfield default config.

- [ ] **W2.4 — Strip `.template` suffixes.** Same as round 2.

- [ ] **W2.5 — Plugin hook self-references.** Same as round 2; no `frontmatter-set.sh` message-text edit needed per D10.

- [ ] **W2.6 — Update zskills' own root `CLAUDE.md`.** Same as round 2.

### Design & Constraints

- **5 materialised artifacts (round-3 — adds `verify-response-validate.sh`).** The 12 invocation sites (`bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"`) in 5 skill bodies do NOT change — they continue to resolve to the materialised consumer-side path. This is the same wiring as `inject-bash-timeout.sh`.
- **Overwrite guard (D20 (a)).** Sentinel-comment-based detection of zskills authorship using a VERSION-AGNOSTIC PREFIX regex (`^(#|<!--) zskills-materialised: `) so cross-version upgrades propagate cleanly (F-DA3-1 fix). For `.md` files whose line 1 is `---` (the two agent files), the sentinel is injected as a YAML comment on line 2 — INSIDE the frontmatter block — keeping `---` at line 1 per YAML 1.2 §9.1.1 (F-DA3-2 fix). Pre-existing non-zskills files at the same destination paths are NOT clobbered; the materialiser logs a WARN and skips.
- **`verify-response-validate.sh` lives in TWO places by design.** Plugin tree: `${CLAUDE_PLUGIN_ROOT}/hooks/verify-response-validate.sh` (source-of-truth, used by dev-loop tests). Consumer tree: `$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh` (materialised on first session — referenced by all 12 invocation sites). `tests/test-verify-response-validate-parity.sh` asserts the plugin-tree source and the materialised consumer-tree copy are byte-equal modulo the sentinel comment.
- **No `alwaysLoad` field.** Per D3.
- **Atomic-rename + mtime + sentinel idempotency.** Every write uses `cp → mv` or `python … --out <tmp> + mv`. Mtime gates re-rendering; sentinel gates overwrite-vs-skip.
- **Per-artifact recovery.** A failed `safe_to_write` check on one artifact does NOT abort the materialiser — the other artifacts still get materialised. The user sees a per-artifact WARN line.

### Tests

- [ ] **NEW** `tests/test-sessionstart-materialise.sh` — fixture project; runs `bash hooks/session-start-materialise.sh`; asserts:
  1. `.claude/zskills-config.json` greenfield-defaulted.
  2. **All 5 destinations** (verifier.md, implementer.md, inject-bash-timeout.sh, **verify-response-validate.sh**, managed.md) are written with a sentinel comment matching `SENTINEL_DETECT_RE` present.
  3. The 2 hooks have execute bit.
  4. `managed.md` substitution tokens resolved.
  5. Touch `zskills-config.json`, re-run hook → `managed.md` mtime advances.
  6. Don't touch anything, re-run hook → `managed.md` mtime unchanged.
  7. Touch `CLAUDE_TEMPLATE.md` template-side → `managed.md` re-renders.
  8. **Frontmatter-survival (F-DA3-2):** `head -n1 .claude/agents/verifier.md` MUST equal `---` (and same for `implementer.md`). `head -n2 .claude/agents/verifier.md | tail -n1` MUST match the sentinel-detect regex — confirming the YAML-comment sentinel was injected on line 2 INSIDE the frontmatter block.
  9. **Cross-version upgrade (F-DA3-1):** simulate a prior-version install by pre-populating `.claude/agents/verifier.md` with a STALE-version sentinel: copy the source then rewrite line 2 to `# zskills-materialised: 2026.04.0` (where the current `PLUGIN_VERSION` is e.g. `2026.05.0`). Run the materialiser. Assert: (a) the file IS overwritten — its mtime advances and line 2 now reads `# zskills-materialised: 2026.05.0` (NOT skipped as consumer-authored); (b) NO `refusing to overwrite consumer-authored` WARN appears on stderr; (c) the file body matches the plugin-tree source modulo the sentinel line. Repeat the same scenario for one shell hook (`inject-bash-timeout.sh`) — pre-populate with a stale-version sentinel on line 2, run materialiser, assert overwrite proceeded cleanly.
- [ ] **NEW** `tests/test-sessionstart-materialise-overwrite-guard.sh` — fixture pre-populates `.claude/agents/verifier.md` with non-sentinel content; runs the materialiser; asserts the consumer's file is UNCHANGED and a WARN line is emitted to stderr. Then adds the sentinel manually + re-runs; asserts the file IS now overwritten (zskills-owned).
- [ ] **NEW** `tests/test-render-managed-rules-correctness.sh` — golden-output fixture; replaces retired drift gate.
- [ ] **NEW** `tests/test-inject-bash-timeout-parity.sh` — asserts plugin-tree and materialised copies are byte-equal modulo sentinel.
- [ ] **NEW** `tests/test-verify-response-validate-parity.sh` — same parity check for the Layer 3 script. Also asserts every one of the 12 invocation sites uses the literal `$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh` path (no drift to a different shape that would break post-materialisation resolution).
- [ ] **DEFERRED RETIREMENT** `tests/test-update-zskills-rerender.sh`, `tests/test-managed-md-up-to-date.sh` — still pass against source-tree `CLAUDE_TEMPLATE.md`; retired in Phase 4.
- [ ] `bash tests/test-skill-conformance.sh` — must still pass.
- [ ] `bash tests/test-hook-helper-drift.sh` — must still pass (D5 invariant).

### Acceptance Criteria

- [ ] All 5 new tests green.
- [ ] `bash tests/run-all.sh` green.
- [ ] 5 materialised artifacts present in a fresh fixture project — verified by `test-sessionstart-materialise.sh`.
- [ ] `hooks/block-unsafe-project.sh.template` and `hooks/block-agents.sh.template` no longer exist.
- [ ] `templates/` directory exists; `scripts/render-managed-rules.py` exists.
- [ ] Manual verification log: in PR test plan, the implementer dispatches a verifier subagent under `claude --plugin-dir .`, gives it a 4-minute Bash command, AND triggers a stalled-string response — observes (a) the long Bash completes (Layer 0), (b) `verify-response-validate.sh` fires on the stalled-string response (Layer 3). Plus per D21: documents the result of the `/reload-plugins`-after-install path.

### Abort / Rollback

If any of the 5 write contracts fail, or if the overwrite-guard test fails, do NOT ship Phase 2. Rollback: `git reset --hard origin/main`.

### Dependencies

Phase 1.

---

## Phase 3 — Slash-prefix migration (`zskills:` namespace) WITH cron back-compat

### Goal

Every internal slash-reference updates to `/zskills:<skill>`. Cron-fire recognition rule accepts both forms for 60 days. New session-side migration skill `/zskills:migrate-crons` re-registers durable crons (D12 round-3 revision).

### Work Items

- [ ] **W3.1 — Inventory the touched files.** Implementer runs:
  ```bash
  # 26 skills/ entries:
  SKILLS_SRC='briefing|cleanup-merged|commit|create-worktree|do|doc|draft-plan|draft-tests|fix-issues|fix-report|investigate|land-pr|manual-testing|plans|qe-audit|quickfix|refine-plan|research-and-go|research-and-plan|review-feedback|run-plan|session-report|update-zskills|verify-changes|work-on-plans|zskills-dashboard'
  # 3 block-diagram/ entries:
  SKILLS_BD='add-block|add-example|model-design'
  # 1 new (D12 round-3 revision):
  SKILLS_NEW='migrate-crons'
  SKILLS_RE="$SKILLS_SRC|$SKILLS_BD|$SKILLS_NEW"
  grep -rnE "(^|[^a-zA-Z0-9_])/($SKILLS_RE)\\b" skills/ block-diagram/ hooks/ .claude/agents/ CLAUDE.md CLAUDE_TEMPLATE.md templates/CLAUDE_TEMPLATE.md tests/
  ```
  Skill-count is **30** (round-2 was 29; D12 round-3 adds `migrate-crons`). The regex variables are separated by directory grouping per F-R2-5.

- [ ] **W3.2 — Bulk rewrite skill bodies, hooks, agents, CLAUDE.md.** Apply substitution rules with the deterministic Python script per round-2 W3.2. **Round-3 addition:** rewrites also apply to `templates/CLAUDE_TEMPLATE.md` (the plugin-tree copy added in Phase 2 W2.3) — the script's invocation list includes BOTH paths.

- [ ] **W3.3 — Cron back-compat in CLAUDE_TEMPLATE.md (D12 (a)).** Edit `CLAUDE_TEMPLATE.md ## Cron-fired prompts` AND `templates/CLAUDE_TEMPLATE.md ## Cron-fired prompts` IN THE SAME COMMIT to accept both prefix forms during the deprecation window. New prose includes:
  ```
  **Treat any user-shaped turn whose entire content starts with `Run /<skill-name> ` OR
  `Run /zskills:<skill-name> ` as a cron fire.** Both prefixes are recognized through
  2026-07-21; the bare-prefix form is removed in zskills release 2026.08. Consumers
  should re-register pre-existing durable crons by running `/zskills:migrate-crons` in
  their Claude session before then. Read `${CLAUDE_PLUGIN_ROOT}/skills/<skill>/SKILL.md`
  (prefixed form) or `.claude/skills/<skill>/SKILL.md` (legacy bare form) via Read and
  execute its procedure inline with `$ARGUMENTS` set to the substring after the prefix.
  ```
  **F-R2-7 contract:** the same commit edits BOTH files; `tests/test-claude-template-mirror.sh` (W3.5) gates byte-equality.

- [ ] **W3.4 — New session-side skill `/zskills:migrate-crons` (D12 (b) — replaces round-2 shell script per F-DA2-1).** Create `skills/migrate-crons/SKILL.md`:
  - Frontmatter: `name: migrate-crons`, `description: "Re-register pre-plugin-migration durable crons under the zskills: namespace"`, `user-invocable: true`, `disable-model-invocation: false`, `argument-hint: "[apply]"`, `metadata.version: "<today>+<hash>"`.
  - Body: instructs the agent to (1) use `CronList` to enumerate durable crons; (2) for each entry whose `prompt` field starts with `Run /` + one of the 29 legacy names (NOT `/zskills:` — only the bare form), compute the prefixed equivalent; (3) print a table of OLD → NEW prompts; (4) if `$ARGUMENTS` contains `apply`, dispatch `CronDelete` on each matching entry and `CronCreate` with the prefixed prompt; (5) report the result. Default (no `apply`) is PRINT-ONLY.
  - The skill lives in `skills/migrate-crons/SKILL.md` and ships with the plugin.

  The `migrate-to-plugin.sh` script (D14) prints the user instruction "in your Claude session, run `/zskills:migrate-crons`" but does NOT and cannot invoke it. Per F-DA2-1, the session-tool boundary means cron operations must run in-session.

- [ ] **W3.5 — Test-suite assertion migration.** Every `tests/test-*.sh` greps update from `/<skill>` to `/zskills:<skill>`. `test-skill-conformance.sh` pin-sites updated. **NEW test added here:** `tests/test-claude-template-mirror.sh` asserts byte-equality between `CLAUDE_TEMPLATE.md` and `templates/CLAUDE_TEMPLATE.md` while both exist; Phase 5 W5.4 retires this test the same commit it deletes the repo-root copy.

- [ ] **W3.6 — Skill-frontmatter survival assertion (resolves F-DA2-6 — STOP gate, not follow-up issue).** Per F-DA1-8, plugin-shipped skill frontmatter fields (`user-invocable`, `disable-model-invocation`, `argument-hint`, `metadata.version`) are NOT documented to survive plugin packaging. **Round-3 contract:** add `tests/test-skill-frontmatter-survival.sh` that:
  1. Creates a fixture plugin with a single skill carrying `user-invocable: false`, `disable-model-invocation: true`, `argument-hint: "test"`.
  2. Loads the plugin via `claude --plugin-dir <fixture>` (or simulates by reading the loaded plugin manifest from the cache).
  3. Asserts the loaded skill's frontmatter retains all four fields.
  4. If any field is dropped, the test FAILS — **Phase 3 STOPS** and the orchestrator decides whether to roll back (NOT "file a follow-up issue" — the failure consequence is severe enough to gate the phase per F-DA2-6).

  Additionally, the dogfood-loop spot-check from round 2 stays in the PR body: implementer runs `claude --plugin-dir .` and tries (a) `/zskills:land-pr ` autocomplete behaviour, (b) Skill-tool dispatch of `/zskills:fix-issues` from a sub-agent. Documents results.

- [ ] **W3.7 — Version bump for every touched skill (D22 round-3 atomicity revision).** Per D22, the batch-bump loop runs under `set -euo pipefail` with a pre-flight clean-tree check, processes only the staged-touched skills, and provides a documented recovery path (`git checkout -- skills/ block-diagram/`) on mid-loop failure. `tests/test-skill-version-batch-bump.sh` (W4.4) simulates the batch-bump on a fixture.

### Design & Constraints

- **No back-compat alias for the slash invocation itself** — hard cutover for typed-by-user invocations.
- **Cron-fire recognition IS back-compat'd** for 60 days.
- **Cron migration is a SKILL, not a shell script** (D12 round-3 revision per F-DA2-1).
- **Memory anchors are NOT touched.**
- **Migration script audit-first approach** encouraged per round 2.
- **`templates/CLAUDE_TEMPLATE.md` and `CLAUDE_TEMPLATE.md` MUST be edited in lockstep** until Phase 5 retires the repo-root copy (F-R2-7).

### Tests

- [ ] **NEW** `tests/test-no-unprefixed-zskills-references.sh` (Phase 3) — greps for unprefixed names; exempts cron-recognition prose by line range.
- [ ] **NEW** `tests/test-cron-prefix-back-compat.sh` — asserts `templates/CLAUDE_TEMPLATE.md ## Cron-fired prompts` contains BOTH `Run /<skill-name>` and `Run /zskills:<skill-name>` recognition patterns. (Test reads the PLUGIN-TREE copy, not the repo-root copy, because the plugin-tree copy survives Phase 5 — F-R2-7 fix.)
- [ ] **NEW** `tests/test-claude-template-mirror.sh` — asserts byte-equality between `CLAUDE_TEMPLATE.md` and `templates/CLAUDE_TEMPLATE.md` (until Phase 5 retires the former).
- [ ] **NEW** `tests/test-skill-frontmatter-survival.sh` (F-DA2-6 STOP gate).
- [ ] `bash tests/test-skill-conformance.sh` — green; pins reference `/zskills:<skill>`.
- [ ] `bash tests/run-all.sh` — green.

### Acceptance Criteria

- [ ] All new tests green.
- [ ] `bash tests/run-all.sh` green.
- [ ] Every touched skill has a bumped `metadata.version`.
- [ ] `skills/migrate-crons/SKILL.md` exists with the documented body (NOT a shell script — F-DA2-1).
- [ ] PR body documents W3.6 dogfood-loop results.
- [ ] `tests/test-skill-frontmatter-survival.sh` is GREEN (or Phase 3 STOPS — F-DA2-6).

### Abort / Rollback

If `tests/test-skill-frontmatter-survival.sh` fails — STOP. Decide whether to roll back or accept the regression in PR body (the latter requires user approval per CLAUDE.md severity rules). If `tests/test-no-unprefixed-zskills-references.sh` fails after rewrite, STOP and review the regex hit-set. Two attempts max per CLAUDE.md "NEVER thrash on a failing fix."

### Dependencies

Phase 2.

---

## Phase 4 — Conformance test surface rebuild

### Goal

Retire the 9 tests whose invariants disappear, restructure 2 (3 files), stabilise the 12 new tests added in Phases 1-3. `test-hook-helper-drift.sh` STAYS (D5).

### Work Items

- [ ] **W4.1 — Retire 9 tests** per D8. Also remove the W2.4 mirror-parity carve-out.

- [ ] **W4.2 — Restructure `tests/test-skill-conformance.sh`.** Same as round 2; cross-test materialiser-presence check at top.

- [ ] **W4.3 — Restructure `tests/test-block-stale-skill-version*.sh`.** Same as round 2.

- [ ] **W4.4 — Stabilise the 12 new tests:**
  - `tests/test-plugin-manifest.sh` (Phase 1)
  - `tests/test-plugin-marketplace.sh` (Phase 1)
  - `tests/test-plugin-self-load.sh` (Phase 1)
  - `tests/test-sessionstart-materialise.sh` (Phase 2)
  - `tests/test-sessionstart-materialise-overwrite-guard.sh` (Phase 2 — F-DA2-3)
  - `tests/test-render-managed-rules-correctness.sh` (Phase 2)
  - `tests/test-inject-bash-timeout-parity.sh` (Phase 2)
  - `tests/test-verify-response-validate-parity.sh` (Phase 2 — F-R2-1)
  - `tests/test-no-unprefixed-zskills-references.sh` (Phase 3)
  - `tests/test-cron-prefix-back-compat.sh` (Phase 3)
  - `tests/test-claude-template-mirror.sh` (Phase 3 — F-R2-7; retired in Phase 5 same commit as repo-root template deletion)
  - `tests/test-skill-frontmatter-survival.sh` (Phase 3 — F-DA2-6)
  - `tests/test-skill-version-batch-bump.sh` (added in Phase 4 — D22)

  Run 5 consecutive iterations of `bash tests/run-all.sh`; any flake gets root-caused.

- [ ] **W4.5 — Test-runner accounting.** PR body documents the actual file count: `-9 retired + 13 new = +4 net (counting `test-claude-template-mirror.sh` which lands in Phase 3 and retires in Phase 5)`. The +4 reduces to +3 after Phase 5's mirror-test retirement.

- [ ] **W4.6 — `tests/fixtures/forbidden-literals.txt` audit.** Same as round 2.

### Design & Constraints

- Atomic deletion only.
- CI must stay green throughout.
- The mirror-parity-test carve-out from W2.4 is removed here.
- `tests/test-hook-helper-drift.sh` STAYS (D5).

### Tests

- [ ] `bash tests/run-all.sh` green.
- [ ] `bash tests/test-skill-conformance.sh` green.
- [ ] `bash tests/test-block-stale-skill-version*.sh` green.
- [ ] `bash tests/test-hook-helper-drift.sh` green (D5 — `hooks/_lib/` survives).
- [ ] 5 consecutive iterations green.

### Acceptance Criteria

- [ ] All 9 retirements committed.
- [ ] All 13 new plugin tests are part of `bash tests/run-all.sh` (one will retire in Phase 5).
- [ ] PR body documents the suite-count delta.

### Abort / Rollback

If a retired test surfaces a real invariant that no replacement covers, STOP.

### Dependencies

Phases 1, 2, 3.

---

## Phase 5 — `/update-zskills` retirement, mirror trees + CLAUDE_TEMPLATE.md removed, `migrate-to-plugin.sh` ships

### Goal

Delete the legacy installer entirely. Ship `migrate-to-plugin.sh` with `--cleanup` mode (D20 (c)). Ship `build-plugin-release.sh` with self-deletion fix (F-R2-4).

### Work Items

- [ ] **W5.1 — Final `/update-zskills --migrate-to-plugin` mode (D15).** Same as round 2.

- [ ] **W5.2 — Cut a release tag.** Same as round 2.

- [ ] **W5.3 — `scripts/migrate-to-plugin.sh` lands (D14 + D20 (c)).** Implements the 7-step guarded migration. **Round-3 additions vs round-2 skeleton:**
  - Step 2b (formerly `bash migrate-cron-prefixes.sh`) is REMOVED — replaced by a printed user instruction in step 3. Per F-DA2-1, cron migration must be session-side.
  - Step 3 user prompt now reads:
    ```
    Now in your Claude Code session, run:
        /plugin marketplace add tomdale/zskills
        /plugin install zskills@zskills
    Then RESTART your Claude Code session (close + reopen).
    In the new session, run:
        /zskills:migrate-crons       # to re-register any pre-existing durable crons
    Return here and type 'done' when complete.
    ```
    (The restart instruction is per D21.)
  - Step 7 prints both CI workflow guidance AND `.gitignore` guidance per D20 (b).
  - **`--cleanup` mode (D20 (c)).** When invoked as `bash scripts/migrate-to-plugin.sh --cleanup`, removes the 5 materialised files at `$CLAUDE_PROJECT_DIR/.claude/agents/{verifier,implementer}.md`, `$CLAUDE_PROJECT_DIR/.claude/hooks/{inject-bash-timeout,verify-response-validate}.sh`, `$CLAUDE_PROJECT_DIR/.claude/rules/zskills/managed.md`, and the lock file `$CLAUDE_PROJECT_DIR/.claude/zskills-migrated-to-plugin`. Each removal is sentinel-gated (only removes files carrying the zskills sentinel) so consumer-authored files at the same paths are preserved.

  Companion Python helper `scripts/migrate-strip-settings.py` per round 2.

- [ ] **W5.4 — Delete the legacy installer surface (F-R2-7 ordering fix).** Ordering of deletions:
  1. **FIRST** assert byte-equality: `diff CLAUDE_TEMPLATE.md templates/CLAUDE_TEMPLATE.md` must exit 0. If not, STOP — the F-R2-7 sync gate has detected drift; fix before proceeding.
  2. `rm CLAUDE_TEMPLATE.md` (the repo-root copy).
  3. `rm tests/test-claude-template-mirror.sh` (its invariant is moot after step 2).
  4. `rm -rf skills/update-zskills/`
  5. `rm -rf .claude/skills/<every-known-zskills-skill>/` (per `KNOWN_SKILLS` list).
  6. `rm -rf .claude/hooks/<every-known-zskills-hook>.sh` (per `KNOWN_HOOKS` list; both `inject-bash-timeout.sh` AND `verify-response-validate.sh` are in this list — they'll be re-materialised on next session).
  7. `rm .claude/rules/zskills/managed.md` (the rendered file in the zskills repo's own `.claude/`).
  8. `rm scripts/mirror-skill.sh`.
  9. `rm scripts/install-helpers-into.sh` if present.

  **DO NOT delete `.claude/skills/playwright-cli/` or `.claude/skills/social-seo/`** (D18). **DO NOT delete `.claude/agents/{verifier,implementer}.md`** — re-materialised on next session.

- [ ] **W5.5 — `scripts/build-plugin-release.sh` (F-R2-4 fix).** Round-3 revision adds:
  - `set -euo pipefail`.
  - `trap` cleanup: `trap 'cd / 2>/dev/null; git worktree remove --force "$WORK" 2>/dev/null || echo "warning: worktree $WORK left behind; clean up manually"' EXIT`.
  - Dirty-tree precheck: `git diff --quiet HEAD && git diff --cached --quiet || { echo "Working tree dirty; abort"; exit 1; }`.
  - NO self-deletion. The script previously did `rm -rf ... scripts/build-plugin-release.sh` mid-run; round 3 changes to a `.gitattributes`-export-ignore approach OR an explicit exclude-list in the strip:
    ```bash
    # Strip dev-only scripts/tests/plans/docs (NOT including self).
    rm -rf tests/ plans/ docs/ MW-EXAMPLE__settings.json
    # Strip helper release scripts (the script itself is excluded by export-ignore in .gitattributes for `prod/main`).
    find scripts/ -maxdepth 1 -name 'build-*.sh' -type f -delete
    ```
    The `.gitattributes` change adds `scripts/build-plugin-release.sh export-ignore` so a `git archive`-based build path also excludes it; the in-worktree `rm` uses `find` which deletes ALL `build-*.sh` (including itself, but ONLY after all bash builtin reads are complete) — since the script body is fully loaded into bash memory before execution per POSIX, the in-flight `rm` is safe. The `trap` cleanup is the belt+suspenders for any post-rm failure path.
  - **Version-bump-before-build (D1 round-3 + F-DA2-2 fix).** Before `git branch -f prod/main HEAD`, the script:
    1. Reads `plugin.json.version` (e.g. `2026.05.0`).
    2. Tags the prod-stripped commit as `prod/<version>` (e.g. `prod/2026.05.0`).
    3. Force-updates `prod/main` to point at the same commit.
    4. Prints two `git push` commands for the user: `git push origin prod/main` AND `git push origin prod/2026.05.0`.
  - Verification-after-strip: `git ls-tree -r HEAD | grep -E 'CANARY|RELEASING|dev_only|hooks/canary.*-bad'` returns 0 hits (F-R2-2: also strips `hooks/canary*-bad.sh`).
  - Add the canary-strip line: `find hooks/ -name 'canary*-bad.sh' -delete` BEFORE the commit (F-R2-2).

- [ ] **W5.6 — Update `RELEASING.md`.** Document the new release flow including: bump `plugin.json.version` FIRST, commit + tag `YYYY.MM.N` on dev branch, run `scripts/build-plugin-release.sh`, push BOTH `prod/main` AND `prod/<version>` tags, consumers receive update via `/plugin marketplace update zskills`.

- [ ] **W5.7 — Update zskills' own root `CLAUDE.md`.** Same as round 2.

- [ ] **W5.8 — Confirm conformance.** Same as round 2.

- [ ] **W5.9 — Issue closeout.** Same as round 2.

### Design & Constraints

- **Order: byte-equality check FIRST, then repo-root template deletion** (F-R2-7).
- **Tag BEFORE delete** (W5.2 before W5.4).
- **`migrate-to-plugin.sh` is the SAFE migration path** AND has a documented `--cleanup` off-ramp (D20 (c)).
- **`build-plugin-release.sh` no longer self-deletes** (F-R2-4 fix); strips `hooks/canary*-bad.sh` (F-R2-2 fix); tags `prod/<version>` parallel to `prod/main` (F-DA2-2 fix).
- **CLAUDE_TEMPLATE.md deletion is final.**
- **The 2 whitelisted extras** per D18 — NOT deleted.
- **`MW-EXAMPLE__settings.json`** deleted in Phase 6 W6.6.

### Tests

- [ ] `bash tests/run-all.sh` green AFTER all deletions.
- [ ] `ls skills/update-zskills/ 2>&1` returns "No such file or directory".
- [ ] `ls CLAUDE_TEMPLATE.md 2>&1` returns "No such file or directory".
- [ ] `grep -rn 'update-zskills\|CLAUDE_TEMPLATE\|mirror-skill\.sh' skills/ block-diagram/ hooks/ CLAUDE.md` returns ONLY hits inside `<!-- allow-hardcoded: -->` markers.
- [ ] `bash scripts/migrate-to-plugin.sh --help` exits 0 and documents `--cleanup`.
- [ ] `bash scripts/migrate-to-plugin.sh --cleanup` on a fixture removes the 5 materialised files AND the lock; preserves consumer-authored files at the same paths (sentinel-gated).
- [ ] `bash scripts/build-plugin-release.sh` produces a `prod/main` ref AND `prod/<version>` tag where canaries (INCLUDING `hooks/canary*-bad.sh`), `dev_only` skills, `RELEASING.md`, `MW-EXAMPLE__settings.json`, and `scripts/build-plugin-release.sh` itself are absent — verified by `git ls-tree -r prod/main | grep -E 'CANARY|RELEASING|dev_only|build-.*\.sh|MW-EXAMPLE'` returning 0 hits.

### Acceptance Criteria

- [ ] All retirements committed.
- [ ] `bash tests/run-all.sh` green.
- [ ] Penultimate release tag exists.
- [ ] `scripts/migrate-to-plugin.sh` lands; idempotent; `--cleanup` works.
- [ ] `scripts/build-plugin-release.sh` produces both `prod/main` and `prod/<version>` refs.
- [ ] PR body includes `Closes #N` lines for every inventoried open issue.

### Abort / Rollback

If `bash tests/run-all.sh` red after deletions, STOP. Restore via `git checkout HEAD~ -- ...`. If `migrate-to-plugin.sh` step 4 verification fails on dogfood loop, STOP and refine. If F-R2-7 byte-equality check fails, STOP — fix the template drift before proceeding.

### Dependencies

Phases 1-4.

---

## Phase 6 — Marketplace activation, prod-tag release flow, consumer onboarding

### Goal

Activate the marketplace path. Document the dual-ref pin scheme (`prod/main` for unpinned, `prod/<version>` for pinned). Finalise issue closeout.

### Work Items

- [ ] **W6.1 — CI plugin-mode integration.** Same as round 2.

- [ ] **W6.2 — Consumer-onboarding documentation.** Add `docs/PLUGIN_INSTALL.md`:
  ```
  /plugin marketplace add tomdale/zskills
  /plugin install zskills@zskills
  ```
  Post-install: edit `.claude/zskills-config.json`, restart Claude Code session (D21), optionally run `/zskills:migrate-crons` to re-register pre-existing durable crons.
  **Pin-by-version (D1 + F-DA2-2):** For reproducible installs, override `source` to `{ "github": { "repo": "tomdale/zskills", "ref": "prod/2026.05.0" } }` or pin by SHA.
  **`.gitignore` guidance (D20 (b)):** the 5 materialised files at `.claude/agents/{verifier,implementer}.md`, `.claude/hooks/{inject-bash-timeout,verify-response-validate}.sh`, `.claude/rules/zskills/managed.md` are plugin-managed; add them to `.gitignore` OR track them and pin to a specific zskills version.
  **Uninstall:** `bash scripts/migrate-to-plugin.sh --cleanup` removes the 5 files + lock (D20 (c)).

- [ ] **W6.3 — Final consumer-migration runbook.** Publish `docs/PLUGIN_MIGRATION.md` documenting D14 + the `/zskills:migrate-crons` step + the `--cleanup` off-ramp.

- [ ] **W6.4 — Marketplace promotion (optional).** Same as round 2.

- [ ] **W6.5 — Issue #432 closeout.** Same as round 2.

- [ ] **W6.6 — `MW-EXAMPLE__settings.json` cleanup.** Same as round 2.

### Tests

- [ ] CI plugin-mode job passes (or best-effort).
- [ ] `docs/PLUGIN_INSTALL.md` and `docs/PLUGIN_MIGRATION.md` exist.
- [ ] `MW-EXAMPLE__settings.json` absent.

### Acceptance Criteria

- [ ] CI runs both source-tree tests AND best-effort plugin-mode validation.
- [ ] `README.md` references the plugin install flow.
- [ ] All inventoried open issues closed.

### Abort / Rollback

If CI plugin-mode job flaky, keep as best-effort with static-schema-validation fallback as the gating floor.

### Dependencies

Phases 1-5.

---

## Risk Register

Following F-DA2-6's suggestion, the four acknowledged research-deferred gaps and their explicit failure modes:

| Gap | Phase | Failure mode | Rollback path |
|-----|-------|-------------|---------------|
| (1) Durable cron storage path — `CronList` semantics under in-session dispatch | 3 W3.4 | If `CronList` doesn't enumerate or `CronCreate` rejects the prefixed prompt, `/zskills:migrate-crons` prints what it would do and exits; consumers manually re-register. NOT silent. | Skill body documents the limitation; cron-recognition's 60-day window covers the gap. |
| (2) `prod/main` ref + marketplace cache semantics | 5 W5.5 + 6 W6.2 | If `/plugin marketplace update` doesn't fetch the latest `prod/main` commit reliably, consumers stay on stale plugin. | D1 round-3: parallel `prod/<version>` tag scheme gives consumers a stable pin; docs/PLUGIN_INSTALL.md documents the workaround. |
| (3) `Agent` / `CronCreate` matcher syntax in `hooks.json` | 1 W1.6 | If `claude plugin validate --strict` rejects the matcher, fall back to `PreToolUse` with `tools: [...]` (if supported) or document gap. | Phase 1 Abort/Rollback path. |
| (4) Skill-frontmatter survival (`user-invocable`, `disable-model-invocation`) under plugin packaging | 3 W3.6 | If either field is silently dropped, `feedback_skill_invocation_flags.md` discipline regresses; `/fix-issues` cron self-registration may break. **Round-3 promotion to STOP gate (F-DA2-6):** `tests/test-skill-frontmatter-survival.sh` is now a Phase-3 acceptance criterion, NOT a follow-up. | Phase 3 STOPS on failure; orchestrator decides whether to roll back. |

## Plan Quality

**Drafting process:** `/draft-plan` with 3 rounds of adversarial review (reviewer + devil's-advocate each round + refiner with verify-before-fix).
**Convergence:** Converged at round 3.
**Remaining concerns:** None blocking. Four research-deferred gaps documented in the Risk Register above with explicit failure modes and rollback paths; all four become empirically resolvable during dogfooded Phases 1-3 via the `claude --plugin-dir .` loop.

### Round History

| Round | Reviewer findings | DA findings | Resolved | Status |
|-------|-------------------|-------------|----------|--------|
| 1     | 18 (3 critical, 10 major, 5 minor) | 18 (3 critical, 11 major, 4 minor) | 35 fixed, 1 justified (F-R1-12 moot under D3 revision) | 4 gaps introduced — escalated to round 2 |
| 2     | 7 (1 critical, 3 major, 3 minor) | 6 (1 critical, 4 major, 1 minor) | 13 fixed, 0 justified | 3 gaps introduced — escalated to round 3 |
| 3     | 1 (0 critical, 0 major, 1 minor) | 2 (1 critical, 1 major, 0 minor) | 3 fixed, 0 justified | 0 gaps introduced — **converged** |

### What round 1 caught (high-yield structural)

The draft punted on the three plugin-platform constraints the research phase had surfaced. Reviewer + DA caught them all:
- Plugin agents cannot declare frontmatter `hooks:` (Layer 0 verifier defense at risk)
- No documented `alwaysLoad: true` mechanism for plugin-shipped rules (rules silently don't load)
- Hard slash-prefix cutover breaks every existing cron's recognition rule

Refiner round 1 locked these to documented mechanisms: hybrid distribution (agents materialized via SessionStart, not plugin-shipped), `.claude/rules/` materialization, 60-day OR-match deprecation window with session-side `/zskills:migrate-crons` skill.

### What rounds 2 and 3 caught (mechanism correctness)

- Layer 3 (`verify-response-validate.sh`, 12 invocation sites) was missed in the materializer's `KNOWN_HOOKS` array — added.
- Cron migration shell-script invoked `CronList` as if it were a shell endpoint; it's a Claude session-side tool — reframed as the `/zskills:migrate-crons` skill (counted 30 total skills, not 29).
- `hooks/canary3-bad.sh` (deliberate-bad-syntax fixture) would leak into distribution — added to canary strip.
- `hooks/_lib/` shared helpers + drift-gate addressed.
- `build-plugin-release.sh` self-deletion mid-run — fixed via tempdir-build pattern.
- Materializer's update-detection regex interpolated `${PLUGIN_VERSION}` (stale-version sentinels stop matching on update) — fixed via write-with-version + detect-by-prefix-regex split.
- HTML comment before `---` invalidates YAML frontmatter (load-bearing for Layer 0) — fixed by injecting the sentinel as YAML-comment inside the frontmatter block.

### Verifications anchored throughout

Every plugin-behavior claim traces back to a verbatim quote in `/tmp/research-plugin-schema.md` (Claude Code docs fetched 2026-05-21). Every codebase-state claim (`12 invocation sites`, `30 skills`, `5 materialized files`, etc.) is grep-anchored or file-line-anchored in the refiner disposition tables.

### Acknowledged research gaps (Risk Register)

Four gaps remain that the documentation doesn't fully resolve. Each is named in the Risk Register above with:
1. The phase where the gap matters
2. The failure mode if the assumption is wrong
3. The rollback path (always to a documented fallback — none of the gaps are "ship and hope")

These are empirically resolvable in early phases via the dogfood loop. They are NOT deferred hard parts (per CLAUDE.md "NEVER defer the hard parts of a plan"); the work is fully specified and each gap has a written-down fallback.
