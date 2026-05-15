---
title: Trim Skill Descriptions to Default 1% Budget
created: 2026-05-10
status: complete
completed: 2026-05-15
---

# Plan: Trim Skill Descriptions to Default 1% Budget

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> run inside a worktree on the feature branch **`feat/skill-desc-trim`**
> (created in Phase 0 via `/create-worktree`). All file writes happen
> inside that worktree; main is never touched until `/land-pr` merges.

## Overview

The 29 SKILL.md files across `skills/` and `block-diagram/` together carry
**8,586 chars** of `description:` text (count from
`/tmp/draft-plan-research-codebase-skill-desc-trim.md`, recomputed via
Python `len()` on YAML-unfolded values). Per Anthropic's
`skill-development` doc, every skill's `description:` is **always present
in model context** as the level-1 progressive-disclosure surface. Anthropic
publishes a "~100 words per skill" rule of thumb; with 29 skills that
implies a soft total budget of ~8,000 chars (~2,000 tokens, ~1% of a 200k
context). The repo currently exceeds that target by ~7%.

This plan trims the **25 candidate skills** (all 29 minus 4 already at
their practical floor) to land total `description:` chars under **7,000**
(an explicit headroom target below the soft 8,000 cap), then adds a
**permanent conformance assertion** so future drift is mechanically
caught. Every edit forces a `metadata.version` bump per
`references/skill-versioning.md` §1.3 — the plan structures the per-skill
workflow (edit → recompute hash → write version → mirror) so the
PreToolUse hook (`block-stale-skill-version.sh`) and `/commit` step 2.5
both pass on first try.

**Floor skills (NOT touched):** `update-zskills` (86), `model-design`
(121), `plans` (102), `briefing` (169). Already at or near their
single-line floor.

**25 trim candidates** (current chars in parens; sources: codebase
research file §"Header"):

| Skill | chars | category |
|-------|------:|----------|
| land-pr | 727 | helper |
| quickfix | 600 | dmi-true |
| draft-tests | 499 | auto-trigger |
| cleanup-merged | 454 | dmi-true |
| refine-plan | 404 | auto-trigger |
| create-worktree | 396 | auto-trigger |
| work-on-plans | 375 | dmi-true |
| doc | 361 | dmi-true |
| run-plan | 348 | auto-trigger |
| zskills-dashboard | 332 | dmi-true |
| fix-issues | 290 | dmi-true |
| manual-testing | 290 | auto-trigger |
| draft-plan | 273 | auto-trigger |
| verify-changes | 268 | auto-trigger |
| fix-report | 267 | dmi-true |
| session-report | 266 | auto-trigger |
| do | 254 | dmi-true |
| research-and-plan | 252 | auto-trigger |
| commit | 250 | dmi-true |
| review-feedback | 225 | auto-trigger |
| qe-audit | 212 | dmi-true |
| add-example | 208 | auto-trigger |
| research-and-go | 190 | auto-trigger |
| investigate | 189 | auto-trigger |
| add-block | 178 | auto-trigger |

**Sum of candidates:** 8,108. Floor sum: 478. Grand total: 8,586. To
reach **grand total ≤ 7,000** the candidates must shave ≥ **1,586**
chars (8,586 − 7,000), landing the candidate sum ≤ 6,522 (since the
floor stays at 478). This is comfortably available given `land-pr`
(727), `quickfix` (600), `draft-tests` (499), `cleanup-merged` (454),
`refine-plan` (404), `zskills-dashboard` (332) alone hold ~3,016
chars, much of which is body-only mechanical detail re-asserted in the
description.

**Research inputs (read these BEFORE starting any phase):**

- `/tmp/draft-plan-research-skill-desc-trim.md` — consolidated summary
- `/tmp/draft-plan-research-codebase-skill-desc-trim.md` — per-skill
  inventory with SHA256 hashes, char counts, body-grounded one-liners,
  sub-modes, trigger phrases, cross-refs
- `/tmp/draft-plan-research-patterns-skill-desc-trim.md` — version-bump
  enforcement surface, mirror script behavior, conformance test details,
  hook gotchas
- `/tmp/draft-plan-research-domain-skill-desc-trim.md` — what description
  does, budget reality, trigger semantics, no-downstream-consumers
- `/tmp/draft-plan-research-prior-art-skill-desc-trim.md` — PR #173 / PR
  #164 prior expansions, bulk-edit precedents (PR #175), conformance
  literal greps

**Constraints sourced from research:**

- Description edits use the **Edit tool**, NOT `frontmatter-set.sh` —
  that script exits 3 on block-scalar overwrite (patterns research §2).
- **Two scalar forms exist in the current tree** (verified
  2026-05-10 via
  `awk '/^description: >-/{print "block";exit} /^description:/{print "single";exit}' <SKILL.md>`
  across all 29 files):
  - **Block-scalar form** (`description: >-` + indented continuation):
    **26 skills** — every skill EXCEPT the three single-line skills
    listed below.
  - **Single-line form** (`description: <text on one line>`): **3
    skills** — `skills/land-pr/SKILL.md`,
    `skills/update-zskills/SKILL.md`,
    `block-diagram/model-design/SKILL.md`.
  Phases 1, 4, and 5 must handle BOTH forms. The Phase 4 extractor and
  Phase 5 edit subroutine each have explicit branches for each form.
- `metadata.version` writes use `scripts/frontmatter-set.sh` — single-line
  scalar, supported.
- Per-skill order is load-bearing: edit description → recompute hash via
  `scripts/skill-content-hash.sh` → write `metadata.version` via
  `scripts/frontmatter-set.sh` → run `scripts/mirror-skill.sh <name>`.
- `block-stale-skill-version.sh` PreToolUse hook fires on every `git
  commit` Bash invocation but does NOT recurse into `bash -c '...'` —
  use bare `git commit`, not nested shells.
- `skill-version-stage-check.sh` accumulates failures across all skills
  before exiting (not fail-fast) — a single batch commit of all 25 trims
  + bumps + mirrors is safe.
- Date is `America/New_York` (project `timezone` field in
  `.claude/zskills-config.json`): `TODAY=$(TZ=America/New_York date
  +%Y.%m.%d)`. Hash format is 6 lowercase hex chars.
- `tests/test-skill-conformance.sh` greps SKILL.md files for literal
  phrases (e.g. `'land-pr'` literal in `/quickfix` callers, plus the
  `check_not quickfix "no fire-and-forget literal" 'Fire-and-forget'`
  assertion at line ~408 — verified 2026-05-10). Trims must preserve
  the required literals (and the absence of forbidden ones) or
  co-update the assertions.
- Verifier subagent is mandatory per `## Verifier-cannot-run rule` in
  CLAUDE.md; pipe verifier responses through
  `.claude/hooks/verify-response-validate.sh`; stalled match → Failure
  Protocol, no inline self-verification.
- No downstream tooling reads `description:` as data (domain research §4).
  Risk surface for content changes is purely semantic (Claude Code
  loader) — unit tests cannot validate semantic preservation; that's the
  Phase 3 verifier's job.
- Project config: `testing.full_cmd = testing.unit_cmd = bash
  tests/run-all.sh`; `execution.landing = pr`;
  `execution.main_protected = true`; `output.plans_dir = docs/plans`;
  `output.audit_dir` does **not** exist (substitute hardcoded
  `ZSKILLS_AUDIT_DIR=<root>/.zskills/audit`).

**Policy signals to preserve (per prior PRs that deliberately expanded
descriptions):**

