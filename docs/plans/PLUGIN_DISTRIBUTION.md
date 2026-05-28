---
title: Plugin Distribution Migration
created: 2026-05-21
status: active
---

# Plan: Plugin Distribution (Dual-Path)

> **Landing mode: PR** — All phases use worktree isolation with a named feature branch. `execution.landing = "pr"` and `execution.main_protected = true` per `.claude/zskills-config.json`.

## Overview

zskills currently distributes itself via a bespoke installer (`/update-zskills`) that mirrors `skills/` → `.claude/skills/`, copies `hooks/*.sh` → `.claude/hooks/`, copies `.claude/agents/*.md`, registers PreToolUse/PostToolUse hooks in the consumer's `.claude/settings.json`, and renders `CLAUDE_TEMPLATE.md` → `.claude/rules/zskills/managed.md` against `.claude/zskills-config.json`. Claude Code now ships a first-class plugin/marketplace system. **This plan adds plugin distribution as a permanent second install path alongside the existing `/update-zskills` path. Neither path is retired. Both are first-class.**

**Honest framing of scope (round-4 drift correction).** Rounds 1-3 specced a one-way replacement: `/update-zskills` retired, `CLAUDE_TEMPLATE.md` deleted, mirror trees gone, every internal slash reference bulk-rewritten to `/zskills:<skill>`. The round-4 pivot keeps both paths permanent. This is **roughly equivalent total work** to the single-path-with-cutover plan, not less work — the deletion phases shrink, but new dual-path-only work appears: dual-install detection, bidirectional switch tooling, two-renderer equivalence, dual-lane CI, dual-resolution prose for cron-fire rule, and per-site path-fallback for every in-skill script source reference. The earlier "Phase 3 narrows / Phase 5 narrows" framing under-stated this. The plan below honors the dual-path commitment without pretending the bill is smaller than it is. **What disappears:** the 1,621 prose-reference rewrites, the slash-prefix version-bump cascade, the CLAUDE_TEMPLATE.md deletion. **What appears:** dual-install detection + WARN, bidirectional `--switch-install-path` tooling with lock-LAST in both directions, renderer-equivalence test, plugin hooks.json conditional-skip when settings.json already registers, dual-path resolution in every script-source site and in the cron-fire rule prose, plugin-lane CI in addition to the existing source-tree lane, and a default-path recommendation in README.

> **Drift-proofing note (2026-05-26 realignment).** Every frozen integer count in this plan drifts monotonically as the repo grows and WILL rot again before /run-plan executes. This plan therefore states acceptance-gating quantities as **execution-time re-derivation commands**, not frozen integers. Each retains a parenthetical "(was N as of 2026-05-26)" for reader orientation, but the EXECUTABLE instruction is always a re-derivation. The re-derivation commands (run from repo root):
> - Resolver-sourcing SITES: `grep -rho 'zskills-resolve-config.sh' skills/ block-diagram/ | wc -l` (was 151)
> - Resolver-sourcing FILES: `grep -rl 'zskills-resolve-config.sh' skills/ block-diagram/ | wc -l` (was 44)
> - Resolver-sourcing SKILL DIRS (the version-bump key — one `metadata.version` per skill dir): `grep -rl 'zskills-resolve-config.sh' skills/ block-diagram/ | sed -E 's#^(skills/[^/]*\|block-diagram/[^/]*)/.*#\1#' | sort -u` (was 22 dirs: 20 in `skills/`, 2 in `block-diagram/`; `migrate-crons` may add 1 if its body sources the resolver)
> - Legacy `.claude/skills/update-zskills/scripts/` REFS: `grep -rho '\.claude/skills/update-zskills/scripts/' skills/ block-diagram/ | wc -l` (was 228)
> - Registered settings.json hooks: `python3 -c 'import json,os; d=json.load(open(".claude/settings.json")); s=set(); [s.add(os.path.basename(h["command"].split()[-1].strip(chr(34)))) for ev in d["hooks"] for m in d["hooks"][ev] for h in m["hooks"]]; print(sorted(s))'` (was 10 distinct scripts / 11 command entries as of 2026-05-26)
> - Skill counts: `ls -d skills/*/ | wc -l` (was 25) and `find block-diagram -mindepth 2 -name SKILL.md | wc -l` (was 4 — `screenshots/` is a non-skill asset dir)
>
> When implementing a phase, re-run the relevant command and use ITS output, not the parenthetical. A verifier comparing a diff against a re-derived count is the gate — never a hardcoded integer.

The headline structural choices:

1. **One plugin** named `zs` (slash prefix `/zs:`) distributed via `.claude-plugin/marketplace.json` at the repo root. Marketplace name stays `zskills` (the org-level identifier); the install address is `zs@zskills`. **One additional sibling plugin** named `zsbd` ships in the same marketplace (D2 — per pivot point 7).
2. **Hybrid distribution for the two zskills agents and Layer-3 hook.** `verifier.md`, `implementer.md`, `inject-bash-timeout.sh`, and `verify-response-validate.sh` materialise into the consumer's `.claude/` via a SessionStart hook so frontmatter `hooks:` survives unchanged AND the 12 in-skill invocation sites resolve without edits.
3. **Rules content is materialised, not packaged.** `CLAUDE_TEMPLATE.md` is the source-of-truth for BOTH install paths and is rendered into `$CLAUDE_PROJECT_DIR/.claude/rules/zskills/managed.md` — by `/update-zskills` Step B/D on the legacy path, by the SessionStart materialiser on the plugin path. A renderer-equivalence test gates byte-equal output (D24 — F-DA1-5).
4. **Slash prefix is install-path-dependent.** Source skills stay bare-prefix (`skills/<name>/SKILL.md`). On `/update-zskills` install the slash menu shows `/<skill>`; on plugin install it shows `/zs:<skill>`. No bulk rewrite. Cross-skill prose references in skill bodies stay bare and the cron-fire rule is taught to OR-match both forms permanently (D12 — F-DA1-1 Option Y locked). The block-diagram addon ships exactly the 4 SKILL.md-bearing dirs under `block-diagram/` (`add-block`, `add-example`, `model-design`, `review-feedback`); the sibling `screenshots/` dir is a non-skill asset dir and is NOT a fifth skill.
5. **`{{...}}` template substitution survives in both renderers.** A new Python renderer `scripts/render-managed-rules.py` runs from the plugin SessionStart hook; `/update-zskills` Step B/D continues to call that same Python renderer (D24 — collapse to one renderer to eliminate divergence, F-DA1-5 (i)).
6. **zskills dogfoods both lanes** from Phase 1 onward — `claude --plugin-dir .` for the plugin lane; source-tree `/update-zskills` for the legacy lane.
7. **Dual-install state is detected, not assumed away.** Phase 2 ships a detection probe inside the SessionStart materialiser; Phase 5 ships the bidirectional `--switch-install-path` tool with lock-LAST in both directions (D25 — F-DA1-4, F-DA1-7).
8. **Prod-strip discipline preserved.** Marketplace `source` points at `prod/main`, force-pushed at release time by `build-plugin-release.sh`. Parallel `prod/<version>` tags are pushed each release for consumers who want to pin (D1).

### Install paths (terminology)

| Surface | `/update-zskills` lane | Plugin lane |
|---|---|---|
| Install command | `/update-zskills install ...` | `/plugin marketplace add zeveck/zskills && /plugin install zs@zskills` |
| Slash prefix | bare (`/run-plan`, `/quickfix`) | `/zs:` (`/zs:run-plan`, `/zs:quickfix`) |
| Skills location | `.claude/skills/<name>/` | `${CLAUDE_PLUGIN_ROOT}/skills/<name>/` |
| Hooks location | `.claude/hooks/<name>.sh` | `${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh` (plus 4 materialised under `.claude/`) |
| Rules file | `.claude/rules/zskills/managed.md` (rendered by `/update-zskills`) | `.claude/rules/zskills/managed.md` (materialised by SessionStart hook) |
| Updates | `/update-zskills install` (re-fetch + re-mirror) | `/plugin marketplace update` |
| Marketplace name / Plugin name | n/a | `zskills` / `zs` |

**Default recommendation** (D26 — F-DA1-11): zskills' README recommends the plugin lane as the default for interactive workflows and the `/update-zskills` lane as the default for headless-CI consumers (the plugin lane requires the `claude` CLI on runners; the `/update-zskills` lane does not). Both paths are first-class; the recommendation is for the indecisive reader, not a constraint.

## Locked Decisions

D1. **Marketplace shape & release-tag scheme (revised — F-R2-1).** Single marketplace manifest at `.claude-plugin/marketplace.json` in the zskills repo root, listing TWO plugin entries: `zs` (the full distribution, `source: { "github": { "repo": "<owner>/zskills", "ref": "prod/main" } }`) and `zsbd` (the block-diagram addon subset, `source: "./block-diagram"` — relative-path string per `/tmp/research-plugin-schema.md` §3 lines 152-158, which lists `Relative path | string (e.g. "./my-plugin") | none | Local directory within the marketplace repo. Must start with ./`). Round-2 specced `github.path` on the sibling entry; that field does NOT exist in the documented `github` source schema (which only accepts `repo`, `ref?`, `sha?`). The relative-path form is the research-recommended alternative (§3 inferred implication, line 173). **Each release pushes BOTH the moving `prod/main` ref AND a parallel `prod/<version>` tag** (e.g., `prod/2026.05.0`). Consumers wanting reproducibility pin marketplace `source.sha` or override `source.ref` to `prod/<version>`. The `prod/main` force-push is the moving-window pointer for unpinned consumers. Per `/tmp/research-plugin-schema.md` §11 lines 437-446, when no `plugin.json.version` resolves, marketplace falls back to "git commit SHA" — so we ALSO bump `plugin.json.version` in the prod-stripped commit BEFORE force-pushing (W5.5 ordering). `docs/PLUGIN_INSTALL.md` documents the pin-by-version idiom. **Co-located plugin caveat:** because `zsbd` ships as `./block-diagram` inside the same marketplace repo, both plugin entries follow the same `prod/main` ref — the relative-path source uses the marketplace's checked-out ref by construction. No separate `ref` is needed (or supported) on the relative-path entry.

D2. **Plugin granularity — TWO plugins, ONE marketplace, EXPLICIT dependency (revised — F-R1-14, F-R1-17, F-DA1-8, F-DA2-1; block-diagram roster corrected 2026-05-26 — F-R1-2, F-DA1-1).** Round-2 D2 said "ONE plugin"; round 4 splits to two: `zs` (full, includes everything `/update-zskills` ships by default) and `zsbd` (addon subset matching `/update-zskills --with-block-diagram-addons`). **`zsbd` ships exactly the 4 SKILL.md-bearing block-diagram skills: `add-block`, `add-example`, `model-design`, `review-feedback`** (re-derive via `find block-diagram -mindepth 2 -name SKILL.md`; the sibling `screenshots/` dir under `block-diagram/` is a non-skill asset dir, NOT a fifth skill). `manual-testing` is NOT a block-diagram skill — it lives in `skills/manual-testing` and ships with `zs`; earlier drafts that named it in the `zsbd` roster were wrong. Both plugins ship from the same marketplace manifest in the same repo. **`zsbd`'s `plugin.json` declares `"dependencies": [{"name": "zs"}]`** per `/tmp/research-plugin-schema.md` §11 lines 554-560 (verbatim: `Other plugins this plugin requires, optionally with semver version constraints` and `If the plugin declares dependencies, Claude Code enables them transitively at the same scope, and the command fails when a dependency is not installed`). This closes the orphan-install failure mode F-DA2-1 surfaced: a consumer who runs `/plugin install zsbd@zskills` standalone — without `zs` — would otherwise receive the 4 block-diagram skills but zero supporting infrastructure (no `inject-bash-timeout.sh` materialiser, no `verifier`/`implementer` agents, no `block-stale-skill-version.sh` hook, no `managed.md` rules) because all of those ship from `zs`. The block-diagram skills source `zskills-resolve-config.sh` (verified by grep against `/workspaces/zskills/block-diagram/` — `add-block` and `add-example` are the 2 block-diagram dirs that source it) which lives under `zs` — standalone install would yield broken script-sourcing. With the dependency declaration, Claude Code transitively enables `zs` whenever `zsbd` is installed. If `dependencies` semantics turn out to be unreliable in empirical Phase 1 testing (the `/en/plugin-dependencies` page was research-deferred per §15 line 574), the fallback is a documented "install `zs` first" note in `docs/PLUGIN_INSTALL.md` — but the dependency-declaration is the load-bearing structural mechanism. `tests/test-plugin-manifest.sh` asserts `dependencies` present on `zsbd` and absent on `zs`, AND asserts the `zsbd` skill roster enumerates exactly the 4 SKILL.md-bearing dirs (re-derived, not a frozen list). The "if both installed, namespacing wins" sentence in round-2 D2 stays — that addresses the orthogonal duplicate-skill case, not orphan install. D17 retired.

D3. **`CLAUDE_TEMPLATE.md` is the dual-path source-of-truth.** `CLAUDE_TEMPLATE.md` stays at the repo root forever — it is the single source-of-truth read by `/update-zskills` Step B/D AND by the plugin SessionStart materialiser. **No `templates/CLAUDE_TEMPLATE.md` copy.** The dual-checkin-with-byte-equality-gate approach from round 3 is dropped (it created ongoing 2-file-edit overhead — F-R1-9 Option A locked). The plugin's `${CLAUDE_PLUGIN_ROOT}/scripts/render-managed-rules.py` reads `$CLAUDE_PROJECT_DIR/CLAUDE_TEMPLATE.md` if present; otherwise falls back to a bundled copy at `${CLAUDE_PLUGIN_ROOT}/CLAUDE_TEMPLATE.md` (synced from the repo root by `scripts/build-plugin-release.sh` during prod-strip). Per CLAUDE.md `## Migration scripts`, the rendered `managed.md` IS the lock and is written LAST.

D4. **`.template` hook strategy.** `block-agents.sh.template` and `block-unsafe-project.sh.template` retain their `.template` suffix on the `/update-zskills` lane (the suffix tells `/update-zskills` to substitute at install time). On the plugin lane, the SAME suffixed files ship in `hooks/` and are read by the same hook scripts at runtime (they read `$CLAUDE_PROJECT_DIR/.claude/zskills-config.json` directly — the `.template` suffix is purely an install-time signal for `/update-zskills`). Plugin `hooks.json` registers the suffixless runtime form for `block-agents.sh` and `block-unsafe-project.sh` by pointing at `${CLAUDE_PLUGIN_ROOT}/hooks/block-agents.sh.template` directly with a wrapper, OR — preferred — the plugin tree carries a sibling suffixless copy generated at release time by `build-plugin-release.sh`. **LOCKED: sibling suffixless copy in plugin tree** (simpler — no wrapper needed). `tests/test-hook-template-sibling.sh` asserts the two are byte-equal when both exist.

D5. **Source-of-truth layout.** `skills/` and `block-diagram/` stay at the zskills repo root and are referenced by BOTH plugin manifests (`zs` points at both; `zsbd` points at just `block-diagram/`). `hooks/` stays at root. `hooks/_lib/` ships as part of `hooks/`; the helpers (`hooks/_lib/git-tokenwalk.sh`, `hooks/_lib/resolve-effective-worktree-root.sh`) are inlined into 3+ hooks today and `tests/test-hook-helper-drift.sh` enforces byte-equality. The drift test STAYS in the suite. Path-fallback rewrites (W1.4) MUST NOT touch the inlined `_lib` regions in hooks. `.claude-plugin/` contains `plugin.json` and `marketplace.json`. **The `.claude/skills/`, `.claude/hooks/`, `.claude/rules/zskills/`, and `.claude/agents/` mirror trees in consumer repos STAY** — they are the `/update-zskills` lane's install state.

