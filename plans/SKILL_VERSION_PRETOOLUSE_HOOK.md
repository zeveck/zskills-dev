---
title: SKILL_VERSION_PRETOOLUSE_HOOK
created: 2026-04-30
status: active
---

# Plan: SKILL_VERSION_PRETOOLUSE_HOOK

> **Landing mode: PR** -- This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

PR #175 (squash `f0ef441`, 2026-05-02) landed per-skill `metadata.version` enforcement at three points:

1. **Edit-time warn** — `hooks/warn-config-drift.sh` Branch 3 (PostToolUse, non-blocking, fires on `Edit`/`Write` of skill files).
2. **Commit-time hard stop** — `scripts/skill-version-stage-check.sh` invoked from `/commit` Phase 5 step 2.5. Exits 1 with `STOP:` and bump command on mismatch.
3. **CI gate** — `tests/test-skill-conformance.sh` (3 sections: cleanliness, version frontmatter, mirror parity).

**The lock-step gap.** `/commit` step 2.5 only fires when the user invokes `/commit`. A bare `git commit` from terminal — the natural path for any agent that has not internalized the `/commit` flow, or any human who forgets — is not gated locally. CI catches it after a feature branch already carries the bad commit, which means rebases, force-pushes, and noisy review threads.

**This plan adds the missing structural backstop:** a Claude Code PreToolUse Bash hook (`hooks/block-stale-skill-version.sh`) that DENIES `git commit` invocations when staged skill files have a stale `metadata.version` hash. The hook is harness-level (every Claude Code session in this repo or any consumer who has run `/update-zskills`), runs BEFORE the Bash tool executes git, and is unbypassable by `--no-verify` (PreToolUse fires before git, so git-level flags are irrelevant by construction). The hook reuses `scripts/skill-version-stage-check.sh` — same exit semantics, same STOP message, no logic duplication.

**Success criterion.** A fresh agent that edits `skills/run-plan/SKILL.md` body and runs `git commit -am "..."` directly (bypassing `/commit`) gets DENIED at PreToolUse with the script's STOP message and bump command. CI is no longer the only mechanical safety net for what lands on a feature branch.

**Non-goals.**
- Reimplementing `scripts/skill-version-stage-check.sh` inside the hook. Reuse it.
- Git pre-commit hooks (per-clone, bypassable via `--no-verify`, rejected in prior conversation).
- Aggressive denial. The script already returns 0 when no skill files are staged or when version+content are consistent — pass-through.
- Restructuring the existing skill-version stage-check script (it works).
- Any change to the SKILL_VERSIONING enforcement design (already landed in PR #175).

## Decisions (D1-D5)

The /draft-plan prompt called out 5 decisions. Each is resolved here verbatim; Phase 1's reference doc snapshots the same rationale for downstream agents (formatted as `### D1` … `### D5` headings, both in this section and in the reference doc, so AC1's grep `^### D[1-5] —` matches).

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

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Decision doc + manual-recipe verifications | ⏳ Pending | — | reference doc only; R1/R2/R3 already empirically confirmed in research |
| 2 — Hook script + JSON-escape function + unit tests | ⏳ Pending | — | `hooks/block-stale-skill-version.sh` + `tests/test-block-stale-skill-version.sh` |
| 3 — `.claude/settings.json` registration + canonical extension table | ⏳ Pending | — | zskills-side wiring + `skills/update-zskills/SKILL.md:882-888` row |
| 4 — Helper-script install flow extension + sandbox integration test | ⏳ Pending | — | F1 fix; copy 4 scripts; sandbox edit→bare-commit→deny test |
| 5 — CHANGELOG + CLAUDE.md note + final conformance | ⏳ Pending | — | PR-tier finalization |

---

## Phase 1 — Decision doc + manual-recipe verifications

### Goal

Lock the 5 decisions (D1-D5 above) in a reference document. The three Claude-Code-runtime semantics claims this plan depends on (R1 chain composition, R2 reason length, R3 PreToolUse-before-tool) were already **empirically confirmed during research** against Claude Code 2.1.126 — see consolidated research §"Resolved unverified claims" items 1–3. Re-running them as executable canary scripts adds reproducibility cost (isolating tmp `.claude/settings.json` from parent session settings is non-trivial; `claude -p` invocations against tmp dirs are fragile) for zero new information.

This phase produces ONE artifact: the reference doc, with a "Phase 1 verifications (manual recipes)" subsection cataloguing the exact `claude -p '!<cmd>'` invocations users can re-run if they want to re-verify, the harness version under which they were last confirmed (2.1.126), and a Phase 5 conformance hook to re-run them if Claude Code is upgraded between Phase 1 and PR open.

NO code lands in `skills/`, `hooks/`, or `.claude/settings.json` in this phase.

### Work Items

- [ ] 1.1 — Author `references/skill-version-pretooluse-hook.md`. Body sections (in order):
  1. **Decisions D1-D5** copied verbatim from this plan's Decisions section (heading form `### D1 — …` so AC1's grep works).
  2. **Phase 1 verifications (manual recipes)** — three subsections (R1/R2/R3) each containing: (i) the empirical assertion verbatim from research consolidation §"Resolved unverified claims", (ii) the exact `claude -p '!<cmd>'` recipe a user can run to re-verify, (iii) `Last confirmed against: Claude Code 2.1.126`. State explicitly: "if `claude --version` reports a new version when Phase 5 runs, re-run these recipes; otherwise treat as authoritative."
  3. **Recursive risk: NONE.** "PreToolUse hooks run as subprocesses outside Claude Code's tool-dispatch loop; they cannot themselves invoke the Bash tool. Verified by construction."
  4. **`tests/run-all.sh` dispatcher pattern** — short subsection (3-5 lines) documenting the pattern: each test is invoked via `run_suite "<filename>" "tests/<filename>"`; addition is a single line. Reference for Phase 2.3 / Phase 4.4.

  The reference document is the single source of truth that subsequent phases cite — do NOT scatter D1-D5 rationale across phase prose.

- [ ] 1.2 — Read `tests/run-all.sh` and confirm the dispatcher pattern matches the prose written in 1.1 §4 above. If `tests/run-all.sh` has changed shape since this plan was drafted, update the reference doc's pattern documentation BEFORE committing.

- [ ] 1.3 — Verify the plan is registered in `plans/PLAN_INDEX.md` "Ready to Run". If absent, add a row matching the existing format. Idempotent.

### Design & Constraints

- **Per-phase commit boundary:** ONE commit at end of phase, scope = `references/skill-version-pretooluse-hook.md` + (if needed) `plans/PLAN_INDEX.md` row. Subject: `feat(plans): SKILL_VERSION_PRETOOLUSE_HOOK Phase 1 — decision doc`.
- **No code in `hooks/`, `skills/`, `tests/`, or `.claude/settings.json` in this phase.** No canary scripts. Verification is recipe-form in the reference doc.
- **No `--no-verify`.**

### Acceptance Criteria

- [ ] AC1 — `[ -f references/skill-version-pretooluse-hook.md ]` AND `grep -c '^### D[1-5] —' references/skill-version-pretooluse-hook.md` returns `5`.
- [ ] AC2 — `grep -c '^Last confirmed against: Claude Code' references/skill-version-pretooluse-hook.md` returns `3` (one per R1/R2/R3 subsection).
- [ ] AC3 — `grep -F 'Recursive risk: NONE' references/skill-version-pretooluse-hook.md` returns 1 match.
- [ ] AC4 — Reference doc contains a `tests/run-all.sh` dispatcher subsection AND its prose matches the actual `tests/run-all.sh` pattern (manual cross-check before commit).
- [ ] AC5 — `grep -n 'SKILL_VERSION_PRETOOLUSE_HOOK' plans/PLAN_INDEX.md` returns exactly one match.
- [ ] AC6 — `git diff --stat HEAD~1..HEAD` after the phase commit shows ONLY `references/skill-version-pretooluse-hook.md`, and optionally `plans/PLAN_INDEX.md`. No other paths.

### Dependencies

None. This phase is a pure precondition.

---

## Phase 2 — Hook script + JSON-escape function + unit tests

### Goal

