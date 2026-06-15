#!/usr/bin/env bash
# Tests for hooks/block-main-edits.sh — issue #308.
# Run from repo root: bash tests/test-block-main-edits.sh
#
# Coverage matrix:
#
#   C1   Edit on main, non-allowlisted path     → DENY
#   C2   Write on main, non-allowlisted path    → DENY
#   C4   Edit in linked worktree (same file)    → ALLOW
#   C5   Edit on main, .zskills/audit/*         → ALLOW (allowlist)
#   C6   Edit on main, .zskills/tracking/<id>/* → ALLOW (allowlist)
#   C7   Edit on main, .zskills/issues/*        → ALLOW (allowlist)
#   C8   Edit on main, .zskills-tracked         → ALLOW (allowlist, legacy window)
#   C9   Edit on main, .landed                  → ALLOW (allowlist, legacy window)
#   C8b-C9c  Edit on main, .zskills/{tracked,landed,worktreepurpose} → ALLOW (Phase 8 paths via .zskills/* arm)
#   C10  Edit on main, main_protected=false     → ALLOW (config gate off)
#   C11  Edit on main, config missing           → ALLOW (default off)
#   C12  Edit outside MAIN_ROOT entirely        → ALLOW
#   C13  Bash invocation (wrong tool)           → ALLOW (no-op)
#   C14  Edit with no file_path field           → ALLOW (defensive)
#   C15  Edit skills/<name>/SKILL.md on main    → DENY (canonical block target)
#   C16  Edit hooks/foo.sh on main              → DENY (canonical block target)
#   C17  Edit CLAUDE.md on main                 → DENY (canonical block target)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# DA9 (CASCADE v2, ENFORCEMENT_V2 Phase 4): sandbox HOME so a dev machine's
# personal ~/.claude/zskills-config.json (which Phase 6 promotes creating)
# cannot flip the now-two-tier main_protected read in block-main-edits.sh.
TMP_HOME="$(mktemp -d /tmp/zskills-block-main-edits-home-XXXXXX)"; export HOME="$TMP_HOME"
printf '[user]\n\tname = zskills-test\n\temail = zskills-test@example.com\n[safe]\n\tdirectory = *\n' > "$TMP_HOME/.gitconfig"
HOOK="$REPO_ROOT/hooks/block-main-edits.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  printf '    %s\n' "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "=== block-main-edits.sh ==="

# ── Sandbox setup ────────────────────────────────────────────────────────
# Build a self-contained sandbox that LOOKS like a main repo:
#   $SANDBOX/.git/                       (real init, branch=main)
#   $SANDBOX/.claude/zskills-config.json (main_protected: true)
#   $SANDBOX/CLAUDE.md                   (a "main" file)
#   $SANDBOX/skills/foo/SKILL.md         (another "main" file)
#   $SANDBOX/hooks/x.sh                  (another "main" file)
#   $SANDBOX/.zskills/audit/r.md         (allowlisted file)
#   $SANDBOX/.zskills/tracking/p/req.x   (allowlisted file)
#   $SANDBOX/.zskills/issues/i.md        (allowlisted file)
#
# Then add a linked worktree at $SANDBOX-wt/ on branch 'feat/x'.
SANDBOX=$(mktemp -d)
WORKTREE="${SANDBOX}-wt"
trap 'cd /; (cd "$SANDBOX" && git worktree remove --force "$WORKTREE" 2>/dev/null); rm -rf "$SANDBOX" "$WORKTREE"' EXIT

