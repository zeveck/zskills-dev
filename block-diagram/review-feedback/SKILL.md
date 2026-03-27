---
name: review-feedback
description: >-
  Review exported feedback JSON from the in-app feedback panel, evaluate each
  pending entry, and selectively file GitHub issues via gh CLI. Use when the user
  says "review feedback", "triage feedback", or "file feedback issues".
---

# /review-feedback — Review and triage user feedback

Review exported feedback JSON from the in-app feedback panel, evaluate each
pending entry, and selectively file GitHub issues.

## Trigger

User says: "review feedback", "triage feedback", "file feedback issues",
or invokes `/review-feedback`.

## Input

The exported `feedback.json` file should be in the repo root (or the user
will specify the path). This file is exported from the app via
**Feedback Panel > History > Export JSON**.

## Workflow

1. **Read** the feedback JSON file:
   ```bash
   cat feedback.json
   ```
   Or run the summary helper first:
   ```bash
   node scripts/review-feedback.js feedback.json
   ```

2. **For each pending entry**, evaluate:
   - Is it a real, actionable bug or feature request?
   - Is it a duplicate of an existing GitHub issue? Check with:
     ```bash
     gh issue list --search "keyword" --state open
     ```
   - What label(s) should it get? (`bug`, `enhancement`, `ui`, `question`)

3. **Present a summary table** to the user showing your recommendations:
   | # | Title | Type | Severity | Recommendation | Reason |
   |---|-------|------|----------|----------------|--------|
   | 1 | ... | bug | high | File | Clear repro |
   | 2 | ... | feature | low | Dismiss | Too vague |

4. **Wait for user approval** before filing anything.

5. **File approved entries** as GitHub issues:
   ```bash
   gh issue create --title "Title here" --body "$(cat <<'EOF'
   **Type:** bug
   **Severity:** high
   **Reported:** 2026-03-11

   Description here.

   ### Context
   - Model: ModelName
   - Blocks: 12
   - Sim state: idle
   - Solver: ode45
   EOF
   )" --label "bug"
   ```

6. **Update the JSON file** with filed status and issue numbers:
   - Set `status: "filed"` and `githubIssue: "#NNN"` for filed entries
   - Set `status: "dismissed"` for dismissed entries
   - Write the updated JSON back to the file

7. **Tell the user** they can re-import the updated JSON in the app
   via the browser console:
   ```js
   // In browser console:
   const store = new (await import('./src/io/FeedbackStore.js')).FeedbackStore();
   store.importJSON(await (await fetch('feedback.json')).text());
   ```

## Label Mapping

| Feedback type | GitHub label |
|--------------|-------------|
| bug | `bug` |
| ui | `bug`, `ui` |
| feature | `enhancement` |
| question | `question` |

## Rules

- Never file issues without user approval
- Check for duplicates before filing
- Include the auto-captured context in the issue body
- One GitHub issue per feedback entry (don't merge entries)
- Critical severity bugs should be flagged prominently in the summary
