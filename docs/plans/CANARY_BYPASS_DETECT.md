---
title: Canary — Bypass-Detect Hook + Caller-Marker Wrapper Carve-Out (LAND_PR_BYPASS_HARDENING Phase 5)
created: 2026-05-13
status: ready
---

# Plan: Canary — Bypass-Detect Hook + Wrapper-Script Carve-Out

> **Landing mode: none — this is a behavioral canary.** No PR is opened
> or merged. The canary exercises the hook decision surface against
> synthesized stdin envelopes and synthesized marker fixtures inside a
> sandbox tmpdir. No `gh pr create` / `gh pr merge --auto` is invoked
> against any remote.

## Overview

End-to-end behavioral validation that `hooks/block-bypassed-land-pr.sh`
(shipped in Phase 1) plus the per-caller `requires.land-pr.<id>` +
`fulfilled.<skill>.<id>` markers (shipped in Phase 2) plus the active
`.claude/settings.json` registration (shipped in Phase 3) interlock the
way the design says they do, without driving a real PR landing.

Two phases:

- **Phase 1 — sandbox-stub hook stdin.** Drive the hook directly with a
  JSON Bash-tool envelope (`{tool_name:Bash, tool_input:{command:...}}`)
  for both bypass-class commands (`gh pr create`, `gh pr merge --auto`,
  including the chained / multi-flag / `--repo=` / 2-token-`--repo`
  forms) and confirm the deny envelope is emitted. Verify Pattern 1
  fires with no marker present, and Pattern 2 fires when a synthesized
  `requires.land-pr.<id>` marker with `branch: $HEAD` is present in the
  sandbox tracking tree.

- **Phase 2 — synthesized `/commit pr` markers + wrapper-script
  carve-out.** Synthesize a complete pair (`requires.land-pr.$BRANCH_SLUG`
  + `fulfilled.commit.$BRANCH_SLUG`) matching exactly the printf shape
  in `skills/commit/modes/pr.md`. Then run the hook against a
  `bash $CLAUDE_PROJECT_DIR/.claude/skills/land-pr/scripts/pr-push-and-create.sh ...`
  envelope (the wrapper-script invocation /land-pr itself uses) and
  confirm it is allowed through cleanly — the inner `gh pr create`
  inside that script is NOT visible to the PreToolUse Bash hook.

## Success criteria (whole run)

- Phase 1: all bypass-class envelopes (C1, C5, C6, C7, C8, C16, C19,
  C20 from `tests/test-block-bypassed-land-pr.sh`) produce deny
  envelopes with valid JSON + `permissionDecision: deny` +
  `STOP: direct gh pr` anchor.
- Phase 1: ALLOW-class envelopes (C9-C14) produce empty stdout +
  exit 0.
- Phase 1: Pattern 1 vs Pattern 2 selection follows the caller-marker
  state — matching-branch marker → Pattern 2, no marker → Pattern 1.
- Phase 2: synthesized `requires.land-pr.$BRANCH_SLUG` matches the
  exact line shape in `skills/commit/modes/pr.md` (5 fields, one per
  line, ISO-8601 date, branch matching `^[a-zA-Z0-9./_-]+$`).
- Phase 2: `bash $wrapper-script-path` envelope passes (no deny —
  wrapper-script carve-out works).
- Phase 2: removing the marker pair AFTER simulating fulfillment and
  re-running the hook on `gh pr create` flips Pattern 2 back to
  Pattern 1 (state-driven, not heuristic).
- No live `gh pr create` / `gh pr merge --auto` issued. Verify with
  `gh api user >/dev/null` skipped — the canary needs no network.

## Setup

1. Confirm the bypass-detect hook file is present and executable:
   ```bash
   [ -x hooks/block-bypassed-land-pr.sh ] && echo "OK"
   [ -x scripts/land-pr-bypass-message.sh ] && echo "OK"
   [ -f hooks/_lib/git-tokenwalk.sh ] && echo "OK"
   ```
2. Confirm the integration test passes against the current tree:
   ```bash
   bash tests/test-block-bypassed-land-pr.sh
   # Expect: 26 passed, 0 failed
   ```
3. Confirm the umbrella runner includes the test:
   ```bash
   grep -F 'test-block-bypassed-land-pr.sh' tests/run-all.sh
   ```
