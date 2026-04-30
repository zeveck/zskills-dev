---
title: Skill Versioning
created: 2026-04-30
status: active
---

# Plan: Skill Versioning

> **Landing mode: PR** — This plan touches 25 source skills + 3 add-ons + tests + hooks + a runtime helper script + `/update-zskills`. PR review is appropriate.

## Overview

zskills already ships a **repo-level** `YYYY.MM.N` version (`git tag --list` shows `2026.04.0`; `RELEASING.md:44-46` documents the scheme; `.github/workflows/ship-to-prod.yml:69-77` computes it). It does NOT ship a **per-skill** version: `grep -rli "^version:" skills/ block-diagram/` returns empty, and the four frontmatter keys actually present in any zskills SKILL.md are `name`, `description`, `argument-hint`, `disable-model-invocation`. The gap is asymmetric: the repo knows when it changed; individual skills do not. A consumer running `/update-zskills` against a tag bump cannot tell whether `/run-plan` changed or only `/briefing`. An agent editing a skill cannot tell whether they need to bump anything, because nothing exists to bump.

This plan adds a per-skill version field to SKILL.md frontmatter, defines a mechanically-applicable bump rule that two independent agents would agree on, enforces the bump at edit-time (`warn-config-drift.sh` non-blocking warn) AND at commit-time (`/commit` Phase 5 step 2.5 hard stop) AND at CI-time (`test-skill-conformance.sh` gate), and surfaces both the per-skill and repo-level deltas in `/update-zskills`'s install / update / audit reports. Helper scripts (`scripts/frontmatter-get.sh`, `scripts/frontmatter-set.sh`, `scripts/skill-content-hash.sh`) own the parse/write/hash logic so skill prose stays thin and downstream tools can reuse them. No `jq` introduced; bash regex (`BASH_REMATCH`) + `awk` only, matching the canonical idiom in `zskills-resolve-config.sh:37-44`.

