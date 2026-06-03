# Factsheet — `docs/guides/tracking-overview.md`

Each doc sentence is paired with the source line(s) that justify it. Quotes are
verbatim from HEAD of this worktree. This guide has no single SKILL.md source;
ground truth is the tracking hook, `docs/tracking/TRACKING_NAMING.md`, and
CLAUDE.md's tracking sections.

---

## Behavior: what tracking does for the user

**Doc:** "It stops unverified code from landing. A skill that writes code but
skips the verification step cannot commit, cherry-pick, or push that code — a
git hook blocks the operation until verification has actually run."

- `hooks/block-unsafe-project.sh.template:344-346`: `enforce_step_implement_marker() { ... block_with_reason "BLOCKED: ${base#step.} has implementation but no verification. Run verification before ${action}. ...`
- `hooks/block-unsafe-project.sh.template:814`: `if is_git_subcommand_in_wrappers "$COMMAND" commit; then` (commit path runs the tracking checks)
- `hooks/block-unsafe-project.sh.template:973`: `if is_git_subcommand_in_wrappers "$COMMAND" cherry-pick; then` (cherry-pick path)
- `hooks/block-unsafe-project.sh.template:1047`: `if is_git_subcommand_in_wrappers "$COMMAND" push; then` (push path)

**Doc:** "It keeps concurrent pipelines from stepping on each other. Two skills
running at once each have their own tracking state, so one pipeline's
half-finished work never blocks the other's commit."

