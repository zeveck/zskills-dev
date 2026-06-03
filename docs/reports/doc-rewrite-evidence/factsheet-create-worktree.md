# Fact sheet — docs/skills/create-worktree.md

Every factual claim in the rewritten `docs/skills/create-worktree.md` traced to a
verbatim line in `skills/create-worktree/SKILL.md` (the ground-truth source).
Source read in full.

Source version at time of writing: `metadata.version: "2026.06.01+e7b84c"`
(`skills/create-worktree/SKILL.md:12`).

---

## Lead / "What it does" — creates an isolated git worktree on a fresh branch

**Doc sentence:** "`/create-worktree` sets up a fresh git worktree — a separate
checkout of the repository in its own directory — so an agent can work on a
change in isolation."

- `skills/create-worktree/SKILL.md:6`: `"Create a git worktree for agent work."`
- `skills/create-worktree/SKILL.md:15`: `"# /create-worktree — Unified Worktree Creation"`

**Doc sentence:** "You give it a short slug; it picks a directory and a branch
name from that slug."

- `skills/create-worktree/SKILL.md:52`: `"\`<slug>\` (required, positional) — last non-flag token. Must match \`[A-Za-z0-9._-]+\`."`
- `skills/create-worktree/SKILL.md:68` (path template): `"\`... <slug>\` | \`${WORKTREE_ROOT}/${PROJECT_NAME}-${SLUG}\` | \`wt-${SLUG}\`"` — directory leaf and branch both derived from the slug.

**Doc sentence:** "creates the worktree there, and prints the worktree's absolute
path so the caller can `cd` into it and start working."

- `skills/create-worktree/SKILL.md:9-10` (description): `"Prints the worktree path on stdout."`
- `skills/create-worktree/SKILL.md:77`: `"On success (rc=0), stdout is exactly one line: the absolute worktree path. ... Callers may safely \`WT_PATH=$(bash … <slug>)\` and \`cd \"$WT_PATH\"\`."`

**Doc sentence (default branch is `wt-<slug>`, off `main`):** "on a new branch
`wt-my-feature`, branched from `main`."

- `skills/create-worktree/SKILL.md:68`: branch `wt-${SLUG}` for the bare-slug invocation.
- `skills/create-worktree/SKILL.md:56`: `"\`--from B\` — base branch for pre-flight and \`worktree-add-safe.sh\`. Default \`main\`."`

---

## Pre-flight (tidy-up) paragraph

**Doc sentence:** "By default it first tidies up: it prunes stale worktree
entries, fetches `main` from the remote, and fast-forwards your local `main` to
match ... You can skip this tidy-up with `--no-preflight`."

- `skills/create-worktree/SKILL.md:60`: `"\`--no-preflight\` — skip \`git worktree prune\`, \`git fetch origin <BASE>\`, \`git merge --ff-only origin/<BASE>\`. Preserves pre-migration semantics for \`/do\` worktree mode."`
- `skills/create-worktree/SKILL.md:8` (description): `"optional pre-flight prune+fetch+ff-merge"`.

---

## "Shared building block / rarely typed directly" framing

**Doc sentence:** "This is the shared building block that every isolation-using
skill relies on. `/do`, `/run-plan`, `/fix-issues`, and others call it to get a
clean worktree before they make changes — which is why you seldom type
`/create-worktree` yourself."

- `skills/create-worktree/SKILL.md:23`: `"**Tier 1 — bash callers inside other skills** (e.g. \`/run-plan\`, \`/fix-issues\`, \`/do\`)."`
- `COMPANIONS.md:78` (create-worktree row): relationship = `"The shared worktree-setup primitive every isolation-using skill calls."`
- `USAGE_MAP.md:62-68`: `/create-worktree` is in the "Never observed in the \`Run /<skill>\` cron form" list — "several are dispatched *by* other skills, not cron-fired, e.g. \`create-worktree\`."

**Doc sentence:** "It is still a normal command you *can* run directly."

