<!-- prod-strip:start -->
# DEV-QUAL — zskills maintainer manual-acceptance checklist

This file is the **maintainer-facing manual dev-quality checklist** for
zskills. It holds (1) the five manual install scenarios a human runs to
accept a release across both distribution lanes, and (2) how to run the
autonomous `scripts/dogfood-plugin-install.sh`.

Like `RELEASING.md`, this is **dev-maintainer-only and prod-stripped**: its
entire content sits inside `<!-- prod-strip:start --> … <!-- prod-strip:end
-->` markers AND the build scripts remove the file wholesale, so it never
ships to either lane's consumers. You will not see this file on
`github.com/zeveck/zskills` or in any installed plugin tree. (If you are
adding a new dev-only top-level doc, mirror BOTH mechanisms — the marker
wrap and the `for f in RELEASING.md DEV-QUAL.md; do … done` removal loops in
`scripts/build-prod.sh`, `scripts/build-plugin-release.sh`, and
`tests/test-plugin-mirrorless-resolution.sh`.)

## How to use this checklist

These are **manual** acceptance scenarios — a human runs them, by hand,
against a release candidate. They complement, not replace, the automated
gate (`bash tests/run-all.sh`) and the autonomous install dogfood (Part 3).
Each scenario states its **purpose**, **preconditions**, **step-by-step
commands** (traced to the real install machinery — no invented commands),
and **expected observable results** (what to check to call it a PASS).

Internalize the **plugin-lane mental model** from `CLAUDE.md` before running
these:

- A real consumer is **single-lane** — it installs zskills via the plugin
  lane OR the legacy `/update-zskills` lane, never both.
- **Mirror-less plugin is the norm and the goal**: a real plugin consumer
  has NO `.claude/skills/` mirror — only the 5 materialised artifacts +
  `.claude/zskills-config.json`, everything resolving under
  `${CLAUDE_PLUGIN_ROOT}`.
- **Dual install** (both lanes present at once) is NOT a supported consumer
  state. It exists only in this dogfooding repo and transiently during a
  lane switch; the system actively pushes to consolidate it.
- **The dogfood trap**: zskills-dev itself carries a `.claude/skills/`
  mirror because it is the source repo. Never treat the presence of that
  mirror as evidence the plugin lane works — validate **mirror-less** or you
  reproduce the "dogfood-mask" that shipped the non-functional plugin lanes
  in #799/#831.

The lane lock lives at `.claude/zskills-install-lane` (bare value `plugin`
or `update-zskills`, written LAST by `scripts/switch-install-path.sh`).

---

## Scenario 1 — Legacy `/update-zskills` install in a fresh repo

**Purpose.** Accept the bespoke installer end-to-end: it mirrors `skills/` →
`.claude/skills/`, copies hooks, registers them in `.claude/settings.json`,
and renders `CLAUDE_TEMPLATE.md` → `.claude/rules/zskills/managed.md`.

**Preconditions.**
- A fresh consumer repo (git-initialised, NO existing zskills install — no
  `.claude/skills/`, no `.claude/zskills-install-lane`).
- A Claude Code session in that repo with the `update-zskills` skill
  available (either via the plugin lane's `/zs:update-zskills`, or by
  pointing at the source tree during dogfooding).

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
- `.claude/rules/zskills/managed.md` exists and is rendered (no unsubstituted
  `<!-- TODO: ... -->` placeholders for values the config supplies).
- `.claude/zskills-install-lane` is absent OR — if a switch has ever run —
  it is NOT `plugin`. (A pure legacy install does not itself write the lock;
  the lock is written by `switch-install-path.sh`. The defining signal of
  the legacy lane is the **mirror present**, not the lock value.)
- A subsequent `/update-zskills` (no arg, smart-detect) reports "already
  installed" and pulls/updates rather than re-installing.

---

## Scenario 2 — Plugin install (mirror-less is the goal)

**Purpose.** Accept the plugin lane in its NORMAL shape: skills namespaced
under `/zs:`, `${CLAUDE_PLUGIN_ROOT}` set, the SessionStart materialiser
writing the 5 consumer artifacts, and **no `.claude/skills/` mirror**.

