# Skill Usage Map (bounded sample)

> **Single-user-biased sample — informs typical-usage examples, never
> deprioritizes a peer skill the sample happens to avoid (R7).** This is one
> developer's transcript history, not a census of how zskills is used in the
> wild. Use it to pick *realistic argument shapes* for "typical usage"
> examples. Do **not** use a low count to under-serve a peer doc — peers read
> as peers (R7). A skill with 30 invocations and a skill with 300 get
> equal-quality docs.

## Method (bounded, no whole-file loads)

Source: `~/.claude/projects/-workspaces-zskills/*.jsonl` — **107 files, ~728 MB**.
Never loaded whole; streamed with `grep -o` and reduced with `sort | uniq -c`.
Two signals were extracted:

- **All-token mentions** — every `/(zs:)?<skill>` token anywhere in the
  transcripts. This is *noisy*: it counts mentions inside plan files quoted in
  context, skill bodies loaded into the orchestrator, prose discussion, and
  example blocks — NOT just invocations. Treat it as an upper-bound popularity
  proxy, not an invocation count.
- **Cron-fire form `Run /<skill> …`** — the strongest *real-invocation* signal,
  because CLAUDE.md's cron-fired-prompt convention means a turn starting with
  `Run /<skill>` IS an invocation. Argument shapes are mined from this form.

Reproduce:

```bash
SKILLS=$(ls skills/ | tr '\n' '|' | sed 's/|$//')
# all-token mentions (noisy popularity proxy)
grep -ohE '(^|[^a-zA-Z/])/(zs:)?('"$SKILLS"')\b' ~/.claude/projects/-workspaces-zskills/*.jsonl \
  | grep -oE '/(zs:)?('"$SKILLS"')\b' | sed 's#/zs:#/#' | sort | uniq -c | sort -rn
# cron-fire invocations (clean signal)
grep -ohE 'Run /(zs:)?('"$SKILLS"')\b' ~/.claude/projects/-workspaces-zskills/*.jsonl \
  | sed 's#Run /zs:#Run /#' | sort | uniq -c | sort -rn
```

---

## Cron-fire invocations (clean real-invocation signal)

| Skill | `Run /<skill>` fires |
|---|---|
| `/fix-issues` | 3010 |
| `/run-plan` | 1555 |
| `/do` | 1090 |
| `/qe-audit` | 684 |
| `/update-zskills` | 299 |
| `/work-on-plans` | 181 |
| `/verify-changes` | 163 |
| `/briefing` | 43 |
| `/cleanup-merged` | 19 |
| `/draft-plan` | 15 |
| `/quickfix` | 12 |
| `/land-pr` | 10 |
| `/plans` | 7 |
| `/refine-plan` | 2 |
| `/commit` | 2 |
| `/session-report` | 1 |
| `/investigate` | 1 |

**Never observed in the `Run /<skill>` cron form:** `/create-worktree`,
`/doc`, `/draft-tests`, `/fix-report`, `/manual-testing`, `/research-and-go`,
`/research-and-plan`, `/zskills-dashboard`. (Expected — several are dispatched
*by* other skills, not cron-fired, e.g. `create-worktree`, `land-pr`,
`manual-testing`, `fix-report`; and the research/dashboard skills are
interactively typed. Absence here means "not cron-driven by this user," NOT
"unimportant" — R7.)

## All-token mentions (noisy upper-bound popularity proxy)

Every skill appears at least 600 times somewhere in the transcripts — i.e.
**zero skills are truly "never observed."** Ordering only:
`do` > `land-pr` > `fix-issues` > `run-plan` > `draft-plan` > `quickfix` >
`update-zskills` > `commit` > `refine-plan` > `verify-changes` >
`work-on-plans` > `qe-audit` > `fix-report` > `cleanup-merged` >
`draft-tests` > `research-and-plan` > `plans` > `zskills-dashboard` >
`research-and-go` > `investigate` > `briefing` > `session-report` >
`create-worktree` > `manual-testing` > `doc`. (Counts span 33000 → 616; the
high end is dominated by skills whose bodies are large and frequently loaded
into context, so this is popularity-shaped, not invocation-accurate — prefer
the cron table above for "how is it actually called.")

---

## Common argument shapes (from the cron-fire form)

These are the realistic invocation shapes to anchor "typical usage" examples on.
`N`/`Nm`/`Nh` denote numbers normalized out of the sample.

**`/fix-issues`** (by far the most-driven skill):
- `Run /fix-issues N auto dashboard every Nm now` (979) — the dominant shape
- `Run /fix-issues N auto dashboard pr every Nm` (352)
- `Run /fix-issues N dashboard auto every Nm now` (215)
- `Run /fix-issues N auto every Nh now` (122) / `... every Nh` (114)
- `Run /fix-issues N auto pr every Nm now` (65)
- → typical: a count, `auto`, optionally `dashboard`, optionally `pr`, on a cron.

**`/run-plan`:**
- `Run /run-plan <plan-file> finish auto` (337) — the dominant shape
- `Run /run-plan <plan-file> auto every <schedule>` (70)
- `Run /run-plan plans/<NAME>.md finish auto` / `docs/plans/<NAME>.md …` (many)
- → typical: a plan path + `finish auto`, often cron-chunked.

**`/do`:**
- `Run /do Make sure docs are up to date` (128)
- `Run /do Check broken links every Nh now` (126)
- `Run /do <task> --force every Nh now` (127)
- → typical: a free-text description, optional `--force`, optional cron.

**`/qe-audit`:**
- `Run /qe-audit every Nh now` (281)
- `Run /qe-audit confirm recent fixes every Nh` (120)
- `Run /qe-audit now` (100)
- → typical: bare or with a focus phrase, usually on a cron.

**`/work-on-plans`:**
- `Run /work-on-plans $N <mode> every $SCHEDULE now` (49)
- `Run /work-on-plans N finish every Nh now` (37)
- → typical: a count + mode (`finish`) + cron.

**`/verify-changes`:**
- `Run /verify-changes branch tracking-id=$TRACKING_ID` (122)
- → typical: a scope (`branch`/`worktree`/`last N`), often dispatched.

**`/update-zskills`:** mostly appears as guidance prose
(`Run /update-zskills to configure, or edit .claude/...`, 72) rather than a
clean invocation — treat its cron count as soft.

Lower-volume skills (`/commit`, `/refine-plan`, `/session-report`,
`/investigate`, `/plans`, `/cleanup-merged`, `/briefing`) have too few
cron fires to derive a stable argument shape from this sample — pull their
"typical usage" examples from the skill's own `argument-hint` + body and
`COMPANIONS.md`, not from this map (R7: do not under-write them for low count).
