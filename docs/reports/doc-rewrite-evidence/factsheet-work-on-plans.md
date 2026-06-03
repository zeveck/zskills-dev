# Factsheet — `docs/skills/work-on-plans.md`

Each doc claim paired with the verbatim source line that backs it. Source of
truth: `skills/work-on-plans/SKILL.md` (HEAD). Companion edges cite
`COMPANIONS.md`; routing cites `CLAUDE.md`.

---

## Summary blockquote

**Doc:** "Drive your ready plans as a batch: take the plans queued as ready and run each one with `/run-plan` until it lands."
- `skills/work-on-plans/SKILL.md:17`: "# /work-on-plans N|all [phase|finish] [every SCHEDULE] [now] [continue] [--force] | default <phase|finish> | stop | next — Batch Plan Executor"
- `skills/work-on-plans/SKILL.md:18-19`: "Dispatches `/run-plan <plan> auto [finish]` per entry in the / prioritized ready queue from the monitor dashboard."

**Doc:** "The plan-side counterpart to `/fix-issues` for bugs."
- `skills/work-on-plans/SKILL.md:19-20`: "Mirrors / `/fix-issues` for bugs but operates on plans instead."

---

## What it does

**Doc:** "works through your queue of ready-to-run plans, running each one for you … you give it a count (or `all`), and it runs that many plans from the front of the queue"
- `skills/work-on-plans/SKILL.md:18-19`: "Dispatches `/run-plan <plan> auto [finish]` per entry in the / prioritized ready queue from the monitor dashboard."
- `skills/work-on-plans/SKILL.md:106-107`: "**First token matches `^[0-9]+$` → dispatch path (N).** Set `N` to / that integer."
- `skills/work-on-plans/SKILL.md:107-110`: "**First token is `all` → dispatch path (all).** Set `ALL_MODE=1`; / `N` resolves to the count of `plans.ready` after sync"

**Doc:** "For each plan it picks, `/work-on-plans` runs `/run-plan` to execute it."
- `skills/work-on-plans/SKILL.md:18`: "Dispatches `/run-plan <plan> auto [finish]` per entry"

**Doc:** "By default each plan runs to completion — all of its phases — and lands as a pull request"
- `skills/work-on-plans/SKILL.md:28-30`: "**Default mode is `finish`** … each / dispatch resolves to `/run-plan <slug> auto finish` — one PR per plan."

**Doc:** "If you would rather pace the work one phase per plan instead, add the `phase` token."
- `skills/work-on-plans/SKILL.md:30-31`: "The explicit `phase` token still opts out to phase-pacing."

**Doc:** "When a plan finishes, it drops off the ready queue so it won't be picked up again."
- `skills/work-on-plans/SKILL.md:531-535`: "**Prune on completion (issue #906).** When a dispatched `/run-plan` / reports `status: complete` for a plan, remove that slug from / `plans.ready` … (a merged plan must not linger in `ready`)."

**Doc:** "the plan-side counterpart to `/fix-issues`: where `/fix-issues` drives a backlog of bugs, `/work-on-plans` drives the backlog of plans."
- `skills/work-on-plans/SKILL.md:19-20`: "Mirrors / `/fix-issues` for bugs but operates on plans instead."

**Doc:** "Run bare with no arguments, it just lists the ready queue … without changing anything."
- `skills/work-on-plans/SKILL.md:95-97`: "**Empty `$ARGUMENTS` → no-args read-only mode.** Print the ready / queue listing (see "No-args output format") and exit 0."

**Doc:** "add a plan to it, re-order entries by priority, remove one, or set the default mode new entries inherit."
- `skills/work-on-plans/SKILL.md:66-69`: "/work-on-plans add <slug> [pos] / … rank <slug> <pos> / … remove <slug> / … default <phase|finish>"

**Doc:** "If a plan in the queue points at a plan file that no longer exists, `/work-on-plans` stops and tells you rather than silently skipping it"
- `skills/work-on-plans/SKILL.md:492-494`: "**Fail loud on unknown slug.** Never silently skip a queued slug / whose plan file is missing — the user needs to remove it from the / queue."

---

## Usage / Arguments

**Doc usage block** (`N|all [phase|finish] [every SCHEDULE] [now] [continue] [--force]`, `add`, `rank`, `remove`, `default`, `stop`, `next`):
- `skills/work-on-plans/SKILL.md:62-71`: the verbatim Arguments synopsis block.

**Doc:** "`N` — Run this many plans from the front of the ready queue"
- `skills/work-on-plans/SKILL.md:106-107`: "**First token matches `^[0-9]+$` → dispatch path (N).** Set `N` to / that integer."

**Doc:** "`all` — Run every plan in the ready queue"
- `skills/work-on-plans/SKILL.md:107-110`: "**First token is `all` → dispatch path (all).** … `N` resolves to the count of `plans.ready`"

**Doc:** "`phase` — Run one phase per plan instead of running each to completion"
- `skills/work-on-plans/SKILL.md:128`: "- `phase` → `MODE_OVERRIDE=phase` (mutex with `finish`)"
- `skills/work-on-plans/SKILL.md:30-31`: "The explicit `phase` token still opts out to phase-pacing."

