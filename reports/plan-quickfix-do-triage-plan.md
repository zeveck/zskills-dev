# Plan Report — /quickfix and /do Triage Gate, Inline Plan, Fresh-Agent Review

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