Land `hooks/block-stale-skill-version.sh`, an executable PreToolUse Bash hook that:
1. Filters non-Bash tool invocations (early exit 0).
2. Extracts the `command` field from stdin via the canonical `sed` pattern from `block-unsafe-generic.sh:32-40` (verbatim, with the same fallback-to-$INPUT defensive scan if extraction fails).
3. Pattern-matches `git commit` (with all its forms: `git commit`, `git commit -m`, `git commit -am`, `git commit --amend`, `git commit --message=...`, env-var-prefixed `FOO=bar git commit ...`, leading whitespace, command-boundary anchored).
4. On match, calls `bash "$CLAUDE_PROJECT_DIR/scripts/skill-version-stage-check.sh"` (gated by `[ -x "$SCRIPT" ]`).
5. If the script exits 0 → emit nothing, exit 0 (allow).
6. If the script exits 1 → capture stderr, JSON-escape it via the pure-bash `json_escape` function, emit the deny envelope (verbatim shape from `block-unsafe-generic.sh:88` with the escaped reason), exit 0.
7. If the script is missing or not executable → emit nothing, exit 0 (fail-open is the right call: see Design & Constraints below).

Plus `tests/test-block-stale-skill-version.sh` with synthetic JSON inputs covering the success, miss, deny, and edge cases.

### Work Items

- [ ] 2.1 — Author `hooks/block-stale-skill-version.sh`. Skeleton:

  ```bash
  #!/bin/bash
  # block-stale-skill-version.sh — PreToolUse hook denying git commit when
  # staged skill files have stale metadata.version hash. See
  # references/skill-version-pretooluse-hook.md.
  set -u

  INPUT=$(cat)
  # Filter non-Bash invocations
  if [[ "$INPUT" != *'"tool_name":"Bash"'* ]] && [[ "$INPUT" != *'"tool_name": "Bash"'* ]]; then
    exit 0
  fi

  # Canonical command extraction (verbatim from block-unsafe-generic.sh:37)
  COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\"/"/g')
  [ -z "$COMMAND" ] && COMMAND="$INPUT"

  # Match `git commit` via two-stage tokenize-then-walk. Rationale: a
  # single regex that allows arbitrary git top-level flags (--no-pager,
  # --git-dir=/x, -P, -C path, -c k=v, --work-tree=/y, …) becomes a
  # combinatorial mess and was empirically shown bypassable in Round 2
  # finding N1 (e.g., `git --no-pager commit` slipped past the narrow
  # `(-C …|-c …)?` form). Tokenize on whitespace, skip env-var prefixes,
  # find literal `git`, then walk past every `-…`/`--…` flag (consuming
  # an extra token only for `-C` and `-c`, which take a separate arg —
  # all other top-level flags either embed their value with `=` or take
  # none) and check if the next token is `commit`.
  is_git_commit() {
    local cmd="$1"
    local -a TOKENS
    # shellcheck disable=SC2206
    read -ra TOKENS <<< "$cmd"
    local i=0 n=${#TOKENS[@]}
    # Skip env-var prefixes (KEY=VAL...) before any command.
    while [[ $i -lt $n && "${TOKENS[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      ((i++))
    done
    # Optional literal `env` prefix.
    [[ $i -lt $n && "${TOKENS[$i]}" == "env" ]] && ((i++))
    # Skip env-var prefixes after `env`.
    while [[ $i -lt $n && "${TOKENS[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      ((i++))
    done
    # Must see literal `git` (or quoted `"git"`/`'git'`).
    local g="${TOKENS[$i]:-}"
    g="${g%\"}"; g="${g#\"}"
    g="${g%\'}"; g="${g#\'}"
    [[ "$g" != "git" ]] && return 1
    ((i++))
    # Skip git's top-level flags. Conservative: any token starting with
    # `-`. `-C` and `-c` take a separate arg (consume next token too);
    # all other `--foo`, `--foo=bar`, `-X`, `-Xvalue` consume only the
    # flag token itself.
    while [[ $i -lt $n && "${TOKENS[$i]:0:1}" == "-" ]]; do
      case "${TOKENS[$i]}" in
        -C|-c) ((i+=2)) ;;
        *)     ((i+=1)) ;;
      esac
    done
    # Subcommand.
    [[ "${TOKENS[$i]:-}" == "commit" ]]
  }
  is_git_commit "$COMMAND" || exit 0

  # Guard against `set -u` + unset `$CLAUDE_PROJECT_DIR` (rare but
  # documented harness edge case). `${X:-$PWD}` falls back to cwd; if
  # the script is absent under the fallback path, `[ -x ]` trips the
  # fail-open below. Per N5 (Round 2): without the guard, `set -u`
  # would crash the hook → nonzero exit + empty stdout → silent
  # failure mode worse than fail-open.
  SCRIPT="${CLAUDE_PROJECT_DIR:-$PWD}/scripts/skill-version-stage-check.sh"
  [ -x "$SCRIPT" ] || exit 0  # fail-open: script absent (consumer pre-/update-zskills)

  # Run script; capture stderr (the STOP message); discard stdout.
  STDERR=$(bash "$SCRIPT" 2>&1 >/dev/null) && exit 0  # rc=0 means clean
  # Script exited non-zero — deny.

  json_escape() {
    # Pure-bash JSON string escape. Argument → stdout, no surrounding quotes.
    # Order: \ first, then ", then named control-char escapes.
    # `LC_ALL=C` makes ${var//pat/repl} byte-deterministic (no UTF-8 char
    # boundary surprises). Rare control bytes (0x00-0x1F) outside the
    # named escapes are STRIPPED rather than \u00XX-escaped: stage-check
    # stderr is ASCII text by inspection of skill-version-stage-check.sh,
    # so the strip path never triggers in practice but is a defense-in-
    # depth backstop against malformed input. See D4 in
    # references/skill-version-pretooluse-hook.md.
    local LC_ALL=C
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\b'/\\b}"
    s="${s//$'\f'/\\f}"
    # Strip remaining control bytes (0x00-0x1F).
    # POSIX char class works correctly under LC_ALL=C; the bash range
    # form `[$'\x00'-$'\x1f']` only matches the upper bound byte (0x1F),
    # NOT the range — verified empirically in Round 2 finding N2 (bytes
    # 0x01-0x1E pass through verbatim, producing invalid JSON with raw
    # control bytes → harness silently rejects → silent allow).
    s="${s//[[:cntrl:]]/}"
    printf '%s' "$s"
  }

  REASON=$(json_escape "$STDERR")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$REASON"
  exit 0
  ```

  Make executable: `chmod +x hooks/block-stale-skill-version.sh`.

