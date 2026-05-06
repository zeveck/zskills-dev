# Skill-version PreToolUse hook — design reference

This is the single source of truth for the `block-stale-skill-version.sh`
PreToolUse hook design. Subsequent phases of
`plans/SKILL_VERSION_PRETOOLUSE_HOOK.md` cite this document instead of
restating rationale inline.

## 1. Decisions D1-D5

The five decisions resolved during /draft-plan, copied verbatim from the
plan's Decisions section. The heading form `### D1 — …` matches the plan
so AC1's `^### D[1-5] —` grep finds both.

### D1 — Hook file shape: flat `hooks/block-stale-skill-version.sh` (no `.template`)

Research finding F4 verified `block-unsafe-project.sh.template` is byte-identical to its installed `.claude/hooks/block-unsafe-project.sh` (`diff -q` exit=0); the `.template` suffix is cosmetic legacy, not a render mechanism. The new hook has no install-time placeholders to fill (it calls a script and emits a JSON envelope — both runtime concerns), so the suffix would add zero value and confuse the install loop. Flat matches `block-unsafe-generic.sh`'s shape, which is the closest live analog (universal-rules, no project-config gating).

### D2 — Commit-only gating; DROP push gating

Research finding F2 verified `skill-version-stage-check.sh` reads `git diff --cached --name-only`; at push time the cached set is empty, so a naive push hook is silently degraded (no detection → silent allow). Designing a separate push code path that scans `@{u}..HEAD` is meaningful net-new work (commit-walk, name-only-per-commit, hash-recompute against HEAD's blobs) for marginal coverage — the only hole it closes is "amend a stale commit and push" or "push from a branch authored elsewhere," both of which are caught by CI's conformance gate. `git push` from outside Claude Code is already an unguarded path; CI is the documented backstop. Note: `/land-pr` invokes `git push` from inside Claude Code — this hook will NOT deny that push, but the underlying commits will have been gated at commit time, so `/land-pr` only ever pushes already-clean commits. No regression.

Note: prompt Goal language was overbroad ("DENIES git commit / git push"); the singular success criterion (prompt line 7) only covers `git commit`. We honor the success criterion.

Transient rollout window: commits authored before the hook landed (or in sessions that have not yet run `/update-zskills`) won't have been gated. `/land-pr` will push them; CI's conformance gate is the backstop. After all consumers run `/update-zskills`, the window closes.

### D3 — KEEP `/commit` Phase 5 step 2.5 (defense-in-depth)

The hook is THE structural backstop, but step 2.5 surfaces failure earlier in `/commit`'s flow (before the user even sees confirmation), with clearer context — the script runs interactively with stderr visible to the user, vs. the hook's deny envelope which the harness renders as an opaque tool denial. Step 2.5 covers `/commit` invocations; the hook covers bare `git commit` (and any future caller path that reaches `git commit` outside `/commit`). They fire at different moments with different UX surfaces — not duplicative.

### D4 — JSON escape: pure-bash function (no Python dep)

Research finding F3 verified the canonical `printf` envelope in `block-unsafe-generic.sh:88` does ZERO escaping of the reason string. The stage-check STOP message contains `"`, `\`, and newlines; without escape, the harness silently rejects malformed JSON → silent allow (worst possible failure: looks like the hook approved). zskills convention is "no `jq`, bash regex + `awk`" (per CLAUDE.md and per [feedback_no_jq_in_skills]). Python `json.dumps` is stdlib but adds a process per call; pure bash is in keeping with hook conventions and faster.

The escape function uses `LC_ALL=C` for byte-deterministic operation, then handles `\` (must be first), `"`, and the named control-char escapes (`\n`, `\r`, `\t`, `\b`, `\f`). Other rare control bytes (0x00–0x1F) outside the named set are STRIPPED rather than `\u00XX`-escaped — these don't appear in stage-check stderr by inspection of `scripts/skill-version-stage-check.sh` (it emits ASCII text only). Stripping rather than escaping eliminates a fragile per-character UTF-8-aware loop. Implementation skeleton in Phase 2.

### D5 — Helper-script consumer install (Phase 4 mandatory)

Research finding F1 verified zero copy lines exist in `skills/update-zskills/SKILL.md` for `scripts/skill-version-stage-check.sh`, `scripts/skill-content-hash.sh`, `scripts/frontmatter-get.sh`, `scripts/frontmatter-set.sh`. These ship today only via PR #175's seed-and-mirror flow on the zskills side; consumer repos installing via `/update-zskills` get NONE of them. Without these, the new hook's `[ -x "$SCRIPT" ]` guard (mandatory failsafe) trips → no enforcement on any consumer. Phase 4 extends `/update-zskills`'s install loop (via a new `scripts/install-helpers-into.sh` driver shared between the prose and the sandbox test) to copy all four helpers from `$PORTABLE/scripts/` to consumer `scripts/`, AND bumps `skills/update-zskills/SKILL.md`'s `metadata.version`.

## 2. Phase 1 verifications (manual recipes)

Three Claude-Code-runtime semantics claims this plan depends on were
empirically confirmed during /draft-plan research against Claude Code
**2.1.126**. They are catalogued here as runnable recipes for re-verification
if the harness is upgraded.

### R1 — PreToolUse hook chain composition

(i) Empirical assertion: subagent frontmatter PreToolUse hooks compose
with project `settings.json` PreToolUse hooks — both fire for the same
tool invocation; neither suppresses the other; either may DENY.
A new project-level PreToolUse hook does NOT need to be re-declared in
each subagent's frontmatter to apply to that subagent's tool calls.

(ii) Recipe to re-verify:

```bash
claude -p '!cat .claude/agents/verifier.md | head -30 && echo --- && cat .claude/settings.json | head -30 && echo --- && echo "issue a Bash invocation in a verifier subagent and confirm both hook layers ran"'
```

Cross-check: the `verifier` agent's frontmatter need not enumerate
`block-stale-skill-version.sh` for the hook to apply to its `git commit`
tool invocations (the project-level registration in `.claude/settings.json`
is sufficient).

Last confirmed against: Claude Code 2.1.126

### R2 — Deny-envelope `permissionDecisionReason` accepts long strings

(i) Empirical assertion: the PreToolUse deny envelope's
`hookSpecificOutput.permissionDecisionReason` field accepts long
multi-line strings (well beyond the typical stage-check STOP message of
~200-800 bytes). The harness does not silently truncate at small
boundaries; the full message is rendered to the user.

(ii) Recipe to re-verify:

```bash
claude -p '!echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"$(printf 'A%.0s' {1..2000})\"}}"'
```

Then dispatch a tool call gated by a hook that emits the above and
confirm the user sees the full 2000-char reason rendered (not silently
truncated to a few dozen bytes).

Last confirmed against: Claude Code 2.1.126

### R3 — PreToolUse fires BEFORE the tool is invoked

(i) Empirical assertion: PreToolUse hooks fire BEFORE the named tool
(here, `Bash`) is dispatched. A `deny` decision prevents the tool call
entirely; the underlying process (e.g. `git`) never runs. Therefore,
git-level bypass flags such as `git commit --no-verify` cannot defeat
this hook — `--no-verify` only suppresses git's own pre-commit hooks,
which are evaluated inside the `git` process that the harness never
spawns when the PreToolUse decision is `deny`.

(ii) Recipe to re-verify: read the PreToolUse hook semantics in the
official documentation —

```bash
claude -p '!echo "Reference: https://code.claude.com/docs/en/hooks — see PreToolUse section"'
```

Source: <https://code.claude.com/docs/en/hooks>. The `PreToolUse` hook
event fires "before tool calls are dispatched"; a `permissionDecision`
of `deny` prevents tool execution. `--no-verify` is therefore irrelevant
to a PreToolUse-based gate.

Last confirmed against: Claude Code 2.1.126

---

If `claude --version` reports a new version when Phase 5 runs, re-run
these recipes; otherwise treat as authoritative.

## 3. Recursive risk

Recursive risk: NONE. PreToolUse hooks run as subprocesses outside
Claude Code's tool-dispatch loop; they cannot themselves invoke the Bash
tool. Verified by construction.

## 4. `tests/run-all.sh` dispatcher pattern

Each test suite is invoked via a single line of the form:

```bash
run_suite "<filename>" "tests/<filename>"
```

`run_suite` is defined at the top of `tests/run-all.sh`; it `bash`-executes
the script under `$REPO_ROOT/$script`, captures `output`, parses the
trailing `Results: X passed, Y failed` line via `grep -oP`, and accumulates
into `TOTAL_PASS` / `TOTAL_FAIL` / `OVERALL_EXIT`. Adding a new test suite
is therefore a **single-line addition** — append a `run_suite` line in the
existing block before the `RUN_E2E` opt-in section. Reference for Phase 2.3
and Phase 4.4 of the parent plan.