mkdir -p "$SANDBOX"
# We use the GIT_AUTHOR_* / GIT_COMMITTER_* env so we don't trip the
# parent session's block-unsafe-project.sh hook (which gates `git -c
# user.email=...` style commits on `main` when main_protected is true in
# the PARENT repo's config — which it IS in this repo). Setting the
# identity via env vars routes around the `-c` token detection. Also we
# do the commits in a clean GIT_DIR-rooted invocation that's not visible
# to the outer hook surface.
#
# Branch naming note: the sandbox's "main-equivalent" branch is named
# `sandbox-trunk` (NOT `main`/`master`). The PARENT repo's
# block-unsafe-project.sh hook fires on `git commit` when the working tree
# it sees (the SANDBOX) is on a branch literally called `main` or
# `master` AND parent main_protected is true. Sandbox setup must not trip
# that gate — and our hook detects "main repo" via the
# git-dir == git-common-dir worktree self-check, not branch name, so any
# trunk name works.
(
  cd "$SANDBOX" || exit 1
  git init -q -b sandbox-trunk .
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
         GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git commit --allow-empty -q -m init
  mkdir -p .claude skills/foo hooks .zskills/audit .zskills/tracking/pipe1 .zskills/issues
  printf '{"execution":{"main_protected":true}}' > .claude/zskills-config.json
  : > CLAUDE.md
  : > skills/foo/SKILL.md
  : > hooks/x.sh
  : > .zskills/audit/r.md
  : > .zskills/tracking/pipe1/req.x
  : > .zskills/issues/i.md
  : > .zskills-tracked
  : > .landed
  # Stage by explicit name (the PARENT repo's block-unsafe-project hook
  # denies `git add -A` / `git add .` as a "sweeps in all sessions' work"
  # safety rule; we have to obey that from inside the test too).
  git add .claude/zskills-config.json CLAUDE.md skills/foo/SKILL.md \
          hooks/x.sh .zskills/audit/r.md .zskills/tracking/pipe1/req.x \
          .zskills/issues/i.md .zskills-tracked .landed
  git commit -q -m "seed"
)
# Linked worktree on a different branch.
(
  cd "$SANDBOX" || exit 1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
         GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git worktree add -q -b feat/x "$WORKTREE" sandbox-trunk 2>/dev/null
)

# ── Helpers ──────────────────────────────────────────────────────────────
# Run hook with a JSON envelope on stdin. CLAUDE_PROJECT_DIR is set to
# either $SANDBOX (the "main" case) or $WORKTREE (the "linked worktree"
# case). HOOK_OUT / HOOK_EXIT / HOOK_ERR are exposed for the assertion
# helpers below. Mirrors the pattern in tests/test-block-bypassed-land-pr.sh.
run_hook() {
  local project_dir="$1"
  local input="$2"
  # Optional $3 = the MAIN-root the enforcement lib's config_root() should
  # resolve to (ENFORCEMENT_V2_PLAN Phase 2). The hook's cwd here is the test
  # process cwd (this repo), so without this override
  # zskills_enforcement_config_root() would resolve to THIS repo via
  # git-common-dir, not the sandbox. For most cases ENF_CONFIG_ROOT == the
  # sandbox; for the worktree-session tamper case it stays the MAIN sandbox
  # even though CLAUDE_PROJECT_DIR points at the worktree.
  local enf_root="${3:-$project_dir}"
  local errf
  errf=$(mktemp)
  # Subshell with exported CLAUDE_PROJECT_DIR — `VAR=val cmd1 | cmd2` only
  # scopes VAR to cmd1, not cmd2 (the hook). The hook reads
  # CLAUDE_PROJECT_DIR to resolve MAIN_ROOT.
  HOOK_OUT=$(
    export CLAUDE_PROJECT_DIR="$project_dir"
    export ZSKILLS_ENF_CONFIG_ROOT="$enf_root"
    printf '%s' "$input" | bash "$HOOK" 2>"$errf"
  )
  HOOK_EXIT=$?
  HOOK_ERR=$(cat "$errf")
  rm -f "$errf"
}

