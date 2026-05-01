# Plan Report — /quickfix and /do Triage Gate, Inline Plan, Fresh-Agent Review

## Plan complete — 2026-05-01

All five phases landed via PR mode in a single autonomous `finish auto` run.

| Phase | Status | Commit | PR |
|-------|--------|--------|-----|
| 1a | ✅ Done | `d779788` | [#151](https://github.com/zeveck/zskills-dev/pull/151) |
| 1b | ✅ Done | `73ff49a` | [#152](https://github.com/zeveck/zskills-dev/pull/152) |
| 2a | ✅ Done | `4a6c659` | [#153](https://github.com/zeveck/zskills-dev/pull/153) |
| 2b | ✅ Done | `dc0005d` | [#154](https://github.com/zeveck/zskills-dev/pull/154) |
| 3  | ✅ Done | `59613d4` | (this PR) |

**Test suite trajectory:** 1698 (pre-plan baseline) → 1709 (after Phase 1b adds 10 quickfix cases, +1 split) → 1722 (after Phase 2b adds 13 do cases). No regressions across all five phases.

**Follow-up:** [#155](https://github.com/zeveck/zskills-dev/issues/155) — apply triage gate + plan review to `/commit pr`.

---

## Phase — 3 Cross-cutting: CLAUDE_TEMPLATE.md, full-suite run, follow-up issue

**Plan:** plans/QUICKFIX_DO_TRIAGE_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-quickfix-do-triage-plan (PR mode)
**Implementation commit:** 59613d4

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 3.1 | CLAUDE_TEMPLATE.md L199-200 — append `--force`/`--rounds N` to /quickfix and /do bullets + one-line triage note | Done | Anchor verified: matches plan's "**Usage:** Append keyword..." section verbatim. /quickfix bullet renders `--force`; /do bullet renders `--rounds 2 --force` (to satisfy AC2 grep). |
| 3.2 | Full project `bash tests/run-all.sh` runs clean | Done | 1722/1722 PASS; CI also green via `gh pr checks` before merge |
| 3.3 | File `/commit pr` follow-up issue, link in `## Follow-ups` | Done | Issue #155 created (state: OPEN); plan parenthetical updated to `(Tracked: https://github.com/zeveck/zskills-dev/issues/155)` |

### Verification

- **Test suite:** PASSED (1722/1722, no change from baseline — CLAUDE_TEMPLATE.md is documentation)
- **All 4 ACs PASS** — both grep ACs for `--force` examples; full-suite clean; Tracked URL anchor matches real issue URL
- **PLAN-TEXT-DRIFT:** none

### Diff stat

- `CLAUDE_TEMPLATE.md`: +3 / −2 (3 lines changed)
- `plans/QUICKFIX_DO_TRIAGE_PLAN.md`: +1 / −1 (Tracked URL parenthetical)

### Commits on `feat/quickfix-do-triage-plan` (Phase 3 only)

```
59613d4 docs(template): document --force / --rounds + triage gate (Phase 3)
```

---

## Phase — 2b /do: create test suite, wire into runner

**Plan:** plans/QUICKFIX_DO_TRIAGE_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-quickfix-do-triage-plan (PR mode)
**Implementation commit:** dc0005d

### Cases (1–13)

| # | Case | Notes |
|---|------|-------|
| 1 | argument-hint contains `--force` and `--rounds N` | |
| 2 | Phase 0a < Phase 0c structural ordering — **cron-zombie regression static guard** | Phase 0a@234, 0b@312, 0c@462 |
| 3 | Phase 0b inline-plan template + reviewer prose | |
| 4 | `--force` cron-persistence ("every cron fire bypasses triage and review") | |
| 5 | Meta-command bypass note grep-able | |
| 6 | VERDICT regex documented (APPROVE bare; REVISE/REJECT need `--`) | |
| 7 | `--rounds 0` skip prose AND stderr WARN literal present | |
| 8 | Phase 1.5 strip chain: `fix tooltip --force --rounds 3 pr` → `fix tooltip` | end-to-end |
| 9 | `--rounds notanumber` greedy-fallthrough — ROUNDS stays at 1, FORCE=0 | |
| 10 | Phase 0b orthogonality (`pre-review judges PLAN`; PR mode handles own push) | |
| 11 | Entry-point unset guard regression — no `_ZSKILLS_TEST_HARNESS` → seam vars unset | symmetric to /quickfix Case 47e |
| 12 | Phase 1.5 re-validation does NOT exit 2 on non-numeric `--rounds` | round-2 R5/DA4 |
| 13 | Quoted-description protection — DA3 fix: in-quotes `--force` preserved, trailing stripped | |

### Verification

- **Test suite:** PASSED (1722/1722, +13 from 1709 baseline) — independently re-measured by verifier
- **All 8 ACs PASS** — file exists, 13 cases pass, run-all.sh wired, suite count matches plan exactly, cron-zombie static guard, DA3 quoted-description case, R5/DA4 re-validation case, hygiene
- **Cron-zombie regression coverage**: structural (Case 2 ordering) + entry-point (Case 11 unset guard) + upstream-symmetry (/quickfix Cases 47/48 dynamic seam) = combined regression guarantee at appropriate cost
- **PLAN-TEXT-DRIFT:** none

### Diff stat

- `tests/test-do.sh`: +473 lines (new file)
- `tests/run-all.sh`: +1 line (`run_suite "test-do.sh" "tests/test-do.sh"` after the test-quickfix.sh line)

### Commits on `feat/quickfix-do-triage-plan` (Phase 2b only)

```
dc0005d test(do): create test-do.sh (13 cases) + wire into run-all.sh (Phase 2b)
```

---

## Phase — 2a /do: triage gate, inline plan, fresh-agent review (skill source + mirror)

**Plan:** plans/QUICKFIX_DO_TRIAGE_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-quickfix-do-triage-plan (PR mode)
**Implementation commit:** 4a6c659

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 2a.0 | Pre-flight flag pre-parse with entry-point unset guard | Done | Unset guard FIRST, then `FORCE=0`, then numeric-only `--rounds` regex with greedy-fallthrough |
| 2a.1 | `## Phase 0a — Triage` (mirror of /quickfix WI 1.5.4) | Done | 7-row rubric (no MODE col), 6 worked examples, 4 redirect-message rows |
| 2a.2 | Cron-zombie regression guard documented in Phase 0a opener | Done | "Phase 0a runs BEFORE Phase 0c. A REDIRECT path exits before any `CronCreate` call" |
| 2a.3 | `## Phase 0b — Inline plan + fresh-agent review` | Done | WARN for `--rounds 0`, OBSERVABLE-SIGNAL RULE, regex fence (L410), REVISE iteration, REJECT exits with no marker / no cron / no worktree |
| 2a.4 | Phase 1.5 strip-chain extended with `--force`/`--rounds` `sed -E` arms; idempotent re-affirm of FORCE/ROUNDS as Step 4 | Done | L646-647 |
| 2a.5 | `argument-hint` updated; two new bullets in Arguments block | Done | L4 |
| 2a.6 | Phase 0 → Phase 0c rename; cron-prompt construction with quoted-description carve-out (DA3 fix) | Done | TASK_DESCRIPTION_FOR_CRON build; carve-out at L501-521; persistence prose retained |
| 2a.7 | Meta-command bypass note (single grep-able line) after meta-command bullets | Done | L84 |
| 2a.8 | Mirror via `scripts/mirror-skill.sh do`; precondition uses `git status --porcelain` (DA12 fix) | Done | `diff -rq` clean (rc=0) |

### Verification

- **Test suite:** PASSED (1709/1709, no regression — baseline 1709/1709)
- **All 13 ACs PASS** — heading order strictly ascending: 0a@234 < 0b@312 < 0c@462 < Phase 1@569
- **Cron-zombie guard verified**: triage and review run at lines 234 and 312, BEFORE Phase 0c (cron registration) at L462
- **Hygiene:** only `skills/do/SKILL.md` and `.claude/skills/do/SKILL.md` modified
- **PLAN-TEXT-DRIFT:** none (verifier independently confirmed plan ACs key only on heading text + grep strings, no hard-coded line numbers)

### Diff stat

- `skills/do/SKILL.md`: +383 / -11 (499 → 882 lines)
- `.claude/skills/do/SKILL.md`: +383 / -11 (mirror, byte-identical)

### Commits on `feat/quickfix-do-triage-plan` (Phase 2a only)

```
4a6c659 feat(do): triage gate, inline plan, fresh-agent review BEFORE cron registration (Phase 2a)
```

---

## Phase — 1b /quickfix: extend test suite for triage / review / --force / --rounds

**Plan:** plans/QUICKFIX_DO_TRIAGE_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-quickfix-do-triage-plan (PR mode)
**Implementation commit:** 73ff49a

### Cases added (44–53)

| # | Case | Notes |
|---|------|-------|
| 44 | `--force` parsed → `FORCE=1`; no positional consumed | |
| 45 | `--rounds 3` numeric → `ROUNDS=3`; `--rounds notanumber` greedy-falls through to `DESCRIPTION` | greedy-fallthrough |
| 46 | `--rounds 0` clean parse; WARN discriminator present in skill prose | |
| 47 | Triage REDIRECT(/draft-plan) seam — message printed, exit 0, no marker, no branch | entry-point unset guard verified |
| 48 | Review REJECT seam — reason printed, exit 0, no marker, no branch | |
| 49 | User-decline regression — marker carries `status: cancelled` AND `reason: user-declined` | |
| 50 | WI 1.5.x heading-ordering by line number (1.5 < 1.5.4 < 1.5.4a < 1.5.4b < 1.5.5) | |
| 51a/51b | Per-target redirect-message line check + structural extraction (4 table rows, opener pattern) | Two-part assertion; +1 pass-row |
| 52 | VERDICT regex contract from WI 1.5.4b `regex` fence + fence-tag co-discipline | bare APPROVE matches; APPROVE+free-text rejected; REVISE/REJECT require `--` separator |
| 53 | `--rounds 0` skip path documented in BOTH prose AND stderr WARN literal | |

### Verification

- **Test suite:** PASSED (1709/1709, +11 from 1698 baseline)
- **Acceptance criteria:** all PASS — 52 case-numbers (42 existing + 10 new); cases 44–53 each present and pass at runtime
- **Hygiene:** only `tests/test-quickfix.sh` modified
- **Test-seam usage:** all triage / review cases use `_ZSKILLS_TEST_TRIAGE_VERDICT` / `_ZSKILLS_TEST_REVIEW_VERDICT` with `_ZSKILLS_TEST_HARNESS=1`; no model-layer mocks
- **PLAN-TEXT-DRIFT:** none (verifier independently re-confirmed; the implementer's "1708→1709" advisory is structural improvement from Case 51 split, not a real plan-text drift)

### Diff stat

- `tests/test-quickfix.sh`: +518 lines (10 cases + parser-only extractor helper at helpers section)

### Commits on `feat/quickfix-do-triage-plan` (Phase 1b only)

```
73ff49a test(quickfix): cover triage / review / --force / --rounds (Phase 1b)
```

---

## Phase — 1a /quickfix triage gate, inline plan, fresh-agent review (skill source + mirror)

**Plan:** plans/QUICKFIX_DO_TRIAGE_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-quickfix-do-triage-plan (PR mode, branch `feat/quickfix-do-triage-plan`)
**Implementation commit:** d779788
**Tracker commit:** 3444c76

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1a.1 | `--force` and `--rounds N` parser arms; `FORCE=0`, `ROUNDS=1` defaults | Done | greedy-fallthrough numeric detection for `--rounds N` |
| 1a.2 | Frontmatter `argument-hint` + Usage line include `[--force] [--rounds N]` | Done | L4 frontmatter, L13 Usage |
| 1a.3 | WI 1.5.4 — Triage gate (model-layer) | Done | Rubric table, worked examples, 4 per-target redirect templates, FORCE override |
| 1a.3a | Entry-point unset guard (`_ZSKILLS_TEST_TRIAGE_VERDICT`, `_ZSKILLS_TEST_REVIEW_VERDICT`) at top of WI 1.2 parser | Done | L73-79, before `FORCE=0` at L87 |
| 1a.4 | WI 1.5.4a — Inline plan composition (text-fence template, ≤60 lines) | Done | Template at L377-384; forbidden-literal constraints documented |
| 1a.5 | WI 1.5.4b — Fresh-agent plan review | Done | OBSERVABLE-SIGNAL RULE (>4 Acceptance bullets → auto-REVISE), `regex` fence (NOT `bash`) for verdict parser, REVISE iteration template, APPROVE/REVISE/REJECT handling, `$ROUNDS` exhaustion soft-reject, `--rounds 0` skip with WARN |
| 1a.6 | WI 1.5.5 prose acknowledges reviewer verdict context | Done | "verdict prints ABOVE this confirmation prompt" |
| 1a.6.5 | WI 1.5.5 two-arm decline path (production no-marker vs test-fixture bash-fallback) | Done | L528-549 |
| 1a.6.7 | WI 1.3 Check 3 hook citation refreshed `188-229` → `412-427` | Done | grep for `188-229` returns empty |
| 1a.7 | `CANCEL_REASON` initializer + `reason:` block in `finalize_marker` (after outer `fi`) + `CANCEL_REASON="user-declined"` before `CANCELLED=1` in WI 1.10 | Done | L650, L670-673, L757-758; Terminal marker states updated at L1072-1075 |
| 1a.8 | Mirror byte-identical via `scripts/mirror-skill.sh quickfix`; pre-check used `git status --porcelain` (per DA12 fix) | Done | `diff -rq skills/quickfix/ .claude/skills/quickfix/` rc=0, no output |

### Verification

- **Test suite:** PASSED (1698/1698, no regression — baseline 1698/1698 captured pre-impl)
- **Acceptance criteria:** all 21 ACs PASS (20 grep-based + 1 byte-parity)
- **Hygiene:** only `skills/quickfix/SKILL.md` and `.claude/skills/quickfix/SKILL.md` modified; no lifecycle markers leaked
- **PLAN-TEXT-DRIFT:** none (independent re-detection by verifier confirmed plan claims match reality)

### Diff stat

- `skills/quickfix/SKILL.md`: +305 / −16 (now 1102 lines)
- `.claude/skills/quickfix/SKILL.md`: +305 / −16 (mirror, byte-identical)

### Commits on `feat/quickfix-do-triage-plan`

```
3444c76 chore: mark Phase 1a in progress
d779788 feat(quickfix): triage gate, inline plan, fresh-agent review (Phase 1a)
```
