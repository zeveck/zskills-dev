# Fact sheet — `docs/skills/run-plan.md`

Every factual claim in the rewritten `docs/skills/run-plan.md`, paired with the
verbatim source line that backs it. Format:
`doc sentence → skills/run-plan/SKILL.md:LINE: "<verbatim quoted text>"`.
Subcommand-file citations use `skills/run-plan/subcommands/<file>.md:LINE`;
companion/routing claims cite `COMPANIONS.md`; usage examples cite `USAGE_MAP.md`.

---

## Summary line + "What it does" section

- `/run-plan` executes a drafted plan one phase at a time →
  skills/run-plan/SKILL.md:6: "Execute the next phase of a plan: parse status, dispatch implementation"

- For each phase: read the plan, find the next incomplete phase, implement it, verify, update progress, land →
  skills/run-plan/SKILL.md:17: "Orchestrates plan-driven development. Reads a plan document, identifies the"

- Identifies the next incomplete phase →
  skills/run-plan/SKILL.md:18: "next incomplete phase, dispatches implementation in a worktree, verifies with a"

- Implements in an isolated worktree →
  skills/run-plan/SKILL.md:7: "  in a worktree, verify via a separate agent, update progress, write the"

- Verification is a separate agent →
  skills/run-plan/SKILL.md:18: "next incomplete phase, dispatches implementation in a worktree, verifies with a"

- Updates the plan's progress tracking →
  skills/run-plan/SKILL.md:19: "separate agent, updates progress tracking, writes a persistent report, and"

- Writes a report →
  skills/run-plan/SKILL.md:19: "separate agent, updates progress tracking, writes a persistent report, and"

- Lands the change to main →
  skills/run-plan/SKILL.md:20: "optionally auto-lands to main. Can self-schedule for recurring runs to work"

- Point it at a plan and it runs just the next incomplete phase (phase auto-detect) →
  skills/run-plan/SKILL.md:33: "- **phase** (optional) — specific phase, e.g. `4a`. If omitted, auto-detect"

- The plan file is the kind `/draft-plan` produces →
  COMPANIONS.md:53: "- **`/draft-plan` → `/run-plan`** are sequential, not alternatives:"

- `finish` runs all remaining phases in order →
  skills/run-plan/SKILL.md:35: "- **finish** (optional) — run ALL remaining phases sequentially until the"

- Stops the moment a phase fails verification or hits a conflict →
  skills/run-plan/SKILL.md:45: "  safety rails. If any phase fails verification or hits a conflict,"

- Each phase still gets full verification, testing, and safety checks →
  skills/run-plan/SKILL.md:44: "  fatigue. Each phase still gets full verification, testing, and all"

- `finish auto`: each phase runs as its own separate turn →
  skills/run-plan/SKILL.md:40: "  alias): each phase runs as its own cron-fired top-level turn (~5 min"

- Fresh context per phase; no late-phase fatigue →
  skills/run-plan/SKILL.md:43: "  prior phase lands. Preserves fresh context per phase — no late-phase"

- First phase starts right away; each later phase begins after the prior lands →
  skills/run-plan/SKILL.md:42: "  phase runs immediately; each subsequent phase is scheduled after the"

- Can run remaining phases autonomously →
  skills/run-plan/SKILL.md:20: "optionally auto-lands to main. Can self-schedule for recurring runs to work"

- Multi-phase plans run autonomously →
  skills/run-plan/SKILL.md:21: "through multi-phase plans autonomously."

- Protected-main common shape is a PR / feature branch →
  skills/run-plan/SKILL.md:90: "1. Explicit argument wins: `pr` or `direct` in $ARGUMENTS"

- A phase's dependencies are checked before running; if a prerequisite isn't done it stops and names it →
  skills/run-plan/SKILL.md:1265: "- **Dependency not met:** stop cleanly, report which dependency. If `every`,"

## "Typical usage" section

- `finish auto` (plan path + finish auto) is the dominant real shape →
  USAGE_MAP.md:100: "- `Run /run-plan <plan-file> finish auto` (337) — the dominant shape"

- `auto every <schedule>` is a real shape →
  USAGE_MAP.md:101: "- `Run /run-plan <plan-file> auto every <schedule>` (70)"

- Typical: a plan path + `finish auto`, often cron-chunked →
  USAGE_MAP.md:104: "- → typical: a plan path + `finish auto`, often cron-chunked."

- `/run-plan plans/X.md` alone runs the next phase interactively →
  skills/run-plan/SKILL.md:33: "- **phase** (optional) — specific phase, e.g. `4a`. If omitted, auto-detect"

## "Companion skills" section

- `/draft-plan` is the prior step; produces the plan `/run-plan` executes →
  COMPANIONS.md:94: "| `run-plan` | `draft-plan` (prior step), `refine-plan`, `draft-tests`, `commit`, `land-pr`, `verify-changes`, `work-on-plans`, `create-worktree`, `fix-issues` | Executes a drafted plan; lands phases via `/land-pr`; `/refine-plan` corrects drift. |"

- `/draft-plan` and `/run-plan` are sequential, not alternatives →
  COMPANIONS.md:53: "- **`/draft-plan` → `/run-plan`** are sequential, not alternatives:"

