#!/usr/bin/env bash
# tests/test-plugin-live-load.sh
#
# PLUGIN_LANE_VERIFICATION Phase 2 — Live dual-lane behavioral validation.
#
# This suite invokes the REAL `claude` CLI under a HERMETIC environment.
# `claude` is present in the dev devcontainer but ABSENT on CI runners; the
# SKIP preamble handles CLI-absent by exiting 0 (mirrors
# test-plugin-self-load.sh).
#
# The phase is split HONESTLY (do not conflate):
#
#   (A) CI-GATEABLE delta over the parse-only test-plugin-self-load.sh:
#       - `claude plugin validate .` exits 0 AND prints "Validation passed"
#         under a fully isolated HOME/XDG/CLAUDE_CONFIG_DIR (proving the real
#         ~/.claude is never read or mutated).
#       - GRACEFUL DEGRADATION (rough edge c, CONFIRM-not-fix): from the
#         source tree the two D4 suffixless hooks block-unsafe-project.sh /
#         block-agents.sh do NOT exist (only `.template`). We confirm the
#         live load does not FATALLY error on those missing registered hooks.
#         IMPORTANT empirical finding (see the function): this is only
#         partially observable non-interactively — see notes inline.
#
#   (B) ATTENDED, NOT CI gates (guarded behind ZSKILLS_LIVE_ATTENDED=1):
#       - run_attended_hookfire_check
#       - run_attended_dual_install_skip_shim_check
#       Review VERIFIED that headless `claude -p "<prompt>"` with an isolated
#       (credential-less) HOME prints "Not logged in · Please run /login" and
#       exits WITHOUT running the prompt — so PreToolUse hooks NEVER fire
#       headlessly in an unauthenticated sandbox. These two functions are
#       therefore flag-guarded one-shots a human runs once in an authed env
#       before launch. The CI path (flag unset) SKIPS them and records
#       "skipped: attended-only, headless auth unavailable". They assert an
#       OBSERVABLE hook side-effect with explicit PASS/FAIL. They are NEVER
#       faked, NEVER prose-only, NEVER claimed as a recurring CI gate.
#
# No jq — Python json per `## Python is required` (not needed here; documented
# for consistency with sibling plugin suites).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT+1)); }

echo "=== plugin live load (zs + zsbd) — Phase 2 ==="

# ── MANDATORY ISOLATION (before ANY `claude` invocation) ──────────────────
# Build the hermetic sandbox FIRST. We export a throwaway HOME, XDG_CONFIG_HOME
# AND CLAUDE_CONFIG_DIR (the var the CLI honors for its config/credentials/
# installed-plugins state — verified empirically: with it pointed at $TMP, the
# CLI's writes (.claude.json, backups/) land under $TMP and the real ~/.claude
# tree is byte-identical before/after). We also pin TMPDIR=/tmp so the CLI's
# own mktemp usage stays predictable. Every `claude` invocation in this suite
# goes through run_isolated_claude so isolation can never be forgotten.
#
# We create $TMP + trap + sensitivity self-check BEFORE the CLI-absent SKIP
# preamble so the synthetic-tree sensitivity case runs on EVERY invocation
# (including CI runners without `claude`). The CLI-absent SKIP comes after.
#
# If TMP cannot be created, the WHOLE live phase SKIPs rather than risk
# touching real state.
if ! TMP="$(mktemp -d 2>/dev/null)"; then
  echo "SKIP: could not create isolated tmpdir — refusing to risk real ~/.claude"
  echo ""
  echo "Results: 0 passed, 0 failed"
  exit 0
fi
trap 'rm -rf "$TMP"' EXIT

ISO_HOME="$TMP/home"
ISO_XDG="$TMP/home/.config"
ISO_CFG="$TMP/home/.claude"
mkdir -p "$ISO_HOME" "$ISO_XDG" "$ISO_CFG" "$TMP/proj"