- [ ] 2.2 — Author `tests/test-block-stale-skill-version.sh`. Synthetic-JSON unit tests following `tests/test-hooks.sh`'s pattern (pipe JSON to script, assert exit + stdout shape). Cases:
  - **C1: Non-Bash tool** → `{"tool_name":"Edit","tool_input":{...}}` → exit 0, stdout empty.
  - **C2: Non-git Bash** → `{"tool_name":"Bash","tool_input":{"command":"echo hello"}}` → exit 0, stdout empty.
  - **C3: `git status` (not commit)** → exit 0, stdout empty.
  - **C4: `git commit` with no skill files staged** (empty stage set, script exits 0) → exit 0, stdout empty.
  - **C5: `git commit` with stale-version skill staged** → exit 0, stdout contains valid JSON deny envelope with `permissionDecision":"deny"` AND escaped reason includes `STOP:` AND bump command.
  - **C6: `git commit -am`** → matches, script runs.
  - **C7: `git commit --amend`** → matches, script runs.
  - **C7a: `git -C /tmp/foo commit -m bar`** (multi-worktree form, used inside `skill-version-stage-check.sh` itself) → matches, script runs.
  - **C7b: `git -C /tmp/foo log`** → does NOT match (the `-C` allowance must not over-match non-commit subcommands).
  - **C7c: `git -c user.email=x@y.z commit -m msg`** → matches (the `-c key=val` form is tolerated by the tokenize-then-walk).
  - **C7d: `git --no-pager commit -m foo`** → matches (any `--…` top-level flag is consumed in the flag-skip loop). Per N1 (Round 2).
  - **C7e: `git --git-dir=/x commit`** → matches (long-flag with embedded `=value` is one token).
  - **C7f: `git -P commit`** → matches (short-form `--no-pager`).
  - **C7g: `git -C /tmp -c user.email=x commit`** → matches (mixed `-C` AND `-c`; tokenize-then-walk handles arbitrary combinations, unlike the earlier alternation form which only fired once).
  - **C7h: `git --git-dir=/x --work-tree=/y commit -m msg`** → matches (multiple long flags in series).
  - **C7i (negative): `git --no-pager log`** → does NOT match (subcommand check after flag-skip is `log`, not `commit`).
  - **C7j (negative): `git -C /tmp diff`** → does NOT match.
  - **C8: `FOO=bar git commit -m msg`** → matches (env-var prefix tolerated).
  - **C9: `   git commit` (leading whitespace)** → matches.
  - **C10: `echo "git commit"` (mention in echo arg)** → does NOT match (boundary anchor scopes to actual invocations; data-region redaction is NOT done here because the script's check is filesystem-state-driven, not argument-driven — even a false-positive match would invoke the script and the script would correctly return 0 if no stale skill is staged).
  - **C11: `git commit && git push`** → matches `git commit` (and the chained `git push` is a different concern, not gated here per D2).
  - **C12: Script missing** (rename or `chmod -x`, fail-open path) → exit 0, stdout empty.
  - **C12a: `unset CLAUDE_PROJECT_DIR`** (or `env -i bash hooks/...`) piped a `git commit` Bash invocation → exit 0, stdout empty (fail-open). Asserts the `${CLAUDE_PROJECT_DIR:-$PWD}` guard prevents `set -u` crash on unset env (Round 2 N5 fix).
  - **C13: Multi-line reason with `"` and `\` characters** → assert resulting JSON is parseable by `python3 -c 'import json,sys; json.loads(sys.stdin.read())'` (used here as ASSERTION ONLY, not as a runtime dep — the hook itself does NOT call python).
  - **C14: Reason containing multi-byte UTF-8 (e.g., `tëst skipped`)** → assert `json_escape` output round-trips through `python3 -c "import json,sys; json.loads(sys.stdin.read())"` AND the decoded string equals the original UTF-8 bytes (proves `LC_ALL=C` byte-mode preserves UTF-8 sequences intact).
  - **C15: Reason containing rare control bytes (`$'a\x01\x02\x07\x0Bb'`)** → after `json_escape` + JSON-decode via `python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["hookSpecificOutput"]["permissionDecisionReason"])'`, decoded reason equals `'ab'` (control bytes 0x01, 0x02, 0x07, 0x0B are stripped). Proves the POSIX `[[:cntrl:]]` class strips the full control range, NOT just the upper-bound byte (Round 2 N2 fix).

- [ ] 2.3 — Add `tests/test-block-stale-skill-version.sh` to `tests/run-all.sh` dispatcher.

- [ ] 2.4 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` and verify the new test file's cases all pass; full-suite count increases by exactly the new case count (26).

### Design & Constraints

- **Per-phase commit boundary:** ONE commit, scope = `hooks/block-stale-skill-version.sh` + `tests/test-block-stale-skill-version.sh` + addition to `tests/run-all.sh` (single `run_suite` line, per the dispatcher pattern documented in `references/skill-version-pretooluse-hook.md` §"`tests/run-all.sh` dispatcher pattern" from Phase 1.1). Subject: `feat(hooks): block-stale-skill-version PreToolUse hook + unit tests`.
- **Phase ordering: NO `skills/` edits in this phase.** The hook source itself is under `hooks/`, not `skills/`, so no skill version bump is required here. Phase 3 is the first phase that touches `skills/update-zskills/SKILL.md`. Per the per-phase versioning discipline (see Phase 3 / Phase 4 D&C), version bump and mirror MUST be the FINAL two operations of any phase that edits a SKILL.md.
- **NO `jq`** — `json_escape` is pure bash (per D4).
- **`python3` is allowed in tests; NOT in hook runtime.** The hook itself uses pure-bash `json_escape` per D4. Phase 2 unit tests AND Phase 4 sandbox tests MAY use `python3 -c 'import json,sys; json.loads(...)'` for JSON-validity assertions — `python3` is on every CI image and dev container, and using it as a JSON validator avoids reinventing a parser. The runtime/test distinction is enforced by AC8 below (`grep -F 'python' hooks/block-stale-skill-version.sh` returns 0).
- **NO `2>/dev/null` on critical operations** — the script invocation uses `STDERR=$(... 2>&1 >/dev/null)` which routes stderr to capture (not to /dev/null).
- **Fail-open on missing `scripts/skill-version-stage-check.sh`.** This is deliberate: a consumer pre-`/update-zskills` (Phase 4) has the hook but not yet the script; failing CLOSED would brick every `git commit` in those repos. Failing OPEN matches the prior-art convention (`block-unsafe-project.sh` reads its config at runtime and silently no-ops if config is absent). Phase 4 closes the install gap; Phase 5's CLAUDE.md note documents the temporary window for early adopters.
- **Match strategy — tokenize-then-walk (chosen over regex):** the hook tokenizes `$COMMAND` on whitespace, skips env-var prefixes, finds literal `git`, walks past every top-level flag (handling `-C path` and `-c k=v` as two-token consumes; all other `--foo`, `--foo=bar`, `-X` as single-token), and checks if the next token is `commit`. This robustly covers arbitrary git top-level flag combinations (`--no-pager`, `--git-dir=/x`, `-P`, mixed `-C path -c k=v`, `--git-dir=/x --work-tree=/y`, …) — all empirically demonstrated to bypass the earlier alternation-based regex (Round 2 finding N1). Tokenize-then-walk was chosen over a generalized regex for readability AND robustness against future flag additions; the regex form would still be combinatorial. Echo/printf args containing the literal string `git commit` do NOT match because `read -ra` on the outer command splits on whitespace and the matcher applies only to the command's leading position (verified by C10). Heredoc bodies and quoted commit messages are NOT pre-redacted (unlike `block-unsafe-generic.sh`'s data-region redaction) — because for THIS hook, even a hypothetical false-positive match harmlessly invokes the stage-check script, which is filesystem-state-driven and exits 0 on a clean stage. Adding redaction is unnecessary defensive code.
- **Test output capture:** `TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"; mkdir -p "$TEST_OUT"`.

### Acceptance Criteria

- [ ] AC1 — `[ -x hooks/block-stale-skill-version.sh ]`.
- [ ] AC2 — `bash tests/test-block-stale-skill-version.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns `0`.
- [ ] AC3 — All 26 cases pass: `grep -c '^PASS' "$TEST_OUT/.test-results.txt"` returns `26` (C1–C15 plus C7a/C7b/C7c/C7d/C7e/C7f/C7g/C7h/C7i/C7j plus C12a).
- [ ] AC4 — `grep -n 'test-block-stale-skill-version.sh' tests/run-all.sh` returns exactly one match AND it follows the canonical `run_suite "<filename>" "tests/<filename>"` shape.
- [ ] AC5 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns `0`; total case count increases by 26 vs HEAD~1.
- [ ] AC6 — `grep -F 'json_escape' hooks/block-stale-skill-version.sh` returns the function definition AND the call site.
- [ ] AC7 — `grep -F 'jq' hooks/block-stale-skill-version.sh` returns 0 matches (no jq).
- [ ] AC8 — `grep -F 'python' hooks/block-stale-skill-version.sh` returns 0 matches (no python in hook; only in test harness).
- [ ] AC9 — Synthetic deny output passes `python3 -c 'import json,sys; json.loads(sys.stdin.read())'` validation (case C13 assertion).
- [ ] AC10 — UTF-8 round-trip case C14 passes: input `tëst` survives `json_escape` + JSON-decode and equals the original string byte-for-byte.
- [ ] AC11 — `grep -F 'LC_ALL=C' hooks/block-stale-skill-version.sh` returns ≥ 1 match (locale guard present) AND `grep -F '[[:cntrl:]]' hooks/block-stale-skill-version.sh` returns ≥ 1 match (POSIX char class for control-byte strip per N2 fix).
- [ ] AC12 — Bypass-canary battery (Round 2 N1 expansion): all of C7a, C7c, C7d, C7e, C7f, C7g, C7h match (positive); C7b, C7i, C7j do NOT match (negative). All ten cases assert against `is_git_commit` directly via the test harness.

### Dependencies

Phase 1 complete. Reference doc exists with R1/R2/R3 manual recipes (research already empirically confirmed the chain-composition / reason-length / before-tool semantics; recipes catalogued for re-verification on Claude Code upgrade).

---

## Phase 3 — `.claude/settings.json` registration + canonical extension table

### Goal

Wire `hooks/block-stale-skill-version.sh` into zskills' own `.claude/settings.json` (so the hook fires for development sessions in this repo), and extend the canonical zskills-owned hook table at `skills/update-zskills/SKILL.md:882-888` so consumer installs pick it up via Step C's existing surgical-merge algorithm. Bump `skills/update-zskills/SKILL.md`'s `metadata.version` per the PR #175 enforcement chain.

### Work Items

Ordering matters this phase: all SKILL.md content edits FIRST, then version bump + mirror, then the `.claude/hooks/` mirror copy and `.claude/settings.json` registration LAST. The settings.json edit is deliberately the last file modified before commit — once the new hook is registered AND the script is in place, every subsequent `git commit` in this worktree is gated. If the bump-and-commit fails for an unrelated reason and we have to retry, doing the registration earlier could leave the recovery commit blocked. See Design & Constraints "Phase commit ordering."

- [ ] 3.1 — Edit `skills/update-zskills/SKILL.md` lines 882-888 (the canonical zskills-owned triples table). Append one row:

  | Event        | Matcher | Command literal                                                                  |
  |--------------|---------|----------------------------------------------------------------------------------|
  | PreToolUse   | Bash    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-stale-skill-version.sh"`          |

  The row count goes from 5 to 6. Update the prose at line 890 (`All 5 rows...`) to `All 6 rows...`. Update the explainer block at lines 842-851 (the install user-facing message) to mention `block-stale-skill-version.sh`:

  > Installing 3 safety hooks:
  > - **block-unsafe-generic.sh** — blocks destructive commands ...
  > - **block-unsafe-project.sh** — project-specific guards ...
  > - **block-stale-skill-version.sh** — denies `git commit` when staged skill files have a stale `metadata.version` hash; reuses `scripts/skill-version-stage-check.sh`.