- `skills/create-worktree/SKILL.md:3`: `disable-model-invocation: false` (it is NOT `user-invocable: false`; it stays a normal catalog command — per the task framing, only `land-pr` + `manual-testing` move to Internal Skills).
- `skills/create-worktree/SKILL.md:25`: `"**Tier 2 — user / Claude invoking \`/create-worktree\` as a slash command.** Users say \"make a worktree called \`foo-task\`\"."`

---

## Usage block + bare-slug example

**Doc:** `/create-worktree <slug> [--prefix P] [--branch-name REF] [--from B] [--root R] [--purpose TEXT] [--allow-resume] [--no-preflight]`

- `skills/create-worktree/SKILL.md:4` (argument-hint), minus the internal
  `[--pipeline-id ID]` flag (see "Deliberately DROPPED" below):
  `"<slug> [--prefix P] [--branch-name REF] [--from B] [--root R] [--purpose TEXT] [--pipeline-id ID] [--allow-resume] [--no-preflight]"`

**Doc sentence:** "the simplest form is just a slug ... a worktree directory named
after your project and the slug (for example `/tmp/zskills-my-feature`)."

- `skills/create-worktree/SKILL.md:64`: `"PROJECT_NAME=$(basename \"$MAIN_ROOT\")"`.
- `skills/create-worktree/SKILL.md:68`: path `${WORKTREE_ROOT}/${PROJECT_NAME}-${SLUG}`.
- `skills/create-worktree/SKILL.md:73`: `"\`WORKTREE_ROOT\` comes from \`execution.worktree_root\` in \`.claude/zskills-config.json\`; default \`/tmp\`."` (so `/tmp/<project>-<slug>`).

---

## Typical usage examples

**Doc:** `/create-worktree my-feature` / `... --purpose "..."` / `... --from release-2.0`.

- `--purpose`: `skills/create-worktree/SKILL.md:58`: `"\`--purpose TEXT\` — write \`.worktreepurpose\` with this text."`
- `--from`: `skills/create-worktree/SKILL.md:56` (base branch).
- `--allow-resume`: `skills/create-worktree/SKILL.md:59`: `"permits attach-to-existing-branch that is ahead of base"`.

**Doc sentence:** "The other flags (`--prefix`, `--branch-name`, `--root`) are
mostly used by the skills that call `/create-worktree` internally."

- `skills/create-worktree/SKILL.md:54-57`: these flags control path leaf / branch
  / root; `skills/create-worktree/SKILL.md:48` and `:53` describe the skill-layer
  (internal) ownership of prefix-derived defaults.

---

## Companion skills (R6 — from COMPANIONS.md)

Drawn verbatim-in-relationship from `COMPANIONS.md:78` (create-worktree row):
companions `do`, `fix-issues`, `run-plan`, `commit`, `update-zskills`;
relationship = **"The shared worktree-setup primitive every isolation-using
skill calls."**

- `/do`, `/run-plan`, `/fix-issues` call it — `COMPANIONS.md:78`, and source
  `skills/create-worktree/SKILL.md:23`.
- `/commit` lands worktree work + refuses to clean a worktree with committed
  tracking files — `skills/create-worktree/SKILL.md:100-101`: `"\`.claude/skills/commit/scripts/land-phase.sh\` refuses to clean up a worktree that has git-tracked copies of either."`
- `/update-zskills` configures the worktree machinery — `COMPANIONS.md:96`
  (`update-zskills` "configures and is referenced by nearly every skill") and
  `skills/create-worktree/SKILL.md:73` (`execution.worktree_root` config field).

---

## Arguments table

Each row sourced from the skill body's Arguments section (`skills/create-worktree/SKILL.md:50-60`):

