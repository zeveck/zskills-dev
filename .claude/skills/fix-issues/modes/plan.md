## Plan (if `plan` is present)

Draft plans for issues previously skipped as "too complex for batch fix."
Selection gate is skipped when EITHER (a) `$AUTO_FLAG=1` (the canonical
Phase 2 bash variable, set by `auto` in `$ARGUMENTS`), OR (b) the literal
substring `plan auto` appears in `$ARGUMENTS` (legacy composite phrase,
preserved as a user-facing token for backward compatibility). Resolution
order: bash flag is checked first; literal phrase is a fallback. When
either fires, all candidate issues are selected without prompting.

1. **Find skipped issues from `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md`.** Scan the entire
   sprint report for issue numbers under "Skipped" / "Too Complex" /
   "Remaining Open" headings. Use grep to extract candidate numbers
   (handles bare `#NNN`, ranges like `#148-#168`, and `#NNN, #MMM` lists):

   <!-- allow-hardcoded: (^|[^A-Za-z0-9_])SPRINT_REPORT\.md reason: filename basename suffixed onto $ZSKILLS_REPORTS_DIR (resolved via zskills-paths.sh; issue #217); the basename token itself remains literal so the regex still flags the /SPRINT_REPORT.md tail -->
   ```bash
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
   else
     source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
   fi
   grep -nE '#[0-9]+' "$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md" | grep -iE 'skip|complex|remain'
   ```

   Then for each candidate `#N`:
   - Check `$ZSKILLS_PLANS_DIR/` for an existing executable plan covering it:
     `grep -l "#$N\b" "$ZSKILLS_PLANS_DIR"/*.md` (existing plan = skip)
   - Check GitHub state: `gh issue view "$N" --json state -q .state`
     (`OPEN` = candidate; `CLOSED` = skip)

   Build the working list of `needs-plan` issues from candidates that
   have NO existing plan AND are still `OPEN`. Skip the rest.

2. **Deduplicate** — check `plans/` for existing plans that already cover
   each issue. Also check whether the issue is still open on GitHub
   (`gh issue view <N> --json state`). Remove issues that already have
   a plan or are closed.

3. **Present findings** (unless the selection-skip OR-rule above fires —
   `$AUTO_FLAG=1` OR the literal `plan auto` substring is in
   `$ARGUMENTS`):
   > Found N issues needing plans:
   > | # | Title | Source |
   > |---|-------|--------|
   > | #142 | Drag into subsystem | Sprint 2026-03-17: Skipped — Too Complex |
   > | #363 | Algebraic loop detection | Sprint 2026-03-16: Remaining Open |
   > ...
   > Already have plans: #NNN, #NNN (skipped)
   > Already closed: #NNN (skipped)
   >
   > Which issues should I draft plans for? (all / comma-separated numbers / none)

   Wait for the user's selection before proceeding. If the selection-skip
   OR-rule fires (`$AUTO_FLAG=1` OR literal `plan auto` in `$ARGUMENTS`),
   skip this step and plan all of them.

4. **For each selected issue**, create a delegation requirement marker and
   then dispatch `/draft-plan`. The marker goes under fix-issues' own
   per-sprint subdir ($PIPELINE_ID) — the parent reconciles child
   fulfillment in its own scope:
   ```bash
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
   mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
   printf 'skill: draft-plan\nparent: fix-issues\nissue: %s\ndate: %s\n' \
     "$ISSUE_NUMBER" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
     > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.draft-plan.$ISSUE_NUMBER"
   # #808: record the skip in monitor-state.json so subsequent sprint
   # fires drop this issue BEFORE re-triage (the user explicitly chose
   # /draft-plan here; that decision is now persistent state, symmetric
   # with the sprint-mode plan-scale-decline path). `reconsider <N>`
   # clears the entry if the user later changes their mind.
   ZSKILLS_MAIN_ROOT="$MAIN_ROOT" bash \
     "$CLAUDE_PROJECT_DIR/.claude/skills/fix-issues/scripts/record-skip.sh" \
     "$ISSUE_NUMBER" plan-scale \
     || echo "WARN: fix-issues plan: record-skip.sh failed for #$ISSUE_NUMBER — sprint may re-pick" >&2
   ```
   Then dispatch `/draft-plan` with:
   - The issue number and full body (`gh issue view <N> --json body`)
   - Any research blurb from the tracker files
   - Output path: `plans/{issue-slug}.md`

5. **Report:**
   > Plans drafted: N
   > - plans/foo-bar.md (#123) — [one-line summary]
   > - plans/baz-qux.md (#456) — [one-line summary]
   > Already had plans: M (skipped)
   > Closed issues: K (skipped)
   > User declined: J

6. **Exit.** Plans are ready for `/run-plan` execution.