D6. **In-skill source paths — per-site dual-path fallback (revised — F-R1-5, F-DA1-3).** Round-2 D6 said "skill bodies migrate from `${CLAUDE_PROJECT_DIR}/.claude/skills/update-zskills/scripts/...` → `${CLAUDE_PLUGIN_ROOT}/scripts/...`". Under dual-path that breaks the `/update-zskills` lane (where `${CLAUDE_PLUGIN_ROOT}` is unset). **LOCKED: per-site existence-test fallback** in EVERY site that sources `zskills-resolve-config.sh` (re-derive: `grep -rho 'zskills-resolve-config.sh' skills/ block-diagram/ | wc -l` — was 151 as of 2026-05-26) and EVERY site referencing `.claude/skills/update-zskills/scripts/...` (re-derive: `grep -rho '\.claude/skills/update-zskills/scripts/' skills/ block-diagram/ | wc -l` — was 228 as of 2026-05-26). The canonical two-line form:

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/scripts/zskills-resolve-config.sh"
else
  . "${CLAUDE_PROJECT_DIR}/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
```

`references/canonical-config-prelude.md` updates to document the new two-line form as the preferred pattern (lane-portable; works on both install lanes). **`tests/test-skill-conformance.sh`'s per-fence sourcing-discipline check accepts EITHER the legacy one-liner OR the new dual-path form PERMANENTLY** (revised — F-DA2-4): under D23's permanent dual-path commitment the legacy one-liner stays valid forever on the `/update-zskills` lane (where `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh` exists). The legacy form on the plugin lane would fail (the path doesn't exist), but the legacy form was authored to run on `/update-zskills`-lane consumer repos in the first place — its semantics are unchanged. New code SHOULD prefer the dual-path two-line form for lane portability, but no deadline forces migration. Round-2 D6 specced a `2026.08.0` warn-only deadline; F-DA2-4 verified that the deadline contradicts D23's permanent-dual-path commitment (the legacy form will never fail on `/update-zskills` lane, so "warn after deadline" is a no-op-with-noise). Deadline dropped. All the mechanical sed edits in Phase 3 W3.1 land at once (the dual-path form is the new edit standard for in-skill source-paths, applied wholesale to avoid leaving half the codebase legacy and half dual). **Three distinct quantities — do NOT conflate (F-R1-6):** the resolver is sourced across ~151 SITES in ~44 FILES spanning ~22 SKILL DIRS (20 in `skills/`, 2 in `block-diagram/`: `add-block`, `add-example`) as of 2026-05-26. The `metadata.version` bump count keys off DISTINCT SKILL DIRS (one `metadata.version` per skill), so it is the skill-dir count — re-derive at execution time via `grep -rl 'zskills-resolve-config.sh' skills/ block-diagram/ | sed -E 's#^(skills/[^/]*\|block-diagram/[^/]*)/.*#\1#' | sort -u | wc -l` (was 22; `migrate-crons` may add 1 IF its body sources the resolver). The bump count is NOT the file count (44) and NOT the site count (151).

D7. **Phase 1 = pure-additive constraint relaxation.** Phase 1 does NOT move scripts. Phase 1's only edit surface is `.claude-plugin/`, `hooks/hooks.json`, `hooks/*.sh` (path-fallback edits where applicable), the 3 new plugin-manifest tests, the dev-loop docs, and the `zsbd` plugin entry. NO skill bodies are touched in Phase 1.

D8. **Conformance test surface — DUAL-PATH RESOLVED COUNTS (revised — F-R1-4, F-R1-13).**

- **0 RETIRED.** Pivot point 5 keeps `/update-zskills`, mirror trees, and `managed.md` rendering alive — every test that gates those invariants STAYS. The round-2 "9 retired" list is wrong under dual-path. Specifically the following all STAY: `test-skills-mirror-parity.sh`, `test-hooks-mirror-parity.sh`, `test-mirror-skill.sh`, `test-managed-md-up-to-date.sh`, `test-update-zskills-rerender.sh`, `test-update-zskills-agent-install.sh`, `test-update-zskills-migration.sh`, `test-update-zskills-paths-migration.sh`, `test-update-zskills-version-surface.sh`.
- **2 RESTRUCTURED (3 files):** `test-skill-conformance.sh` (teaches the per-fence sourcing-discipline check the new two-line dual-path form per D6); `test-skill-version-enforcement.sh` + `test-block-stale-skill-version*.sh` (3 tests as one structural change — same as round 2).
- **STAYS UNCHANGED:** `tests/test-hook-helper-drift.sh` — `hooks/_lib/` survives under D5.
- **16 NEW TEST FILES** (revised — F-R2-5; plugin-layout invariants + dual-path detection + renderer equivalence + cron-fire prose dual-path + hook-template sibling + switch-install-path):
  1. `tests/test-plugin-manifest.sh` (Phase 1)
  2. `tests/test-plugin-marketplace.sh` (Phase 1; covers BOTH plugin entries)
  3. `tests/test-plugin-self-load.sh` (Phase 1; covers both plugins)
  4. `tests/test-sessionstart-materialise.sh` (Phase 2)
  5. `tests/test-sessionstart-materialise-overwrite-guard.sh` (Phase 2)
  6. `tests/test-sessionstart-dual-install-detect.sh` (Phase 2 — F-R1-10, F-R1-12, F-DA1-4, F-R2-3)
  7. `tests/test-render-managed-rules-correctness.sh` (Phase 2)
  8. `tests/test-managed-md-renderer-equivalence.sh` (Phase 2 — D24, F-DA1-5)
  9. `tests/test-inject-bash-timeout-parity.sh` (Phase 2)
  10. `tests/test-verify-response-validate-parity.sh` (Phase 2)
  11. `tests/test-hook-template-sibling.sh` (Phase 2 — D4)
  12. `tests/test-cron-fire-rule-dual-path.sh` (Phase 3 — F-DA1-2)
  13. `tests/test-cron-prefix-or-match.sh` (Phase 3; permanent OR-match — F-R1-3)
  14. `tests/test-skill-frontmatter-survival.sh` (Phase 3 — F-DA2-6 STOP gate carried forward)
  15. `tests/test-switch-install-path.sh` (Phase 5 — D25 bidirectional)
  16. `tests/test-plugin-hook-skip-on-double-register.sh` (Phase 5 — F-DA1-4, F-R2-2, F-DA2-3 hook double-fire + version-skew)

  Net delta: `0 retired + 16 new + 3 restructured-in-place = +16 net new test files`. (Round-2 D8 said "11 NEW" with a 15-entry enumeration and arithmetic of "+14" — three internal inconsistencies; F-R2-5 corrected by adding `test-hook-template-sibling.sh` and recounting.) **Absolute base for verifier orientation:** the top-level test-file count was 135 as of 2026-05-26 (`find tests -maxdepth 1 -name '*.sh' -type f | wc -l`); post-plan target ≈ 135 + 16 = 151. Re-derive the base at execution time — it drifts as unrelated tests land. The +16/0/3 DELTA is the load-bearing acceptance gate, not the absolute total.

D9. **Plugin-self-load is a real load test, not bash-lint.** `tests/test-plugin-self-load.sh` does THREE things: (a) `claude plugin validate --strict` if CLI available else SKIP-with-reason, (b) Python JSONSchema validation of both `plugin.json` files (`zs` and `zsbd`), (c) `bash -n` on every hook + helper script, **WITH an exclusion list** — files matching `hooks/canary*-bad.sh` are skipped. Step (c) explicit exclusion lives in the script.

D10. **Versioning reconciliation.** Plugin-level `version` in each `plugin.json` tracks the zskills release tag (`YYYY.MM.N`). Per-skill `metadata.version: "YYYY.MM.DD+<hash>"` continues unchanged. `scripts/frontmatter-set.sh` stays at repo-root; STOP-message recovery commands remain correct without edit. Under dual-path, BOTH `plugin.json` files bump in lockstep — `tests/test-plugin-marketplace.sh` asserts equality.

D11. **Hybrid agent + Layer-3 materialisation.** `verifier.md`, `implementer.md`, `inject-bash-timeout.sh`, `verify-response-validate.sh` materialise into consumer-side `.claude/` via the plugin SessionStart hook. Plus the rendered `managed.md`. **Materialiser ships FIVE artifacts (round-3 count carried forward, unchanged under dual-path).**

1. `$CLAUDE_PROJECT_DIR/.claude/agents/verifier.md`
2. `$CLAUDE_PROJECT_DIR/.claude/agents/implementer.md`
3. `$CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh`
4. `$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh`
5. `$CLAUDE_PROJECT_DIR/.claude/rules/zskills/managed.md`

These exact paths are ALSO where `/update-zskills` writes today — so on a dual-installed system the same paths are touched by two install pipelines. The materialiser's overwrite guard (D20) detects zskills-authorship via sentinel and treats `/update-zskills`-written files (no sentinel) as zskills-owned-but-unsentinelled via the dual-install detection probe (D27) — not as consumer-authored.

D12. **Slash-prefix cron back-compat — PERMANENT OR-match (revised — F-R1-3, F-DA1-10).** Round-3 specced a 60-day deprecation window. Under dual-path the bare-prefix form lives forever (it's the canonical form on the `/update-zskills` lane). **LOCKED: permanent OR-match.** Phase 3 W3.3 rewrites `CLAUDE_TEMPLATE.md ## Cron-fired prompts` to recognise BOTH `Run /<skill-name>` and `Run /zs:<skill-name>` forms with **no expiry date**. `tests/test-cron-prefix-or-match.sh` asserts NO `2026-07-21` (or any sunset date) string exists in the recognition rule.

D12-prose. **Cron-fire rule SKILL.md path-resolution dual-path (F-DA1-2).** The recognition-rule prose currently reads `Read .claude/skills/<skill-name>/SKILL.md`. Under plugin install that path doesn't exist. Phase 3 W3.3 rewrites the literal to teach Claude to try BOTH:

```
Read `${CLAUDE_PLUGIN_ROOT}/skills/<skill-name>/SKILL.md` (plugin install) OR
`.claude/skills/<skill-name>/SKILL.md` (legacy install) via the Read tool.
```

`tests/test-cron-fire-rule-dual-path.sh` asserts the rendered `managed.md` contains BOTH path forms in the cron-fire-rule section.

D13. **Migrate-crons skill — OPTIONAL convenience (revised — F-R1-3, F-DA1-10).** The new `skills/migrate-crons/SKILL.md` ships but its purpose narrows: it's a one-time prefix-normalisation tool for consumers switching install lanes who want their cron prompts to read consistently. It is NOT a deprecation-driven requirement. Documented as optional. The skill body uses `CronList`/`CronDelete`/`CronCreate` (session-side tools) — not a shell script (round-3 F-DA2-1 fix carried forward).

D14. **Consumer migration runbook — DEFERRED to D25 (`--switch-install-path`).** Round-3 D14 specced `scripts/migrate-to-plugin.sh` as a one-way migration. Under dual-path, this becomes the forward direction of `scripts/switch-install-path.sh` (D25). See D25 for the full spec.

D15. **`/update-zskills` final form — STAYS, adds `--switch-install-path` mode (revised — F-R1-7).** Round-3 said "skill deleted in Phase 5"; under dual-path `/update-zskills` STAYS forever. Its final-form revision adds a `--switch-install-path={to-plugin,to-update-zskills}` mode that delegates to `scripts/switch-install-path.sh` (D25). Skill never deleted. A6 acceptance criterion retired.

D16. **Hook double-fire during dual-installed state (revised — F-DA1-4, F-R2-2, F-DA2-3).** Round-3 D16 said "no double-fire inside the atomic flow." Under dual-path, dual-install IS a permanent supported state. Three sub-contracts:

- **(a) Plugin hooks.json conditional skip — basename-match against settings.json, with version-skew guard.** Hook entries per `/tmp/research-plugin-schema.md` §5 lines 215-231 are anonymous `{ "type": "command", "command": "<string>" }` records — there is NO `name` field. The shim's matching mechanism is therefore basename-based, defined precisely as:
  1. Each plugin-registered hook script's first executable line sources `${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh`.
  2. The shim computes `MY_BASENAME=$(basename "${BASH_SOURCE[0]}")` — the basename of the hook script that sourced it. **Empirical correction (2026-05-26):** when a hook's first executable line is `source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"`, the shim's body executes inside the sourcing script's frame and `${BASH_SOURCE[0]}` is the sourcing hook's path (NOT the shim's). Round-3 spec said `[1]`; empirical test under `claude` 2.1.149 confirmed `[0]` is correct.
  3. The shim reads `$CLAUDE_PROJECT_DIR/.claude/settings.json` via Python (per `## Python is required`) and iterates `hooks.<event>[].hooks[]` entries.
  4. For each entry's `command` field, it extracts the script PATH-TOKEN via `command.split()[-1]` (the last whitespace-separated token, stripped of quoting). The script basename is `os.path.basename(path_token)` — compared to `MY_BASENAME`. **Empirical correction (2026-05-26):** the path-token inside `command` arrives with `$CLAUDE_PROJECT_DIR` / `${CLAUDE_PROJECT_DIR}` as a LITERAL string (settings.json stores the unexpanded form). Basename extraction works on the literal (basename returns the last path segment regardless of upstream variables). But any subsequent disk-existence check or file-read REQUIRES the shim to substitute the env var first — e.g., `consumer_script="${path_token/\$CLAUDE_PROJECT_DIR/$CLAUDE_PROJECT_DIR}"` (and the same for the `${...}` form) before passing to `head` / `[ -f ]`.
  5. **Version-skew check (F-DA2-3):** if a basename match is found, the shim compares the SCRIPT-version stamp between the plugin's copy (`${BASH_SOURCE[0]}`) and the settings.json-registered copy (`$consumer_script`, post-substitution per step 4). Each zskills hook script carries a `# zskills-hook-version: <YYYY.MM.N>` header comment on line 2 (added in Phase 1 W1.3 alongside the shim). The shim reads both stamps via `head -n 5 "$path" | grep -m1 'zskills-hook-version:'`. If the plugin's version is STRICTLY NEWER than the settings.json copy, the shim emits a one-time WARN to stderr (`zskills: settings.json hook <basename> is version <X> but plugin ships <Y>; deferring to settings.json copy. Run /update-zskills install or bash scripts/switch-install-path.sh --to-plugin to consolidate.`) AND defers to the settings.json copy (exits 0) — running stale-but-registered is preferred to silently double-firing, but the consumer is loudly told. The WARN is gated to once-per-session per-hook via a `.zskills/hook-skew-warned-<basename>` marker.
  6. If the plugin's version is EQUAL OR OLDER than the settings.json copy (or either header is absent), the shim exits 0 silently (settings.json wins — no version regression).
  7. If NO basename match is found, the shim returns (does not exit) and the calling hook continues normally.

  This is implementable per `/tmp/research-plugin-schema.md` §13 (plugin hooks compose additively at the harness level; each hook's bash body controls its own execution). The basename-match has a known cost: two legitimately distinct hooks with the same basename across lanes would be conflated — but zskills owns all its hook basenames and the source tree is the single point of basename assignment. Documented in the shim's top-of-file comment. Env-sentinel races (an alternative mechanism) are explicitly out-of-scope; the basename + version-stamp check is deterministic and stateless across hook invocations.

- **(b) SessionStart dual-install probe (D27).** Detect-and-WARN on dual-installed state, with a `--switch-install-path` recommendation. Once-per-session, gated by `.zskills/dual-install-warned` so the consumer doesn't see repeat-spam. The (a) version-skew WARN runs INDEPENDENTLY of this — it's per-hook, gated by `.zskills/hook-skew-warned-<basename>` markers, so a consumer with multiple skewed hooks sees one WARN per hook per session.

- **(c) `--switch-install-path` consolidation (D25).** The structural answer to long-lived dual-install state. The (a) and (b) WARNs both point the consumer here.

`tests/test-plugin-hook-skip-on-double-register.sh` exercises (a) in three fixture scenarios: (i) basename match, equal version → silent skip; (ii) basename match, plugin NEWER → WARN-then-skip + marker creation; (iii) no basename match → calling hook continues. `tests/test-sessionstart-dual-install-detect.sh` exercises (b).

D17. **Retired (was: single-plugin justification).** Under D2 the plugin split is locked, not deferred. D17 is removed; the dependency-semantics research note moves to D2's commentary.

D18. **Mirror-parity whitelist disposition.** 2 entries (`playwright-cli`, `social-seo`) — consumer-installed, NOT zskills-shipped; the mirror-parity test's whitelist excludes them. (This is `tests/test-skills-mirror-parity.sh`'s own whitelist, NOT the retired-by-D27 `KNOWN_SKILLS`/`known-skills.txt` detection list — those are unrelated mechanisms; the detection probe now uses wildcards per D27.) Unchanged from round 2.

D19. **`pluginConfigs.options` not used — documented deferral.** Unchanged from round 2. Per `/tmp/research-plugin-schema.md` §13, the plugin-config injection point is bypassed in favour of `.claude/zskills-config.json`. Deferred-research note: if a future Claude Code version makes `pluginConfigs.options` canonical, zskills will bridge. Tracked in a follow-up issue.

D20. **Materialiser side-effects (revised — F-DA1-4, F-R1-10).** Three sub-contracts:

- **(a) Overwrite guard — write-with-version, detect-by-prefix, frontmatter-aware injection.** As specced in round 3 (`^(#|<!--) zskills-materialised: ` PREFIX detection; YAML-comment sentinel inside `---` for frontmatter `.md`; HTML-comment for plain `.md`; shell-comment on line 2 for `*.sh`). **Round-4 extension:** before the overwrite-guard fires, the dual-install detection probe (D27) runs FIRST. If `/update-zskills` install state is detected at the destination paths (no sentinel, but content matches `/update-zskills`'s expected install set), the materialiser does NOT overwrite — it emits the dual-install WARN (D16(b)) and skips materialisation. This prevents the round-3 failure mode (F-R1-10) where the materialiser would silently overwrite `/update-zskills`-installed agent files.
- **(b) `.gitignore` guidance — scoped to plugin-lane consumers (F-R1-16).** `docs/PLUGIN_INSTALL.md` tells PLUGIN-LANE consumers to add the 5 materialised paths to `.gitignore` — they're plugin-managed. `/update-zskills`-lane consumers receive different guidance: leave the paths tracked (they ARE the install state).
- **(c) Uninstall cleanup — via `--switch-install-path --to-update-zskills` (D25), not a separate `--cleanup` mode.** Under dual-path the right verb is "switch lanes," not "uninstall." The lane-switch tool removes the 5 materialised files when switching plugin → `/update-zskills`. A separate `--cleanup-plugin-materialised-files` flag on `scripts/switch-install-path.sh` is provided for the "I just want them gone, I'm not switching lanes" case.

D21. **Materialiser-must-run-before-verifier ordering.** Unchanged from round 3. `/reload-plugins` behaviour empirically resolved in Phase 2 W2.1's PR test plan; conservative "restart Claude Code session after `/plugin install`" instruction stays in the runbook.

D22. **Batch-bump atomicity.** Round-3 D22's clean-tree precondition + `set -euo pipefail` discipline carries forward, but the scope shrinks: under dual-path Phase 3 only bumps the skill DIRS touched by the D6 per-site path-fallback edit (NOT all the skills bumped for slash-prefix rewrites — that work is gone). The bump set is the resolver-sourcing SKILL-DIR set — re-derive at execution time (`grep -rl 'zskills-resolve-config.sh' skills/ block-diagram/ | sed -E 's#^(skills/[^/]*\|block-diagram/[^/]*)/.*#\1#' | sort -u`; was 22 dirs as of 2026-05-26, possibly 23 if `migrate-crons` sources the resolver). Bump EXACTLY the dirs the W3.1 edit touched — `git diff --name-only` scoped to `skills/*/SKILL.md` and `block-diagram/*/SKILL.md` is the post-edit source of truth, not a frozen integer. `tests/test-skill-version-batch-bump.sh` simulates on a fixture.

D23. **Dual-path support is PERMANENT, not a transition state (NEW — F-R1-19, pivot directive).** zskills supports BOTH install paths as first-class permanent options. Neither is deprecated. `/update-zskills` is the canonical bare-prefix install path; the plugin is the canonical `/zs:`-prefix install path. The plan body, the README, the docs, and the test suite all reflect this. There is no future phase that consolidates to one path. (If a future redesign DOES consolidate, that's a separate plan with its own adversarial review.)

D24. **Renderer-equivalence test — single canonical substitution module + three callers (NEW — F-DA1-5, F-R2-4, F-DA2-2, F-DA2-5).** To eliminate two-renderer divergence: `/update-zskills` Step B §2 and Step D §2 (the substitution sub-steps) STOP instructing the agent to substitute placeholders mentally (the LLM-prose path) and instead instruct the agent to invoke `scripts/render-managed-rules.py`. The renderer is implemented as a thin wrapper over a SINGLE source-of-truth substitution module — `scripts/managed_rules_substitution.py` — that ALSO replaces the inlined Python substitution map currently embedded in `tests/test-managed-md-up-to-date.sh:30-65` (F-DA2-2). Three callers, ONE substitution map:

  1. **`scripts/render-managed-rules.py`** (used by plugin SessionStart materialiser via W2.1 and by `/update-zskills` Step B/D via W2.7) imports `from managed_rules_substitution import build_substitutions, apply` and writes the rendered file.
  2. **`tests/test-managed-md-up-to-date.sh`** is refactored (W2.7 same commit) to invoke `scripts/render-managed-rules.py` against the live config + template and diff its output against the checked-in `managed.md`. The inlined Python `subs = {...}` block at lines 30-65 is deleted.
  3. **Plugin SessionStart materialiser** invokes the same renderer via `python3 "${PLUGIN}/scripts/render-managed-rules.py" ...`.

  `tests/test-managed-md-renderer-equivalence.sh` is the belt-and-suspenders gate: it invokes `scripts/render-managed-rules.py` from BOTH the `/update-zskills` Step D code path (the Python wrapper W2.7 introduces) AND the plugin materialiser's path against 5 fixture `(config, template)` pairs and asserts byte-equal output. Because all three callers route through the same `managed_rules_substitution` module, byte-equality is structurally guaranteed; the equivalence test is the canary that catches refactor regressions.

  **Step B/D LLM-prose substitution is DELETED IN THE SAME COMMIT, NOT DEPRECATED.** Round-2 D24 said "retain for one release as a deprecated section, then remove" — but the dual-path commitment (D23) makes the legacy `/update-zskills` render path PERMANENT. Retaining the LLM-prose alongside the Python-invocation language would re-open the divergence surface D24 is supposed to close: a future agent reading Step B's prose could execute the LLM-prose path instead of the Python call. Under F-R2-4 Option (a): in W2.7's single commit, the substitution sub-steps in Step B §2 and Step D §2 are REPLACED outright with the Python invocation. The remainder of Step B (config-scan, root-CLAUDE.md migration sub-step, install report) is unchanged. No "one release" window, no follow-up issue, no `test-step-b-removed.sh` test — there's nothing left to remove. Readers wanting the historical LLM-prose can `git log -p skills/update-zskills/SKILL.md`. The `tests/test-managed-md-renderer-equivalence.sh` gate is added to `bash tests/run-all.sh` AS PART OF W2.7's commit — not earlier (where it would be meaningless against pre-port LLM-prose) and not later (it stabilises the moment Python becomes canonical).

  This also retires F-DA2-2's "three substitution maps" concern: post-W2.7 there is ONE map (`scripts/managed_rules_substitution.py`) consumed by THREE callers — no drift possible.

D25. **Bidirectional `scripts/switch-install-path.sh` with lock-LAST in BOTH directions (NEW — F-R1-8, F-DA1-7).** Replaces the round-3 `scripts/migrate-to-plugin.sh` one-way script. Two modes:

- `--to-plugin` (from `/update-zskills` lane):
  1. Pre-flight inventory of `/update-zskills` artifacts (mirror tree, hook scripts, settings.json registrations).
  2. Strip zskills-installed hook entries from `.claude/settings.json` via Python helper.
  3. User instruction: "Now in your Claude session, run `/plugin marketplace add zeveck/zskills` + `/plugin install zs@zskills`. Restart Claude Code (close + reopen). Optionally run `/zs:migrate-crons` to re-tag pre-existing crons. Return here and type `done`."
  4. Block on `read -p`.
  5. Verify plugin install via `${CLAUDE_PLUGIN_DATA}` or `$HOME/.claude/plugins/cache`.
  6. Sentinel-gated removal of `.claude/skills/<zskills>/`, `.claude/hooks/<zskills>/`, `.claude/rules/zskills/managed.md` — removal is gated on **EITHER the zskills sentinel OR a basename match against the shipped source tree computed at runtime** (`hooks/*.sh`, `skills/*/`, `block-diagram/*/`), consistent with D27's wildcard detection. Does NOT touch consumer-authored or third-party skills. (The retired `KNOWN_SKILLS`/`KNOWN_HOOKS` fixture lists from round 3 are NOT used — D27 replaced them with wildcards; do not re-create them.) Neither this step nor the `--to-update-zskills` step 6 touches `.zskills/` — claim markers and other runtime state are lane-independent and preserved across switches (F-DA1-6 confirmed safe).
  7. **Write the lock file LAST.** Path: `.claude/zskills-install-lane`. Content: single line, bare value, trailing newline — `plugin\n` (the lock claim). Atomic via `printf 'plugin\n' > "$PROJ/.claude/zskills-install-lane.tmp" && mv "$PROJ/.claude/zskills-install-lane.tmp" "$PROJ/.claude/zskills-install-lane"`. Per F-R2-6, the format is bare-value-with-trailing-newline (not `key: value`); detection probes read it with `[ "$(cat .claude/zskills-install-lane 2>/dev/null)" = plugin ]`.
  8. Print `.gitignore` and CI-workflow guidance.

- `--to-update-zskills` (from plugin lane):
  1. Pre-flight inventory of materialised plugin artifacts (5 files + sentinels).
  2. User instruction: "Now in your Claude session, run `/plugin uninstall zs@zskills`. Restart Claude Code. Then run `/update-zskills install`. Return here and type `done`."
  3. Block on `read -p`.
  4. Verify plugin uninstalled (`${CLAUDE_PLUGIN_DATA}` no longer lists `zs`).
  5. Verify `/update-zskills install` ran — check for `.claude/skills/update-zskills/SKILL.md` and `.claude/hooks/block-stale-skill-version.sh` presence (non-sentinelled — `/update-zskills` writes without sentinels).
  6. Sentinel-gated removal of the 5 materialised files (only if they STILL carry a zskills sentinel — meaning `/update-zskills install` didn't already overwrite them).
  7. **Write the lock file LAST.** Path: `.claude/zskills-install-lane`. Content: single line, bare value, trailing newline — `update-zskills\n` (the lock claim). Same atomic-rename pattern as the forward direction. Per F-R2-6, the format is bare-value-with-trailing-newline; D27's detection probe reads it with `[ "$(cat .claude/zskills-install-lane 2>/dev/null)" = update-zskills ]`.

Both directions enforce the lock-LAST contract per CLAUDE.md `## Migration scripts`. Both directions have an Abort/Rollback path documented in `docs/PLUGIN_MIGRATION.md`. Both directions have a fixture-dogfood acceptance test in `tests/test-switch-install-path.sh`.

D26. **Default install path recommendation in README (NEW — F-DA1-11).** README documents both paths. Recommended default:

- **Interactive workflows (default):** plugin lane (`/plugin install zs@zskills`). One-command updates, marketplace-native, slash menu shows `/zs:` prefix.
- **Headless CI consumers:** `/update-zskills` lane. No `claude` CLI required on runners; install state is checkable via plain file presence.
- **Power users:** either — the difference is cosmetic.

`docs/PLUGIN_INSTALL.md` carries the full tradeoff matrix. README points to it.

D27. **Dual-install detection probe — conservative ANY-hit detection (NEW — F-R1-10, F-R1-12, F-DA1-4, F-R2-3).** A function `detect_install_state()` in `${CLAUDE_PLUGIN_ROOT}/hooks/_lib/detect-install-state.sh` returns one of `fresh`, `plugin`, `update-zskills`, or `dual`. Detection inputs are NOT binary per-input; the probe collects evidence and picks the lane CONSERVATIVELY (any hit-class fires the corresponding lane; ambiguous combinations collapse to `dual`). Round-2 D27 assumed each detection input was binary and missed partial-cleanup states (e.g., consumer manually deleted `.claude/skills/update-zskills/SKILL.md` to "clean up" but orphaned `.claude/hooks/block-stale-skill-version.sh` + `.claude/rules/zskills/managed.md` remain). F-R2-3 forces the broadening below.

**`/update-zskills`-lane evidence (ANY hit counts):**

- `.claude/zskills-install-lane` lock file content is `update-zskills` (lock-LAST winner per D25)
- **Any** `.claude/skills/*/SKILL.md` exists (wildcard — F-DA3-1 closure 2026-05-26). Empirical test confirmed the round-3 KNOWN_SKILLS fixture-list approach silently misclassified a new-skill case as `fresh`. Wildcard fallback treats ANY skill mirror as `/update-zskills`-lane evidence regardless of basename, even if zskills adds skills later that aren't yet known to this probe. Acceptable false-positive: a third-party skill mirror under `.claude/skills/` would also flag — but plugin install would refuse to materialize over it anyway, which is the desired conservative behavior. Retires the `hooks/_lib/known-skills.txt` fixture file from round 3 and obviates F-DA3-1's proposed `tests/test-known-lists-complete.sh` completeness gate (no list to complete).
- **Any** `.claude/hooks/*.sh` exists (wildcard — same reasoning as above). Retires `hooks/_lib/known-hooks.txt`. Caveat: the materialiser writes to `.claude/hooks/` too (Layer 0 + Layer 3 — D11), so this wildcard must run AFTER the materialiser sentinel check below; the sentinel distinguishes plugin-materialised hooks from `/update-zskills`-installed ones. Concretely, the lane-resolution order in `detect_install_state()` is: (1) check for any plugin-sentinelled artifacts FIRST (plugin-lane evidence), (2) check for any non-sentinelled `.claude/hooks/*.sh` OR `.claude/skills/*/SKILL.md` SECOND (update-zskills-lane evidence). A file with sentinel counts as plugin-lane; without, as update-zskills-lane.
- `.claude/agents/verifier.md` or `.claude/agents/implementer.md` exists WITHOUT a materialiser sentinel (the materialiser writes them WITH a sentinel; `/update-zskills` writes them WITHOUT)
- `.claude/rules/zskills/managed.md` exists WITHOUT a materialiser sentinel
- `.claude/settings.json` contains any `hooks.<event>[].hooks[].command` entry whose path-token (per the D16(a) extraction in step 4) points to a path UNDER `.claude/hooks/` (the substituted-`$CLAUDE_PROJECT_DIR/.claude/hooks/...` form). A generic settings.json hook whose script lives elsewhere — a consumer's own custom hook in `tools/` or `scripts/` — does NOT trigger this evidence. Combined with the wildcard `.claude/hooks/*.sh` rule above, this dual-checks the install lane via two independent paths (the file's presence + the settings.json registration of it). Note: the file-presence wildcard rule is the LOAD-BEARING signal; this settings.json rule is supplementary cross-check, useful when a consumer manually deleted `.claude/hooks/` content but forgot the settings.json registration entries (one common partial-cleanup pattern).

**Plugin-lane evidence (ANY hit counts):**

- `.claude/zskills-install-lane` lock file content is `plugin`
- Any of the 5 materialised artifacts (D11) is present AND carries the materialiser sentinel

**Lane resolution:**

- `lane=fresh` — ZERO `/update-zskills`-lane hits AND ZERO plugin-lane hits.
- `lane=plugin` — at least one plugin-lane hit AND zero `/update-zskills`-lane hits.
- `lane=update-zskills` — at least one `/update-zskills`-lane hit AND zero plugin-lane hits. SessionStart materialiser EXITS EARLY with WARN: `zskills plugin loaded but install lane is /update-zskills. Run /update-zskills --switch-install-path=to-plugin to switch, or /plugin uninstall zs@zskills to remove the plugin.`
- `lane=dual` — BOTH plugin-lane AND `/update-zskills`-lane evidence detected (which subsumes the round-2 "partial-cleanup" edge case: orphan mirror-files without lock OR SKILL.md still register as `/update-zskills` hits and pair with materialiser sentinels to produce `dual`). Emit WARN identifying duplicate-by-basename hooks + pointing at `scripts/switch-install-path.sh --to-plugin` for consolidation. **Materialiser REFUSES to write under `lane=dual` and `lane=update-zskills`** — both states would clobber `/update-zskills` install state.

**Partial-state safety:** any consumer in a "manually-half-cleaned" state (e.g., deleted SKILL.md but left orphaned hook scripts) classifies as `update-zskills` (orphan hook is a `/update-zskills`-lane hit) — materialiser exits early, no clobber. Consumer is directed to `--switch-install-path` for cleanup. This closes the F-R2-3 failure mode where round-2 D27 would have silently materialised over orphan files.

Probe is gated to once-per-session via `.zskills/dual-install-warned` marker so consumers don't see repeat-spam. The probe runs FIRST in the materialiser (before the overwrite-guard) so a `lane=update-zskills` state never gets silently overwritten by the materialiser. `tests/test-sessionstart-dual-install-detect.sh` asserts each lane resolution + a FIFTH fixture exercising the partial-cleanup case (orphan hook, deleted SKILL.md, no sentinels) classifies as `update-zskills` and triggers the early-exit.

## What this plan does NOT do

- **Memory-anchor updates** — out of scope per CLAUDE.md.
- **PRESENTATION.html updates** — separate cosmetic pass.
- **Plugin-dependencies semantics for cross-plugin runtime deps** — N/A under D2 (subset, not dependent).
- **Marketplace listing on Anthropic's discoverability surface** — out of scope.
- **`pluginConfigs.options` bridging** — deferred per D19.
- **Bulk slash-prefix rewrite of 1,621 prose references** — explicitly out per pivot point 4. Plugin-lane consumers see bare slashes in skill-body prose; the cron-fire OR-match (D12) and Skill-tool prefix-agnostic dispatch (the Skill-tool dispatch sites are prefix-agnostic by construction — `grep -rho 'subagent_type' skills/ block-diagram/ | wc -l` was 26 as of 2026-05-26; no acceptance gate keys off this count) absorb the cross-skill dispatch needs; remaining bare-slash prose is documented as a known plugin-lane UX rough edge in `docs/PLUGIN_INSTALL.md` under "Known tradeoffs." (Option Y from the orchestrator's three-option framing — accept the gap, document the tradeoff. See F-DA1-1 disposition.)
- **`/update-zskills` retirement** — `/update-zskills` is permanent (D15). The legacy installer surface STAYS forever.
- **`CLAUDE_TEMPLATE.md` deletion** — STAYS at repo root forever as the dual-path source-of-truth (D3).
- **`templates/CLAUDE_TEMPLATE.md` mirror** — NOT created (D3 explicit revision).
- **Auto-edit consumer `.gitignore`** — per D20(b), `.gitignore` advice is documented per-lane, not enforced.
- **A6 "/update-zskills is gone" acceptance criterion** — retired (D15).

## Acceptance Criteria (plan-wide)

- [ ] **A1.** Both plugin manifests load. **Verification:** `bash tests/test-plugin-self-load.sh` exits 0 for `zs` AND `zsbd`.
- [ ] **A2.** ALL skills are invocable under BOTH bare prefix (on `/update-zskills` lane) AND `/zs:` prefix (on plugin lane). The skill inventory is `26 in skills/ (25 existing + the new migrate-crons; re-derive via ls -d skills/*/ | wc -l, was 25 as of 2026-05-26) + 4 in block-diagram/ (re-derive via find block-diagram -mindepth 2 -name SKILL.md | wc -l, was 4) = 30 total at execution time`. **Do NOT pin a sub-count in any test** — enumerate dynamically. **Verification:** `tests/test-cron-prefix-or-match.sh` asserts the recognition rule contains BOTH prefix patterns; an "all skills invocable" assertion must derive the roster via `find skills block-diagram -mindepth 2 -name SKILL.md` rather than a literal. `tests/test-no-unprefixed-zskills-references.sh` is RETIRED under dual-path — there's nothing to prefix-check because both forms are valid.
- [ ] **A3.** Layer 0 + Layer 3 of the verifier-cannot-run defense survive in BOTH install paths. **Verification:** `tests/test-sessionstart-materialise.sh` (plugin lane); `tests/test-update-zskills-agent-install.sh` (legacy lane, STAYS per D8).
- [ ] **A4.** Rules content reaches Claude's context via `InstructionsLoaded` in both lanes. **Verification:** `tests/test-render-managed-rules-correctness.sh` + `tests/test-managed-md-renderer-equivalence.sh` (D24).
- [ ] **A5.** Conformance test suite reflects dual-path. **Verification:** `bash tests/run-all.sh` green; 0 retired tests; 16 new tests present; 2 restructured (3 files) pass; `test-hook-helper-drift.sh` STAYS green. PR body documents net delta: `0 retired + 16 new + 3 restructured-in-place = +16 net new test files` (revised — F-R2-5).
- [ ] **A6 — RETIRED** (was: `/update-zskills` gone). `/update-zskills` STAYS forever (D15).
- [ ] **A7.** zskills repo dogfoods BOTH lanes (D26 — plugin lane via `claude --plugin-dir .`; legacy lane via source-tree `/update-zskills`).
- [ ] **A8.** `scripts/switch-install-path.sh --to-update-zskills` reverses cleanly. **Verification:** `tests/test-switch-install-path.sh` fixture-dogfood (D25); post-reverse, `/briefing summary` works (bare prefix).
- [ ] **A9.** `scripts/switch-install-path.sh --to-plugin` migrates cleanly in the forward direction. **Verification:** same test; post-forward, `/zs:briefing summary` works.
- [ ] **A10.** Skill-frontmatter survival (D12 + F-DA2-6 STOP gate carried forward). **Verification:** `tests/test-skill-frontmatter-survival.sh`.
- [ ] **A11.** Renderer equivalence (D24). **Verification:** `tests/test-managed-md-renderer-equivalence.sh` runs both render code paths on 5 fixture configs, asserts byte-equal output.
- [ ] **A12.** Dual-install detection works (D27). **Verification:** `tests/test-sessionstart-dual-install-detect.sh` exercises all 4 lane states (`fresh`/`plugin`/`update-zskills`/`dual`) and asserts the documented behaviour for each.
- [ ] **A13.** Hook double-fire prevention (D16(a), F-DA1-4). **Verification:** `tests/test-plugin-hook-skip-on-double-register.sh` simulates a settings.json + plugin hooks.json dual-registration and asserts only one execution per Bash event.
- [ ] **A14.** Cron-fire rule resolves SKILL.md under BOTH layouts (D12-prose, F-DA1-2). **Verification:** `tests/test-cron-fire-rule-dual-path.sh` reads the rendered `managed.md`, asserts both `${CLAUDE_PLUGIN_ROOT}/skills/...` and `.claude/skills/...` path forms appear in the cron-fire-rule section.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Plugin scaffold (`zs` + `zsbd`) + dev-loop transition | ✅ | 2d73aeb | PR #763; plugin manifests + marketplace + hooks.json + D16(a) shim + path-fallback; CI green |
| 2 — SessionStart materialiser (5 artifacts) + dual-install detection + renderer equivalence | ⬚ | | |
| 3 — Dual-path recognition + cron-fire path-aware rules + script-path fallback in all resolver-sourcing + legacy-script-path sites (re-derive; was 151/228) + `migrate-crons` skill | ⬚ | | |
| 4 — Conformance test surface (no retirements; 16 new tests stabilise; 2 restructured) | ⬚ | | |
| 5 — Dual-path hardening: plugin-mode CI lane, bidirectional `--switch-install-path`, hook double-fire prevention, `build-plugin-release.sh` | ⬚ | | |
| 6 — Marketplace activation, prod-tag release flow, README + dual-path docs | ⬚ | | |

## Risk Register

| Gap | Phase | Failure mode | Rollback path |
|-----|-------|-------------|---------------|
| (1) `CronList` semantics under in-session dispatch | 3 W3.4 | If `CronList` doesn't enumerate or `CronCreate` rejects the prefixed prompt, `/zs:migrate-crons` prints what it would do and exits; consumers manually re-register. NOT silent. **Under dual-path the skill is OPTIONAL (D13), not gating.** | Skill body documents the limitation; permanent OR-match means crons keep working regardless of skill execution. |
| (2) `prod/main` ref + marketplace cache semantics | 5 W5.5 + 6 W6.2 | If `/plugin marketplace update` doesn't fetch latest reliably, consumers stay on stale plugin. | Parallel `prod/<version>` tag scheme (D1) gives consumers a stable pin; docs/PLUGIN_INSTALL.md documents the workaround. |
| (3) `Agent` / `CronCreate` matcher syntax in `hooks.json`; relative-path marketplace source; `dependencies` semantics | 1 W1.6 | If `claude plugin validate --strict` rejects the matcher, fall back to `PreToolUse` with `tools: [...]`. If the relative-path source for `zsbd` is rejected, fall back to `git-subdir` (both documented per `/tmp/research-plugin-schema.md` §3). If `dependencies` on `zsbd` is rejected (research-deferred per §15 line 574), accept orphan-install gap and document in `docs/PLUGIN_INSTALL.md`. **Empirical update (2026-05-22):** ran `claude plugin validate --strict` on a fixture plugin with `Bash`, `Agent`, `CronCreate`, `Edit|Write`, `SessionStart`, `Notification`, and several other matchers — ALL passed. The matcher catalog published in the Claude Code docs is incomplete (`CronCreate` isn't enumerated), but the validator and runtime both accept it. Today's production `.claude/settings.json` uses `CronCreate` with confirmed firing behavior. Net effect: Phase 1 W1.6's `claude plugin validate --strict` gate catches structural schema errors but does NOT enforce matcher correctness. Empirical runtime confirmation moves to Phase 2 dogfood as a known-low-risk verification. (Note: zskills has dropped `NotebookEdit` from its `block-main-edits` matcher — the matcher is now `Edit|Write` — so any residual ambiguity around that specific matcher token is moot for our hooks.) | Phase 1 Abort/Rollback path. |
| (4) Skill-frontmatter survival under plugin packaging | 3 W3.6 | If `user-invocable`/`disable-model-invocation` is dropped, `feedback_skill_invocation_flags.md` discipline regresses. STOP gate per F-DA2-6 carried forward. | Phase 3 STOPS; orchestrator decides whether to roll back. |
| (5) **Dual-install hook double-fire (NEW — F-DA1-4)** | 5 W5.7 | If `tests/test-plugin-hook-skip-on-double-register.sh` is flaky or the conditional-skip shim fails on a consumer's settings.json shape, every git commit may fire the version-check twice with potentially divergent results. | Conditional-skip shim is the primary defense; D27's dual-install probe + WARN is the secondary defense. If both fail, consumers can manually run `--switch-install-path` to consolidate. |
| (6) **Renderer divergence (NEW — F-DA1-5)** | 2 W2.7 | If porting `/update-zskills` Step D to call the Python renderer reveals an edge case the LLM-prose substitution handled differently, consumers on the legacy lane could get drifted `managed.md` content vs plugin consumers. | D24 collapse-to-one-renderer eliminates the divergence surface; `tests/test-managed-md-renderer-equivalence.sh` is the gate. |
| (7) **Reverse migration directionality (NEW — F-DA1-7)** | 5 W5.6 | If `--to-update-zskills` mode has an ordering bug (e.g., removes materialised files BEFORE `/update-zskills install` writes its own copies), consumers can end up in an unbootable state. | Lock-LAST in BOTH directions per D25; fixture-dogfood test `tests/test-switch-install-path.sh` covers both directions. |
| (8) **Bare-slash prose UX gap on plugin lane (NEW — F-DA1-1)** | 6 W6.2 | Plugin-lane consumers reading skill-body prose see references to `/quickfix`, `/run-plan`, etc. — slashes that don't resolve to the prefixed plugin form in their slash menu. Cross-skill dispatch via Skill tool works (prefix-agnostic); slash-menu autocomplete shows `/zs:` prefix; ONLY the inline prose is mismatched. | Documented as a known tradeoff in `docs/PLUGIN_INSTALL.md` "Known tradeoffs." Acceptable because (a) Skill-tool dispatch is the load-bearing path, (b) cron-fire OR-match handles auto-fire, (c) typed slash invocation just requires the user to mentally swap `/foo` → `/zs:foo`. Future work: a stop-gate test (`tests/test-no-bare-skill-slashes-in-frontmatter-description.sh`) could enforce the user-visible `description` field stays prefix-neutral. Filed as a follow-up issue, not in this plan. |
| (9) **Claim-hook deny-envelope recovery paths are `/update-zskills`-lane-only (NEW — F-DA1-7)** | 1 W1.4 | `block-run-plan-unclaimed.sh` and `block-fix-issue-unclaimed.sh` emit recovery commands citing `${MAIN_ROOT}/.claude/skills/<skill>/scripts/claim-*.sh`. On a pure-plugin consumer (no `.claude/skills/` mirror) the recovery instruction names a non-existent file; the hook denies correctly but the agent is told to run a command that can't resolve. | W1.4 rewrite pattern 2 adds the `${CLAUDE_PLUGIN_ROOT:-${MAIN_ROOT}/.claude/skills/<skill>}` dual-resolution arm to both claim hooks' recovery paths AND to the `zskills-paths.sh` two-location fallback in `block-run-plan-unclaimed.sh`. This is the one place the dual-path attack genuinely lands on the new hooks (per F-DA1-7 — all other dual-path concerns on the claim hooks are covered by the W1.3 "every plugin-registered hook" rule and D27's wildcard). |

---

## Phase 1 — Plugin scaffold (`zs` + `zsbd`) + dev-loop transition (additive)

### Goal

Land `.claude-plugin/plugin.json` for `zs`, a sibling `block-diagram/.claude-plugin/plugin.json` for `zsbd`, the marketplace manifest at root listing both, and `hooks/hooks.json` for `zs`. Both plugins load via `claude --plugin-dir .` but no existing behaviour changes.

### Work Items

- [ ] **W1.1** — Create `.claude-plugin/plugin.json` for `zs`:
  ```json
  {
    "name": "zs",
    "displayName": "Z Skills",
    "version": "2026.05.0",
    "description": "Agent-discipline skill framework: plans, fix-issues, draft-plan, run-plan, land-pr, and more.",
    "author": { "name": "Rich Conlan", "url": "https://github.com/zeveck/zskills" },
    "homepage": "https://github.com/zeveck/zskills",
    "repository": "https://github.com/zeveck/zskills",
    "license": "MIT",
    "keywords": ["zskills", "agent", "claude-code", "skills", "plans"],
    "skills": ["./skills/", "./block-diagram/"],
    "hooks": "./hooks/hooks.json"
  }
  ```
  AND create `block-diagram/.claude-plugin/plugin.json` for `zsbd`:
  ```json
  {
    "name": "zsbd",
    "displayName": "Z Skills — Block Diagram Addons",
    "version": "2026.05.0",
    "description": "Block-diagram-editor skill addons (add-block, add-example, model-design, review-feedback).",
    "author": { "name": "Rich Conlan", "url": "https://github.com/zeveck/zskills" },
    "homepage": "https://github.com/zeveck/zskills",
    "repository": "https://github.com/zeveck/zskills",
    "license": "MIT",
    "keywords": ["zskills", "block-diagram", "addons"],
    "skills": ["./"],
    "dependencies": [ { "name": "zs" } ]
  }
  ```
  NO `agents` field on either — agents are NOT plugin-shipped (D11). NO `hooks` field on `zsbd` — it's a strict skill-only addon; all hooks ride with `zs` via the dependency declaration (D2 / F-DA2-1). Plugin names: `zs` and `zsbd`; marketplace name `zskills` (W1.2). `skills: ["./"]` on the sibling manifest tells Claude Code the plugin's root IS the skills directory; this works because the marketplace's relative-path source (`./block-diagram`, D1) makes `block-diagram/` the plugin root for `zsbd`.

- [ ] **W1.2** — Create `.claude-plugin/marketplace.json`:
  ```json
  {
    "$schema": "https://anthropic.com/schemas/claude-plugin-marketplace.json",
    "name": "zskills",
    "owner": { "name": "Rich Conlan", "url": "https://github.com/zeveck" },
    "description": "Z Skills — agent-discipline skill framework",
    "version": "1",
    "plugins": [
      {
        "name": "zs",
        "source": { "github": { "repo": "zeveck/zskills", "ref": "prod/main" } }
      },
      {
        "name": "zsbd",
        "source": "./block-diagram"
      }
    ]
  }
  ```
  Install addresses: `zs@zskills`, `zsbd@zskills`.

- [ ] **W1.3** — Create `hooks/hooks.json` for the `zs` plugin. Registers ALL hooks currently in `.claude/settings.json` — enumerate via the cited python one-liner at execution time, do NOT hardcode a count. (Re-derive: `python3 -c 'import json,os; d=json.load(open(".claude/settings.json")); s=set(); [s.add(os.path.basename(h["command"].split()[-1].strip(chr(34)))) for ev in d["hooks"] for m in d["hooks"][ev] for h in m["hooks"]]; print(sorted(s))` — was 10 distinct scripts as of 2026-05-26 across 11 command entries / 4 events: 6 PreToolUse-Bash [`block-unsafe-generic`, `block-unsafe-project`, `block-stale-skill-version`, `block-bypassed-land-pr`, `block-fix-issue-unclaimed`, `block-run-plan-unclaimed`], 1 Agent [`block-agents`], 1 CronCreate [`block-bad-cron`], 1 Edit|Write [`block-main-edits`], 2 PostToolUse [`warn-config-drift` on Edit + Write]. Of these 10, 8 ship from `hooks/` source; `block-agents.sh` and `block-unsafe-project.sh` are D4 `.template` siblings.) An implementer building `hooks.json` against a stale literal under-registers — the two claim hooks (`block-fix-issue-unclaimed`, `block-run-plan-unclaimed`) postdate the original "8" and MUST be included. `inject-bash-timeout.sh` and `verify-response-validate.sh` are NOT in this file (D11 — materialised). `block-agents.sh` and `block-unsafe-project.sh` point at sibling suffixless copies (D4). SessionStart hook is `session-start-materialise.sh` (W2.1). **CRITICAL — D16(a) shim wiring:** Every plugin-registered hook script gains a `# zskills-hook-version: <YYYY.MM.N>` comment AND a FIRST executable line that sources `${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh`. **Stamp placement (F-DA3-2):** the `# zskills-hook-version:` stamp is INSERTED as a new line 2 AHEAD of any existing descriptive line-2 comment; existing line-2 comments shift to line 3. (Every non-canary `.sh` hook today carries a `# <name>.sh — ...` descriptive line-2 comment — verified — so the stamp inserts, it does not replace.) **Stamp target set (F-R1-11):** the line-2 stamp lands on all non-canary `.sh` hooks in `hooks/` PLUS the 2 `.template` hooks (re-derive: `ls hooks/*.sh | grep -v canary` + `ls hooks/*.template` — was 9 non-canary `.sh` + 2 `.template` = 11 as of 2026-05-26; note the source tree has 11 `.sh` total but `inject-bash-timeout.sh` and `verify-response-validate.sh` are materialised-not-registered, and `canary3-bad.sh` is EXCLUDED per D9). The same line-2 version comment lands on the corresponding `.template` hook in the source tree (so `/update-zskills`-installed mirrors carry the version stamp too — without it, the shim's version-skew check sees ABSENT-vs-PRESENT and defers silently per D16(a) step 6). The `# zskills-hook-version:` comment is the SCRIPT-level version stamp (independent of skill-level `metadata.version`); `tests/test-skill-conformance.sh` gains an assertion that every shipped non-canary hook script in `hooks/` carries the line-2 comment.