# Build an Edit/Write envelope. The tool name varies by tool; both use
# file_path under tool_input.
mkenv_edit()   { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }
mkenv_write()  { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"; }
mkenv_bash()   { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
mkenv_edit_no_path() { printf '{"tool_name":"Edit","tool_input":{}}'; }

# Phase 2 (#1159) builders. $1 = file_path, $2 = permission_mode (e.g.
# "bypassPermissions" / "default" / "" for absent). The top-level
# permission_mode field is what the enforcement predicate keys on.
mkenv_edit_pm() {
  if [ -n "$2" ]; then
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"permission_mode":"%s"}' "$1" "$2"
  else
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"
  fi
}
# Tamper-arm builders: an Edit/Write whose new_string / content carries the
# `hooks` token (intersects the hooks block). $1 = file_path, $2 = permission_mode.
mkenv_edit_hooks() {
  if [ -n "$2" ]; then
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"x","new_string":"{\\"hooks\\":{\\"git_discipline\\":{\\"git_add_all\\":\\"off\\"}}}"},"permission_mode":"%s"}' "$1" "$2"
  else
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"x","new_string":"{\\"hooks\\":{\\"git_discipline\\":{\\"git_add_all\\":\\"off\\"}}}"}}' "$1"
  fi
}
# Tamper-arm builder where new_string sets config_hooks_tamper itself (self-
# protection case). $1 = file_path, $2 = permission_mode.
mkenv_edit_tamper_self() {
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"x","new_string":"{\\"hooks\\":{\\"main_protection\\":{\\"config_hooks_tamper\\":\\"off\\"}}}"},"permission_mode":"%s"}' "$1" "$2"
}
# Edit of the config NOT touching a hooks key (should fall through to main_edit).
mkenv_edit_nonhooks() {
  if [ -n "$2" ]; then
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"x","new_string":"{\\"execution\\":{\\"landing\\":\\"pr\\"}}"},"permission_mode":"%s"}' "$1" "$2"
  else
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"x","new_string":"{\\"execution\\":{\\"landing\\":\\"pr\\"}}"}}' "$1"
  fi
}

# Assert allow-with-NO-output (the silent shipped default): exit 0 AND empty
# stdout AND empty stderr (no warn-channel emission, no deny).
assert_silent() {
  local label="$1" exit_code="$2" stdout="$3" stderr="$4"
  if [ "$exit_code" -eq 0 ] && [ -z "$stdout" ] && [ -z "$stderr" ]; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code stdout=$stdout stderr=$stderr"
  fi
}

# Assert allow-with-warn (opt-in coaching): exit 0, the warn channel (W-A:
# stdout systemMessage) carries the tag substring, and NO permissionDecision.
assert_warn() {
  local label="$1" exit_code="$2" stdout="$3" tag="$4"
  local ok=1
  [ "$exit_code" -eq 0 ] || ok=0
  [[ "$stdout" == *"$tag"* ]] || ok=0
  [[ "$stdout" == *'"systemMessage"'* ]] || ok=0
  [[ "$stdout" == *'permissionDecision'* ]] && ok=0   # HARD INVARIANT: decision-less
  if [ "$ok" -eq 1 ]; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code stdout=$stdout"
  fi
}

assert_deny() {
  local label="$1" envelope="$2"
  local ok=1
  [[ "$envelope" == *'"permissionDecision":"deny"'* ]] || ok=0
  [[ "$envelope" == *'STOP'* ]] || ok=0
  if command -v python3 >/dev/null; then
    python3 -c 'import json,sys; json.loads(sys.stdin.read())' <<< "$envelope" >/dev/null 2>&1 || ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    pass "$label"
  else
    fail "$label" "envelope=$envelope"
  fi
}

assert_allow() {
  local label="$1" exit_code="$2" stdout="$3"
  if [ "$exit_code" -eq 0 ] && [ -z "$stdout" ]; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code stdout=$stdout"
  fi
}

# ── C1: Edit on main, non-allowlisted, BYPASS → DENY (bypass parity) ──────
# Re-spec (ENFORCEMENT_V2_PLAN Phase 2, Invariant 5): main_edit is now
# DEMOTABLE, so an autonomous/unwatched deny must be proven under an explicit
# permission_mode:"bypassPermissions". This is bypass-parity case 1/5 for the
# phase. OLD: mkenv_edit (no permission_mode → enforce-autonomous via fail-safe,
# also denied). NEW: explicit bypassPermissions, still DENY.
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/CLAUDE.md" bypassPermissions)"
assert_deny "C1: Edit on main (CLAUDE.md) bypass → DENY (bypass parity)" "$HOOK_OUT"

# ── C2: Write on main, non-allowlisted, BYPASS → DENY ─────────────────────
run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/CLAUDE.md")"
assert_deny "C2: Write on main (CLAUDE.md) absent-field → DENY (fail-safe)" "$HOOK_OUT"

