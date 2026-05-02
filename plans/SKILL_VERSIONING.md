---
title: Skill Versioning
created: 2026-04-30
status: active
---

# Plan: Skill Versioning

> **Landing mode: PR** — This plan touches every source skill under `skills/` and every add-on under `block-diagram/` + tests + hooks + a runtime helper script + `/update-zskills`. PR review is appropriate. (Source-of-truth count: `find skills -maxdepth 1 -mindepth 1 -type d -exec test -f '{}/SKILL.md' \; -print | wc -l` plus same against `block-diagram/`. As of Round-1 refinement: 26 + 3 = 29; was 25 + 3 = 28 at plan-write — PR #159 added `skills/land-pr/` on 2026-05-01. Counts are derivation-driven, NOT pinned. See Drift Log.)

## Overview

zskills already ships a **repo-level** `YYYY.MM.N` version (`git tag --list` shows `2026.04.0`; `RELEASING.md:44-46` documents the scheme; `.github/workflows/ship-to-prod.yml:69-77` computes it). It does NOT ship a **per-skill** version: `grep -rli "^version:" skills/ block-diagram/` returns empty, and the four frontmatter keys actually present in any zskills SKILL.md are `name`, `description`, `argument-hint`, `disable-model-invocation`. The gap is asymmetric: the repo knows when it changed; individual skills do not. A consumer running `/update-zskills` against a tag bump cannot tell whether `/run-plan` changed or only `/briefing`. An agent editing a skill cannot tell whether they need to bump anything, because nothing exists to bump.

This plan adds a per-skill version field to SKILL.md frontmatter, defines a mechanically-applicable bump rule that two independent agents would agree on, enforces the bump at edit-time (`warn-config-drift.sh` non-blocking warn) AND at commit-time (`/commit` Phase 5 step 2.5 hard stop) AND at CI-time (`test-skill-conformance.sh` gate), and surfaces both the per-skill and repo-level deltas in `/update-zskills`'s install / update / audit reports. Helper scripts (`scripts/frontmatter-get.sh`, `scripts/frontmatter-set.sh`, `scripts/skill-content-hash.sh`) own the parse/write/hash logic so skill prose stays thin and downstream tools can reuse them. No `jq` introduced; bash regex (`BASH_REMATCH`) + `awk` only, matching the canonical idiom in `zskills-resolve-config.sh:37-44`.

**Format choice — `YYYY.MM.DD+HHHHHH` (date + 6-char content hash).** The date carries human-legible recency; the hash deterministically distinguishes content states. Two same-day edits produce different hashes (no false `unchanged` claim). Two parallel worktrees that diverge on content produce different hashes (clean-apply cherry-picks of B onto A surface a hash conflict, even when B's body diff doesn't textually overlap A's). The hash is computed by `scripts/skill-content-hash.sh` over a canonicalized projection of the skill: a redacted-frontmatter snapshot of `SKILL.md` (with the `metadata.version` line replaced by a `<REDACTED>` literal preserving exact leading whitespace) + the SKILL.md body + every regular file under the skill directory (excluding `SKILL.md` itself), all whitespace-normalized under `LC_ALL=C`. Pure CalVer was rejected at refinement time after Round-1 critical findings F-DA1 (multi-edit-day rule contradicts hook implementation) and F-DA2 (parallel-worktree clean-apply silently loses edits) — see §1.1 trade-offs. The format is `YYYY.MM.DD+HHHHHH` where `HHHHHH` is 6 lowercase hex chars (canonical command form: `LC_ALL=C sha256sum | cut -d' ' -f1 | head -c 6` — used everywhere); regex `^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$`.

**Success criterion:** A fresh agent landing in this repo, told only "modify skill X to do Y," ends up with the per-skill version bumped on its commit (date AND hash both fresh) without a reminder, AND a consumer running `/update-zskills` afterward sees `zskills 2026.04.0 → 2026.04.1` and `Updated: run-plan 2026.04.20+a1b2c3 → 2026.04.30+d4e5f6 (bumped); briefing 2026.04.18+9a8b7c (unchanged); ...` in the structured summary. The repo-level scheme is **not redefined** — this plan reads it from `git tag` (live) and mirrors it into `.claude/zskills-config.json` (snapshot for consumers without git access to the source clone).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Decision & Specification (no code) | ✅ Done | `8133bde` | references/skill-versioning.md (287L, §1.1-1.11 + Appendix A/B); CLAUDE.md ## Skill versioning section; PLAN_INDEX.md unchanged (idempotent verify) |
| 2 — Tooling: `frontmatter-get.sh` / `frontmatter-set.sh` / `skill-content-hash.sh` + tests | ⬚ | | |
| 3 — Migration: seed every core + add-on skill + extend conformance test | ⬚ | | |
| 4 — Enforcement: drift-warn hook + `/commit` Phase 5 step 2.5 + CI gate + CLAUDE.md rule | ⬚ | | |
| 5a — `/update-zskills` data plumbing (helpers + config + briefing) | ⬚ | | |
| 5b — `/update-zskills` UI surface (3 insertion sites + tests) | ⬚ | | |
| 6 — Verification: 4 canaries (missed bump, correct bump, parallel-worktree merge, revert) | ⬚ | | |

---

## Phase 1 — Decision & Specification

### Goal

Document the chosen format, location, bump rule, enforcement combination, repo-level reconciliation, mirror handling, add-on scope, CHANGELOG integration, migration seed, tooling surface, and runtime-read decision — with explicit "Trade-offs considered" listing rejected alternatives. No code lands in this phase. Phase 1 produces ONE artifact: `references/skill-versioning.md` (zskills repo root, not installed downstream — sister to `references/canonical-config-prelude.md` from SKILL_FILE_DRIFT_FIX). Every later phase cites this file by section anchor.

### Work Items

- [ ] 1.1 — Author `references/skill-versioning.md` covering all 11 design-surface decisions below. Each section ends with a 2-3 line "Trade-offs considered" block listing rejected alternatives and the disqualifying property. The reference document is the single source of truth that subsequent phases cite — do NOT scatter design rationale across phase prose. The reference doc body is **the full content of the §1.1–§1.11 sections below** (not a summary) — the implementing agent copies the §1.1–§1.11 bodies into the reference file verbatim, then adds appendices for the regex / canonical-hash-input rule from Phase 2.

- [ ] 1.2 — Append a `## Skill versioning` section to `CLAUDE.md` (project root, NOT `CLAUDE_TEMPLATE.md` — this is a zskills-internal rule, not shipped to consumers; consumers don't author skills, they consume them). Single paragraph that names the rule, cites the format, and points to `references/skill-versioning.md` for detail. Example shape (verbatim):

  > **Skill versioning.** Every source skill under `skills/<name>/SKILL.md` and `block-diagram/<name>/SKILL.md` carries a `metadata.version: "YYYY.MM.DD+HHHHHH"` field — date in `America/New_York` plus a 6-char content hash. Edits to a skill body, frontmatter (other than `metadata.version` itself), or any regular file under the skill directory (mode files, references, scripts, fixtures, stubs, etc.) MUST bump this field; the date refreshes to today, the hash is recomputed via `scripts/skill-content-hash.sh`. Pure typo / formatting / whitespace edits do not require a bump (the hash naturally absorbs them since the canonical projection normalizes whitespace; see `references/skill-versioning.md` §3). Enforcement fires at three points: `warn-config-drift.sh` (Edit-time warn, fires only when the file is staged), `/commit` Phase 5 step 2.5 (commit-time hard stop), `test-skill-conformance.sh` (CI gate). The repo-level zskills version (`YYYY.MM.N`) lives in git tags and is mirrored into `.claude/zskills-config.json` by `/update-zskills`.

- [ ] 1.3 — Verify the plan is registered in `plans/PLAN_INDEX.md` "Ready to Run" (idempotent — already added by `/draft-plan` registration; `grep -n 'SKILL_VERSIONING' plans/PLAN_INDEX.md` returns the existing row at refine time). If absent for any reason, add a row matching the existing format. Do NOT add a second row. (refine-plan F-R8 / F-DA-12: already-done as of 2026-05-02; work item is idempotent verify, not a fresh insert.)

(Round-2 F-DA-R2-11: the prior 1.4 "Mirror nothing" item was a no-op; moved to Non-Goals.)

### Design & Constraints

The 11 decisions below are answered explicitly. Each must be quoted verbatim in `references/skill-versioning.md`.

#### 1.1 Format choice — `YYYY.MM.DD+HHHHHH` (CalVer + content hash hybrid)

**Chosen.** A skill's per-edit version is `YYYY.MM.DD+HHHHHH` where `YYYY.MM.DD` is the project-timezone date and `HHHHHH` is 6 lowercase hex chars from `sha256(canonical-skill-projection)`. Examples: `2026.04.30+a1b2c3`, `2026.05.15+9f8e7d`. Validation regex: `^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$`.

**Justification.** The user's stated lean is date-style; this preserves human legibility (`2026.04.30+...` reads as "skill last touched on April 30") while closing two failure modes that pure CalVer cannot. Both failure modes were elevated to CRITICAL during Round-1 adversarial review:

- **Multi-edit-day (was F-DA1).** Pure CalVer's §1.3 rule "second edit on the same day produces no warn" contradicted the Phase 4 hook implementation, which fires whenever `on_disk_ver = head_ver AND body_diff > 0`. After day 1's first commit lands, HEAD's version IS today; the second edit triggers the warn. With the hash, every distinct content state has a distinct version even within one day — the hook compares hashes, not just dates, and the rule and implementation agree.
- **Parallel-worktree clean-apply (was F-DA2).** Two worktrees both bump to `2026.04.30`. Cherry-picking B onto A succeeds silently if B's body diff doesn't textually overlap A's — third content state, version still `2026.04.30`. With the hash, A's version is `2026.04.30+aaa111` and B's is `2026.04.30+bbb222`. The cherry-pick now produces a version-line conflict even when bodies don't overlap, so the merger sees the divergence and recomputes.

**Mechanically derivable.** Both halves are mechanical: `TZ="$TIMEZONE" date +%Y.%m.%d` for the date, `bash scripts/skill-content-hash.sh skills/<name>` for the hash. Two independent agents reading the rule produce identical outputs.

**Canonical hash input (deterministic projection).** The hash MUST be deterministic across machines and re-runs. All projection commands run under `LC_ALL=C` (forces byte-wise locale-independent ordering). Files in scope are treated as text via `\r\n→\n` normalization; **binary files in a skill directory are out of scope — Phase 2.3 conformance MUST reject any non-text regular file under a skill directory.** The canonical projection (defined in detail in §3 of the reference doc and implemented by Phase 2.3's helper) — three components, concatenated in this fixed order:

1. **Redacted frontmatter snapshot of `SKILL.md`.** The full frontmatter block (everything between the opening and closing `---`), with the line carrying `metadata.version` replaced in-place by a `<REDACTED>` literal. **Byte-level redaction rule (deterministic across implementations):** find the line whose `awk '{$1=$1};1'` (whitespace-stripped) content matches the literal `version: "..."` form **AND** which immediately follows a `metadata:` parent line (possibly with intervening more-indented sibling lines but no other top-level key); replace that line with `<original-leading-whitespace>version: "<REDACTED>"`. Do NOT alter the leading-whitespace count; do NOT re-indent. The redaction is content-only.
2. **SKILL.md body.** Everything below the closing `---` of frontmatter.
3. **Every regular file under `<skill-dir>/`** (recursive, excluding `SKILL.md` itself, since 1+2 already cover it). This is an explicit deny-list of one (`SKILL.md`), NOT an allow-list of named subdirectories. **Why deny-list:** an allow-list of `modes/, references/, scripts/, fixtures/` silently misses real skill content like `skills/update-zskills/stubs/` (verified: `find /workspaces/zskills/skills/update-zskills -maxdepth 2 -type f` lists `stubs/dev-port.sh`, `stubs/post-create-worktree.sh`, `stubs/start-dev.sh` — editing any of these would leave the projection byte-identical under an allow-list, no enforcement). Sort by path **relative to the skill directory** under `LC_ALL=C sort`.

**Per-file processing for component 3:** strip trailing whitespace per line, collapse `\r\n` → `\n`, ensure exactly one trailing newline per file. Prefix each file with a header line `=== <relative-path> ===\n` so re-orderings change the hash.

**Inter-component separator:** a single `\n` byte between components 1, 2, and each file in component 3.

**Final hash:** `LC_ALL=C sha256sum | cut -d' ' -f1 | head -c 6` (canonical form, used everywhere — same form in Phase 2.3 step 4, the Overview, the §1.1 trade-offs, and the reference doc).

**Why redacted frontmatter is in the projection (not excluded entirely).** Including the redacted frontmatter snapshot is the only choice consistent with §1.3's promise that editing `description:` requires a bump. If frontmatter were excluded, the §1.3 description-edit-triggers-bump rule would be unenforceable (the hash wouldn't see it). Redacting only `metadata.version` keeps the hash stable under version-line edits (no fixed-point problem) while making every OTHER frontmatter field a hash-affecting input.

**Hash collision budget (Round-2 F-R2-9 / F-DA-R2-10).** 6 hex chars = 24 bits = 16,777,216 distinct hash values. Birthday boundary is ~4,096 distinct content states per skill before a 50% collision probability. A single skill cycling through ~4k versions over its lifetime is implausible at zskills' scale (current fleet: ~30 skills, total commits to date < 200). 6 chars is sufficient. Trade-off: visual brevity in `/update-zskills` reports and CHANGELOG annotations beats the marginal collision-margin gain at 8 chars. If a real collision is ever observed, the helper widens to 8 in a one-line change (mechanical migration). Documenting here per F-DA-R2-10 surfaces the choice rather than burying it.

**Hash human-readability trade-off (Round-2 F-DA-R2-9 — DateLean discipline).** The user's lean was "evergreen versioning, recency-at-a-glance." The hash component is **machine-distinguishing, not human-distinguishing**: two visually similar hashes (`a1b2c3` vs `a1b2c4`) read as the same to humans. Downstream report formatters MUST de-emphasize the hash:
- When two versions differ only in the date and share the same hash content state, render the date prominently and omit/dim the hash.
- When two versions differ only in the hash (same date, different content state), render the date once and show both hashes for comparison.
- The default `/update-zskills` install-or-update report renders `<date>+<hash>` in full, but the briefing skill's "Z Skills Update Check" line shows date-prominent form when source and installed share a hash (the "current" case).

This is a presentation-layer concern; the underlying truth is the full `YYYY.MM.DD+HHHHHH` string. Phase 5b.1 Site C's table format already de-emphasizes by aligning on the date column.

**Trade-offs considered:**
- **Pure `YYYY.MM.DD` (no hash).** Rejected. Fails F-DA1 and F-DA2 cleanly; the multi-edit-day fallout was pretending the rule said one thing while the implementation did another. Round-1 disposition called this contradiction load-bearing.
- **`YYYY.MM.DD.N` (date + per-skill counter).** Rejected. Counter has to come from somewhere — either git history (race-prone in parallel worktrees, both compute `N=1` simultaneously) or in-file (creates the same fixed-point problem as including the version line in its own hash). Counter still doesn't detect identical content (revert/no-op edits still drift the counter).
- **SemVer (`MAJOR.MINOR.PATCH`).** Rejected. The judgment-class objection is real — a skill's "interface" is a slash command + args + behavior (not a typed API), and Cargo-style compile-surface anchoring (the only deployed-at-scale "anchor SemVer to observable diff features" recipe per the research file) doesn't translate to prompt-shaped artifacts. Anthropic's bundled skills (`anthropics/skills`: `pdf, docx, xlsx, pptx, skill-creator, brand-guidelines`) ship VERSIONLESS; SemVer appears only in their plugin-distributed skill (`plugin-dev/skills/skill-development/SKILL.md`: `version: 0.1.0`). Plugin distribution is out of scope per the prompt's anti-goals. Migrating CalVer+hash → SemVer is a one-time mechanical bump if plugin distribution lands later.
- **`YYYY.MM.N` (matching repo-level scheme).** Rejected. The repo-level `N` means "Nth release of month YYYY.MM" (RELEASING.md:44-46). Per-skill bumps fire at edit time, not release time — `N` would have to mean something different at the per-skill level, reintroducing judgment.
- **Pure SemVer with date side-channel (e.g., `version: "0.1.0", updated: "2026-04-30"`).** Rejected. Two fields means two enforcement surfaces and two ways for them to disagree.

#### 1.2 Location — `metadata.version:` in SKILL.md frontmatter

**Chosen.** The version line lives **nested under a `metadata:` block** in each skill's YAML frontmatter:

```yaml
---
name: run-plan
argument-hint: "[mode]"
description: >-
  ...
disable-model-invocation: false
metadata:
  version: "2026.04.30+a1b2c3"
---
```

**Justification.** The Agent Skills open spec puts version inside `metadata` and reserves `metadata` as "a map from string keys to string values." This is the canonical spec home for tool-specific extension fields. Top-level `version:` is what Anthropic's plugin-distributed skill uses, but the Claude Code documented schema does NOT include `version` — putting our convention under `metadata` insulates against future top-level-key collisions AND matches the cross-tool standard. Travels with the skill into a future plugin (the soft constraint in the design prompt).

**Trade-offs considered:**
- **Top-level `version:`.** Rejected. Risks colliding with a future Claude Code reserved key.
- **Sidecar `VERSION` file per skill.** Rejected. Doesn't travel with the skill into a plugin in the same way. Adds a second file to mirror, version-bump, and reason about.
- **Repo-root `skills/versions.json` manifest.** Rejected. Centralized — does NOT travel with skill into plugin. Every skill edit becomes a two-file edit. Requires `jq` (forbidden by zskills convention).

#### 1.3 Bump rule — anchored to canonical-projection diff

**Chosen.** A bump is REQUIRED when re-computing `bash scripts/skill-content-hash.sh skills/<name>` against the worktree state produces a different 6-char hash than the value in HEAD's `metadata.version`. The bump procedure: refresh the date to today (`TZ=America/New_York date +%Y.%m.%d`) AND replace the hash with the freshly-computed value. Both halves change together — a same-day re-edit advances the hash even though the date is identical.

**Hash input scope (load-bearing).** The hash covers the canonical projection defined in §1.1. In summary, the projection is three components:
1. **Redacted frontmatter snapshot of `SKILL.md`** — frontmatter block with the `metadata.version` line redacted to a `<REDACTED>` literal preserving leading whitespace.
2. **SKILL.md body** — everything below the closing `---`.
3. **Every regular file under `<skill-dir>/`** (recursive, excluding `SKILL.md` itself) — covers `modes/`, `references/`, `scripts/`, `fixtures/`, **and** any other subdirectory like `stubs/` that a skill may add later.

**Frontmatter changes ARE in the projection.** Editing `description:` or `argument-hint:` etc. requires a bump because the redacted frontmatter snapshot is component 1 of the projection — the hash absorbs every frontmatter key except `metadata.version` itself. Editing `metadata.version` itself does NOT change the projection (the redaction line is byte-identical regardless of the version value), so the hash is invariant under version-line edits — no fixed-point problem. Editing any other frontmatter field changes the projection → changes the hash → bump required.

A bump is NOT required when the projection is byte-identical (the canonical projection's whitespace normalization absorbs trailing-whitespace and `\r\n`→`\n` edits). This makes pure-whitespace edits a no-op for the version line by construction, not by judgment.

**Detection mechanism (mechanically applicable).** The enforcement check at Edit-time and commit-time computes `worktree_hash = bash scripts/skill-content-hash.sh skills/<name>` and compares to the hash extracted from HEAD's `metadata.version`. Mismatch with no version bump → warn/stop. Match with a version bump → warn (no-op edit, symmetric).

**Multi-edit-day handling (now consistent with implementation).** Same skill edited twice on the same date. Edit 1: hash changes from `aaa111` to `bbb222`, agent bumps version to `2026.04.30+bbb222`, commits. HEAD now carries `+bbb222`. Edit 2: hash changes from `bbb222` to `ccc333`. Hook compares: HEAD's hash is `bbb222`, worktree's projection hash is `ccc333` — they differ, bump required. Agent bumps to `2026.04.30+ccc333`. Implementation matches the rule: every distinct content state ends up with a distinct version line.

**Revert / no-op edit handling.** Agent edits SKILL.md, bumps version, then reverts the body change. Worktree projection hash now matches HEAD's hash again. Hook detects: `worktree_hash == head_hash` BUT `worktree_version != head_version` (the version was bumped). Symmetric warn fires: `WARN: <file> metadata.version bumped but content unchanged — revert version line or land a real edit`. Surface-bug rule: do not silently swallow.

**Markdown comment carve-out — DROPPED.** The original carve-out for `<!-- ... -->` comments was judgment-class (Round-1 finding F-DA10). The hash naturally captures comments — adding a comment changes the projection, changes the hash, requires a bump. This is correct: LLM consumers DO read HTML comments. If a comment is added, a bump is appropriate. The `<!-- allow-hardcoded: ... -->` exemption marker convention is preserved (it changes the hash too; bump it normally).

**Trade-offs considered:**
- **"Any edit warrants a bump, no exclusions, computed by `git diff`."** Rejected. Whitespace-normalization should be invisible (it's the convention zskills already enforces). The hash absorbs whitespace edits cleanly; the rule benefits.
- **"Auto-derive the version from `git log -1 --format=%cd skills/<name>/`."** Rejected. The version becomes derived, not stored — `/update-zskills` delta report can't read it without per-skill git-log queries against the source clone (which a downstream consumer may not have). Storing in frontmatter is portable.

#### 1.4 Per-skill enforcement — three-point combination

**Chosen.**
1. **Edit-time warn (`hooks/warn-config-drift.sh` extension).** Non-blocking. Fires on Edit/Write of any regular file under `(skills|block-diagram)/<name>/` (the parent SKILL.md, child mode/reference files, scripts, fixtures, stubs — anything in the projection scope per §1.1). Compares the on-disk parent skill's projection hash to HEAD's `metadata.version` hash; if different and the version line has not been bumped, emits `WARN`. **Fires only when the file is staged** (`git diff --cached --name-only | grep -Fqx "$FILE_PATH_REL"` — fixed-string match, NOT regex; see §F-DA-R2-5 below) — this folds Round-1 finding F-DA7 (hook noise during WIP) into Phase 4.1 itself, not a deferred follow-up.
2. **Commit-time hard stop (`/commit` Phase 5 step 2.5).** Inserted between Phase 5's step 2 (run tests) and step 3 (dispatch reviewer) — see Phase 4.3 for the exact insertion point. When `/commit` runs, the helper script `scripts/skill-version-stage-check.sh` (extracted from the inline pseudocode for testability — see Phase 4.3) computes per-skill projection hashes for every staged skill file's parent skill, compares to the staged version line and to HEAD. STOP if mismatch.
3. **CI gate (`tests/test-skill-conformance.sh` extension).** Adds `=== Per-skill version frontmatter ===` section. Iterates skill dirs, asserts each `SKILL.md` contains `metadata.version: "YYYY.MM.DD+HHHHHH"` matching the strict regex `^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$`. ALSO asserts the hash matches the freshly-computed projection (`bash scripts/skill-content-hash.sh skills/<name>` outputs the same 6-char value). Fails CI on missing, malformed, or stale hash.

**Why all three.** Each catches a different failure mode:
- Edit-time alone is too soft.
- Commit-time alone misses direct edits to mirrors or out-of-flow commits.
- CI alone catches everything but only at PR time, by which point the bump-rule context is stale.

**Trade-offs considered:**
- **Edit-time hard block (PreToolUse deny envelope).** Rejected. Too aggressive.
- **Skip the CI gate.** Rejected. Only point that catches direct-to-main edits and mirrors-out-of-sync.
- **Skip the edit-time warn.** Rejected. Loses the "agent learns the rule" feedback loop.

#### 1.5 Repo-level scheme reconciliation — read from git, mirror to config

**Chosen.** The repo-level version `YYYY.MM.N` is **not redefined**. It lives in `git tag --list` of the source clone. `/update-zskills` (Phase 5) reads it via `git -C "$ZSKILLS_PATH" tag --list | sort -V | tail -1` and mirrors the result into `.claude/zskills-config.json` under a top-level `zskills_version:` key.

**Repo-level bump rule.** The repo-level version bumps on **release-cut events** (`.github/workflows/ship-to-prod.yml:69-77` runs on push to `prod` and computes the next `YYYY.MM.N` automatically). NO new enforcement — the existing workflow is the canonical bump trigger; this plan does not alter it. Per-skill bumps and repo-level bumps are independent: per-skill = "skill content last changed"; repo-level = "Nth release of month". Staleness is visible in the `/update-zskills` delta report, not enforced. (Round-1 finding F-R7.)

**Per-skill versions are independent of repo-level versions.** A skill bumped to `metadata.version: "2026.04.30+a1b2c3"` can coexist with repo-level `2026.04.0`. Schemes mean different things; the report shows both side by side, no arithmetic comparison.

**Updates to `zskills-resolve-config.sh`.** Add a 7th var `ZSKILLS_VERSION` resolved from the new top-level `zskills_version` field via the existing BASH_REMATCH idiom.

**Trade-offs considered:**
- **Live-from-git only (no config mirror).** Rejected. Consumer downstream may not have the source clone present at audit time.
- **New top-level `VERSION` file.** Rejected. Two sources of truth.
- **`zskills_version:` inside `metadata:` block of config.** Rejected. Config schema doesn't have a `metadata` block today.

#### 1.6 Mirror interaction — no script change

`scripts/mirror-skill.sh` uses `cp -a "$SRC/." "$DST/"` (line 35) which copies bytes including any new frontmatter keys. A new `metadata: { version: "..." }` block passes through unchanged. `tests/test-mirror-skill.sh` asserts byte-equivalence via `diff -rq` — also unchanged. No allow-list / skip-list extension needed.

`tests/test-skill-file-drift.sh` tests `zskills-resolve-config.sh` resolution; unrelated to skill content.

**Mirror-only skills (out of scope).** `.claude/skills/` and `skills/` differ by exactly two directories: `playwright-cli` and `social-seo` live ONLY in `.claude/skills/` (pre-source/mirror-split vendor bundle); every other entry in `.claude/skills/` has a `skills/<name>/` source counterpart. These are out of scope for Phase 3 migration: do NOT add `metadata.version` to them. Phase 3.6 conformance enumeration filters via `for skill_dir in "$REPO_ROOT/skills"/*/ "$REPO_ROOT/block-diagram"/*/` (source roots only). A separate plan can fold these in if/when they get a source representation. (Round-1 finding F-R6.)

#### 1.7 Block-diagram add-ons — same scheme, applied uniformly to 3 skills

**Chosen.** All 3 block-diagram add-on skills (`add-block`, `add-example`, `model-design`) carry `metadata.version: "YYYY.MM.DD+HHHHHH"` using the same rule. `block-diagram/screenshots/` does NOT contain a `SKILL.md` (it holds image assets only — verified by `ls block-diagram/screenshots/`); it is excluded from migration and conformance enumeration. (Original Round-1 finding F-R1 cited "25 + 3 = 28"; that figure was correct at plan-write 2026-04-30 but stale once PR #159 added `skills/land-pr/` on 2026-05-01 — current is 26 + 3 = 29. The number is derivation-driven from `find ... -exec test -f '{}/SKILL.md' \; -print` enumeration, NOT pinned. See refine-plan Drift Log.)

Migration in Phase 3 seeds the 3 add-ons. Phase 4 enforcement covers them via the same conformance regex AND the widened drift-warn hook regex (Branch 2 widened from `(^|/)skills/[^/]+/.*\.md$` to `(^|/)(skills|block-diagram)/[^/]+/.*\.md$` — see Phase 4.1 and Round-1 finding F-R4).

**Justification.** They are skills shipped through the same mechanism. Excluding them creates a second class of skill consumers can't tell apart at audit time.

**Trade-offs considered:**
- **No version on add-ons.** Rejected. Inconsistent UX in `/update-zskills` reports.
- **Different format.** Rejected. Adds a category for no consumer benefit.

#### 1.8 CHANGELOG integration — additive, minimal-disruption

**Chosen.** Keep `CHANGELOG.md` date-headed (`## 2026-04-30`) with prose / bullet entries. Add OPTIONAL per-entry version annotations in parentheses for changed skills. **Canonical template** (cited verbatim from this section by phases 3.7, 4.11, 5a.13, 5b.8):

```
## YYYY-MM-DD

### <Type> — <scope> (<skill-name>: <YYYY.MM.DD+HHHHHH>)

- <bullet describing the change, "why" not "what">
```

Where `<Type>` is one of `Added`, `Updated`, `Fixed`, `Removed`. The annotation is informational, not a parse target. The `/update-zskills` delta report does NOT read CHANGELOG.md — it reads SKILL.md frontmatter directly. SKILL.md frontmatter is the source of truth.

(Round-1 finding F-DA12: this canonical template is now defined here, and 3.7, 4.11, 5a.13, 5b.8 cite it.)

**Trade-offs considered:**
- **Switch CHANGELOG to version-headed.** Rejected. Repo-level scheme is `YYYY.MM.N`; existing date-headed CHANGELOG has 6 dated blocks that would orphan.
- **Per-skill `CHANGELOG.md` files.** Rejected. ~30 files multiplies maintenance for no consumer benefit.

#### 1.9 Migration / seeding — uniform initial date, per-skill computed hash

**Chosen.** Every core skill under `skills/<name>/SKILL.md` and every block-diagram add-on under `block-diagram/<name>/SKILL.md` receives `metadata.version: "YYYY.MM.DD+HHHHHH"` set to **the date Phase 3 lands** (`TZ="$TIMEZONE" date +%Y.%m.%d` at migration commit time) PLUS a per-skill hash freshly computed from each skill's content projection. The set of skills is derived at migration time via the Phase 3.2 enumeration (`find ... -maxdepth 1 -mindepth 1 -type d -exec test -f '{}/SKILL.md' \; -print`) — NOT pinned to a literal count, since the number drifts as new skills land.

**Justification.** A uniform date is honest: "all skills synced as of D." A per-skill hash captures that the skills are NOT identical content (each skill's `aaa111` differs from another's). Mixing uniform-date and per-skill-hash is the correct invariant.

**Trade-offs considered:**
- **Per-skill last-touched date.** Rejected (archaeological; date doesn't mean "skill changed on D").
- **Per-skill `0.0.0` placeholder.** Rejected (regex break; placeholder dance).

#### 1.10 Tooling — three helpers, no slash command

**Chosen.** Three scripts under `scripts/` (top-level — repo-tooling, not skill-machinery):

- `scripts/frontmatter-get.sh <file-or-dash> <key>` — extracts a YAML frontmatter value by dotted key (`metadata.version`). Single-dash `-` for `<file>` reads frontmatter from stdin. Pure bash + awk. Output to stdout, exit 0 / 1 (missing key) / 2 (malformed frontmatter).
- `scripts/frontmatter-set.sh <file> <key> <value>` — sets a YAML frontmatter value, in-place. Idempotent. Pure bash + awk.
- `scripts/skill-content-hash.sh <skill-dir>` — computes the 6-char canonical-projection hash for a skill directory. The projection per §1.1 is: redacted-frontmatter snapshot of `SKILL.md` + SKILL.md body + every regular file under `<skill-dir>/` (recursive, excluding `SKILL.md` itself — covers `modes/`, `references/`, `scripts/`, `fixtures/`, `stubs/`, and any future subdirectory). Pure bash + sha256sum (coreutils, ubiquitous), all under `LC_ALL=C`.

**No `/bump-skill` slash command in v1.** The bump frequency does not justify a dedicated slash command; the helpers are invokable from any context:

```bash
TODAY=$(TZ=America/New_York date +%Y.%m.%d)
HASH=$(bash scripts/skill-content-hash.sh skills/run-plan)
bash scripts/frontmatter-set.sh skills/run-plan/SKILL.md metadata.version "$TODAY+$HASH"
```

If frequency rises, revisit and add a slash command in a follow-up plan.

**Trade-offs considered:**
- **Single combined `bump-version.sh`.** Rejected. Get/set/hash are independent operations; downstream tools may want one without the others.
- **`/bump-skill <name>` slash command.** Rejected for v1.
- **Inline awk scripts in each consumer.** Rejected. Drift surface.

#### 1.11 Runtime reads — wire briefing skill in this plan; defer dashboard

**Chosen.** `/briefing` is wired in Phase 5a (the natural surface for "what's installed and how stale is it"). It reads `metadata.version` of installed skills via `frontmatter-get.sh` and compares to source. `/zskills-dashboard` is NOT wired in this plan — the dashboard is a Python service; threading version data through requires a Python-side parser, which is out of scope.

**Trade-offs considered:**
- **Wire dashboard in this plan.** Rejected. Python-side parser is a separate adjacent surface.
- **Wire nothing at runtime.** Rejected. Briefing's "Z Skills Update Check" section currently shows opaque "updates available"; per-skill version delta is a markedly better signal.

### Acceptance Criteria

- [ ] `references/skill-versioning.md` exists, contains H2 sections numbered 1.1 through 1.11 corresponding to the 11 decisions above, each section ending with a "Trade-offs considered" sub-block. Verified by `grep -c '^## 1\.' references/skill-versioning.md` returning 11 AND `grep -c 'Trade-offs considered' references/skill-versioning.md` returning ≥ 11.
- [ ] `grep -q '^## Skill versioning' CLAUDE.md` succeeds.
- [ ] `grep -q 'SKILL_VERSIONING' plans/PLAN_INDEX.md` succeeds (plan registered as active).
- [ ] No edits to `skills/`, `block-diagram/`, `tests/`, `hooks/`, or `scripts/` in this phase. `git diff --cached --stat` for the Phase 1 commit lists only the three files above.
- [ ] `bash tests/run-all.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0 (no test changes; baseline still passes).

### Dependencies

None — Phase 1 is the foundational decision phase.

### Non-Goals

- Implementing any tooling, hook, or test (Phases 2-6).
- Editing any skill (Phase 3).
- Mirroring `skills/` to `.claude/skills/` (Phase 1 produces no `skills/` edits; mirror parity verification belongs to Phase 3.5).
- Plugin distribution support (separate `/draft-plan` per design prompt's anti-goals).

---

## Phase 2 — Tooling: `frontmatter-get.sh`, `frontmatter-set.sh`, `skill-content-hash.sh`, tests

### Goal

Ship three pure-bash helper scripts. Tests cover each helper so Phase 3 can rely on them without re-verifying.

### Work Items

- [ ] 2.1 — Author `scripts/frontmatter-get.sh` (executable bash, `set -eu`):
  - Args: `<file-or-dash> <dotted-key>`. The file argument MAY be `-` (single dash) which means "read frontmatter from stdin." Examples: `metadata.version`, `name`, `description`. (Round-1 findings F-R3 / F-DA6: stdin support is part of Phase 2's contract from day one, not a retrofit.)
  - Reads the file (or stdin). Identifies frontmatter as the block between the first `---` line and the next `---` line. Errors with exit 2 if frontmatter is missing or malformed.
  - For dotted keys (e.g., `metadata.version`), parses nested YAML by tracking indentation. The expected shape is the §1.2 canonical (a top-level `metadata:` line followed by a 2-space-indented `version: "VAL"` line). Awk + bash regex; no jq.
  - **Block-scalar handling.** When traversing frontmatter to locate keys, the parser MUST correctly skip block-scalar continuation lines (`description: >-` is real in every zskills SKILL.md — verified by `head -10 skills/run-plan/SKILL.md` shows `description: >-` followed by indented continuation lines). The parser identifies a block scalar by trailing `>-`, `>`, `|`, or `|-` on a key line, then skips all subsequent more-indented lines until the indent returns to the parent level. Reading block scalars is supported (returns the multi-line value joined as documented in the spec); writing them is NOT supported (see Phase 2.2 below).
  - On success: prints the value (without surrounding quotes for single-line values) to stdout, exits 0.
  - On missing key: exits 1, no stdout output, error to stderr.
  - On malformed frontmatter: exits 2, error to stderr.

- [ ] 2.2 — Author `scripts/frontmatter-set.sh` (executable bash, `set -eu`):
  - Args: `<file> <dotted-key> <new-value>`.
  - Reads file. Identifies frontmatter block.
  - For dotted keys: locates the existing `<key>:` line under the appropriate parent. If missing, INSERTS a new line at the right indentation. If the parent block is missing, inserts the parent block immediately before the closing `---` and adds the child line.
  - Wraps `<new-value>` in double quotes when writing.
  - **Block-scalar handling on write.** The set helper writes single-line scalars only. If a target key already exists as a block scalar (`description: >-` followed by continuation lines), the helper EXITS 3 with an error: `ERROR: cannot rewrite block scalar key '<key>'; use single-line scalar form`. Block scalars are read-passthrough (Phase 2.1) but never overwritten by set. This is intentional — the only key Phase 4/5 actually writes is `metadata.version`, which is always a single-line quoted string. (Round-1 finding F-DA4: prior plan claimed "single-line key-value only" was the convention; reality is block scalars are pervasive. Parser MUST correctly skip continuation lines when locating insertion points.)
  - Idempotent: if the existing value matches `<new-value>`, no write; exits 0 silently.
  - In-place edit via `mv $tmp $file` (atomic). Preserves file mode.
  - On success: exits 0, no stdout.
  - On malformed frontmatter: exits 2, error to stderr.
  - On block-scalar overwrite attempt: exits 3, error to stderr.

- [ ] 2.3 — Author `scripts/skill-content-hash.sh` (executable bash, `set -eu`). **Step 0 — script-wide locale.** The helper script's first executable line MUST be `export LC_ALL=C` — this scope-wide export covers all `find`, `sort`, `awk`, `sed`, `sha256sum`, `grep`, and any redaction-subroutine calls in the same shell process. Per-command `LC_ALL=C` prefixes are NOT required when the script-wide export is in place; the export is sufficient and avoids the Round-3 F-DA-R3-5 ambiguity around helper subroutines (e.g., the redaction's `awk '{$1=$1};1'`) accidentally running under a non-C locale. (Round-3 finding F-DA-R3-5.)
  - Args: `<skill-dir>` (path to a skill directory containing `SKILL.md`).
  - Builds the canonical projection per §1.1 / §1.3:
    1. **Redacted frontmatter snapshot of `SKILL.md`.** **Use the same block-scalar-aware traversal as Phase 2.1's parser** (Round-3 F-DA-R3-4): identify block scalars by trailing `>-`, `>`, `|`, or `|-` on a key line, then skip all subsequent more-indented lines (continuation content) until indent returns to the parent level. The redactor MUST NOT inspect or rewrite block-scalar continuation lines — a `description-extra: >-` continuation line containing literal text like `version: "X"` must be preserved verbatim. Then locate the line whose whitespace-stripped content (`awk '{$1=$1};1'`) matches the literal `version: "..."` form **AND** which sits immediately under the `metadata:` parent line (tracking indentation per the block-scalar-aware traversal). Replace that line with `<original-leading-whitespace>version: "<REDACTED>"` — preserving the leading-whitespace count exactly. Other frontmatter keys (including block scalars) preserved verbatim. The whole frontmatter block (between the first `---` and the next `---`) becomes component 1.
    2. **SKILL.md body** — everything below the closing `---`.
    3. **Every regular file under `<skill-dir>/`** (recursive, excluding `SKILL.md` itself, dotfiles, and conventional dev artifacts). Enumerate via `find "$skill_dir" -type f ! -name SKILL.md ! -name '.*' ! -path '*/__pycache__/*' ! -path '*/node_modules/*' -print0 | sort -z`. The exclusion of `! -name '.*'` filters editor swapfiles, `.DS_Store`, `.landed`, `.zskills-tracked`, `.test-results.txt`, etc., from the projection (Round-3 F-DA-R3-2: skill dirs SHOULD be clean of dotfiles in the first place; the conformance test in 3.6 also asserts this — defense in depth). **Reject any non-text file:** test size first, then mime — `if [ -s "$f" ] && file --mime "$f" | grep -qi 'charset=binary'; then exit 1; fi`. Empty files (`.gitkeep`-style anchors) are treated as zero-byte text and pass through with no projection effect; binary files (PNGs, compiled artifacts) exit 1. (refine-plan F-DA-5: `file --mime` reports `inode/x-empty; charset=binary` for any empty file, so the prior unguarded form would false-positive on `.gitkeep` and on any incidentally-empty fixture under a skill dir. Verified: `file --mime skills/zskills-dashboard/scripts/zskills_monitor/static/.gitkeep` → `inode/x-empty; charset=binary`.)
  - Concatenate with `=== <relative-path> ===\n` headers (paths relative to `<skill-dir>`) and whitespace normalization per file: strip trailing whitespace per line; collapse `\r\n`→`\n`; ensure single trailing `\n` per file. Single `\n` separator between components and between files within component 3.
  - Pipe the projection through `sha256sum | cut -d' ' -f1 | head -c 6` (canonical sha256 cut form; the script-wide `export LC_ALL=C` from step 0 ensures locale-independent byte ordering throughout — no per-command prefix needed).
  - On success: prints the 6-char hash to stdout, exits 0.
  - On missing `<skill-dir>/SKILL.md`: exits 1, error to stderr.
  - On binary file in projection scope: exits 1, error to stderr (`ERROR: binary file in skill projection: <path>`).
  - **Determinism property:** running the helper twice on the same content MUST produce the same 6-char output. Two helpers on different machines (same content, any locale) MUST agree because all commands run under `LC_ALL=C`. Test 2.5 asserts this; Phase 6 adds a cross-locale determinism canary as a sub-case of canary 6.2.

- [ ] 2.4 — Author `tests/test-frontmatter-helpers.sh`:
  - 26 test cases covering: get top-level / dotted / missing key / malformed frontmatter / no frontmatter / value-with-spaces / value-with-quotes / empty value / **stdin via `-` arg (4 cases: top-level key, dotted, missing, malformed)** / block-scalar read (`description: >-` returns joined value); set insert into existing parent / insert with new parent / update existing / idempotent no-op / value-with-special-chars / malformed / **block-scalar write attempt exits 3**; round-trip get→set→get; in-place atomicity.
  - Uses `/tmp/zskills-tests/$(basename "$(pwd)")/`. No network.
  - Fixtures: 7 small YAML-frontmatter test files under `tests/fixtures/frontmatter/` including one with a block scalar.

- [ ] 2.5 — Author `tests/test-skill-content-hash.sh`:
  - 8 test cases covering: hash-on-fixture-skill is 6 hex chars matching `[0-9a-f]{6}`; same fixture twice produces same hash (determinism); whitespace-only edit produces same hash (normalization); body edit produces different hash; mode-file addition produces different hash; missing SKILL.md exits 1; **dotfile invariance — adding a `.DS_Store` to the fixture produces the same hash (the `! -name '.*'` filter from 2.3 step 3 excludes it; Round-3 F-DA-R3-2)**; **block-scalar continuation safety — a fixture frontmatter with `description-extra: >-` whose continuation contains a literal `version: "X"` text line must NOT have that line redacted (the redactor's block-scalar-aware traversal from 2.3 step 1 skips it; Round-3 F-DA-R3-4)**.
  - Fixtures: 5 minimal skill dirs under `tests/fixtures/skill-versioning/` — including (a) one with a `.DS_Store` sibling, (b) one with a block-scalar `description-extra` continuation containing `version: "..."` text.

- [ ] 2.6 — Register both new test files in `tests/run-all.sh` (alphabetical placement, matching existing `run_suite` calls).

- [ ] 2.7 — Smoke-test the helpers from a one-line bash invocation matching the canonical use sites that Phase 4 will introduce:

  ```bash
  bash scripts/frontmatter-get.sh skills/run-plan/SKILL.md name           # → run-plan
  cat skills/run-plan/SKILL.md | bash scripts/frontmatter-get.sh - name   # → run-plan (stdin form)
  bash scripts/skill-content-hash.sh skills/run-plan                      # → 6 hex chars
  TODAY=$(TZ=America/New_York date +%Y.%m.%d)
  HASH=$(bash scripts/skill-content-hash.sh skills/run-plan)
  bash scripts/frontmatter-set.sh /tmp/copy/SKILL.md metadata.version "$TODAY+$HASH"
  ```

  Document the smoke as a manual recipe in `references/skill-versioning.md` §1.10. Do NOT mutate `skills/run-plan/SKILL.md` here; use a fresh `/tmp` copy.

- [ ] 2.8 — Commit message: `feat(scripts): add frontmatter-get/set/skill-content-hash helpers + tests for skill versioning`.

### Design & Constraints

**No `jq`.** Frontmatter parsing is bash regex + awk. Canonical idiom from `zskills-resolve-config.sh:37-44` is reusable; `flip-frontmatter-status.sh:62-85` is the existing in-zskills "iterate between `---` boundaries" pattern. Use that pattern.

**Indentation handling.** YAML is whitespace-sensitive. The helpers MUST handle 2-space child indentation. Tabs are out of scope.

**Atomicity.** `frontmatter-set.sh` MUST write to a temp file then `mv`; no partial-write windows.

**Empty value handling.** `frontmatter-set.sh skills/X/SKILL.md metadata.version ""` writes `metadata.version: ""` and exits 0. Removing a key entirely is OUT of scope for v1.

**Error message style.** stderr messages match existing `scripts/` style: `ERROR: <description>` prefix, no stack traces.

**No `2>/dev/null` on the helpers.** Per CLAUDE.md ("never suppress errors on operations you need to verify") and Round-1 finding F-DA9, the helpers themselves do NOT silently swallow errors. Their callers may use `|| true` IF the empty-output is the intended signal (e.g., a missing key returns nothing) — those sites are reviewed per-call in Phase 4.

### Acceptance Criteria

- [ ] `test -x scripts/frontmatter-get.sh && test -x scripts/frontmatter-set.sh && test -x scripts/skill-content-hash.sh` (all executable).
- [ ] `bash -n` on all three exits 0 (syntax clean).
- [ ] `bash tests/test-frontmatter-helpers.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0 with ≥ 26 cases passing.
- [ ] `bash tests/test-skill-content-hash.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0 with ≥ 6 cases passing.
- [ ] `grep -c 'test-frontmatter-helpers.sh\|test-skill-content-hash.sh' tests/run-all.sh` returns exactly 2.
- [ ] `bash scripts/frontmatter-get.sh skills/run-plan/SKILL.md name` outputs exactly `run-plan`.
- [ ] `cat skills/run-plan/SKILL.md | bash scripts/frontmatter-get.sh - name` outputs exactly `run-plan` (stdin form).
- [ ] `bash scripts/skill-content-hash.sh skills/run-plan` outputs a 6-char string matching `^[0-9a-f]{6}$` (deterministic).
- [ ] Running the hash twice produces identical output: `[ "$(bash scripts/skill-content-hash.sh skills/run-plan)" = "$(bash scripts/skill-content-hash.sh skills/run-plan)" ]`.
- [ ] `grep -c 'jq' scripts/frontmatter-get.sh scripts/frontmatter-set.sh scripts/skill-content-hash.sh tests/test-frontmatter-helpers.sh tests/test-skill-content-hash.sh` returns 0.
- [ ] `bash tests/run-all.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0.
- [ ] **Round-trip property check:** for any value V containing only `[A-Za-z0-9. +-]`, `frontmatter-set $f $k V && frontmatter-get $f $k` outputs V exactly. Asserted by 5 of the 26 test cases.

### Dependencies

Phase 1 (`references/skill-versioning.md` §1.10 names the helpers; this phase implements the contract).

### Non-Goals

- A `/bump-skill` slash command. Out of scope per §1.10.
- Removing keys (only insert and update). Out of scope for v1.
- Block-scalar **writes**. Block-scalar reads ARE supported (Phase 2.1); writes return exit 3.
- Multi-line YAML values, anchors. Out of scope.

---

## Phase 3 — Migration: seed every core + add-on skill + extend conformance test

### Goal

Add `metadata.version: "YYYY.MM.DD+HHHHHH"` to every source skill's `SKILL.md` (every directory under `skills/` and `block-diagram/` that contains a `SKILL.md` — currently 26 + 3 = 29 at refine time; the count is derivation-driven, not pinned), set the date to the date Phase 3 lands and the hash to each skill's freshly-computed content hash, mirror to `.claude/skills/`, and extend `tests/test-skill-conformance.sh` to assert presence and shape AND that the stored hash matches the recomputed projection.

### Work Items

- [ ] 3.1 — Compute migration date once, capture into a shell var:

  ```bash
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  MIGRATION_DATE=$(TZ="$TIMEZONE" date +%Y.%m.%d)
  echo "Migration date: $MIGRATION_DATE"
  ```

- [ ] 3.2 — Enumerate all in-scope skills, filtering for actual `SKILL.md` presence:

  ```bash
  CORE_SKILLS=$(find "$CLAUDE_PROJECT_DIR/skills" -maxdepth 1 -mindepth 1 -type d \
    -exec test -f '{}/SKILL.md' \; -print | sort)
  ADDON_SKILLS=$(find "$CLAUDE_PROJECT_DIR/block-diagram" -maxdepth 1 -mindepth 1 -type d \
    -exec test -f '{}/SKILL.md' \; -print | sort)
  ```

  (Round-1 finding F-R13: `-exec test -f '{}/SKILL.md' \;` filters out `block-diagram/screenshots/` which holds image assets, no SKILL.md.)

  Expected counts at refine time: 26 core, 3 add-on (was "25 / 3" at plan-write 2026-04-30; PR #159 added `skills/land-pr/` on 2026-05-01 so the core figure drifted). The count IS NOT pinned — the gates below are lower-bound + structural assertions, not equality checks. (refine-plan Round-1 F-R1 / F-R2 / F-DA-1 / F-DA-2 — the prior literal `test "$CORE_COUNT" = "25"` gate would hard-fail on first run today.)

  ```bash
  CORE_COUNT=$(echo "$CORE_SKILLS" | wc -l)
  ADDON_COUNT=$(echo "$ADDON_SKILLS" | wc -l)
  [ "$CORE_COUNT" -ge 1 ] || { echo "FAIL: no core skills found under skills/" >&2; exit 1; }
  [ "$ADDON_COUNT" -ge 1 ] || { echo "FAIL: no add-on skills found under block-diagram/" >&2; exit 1; }
  echo "Migrating $CORE_COUNT core + $ADDON_COUNT add-on skills"
  ```

- [ ] 3.3 — **Two-pass migration** (Round-3 finding F-R3-2 / F-DA-R3-1: pre-migration NO SKILL.md has a `metadata:` block, so the byte-level redaction rule in §1.1 cannot fire — pre-migration projection differs from post-migration projection by the new `metadata:\n  version: "<REDACTED>"` lines, breaking the "stable across before/after states" claim. Two-pass closes this cleanly via a placeholder fixed point):

  **Pass 1 — insert a uniform placeholder version block into every SKILL.md.** No hash computation in pass 1. The placeholder is byte-identical across all skills:

  ```bash
  PLACEHOLDER="PLACEHOLDER+PLACEHOLDER"
  for skill_dir in $CORE_SKILLS $ADDON_SKILLS; do
    skill_md="$skill_dir/SKILL.md"
    [ -f "$skill_md" ] || { echo "FAIL: missing $skill_md" >&2; exit 1; }
    bash "$CLAUDE_PROJECT_DIR/scripts/frontmatter-set.sh" "$skill_md" \
      metadata.version "$PLACEHOLDER"
  done
  ```

  After pass 1: every SKILL.md has a `metadata:` parent line and a `  version: "PLACEHOLDER+PLACEHOLDER"` child line. Mirror parity is NOT yet computed.

  **Pass 2 — compute hash on the placeholder-bearing projection, then overwrite the version line with the real value.** Because the §1.1 redaction rule strips the version-line content to `<REDACTED>` regardless of whether the value is the placeholder OR the real `<DATE>+<HASH>`, the projection at pass 1's end is byte-identical to the projection after pass 2's write. The hash computed in pass 2 is therefore consistent with the final stored hash — the redaction creates a fixed point:

  ```bash
  for skill_dir in $CORE_SKILLS $ADDON_SKILLS; do
    skill_md="$skill_dir/SKILL.md"
    hash=$(bash "$CLAUDE_PROJECT_DIR/scripts/skill-content-hash.sh" "$skill_dir") \
      || { echo "FAIL: hash computation for $skill_dir" >&2; exit 1; }
    bash "$CLAUDE_PROJECT_DIR/scripts/frontmatter-set.sh" "$skill_md" \
      metadata.version "$MIGRATION_DATE+$hash"
  done
  ```

  **Fixed-point property (load-bearing).** After pass 2 writes `<DATE>+<HASH>`, recomputing the hash on the post-write file again yields the same `<HASH>`, because the redaction rule replaces the version-line content with `<REDACTED>` regardless of value. The pre-write projection (`metadata: { version: "PLACEHOLDER+PLACEHOLDER" }` → redacted to `metadata: { version: "<REDACTED>" }`) and post-write projection (`metadata: { version: "<DATE>+<HASH>" }` → redacted to `metadata: { version: "<REDACTED>" }`) are byte-identical. Phase 3.6 conformance recomputing on the same content state produces the same hash → no spurious failures.

  **Invariant (no child-file edits between passes).** Between pass 1 and pass 2, NO other file under any `<skill-dir>/` may be modified. The fixed-point argument depends on the projections being byte-identical EXCEPT for the version-line content (which the redaction normalizes). If a future multi-step migration also needs to edit child files (modes/, references/, scripts/, etc.) AS PART of the same migration, run pass 1 → child edits → pass 2 in that order; otherwise pass 2's hash will not match the post-write-pass-2 file's recomputed hash and conformance will fire. (refine-plan F-DA-11.)

  **Enforcement gate (refine-plan F-R2-7).** The invariant above is enforced by snapshotting the working-tree state across the two passes and aborting on any drift. Editor swap-files, transient artifacts from background processes, or concurrent agent edits all manifest as `git ls-files -m -o --exclude-standard` deltas:

  ```bash
  PASS1_TREE=$(git -C "$REPO_ROOT" ls-files -m -o --exclude-standard skills block-diagram | sort)
  # ... run pass 1 (placeholder write) ...
  # ... run pass 2 (real-value write) ...
  PASS2_TREE=$(git -C "$REPO_ROOT" ls-files -m -o --exclude-standard skills block-diagram | sort)
  # Filter to the SKILL.md set (which IS expected to change between passes).
  PASS1_NON_SKILLMD=$(printf '%s\n' "$PASS1_TREE" | grep -v '/SKILL\.md$' || true)
  PASS2_NON_SKILLMD=$(printf '%s\n' "$PASS2_TREE" | grep -v '/SKILL\.md$' || true)
  if [ "$PASS1_NON_SKILLMD" != "$PASS2_NON_SKILLMD" ]; then
    echo "FAIL: filesystem state changed between passes (non-SKILL.md drift)" >&2
    diff <(printf '%s\n' "$PASS1_NON_SKILLMD") <(printf '%s\n' "$PASS2_NON_SKILLMD") >&2
    exit 1
  fi
  ```

  **Why two-pass beats the alternative ("synthesize a virtual redacted line when no `metadata.version` exists").** The synthesis approach requires the redactor to know where in the frontmatter to imagine a virtual line, makes the rule conditional on absence, and complicates the `frontmatter-set.sh` helper's reasoning. Two-pass keeps the redaction rule unconditional and pushes the migration cost into a one-time-only mechanical step. The placeholder is gone after pass 2 lands; no runtime code ever sees it.

  **Idempotence.** Re-running pass 1 on a SKILL.md that already has `metadata.version` is a no-op (`frontmatter-set.sh` is idempotent — same value writes nothing). Re-running pass 2 with the same `$MIGRATION_DATE` and recomputed hash is a no-op. Either pass alone reaches the same eventual state.

- [ ] 3.4 — Mirror each modified core skill to `.claude/skills/`:

  ```bash
  for skill_dir in $CORE_SKILLS; do
    name=$(basename "$skill_dir")
    bash "$CLAUDE_PROJECT_DIR/scripts/mirror-skill.sh" "$name"
  done
  ```

  **Block-diagram add-ons are NOT in `.claude/skills/` of the zskills repo.** They install only on consumer side via `/update-zskills --with-block-diagram-addons`. Skip mirror for them.

- [ ] 3.5 — Verify mirror parity:

  ```bash
  for skill_dir in $CORE_SKILLS; do
    name=$(basename "$skill_dir")
    diff -r "$CLAUDE_PROJECT_DIR/skills/$name" "$CLAUDE_PROJECT_DIR/.claude/skills/$name" > /dev/null \
      || { echo "FAIL: mirror diff for $name" >&2; exit 1; }
  done
  ```

- [ ] 3.6 — Extend `tests/test-skill-conformance.sh` with three new sections (`=== Skill-dir cleanliness ===`, `=== Per-skill version frontmatter ===`, `=== Per-skill version mirror parity ===`) at the insertion point: after the existing per-skill behavior-pattern blocks, before the PROSE-IMPERATIVE coverage block at the file's tail. Mirror loop uses an explicit allow-list of source-less skills (Round-3 F-DA-R3-3) so an orphaned mirror after a future cleanup is NOT silently treated as expected.

  ```bash
  # Skill-dir cleanliness: no dotfiles or build artifacts in GIT-TRACKED content.
  # Scoped to `git ls-files <skill-dir>` rather than `find` so that working-tree
  # runtime artifacts (briefing.py's __pycache__, zskills_monitor's __pycache__,
  # editor swap files, etc.) do NOT trip the gate. The cleanliness rule enforces
  # what consumers see — i.e., what's tracked in git — not what lives transiently
  # in a developer's working tree. (refine-plan F-DA-4 / F-DA-14: the prior
  # `find`-based form would hard-fail on day-zero migration because briefing and
  # zskills-dashboard both materialize __pycache__ when their Python runs, and
  # `.gitkeep` is intentionally tracked in zskills-dashboard's static dir.)
  #
  # `.gitkeep` is the universal Unix idiom for tracking an otherwise-empty
  # directory; allow-list it explicitly. Other dotfiles in tracked content
  # (e.g., `.env`, `.DS_Store`, `.swp`) remain rejected.
  echo "=== Skill-dir cleanliness ==="
  for skill_dir in "$REPO_ROOT/skills"/*/ "$REPO_ROOT/block-diagram"/*/; do
    [ -d "$skill_dir" ] || continue
    name=$(basename "$skill_dir")
    skill_rel="${skill_dir#$REPO_ROOT/}"
    skill_rel="${skill_rel%/}"
    tracked=$(git -C "$REPO_ROOT" ls-files -- "$skill_rel")
    # Reject any tracked dotfile EXCEPT `.gitkeep` (allow-listed).
    dotfile_hits=$(printf '%s\n' "$tracked" | awk -F/ '
      { name=$NF }
      name ~ /^\./ && name != ".gitkeep" { print }
    ')
    # __pycache__ / node_modules: should never be tracked. If git ls-files
    # reports any, that IS a real cleanliness regression.
    # grep returns 1 when no matches; that's the success case here. Use a
    # conditional rather than `|| true` so a real grep error (regex syntax,
    # broken pipe) still surfaces.
    artifact_hits=$(printf '%s\n' "$tracked" | grep -E '(^|/)(__pycache__|node_modules)(/|$)') || \
      [ "$?" -eq 1 ] || { echo "FAIL: grep error" >&2; return 1; }
    if [ -n "$dotfile_hits" ] || [ -n "$artifact_hits" ]; then
      fail "skill $name: contains tracked dotfile/artifact (skill dirs must be clean)" \
        "$(printf '%s\n%s\n' "$dotfile_hits" "$artifact_hits")"
      continue
    fi
    pass "skill $name: clean (no tracked dotfiles/artifacts)"
  done

  echo "=== Per-skill version frontmatter ==="
  for skill_dir in "$REPO_ROOT/skills"/*/ "$REPO_ROOT/block-diagram"/*/; do
    skill_md="${skill_dir}SKILL.md"
    [ -f "$skill_md" ] || continue
    name=$(basename "$skill_dir")
    version=$(bash "$REPO_ROOT/scripts/frontmatter-get.sh" "$skill_md" metadata.version) || {
      fail "skill $name: metadata.version missing or unreadable" "from $skill_md"
      continue
    }
    if [[ ! "$version" =~ ^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$ ]]; then
      fail "skill $name: metadata.version '$version' does not match YYYY.MM.DD+HHHHHH (validated month/day ranges)" "from $skill_md"
      continue
    fi
    # Stale-hash check.
    stored_hash="${version##*+}"
    fresh_hash=$(bash "$REPO_ROOT/scripts/skill-content-hash.sh" "$skill_dir")
    if [ "$stored_hash" != "$fresh_hash" ]; then
      fail "skill $name: stored hash $stored_hash != fresh hash $fresh_hash" "version line stale"
      continue
    fi
    pass "skill $name: metadata.version=$version"
  done

  # Mirror desync check (Round-2 F-R2-7) + allow-list for source-less mirrors
  # (Round-3 F-DA-R3-3). The allow-list is hardcoded; new entries require a
  # documented justification per §1.6.
  #
  #   playwright-cli — pre-dates the source/mirror split; vendor-bundled.
  #   social-seo     — pre-dates the source/mirror split; vendor-bundled.
  #
  # Any other source-less mirror is a CI failure (orphaned cleanup signal).
  MIRROR_ONLY_OK="playwright-cli social-seo"
  echo "=== Per-skill version mirror parity ==="
  for mirror_dir in "$REPO_ROOT/.claude/skills"/*/; do
    mirror_md="${mirror_dir}SKILL.md"
    [ -f "$mirror_md" ] || continue
    name=$(basename "$mirror_dir")
    src_dir="$REPO_ROOT/skills/$name"
    if [ ! -f "$src_dir/SKILL.md" ]; then
      # No source — must be on the allow-list.
      if [[ " $MIRROR_ONLY_OK " == *" $name "* ]]; then
        pass "skill $name: mirror-only (allow-listed, skipped)"
        continue
      fi
      fail "mirrored skill $name: no source counterpart and not on MIRROR_ONLY_OK allow-list" \
        "orphaned mirror — delete .claude/skills/$name or add a source dir"
      continue
    fi
    mirror_ver=$(bash "$REPO_ROOT/scripts/frontmatter-get.sh" "$mirror_md" metadata.version) || {
      fail "mirrored skill $name: metadata.version missing or unreadable" "from $mirror_md"
      continue
    }
    mirror_hash="${mirror_ver##*+}"
    src_fresh_hash=$(bash "$REPO_ROOT/scripts/skill-content-hash.sh" "$src_dir")
    if [ "$mirror_hash" != "$src_fresh_hash" ]; then
      fail "mirrored skill $name: stored hash $mirror_hash != source projection $src_fresh_hash" "mirror desync"
      continue
    fi
    pass "mirrored skill $name: hash matches source projection"
  done
  ```

  (Round-1 findings F-R11, F-R13, F-DA11: dead `screenshots` continue-line removed since enumeration filter handles it; regex tightened to validate month/day ranges. Round-2 F-R2-7: third loop over `.claude/skills/` closes the mirror-desync coverage gap. Round-3 F-DA-R3-2: dotfile-cleanliness loop. Round-3 F-DA-R3-3: hardcoded `MIRROR_ONLY_OK` allow-list with documented entries.)

  Expected: **N passes** for the cleanliness loop and **N passes** for the source-version loop, where `N = $CORE_COUNT + $ADDON_COUNT` (computed by the Phase 3.2 enumeration; refine time = 26 + 3 = 29 but the literal is NOT pinned — the AC asserts `>= $CORE_COUNT + $ADDON_COUNT` PASS lines per loop), plus **M passes** for the mirror loop (`M = .claude/skills` count, with `playwright-cli` and `social-seo` as allow-listed skipped passes; all other mirrors must have a source counterpart). 0 fails after migration lands across all three sections.

- [ ] 3.7 — Append `CHANGELOG.md` entry under today's date heading (create the date heading if absent), per the §1.8 canonical template:

  ```markdown
  ## YYYY-MM-DD

  ### Added — per-skill versioning

  Every source skill under `skills/` and `block-diagram/` now carries
  `metadata.version: "YYYY.MM.DD+HHHHHH"` in its SKILL.md frontmatter,
  seeded to today's date and each skill's content hash. Edits to a
  skill body must bump this field; see `references/skill-versioning.md`
  and CLAUDE.md "Skill versioning" rule. Enforcement lands in subsequent
  commits (Phase 4).
  ```

- [ ] 3.8 — Commit message: `feat(skills): seed metadata.version on all source skills + extend conformance test` (the actual count goes in the commit body, derived from the Phase 3.2 enumeration — do NOT pin a literal in the subject line).

### Design & Constraints

**Atomicity at scale.** Phase 3 modifies one SKILL.md per source-skill directory and one mirror copy per core skill (the count is derived from the Phase 3.2 enumeration; refine time = 26 core SKILL.md + 3 add-on SKILL.md + 26 mirror copies, but the literal is NOT pinned). The script-driven loop is idempotent — re-running with the same `$MIGRATION_DATE` and recomputed hash is a no-op. Verify per-skill mirror parity (3.5) before staging.

**Conformance regex precision.** `^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$` — month restricted to 01-12, day to 01-31, hash exactly 6 lowercase hex. Round-1 finding F-DA11: rejects `2026.13.45+xxx` and similar.

**Block-diagram path enumeration.** `block-diagram/README.md` is not a skill; `block-diagram/screenshots/` has no SKILL.md. The `find ... -exec test -f '{}/SKILL.md' \; -print` form (3.2) filters both correctly.

**Failure mode: revert/no-op edit during migration.** Phase 3's migration is the one exempt event — every SKILL.md gets a NEW key inserted, so the hook (which fires on body diff with no version bump) doesn't fire because the version line itself is being added. The Phase 4 hook lands AFTER Phase 3.

**Failure mode: mirror desync.** Step 3.5's `diff -r` catches it. The post-Phase-3 conformance section ALSO catches it: the conformance test's enumeration adds a third loop over `.claude/skills/*/SKILL.md` that recomputes the projection and asserts the mirrored hash equals the recomputed value (Round-2 finding F-R2-7: prior plan claimed "triple-covered" but conformance only iterated source roots; this third loop closes the real gap). The conformance work item 3.6 is updated to include the `.claude/skills/` walk.

**Failure mode: parallel-worktree convergence (during Phase 3 itself).** This phase MUST run in a single worktree. Phase 6's parallel-worktree canary covers post-migration parallel edits.

### Acceptance Criteria

- [ ] For every source skill (under `skills/` and `block-diagram/`), `bash scripts/frontmatter-get.sh <skill>/SKILL.md metadata.version` outputs a value matching the strict regex `^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$`. Verified per-skill via the conformance test loop (3.6); per-skill grep on indentation patterns is fragile (F-R2-8 — does not verify that `version:` sits under `metadata:`). Use the per-file `frontmatter-get.sh metadata.version` invocation as the authoritative check.
- [ ] Source-skill count check: `find skills -maxdepth 1 -mindepth 1 -type d -exec test -f '{}/SKILL.md' \; -print | wc -l` returns `$CORE_COUNT` from the Phase 3.2 enumeration (refine time: 26; was 25 at plan-write 2026-04-30) AND `find block-diagram -maxdepth 1 -mindepth 1 -type d -exec test -f '{}/SKILL.md' \; -print | wc -l` returns `$ADDON_COUNT` (refine time: 3). The AC checks consistency between Phase 3.2's enumeration result and Phase 3.6's loop output, not against a pinned literal.
- [ ] For every source skill `X`, the stored hash equals the freshly-computed hash: `[ "${version##*+}" = "$(bash scripts/skill-content-hash.sh <X>)" ]`.
- [ ] For every core skill `X` in `skills/`, `diff -r skills/X .claude/skills/X` is empty.
- [ ] `bash tests/test-skill-conformance.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0. Output contains: the cleanliness section `=== Skill-dir cleanliness ===` with at least `$CORE_COUNT + $ADDON_COUNT` PASS lines and 0 fails; the source-loop section `=== Per-skill version frontmatter ===` with at least `$CORE_COUNT + $ADDON_COUNT` PASS lines; AND the mirror-loop section `=== Per-skill version mirror parity ===` with one PASS line per `.claude/skills/*/` directory present (`playwright-cli` and `social-seo` show as allow-listed-skipped; all other mirrors match source). 0 fails across all three sections.
- [ ] `bash tests/test-mirror-skill.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0.
- [ ] `bash tests/run-all.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0.
- [ ] `grep -q "Added — per-skill versioning" CHANGELOG.md` succeeds.
- [ ] Every source skill has the same date prefix (the migration date), assertable by:

  ```bash
  for f in skills/*/SKILL.md block-diagram/*/SKILL.md; do
    [ -f "$f" ] || continue
    v=$(bash scripts/frontmatter-get.sh "$f" metadata.version)
    [ "${v%+*}" = "$MIGRATION_DATE" ] || { echo "FAIL: $f date drift" >&2; exit 1; }
  done
  ```

### Dependencies

Phase 1 (decision), Phase 2 (helpers).

### Non-Goals

- Bumping skills based on their `git log -1` last-modified date (rejected per §1.9).
- Editing `tests/test-skill-file-drift.sh` (it tests `zskills-resolve-config.sh`, unrelated).
- Mirror-only skills (`playwright-cli`, `social-seo`) — out of scope per §1.6.
- Updating `/update-zskills` (Phase 5).

---

## Phase 4 — Enforcement: drift-warn hook + `/commit` Phase 5 step 2.5 + CI gate

### Goal

Wire the three-point enforcement chain (Edit-time warn → commit-time hard stop → CI gate). The CI gate from Phase 3 is already extant; Phase 4 adds Edit-time and commit-time. CLAUDE.md (already updated in Phase 1.2) names the rule.

### Work Items

- [ ] 4.1 — Extend `hooks/warn-config-drift.sh` with a third branch `--- Branch 3: skill version not bumped ---` after the existing skill-file forbidden-literals branch.

  **Outer regex (Branch 3 — this work item).** Branch 3 uses **a single regex** that captures any regular file under a skill directory in either source root: `(^|/)(skills|block-diagram)/([^/]+)/[^/]+`. **No `\.md$` anchor** — Branch 3 must catch edits to `scripts/*.sh`, `stubs/*.sh`, `fixtures/*`, etc., because every regular file under the skill directory is in the projection per §1.1, so any of them can drift the hash. The trailing `[^/]+` (rather than `.*`) requires at least one path segment AFTER the skill name, so `block-diagram/screenshots/foo.png` (no SKILL.md) and `block-diagram/README.md` (top-level doc) both gracefully no-op via the downstream `[ -f "$skill_md" ] || exit 0` check; this regex tightening is defensive (refine-plan F-DA-9, partly verified — `block-diagram/README.md` does NOT match either form, but `block-diagram/screenshots/foo.png` DOES match both forms; the new tighter form keeps the same outcome but reduces surface for future-tightening confusion). (Empirical check: `echo "skills/run-plan/scripts/correct-plan.sh" | grep -E "(^|/)(skills|block-diagram)/[^/]+/.*\.md$"` returns no match — the `.md$` anchor would silently miss script edits. Branch 3's regex deliberately omits the anchor.) Branch 2's existing `\.md$` regex is **separately** widened to add `block-diagram/` for SKILL.md forbidden-literal coverage (Round-1 finding F-R4); that widening is independent of Branch 3.

  **Staged-file gate.** Before doing any work, the new branch checks whether the file is in the staging set. **Use `grep -Fqx` (fixed-string)** — paths can contain regex metacharacters (e.g., a skill named `a.b` or `a+b`) and `grep -qx` would treat them as a regex pattern (F-DA-R2-5: `grep -qx "skills/foo.bar/SKILL.md"` matches `skills/fooXbar/SKILL.md`). Same fix at the pseudocode site below.

  ```bash
  if ! git -C "$REPO_ROOT" diff --cached --name-only 2>/dev/null | grep -Fqx "$FILE_PATH_REL"; then
    exit 0
  fi
  ```

  where `$FILE_PATH_REL` is `$FILE_PATH` made relative to `$REPO_ROOT`. **`$FILE_PATH` may arrive as either an absolute path or a repo-relative path** — the harness's behavior across hook contexts is not stable across versions. The hook MUST normalize to repo-relative form using `git`-aware resolution rather than path-string surgery (refine-plan F-R10 / F-DA-16: the previous `${FILE_PATH#$REPO_ROOT/}` form silently fails when `$FILE_PATH` is symlink-resolved differently from `$REPO_ROOT`, when the strip is a no-op on already-relative input, or when `$REPO_ROOT` ends with a trailing slash). Use:

  ```bash
  # Normalize to repo-relative form. GNU `realpath --relative-to` handles
  # symlink resolution and absolute/relative input symmetrically. BSD/macOS
  # `realpath` exists at /usr/bin/realpath but lacks --relative-to; the
  # `command -v realpath` probe alone is NOT sufficient. Probe the FLAG by
  # actually invoking it and checking that the result is non-empty AND
  # doesn't start with a slash. (refine-plan F-DA-R2-1: prior form passed
  # the `command -v` probe on macOS, then `realpath --relative-to=...`
  # failed with "illegal option", leaving FILE_PATH_REL empty and the
  # `grep -Fqx ""` gate matching nothing — silent miss on macOS.)
  FILE_PATH_REL=""
  if FILE_PATH_REL=$(realpath --relative-to="$REPO_ROOT" "$FILE_PATH" 2>/dev/null) \
       && [ -n "$FILE_PATH_REL" ]; then
    case "$FILE_PATH_REL" in
      /*) FILE_PATH_REL="" ;;  # absolute output (shouldn't happen with --relative-to, but defensive)
    esac
  fi
  if [ -z "$FILE_PATH_REL" ]; then
    # Fallback: string-strip. Works when $FILE_PATH and $REPO_ROOT share a
    # textual prefix; fails on symlink-divergence (e.g., /var/folders/.../X
    # vs /private/var/folders/.../X on macOS).
    FILE_PATH_REL="${FILE_PATH#$REPO_ROOT/}"
    case "$FILE_PATH_REL" in
      /*)
        # Strip didn't reduce the path — symlink divergence, $REPO_ROOT
        # mismatch, or BSD realpath without GNU --relative-to. Surface a
        # WARN diagnostic so the silent no-op is at least observable.
        # (refine-plan F-R2-1: prior fallback exited silently with no
        # diagnostic; consumers reported "the hook didn't fire" with no
        # debugging trail.)
        printf 'WARN: warn-config-drift: could not normalize %s relative to %s — staged-file gate skipped\n' \
          "$FILE_PATH" "$REPO_ROOT" >&2
        exit 0
        ;;
    esac
  fi
  ```

  This folds Round-1 finding F-DA7 (hook noise during WIP) into the hook itself: warn fires only when the agent has explicitly staged the file, signaling commit intent. Mid-WIP edits do not generate noise.

  **Subject disambiguation.** When `$FILE_PATH` is a child file under `<root>/<name>/(modes|references|scripts|fixtures)/...`, the hook compares the PARENT skill's recomputed hash to HEAD's `metadata.version` hash — NOT a hash of the child file itself. The body-diff check operates on the parent SKILL.md's projection, not on the child file. (Round-1 finding F-DA8: subjects must be explicit.)

  Pseudocode:

  ```bash
  # Resolve REPO_ROOT (CLAUDE_PROJECT_DIR is set by harness).
  REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$REPO_ROOT" ] || exit 0

  HASH_HELPER="$REPO_ROOT/scripts/skill-content-hash.sh"
  GET_HELPER="$REPO_ROOT/scripts/frontmatter-get.sh"
  [ -x "$HASH_HELPER" ] && [ -x "$GET_HELPER" ] || exit 0  # graceful no-op

  # Derive the parent skill dir + SKILL.md from the edited path.
  # Trailing `[^/]+` requires the file to be INSIDE a skill dir (not the
  # parent directory itself). refine-plan F-DA-9.
  if [[ "$FILE_PATH" =~ (^|/)(skills|block-diagram)/([^/]+)/[^/]+ ]]; then
    skill_root_kind="${BASH_REMATCH[2]}"
    skill_name="${BASH_REMATCH[3]}"
    skill_dir="$REPO_ROOT/$skill_root_kind/$skill_name"
    skill_md="$skill_dir/SKILL.md"
  else
    exit 0
  fi
  [ -f "$skill_md" ] || exit 0  # not a versioned skill yet

  # Staged-file gate: warn only if THIS path is in the staging set.
  # grep -Fqx (fixed-string) — paths may contain regex metachars; -qx is a regex match.
  # Normalize $FILE_PATH to repo-relative form. Probe `realpath --relative-to`
  # by invocation (BSD realpath exists but lacks the flag; refine-plan F-DA-R2-1).
  # WARN on fallback failure so the silent no-op is observable (refine-plan F-R2-1).
  FILE_PATH_REL=""
  if FILE_PATH_REL=$(realpath --relative-to="$REPO_ROOT" "$FILE_PATH" 2>/dev/null) \
       && [ -n "$FILE_PATH_REL" ]; then
    case "$FILE_PATH_REL" in /*) FILE_PATH_REL="" ;; esac
  fi
  if [ -z "$FILE_PATH_REL" ]; then
    FILE_PATH_REL="${FILE_PATH#$REPO_ROOT/}"
    case "$FILE_PATH_REL" in
      /*)
        printf 'WARN: warn-config-drift: could not normalize %s relative to %s — staged-file gate skipped\n' \
          "$FILE_PATH" "$REPO_ROOT" >&2
        exit 0
        ;;
    esac
  fi
  if ! git -C "$REPO_ROOT" diff --cached --name-only | grep -Fqx "$FILE_PATH_REL"; then
    exit 0
  fi

  # Get the parent skill's stored version (the version_check_subject).
  on_disk_ver=$(bash "$GET_HELPER" "$skill_md" metadata.version) || on_disk_ver=""

  # Get HEAD's version line (the parent skill's HEAD state).
  head_blob=$(git -C "$REPO_ROOT" show "HEAD:${skill_md#$REPO_ROOT/}" 2>/dev/null) \
    || head_blob=""
  head_ver=""
  if [ -n "$head_blob" ]; then
    head_ver=$(printf '%s' "$head_blob" | bash "$GET_HELPER" - metadata.version) \
      || head_ver=""
  fi

  # Compute the parent skill's CURRENT (worktree) projection hash.
  cur_hash=$(bash "$HASH_HELPER" "$skill_dir")

  # Stored hash from on_disk_ver.
  stored_hash="${on_disk_ver##*+}"
  head_hash="${head_ver##*+}"

  # Asymmetric warn: hash drifted but version line not bumped.
  if [ -n "$on_disk_ver" ] && [ "$on_disk_ver" = "$head_ver" ] && [ "$cur_hash" != "$stored_hash" ]; then
    today=$(TZ="${TIMEZONE:-America/New_York}" date +%Y.%m.%d)
    printf 'WARN: %s — skill content changed (hash %s → %s) but metadata.version unchanged. Bump to %s+%s before commit.\n' \
      "$skill_md" "$stored_hash" "$cur_hash" "$today" "$cur_hash" >&2
  fi

  # Symmetric warn: version bumped but content unchanged (no-op edit / revert).
  if [ -n "$on_disk_ver" ] && [ "$on_disk_ver" != "$head_ver" ] && [ "$cur_hash" = "$head_hash" ]; then
    printf 'WARN: %s — metadata.version bumped (%s → %s) but content unchanged. Revert version line or land a real edit.\n' \
      "$skill_md" "$head_ver" "$on_disk_ver" >&2
  fi
  ```

  **No `2>/dev/null` on operations whose success matters.** Plan-wide audit (Round-2 F-R2-5): four operational `2>/dev/null` uses survive in the pseudocode, all with explicit empty-output-as-signal justification:
  - **Phase 4.1 staged-file gate** (`git diff --cached --name-only 2>/dev/null`) — in a non-git tree the gate cleanly returns no matches and the hook exits 0; git failure here is the legitimate signal "no staged set."
  - **Phase 4.1 `git show "HEAD:<path>"`** — file not yet in HEAD is the legitimate signal for "first migration commit."
  - **Phase 4.3 `git show ":$sk/SKILL.md"`** (staged blob) — same class: empty output = "not staged."
  - **Phase 4.3 `git show "HEAD:$sk/SKILL.md"`** — same class: empty output = "not in HEAD."

  Helper invocations (`frontmatter-get`, `skill-content-hash`) do NOT use `2>/dev/null`; their stderr surfaces if they fail. None of the four operational sites suppress stderr that would surface a real bug. The remaining `2>/dev/null` mentions in the plan are prose discussions (§1.6, Phase 5b.1, Plan Quality), not code. (Round-1 finding F-DA9; Round-2 F-R2-5 audit-completeness.)

- [ ] 4.2 — **Removed.** Stdin support for `frontmatter-get.sh` is a Phase 2.1 contract from the start (Round-1 findings F-R3 / F-DA6). Phase 4 just uses it.

- [ ] 4.3 — Extract the commit-time check into a runnable script `scripts/skill-version-stage-check.sh` (testable, reusable, single source of truth — sister of `plan-drift-correct.sh`):

  ```bash
  #!/bin/bash
  # skill-version-stage-check.sh — for /commit Phase 5 step 2.5.
  # Iterates staged files matching (skills|block-diagram)/<name>/...,
  # for each unique parent skill compares stored hash vs. recomputed
  # projection. Exit 0 on pass, 1 on STOP.
  set -u
  REPO_ROOT="${CLAUDE_PROJECT_DIR:?CLAUDE_PROJECT_DIR required}"
  GET="$REPO_ROOT/scripts/frontmatter-get.sh"
  HASH="$REPO_ROOT/scripts/skill-content-hash.sh"
  . "$REPO_ROOT/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"

  declare -A SKILLS_TO_CHECK
  while IFS= read -r f; do
    [[ "$f" =~ ^(skills|block-diagram)/([^/]+)/ ]] || continue
    SKILLS_TO_CHECK["${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"]=1
  done < <(git diff --cached --name-only)

  FAIL_LIST=()
  for sk in "${!SKILLS_TO_CHECK[@]}"; do
    skill_md="$REPO_ROOT/$sk/SKILL.md"
    [ -f "$skill_md" ] || continue

    staged_blob=$(git show ":$sk/SKILL.md" 2>/dev/null) || staged_blob=""
    staged_ver=""
    if [ -n "$staged_blob" ]; then
      staged_ver=$(printf '%s' "$staged_blob" | bash "$GET" - metadata.version) || staged_ver=""
    fi
    head_blob=$(git show "HEAD:$sk/SKILL.md" 2>/dev/null) || head_blob=""
    head_ver=""
    if [ -n "$head_blob" ]; then
      head_ver=$(printf '%s' "$head_blob" | bash "$GET" - metadata.version) || head_ver=""
    fi

    cur_hash=$(bash "$HASH" "$REPO_ROOT/$sk")
    staged_hash="${staged_ver##*+}"
    head_hash="${head_ver##*+}"

    if [ "$cur_hash" != "$head_hash" ] && [ "$staged_ver" = "$head_ver" ]; then
      FAIL_LIST+=("$sk: content changed (hash $head_hash → $cur_hash) but staged metadata.version still $staged_ver")
    fi
    if [ "$cur_hash" = "$head_hash" ] && [ -n "$staged_ver" ] && [ "$staged_ver" != "$head_ver" ]; then
      FAIL_LIST+=("$sk: metadata.version bumped ($head_ver → $staged_ver) but content unchanged")
    fi
  done

  if [ ${#FAIL_LIST[@]} -gt 0 ]; then
    today=$(TZ="$TIMEZONE" date +%Y.%m.%d)
    echo "STOP: skill version mismatch in staged commit:" >&2
    for msg in "${FAIL_LIST[@]}"; do
      echo "  $msg" >&2
    done
    echo "" >&2
    echo "To fix, for each affected skill <S>:" >&2
    echo "  hash=\$(bash $REPO_ROOT/scripts/skill-content-hash.sh <S>)" >&2
    echo "  bash $REPO_ROOT/scripts/frontmatter-set.sh <S>/SKILL.md metadata.version \"$today+\$hash\"" >&2
    echo "Then re-stage and re-run /commit." >&2
    exit 1
  fi
  ```

  Mirror to `.claude/skills/`? **No** — top-level `scripts/` isn't mirrored; it lives at `scripts/` only.

- [ ] 4.4 — Extend `skills/commit/SKILL.md` Phase 5 (Commit) with a new sub-step `2.5` between the existing step 2 (`Run tests if code was staged`) and step 3 (`Dispatch a fresh agent to review`) of `## Phase 5 — Commit`. Locate by heading text via `awk '/^## Phase 5 — Commit/,/^## Phase 6/' skills/commit/SKILL.md`; do NOT anchor to line numbers (refine-plan F-DA-13: the previous "line 239" cite is correct at refine time but brittle — any future edit to commit/SKILL.md upstream of Phase 5 shifts it). The natural gate placement is at Phase 5 step 2.5, AFTER tests pass (so the command is correctly ordered: tests then version-check then reviewer). (Round-1 finding F-R2: the prior plan said "Phase 4 step 3.5" which would interleave between staging and presenting-to-user — wrong location, since presenting-to-user is the Phase 4 outcome.)

  > **2.5. Skill-version bump check.** For every staged file under `skills/<owner>/...` or `block-diagram/<owner>/...`, verify each affected skill's `metadata.version` was correctly bumped (date refreshed AND hash matches recomputed projection):
  >
  > ```bash
  > bash "$CLAUDE_PROJECT_DIR/scripts/skill-version-stage-check.sh" || {
  >   echo "STOP: skill version check failed; see message above." >&2
  >   exit 1
  > }
  > ```
  >
  > Exit non-zero halts `/commit` until the agent fixes. The script's STOP message includes the exact bump command for each affected skill.

- [ ] 4.5 — Update `references/skill-versioning.md` §1.3 with the body-diff-detection rule used by both the hook (4.1) and `/commit` (4.4 + extracted script in 4.3): same script, single source of truth.

- [ ] 4.6 — Add `tests/test-skill-version-enforcement.sh` covering the hook AND the extracted script in isolation:
  - 12 hook test cases (each sandbox-based): edit-with-no-bump (warns); edit-with-bump (silent); revert-with-bump-only (warns symmetric); whitespace-only edit (silent — projection identical); new file (silent — no HEAD); helper missing (silent — graceful); HEAD missing version (silent — first migration); body diff with version line untouched (warns); **edit a child file under modes/ without staging it (silent — staged-file gate)**; **edit a child file under modes/ AND stage it without bumping parent SKILL.md (warns referencing parent)**; **`$FILE_PATH` fed as absolute path → same outcome as repo-relative case** (refine-plan F-R10 / F-DA-16: covers realpath normalization); **`$FILE_PATH` fed as repo-relative path → same outcome as absolute case** (covers fallback strip).
  - 8 stage-check script test cases: same matrix but checking exit code (0 = pass, 1 = STOP).
  - Uses `/tmp/zskills-tests/$(basename "$(pwd)")/`. Creates a sandbox git repo per case.

- [ ] 4.7 — Register `tests/test-skill-version-enforcement.sh` in `tests/run-all.sh`.

- [ ] 4.8 — Add `<!-- allow-skill-version-literal: ... -->` exemption marker for prose containing version literals (e.g., `references/skill-versioning.md` itself shows `2026.04.30+a1b2c3` as an example). Reuse the SKILL_FILE_DRIFT_FIX marker convention. Document in `references/skill-versioning.md`. **Scope the deny-list to skill content only** (`skills/<name>/**` and `block-diagram/<name>/**`) — NOT `plans/**`, `references/**`, `CHANGELOG.md`, or other non-skill content. Verify this BEFORE updating `tests/fixtures/forbidden-literals.txt`: read `tests/test-skill-conformance.sh` and confirm its forbidden-literal scan iterates only over skill files. If it scans more broadly today, extend the conformance test to scope itself first, then add the regex to the fixture. (refine-plan F-R14: a broadly-scoped deny-list would fire on this very plan file, which embeds many `2026.04.30+xxxxxx` examples; scoping the deny-list to skill content is the cleaner fix.) The regex to add is `[0-9]{4}\.[0-9]{2}\.[0-9]{2}\+[0-9a-f]{6}`.

- [ ] 4.9 — **Bump `metadata.version` of `skills/commit/SKILL.md` FIRST** — this phase edits the commit skill's body. Compute fresh hash via `bash scripts/skill-content-hash.sh skills/commit`, write today's date + hash via `frontmatter-set.sh`. **Bump precedes mirror** (Round-2 F-DA-R2-4: mirroring before bumping leaves the mirror immediately stale, fails the AC `diff -r skills/commit .claude/skills/commit` is empty). This bump also validates the gate end-to-end (the commit landing this phase must itself pass the gate).

- [ ] 4.10 — Mirror modified files **after the bump**: `bash scripts/mirror-skill.sh commit`. Hooks live at `hooks/` (top-level), no mirror needed.

- [ ] 4.11 — Append `CHANGELOG.md` entry under today's date heading (create the date heading if absent), per the §1.8 canonical template (refine-plan F-R19: explicit "create today's heading if absent" matches Phase 3.7's wording):

  ```markdown
  ### Added — skill-version enforcement (commit: <YYYY.MM.DD+HHHHHH>)

  Three-point gate on metadata.version: warn-config-drift hook
  (Edit-time, fires only on staged files), /commit Phase 5 step 2.5
  hard stop, test-skill-conformance.sh CI gate (now also validates
  hash freshness).
  ```

- [ ] 4.12 — Commit message: `feat(enforcement): three-point gate on skill metadata.version (Edit-time warn + commit-time stop + CI conformance with hash check)`.

### Design & Constraints

**Hash recomputation cost.** `skill-content-hash.sh` runs `find` + `sha256sum` over the skill dir. For zskills' largest skill (`run-plan` is 1912 lines), this is < 50ms. The hook fires on Edit; one Edit triggers one hash recomputation; well within budget.

**Hook exits 0 even when warning.** PostToolUse non-blocking convention.

**Commit-time check uses `git show :path`** (staged blob) for staged content and `git show HEAD:path` for HEAD content; the script (4.3) handles both.

**Failure mode: agent edits SKILL.md, doesn't bump.** Edit-time hook warns when staging. Agent runs `/commit`. Phase 5 step 2.5 stops with the bump command. Agent runs the bump command, re-stages, re-commits.

**Failure mode: agent edits SKILL.md, bumps version, then reverts only the body change.** Edit-time hook warns symmetric. Agent must either revert the version line OR land a real edit.

**Failure mode: agent edits a `modes/` or `references/` file under `skills/<X>/` without touching SKILL.md.** Per §1.3, this DOES require a SKILL.md version bump (the hash projection includes child files). The Phase 4.1 hook's regex covers child files; the body-diff check runs against the parent SKILL.md. (Subject-disambiguation per Round-1 finding F-DA8.)

**Failure mode: parallel-worktree clean-apply (was F-DA2).** Two worktrees both bump `skills/run-plan/SKILL.md` to `2026.04.30`, but each has different content. Worktree A: `2026.04.30+aaa111`. Worktree B: `2026.04.30+bbb222`. On cherry-pick of B onto A, the version line itself differs (`+aaa111` vs `+bbb222`) — `git cherry-pick` produces a CONFLICT on the version line even when the bodies don't textually overlap. The merger sees the divergence and recomputes the hash for the merged content, yielding a third hash `ccc333` that captures the union. Phase 6.3 canary verifies this end-to-end. **The hash format is what closes this failure mode; pure CalVer could not.**

### Acceptance Criteria

- [ ] `hooks/warn-config-drift.sh` Branch 2 outer regex includes `block-diagram`: `grep -E 'skills\|block-diagram' hooks/warn-config-drift.sh | grep -c '\.\*\\.md\$'` returns ≥ 1.
- [ ] `hooks/warn-config-drift.sh` Branch 3 invokes the hash and frontmatter-get helpers: `grep -c 'skill-content-hash\.sh\|frontmatter-get\.sh' hooks/warn-config-drift.sh` returns ≥ 2.
- [ ] `hooks/warn-config-drift.sh` includes the staged-file gate: `grep -c 'diff --cached --name-only' hooks/warn-config-drift.sh` returns ≥ 1.
- [ ] Editing `skills/run-plan/SKILL.md` body, staging it, then running the hook produces stderr `WARN:` containing `body changed` or `content changed`. Verified by `tests/test-skill-version-enforcement.sh` case 1.
- [ ] Editing the same and BUMPING `metadata.version` produces NO warn. Verified by case 2.
- [ ] `scripts/skill-version-stage-check.sh` exists and is executable: `test -x scripts/skill-version-stage-check.sh`.
- [ ] `skills/commit/SKILL.md` Phase 5 contains a step `2.5` invoking the script: `awk '/^## Phase 5/,/^## Phase 6/' skills/commit/SKILL.md | grep -c 'skill-version-stage-check\.sh'` returns ≥ 1.
- [ ] In a sandbox git repo, staging a body change to `skills/X/SKILL.md` without bumping the version and running `scripts/skill-version-stage-check.sh` exits 1 with `STOP:` on stderr.
- [ ] Same sandbox with the version bumped exits 0.
- [ ] Editing `skills/run-plan/modes/pr.md` AND staging it without bumping `skills/run-plan/SKILL.md`'s `metadata.version` produces a WARN referencing the parent SKILL.md (subject disambiguation). Verified by case 10.
- [ ] `bash tests/test-skill-version-enforcement.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0 with ≥ 20 cases passing (12 hook + 8 stage-check).
- [ ] `bash tests/test-skill-conformance.sh` STILL passes.
- [ ] `bash tests/run-all.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0.
- [ ] `diff -r skills/commit .claude/skills/commit` is empty.
- [ ] `grep -c 'jq' hooks/warn-config-drift.sh skills/commit/SKILL.md scripts/skill-version-stage-check.sh tests/test-skill-version-enforcement.sh` returns 0.
- [ ] `bash scripts/frontmatter-get.sh skills/commit/SKILL.md metadata.version` returns a date `>=` today (4.9 bump landed).

### Dependencies

Phase 1 (decision), Phase 2 (helpers), Phase 3 (migration — required so the hook isn't false-positive on un-versioned skills).

### Non-Goals

- A `/bump-skill` slash command.
- Updating `/update-zskills` (Phase 5).

---

## Phase 5a — `/update-zskills` data plumbing (helpers + config + briefing)

### Goal

Surface the *plumbing* layer for version data: config-schema field, repo-version helper, per-skill delta helper, briefing skill rewire, JSON-write helper. Phase 5b consumes these in `/update-zskills`'s SKILL.md UI sites. Splitting Phase 5 into 5a (plumbing) + 5b (UI) addresses Round-1 finding F-R9 (Phase 5 too large for one agent) and lets each commit stay scope-bounded.

### Work Items

- [ ] 5a.0 — **Preflight: `/update-zskills` PR check.** (Round-1 finding F-DA5.)

  **Re-anchor before editing.** Before starting 5a, re-derive the actual line numbers / anchor text for each insertion site in `skills/update-zskills/SKILL.md` from CURRENT state — the file has shifted since plan-draft (PR #171 on 2026-05-02 added Step 3.6 backfill at line 286, shifting everything below by ~30 lines). Phase 5b's three sites in particular MUST be located by heading text (`### Step 6 — Produce the gap report`, `#### Step G — Final report`, the `Updated: N skills` line under `### Pull Latest and Update`), NOT by the line numbers the plan was originally drafted against. (refine-plan F-DA-15.)

  ```bash
  # `in:files` qualifier is NOT supported by `gh pr list --search`; it's a
  # `gh search prs` qualifier. Use `gh pr list --state open --json` and
  # post-filter via fixed-string match on file paths from the JSON. (refine-plan
  # F-DA-7: the prior `gh pr list --search 'in:files ...'` form silently
  # returned empty regardless of actual PR state.)
  # Limit 100 is well above zskills' typical open-PR count (rarely >10). If
  # the soft cap is ever hit, the count check below logs a warning so the
  # gate doesn't silently miss PRs beyond row 100. (refine-plan F-R2-9.)
  raw=$(gh pr list --state open --limit 100 --json number,title,files)
  raw_count=$(printf '%s' "$raw" | grep -c '"number":' || true)
  if [ "$raw_count" -ge 100 ]; then
    echo "WARN: gh pr list returned $raw_count PRs (soft cap is 100); re-run with --limit 1000 to verify no missed entries." >&2
  fi
  # Match any PR whose JSON entry contains the file-path substring.
  hits=$(printf '%s\n' "$raw" | grep -F 'skills/update-zskills/' || \
    [ "$?" -eq 1 ] || { echo "FAIL: gh/grep error" >&2; exit 1; })
  if [ -n "$hits" ]; then
    echo "FAIL: open PRs touching skills/update-zskills/:" >&2
    # Print only the matching lines — for an active repo with many open PRs,
    # dumping `$raw` (full JSON of all open PRs) is unreadable noise.
    # (refine-plan F-DA-R2-5.)
    printf '%s\n' "$hits" >&2
    echo "Land or coordinate before starting Phase 5." >&2
    exit 1
  fi
  ```

  This is a hard preflight gate. If any open PR touches `skills/update-zskills/`, abort Phase 5a and surface to the user. Coordination is a user decision, not an agent decision.

  **Title-only fallback (informational).** If the user wants ALSO to surface PRs whose titles mention `update-zskills` (regardless of files), run `gh pr list --state open --search 'update-zskills in:title' --json number,title` separately and present the union. Do NOT collapse this into the file-path gate above — the file-path test is the load-bearing one.

- [ ] 5a.1 — Update `skills/update-zskills/scripts/zskills-resolve-config.sh` to resolve a 7th var `ZSKILLS_VERSION` from a top-level `zskills_version` field in `.claude/zskills-config.json`:

  ```bash
  ZSKILLS_VERSION=""
  if [[ "$_ZSK_CFG_BODY" =~ \"zskills_version\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    ZSKILLS_VERSION="${BASH_REMATCH[1]}"
  fi
  ```

  Initialize to empty string before the regex (empty-pattern-guard). Mirror to `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh`.

- [ ] 5a.2 — Update `tests/test-zskills-resolve-config.sh` with a 7th var case.

- [ ] 5a.3 — ADD `zskills_version` to `config/zskills-config.schema.json` as a top-level optional string field with default empty string. **Do NOT touch the existing `dashboard`, `commit`, `execution`, `testing`, `dev_server`, `ui`, or `ci` blocks** — those carry recently-added fields (notably `dashboard.work_on_plans_trigger` from PR #171, 2026-05-02) and a careless `Edit` on the schema would regress them. The change is purely additive at the top-level. (refine-plan F-R9: schema must survive the additive change unchanged elsewhere.)

- [ ] 5a.4 — Add `skills/update-zskills/scripts/resolve-repo-version.sh` (mirrored):

  ```bash
  #!/bin/bash
  # resolve-repo-version.sh — extract latest YYYY.MM.N tag from zskills source.
  # Tag scheme is defined by RELEASING.md:44-46 (zero-indexed YYYY.MM.N).
  # If the tag scheme changes (suffixes like `-rc`, prefixes like `v`, etc.),
  # update this regex AND tests/test-skill-version-delta.sh together.
  # (refine-plan F-R15: surface the cross-file dependency.)
  set -u
  ZSKILLS_PATH="${1:-}"
  [ -d "$ZSKILLS_PATH/.git" ] || { echo ""; exit 0; }
  git -C "$ZSKILLS_PATH" tag --list \
    | grep -E '^[0-9]{4}\.(0[1-9]|1[0-2])\.[0-9]+$' \
    | sort -V | tail -1
  ```

  Stricter month-range regex (Round-1 finding F-DA11 carried into repo-version regex).

- [ ] 5a.5 — Add `skills/update-zskills/scripts/skill-version-delta.sh` (mirrored):

  ```bash
  #!/bin/bash
  # Per-skill version delta. Stdout: <name>\t<kind>\t<source-ver>\t<installed-ver>\t<status>.
  # `<kind>` is `core` for skills/<name>/ or `addon` for block-diagram/<name>/.
  # Iterating BOTH source roots so block-diagram add-ons surface in install /
  # update / audit reports. (refine-plan F-R13 / F-DA-10: prior loop ranged only
  # over `skills/*/`, silently dropping the 3 add-ons even though §1.7 promised
  # parity.)
  set -u
  ZSKILLS_PATH="${1:?usage: skill-version-delta.sh <zskills-source-path>}"
  GET="$CLAUDE_PROJECT_DIR/scripts/frontmatter-get.sh"
  [ -x "$GET" ] || GET="$ZSKILLS_PATH/scripts/frontmatter-get.sh"
  for src_skill in "$ZSKILLS_PATH/skills"/*/ "$ZSKILLS_PATH/block-diagram"/*/; do
    [ -f "${src_skill}SKILL.md" ] || continue
    name=$(basename "$src_skill")
    case "$src_skill" in
      "$ZSKILLS_PATH/skills"/*) kind="core" ;;
      "$ZSKILLS_PATH/block-diagram"/*) kind="addon" ;;
      *) kind="unknown" ;;
    esac
    src_ver=$(bash "$GET" "${src_skill}SKILL.md" metadata.version) || src_ver=""
    inst_skill="$CLAUDE_PROJECT_DIR/.claude/skills/$name"
    inst_ver=""
    if [ -f "$inst_skill/SKILL.md" ]; then
      inst_ver=$(bash "$GET" "$inst_skill/SKILL.md" metadata.version) || inst_ver=""
    fi
    if [ -z "$inst_ver" ]; then
      status="new"
    elif [ -z "$src_ver" ]; then
      status="malformed"
    elif [ "$src_ver" = "$inst_ver" ]; then
      status="unchanged"
    else
      status="bumped"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$kind" "$src_ver" "$inst_ver" "$status"
  done
  ```

  **Render-time filter (consumed by Phase 5b.1 Site C):** the renderer applies the `--with-block-diagram-addons` heuristic: include `kind=addon` rows ONLY when `--with-block-diagram-addons` was passed OR when at least one `block-diagram/*` skill is currently installed under `.claude/skills/`. Otherwise emit only `kind=core` rows. Filtering happens at the renderer, not the enumerator — so the data plumbing is symmetric and downstream callers can render either subset.

- [ ] 5a.6 — Add `skills/update-zskills/scripts/json-set-string-field.sh` (mirrored) — JSON-aware string-field write, no jq. **Pre-condition: verify whether `apply-preset.sh` already factors out a JSON-write helper before adding this file** — read `skills/update-zskills/scripts/apply-preset.sh` and check; if a reusable function already exists there, source/extend it instead of duplicating. If `apply-preset.sh` does NOT factor it out, add this new helper as a sibling. (refine-plan F-DA-8: the original "If `apply-preset.sh` already factors this out, reuse its helper" was non-binding; the verifier MUST check, not assume.)

  Use `awk` for in-place rewriting (matches `frontmatter-set.sh`'s 2.2 approach). `awk`'s string-replacement is metacharacter-clean (no `&`, `\1`, etc. trap). Sed was rejected here specifically because `${VALUE}` may contain `&` (sed's matched-text backreference) or `\N` (sed backreference); only escaping `|` was insufficient. (refine-plan F-DA-8.)

  ```bash
  #!/bin/bash
  # json-set-string-field.sh <json-file> <key> <value>
  # Updates a top-level string field in a JSON file in-place.
  # Inserts the field if absent. No jq, no sed (awk is metacharacter-clean).
  set -u
  FILE="${1:?json-file required}"
  KEY="${2:?key required}"
  VALUE="${3:?value required}"
  TMP="$(mktemp)"
  # Preserve original file mode — `mktemp` defaults to 0600 which would lock
  # other readers (e.g., the dashboard server) out of the JSON file. Match
  # the original perms before mv. (refine-plan F-DA-8.)
  # `chmod --reference` is GNU coreutils; BSD/macOS lacks it. Probe-and-fall
  # back via `stat`. The probe pattern uses `2>/dev/null` defensibly (probe-
  # then-detect-failure-via-exit-code), not to silence a fallible op whose
  # success matters. (refine-plan F-R2-8.)
  if ! chmod --reference="$FILE" "$TMP" 2>/dev/null; then
    perms=$(stat -c '%a' "$FILE" 2>/dev/null || stat -f '%Lp' "$FILE")
    chmod "$perms" "$TMP"
  fi
  if grep -q "\"$KEY\"" "$FILE"; then
    # Update existing field. awk uses match()/substr() (no gsub) so the
    # replacement value `v` is treated as a literal string — no metacharacter
    # expansion. Whatever follows the closing quote (trailing comma, newline,
    # `}`, etc.) is preserved byte-for-byte. (refine-plan F-R2-3 / F-DA-R2-2:
    # earlier awk arithmetic dropped the opening quote AND the trailing
    # comma on middle fields. The form below uses match() once on the full
    # `"key" : "..."` pattern and slices the line into pre/head/post.)
    awk -v k="$KEY" -v v="$VALUE" '
      {
        # Build the pattern: "<key>"<ws>:<ws>"<anything-without-quote>"
        # `[^"]*` is awk-regex (NOT shell glob); the inner pattern matches
        # the existing quoted value with NO embedded quotes. Embedded quotes
        # are out of scope for v1 (see Non-Goals; refine-plan F-DA-R2-3).
        pat = "\"" k "\"" "[[:space:]]*:[[:space:]]*\"[^\"]*\""
        if (match($0, pat)) {
          pre  = substr($0, 1, RSTART - 1)              # before "key"
          head = substr($0, RSTART, RLENGTH)            # "key": "old"
          post = substr($0, RSTART + RLENGTH)           # everything after closing "
          # Replace just the trailing quoted value inside `head`. Anchor to
          # end-of-string so we only touch the value, not the key. The
          # replacement uses sub() with v interpolated as a literal awk
          # string, so `&`/`\1`/etc. in v are NOT awk-regex metacharacters
          # in the REPLACEMENT side — but sub() DOES treat `&` and `\&` as
          # specials in the replacement. To stay metacharacter-clean,
          # construct the new head by string concatenation:
          if (match(head, /"[^"]*"$/)) {
            head_pre = substr(head, 1, RSTART - 1)      # "key": (trailing space then opening ")
            # head_pre ends just before the OPENING quote of the value.
            new_head = head_pre "\"" v "\""
            print pre new_head post
            next
          }
        }
        print
      }
    ' "$FILE" > "$TMP"
  else
    # Insert before the outer closing brace, comma-aware (matches
    # apply-preset.sh:99-115). For an empty object `{ }` the inserted
    # field is the only entry — no leading comma needed AND no trailing
    # comma. For a non-empty object, the previous last field needs a
    # trailing comma added (if absent), and the inserted field gets
    # NO trailing comma. (refine-plan F-R2-6: the prior insert path
    # always wrote a trailing comma → invalid JSON.)
    awk -v k="$KEY" -v v="$VALUE" '
      { buf[NR] = $0 }
      END {
        # Find the last standalone closing brace.
        last_close = 0
        for (i = NR; i >= 1; i--) {
          if (buf[i] ~ /^[[:space:]]*\}[[:space:]]*$/) { last_close = i; break }
        }
        if (last_close == 0) {
          # Malformed JSON — leave file untouched and exit non-zero.
          for (i = 1; i <= NR; i++) print buf[i]
          exit 2
        }
        # Find the last non-blank line before the closing brace.
        preceding = 0
        for (i = last_close - 1; i >= 1; i--) {
          if (buf[i] !~ /^[[:space:]]*$/) { preceding = i; break }
        }
        for (i = 1; i < preceding; i++) print buf[i]
        if (preceding > 0) {
          # `preceding` is either the opening `{` (empty object) or the
          # last existing field. If it ends in `{`, no comma needed.
          # If it ends in `,`, no extra comma needed. Otherwise add one.
          if (buf[preceding] ~ /\{[[:space:]]*$/) {
            print buf[preceding]
          } else if (buf[preceding] ~ /,[[:space:]]*$/) {
            print buf[preceding]
          } else {
            line = buf[preceding]
            sub(/[[:space:]]*$/, "", line)
            print line ","
          }
        }
        # Inject the new field WITHOUT trailing comma (it lands as the
        # last field before `}`).
        print "  \"" k "\": \"" v "\""
        # Preserve any blank lines between preceding and last_close.
        for (i = preceding + 1; i < last_close; i++) print buf[i]
        for (i = last_close; i <= NR; i++) print buf[i]
      }
    ' "$FILE" > "$TMP" || {
      rm -f "$TMP"
      echo "json-set-string-field: malformed JSON in $FILE (no outer closing brace)" >&2
      exit 2
    }
  fi
  mv "$TMP" "$FILE"
  ```

  Document edge cases in test 5a.7: value-with-special-chars MUST cover `&`, `\1`, `|`, embedded quotes (round-trip get/set/get); update-middle-field MUST preserve trailing commas; insert-into-empty-object MUST produce valid JSON (no trailing comma); insert-into-non-empty-object MUST add a comma to the prior last field.

- [ ] 5a.7 — Add `tests/test-json-set-string-field.sh` — at least **11** cases. Each case MUST pipe the resulting file through `python3 -c "import sys,json; json.load(sys.stdin)"` (or equivalent JSON validator) to catch malformed-JSON output that grep-based assertions would miss:
  1. Insert into empty `{}` object — output MUST be valid JSON, no trailing comma. (refine-plan F-R2-6.)
  2. Insert into non-empty object — output MUST be valid JSON with comma added to the prior last field, NO trailing comma on the new field. (refine-plan F-R2-6.)
  3. Update existing field that is the LAST field — output MUST be valid JSON, no trailing comma.
  4. **Update middle field with trailing comma** — output MUST preserve the trailing comma; output MUST be valid JSON. (refine-plan F-R2-3 / F-DA-R2-2: prior awk arithmetic dropped the comma.)
  5. Idempotent no-change (set field to same value twice) — file unchanged after second invocation.
  6. **Value-with-`&`-and-`\1` round-trip** — verifies awk-replacement doesn't expand metacharacters (refine-plan F-DA-8 / F-R2-3).
  7. Value-with-`|`-and-embedded-quotes — note: embedded quotes in v1 contract are out-of-scope per Non-Goals (refine-plan F-DA-R2-3); the test asserts the helper either round-trips correctly OR exits non-zero, NOT silently corrupts.
  8. **File-mode preservation** — set perms to 0644 pre-call, assert post-call still 0644 (refine-plan F-DA-8).
  9. Malformed JSON (no closing brace) — helper exits non-zero, file unchanged.
  10. Insert when only line is `{}` on a single line — currently out of scope; helper exits non-zero (the awk regex requires the closing brace on its own line). Document as v1 limitation.
  11. Update where the value contains the key name as a substring (e.g., `"version": "...version..."`) — verifies the regex anchors correctly to the FIELD's quoted value, not a substring elsewhere.

- [ ] 5a.8 — Add `tests/test-skill-version-delta.sh` — fixture cases: source-newer (bumped), source-older (still emits, downstream decides), installed-missing (new), source-missing-but-installed-present (would be `removed` if implemented; v1 doesn't enumerate that case — out of scope), both-empty (malformed), both-equal (unchanged), **add-on-source-installed** (`kind=addon` row emitted when `block-diagram/<name>/SKILL.md` exists in source AND `.claude/skills/<name>/SKILL.md` exists; refine-plan F-R13 / F-DA-10), **add-on-source-not-installed** (`kind=addon` row STILL emitted by the script; renderer-side filter is responsible for hiding when no add-on is installed).

- [ ] 5a.9 — Update `skills/briefing/SKILL.md` "Z Skills Update Check" section (lines 339-356):

  ```bash
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  # ZSKILLS_VERSION is the installed version (from .claude/zskills-config.json).
  source_ver=""
  if [ -d "$ZSKILLS_PATH/.git" ]; then
    source_ver=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/resolve-repo-version.sh" "$ZSKILLS_PATH")
  fi
  if [ -n "$source_ver" ] && [ "$source_ver" != "$ZSKILLS_VERSION" ]; then
    echo "  zskills: $ZSKILLS_VERSION → $source_ver (run /update-zskills)"
  else
    echo "  zskills: ${ZSKILLS_VERSION:-(unknown)} (current)"
  fi
  ```

- [ ] 5a.10 — Register both new tests in `tests/run-all.sh`.

- [ ] 5a.11 — **Bump `metadata.version` of `skills/briefing/SKILL.md` FIRST** (body edit landed in 5a.9). Compute fresh hash via `bash scripts/skill-content-hash.sh skills/briefing`, write today's date + hash via `frontmatter-set.sh`. **Bump precedes mirror** (Round-2 F-DA-R2-4: mirror-before-bump leaves the mirror stale, fails AC `diff -r skills/briefing .claude/skills/briefing` is empty).

- [ ] 5a.11.5 — **Bump `metadata.version` of `skills/update-zskills/SKILL.md` after the script additions in 5a.1, 5a.4, 5a.5, 5a.6** (Round-3 F-R3-1 / F-DA-R3-2-pair: per §1.1's deny-list rule, every regular file under `<skill-dir>/` is in the projection — so adding three new scripts to `skills/update-zskills/scripts/` AND modifying `zskills-resolve-config.sh` changes `update-zskills`'s projection hash. Without this bump, the Phase 4 `/commit` step 2.5 gate would block the 5a commit and Phase 3.6 conformance would fail). The bump captures the post-5a content state — the SKILL.md body itself is NOT touched in 5a (body edits land in 5b.1 and 5b.2). 5b.6 then RE-bumps after 5b's body edits. Two bumps, one per content state: 5a.11.5 = "scripts changed", 5b.6 = "SKILL.md body changed". The intermediate version landed in 5a.11.5 is on main for the duration of 5b's commit window — this is by design, the version line tracks content states, not deliverable milestones.

  ```bash
  TODAY=$(TZ="$TIMEZONE" date +%Y.%m.%d)
  HASH=$(bash "$CLAUDE_PROJECT_DIR/scripts/skill-content-hash.sh" skills/update-zskills)
  bash "$CLAUDE_PROJECT_DIR/scripts/frontmatter-set.sh" skills/update-zskills/SKILL.md \
    metadata.version "$TODAY+$HASH"
  ```

- [ ] 5a.12 — Mirror modified files **after both bumps**: `bash scripts/mirror-skill.sh briefing && bash scripts/mirror-skill.sh update-zskills`. Verify mirror parity via `diff -r skills/briefing .claude/skills/briefing` (empty) and `diff -r skills/update-zskills .claude/skills/update-zskills` (empty). Both source skills now have refreshed `metadata.version`; both mirrors are byte-identical.

- [ ] 5a.13 — Append `CHANGELOG.md` entry under today's date heading (create the date heading if absent), per the §1.8 canonical template (refine-plan F-R19).

- [ ] 5a.14 — Commit message: `feat(update-zskills): plumbing for per-skill + repo-level version delta (helpers, config schema, briefing rewire)`.

### Design & Constraints

**`--rerender` mode is excluded from this phase.** Lines 1273-1308 of `skills/update-zskills/SKILL.md` (the rerender mode) do not touch skills, hooks, or settings — they regenerate stub files from canonical sources. Version-display surfaces belong to install/update/audit modes only. Phase 5b.3 + 5b.4 enforce the boundary; 5a does not introduce rerender-side reads or writes.

**JSON parsing convention — inline `BASH_REMATCH`, not the YAML helpers.** The new `json-set-string-field.sh` (5a.6) writes JSON via the same `apply-preset.sh` pattern (inline `sed` + `awk`, no jq). The corresponding READ path in 5a.1 (and reused at 5b.1 Site A) uses the inline `BASH_REMATCH` idiom from `zskills-resolve-config.sh`:

```bash
[[ "$cfg" =~ \"zskills_version\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && val="${BASH_REMATCH[1]}"
```

The `frontmatter-get.sh` helper is YAML-only; calling it on a JSON file exits 2 and `2>/dev/null` would silently swallow the failure (anti-CLAUDE.md per Round-1 F-R5 / F-DA3). zskills convention forbids `jq` (per CLAUDE.md memory note "no jq in skills"); BASH_REMATCH is the canonical alternative.

**PR-preflight rationale.** 5a.0's `gh pr list` preflight is a hard abort, not a warn (Round-1 F-DA5). `/update-zskills` is the most centrally-imported skill in the fleet — every consumer install runs through it. A staggered rebase against an unfinished PR risks shipping a half-merged version-surface to consumers. Coordination is a user decision; the agent's job is to surface, not to choose. Phase 6.7 re-runs the preflight as a final gate before landing.

**Two-bump cadence on `update-zskills` (5a.11.5 + 5b.6).** Per Round-3 F-R3-1, `update-zskills`'s projection changes twice in this plan: once when 5a's helper scripts land, once when 5b's SKILL.md body changes. Each content state gets its own version. This is the correct semantics — the version line is "skill content fingerprint at this commit," not "skill milestone marker." Two commits, two bumps; no exemption shortcut.

**Failure mode: 5a partial landing.** If 5a lands but 5b never lands, the fleet still has a coherent state — `update-zskills` shipped with new helpers, the SKILL.md body still references the old behavior, the version reflects the script-changed state. Consumers running `/update-zskills` get the helpers but no new UI; the audit gap report renders the prior format. Not a regression; degrades gracefully.

### Acceptance Criteria

- [ ] `gh pr list` preflight runs and aborts on any open PR touching `skills/update-zskills/` (verified by manual review of 5a.0).
- [ ] `bash skills/update-zskills/scripts/zskills-resolve-config.sh` (or sourcing it) sets `ZSKILLS_VERSION`. Verified by extending `tests/test-zskills-resolve-config.sh`.
- [ ] (refine-plan F-R2-10) `grep -c 'ZSKILLS_VERSION' tests/test-zskills-resolve-config.sh` returns ≥ 1 — confirms the 7th-var case was actually added, not just promised in 5a.2.
- [ ] (refine-plan F-R2-10) `bash tests/test-zskills-resolve-config.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0 with at least one new ZSKILLS_VERSION-related case passing.
- [ ] Schema preservation (refine-plan F-R9): `grep -q '"work_on_plans_trigger"' config/zskills-config.schema.json` AND `grep -q '"zskills_version"' config/zskills-config.schema.json` both succeed post-5a.3. The existing `dashboard`, `commit`, `execution`, `testing`, `dev_server`, `ui`, `ci` top-level blocks are unchanged from the pre-5a.3 file — verifiable via `git diff config/zskills-config.schema.json` only showing the additive `zskills_version` insertion.
- [ ] `bash skills/update-zskills/scripts/resolve-repo-version.sh /workspaces/zskills` outputs a value matching `^[0-9]{4}\.(0[1-9]|1[0-2])\.[0-9]+$`.
- [ ] `bash skills/update-zskills/scripts/skill-version-delta.sh /workspaces/zskills` outputs at least `$CORE_COUNT + $ADDON_COUNT` tab-delimited lines (refine time = 26 + 3 = 29; the AC is derivation-driven, not pinned, since the count drifts as new skills land — see F-R13 / F-DA-10 fix that adds add-ons to the loop).
- [ ] `bash tests/test-skill-version-delta.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0.
- [ ] `bash tests/test-json-set-string-field.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0.
- [ ] `diff -r skills/briefing .claude/skills/briefing` is empty.
- [ ] `diff -r skills/update-zskills .claude/skills/update-zskills` is empty.
- [ ] `bash scripts/frontmatter-get.sh skills/briefing/SKILL.md metadata.version` returns a value > Phase 3 migration date.
- [ ] `bash scripts/frontmatter-get.sh skills/update-zskills/SKILL.md metadata.version` returns a value > Phase 3 migration date (Round-3 F-R3-1: the script additions in 5a require an `update-zskills` bump in 5a.11.5, distinct from 5b.6's bump after body edits).
- [ ] The hash component of `update-zskills`'s 5a-landed version equals the freshly-computed projection: `[ "$(bash scripts/frontmatter-get.sh skills/update-zskills/SKILL.md metadata.version | awk -F+ '{print $2}')" = "$(bash scripts/skill-content-hash.sh skills/update-zskills)" ]`.
- [ ] `bash tests/run-all.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0 (including conformance which now hash-checks update-zskills against its post-5a content state).
- [ ] `grep -c 'jq' skills/update-zskills/scripts/*.sh skills/briefing/SKILL.md` returns 0.

### Dependencies

Phase 1, Phase 2, Phase 3, Phase 4.

### Non-Goals

- Updating `skills/update-zskills/SKILL.md` UI surface (Phase 5b).
- Wiring `/zskills-dashboard` (deferred).
- **Embedded quotes / JSON-escapes inside string values for `json-set-string-field.sh`.** v1 contract is "string fields whose values contain no `"` characters." The awk regex `[^"]*` stops at the first inner quote; values containing `\"` (JSON-escaped) are not supported. `.claude/zskills-config.json`'s actual usage (a date+hash version string) does not need them. Out of scope; document as a known limitation in the helper's header. (refine-plan F-DA-R2-3.)

---

## Phase 5b — `/update-zskills` UI surface (3 insertion sites)

### Goal

Wire the data plumbing from Phase 5a into `skills/update-zskills/SKILL.md`'s three user-facing reports: audit gap report, install final report, update final report. Add the mirror-tag-into-config step.

### Work Items

- [ ] 5b.1 — Insert version-delta surfacing in three sites within `skills/update-zskills/SKILL.md`:

  **Site A — Audit gap report (`### Step 6 — Produce the gap report` in `skills/update-zskills/SKILL.md`; locate via `grep -n '### Step 6 — Produce the gap report' skills/update-zskills/SKILL.md` — at refine time line 559, but line numbers will shift; anchor by heading text).** Insert AFTER the closing fence of the audit-report template body (the `Overall: X/Y dependencies satisfied.` line) and BEFORE the "If everything is satisfied" prose paragraph that follows. Add:

  ```bash
  # Repo-level version
  current_zskills_ver=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/resolve-repo-version.sh" "$ZSKILLS_PATH")
  installed_zskills_ver=""
  if [ -f "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json" ]; then
    cfg=$(cat "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json")
    if [[ "$cfg" =~ \"zskills_version\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      installed_zskills_ver="${BASH_REMATCH[1]}"
    fi
  fi
  ```

  Render: `Versions: zskills <installed_ver>→<current_ver>; <N> skills changed`.

  **JSON read uses inline BASH_REMATCH, NOT `frontmatter-get.sh`** (Round-1 findings F-R5 / F-DA3: helper is YAML-only; calling it on JSON exits 2 and `2>/dev/null` would silently swallow the failure, anti-CLAUDE.md). The same idiom appears in `zskills-resolve-config.sh` — single source of truth for JSON parsing.

  **Site B — Install final report (`#### Step G — Final report` in `skills/update-zskills/SKILL.md`; locate via `grep -n '#### Step G — Final report' skills/update-zskills/SKILL.md` — at refine time line 1221; line numbers will shift, anchor by heading).** Add a "Per-skill versions" sub-section between the existing `Skills with additional requirements:` bullet and the closing `Run /update-zskills to check for updates later.` line, showing each skill's installed version. For an install, all skills are "new" relative to the (empty) prior state.

  **Site C — Update final report (the `Updated: N skills (list)` line inside step `6. Report:` of `### Pull Latest and Update (already-installed path)` in `skills/update-zskills/SKILL.md`; locate via `grep -n 'Updated: N skills' skills/update-zskills/SKILL.md` — at refine time line 1283; line numbers will shift, anchor by text).** REPLACE that line with a structured table:

  ```
  Z Skills updated.

  Repo version: <old_zskills_ver> → <new_zskills_ver>

  Updated: N skills
    run-plan          2026.04.20+a1b2c3 → 2026.04.30+d4e5f6
    briefing          2026.04.18+9a8b7c → 2026.04.30+1f2e3d
    commit            2026.04.15+5a6b7c (unchanged)
    ...
  New: M items installed (list)
  ```

  Generated by piping `skill-version-delta.sh` output through a formatting `awk` script.

- [ ] 5b.2 — Add a "mirror-the-tag-into-config" step to `/update-zskills` Step C (install) and the update flow's "Pull Latest" step. Pseudocode using the helper from Phase 5a.6:

  ```bash
  new_repo_ver=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/resolve-repo-version.sh" "$ZSKILLS_PATH")
  if [ -n "$new_repo_ver" ]; then
    bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/json-set-string-field.sh" \
      "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json" zskills_version "$new_repo_ver"
  fi
  ```

- [ ] 5b.3 — **`--rerender` mode unchanged.** Lines 1273-1308 of `skills/update-zskills/SKILL.md` do NOT touch skills, hooks, or settings; version display does NOT belong there. Test 5b.4 below asserts `--rerender` output contains no version-delta data.

- [ ] 5b.4 — Add `tests/test-update-zskills-version-surface.sh` covering the three sites (audit / install / update) end-to-end against fixture state. AC: rerender output capture is empty for `Repo version|metadata.version` (Round-1 finding F-R14).

- [ ] 5b.5 — Register the new test in `tests/run-all.sh`.

- [ ] 5b.6 — **Bump `metadata.version` of `skills/update-zskills/SKILL.md` FIRST** (body edits in 5b.1 and 5b.2 landed). Compute fresh hash via `bash scripts/skill-content-hash.sh skills/update-zskills`, write today's date + hash. **Bump precedes mirror** (Round-2 F-DA-R2-4 cascade — same ordering bug fixed in Phase 4 and Phase 5a applies here).

- [ ] 5b.7 — Mirror modified file **after the bump**: `bash scripts/mirror-skill.sh update-zskills`. Verify parity via `diff -r skills/update-zskills .claude/skills/update-zskills` (empty).

- [ ] 5b.8 — Append `CHANGELOG.md` entry under today's date heading (create the date heading if absent), per the §1.8 canonical template (refine-plan F-R19).

- [ ] 5b.9 — Commit message: `feat(update-zskills): per-skill + repo-level version delta in install/update/audit reports`.

### Design & Constraints

**`zskills_version` is consumer-side, not source-side.** The source repo's `git tag --list` IS the truth.

**JSON parsing without jq.** The mirror-into-config step uses `json-set-string-field.sh` (Phase 5a.6) — no jq.

**Block-diagram add-ons in the report.** Show them when `--with-block-diagram-addons` was passed OR when any block-diagram skill is present in `.claude/skills/`. Otherwise omit.

**Failure mode: source clone has no tags.** `resolve-repo-version.sh` outputs empty string. Audit gap report shows `Repo version: (unversioned) — source clone has no tags`. Surface-bug rule.

**Failure mode: installed has no `zskills_version` field (pre-Phase-5 install).** First post-Phase-5 invocation finds the field absent; the tag-mirror step writes it.

**Failure mode: per-skill version regression (downgrade).** Source `2026.04.20+xxx`, installed `2026.04.30+yyy`. Delta script emits `bumped` for any non-equal pair regardless of direction; report prints `→` and lets the consumer notice.

### Acceptance Criteria

- [ ] `skills/update-zskills/SKILL.md` Step 6 (audit gap report) contains a `Repo version:` line.
- [ ] `skills/update-zskills/SKILL.md` Update final report references `metadata.version`: `grep -c 'metadata.version' skills/update-zskills/SKILL.md` returns ≥ 2.
- [ ] `bash tests/test-update-zskills-version-surface.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0.
- [ ] **Rerender output AND its written file are both version-data-free** (refine-plan F-DA-17 strengthening — the prior AC was trivially satisfied because `--rerender` writes only `.claude/rules/zskills/managed.md` from `CLAUDE_TEMPLATE.md`, and neither file ever had version data; the AC needs CONTRAST to verify the boundary is intentional):
  - Run `bash scripts/update-zskills.sh --rerender 2>&1 | tee /tmp/rerender-capture`; assert `grep -E 'Repo version|metadata.version' /tmp/rerender-capture` returns 0 matches.
  - Run `cat .claude/rules/zskills/managed.md`; assert `grep -E 'Repo version|metadata.version'` returns 0 matches there too.
  - Then run `bash scripts/update-zskills.sh` (without `--rerender`) against an installed-state fixture; assert its output DOES contain at least one `metadata.version` reference (Phase 5b.1 Sites B/C). The contrast between "rerender silent" and "install/update populated" is what verifies the boundary is real, not just incidentally absent.
- [ ] `diff -r skills/update-zskills .claude/skills/update-zskills` is empty.
- [ ] `bash scripts/frontmatter-get.sh skills/update-zskills/SKILL.md metadata.version` returns a value > Phase 3 migration date.
- [ ] `bash tests/run-all.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0.
- [ ] `grep -c 'jq' skills/update-zskills/SKILL.md` returns 0.

### Dependencies

Phase 5a (data plumbing).

### Non-Goals

- Telemetry / metrics emission of version data.
- Changing `--rerender` (unrelated).

---

## Phase 6 — Verification: 4 canaries (missed bump, correct bump, parallel-worktree merge, revert)

### Goal

Prove the enforcement chain fires correctly. Four canaries cover the design prompt's required failure modes plus the hash-format-specific cases.

### Work Items

- [ ] 6.1 — Author `tests/test-skill-version-canary-missed-bump.sh`:
  - Setup: clone `/workspaces/zskills` into sandbox, replicate Phase-3-landed state. **Defensive sandbox guard (refine-plan F-R2-2 / F-DA-R2-6):** before any `git add` of synthetic artifacts, assert the canary is NOT operating against the live repo. Apply uniformly to canaries 6.1, 6.2, 6.3, 6.4 — all four materialize sandbox state and could in principle be mis-targeted if `$REPO_ROOT` shadows or misresolves.
    ```bash
    SANDBOX_REPO=$(mktemp -d)/zskills-clone
    git clone --quiet "$REPO_ROOT" "$SANDBOX_REPO"
    cd "$SANDBOX_REPO"
    # Hard-fail if we are still inside the live repo.
    case "$(realpath "$PWD")" in
      "$(realpath "$REPO_ROOT")"|"$(realpath "$REPO_ROOT")"/*)
        echo "FAIL: canary refusing to run inside live repo: $PWD" >&2
        exit 1 ;;
    esac
    ```
  - Action: edit a sandbox SKILL.md body, stage it, do NOT bump version.
  - Assertion 1 (Edit-time): run hook with synthetic input, assert stderr contains `WARN:` and `content changed`.
  - Assertion 2 (commit-time): stage, run `scripts/skill-version-stage-check.sh`, assert exit 1 and stderr contains `STOP:`.
  - Assertion 3 (CI gate): conformance test against sandbox state — passes regex but fails hash-freshness check (Phase 3.6 added the stale-hash check).
  - **Cleanliness-loop honest-clone case (refine-plan F-DA-14):** materialize a `__pycache__/` artifact under one sandbox skill dir, mirror what would happen if the dev had run briefing.py. Run conformance's `=== Skill-dir cleanliness ===` loop against the sandbox. Because the cleanliness check now scopes to `git ls-files` (refine-plan F-DA-4 fix), the materialized `__pycache__/` is NOT tracked, so cleanliness still passes — i.e., the canary tests the same thing CI would test, no false-green. Then `git add` the `__pycache__` directory and re-run cleanliness; the check MUST fail (artifact-tracking is a real regression). This is the contrast assertion — without it, the cleanliness gate could be silently subverted by future "fix" agents.
  - Cleanup.

- [ ] 6.2 — Author `tests/test-skill-version-canary-correct-bump.sh`:
  - Setup: same.
  - Action: edit body AND bump `metadata.version` to `today+freshhash`.
  - Assertion 1 (Edit-time): NO `WARN:` matching version-bump-missing pattern.
  - Assertion 2 (commit-time): stage-check exits 0.
  - Assertion 3 (CI gate): conformance passes.
  - Cleanup.

- [ ] 6.3 — Author `tests/test-skill-version-canary-parallel-merge.sh` — covers Round-1 F-DA2 explicitly:
  - Setup: two sandbox clones from same base.
  - Action: Worktree A edits body adding "edit from A", computes fresh hash `aaa111`, bumps to `2026.04.30+aaa111`, commits. Worktree B edits body adding "edit from B" (non-overlapping line range), computes `bbb222`, bumps to `2026.04.30+bbb222`, commits.
  - Replay: cherry-pick A onto fresh branch, then cherry-pick B onto it.
  - Assertion 1 (version-line conflict): cherry-picking B produces a CONFLICT on the version line (A is `+aaa111`, B is `+bbb222`, conflict markers around the version line). **This is the load-bearing assertion.** Pure CalVer would NOT produce this conflict because both versions would textually equal `2026.04.30`.
  - Assertion 2 (resolution): resolve by keeping both body edits; recompute hash to `ccc333`; bump version to `2026.04.30+ccc333` (date stays today; hash captures the merged content).
  - Assertion 3 (post-merge state): conformance test passes; stored hash matches recomputed projection.
  - Assertion 4: the merge resolution requires the agent to recompute the hash and rebump — this is the correct intent (the merged content is a new state).
  - Cleanup.

- [ ] 6.4 — Author `tests/test-skill-version-canary-revert.sh` — covers §1.3 revert/no-op failure mode and §1.1 multi-edit-day handling (was F-DA1):
  - Setup: sandbox.
  - **Multi-edit-day sub-case:** edit A on date D, bump to `D+aaa`. Land. Then edit B on same date D, bump to `D+bbb` (different hash because content differs). Hook predicates: `on_disk_ver != head_ver` (asymmetric warn at Phase 4.1 lines 703-714 skipped) AND `cur_hash != head_hash` (symmetric warn skipped); both fall through; hook exits 0 with no stderr. Stage-check exits 0. **This is the F-DA1 closure.** (refine-plan F-R20: cite the underlying hook conditions so the implementing agent can cross-check against Phase 4.1 directly.)
  - **Revert/no-op sub-case:** edit body, bump version, revert body change leaving version bumped. Hook emits `WARN:` matching `version bumped but content unchanged`. Stage-check exits 1.

- [ ] 6.5 — Register all 4 canaries in `tests/run-all.sh`: `grep -c 'test-skill-version-canary' tests/run-all.sh` returns 4.

- [ ] 6.6 — Run the full suite end-to-end. All Phase 1-5b changes plus all 4 canaries must pass.

- [ ] 6.7 — `/verify-changes` end-to-end review:
  - Cumulative diff stat across all 6 phases (one SKILL.md frontmatter addition per source skill — count derived from Phase 3.2 enumeration, refine time = `$CORE_COUNT + $ADDON_COUNT`; **7 new helper scripts** (`scripts/{frontmatter-get,frontmatter-set,skill-content-hash,skill-version-stage-check}.sh` + `skills/update-zskills/scripts/{resolve-repo-version,skill-version-delta,json-set-string-field}.sh`); **10 new tests** (6 non-canary: `test-frontmatter-helpers.sh`, `test-skill-content-hash.sh`, `test-skill-version-enforcement.sh`, `test-json-set-string-field.sh`, `test-skill-version-delta.sh`, `test-update-zskills-version-surface.sh` + 4 canaries from Phase 6); 1 hook extension; 1 commit-skill extension; 1 update-zskills overhaul; 1 briefing tweak; 2 schema updates; plan + reference docs. (refine-plan F-R2-4: prior "6 new scripts, 6 new tests" undercounted; recounted from work items.)
  - **Rebase-clean preflight (carryover from F-DA5).** Before final landing, re-run the Phase 5a.0 file-path-grep preflight (`gh pr list --state open --limit 100 --json number,title,files` piped through `grep -F 'skills/update-zskills/'`). Abort if any open PR has appeared since Phase 5a. Do NOT use the un-supported `gh pr list --search 'in:files ...'` form (refine-plan F-DA-7).
  - Scope assessment: stay within stated phase contracts.
  - Full test suite run captured to `.test-results.txt`.
  - Manual smoke: helpers, mirror parity, conformance, all 4 canaries.

- [ ] 6.8 — Mark plan `status: complete` in frontmatter; move plan from active to complete in `plans/PLAN_INDEX.md`.

- [ ] 6.9 — Final commit: `feat(versioning): canary suite for skill metadata.version enforcement (missed/correct/parallel/revert) + verification`.

### Design & Constraints

**Canaries run in sandbox dirs, never against the live repo.** Each canary creates its own `$TEST_OUT/canary-<name>-sandbox/`.

**Hook invocation in tests.** Hook reads from stdin; tests feed synthetic JSON matching Claude Code hook input format. Canonical envelope from `warn-config-drift.sh:31-33`.

**Phase 5 commit-stage logic.** Already extracted to `scripts/skill-version-stage-check.sh` in Phase 4.3. Canaries invoke the script directly.

**Parallel-worktree canary correctness.** The version line being DIFFERENT across both edits (because hashes differ) is the load-bearing property. If a future change reverts to pure CalVer, the canary's "version-line conflict on cherry-pick" assertion fails — caught loudly.

**Surface-bug rule.** If any canary fails, it's a real signal. Do NOT weaken.

### Acceptance Criteria

- [ ] All 4 canary scripts exist, are executable, pass: `for c in missed-bump correct-bump parallel-merge revert; do test -x tests/test-skill-version-canary-$c.sh && bash tests/test-skill-version-canary-$c.sh; done`.
- [ ] `grep -c 'test-skill-version-canary' tests/run-all.sh` returns exactly 4.
- [ ] `bash tests/run-all.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0 with all canaries passing.
- [ ] **Manual recipe (deterministic, captured to log file):** `cd /tmp/zskills-clone; edit skills/run-plan/SKILL.md body; git add skills/run-plan/SKILL.md; bash $REPO/hooks/warn-config-drift.sh < /tmp/synthetic-edit-event.json 2>&1 | grep -q 'WARN'`. (Round-1 finding F-R12: deterministic command + expected output, not "verified during /verify-changes" judgment.)
- [ ] `grep -q '^status: complete' plans/SKILL_VERSIONING.md` post-landing.
- [ ] `grep -q 'SKILL_VERSIONING' plans/PLAN_INDEX.md` shows it under the Complete section.
- [ ] No skill in `skills/` or `block-diagram/` has a missing or malformed `metadata.version`.
- [ ] `git log --oneline -10 | head` shows ≤ 7 phase commits (one per phase: 1, 2, 3, 4, 5a, 5b, 6).

### Dependencies

Phases 1, 2, 3, 4, 5a, 5b.

### Non-Goals

- Cross-version migration tooling. Out of scope.
- Plugin distribution canaries (separate `/draft-plan`).
- Performance benchmarking (single-skill hash computation < 50ms — well under hook budget).

---

## Plan Quality

**Drafting process:** `/draft-plan` with 3 rounds of adversarial review (Reviewer + Devil's Advocate dispatched in parallel; Refiner with verify-before-fix discipline). Budget was 4 rounds; converged at Round 3.
**Convergence:** Converged at Round 3 — orchestrator-judged. Refiner's disposition table for Round 3 reported 7 Fixed / 0 Justified / 0 Deferred; spot-check verified all 7 fixes landed in v4 with no new contradictions introduced.
**Remaining concerns:** None blocking execution. The trade-off taken (CalVer+hash adds machinery vs. pure CalVer's correctness gaps) is documented in §1.1 Trade-offs. The hash collision boundary (~4096 distinct content states per skill) is documented as sufficient at zskills' scale; widening to 8 hex chars if a collision is observed is mechanical.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | After Dedup | Resolved |
|-------|-------------------|---------------------------|-------------|----------|
| 1     | 15 (1 CRIT, 5 HI, 6 MED, 3 LOW) | 12 (3 CRIT, 5 HI, 3 MED, 1 LOW) | 25 unique | 24 Fixed, 1 Justified |
| 2     | 10 (1 CRIT, 2 HI, 4 MED, 3 LOW) | 11 (1 CRIT, 5 HI, 4 MED, 1 LOW) | 21 unique | 21 Fixed |
| 3     | 4  (0 CRIT, 2 HI, 0 MED, 2 LOW) | 5  (0 CRIT, 2 HI, 1 MED, 2 LOW) | 7 unique  | 7 Fixed |
| Total | 29                | 28                        | 53 unique   | 52 Fixed, 1 Justified |

### Major design pivots forced by adversarial review

- **Round 1 → Round 2:** Pure `YYYY.MM.DD` (CalVer) → `YYYY.MM.DD+HHHHHH` (date + 6-char content hash). Forced by F-DA1 (multi-edit-day rule contradicted Phase 4 hook implementation) and F-DA2 (parallel-worktree clean-apply silently lost edits). Pure CalVer cannot detect either.
- **Round 2 → Round 3:** Hash projection scope made consistent across 6 contradicting plan sites (most damning Round 2 finding); projection rewritten as **deny-list of one** ("every regular file under `<skill-dir>/`" excluding `SKILL.md`) instead of allow-list of named subdirectories — the allow-list silently missed `skills/update-zskills/stubs/`.
- **Round 3 (final):** Phase 3.3 rewritten as **two-pass migration** to resolve the chicken-and-egg between the byte-level redaction rule (which requires a `metadata:` parent line) and pre-migration state (no SKILL.md has a `metadata:` block yet). Phase 5a.11.5 added because the new deny-list rule means script additions in 5a require an `update-zskills` bump (one bump per content state, not one per landing). `find -type f` enumeration tightened with explicit dotfile/artifact exclusions.

### Round-by-round detail

This plan went through **three rounds** of `/draft-plan` adversarial review. Round 1 produced 25 unique findings (4 CRITICAL, 9 HIGH, 9 MEDIUM, 3 LOW) across a Reviewer pass and a Devil's-Advocate pass. Round 2 produced 21 unique findings (1 CRITICAL — the hash-projection-scope contradiction; 6 HIGH; 6 MEDIUM; 3 LOW), most surfacing follow-on bugs introduced by Round-1's pivot to the CalVer+hash format. Round 3 produced 7 unique findings (0 CRITICAL, 3 HIGH, 1 MEDIUM, 3 LOW), all surfacing follow-on bugs introduced by Round-2's tightening (deny-list strengthening + byte-level redaction made migration's chicken-and-egg explicit; `find -type f` exposed dotfile risk).

**Round-3 most load-bearing changes:**

- **Phase 3.3 rewritten as a two-pass migration** (R3-HIGH F-R3-2 / F-DA-R3-1). Pre-migration NO SKILL.md has a `metadata:` block, so the §1.1 byte-level redaction rule cannot fire pre-bump — pre/post projections differed by ~2 lines, breaking the "stable across before/after" claim and failing conformance on every skill. Pass 1 inserts a uniform `metadata.version: "PLACEHOLDER+PLACEHOLDER"` (no hash needed). Pass 2 computes the hash on the now-metadata-bearing projection and overwrites the version line. Because the redaction maps both placeholder and final values to `<REDACTED>`, the projections at end-of-pass-1 and after-pass-2-write are byte-identical — the hash is a fixed point.
- **Phase 5a.11.5 added** — bump `update-zskills/SKILL.md` after the script additions in 5a (R3-HIGH F-R3-1 / F-DA-R3-2-pair). Per §1.1's deny-list rule, every regular file under the skill dir is in the projection; adding three new scripts and modifying one changes the projection hash. Without this bump, the Phase 4 `/commit` gate would block the 5a commit. 5b.6 then re-bumps after body edits — two bumps, one per content state.
- **`find` enumeration tightened** (R3-HIGH F-DA-R3-2): `! -name '.*' ! -path '*/__pycache__/*' ! -path '*/node_modules/*'` excludes editor artifacts, `.DS_Store`, etc., from the projection. Phase 3.6 also adds a "Skill-dir cleanliness" CI section asserting no dotfiles/artifacts in skill dirs (defense in depth). Phase 2.5 adds a fixture that proves dotfile invariance.
- **Conformance mirror-only allow-list hardcoded** (R3-MEDIUM F-DA-R3-3): `MIRROR_ONLY_OK="playwright-cli social-seo"`. Other source-less mirrors fail (orphaned-cleanup signal). Each entry has a one-line justification.
- **Phase 5a `### Design & Constraints` added** (R3-LOW F-R3-3): documents the `--rerender` exclusion, the inline-BASH_REMATCH JSON-read convention (vs YAML helpers), the PR-preflight rationale, and the two-bump cadence on `update-zskills`.
- **Overview line 17 + Phase 2.3 sha256 line both reconciled with `LC_ALL=C`** (R3-LOW F-R3-4 + R3-LOW F-DA-R3-5): line 17 now carries the prefix; Phase 2.3 makes the helper script `export LC_ALL=C` script-wide as the first executable line, removing per-command-prefix ambiguity for the redaction subroutine.
- **Block-scalar awareness in redaction explicitly cited** (R3-LOW F-DA-R3-4): Phase 2.3 step 1 cites Phase 2.1's block-scalar-aware traversal so a `description-extra: >-` continuation line containing literal `version: "X"` text is NOT rewritten. Phase 2.5 fixture proves it.

**Round-2 most load-bearing changes:**

- **Hash projection scope made consistent across §1.1, §1.3, §1.10, Overview, Phase 2.3, and CLAUDE.md prose** (R2-CRITICAL F-R2-1 / F-DA-R2-1). Six plan lines previously contradicted on whether the redacted-frontmatter snapshot was IN the projection or excluded entirely. Resolution: **include**, because that is the only choice consistent with §1.3's promise that editing `description:` requires a bump. Excluding would silently break the rule.
- **Projection scope rewritten as deny-list of one (`SKILL.md`), not allow-list of named subdirectories** (F-DA-R2-2). Allow-list of `modes/, references/, scripts/, fixtures/` silently missed `skills/update-zskills/stubs/`. Deny-list captures every regular file under the skill directory automatically.
- **Hash determinism specified across locales** (F-R2-3): `LC_ALL=C` prepended to `find`, `sort`, `awk`, `sed`, `sha256sum` everywhere. Binary fixtures rejected by Phase 2.3 with explicit error.
- **Redaction-line redaction rule given byte-level spec** (F-DA-R2-6): preserve original leading whitespace; replace content only.
- **Phase 4 and Phase 5a/5b ordering swapped — bump precedes mirror** (F-DA-R2-4). Prior order produced an immediately-stale mirror that fails the AC `diff -r skills/<name> .claude/skills/<name>` is empty. Both Phase 4 (4.9 ↔ 4.10) AND Phase 5a (5a.11 ↔ 5a.12) AND Phase 5b (5b.6/7 sequence) re-ordered.
- **Hook regex prose-vs-pseudocode reconciled** (F-DA-R2-3): Branch 3's prose now correctly states a single regex with **no `\.md$` anchor** (so `scripts/*.sh`, `stubs/*.sh`, etc., all match — empirically verified `echo "skills/run-plan/scripts/correct-plan.sh" | grep -E '(^|/)(skills|block-diagram)/[^/]+/.*$'` matches, while the old `\.md$` form did not). Branch 2's `\.md$` widening is independent.
- **`grep -qx` → `grep -Fqx`** at both sites (F-DA-R2-5): paths can contain regex metacharacters; fixed-string match is correct.
- **`$FILE_PATH` → `$FILE_PATH_REL`** in §1.4 prose (F-R2-6) — matches Phase 4.1 pseudocode.
- **Sha256 cut form canonicalized** (F-R2-4 / F-DA-R2-7): `sha256sum | cut -d' ' -f1 | head -c 6` everywhere (Overview, §1.1, Phase 2.3, reference doc).
- **§1.8 cross-references corrected** (F-R2-2 / F-DA-R2-8): "3.7, 4.9, 5b.13" → "3.7, 4.11, 5a.13, 5b.8" — matches actual phase numbering after Phase 5 split.
- **Conformance test extended to walk `.claude/skills/`** (F-R2-7): the prior "Triple-covered" claim only had double coverage. New third loop iterates mirror dirs and asserts mirrored hash equals source projection. Handles mirror-only skills (`playwright-cli`, `social-seo`) as `skipped` passes per §1.6.
- **`grep '^  version:'` ACs replaced with `frontmatter-get.sh metadata.version`** per-file (F-R2-8) — indentation-grep doesn't verify parent is `metadata:`.
- **Hash collision budget documented** (F-R2-9 / F-DA-R2-10): 6 hex = ~4096-state birthday boundary per skill; sufficient at zskills' scale; widening to 8 if a collision is observed is mechanical.
- **Hash human-noise trade-off documented** (F-DA-R2-9 — DateLean-discipline): hash is machine-distinguishing, not human-distinguishing; downstream report formatters de-emphasize.
- **`2>/dev/null` audit truthfully enumerated** (F-R2-5): two retained sites (staged-file gate + `git show`); both have empty-output-as-signal justification; full audit count documented.
- **Phase 1.4 ("Mirror nothing") deleted as no-op work item** (F-DA-R2-11) — moved to Non-Goals.
- **Phase 6.7 ("Update tests/run-all.sh expected total count") deleted** (F-R2-10) — placeholder with no concrete change.

**Round-1 most load-bearing changes (preserved):**

- **Format choice changed from pure `YYYY.MM.DD` to `YYYY.MM.DD+HHHHHH` (date + 6-char content hash)** in response to F-DA1 (multi-edit-day rule contradicted hook implementation) and F-DA2 (parallel-worktree clean-apply silently lost edits). The hash deterministically distinguishes content states; both failure modes resolve cleanly. Cascade through §1.1 trade-offs, Phase 2.3 (new helper script), Phase 3.3 (per-skill hash computation in migration), Phase 4.1 / 4.3 (hash-comparison enforcement), Phase 6.3 / 6.4 (canaries verify hash-format-specific failure modes).
- **Skill counts corrected from 29 (25+4) to 28 (25+3)** since `block-diagram/screenshots/` holds image assets only, no SKILL.md (F-R1 verified). Threaded through Phase 3 enumeration filter, conformance counts, prose, ACs.
- **Phase 5 split into 5a (plumbing) + 5b (UI surface)** to address F-R9 (single-phase scope overflow). Each commit stays scope-bounded.
- **Hook insertion site corrected from "Phase 4 step 3.5" to "Phase 5 step 2.5"** (between run-tests and dispatch-reviewer) per F-R2 verified against `skills/commit/SKILL.md`.
- **Hook regex widened to cover `block-diagram/`** (F-R4) and **child files** (`modes/`, `references/`, `scripts/`, `fixtures/`); subject disambiguation between body-diff-subject and version-check-subject (F-DA8); staged-file gate folded into Phase 4.1 (F-DA7, anti-noise).
- **Regex tightened to validate month/day ranges** (F-DA11): `^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$`.
- **Block-scalar handling specified** in Phase 2 (F-DA4) — read passes through, write returns exit 3.
- **Markdown-comment carve-out dropped** (F-DA10) — the hash naturally captures comments, no judgment-class rule needed.
- **`2>/dev/null` audit** (F-DA9) — retained only where empty-output is the intended signal; helper-call sites use the helpers' own exit codes.
- **`/update-zskills` PR preflight added** as Phase 5a.0 (F-DA5).
- **CHANGELOG canonical template** defined in §1.8 (F-DA12) and cited from 3.7, 4.11, 5a.13, 5b.8.
- **Mirror-only skills (`playwright-cli`, `social-seo`) marked out of scope** for migration (F-R6).

The trade-off taken: the hash adds machinery (a new helper script, a canonicalization rule, an additional CI check) in exchange for closing two CRITICAL failure modes that pure CalVer could not. Migrating CalVer+hash → SemVer (if plugin distribution lands) is a one-time mechanical bump, costing less than living with the failure modes now.

---

## Drift Log — Round 1 (refine-plan)

The plan was drafted 2026-04-30. /refine-plan ran 2026-05-02. Between those two dates, eight PRs landed on `main`:

| PR # | Subject | Impact on this plan |
|------|---------|---------------------|
| #159 | `pr-landing-unification` extract `/land-pr` from 5 duplicating skills | **CORE_COUNT drift 25 → 26.** Added `skills/land-pr/` directory. Phase 3.2 sanity gate (`test "$CORE_COUNT" = "25"`) would hard-fail today — re-anchored as a lower-bound assertion. Threaded through Overview, Phase 3 prose, Phase 3.6 expected counts, Phase 3 ACs, Phase 5a.5 delta-script enumeration (now also iterates block-diagram/), Phase 6.7 cumulative diff stat. |
| #160 | `/land-pr` validation phase | Lands inside `skills/land-pr/` — counted in #159's drift. |
| #161-#166 | `pr-landing-unification` migration phases | Re-wires `/run-plan`, `/commit pr`, `/do pr`, `/fix-issues pr`, `/quickfix` to call `/land-pr`. Source content of those 5 skills changed but no count/path changes. Phase 3 enumeration picks them up automatically. |
| #167 | `chore(devcontainer): track .playwright/cli.config.json` | Outside skill dirs; no impact. |
| #168 | `fix(dashboard): make modal dismissable + absorb dashboard config block` | No skill-tree shape change. Re-shuffled `skills/zskills-dashboard/` content but path counts unchanged. |
| #169 | `fix(skills): add Agent-tool-required preflight to 5 multi-agent skills` | Added `## Preflight` block to `refine-plan`, `draft-plan`, `draft-tests`, `research-and-plan`, `research-and-go`. Phase 3.3's pass-2 hash captures the preflight content automatically — no plan change required. Surfaced explicitly so a future refiner doesn't think "did the plan know about #169?" |
| #170 | `fix(tests): materialize temp worktree so worktree-portable case runs in CI` | Test-only; no plan impact. |
| #171 | `fix(dashboard): move config migration to /update-zskills + schema` | **TWO impacts.** (a) Added `dashboard.work_on_plans_trigger` field to `config/zskills-config.schema.json`. Phase 5a.3 must add `zskills_version` as a sibling top-level field WITHOUT touching `dashboard` block — added explicit AC and prose guard. (b) Added Step 3.6 "Backfill dashboard.work_on_plans_trigger if absent" to `skills/update-zskills/SKILL.md` at line 286. Shifted everything below by ~30 lines: Step 6 (gap report) is now at 559 (was ~542), Step G (final report) at 1221 (was ~1202), the `Updated: N skills` line at 1283 (was ~1260). Phase 5b.1 line citations (Sites A/B/C) re-anchored to text instead of line numbers. |
| #172 | `docs(sprint)` record of 169/170/171 | No code; no impact. |

### Skill-count drift consolidated

The literal counts "25 core", "28 total", "25 + 3 = 28" were correct at plan-write (2026-04-30) and stale at refine-time (2026-05-02). Plan strategy: replace literals with derivation-driven enumeration where feasible; where a literal must remain, anchor it to the migration-time `$CORE_COUNT + $ADDON_COUNT` expression. **Sites patched** (in remaining phases — historical Round-2/3 narrative left intact since it's a historical record):

- Overview line 9 — count phrasing replaced with "every source skill under skills/" + a parenthetical noting the live count is derivation-driven
- Progress Tracker row for Phase 3
- §1.6 Mirror-only skills prose (count-free phrasing)
- §1.7 Block-diagram add-ons prose (parenthetical noting current vs draft-time count)
- §1.8 Per-skill CHANGELOG rejection rationale ("~30 files")
- §1.9 Migration prose
- Hash collision budget (current fleet: ~30 skills)
- Phase 3 heading + Goal
- Phase 3.2 sanity gate (now lower-bound + structural assertion, NOT equality)
- Phase 3.6 expected pass counts (re-anchored to `$CORE_COUNT + $ADDON_COUNT`)
- Phase 3.7 CHANGELOG body
- Phase 3.8 commit message
- Phase 3 atomicity prose
- Phase 3 ACs (count check, conformance pass count, "all 28 skills")
- Phase 5a AC for `skill-version-delta.sh` line count (now `>= $CORE_COUNT + $ADDON_COUNT`)
- Phase 6.7 cumulative diff stat

### Line-number drift in `skills/update-zskills/SKILL.md`

PR #171 added ~30 lines at line 286 of `update-zskills/SKILL.md`. All Phase 5b.1 line citations re-anchored to **heading text** rather than line numbers (defense against future drift):

- Site A: was "Step 6, lines ~542-595" → now "`### Step 6 — Produce the gap report`; locate via `grep -n`"
- Site B: was "lines ~1202-1218" → now "`#### Step G — Final report`; locate via `grep -n`"
- Site C: was "lines ~1260-1269" → now "`Updated: N skills` line inside `### Pull Latest and Update`'s step `6. Report:`; locate via `grep -n`"

Phase 4.4 (commit-skill insertion site) anchored similarly — by `## Phase 5 — Commit` heading text rather than the existing `line 239` cite.

### Pre-existing-state surprises discovered

- **`__pycache__` contamination in working tree.** `skills/briefing/scripts/__pycache__/` and `skills/zskills-dashboard/scripts/zskills_monitor/__pycache__/` exist as untracked artifacts whenever briefing.py or the zskills_monitor server runs. The original Phase 3.6 cleanliness loop used `find` to assert no dotfiles/artifacts under skill dirs — would hard-fail on day-zero migration. Cleanliness loop now scoped to `git ls-files` so the working-tree noise doesn't trip the gate; tracked artifacts (a real regression) still fail loudly. Phase 6.1 canary now MATERIALIZES a `__pycache__/` artifact in its sandbox to assert the working-tree variant still passes (no false-green from sandbox cloning) AND `git add`-ing the artifact triggers a fail (regression detection).
- **`.gitkeep` is git-tracked AND empty.** `skills/zskills-dashboard/scripts/zskills_monitor/static/.gitkeep` is intentionally tracked. Phase 2.3's `file --mime ... charset=binary` rejection rule would trip on it because `file --mime` reports `inode/x-empty; charset=binary` for any zero-byte file. Phase 2.3 now guards with `[ -s "$f" ]` — empty files pass through (treated as zero-byte text, no projection effect). Phase 3.6 cleanliness loop allow-lists `.gitkeep` explicitly (universal Unix idiom for tracking empty directories).
- **`gh pr list --search 'in:files ...'` does not work.** The `in:files` qualifier is a `gh search prs` qualifier, not a `gh pr list --search` qualifier. The original Phase 5a.0 preflight silently returned empty regardless of actual PR state (false-green). Re-written to use `gh pr list --json files` + post-filter via `grep -F`.
- **PR #169 preflight blocks in 5 multi-agent skills.** Mirror parity verified clean (no diff between `skills/<name>/SKILL.md` and `.claude/skills/<name>/SKILL.md` for any of the 5). Phase 3.3 pass-2 hash captures the preflight content automatically; subsequent edits will trip the normal bump rule. No code change needed; documented here for future refiners.

---

## Plan Review — Round 1 (refine-plan)

| Finding | Severity | Disposition | Rationale | Verification outcome |
|---------|----------|-------------|-----------|----------------------|
| F-R1 | CRIT | Fixed | Skill-count drift consolidated. Sites patched: Overview line 9, Progress Tracker phase 3, §1.6, §1.7, §1.8, §1.9, hash collision budget prose, Phase 3 heading, Phase 3 Goal, Phase 3.2 sanity gate (now lower-bound + structural, not equality), Phase 3.6 expected counts, Phase 3.7 CHANGELOG body, Phase 3.8 commit-msg, atomicity prose, Phase 3 ACs (×3), Phase 5a delta-script AC, Phase 6.7 cumulative diff. Round History narrative left intact as historical record. | Verified — `find skills -maxdepth 1 -mindepth 1 -type d -exec test -f '{}/SKILL.md' \; -print \| wc -l` returns 26; PR #159 (`skills/land-pr/`) confirmed via `git log --oneline`. |
| F-R2 | HIGH | Fixed (consolidates with F-R1) | Phase 3.2 sanity gate replaced with structural lower-bound + log; downstream assertions now reference `$CORE_COUNT + $ADDON_COUNT` derivation, not literal "28". | Verified — same enumeration command. |
| F-R3 | HIGH | Fixed | Site A line citation re-anchored to `### Step 6 — Produce the gap report` heading text. | Verified — `grep -n '### Step 6' skills/update-zskills/SKILL.md` → 559 (was ~542 in plan; PR #171 shifted). |
| F-R4 | MED | Fixed | Site B line citation re-anchored to `#### Step G — Final report` heading text. | Verified — `grep -n '#### Step G' skills/update-zskills/SKILL.md` → 1221 (was ~1202 in plan). |
| F-R5 | MED | Fixed | Site C line citation re-anchored to `Updated: N skills` text + `### Pull Latest and Update` heading. | Verified — `grep -n 'Updated: N skills' skills/update-zskills/SKILL.md` → 1283 (was ~1260 in plan). |
| F-R6 | LOW | Justified | PR #171's Step 3.5/3.6 are nested inside Step 0.5 (config-write path), not in the audit/install/update report sites that Phase 5b touches; no plan-text collision. Drift Log notes the schema-survival concern (now also covered by F-R9 fix). | Verified — `grep -n '3\.5\|3\.6' skills/update-zskills/SKILL.md` confirms 275/286 nested under Step 0.5 (line 213). |
| F-R7 | LOW | Justified | PR #169 preflight blocks in 5 multi-agent skills are part of HEAD content; Phase 3.3 pass-2 hash captures automatically; subsequent edits trip the normal bump. Drift Log notes for future refiners. | Verified — preflight present in all 5 skills at the cited lines; mirror parity diff -q clean. |
| F-R8 | LOW | Fixed | Phase 1.3 reworded as idempotent verify ("if absent for any reason, add a row matching the existing format; do NOT add a second row"). | Verified — `grep -n 'SKILL_VERSIONING' plans/PLAN_INDEX.md` returns existing row at line 17/18. |
| F-R9 | MED | Fixed | Phase 5a.3 prose explicitly forbids touching `dashboard`, `commit`, `execution`, `testing`, `dev_server`, `ui`, `ci` blocks; new AC asserts `work_on_plans_trigger` survives AND `zskills_version` is added. | Verified — `grep -n work_on_plans_trigger config/zskills-config.schema.json` returns line 150 (PR #171). |
| F-R10 | MED | Fixed | Hook FILE_PATH normalization upgraded to `realpath --relative-to` with string-strip fallback that asserts no leading slash. Phase 4.6 tests extended with absolute-path and relative-path cases (12 hook cases total, AC raised to ≥ 20 passes). | Verified — bash semantics for `${var#prefix}` confirm the documented edge cases. |
| F-R11 | LOW | Fixed | §1.6 prose rewritten count-free ("two skills live ONLY in `.claude/skills/` ... every other entry has a `skills/<name>/` source counterpart"). | Verified — `comm -23 <(ls .claude/skills/ \| sort) <(ls skills/ \| sort)` → playwright-cli, social-seo. |
| F-R12 | LOW | Justified | "≤ 7 phase commits" in Phase 6 ACs is achievable per current phase plan (5a.11 + 5a.11.5 land in same 5a commit; 4.9-4.11 in same Phase 4 commit). The reviewer's softening suggestion ("each phase lands as a single commit; fix-up commits acceptable if folded in") is a reasonable refinement but not load-bearing — the existing AC reads "≤ 7" not "= 7", so a fix-up commit just nudges the count without breaking the AC. No edit. | Judgment — no verifiable anchor (future state). |
| F-R13 | HIGH | Fixed | Phase 5a.5 `skill-version-delta.sh` loop extended to iterate both `skills/*/` and `block-diagram/*/`; output now includes a `kind` (core/addon) column; renderer-side filter on `--with-block-diagram-addons` documented. Phase 5a.8 test fixtures extended with add-on cases. | Verified — Phase 5a.5 pseudocode reading; §1.7 parity promise. |
| F-R14 | LOW | Fixed | Phase 4.8 prose explicitly scopes the deny-list to skill content only (`skills/<name>/**` and `block-diagram/<name>/**`); plan, references, CHANGELOG out of scope. Verifier instructed to read `tests/test-skill-conformance.sh` to confirm scoping BEFORE updating `forbidden-literals.txt`. | Verified — plan file embeds many `2026.04.30+xxxxxx` examples; broad scoping would self-fire. |
| F-R15 | LOW | Fixed | `resolve-repo-version.sh` comment cites `RELEASING.md:44-46` and notes regex must update with release scheme. | Verified — `git tag --list` → `2026.04.0`; RELEASING.md:44-46 documents zero-indexed `YYYY.MM.N`. |
| F-R16 | LOW | Justified | Phase 5a.0 preflight already targets `skills/update-zskills/`, not `skills/commit/` (Phase 4's surface). Sequential phase landing means by the time 5a.0 runs, Phase 4's PR is merged. Reviewer's suggestion is a documentation nicety; no functional fix needed. The 5a.0 prose was already substantially rewritten by F-DA-7 fix; further nuance can wait. | Judgment — no verifiable anchor; sequential ordering verified by phase dependency graph. |
| F-R17 | LOW | Justified | `grep -c 'test-skill-version-canary' tests/run-all.sh returns 4` is correctly scoped to the canary string only; other Phase 2/4/5a tests use different names. Reviewer concurs ("AC is correct; no change"). | Judgment — pattern is specific to canaries. |
| F-R18 | LOW | Justified | `! -name '.*'` filter is correct as defense-in-depth; `.landed` lives at WORKTREE root, never inside skill dirs. No code change. (Reviewer's suggestion to document this in §1.1 is documentation polish only.) | Verified — `find skills /workspaces/zskills/block-diagram -maxdepth 2 -name '.*' -type f` returns nothing. |
| F-R19 | LOW | Fixed | Phases 4.11, 5a.13, 5b.8 reworded to match Phase 3.7 verbatim ("Append CHANGELOG.md entry under today's date heading (create the date heading if absent), per the §1.8 canonical template"). | Judgment — text consistency. |
| F-R20 | MED | Fixed | Phase 6.4 multi-edit-day sub-case now cites the underlying Phase 4.1 hook predicates (`on_disk_ver != head_ver` AND `cur_hash != head_hash` → both fall through). | Verified — Phase 4.1 lines 703-714 walked manually. |
| F-R21 | LOW | Justified | Naming hygiene only; "2.5" sub-step style matches existing `update-zskills` precedent (3.5/3.6 in Step 0.5). No code change. | Judgment. |
| F-DA-1 | CRIT | Fixed (consolidates with F-R1) | Phase 3.2 hardcoded `test "$CORE_COUNT" = "25"` replaced with structural lower-bound assertion + log; AC at line 601 (now 715-ish post-edit) re-anchored similarly. | Verified — `find skills ... \| wc -l` → 26. |
| F-DA-2 | CRIT | Fixed (consolidates with F-R1) | "28 total" / "25 + 3" / "28 PASS" hardcoded literals replaced with derivation-driven references throughout remaining phases; original Round-2/3 narrative left intact as historical record. | Verified — same as F-R1. |
| F-DA-3 | MED | Justified — evidence did not reproduce | Plan asserts briefing's "Z Skills Update Check" is at "lines 339-356"; DA claimed body at 343-360. Re-verification: heading at line 339, body 341-355, next section at 357 — plan's range INCLUDES the heading and IS correct. DA's "off by 2-4" claim does not reproduce. No edit needed. | Verified — `grep -n '^## Z Skills Update Check' skills/briefing/SKILL.md` → 339; `awk 'NR==339,NR==356'` shows complete section. |
| F-DA-4 | CRIT | Fixed | Phase 3.6 cleanliness loop scoped to `git ls-files` (tracked content only) — working-tree `__pycache__` no longer trips the gate; `.gitkeep` allow-listed explicitly. Conformance still detects real regressions (tracked dotfiles, tracked `__pycache__`/`node_modules`). | Verified — `find skills -name '__pycache__' -type d` → 2 hits (briefing, zskills-dashboard); `git ls-files skills/zskills-dashboard \| grep gitkeep` confirms `.gitkeep` is tracked. |
| F-DA-5 | HIGH | Fixed | Phase 2.3 `file --mime` rejection now guarded with `[ -s "$f" ]` — empty files pass through as zero-byte text. | Verified — `file --mime <empty>` → `inode/x-empty; charset=binary` (would false-positive without the size guard). |
| F-DA-6 | HIGH | Fixed (consolidates with F-R3, F-R4, F-R5) | Sites A/B/C re-anchored to heading text + `grep -n` recipes. | Verified — see F-R3/4/5. |
| F-DA-7 | MED | Fixed | Phase 5a.0 preflight rewritten to use `gh pr list --json files` + post-filter via `grep -F`; the broken `--search 'in:files ...'` form is gone. Phase 6.7 re-run preflight matched. Title-only fallback offered as informational sibling check. | Verified — empirical `gh pr list --search "in:files ..."` confirms no support; `gh search prs` is the supported path. |
| F-DA-8 | HIGH | Fixed | `json-set-string-field.sh` rewritten to use `awk` (metacharacter-clean) for both update and insert paths; preserves file mode via `chmod --reference`; verifier instructed to check `apply-preset.sh` for an existing factored helper BEFORE adding the new file. Phase 5a.7 test extended with `&` / `\1` / `|` / file-mode-preservation cases. | Verified — `man sed` confirms `&` and `\N` are sed-special; `man mktemp` confirms 0600 default. |
| F-DA-9 | LOW | Fixed (partial — DA over-claimed) | Branch 3 outer regex tightened from `(^|/)(skills\|block-diagram)/[^/]+/.*$` → `(^|/)(skills\|block-diagram)/([^/]+)/[^/]+` (requires at least one path segment after the skill name). Defensive, not load-bearing. **Re-verification: DA claimed `block-diagram/README.md` matches; it does NOT** — `[^/]+` requires the second segment to itself contain a slash, which `README.md` (no slash) doesn't. The screenshots case (`block-diagram/screenshots/foo.png`) DOES match both old and new — gracefully no-ops via downstream `[ -f "$skill_md" ]` check. | Verified — `echo "block-diagram/README.md" \| grep -E ...` → no match (DA was wrong on this); `echo "block-diagram/screenshots/foo.png" \| grep -E ...` → match (DA was right). Tightened regex anyway as defensive cleanup. |
| F-DA-10 | MED | Fixed (consolidates with F-R13) | Same fix as F-R13 — `skill-version-delta.sh` iterates both source roots; `kind` column added; renderer-filter documented. | Verified — same as F-R13. |
| F-DA-11 | MED | Fixed | Phase 3.3 fixed-point property block extended with explicit invariant: "between pass 1 and pass 2, NO other file under any `<skill-dir>/` may be modified." | Verified — `grep -n 'no child-file edits\|Invariant' plans/SKILL_VERSIONING.md` returns 0 before edit; the rule was missing. |
| F-DA-12 | LOW | Fixed (consolidates with F-R8) | Same as F-R8: Phase 1.3 reworded as idempotent verify. | Verified — see F-R8. |
| F-DA-13 | LOW | Fixed | Phase 4.4 insertion site re-anchored to `## Phase 5 — Commit` heading text via `awk` recipe; line-239 cite preserved as a refine-time data point but no longer load-bearing. | Verified — `grep -n '^## Phase 5' skills/commit/SKILL.md` → 239 today; matches plan. |
| F-DA-14 | HIGH | Fixed | Phase 6.1 canary now materializes a `__pycache__/` artifact in its sandbox AND tests both the untracked case (cleanliness should pass — same as F-DA-4 fix) AND the tracked case (cleanliness MUST fail). Tied pair with F-DA-4 — the cleanliness scoping change makes the canary honest. | Verified — `git ls-files skills/briefing \| grep -c __pycache__` → 0 confirms the artifact is untracked; sandbox-clone semantics walked through. |
| F-DA-15 | MED | Fixed (consolidates with F-R3, F-R4, F-R5, F-DA-6) | Phase 5a.0 preamble explicitly tells the implementing agent to "re-derive the actual line numbers / anchor text from current state — the file has shifted since plan-draft (PR #171, 2026-05-02 added ~30 lines)." Sites A/B/C anchored to heading text. | Verified — `git log --oneline -- skills/update-zskills/SKILL.md \| head -3` shows PR #171 as most recent. |
| F-DA-16 | MED | Fixed (consolidates with F-R10) | Same fix as F-R10: hook normalizes via `realpath --relative-to` with string-strip fallback; Phase 4.6 tests extended. | Verified — see F-R10. |
| F-DA-17 | LOW | Fixed | Phase 5b AC for `--rerender` strengthened: now asserts BOTH stdout AND `managed.md` are version-data-free, AND that running `update-zskills` (without `--rerender`) DOES populate version data. The contrast verifies the boundary is intentional. | Verified — `grep -nE 'Repo version\|metadata.version' CLAUDE_TEMPLATE.md` → 0 confirms the hollow-check criticism. |

**Summary**

- Total findings: 38 (21 reviewer + 17 DA)
- Fixed: 28
  - F-R1, F-R2, F-R3, F-R4, F-R5, F-R8, F-R9, F-R10, F-R11, F-R13, F-R14, F-R15, F-R19, F-R20, F-DA-1, F-DA-2, F-DA-4, F-DA-5, F-DA-6, F-DA-7, F-DA-8, F-DA-9, F-DA-10, F-DA-11, F-DA-12, F-DA-13, F-DA-14, F-DA-15, F-DA-16, F-DA-17 (counting consolidations: F-R1/F-DA-1/F-DA-2 are one logical fix at many sites, etc.; the disposition table marks consolidations explicitly)
- Justified: 9
  - F-R6 (PR #171 nested in Step 0.5; no collision)
  - F-R7 (PR #169 preflight; hash captures automatically)
  - F-R12 (≤ 7 phase commits achievable; reviewer's softening is polish)
  - F-R16 (Phase 4 vs 5a.0 preflight scope correct as written)
  - F-R17 (canary AC is well-scoped; no change)
  - F-R18 (`! -name '.*'` filter is defense-in-depth; correct)
  - F-R21 (naming hygiene only; matches precedent)
  - F-DA-3 (evidence did NOT reproduce — briefing line 339 is correct in plan; DA was wrong)
  - F-DA-9 partly justified (DA's `block-diagram/README.md` claim does not reproduce; regex tightened anyway as defensive cleanup, so net Fixed — but DA was over-claiming on the README case)

Round 1 disposition complete. Convergence is the orchestrator's call.

---

## Drift Log — Round 2 (refine-plan)

### Regression closure: `json-set-string-field.sh` awk pseudocode

Round 1's F-DA-8 fix replaced sed (vulnerable to `&` / `\1` metacharacter expansion in `$VALUE`) with awk (metacharacter-clean by construction). The awk replacement was not mentally simulated end-to-end before landing, and shipped two concrete bugs:

- **Update path** (Round 2 F-R2-3 / F-DA-R2-2). The arithmetic at `before = substr($0, 1, i + length(pat) + colon_part_len - 1)` plus `print before v "\""` produced output that dropped the trailing comma whenever the field being updated was a middle field (any field followed by `,`) — empirically reproduced on `{ "zskills_version": "OLD", "other": "value" }` → `{ "zskills_version": "2026.04.0"\n  "other": "value" }`. Invalid JSON. Phase 5b.2 writes `zskills_version` into `.claude/zskills-config.json`; if any other field landed below it, every consumer of that config would break on next read.
- **Insert path** (Round 2 F-R2-6). The `awk '/^\}[[:space:]]*$/ && !done { print "  \"" k "\": \"" v "\","; ...'` form unconditionally wrote a trailing comma. On an empty `{}` object the result was `"key": "v",\n}` — invalid JSON. On a non-empty object the result was `"prior": "v"\n"new": "v",` — invalid JSON because the prior last field gained no comma.

Round 2 closure: rewrote both paths.

- Update path now uses one outer `match($0, ...)` against the full `"key"<ws>:<ws>"<value>"` shape, slices the line into `pre / head / post`, then a second `match(head, /"[^"]*"$/)` to surgically replace just the value's quoted portion. Whatever follows the closing quote (trailing comma, newline, brace, etc.) lands in `post` byte-for-byte.
- Insert path now mirrors `apply-preset.sh:99-115`'s comma-aware pattern: scan for the last non-blank line before the outer `}`, add a comma to that line if it doesn't already end in `,` or `{`, then emit the new field WITHOUT a trailing comma.

Verified empirically against five canonical inputs (insert empty, insert non-empty, update last, update middle, special-char value). Output piped through `python3 -c "json.load(sys.stdin)"` succeeds in all five.

Phase 5a.7 test plan extended from 8 to 11 cases. New cases explicitly cover: insert-into-empty-`{}` (no trailing comma); insert-into-non-empty (prior field gets comma); update-middle-field-with-trailing-comma-preserved; key-as-substring-of-value (regex anchoring). Each case MUST pipe through a JSON validator — grep-based assertions would have missed these bugs.

### Portability: `realpath --relative-to` is GNU-only

Round 2 F-DA-R2-1. Round 1's hook normalization assumed `command -v realpath` was sufficient — but BSD/macOS `realpath` exists at `/usr/bin/realpath` AND lacks the `--relative-to` flag, so the probe passed and the actual call failed silently. Round 2 swapped the probe-by-name for probe-by-invocation: `realpath --relative-to=... 2>/dev/null` AND check the result is non-empty. If it fails OR the result starts with `/`, fall through to the string-strip path. Applied to both occurrences (lines ~684 and ~727 of the plan).

### WARN-on-fallback diagnostic

Round 2 F-R2-1 (refiner-surfaced gap #2). The string-strip fallback in the hook silently no-oped when `$REPO_ROOT` and `$FILE_PATH` were symlink-divergent, leaving consumers to report "the hook didn't fire" with no debugging trail. Round 2 added a one-line `printf 'WARN: ...' >&2` before the silent `exit 0`, gated on the same `case "$FILE_PATH_REL" in /*` check that triggers the no-op. Preserves the safer-failure-mode property (no false-positive warns) while making the failure observable.

### Sandbox guard for canaries

Round 2 F-R2-2 / F-DA-R2-6 (refiner-surfaced gap #3). Phase 6.1's setup says "clone /workspaces/zskills into sandbox" then later runs `git add __pycache__` against an environment-resolved path. If `$REPO` or `$REPO_ROOT` were misconfigured or shadowed, the `git add` could land against the live repo. Round 2 added a defensive `case "$(realpath "$PWD")" in "$(realpath "$REPO_ROOT")"|"$(realpath "$REPO_ROOT")"/*) exit 1` guard, with prose telling 6.2/6.3/6.4 to apply the same pattern.

### Phase 6.7 cumulative diff stat: 6 → 7 scripts, 6 → 10 tests

Round 2 F-R2-4. Re-derived the cumulative count directly from work items (`grep -E '^- \[ \] [0-9]+\.[0-9]+ — Author|Add' plan` shaped enumeration). Plan now lists scripts and tests by name rather than literal counts. Round 1 patched many counts but missed this one.

### Phase 5a.6 surfaced-gap #1 (apply-preset.sh reuse) — confirmed non-load-bearing

Round 2 F-R2-3 part A and DA Round 2 surfaced-gap #1. Read `skills/update-zskills/scripts/apply-preset.sh` (191 lines): it has a `sed_inplace` helper that hardcodes the field names `landing` and `main_protected`, and an `awk` block for execution-block insertion. Neither is a generic JSON-set-string-field helper. The plan's verifier mandate ("read apply-preset.sh, decide reuse vs. duplicate") is correctly worded — the verifier's check will conclude "no reusable helper exists, write the new file." No plan-text change needed. The Round 2 awk rewrite (above) borrows the comma-aware INSERT pattern from `apply-preset.sh:99-115` rather than reusing a function — which is the right level of factoring.

### Other Round 2 finds

- **F-DA-R2-3** (embedded quotes in value). The awk pattern `[^"]*` stops at the first inner quote, so values containing `\"` (JSON-escape) don't round-trip. Out of scope for v1; documented as a Phase 5a Non-Goal. The actual usage (date+hash version string) doesn't need them.
- **F-DA-R2-4** (typo "Those two These"). Fixed in §1.6 prose.
- **F-DA-R2-5** (5a.0 FAIL message dumps `$raw` instead of `$hits`). Fixed: changed to `printf '%s\n' "$hits" >&2` so the failure message shows only matching PRs, not every open PR's JSON.
- **F-R2-7** (two-pass invariant unenforced). Phase 3.3 now snapshots `git ls-files -m -o --exclude-standard skills block-diagram` at start of pass 1 and compares against pass 2's snapshot, filtered to non-SKILL.md paths (since SKILL.md IS expected to change). Editor swap-files / background-process artifacts now produce a loud failure rather than a confusing hash-mismatch downstream.
- **F-R2-8** (`chmod --reference` GNU-only). Added probe-and-fallback via `stat -c '%a' || stat -f '%Lp'` to `json-set-string-field.sh`. Defensible `2>/dev/null` use (probe-then-detect-via-exit-code), per CLAUDE.md.
- **F-R2-9** (gh pr list 100 cap). Added a soft warn when the cap is hit, with a recommendation to re-run with `--limit 1000`. Not blocking.
- **F-R2-10** (missing test-zskills-resolve-config.sh AC). Added two ACs to Phase 5a: `grep -c 'ZSKILLS_VERSION' tests/test-zskills-resolve-config.sh >= 1` and `bash tests/test-zskills-resolve-config.sh exits 0`. Promised work in 5a.2 now actually verified.
- **F-R2-11** (PR #169 verification noted but not pursued by reviewer). Verifier work item; not a plan finding.
- **F-R2-5** (Round 1 disposition prose for F-DA-9 muddled). Round 1 disposition table is EFFECTIVELY-IMMUTABLE per orchestrator constraints. Cannot rewrite. Justified — outcome was correct, only prose explanation was sloppy.

---

## Plan Review — Round 2 (refine-plan)

| Finding | Severity | Disposition | Rationale | Verification outcome |
|---------|----------|-------------|-----------|----------------------|
| F-R2-1 | LOW | Fixed | Hook fallback path now emits a `WARN:` diagnostic before the silent `exit 0`, applied at both occurrences (Phase 4.1 outer + inner pseudocode). | Verified — re-read both edited blocks; diagnostic message names both `$FILE_PATH` and `$REPO_ROOT`. |
| F-R2-2 | LOW | Fixed | Phase 6.1 setup now includes a `case "$(realpath "$PWD")"` guard against the live repo; prose generalizes to canaries 6.2/6.3/6.4. | Verified — sandbox-guard pseudocode embedded in 6.1 setup. |
| F-R2-3 (part A) | N/A | Justified — non-load-bearing | Verifier-mandate to read `apply-preset.sh` is correctly worded; empirical check shows no reusable helper exists. | Verified — read apply-preset.sh; sed_inplace + execution-block awk only, no generic helper. |
| F-R2-3 (part B) | HIGH | Fixed (regression) | awk update path rewritten to use single outer `match()` + slice into `pre/head/post`, then second `match(head, /"[^"]*"$/)` for surgical value replacement. Trailing context (commas, newlines, braces) preserved byte-for-byte. | Verified — empirical test on 5 canonical inputs; all outputs valid per `python3 -c "json.load(sys.stdin)"`. Reproduced original bug first (`,` dropped on middle-field update). |
| F-R2-4 | LOW | Fixed | Phase 6.7 prose enumerates 7 scripts (by file name) and 10 tests (6 non-canary + 4 canaries) instead of literal count "6 + 6". | Verified — re-counted from `grep -E '5a\.[0-9]+ — Add' plan` and similar across phases; 7 scripts confirmed, 6 non-canary tests confirmed. |
| F-R2-5 | LOW | Justified | Round 1 disposition table is EFFECTIVELY-IMMUTABLE per orchestrator constraints. F-DA-9's outcome was correct; only the prose rationale was muddled. Cannot rewrite without violating immutability. | Judgment — orchestrator constraint explicit. |
| F-R2-6 | MED | Fixed (regression) | awk insert path rewritten to mirror `apply-preset.sh:99-115`'s comma-aware pattern: scan for last non-blank line before `}`, add `,` if needed, emit new field WITHOUT trailing comma. | Verified — empirical test on empty `{}` and non-empty `{...}` produced valid JSON outputs in both cases (Tests 4 and 5 of /tmp/test-fixed-awk.sh). |
| F-R2-7 | LOW | Fixed | Phase 3.3 now snapshots non-SKILL.md `git ls-files` state at start of pass 1, compares to pass 2 snapshot, hard-fails on drift. | Verified — pseudocode embedded in Phase 3.3 prose; uses `git ls-files -m -o --exclude-standard skills block-diagram`. |
| F-R2-8 | LOW | Fixed | `json-set-string-field.sh` now probes `chmod --reference` and falls back to `stat -c '%a'` / `stat -f '%Lp'`. Documented in helper header. | Verified — re-read helper pseudocode; probe pattern is `if ! chmod --reference="$FILE" "$TMP" 2>/dev/null; then ... fi`. |
| F-R2-9 | LOW | Fixed | Phase 5a.0 preflight now warns when `gh pr list` returns ≥ 100 entries; recommends `--limit 1000` re-run. Not blocking. | Verified — `raw_count` derivation embedded in 5a.0; warn message names the soft cap. |
| F-R2-10 | LOW | Fixed | Two new ACs added to Phase 5a: `grep -c ZSKILLS_VERSION tests/test-zskills-resolve-config.sh >= 1` AND test exits 0. | Verified — re-read Phase 5a Acceptance Criteria; new ACs present below the existing "verified by extending..." line. |
| F-R2-11 | N/A | Out of scope | Reviewer noted as "verification I would do, not a finding." No action required. | N/A. |
| F-DA-R2-1 | MED | Fixed | Hook normalization now probes `realpath --relative-to` BY INVOCATION rather than `command -v realpath` — captures BSD/macOS where flag is absent. Falls through to string-strip on either failure mode. | Verified — re-read both edited blocks; `if FILE_PATH_REL=$(realpath --relative-to=... 2>/dev/null) && [ -n "$FILE_PATH_REL" ]` pattern at both sites. |
| F-DA-R2-2 | HIGH | Fixed (regression — same as F-R2-3 part B) | Same fix as F-R2-3 part B — awk update path rewritten. | Verified — empirical test reproduced the bug first, then verified the corrected pseudocode produces valid JSON. |
| F-DA-R2-3 | LOW | Justified — out of scope for v1 | Embedded quotes (`\"` JSON escape) in string values explicitly excluded. Documented as Phase 5a Non-Goal. Real usage (date+hash version string) doesn't need them. | Verified — Phase 5a Non-Goals list updated. |
| F-DA-R2-4 | LOW | Fixed | §1.6 typo "Those two These are out of scope" → "These are out of scope". | Verified — `grep 'Those two These' plan` returns no matches post-edit. |
| F-DA-R2-5 | LOW | Fixed | Phase 5a.0 FAIL block prints `$hits` instead of `$raw` — only matching PRs surface, not every open PR's JSON. | Verified — `grep "printf '%s\\\\n' \"\\\$hits\" >&2" plan` matches the new line. |
| F-DA-R2-6 | LOW | Fixed (consolidates with F-R2-2) | Same fix as F-R2-2 — sandbox guard added to Phase 6.1 setup with prose to apply uniformly. | Verified — see F-R2-2. |

**Summary**

- Round 2 substantive findings: 17 total (Reviewer 11 + DA 6).
- Fixed: 14
  - F-R2-1, F-R2-2, F-R2-3 (part B), F-R2-4, F-R2-6, F-R2-7, F-R2-8, F-R2-9, F-R2-10, F-DA-R2-1, F-DA-R2-2, F-DA-R2-4, F-DA-R2-5, F-DA-R2-6 (counting the awk-update-path fix once across F-R2-3-partB and F-DA-R2-2 — they are the same bug from two angles).
- Justified: 3
  - F-R2-3 (part A) — verifier-mandate is correctly worded; non-load-bearing.
  - F-R2-5 — Round 1 disposition table is EFFECTIVELY-IMMUTABLE per orchestrator constraints; outcome was correct, only prose muddled.
  - F-DA-R2-3 — embedded JSON-escapes in values are out of scope for v1; documented as Non-Goal.
- Out of scope (no action): 1
  - F-R2-11 — reviewer noted as "verification I would do, not a finding."

**Headline**: Round 1 traded one bug class (sed-metacharacter expansion) for another (awk arithmetic produces invalid JSON on update-middle-field and insert-into-`{}`/non-empty cases). Round 2 closure rewrites both paths to match `apply-preset.sh`'s proven comma-aware pattern, expands Phase 5a.7 from 8 to 11 test cases, and gates each with a JSON validator. The portability concern (BSD/macOS `realpath --relative-to`, `chmod --reference`) was real and is now addressed via probe-and-fallback patterns. The remaining LOW/justified items are polish.

Round 2 disposition complete. Convergence is the orchestrator's call.
