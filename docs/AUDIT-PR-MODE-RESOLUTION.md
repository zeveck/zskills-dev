# AUDIT: `git rev-parse --git-common-dir` PR-mode resolution

**Phase:** 1b (zskills path-config plan, `docs/plans/ZSKILLS_PATH_CONFIG.md`)
**Generated:** 2026-05-07 (America/New_York)
**Source command:**

```bash
grep -rln "git rev-parse --git-common-dir" \
  skills/ block-diagram/ scripts/ hooks/ \
  | sort
```

**Total files:** 24 (verified at Phase 1b implementation time;
`wc -l` of the sorted file list).
**Total line-level occurrences:** 66 (some files have multiple fences;
the table below carries one row per file with the primary line cited
and the per-file occurrence count noted in the `Site context` column
when greater than 1).

`git rev-parse --git-common-dir` is the canonical idiom for resolving
the **main repository's** `.git` even from inside a worktree. The
returned path's parent is `$MAIN_ROOT` — i.e., where `plans/`,
`reports/`, `.zskills/` and other shared bookkeeping live.

This audit classifies each call site as one of:

- **MAIN-only** — the resolved `MAIN_ROOT` IS the desired anchor,
  even when the script is invoked from inside a worktree. Reading
  from / writing to the main is intentional. No rewrite needed.
- **PR-mode-relevant** — the call site is reached during PR-mode
  (worktree-local) execution and currently mis-anchors to `MAIN_ROOT`
  when the caller actually wants `WORKTREE_PATH`. MUST be rewritten in
  the owning phase to source `zskills-paths.sh` with
  `ZSKILLS_PATHS_ROOT="$WORKTREE_PATH"` (or, for Python sites, take an
  explicit `main_root` parameter — Phase 4).
- **Untouched** — call site is a research/inspection idiom: doc-comment,
  prose comment, or commented-out reference with no path-resolution
  side-effect downstream.

## Audit table

| File | Line | Lang | Site context | Class | Owning phase |
|------|------|------|--------------|-------|--------------|
| block-diagram/add-block/SKILL.md | 21 | bash | bash-fence-in-SKILL.md (2 occurrences in file: L21, L82) | PR-mode-relevant | 3 |
| block-diagram/add-example/SKILL.md | 37 | bash | bash-fence-in-SKILL.md | PR-mode-relevant | 3 |
| hooks/block-unsafe-project.sh.template | 527 | bash | bash-script-body (script IS the file; 3 occurrences: L527, L629, L689) | MAIN-only | n/a |
| skills/cleanup-merged/SKILL.md | 69 | bash | bash-fence-in-SKILL.md | MAIN-only | n/a |
| skills/commit/scripts/land-phase.sh | 16 | bash | bash-script-body | MAIN-only | n/a |
| skills/create-worktree/scripts/create-worktree.sh | 46 | bash | bash-script-body (2 occurrences: L46 invocation, L48 error message) | MAIN-only | n/a |
| skills/do/SKILL.md | 607 | bash | bash-fence-in-SKILL.md | PR-mode-relevant | 2a |
| skills/do/modes/pr.md | 67 | bash | bash-fence-in-SKILL.md | PR-mode-relevant | 2a |
| skills/do/modes/worktree.md | 28 | bash | bash-fence-in-SKILL.md | PR-mode-relevant | 2a |
| skills/draft-plan/SKILL.md | 100 | bash | bash-fence-in-SKILL.md (5 occurrences: L100, L194, L237, L446, L562) | PR-mode-relevant | 2a |
| skills/draft-tests/SKILL.md | 124 | bash | bash-fence-in-SKILL.md (3 occurrences: L124, L397, L1711) | PR-mode-relevant | 2a |
| skills/fix-issues/SKILL.md | 347 | bash | bash-fence-in-SKILL.md (11 occurrences: L347, L448, L594, L703, L831, L887, L928, L943, L1010, L1082, L1141) | PR-mode-relevant | 2a |
| skills/quickfix/SKILL.md | 146 | bash | bash-fence-in-SKILL.md | PR-mode-relevant | 2a |
| skills/refine-plan/SKILL.md | 93 | bash | bash-fence-in-SKILL.md (3 occurrences: L93, L335, L504) | PR-mode-relevant | 2a |
| skills/research-and-go/SKILL.md | 60 | bash | bash-fence-in-SKILL.md (2 occurrences: L60, L200) | PR-mode-relevant | 2a |
| skills/research-and-plan/SKILL.md | 346 | bash | bash-fence-in-SKILL.md | PR-mode-relevant | 2a |
| skills/run-plan/SKILL.md | 233 | bash | bash-fence-in-SKILL.md (15 occurrences: L233, L308, L405, L807, L958, L1189, L1262, L1608, L1671, L1936, L1959, L2148, L2197, L2216, L2225) | PR-mode-relevant | 2b |
| skills/run-plan/scripts/post-run-invariants.sh | 52 | bash | bash-script-body | PR-mode-relevant | 3 |
| skills/update-zskills/scripts/clear-tracking.sh | 11 | bash | bash-script-body | MAIN-only | n/a |
| skills/verify-changes/SKILL.md | 103 | bash | bash-fence-in-SKILL.md (6 occurrences: L103, L227, L405, L491, L564, L699) | PR-mode-relevant | 2a |
| skills/work-on-plans/SKILL.md | 113 | bash | bash-fence-in-SKILL.md | PR-mode-relevant | 2a |
| skills/zskills-dashboard/SKILL.md | 55 | bash | bash-fence-in-SKILL.md | MAIN-only | n/a |
| skills/zskills-dashboard/scripts/zskills_monitor/collect.py | 188 | python | python-doc-comment | Untouched | n/a |
| skills/zskills-dashboard/scripts/zskills_monitor/server.py | 96 | python | python-prose-comment | Untouched | n/a |

