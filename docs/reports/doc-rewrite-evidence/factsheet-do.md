# Fact sheet — `docs/skills/do.md`

Every factual claim in the rewritten `docs/skills/do.md`, paired with the
verbatim source line that backs it. Format:
`doc sentence → skills/do/SKILL.md:LINE: "<verbatim quoted text>"`.
Mode-file citations use `skills/do/modes/<file>.md:LINE`.

---

## "What it does" section

- `/do` runs one small task end to end (research, make, verify, land) →
  skills/do/SKILL.md:15: "Execute small, ad-hoc tasks with structured research, verification, and"

- It's for work that doesn't warrant `/run-plan` or `/fix-issues` ceremony →
  skills/do/SKILL.md:18: "phases) or `/fix-issues` (batch bug fixing)."

- Documentation, examples, refactors, content updates are the fit →
  skills/do/SKILL.md:5: "  Lightweight task dispatcher for ad-hoc work: documentation, examples,"

- `/do` checks the task is a good fit before proceeding (triage) →
  skills/do/SKILL.md:448: "runs a triage gate to decide whether `/do` is the right skill for this"

- Redirects to `/draft-plan` when the task spans more than one concept →
  skills/do/SKILL.md:478: "| Verbs include any of: `add feature`, `redesign`, `rewrite`, `refactor across` | REDIRECT → `/draft-plan` |"

- Redirects to `/draft-plan` when ≥3 files are named →
  skills/do/SKILL.md:477: "| ≥ 3 distinct files explicitly named in description | REDIRECT → `/draft-plan` |"

- Redirects to `/run-plan` when the description references an existing plan file →
  skills/do/SKILL.md:481: "| References an existing plan file under `$ZSKILLS_PLANS_DIR` | REDIRECT → `/run-plan` |"

- Asks the user when the description is too vague →
  skills/do/SKILL.md:480: "| Vague verbs alone: `improve`, `fix it`, `update`, `clean up` (no concrete object) | REDIRECT → ask user |"

- `--force` overrides a redirect →
  skills/do/SKILL.md:73: "- **--force** (optional) — bypass triage redirect and review reject. Persists"

- A fresh review agent sanity-checks the plan before work →
  skills/do/SKILL.md:524: "short inline plan and dispatches one fresh Agent to review it. This phase"

- Verification matches the kind of change →
  skills/do/SKILL.md:927: "Verification intensity matches the change type (from Phase 1):"

- Code changes run the full test suite →
  skills/do/SKILL.md:964: "- **Run `$FULL_TEST_CMD`** (resolve via the dual-lane prelude in"

- Code changes get a separate `/verify-changes` pass →
  skills/do/SKILL.md:981: "- **Dispatch a separate verification agent (worktree/direct mode)** running"

- Content-only changes skip the test suite →
  skills/do/SKILL.md:932: "- **Do NOT run tests** — running 4,000+ tests for a markdown edit is"

- Content-only changes get a focused diff review instead →
  skills/do/SKILL.md:934: "- **Dispatch a separate verification agent (worktree/direct mode).** Tell"

- `auto` controls landing, not whether verification runs →
  skills/do/SKILL.md:60: "  Verification (`/verify-changes`) runs on ALL code changes regardless"

- Code changes are always verified →
  skills/do/SKILL.md:1201: "- **All code changes require verification** — worktree/direct mode always"

- The common protected-main shape is a PR via an isolated worktree →
  skills/do/modes/pr.md:3: "Full end-to-end PR flow: create branch, worktree, dispatch agents, open the PR, poll CI, then write the landing marker."

- PR mode runs verification locally before opening the PR →
  skills/do/modes/pr.md:9: "It performs its OWN verification gate (Step A6.5, equivalent to Phase 3) BEFORE handing off to `/land-pr`, then after the PR is created skips to Phase 5 Report."

- PR mode watches CI →
  skills/do/SKILL.md:50: "    poll CI. Matches `execution.landing: \"pr\"`."

- `/do` writes no persistent report file; the commit is the artifact →
  skills/do/SKILL.md:1197: "- **No persistent report files** — `/do` outputs results inline. It does"

- `/do` and `/quickfix` are co-equal peers, differ in where work happens →
  COMPANIONS.md:48: "- **`/quickfix` vs `/do` are PEERS, not tiers.** Same lifecycle; same `/land-pr`"

- `/quickfix` edits in place on main; `/do` isolates the work →
  COMPANIONS.md:50: "  lives* — `/quickfix` does `git checkout -b` on main; `/do` uses a worktree."

- `/quickfix` in-place on main is valid only when main is unprotected →
  COMPANIONS.md:32: "| One-commit PR — edit in-place on main, no worktree (only valid when `main_protected: false`) | `/quickfix` |"

- Pick by project policy, not task size →
  COMPANIONS.md:51: "  Pick by **project policy**: `main_protected: true` → `/do`; otherwise either."

