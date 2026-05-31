---
title: /fix-issues Sprint Report
status: complete
---

# /fix-issues sprint — sprint-20260531-130658-docsngate

**Mode:** N=1, auto, every 2h, cron-fired sprint
**Started:** 2026-05-31T09:13:39-04:00
**Open issues at sprint start:** 3 (#832, #833, #67)
**Actionable picks dispatched:** 1 (joint #832+#833 fix)
**Actually shipped:** 0 (implementer surfaced structural ambiguities; no code changes)

## Triage

| # | Title | Verdict | Route |
|---|-------|---------|-------|
| #832 | skills/doc/SKILL.md missed by PR #831 plugin-lane migration | Premise contradicts D23 (canonical-config-prelude §1: legacy form "valid forever, NOT deprecated"). Doc-skill is NOT uniquely missed — 11 other inline-prose sites across 9 skills use the same literal. | Skip — needs author decision; tagged `/draft-plan` |
| #833 | conformance gate for legacy single-lane resolver pattern | Gate as proposed contradicts D23 and would catch legitimate inline-prose mentions including the canonical reference doc itself. | Skip — depends on #832 resolution; tagged `/draft-plan` |
| #67  | GitLab support — deferred until prereqs land | Skip-tagged `deferred` per Phase 2 SKIP_TAGGED filter | Skip |

## Implementer findings (full analysis)

Implementer agent dispatched for the joint #832+#833 fix. After reading `skills/doc/SKILL.md`, four peer skills (`briefing`, `commit`, `do`, `draft-plan`, `verify-changes`), `references/canonical-config-prelude.md`, `tests/test-skill-conformance.sh`, `tests/test-plugin-mirrorless-resolution.sh`, and `tests/fixtures/forbidden-literals.txt`, the agent surfaced three structural blockers:

1. **D23 contradiction.** `references/canonical-config-prelude.md` §1 (decision D23 / F-DA2-4) explicitly states the legacy single-line resolver form is "valid forever, NOT deprecated" and `test-skill-conformance.sh`'s per-fence check accepts EITHER form permanently. #833's proposed gate would invalidate this. The canonical reference doc itself uses the legacy literal in 4+ examples.

2. **Scope wider than one skill.** Grep across the source tree found 11+ inline-prose sites in 9 skills using the legacy literal (`fix-issues`, `do`, `do/modes/direct`, `qe-audit`, `verify-changes` ×3, `fix-report`, `run-plan/modes/execute-phase`, `fix-issues/modes/sprint`, `doc` ×2). PR #831 migrated only **executable bash fences**, not inline-prose parentheticals. The doc-skill is NOT uniquely missed; #832's framing is empirically false.

3. **No precedent for "inline-prose dual-prelude."** The dual-prelude is a 5-line bash block; it doesn't fit inside a `(resolve via [code-span])` parenthetical. The four peer skills #832 cites got their **executable fences** migrated — none have a precedent for an inline-prose dual-prelude pattern. Any fix would be a NEW prose pattern, not a "mirror existing peer" substitution.

## Three resolution paths (for author decision)

- **A — Narrow #832 only.** Migrate doc-skill's 2 inline-prose sites to a new prose pattern referencing `references/canonical-config-prelude.md` §1 (e.g., `(resolve via the dual-prelude in references/canonical-config-prelude.md §1)`). Drop #833 — gate contradicts D23. File follow-up to revise D23 or design a nuanced gate.

- **B — Full prose-form sweep.** Migrate all 12 inline-prose sites across 9 skills to the new prose pattern. Add the gate scoped to inline-prose-backtick form ONLY (NOT executable fences). Revise D23 to scope its "forever" guarantee to fences. Largest change; cleanest end state.

- **C — Close both as design-correct.** Per D23 the legacy form is valid forever; mirror-less plugin consumers who hit it should run `/update-zskills` to install the legacy mirror. Issues are confused; close both.

## Sprint metadata

- Sprint pipeline ID: fix-issues.sprint-20260531-130658-docsngate
- Sprint worktree: /tmp/zskills-fix-issues-sprint-20260531-130658-docsngate
- Issue claims for #832 and #833: acquired and released cleanly.
- No PR opened this fire.
- Cron: `36 */2 * * *` — next fire ~2h. #832 and #833 now skip-tagged so future fires drop them via Phase 2 SKIP_TAGGED filter.