- [ ] **W1.4** — Inside each hook script under `hooks/`, rewrite path references to lane-portable forms. THREE rewrite patterns:
  1. `$CLAUDE_PROJECT_DIR/.claude/hooks/` self-references and `$CLAUDE_PROJECT_DIR/scripts/` references → `${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}/.claude/skills/update-zskills}` per-site fallback (the analogue of the D6 skill-body two-line form, adapted for hook self-references). Today these live in `block-bypassed-land-pr.sh` and `block-stale-skill-version.sh` (`${CLAUDE_PROJECT_DIR:-$PWD}/scripts/...`); re-grep at execution time.
  2. **(F-DA1-7) Claim-hook deny-envelope recovery paths.** `block-run-plan-unclaimed.sh` and `block-fix-issue-unclaimed.sh` emit recovery commands citing `${MAIN_ROOT}/.claude/skills/run-plan/scripts/claim-plan.sh` (block-run-plan-unclaimed.sh:244) and `${MAIN_ROOT}/.claude/skills/fix-issues/scripts/claim-issue.sh` (block-fix-issue-unclaimed.sh:215) — verify line numbers at execution time. These are `/update-zskills`-lane-only paths; on a pure-plugin consumer (no `.claude/skills/` mirror) the recovery instruction names a non-existent file. Rewrite to the `${CLAUDE_PLUGIN_ROOT:-${MAIN_ROOT}/.claude/skills/<skill>}/scripts/claim-*.sh` dual-resolution form so the recovery command resolves on BOTH lanes. ALSO add the `${CLAUDE_PLUGIN_ROOT}` arm to the existing two-location `zskills-paths.sh` fallback in `block-run-plan-unclaimed.sh` (lines 212-214: it currently tries `.claude/skills/.../zskills-paths.sh` then `skills/.../zskills-paths.sh` — dogfood-only, not plugin-root). These claim hooks are explicitly NAMED in W1.3's stamp set — they postdate the plan draft, so naming removes doubt they are covered by the "every plugin-registered hook" rule. **NOTE this is a source-code fix the implementer makes** (the recovery-path resolution is real broken behavior under the plugin lane), surfaced here because W1.4 already opens these files.
  3. **(F-DA1-4 — source-code fix, surfaced here) Stale SKILL.md:NNN deny-envelope refs.** `block-fix-issue-unclaimed.sh:213` cites `SKILL.md:2161-2186 (cherry-pick/direct) or SKILL.md:2219-2243 (PR mode)` but #740's extraction shrank `skills/fix-issues/SKILL.md` to ~362 lines — those line refs now point past EOF (the dispatch fence moved into `references/` files). While editing this file for path-fallback, also fix the stale refs: point at the dispatch fence's new location (`references/<file>`) or drop the line numbers and name the fence by section heading. (Confirmed `block-run-plan-unclaimed.sh` has NO `SKILL.md:NNN` ref — this fix is fix-issue-only.)
  **CONSTRAINT:** rewrites MUST NOT touch the inlined `_lib` regions delimited by `# Inlined from hooks/_lib/...` comments. `tests/test-hook-helper-drift.sh` gates this.