- [ ] 3.2 — Update Step C of `skills/update-zskills/SKILL.md` (lines 816-840) to copy `hooks/block-stale-skill-version.sh` from `$PORTABLE/hooks/` to `.claude/hooks/block-stale-skill-version.sh` (no `.template`, no placeholder fill — flat copy, identical pattern to `block-unsafe-generic.sh`). Add a one-line bullet to the existing copy-list.

- [ ] 3.3 — Mirror `hooks/block-stale-skill-version.sh` to zskills' own runtime hook directory:

  ```bash
  cp hooks/block-stale-skill-version.sh .claude/hooks/block-stale-skill-version.sh
  chmod +x .claude/hooks/block-stale-skill-version.sh
  ```

  This matches the `block-unsafe-generic.sh` idiom (no `mirror-hook.sh` script exists; flat `cp` is the convention).

- [ ] 3.4 — Verify `git diff --cached --name-only` (after `git add` of all SKILL.md and `.claude/hooks/` edits, but BEFORE the SKILL.md version bump) shows only the expected paths and no skill-version drift on any other skill. This catches accidental cross-skill edits before the bump cements the wrong hash.

- [ ] 3.5 — Bump `skills/update-zskills/SKILL.md` `metadata.version` (FINAL content op for this phase): `today=$(TZ=America/New_York date +%Y.%m.%d); hash=$(bash scripts/skill-content-hash.sh skills/update-zskills); bash scripts/frontmatter-set.sh skills/update-zskills/SKILL.md metadata.version "$today+$hash"`. Then mirror: `bash scripts/mirror-skill.sh update-zskills`.

- [ ] 3.6 — Edit `.claude/settings.json` LAST: append a third entry to the existing `PreToolUse` `Bash` matcher's `hooks` array (after the two existing entries at lines 8-15):

  ```json
  {
    "type": "command",
    "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-stale-skill-version.sh\"",
    "timeout": 5
  }
  ```

  Verify with `python3 -c 'import json; json.load(open(".claude/settings.json"))'` BEFORE staging.

- [ ] 3.7 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` — verify all tests still pass (no regressions). Conformance test specifically confirms the new mirror is clean and the version line is fresh.

- [ ] 3.8 — Verify the hook fires in zskills' own session by opening a sandbox child session inside the worktree, editing a skill body without bumping, and running `git commit -am test` — observe deny envelope in the harness output. Log result to `tests/canary-zskills-self-fires.txt` (one-shot, not a regression test).

### Design & Constraints

- **Per-phase commit boundary:** ONE commit, scope = `.claude/settings.json` + `.claude/hooks/block-stale-skill-version.sh` (mirror) + `skills/update-zskills/SKILL.md` (3 edit sites: extension table + explainer + Step C copy bullet + version bump) + `.claude/skills/update-zskills/SKILL.md` (mirror via `mirror-skill.sh`). Subject: `feat(hooks): wire block-stale-skill-version into zskills + canonical table`.
- **Phase commit ordering (LOAD-BEARING):** version bump and mirror MUST be the FINAL two operations among `skills/`-side content. Settings.json registration is the LAST file edit overall — once both the script-mirror AND settings.json registration land, every subsequent `git commit` in this worktree is gated by the new hook. **Recovery rule (softened in Round 2 per N4):** if the phase commit fails on first attempt with a **stage-check deny**, READ the deny message:
  - If it identifies a **sibling skill** (any skill OTHER than `update-zskills`) needing bump: bump that sibling, re-stage, retry. Sibling-skill bumps don't conflict with the just-registered version of `update-zskills`, so retry is safe and is the obvious correct action the deny message itself recommends.
  - If it identifies `update-zskills/SKILL.md` itself as stale (only happens if the bumped hash didn't capture all edits — e.g., a last-minute prose tweak after the hash was computed): revert the settings.json registration line, drop the partial stage, restart the phase from a clean working tree. This is the deadlock case the no-retry rule was originally designed for.
  - For non-deny failure modes (network error pushing to remote, hook crash, etc.): diagnose externally without retry inside the worktree.

  Document any retry's cause in the commit message footer (e.g., `Retry: bumped sibling skill <name> per stage-check deny`).
- **`mirror-skill.sh` discipline:** any source skill edit (here: `skills/update-zskills/`) requires `bash scripts/mirror-skill.sh update-zskills` to update the `.claude/skills/update-zskills/` mirror. The version bump and mirror must be in the SAME commit (per PR #175 conformance test §3 mirror parity).
- **No edits to `hooks/block-stale-skill-version.sh` itself** in this phase — only the mirror copy under `.claude/hooks/`.
- **`.claude/settings.json` JSON-validity:** verify with `python3 -c 'import json; json.load(open(".claude/settings.json"))'` BEFORE commit (per work item 3.6). The existing PostToolUse `Edit`/`Write` blocks and Agent matcher must be untouched.
- **No `2>/dev/null` on `mirror-skill.sh`** or any verification step.
- **No `--no-verify`.**

### Acceptance Criteria

- [ ] AC1 — `python3 -c 'import json; d=json.load(open(".claude/settings.json")); assert any("block-stale-skill-version.sh" in h["command"] for ev in d["hooks"]["PreToolUse"] for h in ev.get("hooks", []))'` returns 0.
- [ ] AC2 — `[ -x .claude/hooks/block-stale-skill-version.sh ] && diff -q hooks/block-stale-skill-version.sh .claude/hooks/block-stale-skill-version.sh` returns 0 (mirror is byte-identical).
- [ ] AC3 — `grep -c 'block-stale-skill-version.sh' skills/update-zskills/SKILL.md` returns ≥ 3 (extension-table row + Step C copy bullet + explainer block).
- [ ] AC4 — `grep -E 'All [0-9]+ rows carry' skills/update-zskills/SKILL.md` matches `All 6 rows`.
- [ ] AC5 — Conformance test `bash tests/test-skill-conformance.sh` passes; `metadata.version` of `skills/update-zskills/SKILL.md` matches `^[0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])\+[0-9a-f]{6}$` AND the hash equals `bash scripts/skill-content-hash.sh skills/update-zskills`.
- [ ] AC6 — Mirror parity: `diff -r skills/update-zskills .claude/skills/update-zskills` returns no differences (per conformance §3).
- [ ] AC7 — `bash tests/run-all.sh` exits 0; case count is at least the Phase 2 baseline.
- [ ] AC8 — One-shot sandbox check (3.8) produced a deny envelope. Result logged.
- [ ] AC9 — Phase 3 commit succeeded with at most ONE retry; if a retry happened, the cause is documented in the commit message footer (e.g., `Retry: bumped sibling skill <name> per stage-check deny`). The recovery rule (per Round 2 N4 fix) distinguishes sibling-skill stage-check denies (safe to retry) from `update-zskills`-self denies (must restart phase from clean tree).

### Dependencies

Phase 2 complete. The hook script must exist and be unit-tested before wiring.

---

## Phase 4 — Helper-script install flow extension + sandbox integration test

### Goal

Close research finding F1: extend `/update-zskills`'s install loop to copy `scripts/skill-version-stage-check.sh`, `scripts/skill-content-hash.sh`, `scripts/frontmatter-get.sh`, and `scripts/frontmatter-set.sh` from `$PORTABLE/scripts/` to consumer `scripts/`. Without this, the new hook fails-open on every consumer (per Phase 2's deliberate fail-open policy) and the entire enforcement chain is dead-on-arrival downstream. Plus a sandbox integration test that proves end-to-end: install → edit skill → bare commit → DENY.

### Work Items

Ordering: helper-script driver + Step B prose + sandbox test FIRST, then version bump + mirror LAST. Per the per-phase versioning discipline (CLAUDE.md `## Skill versioning`: "Edits to a skill body, frontmatter, or any regular file under the skill directory MUST bump this field"), the bump must be the final operation that touches `skills/update-zskills/`. Multiple bumps within a single PR are normal — each phase that edits a SKILL.md bumps immediately, and per-phase commits accumulate.