**Doc:** "`finish` — Run each plan to completion (this is the default)"
- `skills/work-on-plans/SKILL.md:129`: "- `finish` → `MODE_OVERRIDE=finish` (mutex with `phase`)"
- `skills/work-on-plans/SKILL.md:28`: "**Default mode is `finish`**"

**Doc:** "`continue` — If one plan fails, skip it and keep going instead of stopping"
- `skills/work-on-plans/SKILL.md:130`: "- `continue` → `CONTINUE_ON_FAILURE=1`"

**Doc:** "`every SCHEDULE` — Run on a recurring schedule … each fire runs the count"
- `skills/work-on-plans/SKILL.md:131-133`: "- `every` followed by a SCHEDULE expression → `SCHEDULE` captured; / register a recurring cron … **Composes with / `N`/`all`** — the count is carried into the cron prompt."
- `skills/work-on-plans/SKILL.md:85-86`: "Each fire drains the / captured `N` plans — NOT unconditional `all`"

**Doc:** "`now` — With `every`, run immediately as well as scheduling"
- `skills/work-on-plans/SKILL.md:134-136`: "- `now` → `RUN_NOW=1`. With `every`, dispatch this invocation AND / schedule. Without `every`, `now` is a no-op (the default is to run)."

**Doc:** "`--force` — Take over a recurring schedule currently owned by another session"
- `skills/work-on-plans/SKILL.md:137`: "- `--force` → `FORCE=1` (take over a foreign live schedule; relevant / only with `every`)."
- `skills/work-on-plans/SKILL.md:538-541`: "Different-session non-stale entries refuse / unless `--force`."

**Doc:** "`next` — Print the active schedule (read-only)"
- `skills/work-on-plans/SKILL.md:98-99`: "**First token is `next` → next read-only mode.** Print the active / schedule line and exit 0."

**Doc:** "`stop` — Cancel any active schedule"
- `skills/work-on-plans/SKILL.md:101-103`: "**First token is `stop` → cancel any active `/work-on-plans` / cron**"

**Doc:** "`phase` and `finish` are mutually exclusive — pass at most one."
- `skills/work-on-plans/SKILL.md:139-141`: "If both `phase` and `finish` appear, error: / > … `phase` and `finish` are mutually exclusive."

**Doc:** "The mode you pass applies to that batch only; it does not change the saved mode on individual queue entries or the queue-wide default"
- `skills/work-on-plans/SKILL.md:159-161`: "**The mode override is per-batch only.** It does NOT mutate the saved / `mode` on individual ready-queue entries or the top-level / `default_mode` in `monitor-state.json`."

**Doc:** "A count and a schedule combine: `/work-on-plans 1 finish every 1h now` runs one plan now and one more every hour"
- `skills/work-on-plans/SKILL.md:21-25`: "The count / (`N`/`all`) **composes** with `every SCHEDULE` + `now`: each recurring / fire drains the captured count of plans … `/work-on-plans 1 every 1h finish now` runs one plan now and one per / hour thereafter"

**Doc:** "A bare `every SCHEDULE` with no leading count runs the whole queue on each fire."
- `skills/work-on-plans/SKILL.md:87-90`: "(Bare / `every SCHEDULE` with no leading count still registers a recurring / schedule; absent an explicit count it drains `all` per fire, as / before.)"

**Doc:** "runs at the top level of your session so it can hand each plan to `/run-plan`; it cannot run as a dispatched sub-task, and will tell you so"
- `skills/work-on-plans/SKILL.md:46-57`: "`/work-on-plans` runs at the parent session and dispatches `/run-plan` / via the **Skill tool** … If `Agent` (or `Task`) is **not** in your tool list, you are running / as a subagent. Print: / > `/work-on-plans` must run at top-level to dispatch /run-plan / and **exit 2.**"

---

## Subcommands

**Doc:** "`add <slug> [pos]` … slug must start with a letter and contain only lowercase letters, digits, and hyphens … optional 1-based position … with no position it is appended"
- `skills/work-on-plans/SKILL.md:66`: "/work-on-plans add <slug> [pos]"
- Prior doc line 37 (carried, body-consistent): slug rule `^[a-z][a-z0-9-]*$`; SKILL body slug-normalization at `skills/work-on-plans/SKILL.md:93` "(slugs come pre-lowercased per Shared Schemas)" and `:498-500` "inline / one-line `tr '[:upper:]_' '[:lower:]-'`".

**Doc:** "`rank <slug> <pos>` … Move a plan already in the ready queue to a new 1-based position"
- `skills/work-on-plans/SKILL.md:67`: "/work-on-plans rank <slug> <pos>"

**Doc:** "`remove <slug>` … Removing a slug that isn't there exits cleanly"
- `skills/work-on-plans/SKILL.md:68`: "/work-on-plans remove <slug>"
- (Idempotent-remove wording carried from prior doc line 45; consistent with fail-loud applying only to *queued* slugs whose file is missing, `:492-494`.)

