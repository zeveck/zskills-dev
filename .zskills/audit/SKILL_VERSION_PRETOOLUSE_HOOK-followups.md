# SKILL_VERSION_PRETOOLUSE_HOOK — Phase 5.6 follow-ups

Per spec D3 + CLAUDE.md "Skill-framework repo — surface bugs, don't patch":
two pre-existing bugs were surfaced during this plan's research. They are
NOT shipped as patches in this PR (out of scope per Phase 5 D&C: docs-only
finalization). They are routed below to the appropriate next-step surface.

## 1. skill-version-stage-check.sh STOP message — UX nit

**Surface:** GitHub issue (one-line fix, not architectural).

**Symptom:** `scripts/skill-version-stage-check.sh:91-93` emits the same
STOP message text whether (a) the user edited a SKILL.md without bumping
`metadata.version`, OR (b) the user bumped `metadata.version` but did not
`git add` the SKILL.md. The two recovery paths differ (case (a) → run
`frontmatter-set.sh`; case (b) → `git add SKILL.md`), but the message
gives no hint which case applies.

**Suggested fix:** add a one-line conditional hint in the STOP block:

```bash
[ -z "$staged_ver_was_set_initially" ] && hint="(SKILL.md not staged — git add it)"
```

**Routing:** file via `gh issue create` AFTER this PR lands (issue body
should reference the merged PR for context). The verifier subagent or
orchestrator may file it once `feat/skill-version-pretooluse-hook` is on
main. Suggested issue title:
`skill-version-stage-check.sh STOP message: same text for "didn't bump" vs "didn't stage bump"`.

Suggested body:
- Cite `scripts/skill-version-stage-check.sh:91-93`.
- Mark as UX clarity, not blocking.
- Reference `plans/SKILL_VERSION_PRETOOLUSE_HOOK.md` Phase 5.6 for context.

## 2. block-unsafe-project.sh:404 over-matching — drafted hardening plan

**Surface:** existing drafted plan + recommended `/run-plan` invocation
(NOT a new issue — see rationale below).

**Symptom:** the `git[[:space:]]+commit` regex at
`.claude/hooks/block-unsafe-project.sh:404` lacks command-boundary
anchoring + data-region redaction. Read-only Bash invocations whose
argument strings contain the literal `git commit` (e.g.
`grep -n 'git commit' .claude/hooks/block-unsafe-project.sh`,
`sed -n '404,420p' .claude/hooks/block-unsafe-project.sh`) trip the hook
even though they are not commit operations.

**Why no new issue:** PR #73 (Issue #58) and PR #87 (Issue #81) already
patched this hook for prior over-match incidents. Filing a third
`404`-specific issue would queue a third regex patch in a pile rather
than fix the class. Same root cause as Plan B's own evolution (Round 1
regex extension → Round 2 tokenize-then-walk pivot): regex-based
command-classification is fundamentally fragile.

**Routing:** the hardening plan is already drafted —
`plans/BLOCK_UNSAFE_HARDENING.md` (PR #192, drafted 2026-05-06). Scope is
the tokenize-then-walk pivot for `block-unsafe-project.sh` +
`block-unsafe-generic.sh` command-detection, plus a data-region
redaction pass that handles heredoc bodies + quoted args uniformly.

**Recommended next step (after this PR lands):**

```
/run-plan plans/BLOCK_UNSAFE_HARDENING.md finish auto
```

This consumes the drafted plan end-to-end, cherry-picks each phase to
main, and closes the over-match class.

## Out-of-scope for this PR

Per spec Phase 5 D&C: NO new code in `hooks/`, `skills/`, or
`tests/run-all.sh`. Phase 5 is documentation finalization only. Both
follow-ups above route to post-merge surfaces.