# Snapshot the REAL ~/.claude tree so we can prove isolation held. We compare a
# listing-hash before and after the whole run. (Defense in depth: the env vars
# already redirect all writes; this is the belt to that suspenders.)
REAL_CLAUDE="${HOME:-/nonexistent}/.claude"
# Paths a plugin-install operation would naturally write to. Anything outside
# this set is live-session state (transcripts, jobs, sessions, backups) that
# the running Claude session writes continuously — fingerprinting it makes the
# isolation check perpetually fail (issue #954). See:
#   https://github.com/zeveck/zskills-dev/issues/954
PLUGIN_WRITE_PATHS=( "settings.json" "plugins" "hooks" "agents" "skills" )

# Parametric helper: snapshot a given root restricted to an allow-list of
# child paths. Used by real_claude_snapshot AND the sensitivity case below.
snapshot_tree_scoped() {
  local root="$1"; shift
  local p
  for p in "$@"; do
    if [ -e "$root/$p" ]; then
      find "$root/$p" -maxdepth 3 -printf '%p %s %T@\n' 2>/dev/null
    fi
  done | LC_ALL=C sort | md5sum | awk '{print $1}'
}

real_claude_snapshot() {
  snapshot_tree_scoped "$REAL_CLAUDE" "${PLUGIN_WRITE_PATHS[@]}"
}

# ── (iso-sensitivity) prove snapshot_tree_scoped catches writes in allow-list ─
# This is a self-check against a SYNTHETIC tree we control — we never write
# into real ~/.claude/. If snapshot_tree_scoped is broken (e.g., the find
# command silently fails, the allow-list is misspelled, or md5sum collapses
# distinct trees), this case fails and the (iso) check below is unreliable.
SYNTH="$TMP/synth"
mkdir -p "$SYNTH/plugins" "$SYNTH/hooks" "$SYNTH/agents" "$SYNTH/skills"
echo '{}' > "$SYNTH/settings.json"
SYNTH_SNAP_1="$(snapshot_tree_scoped "$SYNTH" "${PLUGIN_WRITE_PATHS[@]}")"
# Inject a probe file inside one of the allow-list subdirectories.
echo "probe" > "$SYNTH/plugins/zzz-zskills-isolation-probe-$$"
SYNTH_SNAP_2="$(snapshot_tree_scoped "$SYNTH" "${PLUGIN_WRITE_PATHS[@]}")"
if [ "$SYNTH_SNAP_1" != "$SYNTH_SNAP_2" ]; then
  pass "(iso-sensitivity) snapshot_tree_scoped detects an in-scope write (synthetic tree, no real ~/.claude touched)"
else
  fail "(iso-sensitivity) snapshot_tree_scoped did NOT detect an in-scope write — isolation check is hollow"
fi
# Inject another file OUTSIDE the allow-list (e.g., a sibling 'projects' dir,
# which mimics live-session transcript writes). The snapshot MUST NOT change
# — proving the allow-list correctly excludes live-session noise.
mkdir -p "$SYNTH/projects"
echo "transcript" > "$SYNTH/projects/zzz-out-of-scope-$$.jsonl"
SYNTH_SNAP_3="$(snapshot_tree_scoped "$SYNTH" "${PLUGIN_WRITE_PATHS[@]}")"
if [ "$SYNTH_SNAP_3" = "$SYNTH_SNAP_2" ]; then
  pass "(iso-sensitivity) snapshot_tree_scoped correctly IGNORES out-of-scope writes (live-session noise excluded)"
else
  fail "(iso-sensitivity) snapshot_tree_scoped INCORRECTLY caught an out-of-scope write — allow-list is broken"
fi
# Cleanup not strictly needed — the existing `trap 'rm -rf "$TMP"' EXIT` at
# the top of this file removes $TMP/synth automatically. But explicit removes
# keep the synth dir hygienic for subsequent assertions in this file:
rm -rf "$SYNTH"

# ── SKIP preamble: never FAIL on CLI-absent (this is what CI hits) ─────────
# Comes AFTER the sensitivity self-check so that check runs even on CI runners
# without `claude`.
if ! command -v claude >/dev/null 2>&1; then
  echo "SKIP: claude CLI unavailable"
  echo ""
  printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
  exit "$FAIL_COUNT"
fi
if ! claude plugin --help >/dev/null 2>&1; then
  echo "SKIP: claude CLI unavailable ('claude plugin --help' failed)"
  echo ""
  printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
  exit "$FAIL_COUNT"
