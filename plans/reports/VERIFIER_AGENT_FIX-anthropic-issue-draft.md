# Anthropic upstream issue draft — VERIFIER_AGENT_FIX

**Status:** Draft. Filing deferred to user (this environment is not authorized
to file issues against `anthropics/claude-code`). Per AC-6.10's allowance
("Skip with justification only if the vendor's issue tracker is not publicly
accessible from this environment — record the would-be body in
plans/reports/..."), the body below is the would-be issue.

**Target tracker:** https://github.com/anthropics/claude-code/issues/new
(or appropriate vendor channel)

---

## Title

`Subagent dispatch hangs when bash backgrounding + Monitor/BashOutput poll`

## Body

### Failure mode

When a Claude Code subagent (dispatched via `subagent_type:` from a parent
agent's `Agent`-tool call) launches a Bash command with
`run_in_background: true` and then polls for completion via the `Monitor`
or `BashOutput` tools, **wake events for backgrounded processes do not
reliably deliver to one-shot subagent dispatches**. The poll never returns;
the subagent's turn ends mid-wait, typically with a final assistant text
along the lines of "Tests are running. Let me wait for the monitor."

This is asymmetric with top-level (non-subagent) Bash backgrounding, where
`Monitor` / `BashOutput` does deliver wake events as designed.

The trigger in our environment is the default 120-second Bash-tool timeout:
any test invocation longer than 120s hits the timeout, and the subagent's
trained recovery reflex is to re-issue the same command with
`run_in_background: true` and then poll. That second invocation hangs.

### Reproducer

Minimum repro:

1. Define a custom subagent (`.claude/agents/<name>.md`) with the full
   `Bash, Monitor, BashOutput` tool allowlist.
2. From a parent agent, dispatch via `Agent` tool with
   `subagent_type: "<name>"` and a prompt that asks the subagent to run a
   shell command whose runtime exceeds the default 120s tool timeout
   (e.g., a test suite that takes ~3 minutes).
3. Observe: the subagent foregrounds the command, hits 120s timeout,
   re-issues with `run_in_background: true`, calls `Monitor` /
   `BashOutput`, and the dispatch ends without ever surfacing test
   results.

Concretely in our repo (zskills): `bash tests/run-all.sh` takes ~3 min
and exhibits this behavior on every dispatch from `/run-plan` Phase 3,
`/commit` Phase 5 step 3, `/fix-issues` per-issue verification, `/do`
Phase 3, and `/verify-changes` self-dispatch.

### Workaround we shipped (Layer 0 — PR #189)

A frontmatter `PreToolUse` hook on `Bash` (at
`.claude/hooks/inject-bash-timeout.sh`) that auto-extends every Bash
call's `timeout` field to 600000 ms (10 min) via the `updatedInput`
envelope, ensuring the 120s default never trips. Once Bash never times
out at 120s, the bg+Monitor recovery reflex never triggers from our
verifier dispatches.

This is documented in our codebase's CLAUDE.md as "Verifier-cannot-run is
a verification FAIL, not a routing decision" — we treat the harness
behavior as a defect to surface, not silently route around (per our
"skill-framework repo — surface bugs, don't patch" discipline). The
workaround unblocks zskills, but **the underlying primitive is still
defective and other consumers will hit it** — hence this upstream issue.

### What we'd ask Anthropic to investigate

- Why `Monitor` / `BashOutput` wake events fail to deliver to one-shot
  subagent dispatches (confirm vs. our hypothesis above).
- Whether the fix should be at the harness level (deliver wake events to
  active subagent turns) or via documentation (mark the bg+Monitor
  pattern as unsupported in subagent contexts).
- Whether the default 120s Bash-tool timeout should be configurable via
  agent frontmatter (so callers can opt out of the trigger without
  needing a `PreToolUse` hook).

### References

- **PR #148** (zskills, 2026-05-01): the prose-only first attempt — added
  verbatim "DO NOT use `run_in_background: true`" warnings to four
  SKILL.md files. Failed mechanically: subagents continued to hit the
  pattern despite the warning.
- **PR #175** (zskills, 2026-05-02 — skill-versioning): the failing
  canary case. Every Phase 1-6 verifier dispatch hit the Monitor pattern;
  the orchestrator did inline self-verification across 5 of 7 phases and
  committed unverified work. Filed as our internal issues
  zeveck/zskills-dev#176 (Monitor anti-pattern recurrence) and
  zeveck/zskills-dev#180 (verifier-skipped silent pass).
- **PR #189** (zskills, 2026-05-03): this plan's structural fix —
  `.claude/agents/verifier.md` + Layer 0 timeout-injection hook +
  Layer 3 failure-protocol validation script. Closes #176 and #180
  locally.

---

Filing deferred to user — please copy the body above into a new issue at
https://github.com/anthropics/claude-code/issues/new (or appropriate
vendor channel).