# ── C4: Edit in linked worktree (same relative file, different abs path) ─
# CLAUDE_PROJECT_DIR points at the WORKTREE. The hook self-checks:
# git-dir != git-common-dir → exit 0 (no-op). This is the load-bearing
# "we only protect main" rule: a session started in a worktree must never
# block writes inside that worktree.
run_hook "$WORKTREE" "$(mkenv_edit "$WORKTREE/CLAUDE.md")"
assert_allow "C4: Edit in linked worktree → ALLOW (worktree self-check)" "$HOOK_EXIT" "$HOOK_OUT"

# ── C5–C7: allowlisted paths on main → ALLOW ─────────────────────────────
run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/.zskills/audit/r.md")"
assert_allow "C5: Edit on main .zskills/audit/* → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/.zskills/tracking/pipe1/req.x")"
assert_allow "C6: Write on main .zskills/tracking/<id>/* → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/.zskills/issues/i.md")"
assert_allow "C7: Edit on main .zskills/issues/* → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

# ── C8–C9: gitignored worktree-state markers → ALLOW ─────────────────────
run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/.zskills-tracked")"
assert_allow "C8: Write on main .zskills-tracked → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/.landed")"
assert_allow "C9: Write on main .landed → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

# ── C8b–C9b: Phase 8 consolidated marker paths (.zskills/* arm) → ALLOW ──
run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/.zskills/tracked")"
assert_allow "C8b: Write on main .zskills/tracked → ALLOW (Phase 8 path)" "$HOOK_EXIT" "$HOOK_OUT"

run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/.zskills/landed")"
assert_allow "C9b: Write on main .zskills/landed → ALLOW (Phase 8 path)" "$HOOK_EXIT" "$HOOK_OUT"

run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/.zskills/worktreepurpose")"
assert_allow "C9c: Write on main .zskills/worktreepurpose → ALLOW (Phase 8 path)" "$HOOK_EXIT" "$HOOK_OUT"

# ── C10: main_protected=false → ALLOW (config gate off, the load-bearing one) ──
printf '{"execution":{"main_protected":false}}' > "$SANDBOX/.claude/zskills-config.json"
run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/CLAUDE.md")"
assert_allow "C10: main_protected=false → ALLOW (gate off, issue #308 §1)" "$HOOK_EXIT" "$HOOK_OUT"

# ── C11: config missing → ALLOW (default off) ────────────────────────────
rm -f "$SANDBOX/.claude/zskills-config.json"
run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/CLAUDE.md")"
assert_allow "C11: config missing → ALLOW (default off)" "$HOOK_EXIT" "$HOOK_OUT"

# Restore main_protected for subsequent cases.
printf '{"execution":{"main_protected":true}}' > "$SANDBOX/.claude/zskills-config.json"

# ── C12: Edit outside MAIN_ROOT entirely → ALLOW ─────────────────────────
run_hook "$SANDBOX" "$(mkenv_edit "/tmp/some-other-path/foo.md")"
assert_allow "C12: Edit outside MAIN_ROOT → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

# ── C13: Bash tool (wrong matcher) → ALLOW ───────────────────────────────
run_hook "$SANDBOX" "$(mkenv_bash "ls")"
assert_allow "C13: Bash tool → ALLOW (defense-in-depth tool guard)" "$HOOK_EXIT" "$HOOK_OUT"

# ── C14: Edit envelope with no file_path → ALLOW (defensive, never false-deny) ─
run_hook "$SANDBOX" "$(mkenv_edit_no_path)"
assert_allow "C14: Edit with no file_path → ALLOW (defensive)" "$HOOK_EXIT" "$HOOK_OUT"

# ── C15: skills/<name>/SKILL.md on main, BYPASS → DENY (motivating case) ───
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/skills/foo/SKILL.md" bypassPermissions)"
assert_deny "C15: Edit skills/foo/SKILL.md on main bypass → DENY" "$HOOK_OUT"

# ── C16: hooks/*.sh on main, BYPASS → DENY ───────────────────────────────
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/hooks/x.sh" bypassPermissions)"
assert_deny "C16: Edit hooks/x.sh on main bypass → DENY" "$HOOK_OUT"