- [ ] **W1.5** — `tests/test-plugin-manifest.sh` + `tests/test-plugin-marketplace.sh` (D8). The marketplace test covers BOTH plugin entries; the manifest test validates `plugin.json` schema against `/tmp/research-plugin-schema.md`.

- [ ] **W1.6** — `tests/test-plugin-self-load.sh` per D9 — covers both `zs` and `zsbd`. Same (a)/(b)/(c) structure as round 3, with the canary-bad exclusion.

- [ ] **W1.7** — Add `.claude-plugin/` to `.gitignore` allow-list.

- [ ] **W1.8** — Dev-loop transition. Update `RELEASING.md` and root `CLAUDE.md` to document BOTH lanes:
  - `claude --plugin-dir .` for plugin-lane dogfooding.
  - Source-tree `/update-zskills install` invocation pattern for legacy-lane dogfooding.
  The CI workflow (Phase 5 W5.7) runs both.

### Design & Constraints

- `${CLAUDE_PLUGIN_ROOT}` substitution documented per `/tmp/research-plugin-schema.md` §4.
- Plugin hooks.json does NOT merge into consumer's `.claude/settings.json` — they compose at the harness level per §13. **The conditional-skip shim (D16(a)) is the harmless-no-op defense against double-fire when both are registered.**
- Phase 1's no-skill-edit boundary satisfied — scripts STAY at `scripts/`; no in-skill source-path edits yet (those land in Phase 3 W3.1 per D6).
- `inject-bash-timeout.sh` AND `verify-response-validate.sh` are NOT registered as plugin-level hooks (D11). Both materialise into `$CLAUDE_PROJECT_DIR/.claude/hooks/` in Phase 2.
- `hooks/_lib/` ships verbatim in the plugin tree (D5). No path-rewrites inside `_lib/` source files. **New file `hooks/_lib/plugin-hook-skip-if-mirrored.sh` is added in Phase 1 W1.3.**

