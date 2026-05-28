# /qe-audit

> QE audit: check recent commits for test coverage gaps, or bash/stress-test features to find bugs. Files GitHub issues for findings. Recurring via `every SCHEDULE`; `stop`/`next` manage it.

## Usage

```
/qe-audit [bash [area]] [every SCHEDULE] [now]
/qe-audit stop
/qe-audit next
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `bash` | No | Switch to bash/stress-test mode instead of commit audit |
| `area` | No (with bash) | Specific feature area to stress-test (e.g., `undo/redo`, `solver`, `codegen`) |
| `every SCHEDULE` | No | Self-schedule recurring runs (`4h`, `day at 9am`, etc.) |
| `now` | No | Run immediately (with `every`: run now AND schedule) |
| `stop` | No | Cancel the recurring cron |
| `next` | No | Check when the next run will fire |

## Modes

### Commit Audit (default)

Review recent commits for test coverage gaps, missing tests, and bugs. Files GitHub issues for findings.

### Bash Mode

Adversarial stress-testing of features. Pick a specific area or let the agent choose under-tested areas. Try to break things with edge cases, unusual inputs, and unexpected workflows.

## Examples

```
/qe-audit
/qe-audit bash
/qe-audit bash undo/redo
/qe-audit bash solver
/qe-audit every day at 9am
/qe-audit every 4h now
/qe-audit bash every 12h
/qe-audit stop
/qe-audit next
```

## Common Patterns

- **Daily audit:** `/qe-audit every day at 9am` -- schedule a daily commit audit
- **Targeted stress test:** `/qe-audit bash solver` -- stress-test the solver specifically
- **Quality feedback loop:** `/qe-audit` finds gaps, `/fix-issues` fixes them, `/qe-audit` validates

## Tips & Gotchas

- Both modes file GitHub issues and update the QE issues tracker
- The commit audit mode examines recent commits, not the entire codebase
- Bash mode is adversarial -- it actively tries to break features
- Scheduling follows the same `every SCHEDULE` pattern as other skills
- Cron is session-scoped -- it dies when the session dies
