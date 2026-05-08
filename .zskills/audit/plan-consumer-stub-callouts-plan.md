# Plan Report — Consumer stub-callout extension

## Phase — 7 Close-out (CHANGELOG / plan index / frontmatter complete / DA6 policy + carryovers) [UNFINALIZED]

**Plan:** plans/CONSUMER_STUB_CALLOUTS_PLAN.md
**Status:** Completed (verified) — **plan complete**
**Worktree:** /tmp/zskills-pr-consumer-stub-callouts-plan
**Branch:** feat/consumer-stub-callouts-plan
**Commits:** 4820e09 (In Progress), dd1a668 (close-out + carryovers)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 7.1 | CHANGELOG entry | Done | "consumer stub-callout convention" entry at top of unreleased |
| 7.2 | Plan index update | Done | moved from Ready-to-Run to Complete; totals updated |
| 7.3 | Frontmatter flip `status: complete` + `completed: 2026-04-28` | Done | America/New_York date per project tz |
| 7.4 | DA6 stub-body versioning policy in `script-ownership.md` | Done | "Failing-stub body revisions" section added |

### Carryovers folded in

**Carryover A — Phase 2 bookkeeping debt resolved:**
- `zskills-stub-lib.sh` registered Tier-1 owned by `update-zskills` in `script-ownership.md`
- Hash `52ef89b146d789734326df6866808f8c7ae57ca3` added to `tier1-shipped-hashes.txt`
- STALE_LIST sync (case 6a parity check requires both `script-ownership.md` and `SKILL.md`'s `STALE_LIST=(...)` array to match)

**Carryover B — Phase 3+4+5 plan-text drift cleanup:**
4 ACs in this plan (lines 717, 908, 1241, 1243) relaxed from `grep -F '<file>.sh if missing'` to `grep -F '\`<file>.sh\` if missing'` so they match the SKILL.md backtick-wrapped bullet text the implementers wrote. Advisory-only (no behavioral change).

### Verification

All 5 ACs PASS (4 plan ACs + 1 implicit "tests green"):
- `grep -F 'consumer stub-callout convention' CHANGELOG.md` — PASS
- frontmatter shows `status: complete` + `completed: 2026-04-28` — PASS
- plan index entry present — PASS
- `grep -F 'Failing-stub body revisions' script-ownership.md` — PASS
- `bash tests/run-all.sh` exits 0 — PASS (1066/1066)

Mirror parity clean (`diff -r skills/update-zskills .claude/skills/update-zskills` empty).

### Plan-text drift (advisory)

```
PLAN-TEXT-DRIFT: phase=7 bullet=7.3 field=completed-date plan=2026-04-29 actual=2026-04-28
```

Orchestrator prompt referenced 2026-04-29 (UTC); the implementer used `TZ=America/New_York date +%Y-%m-%d` and got 2026-04-28. Project timezone convention is ET, so 2026-04-28 is correct.

### Plan complete

Frontmatter is now `status: complete`. The orchestrator's recurring `*/1` chunking cron will hit Step 0 Case 1 on its next fire and self-delete (Design 2a terminal cron cleanup). Auto-merge requested via `gh pr merge --auto --squash` — PR #106 will squash-merge to main once CI / required reviews pass.

### Dependencies

Phases 1, 2, 3, 4, 5, 6.

## Phase — 6 Hooks / CLAUDE_TEMPLATE / docs sweep + briefing-extra.sh decision [UNFINALIZED]

**Plan:** plans/CONSUMER_STUB_CALLOUTS_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-consumer-stub-callouts-plan
**Branch:** feat/consumer-stub-callouts-plan
**Commits:** 3543805 (In Progress), 631653f (briefing-extra deferral entry + mirror)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 6.1 | README sweep verification | Done | zero matches for `scripts/(test-all\|stop-dev\|start-dev\|dev-port\|post-create-worktree)` — vacuously stub-aware |
| 6.2 | CLAUDE_TEMPLATE.md regression guards | Done | `{{PORT_SCRIPT}}` 0 matches; `{{TIMEZONE}}` count=1 (DA4) |
| 6.3 | briefing-extra.sh deferred — recorded in `references/stub-callouts.md` | Done | dual-runtime note (cjs + py3) included |
| 6.4 | Step D install report | Done | existing dynamic "Installed N scripts: [list]" at SKILL.md:944 satisfies the requirement |
| 6.5 | Mirror | Done | `diff -r` empty |

### Verification

All 6 ACs PASS:

- **AC1** `grep -nE 'scripts/(test-all|stop-dev|start-dev)' README.md` — every match in stub-aware prose: PASS (0 matches; vacuous).
- **AC2** `grep -F '{{PORT_SCRIPT}}' CLAUDE_TEMPLATE.md` returns no matches: PASS.
- **AC3** `[ "$(grep -c -F '{{TIMEZONE}}' CLAUDE_TEMPLATE.md)" -eq 1 ]`: PASS.
- **AC4** `grep -F 'briefing-extra' skills/update-zskills/references/stub-callouts.md`: PASS.
- **AC5** Every shipped stub references the canonical doc: PASS (all 3 — `post-create-worktree.sh`, `dev-port.sh`, `start-dev.sh`).
- **AC6** `bash tests/run-all.sh` exits 0: PASS (1066/1066).

### Notes

- Phase 6 was largely a verification phase — most edits were anticipated by Phase 5's CLAUDE_TEMPLATE.md / README work. Only WI 6.3 required a substantive doc edit (the briefing-extra deferral entry).
- AC5's "every stub references canonical doc" already passed because the implementer of Phases 3, 4, 5 included the `references/stub-callouts.md` reference in each stub's header. The AC enshrines this discipline as a regression guard for future PRs.
- No Tier-1 hash regen needed (only `.md` files modified).

### Dependencies

Phase 1, Phase 2, Phase 3, Phase 4, Phase 5.

## Phase — 5 `start-dev.sh` + convert `stop-dev.sh` / `test-all.sh` to failing stubs [UNFINALIZED]

**Plan:** plans/CONSUMER_STUB_CALLOUTS_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-consumer-stub-callouts-plan
**Branch:** feat/consumer-stub-callouts-plan
**Commits:** e93f5d3 (In Progress), f8ab398 (impl + hook + template + README + mirror)

### Work Items

All 14 WIs completed:

| # | Item | Status |
|---|------|--------|
| 5.1 | `skills/update-zskills/stubs/start-dev.sh` (new failing stub) | Done |
| 5.2 | Step D bullet for start-dev.sh | Done |
| 5.3 | Drop current `scripts/stop-dev.sh` impl | Done |
| 5.4 | Replace `scripts/stop-dev.sh` with failing stub (in place) | Done |
| 5.5 | Step D bullet for stop-dev.sh updated | Done |
| 5.6 | Hook help-text at `hooks/block-unsafe-generic.sh:159,177` | Done |
| 5.7 | `CLAUDE_TEMPLATE.md` Dev Server section | Done |
| 5.8 | Drop current `scripts/test-all.sh` impl | Done |
| 5.9 | Replace `scripts/test-all.sh` with failing stub | Done |
| 5.10 | Step D bullet for test-all.sh updated | Done |
| 5.11 | Skill-side test-all.sh callsite check + preset (regression-guard verified) | Done |
| 5.12 | Delete `tests/test-stop-dev.sh` + remove run-all.sh entry; update test-hooks.sh stale allow-list | Done |
| 5.13 | `README.md` sweep for failing-stub anchor + start-dev mention | Done |
| 5.14 | Mirror `update-zskills` + hook source/.claude parity | Done |

### Verification

- `bash tests/run-all.sh` → **1066/1066 pass**. Math: baseline 1075 − 7 (deleted `test-stop-dev.sh` cases) − 2 (removed stale `{{E2E_TEST_CMD}}` / `{{BUILD_TEST_CMD}}` placeholder allow-list cases that no longer apply post-WI 5.9) = **1066** ✓ exact.
- `test -x skills/update-zskills/stubs/start-dev.sh` ✓.
- `bash scripts/stop-dev.sh; rc=1; stderr matches "not configured"` ✓.
- `bash scripts/test-all.sh; rc=1; stderr matches "not configured"` ✓.
- `grep -F 'not configured' scripts/{stop,test-all}-dev.sh` matches both ✓.
- `grep -F 'failing-stub by default' README.md` matches ✓.
- `grep -F 'failing stub by default' hooks/block-unsafe-generic.sh` ≥ 2 ✓ (lines 159, 177 both updated; **plan AC line numbers verified accurate, no drift on those**).
- Hook source/.claude mirror parity: `diff hooks/block-unsafe-generic.sh .claude/hooks/block-unsafe-generic.sh` empty ✓.
- `! test -e tests/test-stop-dev.sh` ✓ (file deleted).
- `! grep -F 'test-stop-dev.sh' tests/run-all.sh` ✓ (entry removed).

### Notes

- The two pre-existing Tier-2 templates (`stop-dev.sh`, `test-all.sh`) stayed at top-level `scripts/` per Phase 2 DA5. Their bodies were overwritten in place; their location did not move.
- No Tier-1 hash regen needed — neither converted script is Tier-1 (per `script-ownership.md`).
- Major value-add: removed silent `{{E2E_TEST_CMD}}` / `{{BUILD_TEST_CMD}}` runtime "command not found" exit-127 errors that the prior implementation produced. The new failing stubs surface "not configured" cleanly to stderr with rc=1.

### Plan-text drift (advisory)

```
PLAN-TEXT-DRIFT: phase=5 bullet=AC6 field=grep_string plan="start-dev.sh if missing" actual="`start-dev.sh` if missing"
PLAN-TEXT-DRIFT: phase=5 bullet=AC7 field=grep_string plan="test-all.sh if missing" actual="`test-all.sh` if missing"
```

Same backtick AC drift as Phase 3 AC3 + Phase 4 AC3 — bullets verbatim use backticks, AC's literal `grep -F` omits them. Functionality correct; AC text too strict. Phase 7 close-out can relax all four AC patterns together.

### Dependencies

Phase 1, Phase 2.

## Phase — 4 `dev-port.sh` callout [UNFINALIZED]

**Plan:** plans/CONSUMER_STUB_CALLOUTS_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-consumer-stub-callouts-plan
**Branch:** feat/consumer-stub-callouts-plan
**Commits:** d055101 (In Progress), c632391 (impl + mirror + Tier-1 hash regen)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 4.1 | Callout block in `skills/update-zskills/scripts/port.sh` | Done | between DEV_PORT fast-path and main-repo branch; numeric-stdout regex + non-numeric warn-and-fall-through; DA15 stderr wired |
| 4.2 | `skills/update-zskills/stubs/dev-port.sh` | Done | exec; 2-positional-arg no-op default body |
| 4.3 | Step D bullet | Done | after post-create-worktree.sh bullet |
| 4.4 | `references/stub-callouts.md` extended with `dev-port.sh` section | Done | args, stdout numeric-port contract, fall-through semantics |
| 4.5 | `tests/test-port.sh` extended with 6 new cases (existing 4 + new 6 = 10) | Done | absent, numeric, empty fall-through, non-numeric warn, non-exec, DEV_PORT-wins |
| 4.6 | Mirror via `mirror-skill.sh update-zskills` | Done | `diff -r` empty |

### Verification

- `bash tests/test-port.sh` → 10/10 PASS.
- `bash tests/run-all.sh` → **1075/1075 pass** (was 1068/1069 with case 6c failing pre-commit; case 6c now passes since git log sees the co-committed hash file update).
- `grep -c 'zskills_dispatch_stub dev-port.sh' skills/update-zskills/scripts/port.sh` = 1.
- `grep -c -F 'stub-lib missing' skills/update-zskills/scripts/port.sh` = 1.
- **Phase 2 cross-phase AC (DA15) now satisfied:** both callsites wired (`create-worktree.sh` from Phase 3, `port.sh` from this phase).
- Mirror parity clean.

### Bonus — Tier-1 hash regeneration (case 6c fix)

Pre-existing zskills convention surfaced post-Phase-3: when a Tier-1 script (per `script-ownership.md`) changes, its CRLF-stripped blob hash must be appended to `skills/update-zskills/references/tier1-shipped-hashes.txt` in the same commit (or a later one by `merge-base --is-ancestor`). Phase 3 modified `create-worktree.sh` (Tier-1) without updating the hash file — case 6c failed in `tests/test-update-zskills-migration.sh:466-509`. Phase 4 also modifies a Tier-1 script (`port.sh`), so this phase's commit appends both new hashes:

- `44fdf87b192cd8e356d4992f92c90050cfa641f0` — `create-worktree.sh` post-Phase-3
- `1a839c0a5cd35d4324f417a96decb606bb47346e` — `port.sh` post-Phase-4

**`zskills-stub-lib.sh` registration in `script-ownership.md` deferred to Phase 7** — that script was added in Phase 2 and is internal Tier-1 machinery, but case 6c only iterates entries already in the ownership table, so deferring registration doesn't break the build. Phase 7 close-out adds it alongside the CHANGELOG entry.

### Plan-text drift (advisory)

```
PLAN-TEXT-DRIFT: phase=4 bullet=AC3 field=grep_pattern plan="dev-port.sh if missing" actual="`dev-port.sh` if missing"
```

Same backtick drift as Phase 3 AC3 — bullet wraps the filename in backticks, AC's literal `grep -F` pattern doesn't match. Functionality correct; AC text too strict. Phase 7 close-out can relax both Phase 3 AC3 and Phase 4 AC3 together.

### Dependencies

Phase 1, Phase 2, Phase 3.

## Phase — 3 `post-create-worktree.sh` callout [UNFINALIZED]

**Plan:** plans/CONSUMER_STUB_CALLOUTS_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-consumer-stub-callouts-plan
**Branch:** feat/consumer-stub-callouts-plan
**Commits:** d83819c (In Progress), 698c6e6 (impl + mirror + lib fix)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 3.1 | Callout block in `skills/create-worktree/scripts/create-worktree.sh` | Done | DA15 stub-lib-missing stderr wired |
| 3.2 | Step D bullet in `skills/update-zskills/SKILL.md` | Done | references stub-callouts.md |
| 3.3 | `skills/update-zskills/stubs/post-create-worktree.sh` (new dir populated) | Done | exec; 6-arg no-op default body |
| 3.4 | `tests/test-post-create-worktree.sh` 3 cases | Done | absent / present-success / present-fail rc=9 worktree-preserved |
| 3.5 | Mirror via `mirror-skill.sh create-worktree` + `update-zskills` | Done | `diff -r` empty for both |

### Verification

- `bash tests/test-post-create-worktree.sh` → 3/3 PASS.
- `bash tests/test-stub-callouts.sh` → 8/8 PASS (Phase 2 lib unaffected by the fix).
- `bash tests/run-all.sh` → **1016/1016 pass** (was 951/951 + 3 new + 62 new from main during rebase).
- `grep -c 'zskills_dispatch_stub post-create-worktree.sh' skills/create-worktree/scripts/create-worktree.sh` = 1.
- `grep -c -F 'stub-lib missing' skills/create-worktree/scripts/create-worktree.sh` = 1 (DA15 wiring complete for create-worktree.sh; Phase 4 wires the analogous warning into port.sh).
- Mirror parity: clean.

### Bonus — surfaced Phase 2 latent lib bug

While wiring the callout into `create-worktree.sh` (which runs under `set -eu`), the implementer found that `zskills-stub-lib.sh` captured the stub's RC with `ZSKILLS_STUB_STDOUT=$(bash "$stub" "$@"); ZSKILLS_STUB_RC=$?` — but a non-zero `$(...)` aborts the caller before the next line under `set -e`. Fix: `ZSKILLS_STUB_STDOUT=$(bash "$stub" "$@") || ZSKILLS_STUB_RC=$?` keeps the assignment safe and lets the caller propagate the failure correctly. Comment in the lib documents the constraint.

### Plan-text drift (advisory)

```
PLAN-TEXT-DRIFT: phase=3 bullet=AC3 field=grep_pattern plan="post-create-worktree.sh if missing" actual="`post-create-worktree.sh` if missing"
```

The Phase 3 AC at line ~702 of the plan says
`grep -F 'post-create-worktree.sh if missing' skills/update-zskills/SKILL.md` should match — but the bullet wraps the filename in backticks, so the literal pattern doesn't match. The bullet IS present (functionality correct); the AC pattern is too strict. Phase 7 close-out can relax this AC text. No code change needed.

### Dependencies

Phase 1, Phase 2.

## Phase — 2 Stub-callout convention + sourceable dispatch helper [UNFINALIZED]

**Plan:** plans/CONSUMER_STUB_CALLOUTS_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-consumer-stub-callouts-plan
**Branch:** feat/consumer-stub-callouts-plan
**Commits:** 18f755f (In Progress), 4f457a3 (impl + mirror)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 2.1 | `references/stub-callouts.md` (contract + helper-fn verbatim + canonical inventory + when-to-add prose) | Done | 189 lines |
| 2.2 | `scripts/zskills-stub-lib.sh` (sourceable `zskills_dispatch_stub`) | Done | exec bit set; verbatim from plan WI 2.2 |
| 2.3 | `tests/test-stub-callouts.sh` (8 cases incl. DA10 literal-`--` and DA9 multi-invocation clean state) | Done | sources via `$REPO_ROOT`; 8/8 PASS |
| 2.4 | SKILL.md Step D (dual source: `scripts/` + `stubs/`) | Done | 3 mentions of `skills/update-zskills/stubs/` |
| 2.5 | Mirror via `bash scripts/mirror-skill.sh update-zskills` | Done | `diff -r` empty |

### Verification

- `bash tests/test-stub-callouts.sh` → 8/8 PASS.
- `bash tests/run-all.sh` → **951/951 pass** (was 943/943 baseline, +8 new cases).
- Mirror parity: `diff -r skills/update-zskills .claude/skills/update-zskills` empty.
- Cross-phase ACs (lib-missing stderr warning at `create-worktree.sh` and
  `port.sh`) DEFERRED to Phases 3 + 4 by design — those are the wiring phases.

### Notes

- Phase 2's AC list at lines 489–495 of the plan references "lib-missing
  stderr warning wired at both callsites (DA15 — split per-file)". The
  WIRING work happens in Phase 3 (`create-worktree.sh`) and Phase 4
  (`port.sh`); Phase 2 only ships the lib + docs + tests + Step D edit.
  Both callsite greps will become non-zero after Phase 4 lands.
- Implementer agent `aa471f42f50ea0c19` was paused mid-run by a 5-hour
  usage-window limit (with extra-usage on; suspected harness or billing
  glitch). All 5 WIs completed cleanly before pause; only the implementer's
  final-report message was lost. Orchestrator inspected the worktree, ran
  the full suite, and committed the verified work.

### Dependencies

Phase 1.

## Phase — 1 Staleness gate [UNFINALIZED]

**Plan:** plans/CONSUMER_STUB_CALLOUTS_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-consumer-stub-callouts-plan
**Branch:** feat/consumer-stub-callouts-plan
**Commits:** 942c4f4 (tracker In Progress; Done committed at land time)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1.1 | Frontmatter check (prereq plan `status: complete`) | Done | grep matched |
| 1.2 | Multi-anchor filesystem check (8 anchors incl. `tests/run-all.sh` `CLAUDE_PROJECT_DIR` export) | Done | all anchors satisfied |
| 1.3 | CHANGELOG entry check (Tier-1 owning skills tolerant regex) | Done | `CHANGELOG.md:6` matched |
| 1.4 | HALT-on-FAIL conditional (`exit 1` if any FAIL) | Done | not tripped — all anchors pass |

### Verification

- `bash tests/run-all.sh` → 943/943 pass on baseline before any phase work.
- WIs 1.1–1.4 ran clean against current main; gate did not trip (expected
  behavior on a clean tree per the plan's "regression guard" framing).
- No diff to verify (Phase 1 is regression-guard-only by design — no code
  changes); orchestrator attests fulfillment.

### Notes

Phase 1 is a hard staleness gate. As of refine-round-1 (post-PRs #94–#100,
#88), all anchors pass against current main; the HALT path is intentionally
not exercised here. Phase 1 functions as a regression guard, not a discovery
check — a future re-rolled or partially-rolled-back prereq would re-trip it.

### Dependencies

None.