### Tests

- [ ] **NEW** `tests/test-plugin-manifest.sh`, `tests/test-plugin-marketplace.sh`, `tests/test-plugin-self-load.sh` (3 new in Phase 1).
- [ ] **EXISTING tests STAY GREEN.** Including all 9 `/update-zskills`-related tests that D8 retires in round 3 but RESTORES under dual-path.

### Acceptance Criteria

- [ ] All 3 new tests green.
- [ ] `bash tests/run-all.sh` green.
- [ ] `git diff --stat origin/main..HEAD` includes ONLY `.claude-plugin/`, `hooks/hooks.json`, `hooks/_lib/plugin-hook-skip-if-mirrored.sh`, `hooks/*.sh` (path-fallback edits), `tests/test-plugin-*.sh`, `RELEASING.md`, `CLAUDE.md`. NO skill body edits, NO `scripts/` moves, NO `hooks/_lib/` core-helper edits.

### Abort / Rollback

If `claude plugin validate --strict` rejects the `Agent` or `CronCreate` matcher — STOP. If the marketplace.json `zsbd` relative-path source (`./block-diagram`) is rejected by validation despite matching `/tmp/research-plugin-schema.md` §3's `Relative path` source type, fall back to `git-subdir` (`{ "url": "https://github.com/zeveck/zskills.git", "path": "block-diagram/", "ref": "prod/main" }`) — also documented in §3. Both are valid documented source types; if BOTH are rejected, restructure to publish `zsbd` from its own repo and re-evaluate D2. If the `dependencies: [{"name": "zs"}]` declaration on `zsbd` is rejected (the `/en/plugin-dependencies` page was research-deferred per `/tmp/research-plugin-schema.md` §15 line 574), document the orphan-install caveat in `docs/PLUGIN_INSTALL.md` and accept the failure mode as a known gap pending Anthropic doc-fetch.

### Dependencies

None.

---

## Phase 2 — SessionStart materialiser (5 artifacts) + dual-install detection + renderer equivalence

### Goal

Land the SessionStart materialiser. Five artifacts written to consumer `.claude/`. Dual-install detection probe (D27) runs BEFORE the overwrite-guard. `/update-zskills` Step D ported to call the same Python renderer (D24), eliminating two-renderer divergence.

### Work Items