fi

SNAP_BEFORE="$(real_claude_snapshot)"

# Run `claude` with the isolated environment. We use `env -i` to start from a
# clean slate (so a stray CLAUDE_* in the dev shell can't leak real state),
# then re-export only PATH + the isolation vars. Args are passed through.
run_isolated_claude() {
  env -i \
    PATH="$PATH" \
    HOME="$ISO_HOME" \
    XDG_CONFIG_HOME="$ISO_XDG" \
    CLAUDE_CONFIG_DIR="$ISO_CFG" \
    TMPDIR=/tmp \
    claude "$@"
}

# ── (A1) CI-gateable load assertion: validate exits 0 + "Validation passed" ─
# Point at the REAL repo via the positional path (read-only — verified: the
# isolated CLAUDE_CONFIG_DIR captures all writes, the --plugin-dir/path target
# repo is not mutated). We do NOT grep for the literal zs/zsbd tokens: F4
# verified `validate` prints only "✔ Validation passed" and does not name the
# plugins. `plugin details <name>` would name them but requires the plugin to
# be INSTALLED (mutating real state) — dropped per F4; exit-0 + banner stands.
VAL_OUT="$TMP/validate.out"
if run_isolated_claude plugin validate "$REPO_ROOT" >"$VAL_OUT" 2>&1; then
  VAL_RC=0
else
  VAL_RC=$?
fi
if [ "$VAL_RC" -eq 0 ] && grep -q 'Validation passed' "$VAL_OUT"; then
  pass "(A1) claude plugin validate .: exit 0 + 'Validation passed' (marketplace manifest)"
else
  fail "(A1) claude plugin validate . (exit=$VAL_RC, expected 0 + 'Validation passed')"
  sed 's/^/      /' "$VAL_OUT"
fi

# Same for the zsbd plugin manifest directly (covers the addon lane).
VAL_BD_OUT="$TMP/validate-bd.out"
if run_isolated_claude plugin validate "$REPO_ROOT/block-diagram" >"$VAL_BD_OUT" 2>&1; then
  VAL_BD_RC=0
else
  VAL_BD_RC=$?
fi
if [ "$VAL_BD_RC" -eq 0 ] && grep -q 'Validation passed' "$VAL_BD_OUT"; then
  pass "(A1) claude plugin validate block-diagram: exit 0 + 'Validation passed' (zsbd manifest)"
else
  fail "(A1) claude plugin validate block-diagram (exit=$VAL_BD_RC, expected 0 + 'Validation passed')"
  sed 's/^/      /' "$VAL_BD_OUT"
fi

# ── (A2) Graceful degradation (rough edge c — CONFIRM, do not fix) ─────────
# The source tree registers two suffixless D4 hooks in hooks/hooks.json
# (block-unsafe-project.sh, block-agents.sh) but ships only their `.template`
# siblings — the suffixless files are materialised consumer-side, so they are
# absent here. Acceptance: a live plugin load from the source tree must NOT
# FATALLY error on those two missing registered hooks.
#
# OBSERVABILITY FINDING (recorded — this is a real limitation, not padding):
#   The fullest signal would be a `claude --plugin-dir . -p "<prompt>"` load
#   that exercises plugin-sync + hook registration. But review VERIFIED (and
#   this suite re-confirms in the attended section) that headless `claude -p`
#   bails at "Not logged in" BEFORE plugin-sync/hook wiring runs — so the
#   runtime hook-registration path is NOT observable non-interactively.
#   What IS observable non-interactively and offline is `claude plugin
#   validate`, which loads & checks the marketplace + plugin manifests
#   (including hooks.json wiring) WITHOUT executing a session. We assert that
#   validate does not fatally error in the presence of the missing suffixless
#   hooks — i.e. the manifest/hooks.json registration of a not-yet-
#   materialised hook is tolerated, not a hard load error.
#
# First, sanity-check the premise (so a future source change that adds the
# suffixless files turns this into a clear SKIP rather than a silent false
# pass).
MISSING_HOOKS=()
for h in block-unsafe-project.sh block-agents.sh; do
  [ -e "$REPO_ROOT/hooks/$h" ] || MISSING_HOOKS+=("$h")