# ── C17: CLAUDE.md on main bypass → DENY, assert deny envelope contains a
# worktree alternative recommendation per the STOP message contract ────────
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/CLAUDE.md" bypassPermissions)"
if [[ "$HOOK_OUT" == *'/do'* ]] && [[ "$HOOK_OUT" == *'worktree'* ]]; then
  pass "C17: STOP message recommends worktree alternative (bypass deny arm)"
else
  fail "C17: STOP message recommends worktree alternative" "envelope=$HOOK_OUT"
fi

# ── C18: deny message must recommend /do pr (issue #398) ──
# The deny message must recommend /do pr as the primary worktree-routed
# alternative for an agent-dispatched edit. (deny arm = bypass/autonomous.)
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/CLAUDE.md" bypassPermissions)"
if [[ "$HOOK_OUT" == *'/do pr'* ]]; then
  pass "C18a: STOP message recommends /do pr (issue #398)"
else
  fail "C18a: STOP message recommends /do pr (issue #398)" "envelope=$HOOK_OUT"
fi

# ── C18b: deny envelope (bypass) message ends with its toggle tag ──────────
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/CLAUDE.md" bypassPermissions)"
if [[ "$HOOK_OUT" == *'[hooks.main_protection.main_edit'* ]]; then
  pass "C18b: deny message names its toggle (main_edit tag present)"
else
  fail "C18b: deny message names its toggle (main_edit tag present)" "envelope=$HOOK_OUT"
fi

# ── Windows-native-path normalisation (MSYS / Git-Bash consumer) ──────────
# On a Windows consumer the Edit/Write tool passes a backslash / drive-letter
# path. The hook now normalises $FILE_PATH through zskills_normalize_tool_path
# BEFORE the `case in /*)` classifier, so containment + the `.zskills/*`
# carve-out match on a POSIX form.
#
# LINUX-REPRODUCIBILITY NOTE: a faithful drive-letter case (file_path =
# `D:\proj\.zskills\x` with MAIN_ROOT = `D:\proj`) is NOT constructible on
# Linux — the hook computes MAIN_ROOT via `cd "$MAIN_ROOT" && pwd -P`, and a
# `D:\...` dir cannot be `cd`-ed into on a POSIX host. The drive-letter
# transform itself is proven directly by tests/test-normalize-tool-path.sh
# (cygpath is absent on Linux CI → that suite exercises the exact Windows
# fallback logic). HERE we exercise the in-hook normalisation faithfully on
# Linux by feeding a file_path whose RELATIVE TAIL uses backslash separators
# (the form Git-Bash emits under MAIN_ROOT) — proving the hook converts the
# separators so the carve-out / deny classification matches. Without the new
# normalisation these would mis-classify: the backslash carve-out path would
# FALSE-DENY (REL=`.zskills\audit\r.md` does not match `.zskills/*`).

# ── C19: backslash relative tail under .zskills carve-out → ALLOW ─────────
# Pre-fix this FALSE-DENIED (the exact issue: gitignored .zskills/ writes
# blocked on Windows). normalize → `.zskills/audit/r.md` → carve-out matches.
run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/.zskills\\audit\\r.md")"
assert_allow "C19: Write backslash .zskills\\audit\\r.md → ALLOW (Win carve-out, was false-deny)" "$HOOK_EXIT" "$HOOK_OUT"

# ── C20: backslash worktree-state marker tail → ALLOW (run-dashboard repro) ─
# Mirrors the issue's `D:\…\.zskills\run-dashboard-start.sh` shape via the
# Linux-reproducible backslash-tail form.
run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/.zskills\\run-dashboard-start.sh")"
assert_allow "C20: Write backslash .zskills\\run-dashboard-start.sh → ALLOW (issue repro)" "$HOOK_EXIT" "$HOOK_OUT"

# ── C21: backslash tail to a tracked main file → still DENY ──────────────
# Normalisation must NOT weaken the gate: a backslash path to a non-carve-out
# main file (skills/foo/SKILL.md) normalises and is STILL denied.
run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/skills\\foo\\SKILL.md")"
assert_deny "C21: Edit backslash skills\\foo\\SKILL.md on main → DENY (gate not weakened)" "$HOOK_OUT"