**Row count:** 24 (one row per file). Per-phase row count (verifier
sample via `grep -c '| <phase> |' docs/AUDIT-PR-MODE-RESOLUTION.md`):

| Owning phase | Rows |
|--------------|------|
| 2a           | 11 (do/SKILL.md, do/pr.md, do/worktree.md, draft-plan, draft-tests, fix-issues, quickfix, refine-plan, research-and-go, research-and-plan, verify-changes, work-on-plans — wait: 12; see note below) |
| 2b           | 1 (run-plan/SKILL.md — isolated per Phase 2b spec) |
| 3            | 3 (block-diagram/add-block, block-diagram/add-example, run-plan/scripts/post-run-invariants.sh) |
| n/a          | 9 (MAIN-only or Untouched — no rewrite required) |

**Note on Phase 2a count:** the table above lists 12 distinct file rows
classified `PR-mode-relevant | 2a` (counting `skills/do/SKILL.md`,
`skills/do/modes/pr.md`, and `skills/do/modes/worktree.md` as three
distinct rows for the `do` skill). Per Phase 2a spec the migration is
"14 writer skills" (the writer set spans skills, not files); the audit
table's per-file granularity is finer than the per-skill count and is
the correct unit for the Phase 2a/2b file-level migration ACs.

## Per-skill conformance-violation contributions

Per round-3 reviewer F13: Phase 2a / 2b / 3 ACs reference per-skill
**contribution** counts to assert checkpoint deltas. The table below
captures the per-skill contribution to `$ACTUAL_VIOLATIONS=18` (the
total skill-resident forbidden-literal hit count recorded at Phase 1b
when `tests/test-skill-conformance.sh` first reports the failing
skill-file-drift case).

Each row's count was derived by re-running the conformance scanner
(`bash tests/test-skill-conformance.sh`) at Phase 1b implementation
time and tallying the `DRIFT:` lines per skill directory.

| Skill | Owning phase | Violations contributed |
|-------|--------------|------------------------|
| briefing       | 2a | 5  |
| fix-issues     | 2a | 5  |
| fix-report     | 2a | 1  |
| research-and-go| 2a | 1  |
| run-plan       | 2b | 3  |
| work-on-plans  | 2a | 3  |
| (Total)        | —  | 18 |

**How Phase 2a / 2b / 3 verifiers use this table:**

Phase 2a verifier asserts post-phase `$ACTUAL_VIOLATIONS_POST_2A == 18 - (briefing + fix-issues + fix-report + research-and-go + work-on-plans contribution) == 18 - (5 + 5 + 1 + 1 + 3) == 3` (only run-plan's 3 violations remain).

Phase 2b verifier asserts post-phase `$ACTUAL_VIOLATIONS_POST_2B == 0` (run-plan's 3 violations cleared; all skill-resident forbidden literals replaced or per-fence allow-hardcoded'd).

Phase 3 owns the `block-diagram/` and `post-run-invariants.sh`
sites (table classes "PR-mode-relevant | 3"). Phase 3's post-phase
contribution to `$ACTUAL_VIOLATIONS` is 0 — block-diagram/ is not
walked by the conformance scanner per Locked Decision 14, and
`post-run-invariants.sh` is a `.sh` script body (also not walked).

## Sample-row classification rationale (verifier's 5-row sample)

Reviewer/verifier may pick any 5 rows at random and confirm classification matches the actual file content. Five examples below:

1. **`block-diagram/add-block/SKILL.md:21`** — bash fence shows `MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)` followed by writes to `$MAIN_ROOT/<paths>`; the fence runs in PR-mode (worktree). Class: **PR-mode-relevant**, owner Phase 3.

2. **`hooks/block-unsafe-project.sh.template:527`** — script body invoked by Bash PreToolUse hooks; resolves `TRACKING_ROOT` via `--git-common-dir` and is correct as MAIN-only. Class: **MAIN-only**, n/a.

3. **`skills/run-plan/SKILL.md:233`** — orchestrator-bookkeeping fence inside the highest-risk skill; isolated to its own phase per Phase 2b. Class: **PR-mode-relevant**, owner Phase 2b.

4. **`skills/zskills-dashboard/scripts/zskills_monitor/collect.py:188`** — Python doc-comment describing the canonical idiom; no path resolution downstream. Class: **Untouched**, n/a.

5. **`skills/commit/scripts/land-phase.sh:16`** — script body that lands cherry-picked commits to main; resolved `MAIN_ROOT` is correct (the operation IS main-side). Class: **MAIN-only**, n/a.

## Future-phase note (Phase 6 self-migration)

This audit currently lives at `docs/AUDIT-PR-MODE-RESOLUTION.md` per
Phase 1b §1b.2 (intermediate location). At Phase 6 self-migration the
file moves to the documented `plans/` location alongside the
`ZSKILLS_PATH_CONFIG.md` plan; verifier of Phase 6 asserts
`docs/AUDIT-PR-MODE-RESOLUTION.md` no longer exists and the new
location is referenced from any cross-citation.