- `slug` — `:52` (`"Must match \`[A-Za-z0-9._-]+\`"`; the doc renders this as "letters, digits, `.`, `_`, `-`").
- `--prefix P` — `:54` (`"adds \`P-\` to branch name and path leaf. Slashes rejected"`).
- `--branch-name REF` — `:55` (`"overrides branch verbatim"`).
- `--from B` — `:56` (`"Default \`main\`"`).
- `--root R` — `:57` (`"override ... stem"`).
- `--purpose TEXT` — `:58` (`"Without this flag, the script does NOT write \`.worktreepurpose\`"`).
- `--allow-resume` — `:59`.
- `--no-preflight` — `:60`.

**Doc sentence:** "Where worktrees are created is set by `execution.worktree_root`
in `.claude/zskills-config.json` (default `/tmp`)."

- `skills/create-worktree/SKILL.md:73`.

**Doc sentence (error behaviour, R3-c plain carve-out):** "exits with an error ...
when the slug is malformed, when the target directory already exists, or when the
branch is in a state that needs your decision — for example, a branch that's
behind the base, or one that's ahead of the base without `--allow-resume`."

- `skills/create-worktree/SKILL.md:84` (code 2): `"Path exists"`.
- `skills/create-worktree/SKILL.md:85` (code 3): `"Poisoned branch (behind base, 0 ahead)"` → doc says "behind the base".
- `skills/create-worktree/SKILL.md:86` (code 4): `"Branch ahead of base without \`--allow-resume\`"`.
- `skills/create-worktree/SKILL.md:87` (code 5): `"bad slug, slash in \`--prefix\`, unknown flag"` → doc says "slug is malformed".

The exit-code *numbers* are deliberately not exposed (R5) — only the plain
behaviour ("exits with an error … that needs your decision") is, because the
codes are caller plumbing the user never reads.

---

## Deliberately DROPPED (R5 — no internals voice; the plan's specific fix)

- **The entire "Two-tier contract / Tier 1 / Tier 2" framing**
  (`skills/create-worktree/SKILL.md:19-27`, `:46-48`, `:53`) — removed entirely.
  "Tier 1"/"Tier 2"/"two-tier" are on the banned-term list
  (`banned-terms.txt:9-10`) and name an internal classification. The genuine
  user-facing distinction it encodes ("other skills call it; you rarely do") is
  preserved in plain words in "What it does."
- **`--pipeline-id` and all its machinery** (`skills/create-worktree/SKILL.md:23`,
  `:46-48`, `:53`, `:96-98`) — dropped from the usage block, the arguments
  table, and the prose. It is required only for the internal bash callers and is
  synthesised automatically for a standalone invocation, so a user never types
  it. The `.zskills-tracked` write and `sanitize-pipeline-id.sh`
  (`skills/create-worktree/SKILL.md:96-98`) are internal side effects and are not
  surfaced.
- **The `## Invocation` bash block** (`skills/create-worktree/SKILL.md:30-44`) —
  the `zskills-resolve-config.sh` sourcing + `$ZSKILLS_SKILLS_ROOT` script call
  is caller plumbing, not a user-typed command.
- **The exit-code table numbers and `## Stdout contract` detail**
  (`skills/create-worktree/SKILL.md:79-92`, `:75-77`) — internal hand-off
  contract; collapsed to the plain "prints the path" + "exits with an error"
  statements.
- **`.worktreepurpose` / `.zskills-tracked` file names and the
  `land-phase.sh` clean-up refusal mechanics** (`skills/create-worktree/SKILL.md:94-101`)
  — surfaced only as the plain `/commit` companion note, not as file-name
  internals.
- **The `## Pointer` to `create-worktree.sh`** (`skills/create-worktree/SKILL.md:17`,
  `:103-105`) — the "thin wrapper around a script" implementation note is dropped;
  the user does not run the script.

---

## Banned-term check

```
grep -nEf docs/reports/doc-rewrite-evidence/banned-terms.txt docs/skills/create-worktree.md
```

Returns no hits (verified: rc=1). No `Tier 1`/`Tier 2`/`two-tier`, no
`materialise`/`sentinel`/`atomic`, no `Phase N`, no design-decision `D[0-9]+`,
no `subagent_type`/`inject-bash-timeout`, no `idempoten*`.