- [ ] **W2.1 — SessionStart materialiser (`hooks/session-start-materialise.sh`).** Same 5-artifact write-set as round 3, but with the dual-install probe running FIRST (D27). Materialiser body (annotated for changes):
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  PROJ="$CLAUDE_PROJECT_DIR"
  PLUGIN="${CLAUDE_PLUGIN_ROOT}"
  CONFIG="$PROJ/.claude/zskills-config.json"
  PLUGIN_VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/.claude-plugin/plugin.json")"

  # D27 — Dual-install detection runs FIRST (before any write).
  . "$PLUGIN/hooks/_lib/detect-install-state.sh"
  LANE="$(detect_install_state "$PROJ")"
  case "$LANE" in
    fresh|plugin) ;;
    update-zskills)
      if [ ! -f "$PROJ/.zskills/dual-install-warned" ]; then
        mkdir -p "$PROJ/.zskills"
        echo "zskills: plugin loaded but install lane is /update-zskills. Run /update-zskills --switch-install-path=to-plugin to switch, or /plugin uninstall zs@zskills to remove the plugin." >&2
        touch "$PROJ/.zskills/dual-install-warned"
      fi
      exit 0  # Do NOT materialise — would clobber /update-zskills install state.
      ;;
    dual)
      if [ ! -f "$PROJ/.zskills/dual-install-warned" ]; then
        mkdir -p "$PROJ/.zskills"
        echo "zskills: dual install detected (/update-zskills AND plugin). Run bash scripts/switch-install-path.sh --to-plugin to consolidate." >&2
        touch "$PROJ/.zskills/dual-install-warned"
      fi
      # Conditional-skip shim handles double-fire on hooks; we still skip the materialiser here too.
      exit 0
      ;;
  esac

  # (round-3 materialise_static + safe_to_write + inject_sentinel logic unchanged; see round 3 body)
  # The 5 materialise_static calls + managed.md render call follow.
  # Sentinel format and frontmatter-aware injection per D20(a) — write-with-version, detect-by-prefix.
  ```

- [ ] **W2.2 — Python renderer + canonical substitution module (D24, F-DA2-2).** Land TWO files in the same commit:
  - `scripts/managed_rules_substitution.py` — the single source-of-truth substitution map (`build_substitutions(cfg)` returns the `subs` dict; `apply(template, subs)` returns the rendered text). Lifted verbatim from the `subs = {...}` Python dict block in `tests/test-managed-md-up-to-date.sh` (locate by `grep -n 'subs = {' tests/test-managed-md-up-to-date.sh` — was line 48 as of 2026-05-26 in a 117-line file; lift the dict literal by grep, NOT a fixed line range). It already encodes the correct 10-placeholder map; verified by grep.
  - `scripts/render-managed-rules.py` — thin wrapper: parses CLI flags (`--config`, `--template`, `--out`, `--sentinel`), imports `managed_rules_substitution`, writes the rendered file. Supports the `--sentinel` flag (injects the `^(#|<!--) zskills-materialised: ` prefix per D20(a)).

  `tests/test-managed-md-up-to-date.sh` is refactored (same commit OR W2.7's commit — see W2.7) to invoke `scripts/render-managed-rules.py` and diff its output against `.claude/rules/zskills/managed.md`. The existing inlined `subs = {...}` Python dict block (locate via `grep -n 'subs = {'`; was ~line 48 as of 2026-05-26) is DELETED — its content moves verbatim into `scripts/managed_rules_substitution.py`. This consolidates F-DA2-2's three-substitution-map concern: one map, three callers (renderer wrapper, materialiser, test).

- [ ] **W2.3 — Bundle template inside plugin tree at release time (revised — D3).** No `templates/CLAUDE_TEMPLATE.md` checked in. `scripts/build-plugin-release.sh` (W5.5) copies the repo-root `CLAUDE_TEMPLATE.md` to `${CLAUDE_PLUGIN_ROOT}/CLAUDE_TEMPLATE.md` during prod-strip. The materialiser reads from `$CLAUDE_PROJECT_DIR/CLAUDE_TEMPLATE.md` first (so consumers running zskills inside the zskills repo dogfood the live template) and falls back to `${CLAUDE_PLUGIN_ROOT}/CLAUDE_TEMPLATE.md` for installed-plugin consumers.

- [ ] **W2.4 — Strip `.template` suffixes from plugin-tree hooks (D4 revision).** In the plugin tree only: `build-plugin-release.sh` generates sibling suffixless copies of `block-agents.sh.template` and `block-unsafe-project.sh.template`. Source-tree files keep the `.template` suffix (the `/update-zskills` lane depends on it). `tests/test-hook-template-sibling.sh` asserts byte-equality between the suffixed and suffixless copies when both exist.

- [ ] **W2.5 — Plugin hook self-references.** Same as round 3.

- [ ] **W2.6 — Update zskills' own root `CLAUDE.md`.** Document the dual-path dogfood loop.

- [ ] **W2.7 — Port `/update-zskills` Step B §2 + Step D §2 to call `render-managed-rules.py` AND add the equivalence gate (D24, F-DA1-5, F-R2-4, F-DA2-2, F-DA2-5).** Single commit, ordering:
  1. Edit `skills/update-zskills/SKILL.md` to replace the inline LLM-prose substitution language in TWO sub-steps — locate by SECTION ANCHOR, not line number (the file is ~1930 lines as of 2026-05-26 and #738/#740/#737/#736/#750 refactors moved content; hardcoded line numbers WILL rot): **(a) Step B's substitution sub-step** — under the `#### Step B — Render zskills-managed rules file` heading, the numbered step `2. **Substitute placeholders** in $PORTABLE/CLAUDE_TEMPLATE.md ...` (grep `grep -n 'Substitute placeholders' skills/update-zskills/SKILL.md`); **(b) Step D's substitution sub-step** — locate the `### Step D — --rerender` heading via `grep -n '### Step D — --rerender' skills/update-zskills/SKILL.md`, then the `2. Render the template against current config` step immediately below it (the trailing phrase "same substitution logic as Step B step 2" is line-wrapped in source, so anchor on the unique heading + the `Render the template against current config` line — NOT the wrapped phrase, which no single-line grep will match). Replace both with: `Run python3 "$PORTABLE/scripts/render-managed-rules.py" --config .claude/zskills-config.json --template "$PORTABLE/CLAUDE_TEMPLATE.md" --out .claude/rules/zskills/managed.md`. No "deprecated" markers, no retained legacy prose — the substitution sub-steps are REPLACED. The rest of Step B (config-scan, root-CLAUDE.md migration, install report) is unchanged.
  2. Refactor `tests/test-managed-md-up-to-date.sh` to invoke `scripts/render-managed-rules.py` and diff its output against the checked-in `managed.md`. Delete the inlined `subs = {...}` Python block.
  3. Add `tests/test-managed-md-renderer-equivalence.sh` to `bash tests/run-all.sh`. The test runs `render-managed-rules.py` against 5 fixture `(config, template)` pairs and asserts byte-equal output between invocations originating from "Step D wrapper" and "plugin materialiser" code paths (both internally route through `managed_rules_substitution.py`, so equivalence is structural — the test catches refactor regressions).
  4. Bump `skills/update-zskills/SKILL.md` `metadata.version` per skill-versioning enforcement.

- [ ] **W2.8 — Add `hooks/_lib/detect-install-state.sh` (D27).** Function `detect_install_state()` returns one of `fresh`/`plugin`/`update-zskills`/`dual` per the D27 spec. Sourced by `session-start-materialise.sh` (W2.1) and by `scripts/switch-install-path.sh` (W5.6).

### Design & Constraints

- **5 materialised artifacts (unchanged from round 3).**
- **Overwrite guard + dual-install probe.** The probe runs FIRST. The overwrite-guard's "treat unsentinelled files as consumer-authored" semantic is now augmented: in `lane=update-zskills`, the materialiser exits BEFORE the overwrite-guard ever fires, so `/update-zskills`-installed files are never seen as "consumer-authored to skip" — they're seen as "lane mismatch, don't touch."
- **`verify-response-validate.sh` lives in TWO places by design.** Same as round 3.
- **No `alwaysLoad` field.** Same as round 3.
- **Atomic-rename + mtime + sentinel idempotency.** Same as round 3.
- **One canonical renderer (D24).** Step D calls Python; W2.7 ports the language; W4.4 verifies equivalence.

### Tests

- [ ] **NEW** `tests/test-sessionstart-materialise.sh` — fixture project; 9 assertions per round 3 (5 destinations written, exec bits, substitution tokens, mtime touch behaviour, frontmatter survival, cross-version upgrade).
- [ ] **NEW** `tests/test-sessionstart-materialise-overwrite-guard.sh` — round-3 spec carried forward.
- [ ] **NEW** `tests/test-sessionstart-dual-install-detect.sh` — exercises all 4 lane states (`fresh`/`plugin`/`update-zskills`/`dual`); asserts the materialiser behaviour for each per D27. The `dual` and `update-zskills` cases assert the WARN text and the `dual-install-warned` marker creation.
- [ ] **NEW** `tests/test-render-managed-rules-correctness.sh` — golden-output fixture; round-3 spec.
- [ ] **NEW** `tests/test-managed-md-renderer-equivalence.sh` (D24) — runs `/update-zskills` Step D's render path (via the Python wrapper W2.7 introduces) AND the plugin SessionStart materialiser's render path against 5 fixture `(config, template)` pairs; asserts byte-equal output for each. **This is the F-DA1-5 gate.**
- [ ] **NEW** `tests/test-inject-bash-timeout-parity.sh` + `tests/test-verify-response-validate-parity.sh` — round-3 spec.
- [ ] **STAY GREEN** `tests/test-update-zskills-rerender.sh`, `tests/test-managed-md-up-to-date.sh` (D8 — STAY under dual-path; both must pass AFTER W2.7 ports Step D to Python).

### Acceptance Criteria

- [ ] All 6 new tests green.
- [ ] `bash tests/run-all.sh` green.
- [ ] 5 materialised artifacts present in a fresh fixture project.
- [ ] Dual-install detection emits the documented WARN strings and skips materialisation in `update-zskills`/`dual` lane states.
- [ ] `/update-zskills` Step D dogfood: run `/update-zskills --rerender` in the source tree, verify `managed.md` mtime advances AND `tests/test-managed-md-renderer-equivalence.sh` passes against the just-rendered output.

### Abort / Rollback

If any of the 5 write contracts fail, OR if the dual-install probe misclassifies a fixture state, do NOT ship Phase 2. Rollback: `git reset --hard origin/main`.

### Dependencies

Phase 1.

---

## Phase 3 — Dual-path recognition + cron-fire path-aware rules + script-path fallback (all resolver-sourcing sites) + `migrate-crons` skill

### Goal

Apply the per-site dual-path fallback in EVERY site that sources `zskills-resolve-config.sh` (D6 — re-derive the count; was 151 as of 2026-05-26). Rewrite the cron-fire recognition rule to OR-match both prefix forms permanently (D12) AND to resolve SKILL.md paths under both layouts (D12-prose). Ship the new optional `migrate-crons` skill (D13). This is NOT a small phase — it's the largest mechanical-edit phase in the plan. The earlier narrative that "Phase 3 narrows" was wrong; under dual-path the bulk-rewrite work doesn't vanish, it shifts from 1,621 prose refs to the full set of script-source refs.

### Work Items

- [ ] **W3.1 — Per-site dual-path fallback for `zskills-resolve-config.sh` sourcing (D6).** Re-derive the site count at execution time — do NOT pin a frozen integer (`grep -rho 'zskills-resolve-config.sh' skills/ block-diagram/ | wc -l` was 151 sites across 44 files as of 2026-05-26). Mechanical sed edit applied via a deterministic Python script (so the diff is reviewable). The script replaces:
  ```bash
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  ```
  with the two-line dual-path form from D6. Edits also apply to EVERY site referencing `.claude/skills/update-zskills/scripts/<other-script>` for `sanitize-pipeline-id.sh`, `port.sh`, `clear-tracking.sh`, `statusline.sh`, `plan-drift-correct.sh` (re-derive: `grep -rho '\.claude/skills/update-zskills/scripts/' skills/ block-diagram/ | wc -l` was 228 as of 2026-05-26) — same two-line existence-test pattern. The acceptance gate is "every grep-matched site rewritten," verified by a post-edit re-grep showing zero un-wrapped legacy-only sources — NOT a hardcoded count match.

- [ ] **W3.2 — Update `references/canonical-config-prelude.md`** to document the new two-line form as the PREFERRED pattern for new code (lane-portable). Per F-DA2-4, the legacy one-liner is NOT marked DEPRECATED and carries NO deadline — under D23's permanent dual-path commitment, the legacy one-liner remains valid forever on the `/update-zskills` lane and the deadline-warn would contradict that commitment. `tests/test-skill-conformance.sh`'s per-fence sourcing-discipline check accepts BOTH forms permanently (the legacy form is a documentation-class advisory; new code should prefer the dual-path two-line form; no test-suite enforcement of migration).

- [ ] **W3.3 — Cron-fire recognition-rule rewrite (D12 + D12-prose).** Edit `CLAUDE_TEMPLATE.md ## Cron-fired prompts` to:
  ```
  **Treat any user-shaped turn whose entire content starts with `Run /<skill-name> `
  OR `Run /zs:<skill-name> ` as a cron fire.** Both prefixes are recognized PERMANENTLY —
  the bare prefix is the form on the `/update-zskills` install lane; `zs:` is the form
  on the plugin install lane. Read `${CLAUDE_PLUGIN_ROOT}/skills/<skill-name>/SKILL.md`
  (plugin install) OR `.claude/skills/<skill-name>/SKILL.md` (legacy install) via the
  Read tool — try the plugin path first if `${CLAUDE_PLUGIN_ROOT}` is set, otherwise
  the legacy path — and execute its procedure inline with `$ARGUMENTS` set to the
  substring after the prefix.
  ```
  Edit `CLAUDE_TEMPLATE.md` ONLY (no `templates/CLAUDE_TEMPLATE.md` copy per D3).

- [ ] **W3.4 — Ship new `skills/migrate-crons/SKILL.md` (D13 — OPTIONAL convenience).** Body documents that the skill is OPTIONAL under dual-path's permanent OR-match. Same `CronList`/`CronDelete`/`CronCreate` mechanism as round 3. Frontmatter: `name: migrate-crons`, `user-invocable: true`, `disable-model-invocation: false`, `argument-hint: "[apply]"`, `metadata.version: "<today>+<hash>"`. The skill ships in `skills/`, bringing the `skills/` count to 26 (re-derive: `ls -d skills/*/ | wc -l` was 25 as of 2026-05-26, so this skill makes it 26).

- [ ] **W3.5 — Test-suite assertion updates.** `tests/test-skill-conformance.sh` learns the new two-line dual-path form per D6. The per-fence sourcing-discipline check accepts EITHER the legacy one-liner OR the new dual-path form during the transition window. NO bulk grep-rewrite of `tests/test-*.sh` files — the source-tree slash references stay bare per pivot point 4.

- [ ] **W3.6 — Skill-frontmatter survival assertion (F-DA2-6 STOP gate carried forward).** Same as round 3.

- [ ] **W3.7 — Version bump for the touched skill DIRS (D22 atomicity discipline carried forward).** Bump `metadata.version` on EXACTLY the skill dirs W3.1 edited — enumerate via `git diff --name-only` scoped to `skills/*/SKILL.md` + `block-diagram/*/SKILL.md` AFTER the W3.1 edit lands; do NOT assert a fixed count. (Re-derivation predicts the resolver-sourcing skill-dir set was 22 as of 2026-05-26, possibly 23 with `migrate-crons` — but the git-diff scope is the source of truth, since W3.1 may also touch dirs that reference the legacy `scripts/` path without sourcing the resolver.) Loop discipline per round 3 D22.

### Design & Constraints

- **Bare-slash prose in skill bodies is NOT rewritten** — pivot point 4. Plugin-lane consumers see bare slashes in prose; acceptable per Risk Register gap (8) and `docs/PLUGIN_INSTALL.md` "Known tradeoffs."
- **Cron-fire OR-match is PERMANENT (D12).** `tests/test-cron-prefix-or-match.sh` asserts NO sunset date in the recognition rule.
- **Cron-fire SKILL.md path is DUAL (D12-prose, F-DA1-2).** `tests/test-cron-fire-rule-dual-path.sh` asserts both `${CLAUDE_PLUGIN_ROOT}/skills/...` and `.claude/skills/...` appear in the rendered `managed.md`.
- **Migrate-crons skill is OPTIONAL (D13).** Documented as such.
- **Per-site fallback (D6) is mechanical, but the LLM-readability hit is real.** A two-line existence test is uglier than a one-line source. Accepted cost.

### Tests

- [ ] **NEW** `tests/test-cron-prefix-or-match.sh` (Phase 3) — asserts both `Run /<skill-name>` and `Run /zs:<skill-name>` recognition patterns in `managed.md`; asserts NO sunset date strings.
- [ ] **NEW** `tests/test-cron-fire-rule-dual-path.sh` (Phase 3 — F-DA1-2) — asserts both SKILL.md path forms appear in the rendered cron-fire-rule section.
- [ ] **NEW** `tests/test-skill-frontmatter-survival.sh` (Phase 3 — F-DA2-6 STOP gate).
- [ ] `bash tests/test-skill-conformance.sh` — green; per-fence sourcing-discipline check accepts both legacy and dual-path forms.
- [ ] `bash tests/run-all.sh` — green.

### Acceptance Criteria

- [ ] All 3 new Phase-3 tests green.
- [ ] `bash tests/run-all.sh` green.
- [ ] Every skill DIR touched by W3.1 has its `metadata.version` bumped, committed atomically — verified by `git diff --name-only` scope, NOT a frozen count (was ~22 dirs as of 2026-05-26).
- [ ] `skills/migrate-crons/SKILL.md` exists with the OPTIONAL framing.
- [ ] `tests/test-skill-frontmatter-survival.sh` GREEN (or Phase 3 STOPS per F-DA2-6).
- [ ] Cron-fire rule prose contains both prefix forms AND both SKILL.md path forms.
- [ ] PR body documents the re-derived site count touched (was 151) and the re-derived skill-dir count version-bumped (was ~22) — execution-time numbers, not the parentheticals.

### Abort / Rollback

Same as round 3 STOP conditions. If `test-skill-frontmatter-survival.sh` fails — STOP. If `test-cron-fire-rule-dual-path.sh` fails after rewrite — STOP and review the regex. Two attempts max.

### Dependencies

Phase 2.

---

## Phase 4 — Conformance test surface (0 retirements; 16 new stabilise; 2 restructured)

### Goal

Stabilise the 16 new tests added in Phases 1-3 and 5. Restructure 2 existing tests (3 files) per D8. NO retirements. `test-hook-helper-drift.sh` STAYS.

### Work Items

- [ ] **W4.1 — Retire 0 tests.** Under dual-path, every test in the round-3 "9 retired" list STAYS. Confirm by running them all green AFTER Phase 3.

- [ ] **W4.2 — Restructure `tests/test-skill-conformance.sh`.** Per D6, teach the per-fence sourcing-discipline check the new two-line dual-path form. Cross-test materialiser-presence check at top.

- [ ] **W4.3 — Restructure `tests/test-block-stale-skill-version*.sh`.** Same as round 2.

- [ ] **W4.4 — Stabilise the 16 new tests.** Run 5 consecutive iterations of `bash tests/run-all.sh`; root-cause any flake. Test inventory (matches D8 enumeration; F-R2-5):
  1. `tests/test-plugin-manifest.sh` (Phase 1)
  2. `tests/test-plugin-marketplace.sh` (Phase 1)
  3. `tests/test-plugin-self-load.sh` (Phase 1)
  4. `tests/test-sessionstart-materialise.sh` (Phase 2)
  5. `tests/test-sessionstart-materialise-overwrite-guard.sh` (Phase 2)
  6. `tests/test-sessionstart-dual-install-detect.sh` (Phase 2 — D27)
  7. `tests/test-render-managed-rules-correctness.sh` (Phase 2)
  8. `tests/test-managed-md-renderer-equivalence.sh` (Phase 2 — D24)
  9. `tests/test-inject-bash-timeout-parity.sh` (Phase 2)
  10. `tests/test-verify-response-validate-parity.sh` (Phase 2)
  11. `tests/test-cron-fire-rule-dual-path.sh` (Phase 3 — F-DA1-2)
  12. `tests/test-cron-prefix-or-match.sh` (Phase 3 — D12)
  13. `tests/test-skill-frontmatter-survival.sh` (Phase 3)
  14. `tests/test-hook-template-sibling.sh` (Phase 2 — D4)

  Plus 2 more added in Phase 5:
  15. `tests/test-switch-install-path.sh` (Phase 5 — D25)
  16. `tests/test-plugin-hook-skip-on-double-register.sh` (Phase 5 — D16(a))

- [ ] **W4.5 — Test-runner accounting.** PR body documents the actual count: `0 retired + 16 new + 3 restructured-in-place = +16 net new test files`. (Higher than round 3's "+3" — see Drift Log.)

- [ ] **W4.6 — `tests/fixtures/forbidden-literals.txt` audit.** Same as round 2.

### Design & Constraints

- No retirements.
- CI must stay green throughout.
- `tests/test-hook-helper-drift.sh` STAYS (D5).
- The 9 `/update-zskills`-related tests STAY.

### Tests

- [ ] `bash tests/run-all.sh` green.
- [ ] All 16 new tests green.
- [ ] All 9 `/update-zskills` tests STAY green.
- [ ] 5 consecutive iterations green.

### Acceptance Criteria

- [ ] 0 retirements committed.
- [ ] All 16 new plugin/dual-path tests are part of `bash tests/run-all.sh`.
- [ ] PR body documents the suite-count delta (`+16 net new`).

### Abort / Rollback

If any flake cannot be root-caused in 2 attempts, STOP per CLAUDE.md "NEVER thrash."

### Dependencies

Phases 1, 2, 3.

---

## Phase 5 — Dual-path hardening: plugin-mode CI, bidirectional `--switch-install-path`, hook double-fire prevention, `build-plugin-release.sh`

### Goal

Ship the dual-path-only runtime infrastructure. Plugin-mode CI lane (in addition to existing source-tree CI). Bidirectional `scripts/switch-install-path.sh` (D25). Plugin hooks.json conditional-skip shim acceptance tests (D16(a)). `build-plugin-release.sh` with self-deletion fix + parallel `prod/<version>` tag (round-3 spec carried forward). **Phase 5 does NOT retire anything** — round 3's W5.4 deletion list is removed entirely per F-R1-6.

### Work Items

- [ ] **W5.1 — Plugin-mode CI lane.** Add a GitHub Actions job that:
  - Tier 1 (cheap, mandatory): Python JSON-schema validation of both `plugin.json` files and `marketplace.json` — already covered by `test-plugin-manifest.sh` / `test-plugin-marketplace.sh`. Runs on every PR.
  - Tier 2 (moderate cost, best-effort): if a `claude` CLI binary URL is documented and reachable, install it on the runner and run `claude plugin validate --strict .`. Asserts exit 0. SKIP-with-reason if the CLI install fails (e.g., binary URL changes upstream).
  - Tier 3 (expensive, deferred): actual `claude -p '/zs:briefing summary'` dispatch. NOT in this plan. Tracked as a follow-up issue.

  Per F-DA1-6, "cheap" was misleading; the spec now documents the three tiers explicitly.

- [ ] **W5.2 — Cut a release tag.** Bump `plugin.json.version` in BOTH `zs` and `zsbd` manifests in lockstep (D10). Tag the dev commit `YYYY.MM.N`. Run `scripts/build-plugin-release.sh` (W5.5) to produce the prod-stripped commit + parallel tag.

- [ ] **W5.3 — `/update-zskills --switch-install-path={to-plugin,to-update-zskills}` mode (D15).** Edit `skills/update-zskills/SKILL.md` to add the new sub-mode that delegates to `scripts/switch-install-path.sh`. Documented as the supported lane-switch entry point.

- [ ] **W5.4 — RETIRED.** Round-3 W5.4 deleted the legacy installer surface. Under dual-path NOTHING is deleted (D8 zero retirements). W5.4 is intentionally empty as a tombstone.

- [ ] **W5.5 — `scripts/build-plugin-release.sh` (round-3 spec carried forward + D3 + D4 additions).** Same round-3 contract:
  - `set -euo pipefail`, `trap` cleanup, dirty-tree precheck, no self-deletion (via the `find ... -name 'build-*.sh' -delete` + POSIX bash-fully-loaded semantics), version-bump before `git branch -f prod/main HEAD`, parallel `prod/<version>` tag push, canary-strip including `hooks/canary*-bad.sh`.
  - **New additions for dual-path:**
    - **D3:** copy `CLAUDE_TEMPLATE.md` from repo root to `${PLUGIN_TREE}/CLAUDE_TEMPLATE.md` (the fallback path for installed-plugin consumers).
    - **D4:** generate suffixless sibling copies of `block-agents.sh.template` and `block-unsafe-project.sh.template` in the plugin tree.
  - Verification: `git ls-tree -r prod/main | grep -E 'CANARY|RELEASING|dev_only|build-.*\.sh|MW-EXAMPLE'` returns 0 hits.

- [ ] **W5.6 — `scripts/switch-install-path.sh` (D25 bidirectional).** Implements both `--to-plugin` and `--to-update-zskills` modes per D25 with lock-LAST in both directions. Companion Python helper `scripts/migrate-strip-settings.py` (same shape as round-3 round-2). **Lock file shape (F-R2-6):** path `.claude/zskills-install-lane`, single-line bare content (`plugin\n` or `update-zskills\n`), written atomically via tmpfile+rename as the FINAL step of each mode. `--switch-install-path.sh` also reads any pre-existing lock at START to detect prior lane and validate the requested transition (e.g., `--to-plugin` on an already-`plugin` lane is a no-op-with-INFO; `--to-update-zskills` on a lock-free `lane=fresh` repo is a re-confirmation prompt).

- [ ] **W5.7 — `hooks/_lib/plugin-hook-skip-if-mirrored.sh` testbed (D16(a)).** The shim itself lands in Phase 1 W1.3; W5.7 adds the acceptance test `tests/test-plugin-hook-skip-on-double-register.sh` that simulates a settings.json + plugin hooks.json dual-registration and asserts the plugin's hook exits 0 immediately without doing the real work. Test fixture pre-populates settings.json with a known zskills hook entry.

- [ ] **W5.8 — Update `RELEASING.md`.** Document the dual-path release flow: bump BOTH `plugin.json.version` files, run `build-plugin-release.sh`, push BOTH `prod/main` AND `prod/<version>` tags, communicate updates to BOTH lanes' consumers.

- [ ] **W5.9 — Update zskills' own root `CLAUDE.md`.** Document dual-path dogfooding final form.

- [ ] **W5.10 — Issue closeout.** PR body uses `Closes #N` per inventoried open issue.

### Design & Constraints

- **NO file deletions.** Round-3 W5.4 list is removed entirely (F-R1-6). `CLAUDE_TEMPLATE.md` STAYS. `skills/update-zskills/` STAYS. Mirror trees STAY.
- **`build-plugin-release.sh`** runs at release time on the dev commit; produces a prod-stripped sibling commit on `prod/main`. Does NOT modify the dev commit.
- **Lock-LAST in BOTH directions.** Per D25; per CLAUDE.md `## Migration scripts`.
- **Plugin-mode CI tiering** explicitly documented (F-DA1-6).
- **Hook double-fire is structurally prevented** by the conditional-skip shim (D16(a)) and observable via the dual-install WARN (D16(b) / D27).

### Tests

- [ ] **NEW** `tests/test-switch-install-path.sh` — exercises both `--to-plugin` and `--to-update-zskills` modes on fixture projects; asserts post-switch slash invocation works on the target lane.
- [ ] **NEW** `tests/test-plugin-hook-skip-on-double-register.sh` — round-2 fixture; asserts the conditional-skip shim works.
- [ ] `bash tests/run-all.sh` green.
- [ ] `bash scripts/build-plugin-release.sh` (dry-run) produces a clean `prod/main` + `prod/<version>` ref.

### Acceptance Criteria

- [ ] Plugin-mode CI lane runs on every PR (Tier 1 mandatory; Tier 2 best-effort).
- [ ] `scripts/switch-install-path.sh` ships both modes; both pass `tests/test-switch-install-path.sh`.
- [ ] Hook conditional-skip shim ships; `tests/test-plugin-hook-skip-on-double-register.sh` green.
- [ ] `bash scripts/build-plugin-release.sh` produces both `prod/main` and `prod/<version>` refs with the documented strip set.
- [ ] PR body includes `Closes #N` for every inventoried issue.

### Abort / Rollback

If `bash tests/run-all.sh` red after Phase 5 additions, STOP. If `switch-install-path.sh` fixture test fails in either direction, STOP and refine. If the plugin-mode CI tier-2 lane is chronically flaky (>50% of runs SKIP for non-`claude`-CLI reasons), keep tier-1 as the gating floor and document the tier-2 limitation.

### Dependencies

Phases 1-4.

---

## Phase 6 — Marketplace activation, prod-tag release flow, README + dual-path docs

### Goal

Activate the marketplace path. Document the dual-path install model (D26). Document the dual-ref pin scheme. Finalise issue closeout.

### Work Items

- [ ] **W6.1 — Consumer-onboarding documentation (`docs/PLUGIN_INSTALL.md`).** Documents BOTH paths under a side-by-side comparison. Includes:
  - Install commands for both lanes.
  - Slash-prefix expectations per lane.
  - Update workflow per lane.
  - The default recommendation (D26).
  - Pin-by-version idiom (D1).
  - `.gitignore` guidance scoped per-lane (D20(b), F-R1-16).
  - **"Known tradeoffs" section (Risk Register gap 8):** documents the bare-slash prose UX gap for plugin-lane consumers — skill-body prose references unprefixed slash names; cross-skill dispatch via Skill tool works; cron-fire OR-match handles auto-fire; only typed-slash invocations require the user to mentally swap `/foo` → `/zs:foo`.

- [ ] **W6.2 — Dual-path migration runbook (`docs/PLUGIN_MIGRATION.md`).** Documents the bidirectional `--switch-install-path` tool (D25). Renamed from round-3's one-way framing ("migrating away from `/update-zskills`") to "switching install paths (optional)." Covers Abort/Rollback for both directions.

- [ ] **W6.3 — Marketplace promotion (optional).** Same as round 2.

- [ ] **W6.4 — Issue #432 closeout.** Same as round 2.

- [ ] **W6.5 — `MW-EXAMPLE__settings.json` cleanup — ALREADY SATISFIED (no-op tombstone, F-R1-13).** The file does not exist anywhere in the tree as of 2026-05-26 (`find . -name 'MW-EXAMPLE*' -not -path './.git/*'` → empty). No deletion to perform. The Phase 6 "absent" test and the W5.5 strip-regex `MW-EXAMPLE` guard STAY as harmless regression guards.

- [ ] **W6.6 — README.md updates.** Document both install paths at top-level. Point at `docs/PLUGIN_INSTALL.md` for the full comparison. Default recommendation per D26.

### Tests

- [ ] `docs/PLUGIN_INSTALL.md` and `docs/PLUGIN_MIGRATION.md` exist.
- [ ] `MW-EXAMPLE__settings.json` absent.
- [ ] README references both install paths.

### Acceptance Criteria

- [ ] Both docs exist and document the dual-path model.
- [ ] README links to both lanes.
- [ ] All inventoried open issues closed.

### Abort / Rollback

If README's default recommendation generates community pushback, the recommendation is editorial and can be retracted in a follow-up commit without affecting the plan's structural acceptance criteria.

### Dependencies

Phases 1-5.

---

## Drift Log

This plan was originally drafted (rounds 1-3) as a one-way replacement of `/update-zskills` with the plugin distribution system. Round-3 convergence locked: `/update-zskills` deleted in Phase 5, `CLAUDE_TEMPLATE.md` deleted, `.claude/skills/` and `.claude/hooks/` mirror trees retired, 1,621 bare-slash prose references bulk-rewritten to `/zskills:<skill>` (Phase 3 with a 29-skill version-bump cascade), 9 conformance tests retired. Round 4 received a user pivot: keep BOTH install paths permanently as first-class options.

Key directional changes round-3 → round-4:

1. **Slash prefix renamed `zskills:` → `zs:`.** Mass rename across the plan body (verified: 20 sites in round-3 plan). Plugin name in `plugin.json` is `zs`; marketplace name stays `zskills`. F-R1-1.
2. **`/update-zskills` STAYS forever.** D15 retired the "skill deleted in Phase 5" claim. A6 acceptance criterion retired. F-R1-7.
3. **`CLAUDE_TEMPLATE.md` STAYS forever** as the dual-path source-of-truth. D3 simplified: no `templates/` mirror, no byte-equality gate; the plugin reads the repo-root template directly during dev, fallback-bundled at release time. F-R1-9.
4. **No bulk slash-prefix rewrite.** Phase 3 W3.2 (the 1,621-hit prose rewrite) deleted. F-R1-2. Bare slashes in skill-body prose stay; documented as a plugin-lane UX rough edge in `docs/PLUGIN_INSTALL.md`. F-DA1-1 Option Y locked.
5. **No 29-skill version-bump cascade for slash-prefix.** F-R1-13. But the per-site path-fallback work (D6) introduces a **version-bump cascade across the resolver-sourcing skill DIRS for `zskills-resolve-config.sh` sourcing** (re-derive at execution time; was ~22 dirs as of 2026-05-26 — see D22) — net version-bump count comparable to round 3, just for different reasons. F-DA1-3, F-R1-5.
6. **0 conformance test retirements.** Round-3's "9 retired" list was specific to deleting the legacy installer surface; under dual-path every one of those tests gates a still-living invariant. F-R1-4.
7. **NEW: dual-install detection probe (D27).** Round-3 had no spec for the case where a consumer has both lanes simultaneously. Round-4 adds `hooks/_lib/detect-install-state.sh` returning `fresh`/`plugin`/`update-zskills`/`dual`, runs FIRST in the materialiser (before the overwrite-guard), emits per-state WARN. F-R1-10, F-R1-12, F-DA1-4.
8. **NEW: bidirectional `scripts/switch-install-path.sh` (D25).** Replaces round-3's one-way `migrate-to-plugin.sh`. Both `--to-plugin` and `--to-update-zskills` modes; lock-LAST in BOTH directions. F-R1-8, F-DA1-7.
9. **NEW: plugin hooks.json conditional-skip shim (D16(a)).** `hooks/_lib/plugin-hook-skip-if-mirrored.sh` sourced at the top of every plugin-registered hook; exits 0 if the same hook is registered in settings.json for the same matcher. F-DA1-4.
10. **NEW: renderer-equivalence test (D24).** `/update-zskills` Step D ported to call `scripts/render-managed-rules.py` (the same Python renderer the plugin uses); `tests/test-managed-md-renderer-equivalence.sh` is the belt-and-suspenders gate. F-DA1-5.
11. **NEW: cron-fire rule SKILL.md path is dual-path (D12-prose).** The rule literal teaches Claude to try `${CLAUDE_PLUGIN_ROOT}/skills/<skill-name>/SKILL.md` AND `.claude/skills/<skill-name>/SKILL.md`. F-DA1-2.
12. **Permanent cron OR-match (D12).** No 2026-07-21 sunset. F-R1-3, F-DA1-10.
13. **Two plugins under one marketplace (D2 revised).** `zs` (full) and `zsbd` (addon subset). D17 retired. F-R1-14, F-R1-17, F-DA1-8.
14. **Default install path recommendation (D26).** README recommends the plugin lane for interactive workflows, `/update-zskills` for headless CI. F-DA1-11.

**Honest scope summary.** The dual-path pivot was framed as "Phase 3 narrows, Phase 5 narrows" — that was misleading. The TOTAL work is roughly equivalent to single-path-with-cutover:

- **Work that disappears:** Phase 3's 1,621-prose-ref rewrite (Phase 3 W3.2 deletion), Phase 5's `/update-zskills` retirement + mirror-tree deletion + `CLAUDE_TEMPLATE.md` deletion (Phase 5 W5.4 entire block removed).
- **Work that appears:** per-site dual-path script-source fallback across every resolver-sourcing site (D6, Phase 3 W3.1; was ~151 sites as of 2026-05-26 — re-derive), dual-install detection probe (D27, Phase 2 W2.8), bidirectional `--switch-install-path` (D25, Phase 5 W5.6), hook double-fire conditional-skip shim (D16(a), Phase 1 W1.3 + Phase 5 W5.7), renderer-equivalence collapse + gate (D24, Phase 2 W2.7 + tests), cron-fire rule prose dual-path (D12-prose, Phase 3 W3.3), plugin-mode CI tiered (F-DA1-6, Phase 5 W5.1), second plugin manifest for `zsbd` (D2, Phase 1 W1.1/W1.2), default-path README guidance (D26, Phase 6 W6.6).

Net delta on test files: round 3 was `-9 retired + 12 new = +3 net`. Round 4 is `0 retired + 16 new = +16 net`. The conformance suite GROWS more under dual-path than under single-path-with-cutover, because every retired-under-single-path invariant STAYS PLUS the new dual-path-specific invariants are added.

The plan body now reflects this honestly. The benefit consumers receive: two long-term-supported install experiences. That's the actual tradeoff.

### Round-3 refinement (F-R2-1 through F-R2-6, F-DA2-1 through F-DA2-5)

Round-2 review surfaced 11 findings (1 critical, 6 major, 4 minor). Convergence trajectory: 30 → 11. All 11 closed in round-3 refinement:

- **F-R2-1 (critical) — marketplace `github.path` field is not in the documented schema.** Re-anchored to `/tmp/research-plugin-schema.md` §3 lines 152-158. Switched `zsbd`'s marketplace entry to `source: "./block-diagram"` (relative-path string per §3, the research-recommended alternative at line 173). D1 rewritten with the schema citation. W1.2 marketplace.json example updated. Abort/Rollback re-anchored: if relative-path source is rejected, fall back to `git-subdir` (also documented per §3); both rejected → republish from a separate repo. Risk Register gap (3) text updated to name all three Phase-1 validation risks together.
- **F-R2-2 (major) — D16(a) "same hook by name" was unimplementable.** Hook entries are anonymous `{type, command}` records per `/tmp/research-plugin-schema.md` §5. D16(a) rewritten with a concrete 7-step mechanism: shim sources at the top of every plugin hook, computes its own basename via `BASH_SOURCE[1]`, reads `.claude/settings.json` via Python, iterates entries, basename-matches via `os.path.basename(command.split()[-1])`, and (per F-DA2-3) version-compares via line-2 `# zskills-hook-version:` header. Multiple deferment outcomes documented: equal/older → silent skip; newer-on-plugin → WARN+defer with marker; no match → continue. W1.3 specifies the line-2 version comment as a new convention added in Phase 1 and gated by a new `tests/test-skill-conformance.sh` assertion.
- **F-R2-3 (major) — D27 partial-cleanup case missing.** D27 rewritten with explicit "ANY hit counts" detection rules: per-lane evidence lists (lock-file content, KNOWN_SKILLS / KNOWN_HOOKS presence, sentinel-absent agents/managed.md, settings.json hook entries with matching basename); lane resolution rule (zero+zero=fresh, plugin-only=plugin, update-zskills-only=update-zskills, both=dual); explicit partial-state safety paragraph showing orphan-hook-without-SKILL.md classifies as `update-zskills` and triggers materialiser early-exit. Test fixture grows to a fifth case exercising the partial-cleanup scenario. Materialiser refuses to write under BOTH `dual` and `update-zskills`.
- **F-R2-4 + F-DA2-5 (major + minor) — D24 Step B retirement deferred without tracking.** Picked Option (a) from F-R2-4: Step B §2 and Step D §2 LLM-prose are DELETED outright in W2.7's single commit, replaced with a `python3 render-managed-rules.py ...` invocation. No deprecation window, no follow-up issue, no "retain for one release" language. Rationale documented in D24: under D23's permanent-dual-path commitment, retaining the LLM-prose alongside the Python invocation would re-open the divergence surface D24 is supposed to close. W2.7 reordered into 4 explicit sub-steps (port Step B+D, refactor test, add equivalence gate, version-bump).
- **F-DA2-1 (major) — `zsbd` lacked `dependencies: [{name: "zs"}]` declaration.** Added per `/tmp/research-plugin-schema.md` §11 lines 554-560. W1.1 now includes the second `plugin.json` for `zsbd` with the `dependencies` field. D2 rewritten with the failure-mode walkthrough (orphan-install yields 3 block-diagram skills with zero supporting infrastructure because all hooks/agents/rules ride on `zs`). `tests/test-plugin-manifest.sh` gains the dependency-declaration assertion. Risk Register gap (3) covers the research-deferred dependency-semantics fallback.
- **F-DA2-2 (major) — three substitution maps risk diverging.** Resolved via D24 consolidation: introduce `scripts/managed_rules_substitution.py` as the single source-of-truth substitution module; `scripts/render-managed-rules.py` becomes a thin wrapper; `tests/test-managed-md-up-to-date.sh` is refactored to invoke the renderer rather than inline its own Python; plugin SessionStart materialiser invokes the same renderer. Three callers, one map. W2.2 spec landed both files (`managed_rules_substitution.py` + `render-managed-rules.py`); W2.7 refactors the test in the same commit. Equivalence test is structurally guaranteed and acts as a canary against future refactor drift.
- **F-DA2-3 (major) — D16(a) skip-on-presence ignored version skew.** Folded into the rewritten D16(a) Option 1: each shipped hook script carries a line-2 `# zskills-hook-version: <YYYY.MM.N>` comment; the shim version-compares plugin-vs-settings.json copies; on plugin-newer it emits a one-time-per-hook WARN (gated by `.zskills/hook-skew-warned-<basename>` marker) and defers to settings.json (preferring stale-but-loudly-flagged over silent-double-fire). W1.3 specifies the line-2 stamp convention and a `tests/test-skill-conformance.sh` assertion that every shipped hook carries it.
- **F-R2-5 (minor) — test-count drift.** D8 enumeration grew from 15 to 16 (added `test-hook-template-sibling.sh`), header changed from "11 NEW" to "16 NEW", arithmetic restated as `0 retired + 16 new + 3 restructured-in-place = +16 net`. A5 + Phase 4 W4.4/W4.5 + Phase 4 header + Progress Tracker row 4 all updated to the canonical 16. D8 and Phase 4 W4.4 inventory lists now match exactly.
- **F-R2-6 (minor) — D25 lock-file shape ambiguous.** Spec'd explicitly: file path `.claude/zskills-install-lane`, content is single line bare value + trailing newline (`plugin\n` or `update-zskills\n`), written atomically via tmpfile+rename. Detection probes read with `[ "$(cat .claude/zskills-install-lane 2>/dev/null)" = plugin ]`. Both directions in D25 and W5.6 carry the same spec. D27 detection bullets use the bare-value form.
- **F-DA2-4 (minor) — `2026.08.0` deadline contradicted D23.** Deadline dropped from D6 and W3.2. The legacy one-liner is documented as a "documentation-class advisory" — preferred form is the new two-line dual-path source-pattern, but no test-suite-enforced migration deadline. Per F-DA2-4, the legacy form remains structurally valid on the `/update-zskills` lane forever.

### 2026-05-26 realignment round (`/refine-plan` against baseline `4761eef`)

Zero phases had executed; this round realigned the plan against repo drift after the #738/#740/#737/#736/#750 extraction refactors and the new claim-enforcement hook family (`block-run-plan-unclaimed.sh`, `block-fix-issue-unclaimed.sh`). Combined 20 findings (13 reviewer, 7 DA — 0 critical, 12 major, 8 minor); **zero architectural problems** — the dual-path design, the zs/zsbd split, the hybrid materialiser, and the #665 wildcard tightenings all held. All findings were stale-count, stale-reference, or internal-contradiction drift. The highest-leverage change was converting frozen integer counts into **execution-time re-derivation commands** (see the Drift-proofing note in the Overview) so the plan stops rotting between refine and execute.

Changes applied:

1. **Count drift → re-derivation (F-R1-1, F-R1-3/4/5/6, F-R1-7, F-DA1-2/5).** Every acceptance-gating count is now a re-derivation command with a "(was N as of 2026-05-26)" parenthetical: hooks (was 10 distinct / 11 commands, not "8"), resolver sites (was 151, not 145), legacy script-path refs (was 228, not 219), resolver skill DIRS for the version-bump (was **22**, not "38" — the "38" conflated 44 files / 151 sites / 22 dirs), `skills/` count (was 25), Skill-tool dispatch sites (was 26, not 18), test base (was 135). The W3.7 bump count is now keyed to `git diff --name-only` post-W3.1, not a literal.
2. **block-diagram roster corrected to 4 (F-R1-2, F-DA1-1).** Ground truth is 4 SKILL.md-bearing dirs (`add-block`, `add-example`, `model-design`, `review-feedback`); the reviewer's "5" wrongly counted the non-skill `screenshots/` asset dir; the original plan's "3" + the `zsbd` `plugin.json` description naming `manual-testing` (a `zs`-lane skill) were both wrong. Fixed in D2, W1.1 description, A2, pivot point 4. `tests/test-plugin-manifest.sh` now asserts the 4-dir roster (re-derived).
3. **KNOWN_SKILLS/KNOWN_HOOKS contradiction swept (F-R1-10, F-DA1-3).** D27's #665 wildcard fix retired the lists but left dangling references in D25 step 6 (removal gate) and D18 (mirror-parity whitelist) and the "Remaining concerns" F-DA3-1 item. D25 step 6 now gates removal on sentinel OR runtime basename-match against the shipped tree; D18 clarified to reference the mirror-parity test's own whitelist (unrelated mechanism); F-DA3-1 marked RESOLVED-by-D27.
4. **Stale line-number citations → section anchors (F-R1-8, F-R1-9).** W2.7's Step B §2 / Step D §2 edit targets and W2.2's subs-map citation now use grep-able section anchors / `grep -n 'subs = {'` instead of line numbers (the file is ~1930 lines and #750 already had to fix stale `SKILL.md:NNN` cross-refs once).
5. **Dual-path recovery-path gap on the new claim hooks (F-DA1-7) → Risk Register gap (9) + W1.4 rewrite pattern 2.** The claim hooks' deny-envelope recovery commands cite `${MAIN_ROOT}/.claude/skills/.../claim-*.sh` — a `/update-zskills`-lane-only path that ships broken under the plugin lane. W1.4 now adds the `${CLAUDE_PLUGIN_ROOT}` dual-resolution arm to those recovery paths and to `block-run-plan-unclaimed.sh`'s `zskills-paths.sh` fallback. This is the ONE place the DA's dual-path attack genuinely landed.
6. **Source-code fixes surfaced for the W1.4 implementer (F-DA1-4).** `block-fix-issue-unclaimed.sh:213` cites `SKILL.md:2161-2186`/`:2219-2243` which #740's extraction invalidated (file is now ~362 lines). Noted in W1.4 as a same-pass source-code fix (not a plan-prose fix). `block-run-plan-unclaimed.sh` confirmed to have no such stale ref.
7. **Stamp-placement + target-set ambiguity resolved (F-R1-11, F-DA3-2).** W1.3 now states the `# zskills-hook-version:` stamp INSERTS as a new line 2 (existing line-2 comments shift to line 3) and enumerates the target set (non-canary `.sh` + 2 `.template`; canary excluded).
8. **MW-EXAMPLE no-op tombstone (F-R1-13).** W6.5 marked already-satisfied (file gone); regression guards kept.

Confirmed-correct-don't-touch (verified, no change): CLAUDE_TEMPLATE.md 10 tokens / D24 placeholder map; `block-main-edits` matcher already `Edit|Write`; the 2 `.template` hooks exist (D4); the +16/0/3 net-new test delta math (base was 135, all 16 new files genuinely absent, all 3 restructure targets present); claim-state under `.zskills/` preserved across lane switches (F-DA1-6 negative finding); the load-bearing DA attack (W1.4 enumerating hooks by stale name-list) FAILED because W1.3/W1.4/D27 all use rules/wildcards.

## Plan Review

**Drafting process:** `/draft-plan` rounds 1-3 (single-path), then `/refine-plan` rounds 1 (dual-path drift correction), 2 (consistency tightening + schema-traceability), and a 2026-05-26 realignment round against baseline `4761eef` (count/reference drift after extraction refactors + the new claim-hook family) — reviewer + devil's-advocate + refiner with verify-before-fix on every finding.

**Round-1 disposition:** see `/tmp/refine-plan-disposition-round-1-PLUGIN_DISTRIBUTION.md`. 30 findings examined; 28 fixed in-plan, 2 justified-not-fixed, 0 new gaps introduced.

**Round-2 disposition:** see `/tmp/refine-plan-disposition-round-2-PLUGIN_DISTRIBUTION.md`. 11 findings examined (6 reviewer, 5 DA); 11 fixed in-plan, 0 justified-not-fixed, 0 deferred-within-plan, 0 new gaps introduced.

**Round-3 final review:** reviewer returned 0 findings; DA returned 2 minor findings (no critical, no major). Both are judgment-class gaps with one-paragraph fixes; neither contradicts a locked decision. Documented under "Remaining concerns" below.

**Round History**

| Round | Reviewer | DA | Total | Substantive after refine |
|-------|----------|-----|-------|--------------------------|
| 1 | 19 (6 crit, 7 maj, 6 min) | 11 (4 crit, 4 maj, 3 min) | 30 | 2 justified-not-fixed |
| 2 | 6 (1 crit, 3 maj, 2 min) | 5 (0 crit, 3 maj, 2 min) | 11 | 0 (all fixed) |
| 3 | 0 | 2 (0 crit, 0 maj, 2 min) | 2 | 2 (rounds budget exhausted) |
| realign R1 (2026-05-26) | 13 (0 crit, 9 maj, 4 min) | 7 (0 crit, 3 maj, 4 min) | 20 | 19 fixed, 1 justified (DA's load-bearing attack FAILED — new claim hooks structurally covered by wildcard/rule enumeration, no plan edit needed) |
| realign R2 (2026-05-26) | 1 (0 crit, 0 maj, 1 min) | 1 (0 crit, 0 maj, 1 min) | 1 unique | 0 — both reviewers independently found the SAME single anchor-typo (W2.7/D24 Step D grep), now fixed |

Trajectory 30 → 11 → 2 (convergence on the dual-path design), then a realignment pass driven purely by repo drift after the plan sat un-executed through ~85 commits of refactors: realign R1 = 20 findings (all drift/contradiction, ZERO architectural), realign R2 = 1 finding (both reviewers converged on the same anchor typo). The architecture held entirely across both the original convergence and the realignment.

**Remaining concerns (round 3 — both RESOLVED in the 2026-05-26 realignment):**

1. **F-DA3-1 (minor) — RESOLVED by D27's wildcard detection (2026-05-26).** Round 3 proposed `hooks/_lib/known-skills.txt`/`known-hooks.txt` fixture lists plus a `tests/test-known-lists-complete.sh` completeness gate. D27 was subsequently rewritten to use WILDCARD detection (`.claude/skills/*/SKILL.md` + `.claude/hooks/*.sh` patterns, sentinel-distinguished) and explicitly RETIRES both fixture lists and obviates the completeness gate (no list to complete — see D27 "/update-zskills-lane evidence"). The lists do not exist in the repo (`ls hooks/_lib/` → only `git-tokenwalk.sh`, `resolve-effective-worktree-root.sh`). Do NOT create them; do NOT add `test-known-lists-complete.sh`. The stale references in D25 step 6 (removal gate) and D18 (mirror-parity whitelist) have been scrubbed to point at the wildcard + sentinel mechanism.

2. **F-DA3-2 (minor) — RESOLVED in W1.3 (2026-05-26).** The stamp-placement ambiguity is now disambiguated directly in W1.3: the `# zskills-hook-version:` stamp is INSERTED as a new line 2 ahead of any existing descriptive line-2 comment (existing comments shift to line 3), and the target set is enumerated (all non-canary `.sh` hooks + the 2 `.template` hooks; `canary3-bad.sh` excluded per D9 — re-derive, was 11 as of 2026-05-26). No remaining work.

**Convergence:** the plan is internally consistent under the dual-path commitment. All round-2 critical/major findings closed via verified spec-tightening, not papered-over with justifications. The 9 risk-register entries carry through (3 research-deferred, 6 dual-path-specific incl. the new gap (9) claim-hook recovery-path) with explicit failure-mode + mitigation pairs.

**Verifications anchored throughout — and now drift-PROOFED (2026-05-26 realignment).** Acceptance-gating counts are no longer frozen integers; they are execution-time re-derivation commands (see the Overview Drift-proofing note). The 2026-05-26 ground-truth anchors (re-verified by grep against baseline `4761eef`): resolver sites 151 across 44 files spanning 22 skill dirs (NOT the prior "145 / 38"); legacy `.claude/skills/update-zskills/scripts/` refs 228 (NOT 219); registered settings.json hooks 10 distinct / 11 commands (NOT 8); `skills/` dirs 25; block-diagram SKILL.md dirs 4 (NOT 3 or 5); Skill-tool dispatch sites 26 (NOT 18); top-level test files 135; CLAUDE_TEMPLATE.md tokens 10 (unchanged); 5 materialised artifacts; 4 install lane states; +16 net-new tests. Schema citations point at `/tmp/research-plugin-schema.md` §3 (marketplace source types), §5 (hook entry shape), §11 (plugin dependencies). Per-skill / per-site numbers will drift again before execution — implementers MUST re-run the cited commands and gate on their output, never on the parentheticals.

**What this plan does NOT pretend.** It does NOT pretend dual-path is smaller than single-path-with-cutover. It does NOT pretend `/update-zskills` will be deprecated quietly. It does NOT pretend the bare-slash prose refs in skill bodies will magically resolve correctly for plugin-lane consumers — the tradeoff is documented in Risk Register gap (8) and `docs/PLUGIN_INSTALL.md`. It does NOT pretend the plugin-mode CI lane is "cheap" without acknowledging the three-tier cost structure (F-DA1-6).

The plan is ready for execution. Phase 1 has zero skill-body edits and is fully additive; the highest-risk decisions (D6 per-site fallback, D24 renderer collapse, D27 dual-install probe) land in Phases 2-3 where the dogfood loop catches misbehaviour empirically.