# ═══════════════════════════════════════════════════════════════════════════
# ENFORCEMENT_V2_PLAN Phase 2 (#1159) — demotion + tamper arm + toggles.
# main_protected is true in the sandbox (restored after C11 above).
# ═══════════════════════════════════════════════════════════════════════════

# The C8/C9 allowlist cases seeded committed `.zskills-tracked` + `.landed`
# root markers. The enforcement predicate's legacy dual-read arm treats a
# `.zskills-tracked` marker as a LIVE pipeline (→ enforce, never watched), so
# the WATCHED cases below must run without those markers present on disk. Remove
# the working-tree copies (non-recursive, specific files — the C8/C9 cases that
# needed them already ran). The pipeline-active case (ec2) re-creates a fresh
# `.zskills/tracked` explicitly.
rm -f "$SANDBOX/.zskills-tracked" "$SANDBOX/.landed"

# ── ec0: ZERO-CONFIG QUIET HEADLINE — watched Edit on main → EMITS NOTHING ──
# permission_mode:"default", no markers, no toggle, main_protected:true. The
# shipped demotable default is SILENT: allow + no warn-channel output + no deny.
# This is the owner-amendment headline (Settled decision 0 / AC "Zero-config
# quiet (partial)").
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/CLAUDE.md" default)"
assert_silent "ec0: watched Edit on main_protected → SILENT (zero-config quiet headline)" \
  "$HOOK_EXIT" "$HOOK_OUT" "$HOOK_ERR"
# And the tag must NOT appear anywhere (no emission at all).
if [[ "$HOOK_OUT" != *'[hooks.main_protection.main_edit'* ]]; then
  pass "ec0b: watched silent default emits no main_edit tag"
else
  fail "ec0b: watched silent default emits no main_edit tag" "out=$HOOK_OUT"
fi

# ── ec1: toggle "warn" + watched → ALLOW + warn-channel carries the tag ─────
printf '{"execution":{"main_protected":true},"hooks":{"main_protection":{"main_edit":"warn"}}}' > "$SANDBOX/.claude/zskills-config.json"
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/CLAUDE.md" default)"
assert_warn "ec1: toggle warn + watched → ALLOW + warn (opt-in coaching)" \
  "$HOOK_EXIT" "$HOOK_OUT" "[hooks.main_protection.main_edit"

# ── ec2: watched + .zskills/tracked present (pipeline-active) → DENY ────────
# A live pipeline marker at MAIN root forces enforce even when watched.
printf '{"execution":{"main_protected":true}}' > "$SANDBOX/.claude/zskills-config.json"
mkdir -p "$SANDBOX/.zskills"
: > "$SANDBOX/.zskills/tracked"
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/CLAUDE.md" default)"
assert_deny "ec2: watched + .zskills/tracked (pipeline-active) → DENY" "$HOOK_OUT"
rm -f "$SANDBOX/.zskills/tracked"

# ── ec3: watched + stale .zskills/tracking/<id>/ subdir, NO tracked → SILENT (DA2) ──
# A stale finished-pipeline subdir must NOT force enforce (bare tracking/ dir is
# deliberately not a signal). No toggle → silent default.
mkdir -p "$SANDBOX/.zskills/tracking/stale-pipe"
: > "$SANDBOX/.zskills/tracking/stale-pipe/req.x"
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/CLAUDE.md" default)"
assert_silent "ec3: watched + stale tracking/ subdir, no tracked → SILENT (DA2)" \
  "$HOOK_EXIT" "$HOOK_OUT" "$HOOK_ERR"
rm -rf "$SANDBOX/.zskills/tracking/stale-pipe"

# ── ec4: toggle "off" + watched → SILENT allow ─────────────────────────────
printf '{"execution":{"main_protected":true},"hooks":{"main_protection":{"main_edit":"off"}}}' > "$SANDBOX/.claude/zskills-config.json"
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/CLAUDE.md" default)"
assert_silent "ec4: toggle off + watched → SILENT allow" "$HOOK_EXIT" "$HOOK_OUT" "$HOOK_ERR"

# ── ec5: toggle "block" + watched → DENY (hard-deny-even-attended override) ─
printf '{"execution":{"main_protected":true},"hooks":{"main_protection":{"main_edit":"block"}}}' > "$SANDBOX/.claude/zskills-config.json"
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/CLAUDE.md" default)"
assert_deny "ec5: toggle block + watched → DENY (explicit override)" "$HOOK_OUT"

