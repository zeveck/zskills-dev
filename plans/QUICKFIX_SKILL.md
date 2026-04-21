---
title: /quickfix Skill — Low-Ceremony Branch+Commit+PR from Main
created: 2026-04-19
status: complete
completed: 2026-04-21
---

# Plan: /quickfix Skill — Low-Ceremony Branch+Commit+PR from Main

## Overview

`/quickfix` ships in-flight edits in the main working tree as a PR, with no
worktree. No existing skill handles branch+commit+PR in main checkout:

| Skill | Entry state | Worktree | Agent-dispatch | Makes PR |
|-------|-------------|----------|----------------|----------|
| `/commit pr` | Already on feature branch with commits | No | No | Yes |
| `/do pr` | On main, no work done yet | Yes (fresh) | Yes | Yes |
| `/fix-issues pr` | Starts from GitHub issue list | Yes (per-issue) | Yes | Yes |
| **`/quickfix`** | **On main with in-flight edits** (or clean+description) | **No** | **Optional fallback** | Yes |

**Seven locked-in architectural decisions:**

1. **Coexists with `/do`.** `/quickfix` picks up dirty-tree edits in main; `/do pr` branches fresh in a worktree.
2. **Dual-mode auto-detected.** Dirty tree → user-edited. Clean tree + description → agent-dispatched. Neither → hard error.
3. **Dirty tree is the INPUT.** Show diff, confirm, proceed. Never stash. Unrelated edits → refuse.
4. **Test gate via `unit_cmd` only.** Pre-flight requires `unit_cmd` set AND (`full_cmd` unset OR `full_cmd == unit_cmd`) so the project hook's transcript check doesn't block our commits.
5. **Fire-and-forget CI.** End at `gh pr create`; print URL; exit.
6. **PR-only.** `execution.landing != "pr"` → hard error pointing to `/commit` or `/do`.
7. **No `.landed` marker.** `/quickfix` has no worktree; PR state is authoritative via `gh pr view`.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1a — Core skill + happy paths | ✅ Done | `948d8a8` | SKILL.md (661 lines, WIs 1.1–1.15 + 1.3.5) + test-quickfix.sh (250 lines, 19 assertions across cases 1–10+14) + run-all.sh registration; 673/673 suite pass, 0 regressions |
| 1b — Guards, hardening, edge cases | ✅ Done | `dd61421` | WI 1.16 pr-URL append + terminal-states doc; WI 1.17 test-quickfix.sh 11→42 cases / 19→50 assertions (load-bearing cases 11/18/19/20/33/34 by number); WI 1.18 run-all.sh reg (carried from 1a); WI 1.19 .claude/skills/quickfix/ byte-identical mirror; 704/704 suite pass |
| 3 — Documentation and cross-skill notes | ✅ Done | `5708525` | CLAUDE_TEMPLATE.md bullet, README.md Ship-row, update-zskills count 18→19 + enum, .claude/skills/update-zskills/ mirror; 704/704 suite (docs-only, 0 regressions) |

**Phase split rationale:** Phase 1 grew to 20 WIs / 25+ tests. 1a = shippable core; 1b = hardening + structural guards. Phase 3 writes docs only after the hardened skill lands.

## Phase 1a — Core Skill + Happy Paths

### Goal

Ship `skills/quickfix/SKILL.md` with the end-to-end flow (pre-flight, mode
detection, slug/branch/tracking, make-the-change both modes, test gate,
commit, push, PR). Add `tests/test-quickfix.sh` with cases 1–10 + 14 and
register in `tests/run-all.sh`. Phase 1a ships the common path.

### Work Items

- [ ] 1.1 — Create `skills/quickfix/SKILL.md` with YAML frontmatter: `name: quickfix`, `disable-model-invocation: true`, `argument-hint: "[<description>] [--branch <name>] [--yes] [--from-here] [--skip-tests]"`, description covering both modes and PR-only behavior. Include an entry self-assertion that greps `$SKILL_SELF` for `disable-model-invocation: true` and exits 1 on mismatch (non-fatal if `$SKILL_SELF` cannot be located — test harness may inject).