## "Typical usage" section

- Free-text description is the common form →
  USAGE_MAP.md:109: "- → typical: a free-text description, optional `--force`, optional cron."

- `Run /do Make sure docs are up to date` is a real typical invocation →
  USAGE_MAP.md:106: "- `Run /do Make sure docs are up to date` (128)"

- `/do Sort the screenshots in session-sequence-snapshots` is a real example →
  skills/do/SKILL.md:134: "- `/do Sort the screenshots in session-sequence-snapshots`"

- `/do Update the presentation auto` is a real example →
  skills/do/SKILL.md:125: "- `/do Update the presentation auto` — description + auto (direct + verify + push)"

- `/do Add dark mode to editor pr` is a real example →
  skills/do/SKILL.md:139: "- `/do Add dark mode to editor pr`"

- `/do Check for broken links in examples every 12h now` is a real example →
  skills/do/SKILL.md:138: "- `/do Check for broken links in examples every 12h now`"

- A description alone runs immediately →
  skills/do/SKILL.md:71: "- **now** (optional) — run immediately. When combined with `every`, runs"

- `every SCHEDULE` with `now` schedules and runs straight away →
  skills/do/SKILL.md:68: "  - With `now`: schedules AND runs immediately"

## "Companion skills" section

- `/quickfix` is the peer skill (relationship) →
  COMPANIONS.md:79: "| `do` | `quickfix` (peer), `draft-plan`, `create-worktree`, `verify-changes`, `commit`, `land-pr`, `run-plan`, `fix-issues`, `doc`, `update-zskills` | Peer of `/quickfix`; triage may redirect to `/draft-plan`/`/run-plan`; lands via `/land-pr`; runs `/verify-changes`. |"

- `/draft-plan` is the redirect target for too-big tasks →
  skills/do/SKILL.md:505: "| `/draft-plan` | `Triage: redirecting to /draft-plan. Reason: <reason>` | `This task spans more than one concept; /draft-plan will research and decompose it. Run \\`/draft-plan <description>\\` instead, or re-invoke with --force to bypass.` |"

- `/run-plan` is the redirect target for plan-file references →
  skills/do/SKILL.md:506: "| `/run-plan` | `Triage: redirecting to /run-plan. Reason: <reason>` | `This task references an existing plan file. Run \\`/run-plan <plan-path>\\` to execute it, or re-invoke with --force to bypass.` |"

- `/fix-issues` is for issue-batch work →
  skills/do/SKILL.md:30: "| Batch bug fixing (N issues) | `/fix-issues N` |"

- `/verify-changes` is the verification gate on code changes →
  skills/do/SKILL.md:983: "  test coverage audit, `npm run test:all`, manual verification if UI, fix"

- `/land-pr` is dispatched by `/do` in PR mode for the PR lifecycle →
  skills/do/SKILL.md:1205: "- **PR mode CI runs through `/land-pr`** — `/do pr` dispatches the"

- `/land-pr` polls CI and drives a fix-cycle on failure →
  skills/do/SKILL.md:1206: "  shared `/land-pr` skill, which polls CI and (on failure) drives a"

- `/land-pr` is never typed directly (internal) →
  COMPANIONS.md:86: "| `land-pr` | `commit`, `do`, `quickfix`, `fix-issues`, `run-plan`, `draft-plan`, `refine-plan`, `research-and-plan`, `draft-tests` | **Internal** (`user-invocable: false`). Dispatched BY its callers; never typed directly. |"

- `/cleanup-merged` runs after a landing skill merges a PR →
  COMPANIONS.md:76: "| `cleanup-merged` | `commit`, `do`, `fix-issues`, `quickfix`, `work-on-plans`, `land-pr` | Run AFTER any landing skill merges a PR, to catch the local clone up. |"

## "Arguments" section

- `description` is required, natural language →
  skills/do/SKILL.md:44: "- **description** (required) — what to do, in natural language"

- `worktree` isolates and cherry-picks back after verification →
  skills/do/SKILL.md:47: "  - **worktree** — isolate in `/tmp/<project>-do-<slug>/`, cherry-pick"

- `direct` works on main in place, no landing step →
  skills/do/SKILL.md:51: "  - **direct** — work on main in place, no landing step. Matches"

- `pr` = named worktree + feature branch, push, create PR, poll CI →
  skills/do/SKILL.md:49: "  - **pr** — named worktree + feature branch, push, create PR to main,"

- Landing flags are mutually exclusive and override config →
  skills/do/SKILL.md:45: "- **landing flags** (optional, mutually exclusive) — override the"

- `auto` lands autonomously; PR auto-merge, worktree cherry-pick+push, direct push →
  skills/do/SKILL.md:57: "  PR mode: opens PR + requests auto-merge via `--auto` to `/land-pr`,"