- [ ] 4.1 — Author `scripts/install-helpers-into.sh <consumer-root>`. A small driver that:
  - Validates `$1` is provided and is an existing directory. (Note: per Round 2 N6 fix, the `.git` requirement is DROPPED — `cp` to a nonexistent destination already fails with a clear error; requiring `.git` was defense-against-typo, not load-bearing.)
  - Ensures `<consumer-root>/scripts/` exists: `mkdir -p "<consumer-root>/scripts"` BEFORE the cp loop. Per Round 2 N7 — fresh installs (pre-SCRIPTS_INTO_SKILLS layout) may have no `scripts/` dir, in which case `cp` would fail with "No such file or directory."
  - Copies the 4 helper scripts (`skill-version-stage-check.sh`, `skill-content-hash.sh`, `frontmatter-get.sh`, `frontmatter-set.sh`) from `$(dirname "$0")/../scripts/` (resolved via `realpath` or `cd … && pwd`) to `<consumer-root>/scripts/`. The driver lives at `$PORTABLE/scripts/install-helpers-into.sh` and is invoked SOURCE-SIDE — no consumer-local copy of the driver itself is needed (avoids chicken-and-egg: the driver would have to copy itself before invoking, which is awkward). See N3 for rationale.
  - **Collision policy** (per Round 2 N3): for each helper `$h`:

    ```
    src="$PORTABLE/scripts/$h"
    dst="<consumer-root>/scripts/$h"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
      echo "  SKIP: $h (identical)"
      continue
    fi
    cp "$src" "$dst" && chmod +x "$dst" && echo "  COPY: $h"
    ```

    Identical pre-existing files → SKIP (no-op log). Different content → COPY (overwrite). Never prompt; never error on collision; log every action.
  - `chmod +x` is bundled into the COPY branch; SKIP path leaves the existing file's mode untouched.
  - Echoes one line per file for visible logging (`SKIP:` or `COPY:`).
  - Exits 0 on success, non-zero on any `cp`/`chmod`/`mkdir` failure (NO `2>/dev/null`).

  This driver is the SHARED CODE PATH between (a) the sandbox integration test (work item 4.3) and (b) `/update-zskills` Step C prose (work item 4.2). Sharing the code path closes the C2 review finding: tests prove the binary works AND the install path works, because they invoke the same script.

- [ ] 4.2 — Read `skills/update-zskills/SKILL.md` **Step C** (the hook/script-copy block at line 816, "Fill hook gaps") and the surrounding install prose. (Round 2 N3 corrected the prior citation: Step B is rules-render, not script-install.) Identify the canonical insertion point alongside the existing `block-unsafe-project.sh.template` and `scripts/test-all.sh` copy bullets. Update the prose to invoke `bash "$PORTABLE/scripts/install-helpers-into.sh" "$CONSUMER_ROOT"` as part of the Step C install sequence — invoked SOURCE-SIDE from `$PORTABLE`, no consumer-local copy of the driver itself. Add an explanatory paragraph: "These four helpers are dependencies of `block-stale-skill-version.sh` (the PreToolUse hook installed in this same Step C). Without them, the hook fails-open on every commit, defeating the lock-step skill-version enforcement chain. The `install-helpers-into.sh` driver is the same one exercised by `tests/test-block-stale-skill-version-sandbox.sh`, so the install path and the test path share code. Collision policy: existing identical helpers are skipped; existing different helpers are overwritten; logged either way."

