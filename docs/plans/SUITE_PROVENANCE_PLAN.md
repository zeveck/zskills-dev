---
issue: 1166
title: Suite-result provenance — stamp, validate, and de-duplicate test runs without ever skipping verification
created: 2026-06-15
status: "active"
---

# Plan: Suite-result provenance — stamp, validate, and de-duplicate test runs without ever skipping verification

## Overview

**Issues: #1166 (suite-result provenance / test-run de-duplication).**

The problem this plan solves: the same `tests/run-all.sh` full suite is run
multiple times for one unit of work — the orchestrator captures a baseline,
the implementer runs it before committing, then the fresh verifier runs it
AGAIN — even when the tree has not changed between runs. Each run is 3–4
minutes. #1166 introduces **result provenance**: a run-all.sh output now
carries a header recording WHICH tree produced it, a sourced validator that
answers "is this result still true for the current tree?", and a verifier
protocol that REUSES a provenance-valid result (verifying the tally + re-running
only the targeted suites for the changed area) instead of blindly re-running
everything.

**This is de-duplication, NEVER skipping verification.** A reused result is
only accepted when the validator proves it was measured on the EXACT current
tree, within the last 30 minutes, AND the verifier still independently audits
the diff and re-runs the changed area's suites. The full local run before
landing shared-infra changes, the plan-completion boundary run, and the CI
fresh-clone full run all remain non-negotiable. The threat model is explicit:
a fabricated results file fails at THREE independent layers (validator = wrong
tree hash; targeted re-run = the changed area must actually pass; CI = fresh
full run).

**Falsifiable end state:**

1. **Stamp present.** `tests/run-all.sh` output begins with a provenance
   header (`zskills-suite-provenance: v1` + `tree=`, `fingerprint=`,
   `timestamp=`, `epoch=`, `command=` lines) emitted ONCE by the main
   process before any suite output, and ends with the existing
   `Overall: N/M passed, F failed` tally. No suite breaks; parallel and
   serial modes both emit it identically.
2. **Validate works.** `bash tests/lib/suite-result-valid.sh <file>` exits 0
   IFF the header's `tree` == `git -C "$REPO_ROOT" rev-parse HEAD` AND
   `fingerprint` == the live content-sensitive tree fingerprint (see
   "Provenance header format" — hashes tracked staged+unstaged CONTENT plus
   untracked file CONTENT, NOT just changed paths) AND the recorded `epoch`
   is < 30 minutes old; exit 1 otherwise (empty/missing field, wrong tree,
   content drift, stale, missing/garbled header, absent file, or git
   unavailable). The unit suite `tests/test-suite-result-valid.sh` is
   triplet-registered and green in `bash tests/run-all.sh`.
3. **Verifier reuses.** `agents/verifier.md` and its `.claude/agents/verifier.md`
   twin (byte-identical modulo the frontmatter hooks block — parity-locked)
   carry the de-dup protocol; the 4 dispatch templates (run-plan execute-phase,
   verify-changes, do, fix-issues) instruct the same reuse-when-valid +
   targeted-rerun + full-rerun-on-shared-infra protocol. `bash tests/test-agents-parity.sh`
   stays green; the 4 skill `metadata.version` fields are bumped + mirrored.
4. **Baseline reuses uniformly.** After the stamp lands, the orchestrator
   baseline (`$TEST_OUT/.test-baseline.txt`) carries the same header, so the
   validator accepts it as a reusable result at the same tree — killing the
   baseline-refresh re-run class.
5. **Docs-only classifier refined.** `/do`'s content-only classifier
   (`skills/do/SKILL.md`) is refined to EXCLUDE `skills/**/*.md` (skill
   bodies are behavior, not docs); a docs-confined diff (`docs/`, `README*`,
   `CHANGELOG*`, `PRESENTATION*`) runs only the prose-pinning subset locally
   (conformance, catalog, managed-md-up-to-date) — CI still full. A diff
   touching any `skills/**/*.md` runs the full local suite + full CI.
6. **Policy prose landed.** `CLAUDE_TEMPLATE.md` `## Tests` gains an additive
   "Tests — result provenance / de-duplication" subsection defining reuse as
   de-dup-not-skip with the safety-floor invariant stated verbatim;
   `.claude/rules/zskills/managed.md` is re-rendered in the same commit via
   `scripts/render-managed-rules.py`; conformance pins lock the new prose +
   the new helper's existence.
7. `bash tests/run-all.sh` passes clean at every phase boundary.

## Settled decisions (do not relitigate)

