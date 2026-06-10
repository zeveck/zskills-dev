# Plan Report — Plugin-Lane Install Redesign

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