- `docs/tracking/TRACKING_NAMING.md:449-450`: `The isolation is structural — two concurrent pipelines cannot see / each other's markers because they live in disjoint subdirectories.`
- `hooks/block-unsafe-project.sh.template:913`: `PIPELINE_SUBDIR="$TRACKING_DIR/$PIPELINE_ID"` (the hook scopes its scan to the current pipeline's own subdirectory)

---

## What you'd observe — the BLOCKED messages

**Doc:** quotes the "Required skill invocation '...' not yet fulfilled. Invoke
the required skill via the Skill tool." message.

- `hooks/block-unsafe-project.sh.template:334`: `block_with_reason "BLOCKED: Required skill invocation '${base#requires.}' not yet fulfilled. Invoke the required skill via the Skill tool. To clear stale tracking: ! bash .claude/skills/update-zskills/scripts/clear-tracking.sh"`

**Doc:** quotes the "has implementation but no verification. Run verification
before committing." message.

- `hooks/block-unsafe-project.sh.template:346`: `block_with_reason "BLOCKED: ${base#step.} has implementation but no verification. Run verification before ${action}. ...` (`${action}` is `committing` on the commit path, `hooks/block-unsafe-project.sh.template:947`: `enforce_step_implement_marker "$impl" "committing"`)

**Doc:** "A commit, cherry-pick, or push that touches only non-code files
(markdown, images, and similar) is exempt — tracking checks are skipped for
content-only changes."

- `hooks/block-unsafe-project.sh.template:911`: `if [ -n "$CODE_FILES" ]; then` (the entire tracking-enforcement block is guarded on code files being present; commit path)
- `hooks/block-unsafe-project.sh.template:905`: `if [[ "$line" =~ \.(js|ts|json|css|html|rs|py|go|rb)$ ]]; then` (only these extensions count as code)
- `hooks/block-unsafe-project.sh.template:1125`: `if [ -n "$CODE_FILES" ]; then` (push path, same guard)

---

## When tracking applies — pipeline association

**Doc:** "Inside a worktree: the skill writes a small `.zskills-tracked` file at
the worktree root naming the pipeline. If that file is present, the session is
part of that pipeline."

- `hooks/block-unsafe-project.sh.template:881-882`: `if [ -f "$LOCAL_ROOT/.zskills-tracked" ]; then / PIPELINE_ID=$(cat "$LOCAL_ROOT/.zskills-tracked" 2>/dev/null | tr -d '[:space:]')`
- `hooks/block-unsafe-project.sh.template:864`: `# Tier 1: .zskills-tracked file in LOCAL repo root (worktree agents).`

**Doc:** "On the main checkout: the skill prints a `ZSKILLS_PIPELINE_ID=<id>`
line early in the session, which the hook reads back from the session
transcript."

- `hooks/block-unsafe-project.sh.template:890`: `PIPELINE_ID=$(grep -o 'ZSKILLS_PIPELINE_ID=[^[:space:]"]*' "$TRANSCRIPT" 2>/dev/null | tail -1 | cut -d= -f2)`
- `hooks/block-unsafe-project.sh.template:867`: `# Tier 2: ZSKILLS_PIPELINE_ID=<id> in transcript (orchestrators on main).`

**Doc:** "If neither is present, the hook treats your session as unrelated to any
pipeline and skips enforcement entirely. ... an ordinary commit you make by
hand, or an unrelated agent in another session, can commit freely even while a
pipeline is mid-run."

- `hooks/block-unsafe-project.sh.template:872`: `# Neither → unrelated session → skip enforcement → parallel work unblocked.`
- `hooks/block-unsafe-project.sh.template:898`: `if [ -d "$TRACKING_DIR" ] && $TRACKING_SESSION_HAS_PIPELINE; then` (all enforcement is gated on the session having a pipeline)

---

## Where the markers live — per-pipeline subdirectories

**Doc:** "Tracking markers are small text files under `.zskills/tracking/` in
your project. They are grouped into one subdirectory per pipeline, named after
that pipeline's ID."

- `CLAUDE.md:94-95`: `Tracking markers live in \`.zskills/tracking/\` and are scoped per pipeline / via a subdirectory named after \`PIPELINE_ID\`.`
- `CLAUDE.md:99-100`: `construct them under / \`.zskills/tracking/$PIPELINE_ID/\` using the \`requires.*\`, \`fulfilled.*\`, / and \`step.*\` basenames — never flat under \`.zskills/tracking/\` directly.`
- `docs/tracking/TRACKING_NAMING.md:44`: `Markers live in \`.zskills/tracking/$PIPELINE_ID/{fulfilled,requires,step}.*\`.`
- `hooks/block-unsafe-project.sh.template:913`: `PIPELINE_SUBDIR="$TRACKING_DIR/$PIPELINE_ID"` (reader globs the per-pipeline subdir)

**Doc:** layout example (`requires.draft-plan.*`, `fulfilled.draft-plan.*`,
`step.phase2.implement/.verify/.report`).

- `docs/tracking/TRACKING_NAMING.md:408-416` (the "Expected layout" block):
  ```
  .zskills/tracking/
    run-plan.thermal-domain/
      requires.draft-plan.thermal-domain      # child skill invocation required
      fulfilled.draft-plan.thermal-domain     # written back after /draft-plan returns
      step.phase2.implement                   # implementation started
      step.phase2.verify                      # verifier ran
      step.phase2.report                      # report written — commit now allowed
  ```

**Doc:** "The per-pipeline subdirectory is what keeps pipelines isolated: two
pipelines live in two different directories, so the hook checking one pipeline's
commit never sees the other pipeline's markers."

- `docs/tracking/TRACKING_NAMING.md:449-450`: `The isolation is structural — two concurrent pipelines cannot see / each other's markers because they live in disjoint subdirectories.`
- `hooks/block-unsafe-project.sh.template:931-933`: `if [ -n "$PIPELINE_ID" ] && [ -d "$PIPELINE_SUBDIR" ]; then / for req in "$PIPELINE_SUBDIR"/requires.*; do` (the loop only iterates the current pipeline's subdir)

**Doc:** the concurrent `fix-issues.sprint-20260417-152301-foobar/` example.

- `docs/tracking/TRACKING_NAMING.md:421-422`: `.zskills/tracking/ / fix-issues.sprint-20260417-152301-foobar/`

**Doc:** "`.zskills/` is not committed to git — these markers are short-lived
process state, not part of your project's history."

- `.gitignore:4`: `.zskills/`
- `docs/tracking/TRACKING_NAMING.md:189-190`: `Markers are short-lived and the Phase 2 reader change is / backward-compatible` (markers are short-lived process state)

**Doc:** "The marker files themselves are plain key-value text recording which
skill created them and when."

- `hooks/block-unsafe-project.sh.template:323-325` (marker body is read as key/value lines): `local fulfilled="${TRACKING_DIR}/${base/requires./fulfilled.}"`
- `docs/tracking/TRACKING_NAMING.md:324-326`: `parent: <parent-skill-name>` — markers carry key:value body fields (e.g. an optional `parent:` line)

---

## When the checks run — commit, cherry-pick, push (NOT "only on main")

**Doc:** "The hook applies the same tracking checks at three points where code
could otherwise reach a branch — `git commit`, `git cherry-pick`, and `git
push`."

- `hooks/block-unsafe-project.sh.template:814`: `if is_git_subcommand_in_wrappers "$COMMAND" commit; then`
- `hooks/block-unsafe-project.sh.template:973`: `if is_git_subcommand_in_wrappers "$COMMAND" cherry-pick; then`
- `hooks/block-unsafe-project.sh.template:1047`: `if is_git_subcommand_in_wrappers "$COMMAND" push; then`
- `hooks/block-unsafe-project.sh.template:1044-1045`: `# Push is the landing gate for PR mode — same tracking checks as commit/cherry-pick.`

**Doc:** "Separately, when your project sets `main_protected: true`, the hook
also refuses any commit, cherry-pick, or push directly to `main` — that is a
different rule from tracking."

- `hooks/block-unsafe-project.sh.template:806`: `if is_git_subcommand_in_wrappers "$COMMAND" commit && is_main_protected && is_on_main; then` (main-protection on commit — a separate `is_main_protected && is_on_main` gate, independent of the tracking checks)
- `hooks/block-unsafe-project.sh.template:966`: `if is_git_subcommand_in_wrappers "$COMMAND" cherry-pick && is_main_protected && is_on_main; then`
- `hooks/block-unsafe-project.sh.template:1171`: `if is_git_subcommand_in_wrappers "$COMMAND" push && is_main_protected; then`

---

## Clearing stale tracking

**Doc:** "Clearing them is a user-only action — the hook deliberately blocks
agents from running the cleanup script, so you run it yourself: `! bash
.claude/skills/update-zskills/scripts/clear-tracking.sh`"

- `hooks/block-unsafe-project.sh.template:615-616`: `if [[ "$COMMAND" =~ $_CT_EXEC_CMD ]] || [[ "$COMMAND" =~ $_CT_EXEC_DIR ]]; then / block_with_reason "BLOCKED: Only the user can run the clear-tracking script. Run: ! bash .claude/skills/update-zskills/scripts/clear-tracking.sh"`
- script exists at `.claude/skills/update-zskills/scripts/clear-tracking.sh` (confirmed present in worktree)

**Doc:** "The leading `!` runs it as you rather than as the agent. The script
lists every tracking file with its contents, asks you to confirm, and only then
removes them."

- `.claude/rules/zskills/managed.md:370`: `The \`.claude/skills/update-zskills/scripts/clear-tracking.sh\` script lets the user manually clear stale tracking state -- agents are blocked from running it directly.`
- `hooks/block-unsafe-project.sh.template:616`: BLOCKED message above instructs the `! bash ...clear-tracking.sh` form (the `!` prefix runs as user)

**Doc:** "the hook also refuses any recursive delete that reaches inside
`.zskills/` — so an agent cannot wipe the tracking tree (or the audit and issues
state that lives alongside it) by accident."

- `hooks/block-unsafe-project.sh.template:601-602`: `if [[ "$COMMAND" =~ rm[[:space:]]+...\.zskills ]]; then / block_with_reason "BLOCKED: Cannot recursively delete inside .zskills/. The tree holds tracking markers, audit history, issues, monitor state, and dashboard runtime. ..."`

---

## Related concepts

**Doc:** "`.landed` is not a tracking marker. It is a separate file written at a
worktree's root after that worktree's commits are confirmed on `main`, used by
cleanup tools to tell which worktrees are safe to remove. It does not affect
commit gating."

- `docs/tracking/TRACKING_NAMING.md:233`: `**Decision: \`.landed\` is NOT a tracking marker.**`
- `docs/tracking/TRACKING_NAMING.md:235-240`: `\`.landed\` is a separate artifact written at worktree-root by / \`/commit land\` ... when cherry-picked / commits have been confirmed on \`main\`. It records landing state for / worktree-cleanup tools; it does not participate in pre-commit / enforcement and is not read by the hook's ... globs.`
- `CLAUDE.md:103-104`: `\`.landed\` is NOT a tracking marker — it is a separate / worktree-state artifact managed by \`/commit land\``

**Doc:** "Claiming work items is a related but distinct mechanism: before a
pipeline works an issue or plan, it claims it so two pipelines don't pick up the
same item. That is separate from the commit-gating tracking described here."

- `.claude/rules/zskills/managed.md:374`: `Claim any tracked work-item (issue or plan) before working it; the claim is held for the work's full lifetime ... released only on resolve/abandon` (claiming is a distinct mechanism from the tracking-marker commit gate)

---

## Defects fixed vs. the previous version of this guide

1. **Flat layout → per-pipeline subdirectories.** The old guide showed all
   markers flat under `.zskills/tracking/` (e.g. `pipeline.fix-issues.sprint`,
   `requires.verify-changes.sprint` side by side). Current reality is one
   subdirectory per pipeline. Corrected per `CLAUDE.md:94-100`,
   `docs/tracking/TRACKING_NAMING.md:44`, and the hook reader at
   `hooks/block-unsafe-project.sh.template:913`.

2. **"Pipeline scoping via suffix matching" section removed (obsolete).** The
   old guide described scope filtering by basename suffix (`*.$PIPELINE_ID`).
   That scheme was replaced by the per-pipeline subdirectory glob. The hook is
   now subdir-only: `hooks/block-unsafe-project.sh.template:943`: `# Subdir-only
   reader (Phase 6: dual-read fallback removed; all writers migrated).` (also
   :1016, :1130). The suffix-matching prose was dropped entirely. (Note: the
   rendered `.claude/rules/zskills/managed.md:370` still says "suffix matching"
   — that line is stale relative to `CLAUDE.md:94-100` and the hook; this guide
   follows the hook, the authoritative reader.)

3. **"identical for all three" overstatement scoped to the truth.** The old
   guide claimed enforcement is "identical for all three" of
   commit/cherry-pick/push with only minor file-detection differences. The
   tracking checks (delegation + step) ARE applied at all three points
   (`:814`, `:973`, `:1047`), so the doc now states that plainly — but the doc
   also separates that from the `main_protected` rule (`:806`, `:966`, `:1171`),
   which is a *different* gate (it fires on operations targeting `main`, not as
   part of the tracking checks). The previous framing conflated the two.

4. **Hardcoded `npm run test:all` removed.** The old guide's worked example
   asserted "Because the verification agent's transcript contains the test
   command (`npm run test:all`)". That entire worked-example section was
   replaced; the rewrite carries no project-specific test command. (The hook's
   transcript test gate is config-driven via `full_cmd`,
   `hooks/block-unsafe-project.sh.template:651-653`, so naming a specific
   command would be wrong for any other consumer.)
</content>