4. Confirm hook registration in `.claude/settings.json`:
   ```bash
   grep -F 'block-bypassed-land-pr.sh' .claude/settings.json
   ```
5. Conformance baseline green:
   ```bash
   bash tests/test-skill-conformance.sh
   ```

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Hook stdin sandbox-stub | ⬜ Ready | — | bash hook < envelope, assert deny/allow |
| 2 — Marker synthesis + wrapper-script carve-out | ⬜ Ready | — | requires.land-pr.* + fulfilled.commit.* + bash wrapper |

## Phase 1 — Hook stdin sandbox-stub

### Goal

Drive `hooks/block-bypassed-land-pr.sh` directly with synthesized JSON
envelopes (matching the PreToolUse `Bash` shape Claude Code passes on
stdin) for both bypass and non-bypass commands; assert the hook's
decision matches the design.

### Work Items

- [ ] Create a sandbox tmpdir and initialize it as `$CLAUDE_PROJECT_DIR`:
  ```bash
  SANDBOX=$(mktemp -d)
  trap 'rm -rf "$SANDBOX"' EXIT
  mkdir -p "$SANDBOX/scripts" "$SANDBOX/.zskills/tracking"
  cp scripts/land-pr-bypass-message.sh "$SANDBOX/scripts/"
  chmod +x "$SANDBOX/scripts/land-pr-bypass-message.sh"
  (cd "$SANDBOX" && git init -q -b main . && \
     git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init)
  export CLAUDE_PROJECT_DIR="$SANDBOX"
  ```

- [ ] **Pattern 1 (no markers)** — drive each bypass-class command and
  assert deny envelope + Pattern 1 anchor:
  ```bash
  for cmd in \
    'gh pr create -B main' \
    'gh pr merge --auto' \
    'gh pr merge --auto --squash' \
    'gh pr merge --squash --auto' \
    'gh pr merge --merge --auto' \
    'cd /tmp/wt && gh pr create -B main' \
    'gh --repo foo/bar pr create -B main' \
    'gh --repo=foo/bar pr create -B main'
  do
    envelope=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd")
    out=$(cd "$SANDBOX" && printf '%s' "$envelope" | bash hooks/block-bypassed-land-pr.sh)
    case "$out" in
      *'"permissionDecision":"deny"'*'STOP: direct gh pr'*'outside a caller skill'*)
        echo "OK Pattern1: $cmd" ;;
      *) echo "FAIL Pattern1: $cmd → $out"; exit 1 ;;
    esac
  done
  ```

- [ ] **Pattern 2 (matching-branch marker)** — synthesize a marker
  pointing at the sandbox's HEAD branch and re-drive the bypass-class
  command; assert Pattern 2 anchor:
  ```bash
  HEAD=$(cd "$SANDBOX" && git symbolic-ref --short HEAD)
  PIPELINE="commit.canary-bypass-p1"
  ID="canary-bypass-p1"
  mkdir -p "$SANDBOX/.zskills/tracking/$PIPELINE"
  NOW=$(TZ=UTC date -Iseconds)
  cat > "$SANDBOX/.zskills/tracking/$PIPELINE/requires.land-pr.$ID" <<MARK
  skill: land-pr
  parent: commit
  id: $ID
  branch: $HEAD
  date: $NOW
  MARK
  envelope='{"tool_name":"Bash","tool_input":{"command":"gh pr create -B main"}}'
  out=$(cd "$SANDBOX" && printf '%s' "$envelope" | bash hooks/block-bypassed-land-pr.sh)
  case "$out" in
    *'/land-pr invocation appears to have errored'*) echo "OK Pattern2" ;;
    *) echo "FAIL Pattern2 → $out"; exit 1 ;;
  esac
  ```

- [ ] **ALLOW path** — drive each non-bypass command and assert empty
  stdout + exit 0:
  ```bash
  for cmd in \
    'gh issue create -t foo' \
    'gh pr view 123' \
    'gh pr checks --watch' \
    'gh pr merge 123' \
    'gh pr --help' \
    'gh --help'
  do
    envelope=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd")
    out=$(cd "$SANDBOX" && printf '%s' "$envelope" | bash hooks/block-bypassed-land-pr.sh)
    rc=$?
    if [ "$rc" -ne 0 ] || [ -n "$out" ]; then
      echo "FAIL ALLOW: $cmd → rc=$rc out=$out"; exit 1
    fi
    echo "OK ALLOW: $cmd"
  done
  ```

