---
title: Restructure /run-plan and Siblings with Progressive Disclosure
created: 2026-04-18
status: active
---

# Plan: Restructure /run-plan and Siblings with Progressive Disclosure

## Overview

Restructure `/run-plan`, `/fix-issues`, `/do`, and `/commit` to follow
Anthropic's progressive-disclosure pattern for skill authoring: a lean
`SKILL.md` that dispatches, with mode-specific procedures extracted to
`modes/*.md` and large auxiliary procedures extracted to `references/*.md`.

This is **pure reorganization**: no semantic changes, no behavior changes,
no "improvements" during extraction. Byte-preservation of extracted
content is a hard acceptance criterion for every phase. Bugs or gaps
discovered during extraction are filed as issues and handled in a
separate plan; this plan does not expand in scope.

**Why now.** `skills/run-plan/SKILL.md` is 2,532 lines — roughly 5× the
500-line target Anthropic documents in [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices).
PR mode (+~300 lines, landed 2026-04-13) and chunked finish auto
(+~600 lines, restored 2026-04-15) account for most of the recent growth.
Canary coverage is unusually fresh (CANARY10 PR-mode E2E passed 2026-04-16;
CI fix cycle canary landed in PR #35 on 2026-04-17), giving us a strong
safety net for a bulk-text-movement restructure. Further accretion (FIX_PR_STATE_RATE_LIMIT,
FIX_WORKTREE_POISONED_BRANCH) is imminent — restructuring before those
land is cheaper than restructuring after.

**Design principle (answers the user's "per-mode complete with overlap"
question).** Each `modes/<mode>.md` is **self-contained** — the mode file
alone plus SKILL.md is sufficient to execute the mode end to end. Small
procedures duplicated across modes (stash+cherry-pick loop, rebase
conflict agent dispatch) are inlined into each mode file rather than
extracted to shared references. This matches Anthropic's documented
"bigquery-skill" example and respects the *"avoid deeply nested references"*
anti-pattern (one level deep only). **Exception:** procedures that exceed
~100 lines AND are genuinely invariant across modes (Failure Protocol;
chunked finish auto) go in `references/*.md` and are linked from SKILL.md.
Cross-skill sharing is **not** attempted: each skill owns its own
`modes/` and `references/` even where content overlaps, because cross-skill
relative links (`../run-plan/references/ci-fix-cycle.md`) violate the
one-level-deep principle and create fragile coupling.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — /commit restructure                                         | ⬚ | | |
| 2 — /do restructure                                             | ⬚ | | |
| 3 — /fix-issues restructure                                     | ⬚ | | |
| 4 — /run-plan restructure                                       | ⬚ | | |
| 5 — Mirror install, full canary validation, and close-out       | ⬚ | | |

### Important: line numbers in this plan are research-time anchors and will drift

All "lines N–M" references below are **approximate, captured from research at
draft time (2026-04-18)**. Before each phase begins, the implementing agent
MUST re-derive exact line ranges by running:

```
grep -n "^## \|^### " skills/<skill>/SKILL.md
```

and using the section **headings** (e.g., `## Phase 5c — Chunked finish auto
transition`) as ground truth. Do NOT trust absolute line numbers after any
unrelated edit has landed. At draft time, verified line-count inventory:

| Skill | Lines at research (2026-04-18) | Lines at draft time (2026-04-18) |
|-------|-------------------------------:|---------------------------------:|
| `skills/run-plan/SKILL.md`   | 2532 | **2600** |
| `skills/fix-issues/SKILL.md` | 1460 | **1460** |
| `skills/do/SKILL.md`         |  664 |  **669** |
| `skills/commit/SKILL.md`     |  412 |  **417** |

Implementers: compute the current counts first, compare to this table, and
if the delta is >50 lines on any skill, re-read the relevant section ranges
before editing.

---

## Phase 1 — /commit restructure

### Goal

Extract `/commit`'s two subcommand flows (`pr` and `land`) from `skills/commit/SKILL.md`
into `skills/commit/modes/pr.md` and `skills/commit/modes/land.md`, leaving
SKILL.md with the core commit flow + dispatch to the mode files. Warm-up
phase on the smallest skill; validates the pattern before applying to
larger skills.

### Work Items

- [ ] 1.1 Create `skills/commit/modes/` directory.
- [ ] 1.2 Extract the `## Phase 6 (PR subcommand) — PR Mode` section from
      `skills/commit/SKILL.md` into `skills/commit/modes/pr.md`. At draft time
      this section spans lines 235–328 (ending immediately before the
      `## Phase 7` heading at line 329). Re-derive the end line before editing
      by finding `## Phase 7 — Land` and using (its line number − 1) as the
      last line of the extraction range. Copy byte-for-byte; do not reword.
      Prepend exactly two lines: an H1 (`# /commit pr — PR Subcommand Mode`)
      and a blank line, followed by a one-sentence intro (≤25 words)
      explaining this file is loaded by `/commit` when the first token is `pr`.
      (Header total: 3 lines — H1, blank, intro. Verify with
      `head -3 skills/commit/modes/pr.md`.)
- [ ] 1.3 Extract the `## Phase 7 — Land` section into `skills/commit/modes/land.md`.
      At draft time this section spans lines 329–417 (end of file). Re-derive
      by running `wc -l skills/commit/SKILL.md` and using that value as the
      last line. Same byte-preservation rule. Same 3-line header
      (`# /commit land — Land Worktree Commits` + blank + one-sentence intro).
- [ ] 1.4 In `skills/commit/SKILL.md`, replace each extracted section with a
      short **active-instruction** dispatch stub. The stub MUST tell the
      executing agent to Read the mode file — passive markdown links alone
      do not trigger a Read. Paste these stubs VERBATIM (no rewording):

      Replace the entire Phase 6 PR subcommand section with:
      ```
      ## Phase 6 (PR subcommand) — PR Mode (if `pr` is the first token)

      When the first argument token is `pr`, this flow replaces Phases 1–5.

      **Read [modes/pr.md](modes/pr.md) in full and follow its procedure
      end-to-end. Do not proceed until you have read that file.**
      ```

      Replace the entire Phase 7 Land section with:
      ```
      ## Phase 7 — Land (if `land` argument)

      **Read [modes/land.md](modes/land.md) in full and follow its procedure
      end-to-end. Do not proceed until you have read that file.**
      ```
- [ ] 1.5 In `skills/commit/SKILL.md`'s Arguments section (lines 16–51), add a
      one-line note: `PR subcommand behavior is defined in [modes/pr.md](modes/pr.md);
      land behavior in [modes/land.md](modes/land.md).`
      Place this note at the end of the argument list, before the next section.
- [ ] 1.6 Capture the pre-edit original ONCE at the start of the phase:
      `git show HEAD:skills/commit/SKILL.md > /tmp/commit-original.md`.
      Record the original line count: `wc -l /tmp/commit-original.md`.
- [ ] 1.6b Verify byte-preservation of `modes/pr.md` with a specific command.
      Let `$PR_END` = (line of `## Phase 7 — Land` in original) − 1.
      Run:
      ```
      diff <(tail -n +4 skills/commit/modes/pr.md) \
           <(sed -n "235,${PR_END}p" /tmp/commit-original.md)
      ```
      (`tail -n +4` skips the 3-line header: H1 + blank + intro.)
      Expected output: empty. Any non-empty diff is a FAIL — fix the
      extraction and re-run before proceeding.
- [ ] 1.6c Verify byte-preservation of `modes/land.md` similarly.
      Let `$LAND_END` = line count of `/tmp/commit-original.md` (usually 417).
      Run:
      ```
      diff <(tail -n +4 skills/commit/modes/land.md) \
           <(sed -n "329,${LAND_END}p" /tmp/commit-original.md)
      ```
      Expected output: empty.
- [ ] 1.6d Verify the header structure of both mode files:
      `head -3 skills/commit/modes/pr.md` and
      `head -3 skills/commit/modes/land.md` each return exactly:
      line 1 = `# <title>`, line 2 = empty, line 3 = one sentence.
      - Line 1 matches `^# `: `head -1 <file> | grep -q "^# " || echo FAIL`
      - Line 2 is empty: `sed -n '2p' <file> | grep -q "^$" || echo FAIL`
      - Line 3 non-empty, ≤25 words, single line:
        `L3=$(sed -n '3p' <file>); test -n "$L3" && [ $(echo "$L3" | wc -w) -le 25 ] || echo FAIL`
      - Line 4 is the first body line (no extra blank or header lines):
        `sed -n '4p' <file>` should NOT start with `# ` or `## ` (the
        extracted body's first line is not a heading; if it is, the
        header/body boundary is off).
- [ ] 1.6e Verify tracking marker count preservation. `/commit` does not
      currently emit tracking markers (it's a commit workflow, not a
      tracked skill invocation). Sanity-check:
      ```
      grep -c 'printf.*tracking' /tmp/commit-original.md     # expected: 0
      grep -rc 'printf.*tracking' skills/commit/             # expected: same
      ```
      If the pre-edit count is non-zero, the post-edit count across SKILL.md
      + modes/*.md combined must equal it exactly.
- [ ] 1.7 Mirror to installed location safely. The mirror copy MUST NOT leave
      stale files behind:
      ```
      rm -rf .claude/skills/commit && cp -r skills/commit .claude/skills/
      diff -r skills/commit .claude/skills/commit   # expect empty
      ```
      Do NOT use `cp -r skills/commit/* .claude/skills/commit/` — that would
      leave stale files (including any previously-mirrored `modes/` content
      from a botched prior attempt) in place.
- [ ] 1.8 Smoke test: in a throwaway worktree with a trivial diff, run `/commit`
      (no args) end-to-end; verify behavior unchanged. Do NOT test `pr`/`land`
      here — those require network/real state. They are covered by the
      existing canaries run in Phase 5.
- [ ] 1.9 Commit with message `refactor(commit): extract pr and land modes to modes/`.
      Do NOT push; Phase 5 handles the end-to-end commit/push.

### Design & Constraints

**Target post-phase structure:**
```
skills/commit/
├── SKILL.md                (expected ~330 lines, down from 412)
├── modes/
│   ├── pr.md               (~90 lines: lines 235–322 content + 2-line header)
│   └── land.md             (~65 lines: lines 323–383 content + 2-line header)
```

**Line ranges are authoritative from the pre-edit file.** If `git diff` shows
shifts after Phase 0 edits (e.g., an unrelated commit has landed), re-read
the file and re-identify the section headings (`## Phase 6 (PR subcommand)`,
`## Phase 7 — Land`) and use the headings as the ground truth. Do NOT rely
on absolute line numbers after edits have occurred.

**Reviewer-agent block on lines 172–194 stays in SKILL.md.** It's in Phase 4
(Stage & Review), not Phase 6/7. Do not touch.

**The Arguments section (lines 16–51) is not extracted** — it's the public
contract and must remain in the Level 2 file per Anthropic's three-level model.

**Progressive-disclosure linking.** Links from SKILL.md to mode files use
relative paths (`[modes/pr.md](modes/pr.md)`), not absolute. The `modes/`
directory is at one level of depth from SKILL.md; mode files do NOT contain
further links to deeper references.

### Acceptance Criteria

- [ ] `skills/commit/modes/pr.md` and `skills/commit/modes/land.md` exist.
- [ ] Byte-preservation diff (Work Items 1.6b and 1.6c) is empty (zero lines)
      for BOTH mode files. Header is excluded via `tail -n +4`.
- [ ] Header structure correct (Work Item 1.6d): both mode files have a
      3-line header (H1 + blank + ≤25-word intro).
- [ ] Tracking-marker-count invariant (Work Item 1.6e): post-edit count
      across `skills/commit/SKILL.md` + `skills/commit/modes/*.md` combined
      equals pre-edit count in `/tmp/commit-original.md`.
- [ ] `skills/commit/SKILL.md` line count is within 300–355 lines after
      extraction; it contains exactly two dispatch stubs pointing at
      `modes/pr.md` and `modes/land.md` (and nothing else pointing at
      modes/*).
- [ ] `diff -r skills/commit .claude/skills/commit` returns nothing.
- [ ] `/commit` smoke test in a throwaway worktree (trivial one-file diff)
      runs to completion and produces a commit identical in structure to a
      pre-restructure `/commit` invocation. Capture both commit messages
      to `/tmp/zskills-tests/restructure-run-plan/commit-smoke.txt` and
      verify they follow the same pattern.
- [ ] No references to "modes/pr.md" or "modes/land.md" exist anywhere
      OTHER than in `skills/commit/SKILL.md` and its mirror. (Guards against
      accidental cross-skill linking.)

### Dependencies

None. This phase extracts from `skills/commit/SKILL.md` only.

---

## Phase 2 — /do restructure

### Goal

Extract `/do`'s three execution paths (Path A PR mode, Path B Worktree mode,
Path C Direct mode) from `skills/do/SKILL.md` into `skills/do/modes/pr.md`,
`skills/do/modes/worktree.md`, and `skills/do/modes/direct.md`. These paths
are already clearly separated in the source, making this the cleanest of
the three skill restructures.

### Work Items

- [ ] 2.1 Create `skills/do/modes/` directory.
- [ ] 2.2 Capture pre-edit original: `git show HEAD:skills/do/SKILL.md > /tmp/do-original.md`.
      Record line count. Re-derive the Path A/B/C section start lines via
      `grep -n "^### Path" /tmp/do-original.md`. At draft time these are:
      Path A line 283, Path B line 463, Path C line 487, followed by
      `## Phase 3 — Verify` at line 505 (which sets Path C's end as 504).
- [ ] 2.3 Extract the `### Path A: PR mode (`pr` flag)` section (starts at
      Path-A line, ends immediately before the Path-B heading) into
      `skills/do/modes/pr.md`. Prepend 3-line header (`# /do — PR Mode (Path A)`
      + blank + ≤25-word intro). Byte-preserve everything else.
- [ ] 2.4 Extract the `### Path B: Worktree mode` section (start to one line
      before Path C) into `skills/do/modes/worktree.md`. Same 3-line header
      pattern.
- [ ] 2.5 Extract the `### Path C: Direct` section (start to one line before
      `## Phase 3 — Verify`) into `skills/do/modes/direct.md`. Same 3-line
      header pattern.
- [ ] 2.6 In `skills/do/SKILL.md`, replace the entire Phase 2 body (from
      `## Phase 2 — Execute` down to one line before `## Phase 3 — Verify`)
      with an **active-instruction** dispatch stub:
      ```
      ## Phase 2 — Execute

      Select the execution path based on the parsed flags from Phase 1.5,
      then **read the corresponding mode file in full and follow its
      procedure end-to-end**. Do not proceed until you have read the file.

      | Flags include | Path | Mode file |
      |---------------|------|-----------|
      | `pr`          | A    | [modes/pr.md](modes/pr.md) |
      | `worktree`    | B    | [modes/worktree.md](modes/worktree.md) |
      | (neither)     | C    | [modes/direct.md](modes/direct.md) |
      ```
- [ ] 2.7 Phase 3 (Verify, lines 500–536), Phase 4 (Push, 537–563), and
      Phase 5 (Report, 564–612) contain path-specific branches. For each of
      these three phases, identify which branches apply to which mode, and
      decide: keep the branches in SKILL.md (if small, ≤40 lines total) OR
      move the path-specific branches into the corresponding mode file.
      **Default: keep in SKILL.md** unless doing so would break the
      "self-contained mode file" principle for Path A (PR mode), which
      exits before Phases 3–5 anyway per Path A's own report template.
      Document the decision in the commit message.
- [ ] 2.8 Verify byte-preservation for each mode file. For each of
      `modes/pr.md`, `modes/worktree.md`, `modes/direct.md`:
      ```
      diff <(tail -n +4 skills/do/modes/<name>.md) \
           <(sed -n "${start},${end}p" /tmp/do-original.md)
      ```
      where `${start}` and `${end}` are the start and end line numbers of
      the corresponding Path section in the ORIGINAL file. All three diffs
      must return empty. Also verify header structure:
      `head -3 skills/do/modes/<name>.md` has H1+blank+≤25-word intro.
- [ ] 2.8b Verify tracking-marker-count invariant:
      ```
      grep -c 'printf.*tracking' /tmp/do-original.md
      find skills/do -name '*.md' -exec grep -c 'printf.*tracking' {} + \
        | awk -F: '{s+=$2} END{print s}'
      ```
      The two numbers must match. Any mismatch means a marker was lost
      or duplicated during extraction — investigate and fix.
- [ ] 2.9 Mirror safely:
      ```
      rm -rf .claude/skills/do && cp -r skills/do .claude/skills/
      diff -r skills/do .claude/skills/do   # expect empty
      ```
- [ ] 2.10 Smoke test: `/do stop` and `/do next` (which do not actually
      execute anything) run cleanly. Verify `/do --help` or argument-parsing
      flow doesn't reference old line numbers or missing sections.
      Do NOT run a real `/do` invocation here — that's covered by targeted
      manual test in Phase 5.
- [ ] 2.11 Commit with `refactor(do): extract execution paths A/B/C to modes/`.

### Design & Constraints

**Target post-phase structure:**
```
skills/do/
├── SKILL.md                (expected ~480 lines, down from 664)
├── modes/
│   ├── pr.md               (~175 lines)
│   ├── worktree.md         (~25 lines)
│   └── direct.md           (~20 lines)
```

**Path A (PR mode)** is a full end-to-end replacement for Phases 3–5
(the `pr` flag exits after creating the PR and writing `.landed`). The
mode file MUST include its own "Report" template (lines 564–612 has a
PR-mode-specific variant), the `.landed` marker write, and CI polling
block. Self-contained per the design principle.

**Path B and Path C** fall through into Phases 3–5 of SKILL.md. Their
mode files are small and primarily document the initial branch+worktree
setup. Phases 3–5 stay in SKILL.md.

**Do NOT extract Phase 1.5 (Argument Parsing, lines 241–278).** It's
the dispatch logic itself and must live in SKILL.md — it's what decides
which mode file to load.

**Do NOT extract Meta-Commands (stop/next/now, lines 120–172).** These
are orthogonal subcommands, not modes.

**Do NOT split the cron registration / deduplication logic.** It's
shared infrastructure used by every path.

### Acceptance Criteria

- [ ] Three mode files exist; byte-preservation diff (Work Item 2.8) is
      empty for all three.
- [ ] Header structure (Work Item 2.8 last check): all three mode files
      have a 3-line header (H1 + blank + ≤25-word intro).
- [ ] Tracking-marker-count invariant (Work Item 2.8b): pre- and post-edit
      counts match.
- [ ] SKILL.md Phase 2 section is an active-instruction dispatch stub
      pointing at the three mode files and nothing else.
- [ ] `skills/do/SKILL.md` line count is 450–505 lines.
- [ ] `/do stop` and `/do next` smoke tests succeed with no error output.
      Capture output to `/tmp/zskills-tests/restructure-run-plan/do-smoke.txt`.
- [ ] `diff -r skills/do .claude/skills/do` is empty.
- [ ] No changes outside `skills/do/` and `.claude/skills/do/` directories.

### Dependencies

None structurally; proceed after Phase 1 lands so we validate the
pattern on the smallest skill first.

---

## Phase 3 — /fix-issues restructure

### Goal

Extract `/fix-issues`'s two landing modes (cherry-pick per-issue, PR
per-issue) into `skills/fix-issues/modes/cherry-pick.md` and
`skills/fix-issues/modes/pr.md`. Extract the Failure Protocol into
`skills/fix-issues/references/failure-protocol.md`. SKILL.md retains
the orchestration: Sync, Plan, Phase 0 Schedule, Phase 1 Preflight,
Phase 1b Read Bodies, Phase 2 Prioritize, Phase 3 Execute, Phase 4
Review, Phase 5 Report, plus a Phase 6 dispatch to the mode files.

### Work Items

- [ ] 3.1 Create `skills/fix-issues/modes/` and `skills/fix-issues/references/`
      directories.
- [ ] 3.2 Capture pre-edit original: `git show HEAD:skills/fix-issues/SKILL.md
      > /tmp/fix-issues-original.md`.
- [ ] 3.3 Before extraction, re-derive the landing-mode sub-section
      boundaries under Phase 6. Run
      `grep -n "^### \|^## Phase 6 \|^## Failure" /tmp/fix-issues-original.md`
      (captured via `git show HEAD:skills/fix-issues/SKILL.md > /tmp/fix-issues-original.md`).
      Identify the line ranges of: (a) the cherry-pick per-issue landing
      subsection, (b) the PR per-issue landing subsection, (c) the Phase 6
      preamble (if any) that is mode-agnostic and should stay in SKILL.md.
      At draft time: Phase 6 starts at line 964; Failure Protocol starts
      at line 1299 (so Phase 6 ends at 1298); the cherry-pick/PR sub-bounds
      are within 964–1298 and MUST be re-derived from the headings.
      Document the chosen ranges in the commit message.
- [ ] 3.4 Extract the per-issue cherry-pick landing subsection into
      `skills/fix-issues/modes/cherry-pick.md`. Prepend 3-line header
      (`# /fix-issues — Cherry-pick Mode (Per-Issue)` + blank + ≤25-word
      intro). Byte-preserve the body.
- [ ] 3.4b Extract the per-issue PR landing subsection into
      `skills/fix-issues/modes/pr.md`. Prepend same-pattern 3-line header.
      Include the entire per-issue CI polling block (5-min timeout,
      rate-limit handling, per-issue auto-merge). The block's cross-reference
      to `/run-plan`'s PR mode must be **preserved verbatim in this phase**
      — Phase 4 Work Item 4D.2 updates it later. Do NOT "improve" by inlining
      `/run-plan`'s CI cycle; that's out of scope and violates
      byte-preservation.
- [ ] 3.5 Extract the Failure Protocol section (lines 1299 to end-of-file,
      or to the line before `## Key Rules` / `## Edge Cases` if those exist;
      re-derive boundaries with grep) into
      `skills/fix-issues/references/failure-protocol.md`. Prepend 3-line
      header (`# /fix-issues — Failure Protocol` + blank + ≤25-word intro).
- [ ] 3.6 In `skills/fix-issues/SKILL.md`, replace Phase 6 Land body with an
      active-instruction dispatch stub. If Phase 6 has a mode-agnostic
      preamble (per Work Item 3.3 analysis), keep the preamble; replace
      ONLY the mode-specific body:
      ```
      ## Phase 6 — Land

      <preserve any mode-agnostic Phase 6 preamble verbatim>

      Landing is per-issue. Select the mode based on the landing-mode
      detection from the Arguments section, then **read the corresponding
      mode file in full and follow its procedure end-to-end** per-issue.
      Do not proceed until you have read the file.

      - **cherry-pick** (default) → [modes/cherry-pick.md](modes/cherry-pick.md)
      - **PR mode** → [modes/pr.md](modes/pr.md)

      Both mode files assume Phase 5 (Sprint Report) has written the
      persistent report and Phase 4 (Review) has populated the
      before-landing summary.
      ```
- [ ] 3.7 Replace the Failure Protocol section with a stub:
      ```
      ## Failure Protocol

      **Read [references/failure-protocol.md](references/failure-protocol.md)**
      for crash handling, cron cleanup, worktree restoration, and sprint
      failure reporting.
      ```
- [ ] 3.8 Verify byte-preservation for each of the three extracted files.
      For each, run:
      ```
      diff <(tail -n +4 <extracted-file>) \
           <(sed -n "${start},${end}p" /tmp/fix-issues-original.md)
      ```
      where `${start}` and `${end}` are the ranges derived in 3.3/3.5.
      All three diffs must be empty. Also verify header structure for
      each (H1 + blank + ≤25-word intro via `head -3`).
- [ ] 3.8b Verify tracking-marker-count invariant:
      ```
      grep -c 'printf.*tracking' /tmp/fix-issues-original.md
      find skills/fix-issues -name '*.md' -exec grep -c 'printf.*tracking' {} + \
        | awk -F: '{s+=$2} END{print s}'
      ```
      The two numbers must match exactly.
- [ ] 3.9 Inventory cross-references in `skills/fix-issues/SKILL.md` after
      edits. Grep for "Phase 6" and "Failure Protocol" — every remaining
      reference must either be the dispatch stub itself or a contextual
      mention (e.g., "as landed in Phase 6"). No stale "see lines 964…"
      style references.
- [ ] 3.10 Mirror safely:
      ```
      rm -rf .claude/skills/fix-issues && cp -r skills/fix-issues .claude/skills/
      diff -r skills/fix-issues .claude/skills/fix-issues   # expect empty
      ```
- [ ] 3.11 Smoke test: `/fix-issues sync` (the sync subcommand is read-only
      — tracker update + verify) runs cleanly and returns the existing
      sprint tracker state unchanged. Capture output before and after the
      restructure; they must match modulo timestamps.
- [ ] 3.12 Commit with `refactor(fix-issues): extract landing modes and
      failure protocol to modes/ and references/`.

### Design & Constraints

**Target post-phase structure:**
```
skills/fix-issues/
├── SKILL.md                         (expected ~900 lines, down from 1460)
├── modes/
│   ├── cherry-pick.md               (~145 lines)
│   └── pr.md                        (~160 lines)
└── references/
    └── failure-protocol.md          (~90 lines)
```

**Line ranges quoted above are from the research consolidation and may
drift slightly if unrelated commits land before Phase 3 starts.** The
ground truth is the section heading at extraction time. Re-derive line
ranges if necessary before editing.

**The per-issue PR cross-reference to /run-plan stays as-is.** Current
text at line 1224–1239 says "See skills/run-plan/SKILL.md 'PR mode
landing', with caveat: per-issue timeout is 5 min vs run-plan's 10 min."
After this phase, `/run-plan`'s PR mode content will be at
`skills/run-plan/modes/pr.md` — but Phase 3 does not know that yet
(Phase 4 produces it). So: keep the current reference verbatim in
`skills/fix-issues/modes/pr.md`. Phase 4 (not this phase) updates the
reference to point at the new location. This ordering is mandatory —
swapping Phase 3 and Phase 4 would require Phase 3 to know Phase 4's
output paths.

**Do NOT extract**:
- Sync command (180–293): unique to fix-issues, stays in SKILL.md.
- Plan command (294–353): unique.
- Phase 0 Schedule (354–418): shared cron registration — stays.
- Phase 1/1b/2/3/4/5: orchestration — stays.

### Acceptance Criteria

- [ ] Three extracted files exist at the expected paths.
- [ ] Byte-preservation diff is zero for each.
- [ ] `skills/fix-issues/SKILL.md` is 850–950 lines.
- [ ] `/fix-issues sync` smoke test produces output byte-identical
      (modulo timestamps and remote state) to the pre-restructure run.
- [ ] `diff -r skills/fix-issues .claude/skills/fix-issues` is empty.
- [ ] The cross-reference to `/run-plan` PR mode in `modes/pr.md` is
      still the original text. (To be updated in Phase 4.)
- [ ] Tracking-marker-count invariant (Work Item 3.8b) holds.

### Dependencies

Phase 1 and Phase 2 provide pattern validation but are not structurally
required. Phase 4 (run-plan) must come AFTER Phase 3 because Phase 4
will update the cross-reference in `skills/fix-issues/modes/pr.md` to
point at `skills/run-plan/modes/pr.md`.

---

## Phase 4 — /run-plan restructure

### Goal

The main event. Extract `/run-plan`'s four landing modes (direct, delegate,
cherry-pick, PR) from the monolithic `## Phase 6 — Land` section into
`skills/run-plan/modes/*.md`. Extract the `## Phase 5c — Chunked finish auto
transition` section into `skills/run-plan/references/finish-mode.md`. Extract
the `## Failure Protocol` and `## Run Failed — YYYY-MM-DD HH:MM` sections into
`skills/run-plan/references/failure-protocol.md`.

**At draft time (2026-04-18), the boundaries are:**
- `## Phase 5b — Plan Completion`: line 1158 (stays in SKILL.md)
- `## Phase 5c — Chunked finish auto transition`: line 1397 (EXTRACT to references/finish-mode.md)
- `## Phase 6 — Land`: line 1555 (dispatcher preamble stays; mode bodies EXTRACT)
- `## Failure Protocol`: line 2471 (EXTRACT)
- `## Run Failed — YYYY-MM-DD HH:MM`: line 2515 (EXTRACT into same references/failure-protocol.md as Failure Protocol)
- End of file: line 2600

Re-derive at implementation time; do NOT trust these absolute numbers.

### Phase 4 execution structure: four atomic sub-commits

Because this phase moves ~1,200 lines across 6 files, it is broken into
**four atomic sub-commits (4A, 4B, 4C, 4D)**. Each sub-commit is a
self-contained, verifiable, revertable unit. If any sub-commit fails the
byte-preservation or tracking-marker check, revert ONLY that sub-commit,
fix, and re-attempt. Do NOT proceed to the next sub-commit with a prior
one in a failing state.

**Sub-commits must land in order 4A → 4B → 4C → 4D.** They are NOT
independent: 4B reads the post-4A state of SKILL.md, 4C reads the post-4B
state, 4D tidies the post-4C state. Attempting to parallelize across
branches will produce a broken merge order.

**What the smoke tests at each sub-commit cover — and what they don't.**
`/run-plan next` and the parser test `/run-plan <plan> next` verify the
file loads and parses correctly (Level 1/2). They do NOT exercise any
landing dispatch — so a malformed dispatch stub that skips the Read
instruction would not be caught until Phase 5 canaries actually land.
The sub-commits' primary value is byte-preservation checkpoints with
clean revert granularity, not runtime regression detection.

Do not land to main until all four sub-commits are present, green, and
all Phase 4 acceptance criteria pass.

### Work Items — Sub-commit 4A: References (finish-mode + failure-protocol)

- [ ] 4A.1 Create `skills/run-plan/references/` directory.
- [ ] 4A.2 Capture pre-edit original ONCE:
      `git show HEAD:skills/run-plan/SKILL.md > /tmp/run-plan-original.md`
      and record the line count (expected ~2600 at draft time).
- [ ] 4A.3 Re-derive the exact line ranges:
      ```
      grep -n "^## " /tmp/run-plan-original.md
      ```
      Record: `PHASE_5C_START`, `PHASE_6_START` (= `PHASE_5C_END + 1`),
      `FAILURE_START`, `RUNFAILED_START`, `EOF` (total line count).
- [ ] 4A.4 Extract Phase 5c chunked finish auto transition into
      `skills/run-plan/references/finish-mode.md`. Byte-preserve lines
      `$PHASE_5C_START` through `$PHASE_6_START - 1`. Prepend 3-line header
      (`# /run-plan — Finish-Auto Chunked Execution` + blank + ≤25-word intro).
- [ ] 4A.5 Extract Failure Protocol + Run Failed into
      `skills/run-plan/references/failure-protocol.md` as one file.
      Byte-preserve lines `$FAILURE_START` through `$EOF`. Prepend 3-line
      header (`# /run-plan — Failure Protocol & Failed-Run Template` + blank
      + ≤25-word intro).
- [ ] 4A.6 Replace the extracted Phase 5c section in `skills/run-plan/SKILL.md`
      with an active-instruction stub:
      ```
      ## Phase 5c — Chunked finish auto transition (CRITICAL for finish auto mode)

      When `finish auto` is active and Phase 5b determined another phase
      is queued, Phase 5c transitions execution to the next phase via a
      one-shot cron.

      **Read [references/finish-mode.md](references/finish-mode.md) in full
      and follow its procedure.** It covers cron scheduling, timestamp/TZ
      handling, and Phase 5b gating. Do not proceed past Phase 5b without
      reading this file.
      ```
- [ ] 4A.7 Replace the extracted Failure Protocol + Run Failed sections
      with a single stub:
      ```
      ## Failure Protocol

      **Read [references/failure-protocol.md](references/failure-protocol.md)**
      for crash handling, cron cleanup, working-tree restoration, failure-report
      template, and user-facing failure messaging. The failed-run report
      template is in the same file.
      ```
- [ ] 4A.8 Byte-preservation verification for 4A:
      ```
      # finish-mode.md
      diff <(tail -n +4 skills/run-plan/references/finish-mode.md) \
           <(sed -n "${PHASE_5C_START},$((PHASE_6_START - 1))p" /tmp/run-plan-original.md)

      # failure-protocol.md
      diff <(tail -n +4 skills/run-plan/references/failure-protocol.md) \
           <(sed -n "${FAILURE_START},${EOF}p" /tmp/run-plan-original.md)
      ```
      Both diffs must be empty.
- [ ] 4A.9 Tracking-marker invariant for 4A (partial — only the extracted
      sections). Count markers in the pre-edit range vs the extracted files:
      ```
      grep -c 'printf.*tracking' <(sed -n "${PHASE_5C_START},$((PHASE_6_START - 1))p" /tmp/run-plan-original.md)
      grep -c 'printf.*tracking' skills/run-plan/references/finish-mode.md

      grep -c 'printf.*tracking' <(sed -n "${FAILURE_START},${EOF}p" /tmp/run-plan-original.md)
      grep -c 'printf.*tracking' skills/run-plan/references/failure-protocol.md
      ```
      Each pair must match.
- [ ] 4A.10 Smoke test: `/run-plan next` runs cleanly (read-only).
- [ ] 4A.11 Parser-readiness smoke: `/run-plan plans/RESTRUCTURE_RUN_PLAN.md next`
      runs cleanly and recognizes the plan's phases correctly. If this
      fails after 4A, the references-extraction broke parsing — investigate
      before proceeding.
      **Commit 4A**: `refactor(run-plan): extract finish-mode and failure-protocol to references/`.
      Do NOT push.

### Work Items — Sub-commit 4B: Small modes (direct, delegate, cherry-pick)

- [ ] 4B.1 Create `skills/run-plan/modes/` directory.
- [ ] 4B.2 Open `skills/run-plan/SKILL.md` (post-4A state, with finish-mode
      and failure-protocol already extracted). Re-derive the Phase 6 Land
      body boundaries:
      ```
      grep -n "^## " skills/run-plan/SKILL.md
      ```
      The Phase 6 body runs from `## Phase 6 — Land` down to one line
      before the next `##` heading (likely `## Failure Protocol` stub or
      `## Run Failed` stub or `## Key Rules`, depending on post-4A layout).
      Read that range in full. Identify structural boundaries by
      headings and narrative:
      - Phase 6 preamble + pre-landing checklist (MODE-AGNOSTIC — stays in
        SKILL.md)
      - Direct-mode body (very short; ~10 lines at draft time)
      - Delegate-mode body (~12 lines)
      - Cherry-pick / worktree-mode body (~140 lines incl. stash loop + rebase)
      - PR-mode body (EXTRACTED in sub-commit 4C — leave in place for 4B)
      Record the exact boundary line numbers in the commit message.
- [ ] 4B.3 Extract direct mode body into `skills/run-plan/modes/direct.md`.
      3-line header (`# /run-plan — Direct Landing Mode` + blank + ≤25-word
      intro). Byte-preserve the body.
- [ ] 4B.4 Extract delegate mode body into `skills/run-plan/modes/delegate.md`.
      Same pattern.
- [ ] 4B.5 Extract cherry-pick mode body into
      `skills/run-plan/modes/cherry-pick.md`. Include the stash+cherry-pick
      loop and the rebase-conflict agent dispatch block **inline** (per the
      "self-contained mode file" design principle). Same 3-line header.
- [ ] 4B.6 Replace the direct, delegate, and cherry-pick subsections of
      Phase 6 in SKILL.md with active-instruction dispatch entries. Leave
      the PR-mode section and any Phase 6 preamble intact. Temporary mixed
      state is OK — sub-commit 4C completes the PR mode extraction.

      Example replacement (mode-specific bodies become):
      ```
      **If LANDING_MODE = direct**: Read [modes/direct.md](modes/direct.md) in full and follow it.

      **If LANDING_MODE = delegate**: Read [modes/delegate.md](modes/delegate.md) in full and follow it.

      **If LANDING_MODE = cherry-pick (default)**: Read [modes/cherry-pick.md](modes/cherry-pick.md) in full and follow it.
      ```
- [ ] 4B.7 Byte-preservation verification for 4B's three mode files.
      For each: `diff <(tail -n +4 <extracted>) <(sed -n "${start},${end}p" /tmp/run-plan-original.md)`
      must be empty.
- [ ] 4B.8 Tracking-marker invariant for 4B: count markers in each extracted
      body's source range vs the corresponding mode file. Pairs must match.
- [ ] 4B.9 Smoke test: `/run-plan next` still runs cleanly.
- [ ] 4B.10 Parser-readiness smoke: `/run-plan plans/RESTRUCTURE_RUN_PLAN.md next`.
      Same rationale as 4A.11 — if parsing broke after adding the three
      dispatch stubs, catch it here, not in Phase 5.
      **Commit 4B**: `refactor(run-plan): extract direct, delegate, cherry-pick landing modes to modes/`.

### Work Items — Sub-commit 4C: PR mode (largest single extraction)

- [ ] 4C.1 Identify the PR-mode body line range in the post-4B SKILL.md.
      It is the remaining mode-specific content under Phase 6 that was not
      extracted in 4B.
- [ ] 4C.2 Extract PR-mode body into `skills/run-plan/modes/pr.md`. Include
      rebase points 1 & 2, the full CI polling + fix-cycle block, auto-merge
      request, post-merge `.landed` upgrade, and all PR-mode-specific
      tracking marker emissions. 3-line header (`# /run-plan — PR Landing
      Mode` + blank + ≤25-word intro). Byte-preserve the body.
- [ ] 4C.3 Replace the PR-mode body in SKILL.md with an active-instruction
      dispatch entry:
      ```
      **If LANDING_MODE = pr**: Read [modes/pr.md](modes/pr.md) in full and follow it.
      ```
- [ ] 4C.4 Byte-preservation verification for `modes/pr.md`. Source range
      is the PR-mode body as it appeared in `/tmp/run-plan-original.md`
      (NOT the post-4B state — always compare against the original).
      `diff <(tail -n +4 skills/run-plan/modes/pr.md) <(sed -n "${pr_start},${pr_end}p" /tmp/run-plan-original.md)`
      must be empty.
- [ ] 4C.5 Tracking-marker invariant for 4C.
- [ ] 4C.6 Whole-file tracking-marker invariant (combined across all
      sub-commits so far):
      ```
      grep -c 'printf.*tracking' /tmp/run-plan-original.md
      find skills/run-plan -name '*.md' -exec grep -c 'printf.*tracking' {} + \
        | awk -F: '{s+=$2} END{print s}'
      ```
      Must match.
- [ ] 4C.7 Smoke test: `/run-plan next` still runs cleanly.
- [ ] 4C.8 Parser-readiness smoke: `/run-plan plans/RESTRUCTURE_RUN_PLAN.md next`.
      Same rationale as 4A.11.
      **Commit 4C**: `refactor(run-plan): extract PR landing mode to modes/pr.md`.

### Work Items — Sub-commit 4D: Dispatcher cleanup + cross-reference update + mirror

- [ ] 4D.1 Tidy the Phase 6 Land section in SKILL.md. Post-4B/4C, Phase 6
      should contain:
      - The original mode-agnostic preamble (pre-landing checklist).
      - Four `**If LANDING_MODE = X**: Read [modes/X.md](modes/X.md) in
        full and follow it.` lines.
      Convert these four scattered lines into a unified dispatch block at
      the bottom of Phase 6. Preamble stays at the top. Remove any stale
      transitions or orphaned prose. Target Phase 6 section ≤30 lines of
      actual content in SKILL.md (preamble + dispatch).
- [ ] 4D.2 Update the cross-reference in `skills/fix-issues/modes/pr.md`
      (created in Phase 3). First, confirm the current state:
      ```
      grep -n "skills/run-plan" skills/fix-issues/modes/pr.md
      ```
      Expected: one or more hits pointing at `skills/run-plan/SKILL.md`.
      Then apply the replacement:
      ```
      sed -i 's#skills/run-plan/SKILL\.md#skills/run-plan/modes/pr.md#g' \
        skills/fix-issues/modes/pr.md
      ```
      This changes ONLY the link target; surrounding prose (including
      the "5-min per-issue vs 10-min per-phase" caveat) is preserved
      because sed only matches the literal path string. Verify post-edit:
      ```
      grep -n "skills/run-plan/SKILL\.md" skills/fix-issues/modes/pr.md \
        && echo FAIL || echo OK
      grep -n "skills/run-plan/modes/pr\.md"  skills/fix-issues/modes/pr.md
      ```
      First command must print `OK` (zero matches on old path). Second
      command must print at least one hit on the new path. Any other
      outcome: revert the file (`git checkout HEAD -- skills/fix-issues/modes/pr.md`)
      and investigate before retrying.
- [ ] 4D.3 Post-edit SKILL.md line count check:
      `wc -l skills/run-plan/SKILL.md`. Target 700–900 lines. If below 700,
      investigate for over-extraction; if above 900, investigate for
      incomplete extraction.
- [ ] 4D.4 Mirror install safely:
      ```
      rm -rf .claude/skills/run-plan && cp -r skills/run-plan .claude/skills/
      diff -r skills/run-plan .claude/skills/run-plan   # expect empty
      ```
      Also mirror fix-issues (since 4D.2 edited it):
      ```
      rm -rf .claude/skills/fix-issues && cp -r skills/fix-issues .claude/skills/
      diff -r skills/fix-issues .claude/skills/fix-issues   # expect empty
      ```
- [ ] 4D.5 Final smoke tests:
      `/run-plan next` and `/run-plan plans/CANARY1_HAPPY.md status`
      (if `status` subcommand exists, read-only). Capture to
      `/tmp/zskills-tests/restructure-run-plan/run-plan-smoke.txt`.
- [ ] 4D.6 Semantic tracking-marker check (addresses DA-5). Not just
      counts — verify markers still use `$PIPELINE_ID` and
      `$ZSKILLS_PIPELINE_ID` variables (not hardcoded pipeline names):
      ```
      grep -E 'tracking/(run-plan|fix-issues)\.' skills/run-plan/modes/*.md \
        skills/run-plan/references/*.md skills/run-plan/SKILL.md || echo "OK: no hardcoded pipeline IDs"
      ```
      Zero matches expected (all writes go through `$PIPELINE_ID`).
- [ ] 4D.7 Phase 6 preamble marker sanity check. The Phase 6 preamble
      (pre-landing checklist, still in SKILL.md) is mode-agnostic. It
      should NOT emit any per-mode landing marker (e.g., `.landed
      status: full` belongs in cherry-pick mode; `.landed status:
      pr-ready` belongs in PR mode). Inspect:
      ```
      awk '/^## Phase 6 — Land/,/^## /' skills/run-plan/SKILL.md \
        | head -n -1 | grep -E 'printf.*\.landed|printf.*tracking' \
        && echo "REVIEW: preamble contains marker emissions" || echo "OK"
      ```
      If any emissions are in the preamble, verify they are genuinely
      shared across all modes (e.g., a "phase-complete" marker written
      before mode selection). If they belong in a specific mode, they
      were extracted incorrectly — move them to the mode file.
- [ ] 4D.8 Parser-readiness smoke: `/run-plan plans/RESTRUCTURE_RUN_PLAN.md next`.
      Same rationale as 4A.11.
      **Commit 4D**: `refactor(run-plan): tidy Phase 6 dispatch, update
      cross-reference, mirror install`.

### Design & Constraints

**Target post-phase structure:**
```
skills/run-plan/
├── SKILL.md                           (expected 700–900 lines, down from 2532)
├── modes/
│   ├── direct.md                      (~25 lines)
│   ├── delegate.md                    (~35 lines)
│   ├── cherry-pick.md                 (~185 lines incl. stash loop + conflict block)
│   └── pr.md                          (~620 lines incl. rebase points + CI fix cycle)
└── references/
    ├── finish-mode.md                 (~450 lines: Phase 5c chunked auto)
    └── failure-protocol.md            (~100 lines: Failure Protocol + Run Failed)
```

**Phase 5c extraction is the riskiest single bulk move.** It's ~160 lines
of cron scheduling logic with subtle timestamp/TZ handling (recent fixes:
`b172366` 5-min spacing, `d1b96bb` TZ warning). Byte-preservation diff
MUST be zero — any character change here is likely a regression.

**Scope justification.** Phase 4 moves ~1,200 lines across 6 new files,
which exceeds the `/draft-plan` guideline of "~500 lines new code per phase."
This is acceptable because: (a) moved code, not new code — no new logic is
authored, so the review burden is verification-of-preservation, not
correctness review of novel work; (b) each extracted file is loaded
on-demand only when its mode is active, so context cost for a typical
invocation goes down; (c) the phase cannot split further without violating
the "one level deep" progressive-disclosure principle (a "Phase 4 that only
does references" and a "Phase 4 that only does modes" would produce an
intermediate state where mode-dispatch stubs refer to non-existent files
and break any invocation in between landings); (d) the four atomic
sub-commits (4A/4B/4C/4D) provide checkpoint granularity without fracturing
the phase.

**Ordering rationale** (answers F-4). Phases 1–3 run before Phase 4 because
restructuring the smallest skill first validates the byte-preservation
pattern, the 3-line-header convention, and the mirror workflow on a small
blast radius. The cost is one deferred cross-reference update (Work Item
4D.2) — a single-grep / single-sed fix that cannot go wrong in practice.
Swapping the order to put Phase 4 first would trade a trivial deferred
reference for a high-risk first attempt with no pattern-validation
feedback; keep the current order.

**Preamble in Phase 6 stays in SKILL.md.** The pre-landing checklist is
shared invariants that every mode relies on (pushability of main, absence
of local-only commits, test status). Duplicating it into four mode files
would violate the "change-once" property of shared-preamble content.
Per-mode bodies take over after the preamble.

**Tracking markers.** Each mode emits different markers (e.g., cherry-pick
writes `.landed status: full` after successful cherry-pick; PR mode
writes `.landed status: pr-ready` then upgrades to `full` post-merge).
These writes MUST move with the mode body into the mode file. Do NOT
leave them in SKILL.md "for safety" — that breaks the self-contained
mode-file principle and creates a bug: a mode file read in isolation
without the matching SKILL.md would skip marker emission.

**PR mode is the biggest single file at ~620 lines.** That's over the
500-line guideline itself. Acceptable because: (a) it's one complete
end-to-end procedure with no natural internal split, (b) it's only loaded
when PR mode is active, (c) splitting it further would create the nested
references anti-pattern. The 500-line target applies most strongly to
SKILL.md (Level 2, always loaded when the skill fires); mode files
(Level 3, loaded only when the specific mode is selected) are under less
pressure.

**CANARY plans are read-only artifacts** (`plans/CANARY*.md`); this phase
does NOT modify them. They stay as-is and are the Phase 5 validation input.

### Acceptance Criteria

- [ ] Four commits exist on the branch, one per sub-commit (4A, 4B, 4C, 4D).
      Each is individually revertable.
- [ ] Six extracted files exist at the expected paths with approximate line
      counts (±20%): `modes/{direct,delegate,cherry-pick,pr}.md`,
      `references/{finish-mode,failure-protocol}.md`.
- [ ] Byte-preservation diff (4A.8, 4B.7, 4C.4) is empty for each of the 6
      extracted files.
- [ ] Header structure correct for all 6 files (`head -3 <file>` returns
      H1 + blank + ≤25-word intro).
- [ ] Whole-file tracking-marker invariant (4C.6) holds: pre-edit count in
      `/tmp/run-plan-original.md` equals post-edit count across all
      `skills/run-plan/**/*.md` files combined.
- [ ] Semantic tracking-marker check (4D.6): no hardcoded pipeline IDs in
      any extracted file.
- [ ] `skills/run-plan/SKILL.md` is 700–900 lines.
- [ ] `diff -r skills/run-plan .claude/skills/run-plan` is empty.
- [ ] `diff -r skills/fix-issues .claude/skills/fix-issues` is empty (updated
      in 4D).
- [ ] `/run-plan next` smoke test succeeds with no error output.
- [ ] The cross-reference in `skills/fix-issues/modes/pr.md` now points
      at `skills/run-plan/modes/pr.md`; zero references to the old path
      (verified via grep in 4D.2).
- [ ] `/run-plan` skill frontmatter (`name`, `description`, `argument-hint`)
      is byte-identical to pre-edit (compare with
      `head -15 /tmp/run-plan-original.md` and `head -15 skills/run-plan/SKILL.md`).

### Dependencies

Phase 3 must be complete because Work Item 4D.2 edits a file created in
Phase 3. Phase 1 and Phase 2 are recommended but not strictly required.

If Phase 4 is reverted in whole, Work Item 4D.2 must be reverted as well
(`git checkout HEAD skills/fix-issues/modes/pr.md` on the 4D cross-reference
edit, or manually reverse the one-word change) so the cross-reference in
fix-issues again matches `skills/run-plan/SKILL.md`. If Phase 4 is reverted
in part (e.g., only 4C and 4D), the cross-reference is still safe to keep
on the new path IF 4A and 4B remain landed AND the pr.md file exists — but
in practice, if 4C is reverted pr.md won't exist, so the reference will
be broken. **Recovery rule:** if any Phase 4 sub-commit is reverted, also
revert 4D including the cross-reference edit.

---

## Phase 5 — Mirror install, full canary validation, and close-out

### Goal

Validate the restructure end-to-end by running the existing canary plans
that exercise the modes we moved. Confirm the mirrored install is
byte-identical to source. Write the close-out report. File issues for any
gaps discovered. Update memory to reflect the new structure.

### Work Items

- [ ] 5.0 Parser-readiness: run `/run-plan plans/RESTRUCTURE_RUN_PLAN.md next`
      (read-only schedule check) against this plan file. Verify no parse
      errors. Then inspect `/run-plan`'s Phase 1 Parse Plan logic and
      confirm the plan's Progress Tracker and Phase sections are correctly
      identified. If parse errors: fix the plan format before Phase 5
      continues.
- [ ] 5.1 Re-mirror all four skills to ensure `.claude/skills/` reflects
      the final state of `skills/`:
      ```
      for s in run-plan fix-issues do commit; do
        rm -rf ".claude/skills/$s"
        cp -r "skills/$s" ".claude/skills/$s"
      done
      diff -r skills/run-plan   .claude/skills/run-plan
      diff -r skills/fix-issues .claude/skills/fix-issues
      diff -r skills/do         .claude/skills/do
      diff -r skills/commit     .claude/skills/commit
      ```
      All four diffs must be empty.
- [ ] 5.2 Run `scripts/post-run-invariants.sh` against a clean main to
      confirm no pipeline state was left behind.
- [ ] 5.3 Run the automated canaries most likely to exercise the
      restructured paths. Capture output to `/tmp/zskills-tests/restructure-run-plan/`
      per the CLAUDE.md output-capture rule:
      ```
      TEST_OUT=/tmp/zskills-tests/restructure-run-plan
      mkdir -p "$TEST_OUT"
      ```
      Run in sequence (each against a clean worktree / main state):
      - CANARY1 (happy path, direct mode) — `/run-plan plans/CANARY1_HAPPY.md`.
        Capture to `$TEST_OUT/canary1.txt`.
      - CANARY6 (multi-PR sequential PR mode) — `/run-plan plans/CANARY6_MULTI_PR.md auto pr`.
        Capture to `$TEST_OUT/canary6.txt`.
      - CANARY7 (chunked finish cron, exercises extracted finish-mode.md) —
        `/run-plan plans/CANARY7_CHUNKED_FINISH.md finish auto every 5m now`.
        Capture to `$TEST_OUT/canary7.txt`.
      - CANARY8 (parallel pipeline isolation) — run per the canary's setup
        instructions. Capture to `$TEST_OUT/canary8.txt`.
      - CI fix cycle canary — `/ci-fix-canary` (skill-form). Captures CI
        polling + fix cycle + auto-merge. Output to `$TEST_OUT/ci-fix.txt`.
- [ ] 5.3b Sibling-skill smoke tests (addresses F-6 and DA-6). Phase 5.3
      canaries exercise `/run-plan`. The other three restructured skills
      need separate confirmation:
      - **`/commit` smoke**: in a throwaway worktree with one trivial file
        change, run `/commit`. Capture to `$TEST_OUT/commit-smoke.txt`.
        Verify it produces a commit with the expected message structure.
      - **`/do` smoke**: run `/do next` and `/do stop` in sequence. Capture
        to `$TEST_OUT/do-smoke.txt`. Verify no errors. (Read-only operations.)
      - **`/fix-issues sync` smoke**: run `/fix-issues sync`. This is
        read-only (tracker update + issue verification). Capture to
        `$TEST_OUT/fix-issues-sync.txt`. Verify the sprint tracker is
        correctly parsed and sprint state is readable.
      Any failure in this set is the same severity as a canary failure
      (5.4 policy applies).
- [ ] 5.4 For each canary output, check for: successful run-to-completion,
      no errors about missing sections or broken refs, tracking markers
      written in the right locations, `.landed` markers in the right state.
      Any failure: STOP, do not file a "fix-on-top" commit; revert the
      restructure commit(s) for the offending skill and investigate. (Per
      CLAUDE.md: no thrashing on failing fixes; two attempts max.)
      **Per-skill revert scope (addresses DA-9):** revert ONLY the phase
      related to the failing canary. CANARY1/6/7/8 and the CI fix canary
      exercise `/run-plan` → revert Phase 4 sub-commits (4D, 4C, 4B, 4A
      in reverse). `/commit` smoke failure → revert Phase 1 only. `/do`
      smoke failure → revert Phase 2 only. `/fix-issues sync` failure →
      revert Phase 3 only, AND also revert Phase 4's 4D.2 cross-reference
      edit (see Phase 4 Dependencies). Do NOT revert phases unrelated to
      the failing skill.
- [ ] 5.5 Manual spot-check for PR mode: do not run CANARY10 (hits real
      GitHub, needs operator coordination). Instead, create a minimal
      throwaway plan at `plans/_pr_smoke.md` with a single trivial phase
      (e.g., "add a comment to CHANGELOG.md"), then invoke:
      ```
      /run-plan plans/_pr_smoke.md pr
      ```
      Verify in this order:
      1. A branch matching `feat/_pr_smoke-phase-*` exists:
         `git branch | grep 'feat/_pr_smoke'`
      2. A PR is open:
         `gh pr list --head feat/_pr_smoke-phase-1 --state open`
      3. The worktree `.landed` marker has `status: pr-ready`:
         `cat <worktree-path>/.landed | grep '^status:'`
         (Worktree path is printed by `/run-plan` on completion; capture
         it from `$TEST_OUT/pr-smoke.txt`.)
      4. Close and clean up:
         `gh pr close <PR#> --delete-branch`, `rm -f plans/_pr_smoke.md`,
         `scripts/land-phase.sh` or manual worktree removal.
      Any failure here is NOT a restructure failure by default — triage
      against pre-restructure behavior first (the pre-restructure state
      for PR mode is validated by CANARY10's 2026-04-16 pass). Only
      revert if the failure is clearly tied to the restructure.
- [ ] 5.6 Update `skills/run-plan/SKILL.md`'s `description` frontmatter
      field ONLY IF the new description is clearer about the skill's
      scope. If the current description is already accurate, leave it
      alone. Same for the other three skills. This is optional cleanup;
      skip if in doubt.
- [ ] 5.7 If `plans/PLAN_INDEX.md` exists, add a row for this plan under
      the "Complete" table. Otherwise, include in the close-out report:
      "Run `/plans rebuild` to generate a plan index."
- [ ] 5.8 Update project memory entry `project_run_plan_progressive_disclosure.md`:
      - **If the outcome matches the prediction** (line counts within
        ±20% of target, extracted files match the plan, all canaries
        passed): overwrite the entry with an outcome summary
        (`status: confirmed — <date>; actual counts: ...`). Keep it short
        — it's a lesson learned, not a changelog.
      - **If the outcome diverges** (line counts off by >20%, any canary
        failed, any planned extraction skipped): DO NOT overwrite.
        Append a dated outcome section below the original prediction with
        the divergence details. Preserves the audit trail.
- [ ] 5.9 Write the close-out summary to a new file
      `reports/plan-restructure-run-plan.md` per `/run-plan` report
      conventions. Include: before/after line counts, list of extracted
      files with sizes, canaries run and results, any gaps filed as
      issues, and recommendations for further cleanup if any.
- [ ] 5.10 Mark plan `status: complete` in the frontmatter.
- [ ] 5.11 Final commit: one commit per skill was made in Phases 1–4;
      this phase commits only the index/memory/report updates and the
      status: complete flip. Commit message:
      `docs(restructure): close out progressive-disclosure restructure`.
      Do NOT push without explicit user approval (per CLAUDE.md).

### Design & Constraints

**Canary selection rationale:**
- CANARY1: validates direct mode (Phase 4's modes/direct.md).
- CANARY6: validates multi-PR sequential, the scenario that exercises
  PR mode + the extracted Phase 5c chunked finish.
- CANARY7: explicitly exercises the extracted finish-mode.md.
- CANARY8: validates parallel-pipeline isolation — restructure must not
  have broken tracking subdir naming.
- CI fix canary: exercises the modes/pr.md CI polling block.

**Why not CANARY10?** It's manually operated and hits real GitHub. Its
pre-restructure pass (2026-04-16) covered the semantic behavior we're
preserving. Re-running it is operator-intensive; a restricted PR-mode
spot-check (work item 5.5) plus the CI fix canary is sufficient coverage.

**Why not CANARY11?** It exercises scope-vs-plan LLM judgment in
`/verify-changes`, not a procedure we touched.

**Gaps policy.** If a canary surfaces a bug that was latent pre-restructure
(e.g., byte-preservation exposed a typo that was harmless only because
nothing referenced it), file a GitHub issue and **do NOT fix in this plan**.
This plan's scope is reorganization. Fixes land in a follow-up plan.

**Failure policy.** Per CLAUDE.md "never thrash on failing fix": if a
canary fails and the first fix attempt also fails, STOP. Revert the
offending phase's commit and report to the user with the error details
and hypothesis.

### Acceptance Criteria

- [ ] All four `diff -r skills/<s> .claude/skills/<s>` invocations
      return empty output.
- [ ] All five canary runs (CANARY1, CANARY6, CANARY7, CANARY8, CI fix
      canary) complete successfully with tracker/markers in expected
      states.
- [ ] Spot-check PR mode run produces a branch + PR + correct `.landed`
      marker (`status: pr-ready`).
- [ ] `reports/plan-restructure-run-plan.md` exists and documents
      before/after line counts, extracted files, canary results.
- [ ] Plan frontmatter shows `status: complete`.
- [ ] Project memory entry `project_run_plan_progressive_disclosure.md`
      is updated to reflect outcome (not the original prediction).
- [ ] No uncommitted changes in `skills/**` or `.claude/skills/**`.

### Dependencies

Phases 1–4 must all be complete and committed. If any phase was
committed with follow-up fixes, Phase 5 runs against the latest commits.

---

## Non-Goals

This plan explicitly does NOT:
- Change any skill's public contract (argument names, frontmatter,
  `disable-model-invocation`, or behavior).
- Fix bugs discovered during extraction — those are filed as issues.
- Restructure other skills (`/draft-plan`, `/refine-plan`, `/verify-changes`,
  etc.). If they need it, a separate plan.
- Introduce cross-skill `references/` sharing. Each skill owns its own
  modes/ and references/ even where content overlaps.
- Introduce a skill-authoring lint tool. Enforcement is via plan
  acceptance criteria only.
- Modify ambient scripts in `scripts/`. Those are already factored.
- Modify the tracking system. Structural preservation is asserted via
  the tracking-marker-count acceptance criterion.

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Bulk text movement loses content | Medium | Byte-preservation diff acceptance on every extracted file |
| Tracking markers accidentally dropped | Medium | Explicit marker-count invariant in Phase 4 acceptance |
| Cron timestamp/TZ handling broken in finish-mode.md | Low | CANARY7 validates chunked cron E2E |
| Cross-skill cross-reference breaks | Low | Phase 4 Work Item 4D.2 updates the one known cross-reference |
| Mirror install out of sync | Low | Phase 5 `diff -r` check on all four skills |
| In-flight plan conflicts | Low | Research confirmed no source-modifying plans actively in flight; RESTORE_CHUNKED_EXECUTION marks all phases done |
| PR mode regression not caught by automated canaries | Medium | Work Item 5.5 spot-check + reliance on CANARY10's prior pass |

## Round 1 Disposition

Round 1 surfaced 11 reviewer findings (F-1…F-11) and 10 devil's-advocate
findings (DA-1…DA-10). All were verified with the exact empirical checks
each finding requested, then dispositioned as Fixed or Justified. Summary:

| ID   | Severity | Evidence       | Disposition                                                                 |
|------|----------|----------------|-----------------------------------------------------------------------------|
| F-1  | high     | Verified       | Fixed — Phase 4 now cites section headings as ground truth, line ranges re-derived at draft time, 5c at 1397                  |
| F-2  | high     | Verified       | Fixed — Phase 1 line ranges corrected (235–328 and 329–417)                  |
| F-3  | med      | Judgment       | Fixed — all phases now use `diff <(tail -n +4 ...) <(sed -n ...)` with explicit commands |
| F-4  | med      | Judgment       | Justified — explicit ordering rationale added to Phase 4 Design & Constraints; warm-up-first preserves blast-radius control |
| F-5  | med      | Judgment       | Fixed — explicit scope justification added; sub-commit structure provides checkpoint granularity                                            |
| F-6  | med      | Verified       | Fixed — Phase 5 now includes `/commit`, `/do`, and `/fix-issues` smoke tests (5.3b)                                               |
| F-7  | med      | Verified       | Fixed — tracking-marker-count invariant added to Phases 1, 2, 3 (1.6e, 2.8b, 3.8b)                                                |
| F-8  | low      | Judgment       | Fixed — Work Item 5.5 now has explicit verification steps and `gh` commands  |
| F-9  | low      | Judgment       | Fixed — Work Item 4D.2 specifies exact grep verification                     |
| F-10 | low      | Judgment       | Fixed — 5.8 now differentiates confirmed vs divergent outcome                |
| F-11 | low      | Judgment       | Fixed — Work Item 5.0 runs `/run-plan next` against this plan                |
| DA-1 | high     | Verified (inconsistency) | Fixed — all dispatch stubs now use active "Read X in full and follow it" instruction        |
| DA-2 | med      | Verified       | Fixed — no claim of `playwright-cli/references/` precedent appears in the plan itself; research file annotation not required    |
| DA-3 | med      | Judgment       | Fixed — every phase has explicit `diff` command with `tail -n +4` (3-line header); header structure verification added          |
| DA-4 | high     | Judgment       | Fixed — Phase 4 split into four atomic sub-commits (4A/4B/4C/4D)             |
| DA-5 | med      | Judgment       | Fixed — Work Item 4D.6 adds semantic check (no hardcoded pipeline IDs)       |
| DA-6 | med      | Verified       | Fixed — merged with F-6                                                      |
| DA-7 | med      | Judgment       | Fixed — Phase 4 Dependencies now documents Phase 3/4 revert coupling         |
| DA-8 | low      | Judgment       | Justified — already addressed in plan body (PR mode at 620 lines acceptable for Level-3 file)                                   |
| DA-9 | low      | Judgment       | Fixed — Work Item 5.4 adds per-skill revert scope                            |
| DA-10| low      | Judgment       | Fixed — all mirror steps use `rm -rf <dest> && cp -r <src> <dest-parent>/`   |

**Note on verification:** F-1, F-2, DA-2 and DA-6 were empirically
reproduced during refinement (grep of section headings, ls of
`skills/playwright-cli/`, grep of plans/CANARY*.md). DA-1 was verified
as a real inconsistency in my own draft between Phase 1 (active
"Read ... and follow it") and Phase 4 (passive bullet list); fix is a
uniform "Read X in full and follow it" everywhere.

## Round 2 Disposition

Round 2 surfaced 5 reviewer findings (R2-1…R2-5) and 7 devil's-advocate
findings (DA2-1…DA2-7). Verified findings dispositioned:

| ID     | Severity | Evidence                                   | Disposition                                                                                                 |
|--------|----------|--------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| R2-1   | high     | Verified via `grep -n "4\.9"`              | Fixed — two stale "4.9" refs updated to "4D.2"                                                              |
| R2-2   | med      | Verified (FAILURE_STUB_END only in 4B.2)   | Fixed — reworded 4B.2 to `grep -n "^## "` + heading-based boundary derivation                               |
| R2-3   | med      | Judgment                                   | Fixed — 4D.2 now prescribes an explicit `sed -i` command + pre/post-grep verification                        |
| R2-4   | low      | Judgment                                   | No action — 5.0 correctly scoped (Phase 1 Parse Plan stays in SKILL.md post-refactor)                       |
| R2-5   | low      | Judgment                                   | Fixed — Phase 4 execution structure now explicitly states "Sub-commits must land in order 4A → 4B → 4C → 4D" |
| DA2-1  | med      | Judgment                                   | Fixed — Work Item 1.6d tightened: line-1 grep, line-2 empty, single-line intro, line-4 non-heading          |
| DA2-2  | med      | Judgment                                   | Justified — 5.4 per-skill revert policy covers late detection; added explicit note that sub-commit smoke tests validate parse, not landing |
| DA2-3  | low      | Judgment                                   | Justified — already covered by Phase 4 Dependencies; sed command in 4D.2 reduces botch risk                  |
| DA2-4  | med      | Judgment                                   | Fixed — parser-readiness smoke test added to every sub-commit (4A.11, 4B.10, 4C.8, 4D.8)                    |
| DA2-5  | med      | Judgment                                   | Justified — added explicit note in Phase 4 execution structure: "Smoke tests verify parse, not landing"     |
| DA2-6  | low      | Judgment                                   | Fixed — Work Item 4D.7 adds Phase 6 preamble marker sanity check                                            |
| DA2-7  | judgment | Judgment                                   | No action — meta-splitting the plan would add friction without concrete benefit; plan is already indexed by phase and has explicit sub-commit headings |

**Round 2 convergence check.** R2 produced 0 new high-severity empirical
claims that R1 missed. R2-1 was a refactor-induced regression (my own),
caught and fixed. All other R2 findings were either judgment calls on
wording precision (fixed with surgical edits) or already-justified design
trade-offs. No new substantive structural issues. **Converged.**

## Plan Quality

**Drafting process:** /draft-plan with 2 rounds of adversarial review
**Convergence:** Converged at round 2 (round 2 surfaced only surgical/wording improvements, no new structural issues)
**Remaining concerns:** None blocking execution. Two judgment calls remain explicitly as-is:
1. Sub-commit smoke tests validate parse, not landing — landing regressions are caught only by Phase 5 canaries. Trade-off accepted because running a real landing per sub-commit would be prohibitively slow.
2. Plan size (~1,200 lines) exceeds the progressive-disclosure target for skills — but this is a plan, not a skill; plans are read-once by the executing agent and don't incur repeated pre-load cost.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 11 issues         | 10 issues                 | 21/21    |
| 2     | 5 issues          | 7 issues                  | 12/12 (converged; no new structural issues) |
