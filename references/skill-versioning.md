# Skill Versioning Reference

This is a reference doc for skill authors and tooling implementers working
in the zskills repo. It is **not** installed downstream. It is the single
source of truth for the per-skill versioning scheme — every later phase of
`plans/SKILL_VERSIONING.md` cites this file by section anchor. It captures
all 11 design-surface decisions verbatim from the plan's `Phase 1 — Decision
& Specification` section, plus appendices summarizing the validation regex
and the canonical hash-input rule.

The repo-level zskills version (`YYYY.MM.N`) is **not redefined** by this
scheme — it lives in `git tag --list` and is mirrored into
`.claude/zskills-config.json` by `/update-zskills` (see §1.5). The per-skill
version (`YYYY.MM.DD+HHHHHH`, defined below) is independent of, and
co-exists with, the repo-level version.

---

## 1.1 — Format choice — `YYYY.MM.DD+HHHHHH` (CalVer + content hash hybrid)

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

## 1.2 — Location — `metadata.version:` in SKILL.md frontmatter

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

## 1.3 — Bump rule — anchored to canonical-projection diff

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

## 1.4 — Per-skill enforcement — three-point combination

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

## 1.5 — Repo-level scheme reconciliation — read from git, mirror to config

**Chosen.** The repo-level version `YYYY.MM.N` is **not redefined**. It lives in `git tag --list` of the source clone. `/update-zskills` (Phase 5) reads it via `git -C "$ZSKILLS_PATH" tag --list | sort -V | tail -1` and mirrors the result into `.claude/zskills-config.json` under a top-level `zskills_version:` key.

**Repo-level bump rule.** The repo-level version bumps on **release-cut events** (`.github/workflows/ship-to-prod.yml:69-77` runs on push to `prod` and computes the next `YYYY.MM.N` automatically). NO new enforcement — the existing workflow is the canonical bump trigger; this plan does not alter it. Per-skill bumps and repo-level bumps are independent: per-skill = "skill content last changed"; repo-level = "Nth release of month". Staleness is visible in the `/update-zskills` delta report, not enforced. (Round-1 finding F-R7.)

**Per-skill versions are independent of repo-level versions.** A skill bumped to `metadata.version: "2026.04.30+a1b2c3"` can coexist with repo-level `2026.04.0`. Schemes mean different things; the report shows both side by side, no arithmetic comparison.

**Updates to `zskills-resolve-config.sh`.** Add a 7th var `ZSKILLS_VERSION` resolved from the new top-level `zskills_version` field via the existing BASH_REMATCH idiom.

**Trade-offs considered:**
- **Live-from-git only (no config mirror).** Rejected. Consumer downstream may not have the source clone present at audit time.
- **New top-level `VERSION` file.** Rejected. Two sources of truth.
- **`zskills_version:` inside `metadata:` block of config.** Rejected. Config schema doesn't have a `metadata` block today.

## 1.6 — Mirror interaction — no script change

`scripts/mirror-skill.sh` uses `cp -a "$SRC/." "$DST/"` (line 35) which copies bytes including any new frontmatter keys. A new `metadata: { version: "..." }` block passes through unchanged. `tests/test-mirror-skill.sh` asserts byte-equivalence via `diff -rq` — also unchanged. No allow-list / skip-list extension needed.

`tests/test-skill-file-drift.sh` tests `zskills-resolve-config.sh` resolution; unrelated to skill content.

**Mirror-only skills (out of scope).** `.claude/skills/` and `skills/` differ by exactly two directories: `playwright-cli` and `social-seo` live ONLY in `.claude/skills/` (pre-source/mirror-split vendor bundle); every other entry in `.claude/skills/` has a `skills/<name>/` source counterpart. These are out of scope for Phase 3 migration: do NOT add `metadata.version` to them. Phase 3.6 conformance enumeration filters via `for skill_dir in "$REPO_ROOT/skills"/*/ "$REPO_ROOT/block-diagram"/*/` (source roots only). A separate plan can fold these in if/when they get a source representation. (Round-1 finding F-R6.)

**Trade-offs considered:**
- **Extend the mirror script's allow-list to recognize the new key.** Rejected. The script is byte-faithful via `cp -a`; no allow-list exists to extend, and adding one would create a drift surface the new field doesn't need.
- **Migrate the two mirror-only skills now.** Rejected. They have no `skills/<name>/` source counterpart to author against; a separate plan covers source-ifying them.

## 1.7 — Block-diagram add-ons — same scheme, applied uniformly to 3 skills

**Chosen.** All 3 block-diagram add-on skills (`add-block`, `add-example`, `model-design`) carry `metadata.version: "YYYY.MM.DD+HHHHHH"` using the same rule. `block-diagram/screenshots/` does NOT contain a `SKILL.md` (it holds image assets only — verified by `ls block-diagram/screenshots/`); it is excluded from migration and conformance enumeration. (Original Round-1 finding F-R1 cited "25 + 3 = 28"; that figure was correct at plan-write 2026-04-30 but stale once PR #159 added `skills/land-pr/` on 2026-05-01 — current is 26 + 3 = 29. The number is derivation-driven from `find ... -exec test -f '{}/SKILL.md' \; -print` enumeration, NOT pinned. See refine-plan Drift Log.)

Migration in Phase 3 seeds the 3 add-ons. Phase 4 enforcement covers them via the same conformance regex AND the widened drift-warn hook regex (Branch 2 widened from `(^|/)skills/[^/]+/.*\.md$` to `(^|/)(skills|block-diagram)/[^/]+/.*\.md$` — see Phase 4.1 and Round-1 finding F-R4).

**Justification.** They are skills shipped through the same mechanism. Excluding them creates a second class of skill consumers can't tell apart at audit time.

**Trade-offs considered:**
- **No version on add-ons.** Rejected. Inconsistent UX in `/update-zskills` reports.
- **Different format.** Rejected. Adds a category for no consumer benefit.

## 1.8 — CHANGELOG integration — additive, minimal-disruption

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

## 1.9 — Migration / seeding — uniform initial date, per-skill computed hash

**Chosen.** Every core skill under `skills/<name>/SKILL.md` and every block-diagram add-on under `block-diagram/<name>/SKILL.md` receives `metadata.version: "YYYY.MM.DD+HHHHHH"` set to **the date Phase 3 lands** (`TZ="$TIMEZONE" date +%Y.%m.%d` at migration commit time) PLUS a per-skill hash freshly computed from each skill's content projection. The set of skills is derived at migration time via the Phase 3.2 enumeration (`find ... -maxdepth 1 -mindepth 1 -type d -exec test -f '{}/SKILL.md' \; -print`) — NOT pinned to a literal count, since the number drifts as new skills land.

**Justification.** A uniform date is honest: "all skills synced as of D." A per-skill hash captures that the skills are NOT identical content (each skill's `aaa111` differs from another's). Mixing uniform-date and per-skill-hash is the correct invariant.

**Trade-offs considered:**
- **Per-skill last-touched date.** Rejected (archaeological; date doesn't mean "skill changed on D").
- **Per-skill `0.0.0` placeholder.** Rejected (regex break; placeholder dance).

## 1.10 — Tooling — three helpers, no slash command

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

**Smoke-test recipe (manual verification of Phase 2 helpers).** Run these lines from the repo root any time you want to confirm the helpers still work end-to-end. They do NOT mutate any tracked file — the set step writes to a `/tmp` copy.

```bash
# 1. get a top-level key (file form)
bash scripts/frontmatter-get.sh skills/run-plan/SKILL.md name           # → run-plan

