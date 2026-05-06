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
| 1 — Decision doc + manual-recipe verifications | ✅ Done | `67ff929` | All 6 ACs PASS. references/skill-version-pretooluse-hook.md (138 lines): D1-D5 verbatim + R1/R2/R3 manual-recipe verifications + Recursive-risk-NONE + run_suite dispatcher pattern. plans/PLAN_INDEX.md: Plan B added to "Ready to Run". Tests 2071/2071 PASS (parity with baseline; docs-only phase). |
| 2 — Hook script + JSON-escape function + unit tests | ⏳ Pending | — | `hooks/block-stale-skill-version.sh` + `tests/test-block-stale-skill-version.sh` |
| 3 — `.claude/settings.json` registration + canonical extension table | ⏳ Pending | — | zskills-side wiring + `skills/update-zskills/SKILL.md:944-948` row |
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
  - **C10e (negative; Round-2 DA2-L-2 carve-out lock):** `bash -c 'git commit -m foo'` → does NOT match (first token is `bash`; tokenize-then-walk does not recurse into `-c` argument strings — see Phase 2 D&C "Known carve-out"). This is a documented local-dev hole, not a structural defeat; CI's `test-skill-conformance.sh` is the backstop.
  - **C11: `git commit && git push`** → matches `git commit` (and the chained `git push` is a different concern, not gated here per D2).
  - **C12: Script missing** (rename or `chmod -x`, fail-open path) → exit 0, stdout empty.
  - **C12a: `unset CLAUDE_PROJECT_DIR`** (or `env -i bash hooks/...`) piped a `git commit` Bash invocation → exit 0, stdout empty (fail-open). Asserts the `${CLAUDE_PROJECT_DIR:-$PWD}` guard prevents `set -u` crash on unset env (Round 2 N5 fix).
  - **C13: Multi-line reason with `"` and `\` characters** → assert resulting JSON is parseable by `python3 -c 'import json,sys; json.loads(sys.stdin.read())'` (used here as ASSERTION ONLY, not as a runtime dep — the hook itself does NOT call python).
  - **C14: Reason containing multi-byte UTF-8 (e.g., `tëst skipped`)** → assert `json_escape` output round-trips through `python3 -c "import json,sys; json.loads(sys.stdin.read())"` AND the decoded string equals the original UTF-8 bytes (proves `LC_ALL=C` byte-mode preserves UTF-8 sequences intact).
  - **C15: Reason containing rare control bytes (`$'a\x01\x02\x07\x0Bb'`)** → after `json_escape` + JSON-decode via `python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["hookSpecificOutput"]["permissionDecisionReason"])'`, decoded reason equals `'ab'` (control bytes 0x01, 0x02, 0x07, 0x0B are stripped). Proves the POSIX `[[:cntrl:]]` class strips the full control range, NOT just the upper-bound byte (Round 2 N2 fix).

- [ ] 2.3 — Add `tests/test-block-stale-skill-version.sh` to `tests/run-all.sh` dispatcher.

- [ ] 2.4 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` and verify the new test file's cases all pass; full-suite count increases by exactly the new case count (27 — Round-2 added C10e for the `bash -c` carve-out per DA2-L-2).

### Design & Constraints

- **Per-phase commit boundary:** ONE commit, scope = `hooks/block-stale-skill-version.sh` + `tests/test-block-stale-skill-version.sh` + addition to `tests/run-all.sh` (single `run_suite` line, per the dispatcher pattern documented in `references/skill-version-pretooluse-hook.md` §"`tests/run-all.sh` dispatcher pattern" from Phase 1.1). Subject: `feat(hooks): block-stale-skill-version PreToolUse hook + unit tests`.
- **Phase ordering: NO `skills/` edits in this phase.** The hook source itself is under `hooks/`, not `skills/`, so no skill version bump is required here. Phase 3 is the first phase that touches `skills/update-zskills/SKILL.md`. Per the per-phase versioning discipline (see Phase 3 / Phase 4 D&C), version bump and mirror MUST be the FINAL two operations of any phase that edits a SKILL.md.
- **NO `jq`** — `json_escape` is pure bash (per D4).
- **`python3` is allowed in tests; NOT in hook runtime.** The hook itself uses pure-bash `json_escape` per D4. Phase 2 unit tests AND Phase 4 sandbox tests MAY use `python3 -c 'import json,sys; json.loads(...)'` for JSON-validity assertions — `python3` is on every CI image and dev container, and using it as a JSON validator avoids reinventing a parser. The runtime/test distinction is enforced by AC8 below (`grep -F 'python' hooks/block-stale-skill-version.sh` returns 0).
- **NO `2>/dev/null` on critical operations** — the script invocation uses `STDERR=$(... 2>&1 >/dev/null)` which routes stderr to capture (not to /dev/null).
- **Fail-open on missing `scripts/skill-version-stage-check.sh`.** This is deliberate: a consumer pre-`/update-zskills` (Phase 4) has the hook but not yet the script; failing CLOSED would brick every `git commit` in those repos. Failing OPEN matches the prior-art convention (`block-unsafe-project.sh` reads its config at runtime and silently no-ops if config is absent). Phase 4 closes the install gap; Phase 5's CLAUDE.md note documents the temporary window for early adopters. **Fail-open is restricted to the FIRST link in the chain (Round-2 R2-N-4 documentation):** if `skill-version-stage-check.sh` itself is missing, the hook returns 0 silently (the `[ -x "$SCRIPT" ] || exit 0` guard at line 209). If stage-check IS present but ITS dependencies (`frontmatter-get.sh`, `skill-content-hash.sh`) are missing, stage-check exits non-zero and the hook DENIES with stage-check's stderr in the deny envelope's `permissionDecisionReason` — which surfaces a `frontmatter-get.sh: command not found` error rather than the expected STOP message, but is loud-and-visible (correct fail-mode ordering: a half-installed consumer is a strictly broken state and surfacing it loudly is better than silently allowing). The Phase 4 install driver copies all 4 helpers atomically — half-install is only possible via manual tampering or partial-install from a future zskills version that drops a helper.
- **Match strategy — tokenize-then-walk (chosen over regex):** the hook tokenizes `$COMMAND` on whitespace, skips env-var prefixes, finds literal `git`, walks past every top-level flag (handling `-C path` and `-c k=v` as two-token consumes; all other `--foo`, `--foo=bar`, `-X` as single-token), and checks if the next token is `commit`. This robustly covers arbitrary git top-level flag combinations (`--no-pager`, `--git-dir=/x`, `-P`, mixed `-C path -c k=v`, `--git-dir=/x --work-tree=/y`, …) — all empirically demonstrated to bypass the earlier alternation-based regex (Round 2 finding N1). Tokenize-then-walk was chosen over a generalized regex for readability AND robustness against future flag additions; the regex form would still be combinatorial. Echo/printf args containing the literal string `git commit` do NOT match because `read -ra` on the outer command splits on whitespace and the matcher applies only to the command's leading position (verified by C10). Heredoc bodies and quoted commit messages are NOT pre-redacted (unlike `block-unsafe-generic.sh`'s data-region redaction) — because for THIS hook, even a hypothetical false-positive match harmlessly invokes the stage-check script, which is filesystem-state-driven and exits 0 on a clean stage. Adding redaction is unnecessary defensive code.
- **Known carve-out: `bash -c '<git commit ...>'` / `sh -c '...'` / `eval '...'` (Round-2 DA2-L-2 — explicitly documented).** The tokenize-then-walk requires the FIRST non-env-prefix token to be literal `git`. A real-world invocation like `bash -c 'git commit -m foo'` puts `git commit` inside a single-quoted argument to `bash`; the first token is `bash`, so `is_git_commit` returns 1 (no match). Recursing into `bash -c`/`sh -c`/`eval` argument strings would re-introduce the regex-fragility class this hook explicitly avoids (the inner string would need its own tokenize-then-walk, with quote-handling ambiguity). **We accept this as a known bypass.** CI's `test-skill-conformance.sh` catches stale skill versions on the feature branch; the carve-out is a minor local-development hole, not a structural defeat. Test case C10e (negative) locks the carve-out behavior — see Phase 2.2.
- **Test output capture:** `TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"; mkdir -p "$TEST_OUT"`.