done
REGISTERED_BOTH=1
for h in block-unsafe-project.sh block-agents.sh; do
  grep -q "$h" "$REPO_ROOT/hooks/hooks.json" || REGISTERED_BOTH=0
done

if [ "${#MISSING_HOOKS[@]}" -eq 2 ] && [ "$REGISTERED_BOTH" -eq 1 ]; then
  # The precondition holds: both hooks registered in hooks.json, both absent on
  # disk. Re-use the validate run above as the offline load. If validate
  # exited 0 + "Validation passed", the load tolerated the missing suffixless
  # hooks (no fatal error). If validate had FATALLY errored citing the missing
  # hook scripts, (A1) would already have failed AND VAL_OUT would name them —
  # we surface that as the real finding here.
  if [ "$VAL_RC" -eq 0 ] && grep -q 'Validation passed' "$VAL_OUT"; then
    pass "(A2) graceful degradation: offline plugin load tolerates 2 missing suffixless D4 hooks (no fatal error)"
  elif grep -qiE 'block-unsafe-project\.sh|block-agents\.sh|ENOENT|no such file' "$VAL_OUT"; then
    fail "(A2) graceful degradation: live load FATALLY errored on a missing suffixless D4 hook — REAL FINDING, STOP for audit (do not fix here)"
    sed 's/^/      /' "$VAL_OUT"
  else
    # validate failed for an unrelated reason; (A1) already flagged it.
    skip "(A2) graceful degradation: validate failed for an unrelated reason (see A1) — missing-hook tolerance not observable this run"
  fi
  # Honest scope note: the RUNTIME hook-registration path (plugin-sync wiring
  # the suffixless hooks into a live session) is only observable in an authed
  # session; that confirmation lives in the attended dual-install function.
  skip "(A2) graceful degradation — RUNTIME hook-registration tolerance is attended-only (headless 'claude -p' bails at login before plugin-sync); confirmed offline-only here"
else
  skip "(A2) graceful degradation: precondition changed (suffixless hooks now present on disk, or no longer both registered) — check no longer applicable"
fi

# ── (B) ATTENDED functions — NOT CI gates. Flag: ZSKILLS_LIVE_ATTENDED=1 ────
#
# Both functions below assert an OBSERVABLE hook side-effect with explicit
# PASS/FAIL. They run ONLY when ZSKILLS_LIVE_ATTENDED=1 AND a human is in an
# authed env. The CI path (flag unset) SKIPS them with the recorded reason.
# They are NEVER faked and NEVER claimed as recurring CI gates.

# run_attended_hookfire_check
#   Intent: prove a PreToolUse hook actually FIRES under a real `--plugin-dir`
#   session by observing a deny-envelope on a known-blocked command. The
#   block-unsafe-generic.sh hook denies a recursive rm on a non-/tmp path; we
#   ask the authed session to attempt one and assert the hook's deny side-
#   effect is observable. (A human runs this once pre-launch; it requires
#   credentials the isolated sandbox does not have.)
run_attended_hookfire_check() {
  echo "  [attended] run_attended_hookfire_check"
  local proj="$TMP/attended-hookfire"
  mkdir -p "$proj"
  local out="$TMP/attended-hookfire.out"
  # A known-blocked command: recursive rm on a non-/tmp path. The generic
  # hook (sourced by plugin-registered hooks) must DENY it. We observe the
  # deny via the session's tool-error surface in --print mode.
  #
  # NOTE: the exact observable depends on the authed session's transcript
  # format. We assert on a deny/blocked signal in the output. If the prompt
  # does not run (auth failed despite the flag), we SKIP — never fake a PASS.
  if run_isolated_claude -p \
       'Run this exact bash command and report the tool result verbatim: rm -rf /etc/zzz-zskills-hookfire-probe' \
       --plugin-dir "$REPO_ROOT" --dangerously-skip-permissions >"$out" 2>&1; then
    :
  fi
  if grep -qiE 'not logged in|please run /login' "$out"; then
    skip "  [attended] hookfire: session not authed (no creds) — cannot observe hook fire"
    return
  fi
  if grep -qiE 'BLOCKED|deny|recursive rm requires|block-unsafe' "$out"; then
    pass "  [attended] hookfire: PreToolUse hook FIRED — deny-envelope observed on known-blocked command"
  else
    fail "  [attended] hookfire: NO deny-envelope observed on a known-blocked command (hook did not fire?)"
    sed 's/^/      /' "$out"
  fi
}