- `auto` worktree-mode cherry-picks to main and pushes →
  skills/do/SKILL.md:59: "  mode: cherry-picks to main, pushes. Direct mode: pushes main."

- `every SCHEDULE` self-schedules recurring runs via cron →
  skills/do/SKILL.md:64: "- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:"

- `every` accepts intervals (`4h`, `12h`) →
  skills/do/SKILL.md:65: "  - Accepts intervals: `4h`, `2h`, `30m`, `12h`"

- `every` accepts time-of-day (`day at 9am`, `weekday at 9am`) →
  skills/do/SKILL.md:66: "  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`"

- `now` runs immediately; with `every`, runs now and schedules →
  skills/do/SKILL.md:72: "  immediately AND schedules. Without `every`, `now` is the default behavior."

- `--force` bypasses triage redirect and review reject →
  skills/do/SKILL.md:73: "- **--force** (optional) — bypass triage redirect and review reject. Persists"

- `--rounds N` is max review/refine cycles, default 1, 0 skips review with warning →
  skills/do/SKILL.md:84: "- **--rounds N** (optional) — max review/refine cycles (default 1; `0` skips"

- `--no-claim` treats every bare `#N` as a mere mention →
  skills/do/SKILL.md:75: "- **--no-claim** (optional) — treat every bare `#N` in the description as a"

- No flag → mode from `execution.landing`; cherry-pick→worktree, pr→pr, direct→direct →
  skills/do/SKILL.md:54: "    (`cherry-pick` → worktree, `pr` → pr, `direct` → direct, missing"

- Missing config → default direct →
  skills/do/SKILL.md:55: "    config → direct.)"

- `direct` is rejected when `main_protected: true` →
  skills/do/SKILL.md:845: "  echo \"ERROR: direct mode is incompatible with main_protected: true. Use pr, worktree, or change config.\""

- Leading `#N` / `Fix #N …` is claim-position and acquires a claim →
  skills/do/SKILL.md:81: "  to #340\") and you do NOT want /do to halt or warn on it. Claim-positioned"

- Stray `#N` warns; foreign-held stops; `--no-claim` silences →
  skills/do/SKILL.md:77: "  normally STOPS when the description references an issue currently held"

## "Subcommands" section

- `stop` cancels crons; bare → all, query → matching →
  skills/do/SKILL.md:86: "- **stop** — cancel `/do` cron(s). Bare `/do stop` → all crons."

- Targeted stop uses fuzzy description matching →
  skills/do/SKILL.md:160: "3. **Fuzzy match:** check if the user's description words appear in the"

- `next` checks next fire time; bare → all, query → targeted →
  skills/do/SKILL.md:88: "- **next** — check next fire time. Bare → all. With query → targeted."

- `now` triggers a cron immediately; multiple → asks →
  skills/do/SKILL.md:97: "- `now [query]` — meta-command: trigger immediately. Bare → all/ask. With query → targeted."

## "Examples" section

(all verbatim from the source examples block)

- `/do Add example models for Integrator and Derivative blocks` →
  skills/do/SKILL.md:133: "- `/do Add example models for Integrator and Derivative blocks`"

- `/do Refactor color constants in main.css worktree` →
  skills/do/SKILL.md:135: "- `/do Refactor color constants in main.css worktree`"

- `/do Make sure docs are up to date every day at 9am` →
  skills/do/SKILL.md:137: "- `/do Make sure docs are up to date every day at 9am`"

- `/do next` shows all scheduled tasks →
  skills/do/SKILL.md:140: "- `/do next` — all scheduled tasks"

- `/do stop Check docs` cancels a specific task →
  skills/do/SKILL.md:143: "- `/do stop Check docs` — cancel specific task"

## "Common Patterns" / "Tips & Gotchas"

- `--rounds 0` skips review with a warning →
  skills/do/SKILL.md:527: "**Skip when `--rounds 0`.** If `$ROUNDS -eq 0`: print to stderr"

- Quoted descriptions are taken verbatim and bypass subcommand detection →
  skills/do/SKILL.md:90: "**Detection:** If `$ARGUMENTS` starts with a quoted string (`\"...\"`),"

- Quoted description skips meta-command detection →
  skills/do/SKILL.md:91: "the quoted text is the description — skip meta-command detection entirely."

- `--force` and `--rounds N` persist verbatim into the cron prompt →
  skills/do/SKILL.md:767: "   **Persistence of `--force` and `--rounds N`:** these flags are preserved verbatim in the cron prompt. A `/do <task> --force every 4h` produces a cron prompt of `Run /do <task> --force every 4h now`, so every cron fire bypasses triage and review. Intentional: setting `--force` on a recurring task means the user wants the bypass on every fire."

- PR mode runs the same local verification gate as the other modes →
  skills/do/modes/pr.md:236: "`/do pr` runs the SAME local verification gate as its worktree/direct"