- `/refine-plan` corrects drift mid-execution →
  COMPANIONS.md:94: "| `run-plan` | `draft-plan` (prior step), `refine-plan`, `draft-tests`, `commit`, `land-pr`, `verify-changes`, `work-on-plans`, `create-worktree`, `fix-issues` | Executes a drafted plan; lands phases via `/land-pr`; `/refine-plan` corrects drift. |"

- `/run-plan` refreshes the plan with `/refine-plan` on detected staleness →
  skills/run-plan/SKILL.md:1022: "     dependency was implemented. Want me to refresh it with `/refine-plan`?\""

- `/draft-tests` is the test-spec sibling of the plan-authoring family →
  COMPANIONS.md:82: "| `draft-tests` | `draft-plan`, `refine-plan`, `run-plan`, `do`, `quickfix`, `create-worktree` | Test-spec authoring sibling of the plan-authoring family. |"

- `/verify-changes` is the per-phase verification gate →
  skills/run-plan/SKILL.md:1195: "1. **Dispatch an overall verification agent.** In worktree mode, run"

- `/verify-changes` is run over all phases combined at the end of a finish run →
  skills/run-plan/SKILL.md:1191: "In `finish` mode, after ALL phases complete their per-phase implement →"

- `/land-pr` lands each phase as a PR; never typed directly →
  COMPANIONS.md:86: "| `land-pr` | `commit`, `do`, `quickfix`, `fix-issues`, `run-plan`, `draft-plan`, `refine-plan`, `research-and-plan`, `draft-tests` | **Internal** (`user-invocable: false`). Dispatched BY its callers; never typed directly. |"

- `/work-on-plans` drives a queue and dispatches `/run-plan` per plan →
  COMPANIONS.md:98: "| `work-on-plans` | `run-plan` (executor), `fix-issues`, `create-worktree`, `update-zskills` | Drives the plan-ready queue; dispatches `/run-plan` per plan. |"

## "Arguments" section

- `plan-file` is required, e.g. `plans/FEATURE_PLAN.md` →
  skills/run-plan/SKILL.md:32: "- **plan-file** (required) — path to plan, e.g. `plans/FEATURE_PLAN.md`"

- `phase` is a specific phase (e.g. `4a`); omitted → auto-detect next incomplete →
  skills/run-plan/SKILL.md:33: "- **phase** (optional) — specific phase, e.g. `4a`. If omitted, auto-detect"

- `finish` runs all remaining phases until complete →
  skills/run-plan/SKILL.md:35: "- **finish** (optional) — run ALL remaining phases sequentially until the"

- `status` shows progress, read-only, no agents dispatched →
  skills/run-plan/SKILL.md:69: "- **status** — show plan progress: all phases, their status, what's next,"

- `status` dispatches no agents, no approval gate →
  skills/run-plan/SKILL.md:70: "  and what's blocked. Read-only — no agents dispatched, no approval gate."

- `auto` runs without approval prompts / human-review pauses →
  skills/run-plan/SKILL.md:51: "- **auto** (optional) — run autonomously: skip scope-confirmation /"

- `auto` skips the between-phase pause, drift, staleness, verifier-fail review →
  skills/run-plan/SKILL.md:52: "  approval prompts and human-review pauses (between-phase pause, drift"

- `auto` runs unattended →
  skills/run-plan/SKILL.md:53: "  findings, staleness check, verifier-fail review) so the skill can run"

- `auto` auto-merges the resulting PR (in PR mode) →
  skills/run-plan/SKILL.md:54: "  without an attended user, AND pass `--auto` to per-phase `/land-pr`"

- The PR is the thing auto-merged →
  skills/run-plan/SKILL.md:55: "  dispatches (auto-merge the resulting PR). The `finish auto` composite"

- `pr` lands each phase via a PR on a feature branch →
  skills/run-plan/SKILL.md:417: "branch in PR mode; commit on main in cherry-pick/direct mode). Only the"

  (PR landing-mode anchor:)
  skills/run-plan/SKILL.md:103: "  LANDING_MODE=\"pr\""

- `direct` is a landing mode that works directly on main →
  skills/run-plan/SKILL.md:85: "- `direct` (case-insensitive) — direct landing mode"

  (direct = work on main, no PR; behavior anchors:)
  skills/run-plan/SKILL.md:278: "- `/run-plan plans/FEATURE_PLAN.md direct` — direct mode, work on main"
  skills/run-plan/SKILL.md:388: "phases. Cherry-pick and direct modes commit bookkeeping on main directly, so"

- `every SCHEDULE` runs on a recurring schedule via cron →
  skills/run-plan/SKILL.md:57: "- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:"

- `every` accepts intervals and time-of-day forms →
  skills/run-plan/SKILL.md:58: "  - Accepts intervals: `4h`, `2h`, `30m`, `12h`"

- `now` runs immediately; with `every`, runs now and schedules →
  skills/run-plan/SKILL.md:67: "- **now** (optional) — run immediately. When combined with `every`, runs"