# run_attended_dual_install_skip_shim_check
#   Intent: assert the D16(a) conditional-skip shim defers EXACTLY ONCE under a
#   REAL dual install — plugin loaded via --plugin-dir AND a mirrored
#   .claude/hooks/ copy registered in an isolated consumer settings.json. Under
#   a real authed session, a known-blocked command must be denied EXACTLY ONCE
#   (the consumer-lane copy fires; the plugin copy defers via the shim), not
#   twice. (Attended: needs an authed session for the hooks to actually run.)
run_attended_dual_install_skip_shim_check() {
  echo "  [attended] run_attended_dual_install_skip_shim_check"
  local proj="$TMP/attended-dual"
  mkdir -p "$proj/.claude/hooks"
  # Mirror the generic hook consumer-side and register it in settings.json so
  # the same basename exists on BOTH lanes (plugin via --plugin-dir, consumer
  # via settings.json) — the dual-install condition the shim guards.
  cp "$REPO_ROOT/hooks/block-unsafe-generic.sh" "$proj/.claude/hooks/block-unsafe-generic.sh" 2>/dev/null || {
    skip "  [attended] dual-install: could not stage consumer-side hook copy"
    return
  }
  cat > "$proj/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-generic.sh\"", "timeout": 5 }
        ]
      }
    ]
  }
}
JSON
  local out="$TMP/attended-dual.out"
  if run_isolated_claude -p \
       'Run this exact bash command and report the tool result verbatim: rm -rf /etc/zzz-zskills-dualinstall-probe' \
       --plugin-dir "$REPO_ROOT" --add-dir "$proj" --dangerously-skip-permissions >"$out" 2>&1; then
    :
  fi
  if grep -qiE 'not logged in|please run /login' "$out"; then
    skip "  [attended] dual-install: session not authed (no creds) — cannot observe shim defer"
    return
  fi
  # Count deny-envelope occurrences. Exactly one = shim deferred the plugin
  # copy correctly. Two = double-fire (shim failed). Zero = neither fired.
  local n
  n="$(grep -ciE 'recursive rm requires|BLOCKED' "$out")"
  if [ "$n" -eq 1 ]; then
    pass "  [attended] dual-install: hook fired EXACTLY ONCE — plugin copy deferred via shim (no double-fire)"
  elif [ "$n" -ge 2 ]; then
    fail "  [attended] dual-install: hook DOUBLE-FIRED ($n denies) — shim did not defer the plugin copy"
    sed 's/^/      /' "$out"
  else
    fail "  [attended] dual-install: hook did not fire at all (0 denies) — unexpected"
    sed 's/^/      /' "$out"
  fi
}

if [ "${ZSKILLS_LIVE_ATTENDED:-}" = "1" ]; then
  run_attended_hookfire_check
  run_attended_dual_install_skip_shim_check
else
  skip "(B) run_attended_hookfire_check — skipped: attended-only, headless auth unavailable (set ZSKILLS_LIVE_ATTENDED=1 in an authed env to run)"
  skip "(B) run_attended_dual_install_skip_shim_check — skipped: attended-only, headless auth unavailable (set ZSKILLS_LIVE_ATTENDED=1 in an authed env to run)"
fi

# ── Isolation proof: real ~/.claude tree must be byte-identical ───────────
SNAP_AFTER="$(real_claude_snapshot)"
if [ "$SNAP_BEFORE" = "$SNAP_AFTER" ]; then
  pass "(iso) real ~/.claude tree unchanged across the run (writes went to isolated CLAUDE_CONFIG_DIR)"
else
  fail "(iso) real ~/.claude tree CHANGED — isolation breach (env vars did not redirect writes)"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