**Preconditions.**
- For in-place dogfooding from this repo: a Claude Code session launched with
  `claude --plugin-dir .` from the zskills-dev root. (Caveat: this repo
  carries the `.claude/skills/` mirror — the dogfooding exception, case 3 in
  the mental model — so it does NOT validate mirror-less resolution. Use
  Scenario 5 for that.)
- For the **real consumer path**: a marketplace install
  (`/plugin marketplace add zeveck/zskills` → `/plugin install zs@zskills`)
  in a clean consumer repo. The install-lane half of that path is dogfooded
  autonomously by `scripts/dogfood-plugin-install.sh` (Part 3) — run that
  first to confirm clone + marketplace-resolution + cache before doing a
  manual marketplace install.

**Steps.**
1. Launch the plugin-loaded session:
   ```bash
   claude --plugin-dir .        # in-place dogfood from zskills-dev
   ```
   (Real consumers instead use the `/plugin marketplace add` +
   `/plugin install zs@zskills` flow.)
2. Confirm the plugin loaded: the skills are namespaced under `/zs:`
   (e.g. `/zs:do`, `/zs:fix-issues`).
3. On SessionStart, `hooks/session-start-materialise.sh` runs. In a
   mirror-less consumer it seeds a default `.claude/zskills-config.json` (if
   absent) and materialises the 5 artifacts.

**Expected observable results (PASS criteria).**
- Skills dispatch under the `/zs:` namespace (`/zs:update-zskills`,
  `/zs:do`, etc.).
- `${CLAUDE_PLUGIN_ROOT}` is set in the session (hooks and skills resolve
  paths under it).
- The 5 materialised artifacts exist in the consumer's `.claude/`, each
  carrying a `zskills-materialised:` sentinel in its first 3 lines:
  - `.claude/agents/verifier.md`
  - `.claude/agents/implementer.md`
  - `.claude/hooks/inject-bash-timeout.sh` (executable)
  - `.claude/hooks/verify-response-validate.sh` (executable)
  - `.claude/rules/zskills/managed.md` (rendered)
- In a **mirror-less** consumer: NO `.claude/skills/` directory. (In the
  zskills-dev dogfood, the mirror IS present — that is the dogfooding
  exception, NOT a pass signal for mirror-less behavior.)
- `.claude/zskills-install-lane` is `plugin` if a switch has run; on a pure
  fresh plugin install the materialiser does not write the lock — the
  defining signal is the materialised artifacts + absent mirror.

---

## Scenario 3 — Legacy → plugin switch

**Purpose.** Accept the consolidation tool's `--to-plugin` direction: a
consumer on the `/update-zskills` lane switches to the plugin lane, the
mirror artifacts are stripped, and the lane lock flips to `plugin`.

**Preconditions.**
- A consumer currently on the legacy lane (Scenario 1 passed): `.claude/skills/`
  mirror present, zskills hooks registered in `.claude/settings.json`.

**Steps.**
1. Run the switcher in your Claude session:
   ```
   /update-zskills --switch-install-path=to-plugin
   ```
   (it dispatches the bundled `scripts/switch-install-path.sh --to-plugin`
   for you; invoke the script directly only when debugging the switch
   machinery.)
2. It strips the zskills hook entries from `.claude/settings.json` FIRST
   (config write first), prints the
   `/plugin marketplace add zeveck/zskills` + `/plugin install zs@zskills`
   steps, and (interactively) blocks until you type `done`. Follow the
   printed `/plugin` steps in your Claude session, then confirm.
   (For a non-interactive smoke, set `ZSKILLS_SWITCH_NONINTERACTIVE=1` to
   skip the `read`-block; the instruction is still printed.)
3. It then does basename-gated removal of the mirrored `.claude/skills/`,
   `.claude/hooks/`, and `.claude/rules/zskills/managed.md` (consumer-authored
   skills/hooks are preserved), and writes the lock LAST.

**Expected observable results (PASS criteria).**
- `.claude/zskills-install-lane` contains exactly `plugin`.
- The zskills hook entries are gone from `.claude/settings.json` (consumer
  hooks preserved).
- The mirrored zskills skills/hooks/managed.md are removed (only
  zskills-owned basenames — third-party skills/hooks under `.claude/` are
  kept).
- `.zskills/` runtime state (claim markers, tracking) is untouched
  (lane-independent).
- Re-running `/update-zskills --switch-install-path=to-plugin` is a
  no-op-with-INFO ("Already on the plugin lane").

