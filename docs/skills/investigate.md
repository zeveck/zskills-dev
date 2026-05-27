# /investigate

> Deep debugging for one complex bug at a time. Disciplined workflow: reproduce, trace, state root cause, fix, verify. The agent must PROVE root-cause understanding before writing a fix.

## Usage

```
/investigate <description or #issue>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `description` | Yes | Description of the bug, or a GitHub issue number |

## Examples

```
/investigate #387
/investigate Scope block shows NaN after 10 seconds of simulation
/investigate test failure in tests/blocks/pid.test.js "derivative term"
```

## Workflow

### Phase 1 -- Reproduce

See the bug. Confirm it exists. Get a reproducible test case or steps.

### Phase 2 -- Trace

Follow the execution path. Read the code. Identify where the behavior diverges from expectations.

### Phase 3 -- Root Cause

State the root cause explicitly. You may not write a fix until this phase is complete.

### Phase 4 -- Fix

Write the minimal fix that addresses the root cause.

### Phase 5 -- Verify

Confirm the fix resolves the issue. Run tests. Check for regressions.

## Common Patterns

- **GitHub issue:** `/investigate #387` -- fetches the issue body and comments as the starting point
- **Error message:** `/investigate Scope block shows NaN after 10 seconds` -- start from a symptom description
- **Test failure:** `/investigate test failure in tests/blocks/pid.test.js` -- start from a specific failing test
- **After /fix-issues skip:** when `/fix-issues` skips an issue as too complex, `/investigate` is the follow-up

## Tips & Gotchas

- One bug at a time -- this is not `/fix-issues`. For batch fixing, redirect to `/fix-issues`
- Every phase is gated -- you cannot skip to writing a fix without proving root-cause understanding
- `/fix-issues` should escalate here when a fix agent fails after 2 attempts
- The escalation boundary is the user's decision -- no automatic escalation from `/fix-issues`