- [ ] 4.3 — Author `tests/test-block-stale-skill-version-sandbox.sh`: end-to-end sandbox integration test. Steps:
  1. `TMP=$(mktemp -d -p /tmp zskills-sandbox.XXXX)`; `trap 'rm -rf "$TMP"' EXIT INT TERM`.
  2. Initialize a git repo in `$TMP/consumer`. Seed a fake `skills/foo/SKILL.md` with valid frontmatter and `metadata.version: "2026.05.02+aaaaaa"` (placeholder hash; doesn't need to match real content for this test).
  3. **Run the shared install driver:** `bash "$REPO_ROOT/scripts/install-helpers-into.sh" "$TMP/consumer"`. Assert exit 0.
  4. Verify all 4 helpers landed: `[ -x $TMP/consumer/scripts/skill-version-stage-check.sh ] && [ -x $TMP/consumer/scripts/skill-content-hash.sh ] && [ -x $TMP/consumer/scripts/frontmatter-get.sh ] && [ -x $TMP/consumer/scripts/frontmatter-set.sh ]`.
  5. Manually replicate the hook + settings.json install (the prose-only portion of `/update-zskills`): `cp hooks/block-stale-skill-version.sh "$TMP/consumer/.claude/hooks/"; chmod +x "$TMP/consumer/.claude/hooks/block-stale-skill-version.sh"`. Write a minimal `$TMP/consumer/.claude/settings.json` with the PreToolUse `Bash` entry pointing at the consumer's hook.
  6. Verify settings.json validity: `python3 -c 'import json; d=json.load(open("'"$TMP"'/consumer/.claude/settings.json")); assert any("block-stale-skill-version.sh" in h["command"] for ev in d["hooks"]["PreToolUse"] for h in ev.get("hooks", []))'`.
  7. **Synthetic-JSON deny test:** edit `$TMP/consumer/skills/foo/SKILL.md` body (no version bump), `git -C $TMP/consumer add skills/foo/SKILL.md`, then pipe a synthetic `{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}` into the consumer's hook with `CLAUDE_PROJECT_DIR=$TMP/consumer`. Assert: stdout contains `permissionDecision":"deny"` AND, after JSON-decoding the reason via `python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["hookSpecificOutput"]["permissionDecisionReason"])'`, the decoded reason contains `STOP:`.
  8. **Negative test:** revert the body (or bump the version correctly), re-stage, re-pipe. Assert: stdout empty (allow).
  9. Cleanup verification: explicit `rm -rf "$TMP" && [ ! -d "$TMP" ] && echo "cleanup OK"` (do NOT rely solely on trap; verify the directory is actually gone).

  Note: this test does NOT invoke `claude -p` — it directly pipes JSON to the installed hook script, same pattern as `tests/test-hooks.sh`. The Phase 1 reference doc's manual recipes already establish that the harness composes hooks correctly; this test proves install + invocation against the shared driver.

- [ ] 4.4 — Add `tests/test-block-stale-skill-version-sandbox.sh` to `tests/run-all.sh` via `run_suite "test-block-stale-skill-version-sandbox.sh" "tests/test-block-stale-skill-version-sandbox.sh"` (matching the dispatcher pattern documented in Phase 1's reference doc).

- [ ] 4.5 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` and confirm exit 0. This catches drift between Phase 2 unit tests and the new sandbox test.

- [ ] 4.6 — Bump `skills/update-zskills/SKILL.md` `metadata.version` (FINAL content op for this phase): same recipe as Phase 3.5 (`today=$(...); hash=$(...); frontmatter-set ...`). Mirror with `bash scripts/mirror-skill.sh update-zskills`. Per CLAUDE.md `## Skill versioning`, multiple bumps within a single PR are normal — each phase that edits a SKILL.md MUST bump immediately; the Phase 3 + Phase 4 bumps accumulate in the PR's per-phase commits.

### Design & Constraints

- **Per-phase commit boundary:** ONE commit, scope = `scripts/install-helpers-into.sh` + `skills/update-zskills/SKILL.md` (Step B prose extension + version bump) + `.claude/skills/update-zskills/SKILL.md` mirror + `tests/test-block-stale-skill-version-sandbox.sh` + `tests/run-all.sh` registration. Subject: `feat(update-zskills): install skill-version helpers + sandbox integration test`.
- **Phase commit ordering (LOAD-BEARING, same rule as Phase 3):** version bump and mirror MUST be the FINAL two operations of this phase, AFTER all SKILL.md content edits and AFTER the install driver and sandbox test are written. The hook installed in Phase 3 is now active in this worktree. **Recovery rule (softened in Round 2 per N4, mirrors Phase 3):** if the bump+commit fails with a stage-check deny on a sibling skill, bump it and retry; document the cause in the commit message footer. If the deny identifies `update-zskills/SKILL.md` itself, restart the phase from a clean working tree. Other failure modes: diagnose externally without in-worktree retry.
- **`mirror-skill.sh` discipline:** the version bump in 4.6 + Step B prose extension in 4.1/4.2 ARE source skill edits, so `bash scripts/mirror-skill.sh update-zskills` MUST run in the same commit.
- **Shared install code path (closes C2):** `scripts/install-helpers-into.sh` is invoked by both `tests/test-block-stale-skill-version-sandbox.sh` (work item 4.3) AND `/update-zskills` Step C/D prose (work item 4.2). The test does NOT manually replicate the helper-script install — it calls the same driver the real install path uses. If the driver is broken, both surfaces fail together (visible signal, no false greens).
- **Sandbox cleanup is mandatory.** `trap 'rm -rf "$TMP"' EXIT INT TERM` AND explicit post-test verification `rm -rf "$TMP" && [ ! -d "$TMP" ] && echo "cleanup OK"`. No `2>/dev/null` on the rm. Verify the directory is gone — do not assume the trap fired correctly (per CLAUDE.md "Never suppress errors on operations you need to verify").
- **Sandbox test runs in CI.** Add to `tests/run-all.sh` per the dispatcher pattern in Phase 1's reference doc.
- **`python3` allowed in tests, NOT in hook:** same rule as Phase 2 D&C. The sandbox test uses `python3 -c 'import json …'` for JSON decoding of the deny envelope; the hook itself uses pure-bash `json_escape`.
- **No `--no-verify`. No `2>/dev/null` on critical ops.**

### Acceptance Criteria

- [ ] AC1 — `[ -x scripts/install-helpers-into.sh ]` AND `bash scripts/install-helpers-into.sh /tmp/install-helpers-into-smoke-$$` succeeds against a freshly-`mkdir`ed throwaway dir (no `.git` required per N6 fix; smoke test verifies the driver creates `scripts/` via `mkdir -p` then copies all 4 helpers; clean up after). AC also asserts `[ -d /tmp/install-helpers-into-smoke-$$/scripts ]` post-install (N7 guarantee for fresh repos with no prior `scripts/`).
- [ ] AC2 — `grep -F 'install-helpers-into.sh' skills/update-zskills/SKILL.md` returns ≥ 1 match (Step B prose references the shared driver).
- [ ] AC3 — `bash tests/test-block-stale-skill-version-sandbox.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns `0`. Output contains `deny on stale-version skill commit`, `allow after correct bump`, and `cleanup OK`.
- [ ] AC4 — `metadata.version` of `skills/update-zskills/SKILL.md` is fresh (today's date) AND its hash matches `bash scripts/skill-content-hash.sh skills/update-zskills`.
- [ ] AC5 — Mirror parity: `diff -r skills/update-zskills .claude/skills/update-zskills` returns no differences.
- [ ] AC6 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns 0.
- [ ] AC7 — `grep -n 'test-block-stale-skill-version-sandbox.sh' tests/run-all.sh` returns exactly one match AND it follows the `run_suite` dispatcher pattern.
- [ ] AC8 — Phase 4 commit succeeded with at most ONE retry, with cause documented in the commit message footer if a retry happened (same softened rule as Phase 3 AC9, per Round 2 N4 fix).
- [ ] AC9 — Test/install share-the-driver invariant: `grep -F 'install-helpers-into.sh' tests/test-block-stale-skill-version-sandbox.sh` returns ≥ 1 match (the sandbox test invokes the same driver the install prose references).
- [ ] AC10 — Collision-policy assertions (Round 2 N3): the sandbox test pre-creates `<consumer-root>/scripts/skill-version-stage-check.sh` with **identical** content to the source — driver run logs `SKIP:` and leaves the file untouched (same mtime/inode if cp would have been a no-op via cmp gate). Then it modifies the file content and re-runs — driver logs `COPY:` and the file content matches the source after.
- [ ] AC11 — Phase 4.2 cites Step C, not Step B (Round 2 N3 correction): `grep -nE 'Step (B|C)' plans/SKILL_VERSION_PRETOOLUSE_HOOK.md` in the Phase 4 section shows only "Step C" referencing the install loop.

### Dependencies

Phase 3 complete. The hook is wired in zskills (proves the registration shape), and the canonical extension table has the new row (proves the install path knows what to install).

---

## Phase 5 — CHANGELOG + CLAUDE.md note + final conformance

### Goal

Document the new structural backstop, mark the plan complete, and run the full PR-tier gate (tests + conformance + lint) to surface any cross-phase drift before opening the PR.

### Work Items

- [ ] 5.1 — Append a CHANGELOG entry (top of `CHANGELOG.md`) summarizing the change. Format matches existing entries:

  ```
  ## YYYY-MM-DD — block-stale-skill-version PreToolUse hook (#TBD)
  - Add `hooks/block-stale-skill-version.sh`: PreToolUse Bash hook denying `git commit` when staged skill files have stale `metadata.version` hash. Wraps `scripts/skill-version-stage-check.sh`.
  - Wired in zskills `.claude/settings.json` and shipped to consumers via `/update-zskills` (canonical extension table extended; 4 helper scripts now copied via the new shared `scripts/install-helpers-into.sh` driver: `skill-version-stage-check.sh`, `skill-content-hash.sh`, `frontmatter-get.sh`, `frontmatter-set.sh`).
  - Closes the lock-step gap: bare `git commit` (bypassing `/commit`) is now blocked locally; CI is no longer the only mechanical safety net.
  - Decisions: flat hook (no `.template`); commit-only gating (push gating dropped per F2 design analysis); `/commit` Phase 5 step 2.5 retained for defense-in-depth; pure-bash JSON escape (no `jq`, no Python). See `references/skill-version-pretooluse-hook.md`.
  - **Rollout window note:** consumers who installed Phase 3's hook before Phase 4's helper-script ship would silently fail-open until they re-ran `/update-zskills`. Mitigated by shipping Phases 3 and 4 in the SAME PR with NO intermediate release tag — every consumer that pulls this PR gets the hook AND the helpers atomically.
  ```

- [ ] 5.2 — Append a one-paragraph note to `CLAUDE.md`'s `## Skill versioning` section (after the existing paragraph):

  > **PreToolUse backstop.** A fourth enforcement point — `hooks/block-stale-skill-version.sh` — fires on every `git commit` Bash invocation in any Claude Code session. It reuses `scripts/skill-version-stage-check.sh` and emits a deny envelope on drift. This closes the bare-`git commit` bypass: `/commit` step 2.5 covers `/commit` invocations, and the hook covers everything else. `git push` is NOT gated locally (see `references/skill-version-pretooluse-hook.md` D2 for rationale; CI's `test-skill-conformance.sh` is the push-time backstop).

- [ ] 5.3 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` and confirm 0 failures. Total case count vs main: +26 (Phase 2) + sandbox test cases (Phase 4).

- [ ] 5.4 — `bash tests/test-skill-conformance.sh` — confirm version frontmatter section, mirror parity section, and cleanliness section all pass. `update-zskills` mirror must be byte-identical.

- [ ] 5.5 — Re-verify Claude Code harness assumptions: run `claude --version`. **Comparison is at MAJOR.MINOR granularity** (Round 2 N8 fix): re-run the three manual recipes only when the MAJOR or MINOR component differs from the recorded value (last confirmed: 2.1.x). Patch-version drift (e.g., 2.1.126 → 2.1.127) is treated as authoritative — patch bumps don't change harness contracts. **CI-skip:** if `command -v claude` does not succeed (CI image has no `claude` binary), AC5 is skipped — the conformance test (`tests/test-skill-conformance.sh`) is the CI-side backstop. Update `references/skill-version-pretooluse-hook.md` "Last confirmed against" lines only if a real MAJOR.MINOR drift triggers the re-run.

- [ ] 5.6 — **Surface related pre-existing bugs (different routes per scope).** Per CLAUDE.md "Skill-framework repo — surface bugs, don't patch":
  - **block-unsafe-project.sh:404 over-matching → DRAFT a hardening plan, NOT another issue.** The bare `git[[:space:]]+commit` regex at line 404 lacks boundary anchoring + data-region redaction (DA's reproducer: heredoc bodies / grep patterns containing the literal `git commit` trip the hook). **Same root cause as Plan B's own evolution** (Round 1 regex extension → Round 2 tokenize-then-walk pivot): regex-based command-classification is fundamentally fragile. PR #73 (Issue #58) and PR #87 (Issue #81) already patched this hook for prior over-match incidents; filing another `404`-specific issue would queue a third patch in a pile rather than fix the class. Instead: in PR body and CHANGELOG, recommend `/draft-plan plans/BLOCK_UNSAFE_HARDENING.md` as a follow-up — scope is the tokenize-then-walk pivot for `block-unsafe-project.sh` + `block-unsafe-generic.sh` command-detection, plus a data-region redaction pass that handles heredoc bodies + quoted args uniformly. Do NOT file a `404`-specific issue (it would add to the pile). The follow-up plan, when authored, will reference DA's reproducer + the prior-patch trail.
  - **skill-version-stage-check.sh STOP message ambiguity → file an issue (UX nit, not architectural).** File issue titled `skill-version-stage-check.sh STOP message: same text for "didn't bump" vs "didn't stage bump"`. Body references `scripts/skill-version-stage-check.sh:91-93`. Mark as UX clarity, not-blocking-this-plan. This one IS appropriate for an issue — it's a one-line `[ -z "$staged_ver_was_set_initially" ] && hint="(SKILL.md not staged — git add it)"` fix, not a design pivot.

- [ ] 5.7 — Read `plans/PLAN_INDEX.md`. Update the SKILL_VERSION_PRETOOLUSE_HOOK row's status column from `Ready` (or whatever current) to `Complete`. Update plan frontmatter `status:` from `active` to `complete` and add `completed: <today>`.

- [ ] 5.8 — Open the PR (Landing mode: PR per the blockquote). PR body includes:
  - Summary of the 5 phases.
  - The 5 decision summaries (D1-D5) verbatim.
  - Test plan checkboxes per `feedback_pr_test_plan_checkboxes`: items already exercised in the work session get `[x]`, items requiring manual verification get `[ ]` with the verification command annotated.
  - Cross-link to `plans/SKILL_VERSIONING.md` (PR #175) for context.
  - Links to the two surfaced issues from 5.6.

### Design & Constraints

- **Per-phase commit boundary:** ONE commit, scope = `CHANGELOG.md` + `CLAUDE.md` + `plans/SKILL_VERSION_PRETOOLUSE_HOOK.md` (status flip) + `plans/PLAN_INDEX.md` (status flip) + (if Claude Code version changed since Phase 1) `references/skill-version-pretooluse-hook.md`. Subject: `docs(plans): SKILL_VERSION_PRETOOLUSE_HOOK Phase 5 — CHANGELOG + CLAUDE.md + completion`.
- **No skill or hook edits in this phase.** All implementation is closed by Phase 4.
- **No `--no-verify`.** If pre-commit hook fails (it shouldn't — all bumps are in earlier phases), STOP and diagnose; never bypass.
- **PR test plan scope per `feedback_pr_test_plan_scope`:** check items the work session exercised; do NOT include downstream-only items (e.g., "verify in production after release") — those are scope-creep, not thoroughness.
- **CI is the final verifier per `feedback_check_ci_before_merge`:** local green ≠ CI green. After push, run `gh pr checks <N> --watch` and block on green CI before saying "ready to ship."

### Acceptance Criteria

- [ ] AC1 — `head -20 CHANGELOG.md | grep -F 'block-stale-skill-version'` returns ≥ 1 match.
- [ ] AC2 — `grep -F 'PreToolUse backstop' CLAUDE.md` returns 1 match in the `## Skill versioning` section.
- [ ] AC3 — `bash tests/run-all.sh` exits 0; case count ≥ baseline + 26 (Phase 2 unit cases) + sandbox-test cases (Phase 4).
- [ ] AC4 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC5 — When `command -v claude` succeeds: `claude --version` MAJOR.MINOR matches the value recorded in `references/skill-version-pretooluse-hook.md` §"Phase 1 verifications" (patch drift is authoritative, not a re-run trigger — Round 2 N8 fix). If MAJOR or MINOR drifted, the manual recipes were re-run and the reference doc updated. When `command -v claude` fails (e.g., CI image), AC5 is SKIPPED — the conformance test (AC4) is the backstop.
- [ ] AC6 — Plan frontmatter `status: complete`; `plans/PLAN_INDEX.md` row in "Complete" section.
- [ ] AC7 — Per work item 5.6 split routing: ONE GitHub issue filed (skill-version-stage-check.sh STOP message ambiguity, the UX nit). The block-unsafe-project.sh:404 over-matching is NOT filed as an issue (would queue a third patch in a pile per PR #73 / #87 pattern); instead, the PR body and CHANGELOG entry recommend `/draft-plan plans/BLOCK_UNSAFE_HARDENING.md` as the follow-up route, citing DA's reproducer + the prior-patch trail. AC asserts: (a) `gh issue list --search 'STOP message' --state open` returns ≥ 1 issue; (b) PR body contains the `/draft-plan plans/BLOCK_UNSAFE_HARDENING.md` recommendation verbatim; (c) NO issue exists matching `gh issue list --search 'block-unsafe-project.sh:404' --state open` (negative assertion to lock the routing decision).
- [ ] AC8 — **Phase 3 and Phase 4 commits are on the same PR** — verify with `gh pr view <N> --json commits | grep -c '<Phase3-SHA>\|<Phase4-SHA>'` returning `2`. Round 2 N9 reframed this from `git tag --contains` (a temporal-state query that can be falsified post-hoc by adding a tag later) to a same-PR invariant; this is the same rollout-window mitigation in the CHANGELOG (Phase 3 hook + Phase 4 helpers ship atomically), now expressed as a falsifiable check against the actual PR.
- [ ] AC9 — PR opened; `gh pr checks <N>` shows all CI green; `gh pr view <N>` body contains the 5 decision summaries.

### Dependencies

Phase 4 complete. All implementation is shipped; this phase is documentation + final gate.

---

## Plan Quality

| Round | Reviewer Findings | Devil's Advocate Findings | After Dedup | Resolved |
|-------|-------------------|---------------------------|-------------|----------|
| 1     | 12                | 10                        | 17          | 16       |
| 2     | 7                 | 5                         | 10          | 10       |

### Round History

**Round 1 (2026-05-02):**

Convergence (both reviewers): C1, C2, C3.
Reviewer-only: R1, R6, R7, R8, R9, R10, R11, R12.
DA-only: D3, D6, D7, D8, D9, D10.

Resolved:
- C1 (regex bypass `git -C <path> commit`) — Phase 2.1 regex extended to tolerate `-C <path>` and `-c <key>=<val>` between `git` and `commit`; Phase 2.2 cases C7a/C7b/C7c added; AC12 added.
- C2 (sandbox/install harness bypass) — Phase 4.1 introduces `scripts/install-helpers-into.sh` shared between sandbox test (4.3) and `/update-zskills` Step C/D prose (4.2); AC9 enforces the share-the-driver invariant.
- C3 (Phase 3/4 double-bump ordering trap) — both phases reordered: SKILL.md content edits FIRST, version bump + mirror SECOND-TO-LAST, settings.json registration LAST in Phase 3; D&C "Phase commit ordering" bullet added to both phases; AC9 (Phase 3) and AC8 (Phase 4) require first-attempt commit success with abort-on-retry guidance.
- R1 (`json_escape` locale + per-char loop fragility) — `LC_ALL=C` added; per-char loop dropped; control-byte strip path replaces `\u00XX` escape; D4 prose updated; new test C14 (UTF-8 round-trip) and AC10/AC11 added.
- R6 (D2 language hygiene) — D2 now appends "prompt Goal language was overbroad; we honor the singular success criterion."
- R7 (mirror copy command unspecified) — Phase 3.3 specifies the `cp + chmod +x` idiom matching `block-unsafe-generic.sh`.
- R8 (AC1 grep regex format mismatch) — Decisions section reformatted as `### D1 — …` … `### D5 — …` headings; reference doc inherits the same format; AC1 grep `^### D[1-5] —` works as-spec.
- R9 (canary harness reproducibility) — canary scripts dropped; replaced with manual-recipe subsection in `references/skill-version-pretooluse-hook.md` plus Phase 5.5 re-verification gate keyed off `claude --version`.
- R10 (`python3` in tests acceptable but not declared) — Phase 2 + Phase 4 D&C explicitly carve out the test/runtime distinction; AC8 (Phase 2) keeps the hook python-free.
- R11 (recursive risk not explicitly ruled out) — reference doc gains a "Recursive risk: NONE" subsection; AC3 (Phase 1) requires the literal string.
- R12 (`/land-pr` rollout window) — D2 appends a transient-rollout-window paragraph; CHANGELOG (5.1) and Phase 5 AC8 (no-tag-between-phases) close the loop.
- D3 (block-unsafe-project.sh:404 over-matching) — Phase 5.6 surface-only: post-PR-#182-merge, work item 5.6 redirected from "file an issue" to "recommend `/draft-plan plans/BLOCK_UNSAFE_HARDENING.md`" because PR #73 (Issue #58) and PR #87 (Issue #81) already patched this hook for prior over-match incidents — filing another `404`-specific issue would queue a third patch in a pile rather than fix the regex-fragility class. Same root cause as Plan B's own Round-1→Round-2 evolution (regex extension → tokenize-then-walk pivot).
- D6 (json_escape unicode-escape dead code) — resolved by R1's preferred fix (loop dropped, no dead path remains).
- D7 (`tests/run-all.sh` dispatcher pattern unverified) — Phase 1.1 §4 + 1.2 read `tests/run-all.sh` and document the pattern in the reference doc; Phase 2 AC4 and Phase 4 AC7 require new test invocations to follow it; verified in Refiner's pre-edit pass that pattern is `run_suite "<name>" "tests/<name>"`.
- D8 (rollout window not in CHANGELOG) — Phase 5.1 appends rollout-window paragraph; Phase 5 AC8 enforces no-tag-between-Phase-3-and-Phase-4-commits.
- D9 (STOP message ambiguity) — Phase 5.6 surface-only: file GitHub issue; not in scope.
- D10 (phantom memory citation `feedback_per_skill_mirror_discipline`) — verified phantom (no match in prompt, research, or memory dir); citation removed from Phase 4.6; replaced with plain-language reference to CLAUDE.md `## Skill versioning`.

Justified-not-fixed: none (all 17 deduped findings resolved).

New gaps introduced: none material. Notable cross-references after the Phase 4 work-item renumber (was 4.1-4.6, now still 4.1-4.6 but with the sandbox test moved from former 4.4 to current 4.3 and the bump moved from former 4.3 to current 4.6): Phase 1 `tests/run-all.sh` dispatcher subsection is now a load-bearing reference for Phase 2.3 and Phase 4.4 (drift between the doc and `tests/run-all.sh` would silently break the AC pattern grep — Phase 1.2 explicitly cross-checks). Phase 3 work items renumbered from 3.1-3.6 to 3.1-3.8 to make the "settings.json LAST" ordering and the staging-verification step explicit.

**Round 2 (2026-05-02):**

Round-1-fix verifications: C1, C2, C3, R1 all surfaced new defects on re-examination; R8 holds.

Round-2 new findings (10 deduped, N1-N10):
- N1 (HIGH) — regex still bypassable for `--no-pager`/`--git-dir=`/`-P`/mixed `-C path -c k=v`/etc.; verified empirically.
- N2 (HIGH) — bash strip range pattern `${s//[$'\x00'-$'\x1f']/}` empirically broken (only matches the upper-bound byte 0x1F under LC_ALL=C, not the range); verified empirically.
- N3 (MEDIUM) — Phase 4.2 cited "Step B (the script-install loop)" but Step B is rules-render; Step C is the hook/script-copy step. Bootstrap and collision policy unspecified.
- N4 (MEDIUM) — first-attempt-or-abort rule conflicts with the natural recoverable case where stage-check denies on a sibling-skill bump.
- N5 (MEDIUM) — `set -u` + unguarded `$CLAUDE_PROJECT_DIR` would crash on rare unset-env edge case.
- N6 (MEDIUM) — Phase 4 AC1 contradicts driver's `.git` requirement.
- N7 (MEDIUM) — missing `mkdir -p` for consumer `scripts/` on fresh installs.
- N8 (MEDIUM) — Phase 5.5 version gate over-strict on patch bumps; AC5 can't run on CI.
- N9 (LOW) — AC8 `git tag --contains` is post-hoc and falsifiable; reframe as same-PR invariant.
- N10 (LOW) — Phase 2.4 case-count drift (13 vs 17).

Resolved (10/10): all N1-N10. Hard fixes:
- N1 → tokenize-then-walk replaces the regex `GIT_COMMIT_BOUNDARY` (`is_git_commit` function in Phase 2.1 skeleton). More robust AND more readable than a generalized regex; handles arbitrary git top-level flag combinations.
- N2 → POSIX `[[:cntrl:]]` replaces the broken bash range `[$'\x00'-$'\x1f']`; documented inline why range form fails empirically.
- N3 → Phase 4.2 prose corrected to Step C; bootstrap pinned to source-side invocation from `$PORTABLE/scripts/install-helpers-into.sh` (no consumer-local copy needed); collision policy specified (cmp-gated overwrite, SKIP if identical, COPY if different, log every action).
- N4 → softened recovery rule in Phase 3 D&C and Phase 4 D&C: sibling-skill stage-check denies are safe to retry with cause documented in commit footer; `update-zskills`-self denies still require restart-from-clean-tree.
- N5 → `${CLAUDE_PROJECT_DIR:-$PWD}` guards the unset edge case under `set -u`; new test case C12a asserts fail-open behavior with `unset CLAUDE_PROJECT_DIR`.
- N6 → dropped `.git` requirement from driver spec (defense-against-typo, not load-bearing); AC1 setup matches.
- N7 → `mkdir -p "<consumer-root>/scripts"` added to Phase 4.1 driver before the cp loop; AC asserts directory exists post-install.
- N8 → Phase 5.5 + AC5 pinned to MAJOR.MINOR comparison; CI-skip when `command -v claude` fails (conformance test is CI backstop).
- N9 → AC8 reframed from `git tag --contains` to `gh pr view <N> --json commits` same-PR invariant.
- N10 → Phase 2.4 count updated; now consistent with AC3/AC5 across the round-2 case additions (now 26 cases total).

Justified-not-fixed: none (all 10 N-findings resolved hard).

Restructuring in Round 2:
- Phase 2.1 implementation skeleton: the regex `GIT_COMMIT_BOUNDARY` is replaced by the tokenize-then-walk `is_git_commit` shell function. D&C "Match boundary" rewritten as "Match strategy — tokenize-then-walk" with rationale.
- Phase 2.2 cases added: C7d (`--no-pager`), C7e (`--git-dir=/x`), C7f (`-P`), C7g (mixed `-C path -c k=v`), C7h (multi-long-flag `--git-dir=/x --work-tree=/y`), C7i/C7j (negative cases for non-`commit` subcommands after flag-skip), C12a (unset `CLAUDE_PROJECT_DIR`), C15 (control-byte strip). Total cases now 26 (was 17).
- Phase 2.4, Phase 2 AC3/AC5, Phase 5 AC3, Phase 5.3 case counts updated to 26.
- Phase 2 AC11 strengthened to also assert `[[:cntrl:]]` literal present in hook (Round 2 N2 fix).
- Phase 2 AC12 expanded into a 10-case bypass-canary battery covering all C7a-C7j.
- Phase 4.1 driver gains: `mkdir -p` for consumer `scripts/`; cmp-gated collision policy with SKIP/COPY logging; `.git` requirement dropped.
- Phase 4.2 cites Step C (corrected from Step B); driver invoked source-side from `$PORTABLE`, no consumer-local copy.
- Phase 4 AC10/AC11 added: collision-policy assertions and Step-C-citation grep.
- Phase 5 AC8 reframed as same-PR invariant via `gh pr view`.
- Phase 5.5 + AC5 added MAJOR.MINOR comparison and CI-skip.
