# Plan Report — Plugin-Lane Install Redesign

## Phase — 6a Explicit init (Step 0.7 rework, residue cleanup, lock-LAST)

**Plan:** docs/plans/INSTALL_REDESIGN_PLAN.md
**Status:** Completed (verified)
**Commits:** 5e80c4eb (12 files; one commit, adjudicated vs the plan's optional two-commit shape)

### Work Items
init-state.sh (single path definition: init-done/setup-confirmed paths, atomic lock-LAST writer, 0-byte heal, FROZEN legacy-residue constants incl. the literal seed dict, A1.5 mechanical helpers w/ excluded-keys compare); A0 resolver retarget; Step 0.7 bare-call arm → full init sequence (A1.5 both arms → route → gitignore-first w/ check-ignore STOP → lane-scoped interview w/ non-interactive arm + seeded-config cure + skip-after-cure both arms → schema/stamp when-config → A6 report-only → markers LAST); legacy lane: A2 umbrella carve-out + setup-confirmed fences source init-state.sh; 49-case oracle suite + triplet; lane-aware +9 (incl. discipline + ordering pins); hook-helper-drift consumer registration.

### Verification
- Verifier PASS 5e80c4eb; Layer-3 exit 0. Discipline grep independent: zero new frozen-literal carriers (table in verifier report). W6.1/carve-out/#1080/preset BYTE-identical. check-ignore STOP semantics empirically probed (negation cases). Suite 7752/7752 (+60 exact: 49+9+1+1); post-commit gates 119/119 + 13/13. Weakening: none.
- ATTENDED-PENDING #4 (proceed-safe): live scratch shape-(b) install init transcript + delta-scoped footprint (before/after porcelain + find; delta = umbrella + 2 markers + optional config/schema + expected A1.5 removals) — discharge at Phase 9 DEV-QUAL.

### Fork-portability notes (drift log)
- Plugin-lane UPDATE arm never re-checks gitignore (per plan; flagged for Phase 9 sweep adjudication).
- Frozen seed-shape covers ONE shape (current pre-redesign seed); older key-subset seeds conservatively kept — fork plan should state this explicitly.
- A2 negative-override: spec the verify-fails STOP branch as the mechanism (gitignore is last-match-wins, append self-heals pre-existing negations; only uncurable cases STOP).
- CHANGELOG items must ride the release process (Invariant-11 conflict in the plan text — fix in fork copy).
- Commit-shape latitude ("may be 2-3 commits") should explicitly authorize one staged set when lockstep pairs are co-staged.

### User Sign-off
(No UI files changed — omitted.)

## Phase — 5 Config cascade (project > user > built-ins)

**Plan:** docs/plans/INSTALL_REDESIGN_PLAN.md
**Status:** Completed (verified)
**Commits:** 6afc555b (43 files, +1517/−358)

### Work Items
Two-pass cascade in zskills-resolve-config.sh + zskills-paths.sh (user tier limited to the 6 cascadable string keys; execution.*/zskills_version provably project-only); Python helper ×3 (briefing.py, collect.py, server.py — server forced by LOCKSTEP NOTE) loading the canonical defaults JSON; Family-3 hooks carve-out documented comment-only (stamps bumped, behavior blob-identical); Family-5 inline-reader rule recorded; defaults re-spec plans→docs/plans etc.; conformance congruence section (arm i: 5 marker pins; arm ii: seed≡JSON, Phase-7 deletion note); resolver/paths test re-specs (plan-authorized) + cascade cases; 11 fixture configs pinning legacy layouts; ZSKILLS_VERSION init-done fallback w/ #1132 temporary-note. 3 skill bumps + mirrors + tier1 hashes.

### Verification
- Verifier PASS 6afc555b; Layer-3 exit 0. Cascade sandbox-proven independently (precedence, empty-wins-then-default, malformed fail-open, execution.* immunity, init-done fallback). Suite 7690/7692 pre-commit (2 committed-state gates); post-commit invariants 119/119, migration 13/13. +30 accounting verified. Weakening: none (re-specs gained specificity; fixture pins keep DENY paths reachable).

### Fork-portability notes (drift log)
- server.py must be in the Family-4 list (collect.py's LOCKSTEP NOTE mandates it).
- MERGE-SEMANTICS NUANCE: bash merges per LEAF key; Python shallow-merges TOP-LEVEL blocks — divergent on partial nested user blocks. Both per plan text; Phase 9 docs must state ONE user-facing rule (recommend documenting "top-level blocks merge whole" and aligning bash, or documenting the per-family nuance).
- Migration case 6d passes pre-commit (git add writes blobs) — fork plan's predicted-failures list should name only invariants-Tier-1 + 6c.
- The Family-2 default flip ripples into ~5 fixture suites — fork copy should enumerate the fixture-pin collateral up front.

### User Sign-off
(No UI files changed — omitted.)

## Phase — 4 Rules de-parameterization + delivery channel (R-b)

**Plan:** docs/plans/INSTALL_REDESIGN_PLAN.md
**Status:** Completed (verified)
**Commits:** 3f54ddc8 (19 files, +781/−279)

### Work Items
CLAUDE_TEMPLATE.md: all 10 {{TOKENS}} → config-resolution prose (per-token disposition table in the phase report); 3-4 legacy-mirror-only paths → dual-path; managed.md re-rendered same commit (pass-through — template and render now byte-equal modulo sentinel). Canonical zskills-defaults.json hoisted (skills/update-zskills/scripts/, seed-congruent, mirror twin). Renderer no-config mode (--defaults, fails closed). NEW hooks/session-rules-context.sh (R-b: additionalContext-only, lane+managed.md guards, zero writes, stamp 2026.06.10, shim) + hooks.json entry + 8-case suite w/ triplet + parity-exclusion + Gap-2b + finalizer R-b ship-file gate.

### Verification
- Verifier PASS 3f54ddc8; Layer-3 exit 0. Suite 7662/7662 (+13 net, accounting independently reproduced incl. the −4 environmental attended delta and the +2 baseline dirty-tree gates). Weakening audit: none; +13 net assertions.
- Adjudications: retired-token render hard-error ACCEPTED (designed loud-fail, test-pinned); R-b end-to-end live session = ATTENDED-PENDING #3, non-gating (mechanism live-proven in Phase 1 Claim 3 both shapes; hook structurally proven 8/8) — DISCHARGE BY PHASE 9 DEV-QUAL: model quotes a managed-rules landmark + clean git status in an authed probe session.

### Fork-portability notes (drift log)
- Defaults key is testing.output_file (the seed's key), not output.file — fix the plan-table naming in the fork copy.
- Baseline hygiene: capture baselines post-commit (a mid-pipeline dirty-tree baseline carries the 2 Tier-1 gate failures).
- The renderer's --defaults path resolves renderer-relative (../skills/update-zskills/scripts/) — valid in dev/plugin/legacy-portable trees; fork should keep that relative form.

### User Sign-off
(No UI files changed — omitted.)

## Phase — 3 Layer-3 relocation (verify-response-validate.sh)

**Plan:** docs/plans/INSTALL_REDESIGN_PLAN.md
**Status:** Completed (verified)
**Commits:** d51f79d7 (38 files, +467/−274)

### Work Items
R100 zero-drift relocation to skills/update-zskills/scripts/ (+ mirror twin; both old copies deleted); 14 call sites across 6 skills → dual-lane $ZSKILLS_SKILLS_ROOT form with canonical preludes; conformance pin → dual-lane + rejection arm; parity suite deleted (subject-removal); unit/canary/agent-install retargets; verify-install VI_PLUGIN_ARTIFACTS hoist (congruence by construction + 0b pin); materialiser shrink 5→4 (stamp 2026.06.10) with its 4 lockstep suites incl. the scenario-D vacuous-pass kill (verifier added a D0 non-vacuity guard); update-zskills SKILL.md multi-site edits (document-as-residue choice adjudicated CONFIRMED); STALE_LIST/script-ownership/tier1-hash registries. 6 skill bumps + mirrors.

### Verification
- Verifier PASS d51f79d7; Layer-3 exit 0. Suite 7647/7649 pre-commit (2 = committed-state gates, both green post-commit: invariants 119/119, migration 13/13; +4 delta = environmental attended-live-load passes, reconciled). Weakening audit CLEAN — four surfaces STRENGTHENED.

### Fork-portability notes (drift log)
- hooks-mirror-parity + plugin-self-load are GLOB/enumeration-driven — fork copy should drop "update their lists" items (self-accounting).
- suite-registry derives from run-all.sh — only the run-all entry exists to remove.
- Scenario-D retarget needs an explicit non-vacuity guard (D0 style) or the vacuous-pass failure mode just relocates.
- The relocated script retains its line-2 hook-version stamp (R100 spec) — harmless; Phase 7 tidy candidate.
- Residue documentation must phrase the old path WITHOUT the contiguous literal (AC grep + rejection arm).

### User Sign-off
(No UI files changed — omitted.)

## Phase — 2 Plugin-native agents + hooks.json Layer-0 timeout

**Plan:** docs/plans/INSTALL_REDESIGN_PLAN.md
**Status:** Completed (verified)
**Commits:** 18a004e2 (14 files, +633/−13)

### Work Items (branches 1A + T-A)
Root agents/{verifier,implementer}.md (hooks-block-stripped twins, parity-suite-locked); hooks.json gains the PreToolUse/Bash inject-bash-timeout entry; the hook gains the T-A suffix filter (absent⇒EXTEND; {verifier,implementer} incl. zs:-scoped ⇒ EXTEND; foreign ⇒ bare allow) + stamp 2026.06.9 + mirror; unit suite 11→19 (all legacy identity-less cases preserved); integrity/canary/manifest/conformance pins; finalizer fail-closed agents presence gate + URL-walk addition; new test-agents-parity.sh w/ triplet.

### Verification
- Verifier PASS 18a004e2; Layer-3 exit 0. Suite 7651/7651 (+37 independently accounted per-suite). Weakening audit CLEAN (13 deletions all in-place rewordings, zero assertion sites).
- **Layer-0 STOP rule: SATISFIED with live shape-(b) proof** — real marketplace install (scope: user), probe log `verifier→EXTEND` + `zs:verifier→EXTEND`; legacy frontmatter path untouched; orchestrator absent⇒EXTEND.
- Materialiser output-flip observed (resolve_src now prefers root agents/ → materialised copies lose the hooks: block) — Layer-0-safe, observation-not-edit, expected by plan.

### Fork-portability notes (drift log)
- Plan's "sentinel-half" expectation for test-inject-bash-timeout-parity.sh is stale (no such half exists) — drop from fork copy.
- Finalizer "staging" should be specced as a fail-closed presence ASSERTION (tracked files ride automatically; a copy step is dead code).
- The shim-sourcing in inject-bash-timeout.sh must be GUARDED (dual-context script: frontmatter path may lack CLAUDE_PLUGIN_ROOT) — spec the guarded idiom explicitly.
- PROCESS: refresh .test-baseline.txt BEFORE dispatching the implementer, never after (orchestrator clobbered it this phase; verifier reconstructed).

### User Sign-off
(No UI files changed — omitted.)

## Phase — 1 Empirical verification → recorded branch selections

**Plan:** docs/plans/INSTALL_REDESIGN_PLAN.md
**Status:** Completed (verified)
**Commits:** d592c80a (Findings table + tracker)

### Findings (the decision table)
- **agents = 1A** (bare-name dispatch works on real marketplace installs; manifest `agents` field FORBIDDEN — validate-rejects AND breaks load; project twin SHADOWS plugin agent — A1.5 hazard proven live).
- **timeout = T-A** with a NEW load-bearing caveat: under marketplace installs the hook's `agent_type` value is PLUGIN-SCOPED (`zsprobe:zsprobe-agent`) even for bare dispatch → Phase 2's filter must match {verifier, implementer} by suffix (accept `zs:verifier` AND `verifier`). Orchestrator calls carry NO identity field → absent⇒EXTEND (accepted widening).
- **rules = R-b** (additionalContext: 16KB delivered, both shapes, fires in every project under user-scope install — scope fact recorded for Phase 4's acceptance statement). R-a demotion confirmed factual.
- Claim 5: ${CLAUDE_PLUGIN_ROOT} is TEXT-SUBSTITUTED pre-model (even single-quoted) — direct refs safe.
- Claim 6: updatedInput honored from hooks.json (rewrite discriminator, both arms, both shapes); sibling hooks see ORIGINAL input — Phase 2 STOP check uses the rewrite discriminator.
- ATTENDED-PENDING ×2 (non-gating, conservative fallbacks documented): combined-envelope systemMessage rendering; literal /clear arm.

### Verification
- Independent verifier audited every finding-cell against preserved evidence (10/10 artifact-backed); pendings adjudicated proceed-safe; suite 7614/7614; only the plan file modified; probe isolation + credential integrity verified.

### Fork-portability notes (drift log)
- Fork recipe: capture marker-dir ls listings per arm as files; name stdout-disappearance as claim-6's secondary preserved observable; capture the standalone timeout-hook envelope to a file; capture post-remove marketplace list; pre-mark claim-4 shape-(b) as n/a.
- CARRY-FORWARD for fork Phase 2: the scoped-agent_type filter caveat (zs:verifier form).

### User Sign-off
(No UI files changed — omitted.)
