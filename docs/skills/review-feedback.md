# /review-feedback

> Review exported feedback JSON from the in-app feedback panel, evaluate each pending entry, and selectively file GitHub issues.

## Usage

```
/review-feedback [path-to-feedback.json]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `path-to-feedback.json` | No | Path to the exported feedback file (default: `feedback.json` in repo root) |

## Workflow

1. **Read** the feedback JSON file
2. **Evaluate** each pending entry: is it actionable? Check for duplicates via `gh issue list --search`
3. **Re-rate severity** independently (impact: data loss > crash > broken feature > polish > nit)
4. **Present** findings in a table with severity, category, and recommendation
5. **File issues** for approved entries on GitHub

## Examples

```
/review-feedback
/review-feedback exports/feedback-2026-05-27.json
```

## Common Patterns

- **Regular triage:** `/review-feedback` -- review feedback exported from the app's feedback panel
- **Custom file:** `/review-feedback path/to/feedback.json` -- specify a non-default export file

## Tips & Gotchas

- The feedback JSON is exported from the app via **Feedback Panel > History > Export JSON**
- Severity is independently re-rated -- the reporter's self-rated severity is a hint, not authoritative
- Duplicate detection uses `gh issue list --search` to check for existing issues
- Filed issues include the original feedback text and the agent's severity assessment
