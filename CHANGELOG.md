# Changelog

## 2026-04-21

### Major
- `/create-worktree` skill + `scripts/create-worktree.sh` — unifies the five
  worktree-creation sites across `/run-plan` (cherry-pick + PR modes),
  `/fix-issues` (PR mode), and `/do` (PR + worktree modes) behind one
  well-tested script. Owns prefix-derived path, optional `--branch-name`
  override, optional pre-flight prune+fetch+ff-merge, `worktree-add-safe.sh`
  call with TOCTOU-race remap, sanitised `.zskills-tracked` write, and
  `.worktreepurpose` write. `--pipeline-id <id>` is required — silent
  env-var fallback removed (caught latent bug where callers' canonical
  pipeline IDs weren't reaching tracking).
- `/do`: honors `execution.landing` in zskills-config (same pattern as
  `/run-plan` and `/fix-issues`). `LANDING_MODE` now resolves via explicit
  flag (`pr`/`direct`/`worktree`) → config → fallback `direct`. Config
  `cherry-pick` maps to worktree-mode.

### Minor
- Hook `block-unsafe-generic.sh`: redacts heredoc bodies and
  `git commit -m|--message` / `gh pr|issue create|comment --body|--title`
  arg values before destructive-op scans. Stops false-positives on prose
  that mentions banned patterns (commit messages, PR bodies).
- `scripts/create-worktree.sh` `--no-preflight`: when `--from` is not
  passed, BASE now defaults to the main-repo's current branch (was:
  hardcoded `main`). Restores `/do` worktree-mode's pre-migration base-
  branch semantic.
- `scripts/clear-tracking.sh`: recurses into per-pipeline subdirs; runs
  post-clear residual assertion.
- `/run-plan`, `/verify-changes`: resolve `testing.full_cmd` from config
  via three-case decision tree (config → use; test-infra-exists → fail;
  no-infra → skipped + explicit report note). No more hardcoded
  `npm run test:all`.

## 2026-03-29

### Major
- `/research-and-plan`: mechanical verification gate ensures `/draft-plan` is
  actually used — 3 layers: explicit prohibition, grep for Plan Quality section,
  verification agent audit. Past failure: agents skipped `/draft-plan` 3 times,
  producing plans with 10+ CRITICAL issues each time.
- `/research-and-plan`: max 3 concurrent `/draft-plan` agents with
  dependency-ordered batching. Prevents container overload.
- `/update-zskills` (renamed from `/setup-zskills`): auto-clone from GitHub when portable assets not found
  locally. Auto-detect project settings (test commands, dev server, project
  name) from package.json, Cargo.toml, Makefile, CI configs — no blocking
  prompts. Sensible defaults for new/early-stage projects.
- Report format across `/run-plan`, `/verify-changes`, `/fix-report`: single
  checkbox per item with verification instructions underneath. Replaces the
  dual table + detail card pattern that caused double-counting in viewers.
- `/run-plan`: newest phases prepended at top of reports (not appended at
  bottom). The reader's question is always "what needs my attention?" —
  that's the newest phase.
- `/briefing verify`: sign-off dashboard with viewer URLs, not ASCII checkbox
  replicas. Groups by report with section summaries. Worktrees needing
  verification flagged as unusual (suggests incomplete skill run).

### Minor
- `/research-and-plan`: `auto` flag skips decomposition confirmation checkpoint
- `/research-and-go`: explicitly passes `auto` to `/research-and-plan`
- `/fix-issues`: orchestrator may bundle related issues (same component, same
  root cause) into one worktree beyond N count
- `/fix-issues`: Phase 1 enforcement — complete ALL sync steps before Phase 2
- `/briefing`: Z Skills update check in summary/report modes
- `/briefing`: "present verbatim" enforcement with past-failure reference
- `/draft-plan`: skip user research checkpoint when running as subagent
- `/update-zskills`: no AskUserQuestion — ask naturally in conversation
- `/run-plan`: phase-prefixed IDs (P4b-1 not #1) to avoid collisions
- `/run-plan`: one item per verifiable thing, avoid literal `[ ]` in
  description text (renders as phantom checkbox in viewers)

## 2026-03-27

Initial public release. 20 skills (17 core + 3 block-diagram add-on),
13 CLAUDE.md guardrail rules, safety hooks, session logging, helper scripts.
