<!-- prod-strip:start -->
# DEV-QUAL — zskills maintainer manual-acceptance checklist

This file is the **maintainer-facing manual dev-quality checklist** for
zskills. It holds the five manual install scenarios a human runs to
accept a release across both distribution lanes.

## How to use this checklist

These are **manual** acceptance scenarios — a human runs them by hand against a
release candidate. They complement, not replace, the automated gate
(`bash tests/run-all.sh`). Each scenario states its purpose, preconditions,
step-by-step commands, and the observable results that make it a PASS.

zskills ships **two install lanes**, and a real consumer uses exactly one: the
**plugin lane** (`/plugin install zs@zskills`, zero project writes until the
explicit `/zs:update-zskills` init) and the legacy **`/update-zskills`** lane
(which mirrors the skills into the project's `.claude/`). There is no
in-place lane switch — a consumer that wants the other lane uninstalls one
and installs the other. The scenarios below exercise each lane, the explicit
init, the pre-init gate, and the upgraded-consumer residue path.

---

## Scenario 1 — Legacy `/update-zskills` install in a fresh repo

**Purpose.** Accept the bespoke installer end-to-end: it mirrors `skills/` →
`.claude/skills/`, copies hooks, registers them in `.claude/settings.json`,
and renders `CLAUDE_TEMPLATE.md` → `.claude/rules/zskills/managed.md`.

**Preconditions.**
- A fresh consumer repo (git-initialised, NO existing zskills install — no
  `.claude/skills/`).
- A Claude Code session in that repo with the `update-zskills` skill
  available (by pointing at the source tree during dogfooding).

**Steps.**
1. In the consumer session, run the installer in explicit mode:
   ```
   /update-zskills install
   ```
   (Append a preset if you want a non-default landing mode, e.g.
   `/update-zskills install locked-main-pr` — presets are config-only.)
2. Let it complete its audit + install. It writes the mirror, the hooks, the
   settings.json hook registrations, the config, and the rendered
   `managed.md`.

**Expected observable results (PASS criteria).**
- `.claude/skills/` exists and is non-empty (the mirrored source skills).
- `.claude/hooks/` contains the zskills hook scripts (e.g.
  `block-unsafe-generic.sh`, `inject-bash-timeout.sh`).
- `.claude/settings.json` registers the zskills hooks (grep it for the hook
  basenames).
- `.claude/zskills-config.json` exists.
- `.claude/rules/zskills/managed.md` exists and is rendered.
- `.claude/agents/verifier.md` + `.claude/agents/implementer.md` exist WITH
  their frontmatter `hooks:` block (the legacy Layer-0 delivery).
- `.gitignore` carries the `.zskills/` umbrella entry (the installer appends
  it idempotently).
- A subsequent `/update-zskills` (no arg, smart-detect) reports "already
  installed" and pulls/updates rather than re-installing. It now ALSO runs
  the bundled consumer post-install verifier's cheap structural tier
  (read-only, NON-FATAL) at the end, printing per-check `PASS`/`WARN`/`FAIL`
  lines, a `Result: N PASS, M WARN, K FAIL` line, and an `Overall: PASS`
  summary on a healthy legacy install.

---

## Scenario 2 — Plugin install: zero-write default + explicit init

**Purpose.** Accept the plugin lane in its NORMAL shape — install shape (b),
a REAL marketplace install of a built prod tree: **zero project writes
before init** (skills, hooks, agents, and rules all run from
`${CLAUDE_PLUGIN_ROOT}`), the pre-init greeting, the one-time
`/zs:update-zskills` init, and the **exact post-init footprint**.

**Preconditions.**
- A built, prod-stripped tree (see Scenario 5 step 1, or snapshot + run
  `scripts/build-prod.sh` in the snapshot).
- A sandbox `CLAUDE_CONFIG_DIR` (never your real one) with a local
  marketplace: `claude plugin marketplace add <built-tree-path>` then
  `claude plugin install zs@zskills`.
- A fresh consumer repo (git-initialised, NO `.claude/` at all).

**Steps.**
1. Open a session in the consumer repo with the plugin installed.
2. Observe the one-line setup greeting (the `systemMessage` pointing at
   `/zs:update-zskills`).
3. Exercise a read-only skill and a verifier/implementer dispatch with a
   >120s Bash call (Layer-0 live — the call must NOT hit the 120s default).
4. Check `git status --porcelain` — **empty**; no `.claude/` or `.zskills/`
   paths exist. The model can quote a managed-rules landmark (the R-b
   SessionStart `additionalContext` delivery) with still zero writes.
5. Run the one-time init:
   ```
   /zs:update-zskills
   ```
6. Inspect the footprint and re-open a session.

**Expected observable results (PASS criteria).**
- Pre-init: greeting present; `git status --porcelain` empty; NO
  `.claude/`, NO `.zskills/`; rules landmark quotable; `/zs:` skills
  dispatch from the plugin tree.
- Init transcript shows: gitignore-first append, the optional-config offer
  (decline ⇒ no file), the verify pass, and the lock-LAST marker write.
- Post-init footprint is EXACTLY: a `.zskills/` line in `.gitignore`,
  gitignored `.zskills/init-done` + `.zskills/setup-confirmed`, and — only
  if you accepted the config offer — `.claude/zskills-config.json` + its
  schema sibling. Nothing else. NO `.claude/skills/`, NO `.claude/hooks/`,
  NO `.claude/agents/`, NO `.claude/rules/`.
- Next session start: the greeting is silent (init-done present).
- A later bare `/zs:update-zskills` runs the UPDATE arm (re-verify +
  version-line refresh), not a re-init.

---

## Scenario 3 — Pre-init gate: block → cure → allow

**Purpose.** Accept BOTH branches of the `UserPromptExpansion` gate
(`hooks/block-unmaterialised-skill.sh`) live: pre-init it blocks
state-writing `/zs:` skills with a friendly setup pointer (read-only skills
and `zs:update-zskills` itself pass), and post-init it allows everything.
(#1132 lesson: a gate is only validated when BOTH branches have run live.)

**Preconditions.** Scenario 2's consumer repo, BEFORE its init step (or a
fresh one in the same install).

**Steps + expected observables.**
1. Pre-init, invoke a state-writing skill (e.g. `/zs:do test task`):
   **BLOCKED** — the gate's message names `/zs:update-zskills` as the cure;
   the skill does not execute.
2. Pre-init, invoke a read-only skill (e.g. `/zs:briefing`): **ALLOWED**.
3. Run `/zs:update-zskills` (the cure — always allowed pre-init).
4. Post-init, repeat step 1: **ALLOWED** — zero block records; the skill
   executes.

---

## Scenario 4 — Upgraded materialiser-era consumer (residue cleanup)

**Purpose.** Accept the A1.5 residue path — the one shape a fresh repo can
never exercise. Consumers upgrading from pre-redesign releases arrive with
the old SessionStart materialiser's artifacts; the first
`/zs:update-zskills` on the new release must clean them up.

**Preconditions.**
- A consumer repo fabricated as a materialiser-era install: the 5 legacy
  artifacts (`.claude/agents/{verifier,implementer}.md`,
  `.claude/hooks/{inject-bash-timeout,verify-response-validate}.sh`,
  `.claude/rules/zskills/managed.md` — each carrying the legacy D20
  sentinel prefix in its first 3 lines), the seeded
  `.claude/zskills-config.json` + schema sibling, and the legacy
  seeded-config notice marker. Derive ALL the literals — the sentinel
  prefix, the notice path, the artifact paths, the frozen seed shape —
  from `skills/update-zskills/scripts/init-state.sh`'s frozen
  legacy-residue constants (never re-type them; the literal-string
  discipline keeps them in that one file), or produce them by running the
  pre-Phase-7 materialiser from a historical checkout.
- The NEW built release installed over it (Scenario 2's install shape).

**Steps.**
1. Run `/zs:update-zskills` in the upgraded consumer.
2. When the seeded-config offer fires (notice present + config still matches
   the frozen seed shape), accept the removal.

**Expected observable results (PASS criteria).**
- Every sentinelled artifact is REMOVED (sentinel-less / user-owned files at
  the same paths would be preserved — that is the discriminator).
- The seeded-config offer fired with the documented semantics; on accept the
  config + schema are removed; on every path the notice is consumed exactly
  once (the offer never repeats).
- The post-init footprint equals Scenario 2's exact set.
- A repeat `/zs:update-zskills` performs NO further removals (cleanup is
  permanent; nothing re-creates the residue).

---

## Scenario 5 — Mirror-less `claude --plugin-dir <built-tree>` BEHAVIOR run

**Purpose.** Accept plugin **RUNTIME** behavior in a CLEAN, mirror-less
consumer dir — skills actually resolving under `${CLAUDE_PLUGIN_ROOT}`,
hooks actually firing, `/zs:` slash dispatch working — via the fast
`--plugin-dir` loop. (Scenario 2 is the authoritative shape-(b) proof; this
is the quick regression-class check.)

**Why this scenario.** The "dogfood-mask" (#799/#831) shipped because the
zskills-dev mirror satisfied skill lookups and hid the fact the plugin lane
never resolved under `${CLAUDE_PLUGIN_ROOT}`. **Never run `--plugin-dir .`
from inside zskills-dev as plugin-lane evidence.**

**Preconditions.**
- A built, prod-stripped plugin tree, produced via
  `bash scripts/build-plugin-release.sh` (creates local `prod/main`) and
  checked out with `git worktree add <dir> prod/main`.
- A CLEAN consumer dir with NO `.claude/skills/` mirror.

**Steps.**
1. Build the prod-stripped tree and check it out into a dir:
   ```bash
   bash scripts/build-plugin-release.sh        # creates local prod/main
   git worktree add /tmp/zs-prod-tree prod/main
   ```
2. Create a clean, mirror-less consumer dir (a fresh git repo with NO
   `.claude/skills/`):
   ```bash
   mkdir -p /tmp/zs-consumer && git -C /tmp/zs-consumer init -q
   ```
3. Launch an AUTHED Claude session in the consumer dir, loading the BUILT
   tree as the plugin:
   ```bash
   cd /tmp/zs-consumer && claude --plugin-dir /tmp/zs-prod-tree
   ```
4. In that session: dispatch a `/zs:` skill, trigger a gated git command to
   make a hook fire, and check the project stays clean.

**Expected observable results (PASS criteria).**
- `/zs:` dispatch works against the BUILT tree (e.g. `/zs:update-zskills`
  reports state) — proving skills resolve under `${CLAUDE_PLUGIN_ROOT}`
  with NO mirror present.
- A zskills hook fires (e.g. any command the `block-unsafe-*` hooks gate —
  observe the hook envelope) — proving `hooks/hooks.json` registered under
  the plugin root.
- The built tree carries root `agents/verifier.md` + `agents/implementer.md`
  and NONE of the retired pre-redesign machinery (the old SessionStart
  materialiser hook, the lane-switch script and its strip helper, the
  lane-switching guide — verify with the end-state item-3 grep in
  `docs/plans/INSTALL_REDESIGN_PLAN.md`).
- `git status --porcelain` in `/tmp/zs-consumer` stays EMPTY across the
  session (zero-write default; only an explicit `/zs:update-zskills` init
  writes).
- `/tmp/zs-consumer/.claude/skills/` does NOT exist — confirming mirror-less
  resolution (the norm).
- Clean up afterward: `git worktree remove /tmp/zs-prod-tree`, remove the
  local prod refs (`git update-ref -d refs/heads/prod/main` and the
  `prod/<version>` tag), and remove `/tmp/zs-consumer`.
<!-- prod-strip:end -->