**Format choice — `YYYY.MM.DD+HHHHHH` (date + 6-char content hash).** The date carries human-legible recency; the hash deterministically distinguishes content states. Two same-day edits produce different hashes (no false `unchanged` claim). Two parallel worktrees that diverge on content produce different hashes (clean-apply cherry-picks of B onto A surface a hash conflict, even when B's body diff doesn't textually overlap A's). The hash is computed by `scripts/skill-content-hash.sh` over a canonicalized projection of the skill: a redacted-frontmatter snapshot of `SKILL.md` (with the `metadata.version` line replaced by a `<REDACTED>` literal preserving exact leading whitespace) + the SKILL.md body + every regular file under the skill directory (excluding `SKILL.md` itself), all whitespace-normalized under `LC_ALL=C`. Pure CalVer was rejected at refinement time after Round-1 critical findings F-DA1 (multi-edit-day rule contradicts hook implementation) and F-DA2 (parallel-worktree clean-apply silently loses edits) — see §1.1 trade-offs. The format is `YYYY.MM.DD+HHHHHH` where `HHHHHH` is 6 lowercase hex chars (canonical command form: `LC_ALL=C sha256sum | cut -d' ' -f1 | head -c 6` — used everywhere); regex `^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$`.

**Success criterion:** A fresh agent landing in this repo, told only "modify skill X to do Y," ends up with the per-skill version bumped on its commit (date AND hash both fresh) without a reminder, AND a consumer running `/update-zskills` afterward sees `zskills 2026.04.0 → 2026.04.1` and `Updated: run-plan 2026.04.20+a1b2c3 → 2026.04.30+d4e5f6 (bumped); briefing 2026.04.18+9a8b7c (unchanged); ...` in the structured summary. The repo-level scheme is **not redefined** — this plan reads it from `git tag` (live) and mirrors it into `.claude/zskills-config.json` (snapshot for consumers without git access to the source clone).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Decision & Specification (no code) | ⬚ | | |
| 2 — Tooling: `frontmatter-get.sh` / `frontmatter-set.sh` / `skill-content-hash.sh` + tests | ⬚ | | |
| 3 — Migration: seed all 25 core + 3 add-on skills + extend conformance test | ⬚ | | |
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

- [ ] 1.3 — Update `plans/PLAN_INDEX.md`: add this plan to the active list with one-line description.

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

**Hash collision budget (Round-2 F-R2-9 / F-DA-R2-10).** 6 hex chars = 24 bits = 16,777,216 distinct hash values. Birthday boundary is ~4,096 distinct content states per skill before a 50% collision probability. A single skill cycling through ~4k versions over its lifetime is implausible at zskills' scale (current fleet: 28 skills, total commits to date < 200). 6 chars is sufficient. Trade-off: visual brevity in `/update-zskills` reports and CHANGELOG annotations beats the marginal collision-margin gain at 8 chars. If a real collision is ever observed, the helper widens to 8 in a one-line change (mechanical migration). Documenting here per F-DA-R2-10 surfaces the choice rather than burying it.

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

**Mirror-only skills (out of scope).** `.claude/skills/` carries 27 dirs; `skills/` carries 25. Two skills (`playwright-cli`, `social-seo`) live ONLY in `.claude/skills/` with no source counterpart — they pre-date the source/mirror split. These are out of scope for Phase 3 migration: do NOT add `metadata.version` to them. Phase 3.6 conformance enumeration filters via `for skill_dir in "$REPO_ROOT/skills"/*/ "$REPO_ROOT/block-diagram"/*/` (source roots only). A separate plan can fold these in if/when they get a source representation. (Round-1 finding F-R6.)

#### 1.7 Block-diagram add-ons — same scheme, applied uniformly to 3 skills

**Chosen.** All 3 block-diagram add-on skills (`add-block`, `add-example`, `model-design`) carry `metadata.version: "YYYY.MM.DD+HHHHHH"` using the same rule. `block-diagram/screenshots/` does NOT contain a `SKILL.md` (it holds image assets only — verified by `ls block-diagram/screenshots/`); it is excluded from migration and conformance enumeration. (Round-1 finding F-R1: 25 + 3 = 28 total skills, NOT 29.)

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
- **Per-skill `CHANGELOG.md` files.** Rejected. 25+3 files multiplies maintenance for no consumer benefit.

#### 1.9 Migration / seeding — uniform initial date, per-skill computed hash

**Chosen.** All 25 core + 3 block-diagram skills receive `metadata.version: "YYYY.MM.DD+HHHHHH"` set to **the date Phase 3 lands** (`TZ="$TIMEZONE" date +%Y.%m.%d` at migration commit time) PLUS a per-skill hash freshly computed from each skill's content projection.

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
    3. **Every regular file under `<skill-dir>/`** (recursive, excluding `SKILL.md` itself, dotfiles, and conventional dev artifacts). Enumerate via `find "$skill_dir" -type f ! -name SKILL.md ! -name '.*' ! -path '*/__pycache__/*' ! -path '*/node_modules/*' -print0 | sort -z`. The exclusion of `! -name '.*'` filters editor swapfiles, `.DS_Store`, `.landed`, `.zskills-tracked`, `.test-results.txt`, etc., from the projection (Round-3 F-DA-R3-2: skill dirs SHOULD be clean of dotfiles in the first place; the conformance test in 3.6 also asserts this — defense in depth). **Reject any non-text file:** call `file --mime "$f" | grep -qi 'charset=binary'` and exit 1 if matched (binary fixtures are out of scope; conformance test catches this — see Phase 3.6 update).
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

## Phase 3 — Migration: seed all 25 core + 3 block-diagram skills + extend conformance test

### Goal

Add `metadata.version: "YYYY.MM.DD+HHHHHH"` to every source skill's `SKILL.md` (25 core + 3 block-diagram = 28 files), set the date to the date Phase 3 lands and the hash to each skill's freshly-computed content hash, mirror to `.claude/skills/`, and extend `tests/test-skill-conformance.sh` to assert presence and shape AND that the stored hash matches the recomputed projection.

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

  Expected counts: 25 core, 3 add-on (NOT 4 — Round-1 finding F-R1). Sanity-check before iterating:

  ```bash
  CORE_COUNT=$(echo "$CORE_SKILLS" | wc -l)
  ADDON_COUNT=$(echo "$ADDON_SKILLS" | wc -l)
  test "$CORE_COUNT" = "25" || { echo "FAIL: expected 25 core skills, got $CORE_COUNT" >&2; exit 1; }
  test "$ADDON_COUNT" = "3" || { echo "FAIL: expected 3 add-on skills, got $ADDON_COUNT" >&2; exit 1; }
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
  # Skill-dir cleanliness: no dotfiles or build artifacts in skill directories.
  # (Round-3 F-DA-R3-2: defense-in-depth alongside the find filter in scripts/skill-content-hash.sh.)
  echo "=== Skill-dir cleanliness ==="
  for skill_dir in "$REPO_ROOT/skills"/*/ "$REPO_ROOT/block-diagram"/*/; do
    [ -d "$skill_dir" ] || continue
    name=$(basename "$skill_dir")
    # Find any dotfile (regular file or directory) under the skill dir.
    dotfile_hits=$(find "$skill_dir" -name '.*' ! -name '.' ! -name '..' -print)
    artifact_hits=$(find "$skill_dir" \( -name '__pycache__' -o -name 'node_modules' \) -print)
    if [ -n "$dotfile_hits" ] || [ -n "$artifact_hits" ]; then
      fail "skill $name: contains dotfile/artifact (skill dirs must be clean)" \
        "$(echo "$dotfile_hits"; echo "$artifact_hits")"
      continue
    fi
    pass "skill $name: clean (no dotfiles/artifacts)"
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

  Expected: **28 passes** for the cleanliness loop, **28 passes** for the source-version loop (25 core + 3 add-ons), plus **N passes** for the mirror loop (`N = .claude/skills` count, with `playwright-cli` and `social-seo` as allow-listed skipped passes; all other mirrors must have a source counterpart). 0 fails after migration lands.

- [ ] 3.7 — Append `CHANGELOG.md` entry under today's date heading (create the date heading if absent), per the §1.8 canonical template:

  ```markdown
  ## YYYY-MM-DD

  ### Added — per-skill versioning

  Every source skill (25 core + 3 block-diagram add-ons) now carries
  `metadata.version: "YYYY.MM.DD+HHHHHH"` in its SKILL.md frontmatter,
  seeded to today's date and each skill's content hash. Edits to a
  skill body must bump this field; see `references/skill-versioning.md`
  and CLAUDE.md "Skill versioning" rule. Enforcement lands in subsequent
  commits (Phase 4).
  ```

- [ ] 3.8 — Commit message: `feat(skills): seed metadata.version on all 28 skills + extend conformance test`.

### Design & Constraints

**Atomicity at scale.** Phase 3 modifies 28 SKILL.md files and 25 mirror copies. The script-driven loop is idempotent — re-running with the same `$MIGRATION_DATE` and recomputed hash is a no-op. Verify per-skill mirror parity (3.5) before staging.

**Conformance regex precision.** `^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$` — month restricted to 01-12, day to 01-31, hash exactly 6 lowercase hex. Round-1 finding F-DA11: rejects `2026.13.45+xxx` and similar.

**Block-diagram path enumeration.** `block-diagram/README.md` is not a skill; `block-diagram/screenshots/` has no SKILL.md. The `find ... -exec test -f '{}/SKILL.md' \; -print` form (3.2) filters both correctly.

**Failure mode: revert/no-op edit during migration.** Phase 3's migration is the one exempt event — every SKILL.md gets a NEW key inserted, so the hook (which fires on body diff with no version bump) doesn't fire because the version line itself is being added. The Phase 4 hook lands AFTER Phase 3.

**Failure mode: mirror desync.** Step 3.5's `diff -r` catches it. The post-Phase-3 conformance section ALSO catches it: the conformance test's enumeration adds a third loop over `.claude/skills/*/SKILL.md` that recomputes the projection and asserts the mirrored hash equals the recomputed value (Round-2 finding F-R2-7: prior plan claimed "triple-covered" but conformance only iterated source roots; this third loop closes the real gap). The conformance work item 3.6 is updated to include the `.claude/skills/` walk.

**Failure mode: parallel-worktree convergence (during Phase 3 itself).** This phase MUST run in a single worktree. Phase 6's parallel-worktree canary covers post-migration parallel edits.

### Acceptance Criteria

- [ ] For every source skill (under `skills/` and `block-diagram/`), `bash scripts/frontmatter-get.sh <skill>/SKILL.md metadata.version` outputs a value matching the strict regex `^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$`. Verified per-skill via the conformance test loop (3.6); per-skill grep on indentation patterns is fragile (F-R2-8 — does not verify that `version:` sits under `metadata:`). Use the per-file `frontmatter-get.sh metadata.version` invocation as the authoritative check.
- [ ] Source-skill count check: `find skills -maxdepth 1 -mindepth 1 -type d | wc -l` returns 25 and `find block-diagram -maxdepth 1 -mindepth 1 -type d -exec test -f '{}/SKILL.md' \; -print | wc -l` returns 3.
- [ ] For every source skill `X`, the stored hash equals the freshly-computed hash: `[ "${version##*+}" = "$(bash scripts/skill-content-hash.sh <X>)" ]`.
- [ ] For every core skill `X` in `skills/`, `diff -r skills/X .claude/skills/X` is empty.
- [ ] `bash tests/test-skill-conformance.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0. Output contains: the cleanliness section `=== Skill-dir cleanliness ===` with at least 28 PASS lines and 0 fails; the source-loop section `=== Per-skill version frontmatter ===` with at least 28 PASS lines (25 core + 3 add-on); AND the mirror-loop section `=== Per-skill version mirror parity ===` with one PASS line per `.claude/skills/*/` directory present (`playwright-cli` and `social-seo` show as allow-listed-skipped; all other mirrors match source). 0 fails across all three sections.
- [ ] `bash tests/test-mirror-skill.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0.
- [ ] `bash tests/run-all.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0.
- [ ] `grep -q "Added — per-skill versioning" CHANGELOG.md` succeeds.
- [ ] All 28 skills have the same date prefix (the migration date), assertable by:

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

  **Outer regex (Branch 3 — this work item).** Branch 3 uses **a single regex** that captures any regular file under a skill directory in either source root: `(^|/)(skills|block-diagram)/([^/]+)/.*$`. **No `\.md$` anchor** — Branch 3 must catch edits to `scripts/*.sh`, `stubs/*.sh`, `fixtures/*`, etc., because every regular file under the skill directory is in the projection per §1.1, so any of them can drift the hash. (Empirical check: `echo "skills/run-plan/scripts/correct-plan.sh" | grep -E "(^|/)(skills|block-diagram)/[^/]+/.*\.md$"` returns no match — the `.md$` anchor would silently miss script edits. Branch 3's regex deliberately omits the anchor.) Branch 2's existing `\.md$` regex is **separately** widened to add `block-diagram/` for SKILL.md forbidden-literal coverage (Round-1 finding F-R4); that widening is independent of Branch 3.

  **Staged-file gate.** Before doing any work, the new branch checks whether the file is in the staging set. **Use `grep -Fqx` (fixed-string)** — paths can contain regex metacharacters (e.g., a skill named `a.b` or `a+b`) and `grep -qx` would treat them as a regex pattern (F-DA-R2-5: `grep -qx "skills/foo.bar/SKILL.md"` matches `skills/fooXbar/SKILL.md`). Same fix at the pseudocode site below.

  ```bash
  if ! git -C "$REPO_ROOT" diff --cached --name-only 2>/dev/null | grep -Fqx "$FILE_PATH_REL"; then
    exit 0
  fi
  ```

  where `$FILE_PATH_REL` is `$FILE_PATH` made relative to `$REPO_ROOT`. This folds Round-1 finding F-DA7 (hook noise during WIP) into the hook itself: warn fires only when the agent has explicitly staged the file, signaling commit intent. Mid-WIP edits do not generate noise.

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
  if [[ "$FILE_PATH" =~ (^|/)(skills|block-diagram)/([^/]+)/.*$ ]]; then
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
  FILE_PATH_REL="${FILE_PATH#$REPO_ROOT/}"
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

- [ ] 4.4 — Extend `skills/commit/SKILL.md` Phase 5 (Commit) with a new sub-step `2.5` (between current step 2 "run tests" and step 3 "dispatch reviewer"). Insertion site verified: `grep -n '^## Phase' skills/commit/SKILL.md` shows Phase 4 line 213 (Stage & Review, 4 steps), Phase 5 line 239 (Commit). The natural gate placement is at Phase 5 step 2.5, AFTER tests pass (so the command is correctly ordered: tests then version-check then reviewer). (Round-1 finding F-R2: the prior plan said "Phase 4 step 3.5" which would interleave between staging and presenting-to-user — wrong location, since presenting-to-user is the Phase 4 outcome.)

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
  - 10 hook test cases (each sandbox-based): edit-with-no-bump (warns); edit-with-bump (silent); revert-with-bump-only (warns symmetric); whitespace-only edit (silent — projection identical); new file (silent — no HEAD); helper missing (silent — graceful); HEAD missing version (silent — first migration); body diff with version line untouched (warns); **edit a child file under modes/ without staging it (silent — staged-file gate)**; **edit a child file under modes/ AND stage it without bumping parent SKILL.md (warns referencing parent)**.
  - 8 stage-check script test cases: same matrix but checking exit code (0 = pass, 1 = STOP).
  - Uses `/tmp/zskills-tests/$(basename "$(pwd)")/`. Creates a sandbox git repo per case.

- [ ] 4.7 — Register `tests/test-skill-version-enforcement.sh` in `tests/run-all.sh`.

- [ ] 4.8 — Add `<!-- allow-skill-version-literal: ... -->` exemption marker for prose containing version literals (e.g., `references/skill-versioning.md` itself shows `2026.04.30+a1b2c3` as an example). Reuse the SKILL_FILE_DRIFT_FIX marker convention. Document in `references/skill-versioning.md`. Update `tests/fixtures/forbidden-literals.txt` if needed to include the regex `[0-9]{4}\.[0-9]{2}\.[0-9]{2}\+[0-9a-f]{6}`.

- [ ] 4.9 — **Bump `metadata.version` of `skills/commit/SKILL.md` FIRST** — this phase edits the commit skill's body. Compute fresh hash via `bash scripts/skill-content-hash.sh skills/commit`, write today's date + hash via `frontmatter-set.sh`. **Bump precedes mirror** (Round-2 F-DA-R2-4: mirroring before bumping leaves the mirror immediately stale, fails the AC `diff -r skills/commit .claude/skills/commit` is empty). This bump also validates the gate end-to-end (the commit landing this phase must itself pass the gate).

- [ ] 4.10 — Mirror modified files **after the bump**: `bash scripts/mirror-skill.sh commit`. Hooks live at `hooks/` (top-level), no mirror needed.

- [ ] 4.11 — Append CHANGELOG entry per the §1.8 canonical template:

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
- [ ] `bash tests/test-skill-version-enforcement.sh > /tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt 2>&1` exits 0 with ≥ 18 cases passing.
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

  ```bash
  open=$(gh pr list --state open --search 'in:title update-zskills OR in:files skills/update-zskills/' --json number,title)
  if [ "$(echo "$open" | grep -c '^\[')" -gt 0 ] && [ "$open" != "[]" ]; then
    echo "FAIL: open PRs touching update-zskills:" >&2
    echo "$open" >&2
    echo "Land or coordinate before starting Phase 5." >&2
    exit 1
  fi
  ```

  This is a hard preflight gate. If any open PR touches `skills/update-zskills/`, abort Phase 5a and surface to the user. Coordination is a user decision, not an agent decision.

- [ ] 5a.1 — Update `skills/update-zskills/scripts/zskills-resolve-config.sh` to resolve a 7th var `ZSKILLS_VERSION` from a top-level `zskills_version` field in `.claude/zskills-config.json`:

  ```bash
  ZSKILLS_VERSION=""
  if [[ "$_ZSK_CFG_BODY" =~ \"zskills_version\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    ZSKILLS_VERSION="${BASH_REMATCH[1]}"
  fi
  ```

  Initialize to empty string before the regex (empty-pattern-guard). Mirror to `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh`.

- [ ] 5a.2 — Update `tests/test-zskills-resolve-config.sh` with a 7th var case.

- [ ] 5a.3 — Update `config/zskills-config.schema.json` to declare `zskills_version` as a top-level optional string field. Default: empty string.

- [ ] 5a.4 — Add `skills/update-zskills/scripts/resolve-repo-version.sh` (mirrored):

  ```bash
  #!/bin/bash
  # resolve-repo-version.sh — extract latest YYYY.MM.N tag from zskills source.
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
  # Per-skill version delta. Stdout: <name>\t<source-ver>\t<installed-ver>\t<status>.
  set -u
  ZSKILLS_PATH="${1:?usage: skill-version-delta.sh <zskills-source-path>}"
  GET="$CLAUDE_PROJECT_DIR/scripts/frontmatter-get.sh"
  [ -x "$GET" ] || GET="$ZSKILLS_PATH/scripts/frontmatter-get.sh"
  for src_skill in "$ZSKILLS_PATH/skills"/*/; do
    [ -f "${src_skill}SKILL.md" ] || continue
    name=$(basename "$src_skill")
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
    printf '%s\t%s\t%s\t%s\n' "$name" "$src_ver" "$inst_ver" "$status"
  done
  ```

- [ ] 5a.6 — Add `skills/update-zskills/scripts/json-set-string-field.sh` (mirrored) — JSON-aware string-field write, no jq. Reuse the idiom from `apply-preset.sh`. (If `apply-preset.sh` already factors this out, reuse its helper instead.)

  ```bash
  #!/bin/bash
  # json-set-string-field.sh <json-file> <key> <value>
  # Updates a top-level string field in a JSON file in-place.
  # Inserts the field if absent. No jq.
  set -u
  FILE="${1:?json-file required}"
  KEY="${2:?key required}"
  VALUE="${3:?value required}"
  TMP="$(mktemp)"
  if grep -q "\"$KEY\"" "$FILE"; then
    # Update existing field via sed with escaped quotes.
    sed -E "s|(\"$KEY\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")|\1${VALUE//|/\\|}\2|" "$FILE" > "$TMP"
  else
    # Insert before closing brace.
    awk -v k="$KEY" -v v="$VALUE" '
      /^\}[[:space:]]*$/ && !done { print "  \"" k "\": \"" v "\","; done=1 }
      { print }
    ' "$FILE" > "$TMP"
  fi
  mv "$TMP" "$FILE"
  ```

  Document edge case: sed substitution preserves all other content. Test in 5a.7.

- [ ] 5a.7 — Add `tests/test-json-set-string-field.sh` — 6 cases: insert into empty obj, insert with existing fields, update existing field, idempotent no-change, value-with-special-chars, malformed JSON exits non-zero.

- [ ] 5a.8 — Add `tests/test-skill-version-delta.sh` — fixture cases: source-newer (bumped), source-older (still emits, downstream decides), installed-missing (new), source-missing-but-installed-present (would be `removed` if implemented; v1 doesn't enumerate that case — out of scope), both-empty (malformed), both-equal (unchanged).

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

- [ ] 5a.13 — Append CHANGELOG entry per §1.8 canonical template.

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
- [ ] `bash skills/update-zskills/scripts/resolve-repo-version.sh /workspaces/zskills` outputs a value matching `^[0-9]{4}\.(0[1-9]|1[0-2])\.[0-9]+$`.
- [ ] `bash skills/update-zskills/scripts/skill-version-delta.sh /workspaces/zskills` outputs ≥ 25 tab-delimited lines.
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

---

## Phase 5b — `/update-zskills` UI surface (3 insertion sites)

### Goal

Wire the data plumbing from Phase 5a into `skills/update-zskills/SKILL.md`'s three user-facing reports: audit gap report, install final report, update final report. Add the mirror-tag-into-config step.

### Work Items

- [ ] 5b.1 — Insert version-delta surfacing in three sites within `skills/update-zskills/SKILL.md`:

  **Site A — Audit gap report (Step 6, lines ~542-595).** After the existing gap enumeration, add:

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

  **Site B — Install final report (lines ~1202-1218).** Add a "Per-skill versions" sub-section showing each skill's installed version. For an install, all skills are "new" relative to the (empty) prior state.

  **Site C — Update final report (lines ~1260-1269).** REPLACE the current `Updated: N skills (list)` line with a structured table:

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

- [ ] 5b.8 — Append CHANGELOG entry per §1.8 canonical template.

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
- [ ] **Rerender output is version-data-free:** capture rerender output; `grep -E 'Repo version|metadata.version' "$capture"` returns 0 matches.
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
  - Setup: clone `/workspaces/zskills` into sandbox, replicate Phase-3-landed state.
  - Action: edit a sandbox SKILL.md body, stage it, do NOT bump version.
  - Assertion 1 (Edit-time): run hook with synthetic input, assert stderr contains `WARN:` and `content changed`.
  - Assertion 2 (commit-time): stage, run `scripts/skill-version-stage-check.sh`, assert exit 1 and stderr contains `STOP:`.
  - Assertion 3 (CI gate): conformance test against sandbox state — passes regex but fails hash-freshness check (Phase 3.6 added the stale-hash check).
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
  - **Multi-edit-day sub-case:** edit A on date D, bump to `D+aaa`. Land. Then edit B on same date D, bump to `D+bbb` (different hash because content differs). Hook sees `staged_ver != head_ver` AND `cur_hash != head_hash` — silent. Stage-check exits 0. **This is the F-DA1 closure.**
  - **Revert/no-op sub-case:** edit body, bump version, revert body change leaving version bumped. Hook emits `WARN:` matching `version bumped but content unchanged`. Stage-check exits 1.

- [ ] 6.5 — Register all 4 canaries in `tests/run-all.sh`: `grep -c 'test-skill-version-canary' tests/run-all.sh` returns 4.

- [ ] 6.6 — Run the full suite end-to-end. All Phase 1-5b changes plus all 4 canaries must pass.

- [ ] 6.7 — `/verify-changes` end-to-end review:
  - Cumulative diff stat across all 6 phases (28 SKILL.md frontmatter additions, 6 new scripts, 6 new tests, 1 hook extension, 1 commit-skill extension, 1 update-zskills overhaul, 1 briefing tweak, 2 schema updates, plan + reference docs).
  - **Rebase-clean preflight (carryover from F-DA5).** Before final landing, re-check `gh pr list --state open --search 'in:title update-zskills OR in:files skills/update-zskills/'` — abort if any open PR has appeared since Phase 5a.
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