1. **Five surfaces, exactly — no more, no less** (anti-drift is the explicit
   goal; the plan mirrors #1166 1:1):
   1. **STAMP** — `tests/run-all.sh` emits a provenance header to stdout.
   2. **VALIDATE** — ONE sourced helper `tests/lib/suite-result-valid.sh`
      (single definition, #1132 single-path rule) + the triplet-registered
      unit suite `tests/test-suite-result-valid.sh`.
   3. **VERIFIER PROTOCOL** — `agents/verifier.md` + `.claude/agents/verifier.md`
      twin (the CENTRAL surface) + the 4 dispatch templates.
   4. **ORCHESTRATOR BASELINE REUSE** — `skills/run-plan/modes/execute-phase.md`
      baseline capture + verifier compare reuse a validating result.
   5. **DOCS-ONLY CLASSIFIER** — `CLAUDE_TEMPLATE.md` `## Tests` additive
      subsection + the refinement of `/do`'s existing content-only classifier.
   No surface is added; no surface is dropped.
2. **The safety floor is the hard invariant, encoded verbatim in
   Invariant 2.** De-dup never reads as "skip verification." CI full run on
   every PR is non-negotiable (fresh-clone backstop). Provenance reuse NEVER
   accepts a result for a tree that was not measured.
3. **The stamp is SPLIT** — provenance fields (tree/fingerprint/timestamp/
   epoch/command) at the TOP of stdout; the canonical tally
   `Overall: N/M passed, F failed` stays at the BOTTOM (already emitted at
   run-all.sh ≈L583/585). The validator reads BOTH: the header for
   tree/fingerprint/epoch, and the verifier treats the bottom
   `Overall: ... 0 failed` line as the pass signal (the verifier already
   greps `Overall:` directly today — no back-reference field is needed, so
   the earlier `canonical-tally=` field is DROPPED as inert). run-all.sh
   writes NO results file of its own — the CALLER redirects stdout, so the
   header is the captured file's first lines.
4. **No parallel-write collision.** The stamp is emitted ONLY by the main
   run-all.sh process (header at top, existing tally at bottom). Parallel
   workers write to a private `mktemp -d` and their output is re-emitted in
   registered order by the main process — the header never interleaves.
5. **Validity predicate is non-empty-fields + tree + fingerprint + age
   < 30min, all required.** No partial acceptance. Empty/missing `tree`,
   `fingerprint`, `timestamp`, or `epoch` → INVALID (fail closed; empty NEVER
   equals empty-as-valid). The `fingerprint` is CONTENT-sensitive (it hashes
   tracked staged+unstaged CONTENT and untracked file CONTENT, not just
   changed paths — this deliberately CORRECTS #1166's literal
   `git status --porcelain | git hash-object` formula, which is content-blind;
   see "Provenance header format"). A clean tree's fingerprint is a stable
   normal value, not a sentinel.
6. **Targeted-suite derivation is JUDGMENT + the flat registry, NOT a
   maintained map — and it NEVER replaces the cross-cutting gates.**
   `tests/lib/suite-registry.sh` is a flat path enumerator with no area tags.
   The verifier ALWAYS runs the cross-cutting CONCERN suites (enumerated in
   decision 7), THEN — only as a NARROWING on top of them — derives the
   changed area from `git diff` paths and matches suite-name prefix families
   by judgment (e.g. a `hooks/` change → `test-hooks-*`, `test-*-hook-*`),
   using `list_registered_suites()` only to ENUMERATE candidates. A suite is
   elided ONLY when the verifier can affirmatively prove it unrelated; when in
   doubt, full. The full-rerun fallback is the safety net that makes the
   imprecise heuristic acceptable. No diff-path→suite mapping file is created
   (it would rot).
7. **Full re-run is MANDATORY (not judgment) when:** the implementer's
   results are invalid/stale OR the diff touches `tests/`, `hooks/`,
   `scripts/_lib/`, shared skill scripts (`skills/*/scripts/`), the runner
   (`tests/run-all.sh`), ANY `skills/**/*.md` (skill bodies are behavior),
   `agents/*.md`, `.claude/agents/*.md` (the verifier.md twin lives there),
   `CLAUDE_TEMPLATE.md`, or `.claude/rules/zskills/managed.md`
   OR the targeted candidate set is EMPTY/uncertain OR the verifier judges the
   change risky. Targeted re-run is permitted ONLY when results validate AND
   none of those triggers fire. Regardless of mode, the cross-cutting CONCERN
   suites — `test-skill-conformance.sh`, `test-skills-mirror-parity.sh`,
   `test-skill-version-enforcement.sh`, `test-doc-viewer-catalog.sh`,
   `test-managed-md-up-to-date.sh`, `test-agents-parity.sh` — ALWAYS run (they
   gate nearly every change and are cheap).
8. **The verifier's independence is preserved — de-dup changes WHAT executes,
   never WHO.** The fresh verifier still independently audits the diff. The
   orchestrator never self-verifies. Inline self-verification by the
   orchestrator remains a verification FAIL (CLAUDE.md verifier-cannot-run
   rule, unchanged).
9. **`skills/**/*.md` is NOT docs-only.** Skill bodies are behavior — a
   change to any skill `.md` runs the full local suite + full CI. The
   docs-only class is `docs/`, `README*`, `CHANGELOG*`, `PRESENTATION*`
   ONLY. This REFINES `/do`'s existing coarse "any .md" content-only path
   (the one non-additive skill edit in this plan).
10. **The validator lib lives under `tests/lib/`, repo-only — NOT mirrored**
    to `.claude/`. `tests/lib/` is never mirrored (same as
    `parse-results.sh`/`suite-registry.sh`); no mirror-parity applies. It is
    a SOURCEABLE library, NOT registered as a `run_suite`;
    `tests/test-suite-result-valid.sh` is its registered self-test.
11. **`agents/verifier.md` has no `metadata.version`** (agents/ files are
    not skills) — its twin parity is enforced by `tests/test-agents-parity.sh`,
    not skill-version. The 4 SKILL.md edits DO require version bumps.

## Design-history dispositions

| Decision | Disposition |
|---|---|
| run-all.sh writes results to STDOUT ONLY (caller redirects) | **SURVIVES** — the stamp is `echo`'d to stdout, never file-written by run-all; the caller's `> file` captures it as the header. |
| `Overall: N/M passed, F failed` is the canonical tally, grepped by 3+ consumers | **SURVIVES untouched** — the stamp is ADDITIVE (a new top-of-file header); `parse_results()` anchors on `^Results:` (per-suite) and ignores the header; all `Overall:` consumers are grep-for-presence and tolerate extra leading lines. |
| `/do` content-only classifier skips tests for ANY `.md` — the DECISION at skills/do/SKILL.md ≈L881–887 ("Content only — markdown… No tests needed") AND the downstream consumer at ≈L1018–1029 | **REFINED** (Settled decision 9) — BOTH surfaces narrowed to exclude `skills/**/*.md`; this is the single non-additive skill-prose edit. The classification RULE (L881–887) is the load-bearing decision; L1018 is its consumer — refining only the consumer would leave the rule still calling all markdown "no tests needed." Old/new behavior stated in the commit message. |
| `tests/lib/` is repo-only, never mirrored to `.claude/` | **SURVIVES** — the new validator lib follows the same rule (no mirror parity). |
| verifier independence (CLAUDE.md verifier-cannot-run rule) | **SURVIVES untouched** — de-dup changes WHAT the verifier runs, never that a fresh verifier runs. |
| ENFORCEMENT_V2 + Windows-port adoption (re-render managed.md via same renderer) | **NO textual overlap** with #1166's `## Tests` edit (V2 touches CLAUDE_TEMPLATE ≈L387–394 Tracking + execute-phase tracking lines, NOT `## Tests` and NOT the verifier prompt). Keep #1166's edit self-contained + additive + re-render in-commit so the later work rebases cleanly (Execution context note). |

## Why these phases, in this order

- **Phase 1 — STAMP + VALIDATE first.** Everything downstream consumes the
  validator. The validator can only be written once the header format is
  pinned, so the stamp and the validator land together (the stamp is the
  validator's input). The unit suite proves the predicate before any agent
  prose relies on it. No skill files change in Phase 1 — it is pure
  tests/ infrastructure, independently green.
- **Phase 2 — VERIFIER PROTOCOL** consumes the validator. It is the central
  behavioral surface: the verifier.md twin + the 4 dispatch templates teach
  the reuse-when-valid + targeted-rerun + full-rerun protocol. It depends on
  Phase 1's helper existing (the prose references `tests/lib/suite-result-valid.sh`
  by path). Version bumps + mirrors + agents-parity land here.
- **Phase 3 — ORCHESTRATOR baseline reuse + DOCS-ONLY classifier.** Baseline
  reuse is a small execute-phase edit that builds on the Phase 2 verifier
  protocol (the verifier now accepts the baseline as a reusable result). The
  /do classifier refinement is the one non-additive skill edit; it is grouped
  here because both are orchestrator/skill behavior changes downstream of the
  validated-result mechanism.
- **Phase 4 — POLICY PROSE** last: it advertises the policy (CLAUDE_TEMPLATE
  `## Tests` additive subsection) that Phases 1–3 made real, re-renders
  managed.md in lockstep, and adds the conformance pins that lock every new
  prose surface + the new helper. It is last so the prose describes a system
  that already exists and is green.

The validator is FIRST and the policy is LAST; the two behavioral phases
(verifier, orchestrator/classifier) sit between in dependency order.

## Execution context

`main_protected: true` — execute via
`/run-plan docs/plans/SUITE_PROVENANCE_PLAN.md` in worktree mode.
Implementation dispatches to `subagent_type: "implementer"`; verification to
the verifier subagent. Each phase is one commit. All line numbers are
≈L — **verify by content, not blind line number** (the worktree was read at
`a6dbcb02`; sibling sprints may shift lines).

**Coordination with ENFORCEMENT_V2 + Windows-port adoption.** A separate
ENFORCEMENT_V2 author-amendment + Windows-port adoption will ALSO re-render
`.claude/rules/zskills/managed.md` via the SAME `scripts/render-managed-rules.py`
(`test-managed-md-up-to-date.sh` is the shared lock). Per research there is
NO textual overlap: V2 edits `CLAUDE_TEMPLATE.md` ≈L387–394 (Tracking /
Execution Modes) and execute-phase tracking lines (≈L249 / ≈L1800), NOT the
`## Tests` section (CLAUDE_TEMPLATE ≈L111–172) and NOT the Phase-3 verifier
prompt (execute-phase ≈L614–694) or the baseline block (≈L444–453). #1166
MUST keep its `CLAUDE_TEMPLATE.md` edit a SELF-CONTAINED ADDITIVE subsection
inside `## Tests`, keep its execute-phase edits inside the verifier-dispatch
+ baseline blocks (away from the tracking lines V2 owns), and ALWAYS
re-render managed.md in the SAME commit. A managed.md rebase conflict is
resolved by RE-RENDERING against the merged CLAUDE_TEMPLATE.md, never by hand
merge.

## Critical invariants every phase must honor

1. **Skill-versioning quadruple gate (Inv-1 recipe).** ANY edit to a skill
   body, frontmatter (other than `metadata.version` itself), or any regular
   file under a skill dir requires a `metadata.version` bump in source AND
   mirror, SAME commit:
   ```bash
   today=$(TZ=America/New_York date +%Y.%m.%d)
   hash=$(bash scripts/skill-content-hash.sh skills/<S>)
   bash scripts/frontmatter-set.sh skills/<S>/SKILL.md metadata.version "$today+$hash"
   bash scripts/mirror-skill.sh <S>
   ```
   Compute the hash AFTER all content edits to that skill, per commit. The
   current versions to bump in Phase 2: run-plan `2026.06.12+cddf24`,
   fix-issues `2026.06.12+c4f5cc`, do `2026.06.11+0ebe97`, verify-changes
   `2026.06.10+0b68d4`. A denied `git commit` carries the exact bump command
   in its STOP message — run it, re-stage, re-commit; do NOT treat the deny
   as a test failure.
2. **THE SAFETY FLOOR (encode verbatim in Phase 4 policy prose; agents must
   NOT read de-dup as the forbidden "skip verification").** All of the
   following remain non-negotiable and are never weakened by provenance
   reuse:
   - **CI runs the FULL suite on every PR** (fresh-clone backstop — this is
     the layer no local de-dup can compromise).
   - **Post-commit committed-state gates** (the hook gates that fire on
     `git commit`/`cherry-pick`/`push`) stay in force.
   - **Layer-3 response validation** of every verifier response stays in
     force (`verify-response-validate.sh`).
   - **Fresh-verifier INDEPENDENCE** — provenance reuse changes WHAT the
     verifier executes, NEVER WHO executes it. A fresh verifier still runs;
     the orchestrator never self-verifies.
   - **A full LOCAL run before landing ANY PR that touches shared infra**
     (`tests/`, `hooks/`, `scripts/_lib/`, shared skill scripts, the runner).
   - **Plan-completion boundary runs** (the full suite at every phase
     boundary / before the final landing) stay mandatory.
   - **The two-attempt fix discipline** (CLAUDE.md "NEVER thrash on a
     failing fix") is unchanged.
   **Threat model (the plan's correctness argument):** a fabricated OR stale
   results file fails at THREE layers — the validator (the CONTENT-sensitive
   tree fingerprint mismatches a tree it did not measure; the validator is
   sound on dirty trees because the fingerprint hashes file CONTENT, not just
   changed paths, and fails closed on empty fields / absent git), the targeted
   re-run PLUS the always-on cross-cutting concern suites (the changed area
   must actually pass on the live tree), and CI (a fresh full run on a clean
   clone). Provenance reuse NEVER accepts a result for a tree whose CONTENT was
   not measured.
3. **`agents/verifier.md` twin parity.** `agents/verifier.md` and
   `.claude/agents/verifier.md` must change IDENTICALLY (the de-dup
   subsection lands in BOTH), byte-identical modulo the frontmatter `hooks:`
   block. Gated by `tests/test-agents-parity.sh` — green at the phase
   boundary.
4. **managed.md rendered, never hand-edited.** `.claude/rules/zskills/managed.md`
   is rendered from `CLAUDE_TEMPLATE.md` via `scripts/render-managed-rules.py`.
   Any `CLAUDE_TEMPLATE.md` edit re-renders managed.md in the SAME commit.
   Gated by `tests/test-managed-md-up-to-date.sh`.
5. **Triplet registration.** The new suite `tests/test-suite-result-valid.sh`
   lands with its ONE `tests/run-all.sh` registration line in the SAME commit;
   the `tests/test-suite-registry.sh` count assertion (`150 < distinct < raw`)
   stays green automatically (adding one suite raises the count by 1). The
   sourceable lib `tests/lib/suite-result-valid.sh` is NOT registered as a
   `run_suite`.
6. **Skill-file hardcode discipline.** New prose in skill `.md` files MUST
   NOT hardcode consumer literals (`npm run test:all`, `bash tests/run-all.sh`,
   `$TEST_OUT/.test-results.txt`, `TZ=America/New_York`) inside a bash fence —
   resolve via the canonical prelude (`$FULL_TEST_CMD`, `$TEST_OUTPUT_FILE`)
   or mark with `<!-- allow-hardcoded: … -->`. Keep `tests/run-all.sh` and
   `suite-result-valid.sh` literals confined to `tests/` files and to PROSE
   (not bash fences) in skill bodies. Gated by `tests/test-skill-conformance.sh`
   deny-list + `hooks/warn-config-drift.sh`.
7. **Capture test output out-of-tree, never pipe:**
   ```bash
   TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
   mkdir -p "$TEST_OUT"
   bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
   ```
   Then READ the file; report per-suite pass COUNTS, naming the command and
   each suite's result.
8. **Suite green at every phase boundary** — `bash tests/run-all.sh` passes
   before the phase's commit is considered done.
9. **No new general bypass.** No phase introduces an env var, marker, or flag
   that turns verification off wholesale. The only de-dup is provenance-valid
   reuse + targeted re-run, always backed by the safety floor (Invariant 2).
10. **Historical surfaces are off-limits:** `CHANGELOG.md`, `docs/plans/`
    (other than THIS file's tracker), `docs/reports/`, `docs/issues/`.

## Provenance header format — pinned VERBATIM (the implementer's only spec)

`tests/run-all.sh` emits, ONCE, immediately after the env header (after
`OVERALL_EXIT=0` at ≈L17, BEFORE any `run_suite` registration runs), the
following block to **stdout** (so the caller's `> file` redirect captures it
as the file header). Compute the values once at the top:

```
zskills-suite-provenance: v1
tree=<git -C "$REPO_ROOT" rev-parse HEAD>
fingerprint=<content-sensitive tree fingerprint, formula below>
timestamp=<ISO-8601 UTC, human/forensic, e.g. date -u +%Y-%m-%dT%H:%M:%SZ>
epoch=<integer seconds since epoch at run start, date -u +%s>
command=<the runner command, e.g. tests/run-all.sh>
```

- Each field is a `key=value` line; the first line `zskills-suite-provenance: v1`
  is the format-version marker the validator anchors on.
- `tree` = `git -C "$REPO_ROOT" rev-parse HEAD` (the committed HEAD).
  run-all.sh does NOT `cd` (verified: it exports `REPO_ROOT` at ≈L6 but has
  zero `cd`), so EVERY git call MUST use `-C "$REPO_ROOT"` — bare
  `git rev-parse` would read the caller's cwd.
- **`fingerprint`** = a CONTENT-sensitive hash of the full working-tree state.
  Pinned VERBATIM (compute once at the top, after `tree`):
  ```bash
  fingerprint=$(
    {
      git -C "$REPO_ROOT" rev-parse HEAD
      git -C "$REPO_ROOT" diff HEAD          # tracked staged+unstaged CONTENT
      git -C "$REPO_ROOT" ls-files --others --exclude-standard -z \
        | while IFS= read -r -d '' f; do
            printf '%s\0' "$f"
            git -C "$REPO_ROOT" hash-object "$REPO_ROOT/$f"
          done
    } | git -C "$REPO_ROOT" hash-object --stdin
  )
  ```
  This captures: (1) the committed HEAD, (2) ALL tracked changes — `git diff
  HEAD` includes BOTH staged and unstaged content (verified below), (3) the
  CONTENT of every untracked-not-ignored file (`--exclude-standard` honors
  `.gitignore`, so the gitignored `.zskills/` and test artifacts are excluded).
  **This deliberately CORRECTS the issue's `dirty=$(git status --porcelain |
  git hash-object --stdin)` formula, which hashes changed PATHS not CONTENT and
  therefore COLLIDES** when an already-modified file's content changes further
  (porcelain stays ` M path`). A clean tree yields a stable value (not a
  sentinel). Rationale: the validator's entire promise is "right tree,
  measured"; a content-blind hash makes that FALSE on the common dirty-tree
  state, defeating defense layer 1.
- `timestamp` = ISO-8601 UTC at run start — **forensic/human-readable only**
  (the validator does NOT re-parse it; it uses `epoch`). Kept because it is
  useful in logs.
- `epoch` = integer `date -u +%s` at run start. The validator computes age
  from THIS (a plain integer subtraction), so it never re-parses an ISO string
  — fully portable across GNU and BSD/macOS `date` (closes the
  timestamp-parsing portability gap).
- `command` = the runner invocation string (`tests/run-all.sh`) —
  **forensic-only, NOT part of the validity predicate**; useful in logs.
- The block is emitted by the MAIN process only, in BOTH parallel
  (`ZSKILLS_PARALLEL=1`, default) and serial (`ZSKILLS_PARALLEL=0`) modes,
  at the same top emit point (after ≈L17) — never by parallel workers.
- **Fail-safe on git-absent.** If `git -C "$REPO_ROOT" rev-parse HEAD` fails
  (no git on PATH, not a repo, or unborn HEAD), the corresponding field is
  emitted EMPTY. The header is still emitted, but the validator treats an
  empty `tree`/`fingerprint`/`epoch` as malformed → exit 1 → full re-run,
  INDEPENDENT of any live comparison (so the `""==""` fail-OPEN that a literal
  string-equality check would allow when git is ALSO absent at validate time
  cannot occur — see validator predicate clause 0). Empty NEVER equals
  empty-as-valid.

**Verified transcript (scratch repo `/tmp/prov-collide-test`, isolated env).**
The issue's formula collides; the pinned fingerprint flips on every
content-only change and is stable on a clean tree:

```
=== DIRTY HASH COLLISION (issue formula) ===
X=34b342cb782f8be284288a2a4123e87090befd1b   #  M f.txt, content "CONTENT_X"
Y=34b342cb782f8be284288a2a4123e87090befd1b   #  M f.txt, content "CONTENT_Y…"
COLLISION CONFIRMED                            # identical hash, different content

=== FIX: tracked content change ===
X=56d111c6…  Y=0e8e77f9…  FLIPS (good)
=== untracked content change ===
A=587a5930…  B=1e32a22b…  FLIPS (good)
=== staged+unstaged both covered by diff HEAD ===
staged=e4e0d6e8…  unstaged=f8ff4a92…  FLIPS (good)
=== clean tree stable ===
c1=e4e0d6e8…  c2=e4e0d6e8…  STABLE (good)
```

## Validator predicate — pinned VERBATIM

`tests/lib/suite-result-valid.sh <file>` — a SOURCEABLE library defining
`suite_result_valid <file>` and runnable directly (`bash tests/lib/suite-result-valid.sh <file>`)
for the unit suite. Exit 0 (valid) IFF ALL of the clauses hold; exit 1
otherwise. The validator's live git calls ALSO use `git -C "$REPO_ROOT" …`
(it must NOT assume the caller's cwd is the repo root):

0. **Fields present + non-empty (fail closed).** `<file>` exists, its first
   non-blank line is `zskills-suite-provenance: v1`, and it contains
   NON-EMPTY `tree=`, `fingerprint=`, `timestamp=`, `epoch=` lines (grep the
   header region, ~first 10 lines). Missing file / missing marker / missing OR
   EMPTY field → exit 1. **Empty is malformed, not a wildcard** — this clause
   is checked BEFORE any live comparison, so an empty recorded `tree` can
   never `""==""`-match an empty live value when git is unavailable.
1. **git available + HEAD resolvable.** `git -C "$REPO_ROOT" rev-parse HEAD`
   must succeed (non-empty output, exit 0). If git is absent / not a repo /
   HEAD unborn → exit 1 (cannot prove "same tree" → full re-run).
2. **Tree + fingerprint match the CURRENT tree.** Recorded `tree` ==
   `git -C "$REPO_ROOT" rev-parse HEAD` (live) AND recorded `fingerprint` ==
   the live content-sensitive fingerprint (recompute the EXACT formula pinned
   in "Provenance header format" — same `git diff HEAD` + untracked roll-up).
   Any mismatch → exit 1 (the working-tree CONTENT changed since the result
   was measured — including a content-only edit to an already-modified file,
   which the old porcelain formula missed).
3. **Age < 30 minutes.** `(now_epoch - recorded_epoch) < 1800` where
   `now_epoch=$(date -u +%s)` and `recorded_epoch` is read DIRECTLY from the
   header's `epoch=` field (a plain integer — NO ISO re-parse, so the check is
   portable across GNU and BSD/macOS `date`). A negative or future delta
   (`now_epoch < recorded_epoch`) → invalid (defensive) → exit 1. A
   non-integer / empty `epoch` was already rejected by clause 0.

The pass signal of the RUN itself (every suite passed) is verified SEPARATELY
by the verifier reading the bottom `Overall: N/M passed, F failed` line —
the validator answers ONLY "is this result still TRUE for the current tree?",
not "did it pass?" (the verifier's tally check at agents/verifier.md ≈L22–49
owns the pass check). Keep these two concerns distinct: a result can be VALID
(right tree, fresh) and FAILING (`Overall: ... F failed`) — in which case the
verifier reuses the validity but acts on the failure.

Style: model the file header + single-function shape on
`tests/lib/parse-results.sh` ("SOURCEABLE LIBRARY, NOT A SUITE. Do NOT
register in run-all.sh as a `run_suite`. `tests/test-suite-result-valid.sh`
is the registered self-test."). If the lib self-locates, use the
`${BASH_SOURCE[0]:-$0}` zsh-portable idiom (#1149); a validator taking
`<file>` as `$1` and calling live git/date may not need self-location at all.
Pure bash + `git`/`date` math — NO jq, NO Python (the fields are simple
grep-able lines; bash is the right tool here per research §4).

## Targeted-suite derivation procedure — pinned VERBATIM (verifier protocol)

**Framing (read this FIRST so the protocol cannot be misread as license to
skip):** a suite is elided ONLY when the verifier can affirmatively prove it
unrelated to the change. The cross-cutting CONCERN gates ALWAYS run. When the
targeted set is empty or uncertain, run the FULL suite. "Ran nothing" is never
an acceptable outcome.

When the implementer's results VALIDATE (validator exit 0) for the current
tree AND none of the full-rerun triggers fire (below), the verifier does NOT
re-run the full suite. Instead:

1. **Verify the tally on the reused result.** Read the bottom
   `Overall: N/M passed, F failed` line: assert it is present, `N == M`,
   `F == 0`, and (when a baseline exists) `N >= baseline_N`. Absent/failing
   tally → treat as a verification FAIL even though the result was VALID
   (the run failed); do NOT silently reuse a failing result.
2. **ALWAYS run the cross-cutting CONCERN suites.** Regardless of the derived
   area, run these (cheap, gate nearly every change; exact on-disk names
   verified):
   - `tests/test-skill-conformance.sh`
   - `tests/test-skills-mirror-parity.sh`
   - `tests/test-skill-version-enforcement.sh`
   - `tests/test-doc-viewer-catalog.sh` (catalog/DocsRegistry drift)
   - `tests/test-managed-md-up-to-date.sh`
   - `tests/test-agents-parity.sh`
   These are NOT prefix-matched — they gate by CONCERN, not area, so the
   prefix heuristic in step 3 would MISS them. They are the floor.
3. **Derive the changed-area suites on TOP of the floor.** Run
   `git diff $(git merge-base origin/main HEAD)..HEAD --name-only`. **If
   `merge-base` fails (origin/main unfetched/stale) OR the changed-path set is
   empty while HEAD is provably ahead of main → FULL re-run** (fail closed).
   Otherwise group the changed paths into area families by judgment, e.g.:
   - a change under `hooks/` → the `test-hooks-*` and `test-*-hook-*` families;
   - a change under `skills/do/` → `test-do-*`;
   - a change under `skills/fix-issues/` → `test-fix-issues-*`;
   - a change under `skills/land-pr/` → `test-land-pr-*`;
   - a change under `skills/update-zskills/` → `test-update-zskills-*`;
   - a change under the doc viewer → `test-doc-viewer-*`;
   - a change to a plan-claim path → `test-plan-claim-*`;
   - and analogously for other prefix families.
   This is a JUDGMENT heuristic over the NAMING CONVENTION, not a maintained
   path→suite table (`tests/lib/suite-registry.sh` carries NO area tags —
   Settled decision 6). Enumerate candidates via `list_registered_suites()`
   (from `tests/lib/suite-registry.sh`); select the basenames that match the
   derived families. **If the derived candidate set is EMPTY, or you are not
   confident it covers the changed area → run the FULL suite. An empty
   targeted set is NEVER an acceptable substitute for verification.** Run each
   selected suite as `bash tests/test-<name>.sh`, check its `Results: N
   passed, F failed` line. All (floor + targeted) must pass.
4. **The verifier STILL independently audits the diff** (scope-creep check,
   acceptance-criteria check) regardless of de-dup — de-dup changes WHAT
   runs, never the independent audit (Settled decision 8 / Invariant 2).

**FULL re-run is MANDATORY (overrides steps 2–3) when ANY of:**

- the implementer's results are INVALID or STALE (validator exit 1); OR
- the diff touches `tests/`, `hooks/`, `scripts/_lib/`, shared skill scripts
  (`skills/*/scripts/`), the runner (`tests/run-all.sh`), ANY `skills/**/*.md`
  (skill bodies are behavior — a conformance/mirror/version-bump bug there is
  caught by the concern suites the prefix heuristic misses, AND skill bodies
  warrant the full pass), `agents/*.md`, `.claude/agents/*.md` (the verifier.md
  twin lives there), `CLAUDE_TEMPLATE.md`, or
  `.claude/rules/zskills/managed.md`; OR
- the targeted candidate set is EMPTY/uncertain, or `merge-base` fails; OR
- the verifier judges the change risky (cross-cutting, ambiguous area, large
  surface).

In the full-rerun case the verifier runs the entire `$FULL_TEST_CMD` exactly
as today and applies the existing tally check — no behavior change from the
status quo. The targeted path is a NARROWING that is only entered when it is
demonstrably safe; the full path is the default whenever any doubt exists.

### Reuse timing per dispatch context (where the saving is REAL vs foreclosed)

The de-dup only saves a run when the tree the implementer MEASURED still
matches the tree the consumer CHECKS. This differs per context — stated
honestly so the plan does not promise a reuse the predicate refuses:

- **run-plan (`execute-phase`) — REUSE IS REAL.** The implementer does NOT
  commit; the verifier runs tests and COMMITS afterward (verified:
  execute-phase ≈L241 "implementer does NOT commit; verifier commits after").
  So at verify time the working tree is the SAME dirty pre-commit tree the
  implementer measured → `tree` + `fingerprint` match → the verifier reuses
  the implementer's (or the orchestrator baseline's) result and runs only the
  floor + targeted suites. This is the primary realizable saving.
- **verify-changes — REUSE IS REAL when a fresh result already exists at the
  current working tree** (e.g. the orchestrator captured one moments earlier
  on the same uncommitted tree). If the tree advanced, the validator returns
  exit 1 → full run. No false promise.
- **/do — same as verify-changes** (it dispatches the verifier on the same
  working tree before its own commit). Reuse real iff a fresh same-tree result
  exists.
- **fix-issues — REUSE IS REAL (same model as run-plan).** fix-issues uses the
  IDENTICAL verifier-commits-after model: the impl agent runs `$FULL_TEST_CMD`
  but does NOT commit; the verification agent commits AFTER passing tests
  (verified: `skills/fix-issues/SKILL.md` ≈L369–370 — "The verification agent
  commits after passing tests — the implementation agent does not commit").
  So at verify time the working tree is the SAME dirty pre-commit tree the impl
  agent measured → `tree` + `fingerprint` BOTH match → the verifier reuses the
  impl agent's stamped result and runs only the floor + targeted suites. This is
  a realizable primary saving in fix-issues, exactly as in run-plan. The honest
  caveat that DOES apply: a result captured BEFORE the impl agent's LAST edit is
  invalidated by the content-sensitive fingerprint (content drift between
  capture and verify) → validator exit 1 → full re-run. That is the predicate
  working as designed, not a foreclosure. The Phase-2 fix-issues edit documents
  this true model — it does NOT claim the impl agent self-commits or that reuse
  is foreclosed across a commit boundary.

## Safety-floor policy prose — pinned VERBATIM (Phase 4 CLAUDE_TEMPLATE subsection)

The Phase 4 additive subsection (between the "Capture test output" block,
CLAUDE_TEMPLATE.md ≈L147, and "Pre-existing test failures" ≈L149) reads
substantially as follows (the implementer may adjust surrounding wording for
flow but MUST preserve every load-bearing clause):

> ### Tests — result provenance / de-duplication
>
> A `tests/run-all.sh` run now carries a provenance header recording the
> tree it measured (`tree`, a CONTENT-sensitive `fingerprint`, `timestamp` +
> `epoch`). The sourced validator `tests/lib/suite-result-valid.sh <file>`
> answers "is this result still true for the current tree?" — exit 0 iff the
> recorded `tree` and content `fingerprint` match the live tree AND the result
> is under 30 minutes old; it fails closed on any empty field or absent git.
>
> **Reusing a provenance-validated result for the SAME tree is
> de-duplication, NOT skipping verification.** When a fresh verifier finds a
> result that validates for the current tree, it verifies the tally, ALWAYS
> re-runs the cross-cutting concern suites (conformance, mirror-parity,
> skill-version, catalog, managed-md, agents-parity), and additionally re-runs
> the suites covering the changed area (derived from the diff paths by
> judgment) — instead of blindly re-running everything that was just run on the
> identical tree. A suite is elided ONLY when it is provably unrelated; an
> empty or uncertain targeted set means a FULL re-run, never "ran nothing."
>
> **The safety floor is non-negotiable and is never weakened by reuse:**
> CI runs the full suite on every PR (the fresh-clone backstop); the
> post-commit committed-state gates stay in force; Layer-3 response
> validation stays in force; the fresh verifier's INDEPENDENCE is preserved
> — de-dup changes WHAT the verifier executes, never WHO; a full LOCAL run
> is mandatory before landing ANY PR that touches shared infra (`tests/`,
> `hooks/`, `scripts/_lib/`, shared skill scripts, the runner); the
> plan-completion boundary runs stay mandatory; and the two-attempt fix
> discipline is unchanged.
>
> **A full re-run is MANDATORY** when the result is invalid/stale, when the
> diff touches `tests/`, `hooks/`, `scripts/_lib/`, shared skill scripts, the
> runner, ANY `skills/**/*.md` (skill bodies are behavior), `agents/*.md`,
> `.claude/agents/*.md`, `CLAUDE_TEMPLATE.md`, or `managed.md`, when the
> targeted set is empty, or when the verifier judges the change risky.
>
> **Threat model:** a fabricated or stale results file fails at three
> independent layers — the validator (content-sensitive tree fingerprint
> mismatch), the targeted re-run plus the always-on concern suites (the
> changed area must actually pass), and CI (a fresh full run). Provenance
> reuse never accepts a result for a tree whose CONTENT was not measured.

Skill-file hardcode discipline applies to this prose only insofar as it lands
in `CLAUDE_TEMPLATE.md` (which renders to managed.md) — `tests/run-all.sh`
and `suite-result-valid.sh` are tests/ paths, not config-derived consumer
literals, so they are acceptable in PROSE; do not place them in a bash fence
that would trip the deny-list.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — STAMP (run-all.sh header) + VALIDATE helper + triplet unit suite | ⬚ | | |
| 2 — VERIFIER PROTOCOL: verifier.md twin + 4 dispatch templates + version bumps + mirrors | ⬚ | | |
| 3 — ORCHESTRATOR baseline reuse + DOCS-ONLY classifier refinement | ⬚ | | |
| 4 — POLICY PROSE: CLAUDE_TEMPLATE Tests subsection + managed.md re-render + conformance pins | ⬚ | | |

---

## Phase 1 — STAMP (run-all.sh header) + VALIDATE helper + triplet unit suite

### Goal

Emit the provenance header from `tests/run-all.sh` (surface 1), land the
sourced validator `tests/lib/suite-result-valid.sh` (surface 2), and land its
triplet-registered unit suite `tests/test-suite-result-valid.sh`. No skill
files, no agent files, no policy prose change this phase — pure tests/
infrastructure, independently green. Everything downstream consumes the
validator, so it is first.

### Work Items

- [ ] **`tests/run-all.sh` provenance header.** Insert the header block
  (format pinned in "Provenance header format" above) immediately AFTER
  `OVERALL_EXIT=0` (≈L17), BEFORE the first comment of the parallel driver
  (≈L19) and BEFORE any `run_suite` registration. Compute `tree`,
  `fingerprint` (the CONTENT-sensitive formula — `git -C "$REPO_ROOT" diff
  HEAD` + untracked roll-up, pinned verbatim), `timestamp`, `epoch`, `command`
  once and `printf`/`echo` the lines to stdout. EVERY git call uses
  `git -C "$REPO_ROOT" …` (run-all.sh does NOT `cd` — verified). The bottom
  `Overall: N/M passed, F failed` line (≈L583/585) is UNTOUCHED.
- [ ] **`tests/lib/suite-result-valid.sh`** — sourceable lib defining
  `suite_result_valid <file>` (predicate pinned in "Validator predicate"
  above). Header comment: "SOURCEABLE LIBRARY, NOT A SUITE. Do NOT register
  in run-all.sh as a `run_suite`. `tests/test-suite-result-valid.sh` is the
  registered self-test." Pure bash + `git`/`date`; NO jq, NO Python. Exit
  0/1 per the predicate clauses (clause 0 non-empty-fields fail-closed,
  clause 1 git-available, clause 2 tree+CONTENT-fingerprint match, clause 3
  age from `epoch` < 30min). Live git via `git -C "$REPO_ROOT" …`. Recompute
  the EXACT fingerprint formula from the header-format section. If it
  self-locates, use `${BASH_SOURCE[0]:-$0}`.
- [ ] **`tests/test-suite-result-valid.sh`** — unit suite modeled on
  `tests/test-zsh-fence-resolution.sh` (shebang, `SCRIPT_DIR`/`REPO_ROOT`,
  `PASS_COUNT`/`FAIL_COUNT`, `pass()`/`fail()`, sources the lib, ends with a
  `Results: <N> passed, <N> failed` line). Each fixture synthesizes a header
  from live values via the lib's own fingerprint formula so the test is
  self-consistent on any platform. Cases at minimum:
  - VALID: header whose `tree`/`fingerprint` match the live tree,
    `epoch=$(date -u +%s)` (now) → exit 0.
  - INVALID tree: header with a fabricated/old `tree` SHA → exit 1.
  - INVALID fingerprint: header with a wrong `fingerprint` hash → exit 1.
  - **CONTENT-DRIFT (the R1-1/DA1 regression case): same set of changed paths
    but DIFFERENT file content between measure and check → fingerprint
    differs → exit 1.** Synthesize by capturing a fingerprint, then mutating a
    file's CONTENT without changing its path/status, then re-validating.
  - **UNTRACKED-CONTENT-DRIFT: an untracked-not-ignored file whose content
    changes → fingerprint differs → exit 1.**
  - **CLEAN-STABLE: two fingerprints of an unchanged clean tree are equal →
    a header from the first validates against the second → exit 0.**
  - STALE: header with `epoch=$(( $(date -u +%s) - 1860 ))` (31 min old) →
    exit 1. (Epoch arithmetic — portable, NOT `date -d '-31 min'`.)
  - FRESH boundary: `epoch=$(( $(date -u +%s) - 1740 ))` (~29 min) → exit 0.
  - MISSING file: nonexistent path → exit 1.
  - MISSING/garbled header: a results file with no
    `zskills-suite-provenance: v1` marker, or missing a field → exit 1.
  - **EMPTY-FIELD (the DA3 fail-OPEN case): header with an EMPTY
    `tree=`/`fingerprint=`/`epoch=` value → exit 1** (clause 0; empty never
    equals empty-as-valid).
  - FUTURE epoch (defensive): `epoch` greater than now → exit 1.
  Use `mktemp` for all fixture files (NEVER a hardcoded `/tmp` path —
  `tests/test-tmpdir-hardcode-guard.sh` guards this). For the content-drift
  cases, a `mktemp -d` scratch git repo is the cleanest fixture (the test must
  not mutate the worktree it runs in).
- [ ] **Registration (triplet).** Add ONE line to `tests/run-all.sh` in the
  lib self-test registration block (near ≈L234–235, where
  `test-parse-results.sh` / `test-suite-registry.sh` are registered):
  ```
  run_suite "test-suite-result-valid.sh" "tests/test-suite-result-valid.sh"
  ```
  EXACT format: `run_suite "<display-name>" "<tests/path.sh>"` (two
  double-quoted fields). Do NOT register `tests/lib/suite-result-valid.sh`
  (it is the lib, not a suite). The `tests/test-suite-registry.sh` count
  assertion stays green automatically (distinct count +1, still
  `150 < distinct < raw`).

### Design & Constraints

- The header must not match `^Results:` (so `parse_results()` ignores it)
  and must not contain a suite name (so the 80+ "registered in run-all.sh"
  self-asserts don't false-match). The `key=value` shape and the
  `zskills-suite-provenance:` marker satisfy both.
- The validator answers VALIDITY only (non-empty fields + tree +
  content-fingerprint + age), NOT pass/fail — keep the pass check out of the
  validator (the verifier owns the `Overall:` tally check, Phase 2).
- The fingerprint formula in the lib MUST be byte-identical to the one
  run-all.sh emits (same `git -C "$REPO_ROOT" diff HEAD` + untracked roll-up);
  any divergence makes a freshly-captured header fail its own validator. The
  Phase-1 round-trip AC catches this.
- **Do NOT touch:** any skill `.md`, `agents/*.md`, `.claude/agents/*.md`,
  `CLAUDE_TEMPLATE.md`, `.claude/rules/zskills/managed.md`,
  `tests/test-skill-conformance.sh`, the bottom `Overall:` line of
  run-all.sh, `tests/lib/parse-results.sh`, `tests/lib/suite-registry.sh`.

### Acceptance Criteria

- [ ] Header present, once, at the top of stdout, in both modes:
  `bash tests/run-all.sh 2>/dev/null | head -8 | grep -c '^zskills-suite-provenance: v1'` → `1`
  and `ZSKILLS_PARALLEL=0 bash tests/run-all.sh 2>/dev/null | head -8 | grep -c '^zskills-suite-provenance: v1'` → `1`.
- [ ] Header carries all fields:
  `bash tests/run-all.sh 2>/dev/null | head -8 | grep -cE '^(tree|fingerprint|timestamp|epoch|command)='` → `5`.
- [ ] The dropped field is absent (no inert back-ref):
  `bash tests/run-all.sh 2>/dev/null | head -8 | grep -c '^canonical-tally='` → `0`.
- [ ] The bottom tally is unchanged:
  `bash tests/run-all.sh 2>/dev/null | grep -c 'Overall: '` → `1`.
- [ ] `parse_results()` still ignores the header (no count leak): the
  per-suite `Results:` parsing is unaffected — verify the overall tally still
  reflects the true suite counts (Invariant 8 capture; report counts).
- [ ] Validator predicate:
  `bash tests/test-suite-result-valid.sh` passes; report per-case counts.
- [ ] Direct validator round-trip on a live header:
  `bash tests/run-all.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.prov.txt 2>&1; bash tests/lib/suite-result-valid.sh /tmp/zskills-tests/$(basename "$(pwd)")/.prov.txt; echo $?` → `0`
  (run from the repo root immediately after capture).
- [ ] Suite registered:
  `grep -c 'run_suite "test-suite-result-valid.sh"' tests/run-all.sh` → `1`;
  the lib is NOT registered:
  `grep -c 'run_suite.*suite-result-valid.sh"' tests/run-all.sh` → `1`
  (only the test, not the lib).
- [ ] `bash tests/run-all.sh` green (Invariant 7 capture idiom); per-suite
  counts reported, including `test-suite-registry.sh` and the new
  `test-suite-result-valid.sh`.

### Dependencies

None — first phase.

---

## Phase 2 — VERIFIER PROTOCOL: verifier.md twin + 4 dispatch templates + version bumps + mirrors

### Goal

Teach the de-dup protocol (reuse-when-valid + targeted-rerun + full-rerun-on-shared-infra,
pinned in "Targeted-suite derivation procedure" above) to the CENTRAL
verifier surface — `agents/verifier.md` AND its `.claude/agents/verifier.md`
twin (parity-locked) — and to the 4 dispatch templates. Bump + mirror the 4
affected skills. No validator/runner change this phase (it consumes Phase 1).

### Work Items

- [ ] **`agents/verifier.md` + `.claude/agents/verifier.md` (parity twins —
  edit BOTH identically, Invariant 3).** Add a new subsection (e.g.
  `## Result-provenance de-duplication`) after the tally-check section
  (≈L22–49), referencing the full-suite capture block (≈L12–20). The
  subsection text:
  - When you are handed (or can locate) the implementer's captured results
    file, FIRST run `bash tests/lib/suite-result-valid.sh <file>`. Exit 0
    (VALID for the current tree, < 30min) → you MAY de-duplicate: verify the
    tally on that file (the existing `Overall: N/M passed, F failed` check),
    ALWAYS run the cross-cutting CONCERN suites (`test-skill-conformance.sh`,
    `test-skills-mirror-parity.sh`, `test-skill-version-enforcement.sh`,
    `test-doc-viewer-catalog.sh`, `test-managed-md-up-to-date.sh`,
    `test-agents-parity.sh` — they gate by concern, not area, so the prefix
    heuristic misses them), THEN additionally re-run the suites covering the
    changed area (the targeted derivation procedure: diff paths → prefix
    families → `list_registered_suites()` candidate set). **If the targeted
    set is EMPTY or you are not confident it covers the change → run the FULL
    suite.** A suite is elided ONLY when you can prove it unrelated.
  - Exit 1 (invalid/stale) → run the FULL `$FULL_TEST_CMD` as today.
  - Run the FULL suite REGARDLESS when the diff touches `tests/`, `hooks/`,
    `scripts/_lib/`, shared skill scripts (`skills/*/scripts/`), the runner,
    ANY `skills/**/*.md` (skill bodies are behavior), `agents/*.md`,
    `.claude/agents/*.md`, `CLAUDE_TEMPLATE.md`, or `managed.md`, or when you
    judge the change risky.
  - You STILL independently audit the diff (scope-creep + acceptance
    criteria) in EVERY case — de-dup changes WHAT you run, never that you run
    an independent check (Invariant 2 / Settled decision 8).
  Keep the change byte-identical across both twins modulo the frontmatter
  `hooks:` block. Mention `suite-result-valid.sh` and `provenance` by name
  (these are the conformance anchor tokens Phase 4 pins).
- [ ] **`skills/run-plan/modes/execute-phase.md` — Phase-3 verifier-dispatch
  prompt.** In the verifier prompt block (≈L614–694, near the tally check
  ≈L686–694), add the de-dup instruction: "Before re-running the full suite,
  run `tests/lib/suite-result-valid.sh` on the implementer's results file;
  if it validates for the current tree, verify the tally, ALWAYS run the
  cross-cutting concern suites, and re-run the targeted suites for the changed
  area; run the full suite when invalid/stale, when the targeted set is empty,
  or when the diff touches shared infra (`tests/`, `hooks/`, `scripts/_lib/`,
  shared skill scripts, the runner) or any `skills/**/*.md` / `agents/*.md` /
  `.claude/agents/*.md` / `CLAUDE_TEMPLATE.md`." (NOTE the run-plan timing: the implementer does NOT
  commit and the VERIFIER commits after — so at verify time the tree matches
  what the implementer measured and reuse is real.) Keep it INSIDE the
  verifier-dispatch block — away from the tracking lines ENFORCEMENT_V2 owns
  (≈L249 / ≈L1800). Bump `skills/run-plan/SKILL.md` version + mirror (Inv-1).
- [ ] **`skills/verify-changes/SKILL.md` — full-suite step.** At the head of
  the "Run the full test suite" step (≈L354–367), add: "If a results file
  already exists for the CURRENT working tree, run
  `tests/lib/suite-result-valid.sh` on it; on exit 0, de-duplicate — verify
  the tally, ALWAYS run the cross-cutting concern suites, and re-run only the
  targeted suites for the changed area; on exit 1, when the targeted set is
  empty, or when the diff touches shared infra / any `skills/**/*.md`, run the
  full suite as below." Preserve the existing capture fence. Bump version +
  mirror.
- [ ] **`skills/do/SKILL.md` — code-changes full-suite path.** In the "Code
  changes" full-suite block (≈L1059–1072), add the same de-dup pointer (a
  validating result for the CURRENT working tree → cross-cutting concern
  suites + targeted rerun; invalid/stale, empty targeted set, shared-infra, or
  any `skills/**/*.md` → full). Do NOT touch the content-only classifier here
  (that is Phase 3). Bump version + mirror.
- [ ] **`skills/fix-issues/SKILL.md` — verifier de-dup pointer (reuse is
  real).** At the `$FULL_TEST_CMD before every commit` rule (≈L381–383), add a
  NOTE that the impl-agent's pre-commit run produces a STAMPED results file
  AND — because fix-issues uses the verifier-commits-after model (the impl agent
  does NOT commit; the verification agent commits after passing tests, ≈L369–370)
  — that stamped result IS reusable by the verification agent at verify time:
  the working tree is the SAME dirty pre-commit tree the impl agent measured, so
  `suite-result-valid.sh` validates it (exit 0) and the verifier de-duplicates
  (verify the tally, ALWAYS run the cross-cutting concern suites, re-run the
  targeted area; full suite on invalid/stale, empty/uncertain target, or a
  shared-infra / `skills/**/*.md` / `agents/*.md` / `CLAUDE_TEMPLATE.md` diff).
  The honest caveat: a result captured BEFORE the impl agent's LAST edit drifts
  in content → fingerprint mismatch → exit 1 → full re-run (the predicate
  working, not a foreclosure). Do NOT write that the impl agent self-commits or
  that reuse is foreclosed across a commit boundary (the model is identical to
  run-plan). (fix-issues impl agents are `subagent_type: "implementer"`.) Bump
  version + mirror. — This edit must mention `suite-result-valid.sh` /
  `provenance` for the Phase-4 conformance pin.
- [ ] **Version bumps (Inv-1) for all 4 skills, computed per commit AFTER all
  this-phase edits to each skill:** run-plan, verify-changes, do, fix-issues.
  Mirror each via `bash scripts/mirror-skill.sh <S>` (modes/ files mirror in
  lockstep — `tests/test-skills-mirror-parity.sh`).

### Design & Constraints

- The de-dup prose references `tests/lib/suite-result-valid.sh` (a tests/
  path) and reuses `$FULL_TEST_CMD` — keep `bash tests/run-all.sh`-style
  consumer literals OUT of bash fences in skill bodies (Invariant 6;
  prose-mention of the tests/ path is fine).
- `agents/verifier.md` has NO `metadata.version` — do NOT add one; its parity
  is the gate (`tests/test-agents-parity.sh`).
- **Do NOT touch:** `tests/run-all.sh`, `tests/lib/suite-result-valid.sh`,
  `CLAUDE_TEMPLATE.md`, `managed.md`, the /do content-only classifier
  (≈L1018–1029, Phase 3), the execute-phase baseline block (≈L444–453,
  Phase 3), `tests/test-skill-conformance.sh` (Phase 4).

### Acceptance Criteria

- [ ] Twin parity: `bash tests/test-agents-parity.sh` passes.
- [ ] Both verifier twins carry the new anchor:
  `grep -lF 'suite-result-valid.sh' agents/verifier.md .claude/agents/verifier.md | wc -l` → `2`.
- [ ] Both verifier twins carry a SAFETY-FLOOR token (not just the anchor — so
  a stripped edit that drops the floor fails the gate):
  `grep -lEi 'cross-cutting|independently audit|empty.*full|FULL re-run' agents/verifier.md .claude/agents/verifier.md | wc -l` → `2` (verify by content that the always-run-concern-suites + empty-set-floor clauses are present).
- [ ] All 4 dispatch templates carry the de-dup pointer:
  `grep -lF 'suite-result-valid.sh' skills/run-plan/modes/execute-phase.md skills/verify-changes/SKILL.md skills/do/SKILL.md skills/fix-issues/SKILL.md | wc -l` → `4`.
- [ ] All 4 SKILL.md versions changed from the recorded baselines (run-plan
  `2026.06.12+cddf24`, fix-issues `2026.06.12+c4f5cc`, do `2026.06.11+0ebe97`,
  verify-changes `2026.06.10+0b68d4`): `grep -h 'version:' skills/{run-plan,fix-issues,do,verify-changes}/SKILL.md`
  shows 4 NEW values (verify by content — the date is today, the hash differs).
- [ ] Mirror parity: `bash tests/test-skills-mirror-parity.sh` passes.
- [ ] `bash tests/run-all.sh` green; per-suite counts reported.

### Dependencies

Phase 1 (the validator lib must exist — the prose references it by path).

---

## Phase 3 — ORCHESTRATOR baseline reuse + DOCS-ONLY classifier refinement

### Goal

Make the orchestrator baseline reusable uniformly (surface 4) and refine
`/do`'s existing content-only classifier to exclude `skills/**/*.md`
(surface 5, the one non-additive skill edit).

### Work Items

- [ ] **`skills/run-plan/modes/execute-phase.md` — baseline reuse.** At the
  baseline-capture block (≈L444–453, where `$FULL_TEST_CMD > "$TEST_OUT/.test-baseline.txt"`
  is written) and the verifier baseline-compare guidance (≈L674–694), add:
  after the stamp lands the baseline file ALSO carries the provenance header,
  so the verifier may treat ANY validating result at the current tree
  (baseline OR a fresh capture) as reusable — run
  `tests/lib/suite-result-valid.sh` on the candidate; on exit 0 reuse it
  (tally + targeted rerun); on exit 1 (e.g. the tree advanced between
  baseline capture and verification, or > 30min elapsed) re-run. This kills
  the baseline-refresh re-run and the baseline-clobber class. Keep the edit
  inside the baseline + verifier-compare blocks. Bump
  `skills/run-plan/SKILL.md` version + mirror (Inv-1).
- [ ] **`skills/do/SKILL.md` — refine the content-only classifier at BOTH
  surfaces.** The refinement targets TWO connected places (verify by content —
  the DECISION, not just the consumer):
  1. **The classification RULE (≈L881–887, Phase 1 step 3 "Classify the change
     type").** Today: "**Content only** — markdown, images, presentations,
     documentation. No tests needed." This is the load-bearing decision.
     Refine it: content-only = `docs/`, `README*`, `CHANGELOG*`,
     `PRESENTATION*` and non-skill images/presentations — **EXCLUDING
     `skills/**/*.md`** (skill bodies are behavior → "Code"/full-test path).
  2. **The verification-intensity CONSUMER (≈L1016–1029, "Content-only changes
     (md, jpg, png, presentations)" / "Do NOT run tests").** Mirror the same
     exclusion here so it cannot be read as "all markdown → no tests."
  Refining ONLY the L1018 consumer would leave L881–887 still classifying all
  markdown as "no tests needed" — incoherent. A diff confined to the
  docs-only set runs ONLY the prose-pinning subset locally (conformance,
  catalog, managed-md-up-to-date) — CI still full. A diff touching ANY
  `skills/**/*.md` (or any code) runs the full local suite + full CI (routed
  out of content-only at the classifier). State the old behavior ("skipped for
  any .md") and the new behavior in the commit message (this is the one
  non-additive edit — Invariant 5-equivalent: an intended behavior change,
  named). Bump `skills/do/SKILL.md` version + mirror (Inv-1).

### Design & Constraints

- The docs-only "prose-pinning subset" names three suites
  (`test-skill-conformance.sh`, `test-doc-viewer-catalog.sh` — the catalog/
  `docs/DocsRegistry.js` drift gate, which IS regenerated from doc/skill
  catalog content so it belongs here — and `test-managed-md-up-to-date.sh`).
  Express them as a SUBSET to run, not as a hardcoded `bash tests/run-all.sh`
  consumer literal in a bash fence (Invariant 6). Prose-mention of suite
  names is acceptable; a fenced `bash tests/run-all.sh` invocation is not.
  NOTE (harmless over-run): `test-doc-viewer-catalog.sh` excludes `docs/plans`,
  `docs/reports`, `docs/evals`, `docs/issues`, `docs/tracking`
  (`tests/test-doc-viewer-catalog.sh` ≈L10), so a pure `docs/plans/` markdown
  edit runs it for nothing. This is the SAFE direction (over-run, never
  under-run) and the suite is cheap — keep it in the prose-pinning subset
  rather than trying to special-case which docs path was touched.
- The classifier refinement must make `skills/**/*.md` route to the FULL
  path — verify by reading the existing branch and ensuring the `.md`
  catch-all no longer captures skill bodies.
- **Do NOT touch:** `agents/verifier.md`, `.claude/agents/verifier.md`,
  `tests/run-all.sh`, the validator lib, `CLAUDE_TEMPLATE.md`, `managed.md`,
  `tests/test-skill-conformance.sh` (Phase 4), the verify-changes / fix-issues
  full-suite blocks (Phase 2).

### Acceptance Criteria

- [ ] execute-phase carries the baseline-reuse pointer:
  `grep -c 'suite-result-valid.sh' skills/run-plan/modes/execute-phase.md`
  ≥ `2` (the Phase-2 verifier pointer + the new baseline pointer; verify by
  content that the baseline block mentions reuse).
- [ ] /do classifier excludes skill bodies at BOTH surfaces — verify by
  content that the classification RULE (≈L881–887) AND the verification-
  intensity consumer (≈L1016–1029) both name
  `docs/`/`README*`/`CHANGELOG*`/`PRESENTATION*` and explicitly exclude
  `skills/**/*.md`: `grep -c 'skills/\*\*/\*.md' skills/do/SKILL.md` ≥ `2`
  (one per surface) AND the surrounding prose at each states skill `.md` runs
  full local + CI.
- [ ] run-plan + do versions bumped + mirrored:
  `bash tests/test-skills-mirror-parity.sh` passes; both versions are NEW
  values (verify by content).
- [ ] `bash tests/run-all.sh` green; per-suite counts reported.

### Dependencies

Phase 1 (validator lib) and Phase 2 (the verifier protocol the baseline
reuse plugs into — the baseline pointer references the same de-dup mechanism;
run-plan SKILL.md is re-versioned here on top of its Phase-2 bump).

---

## Phase 4 — POLICY PROSE: CLAUDE_TEMPLATE Tests subsection + managed.md re-render + conformance pins

### Goal

Land the additive `## Tests` "result provenance / de-duplication" subsection
in `CLAUDE_TEMPLATE.md` (with the safety floor + threat model VERBATIM —
"Safety-floor policy prose" above), re-render `managed.md` in the SAME
commit, and add the conformance pins locking every new prose surface + the
new helper's existence. Last so the prose describes a system that already
exists and is green.

### Work Items

- [ ] **`CLAUDE_TEMPLATE.md` `## Tests` additive subsection.** Insert the
  `### Tests — result provenance / de-duplication` subsection (text pinned in
  "Safety-floor policy prose" above) between the "Capture test output to a
  file" block (≈L147) and "Pre-existing test failures" (≈L149), OR
  immediately before `### Test files` (≈L168) — the implementer picks the
  cleaner seam but keeps it a SELF-CONTAINED ADDITIVE subsection (Execution
  context coordination note: V2 + Windows work must rebase cleanly). Preserve
  the surrounding existing prose byte-for-byte; do NOT rewrite the capture
  idiom fence (≈L140–144 — the most likely cross-edit hot-spot).
- [ ] **Re-render `managed.md` in the SAME commit (Invariant 4).** Run
  `scripts/render-managed-rules.py` (the remediation command in the test
  header: `/update-zskills --rerender`, or invoke the renderer directly with
  `--config`/`--template`/`--out`), then stage
  `.claude/rules/zskills/managed.md`. NEVER hand-edit managed.md.
- [ ] **Conformance pins — `tests/test-skill-conformance.sh`.** Add a NEW
  section `echo "=== Suite-result provenance (#1166) ==="` with `grep -qF` +
  `pass()`/`fail()` assertions (model: the tally-line pin ≈L815–819 and the
  helper-exists pin ≈L837–848). **Add a NEW section; do NOT edit the existing
  `_pin` loop** (≈L853–859 — it pins the tally prose on `agents/verifier.md`).
  A single `grep -qF` per file in the new section is SUFFICIENT for the de-dup
  token: `tests/test-agents-parity.sh` already guarantees the
  `agents/verifier.md` ↔ `.claude/agents/verifier.md` de-dup prose is
  byte-identical transitively, so the new token does NOT also need appending to
  the `_pin` loop (avoid the double-pin). Pin:
  - a stable anchor token (e.g. `suite-result-valid.sh` or `provenance`) in
    EACH de-dup surface: `agents/verifier.md`, `.claude/agents/verifier.md`,
    `skills/run-plan/modes/execute-phase.md`, `skills/verify-changes/SKILL.md`,
    `skills/do/SKILL.md`, `skills/fix-issues/SKILL.md`, and
    `CLAUDE_TEMPLATE.md` + `.claude/rules/zskills/managed.md` (the rendered
    copy);
  - a SAFETY-FLOOR token (e.g. `cross-cutting` or `full re-run` or
    `independently audit`) in `agents/verifier.md` + `CLAUDE_TEMPLATE.md`, so a
    floor-eroding edit that keeps the anchor but drops the floor is caught
    (this is the conformance backstop for R1-4);
  - helper-exists pin (model ≈L837–848):
    `if [ -f "$REPO_ROOT/tests/lib/suite-result-valid.sh" ]; then pass … else fail …`;
  - the registered self-test exists:
    `if [ -f "$REPO_ROOT/tests/test-suite-result-valid.sh" ]; then pass … else fail …`.
  No mirror-parity pin for the lib (`tests/lib/` is repo-only — Settled
  decision 10).
- [ ] **`tests/test-skill-conformance.sh` is itself a tests/ file** — its
  edit does NOT require a version bump (not a skill dir), but it IS a "shared
  infra" change, so the full local suite is mandatory before this commit
  (Invariant 2).

### Design & Constraints

- The subsection is ADDITIVE prose; the only content removed/changed in any
  skill body across the whole plan is the /do classifier (Phase 3). This
  phase changes no skill body — only the template, the rendered managed.md,
  and the conformance suite. No `metadata.version` bump applies here (no
  skill dir is touched).
- The conformance section greps for STABLE tokens — choose tokens that the
  Phase-2/3 prose actually contains (`suite-result-valid.sh`, `provenance`)
  so the pins are not brittle.
- **Do NOT touch:** any skill `.md` body, `agents/*.md`, the validator lib,
  `tests/run-all.sh`. (The conformance suite reads these but does not modify
  them.)

### Acceptance Criteria

- [ ] Template subsection present:
  `grep -c 'result provenance' CLAUDE_TEMPLATE.md` ≥ `1` AND the safety-floor
  clauses are present: `grep -c 'CI runs the full suite' CLAUDE_TEMPLATE.md`
  ≥ `1` (verify by content the threat model + the six floor clauses are all
  there).
- [ ] managed.md in sync: `bash tests/test-managed-md-up-to-date.sh` passes
  (proves the re-render landed in-commit).
- [ ] managed.md carries the rendered subsection:
  `grep -c 'result provenance' .claude/rules/zskills/managed.md` ≥ `1`.
- [ ] Conformance pins pass:
  `bash tests/test-skill-conformance.sh` passes; the new
  `=== Suite-result provenance (#1166) ===` section reports all-pass (report
  the section's pass count).
- [ ] Helper-exists pin fires green:
  `grep -c 'suite-result-valid.sh' tests/test-skill-conformance.sh` ≥ `1`.
- [ ] `bash tests/run-all.sh` green; per-suite counts reported.

### Dependencies

Phase 1 (the helper the pins assert), Phase 2 (the verifier/dispatch prose
the pins grep), Phase 3 (the /do classifier prose). This phase pins what the
earlier phases built, so it is last.

---

## Plan Quality

**Drafting process.** Authored via `/draft-plan` with 2 rounds of adversarial
review (reviewer + devil's-advocate, then a combined-seat round-2 pass),
converged at round 2.

**Round History.**

| Round | Seat | Findings | Disposition |
|---|---|---|---|
| 1 | reviewer + devil's-advocate | reviewer 6 (1 CRITICAL / 2 MAJOR / 3 minor); devil's-advocate 8 (2 CRITICAL / 2 HIGH / 2 minor / 2 LOW) | 12/12 addressed — the content-blind dirty hash inherited from #1166 was corrected to a CONTENT-sensitive fingerprint (hashes tracked staged+unstaged CONTENT + untracked file CONTENT, not changed paths); the always-on cross-cutting-suite floor was added; per-context reuse timing was pinned. |
| 2 | combined reviewer + devil's-advocate | 0 CRITICAL / 1 MAJOR / 2 minor / 1 LOW | Fixed in this fold: F1 (MAJOR) — the fix-issues reuse-timing claim was factually inverted (round-1's DA4 "honest reframe" wrongly asserted impl-agent-self-commit → foreclosed reuse; VERIFIED `skills/fix-issues/SKILL.md` ≈L369–370 uses verifier-commits-after, identical to run-plan, so reuse is REAL) — the per-context bullet + Phase-2 work item were rewritten to the true model. F2 (minor) — added `.claude/agents/*.md` to the mandatory-full-rerun trigger glob in all surfaces (the verifier.md twin lives there). F3 (minor) — catalog-suite over-run noted as harmless (accept-with-note). F4 (LOW) — per-file `git hash-object` fork accepted (zskills trees are small; `--exclude-standard` keeps the untracked set tiny; NUL-safe per-file binding is the right portability call). The safety-critical machinery (content-sensitive fingerprint, validator predicate, cross-cutting floor, fail-closed semantics) was re-verified clean and was NOT touched in this fold. Converged at round 2. |

This plan corrects #1166's content-blind dirty-hash formula
(`git status --porcelain | git hash-object`, which collides when an
already-modified file's content changes further) with a content-sensitive
fingerprint that flips on every content change and is stable on a clean tree.

**Remaining concerns (honest).**

- The targeted-suite map is JUDGMENT over the suite naming convention, NOT a
  maintained path→suite map — deliberate, per #1166 (a maintained map would rot;
  the always-on cross-cutting floor + empty-set→full fallback make the imprecise
  heuristic safe).
- The catalog suite may over-run on `docs/plans/` edits (it excludes those
  paths) — harmless: over-run is the safe direction and the suite is cheap.
- CI's fresh-clone full run remains the non-negotiable backstop — no local
  de-dup ever compromises it.

- **Anti-drift / 1:1 mirror.** The plan scopes EXACTLY the 5 surfaces of
  #1166 (Settled decision 1) — STAMP, VALIDATE, VERIFIER PROTOCOL,
  ORCHESTRATOR BASELINE REUSE, DOCS-ONLY CLASSIFIER — with no addition and no
  drop. Each phase cites the surface it implements.
- **Verbatim specs.** The plan text is the implementer's only context, so
  the provenance header format (incl. the CONTENT-sensitive `fingerprint`
  formula correcting the issue's content-blind `dirty` hash), the validator
  predicate (non-empty-fields + tree + content-fingerprint + age<30min, fail
  closed), the targeted-suite-derivation procedure (always-on cross-cutting
  gates + empty-set→full floor), and the safety-floor policy prose are all
  pinned VERBATIM in dedicated sections.
- **Safety floor encoded twice** (Critical Invariant 2 AND the Phase-4 policy
  prose) so de-dup can never be read as the forbidden "skip verification";
  the three-layer threat model is the plan's correctness argument.
- **Repo discipline baked into invariants:** Inv-1 version-bump+mirror recipe,
  agents-parity, managed.md render-in-lockstep, triplet registration, green
  at every boundary, hardcode discipline.
- **Every acceptance criterion is a quotable command** (grep/test
  invocation); ≈L references carry "verify by content" notes.
- **Coordination with ENFORCEMENT_V2 + Windows-port** is stated in the
  Execution context: no textual overlap, edits kept additive + self-contained,
  managed.md conflicts resolved by re-render.
- All line numbers are ≈L against the `a6dbcb02` read — verify by content.