---

## Scenario 4 — Plugin → legacy switch

**Purpose.** Accept the consolidation tool's `--to-update-zskills`
direction: a consumer on the plugin lane switches back to the legacy lane,
the sentinelled plugin artifacts are removed, the mirror is restored by
`/update-zskills install`, and the lane lock flips to `update-zskills` —
without deadlocking on Step 0.7's hard-refuse.

**Preconditions.**
- A consumer currently on the plugin lane (Scenario 2 passed): the 5
  sentinelled artifacts present, no `.claude/skills/` mirror.

**Steps.**
1. Run the switcher in your Claude session:
   ```
   /update-zskills --switch-install-path=to-update-zskills
   ```
   (it dispatches the bundled `scripts/switch-install-path.sh
   --to-update-zskills` for you; invoke the script directly only when
   debugging the switch machinery.)
2. It writes `.zskills/switch-in-progress` at its START. This marker is
   load-bearing: while it is present BOTH (i) the `/update-zskills` Step 0.7
   W6.1 hard-refuse skips itself (so the mandated `/update-zskills install`
   is allowed on a `detect==plugin` consumer instead of being refused) AND
   (ii) `session-start-materialise.sh` skips re-materialising (so it does not
   re-arm `detect==plugin` across the restart). This is what prevents the
   switch from deadlocking.
3. Follow the printed steps in your Claude session:
   ```
   /plugin uninstall zs@zskills
   ```
   restart Claude Code, then:
   ```
   /update-zskills install
   ```
   Confirm back at the switcher prompt (type `done`).
4. The switcher does sentinel-gated removal of any of the 5 artifacts that
   STILL carry a `zskills-materialised:` sentinel (sentinel-less /
   re-installed files are `/update-zskills`-owned and preserved), writes the
   lock LAST, then removes `.zskills/switch-in-progress`.

**Expected observable results (PASS criteria).**
- `.claude/zskills-install-lane` contains exactly `update-zskills`.
- `.claude/skills/` mirror is restored (by the `/update-zskills install`
  step) and `.claude/settings.json` re-registers the zskills hooks.
- `.claude/rules/zskills/managed.md` is present and NOT sentinelled (it is
  now `/update-zskills`-rendered, not plugin-materialised).
- `.zskills/switch-in-progress` is gone (cleared strictly AFTER the lock was
  written — lock-LAST contract preserved).
- `.zskills/` runtime state is untouched.
- Re-running `/update-zskills --switch-install-path=to-update-zskills` is a
  no-op-with-INFO ("Already on the /update-zskills lane").

---

## Scenario 5 — Mirror-less `claude --plugin-dir <built-tree>` BEHAVIOR run

**Purpose.** Accept plugin **RUNTIME** behavior in a CLEAN, mirror-less
consumer dir — the half neither the install dogfood (Part 3) nor any
non-interactive run proves: skills actually resolving under
`${CLAUDE_PLUGIN_ROOT}`, hooks actually firing, `/zs:` slash dispatch
working, and the materialiser writing its 5 artifacts.

**Why this scenario over dual-install consolidation.** The dual-install
consolidation path is already covered structurally — Scenarios 3 and 4
exercise the bidirectional `switch-install-path.sh`, and the D27 nag in
`session-start-materialise.sh` is hit on every dual session. What no other
scenario or automated test proves is **mirror-less RUNTIME resolution** —
and that is precisely the gap the "dogfood-mask" exploited in #799/#831,
where the zskills-dev mirror satisfied skill lookups and hid the fact the
plugin lane never resolved under `${CLAUDE_PLUGIN_ROOT}`. This is the
highest-value manual check because it cannot be made automatic (it needs an
authed `claude` session) and it guards the exact regression class that
shipped two broken plugin lanes.

**Preconditions.**
- A built, prod-stripped plugin tree (Part 3's build, or a manual
  `bash scripts/build-plugin-release.sh` producing local `prod/main`).
- A CLEAN consumer dir with NO `.claude/skills/` mirror — **never run
  `--plugin-dir .` from inside zskills-dev** (that reproduces the
  dogfood-mask).

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
   make a hook fire, and inspect the materialised artifacts.

