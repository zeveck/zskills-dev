# Plan Report — Consumer stub-callout extension

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