**Doc:** "`default <phase|finish>` … Set the default mode that newly added queue entries inherit. It does not change the mode already saved on existing entries."
- `skills/work-on-plans/SKILL.md:69`: "/work-on-plans default <phase|finish>"
- `skills/work-on-plans/SKILL.md:489-491`: "Phase 3's `default <phase|finish>` / subcommand is the only path that mutates `default_mode`."
- `skills/work-on-plans/SKILL.md:159-161`: per-batch override "does NOT mutate the saved / `mode` on individual ready-queue entries".

**Doc:** "`stop` … Cancel the active recurring schedule."
- `skills/work-on-plans/SKILL.md:101-103`: "**First token is `stop` → cancel any active `/work-on-plans` / cron**"

---

## Typical usage examples

**Doc:** `/work-on-plans 1 finish every 1h now` (drain one per hour)
- `skills/work-on-plans/SKILL.md:24-25`: "`/work-on-plans 1 every 1h finish now` runs one plan now and one per / hour thereafter"
- USAGE_MAP.md:118-120: "`Run /work-on-plans $N <mode> every $SCHEDULE now` (49)" / "typical: a count + mode (`finish`) + cron."

**Doc:** `/work-on-plans all finish`, `/work-on-plans 3`
- USAGE_MAP.md:117-120: typical shape is "a count + mode (`finish`) + cron."

---

## Companion skills (R6 — from COMPANIONS.md)

**Doc:** "`/run-plan` — the executor `/work-on-plans` calls for each plan."
- COMPANIONS.md:98: "`work-on-plans` | `run-plan` (executor) … | Drives the plan-ready queue; dispatches `/run-plan` per plan."

**Doc:** "`/plans` — the read-only plan dashboard. Check `/plans` first"
- COMPANIONS.md:88: "`plans` | `run-plan`, `work-on-plans`, `zskills-dashboard` … | The plan-catalog index; `/work-on-plans` and `/run-plan` consume the queue it builds."

**Doc:** "`/draft-plan` — produces the plan files in the first place."
- COMPANIONS.md:81: "`draft-plan` | `run-plan` (next step) … | Produces a plan file `/run-plan` executes"
- CLAUDE.md "Which skill for which input": "Plan file already drafted, ready to execute | `/run-plan <path>`"

**Doc:** "`/zskills-dashboard` — the interactive status UI … reads the same ready queue"
- COMPANIONS.md:99: "`zskills-dashboard` | `work-on-plans` … | The status UI for in-flight pipelines; reads what `/work-on-plans` and others write."

**Doc:** "`/fix-issues` — the bug-backlog counterpart. Same batch-and-schedule shape, but it drives issues"
- COMPANIONS.md:98: "`work-on-plans` | `run-plan` (executor), `fix-issues` …"
- `skills/work-on-plans/SKILL.md:19-20`: "Mirrors / `/fix-issues` for bugs but operates on plans instead."

---

## Tips & Gotchas

**Doc:** "Recurring `finish`-mode schedules require intervals of at least an hour; `phase` mode has no minimum."
- `skills/work-on-plans/SKILL.md:536-537`: "**Finish-mode SCHEDULE ≥ 1h.** `/work-on-plans every <s> finish` / refuses sub-hour intervals. Phase mode has no minimum."

**Doc:** "A recurring schedule remembers the mode it was registered with — to change it, `stop` the schedule and register a new one."
- `skills/work-on-plans/SKILL.md:518-523`: "**Schedule mode-capture invariant.** `every` resolves / `schedule_mode` once at registration … Each cron / fire dispatches with the captured mode … To / change mode, `stop` and re-register."

**Doc:** "`/work-on-plans` does not choose how each plan lands — `/run-plan` decides that from its own configuration."
- `skills/work-on-plans/SKILL.md:502-503`: "**No landing-mode flag passed to `/run-plan`.** It resolves its / own from arg/config (currently `pr`)."

---

## R5 — internals stripped (present in prior doc / SKILL, NOT in rewrite)

- `monitor-state.json` (SKILL :18, :178; prior doc :3, :93-94) — replaced with "ready queue".
- `default_mode` (SKILL :29, :161; prior doc :49, :53) — replaced with "the queue-wide default".
- `flock -x` / lock file (SKILL :42, :193, :511-517; prior doc :93) — dropped (per-line banned-term, RUBRIC :157).
- `plans.ready` / JSON schema (SKILL :22, :222-225) — replaced with "ready queue".
- PR/issue refs `post-#988`, `#906` (SKILL :28, :75, :524, :531; prior doc :3, :53) — dropped (RUBRIC :164).
- "Phase 1 / Phase 3 / Phase 5" (SKILL :37-42, :489) — dropped (RUBRIC :151).
- `os.replace` / atomic rename (SKILL :219-220) — dropped (RUBRIC :150).
- `__DEFAULT__` sentinel (SKILL :418) — dropped (RUBRIC :149).
- `Skill tool` / `Agent`/`Task` tool plumbing (SKILL :46-57) — raised to "runs at the top level … cannot run as a dispatched sub-task" (observable behavior + the verbatim message the user reads, RUBRIC :84).