**Expected observable results (PASS criteria).**
- `/zs:` dispatch works against the BUILT tree (e.g. `/zs:update-zskills`
  smart-detect reports state) — proving skills resolve under
  `${CLAUDE_PLUGIN_ROOT}` with NO mirror present.
- A zskills hook fires (e.g. attempt a `git commit` with a stale skill
  version, or any command the `block-unsafe-*` hooks gate, and observe the
  hook envelope) — proving `hooks/hooks.json` registered under the plugin
  root.
- The 5 materialised artifacts appear in `/tmp/zs-consumer/.claude/` with
  `zskills-materialised:` sentinels — proving the SessionStart materialiser
  ran in a mirror-less consumer.
- `/tmp/zs-consumer/.claude/skills/` does NOT exist — confirming mirror-less
  resolution (the norm).
- Clean up afterward: `git worktree remove /tmp/zs-prod-tree`, remove the
  local prod refs (`git update-ref -d refs/heads/prod/main` and the
  `prod/<version>` tag), and remove `/tmp/zs-consumer`.

---

## Part 3 — Autonomous install dogfood (`scripts/dogfood-plugin-install.sh`)

`scripts/dogfood-plugin-install.sh` exercises a REAL `claude plugin install`
of the `zs` plugin end-to-end, from a throwaway marketplace pointing at the
public dev repo, leaving **zero cruft** in the real `~/.claude`. The whole
run is sandboxed under an isolated `HOME` (= `CLAUDE_CONFIG_DIR`) in `/tmp`,
recursively removed on exit. This is the **install-lane half** of plugin
dogfooding (issue #960).

**What it does.** Under the isolated config root it (1) clones this repo into
the sandbox and runs `scripts/build-plugin-release.sh` inside the clone
(with a clone-scoped git identity, since `git commit-tree` needs an ident a
fresh clone lacks) to produce the prod-stripped tree; (2) writes a throwaway
`marketplace.json` with a single `zs` entry using an https `url` source
(NOT the prod `github` shorthand — that clones via git@ SSH and fails in a
keyless sandbox); (3) runs `claude plugin marketplace add` +
`claude plugin install zs@zskills`; and (4) asserts the cached tree under the
isolated config root contains the load-bearing artifacts (`.claude-plugin/plugin.json`,
`hooks/hooks.json`, the non-empty `skills/` dir,
`hooks/session-start-materialise.sh`, and the lane-portable
`skills/update-zskills/scripts/zskills-resolve-config.sh`).

**Usage.**
```bash
bash scripts/dogfood-plugin-install.sh                  # install from public dev @ main
bash scripts/dogfood-plugin-install.sh --ref my-branch  # from a pushed branch
bash scripts/dogfood-plugin-install.sh --keep           # keep the /tmp dir to inspect
```

**Flags / env.**
- `--ref <branch>` (default `main`; env `ZSKILLS_DOGFOOD_REF`) — the
  PUBLIC-remote branch the install pulls from. Because the install pulls from
  the public dev repo at this ref, the branch MUST already be pushed there to
  reflect non-main work.
- `--keep` (env `ZSKILLS_DOGFOOD_KEEP=1`) — skip teardown; leave the
  isolated `/tmp` dir and print its path for inspection.
- `ZSKILLS_DOGFOOD_REPO` — override the public dev repo URL.
- `ZSKILLS_PYTHON` — override the Python 3 interpreter.
- If the `claude` CLI is absent (e.g. a bare CI runner) the script SKIPs and
  exits 0.

**What it PROVES vs does NOT.** It validates the **clone +
marketplace-resolution + cache** layer only — "installed" is necessary, not
sufficient. It does NOT exercise RUNTIME resolution: skills resolving under
`${CLAUDE_PLUGIN_ROOT}`, hooks actually firing, `/zs:` slash dispatch, or the
SessionStart materialiser writing the 5 consumer artifacts.

**Authed-session caveat.** Confirming the runtime half needs a real AUTHED
`claude` session (interactive, or headless `claude -p` — both require login);
neither the install dogfood nor any non-interactive run covers it. The
runtime half is exactly **Scenario 5** above (`claude --plugin-dir
<built-tree>` from a clean consumer dir). See `RELEASING.md`
"## Dogfooding lanes" for the full dual-lane dogfooding model rather than
duplicating it here.
<!-- prod-strip:end -->