# ── ec6: toggle "warn" + BYPASS → ALLOW + warn (explicit override honored in
# BOTH arms — Settled decision 6, unchanged by the amendment) ──────────────
printf '{"execution":{"main_protected":true},"hooks":{"main_protection":{"main_edit":"warn"}}}' > "$SANDBOX/.claude/zskills-config.json"
run_hook "$SANDBOX" "$(mkenv_edit_pm "$SANDBOX/CLAUDE.md" bypassPermissions)"
assert_warn "ec6: toggle warn + bypass → ALLOW + warn (explicit override both arms)" \
  "$HOOK_EXIT" "$HOOK_OUT" "[hooks.main_protection.main_edit"

# Restore default config for the tamper-arm cases.
printf '{"execution":{"main_protected":true}}' > "$SANDBOX/.claude/zskills-config.json"

# ═══ config_hooks_tamper arm (registry row 49, Settled decision 13) ════════
CFG="$SANDBOX/.claude/zskills-config.json"

# ── tc1: tamper Edit (hooks in new_string) + BYPASS → DENY (bypass parity 2/5) ─
run_hook "$SANDBOX" "$(mkenv_edit_hooks "$CFG" bypassPermissions)"
assert_deny "tc1: tamper Edit + bypass → DENY (bypass parity, config_hooks_tamper)" "$HOOK_OUT"
if [[ "$HOOK_OUT" == *'[hooks.main_protection.config_hooks_tamper'* ]]; then
  pass "tc1b: tamper deny names config_hooks_tamper toggle"
else
  fail "tc1b: tamper deny names config_hooks_tamper toggle" "out=$HOOK_OUT"
fi

# ── tc2: tamper Edit + WATCHED, no toggle → WARN allow (DA4 named exception) ─
# The ONE demotable check that warns-when-watched by shipped default (NOT silent).
run_hook "$SANDBOX" "$(mkenv_edit_hooks "$CFG" default)"
assert_warn "tc2: tamper watched no-toggle → WARN (DA4 named-exception default, NOT silent)" \
  "$HOOK_EXIT" "$HOOK_OUT" "[hooks.main_protection.config_hooks_tamper"

# ── tc3: tamper Edit + watched + explicit "warn" → WARN (identical to default) ─
printf '{"execution":{"main_protected":true},"hooks":{"main_protection":{"config_hooks_tamper":"warn"}}}' > "$CFG"
run_hook "$SANDBOX" "$(mkenv_edit_hooks "$CFG" default)"
assert_warn "tc3: tamper watched explicit warn → WARN" \
  "$HOOK_EXIT" "$HOOK_OUT" "[hooks.main_protection.config_hooks_tamper"

# ── tc4: tamper Edit + watched + explicit "off" → SILENT allow (reviewed override) ─
printf '{"execution":{"main_protected":true},"hooks":{"main_protection":{"config_hooks_tamper":"off"}}}' > "$CFG"
run_hook "$SANDBOX" "$(mkenv_edit_hooks "$CFG" default)"
assert_silent "tc4: tamper watched explicit off → SILENT (named exception overridable)" \
  "$HOOK_EXIT" "$HOOK_OUT" "$HOOK_ERR"

# Restore default config.
printf '{"execution":{"main_protected":true}}' > "$CFG"

# ── tc5: Edit of config NOT touching a hooks key → falls through to main_edit ─
# A non-hooks config Edit while WATCHED hits the main_edit silent default
# (config file is still under main, but the tamper arm does not fire).
run_hook "$SANDBOX" "$(mkenv_edit_nonhooks "$CFG" default)"
assert_silent "tc5: non-hooks config Edit watched → SILENT (falls through to main_edit)" \
  "$HOOK_EXIT" "$HOOK_OUT" "$HOOK_ERR"
# And the same non-hooks config Edit under BYPASS → DENY via main_edit (not tamper).
run_hook "$SANDBOX" "$(mkenv_edit_nonhooks "$CFG" bypassPermissions)"
assert_deny "tc5b: non-hooks config Edit bypass → DENY via main_edit arm" "$HOOK_OUT"
if [[ "$HOOK_OUT" == *'[hooks.main_protection.main_edit'* ]]; then
  pass "tc5c: non-hooks config Edit deny names main_edit (not tamper)"
