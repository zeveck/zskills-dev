# Handoff: `plans/CANARY_FAILURE_INJECTION.md` — for the agent about to run it

You are picking up a well-rested repository. The previous session finished
restoring features destroyed by commit `faab84b`, hardened the pipeline,
and behaviorally validated three canaries (7, 10, 11). Your job is
`CANARY_FAILURE_INJECTION` — a 5-phase PR-mode plan that builds
`tests/test-canary-failures.sh`, the **shareability gate** that external
users will run to verify their zskills install catches known silent-
failure modes. Scope is strict: **lock in CURRENT behavior; no bug
fixes**. Any surprise reproducer → file a follow-up issue, do NOT mix a
fix into the same phase.

Read the whole handoff before your first command. It will save you hours.

## 0. Launch command

```
/run-plan plans/CANARY_FAILURE_INJECTION.md finish auto pr
```

Don't pass `every` — `finish auto` handles chunked scheduling internally.
Landing mode `pr` is explicit (the plan's frontmatter calls for it —
5 separate PRs).

## 1. State of the repo at handoff

- Branch: `main` at `7dda8f2` (one unpushed commit on top of merged PR #19).
  Push before starting OR let the CANARY_FAILURE_INJECTION Phase 1 PR
  land on top — either is fine; just be aware.
- Remotes: `dev` and `origin` both point at `github.com/zeveck/zskills-dev`.
  Treat them as the same. The skill hardcodes `origin` for `git push`
  and `gh pr create`; works transparently.
- Tests: `bash tests/run-all.sh` passes **235/235** (this is your
  baseline — the plan's Phase 1 AC adds 18, so after Phase 1 expect
  253. Final total after Phase 5 is 312 with installed-copy present or
  302 with it skipped).
- Worktrees: only `main`. No stragglers.
- Tracking markers: the `.zskills/tracking/` dir has markers from the
  prior RESTORE run, CANARY7, CANARY10, and CANARY11. These do NOT
  block CANARY_FAILURE_INJECTION because pipeline-scoping filters by
  the current TRACKING_ID. Leave them alone.
- Recent commits worth knowing (see `git log --oneline -10` for full
  context):
  - `7dda8f2` docs(canary10): record validation run — unpushed
  - `8a0273e` PR #19 squash merge (CANARY10 lands canary/canary10.txt)
  - `412b097` wildcard `.gitignore` for ephemerals
  - `d1b96bb` **inline TZ warning** in /run-plan Phase 5b/5c
    (read this commit — it explains gotcha #1 below)

## 2. Critical gotchas (the things that burned me)

Ranked by pain. Read each one before you hit the situation.

### 2.1 Cron TZ — do not "fix" the skill's `date +%M`

**Symptom:** one-shot cron never fires. `CronList` shows it scheduled
for next year.

**Cause:** the `CronCreate` tool reads cron expressions in
**system-local TZ (UTC here)**, not the user-preferred ET. The skill
bash uses plain `date +%M` (system-local); do NOT override with
`TZ=America/New_York date +%M` — that produces an expression anchored
in ET, which CronCreate interprets as UTC, often in the past → pinned
to next year.

**Verify before you schedule:** compute cron in UTC (system-local).
Inline warning now in `skills/run-plan/SKILL.md` Phase 5b step 0b and
Phase 5c "How to schedule the next cron". Read it.

**If you scheduled wrong and cron never fires:** `/run-plan stop` (or
`CronDelete <id>`), reschedule with system-local time. The user can
also manually paste the cron prompt as a message if you prefer to
bypass cron entirely — that still exercises Step 0 idempotent re-entry.

### 2.2 `⚠️ Flag` halt-check grep is substring-based

**Symptom:** `/run-plan` Phase 6 pre-landing checklist halts with
`HALTED: /verify-changes flagged scope violations in <report>` even
though the Scope Assessment table has all "Yes" rows.

**Cause:** the halt-check bash is `grep -q "⚠️ Flag" "$VERIFY_REPORT"`
— a whole-file substring search. If the verify agent's prose
describes the marker ("if any row has `⚠️ Flag`..."), that prose
triggers the halt.

**Mitigation:** when you dispatch `/verify-changes` or any verify
agent, include this instruction verbatim in the prompt:

> IMPORTANT: use the literal string `⚠️ Flag` ONLY inside Scope
> Assessment table cells for rows you actually flag. Do NOT write
> `⚠️ Flag` in prose (checklist descriptions, explanations,
> summaries). If you need to describe the mechanism in prose, call
> it "the violation marker" or "the flag column". The /run-plan
> halt check greps the literal string from the whole report; any
> prose occurrence triggers a spurious halt.

The five CANARY10 turns' verify agents got this right — zero matches.
Replicate that.

**A known follow-up** is in the plan's "Follow-up issues" section to
narrow the grep to table-cell form. Don't fix it now — CANARY_FAILURE_
INJECTION is scope-locked.

### 2.3 Step-marker cleanup must be one at a time

**Symptom:** the project-specific hook blocks this:

```bash
rm -f .zskills/tracking/step.run-plan.$TRACKING_ID.{implement,verify,report,land}
```

with `BLOCKED: Cannot recursively delete tracking directory`.

**Cause:** brace expansion looks enough like recursive deletion for the
hook's regex to fire.

**Workaround:** delete individually:

```bash
rm -f .zskills/tracking/step.run-plan.$TRACKING_ID.implement
rm -f .zskills/tracking/step.run-plan.$TRACKING_ID.verify
rm -f .zskills/tracking/step.run-plan.$TRACKING_ID.report
rm -f .zskills/tracking/step.run-plan.$TRACKING_ID.land
```

Or use `scripts/clear-tracking.sh` if it fits your scope.

### 2.4 Verify reports leak into worktrees and block `land-phase.sh`

**Symptom:** `land-phase.sh` refuses to remove a worktree with
`ERROR: Worktree <path> is not clean — cannot safely remove. Current
dirty state: ?? reports/verify-worktree-<name>.md`

**Cause:** verify agents write their report inside the worktree's
`reports/` dir. The wildcard `.gitignore` catches the names — but
`land-phase.sh` explicitly checks `git status -s` and considers
any untracked file dirty.

**Mitigation:** before calling `land-phase.sh`, `rm <worktree>/reports/verify-worktree-*.md`.
The halt check in Phase 6 has already consumed the report by that
point; deletion is safe.

### 2.5 `.landed` marker status string

**Symptom:** `land-phase.sh` errors with
`ERROR: .landed marker does not say 'status: landed' or 'status: pr-ready'`

**Cause:** doc drift. `CLAUDE.md` says write `status: full`; the script
wants `status: landed` for cherry-pick mode, `status: pr-ready`/
`pr-ci-failing`/`conflict` for PR mode, etc.

**Mitigation:** for cherry-pick landings, use `status: landed`. For
PR-mode landings, use the status matrix in `skills/run-plan/SKILL.md`
Phase 6 PR-mode section.

CANARY_FAILURE_INJECTION is **PR mode**. You'll be writing `status: landed`
when the PR merges, `status: pr-ready` when CI passes but auto-merge
isn't enabled, etc. The skill already handles this.

### 2.6 Wildcard ephemeral `.gitignore` is in place

Commit `412b097` added `.test-*.txt`, `.*-results.txt`, `.*-results-*.txt`,
`.*-diff.txt`, `.*-diff-*.txt`. So agents can freely write
`.test-results.txt` and similar variants without cluttering `git status`
on main.

The proper /tmp migration is queued (prompt in my session; user has the
command). Don't do that migration in this plan — out of scope.

## 3. PR mode specifics (CANARY_FAILURE_INJECTION is PR mode)

The plan's frontmatter banner: **Landing mode: PR** — each phase is its
own PR. 5 phases → 5 PRs.

- Branch naming: `feat/canary-failure-injection` (config default
  `branch_prefix=feat/`, plan-slug `canary-failure-injection`).
  Wait — actually in PR mode with chunked finish, **one branch per plan**
  (all phases accumulate on the same branch, squash-merged as one PR
  per the skill's "One branch per plan" rule).

  **BUT** the plan's frontmatter says "All phases land as separate PRs"
  which conflicts with "one branch per plan". Resolve by reading what
  the skill actually does: in `finish auto pr`, skill Phase 5c schedules
  a next-phase cron AFTER each phase's commits land on the feature
  branch. The skill's Phase 6 push+PR step runs ONCE at the end of the
  last phase per the chunked flow (Phase 5b triggers, then Phase 6
  pushes and creates ONE PR).

  **This means CANARY_FAILURE_INJECTION's plan-stated "5 separate PRs"
  conflicts with the skill's `finish auto pr` semantics** — the skill
  will create ONE PR for all 5 phases, not 5 PRs. You have two options:

  1. **Trust the plan's intent**: run each phase as its own standalone
     `/run-plan plans/CANARY_FAILURE_INJECTION.md <N> auto pr` (no
     `finish`), which does one phase + one PR. Five separate
     invocations. The plan author likely meant this.
  2. **Trust the skill's chunked behavior**: run `finish auto pr` and
     get one PR covering all 5 phases. Cleaner for the repo, but
     conflicts with the plan's frontmatter claim.

  **I recommend option 1** — respect the plan's stated intent. Five
  invocations, five PRs. Each phase is self-contained by design
  (Phase 1 scaffolds; 2-5 extend). Between invocations, `git pull
  --ff-only dev main` to sync local main with the merged PR.

  Flag this ambiguity to the user before you start. They may want to
  clarify the plan.

- Repo has auto-merge enabled (validated during CANARY10). `gh pr
  merge --auto --squash` works; the skill handles it.
- CI workflow `.github/workflows/test.yml` triggers on `pull_request:
  branches: [main]`. Ran in 9s during CANARY10 — fast. Expect similar
  CI time for these phases.
- `gh` is authed as `zeveck` with `repo` + `workflow` scopes.

## 4. Plan-specific risk areas

I read the plan carefully. Specific things the implementing and verify
agents should watch:

### 4.1 The self-referential invariant #6 (Phase 3)

Invariant #6 in `scripts/post-run-invariants.sh` does a whole-file
`grep -q` for the in-progress sentinel character (yellow-circle emoji)
in the plan file. The plan file itself contains that character in the
Progress Tracker table rows (transiently, during execution).

- **Plan's own protection (good):** the plan's prose and fixtures use
  phrases like "yellow-circle emoji" or "the in-progress sentinel"
  INSTEAD of the literal character. This is why invariant #6 won't
  false-positive on the plan file at end-of-plan.
- **Agent must preserve this discipline:** any implementation, verify,
  or bookkeeping agent you dispatch that writes to the plan file or
  to `reports/plan-canary-failure-injection.md` must NOT include the
  emoji character except in Progress Tracker rows (same rule the plan
  follows).
- **Fixtures** `tests/fixtures/canary/plan-with-sentinel.md` and
  `plan-without-sentinel.md` are expected to contain / lack the
  character — those are legitimate test inputs, passed via
  `--plan-file` flag. They're not scanned whole-repo.

### 4.2 Phase 2's ls-remote exit code discrimination (Case C)

Case C sets origin URL to `file:///nonexistent/...` to force ls-remote
rc=128. Make sure the fixture doesn't accidentally create the path.
The test asserts the SCRIPT handles rc=128 correctly — it must NOT
treat "origin unreachable" as "branch absent".

### 4.3 Phase 3 invariant #7 Case C (squash-merge divergence)

The fixture uses `git commit-tree` to create a commit with the same
tree but different SHA as a squash-merge would. This is the legitimate
case where local main has commits absent from origin/main but the tree
is identical (we just saw this exact scenario in CANARY10!). Invariant
#7 is WARN (rc=0), not FAIL. The test asserts rc=0 + the specific WARN
substring.

### 4.4 Phase 4's `REPO_ROOT` override for block-agents

Important subtlety: the hook `hooks/block-agents.sh.template` reads
`$REPO_ROOT/.claude/zskills-config.json`. Tests MUST override
`REPO_ROOT` env var to point at a fixture dir, NOT the real canary
repo root. Otherwise tests read/write the live config.

### 4.5 Phase 4's auto-fallback test is semantic-versioned

The test asserts current behavior: when `min_model: auto` and
transcript has no `claude-*` entry, the hook falls back to Sonnet as
the floor. If someone later changes the fallback (e.g., to Opus), this
test must update in the SAME PR — don't silently "fix" the test. Plan
Phase 4 Acceptance Criteria explicitly calls this out.

### 4.6 Phase 5's installed-copy skip

`skills/commit/SKILL.md` has canonical source; `.claude/skills/commit/SKILL.md`
is the installed mirror. Phase 5 tests both. If the mirror is absent
(fresh clone, no `/update-zskills` run), emit one explicit SKIP pass
with message, NOT a silent pass. Critical distinction.

On the current repo state, the mirror IS present (I mirrored for Phase H
earlier). Final test count should be 77 passed (not 67).

## 5. Validation baselines you can reference

If something looks wrong during your run, here are known-good
reference points from this session:

- **CANARY7 PASSED** 2026-04-16 — chunked finish auto E2E. See
  `plans/CANARY7_CHUNKED_FINISH.md` validation history.
- **CANARY10 PASSED** 2026-04-16 — PR mode E2E. See
  `plans/CANARY10_PR_MODE.md` validation history. PR #19 still visible.
- **CANARY11 PASSED** 2026-04-16 — LLM scope judgment. See
  `plans/CANARY11_SCOPE_VIOLATION.md` validation history.
- **RESTORE complete** — all 8 phases landed earlier in 2026-04-16.
  See `reports/plan-restore-chunked-execution.md`.

The following sub-tests are locked in by the suite you're about to
build, so they validate themselves transitively:

- `tests/test-phase-5b-gate.sh`: 10 tests on the Phase 5b self-
  rescheduling backoff state machine.
- `tests/test-scope-halt.sh`: 6 tests on Phase H's halt logic.
- `tests/test-skill-invariants.sh`: 27 tests on restored anchors.
- `tests/test-hooks.sh`: 177 tests including 14 new pipeline-scoping +
  parser cases.

Plus `tests/test-port.sh` (4) and `tests/test-briefing-parity.sh` (11).
Total 235 pre-CANARY_FAILURE_INJECTION.

## 6. Agent-behavior guidance

When dispatching sub-agents during CANARY_FAILURE_INJECTION phases:

- **Implementation agents**: give them the verbatim phase text from
  the plan (extract to `/tmp/phase-<N>-text.md`). The plan is
  well-specified — trust it. Any deviation should trigger STOP +
  report back, not silent adaptation.
- **Verify agents**: same prompt pattern as CANARY10 (see the
  dispatches earlier in that plan's run for format). Key instruction:
  keep `⚠️ Flag` out of prose (see §2.2).
- **Trust but verify**: per my memory file, sub-agent reports are
  hypotheses. After every impl agent returns, spot-check at least one
  claim (grep for the anchor, read the commit, etc.) before dispatching
  the verify agent.
- **Model**: `.claude/zskills-config.json` has `"min_model": "auto"`
  — the hook will enforce Sonnet-or-better via the transcript read.
  Don't pass `model: "haiku"` to Agent dispatches.
- **Scope discipline (sacred for this plan)**: each phase's commit
  touches only its declared files. If mid-implementation an agent
  discovers a needed change outside the declared file list, STOP.
  This is the faab84b regression-prevention discipline the previous
  session's Phase H was built to enforce — you're literally running
  the plan that locks in that defense.

## 7. Failure modes you might hit (and how)

- **"Branch feat/canary-failure-injection already exists on origin"**:
  stale state from a previous run attempt. `git push --delete origin
  feat/canary-failure-injection` then retry. Or resume from the
  existing branch if the prior run made partial progress.
- **CI fails on the Phase 1 PR**: most likely cause is the scaffold
  doesn't properly emit `Results: N passed, M failed` in a form
  `tests/run-all.sh` aggregates. Check the aggregator regex in
  `tests/run-all.sh` (should be `/^Results: \d+ passed, \d+ failed/`
  or similar).
- **Invariant #6 firing on the plan file itself**: you wrote the
  literal emoji somewhere outside the Progress Tracker. Grep the plan
  for the character, find the intruder, replace with prose.
- **Auto-merge fails with "required reviews"**: the repo's branch
  protection may require code owner review for some paths. Plan line
  43 says to ensure branch protection permits auto-merge. If it
  doesn't, the PR sits with `status: pr-ready` and someone approves
  manually. Skill's state machine handles this — don't panic.

## 8. When you're done

After Phase 5 lands:
- Run `bash tests/run-all.sh` on main — expect 312 total (or 302 if
  installed copy of /commit is absent).
- `git log --oneline -10` — 5 new squash-merge commits (one per PR).
- `plans/CANARY_FAILURE_INJECTION.md` Progress Tracker all ✅ with SHAs.
- `reports/plan-canary-failure-injection.md` exists with the summary
  required by Phase 5's last work item.
- Optionally: add a "Validation history" entry to CANARY_FAILURE_
  INJECTION plan file itself (pattern: see CANARY7/10/11).

Report back to the user with:
- Final test count
- Any follow-up issues filed (the plan's "Follow-up issues" section
  lists candidates — you may file new ones you discover)
- Confidence assessment against the plan's stated "shareability gate"
  goal

## 9. What NOT to do

- **Do not** fix bugs you surface. File issues. This is explicit
  plan policy (line 20-22).
- **Do not** use `git add .` / `git add -A`. The generic hook blocks
  these anyway. Stage by name.
- **Do not** `git checkout -- <file>`. The generic hook blocks this.
  To undo changes, edit manually.
- **Do not** weaken tests to make them pass. If a test fails in a
  surprising way, that's data — report, don't mask.
- **Do not** use `TZ=America/New_York date` in cron expressions (§2.1).
- **Do not** skip verification steps for speed. The previous session
  took ~5 hours to do all this carefully; a rushed run of a 5-phase
  plan with 77 tests would be worse than no run.

Good luck. Ping the user if anything surprises you — they're watching
the run and would rather intervene than have you paper over a real issue.