- In cherry-pick/direct mode there is no PR, so `auto` only removes pauses →
  skills/run-plan/SKILL.md:388: "phases. Cherry-pick and direct modes commit bookkeeping on main directly, so"

  (auto's PR auto-merge is scoped to per-phase /land-pr dispatches, which only
  PR mode performs:)
  skills/run-plan/SKILL.md:54: "  without an attended user, AND pass `--auto` to per-phase `/land-pr`"

- Landing mode resolves: explicit arg → config default → cherry-pick fallback →
  skills/run-plan/SKILL.md:90: "1. Explicit argument wins: `pr` or `direct` in $ARGUMENTS"

- Config default is `execution.landing` →
  skills/run-plan/SKILL.md:91: "2. Config default: read `.claude/zskills-config.json` `execution.landing` field"

- Fallback is cherry-pick →
  skills/run-plan/SKILL.md:92: "3. Fallback: `cherry-pick`"

- cherry-pick = work in a worktree, cherry-pick result to main →
  skills/run-plan/SKILL.md:101: "LANDING_MODE=\"cherry-pick\"  # default"

  (cherry-pick is the default worktree landing path; edge-case anchor describing
  the worktree cherry-pick flow:)
  skills/run-plan/SKILL.md:1273: "  worktree.\" Do not attempt to cherry-pick nothing. In auto mode, invoke"

- `direct` is rejected when `main_protected: true`; use `pr` →
  skills/run-plan/SKILL.md:173: "      echo \"ERROR: direct mode is incompatible with main_protected: true. Use pr mode or change config.\""

- `finish` and `every` are mutually exclusive →
  skills/run-plan/SKILL.md:47: "  **`finish` and `every` are mutually exclusive.** `finish auto` schedules"

- `finish auto` schedules its own per-phase runs; `every` sets a recurring cron →
  skills/run-plan/SKILL.md:48: "  its own ~5-min one-shot crons internally. `every N` schedules a recurring"

## "Subcommands" section

- `status` shows every phase + status (Done/In Progress/Next/Blocked), what's next, blocked deps →
  skills/run-plan/subcommands/stop-next-status.md:48: "4. Present a progress table:"

  (status values shown in the rendered table:)
  skills/run-plan/subcommands/stop-next-status.md:57: "   | 4c — Smooth Nonlinear | Next ← |"

- `status` is read-only, no agents, no work done →
  skills/run-plan/subcommands/stop-next-status.md:68: "6. **Exit.** Read-only — no agents dispatched, no work done."

- `status` shows the schedule when one is active →
  skills/run-plan/subcommands/stop-next-status.md:65: "5. If a cron is active, also show the schedule:"

- `stop` cancels the active schedule for this session and releases claims →
  skills/run-plan/subcommands/stop-next-status.md:101: "2. Delete ALL whose prompt starts with `Run /run-plan` using `CronDelete`"

- `stop` releases the plan's claims →
  skills/run-plan/subcommands/stop-next-status.md:121: "3.5. **Release all run-plan plan AND issue claims (W2a.4 site 1 + W3.4;"

- `stop` takes precedence over every other argument →
  skills/run-plan/SKILL.md:71: "- **stop** — cancel any existing `/run-plan` cron and exit. **Takes"

- `next` reports the next fire as relative and absolute time →
  skills/run-plan/subcommands/stop-next-status.md:90: "     Use `date +%Z` for the timezone. Show both relative and absolute:"

- `next` says so when no schedule is active →
  skills/run-plan/subcommands/stop-next-status.md:93: "   - If none found: `No active /run-plan cron in this session.`"

- `now` (standalone, no plan file) triggers the active schedule's plan immediately →
  skills/run-plan/subcommands/stop-next-status.md:72: "If `$ARGUMENTS` is just `now` (no plan-file, no phase, no every):"

- `now` runs the phase immediately without waiting →
  skills/run-plan/subcommands/stop-next-status.md:76: "3. If found: extract the cron's prompt to get the plan-file, auto, and"

- The schedule stays active after `now` →
  skills/run-plan/subcommands/stop-next-status.md:78: "   ask for confirmation — `now` IS the confirmation. The cron stays active."

## "Examples" section

(all verbatim from the source skill's examples + the prior catalog doc's examples block,
each independently backed by an Arguments line above; representative anchors:)

- `/run-plan plans/X.md finish auto` →
  skills/run-plan/SKILL.md:35: "- **finish** (optional) — run ALL remaining phases sequentially until the"

- `/run-plan plans/X.md auto every 4h now` →
  skills/run-plan/SKILL.md:67: "- **now** (optional) — run immediately. When combined with `every`, runs"

## "Common Patterns" / "Tips & Gotchas"

- Schedule is session-scoped — ends when the session ends →
  skills/run-plan/SKILL.md:66: "  - Cron is session-scoped — dies when the session dies"

- A failing phase stops the run; auto mode tries one fix cycle →
  skills/run-plan/SKILL.md:1262: "- **Phase fails verification:** auto mode tries one fix cycle (dispatch fix"

- Dependency not met → stop cleanly and report which one →
  skills/run-plan/SKILL.md:1265: "- **Dependency not met:** stop cleanly, report which dependency. If `every`,"