### Acceptance Criteria

- [ ] AC1 — `[ -x hooks/block-stale-skill-version.sh ]`.
- [ ] AC2 — `bash tests/test-block-stale-skill-version.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns `0`.
- [ ] AC3 — All 27 cases pass: `grep -c '^PASS' "$TEST_OUT/.test-results.txt"` returns `27` (C1–C15 plus C7a/C7b/C7c/C7d/C7e/C7f/C7g/C7h/C7i/C7j plus C10e plus C12a). Round-2 added C10e (negative `bash -c` carve-out per DA2-L-2).
- [ ] AC4 — `grep -n 'test-block-stale-skill-version.sh' tests/run-all.sh` returns exactly one match AND it follows the canonical `run_suite "<filename>" "tests/<filename>"` shape.
- [ ] AC5 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns `0`; total case count increases by 27 vs HEAD~1.
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

Wire `hooks/block-stale-skill-version.sh` into zskills' own `.claude/settings.json` (so the hook fires for development sessions in this repo), and extend the canonical zskills-owned hook table at `skills/update-zskills/SKILL.md:944-948` so consumer installs pick it up via Step C's existing surgical-merge algorithm. Bump `skills/update-zskills/SKILL.md`'s `metadata.version` per the PR #175 enforcement chain.

### Work Items

Ordering matters this phase: all SKILL.md content edits FIRST, then version bump + mirror, then the `.claude/hooks/` mirror copy and `.claude/settings.json` registration LAST. The settings.json edit is deliberately the last file modified before commit — once the new hook is registered AND the script is in place, every subsequent `git commit` in this worktree is gated. If the bump-and-commit fails for an unrelated reason and we have to retry, doing the registration earlier could leave the recovery commit blocked. See Design & Constraints "Phase commit ordering."

Phase 3.1 is split into three independent sub-bullets (Round-2 R2-CO-C / DA2-L-1: the three edits are disjoint, target distinct anchors, and have no ordering hazard within the same single-threaded `/update-zskills` run; the version-bump in 3.5 is the FINAL operation and captures the merged final state regardless of intermediate-edit order). Sub-bullets may be applied in any order.

- [ ] 3.1a — **Append canonical-table row.** Edit `skills/update-zskills/SKILL.md` (anchor by the literal table-header text `**Canonical zskills-owned triples**` at line 939; the table itself currently sits at lines 942-948 — drift-tolerant by anchor). Append one row to the table:

  | Event        | Matcher | Command literal                                                                  |
  |--------------|---------|----------------------------------------------------------------------------------|
  | PreToolUse   | Bash    | `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-stale-skill-version.sh"`          |

  After: 6 rows total.

- [ ] 3.1b — **Update row-count prose.** Edit the prose at line 950 (anchor by literal text `All 5 rows carry`) → `All 6 rows carry`. Single-token swap. Verify with `grep -F 'All 6 rows' skills/update-zskills/SKILL.md` returns ≥ 1.