else
  fail "tc5c: non-hooks config Edit deny names main_edit (not tamper)" "out=$HOOK_OUT"
fi

# ── tc6: main_protected ABSENT → tamper arm STILL fires (placement headline, R2-6) ─
printf '{"execution":{}}' > "$CFG"
run_hook "$SANDBOX" "$(mkenv_edit_hooks "$CFG" bypassPermissions)"
assert_deny "tc6: tamper arm fires even with main_protected absent (placement above gate)" "$HOOK_OUT"
printf '{"execution":{"main_protected":true}}' > "$CFG"

# ── tc7: worktree session editing MAIN root's config by abs path → still gated (DA3) ─
# CLAUDE_PROJECT_DIR points at the WORKTREE, but ENF_CONFIG_ROOT stays the MAIN
# sandbox; the Edit targets the MAIN config by absolute path with hooks in
# new_string. The tamper arm sits ABOVE the worktree-self early-exit, so it
# STILL gates: warn when watched, deny when bypass.
# The worktree checkout inherited the committed `.zskills-tracked` / `.landed`
# markers from sandbox-trunk; remove them so the WATCHED expectation holds (a
# worktree carrying a live tracked marker would correctly read enforce-pipeline,
# which is a different scenario than the watched-DA3 case under test here).
rm -f "$WORKTREE/.zskills-tracked" "$WORKTREE/.landed"
run_hook "$WORKTREE" "$(mkenv_edit_hooks "$CFG" default)" "$SANDBOX"
assert_warn "tc7: worktree-session Edit of MAIN config (watched) → WARN (above worktree-self, DA3)" \
  "$HOOK_EXIT" "$HOOK_OUT" "[hooks.main_protection.config_hooks_tamper"
run_hook "$WORKTREE" "$(mkenv_edit_hooks "$CFG" bypassPermissions)" "$SANDBOX"
assert_deny "tc7b: worktree-session Edit of MAIN config (bypass) → DENY (above worktree-self, DA3)" "$HOOK_OUT"

# ── tc8: group ceiling main_protection.enabled:false + tamper edit → STILL gated ─
# config_hooks_tamper is EXEMPT from its group's enabled ceiling.
printf '{"execution":{"main_protected":true},"hooks":{"main_protection":{"enabled":false}}}' > "$CFG"
run_hook "$SANDBOX" "$(mkenv_edit_hooks "$CFG" bypassPermissions)"
assert_deny "tc8: group ceiling enabled:false + tamper edit → STILL gated (ceiling exemption)" "$HOOK_OUT"
printf '{"execution":{"main_protected":true}}' > "$CFG"

# ── tc9: self-protection — config WITHOUT a config_hooks_tamper value, Edit
# setting config_hooks_tamper:"off", BYPASS → DENY (gate evaluates pre-write) ─
run_hook "$SANDBOX" "$(mkenv_edit_tamper_self "$CFG" bypassPermissions)"
assert_deny "tc9: self-protection — Edit setting config_hooks_tamper:off bypass → DENY (pre-write eval)" "$HOOK_OUT"

# ── tc10: warn AND deny text both carry the recovery line (Settled decision 13) ─
run_hook "$SANDBOX" "$(mkenv_edit_hooks "$CFG" bypassPermissions)"
if [[ "$HOOK_OUT" == *'human-reviewed'* ]]; then
  pass "tc10a: tamper DENY text contains the recovery line (human-reviewed)"
else
  fail "tc10a: tamper DENY text contains the recovery line (human-reviewed)" "out=$HOOK_OUT"
fi
run_hook "$SANDBOX" "$(mkenv_edit_hooks "$CFG" default)"
if [[ "$HOOK_OUT" == *'human-reviewed'* ]]; then
  pass "tc10b: tamper WARN text contains the recovery line (human-reviewed)"
else
  fail "tc10b: tamper WARN text contains the recovery line (human-reviewed)" "out=$HOOK_OUT"
fi
printf '{"execution":{"main_protected":true}}' > "$CFG"

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