- [ ] 1.2 — Argument parser following the bash-regex idiom at `skills/do/SKILL.md:70-92`. Flags: `--branch <name>`, `--yes`/`-y`, `--from-here`, `--skip-tests`. Remainder is DESCRIPTION (trimmed). Empty DESCRIPTION allowed — WI 1.5 decides.

- [ ] 1.3 — Pre-flight config check. Resolve `MAIN_ROOT = $(cd "$(git rev-parse --git-common-dir)/.." && pwd)` first. Fail-fast on: (1) `jq` missing, (2) `gh` missing, (3) `execution.landing != "pr"`, (4) **test-cmd alignment gate** — see below. Single discriminator-keyword stderr per check.

      **WI 1.3 check 4 — test-cmd alignment gate (load-bearing):**
      ```bash
      UNIT_CMD=$(jq -r '.testing.unit_cmd // ""' "$MAIN_ROOT/.claude/zskills-config.json")
      FULL_CMD=$(jq -r '.testing.full_cmd // ""' "$MAIN_ROOT/.claude/zskills-config.json")
      if [ "$SKIP_TESTS" -eq 0 ] && [ -z "$UNIT_CMD" ]; then
        echo "ERROR: /quickfix requires testing.unit_cmd (or pass --skip-tests)." >&2; exit 1
      fi
      if [ -n "$FULL_CMD" ] && [ "$FULL_CMD" != "$UNIT_CMD" ]; then
        echo "ERROR: testing.full_cmd differs from testing.unit_cmd. Project's pre-commit hook checks full_cmd in transcript; align the two or use /commit pr / /do pr." >&2; exit 1
      fi
      ```
      Rationale: `hooks/block-unsafe-project.sh.template:188-229` rejects `git commit` with staged code files unless the transcript contains `FULL_TEST_CMD`.

- [ ] 1.3.5 — Parallel-invocation gate with staleness. Scan `$MAIN_ROOT/.zskills/tracking/quickfix.*/fulfilled.quickfix.*` for `status: started`; if found and marker `date:` is within `STALE_AGE_SECONDS=3600`, exit 1. If older, warn and proceed. `date -d` is GNU-only (acknowledged — Linux-primary).

- [ ] 1.4 — Pre-flight main-ref fetch. Verify on main/master (unless `--from-here`); capture `BASE_BRANCH="$CURRENT_BRANCH"`; `git fetch origin "$BASE_BRANCH"`. **Do NOT `merge --ff-only`** — dirty tree with overlapping paths would abort. Local main may stay stale; we branch from `origin/$BASE_BRANCH`.

- [ ] 1.5 — Mode detection. `DIRTY_FILES = sort -u` of `git diff --name-only HEAD` + `git diff --name-only --diff-filter=D HEAD` + `git ls-files --others --exclude-standard`. See mode-detection truth table in Design. User-edited without description → exit 2 with "user-edited mode requires a description"; neither → exit 2 with usage.

- [ ] 1.6 — Slug derivation per contract below. Reject empty slug or slug with `/` → exit 2.

- [ ] 1.7 — Branch naming: `BRANCH_PREFIX=$(jq -r '.execution.branch_prefix // "quickfix/"' ...)`. Empty prefix allowed (bare slug). `--branch` overrides verbatim.

- [ ] 1.8 — Tracking setup. `PIPELINE_ID=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "quickfix.$SLUG")`. Echo `ZSKILLS_PIPELINE_ID=$PIPELINE_ID` to transcript (tier-2 tracking, per `tests/test-hooks.sh:245`). Write `started` marker at `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.quickfix.$SLUG`. Install EXIT trap that finalizes to `cancelled` (CANCELLED=1), `complete` (rc=0), or `failed` (rc!=0).