### Acceptance Criteria — Phase 1

- [ ] AC-P1.1: All 8 Pattern-1 envelopes deny with `outside a caller
  skill` substring.
- [ ] AC-P1.2: Matching-branch marker flips the same `gh pr create`
  envelope to Pattern 2 (`/land-pr invocation appears to have errored`
  substring).
- [ ] AC-P1.3: All 6 ALLOW envelopes return exit 0 + empty stdout.

## Phase 2 — Marker synthesis + wrapper-script carve-out

### Goal

Synthesize the full `/commit pr` marker pair (`requires.land-pr.<id>` +
`fulfilled.commit.<id>`) matching the exact printf shape in
`skills/commit/modes/pr.md`, then drive the hook against a `bash
$wrapper-script-path` invocation that mirrors what `/land-pr` itself
runs. Confirm the carve-out is intact (no deny on the wrapper) while
the bare bypass-class command IS denied with Pattern 2 wording.

This validates the load-bearing architectural claim from the Phase 1
hook comment block: "PreToolUse Bash hooks see the outer `bash
scripts/pr-push-and-create.sh ...` invocation, not the inner `gh pr
create` inside that script — so the hook NEVER fires on /land-pr's
own gh invocation."

### Work Items

- [ ] Continue with `$SANDBOX` and `$HEAD` from Phase 1.

- [ ] **Synthesize the `/commit pr` marker pair** matching exactly the
  format `skills/commit/modes/pr.md:88-110` writes:
  ```bash
  BRANCH_SLUG="canary-bypass-p2"
  PIPELINE="commit.$BRANCH_SLUG"
  TRACK_DIR="$SANDBOX/.zskills/tracking/$PIPELINE"
  mkdir -p "$TRACK_DIR"
  NOW_ISO=$(TZ=UTC date -Iseconds)
  # fulfilled.commit.<slug> — exact shape from pr.md:97-103.
  cat > "$TRACK_DIR/fulfilled.commit.$BRANCH_SLUG" <<MARK
  status: started
  date: $NOW_ISO
  skill: commit
  mode: pr
  branch: $HEAD
  MARK
  # requires.land-pr.<slug> — exact shape from pr.md:105-110.
  cat > "$TRACK_DIR/requires.land-pr.$BRANCH_SLUG" <<MARK
  skill: land-pr
  parent: commit
  id: $BRANCH_SLUG
  branch: $HEAD
  date: $NOW_ISO
  MARK
  ```

- [ ] **Marker-shape integration smoke (AC5.6 / DA-5-9)** — parse the
  synthesized `requires.land-pr.$BRANCH_SLUG` and assert:
  - 5 separate lines: `skill:`, `parent:`, `id:`, `branch:`, `date:`.
  - `branch:` value matches `^[a-zA-Z0-9./_-]+$` (not empty, no shell
    metacharacters).
  - `date:` value parses as ISO-8601 via `date -d`.
  ```bash
  marker="$TRACK_DIR/requires.land-pr.$BRANCH_SLUG"
  for field in skill parent id branch date; do
    cnt=$(grep -c "^$field: " "$marker")
    [ "$cnt" -eq 1 ] || { echo "FAIL $field count=$cnt"; exit 1; }
  done
  branch_val=$(grep '^branch: ' "$marker" | cut -d' ' -f2-)
  [[ "$branch_val" =~ ^[a-zA-Z0-9./_-]+$ ]] || { echo "FAIL branch=$branch_val"; exit 1; }
  date_val=$(grep '^date: ' "$marker" | cut -d' ' -f2-)
  date -d "$date_val" >/dev/null || { echo "FAIL date=$date_val"; exit 1; }
  echo "OK marker shape"
  ```

- [ ] **Wrapper-script carve-out** — drive the hook with the EXACT
  wrapper-script command shape `/land-pr` SKILL.md uses:
  ```bash
  WRAPPER_CMD='bash $CLAUDE_PROJECT_DIR/.claude/skills/land-pr/scripts/pr-push-and-create.sh --branch=foo --title=x --body-file=/tmp/x --base=main'
  envelope=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$WRAPPER_CMD")
  out=$(cd "$SANDBOX" && printf '%s' "$envelope" | bash hooks/block-bypassed-land-pr.sh)
  rc=$?
  if [ "$rc" -ne 0 ] || [ -n "$out" ]; then
    echo "FAIL wrapper-script carve-out: rc=$rc out=$out"; exit 1
  fi
  echo "OK wrapper-script carve-out (bash \$script → ALLOW)"
  ```
  This proves the hook's `*"gh "*"pr "*` early-exit substring filter
  does NOT match a `bash <path>` invocation, regardless of whether the
  marker pair is present.

- [ ] **Bypass-class still denied with Pattern 2 wording** — confirm
  the marker pair makes the bare `gh pr create` invocation deny with
  Pattern 2 wording (the carve-out is wrapper-only — bare invocations
  still trip the hook):
  ```bash
  envelope='{"tool_name":"Bash","tool_input":{"command":"gh pr create -B main"}}'
  out=$(cd "$SANDBOX" && printf '%s' "$envelope" | bash hooks/block-bypassed-land-pr.sh)
  case "$out" in
    *'/land-pr invocation appears to have errored'*) echo "OK Pattern2 (markers present)" ;;
    *) echo "FAIL Pattern2 with markers → $out"; exit 1 ;;
  esac
  ```

- [ ] **Fulfillment teardown — Pattern 2 reverts to Pattern 1** —
  simulate `/land-pr` completion by removing `requires.land-pr.*` and
  flipping `fulfilled.commit.*` to `status: landed`, then re-drive the
  hook on the same bare `gh pr create` envelope; assert Pattern 1
  (state-driven, not heuristic):
  ```bash
  rm -f "$TRACK_DIR/requires.land-pr.$BRANCH_SLUG"
  sed -i 's/^status: started$/status: landed/' "$TRACK_DIR/fulfilled.commit.$BRANCH_SLUG"
  envelope='{"tool_name":"Bash","tool_input":{"command":"gh pr create -B main"}}'
  out=$(cd "$SANDBOX" && printf '%s' "$envelope" | bash hooks/block-bypassed-land-pr.sh)
  case "$out" in
    *'outside a caller skill'*) echo "OK Pattern1 (markers cleared)" ;;
    *) echo "FAIL Pattern1 after marker clear → $out"; exit 1 ;;
  esac
  ```

### Acceptance Criteria — Phase 2

- [ ] AC-P2.1: Marker pair synthesized matches the byte-shape
  `skills/commit/modes/pr.md` writes (verified by line-count + per-field
  grep + ISO-8601 date parse + branch regex).
- [ ] AC-P2.2: `bash $wrapper-script-path ...` envelope passes (rc=0,
  empty stdout) — carve-out intact.
- [ ] AC-P2.3: Same `gh pr create -B main` envelope produces Pattern 2
  deny with markers present, Pattern 1 deny with markers cleared —
  state-driven, not heuristic.

## Notes for first-runner

- This canary is **non-interactive** and **non-network**. It can run
  in any sandbox / CI environment that has bash + git + date(1) +
  python3 (for JSON validation, optional). No GitHub API calls.
- The canary EXISTS to prove the structural-defense layer interlocks
  the way Phases 1–4 say it does. If a future PR regresses any of:
  hook registration in `.claude/settings.json`, hook decision logic in
  `hooks/block-bypassed-land-pr.sh`, message-enrichment behavior in
  `scripts/land-pr-bypass-message.sh`, marker shape in any of the 4
  Phase 2 caller skills, OR helper drift in
  `hooks/_lib/git-tokenwalk.sh`, this canary should catch it.
- The unit-level coverage of the same decision matrix is in
  `tests/test-block-bypassed-land-pr.sh` (26 cases). This canary
  complements that test by chaining the decision against synthesized
  caller-side state transitions (marker present → absent flip).
- If the canary fails, check in order:
  1. `bash tests/test-block-bypassed-land-pr.sh` — unit-level failure
     first.
  2. `grep -F block-bypassed-land-pr.sh .claude/settings.json` — hook
     registration.
  3. `bash tests/test-hook-helper-drift.sh` — helper inlining drift.
  4. Marker shape in `skills/commit/modes/pr.md`,
     `skills/quickfix/SKILL.md`, `skills/do/modes/pr.md`,
     `skills/fix-issues/modes/pr.md` — printf shape regression.