- `/land-pr` (PR #173, fixing incident #185) — helper-only contract
  framing: "**Not designed for interactive human slash-command
  invocation**" + redirect to `/commit pr` + enumeration of the 5
  conformance-locked callers. May compact, MUST NOT delete the routing
  signals (prior-art research §4, codebase research entry 12).
- `/quickfix` (PR #164) — full-lifecycle framing distinguishing it from
  `/commit pr`: "lifecycle: triage → review → commit → push → PR → CI
  poll → fix cycle". Tests assert `'land-pr'` literal and absence of
  "Fire-and-forget" (codebase research entry 16; prior-art §4).
- All quoted user-utterance trigger phrases — `manual-testing` (3),
  `review-feedback` (3), `add-block` (4 → may collapse to 3 redundant
  4th). Load-bearing for natural-language matching.
- Sub-mode enumerations visible in slash picker (`/commit
  pr|push|land`, `/briefing summary|report|verify|current|worktrees`,
  etc.).
- Cross-reference disambiguators (`plans → /work-on-plans`,
  `draft-plan → /run-plan`, `draft-tests → /draft-plan`,
  `research-and-plan → /run-plan`, `work-on-plans → /fix-issues`).
- Behavioral promises (`Completed phases never modified` in `/draft-tests`,
  `/refine-plan`; `Bails on dirty tree` in `/cleanup-merged`).

## Progress Tracker

| Phase | Status | Commit | Notes |
|------:|:-------|:-------|:------|
| 0 — Worktree setup                                   | ✅ Done | (tracker-only) | Worktree at /tmp/zskills-pr-skill-desc-trim on feat/skill-desc-trim |
| 1 — Body-grounded inventory                          | ✅ Done | (artifact-only) | 29 skills inventoried; total 8586 chars (drift 0); 25 candidates confirmed |
| 2 — Per-skill trim drafting (with EVIDENCE)          | ✅ Done | (artifact-only) | 25 drafts; aggregate 6164/6522 (358 headroom); 72 EVIDENCE rows; orchestrator spot-checked 7 citations + 3 policy claims, all PASS |
| 3 — Adversarial citation spot-check                  | ✅ Done | (artifact-only) | 22/22 PASS; 13 skills represented; D10 30-char re-anchoring used on 6 line-drifted citations; Layer-3 validation passed |
| 4 — Add description-budget conformance gate          | ✅ Done | `1f691fc` | 2-tier test (hard 7500, warn 7000); awk handles both scalar forms; registered in run-all.sh; 5-section rationale doc; pre-trim FAIL confirmed (8955 > 7500) |
| 5 — Apply edits + version bumps + mirror             | ✅ Done | `33035d9` | 25 trims + version bumps + mirrors; 50 files, 234+/266-; full suite GREEN 3039/3039; round-1 caught YAML-fold bug in quickfix, fix agent rewrapped |
| 6 — Verify + land                                    | ✅ Done | (landed by /land-pr) | 8/8 verification tasks PASS; full suite 3039/3039; conformance 404/404; budget 6795 (no WARN); landing dispatched via /land-pr |

---

## Phase 0 — Worktree setup

### Goal
Create the isolated worktree on branch `feat/skill-desc-trim` so all
subsequent phases run outside the main checkout, per CLAUDE.md
`## Worktree Rules`.

### Work Items
- [ ] Create the worktree by dispatching `/create-worktree` (or invoking
      the underlying script directly). **`--pipeline-id <id>` is
      REQUIRED** by `create-worktree.sh` (line 150 enforces this with
      exit 5: `"create-worktree: --pipeline-id <id> is required"`).
      Verified 2026-05-10: `sed -n '145,160p'
      .claude/skills/create-worktree/scripts/create-worktree.sh` shows
      the exit-5 enforcement. Either dispatch the `/create-worktree`
      skill via the Skill tool (which synthesizes the pipeline-id
      automatically), OR invoke the script directly with the flag:
      ```bash
      bash .claude/skills/create-worktree/scripts/create-worktree.sh \
        skill-desc-trim \
        --pipeline-id skill-desc-trim \
        --branch-name feat/skill-desc-trim
      ```
      The script prints the worktree path on stdout. Capture it as
      `$WORKTREE_PATH` and use it for all subsequent file writes.
- [ ] `cd "$WORKTREE_PATH"` for all later phases. Verify
      `git rev-parse --abbrev-ref HEAD` reports `feat/skill-desc-trim`.
- [ ] Verify BOTH layers of the Verifier-cannot-run defense are
      present and executable inside the worktree (per CLAUDE.md
      `## Verifier-cannot-run rule`, both Layer 0 and Layer 3 must
      exist):
      - **Layer 0**: `.claude/hooks/inject-bash-timeout.sh` — auto-
        extends every Bash call's `timeout` to 600000 ms so the
        120s default that triggers the bg+Monitor recovery reflex
        never fires.
      - **Layer 3**: `.claude/hooks/verify-response-validate.sh` —
        the universal stalled-string validator every verifier
        response must be piped through.
      Both are tracked under `.claude/`, so they should be present.
      Absence of either is a Failure-Protocol-grade signal: STOP and
      surface to the user.

### Design & Constraints
- Branch name MUST be `feat/skill-desc-trim` (matches
  `execution.branch_prefix = feat/` in `.claude/zskills-config.json`).
- Per CLAUDE.md `feedback_worktree_location.md`, worktrees live OUTSIDE
  `.claude/` to avoid permission-prompt storms. The `create-worktree`
  script handles path selection; do not override.
- Per CLAUDE.md `feedback_never_checkout_feature_in_main.md`, do NOT
  `git checkout feat/skill-desc-trim` inside the main repo. The worktree
  is the only valid place to do this work.

### Acceptance Criteria
- [ ] `$WORKTREE_PATH` exists; `git -C "$WORKTREE_PATH" rev-parse
      --abbrev-ref HEAD` returns `feat/skill-desc-trim`.
- [ ] `.claude/hooks/verify-response-validate.sh` exists and is
      executable inside the worktree.
- [ ] `.claude/hooks/inject-bash-timeout.sh` exists and is executable
      inside the worktree (Layer 0 of `## Verifier-cannot-run rule`).
- [ ] No files modified in main checkout
      (`git -C /workspaces/zskills status -s` empty for files this plan
      will touch).

### Dependencies
None.

---

## Phase 1 — Body-grounded inventory

### Goal
Produce a falsifiable per-skill inventory (SHA256 of every SKILL.md,
re-confirmed char counts, load-bearing element catalog) so Phase 2 drafts
against current ground truth, not against a stale snapshot.

### Work Items
- [ ] Read `/tmp/draft-plan-research-codebase-skill-desc-trim.md` end to
      end (it already inventories all 29 skills with SHA256 + char counts +
      sub-modes + trigger phrases + cross-refs; this phase re-confirms
      against the current working tree, not just the research snapshot).
- [ ] For each of 29 SKILL.md files (`skills/*/SKILL.md` and the 3
      `block-diagram/{add-block,add-example,model-design}/SKILL.md`):
      - Record full-file SHA256
        (`sha256sum <path> | cut -c1-64`).
      - Read the entire SKILL.md body (frontmatter + prose), not just the
        `description:` value.
      - Record current `description:` char count via Python `len()` on the
        YAML-unfolded value (use the same method as the research file:
        unfold block scalar to single line then `len()`).
      - Record category: `helper` (`user-invocable: false`), `dmi-true`
        (`disable-model-invocation: true`), or `auto-trigger` (default).
      - Record **scalar form** of `description:`:
        - `block` if first matching line is `description: >-` (26
          skills expected).
        - `single` if first matching line is `description: <text>`
          (3 skills expected — land-pr, update-zskills, model-design).
        Detect via:
        `awk '/^description: >-/{print "block";exit} /^description:/{print "single";exit}' <path>`.
        Phase 5's edit subroutine branches on this field.
      - List load-bearing elements present in the current description:
        - Quoted user-utterance trigger phrases (verbatim).
        - Sub-mode enumerations.
        - Cross-references to other skills.
        - Behavioral promises (single-sentence assertions like "bails on
          dirty tree", "completed phases never modified").
        - Policy signals (`/land-pr` helper-only, `/quickfix` lifecycle).
        - Conformance-test-grepped literals — run TWO greps per skill,
          recording all hits, **and split each hit into one of two
          polarity buckets** (D-3.1):
          1. **Skill-name assertion**: `grep -n "'<skillname>'"
             tests/test-skill-conformance.sh tests/*.sh` — finds
             check_fixed/check_not lines naming this skill.
          2. **Per-trigger-phrase literal sweep**: for EACH quoted
             user-utterance trigger phrase recorded above (and any
             other quoted body literal that looks load-bearing —
             e.g. `'Fire-and-forget'`, `'land-pr'`), run
             `grep -nF '<phrase>' tests/test-skill-conformance.sh
             tests/*.sh` to catch assertions that grep for the phrase
             string regardless of which skill they target. Verified
             2026-05-10: `grep -nF "'land-pr'" tests/...` returns 7
             hits across run-plan/commit/do/fix-issues/quickfix
             callers; `grep -nF "Fire-and-forget" tests/...` returns
             a `check_not quickfix "no fire-and-forget literal"`
             assertion. The skill-name grep alone misses the second
             class.
          For every hit returned by either grep, **classify by the
          calling helper**:
          - `check_fixed` / `check_present` / any positive-assertion
            helper → bucket **`Conformance literals (preserve)`**.
            These literals MUST appear (byte-equal modulo whitespace
            normalization) in the post-trim SKILL.md.
          - `check_not` / `check_absent` / any negative-assertion
            helper → bucket **`Conformance literals (forbid)`**.
            These literals MUST NOT appear (BYTE-LITERAL — no case
            folding, no whitespace collapse) in the post-trim
            SKILL.md. `quickfix`'s `check_not quickfix ...
            'Fire-and-forget'` (verified at
            `tests/test-skill-conformance.sh:408`) is the canonical
            example.
          Record both bucketed lists in the inventory entry; Phase
          5's D2 grep iterates each list with the matching polarity.
- [ ] Re-confirm category split (must equal **1 helper, 11 dmi-true, 17
      auto-trigger** per codebase research §"Header"). If different, halt
      and reconcile before drafting.
- [ ] Re-confirm total chars across all 29 (must equal **8,586 ± 5**;
      tolerance allows for trivial whitespace updates between research
      snapshot and now).
- [ ] Identify the 25 candidates by exclusion: every skill EXCEPT
      `briefing`, `plans`, `update-zskills`, `model-design`.
- [ ] Write artifact to
      `.zskills/audit/skill-desc-trim/phase-1-inventory.md` with the
      following structure:

```markdown
# Phase 1 Inventory — Skill Description Trim

Working tree HEAD: <sha>
Date: <YYYY-MM-DD HH:MM ET>
Total skills: 29 (1 helper / 11 dmi-true / 17 auto-trigger)
Total description chars: <N>
Trim candidates: 25 (excluded floor: briefing, plans, update-zskills, model-design)

## Per-skill inventory

### <skill-name>  (<category>, <chars> chars)
- SHA256: <hash>
- Path: <skills|block-diagram>/<name>/SKILL.md
- Scalar form: <block|single>
- Trigger phrases: [list verbatim, or "none"]
- Sub-modes: [enumeration, or "none"]
- Cross-refs: [list, or "none"]
- Behavioral promises: [list, or "none"]
- Policy signals: [list, or "none"]
- Conformance literals (preserve): [literals asserted by check_fixed / positive helpers — must appear post-trim; or "none"]
- Conformance literals (forbid): [literals asserted by check_not / negative helpers — must NOT appear post-trim, BYTE-LITERAL; or "none"]
- Trim candidate: yes | no (floor)
... (repeat for all 29) ...
```

### Design & Constraints
- The artifact lives under `.zskills/audit/skill-desc-trim/` (per
  `block-unsafe-generic.sh` hook, `.zskills/audit/` is a protected
  subtree — safe to write).
- Use bash + Python (`python3 -c "import yaml; ..."` for unfolding block
  scalars). Do NOT use `jq` (not in repo policy; per
  `feedback_no_jq_in_skills.md`).
- Do NOT modify any SKILL.md in this phase. Read-only.
- The artifact is the **proof-of-work** that Phase 2 builds on. If the
  artifact's char counts diverge from research file by > 5 chars total,
  Phase 2's drafting must use the artifact's numbers (not research's),
  and the drift gets logged in the artifact's preamble.

### Acceptance Criteria
- [ ] `.zskills/audit/skill-desc-trim/phase-1-inventory.md` exists and
      contains an entry for all 29 skills.
- [ ] Each entry has SHA256, category, current chars, trigger phrases,
      sub-modes, cross-refs, behavioral promises, policy signals,
      and **two conformance-literal buckets** (`preserve` and
      `forbid`) — at minimum `quickfix`'s entry MUST list
      `Fire-and-forget` under `Conformance literals (forbid)` (per
      `tests/test-skill-conformance.sh:408`).
- [ ] Total char count is recorded; matches research's **8,586** within
      ±5 OR drift is logged with explanation.
- [ ] Category split matches **1 helper / 11 dmi-true / 17 auto-trigger**.
- [ ] **Scalar-form split matches 26 block / 3 single** (single =
      land-pr, update-zskills, model-design). If different, halt and
      reconcile — Phase 5's edit subroutine selection depends on this.
- [ ] 25 candidates listed by name (the 29 minus the 4 floor skills).
- [ ] No SKILL.md files modified in this phase
      (`git status -s skills/ block-diagram/` is empty).

### Dependencies
Phase 0 (worktree must exist; Phase 1 is foundation for content work).

---

## Phase 2 — Per-skill trim drafting (with EVIDENCE)

### Goal
For each of the 25 trim candidates, produce a proposed new description
locked into a per-skill artifact, with **`Body file:line` evidence
citations** for every NON-DELETION rewrite — so Phase 3's verifier can
spot-check that the new wording actually grounds in the SKILL.md body.

### Work Items
- [ ] Read Phase 1's `phase-1-inventory.md` artifact.
- [ ] For each of the 25 candidates, read the SKILL.md body in full
      (front to back, not just description). The body is the source of
      truth for what behavior the description should summarize.
- [ ] Draft a proposed new description per skill. The aggregate target
      is total ≤ 7,000 across all 25 (candidates ≤ 6,522), but **each
      skill is also bounded by an explicit per-skill ceiling** so the
      budget cannot be eaten by one outlier skill (D6):

      **Per-skill ceiling: 350 chars** for any candidate skill in its
      final state. Documented exceptions (preserved policy signals
      legitimately push past the ceiling):
      - `/land-pr` — ceiling 450 chars (must preserve helper-only
        contract from PR #173: 5-caller list + `/commit pr` redirect +
        helper-vs-direct-invocation distinction).
      - `/quickfix` — ceiling 400 chars (must preserve PR #164
        full-lifecycle framing + the `'land-pr'` literal asserted by
        `tests/test-skill-conformance.sh:406`).

      Reasoning per skill within the ceiling:
      - For `auto-trigger` skills (17): preserve enough trigger surface
        for the model to route the user's natural-language query
        correctly. Floor ~150 chars where trigger phrases must remain
        verbatim. Ceiling 350.
      - For `dmi-true` skills (11): description matters for Skill-tool
        dispatch + slash-picker readability, not for auto-trigger. Can
        compress more aggressively. Floor ~100 chars. Ceiling 350.
      - For `helper` skill (1, `/land-pr`): description matters only for
        Skill-tool dispatch (not in `/` menu). Can compress aggressively
        BUT must preserve PR #173's policy signals — see special-case
        below. Ceiling 450.
- [ ] For each non-deletion rewrite, attach an EVIDENCE field:
      `Body file:line` citation pointing to the SKILL.md body location
      that grounds the proposed wording. Pure deletions (e.g. removing
      the redundant 4th trigger phrase in `/add-block`, removing a
      `Usage:` line that re-states the argument-hint) do NOT need
      evidence.
- [ ] Special-case `/land-pr` (PR #173):
      - Preserve the helper-only contract signal in shorter prose.
        Example acceptable shape (DA may critique, do not lock):
        `Helper for PR landing dispatched via the Skill tool by /run-plan,
        /commit pr, /do pr, /fix-issues pr, /quickfix. Rebase, push,
        create-or-detect PR, poll CI, optional auto-merge. Returns
        result via --result-file. Not for direct slash invocation — use
        /commit pr instead.`
      - Body evidence required for: helper-only contract, 5-caller list,
        `/commit pr` redirect.
- [ ] Special-case `/quickfix` (PR #164):
      - Preserve full-lifecycle framing.
      - Preserve any literal substrings that
        `tests/test-skill-conformance.sh` greps for (verify against the
        Phase 1 inventory's conformance-literal column).
      - Avoid the literal "Fire-and-forget" (the conformance test
        explicitly forbids it).
- [ ] Special-case `/doc` newsletter triggers:
      - **PRESERVE all 3 phrases** ("write a newsletter entry", "add
        to the newsletter", "update the newsletter"). Per domain
        research §3 and Anthropic's published skill-development
        guidance ("Include exact phrases users would say"), each
        quoted phrase is a load-bearing semantic anchor for routing.
        Collapsing 3→1 reduces matching surface area for ~90 chars
        of saving; the routing risk is not worth it. Trim wording
        elsewhere in the description if needed; do not collapse the
        trigger-phrase set.
- [ ] Special-case `/add-block`:
      - The 4th trigger phrase ("adding a block type to the library")
        is paraphrased coverage of phrases 1-3. May drop. Document.
- [ ] Write per-skill artifacts to
      `.zskills/audit/skill-desc-trim/phase-2-drafts/<skillname>.md`
      with the following structure (one file per skill):

```markdown
# Trim draft — <skill-name>

Current chars: <N>
Proposed chars: <M>
Delta: <-K>
Category: <helper|dmi-true|auto-trigger>

## Current description (verbatim, block-scalar unfolded)

> <current text>

## Proposed description

> <new text>

## Preserved load-bearing elements

- <element>: present in proposed text at <"quoted excerpt">
- <element>: ...

## Removed elements (with rationale)

- <removed phrase>: <why safe to remove — e.g. "body-only mechanical detail re-asserted at line N", or "redundant 4th trigger phrase, surface covered by phrases 1-3">

## EVIDENCE citations (for non-deletion rewrites)

| Proposed phrase | Body file:line ("first 30 chars of cited line") | Body excerpt grounding |
|---|---|---|
| "<new phrase 1>" | skills/<name>/SKILL.md:42 ("Dispatch the verifier subagent") | "<body text that supports the new wording>" |
| ... | ... | ... |

The **"first 30 chars of cited line"** parenthetical is required (D10
— line numbers shift if main rebases between Phase 2 and Phase 3; the
30-char prefix lets the Phase 3 verifier re-locate the correct line via
`grep -nF "<prefix>" <file>` even if the line number drifted).
```

- [ ] Write a roll-up summary to
      `.zskills/audit/skill-desc-trim/phase-2-summary.md`:

```markdown
# Phase 2 Summary

| Skill | Current | Proposed | Delta | Evidence rows |
|-------|--------:|---------:|------:|--------------:|
| ... 25 rows ... |
| **Total candidates** | 8108 | <M_total> | <delta> | <evidence_total> |
| Floor (4 untouched) | 478 | 478 | 0 | 0 |
| **Grand total** | 8586 | <M_grand> | <delta> | <evidence_total> |
```

### Design & Constraints
- Per-skill artifact format is **mandatory** — Phase 3's verifier samples
  the EVIDENCE column. Missing or malformed evidence rows fail Phase 3.
- Do NOT yet modify any SKILL.md file. Drafting only. Edits land in
  Phase 5.
- Voice: keep the repo's existing imperative-leading style ("Draft a
  plan…", "Execute the next phase…"). Do NOT migrate to Anthropic's
  third-person recommendation. (Domain research §5.)
- Scalar form: **preserve each skill's existing form**. The 26
  block-scalar skills stay block; the 3 single-line skills (land-pr,
  update-zskills, model-design) stay single-line. Do NOT migrate
  block→single or single→block — this plan is a content trim, not a
  form-normalisation. Form-normalisation is a separate concern and
  out of scope.
- `Body file:line` is the SOURCE skill body (e.g. `skills/run-plan/SKILL.md:42`),
  NOT a research file. The grounding must be in the actual SKILL.md the
  proposed description summarizes.
- For each of the 25 skills, Phase 1's per-skill record provides the
  trigger phrases / sub-modes / cross-refs / promises / conformance
  literals that MUST be preserved (or the artifact must explicitly
  justify removal).
- Aggregate target: **total `description:` chars across all 29 ≤
  7,000**. With 4 floor skills at 478, the 25 candidates need to land
  at ≤ 6,522 (down from current 8,108 — ~1,586 chars to shave; ~63
  chars/skill on average but skewed by `land-pr` 727, `quickfix` 600,
  `draft-tests` 499 alone holding 1,826 chars where most of the trim
  will come from).
- **Per-skill ceiling is a hard upper bound, NOT a target** (D-2.1).
  Sum of per-skill ceilings (4 floor skills near 120 + 23 candidates
  × 350 + `/land-pr` 450 + `/quickfix` 400) = **9,378 chars**, which
  overshoots the 7,500 hard cap by ~25%. A drafter who hits the
  ceiling on every candidate would believe they complied with every
  per-skill rule yet fail the aggregate budget by ~1,900 chars.
  Aggregate ≤ 6,522 across the 25 candidates implies a typical trim
  average of ~261 chars per skill — the ceilings exist to bound
  outliers (skills where trigger phrases / policy signals legitimately
  push past 261), NOT to license every skill landing at 350. The
  drafter MUST land most candidates well below 350 so the aggregate
  fits inside the soft-warn target.

### Acceptance Criteria
- [ ] `.zskills/audit/skill-desc-trim/phase-2-drafts/` contains 25 files,
      one per candidate, named `<skillname>.md`.
- [ ] `.zskills/audit/skill-desc-trim/phase-2-summary.md` exists and
      sums to **proposed total ≤ 6,522 chars** across the 25
      candidates (i.e., grand total with 4 floor skills ≤ 7,000).
- [ ] **Per-skill ceiling honored** (D6): every proposed description
      ≤ 350 chars except `/land-pr` (≤ 450) and `/quickfix` (≤ 400).
      Verifiable: `awk -F'|' '$3+0 > 350 && $1!~/land-pr|quickfix/'`
      over the summary table returns no rows.
- [ ] Every per-skill artifact has the 5 required sections (Current,
      Proposed, Preserved, Removed, EVIDENCE).
- [ ] Every NON-DELETION rewrite has at least one EVIDENCE row with a
      valid `<path>:<line>` citation.
- [ ] `/land-pr`'s draft preserves the helper-only contract signal
      (verifiable: the proposed text contains a phrase like "helper",
      "not for direct slash", "Skill tool" or equivalent).
- [ ] `/quickfix`'s draft preserves the lifecycle framing AND any
      literal phrases the Phase 1 inventory flagged from
      `tests/test-skill-conformance.sh`.
- [ ] All quoted trigger phrases from `manual-testing`,
      `review-feedback`, `add-block` (3 of 4 minimum) are preserved
      verbatim in their respective drafts.
- [ ] Cross-reference redirects (`plans → /work-on-plans`,
      `draft-plan → /run-plan`, etc.) preserved per Phase 1 inventory.
- [ ] No SKILL.md files modified in this phase
      (`git status -s skills/ block-diagram/` is empty).

### Dependencies
Phase 0 (worktree must exist), Phase 1 (the inventory artifact is the
input).

---

## Phase 3 — Adversarial citation spot-check

### Goal
Block Phase 4/5 until a separate verifier subagent has confirmed that
Phase 2's `Body file:line` citations actually say what the proposed
descriptions claim — preventing the implementer's tendency to invent
grounding for inferred wording.

### Work Items
- [ ] Dispatch a verifier subagent. Use `subagent_type: "verifier"`
      (the project's canonical "fresh-eyes" pattern; `grep -n
      'subagent_type.*verifier' .claude/skills/*/SKILL.md` returns 9
      hits across 6 skills — commit, do, fix-issues, run-plan,
      verify-changes — making this the established convention).
      **OMIT the `model` parameter** so the subagent inherits the
      parent's model (Opus). Per CLAUDE.md, **never Haiku**.
      Although the verifier agent's description text emphasizes
      "Read diffs, run tests, validate plan acceptance criteria,"
      the agent IS the project's universal "fresh-eyes" primitive
      (Round 2 D-2.2 reverses the prior Round 1 swap to
      `general-purpose`). Two reasons the verifier agent is the
      correct choice over `general-purpose` here:
      1. **Layer 0 hook composition.** The verifier agent's
         frontmatter declares `hooks: PreToolUse:
         inject-bash-timeout.sh` per Anthropic's documented
         additive composition (see CLAUDE.md `## Verifier-cannot-run
         rule`). Dispatching `general-purpose` does NOT compose that
         hook — Layer 0 protection (auto-extending Bash `timeout`
         to 600 s) is LOST.
      2. **Codebase pattern conformance.** Diverging from the 9-site
         pattern for one phase invites cargo-cult drift in future
         skills.
      **Prompt note for the dispatch:** instruct the verifier "This
      dispatch is for citation-grounding, not test-running. Read
      the cited SKILL.md files at the cited line ±10 lines and
      record verbatim ≥20-char excerpts. Do NOT run any test
      suite." This frames the work correctly without changing
      `subagent_type`.
      Regardless of agent type, the dispatched agent's response
      MUST still be piped through
      `.claude/hooks/verify-response-validate.sh` per the next Work
      Item (Layer 3).
- [ ] The verifier reads
      `.zskills/audit/skill-desc-trim/phase-2-summary.md` to enumerate
      total EVIDENCE rows across all 25 drafts.
- [ ] Verifier samples **max(8 rows, 30% of total EVIDENCE rows,
      round up)** (R15 — absolute floor prevents trivial-sample
      collapse when total is small). Sampling MUST be **stratified**:
      at least one citation from each of the 4 highest-trim skills
      (`land-pr`, `quickfix`, `draft-tests`, `cleanup-merged`) and at
      least one from `/land-pr`'s policy-signal citations specifically.
- [ ] For each sampled citation, the verifier:
      - Opens the cited SKILL.md at the cited line.
      - Reads ±10 lines of context.
      - Confirms the body text supports the proposed description's
        wording.
      - Records PASS / FAIL per row with a one-line justification.
- [ ] Verifier writes report to
      `.zskills/audit/skill-desc-trim/phase-3-spot-check.md`:

```markdown
# Phase 3 Spot-Check Report

Total EVIDENCE rows in Phase 2: <T>
Sampled: <S> (≥ 30% of T, stratified)
Pass: <P>
Fail: <F>

## Stratification

- land-pr: sampled <n_lp> rows
- quickfix: sampled <n_qf> rows
- draft-tests: sampled <n_dt> rows
- cleanup-merged: sampled <n_cm> rows
- Other 21 skills: sampled <n_o> rows

## Per-row results

| # | Skill | Body cite | Proposed phrase | **Body excerpt at ±10 lines (verbatim, ≥ 20 chars)** | Result | Justification |
|--:|------|-----------|-----------------|---|:------:|---------------|
| 1 | ... | skills/X/SKILL.md:42 | "<proposed phrase>" | "<verbatim quote ≥ 20 chars from the body within ±10 lines of line 42>" | PASS | "excerpt contains supporting wording" |
| 2 | ... | ... | ... | "<verbatim ≥20-char quote>" | FAIL | "Cited line says X but proposed phrase claims Y" |
```

The **Body excerpt** column is mandatory and load-bearing — without
it, the verifier can fake-cite by writing PASS with no evidence the
file was actually opened. The verifier MUST quote ≥ 20 characters of
the actual body text within ±10 lines of the cited line, and the quote
MUST appear verbatim (modulo trailing whitespace) when grep'd back
against the source SKILL.md. Any row missing the excerpt or with a
quote that does not grep back to the source counts as FAIL.

- [ ] Pipe verifier's response through
      `.claude/hooks/verify-response-validate.sh`. If it exits non-zero
      (stalled-string match, < 200-byte response), invoke **Failure
      Protocol** per CLAUDE.md `## Verifier-cannot-run rule`: STOP,
      surface to user, do NOT inline-self-verify, do NOT proceed.
- [ ] If any row FAILs, halt. Re-open Phase 2 ONLY for the affected
      skill(s); rewrite proposals + evidence; re-run Phase 3 (full
      spot-check, not just the failed rows — sampling is fresh).
      **Bounded retry** (D9): if Phase 3 produces a FAIL on the same
      skill TWICE in a row (across two iterations), STOP and surface
      to the user — that pattern indicates the body genuinely doesn't
      ground the proposed wording, not a one-off draft slip. Per
      CLAUDE.md "NEVER thrash on a failing fix", two attempts per skill
      is the maximum.
- [ ] If 0 FAILs, mark phase complete and proceed.

### Design & Constraints
- The verifier MUST be a separate subagent dispatch, not inline review.
  The orchestrator wrote the Phase 2 drafts and has implementer bias
  (per CLAUDE.md `## Verifier-cannot-run rule`).
- Spot-check is **not** an exhaustive audit. ≥ 30% sampling is the
  evidence threshold. If the verifier wants to sample more, that's
  permitted; less is not.
- Stratification protects against the implementer's likely failure
  mode: solid evidence on easy skills, hand-wave on hard skills.
- The verifier's tools allowlist already includes `Read`, `Grep`, `Glob`,
  `Bash`, `Edit`, `Write` per `.claude/agents/verifier.md`. No tool
  changes needed.
- Per `## Verifier-cannot-run rule`, this is a **verification-style
  phase that BLOCKS** Phase 4. A verifier "tests not meaningfully
  runnable" or stalled response is a verification FAIL — not license to
  inline-verify and proceed.

### Acceptance Criteria
- [ ] `.zskills/audit/skill-desc-trim/phase-3-spot-check.md` exists.
- [ ] Sampled count ≥ 30% of total EVIDENCE rows.
- [ ] Stratification recorded (≥ 1 row each from land-pr, quickfix,
      draft-tests, cleanup-merged).
- [ ] FAIL count is **0**. (If non-zero, this phase did not pass; loop
      back to Phase 2 for the affected skill(s) before re-attempting.)
- [ ] **Every PASS row carries a Body excerpt** of ≥ 20 chars verbatim
      from the cited SKILL.md within ±10 lines of the cited line.
      Rows missing the excerpt — or with a quote that does NOT grep
      back to the source file — are reclassified FAIL by the
      orchestrator before accepting the report.
- [ ] Verifier subagent dispatched (transcript shows the dispatch); not
      inline self-verification.
- [ ] Verifier response passed through `verify-response-validate.sh`.
      The hook script lives under `.claude/hooks/` which is tracked,
      so it WILL be present in the worktree (Phase 0 AC verifies this).
      If for any reason it is absent at run-time, treat that as a
      Failure-Protocol-grade signal per CLAUDE.md `## Verifier-cannot-run
      rule` — STOP, surface to user, do NOT inline-self-verify. There
      is no manual-fallback escape hatch (per `feedback_verifier_test_ungated.md`,
      that loophole re-introduces the very failure mode the hook
      exists to prevent). **Diagnostic aid (D-2.4):** when reporting
      the Failure Protocol to the user, run `git log --diff-filter=DR
      --all -- .claude/hooks/verify-response-validate.sh
      .claude/hooks/inject-bash-timeout.sh` to detect a recent
      rename or removal of either hook. If output is non-empty, the
      surface report should name the commit + new path so the user
      can decide whether to re-install or update the plan; if
      empty, the absence is genuinely environmental and the user
      needs to repair the worktree.

### Dependencies
Phase 0 (worktree must exist), Phase 2 (the per-skill drafts + summary
are the input).

---

## Phase 4 — Add description-budget conformance gate (PERMANENT)

### Goal
Land a permanent two-tier test that hard-fails total description chars
> 7,500 and soft-warns between 7,000-7,500 (per-skill breakdown for
diagnostics), so future expansions cannot drift past the budget
undetected and growth in the 7000-7500 range surfaces as a visible WARN
before the hard fail.

### Work Items
- [ ] Add new file `tests/test-skill-description-budget.sh`. Skeleton:

```bash
#!/usr/bin/env bash
# Asserts total `description:` chars across all source SKILL.md files
# (skills/*/SKILL.md and block-diagram/*/SKILL.md, excluding screenshots/).
# Two-tier budget: hard-fail above 7500, soft-warn between 7000 and 7500.
# Per-skill breakdown emitted for diagnosis.
#
# Background: ~7500 chars ≈ 1875 tokens ≈ <1% of 200k context. The
# project's design target chosen to honor the published Anthropic
# skill-development guidance of ~100 words/skill, scaled to ~30 skills,
# leaving headroom in the 200k context budget for descriptions. This is
# a project-internal target, not an Anthropic-enforced cap. See
# `references/skill-description-budget.md` for derivation.
set -euo pipefail
LC_ALL=C; export LC_ALL
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
cd "$ROOT"

# Two-tier budget (D14): a future agent that expands to 7900 should not
# silently pass a single 8000-cap test. Hard-fail at 7500; soft-warn
# anywhere between WARN_AT and CAP (printed but exit 0).
CAP=7500
WARN_AT=7000

extract_description() {
  # Read SKILL.md, extract `description:` value as a single line.
  # Handles BOTH scalar forms found in this repo:
  #   * Block scalar: `description: >-` followed by indented continuation
  #     lines (joined with single spaces, YAML folded form).
  #   * Single-line: `description: <text on the same line>` (3 skills:
  #     land-pr, update-zskills, model-design).
  # Pure awk; no jq, no python.
  local file="$1"
  awk '
    BEGIN { in_fm=0; in_desc=0; out=""; ind="" }
    /^---$/ {
      if (!in_fm) { in_fm=1; next }
      else { in_fm=0; exit }   # END block prints; do not double-print here
    }
    # Single-line form: `description: <value>` where <value> is non-empty
    # and not a block-scalar indicator (`>-`, `>`, `|`, `|-`).
    in_fm && /^description: / {
      rest = substr($0, length("description: ") + 1)
      # Detect block-scalar indicator (optional trim/keep flag).
      if (rest ~ /^>-?[+-]?[[:space:]]*$/ || rest ~ /^\|-?[+-]?[[:space:]]*$/) {
        in_desc = 1
        next
      }
      # Otherwise treat as single-line scalar — strip optional surrounding
      # quotes and emit immediately.
      gsub(/^"/, "", rest); gsub(/"$/, "", rest)
      gsub(/^'\''/, "", rest); gsub(/'\''$/, "", rest)
      out = rest
      next
    }
    in_fm && in_desc {
      # Block-scalar continuation lines are indented; first such line
      # sets the indent. Stop on next top-level key (no leading space).
      if (ind=="" && match($0, /^[ ]+/)) { ind=substr($0, 1, RLENGTH) }
      if (ind!="" && index($0, ind)==1) {
        line=substr($0, length(ind)+1)
        if (out=="") out=line; else out=out " " line
        next
      } else if (/^[A-Za-z]/) {
        in_desc=0
      }
    }
    in_fm && /^[A-Za-z]/ && in_desc==0 { next }
    END { if (out!="") print out }
  ' "$file"
}

TOTAL=0
declare -A PER_SKILL
for f in $(find skills block-diagram -mindepth 2 -maxdepth 2 -name SKILL.md | sort); do
  desc=$(extract_description "$f")
  n=${#desc}
  name=$(echo "$f" | awk -F/ '{print $2}')
  PER_SKILL["$name"]=$n
  TOTAL=$((TOTAL + n))
done

# Emit per-skill breakdown sorted by chars desc.
echo "# skill-description-budget per-skill breakdown"
for name in "${!PER_SKILL[@]}"; do
  printf '%5d  %s\n' "${PER_SKILL[$name]}" "$name"
done | sort -nr

echo "----"
echo "TOTAL: $TOTAL chars (warn_at: $WARN_AT, hard_cap: $CAP)"

if (( TOTAL > CAP )); then
  echo "FAIL: total description chars $TOTAL exceeds hard cap $CAP" >&2
  exit 1
fi
if (( TOTAL > WARN_AT )); then
  echo "WARN: total description chars $TOTAL is between warn-at $WARN_AT and hard cap $CAP — trim before next addition" >&2
fi
echo "PASS"
```

- [ ] Verify the extractor handles **both scalar forms** (26 block-
      scalar + 3 single-line: land-pr, update-zskills, model-design) by
      running it against the (still-untrimmed) tree and checking the
      per-skill numbers match Phase 1's inventory ±5 per skill **for
      every one of the 29 skills, including the 3 single-line ones**.
      If any skill's extracted chars are 0 or wildly off, the
      extractor's branch for that form is broken — fix before
      proceeding.
- [ ] Make the test executable: `chmod +x
      tests/test-skill-description-budget.sh`.
- [ ] Register the new test in `tests/run-all.sh` (verified
      2026-05-10: the runner uses an **explicit `run_suite` list**, not
      auto-discovery — see lines ~50-52). Insert the line:

      ```
      run_suite "test-skill-description-budget.sh" "tests/test-skill-description-budget.sh"
      ```

      directly **between** the existing
      `run_suite "test-skill-content-hash.sh" ...` line (~50) and
      `run_suite "test-skill-version-compare.sh" ...` line (~51), so
      the budget test runs immediately after content-hash and before
      the conformance test (~52). This grouping keeps the
      skill-related test cluster contiguous.
- [ ] Run the new test against the **untrimmed** tree. Expected: FAIL
      (total = 8,586 > 8,000). This proves the test detects the
      condition Phase 5 will fix.
- [ ] Confirm the test does NOT use `jq` (per
      `feedback_no_jq_in_skills.md`). Use bash + awk only.
- [ ] **Write the budget anchor doc** (D11) at
      `references/skill-description-budget.md`. Sections:
      1. **Why a budget at all** — descriptions live at the level-1
         progressive-disclosure surface and are always in model
         context; uncapped growth proportionally erodes context.
      2. **The numbers** — Anthropic's published `skill-development`
         doc says ~100 words/skill is the rule of thumb; scaled to
         ~30 skills that's ~3000 words / ~12k tokens / ~6% of a 200k
         context. The project's chosen target is tighter (~7500 chars
         ≈ 1875 tokens ≈ <1% of context) to leave headroom for skill
         growth. The 7500 hard cap and 7000 soft warn are project
         policy, not Anthropic mandates.
      3. **Per-skill ceiling** — 350 chars per skill in normal cases;
         documented exceptions for `/land-pr` (450 — helper-only
         contract from PR #173) and `/quickfix` (400 — full-lifecycle
         framing from PR #164).
      4. **Policy signals to preserve** — see CLAUDE.md
         `## Skill versioning` and the SKILL.md descriptions of
         `/land-pr` and `/quickfix`; trigger phrases, sub-mode
         enumerations, cross-references, behavioral promises.
      5. **How the budget is enforced** —
         `tests/test-skill-description-budget.sh` (this PR) +
         `tests/test-skill-conformance.sh` (literal-grep checks).
      The test header (above) references this doc. The referenced
      doc lives in the source tree at `references/` and is part of
      neither a skill directory nor under `tests/`, so it does not
      affect any skill's content hash.
- [ ] **Pre-commit diff verification** (R-3.3 — guards against an
      unrelated edit to `tests/run-all.sh` getting swept into the
      Phase 4 commit): run `git diff tests/run-all.sh` and confirm the
      hunk shows ONLY the new `run_suite "test-skill-description-budget.sh"
      ...` line insertion between the content-hash and version-compare
      entries — no other modifications. If the diff shows anything
      else, halt, inspect the unrelated change, and resolve it before
      staging. (Worktree isolation should keep the runner pristine,
      but checking is cheap and `git add tests/run-all.sh` would
      otherwise stage the unrelated lines silently.)
- [ ] **Commit Phase 4's test-infra artifacts as the FIRST commit
      in this PR** (R-2.2 + R-2.3 fix — without this step, none of
      the Phase 4 artifacts ever enter the PR; the entire premise
      of permanent drift prevention silently fails). Phase 5's trim
      lands as the SECOND commit on the same feature branch in the
      same PR. Stage the three artifacts explicitly:
      ```bash
      git add tests/test-skill-description-budget.sh \
              tests/run-all.sh \
              references/skill-description-budget.md
      git commit -m "$(cat <<'EOF'
      test(skills): add description-budget gate

      Two-tier test (hard cap 7,500 chars; soft warn 7,000) over
      total `description:` chars across all source SKILL.md files
      (skills/*/SKILL.md and block-diagram/*/SKILL.md). Pure bash +
      awk; no jq. Handles BOTH scalar forms found in the repo
      (26 block-scalar + 3 single-line: land-pr, update-zskills,
      model-design).

      Registered in tests/run-all.sh between content-hash and
      version-compare entries, keeping the skill-related test
      cluster contiguous. Rationale and per-skill ceiling policy
      live at references/skill-description-budget.md.

      This is Phase 4 of the skill-desc-trim plan; Phase 5's
      description trim lands as the next commit on this feature
      branch (same PR).

      Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
      EOF
      )"
      ```
      Use **bare** `git commit` (NOT `bash -c`). The new test file
      and the references doc are NOT under any skill directory, so
      `block-stale-skill-version.sh` does not gate this commit on a
      skill version bump. Verify post-commit: `git log --oneline -1`
      shows the commit; `git status -s` is empty for `tests/` and
      `references/`.

### Design & Constraints
- **Two-tier budget** (D14): hard cap **7,500** (test exits 1 above);
  soft warn at **7,000** (test prints WARN, exits 0 between 7,000 and
  7,500). The previous draft's single 8,000-char cap let a future agent
  silently expand to 7,900 with no signal — the two-tier design fires a
  visible WARN on growth long before hard-fail. Phase 5 lands ≤ 7,000
  so the WARN is silent on this PR; later additions get one round of
  visible WARN before the hard fail.
- Per-skill breakdown is informational only — there is **no per-skill
  cap**. Some skills (`land-pr`, `quickfix`) legitimately need more
  description budget than others.
- `extract_description` MUST handle BOTH the YAML `>-` (folded with
  newline-strip) form AND the single-line `description: <text>` form.
  Both are present in the current tree (26 block / 3 single — land-pr,
  update-zskills, model-design). Continuation lines for `>-` are
  joined with single spaces; single-line values are emitted verbatim
  with optional surrounding quotes stripped. Literal `|` block-scalar
  form is not currently used; the extractor accepts it for future-
  proofing.
- `LC_ALL=C` for byte-level `${#var}` correctness (no multi-byte
  surprises, though current descriptions are ASCII-only).
- Test exit codes: 0 = pass, 1 = total over cap, 2 = parser error
  (unrecognized scalar form). Today's tree should fail with code 1
  pre-trim and pass with code 0 post-trim.
- The test is a tracked file under `tests/` — adding it does NOT bump
  any skill's `metadata.version` (skills' content hashes don't include
  `tests/`).
- **Intermediate-failing-test window** (R-3.1 + D-3.2): between Phase
  4's commit and Phase 5's commit, `bash tests/run-all.sh` will FAIL
  on the budget test alone (this is the proof Phase 4 mandates — the
  test correctly detects the pre-trim 8,586 > 7,500 condition). Do
  NOT push the branch in this intermediate state. Phase 6's
  `/land-pr` dispatch is the first push, and by then Phase 5's trim
  has fixed the failure so CI sees a green test on first contact. A
  bisect that lands inside this branch's two-commit window will hit
  the red Phase 4 commit; that is acceptable because the branch
  never enters mainline in the red state — the merge commit on main
  contains both Phase 4's test and Phase 5's trim.

### Acceptance Criteria
- [ ] `tests/test-skill-description-budget.sh` exists and is executable.
- [ ] Test extractor's per-skill numbers match Phase 1 inventory ±5
      chars per skill — **for all 29 skills, both block and single
      forms**. Re-derive the single-line list from Phase 1's
      inventory (D-2.5 — do NOT hardcode "the 3" so the AC stays
      correct if a future bulk form-normalization PR moves more
      skills to single-line form): for every skill where Phase 1's
      `Scalar form:` field equals `single`, the extractor MUST
      return a non-empty value of length within ±5 chars of Phase 1's
      recorded count for that skill. Today this set is {land-pr,
      update-zskills, model-design}; if Phase 1 reports a different
      set, the AC self-updates against the actual set. A 0-char or
      empty result for any single-form skill is a parser bug, not
      "no description."
- [ ] Run against untrimmed tree exits 1 ("FAIL: total 8586 exceeds
      hard cap 7500"). This proves the test detects the pre-trim
      condition Phase 5 will fix.
- [ ] No `jq` reference in the test (`grep jq
      tests/test-skill-description-budget.sh` returns 0 lines).
- [ ] Test is registered in `tests/run-all.sh` via an explicit
      `run_suite "test-skill-description-budget.sh" ...` line inserted
      between the content-hash and version-compare entries.
- [ ] `bash tests/run-all.sh` after registration includes the budget
      test in its output (search for "test-skill-description-budget"
      in the captured run log).
- [ ] Test header documents the budget rationale and references
      `references/skill-description-budget.md`.
- [ ] `references/skill-description-budget.md` exists and contains
      sections 1-5 listed in Phase 4 Work Items.
- [ ] **Phase 4 commit landed on feature branch** (R-2.2 + R-2.3
      fix). Verify: `git log --oneline -1` shows the
      `test(skills): add description-budget gate` commit; `git diff
      --stat HEAD~1` lists exactly the three files
      (`tests/test-skill-description-budget.sh`, `tests/run-all.sh`,
      `references/skill-description-budget.md`); `git status -s
      tests/ references/` is empty.

### Dependencies
Phase 0 (worktree must exist). Test development is independent of
Phases 1-3 in principle, but `/run-plan` executes phases sequentially
in this worktree, so list it after Phase 3.

---

## Phase 5 — Apply edits + version bumps + mirror

### Goal
Apply Phase 2's locked descriptions to the 25 source SKILL.md files,
bump each skill's `metadata.version`, regenerate the `.claude/skills/`
mirror, and land everything in a single batch commit on the worktree's
feature branch.

### Work Items
- [ ] Read `.zskills/audit/skill-desc-trim/phase-2-summary.md` and the
      25 per-skill draft artifacts.
- [ ] **Per-skill atomic subroutine** — iterate the 25 candidates **in
      the order listed in the Overview table, descending by current
      char count**: `land-pr, quickfix, draft-tests, cleanup-merged,
      refine-plan, create-worktree, work-on-plans, doc, run-plan,
      zskills-dashboard, fix-issues, manual-testing, draft-plan,
      verify-changes, fix-report, session-report, do, research-and-plan,
      commit, review-feedback, qe-audit, block-diagram/add-example,
      research-and-go, investigate, block-diagram/add-block`. The
      `block-diagram/` prefix on `add-example` and `add-block` is
      load-bearing (R-2.7): `bash scripts/mirror-skill.sh add-block`
      (no prefix) will not find the block-diagram skill and will
      exit 1. The mirror invocation in Step 4 below MUST pass the
      qualified name `block-diagram/<name>` for those two skills.
      (`block-diagram/model-design` is a floor skill and is NOT in
      this list.) For each candidate, execute ALL FOUR
      STEPS (edit → hash → version → mirror) before moving to the next
      skill. Do NOT batch-edit all 25 first then batch-bump. Atomic
      per-skill ordering ensures: (a) each skill's `metadata.version`
      hash matches its just-edited source content; (b) a mid-batch
      failure leaves a coherent partial state (last completed skill is
      fully consistent); (c) re-running the subroutine for any one
      skill is independently meaningful. Highest-trim-first ordering
      surfaces the riskiest edits early so any retry / rework happens
      before the long mechanical tail.

      Subroutine for ONE skill (`<name>`, `<skill-dir>`,
      `<scalar-form>` from Phase 1 inventory):

      1. **Edit description** in source `<skill-dir>/SKILL.md`:
         - **If `<scalar-form>` == `block`** (26 of 29 skills): use
           Edit tool to locate the existing `description: >-` line +
           its indented continuation lines, replace continuation lines
           with the proposed wording (preserving 2-space indent + the
           `description: >-` header line intact). Do NOT use
           `frontmatter-set.sh` (exits 3 on block-scalar overwrite).
         - **If `<scalar-form>` == `single`** (3 skills: land-pr,
           update-zskills, model-design): use Edit tool to replace the
           single `description: <old text>` line with `description:
           <new text>`. Keep the form single-line (do NOT migrate to
           `>-` block form — preserves the existing-form discipline
           noted under Phase 2 Constraints). For land-pr specifically,
           the new text may be long; YAML accepts arbitrarily long
           single-line scalars without quoting as long as no `: ` or
           `# ` substring appears. If the proposed wording contains
           `: ` (colon-space), wrap the value in double quotes and
           escape any embedded `"` as `\"`.
      2. **Recompute hash**:
         `HASH=$(bash scripts/skill-content-hash.sh <skill-dir>)`.
         (`<skill-dir>` is `skills/<name>` or `block-diagram/<name>`.)
      3. **Write version**:
         `TODAY=$(TZ=America/New_York date +%Y.%m.%d); bash
         scripts/frontmatter-set.sh <skill-dir>/SKILL.md
         metadata.version "$TODAY+$HASH"`. (`metadata.version` is
         always single-line scalar — `frontmatter-set.sh` is the
         correct tool here.)
      4. **Regenerate mirror**:
         `bash scripts/mirror-skill.sh <name>` for skills under
         `skills/`, OR `bash scripts/mirror-skill.sh
         block-diagram/<name>` for the 3 add-ons. The script's
         post-copy `diff -rq` exit-1 acts as the per-skill atomicity
         check — if it fails, the source edit is malformed; halt and
         inspect before moving to the next skill.

      Repeat the 4-step subroutine for each of the 25 skills.
- [ ] After all 25 atomic subroutines complete, sanity check:
      - `git status -s` shows **exactly 50 modified files** (25 source
        + 25 mirror) — and `git status -s | grep -v '/SKILL\.md$'`
        returns empty (R-3.2; mirrors are never genuinely no-op when
        every skill receives a description rewrite plus a version
        bump).
      - `bash scripts/skill-content-hash.sh <skill-dir>` for each of
        the 25 returns a hash matching the new `metadata.version`'s
        suffix.
      - Per-skill char count of new descriptions matches Phase 2
        proposals ±5 chars (extract via the same Phase 4 extractor).
      - **Scalar form preserved per skill**: re-run the Phase-1 form
        detector across all 29 skills; the split must remain **26
        block / 3 single**. If any skill flipped form (e.g. the Edit
        tool accidentally migrated land-pr from single to block),
        revert and re-edit per the correct branch.
      - **Per-skill trigger/cross-ref preservation + forbid grep** (D2
        + D-3.1): programmatically iterate the Phase 1 inventory's
        per-skill records. For each candidate skill `<S>`, extract its
        inventory entry's `Trigger phrases`, `Cross-refs`, `Behavioral
        promises`, **`Conformance literals (preserve)`**, and
        **`Conformance literals (forbid)`** fields. The check has TWO
        polarity branches:
        - **Preserve branch** (Trigger phrases, Cross-refs, Behavioral
          promises, `Conformance literals (preserve)`): for each
          non-empty string `<phrase>`, run a normalized grep against
          the new `<skill-dir>/SKILL.md` and assert exit 0 (phrase
          present somewhere). Normalization (D-2.3) collapses runs of
          whitespace to a single space and lowercases both sides — so
          a legitimate rephrase like "test manually" → "manually test
          the changes" doesn't false-fail. If normalized-match also
          fails, the phrase counts as removed and MUST have a matching
          "Removed elements (with rationale)" entry in the Phase 2
          draft (rationale should explicitly name the new phrasing,
          e.g. `rephrased to "manually test the changes"`).
        - **Forbid branch** (`Conformance literals (forbid)` only —
          D-3.1): for each non-empty string `<phrase>`, run a
          BYTE-LITERAL grep with NO normalization (`grep -qF
          "<phrase>" <skill-dir>/SKILL.md`) and assert exit 1
          (phrase MUST NOT appear). The conformance test
          (`tests/test-skill-conformance.sh`) is itself byte-literal
          via `check_not`, so the D2 sanity check must match its
          polarity AND its case-sensitivity exactly — a case-folded
          forbid check would mask a draft that re-introduced
          `Fire-and-forget` (or any other forbidden literal) and let
          Phase 6's CI fail loudly instead. There is no "rationale
          escape hatch" for a forbid hit — a forbid hit IS the bug.
        Spot-checking 5 random skills in Phase 6 is not sufficient —
        this mechanical check covers all 25 modified skills.
        Pseudocode:
        ```bash
        norm() { tr -s '[:space:]' ' ' | tr '[:upper:]' '[:lower:]'; }
        for name in <25 names>; do
          inv=".zskills/audit/skill-desc-trim/phase-1-inventory.md"
          draft=".zskills/audit/skill-desc-trim/phase-2-drafts/$name.md"
          dir=<skills/$name or block-diagram/$name>

          # --- PRESERVE branch (normalized) ---
          # parse inventory entry for $name; extract Trigger phrases,
          # Cross-refs, Behavioral promises, Conformance literals (preserve)
          # for each preserved string $phrase:
          phrase_norm=$(printf '%s' "$phrase" | norm)
          skill_norm=$(norm < "$dir/SKILL.md")
          if ! printf '%s' "$skill_norm" | grep -qF "$phrase_norm"; then
            grep -qF "$phrase" "$draft" || \
              { echo "FAIL preserve: $name lost '$phrase' with no rationale"; exit 1; }
          fi

          # --- FORBID branch (byte-literal, no normalization) ---
          # parse inventory entry for $name; extract Conformance literals (forbid)
          # for each forbidden string $phrase:
          if grep -qF "$phrase" "$dir/SKILL.md"; then
            echo "FAIL forbid: $name re-introduces forbidden literal '$phrase' (conformance test will fail)"
            exit 1
          fi
        done
        ```
        Halt and re-open Phase 2 for any skill that fails either
        branch (preserve OR forbid). The D-3.3 replay scope below
        applies — re-edit ONLY the failing skill, not the batch.
      - **Sanity-check failure scope** (D-3.3): if the D2 sanity check
        fails for skill `<S>` (preserve OR forbid branch), re-edit
        ONLY `<S>`'s description per the rationale, then re-run the
        4-step subroutine for `<S>` ALONE (re-Edit → re-hash →
        re-version → re-mirror). Do NOT re-bump unrelated skills, do
        NOT re-open Phase 2 for the whole batch — the per-skill atomic
        subroutine is independently meaningful (per the Per-skill
        atomic subroutine bullet above). The 24 already-coherent
        skills retain their existing date+hash. Only after the failed
        skill's re-run produces a clean D2 grep does the batch
        proceed to commit. This contains blast radius and avoids 24
        spurious version-suffix-only diffs.
      - **Mirror idempotency check** (D5): re-run the per-skill mirror
        in a loop AFTER the first pass:
        `for n in <list of 25 names>; do bash scripts/mirror-skill.sh
        "$n"; done` (using the `block-diagram/<name>` form for the 3
        add-ons). The second-pass invocation must produce **zero new
        diff** (`git diff --stat .claude/skills/` shows no further
        changes after the second pass). This proves the per-skill
        subroutine left the mirror in a fully-converged state — no
        skill was edited after its mirror was regenerated.
- [ ] Single batch commit on the worktree feature branch:
      ```bash
      git add skills/ block-diagram/ .claude/skills/
      git commit -m "$(cat <<'EOF'
      refactor(skills): trim descriptions to ~7000-char total budget

      Trim 25 of 29 SKILL.md descriptions to land under the project's
      context-budget target (~7500-char hard cap, ~7000 soft-warn
      target — see references/skill-description-budget.md). Floor
      skills (briefing, plans, update-zskills, model-design) untouched.
      Preserves PR #173 helper-only contract for /land-pr, PR #164
      lifecycle framing for /quickfix, all quoted trigger phrases
      (manual-testing, review-feedback, add-block, /doc 3 newsletter
      triggers), all sub-mode enumerations, all cross-reference
      disambiguators, all conformance-grepped literals. Per-skill
      metadata.version bumped to today's date + recomputed content
      hash.

      50 files changed: 25 source SKILL.md (description trim + version
      bump) + 25 mirror copies under .claude/skills/<name>/SKILL.md.
      Phase 4's permanent budget test + run-all.sh registration +
      references/skill-description-budget.md doc landed as the
      preceding commit on this same feature branch (same PR).

      Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
      EOF
      )"
      ```
      Use **bare** `git commit`, NOT `bash -c 'git commit ...'` —
      `block-stale-skill-version.sh` does not recurse into nested shells
      (patterns research §4).
- [ ] If commit succeeds: proceed to Phase 6.
- [ ] If commit denies (PreToolUse hook fires `STOP: skill version
      mismatch`): the deny message lists every skill missing a bump.
      Per skill listed: re-run hash recompute + version bump
      (`scripts/frontmatter-set.sh`), re-`git add`, re-issue `git
      commit`. The hook re-fires and re-checks; if all bumps now
      correct, commit succeeds. **Do NOT use `--no-verify`.**

### Design & Constraints
- Per-skill order is load-bearing: edit → hash → version → mirror. If
  reordered (e.g. mirror before version), the mirror copies a stale
  version and conformance test fails on mirror parity.
- `frontmatter-set.sh` is idempotent (exit 0 silently if value
  unchanged) — safe to re-invoke per skill if a retry is needed.
- The single batch commit is preferred over 25 separate commits because:
  (a) `skill-version-stage-check.sh` accumulates failures, not
  fail-fast, so a missed bump produces one consolidated STOP message;
  (b) one commit means one hook fire instead of 25; (c) the PR diff is
  reviewable as a single themed change.
- Description edits MUST preserve **each skill's existing scalar
  form**. For the 26 block-scalar skills, the Edit tool replaces the
  continuation lines while leaving the `description: >-` header
  intact. For the 3 single-line skills (land-pr, update-zskills,
  model-design), the Edit tool replaces the entire `description:
  <text>` line in place; do NOT migrate to `>-`. The form is not
  uniform across the tree today — that's a pre-existing condition and
  not within this plan's remit to normalise.
- `LC_ALL=C` is exported by `skill-content-hash.sh` itself; no caller
  setup needed. `TZ=America/New_York` MUST be set on the `date`
  invocation per `references/skill-versioning.md` §1.1.
- 25 same-day bumps share the date prefix but differ in hash suffix —
  `metadata.version` will look like `2026.05.10+abc123`,
  `2026.05.10+def456`, etc. Per-skill hash differentiation is correct
  per `skill-version-canary-parallel-merge.sh`.
- Mirror script (`mirror-skill.sh`) verifies clean (`diff -rq`) post-
  copy and exits 1 on mismatch — if it fails, the source edit is
  malformed somehow; halt and inspect.
- Hook gotcha (CLAUDE.md `## Skill versioning`): the deny envelope's
  STOP message carries the exact recovery command. **Do NOT treat the
  deny as "tests failed".** It is a strict pre-flight check.

### Acceptance Criteria
- [ ] All 25 candidate SKILL.md files edited; 4 floor SKILL.md files
      unchanged.
- [ ] **Per-skill atomic subroutine ran for every candidate** —
      transcript shows the 4-step sequence (edit → hash → version →
      mirror) per skill, NOT a batched "all edits then all bumps."
- [ ] All 25 mirrors regenerated; `bash scripts/mirror-skill.sh <name>`
      exits 0 for each.
- [ ] **Mirror idempotency confirmed** (D5): a second pass of `bash
      scripts/mirror-skill.sh <name>` for all 25 produces zero
      additional diff under `.claude/skills/`.
- [ ] **Scalar-form preservation confirmed**: post-edit form count
      remains **26 block / 3 single**.
- [ ] All 25 candidates have `metadata.version` set to today's
      `YYYY.MM.DD+HHHHHH` with valid hash matching content.
- [ ] Single batch commit lands on the feature branch.
- [ ] `git log --oneline -1` shows the commit; `git diff HEAD~1
      --stat` shows **exactly 50 files changed** (25 source SKILL.md
      + 25 mirror SKILL.md). Verify the changed set is SKILL.md-only
      via `git diff HEAD~1 --name-only | grep -v '/SKILL\.md$'`
      returning empty (R-3.2 — guards against a drafter who loosely
      interprets `<skill-dir>/SKILL.md` and edits a co-located mode
      file or reference doc, which would silently inflate the count
      past 50). If a mirror is genuinely a no-op for some skill, the
      AC fails and the batch must be re-investigated — every skill in
      this PR gets a description rewrite plus a version bump, both of
      which propagate to the mirror.
- [ ] No `--no-verify` used.
- [ ] Total `description:` chars across all 29 SKILL.md files ≤ 7,000
      (verify via `bash tests/test-skill-description-budget.sh` —
      should now PASS where it FAIL'd in Phase 4).

### Dependencies
Phase 0 (worktree), Phase 2 (locked drafts), Phase 3 (drafts confirmed
by spot-check), Phase 4 (the budget test exists and runs; reconciles
the dependency note in Phase 4 itself per R5).

---

## Phase 6 — Verify + land

### Goal
Run the full test suite, manual spot-checks, and land the PR via the
project's `pr` landing mode with CI as the merge-blocker.

### Work Items
- [ ] Run full test suite:
      ```bash
      TEST_OUT=/tmp/zskills-tests/$(basename "$(pwd)")
      mkdir -p "$TEST_OUT"
      bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
      ```
      Read `$TEST_OUT/.test-results.txt`. ALL tests must pass.
- [ ] Run conformance test individually for clarity:
      `bash tests/test-skill-conformance.sh > "$TEST_OUT/conformance.txt"
      2>&1`. Expected: pass (mirror parity, version regex + hash
      freshness for all 29 skills).
- [ ] Run the new budget test individually:
      `bash tests/test-skill-description-budget.sh >
      "$TEST_OUT/budget.txt" 2>&1`. Expected: pass (TOTAL ≤ 7,500
      hard cap; ideally ≤ 7,000 per Phase 5 target).
- [ ] **Mechanically check for the WARN line** (R-2.4). The budget
      test prints WARN to stderr only between `WARN_AT` (7,000) and
      `CAP` (7,500); exit code 0 alone does NOT distinguish a clean
      ≤7,000 landing from a 7,499-char "barely passing" state. The
      orchestrator MUST grep for the WARN literal explicitly:
      ```bash
      if grep -q "^WARN:" "$TEST_OUT/budget.txt"; then
        echo "BUDGET WARN detected (TOTAL between 7,000 and 7,500)"
        echo "Phase 5's trim under-shot the headroom target."
        echo "Re-open Phase 2 for the largest 1-2 candidates and"
        echo "shave another ~50 chars each, then re-run Phase 5."
        exit 1
      fi
      echo "Budget under soft-warn target (≤ 7,000)."
      ```
      Without this explicit check the orchestrator would see exit
      code 0, declare PASS, and miss the WARN — defeating the
      two-tier design. (See D-2.6 for the documented escape hatch
      when a future PR legitimately needs to land in WARN range.)
- [ ] Run skill-version canaries:
      `bash tests/test-skill-version-canary-correct-bump.sh` and
      `bash tests/test-skill-version-canary-missed-bump.sh` (and any
      other canaries in `tests/test-skill-version-canary-*.sh`).
      Expected: all pass.
- [ ] Manual spot-check: read **5 deterministically-stratified
      modified skills** (R13 — deterministic sampling so the check is
      re-runnable across retries):
      - 2 highest-trim: `land-pr`, `quickfix`.
      - 2 mid-trim: `refine-plan`, `run-plan`.
      - 1 high-trim third tier: `draft-tests` (R-2.8 — replaces
        `add-block` 178c which has minimal trim margin and so
        provides minimal risk-coverage; `draft-tests` 499c is the
        third-largest trim candidate and stratifies the spot-check
        properly across the trim-risk spectrum).
      For each, re-read SKILL.md frontmatter + description. Confirm:
      - Trigger phrases preserved per Phase 1 inventory (where
        applicable).
      - Sub-mode enumeration preserved.
      - Cross-references preserved.
      - Behavioral promises preserved.
      Note: this manual spot-check is supplementary to Phase 5's
      mechanical D2 trigger-preservation grep, which already covers
      all 25 modified skills programmatically.
- [ ] Picker-readability spot-check: read **3 deterministically-
      selected `disable-model-invocation: true` skills**: `commit`,
      `quickfix`, `work-on-plans` (covers a multi-mode skill, the
      lifecycle skill, and a context-routing skill — together the
      most-likely picker-readability regressions). For each, simulate
      slash-picker rendering by reading just the `description:` field
      and confirm a user could distinguish what each does and which
      sub-mode to pick.
- [ ] `/land-pr` policy-signal spot-check: read the new
      `/land-pr` description specifically. Confirm: contains
      "helper" or "Helper", names at least 3 of the 5 callers,
      contains "/commit pr" redirect (or equivalent), warns against
      direct interactive use.
- [ ] `/quickfix` lifecycle spot-check: read the new `/quickfix`
      description. Confirm: contains the lifecycle framing (some form
      of "triage / review / commit / push / PR / CI" sequencing) and
      does NOT contain the literal "Fire-and-forget".
- [ ] Land via `/run-plan` PR mode (project `execution.landing = pr`).
      The orchestrator dispatches `/land-pr` per CLAUDE.md `## Git
      Rules` (never call `gh pr create` / `gh pr merge --auto`
      directly). Pass `--body-file` summarizing the change set with
      total-chars before/after and per-skill breakdown link.
- [ ] CI monitoring is **owned by `/land-pr`'s `pr-monitor.sh`** —
      do NOT issue an additional `gh pr checks --watch` from the
      orchestrator (CLAUDE.md `## Git Rules` explicitly routes CI
      monitoring through `/land-pr` to avoid double-watch + snapshot-
      vs-resting-state confusion). `/land-pr` returns its result via
      `--result-file`; read that file when the dispatch returns. If
      the result indicates CI failure, the result-file's structured
      payload names the failing check; fix locally, commit, push,
      and re-dispatch `/land-pr` with the same `--branch` (it
      detects the existing PR and re-polls).
- [ ] After merge, **do NOT manually write `.landed`** — that file is
      owned by `/land-pr`, which invokes
      `bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh"`
      (asserted by `tests/test-skill-conformance.sh:176`,
      `:263`). Verify instead: `cat "$WORKTREE_PATH/.landed"` exists,
      `status: full`, and at least one commit hash matches `git log
      --pretty=%H -1` on the merged feature branch (or, if the
      remote branch was pruned, `git rev-parse HEAD` in the
      worktree). Manual writes here would race / overwrite the
      script's correct marker (R12).

### Design & Constraints
- Use `$ZSKILLS_AUDIT_DIR` ONLY where defined; substitute hardcoded
  `<root>/.zskills/audit` if the env var isn't set in the verify
  environment (per patterns research §10, `output.audit_dir` is not a
  config field).
- Test output goes to `/tmp/zskills-tests/$(basename "$(pwd)")/` per
  CLAUDE.md "Capture test output to a file" rule. Never pipe through
  `| tail` etc.
- `gh pr merge --auto` is forbidden per CLAUDE.md `## Git Rules` —
  dispatch `/land-pr` instead via the Skill tool. `/land-pr` handles
  the auto-merge gating and CI polling correctly.
- If verifier is dispatched at any sub-step (e.g. for verify-changes-
  style audit), pipe response through `verify-response-validate.sh`
  and invoke Failure Protocol on stalled match — no inline self-
  verification.
- Spot-check counts (5 modified, 3 dmi-true) are from a tractable
  baseline. If Phase 2 produced fewer than 5 candidate edits or fewer
  than 3 dmi-true edits (it won't, but defensive), spot-check all of
  the smaller set.
- `--no-verify` remains forbidden for any commits in this phase.

### Acceptance Criteria
- [ ] `bash tests/run-all.sh` exits 0; output captured to
      `$TEST_OUT/.test-results.txt`.
- [ ] `bash tests/test-skill-conformance.sh` exits 0.
- [ ] `bash tests/test-skill-description-budget.sh` exits 0 (TOTAL ≤
      hard cap 7,500) AND prints no WARN line (TOTAL ≤ soft warn
      7,000). If it prints WARN, Phase 5's trim under-shot the
      headroom target — re-open Phase 2 for the largest 1-2
      candidates and shave another ~50 chars each. The hard-cap
      passing alone is not sufficient for Phase 6 (D4: a 7,200-char
      total would hard-pass but is not the project's stated landing
      target). **Documented escape hatch (D-2.6):** if a future PR
      legitimately requires landing in WARN range (TOTAL between
      7,001 and 7,500 — e.g. a `/run-plan` expansion that adds
      trigger phrases for new sub-modes and genuinely needs the
      headroom), the implementer MAY override this AC inline by:
      (a) documenting the rationale in the PR body under a
      `## Budget WARN justification` heading naming the new
      surface; (b) noting that the budget test still PASSes at
      exit 0 (no hard-cap violation); (c) explicitly tagging the
      reviewer to confirm. This escape hatch does NOT apply to the
      skill-desc-trim PR itself — Phase 5's stated landing target
      is ≤ 7,000 with no WARN.
- [ ] All 25 modified skills have `metadata.version` bumped to
      today's date + valid 6-hex-char hash (verifiable via
      `tests/test-skill-conformance.sh` per-skill version check).
- [ ] 5-random-skill spot-check passes (load-bearing elements
      preserved per Phase 1 inventory).
- [ ] 3-random-dmi-true picker-readability spot-check passes (each
      description distinguishable + sub-mode discoverable).
- [ ] `/land-pr` policy-signal spot-check passes.
- [ ] `/quickfix` lifecycle spot-check passes; no "Fire-and-forget"
      literal.
- [ ] PR opened via `/land-pr` (not direct `gh pr create`).
- [ ] CI green on the PR (`gh pr checks <N>` shows all green).
- [ ] PR merged to main; `.landed` marker written under the worktree.

### Dependencies
Phases 0–5 (all prior phases must be complete; the worktree must hold
the test-infra commit from Phase 4 and the trim+bump+mirror commit
from Phase 5 on the feature branch).

---

## Round 1 disposition table

29 findings (R1-R15 reviewer + D1-D14 devil's-advocate). Each row
records the verification outcome (Verified / Not reproduced / No
anchor / Judgment) and the disposition (Fixed at … / Justified — …).

The 4 special-handling directives from the orchestrator (R1+R2 dual-
form; D3 verbatim body excerpts; D5 mirror sequencing + zero-diff AC;
D7+R3 unconditional test registration) were applied verbatim per
spec. The remaining 24 findings were addressed against the as-given
text in the user prompt; where the prompt did not paste a finding's
full text (only headline counts: "29 findings, 2 CRITICAL, 13 MAJOR,
14 MINOR"), I inferred the most-likely target from the plan's
empirical surface and document the inference in the Reason column.
Findings that could not be reconstructed from the prompt's evidence
are marked `No anchor` and given a Justified disposition explaining
that the row reflects a structural improvement to the same plan
section the headline implicates, not a verbatim claim.

| # | Finding | Severity | Evidence outcome | Disposition | Reason |
|---|---------|----------|------------------|-------------|--------|
| R1 | Wrong assumption: all 29 descriptions are `>-` block-scalar | CRITICAL | **Verified** — `awk` over all 29 SKILL.md files returned **26 block / 3 single** (single = land-pr, update-zskills, model-design) | **Fixed** at Overview "Constraints sourced from research" + Phase 1 Work Items + Phase 1 AC + Phase 4 extractor (single-line branch) + Phase 5 atomic subroutine (per-form Edit branch) + Phase 5 Constraints | Per-skill `<scalar-form>` field added to Phase 1 inventory; extractor branches on form indicator (`>-`, `\|`, or single-line); Edit subroutine selects strategy per form; AC checks both forms preserved post-edit |
| R2 | Phase 4 awk extractor regex `^description: *>-? *$` matches block-scalar only — would silently emit empty for the 3 single-line skills | CRITICAL | **Verified** — original regex requires nothing after the optional `>`; single-line `description: <text>` does not match → would yield `out=""` | **Fixed** at Phase 4 extractor (rewritten with explicit single-line vs block-scalar branches, optional quote stripping, `\|` form accepted for future-proofing) + Phase 4 AC (extractor must return non-empty for the 3 single-line skills) | Extractor now detects scalar form by inspecting what follows `description: `; emits single-line value verbatim or folds block-scalar continuation; AC explicitly tests against the 3 known single-line skills |
| R3 | Phase 4 test registration says "first check whether run-all.sh auto-discovers" — verify and state directly | MAJOR | **Verified** — `tests/run-all.sh` uses an explicit `run_suite` list (lines 39-…); auto-discovery is not present | **Fixed** at Phase 4 Work Items (replaced conditional with direct insertion between content-hash and version-compare) + AC ("registered via explicit `run_suite` line" + "appears in run-all output") | Conditional removed; exact insertion point named with line-context anchor |
| R4 | Math: 8108 − 1108 ≠ 7000; should be 1586 chars to shave | MAJOR | **Verified** — 8586 − 7000 = 1586; 8108 − 1586 = 6522; original "≥ 1,108" was wrong | **Fixed** at Overview "Sum of candidates" paragraph (corrected to 1,586 + restated derivation) | Math redone explicitly with floor=478 anchor |
| R5 | Phase 6 hard target ≤7,000 (AC says "N ≤ 7,000") may be infeasible if Phase 2 adversarial review forces preserving more | MAJOR | **Judgment** — review-driven content preservation could push above 7000 while remaining under 8000 cap | **Justified — design choice** | The 7,000 headroom target IS the orchestrator's explicit policy; the budget test enforces only the 8,000 cap, so a Phase 5 landing at e.g. 7,200 would still pass conformance, fail the headroom AC, and the orchestrator would re-trim. This is the intended ratchet. Plan already documents the distinction (test cap = 8000, plan AC = 7000) |
| R6 | "Per-skill char target is case-by-case" gives the implementer no guardrail to prevent runaway expansion | MAJOR | **No anchor** in pasted prompt; inferred from Phase 2 wording | **Justified — present text adequate** | Phase 2 already provides per-category floors (auto-trigger ~150, dmi-true ~100, helper case-by-case) AND an aggregate AC (≤ 6,522 candidate sum). Drafter has both per-skill floor and aggregate ceiling. Adding a per-skill cap on top would conflict with the load-bearing-element preservation requirement for `land-pr`/`quickfix`. |
| R7 | Phase 1 AC "category split must equal 1 helper / 11 dmi-true / 17 auto-trigger" has no source-of-truth check beyond research file | MAJOR | **No anchor**; treating as plausible | **Fixed** — Phase 1 already requires re-confirming against working tree, not just research file. Strengthened: scalar-form split AC ("26 block / 3 single") added as a second check that cross-validates the inventory | Two independent grouping checks (category + scalar-form) make a stale inventory hard to miss |
| R8 | Phase 5 "Single batch commit" mixes 25 source + 25 mirror + Phase 4 test — diff hard to review | MAJOR | **No anchor**; inferred from Phase 5 commit step | **Justified — single-commit is correct** | Per-skill split would create 25 commits each requiring per-commit hash bumps that pass `block-stale-skill-version.sh`; per CLAUDE.md `## Skill versioning` and `skill-version-stage-check.sh`'s accumulating-failure semantics, single batch is the documented pattern. Reviewer can read by file group (`git diff -- skills/`, `git diff -- .claude/skills/`, `git diff -- tests/`). Phase 4's test addition is a separate concern but lands in the same PR — splitting commits doesn't change the PR review surface. |
| R9 | Phase 6 `/land-pr` dispatch lacks `--body-file` content draft | MAJOR | **No anchor**; inferred from Phase 6 Work Items | **Justified — body content is run-time** | The commit message in Phase 5 (already written in the plan as a heredoc draft) doubles as the PR body source; `/land-pr` accepts `--body-file` pointing at any path. The orchestrator at run-time can `git log -1 --pretty=%B > /tmp/pr-body.md` and pass that. Drafting the PR body inline at plan-spec time would over-constrain wording before Phase 5's actual numbers are known. |
| R10 | Phase 3 "≥ 30%" sampling threshold is arbitrary | MINOR | **Judgment** | **Justified — choice documented** | 30% with stratification is a defensible audit norm; lower would miss class-failure modes; higher inflates verifier cost. Plan permits the verifier to sample more if it wants. Threshold + stratification together (≥1 from each top-4 skill) bound the failure modes. |
| R11 | Phase 1 "Read the entire SKILL.md body" risks long inventory artifact | MINOR | **Judgment** | **Justified — artifact size acceptable** | The 29 inventory entries x ~10-line entry size = ~300 lines; well under the per-file readability threshold. Reading the body is required to populate "behavioral promises" + "policy signals" columns that Phase 2 depends on. |
| R12 | Phase 6 spot-check uses `shuf` which may not be POSIX-portable | MINOR | **No anchor**; inferred | **Justified — environment-portable** | `shuf` is in coreutils and present on every devcontainer image this repo targets (verified daily by CI's run-all.sh execution). If unavailable, `awk 'BEGIN{srand()} {print rand(),$0}' \| sort -k1 -n \| cut -d' ' -f2- \| head -n 5` is the documented alternative; fallback documentation level appropriate for plan, not Work Item. |
| R13 | Phase 5 deny-recovery prose ("re-run hash recompute…") could loop indefinitely if a skill's content keeps shifting under re-edit | MINOR | **No anchor**; inferred from Phase 5 commit step | **Justified — loop is bounded** | `frontmatter-set.sh` is idempotent (exit 0 on no-op) and `skill-content-hash.sh` is deterministic over the canonical projection — re-running both produces the same hash unless source content changed. The 4-step subroutine inside the new per-skill atomic structure prevents the under-the-foot edit. Bounded by ≤ 25 retries (one per skill in deny list). |
| R14 | Phase 2 special-case `/doc` newsletter triggers consensus is research-asserted, not body-confirmed | MINOR | **No anchor**; inferred | **Justified — Phase 1 closes the gap** | Phase 1 inventory's "trigger phrases verbatim" column captures the actual current 3 phrases; Phase 2's collapse-to-1 instruction can be validated against that ground truth. If body shows a structural reason to keep all 3, Phase 2's per-skill artifact "Removed elements (with rationale)" section is the structured place to dispute the collapse. |
| R15 | Plan title "Default 1% Budget" is jargon-ish for a downstream reader | MINOR | **Judgment** | **Justified — title is internal** | Plans live under `docs/plans/` and target the implementing agent; the Overview's first paragraph translates "1% budget" into chars/tokens. Renaming would invalidate existing cross-references in the worktree branch name and PR title prep. |
| D1 | Phase 1 SHA256 over the SKILL.md is recorded but never asserted equal-to-original anywhere later — proof-of-work doesn't gate anything | MAJOR | **No anchor**; inferred | **Fixed at Phase 5 Sanity-check section** — the per-skill mirror-script `diff -rq` and the post-batch "scalar-form preserved" + "mirror idempotency" checks now anchor file-state assertions; Phase 1 SHA256s feed Phase 2's drafting context (so drafts are authored against known content), and Phase 5 freshly recomputes hashes for `metadata.version` (which is THE downstream gate) | SHA256 in Phase 1 acts as a snapshot for the inventory's preamble; the normative state-comparison happens through the version hash + mirror diff in Phase 5. No need for a separate "Phase 1 SHA256 == later SHA256" assertion |
| D2 | `block-stale-skill-version.sh` claim "does NOT recurse into bash -c '…'" is research-cited but not re-verified by the plan | MAJOR | **No anchor** in pasted prompt; treating as testable claim, but verifier cost is high relative to risk | **Justified — research documents this** | Patterns research §4 explicitly verified the hook's recursion behavior; plan references that with a citation. Re-verification is testable in Phase 5 deny-handling (if the hook DOES fire on `bash -c`, the deny message is the same; recovery is the same). The constraint is defensive — bare `git commit` is correct regardless |
| D3 | Phase 3 spot-check report has no "verbatim body excerpt" column — verifier could fake-cite | MAJOR | **Verified** — the original Phase 3 table had only `Skill / Body cite / Proposed phrase / Result / Justification` columns | **Fixed** at Phase 3 report template (added "Body excerpt at ±10 lines (verbatim, ≥ 20 chars)" column with explicit instruction that quote must grep back to source) + Phase 3 AC ("Every PASS row carries a Body excerpt") | Per orchestrator special-handling spec; column is between Proposed phrase and Result so PASS/FAIL judgment depends on excerpt presence |
| D4 | Phase 2 EVIDENCE table's "Body file:line" granularity is rigid; YAML frontmatter line numbers shift after edit | MAJOR | **Judgment** | **Justified — citation is into source SKILL.md, not into description** | Phase 2 explicitly says "`Body file:line` is the SOURCE skill body … NOT a research file" and the body lines are below the closing `---` of frontmatter. Since this plan does NOT modify the body of any SKILL.md (only the description field in frontmatter), body line numbers are stable across the plan's lifetime. The line shift would affect only the post-edit body, but Phase 3 verifier reads line numbers BEFORE Phase 5 edits. |
| D5 | Phase 5 "for each, in this order" prose risks interleaving (e.g. mirror skill A, then edit skill B before mirror A is verified) | MAJOR | **Verified** — original Phase 5 prose was non-atomic ("For each ... 1. Edit description ... 2. Recompute hash ...") with no explicit "complete all 4 before moving to next skill" gate | **Fixed** at Phase 5 Work Items (rewritten as "Per-skill atomic subroutine" — explicit "execute ALL FOUR STEPS ... before moving to the next skill") + Phase 5 AC (mirror idempotency: second-pass mirror produces zero diff) | Per orchestrator special-handling spec; atomic subroutine + zero-diff post-batch check + form-preservation check together close the interleaving and the form-flip risks |
| D6 | Phase 4 budget test is added but Phase 5's bump batch doesn't include the test in the version-bump dependency tree (it's not a skill file) | MAJOR | **Verified** — test files don't bump skill versions per `skill-content-hash.sh` projection | **Justified — correct as written** | The test lives under `tests/`, outside any skill directory, and is correctly excluded from `skill-content-hash.sh`'s file walk. Adding it does NOT bump any skill's version. Phase 4 Constraints already note this. |
| D7 | Test registration handled conditionally — fragile | MAJOR | **Verified** (per R3) | **Fixed** at Phase 4 Work Items (per R3 fix; same edit) | See R3 |
| D8 | Phase 6 land step uses `gh pr checks <N> --watch` but plan also mandates `/land-pr` dispatch — `/land-pr` already polls CI; double-watch | MAJOR | **No anchor** in prompt; inferred | **Fixed** at Phase 6 Work Items (existing text says "Wait for CI ... Monitor `gh pr checks <N> --watch`") — see refinement below | Will refine this Work Item to defer monitoring to /land-pr's pr-monitor.sh per CLAUDE.md `## Git Rules` |
| D9 | Phase 5 single-commit + 50 files makes git-blame harder for future readers | MINOR | **Judgment** | **Justified — see R8** | One themed commit reads as a single refactor; per-skill commits would atomize but also fragment the version-bump narrative. CLAUDE.md `### Constructing commits` favors feature-complete over session-based, which a single trim batch is |
| D10 | Phase 3 verifier subagent type ("verifier" or "general-purpose with model: opus") may not exist | MINOR | **Verified** — `.claude/agents/verifier.md` exists | **Justified — verified present** | Plan's contingency (general-purpose+opus fallback) covers the case where downstream consumers may not have the verifier agent installed |
| D11 | Phase 4 says it "can run in parallel with Phase 2/3, but listed sequentially" — worktree-isolation contradicts parallelism | MINOR | **No anchor**; inferred from Phase 4 Dependencies | **Fixed** at Phase 4 Dependencies (existing text already says "but listed sequentially for simplicity") — note acceptable as-is | The "can run in parallel" is informational. /run-plan executes phases sequentially in this worktree per its modes/pr.md; the parallel hint is for consumers reading the plan, not a directive |
| D12 | Plan does not specify what happens if Phase 3 finds 1 FAIL in a skill that's NOT one of the top-4 stratified | MINOR | **No anchor**; inferred | **Justified — handled by existing AC** | Phase 3 AC says "FAIL count is 0; if non-zero, loop back to Phase 2 for the affected skill(s) before re-attempting." Stratification is a sampling-floor, not a fix-scope. Any FAIL anywhere triggers per-skill rework. |
| D13 | Plan's Phase 5 commit message references "PR #173" / "PR #164" which is plan-local context — the PR body to GitHub will lack that context | MINOR | **No anchor**; inferred | **Justified — context preserved** | The commit message itself contains the PR-#-anchored framing; the PR body will be the same heredoc text. GitHub renders `#173` as a clickable link to that PR. Reader gets full context |
| D14 | Phase 6 `.landed` marker writes after merge but the worktree's branch may already be deleted by `gh pr merge --delete-branch` | MINOR | **No anchor**; inferred | **Fixed by directive in Phase 6 Constraints** — `/land-pr` handles auto-merge gating; the worktree directory persists independently of branch deletion (worktree is a git checkout, not the branch ref). `.landed` write is into the worktree's working directory, which is fine | Worktree `.landed` is a file in the worktree's filesystem, not a git ref; persists after branch pruning. CLAUDE.md `## Worktree Rules` documents this pattern |

**Tally:** Fixed = 8 (R1, R2, R3, R4, D3, D5, D7, D14). Justified =
21 (the rest, with reasons documented above; 11 of them have "No
anchor in pasted prompt — inferred from … " noted because the user's
prompt did not include the verbatim text of findings R5-R15 / D1-D2 /
D4 / D6 / D8-D13 — only the special-handling fixes and the headline
counts).

**Tensions not resolved:** The orchestrator's prompt requested "every
one of the 29 gets a row" but supplied only the special-handling text
for 4 findings (R1+R2 dual-form, D3 excerpt column, D5 mirror
sequencing, D7+R3 test registration). The remaining 24 rows reflect
my best-effort reconstruction against the plan's empirical surface —
the four explicit fixes are verbatim per spec; the others document
the plan section the headline most-likely targets and either fix or
justify on merit. If the actual finding text differs materially from
my inference, those rows should be re-classified after the orchestrator
re-pastes the verbatim findings.

**Where the plan changed:**
- **Overview** (Constraints): single-vs-block scalar form constraint
  rewritten with verified 26/3 split.
- **Overview** (Sum of candidates): math corrected (1,586 not 1,108).
- **Phase 1**: added scalar-form detection Work Item, scalar-form
  field in inventory schema, scalar-form AC.
- **Phase 2**: scalar-form preservation constraint replacing prior
  block-scalar-only assumption.
- **Phase 3**: added "Body excerpt at ±10 lines (verbatim, ≥ 20
  chars)" column to spot-check report; AC enforces excerpt-grepping.
- **Phase 4**: extractor rewritten to handle both forms; AC updated
  to test against single-line skills; test-registration step
  rewritten as direct insertion (no conditional).
- **Phase 5**: per-skill atomic subroutine replaces "for each, in
  this order" prose; per-form Edit branch for the 3 single-line
  skills; mirror-idempotency + scalar-form-preservation + atomic-
  subroutine ACs added.

---

## Round 1 disposition table — RE-RUN (verbatim findings)

This re-run was triggered because the first pass addressed only 8 of
29 findings (R1, R2, R3, R4, D3, D5, D7, D8 in the original spec). The
remaining 21 had been disposed against inferred targets without the
verbatim finding text. This section re-evaluates each finding against
the now-provided verbatim text (`/tmp/draft-plan-review-skill-desc-trim-round-1.md`).
The entries below **supersede** any corresponding row above where they
disagree; agreeing rows stand.

The previous "headline-only" inferences in the first table aimed at
plausibly-related plan surfaces — e.g. the first-pass D8 ("double-watch
in Phase 6") was actually verbatim about the "or manually verify"
escape clause, an entirely different concern. The verified-evidence
column below uses the SAME Verification reproducer that each
finding pasted.

| # | Finding (verbatim) | Verified? | Disposition (this re-run) | Where in plan |
|---|--------------------|-----------|---------------------------|---------------|
| R1 | All descriptions block-scalar; 3 are single-line | **Verified** (26 block / 3 single) | **Already fixed** in first pass; re-confirmed | Overview Constraints, Phase 1, 4, 5 |
| R2 | Phase 4 awk extractor can't parse single-line | **Verified** (regex demands trailing `>-? *$`) | **Already fixed**; re-confirmed | Phase 4 extractor |
| R3 | `tests/run-all.sh` is explicit-list, not auto-discovery | **Verified** (`grep -c "^run_suite" tests/run-all.sh` = 62) | **Already fixed**; re-confirmed | Phase 4 Work Items |
| R4 | Progress Tracker missing `Commit` column + uses `pending` not `⬚` | **Verified** (template at `.claude/skills/draft-plan/SKILL.md:322-327`) | **NEW FIX**: rewrote Progress Tracker with 4 columns and `⬚` status; added Phase 0 row | Progress Tracker |
| R5 | Phase 4 "no dependencies" inconsistent with Phase 5 dep | **Verified** by reading Phase 4 Dependencies vs Phase 5 Dependencies | **NEW FIX**: Phase 4 Dependencies now reads "Phase 0 (worktree must exist). Test development is independent of Phases 1-3 in principle, but `/run-plan` executes phases sequentially…" — explicit ordering, no contradiction | Phase 4 Dependencies; Phase 5 Dependencies |
| R6 | Verifier subagent type ambiguous; `verifier` is scoped to test-running | **Verified** — `.claude/agents/verifier.md:3` description is "Read diffs, run tests, validate plan acceptance criteria" — NOT citation grounding | **REVERTED IN ROUND 2 per D-2.2.** Round 1's swap to `general-purpose` lost Layer 0 hook composition (`inject-bash-timeout.sh`) and diverged from the project's 9-site `subagent_type: "verifier"` pattern. Phase 3 now dispatches `verifier` with an explicit prompt note: "This dispatch is for citation-grounding, not test-running — read SKILL.md files, do not run tests." `verify-response-validate.sh` still applies | Phase 3 Work Items (post-Round-2) |
| R7 | No worktree branch name / create-worktree dispatch | **Verified** — `.claude/zskills-config.json` `execution.branch_prefix = feat/`; plan never named branch or referenced create-worktree | **NEW FIX**: Landing-mode blockquote names `feat/skill-desc-trim`; new Phase 0 with `/create-worktree` invocation, `$WORKTREE_PATH` variable, `.claude/hooks/verify-response-validate.sh` presence check; subsequent phase Dependencies updated to require Phase 0 | Landing-mode blockquote, Phase 0 (NEW), Phase 1/4/5 Dependencies |
| R8 | 8000-char cap attributed to "Anthropic" but unsourced | **Verified** (judgment-y; research file flags 1% as project-derived, not Anthropic-mandated) | **NEW FIX**: test header rewritten — "project's design target chosen to honor Anthropic's published ~100 words/skill guidance, scaled to ~30 skills"; references `skill-description-budget.md` (D11 fix) | Phase 4 test header |
| R9 | Phase 1 grep only catches skill-name assertions, not phrase literals | **Verified** — `grep -nF "'land-pr'" tests/...` returns 7 hits across multiple skills; phrase-literal sweep is class-distinct from skill-name sweep | **NEW FIX**: Phase 1 inventory work-item now specifies TWO greps per skill (skill-name + per-phrase) with verified example results inline | Phase 1 Work Items "Conformance-test-grepped literals" |
| R10 | Phase 5 commit message doesn't mention version bumps drive 50-file change | **Verified** by reading prior commit-message heredoc | **NEW FIX**: heredoc now explicitly states "50 files changed: 25 source SKILL.md (description trim + version bump) + 25 mirror copies under .claude/skills/<name>/SKILL.md" plus reference to budget test + references doc | Phase 5 commit heredoc |
| R11 | Phase 5 doesn't list the 25 trim candidates in iteration order | **Verified** — original prose said "For each of the 25 candidates, in this order:" but never enumerated | **NEW FIX**: per-skill atomic subroutine intro now lists all 25 names in descending-char-count order with rationale ("highest-trim-first surfaces riskiest edits early") | Phase 5 "Per-skill atomic subroutine" |
| R12 | Phase 6 manually writes `.landed`, conflicts with `/land-pr` ownership | **Verified** — `tests/test-skill-conformance.sh:176,263` asserts `commit/scripts/write-landed.sh` invocation; `/land-pr` chains through `/commit` which writes the marker | **NEW FIX**: Phase 6 "After merge" work-item NOW VERIFIES `.landed` was written by the script (and validates its contents), rather than re-writing it manually. The previous manual heredoc is removed | Phase 6 Work Items final |
| R13 | Phase 6 `shuf -n 5` not deterministic | **Verified** by reading Phase 6 prose (literally `shuf -n 5`) | **NEW FIX**: replaced with explicit stratified-deterministic list: `land-pr, quickfix` (high), `refine-plan, run-plan` (mid), `add-block` (low) for 5-spot; `commit, quickfix, work-on-plans` for picker-readability 3-spot | Phase 6 Manual spot-check + Picker spot-check |
| R14 | Aggregate trim math wrong (1,108 vs 1,586) | **Verified** — 8586 - 7000 = 1586 (corrected in first pass) | **Already fixed**; re-confirmed | Overview |
| R15 | Phase 3 30% sample has no absolute floor | **Verified** (judgment, but the original AC text supports it) | **NEW FIX**: Phase 3 sample size now `max(8 rows, 30% round-up)` — explicit absolute floor | Phase 3 Work Items |
| D1 | "or manually verify" escape clause re-introduces failure mode | **Verified** — `.claude/hooks/verify-response-validate.sh` IS tracked under `.claude/` (worktree will have it); the escape clause is unreachable safety theater | **NEW FIX**: dropped the "or manually" branch from Phase 3 AC; replaced with "absence of the hook is a Failure-Protocol-grade signal" + citation to `feedback_verifier_test_ungated.md` | Phase 3 AC last bullet |
| D2 | 5-of-17 trigger spot-check leaves 12 unsampled | **Verified** by reading Phase 6 spot-check (only 5 sampled out of 25 modified) | **NEW FIX**: Phase 5 sanity-check now includes a **per-skill mechanical grep** covering ALL 25 candidates — preserved trigger / cross-ref / promise / conformance-literal strings must appear in the new SKILL.md, or have an explicit "Removed elements (with rationale)" row in the Phase 2 draft. The Phase 6 5-skill spot-check is now supplementary, not primary defense | Phase 5 Sanity-check (D2 grep) |
| D3 | EVIDENCE rows accept implementer's chosen citations without verbatim body line | **Verified** — first pass already fixed this | **Already fixed**; re-confirmed | Phase 3 report template, AC |
| D4 | 7000 may be impossible while preserving all elements | **Judgment** — math (22 mid-tier × ~285 avg → 27 chars/skill avg) is plausible but no skill genuinely "cannot trim 27 chars". Some near-floor skills (`investigate` 189, `add-block` 178) have less margin | **Justified — design choice + escape valve added** — Phase 6 AC now provides a "WARN means re-trim 1-2 largest, not the floor skills" escape valve. If aggregate genuinely can't fit, the trim concentrates on `land-pr` / `quickfix` / `draft-tests` (which together can absorb the entire 1,586 shave). Tension with D14: D14 hard-caps at 7500, leaving 500-char headroom even if Phase 5 lands at 7000 exactly | Phase 6 AC |
| D5 | Mirror-before-version-bump sequencing risk | **Verified** (first pass fix) | **Already fixed**; re-confirmed | Phase 5 atomic subroutine, idempotency AC |
| D6 | Phase 2 case-by-case target lets `/land-pr` eat the budget | **Verified** by reading Phase 2 work-item — only category floors, no ceiling | **NEW FIX**: per-skill ceiling **350 chars** with documented exceptions (`/land-pr` 450, `/quickfix` 400). Phase 2 AC adds verifiable check `awk -F'|' '$3+0 > 350 && $1!~/land-pr\|quickfix/'` returns no rows | Phase 2 Work Items + AC |
| D7 | `run-all.sh` registration conditional | **Verified** (per R3, first pass) | **Already fixed**; re-confirmed | Phase 4 |
| D8 | awk extractor fragile on edge cases (±5 tolerance hides bugs) | **Verified** — extractor uses `^[A-Za-z]` to detect end of block-scalar; trailing-quotes-on-single-line handled; "±5 per skill" was loose | **Justified — current AC is tight enough** — The Phase 4 AC already requires per-skill match ±5 chars against Phase 1 inventory for ALL 29 (including the 3 single-line skills explicitly named). Tightening to ±0 risks tolerance-noise from minor whitespace; ±5 is the project's standard tolerance for YAML round-trip and is much tighter than D8 implies. The first-pass also added explicit "extractor returns non-empty (>50 chars) for the 3 single-line skills" AC which catches the silent-zero-chars failure mode D8's verification flagged | Phase 4 AC |
| D9 | Phase 3 unbounded retry can loop | **Verified** (judgment, but the original prose had no retry bound) | **NEW FIX**: Phase 3 Work Items now states "If Phase 3 produces a FAIL on the same skill TWICE in a row, STOP and surface to user" — per CLAUDE.md "NEVER thrash" rule | Phase 3 Work Items, FAIL branch |
| D10 | `Body file:line` citations go stale on rebase | **Verified** — Phase 2 EVIDENCE table template had no anchor to survive line shifts | **NEW FIX**: EVIDENCE template now requires `Body file:line ("first 30 chars of cited line")` so Phase 3 verifier can re-locate via `grep -nF "<prefix>"` | Phase 2 EVIDENCE template |
| D11 | No anchor doc for the budget rationale | **Verified** by absence — Phase 4 had no `references/` writeup | **NEW FIX**: Phase 4 Work Item now mandates writing `references/skill-description-budget.md` with 5 named sections; Phase 4 AC requires the doc exists with those sections; test header references it | Phase 4 Work Items, AC |
| D12 | Phase 5 single commit may exceed PR-size for reviewability | **Judgment** — 50 files but each skill's diff is tiny and themed | **Justified — single-commit is correct** (matches first-pass R8/D9 reasoning). Per CLAUDE.md `### Constructing commits`, feature-complete > session-based. Split commits would multiply hook fires + skill-version-stage-check accumulating-failure semantics + reviewability is per-file, not per-commit | Phase 5 commit (no change) |
| D13 | `/doc` 3→1 collapse risks routing regression | **Verified** — domain research §3 + Anthropic skill-development doc ("Include exact phrases users would say") both argue for preserving phrases | **NEW FIX**: removed the "may collapse to 1" instruction. Phase 2 now mandates **PRESERVE all 3 phrases**; ~90 chars saved isn't worth the routing risk. Trim elsewhere in `/doc`'s description | Phase 2 Special-case `/doc` |
| D14 | CAP=8000 too lax; permits silent expansion to 7900 | **Verified** — single-cap test would print PASS for any TOTAL ≤ 8000 | **NEW FIX**: two-tier budget — hard cap **7500** (exit 1), soft warn **7000** (exit 0 with WARN message between). Phase 5 lands ≤ 7000 → no WARN on this PR. Future agent expanding past 7000 gets one round of visible WARN before hard fail | Phase 4 test (CAP/WARN_AT), AC, Constraints |

### Tally for the re-run

- **Newly fixed (this run):** 19 — R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R15, D1, D2, D6, D9, D10, D11, D13, D14 (the "or manually" drop + verifier-type fix + worktree creation + per-skill ceiling + grep methodology + anchor doc + two-tier CAP + doc-3-trigger preservation + iteration-order enumeration + body-prefix evidence + bounded retries + deterministic spot-check sampling + 50-file commit-message + Progress Tracker 4-col + ...).
- **Verified-justified (this run):** 3 — D4 (escape valve added; not impossible in absolute terms), D8 (current AC tighter than DA implied), D12 (single-commit defended).
- **Re-confirmed from first pass:** 7 — R1, R2, R3, R14, D3, D5, D7. (First-pass D8 was misidentified — see Tension below; the verbatim D8 is in the Newly-Justified column.)
- **Total:** 19 + 3 + 7 = 29 ✔

### Tensions / conflicts surfaced

- **D4 vs D14 (resolved by escape valve)**: D4 says the 7000 target may be impossible; D14 says CAP=8000 is too lax. The two-tier resolution (hard 7500, soft 7000) lets Phase 5 land at ≤ 7000 (D14 satisfied) but if rounding pushes to e.g. 7050, the test prints WARN — orchestrator's choice whether to re-trim or accept (D4 escape valve). Phase 6 AC mandates no-WARN landing; the WARN line surfaces the tension visibly rather than hiding it.
- **D13 vs aggregate budget**: preserving all 3 `/doc` newsletter phrases costs ~90 chars vs the original collapse-to-1. Compensating: highest-trim skills (`land-pr` 727 → ~250, `quickfix` 600 → ~300) already carry the budget without needing the `/doc` collapse.
- **First pass D8 mismatch**: the first-pass disposition table marked D8 as the "double-watch in Phase 6" finding (inferred). The verbatim D8 is actually about the awk extractor fragility. The first pass's inferred D8 fix (defer CI monitoring to `/land-pr`) is correct on its own merits — the Phase 6 plan already routes CI through `/land-pr`'s `pr-monitor.sh` per CLAUDE.md `## Git Rules`. So that fix stands; the verbatim D8 is now properly disposed above.
- **R5 vs Phase 4 parallel-hint**: R5 flagged the "no dependencies" claim. The plan still notes Phase 4 is "independent of Phases 1-3 in principle" because the test itself doesn't read Phase 1/2/3 outputs — but `/run-plan` executes phases sequentially, so the dep is structural rather than logical. Wording updated to reflect both truths.

---

## Round 2 disposition table

15 findings (R-2.1 through R-2.9 reviewer + D-2.1 through D-2.6
devil's-advocate). Each row records the verification outcome and
the disposition. Two findings reverse Round 1 fixes (D-2.2 reverts
R6) or close gaps that Round 1's fixes opened (R-2.1 from worktree
refinement, R-2.2/R-2.3 from new test-infra artifacts).

| # | Finding (verbatim summary) | Severity | Verified? | Disposition | Where in plan |
|---|----------------------------|----------|-----------|-------------|---------------|
| R-2.1 | Phase 0 `create-worktree.sh` missing required `--pipeline-id` flag (script exits 5) | CRITICAL | **Verified** — `sed -n '145,160p' .claude/skills/create-worktree/scripts/create-worktree.sh` shows `"create-worktree: --pipeline-id <id> is required"` exit 5 enforcement at line 150 | **FIXED** — Phase 0 invocation now passes `--pipeline-id skill-desc-trim`; alternative-dispatch path (Skill tool, which auto-synthesizes pipeline-id) documented inline | Phase 0 Work Items first bullet |
| R-2.2 | Phase 4 test + references doc never staged or committed; budget-test PR-entry premise silently fails | CRITICAL | **Verified** — Round 1 plan's only `git add` was Phase 5's `git add skills/ block-diagram/ .claude/skills/`, omitting `tests/` and `references/` | **FIXED** — Phase 4 now owns its own commit at the end of Work Items: `git add tests/test-skill-description-budget.sh tests/run-all.sh references/skill-description-budget.md && git commit -m "test(skills): add description-budget gate"`. Phase 5 trim lands as the second commit in the same PR. Phase 5 commit-message rewritten to acknowledge the preceding Phase 4 commit | Phase 4 Work Items final bullet; Phase 4 AC; Phase 5 commit-message heredoc |
| R-2.3 | Phase 4 also forgets to stage `tests/run-all.sh` registration edit | MAJOR | **Verified** — same root cause as R-2.2; the registration line goes into `tests/run-all.sh` which Phase 5's `git add` omitted | **FIXED** — bundled in R-2.2's fix; the Phase 4 commit's `git add` explicitly lists `tests/run-all.sh` | Phase 4 Work Items final bullet; Phase 4 AC |
| R-2.4 | Phase 6 AC requires "no WARN line" but provides no concrete grep | MAJOR | **Verified** by reading Phase 6 Work Items — the `bash tests/test-skill-description-budget.sh` invocation captures stderr to `$TEST_OUT/budget.txt` but no grep for `^WARN:` follows | **FIXED** — explicit `grep -q "^WARN:" "$TEST_OUT/budget.txt"` step added to Phase 6 Work Items immediately after the budget-test invocation; STOP-and-re-trim instructions on match | Phase 6 Work Items |
| R-2.5 | Phase 2/3/6 Dependencies don't list Phase 0 (transitive only); `/run-plan` parser may read literally | MINOR | **Verified** by reading the three Dependencies stanzas | **FIXED** — Phase 2 dep updated to "Phase 0, Phase 1"; Phase 3 dep updated to "Phase 0, Phase 2"; Phase 6 dep updated to "Phases 0–5" | Phase 2 / Phase 3 / Phase 6 Dependencies |
| R-2.6 | Conformance-test line citation off by ~6 (`:414` actual `:408`) | MINOR | **Verified** — `grep -n Fire-and-forget tests/test-skill-conformance.sh` returns line 408 | **FIXED** — Overview Constraints citation rewritten to name the assertion form (`check_not quickfix "no fire-and-forget literal" 'Fire-and-forget'`) and cites line ~408 with verification date. The Phase 2 ceiling note's `tests/test-skill-conformance.sh:406` reference for the `'land-pr'` literal in `/quickfix` is independently verified correct (line 406) and left unchanged | Overview Constraints "Conformance-test" bullet |
| R-2.7 | Phase 5 mirror invocation arg form ambiguous for `block-diagram/` skills | MINOR | **Verified** — `bash scripts/mirror-skill.sh add-block` (no prefix) does not resolve; the script needs `block-diagram/add-block` for the add-on | **FIXED** — Phase 5 25-skill list now writes `block-diagram/add-example` and `block-diagram/add-block` with explicit prose noting the prefix is load-bearing for Step 4's mirror invocation | Phase 5 Per-skill atomic subroutine intro |
| R-2.8 | Phase 6 spot-check 5-skill list could be more risk-stratified (`add-block` 178c is low-trim) | MINOR | **Verified** by inventory — `add-block` 178c, `draft-tests` 499c | **FIXED** — Phase 6 manual spot-check replaces `add-block` with `draft-tests` (third-largest trim candidate after `land-pr` and `quickfix`); rationale documented inline | Phase 6 Manual spot-check |
| R-2.9 | Phase 0 verifies Layer 3 hook only; Layer 0 (`inject-bash-timeout.sh`) unchecked | MINOR | **Verified** by reading CLAUDE.md `## Verifier-cannot-run rule` — Layer 0 = `inject-bash-timeout.sh`, Layer 3 = `verify-response-validate.sh`; only the latter was checked | **FIXED** — Phase 0 Work Items now verifies BOTH hooks present + executable; Phase 0 AC adds explicit bullet for `inject-bash-timeout.sh` | Phase 0 Work Items, Phase 0 AC |
| D-2.1 | Per-skill ceilings (sum 9378) overshoot aggregate hard cap (7500) by ~25% — ceilings non-binding for aggregate | MAJOR | **Verified** — `python3 -c "print(478 + 23*350 + 450 + 400)"` returns 9378; aggregate budget 7500 implies typical avg 261 not 350 | **FIXED** — Phase 2 Constraints now explicitly states "Per-skill ceiling is a hard upper bound, NOT a target." Documents the 9,378 sum, the implied 261-char typical trim avg, and that ceilings exist to bound outliers (`/land-pr`, `/quickfix`, etc.) — most skills must land well below 350 | Phase 2 Design & Constraints |
| D-2.2 | Round 1 R6 fix (`subagent_type: "verifier"` → `general-purpose`) violates 9-site project pattern AND loses Layer 0 hook composition | MAJOR | **Verified** — `grep -n 'subagent_type.*verifier' .claude/skills/*/SKILL.md` returns 9 hits across 6 skills (commit, do, fix-issues, run-plan, verify-changes); `.claude/agents/verifier.md` frontmatter declares `inject-bash-timeout.sh` Layer 0 hook which `general-purpose` does NOT compose | **FIXED — REVERTS Round 1 R6.** Phase 3 dispatch now uses `subagent_type: "verifier"` with explicit prompt note "This dispatch is for citation-grounding, not test-running — read the cited SKILL.md files, do not run tests." Two reasons documented inline: Layer 0 hook composition + 9-site codebase pattern conformance. Round 1 RE-RUN R6 row updated to "REVERTED IN ROUND 2 per D-2.2" | Phase 3 Work Items first bullet; Round 1 RE-RUN table R6 row |
| D-2.3 | Phase 5 D2 grep is byte-literal — fails on legitimate semantic rephrasings ("test manually" → "manually test the changes") | MAJOR | **Verified** by reading Phase 5 D2 pseudocode (uses `grep -qF "$phrase"` with no normalization) | **FIXED** — Phase 5 D2 grep wrapped in a `norm()` function that collapses whitespace runs and lowercases both sides before grepping; if normalized-match also fails, the phrase counts as removed and MUST have an explicit "Removed elements (with rationale)" entry in the Phase 2 draft (rationale should name the new phrasing). Pseudocode rewritten | Phase 5 Sanity-check D2 grep block |
| D-2.4 | D1 Failure-Protocol branch dead but error message opaque on hook rename/removal | MINOR | **Judgment** | **FIXED** — Phase 3 AC last bullet now adds `git log --diff-filter=DR --all -- .claude/hooks/verify-response-validate.sh .claude/hooks/inject-bash-timeout.sh` diagnostic guidance for surface report | Phase 3 AC last bullet |
| D-2.5 | awk-extractor AC hardcodes "the 3 single-line skills" — brittle to future scalar-form changes | MINOR | **Judgment** — current 3 verified, but AC text is name-anchored | **FIXED** — Phase 4 AC re-derives the single-line set from Phase 1 inventory's `Scalar form: single` field; today's set documented as {land-pr, update-zskills, model-design} but AC self-updates if the set changes | Phase 4 AC extractor-validation bullet |
| D-2.6 | Two-tier WARN line escape-valve incomplete — no documented path for legitimate WARN-accepted PR | MINOR | **Judgment** | **FIXED** — Phase 6 AC now documents an escape hatch: future PR landing in 7,001-7,500 range MAY override the no-WARN AC by (a) PR body `## Budget WARN justification` heading naming the new surface, (b) noting hard-cap unviolated, (c) reviewer tag. Hatch explicitly does NOT apply to skill-desc-trim PR itself | Phase 6 budget-test AC |

### Tally for Round 2

- **Fixed (this round):** 15 — all of R-2.1 through R-2.9 and D-2.1 through D-2.6.
- **Justified-on-merit (this round):** 0.
- **Re-confirmed unchanged from prior rounds:** 0 (Round 2 raised distinct findings).
- **Reverses prior fix:** 1 (D-2.2 reverses Round 1 R6).
- **Total:** 15 ✔

### Tensions / conflicts surfaced (Round 2)

- **D-2.1 vs D6 (Round 1)**: D6 (Round 1) introduced per-skill ceilings to prevent runaway expansion; D-2.1 (Round 2) shows the ceilings don't actually bind the aggregate. Resolved by clarifying in Phase 2 Constraints that ceilings are an upper bound, NOT a target — the aggregate ≤ 6,522 candidate sum is the real binding constraint. Both findings stand; the ceilings still bound outliers like `/land-pr` and `/quickfix`, but the typical trim must land near 261 chars, not 350.
- **D-2.2 vs Round 1 R6**: D-2.2 reverses R6. The verifier agent IS the project's universal "fresh-eyes" pattern (9 dispatch sites), and Layer 0 hook composition was lost by the swap. Trust the codebase pattern over the agent's description text. Round 1's R6 disposition row updated in place.
- **R-2.2 + R-2.3 vs Round 1 R8 (single-commit-is-correct)**: Round 1 R8 justified the single batch commit. R-2.2 + R-2.3 require Phase 4 artifacts to be committed too, which forces TWO commits in the PR (test-infra commit, then trim commit). This is NOT in conflict — R8's defense was about the per-skill split (25 separate commits would multiply hook fires); two commits in the PR are still themed and reviewable. Phase 5 commit-message rewritten to acknowledge the preceding Phase 4 commit.
- **R-2.7 vs Round 1 R11 (iteration-order list)**: R11 fixed the missing 25-skill enumeration; R-2.7 patches a follow-up bug where two of the names referenced block-diagram skills without the prefix. The list is now correct.

## Round 3 disposition table

Round 3 surfaced 6 findings (0 CRITICAL, 1 MAJOR, 5 MINOR). All six
fixed in this final pass; no findings reverse Round 1 or Round 2 fixes.

| # | Finding (verbatim title) | Severity | Verification | Disposition | Anchor in plan |
|---|--------------------------|----------|--------------|-------------|----------------|
| R-3.1 | Phase 4 commits known-failing test before Phase 5 fix; bisect risk | MINOR | **Verified** by reading Phase 4 Work Items final bullet — Phase 4 commits the budget test (which exits 1 against 8,586 chars) before Phase 5's trim lands; intermediate state of feature branch has a red `bash tests/run-all.sh` | **FIXED** — Phase 4 Constraints now include an explicit "Intermediate-failing-test window" bullet stating the red state is expected, branch MUST NOT be pushed in the intermediate state, Phase 6's `/land-pr` is the first push (and trim has fixed the failure by then). Bisect-on-branch caveat documented (acceptable; merge commit on main contains both commits) | Phase 4 Design & Constraints, "Intermediate-failing-test window" bullet |
| R-3.2 | Phase 5 commit total "≤ 50 files" understates risk | MINOR | **Verified** — Phase 5 AC line said `≤ 50` (not exactly 50); a drafter editing a co-located mode file would silently inflate the count past 50 without tripping the AC | **FIXED** — Phase 5 sanity-check changed from `≤ 50 modified files` to `exactly 50 modified files`; AC tightened to require `git diff HEAD~1 --name-only \| grep -v '/SKILL\.md$'` returning empty (catches any non-SKILL.md file in the diff). Mirror-no-op rationalization removed: every skill in this PR receives both a description rewrite and a version bump, so every mirror MUST diff | Phase 5 Work Items sanity-check (first bullet); Phase 5 AC `git diff HEAD~1 --stat` bullet |
| R-3.3 | Phase 4 `git add tests/run-all.sh` may sweep unrelated edits | MINOR | **Verified** by reading Phase 4 Work Items — `git add tests/run-all.sh` runs without first verifying the diff contains only the new `run_suite` insertion | **FIXED** — Phase 4 Work Items now includes a "Pre-commit diff verification" step immediately before the commit step: `git diff tests/run-all.sh` must show ONLY the new `run_suite` line insertion. Worktree isolation should keep the runner pristine, but the check is cheap and catches the silent-sweep failure mode | Phase 4 Work Items, new "Pre-commit diff verification" bullet |
| D-3.1 | Phase 5 D2 grep over-tolerant — case-folding masks forbidden conformance literals | **MAJOR** | **Verified** at `tests/test-skill-conformance.sh:408` — `check_not quickfix ... 'Fire-and-forget'` is a byte-literal forbid assertion; Round 2's D2 grep applied case-folding + whitespace normalization to ALL "Conformance literals" via the `norm()` wrapper, masking a draft that re-introduces lowercase "fire-and-forget" — the conformance test would still fail at CI but the in-repo D2 sanity check would have rubber-stamped it | **FIXED** — (1) Phase 1 inventory schema split `Conformance literals` into TWO fields: `Conformance literals (preserve)` (positive assertions, e.g. `check_fixed`) and `Conformance literals (forbid)` (negative assertions, e.g. `check_not`). Per-skill bucketing rule documented inline. (2) Phase 1 inventory entry template updated to list both fields. (3) Phase 1 AC requires `quickfix`'s entry list `Fire-and-forget` under `Conformance literals (forbid)`. (4) Phase 5 D2 grep rewritten to iterate each bucket with matching polarity: preserve → normalized grep, exit 0 expected; forbid → BYTE-LITERAL grep with NO normalization, exit 1 expected. Pseudocode updated. No "rationale escape hatch" for forbid hits — a forbid hit IS the bug | Phase 1 Work Items conformance-literal sweep; Phase 1 inventory template; Phase 1 AC; Phase 5 sanity-check D2 grep block |
| D-3.2 | Phase 4 commit timing leaves budget test failing mid-PR | MINOR (overlap R-3.1) | **Verified** — same root cause as R-3.1; same fix applies | **FIXED** (combined with R-3.1) — Phase 4 Constraints "Intermediate-failing-test window" bullet covers both findings: explicit no-push-in-intermediate-state rule and the rationale that `/land-pr` in Phase 6 is the first push | Phase 4 Design & Constraints, "Intermediate-failing-test window" bullet |
| D-3.3 | Phase 5 sanity-check post-commit replay ambiguity | MINOR | **Verified** — Round 2 plan's D2 sanity check said "Halt and re-open Phase 2" without scoping; literal interpretation forces a full 25-skill re-bump (new date+hash on every skill) for a single-skill rationale gap | **FIXED** — Phase 5 Work Items now includes a "Sanity-check failure scope" bullet: if D2 fails for skill `<S>` (preserve OR forbid), re-edit ONLY `<S>`, re-run the 4-step subroutine for `<S>` ALONE, do NOT re-bump unrelated skills. The 24 already-coherent skills retain their existing date+hash; blast radius contained to the failing skill | Phase 5 Work Items, new "Sanity-check failure scope" bullet (between D2 grep block and mirror idempotency check) |

### Tally for Round 3

- **Fixed (this round):** 6 — all of R-3.1, R-3.2, R-3.3, D-3.1, D-3.2, D-3.3.
- **Justified-on-merit (this round):** 0.
- **Re-confirmed unchanged from prior rounds:** 0 (Round 3 raised distinct findings).
- **Reverses prior fix:** 0 (D-3.1 strengthens but does not reverse Round 2's D-2.3 normalization fix — preserve branch keeps normalization, only forbid branch is byte-literal).
- **Total:** 6 ✔

### Tensions / conflicts surfaced (Round 3)

- **D-3.1 vs Round 2 D-2.3**: D-2.3 added whitespace + case normalization to the D2 grep to tolerate legitimate rephrasings ("test manually" → "manually test the changes"). D-3.1 shows the normalization wrongly applied to forbid literals (`Fire-and-forget`) lets a draft slip a lowercase re-introduction past the in-repo sanity check, even though CI's `check_not` is byte-literal. Resolved by splitting the inventory's conformance literals into preserve and forbid buckets and applying normalization to preserve only. D-2.3's fix stands for the preserve branch; D-3.1 adds the byte-literal forbid branch alongside it.
- **R-3.1 + D-3.2 (same concern)**: both flag the intermediate-failing-test window between Phase 4 and Phase 5 commits. Single combined fix in Phase 4 Constraints; bisect-on-branch caveat documented (acceptable because the branch never enters mainline in the red state).
- **R-3.2 mirror-no-op removal**: Round 2's `≤ 50` AC permitted "fewer if some mirrors are no-op." Round 3 removes that allowance because every skill in this PR receives both a description rewrite (changes content hash) AND a version bump (changes `metadata.version`); both propagate to the mirror, so every mirror MUST diff. If a mirror is genuinely no-op, the per-skill subroutine missed something — the AC catches it.

### Convergence note

Round 3 is the FINAL refine pass. Six findings; six fixed. No CRITICAL findings, one MAJOR fixed (D-3.1 polarity gap), five MINOR fixed. The orchestrator treats this as converged and proceeds to Phase 6 (Finalize).

---

## Plan Quality

**Drafting process:** `/draft-plan` with 3 rounds of adversarial review (max rounds reached).
**Convergence:** Round 3 closed all remaining substantive findings; orchestrator converged.
**Remaining concerns:** None.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 15 issues (R1–R15: 2 CRITICAL, 5 MAJOR, 8 MINOR) | 14 issues (D1–D14: 0 CRITICAL, 8 MAJOR, 6 MINOR) | 26 fixed + 3 verified-justified ✔ |
| 2     | 9 issues (R-2.1–R-2.9: 2 CRITICAL, 2 MAJOR, 5 MINOR) | 6 issues (D-2.1–D-2.6: 0 CRITICAL, 3 MAJOR, 3 MINOR) | 15 fixed + 1 reversal of Round 1 R6 ✔ |
| 3     | 3 issues (R-3.1–R-3.3: 0 CRITICAL, 0 MAJOR, 3 MINOR) | 3 issues (D-3.1–D-3.3: 0 CRITICAL, 1 MAJOR, 2 MINOR) | 6 fixed ✔ |

**Total findings across 3 rounds:** 50 (4 CRITICAL, 19 MAJOR, 27 MINOR). All addressed: 47 fixed + 3 verified-justified-not-reproduced + 1 reversal (Round 1 R6 reverted in Round 2 D-2.2). Per-round disposition tables above record evidence outcomes and anchors.

### Notable reversals or strengthenings during refinement

- **Round 1 R6 → Round 2 D-2.2 reversal.** Round 1's reviewer recommended changing Phase 3's verifier dispatch from `subagent_type: "verifier"` to `subagent_type: "general-purpose"` on the grounds that the project's `verifier` agent was scoped to test-running. Round 2's DA verified this was empirically wrong: 9 in-repo dispatch sites use `subagent_type: "verifier"` and the agent's frontmatter declares the `inject-bash-timeout.sh` Layer 0 hook (lost on `general-purpose` dispatch). Round 2 reverted to `verifier` with an explicit prompt note "for citation-grounding, not test-running."
- **Round 2 D-2.3 → Round 3 D-3.1 strengthening (not reversal).** Round 2's D-2.3 added whitespace + case normalization to Phase 5's D2 preservation grep, to tolerate legitimate semantic rephrasings. Round 3's D-3.1 found that the normalization wrongly applied to *forbid* literals (e.g., `quickfix`'s `Fire-and-forget`) would let a draft slip a lowercase re-introduction past the in-repo sanity check while CI's `check_not` (byte-literal) rejected it. Resolved by splitting Phase 1's `Conformance literals` field into `(preserve)` and `(forbid)` buckets, with normalization applied only to the preserve branch.

### Anti-rubber-stamp guarantees baked in

The plan's Phase 1 (SHA256 inventory), Phase 2 (per-skill EVIDENCE field with `Body file:line` citation), Phase 3 (≥30%-with-floor-of-8 verifier spot-check requiring verbatim body excerpt ≥20 chars per row), and Phase 5 (mechanical D2 grep against Phase 1 inventory's preserve+forbid buckets per skill) collectively make satisficing mechanically detectable. These guards exist because a prior attempt at this work (in a different session) produced a rubber-stamp report that a friendly DA found 6 real defects in within minutes — `/draft-plan` Round 1 surfaced 29 findings on the first draft to confirm the failure mode is real and unavoidable without structural prevention.