- [ ] 1.9 — Branch creation from `MAIN_ROOT`. (1) Local ref collision → exit 2. (2) Remote collision via `git ls-remote --heads origin "$BRANCH"` — non-zero rc → exit 1 (network/auth); non-empty output → exit 2 (branch exists). **Never `|| true`.** (3) `git checkout -b "$BRANCH" "origin/$BASE_BRANCH"` — carries dirty tree across.

- [ ] 1.10 — User-edited mode. Enumerate `MODS` (`git diff --name-only HEAD`), `DELS` (`--diff-filter=D`), `UNTRACKED` (`git ls-files --others --exclude-standard`); `CHANGED_FILES = sort -u $MODS $UNTRACKED`. Show diff + file list. If `YES_FLAG==0`, prompt; `n` → set `CANCELLED=1`, verify-each-step cleanup (`git checkout "$BASE_BRANCH"` && `git branch -D "$BRANCH"`; any failure → exit 6 with manual-recovery guidance), exit 0.

- [ ] 1.11 — Agent-dispatched mode. **Model-layer instruction, not bash** (same pattern as `skills/do/SKILL.md:342-358` — skills can't dispatch agents from bash per CREATE_WORKTREE R-F1). Capture `PRE_HEAD`; dispatch agent with prompt telling it to: `cd $MAIN_ROOT`, implement `$DESCRIPTION`, NOT commit, NOT run tests/builds/linters/formatters, list new untracked files in "done" report, check `agents.min_model`. After return: if `HEAD` moved → exit 5 with cleanup. `DIRTY_AFTER=$(git diff --name-only HEAD)` only (no `ls-files --others` — excludes agent build artifacts per R2-M2); empty → exit 5. Then proceed to WI 1.12.

- [ ] 1.12 — Test gate. If `SKIP_TESTS==1`: warn and skip. Else: `TEST_OUT="/tmp/zskills-tests/$(basename "$MAIN_ROOT")-quickfix-$SLUG"`, `mkdir -p "$TEST_OUT"`, `bash -c "$UNIT_CMD" > "$TEST_OUT/.test-results.txt" 2>&1`. Non-zero → checkout `$BASE_BRANCH` (edits persist), `git branch -D "$BRANCH"`, exit 4.

- [ ] 1.13 — Commit. CLAUDE.md feature-complete discipline inline. Stage: `git add -- "${CHANGED_FILES[@]}"` (reject directories → exit 5), `git add -u -- "${DELS[@]}"`. `COMMIT_MSG="$DESCRIPTION"`. Mode-aware trailer (see Design §Commit Template). **No `--no-verify`.** On commit failure: `git reset HEAD -- .`, checkout `$BASE_BRANCH`, delete branch; each verified (exit 6 if cleanup itself fails).

- [ ] 1.14 — Push. `git push -u origin "$BRANCH"`. **Bare-branch form ONLY** — never `HEAD:main`, never `src:dst`. The refspec strip in `hooks/block-unsafe-generic.sh:215-220` (`PUSH_TARGET="${PUSH_TARGET%%:*}"` followed by main/master gate) means refspec forms can bypass the guard if the right-hand-side is main; the bare form is independently sound. On push failure, branch/commit left intact; user retries manually.

- [ ] 1.15 — PR creation. `PR_TITLE=$(printf '%s' "$DESCRIPTION" | cut -c1-70)`. Build PR body via `<<-EOF` heredoc with **TAB-indented** body (tabs stripped; spaces would render as code block). `gh pr create --base "$BASE_BRANCH" --head "$BRANCH" --title "$PR_TITLE" --body "$PR_BODY"`. Non-zero rc → exit 5 (branch pushed; user creates PR manually). Print URL. No `--watch`, no polling.

### Design & Constraints

**Exit codes.**

| Code | Meaning |
|------|---------|
| 0 | Success (PR created) or user-cancelled confirmation |
| 1 | Config / environment error (landing, gh, jq, not-on-main, fetch failed, unit_cmd unset, full_cmd mismatch, parallel in progress, ls-remote network) |
| 2 | Input error (no edits + no description; user-edited no description; branch exists local/remote; slug empty or contains slash) |
| 4 | Test failure (`unit_cmd` non-zero) |
| 5 | Commit / push / PR-create / agent failure |
| 6 | Cleanup failure — manual intervention needed (a rollback step returned non-zero; repo in intermediate state) |

**Slug derivation contract.**

Pipeline: `tr '[:upper:]' '[:lower:]'` → `sed -E 's/[^a-z0-9]+/-/g'` → trim `-` both ends → `cut -c1-40` → trim trailing `-` again.

| Input | Slug |
|-------|------|
| `Fix README typo!` | `fix-readme-typo` |
| `Fix the broken link in docs/intro.md` | `fix-the-broken-link-in-docs-intro-md` |
| `  Update CHANGELOG  ` | `update-changelog` |
| `---Fix---foo---` | `fix-foo` |
| 41-char input where cut lands on `-` | final `sed 's/-+$//'` strips it |
| `!!!` (no alphanumerics) | `""` → exit 2 |

The final trailing-`-` trim after `cut` is load-bearing: otherwise boundary-at-cut emits `quickfix/fix-foo-`. Slugs NEVER contain `/` (enforced).

**Branch-name contract.**

| `--branch` | `branch_prefix` | Slug | BRANCH |
|------------|-----------------|------|--------|
| (absent) | (absent) | `fix-readme-typo` | `quickfix/fix-readme-typo` |
| (absent) | `"fix/"` | `fix-readme-typo` | `fix/fix-readme-typo` |
| (absent) | `""` | `fix-readme-typo` | `fix-readme-typo` |
| `custom/foo` | (any) | (any) | `custom/foo` (verbatim) |

**Mode detection truth table.**

| DIRTY_FILES empty? | DESCRIPTION | Mode | Action |
|--------------------|-------------|------|--------|
| No  | non-empty | user-edited | pick up dirty tree |
| No  | empty     | — | exit 2 (user-edited requires description) |
| Yes | non-empty | agent-dispatched | dispatch agent |
| Yes | empty     | — | exit 2 (need edits or description) |

**Commit template (mode-aware).** Implementation uses same trailer style as `skills/commit/SKILL.md`; copy the `Co-Authored-By: Claude <model> <noreply@anthropic.com>` line verbatim from that skill (do NOT hardcode a model version — `/commit` is canonical).

- **user-edited:** `$DESCRIPTION` + `🤖 Generated with /quickfix (user-edited)`. **No `Co-Authored-By`** (human authored the edits).
- **agent-dispatched:** `$DESCRIPTION` + `🤖 Generated with /quickfix (agent-dispatched)` + same `Co-Authored-By` trailer as `skills/commit/SKILL.md`. Mode suffix in trailer enables `git log --grep` filtering.

### Acceptance Criteria (Phase 1a)

- [ ] `bash tests/run-all.sh` exits 0 with `test-quickfix.sh` registered.
- [ ] `grep -c 'test-quickfix.sh' tests/run-all.sh` ≥ 1.
- [ ] `grep -q 'disable-model-invocation: true' skills/quickfix/SKILL.md`.
- [ ] `grep -q 'execution.landing == "pr"' skills/quickfix/SKILL.md`.
- [ ] `grep -q 'full_cmd' skills/quickfix/SKILL.md` AND `grep -q 'unit_cmd' skills/quickfix/SKILL.md` (test-cmd alignment gate present).
- [ ] `grep -q 'git push -u origin' skills/quickfix/SKILL.md`.
- [ ] **Structural anti-patterns must be ABSENT:**
  - [ ] `grep -qE 'HEAD:main|HEAD:master' skills/quickfix/SKILL.md` FAILS.
  - [ ] `grep -q -- '--no-verify' skills/quickfix/SKILL.md` FAILS.
  - [ ] `grep -nE '\|\| true' skills/quickfix/SKILL.md` produces NO output.
  - [ ] `grep -qE 'merge --ff-only' skills/quickfix/SKILL.md` FAILS.
- [ ] Manual smoke: throwaway repo + aligned config + mock `gh` + `/quickfix Fix smoke --yes` → branch, commit, PR URL printed.

### Dependencies (Phase 1a)

None. Consumes `scripts/sanitize-pipeline-id.sh`, `.claude/zskills-config.json`, hooks, `jq`, `gh`.

---

## Phase 1b — Guards, Hardening, Edge Cases

### Goal

Harden `skills/quickfix/SKILL.md` against edge cases not covered in 1a:
marker polish (`pr:` field), test harness, structural guards, and the
`.claude/skills/` mirror. Add tests 11–25 plus round-2 additions (26–35).
Four WIs total.

### Work Items

- [ ] 1.16 — Append `pr: $PR_URL` to the fulfillment marker on success (EXIT trap writes `status: complete` automatically). Explicitly do NOT write `.landed`.

- [ ] 1.17 — Create `tests/test-quickfix.sh` with ≥35 cases. Harness: per-case `mktemp -d -t zskills-quickfix.XXXXXX` (under `/tmp/` so `is_safe_destruct` allows cleanup); init repo; bare-remote clone; mock `.claude/zskills-config.json` with aligned `unit_cmd`/`full_cmd`; mock `gh` wrapper on PATH echoing a fake URL. Pattern from `tests/test-hooks.sh:226-254` (`setup_project_test()`). `TEST_OUT` derived from `$(pwd)` inside each case.

- [ ] 1.18 — Register `tests/test-quickfix.sh` in `tests/run-all.sh` (`run_suite "test-quickfix.sh" "tests/test-quickfix.sh"`).

- [ ] 1.19 — Mirror skill source to `.claude/skills/`. **Literal-path idiom only** (load-bearing — `hooks/block-unsafe-generic.sh` `is_safe_destruct` rejects any `rm -r[f]` containing `$`/backtick/glob/tilde):
      ```bash
      cd "$MAIN_ROOT" && rm -rf .claude/skills/quickfix && cp -r skills/quickfix .claude/skills/quickfix
      diff -r skills/quickfix .claude/skills/quickfix
      ```
      Precedent: `plans/RESTRUCTURE_RUN_PLAN.md:184,328,491`. The `cd` is a separate command; the `rm` line contains no `$`. Per MEMORY `feedback_claude_skills_permissions.md`, single `cp -r` (not per-file Edit) to avoid permission storms.

### Design & Constraints (Phase 1b additions)

**Pre-flight is fail-fast.** One error per invocation; user fixing three issues re-runs three times. Matches `/do` and `/commit` feel. No enumerated multi-error reports.

**Error message discipline.** Each gate prints a single-line stderr naming the check and the remediation, with a distinct discriminator keyword (e.g., `requires testing.unit_cmd`, `exists on origin`, `needs either in-flight edits`, `cleanup:`). Tests assert the keyword, not the whole message.

**Tracking contract.** `PIPELINE_ID = quickfix.<slug>` (post-sanitize). Marker path: `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.quickfix.<slug>`. Terminal states: `started` → `complete` | `cancelled` | `failed`. Successful runs append `pr: <URL>`. No step markers. No `.landed`.

**Config reading via `jq`.** Hard pre-flight dependency. Regex against JSON can mismatch on keys appearing in string values (`$schema` URLs, description fields).

**Test harness isolation.** Every case: `mktemp -d` under `/tmp/` + `trap 'rm -rf "$TESTDIR"' RETURN`. The `$`-bearing trap runs inside the test script (not as an agent tool call), so the hook doesn't inspect it — hooks only inspect tool calls.

**Test cases (category summary, ≥35 total).** Implementation enumerates specific cases; this plan specifies categories + load-bearing regression guards. Phase 1a covers cases 1–10 + 14 (registration). Phase 1b covers the rest.

- **Config / environment gates:** landing != pr; gh missing; jq missing; not on main; `unit_cmd` unset; `full_cmd` mismatch; `--skip-tests` bypass.
- **Happy paths:** user-edited mode end-to-end; agent-dispatched mode end-to-end.
- **Slug / branch contract:** derivation examples (table above); `branch_prefix` configured / empty / overridden via `--branch`.
- **Cancel / cleanup / failure:** user answers `n` (cancel); unit_cmd fails (rollback preserves edits); commit-hook failure (cleanup-then-rerun).
- **Load-bearing regression guards (MUST exist by number — these prevent past-seen failures from reappearing):**
  - **Case 11 — push-refspec absence:** `grep -E 'git push [^|]*:' skills/quickfix/SKILL.md` finds NO matches.
  - **Case 18 — `full_cmd` mismatch exits 1** with `full_cmd differently` substring (R-H1 plan-killer regression guard).
  - **Case 19 — `unit_cmd` unset exits 1** with `requires testing.unit_cmd`.
  - **Case 20 — `--skip-tests` bypasses** the `unit_cmd` gate to exit 0.
  - **Case 33 — mirror literal-path idiom:** `grep -E 'rm -rf "\$' skills/quickfix/SKILL.md` returns NO output (R2-H1).
  - **Case 34 — no `|| true` suppression:** `grep -nE '\|\| true' skills/quickfix/SKILL.md` returns NO output (R2-H2).
- **Edge-case behavior:** concurrent-invocation refused (stale > 1h → warn-and-proceed); remote-branch collision; agent no-op detection; agent commits unexpectedly; path with spaces; untracked file included; empty-prefix bare-slug branch; cancel writes `status: cancelled` (not `complete`); cleanup-failure returns exit 6; agent-dispatched includes `Co-Authored-By`, user-edited omits; missing `disable-model-invocation` self-assertion fires; `ls-remote` network failure distinct from "branch exists"; DIRTY_AFTER excludes untracked (R2-M2).

### Acceptance Criteria (Phase 1b)

- [ ] Phase 1a criteria still pass.
- [ ] `bash tests/test-quickfix.sh` exits 0 with ≥35 cases passing.
- [ ] `bash tests/run-all.sh` exits 0.
- [ ] `diff -r skills/quickfix .claude/skills/quickfix` empty (mirror byte-identical).
- [ ] **Structural anti-patterns ABSENT** (stricter re-check of 1a):
  - [ ] `grep -E 'rm -rf "\$' skills/quickfix/SKILL.md` NO output.
  - [ ] `grep -nE '\|\| true' skills/quickfix/SKILL.md` NO output.
  - [ ] `grep -qE 'HEAD:main|HEAD:master' skills/quickfix/SKILL.md` FAILS.
  - [ ] `grep -q -- '--no-verify' skills/quickfix/SKILL.md` FAILS.
  - [ ] `grep -qE '(write|cat >).*\.landed' skills/quickfix/SKILL.md` FAILS.
  - [ ] `grep -E 'git push [^|]*:' skills/quickfix/SKILL.md` NO output.
- [ ] **Behavioral gates present:**
  - [ ] `grep -q 'status: cancelled' skills/quickfix/SKILL.md` (R2-M1).
  - [ ] `grep -q 'exit 6' skills/quickfix/SKILL.md` (R2-H2 cleanup exit).
  - [ ] `grep -q 'stale' skills/quickfix/SKILL.md` (R2-M5 staleness).
  - [ ] `grep -q 'sanitize-pipeline-id.sh' skills/quickfix/SKILL.md`.
  - [ ] `grep -q '/tmp/zskills-tests' skills/quickfix/SKILL.md`.

### Dependencies (Phase 1b)

Phase 1a.

---

## Phase 3 — Documentation and Cross-Skill Notes

### Goal

Make `/quickfix` discoverable. Each edit is grep-verifiable.

### Work Items

- [ ] 3.1 — `CLAUDE_TEMPLATE.md`: add bullet immediately before `- \`/do Add dark mode. pr\``:
      ```
      - `/quickfix Fix README typo` — low-ceremony PR for trivial changes (no worktree; picks up in-flight edits in main)
      ```
      Acceptance: `grep -q 'quickfix Fix README typo' CLAUDE_TEMPLATE.md`.

- [ ] 3.3 — `skills/update-zskills/SKILL.md`: register `/quickfix` in the core-skill count and any enumerated list. **Read the current count at run time and increment by 1** — do NOT hardcode. The current count is 18 (verified: `grep -n 'core skills' skills/update-zskills/SKILL.md` → line 58 `only the 18 core skills are installed/updated`). After /quickfix lands, bump to 19. The dynamic-read shell is the insulation against future drift:
      ```bash
      CURRENT_COUNT=$(grep -oE 'only the [0-9]+ core skills are installed' \
        skills/update-zskills/SKILL.md | grep -oE '[0-9]+' | head -1)
      if [ -z "$CURRENT_COUNT" ]; then
        echo "ERROR: canonical count phrase not found. Update manually." >&2; exit 1
      fi
      NEW_COUNT=$((CURRENT_COUNT + 1))
      # Edit the line to use $NEW_COUNT
      ```
      Also grep for other enumerations (`/commit`, `/do `, `/run-plan`, `core skill`) and add `/quickfix` where appropriate.
      Acceptance: `grep -q 'quickfix' skills/update-zskills/SKILL.md` AND count matches `CURRENT+1`.

- [ ] 3.4 — `README.md`: insert `/quickfix` row in the `#### Ship` table (location may drift — use grep, not hardcoded line):
      ```
      | `/quickfix` | Low-ceremony PR from main: picks up in-flight edits (or agent-dispatches), no worktree, fire-and-forget CI |
      ```
      Acceptance: `grep -q '\`/quickfix\`' README.md` AND `grep -A 10 '#### Ship' README.md | grep quickfix` matches.

- [ ] 3.5 — Re-mirror any edited skill source with the **literal-path idiom** (WI 1.19):
      ```bash
      cd "$MAIN_ROOT" && rm -rf .claude/skills/update-zskills && cp -r skills/update-zskills .claude/skills/update-zskills
      diff -r skills/update-zskills .claude/skills/update-zskills
      ```

### Acceptance Criteria (Phase 3)

- [ ] `grep -q 'quickfix Fix README typo' CLAUDE_TEMPLATE.md`.
- [ ] `grep -q '\`/quickfix\`' README.md` AND appears in `#### Ship` table (via `grep -A 10`).
- [ ] `grep -q 'quickfix' skills/update-zskills/SKILL.md` AND count = CURRENT+1.
- [ ] `diff -r skills/update-zskills .claude/skills/update-zskills` empty.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies (Phase 3)

Phase 1a AND Phase 1b.

---

## Drift Log

No completed phases — review is equivalent to a light draft-plan pass. All phases reviewed as remaining.

---

## Plan Quality

**Drafting process:** `/draft-plan` with 3 rounds of adversarial review, then `/refine-plan` conciseness pass.
**Convergence:** Converged at round 3 of draft (0 HIGH remaining); refine pass cut 3 stale-reference HIGHs (R-H1/H2/H3) and ~1230 lines of bloat.
**Remaining concerns:** `date -d` is GNU-only (acknowledged — Linux-primary zskills OK).

### Round History

| Round | Phase | Findings | Resolved |
|-------|-------|----------|----------|
| Draft R1 | `/draft-plan` | 24 (8H/12M/5L) | 24 |
| Draft R2 | `/draft-plan` | 11 (3H/6M/2L) | 11 |
| Draft R3 | `/draft-plan` | 8 (0H/1M/7L polish) | applied inline |
| Refine R1 | `/refine-plan` | 12 (5H/8M/3L stale refs + conciseness) | see Plan Review below |

### Key Decisions

1. **`unit_cmd == full_cmd` alignment gate** (not bypass mechanisms): simpler than patching hook or echoing transcript marker; users opt in by aligning config or using `/commit pr`.
2. **Cleanup via verified steps, no `|| true`**: every rollback step checked; distinct exit 6 for "cleanup failure, manual intervention needed" vs exit 5 for "operation failed, rollback clean."
3. **Mirror uses literal-path idiom** (`cd $MAIN_ROOT && rm -rf .claude/skills/quickfix && cp -r …`): hook's `is_safe_destruct` rejects `rm -rf` containing `$`; precedent in `plans/RESTRUCTURE_RUN_PLAN.md:184,328,491`.
4. **Phase 1 split into 1a/1b**: 20-WI phase is too large; 1a = shippable core (WIs 1.1–1.15 + 1.3.5), 1b = hardening (1.16–1.19) + structural guard tests.
5. **Mode-aware `Co-Authored-By`**: agent-dispatched includes it (Claude authored the edits); user-edited omits (human authored). Trailer copied verbatim from `skills/commit/SKILL.md` — don't hardcode a model version.

---

## Plan Review

### Verification Summary (Refine R1 HIGH findings)

| ID | Finding | Evidence | Disposition |
|----|---------|----------|-------------|
| R-H1 | `DOC_PARTY_COMPARISON.md` referenced but does not exist | Verified — `ls /workspaces/zskills/DOC_PARTY_COMPARISON.md` → no such file | Fixed: deleted WI 3.2, removed §4.1 citation from Overview; replaced with inline "No existing skill handles branch+commit+PR in main checkout." |
| R-H2 | Plan narrative says "17 core skills"; actual is 18 | Verified — `skills/update-zskills/SKILL.md:58` reads `only the 18 core skills` | Fixed: WI 3.3 narrative re-anchored to `18 → 19`; kept dynamic-read shell for future-drift safety. |
| R-H3 | Plan cites `block-unsafe-generic.sh:146` for refspec strip; actual line is 215-216 | Verified — `PUSH_TARGET="${PUSH_TARGET%%:*}"` at line 216, main/master gate at 218 | Fixed: WI 1.14 and Design §Push re-anchored to `hooks/block-unsafe-generic.sh:215-220`. |

### Medium / Low Disposition

| ID | Disposition |
|----|-------------|
| R-H4 | Fixed — Phase 1a compressed from 695 lines to target by cutting per-WI pseudocode (kept WI 1.3 check 4, 1.11 dispatch-layer note, 1.19 mirror idiom). |
| R-H5 | Fixed — Phase 1b compressed from 501 lines by replacing 105-line test matrix with category summary naming regression guards 11/18-20/33/34. |
| R-M1 | Fixed — duplicate Plan Quality stub deleted. |
| R-M2 | Fixed — three disposition tables (~210 lines) compressed into 5 Key Decisions. |
| R-M3 | Fixed — `/do:309 jq` citation dropped (verified 0 `jq` in `skills/do/SKILL.md`). Justification rewritten. |
| R-M4 | Fixed — hardcoded `Claude Opus 4.7 (1M context)` replaced with "same trailer as `skills/commit/SKILL.md`" (canonical source uses 4.6). |
| R-M5 | Fixed — Overview compressed from 54 lines to ~20. |
| R-M6 | Fixed — moot: Round 1 disposition rows containing "WI 2.X" references were deleted with the tables. |
| R-M7 | Fixed — WI 3.4 anchor "line 106" dropped; grep-based acceptance only. |
| R-M8 | Fixed — WI 1.8 terminal-states prose dedup'd against Exit Codes + Tracking contract. |
| R-L1 | Judgment: accept 16 WIs in Phase 1a (phase-split already addresses bulk concern). |
| R-L2 | Fixed — Drift Log one-liner per edge case. |
| R-L3 | Fixed — positive-presence greps pruned; kept structural ANTI-PATTERN greps + behavioral gates. |

### Refine Round History

| Round | Findings | Resolved |
|-------|----------|----------|
| R1 (combined reviewer + DA) | 12 (5H/8M/3L) | 12 |

**Convergence:** Converged. All 12 findings dispositioned. Plan reduced from 1704 to target ~475 lines. Load-bearing contracts (exit codes, slug rules, mode detection, commit template, mirror idiom, structural anti-pattern greps) preserved.