- [ ] 3.1c — **Update install-explainer block (Round-2 carry-over R2-CO-B / DA2-H-2 — count + scope rewrite).** Edit the user-facing install message at lines 904-910 (anchor by literal text `> Installing 2 safety hooks:` at line 904, drift-tolerant by anchor). The current explainer says `Installing 2 safety hooks` and lists ONLY `block-unsafe-generic.sh` + `block-unsafe-project.sh` — but the canonical table at 942-948 wires 5 entries (PreToolUse Bash × 2, PreToolUse Agent × 1, PostToolUse Edit × 1, PostToolUse Write × 1). The explainer is already under-counting pre-existing reality; bumping `2 → 3` (the original Plan B spec) preserves the under-count.

  **Resolution: scope the explainer to PreToolUse-Bash safety hooks specifically** (Plan B's hook is also PreToolUse Bash, joining its peers semantically). This avoids forcing a 6-bullet expansion that touches unrelated hook surfaces. Replace the explainer with:

  > Installing 3 PreToolUse Bash safety hooks (commit-time + pre-tool-execution gates):
  > - **block-unsafe-generic.sh** — blocks destructive commands (`git reset --hard`, `rm -rf`, `kill -9`, `git checkout --`, `--no-verify`, etc.) and discipline violations (`git add .`).
  > - **block-unsafe-project.sh** — project-specific guards: prevents piping test output (must capture to file), verifies tests ran before commit, optionally checks for UI verification before committing UI changes, enforces tracking discipline.
  > - **block-stale-skill-version.sh** — denies `git commit` when staged skill files have a stale `metadata.version` hash; reuses `scripts/skill-version-stage-check.sh`.
  >
  > See the canonical table below for the full hook set (additionally: PreToolUse `Agent` matcher → `block-agents.sh`; PostToolUse `Edit`/`Write` matchers → `warn-config-drift.sh`).

  Verify with `grep -F 'Installing 3 PreToolUse Bash safety hooks' skills/update-zskills/SKILL.md` returns ≥ 1 AND `grep -c 'block-stale-skill-version.sh' skills/update-zskills/SKILL.md` returns ≥ 3 (counting the explainer + canonical-row + Step C copy bullet from 3.2; Phase 4 raises this to ≥ 4 with the Step D mention).

- [ ] 3.2 — Update Step C of `skills/update-zskills/SKILL.md` (Step C heading at line 816, "Fill hook + agent gaps"; the per-hook copy-bullet list lives at lines 820-852, post-Plan-A — Plan A added bullets for `inject-bash-timeout.sh` and `verify-response-validate.sh`) to copy `hooks/block-stale-skill-version.sh` from `$PORTABLE/hooks/` to `.claude/hooks/block-stale-skill-version.sh` (no `.template`, no placeholder fill — flat copy, identical pattern to `block-unsafe-generic.sh`). Add a one-line bullet to the existing copy-list, mirroring Plan A's bullet shape (`- For \`block-stale-skill-version.sh\`: copy as-is from \`$PORTABLE/hooks/\` to \`.claude/hooks/\`.`); insert as the last hook-copy bullet, immediately before the `scripts/test-all.sh` bullet at line 842.

- [ ] 3.3 — Mirror `hooks/block-stale-skill-version.sh` to zskills' own runtime hook directory:

  ```bash
  cp hooks/block-stale-skill-version.sh .claude/hooks/block-stale-skill-version.sh
  chmod +x .claude/hooks/block-stale-skill-version.sh
  ```

  This matches the `block-unsafe-generic.sh` idiom (no `mirror-hook.sh` script exists; flat `cp` is the convention).

- [ ] 3.4 — Verify `git diff --cached --name-only` (after `git add` of all SKILL.md and `.claude/hooks/` edits, but BEFORE the SKILL.md version bump) shows only the expected paths and no skill-version drift on any other skill. This catches accidental cross-skill edits before the bump cements the wrong hash.

- [ ] 3.5 — Bump `skills/update-zskills/SKILL.md` `metadata.version` (FINAL content op for this phase): `today=$(TZ=America/New_York date +%Y.%m.%d); hash=$(bash scripts/skill-content-hash.sh skills/update-zskills); bash scripts/frontmatter-set.sh skills/update-zskills/SKILL.md metadata.version "$today+$hash"`. Then mirror: `bash scripts/mirror-skill.sh update-zskills`.

- [ ] 3.6 — Edit `.claude/settings.json` LAST: append a third entry to the existing `PreToolUse` `Bash` matcher's `hooks` array (after the two existing entries — `block-unsafe-generic.sh` and `block-unsafe-project.sh` — under the PreToolUse Bash matcher; line numbers approximate at 7-15 today, anchor by content). **Match existing indentation conventions** (Round-2 DA2-M-2): the existing entries use **10-space outer-brace indent and 12-space key indent** (4 levels of nesting: `hooks` → `PreToolUse` → matcher object → `hooks` array → object). Read the existing entries first and copy the indent style verbatim. The new entry at the file's actual indentation:

  ```json
            {
              "type": "command",
              "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-stale-skill-version.sh\"",
              "timeout": 5
            }
  ```

  Indent shown above is illustrative-with-leading-spaces; the rule is "match existing entry shape verbatim" so the diff reads as a clean append, not a re-indent. Verify with `python3 -c 'import json; json.load(open(".claude/settings.json"))'` BEFORE staging.

- [ ] 3.7 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` — verify all tests still pass (no regressions). Conformance test specifically confirms the new mirror is clean and the version line is fresh.

- [ ] 3.8 — Verify the hook fires in zskills' own session by opening a sandbox child session inside the worktree, editing a skill body without bumping, and running `git commit -am test` — observe deny envelope in the harness output. Log result to `tests/canary-zskills-self-fires.txt` (one-shot, not a regression test).

### Design & Constraints

- **Per-phase commit boundary:** ONE commit, scope = `.claude/settings.json` + `.claude/hooks/block-stale-skill-version.sh` (mirror) + `skills/update-zskills/SKILL.md` (4 edit sites: 3.1a canonical-table row + 3.1b row-count prose + 3.1c explainer block + 3.2 Step C copy bullet + 3.5 version bump) + `.claude/skills/update-zskills/SKILL.md` (mirror via `mirror-skill.sh`). Subject: `feat(hooks): wire block-stale-skill-version into zskills + canonical table`.
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
- [ ] AC4 — `grep -E 'All [0-9]+ rows carry' skills/update-zskills/SKILL.md` matches `All 6 rows`. AND `grep -F 'Installing 3 PreToolUse Bash safety hooks' skills/update-zskills/SKILL.md` returns ≥ 1 (Round-2 R2-CO-B / DA2-H-2 explainer rewrite — scoped to PreToolUse-Bash safety hooks specifically).
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

Ordering: helper-script driver + Step D prose + sandbox test FIRST, then version bump + mirror LAST. Per the per-phase versioning discipline (CLAUDE.md `## Skill versioning`: "Edits to a skill body, frontmatter, or any regular file under the skill directory MUST bump this field"), the bump must be the final operation that touches `skills/update-zskills/`. Multiple bumps within a single PR are normal — each phase that edits a SKILL.md bumps immediately, and per-phase commits accumulate.

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

  This driver is the SHARED CODE PATH between (a) the sandbox integration test (work item 4.3) and (b) `/update-zskills` Step D prose (work item 4.2). Sharing the code path closes the C2 review finding: tests prove the binary works AND the install path works, because they invoke the same script.

- [ ] 4.2 — Read `skills/update-zskills/SKILL.md` **Step D** (the canonical script-install block at line 1090, "Fill script gaps"; Step D body extends to line 1140 with the canonical two-source pattern documented at lines 1092-1093, the soft-skip on missing second source at lines 1103-1105, the per-script COPY bullets at lines 1107-1133, and the `Report: "Installed N scripts: [list]"` surface at line 1139). Identify the canonical insertion point immediately after the existing per-stub bullets (after line 1133), before the Tier-1 callout at lines 1135-1137. Update the prose to invoke `bash "$PORTABLE/scripts/install-helpers-into.sh" "$CONSUMER_ROOT"` as part of the Step D install sequence — invoked SOURCE-SIDE from `$PORTABLE`, no consumer-local copy of the driver itself. **Step A cross-reference (per Round 2 DA2-M-3):** Step A (`Locate portable assets`, SKILL.md line 685) provides `$PORTABLE` pointing at the zskills source clone — `$PORTABLE/scripts/install-helpers-into.sh` resolves correctly because the driver lives in the source repo's `scripts/` (not under any skill's `scripts/`). Add an explanatory paragraph: "These four helpers (`skill-version-stage-check.sh`, `skill-content-hash.sh`, `frontmatter-get.sh`, `frontmatter-set.sh`) are dependencies of `block-stale-skill-version.sh` (the PreToolUse hook installed in **Step C** above). Without them, the hook fails-open on every commit, defeating the lock-step skill-version enforcement chain. The `install-helpers-into.sh` driver is the same one exercised by `tests/test-block-stale-skill-version-sandbox.sh`, so the install path and the test path share code. Collision policy: existing identical helpers are skipped; existing different helpers are overwritten; logged either way." Ensure the helpers are listed in the existing Step D `Report: "Installed N scripts: [list]"` output (the driver's per-file `SKIP:`/`COPY:` log feeds the count). (Round-2 carry-over R2-CO-A / DA2-H-1: Step C is for hook + agent gaps; Step D is the canonical home for `scripts/` install — Round 1 left this strategy fix out-of-scope, Round 2 NORMAL scope unblocks it.)

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

- **Per-phase commit boundary:** ONE commit, scope = `scripts/install-helpers-into.sh` + `skills/update-zskills/SKILL.md` (Step D prose extension + version bump) + `.claude/skills/update-zskills/SKILL.md` mirror + `tests/test-block-stale-skill-version-sandbox.sh` + `tests/run-all.sh` registration. Subject: `feat(update-zskills): install skill-version helpers + sandbox integration test`.
- **Phase commit ordering (LOAD-BEARING, same rule as Phase 3):** version bump and mirror MUST be the FINAL two operations of this phase, AFTER all SKILL.md content edits and AFTER the install driver and sandbox test are written. The hook installed in Phase 3 is now active in this worktree. **Recovery rule (softened in Round 2 per N4, mirrors Phase 3):** if the bump+commit fails with a stage-check deny on a sibling skill, bump it and retry; document the cause in the commit message footer. If the deny identifies `update-zskills/SKILL.md` itself, restart the phase from a clean working tree. Other failure modes: diagnose externally without in-worktree retry.
- **`mirror-skill.sh` discipline:** the version bump in 4.6 + Step D prose extension in 4.2 ARE source skill edits, so `bash scripts/mirror-skill.sh update-zskills` MUST run in the same commit. (Note: the install-helpers-into.sh driver lives at `scripts/`, NOT under any skill, so it is itself NOT a per-skill versioning trigger; only `skills/update-zskills/SKILL.md`'s Step D prose is.)
- **Shared install code path (closes C2):** `scripts/install-helpers-into.sh` is invoked by both `tests/test-block-stale-skill-version-sandbox.sh` (work item 4.3) AND `/update-zskills` Step D prose (work item 4.2). The test does NOT manually replicate the helper-script install — it calls the same driver the real install path uses. If the driver is broken, both surfaces fail together (visible signal, no false greens).
- **Sandbox cleanup is mandatory.** `trap 'rm -rf "$TMP"' EXIT INT TERM` AND explicit post-test verification `rm -rf "$TMP" && [ ! -d "$TMP" ] && echo "cleanup OK"`. No `2>/dev/null` on the rm. Verify the directory is gone — do not assume the trap fired correctly (per CLAUDE.md "Never suppress errors on operations you need to verify").
- **Sandbox test runs in CI.** Add to `tests/run-all.sh` per the dispatcher pattern in Phase 1's reference doc.
- **`python3` allowed in tests, NOT in hook:** same rule as Phase 2 D&C. The sandbox test uses `python3 -c 'import json …'` for JSON decoding of the deny envelope; the hook itself uses pure-bash `json_escape`.
- **No `--no-verify`. No `2>/dev/null` on critical ops.**

### Acceptance Criteria

- [ ] AC1 — `[ -x scripts/install-helpers-into.sh ]` AND `bash scripts/install-helpers-into.sh /tmp/install-helpers-into-smoke-$$` succeeds against a freshly-`mkdir`ed throwaway dir (no `.git` required per N6 fix; smoke test verifies the driver creates `scripts/` via `mkdir -p` then copies all 4 helpers; clean up after). AC also asserts `[ -d /tmp/install-helpers-into-smoke-$$/scripts ]` post-install (N7 guarantee for fresh repos with no prior `scripts/`).
- [ ] AC2 — `grep -F 'install-helpers-into.sh' skills/update-zskills/SKILL.md` returns ≥ 1 match (Step D prose references the shared driver).
- [ ] AC3 — `bash tests/test-block-stale-skill-version-sandbox.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns `0`. Output contains `deny on stale-version skill commit`, `allow after correct bump`, and `cleanup OK`.
- [ ] AC4 — `metadata.version` of `skills/update-zskills/SKILL.md` is fresh (today's date) AND its hash matches `bash scripts/skill-content-hash.sh skills/update-zskills`.
- [ ] AC5 — Mirror parity: `diff -r skills/update-zskills .claude/skills/update-zskills` returns no differences.
- [ ] AC6 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; echo $?` returns 0.
- [ ] AC7 — `grep -n 'test-block-stale-skill-version-sandbox.sh' tests/run-all.sh` returns exactly one match AND it follows the `run_suite` dispatcher pattern.
- [ ] AC8 — Phase 4 commit succeeded with at most ONE retry, with cause documented in the commit message footer if a retry happened (same softened rule as Phase 3 AC9, per Round 2 N4 fix).
- [ ] AC9 — Test/install share-the-driver invariant: `grep -F 'install-helpers-into.sh' tests/test-block-stale-skill-version-sandbox.sh` returns ≥ 1 match (the sandbox test invokes the same driver the install prose references).
- [ ] AC10 — Collision-policy assertions (Round 2 N3 + Round-2-DA2-M-4 reword to drop inode comparison; `cp` overwrites in place and inode is preserved across COPY too, making inode a useless distinguisher). The sandbox test asserts in two stages, mtime-only, with explicit `sleep 1` boundaries to guarantee `stat -c %Y` granularity:
  1. **SKIP path:** pre-seed `$dst` from `$src` (`cp $src $dst`); record `mtime_before=$(stat -c %Y $dst)`. `sleep 1`. Run driver. Assert `grep -F 'SKIP:' driver_output` returns ≥ 1 AND `[ "$(stat -c %Y $dst)" = "$mtime_before" ]` (mtime unchanged because cmp-gated SKIP didn't touch the file).
  2. **COPY path:** `echo 'modified' >> $dst`; `mtime_before2=$(stat -c %Y $dst)`. `sleep 1`. Re-run driver. Assert `grep -F 'COPY:' driver_output` returns ≥ 1 AND `[ "$(stat -c %Y $dst)" -gt "$mtime_before2" ]` AND `cmp -s $src $dst` (overwrite restored canonical content).
  The mtime+cmp pair is load-bearing; inode comparison is omitted by design (does not distinguish in-place overwrite from no-op).
- [ ] AC11 — Phase 4.2 cites Step D, not Step C (Round-2 carry-over R2-CO-A / DA2-H-1 correction): the only Step reference associated with the helper-install loop in the Phase 4 section is "Step D". Verify with `awk '/^## Phase 4/,/^## Phase 5/' plans/SKILL_VERSION_PRETOOLUSE_HOOK.md | grep -nE 'Step [A-G]\b' | grep -F install-helpers-into.sh` — all hits cite Step D (not Step B, not Step C). Sibling cite to "Step C above" inside the explanatory paragraph (the hook is in Step C; the helpers go in Step D) is allowed and expected.
- [ ] AC12 — Post-Phase-4 row-count: `grep -c 'block-stale-skill-version.sh' skills/update-zskills/SKILL.md` returns ≥ 4 (extension-table row from Phase 3.1a + Step C copy bullet from 3.2 + explainer block from 3.1c + Step D helper-install reference from 4.2). Phase 3 AC3 set the lower bound to ≥ 3 within Phase 3 alone; this AC raises it once Phase 4 lands.

### Dependencies

Phase 3 complete. The hook is wired in zskills (proves the registration shape), and the canonical extension table has the new row (proves the install path knows what to install).

---

## Phase 5 — CHANGELOG + CLAUDE.md note + final conformance

### Goal

Document the new structural backstop, mark the plan complete, and run the full PR-tier gate (tests + conformance + lint) to surface any cross-phase drift before opening the PR.

### Work Items

- [ ] 5.1 — Append a CHANGELOG entry (top of `CHANGELOG.md`).

  **CHANGELOG style (Round-2 carry-over R2-N-2 / DA2-C-2 — verified against current CHANGELOG.md head):** the file uses `## YYYY-MM-DD` date-only H2 headings with `### Added — <title>` H3 blocks beneath. Multiple H3 blocks per date are permitted (each is a separate scoped change). Plan A landed `## 2026-05-03` with one `### Added — Verifier subagent — D'' structural defense` block; Plan B's spec must NOT create a duplicate H2.

  **Date-collision handling:**
  - If today's date already has a `## YYYY-MM-DD` heading (e.g. Plan A landed the same day), DO NOT create a duplicate heading. INSERT a new `### Added —` H3 block UNDER the existing date heading, immediately after the date heading line (above any sibling Added blocks for the same day).
  - If today is a new date, create a new `## YYYY-MM-DD` heading at the top of the file (above the previous newest date), then the `### Added —` H3 block beneath.

  **Block content (H3 + paragraph, matching Plan A's shape — single paragraph, NOT a bullet list):**

  ```
  ### Added — block-stale-skill-version PreToolUse hook (#<PR-NUM>)

  Add `hooks/block-stale-skill-version.sh`: PreToolUse Bash hook denying `git commit` when staged skill files have a stale `metadata.version` hash. Wraps `scripts/skill-version-stage-check.sh` and emits a JSON deny envelope (pure-bash escape — no `jq`, no Python). Wired in zskills `.claude/settings.json` and shipped to consumers via `/update-zskills` (canonical extension table extended; 4 helper scripts — `skill-version-stage-check.sh`, `skill-content-hash.sh`, `frontmatter-get.sh`, `frontmatter-set.sh` — now copied via the new shared `scripts/install-helpers-into.sh` driver invoked from `/update-zskills` Step D). Closes the lock-step gap: bare `git commit` (bypassing `/commit`) is now blocked locally; CI's `test-skill-conformance.sh` is no longer the only mechanical safety net. Decisions: flat hook (no `.template`); commit-only gating (push gating dropped per F2 design analysis); `/commit` Phase 5 step 2.5 retained for defense-in-depth; tokenize-then-walk `git commit` matcher (regex form was empirically bypassable per Round-2 N1). **Rollout window:** consumers who installed Phase 3's hook before Phase 4's helper-script ship would silently fail-open until they re-ran `/update-zskills`. Mitigated by shipping Phases 3 and 4 in the SAME PR with NO intermediate release tag — every consumer that pulls this PR gets the hook AND the helpers atomically. See `references/skill-version-pretooluse-hook.md`. Closes lock-step gap from PR #175 (skill-versioning).
  ```

  Verify after the edit:
  - `head -10 CHANGELOG.md | grep -F '### Added — block-stale-skill-version'` returns 1 match.
  - `grep -c '^## $TODAY' CHANGELOG.md` (where `$TODAY=$(TZ=America/New_York date +%Y-%m-%d)`) returns 1 (no duplicate H2 from a same-day collision).
  - The new H3 block sits BENEATH a date H2, NOT as its own H2.

- [ ] 5.2 — Append a paragraph to `CLAUDE.md`'s `## Skill versioning` section (after the existing paragraph) AND a one-line cross-reference to the `## Verifier-cannot-run rule` section (Round-2 DA2-M-1 — closes the discoverability gap by linking the two sections that share the verifier-hook-interaction concern). Resolved Round-2 critical R2-N-1 / DA2-C-1: hook composition (frontmatter PreToolUse hooks ADD to `settings.json` PreToolUse hooks, not REPLACE) confirmed empirically via Anthropic Code docs (https://code.claude.com/docs/en/sub-agents — "Frontmatter hooks fire when the agent is spawned as a subagent through the Agent tool or an @-mention, and when the agent runs as the main session via `--agent` or the `agent` setting. In the main-session case they run alongside any hooks defined in `settings.json`.") and reinforced by https://code.claude.com/docs/en/hooks (subagent frontmatter hooks active "while the component is active" — additive, not replace).

  **Append to `## Skill versioning`:**

  > **PreToolUse backstop.** A fourth enforcement point — `hooks/block-stale-skill-version.sh` — fires on every `git commit` Bash invocation in any Claude Code session. It reuses `scripts/skill-version-stage-check.sh` and emits a deny envelope on drift. This closes the bare-`git commit` bypass: `/commit` step 2.5 covers `/commit` invocations, and the hook covers everything else. `git push` is NOT gated locally (see `references/skill-version-pretooluse-hook.md` D2 for rationale; CI's `test-skill-conformance.sh` is the push-time backstop). This includes commits made by the **verifier subagent** (introduced by Plan A, loaded from `.claude/agents/verifier.md`). Per Anthropic's documented design (https://code.claude.com/docs/en/sub-agents §"Hooks in subagent frontmatter"), subagent frontmatter `hooks:` declarations COMPOSE WITH (do not replace) project-level `.claude/settings.json` hooks — so the verifier's frontmatter `inject-bash-timeout.sh` AND the project's `block-unsafe-generic.sh` / `block-unsafe-project.sh` / `block-stale-skill-version.sh` ALL fire on every verifier `git commit`. **Recovery (verifier-side):** the deny envelope's `permissionDecisionReason` carries the stage-check STOP message verbatim — including the exact `bash scripts/frontmatter-set.sh <S>/SKILL.md metadata.version "$today+$hash"` command. The verifier has `Edit` and `Bash` in its tools allowlist (`tools: Read, Grep, Glob, Bash, Edit, Write` per `.claude/agents/verifier.md`) and SHOULD execute the bump inline, then re-stage and re-issue the commit. **Recovery (orchestrator-side, when a non-verifier caller hits the deny):** read the STOP message rendered in the tool-error output, run the suggested bump command, and re-issue the commit. Do NOT treat the deny as "tests failed" — it is a strict pre-flight check, not a test result.

  **Append to `## Verifier-cannot-run rule` (one-line cross-reference, DA2-M-1):**

  > See `## Skill versioning` for the verifier subagent's interaction with `block-stale-skill-version.sh` (Plan B PreToolUse backstop): the verifier's frontmatter `inject-bash-timeout.sh` hook composes with project hooks per Anthropic's documented additive behavior, so verifier `git commit` is gated identically to orchestrator-side commits.

  **Hook chain composition (additional reference for `references/skill-version-pretooluse-hook.md` Phase 1 §"Recursive risk: NONE" sibling subsection — Round-2 R2-N-5):** when the verifier subagent runs `git commit`, the chain is (parallel-fire, AND-deny semantics): (1) `inject-bash-timeout.sh` [frontmatter, mutates `updatedInput.timeout`], (2) `block-unsafe-generic.sh`, (3) `block-unsafe-project.sh`, (4) `block-stale-skill-version.sh`. Any DENY short-circuits the tool call; all allows let the tool run with the merged `updatedInput`. Per Anthropic docs, deny short-circuits before tool execution, so an `inject-bash-timeout.sh` `updatedInput` mutation on a denied call is moot — no invariant violation.

- [ ] 5.3 — `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1` and confirm 0 failures. Total case count vs main: +27 (Phase 2) + sandbox test cases (Phase 4).

- [ ] 5.4 — `bash tests/test-skill-conformance.sh` — confirm version frontmatter section, mirror parity section, and cleanliness section all pass. `update-zskills` mirror must be byte-identical.

- [ ] 5.5 — Re-verify Claude Code harness assumptions: run `claude --version`. **Comparison is at MAJOR.MINOR granularity** (Round 2 N8 fix): re-run the three manual recipes only when the MAJOR or MINOR component differs from the recorded value (last confirmed: 2.1.x). Patch-version drift (e.g., 2.1.126 → 2.1.127) is treated as authoritative — patch bumps don't change harness contracts. **CI-skip:** if `command -v claude` does not succeed (CI image has no `claude` binary), AC5 is skipped — the conformance test (`tests/test-skill-conformance.sh`) is the CI-side backstop. **Ambiguous-output skip (Round-2 DA2-L-3):** if `claude --version` produces ambiguous output (e.g. the dev container ships `claude` as a wrapper script that refuses to print its version, returns a non-version string like a help banner, or hangs awaiting interactive input), treat the same as CI-skip — AC5 is SKIPPED and the conformance test is the backstop. Document the skip in the commit message footer as `Phase 5.5 skipped: claude binary unavailable in this environment` or `Phase 5.5 skipped: claude --version ambiguous in this environment`. Update `references/skill-version-pretooluse-hook.md` "Last confirmed against" lines only if a real MAJOR.MINOR drift triggers the re-run.

- [ ] 5.6 — **Surface related pre-existing bugs (different routes per scope).** Per CLAUDE.md "Skill-framework repo — surface bugs, don't patch":
  - **block-unsafe-project.sh:404 over-matching → DRAFT a hardening plan, NOT another issue.** The bare `git[[:space:]]+commit` regex at line 404 lacks boundary anchoring + data-region redaction. **In-session reproducers (Round-2 DA2-H-3, observed live by the DA agent during this round's pass):** two read-only Bash invocations from a fresh DA agent in this same plan tripped the hook because their argument strings contained the literal `git commit`: (1) `grep -n 'git commit\|...' /workspaces/zskills/.claude/hooks/block-unsafe-project.sh`, (2) `sed -n '404,420p' /workspaces/zskills/.claude/hooks/block-unsafe-project.sh`. Both are read-only file inspection commands that should NEVER fire a commit-protection hook. **Same root cause as Plan B's own evolution** (Round 1 regex extension → Round 2 tokenize-then-walk pivot): regex-based command-classification is fundamentally fragile. PR #73 (Issue #58) and PR #87 (Issue #81) already patched this hook for prior over-match incidents; filing another `404`-specific issue would queue a third patch in a pile rather than fix the class. Instead: in PR body and CHANGELOG, recommend `/draft-plan plans/BLOCK_UNSAFE_HARDENING.md` as a follow-up — scope is the tokenize-then-walk pivot for `block-unsafe-project.sh` + `block-unsafe-generic.sh` command-detection, plus a data-region redaction pass that handles heredoc bodies + quoted args uniformly. Do NOT file a `404`-specific issue (it would add to the pile). The follow-up plan, when authored, will reference the two in-session reproducers above + the prior-patch trail (PR #73, PR #87).
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

- [ ] AC1 — `head -20 CHANGELOG.md | grep -F '### Added — block-stale-skill-version'` returns ≥ 1 match (Round-2 R2-N-2 / DA2-C-2 — assert the literal H3 prefix, not just substring); AND `TODAY=$(TZ=America/New_York date +%Y-%m-%d); grep -c "^## $TODAY" CHANGELOG.md` returns exactly 1 (no duplicate-date H2 from a same-day collision with Plan A's entry); AND `head -20 CHANGELOG.md | awk '/^## /{date_h2++} /^### Added/{added_h3++} END{exit !(date_h2 >= 1 && added_h3 >= 2)}'` exits 0 (Plan B's H3 block sits BENEATH a date H2, alongside Plan A's H3 if same-day).
- [ ] AC2 — `grep -F 'PreToolUse backstop' CLAUDE.md` returns 1 match in the `## Skill versioning` section.
- [ ] AC2a — Cross-reference between `## Skill versioning` and `## Verifier-cannot-run rule` is in place (Round-2 DA2-M-1): `grep -c 'block-stale-skill-version' CLAUDE.md` returns ≥ 2 (one mention in each section); AND `awk '/^## Verifier-cannot-run rule/,/^## /' CLAUDE.md | grep -F 'block-stale-skill-version'` returns ≥ 1 (the cross-reference sentence lives in the Verifier-cannot-run section).
- [ ] AC2b — Verifier-recovery affordance is documented (Round-2 R2-N-1 / DA2-C-1): `grep -F 'Edit and Bash' CLAUDE.md` returns ≥ 1 match in the `## Skill versioning` PreToolUse-backstop paragraph (the verifier has `Edit`+`Bash` in its tools allowlist and is expected to self-bump from the deny envelope's STOP message). AND `grep -F 'COMPOSE WITH' CLAUDE.md` returns ≥ 1 (composition semantics asserted with citation to Anthropic docs, not asserted on faith).
- [ ] AC3 — `bash tests/run-all.sh` exits 0; case count ≥ baseline + 27 (Phase 2 unit cases) + sandbox-test cases (Phase 4).
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
| 1-refresh (post-Plan-A annotation refresh, 2026-05-03) | 5 anchor sites + 1 sentence | — | — | 5 anchor sites + 1 sentence (annotation-only scope; 3 substantive findings deferred) |
| 2-refresh (post-Plan-A NORMAL scope, 2026-05-03) | 9 (3 carry-overs + 6 new) | 12 (incl. 3 dup of reviewer + 3 carry-over coverage) | 13 (after dedup) + 6 verified-positive | 13/13 hard-fixed; 0 Justified-not-fixed |

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

---

## Drift Log

Structural comparison of the plan vs current execution state.

| Phase | Planned | Actual | Delta |
|-------|---------|--------|-------|
| 1-5 | All 5 phases ⏳ Pending | All 5 phases ⏳ Pending | No execution drift — refresh round 1 ran before any phase implementation |

**External drift** (changes outside this plan's execution that affected its anchors):
- **Plan A (VERIFIER_AGENT_FIX, PR #189, squash `5db8283`, 2026-05-03)** extended `skills/update-zskills/SKILL.md` Step C in place — heading "Fill hook gaps" → "Fill hook + agent gaps", new hook-copy bullets (`inject-bash-timeout.sh` + `verify-response-validate.sh`, both NO settings.json wiring), agent-copy bash block (~25 lines), Install summary lines. Step C grew from ~lines 816-840 to lines 816-1041. Plan B's pre-Plan-A annotations against this file were stale; refresh round 1 closed the drift on 5 anchor sites + added one operational-caveat sentence to Phase 5.2's CLAUDE.md note (verifier subagent inherits project PreToolUse hooks).
- **No commit-history fallback needed** — Plan B has only one commit on its drafting branch (created 2026-04-30); structural comparison done against current file state and external reality only.

## Plan Review — Round 1 refresh (post-Plan-A annotation refresh)

User scope directive: annotation refresh only (no strategy / AC / commit-boundary changes). Plan A (VERIFIER_AGENT_FIX, PR #189) landed and modified `skills/update-zskills/SKILL.md` Step C in-place — Plan B's line-number anchors against that file went stale. This round refreshed those anchors only.

### Edits applied (annotation refresh)
- Tracker (line 68) + Phase 3 Goal (line 319) + Phase 3.1 (line 325): canonical-table anchor `882-888` → `944-948` (+ literal-text fallback anchor: `**Canonical zskills-owned triples**` at line 939).
- Phase 3.1: prose anchor `line 890` → `line 950` (+ literal-text fallback `All 5 rows carry`).
- Phase 3.1: explainer block anchor `lines 842-851` → `lines 904-910` (+ literal-text fallback `> Installing 2 safety hooks:` at line 904).
- Phase 3.2: Step C anchor `lines 816-840` → Step C heading at line 816 ("Fill hook + agent gaps") with hook-copy bullets at `820-852`. Bullet-shape guidance added (mirror Plan A's `For \`<file>\`: copy as-is from $PORTABLE/hooks/ to .claude/hooks/.` pattern); insertion point pinned (immediately before `scripts/test-all.sh` at line 842).
- Phase 4.2: heading quote `"Fill hook gaps"` → `"Fill hook + agent gaps"`; Step C body extent annotation added (`816-1041` post-Plan-A; hook-copy bullets at 820-852).
- Phase 5.2 CLAUDE.md note: appended one sentence acknowledging that the verifier subagent (Plan A) inherits project PreToolUse hooks, so a verifier that edits a skill body without bumping `metadata.version` will see the deny envelope on `git commit` — recovery is bump-and-retry.

### Out-of-scope findings (recorded for future refinement)
- **DA-3 / DA-O-1 (Phase 4.2 Step C vs Step D placement).** DA pressure-tested Phase 4.2's Step-C placement of `install-helpers-into.sh` invocation. Step D ("Fill script gaps", line 1090) is the canonical home for `scripts/` install — it already documents the two-source pattern (`$PORTABLE/scripts/` AND `$PORTABLE/skills/update-zskills/stubs/`) and a "Report: 'Installed N scripts: [list]'" surface. Step C is "Fill hook + agent gaps"; the `scripts/test-all.sh` bullet inside Step C is a one-off legacy hand-out exception. Plan A widened Step C with the agent-copy block, making it more crowded — sticking another concern in Step C compounds the issue. AC11's negative-assertion (`grep -nE 'Step (B|C)' ... shows only "Step C"`) actively locks the wrong target. **Justified — out of scope this round (strategy change forbidden by user directive).** Recommend a follow-up `/refine-plan` invocation with broader scope to consider moving Phase 4.2's `install-helpers-into.sh` invocation from Step C to Step D and dropping/inverting AC11.
- **R-O-1 (`Installing N safety hooks` under-counts pre-existing).** The current explainer at lines 904-910 mentions only `block-unsafe-generic.sh` + `block-unsafe-project.sh` even though the canonical table at 944-948 wires 3 settings.json hooks (`+block-agents.sh`) + 2 PostToolUse `warn-config-drift.sh` rows. Plan B's Phase 3.1 expansion to "Installing 3 safety hooks" still under-counts. Pre-existing drift in the SKILL.md, not Plan-B-introduced. Out of scope per user directive — surface as a follow-up issue if desired.
- **R-O-3 (Phase 3.1 conflates 3 disjoint edit sites).** After the line-number fixes, Phase 3.1 still reads as one bullet describing three distinct edits (canonical-table append, prose update, explainer-block expansion). Refactoring for readability would not change spec — declined this round to keep changes annotation-only. Refiner's option for a future round.

### Verified-positive (no edit needed)
- Numeric arithmetic AC4 (`5 → 6`) and AC3 (`≥ 3` insertion-point count) still hold.
- Settings.json append-anchor `lines 8-15` (Phase 3.6) still holds — Plan A added zero settings.json wiring.
- Post-install summary at line 1003 in Plan A's new Step C end-block is for **non-settings-wired** hooks only; `block-stale-skill-version.sh` is settings.json-wired and is counted by the existing `Step C: registered N hook entries` report line at 998 — no edit needed there.
- Plan A's refined `tests/test-update-zskills-version-surface.sh` AC #8 jq-invocation regex (refined in PR #189) doesn't trip on Plan B's planned additions — Plan B introduces zero `jq` invocations by design (D4).

## Plan Review — Round 2 refresh (NORMAL scope, post-Plan-A second pass)

User scope directive: NORMAL (no annotation-only cap). All three Round-1 carry-overs and all new Round-2 findings (reviewer + DA) addressed where verified.

### Hook composition resolved empirically (Round 2 R2-N-1 / DA2-C-1 — critical)

DA2-C-1 challenged the Round-1-added Phase 5.2 sentence asserting "verifier subagent inherits project PreToolUse hooks." Composition semantics resolved by reading Anthropic Code docs:
- https://code.claude.com/docs/en/sub-agents §"Hooks in subagent frontmatter": *"Frontmatter hooks fire when the agent is spawned as a subagent through the Agent tool or an @-mention, and when the agent runs as the main session via `--agent` or the `agent` setting. In the main-session case they run alongside any hooks defined in `settings.json`."*
- https://code.claude.com/docs/en/hooks: subagent frontmatter hooks active *"while the component is active"* — additive scoping, not replace.

The "alongside settings.json" language is explicit for the main-session case; the subagent-case docs describe frontmatter hooks as additionally active rather than replacing project hooks. Reasonable interpretation: project PreToolUse hooks fire on EVERY tool call from EVERY context (main session AND subagent); subagent frontmatter hooks add to that set when the subagent is active. Composition is confirmed sufficiently to land Plan B without a new manual recipe; if a future Anthropic doc revision contradicts this, Phase 1's R-recipe pattern accommodates re-verification.

### Round 2 findings + dispositions

Reviewer (R2) and DA (DA2) overlaps de-duplicated. Net 13 findings (2 critical, 4 high — including DA2-H-3 doc-only, 4 medium, 3 low). All 13 fixed; 6 verified-positive findings recorded as no-edit.

| ID | Source | Severity | Disposition |
|----|--------|----------|-------------|
| R2-CO-A / DA2-H-1 | reviewer + DA | High | Fixed — Phase 4.2 moved to Step D; AC2 wording fixed; AC11 inverted; D&C bullets updated; Phase 4 AC10 reworded (mtime-only); new AC12 (≥ 4 row count). |
| R2-CO-B / DA2-H-2 | reviewer + DA | High | Fixed — Phase 3.1c explainer scoped to "Installing 3 PreToolUse Bash safety hooks" (not "6"); Phase 3 AC4 strengthened with explainer assertion. |
| R2-CO-C / DA2-L-1 | reviewer + DA | Low | Fixed — Phase 3.1 split into 3.1a/3.1b/3.1c with order-independence note. |
| R2-N-1 / DA2-C-1 | reviewer + DA | Critical | Fixed — Phase 5.2 paragraph rewritten with composition-semantics citation, verifier-side recovery (`Edit`+`Bash` allowlist → self-bump), orchestrator-side recovery, hook-chain composition note; new ACs 2a, 2b. |
| R2-N-2 / DA2-C-2 | reviewer + DA | Critical | Fixed — Phase 5.1 rewritten to date-only H2 + `### Added —` H3 convention with explicit date-collision handling; Phase 5 AC1 strengthened (no duplicate H2, H3-prefix grep). |
| R2-N-3 | reviewer | Low | Fixed — Phase 3.6 anchor reworded (drift-tolerant by content + line range). |
| R2-N-4 | reviewer | Low (note) | Fixed — Phase 2 D&C "Fail-open is restricted to FIRST link" sentence added documenting half-install behavior. |
| R2-N-5 | reviewer | Low (note) | Fixed — hook chain composition note added to Phase 5.2 (also references-doc sibling subsection per spec). |
| R2-N-6 / R2-N-7 / R2-N-8 | reviewer | Low | Auto-fixed by R2-CO-A's Phase 4 edits (Step B → Step D residue cleared). |
| R2-N-9 | reviewer | Low | Justified — left to implementer; AC5 already MAJOR.MINOR-tolerant per N8. |
| DA2-H-3 | DA | High (doc-only) | Fixed — Phase 5.6 D3 prose strengthened with two in-session reproducers (DA-observed live grep + sed false-positives); routing decision unchanged (`/draft-plan plans/BLOCK_UNSAFE_HARDENING.md` follow-up, not a 404-specific issue). |
| DA2-M-1 | DA | Medium | Fixed — Phase 5.2 cross-reference between `## Skill versioning` and `## Verifier-cannot-run rule` added; new AC2a. |
| DA2-M-2 | DA | Medium | Fixed — Phase 3.6 indent guidance added (10-space outer brace, 12-space keys; "match existing entry shape verbatim"). |
| DA2-M-3 | DA | Medium | Fixed — Phase 4.2 cites Step A explicitly for `$PORTABLE` resolution. |
| DA2-M-4 | DA | Medium | Fixed — Phase 4 AC10 reworded to mtime-only with explicit `sleep 1` boundaries; inode-comparison dropped (cp overwrites in place; inode is preserved across COPY). |
| DA2-L-2 | DA | Low | Fixed — `bash -c '<git commit>'` carve-out documented in Phase 2 D&C "Match strategy"; new test case C10e (negative); Phase 2.4 case count 26 → 27. |
| DA2-L-3 | DA | Low | Fixed — Phase 5.5 ambiguous-output skip rule added alongside the no-binary CI-skip rule. |

### Verified-positive (carried forward unchanged)
- R2-VP-1..6 (numeric AC4 arithmetic, settings.json anchor still holds, helper scripts complete, Phase 2 unaffected, AC4-on-Phase-3, CHANGELOG non-overwrite — last contingent on the now-applied Phase 5.1 rewrite).
- DA2-VP-1..4 (helper-script CLI signatures stable, run-all.sh dispatcher pattern stable, Phase 3.6 line anchors empirically held, `git commit --amend` / `-a` covered by tokenize-then-walk).

### Round 2 net delta
- Phase 2.1 / 2.2 / 2.4 / AC3 / AC5: case count 26 → 27 (added C10e).
- Phase 2 D&C: gained "Known carve-out: bash -c" bullet and "Fail-open is restricted to FIRST link" amendment.
- Phase 3.1 split into 3.1a/3.1b/3.1c; Phase 3 AC4 strengthened; Phase 3 D&C commit-boundary scope updated to enumerate the new sub-bullets.
- Phase 3.6 indent guidance added.
- Phase 4.2 moved Step C → Step D with Step A cross-ref + paragraph rewording; D&C boundary + shared-driver bullet + `mirror-skill.sh` bullet updated; AC2 wording (Step B → Step D); AC10 mtime-only reword; AC11 inverted; new AC12 (≥ 4 row count post-Phase-4).
- Phase 5.1 rewritten to current CHANGELOG convention with date-collision spec; AC1 strengthened.
- Phase 5.2 paragraph rewritten with composition citation + verifier/orchestrator recovery; cross-reference to Verifier-cannot-run section; new ACs 2a, 2b.
- Phase 5.5 ambiguous-output skip rule added.
- Phase 5.6 D3 prose strengthened with DA-observed reproducers.

### Convergence judgment

The Round 2 surface is complete: all 13 deduped findings have hard fixes (no Justified-not-fixed); the 5 verified-positives include the date-collision contingency that Round 2 closed. Net new gaps introduced by these edits: none material. Two cross-edit risk spots flagged for orchestrator confirmation: (a) AC2 + AC11 + AC12 cross-referencing on Phase 4 (Step D placement); (b) Phase 5.2 paragraph composition-citation + AC2b grep alignment.