# 2. get a top-level key (stdin form)
cat skills/run-plan/SKILL.md | bash scripts/frontmatter-get.sh - name   # → run-plan

# 3. compute the 6-char canonical-projection hash
bash scripts/skill-content-hash.sh skills/run-plan                      # → 6 hex chars

# 4. set a versioned value on a /tmp copy (do NOT mutate the real SKILL.md)
mkdir -p /tmp/skill-versioning-smoke
cp skills/run-plan/SKILL.md /tmp/skill-versioning-smoke/SKILL.md
TODAY=$(TZ=America/New_York date +%Y.%m.%d)
HASH=$(bash scripts/skill-content-hash.sh skills/run-plan)
bash scripts/frontmatter-set.sh /tmp/skill-versioning-smoke/SKILL.md metadata.version "$TODAY+$HASH"
bash scripts/frontmatter-get.sh /tmp/skill-versioning-smoke/SKILL.md metadata.version
# → e.g. 2026.04.30+0c846e
```

If any step fails or returns an unexpected value, run `bash tests/test-frontmatter-helpers.sh` and `bash tests/test-skill-content-hash.sh` to localise the regression.

**Trade-offs considered:**
- **Single combined `bump-version.sh`.** Rejected. Get/set/hash are independent operations; downstream tools may want one without the others.
- **`/bump-skill <name>` slash command.** Rejected for v1.
- **Inline awk scripts in each consumer.** Rejected. Drift surface.

## 1.11 — Runtime reads — wire briefing skill in this plan; defer dashboard

**Chosen.** `/briefing` is wired in Phase 5a (the natural surface for "what's installed and how stale is it"). It reads `metadata.version` of installed skills via `frontmatter-get.sh` and compares to source. `/zskills-dashboard` is NOT wired in this plan — the dashboard is a Python service; threading version data through requires a Python-side parser, which is out of scope.

**Trade-offs considered:**
- **Wire dashboard in this plan.** Rejected. Python-side parser is a separate adjacent surface.
- **Wire nothing at runtime.** Rejected. Briefing's "Z Skills Update Check" section currently shows opaque "updates available"; per-skill version delta is a markedly better signal.

---

## Appendix A — Validation regex

The strict regex for `metadata.version` values, used by:
- `tests/test-skill-conformance.sh` (Phase 4 CI gate, §1.4 point 3)
- `hooks/warn-config-drift.sh` (Phase 4 Edit-time warn, §1.4 point 1)
- `scripts/skill-version-stage-check.sh` (Phase 4 commit-time hard stop, §1.4 point 2)

```
^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$
```

Breakdown:
- `[0-9]{4}` — 4-digit year
- `\.` — literal dot
- `(0[1-9]|1[0-2])` — month, 01–12 (no `00`, no `13+`)
- `\.` — literal dot
- `(0[1-9]|[12][0-9]|3[01])` — day, 01–31 (no `00`, no `32+`; permissive on month-length — Feb 30 passes the regex but cannot be produced by `TZ=... date +%Y.%m.%d`, so the producer-side closes the gap)
- `\+` — literal plus separator
- `[0-9a-f]{6}` — 6 lowercase hex chars

Examples that match: `2026.04.30+a1b2c3`, `2026.05.15+9f8e7d`, `2026.12.31+000000`.

Examples that do NOT match: `2026.4.30+a1b2c3` (month not zero-padded), `2026.04.30+A1B2C3` (uppercase hex), `2026.04.30+a1b2c` (5-char hash), `2026.04.30+a1b2c34` (7-char hash), `2026.13.01+a1b2c3` (month 13), `26.04.30+a1b2c3` (2-digit year).

## Appendix B — Canonical hash-input rule

The single-source-of-truth definition of the input to the SHA-256 hash, summarized from §1.1 and §1.3 plus the Phase 2.3 helper spec. Implementations of `scripts/skill-content-hash.sh` MUST produce byte-identical output across machines for the same skill directory state.

**Environment.** All commands run under `LC_ALL=C` to force byte-wise locale-independent ordering and comparisons.

**Inputs.** A single argument: the skill directory path (e.g., `skills/run-plan`). Must contain a `SKILL.md`. Helper exits non-zero if the directory is missing or has no `SKILL.md`.

**Projection — three components, concatenated in this fixed order:**

1. **Redacted frontmatter snapshot of `SKILL.md`.** The block between the opening `---` and the matching closing `---`. Locate the line that, after `awk '{$1=$1};1'` whitespace-stripping, matches the form `version: "..."` AND whose nearest preceding less-indented line is `metadata:`. Replace that single line with `<original-leading-whitespace>version: "<REDACTED>"` — preserving the exact leading-whitespace count. All other frontmatter lines pass through byte-identical. If no `metadata.version` line is present, no redaction occurs (the helper still produces a hash; conformance gates the version's existence separately).

2. **SKILL.md body.** Everything below the closing `---` of frontmatter, byte-identical (no normalization at this layer — normalization happens per-file in component 3 only).

3. **Every regular file under `<skill-dir>/`** (recursive, excluding `SKILL.md` itself). Discovered via `find "$SKILL_DIR" -type f ! -path "$SKILL_DIR/SKILL.md"`. Sorted by path **relative to the skill directory** under `LC_ALL=C sort`. Per-file processing:
   - Strip trailing whitespace per line.
   - Collapse `\r\n` → `\n`.
   - Ensure exactly one trailing newline at end of file.
   - Prefix with header line `=== <relative-path> ===\n` so re-orderings change the hash.

   **Binary files are NOT supported** — Phase 2.3 conformance MUST reject any non-text regular file under a skill directory (detected via `file --mime-encoding` returning `binary` or via NUL-byte presence). Skills that need binary assets must keep them out of the source skill dir.

**Inter-component separator.** A single `\n` byte between component 1 and component 2, between component 2 and the first per-file block of component 3, and between consecutive per-file blocks within component 3.

**Hashing step.** Pipe the concatenated projection through:

```
LC_ALL=C sha256sum | cut -d' ' -f1 | head -c 6
```

Output is exactly 6 lowercase hex chars (no trailing newline). This is the `HHHHHH` half of `YYYY.MM.DD+HHHHHH`.

**Why redact `metadata.version` rather than excluding frontmatter wholesale.** §1.1 covers this in detail; the short version: excluding frontmatter would make the §1.3 promise that `description:` edits trigger a bump unenforceable. Redacting only the version line keeps the hash invariant under version-line edits (no fixed-point) while making every other frontmatter key a hash-affecting input.

**Why deny-list `SKILL.md` (rather than allow-list known subdirs).** §1.1 covers this. An allow-list of `modes/, references/, scripts/, fixtures/` silently misses real skill content like `skills/update-zskills/stubs/`. The deny-list of one (`SKILL.md`) future-proofs against any new subdirectory a skill author may add.

**Determinism check.** Two independent implementations of this rule, given the same skill directory, MUST produce the same 6-char hash. The Phase 2.3 helper tests verify this against fixtures with known projections.
