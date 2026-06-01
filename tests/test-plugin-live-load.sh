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

# ── SKIP preamble: never FAIL on CLI-absent (this is what CI hits) ─────────
if ! command -v claude >/dev/null 2>&1; then
  echo "SKIP: claude CLI unavailable"
  echo ""
  echo "Results: 0 passed, 0 failed"
  exit 0
fi
if ! claude plugin --help >/dev/null 2>&1; then
  echo "SKIP: claude CLI unavailable ('claude plugin --help' failed)"
  echo ""
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

# ── MANDATORY ISOLATION (before ANY `claude` invocation) ──────────────────
# Build the hermetic sandbox FIRST. We export a throwaway HOME, XDG_CONFIG_HOME
# AND CLAUDE_CONFIG_DIR (the var the CLI honors for its config/credentials/
# installed-plugins state — verified empirically: with it pointed at $TMP, the
# CLI's writes (.claude.json, backups/) land under $TMP and the real ~/.claude
# tree is byte-identical before/after). We also pin TMPDIR=/tmp so the CLI's
# own mktemp usage stays predictable. Every `claude` invocation in this suite
# goes through run_isolated_claude so isolation can never be forgotten.
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

# ── Isolation proof, hardened (#956) ──────────────────────────────────────
# The earlier whole-tree md5 snapshot of real ~/.claude false-BREACHed whenever
# ANY concurrent process wrote under ~/.claude — e.g. a live Claude Code session
# running while this suite runs (observed 2026-06-01). The env vars below already
# redirect every write the isolated CLI makes; the ACTUAL safety property this
# suite must prove is narrower and concurrency-robust: the ONE real file we now
# (optionally) read to seed auth — ~/.claude/.credentials.json — is byte-
# identical before and after. We copy that file into the isolated config dir so
# headless `claude -p` can authenticate (mandatory for the (B) hook-fire probes
# — an empty config dir bails at /login); seeding a COPY does not rewrite the
# user's real credential (verified: real mtime unchanged across the probe).
#
# If the real credentials file is absent (CI / unauthed dev), nothing is seeded,
# the (B) checks still hit their "not logged in" SKIP guard, and the iso
# assertion below skips cleanly (there was nothing to protect).
REAL_CLAUDE="${HOME:-/nonexistent}/.claude"
REAL_CREDS="$REAL_CLAUDE/.credentials.json"
cred_content_md5() {
  # Content hash of just the real credentials file. Concurrency-robust: other
  # writers under ~/.claude do not touch this single file. Empty output when
  # the file is absent (CI) — callers treat that as "nothing to protect".
  [ -f "$REAL_CREDS" ] || return 0
  md5sum "$REAL_CREDS" 2>/dev/null | awk '{print $1}'
}
CRED_MD5_BEFORE="$(cred_content_md5)"

# Seed ONLY the credential into the isolated config dir, GUARDED on existence.
# When absent (CI), this is a no-op and every (B) check SKIPs at its login
# guard — unauthed behavior is unchanged. Seeding is harmless for the (A1)/(A2)
# validate calls (validate needs no auth).
if [ -f "$REAL_CREDS" ]; then
  if cp "$REAL_CREDS" "$ISO_CFG/.credentials.json" 2>/dev/null; then
    chmod 600 "$ISO_CFG/.credentials.json" 2>/dev/null || true
  fi
fi

# Run `claude` with the isolated environment. We use `env -i` to start from a
# clean slate (so a stray CLAUDE_* in the dev shell can't leak real state),
# then re-export only PATH + the isolation vars. Args are passed through. The
# seeded $ISO_CFG/.credentials.json (when present) lets headless `claude -p`
# authenticate without touching the real ~/.claude tree.
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
  # format. We assert on a deny/blocked signal in the output. A SINGLE hook
  # fire can score a deny-count >1 here because the model REPEATS the block
  # message in its natural-language explanation (observed: count 3 for one
  # fire). That prose-verbosity does NOT matter for THIS check — we only need
  # "the hook fired at all" (≥1 deny signal), which is prose-robust. (The
  # exactly-once assertion that IS sensitive to prose verbosity lives in the
  # dual-install function below, where it uses a deterministic marker count
  # instead of prose-grep.) If the prompt does not run (auth failed despite
  # the flag), we SKIP — never fake a PASS.
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
    pass "  [attended] hookfire: PreToolUse hook FIRED — deny-envelope observed on known-blocked command (≥1; prose-robust)"
  else
    fail "  [attended] hookfire: NO deny-envelope observed on a known-blocked command (hook did not fire?)"
    sed 's/^/      /' "$out"
  fi
}

# run_attended_dual_install_skip_shim_check
#   Intent: assert that under a REAL dual install — the SAME hook basename
#   registered on BOTH lanes (plugin via --plugin-dir AND a mirrored
#   .claude/hooks/ copy registered in an isolated consumer settings.json) — the
#   D16(a) conditional-skip shim makes the hook take effect EXACTLY ONCE per
#   matching tool call: the consumer-lane copy fires; the plugin-lane copy
#   defers via the shim. ("Exactly once" is the PER-COMMAND effect count, NOT a
#   deferral count — in a dual install the plugin copy defers on EVERY matching
#   call, indefinitely. Dual-install is an unsupported dogfood/transient state;
#   the shim keeps it corruption-free by ensuring one net effect, not zero and
#   not two.) (Attended: needs an authed session for the hooks to actually run.)
#
#   DETERMINISTIC OBSERVABLE (#956): we do NOT grep the model's prose for deny
#   envelopes — a single real hook fire can score a prose deny-count of 3
#   because the model repeats the block message in its explanation. Instead we
#   register on BOTH lanes a tiny synthetic hook fixture (written at runtime
#   into the probe's tmpdir) that SOURCES THE REAL SHIM
#   (hooks/_lib/plugin-hook-skip-if-mirrored.sh) and, when it does NOT defer,
#   appends exactly one line to a marker file. We then count marker-file lines.
#   The plugin copy sources the shim and, finding its same-basename sibling in
#   the consumer settings.json, defers (appends nothing); the consumer copy
#   does not source the shim and fires (appends one line). Expected count: 1.
#   This exercises the REAL shim's defer logic (the actual thing under test)
#   with a verbatim, prose-immune count.
run_attended_dual_install_skip_shim_check() {
  echo "  [attended] run_attended_dual_install_skip_shim_check"
  local proj="$TMP/attended-dual"
  # The synthetic plugin lives in its OWN dir so we never mutate the real repo's
  # hooks.json. It must carry hooks/_lib/plugin-hook-skip-if-mirrored.sh because
  # the plugin-copy fixture sources the REAL shim via ${CLAUDE_PLUGIN_ROOT}.
  local synplug="$TMP/attended-dual-plugin"
  mkdir -p "$proj/.claude/hooks" "$synplug/hooks/_lib" "$synplug/.claude-plugin"
  local marker="$proj/.dualfire-marker"
  : > "$marker"

  # Stage the real shim into the synthetic plugin so the plugin copy can source
  # it the way a shipped plugin hook does (via ${CLAUDE_PLUGIN_ROOT}).
  cp "$REPO_ROOT/hooks/_lib/plugin-hook-skip-if-mirrored.sh" \
     "$synplug/hooks/_lib/plugin-hook-skip-if-mirrored.sh" 2>/dev/null || {
    skip "  [attended] dual-install: could not stage real shim into synthetic plugin"
    return
  }

  # ── Plugin-lane copy of the fixture ──────────────────────────────────────
  # Sources the REAL shim as its first executable line (exactly like a shipped
  # plugin hook). The shim, finding the same basename (dualfire-probe.sh) in the
  # consumer settings.json, calls `exit 0` to DEFER — so this copy appends
  # nothing. The version-stamp line (#2) is required so the shim's skew compare
  # has a plugin stamp to read; we stamp BOTH copies identically (equal → the
  # shim's silent-defer branch fires, which is the dual-install behavior we
  # assert). Marker path is hardcoded at write time (no env dependency at fire).
  cat > "$synplug/hooks/dualfire-probe.sh" <<PLUGINHOOK
#!/usr/bin/env bash
# zskills-hook-version: 2026.05.0
# Synthetic dual-install probe — PLUGIN LANE copy. Sources the REAL D16(a) shim.
[ -n "\${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "\${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "\${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"
# If the shim did NOT defer (no same-basename consumer sibling), we fire.
printf 'fired\n' >> "$marker"
exit 0
PLUGINHOOK
  chmod +x "$synplug/hooks/dualfire-probe.sh"

  # Synthetic plugin manifest + hooks.json registering the plugin-lane fixture.
  cat > "$synplug/.claude-plugin/plugin.json" <<'PLUGINJSON'
{
  "name": "zsdualprobe",
  "version": "2026.05.0",
  "description": "Synthetic dual-install probe plugin (test fixture).",
  "hooks": "./hooks/hooks.json"
}
PLUGINJSON
  cat > "$synplug/hooks/hooks.json" <<'PLUGINHOOKS'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/dualfire-probe.sh\"", "timeout": 5 }
        ]
      }
    ]
  }
}
PLUGINHOOKS

  # ── Consumer-lane copy of the fixture ────────────────────────────────────
  # Does NOT source the shim (consumer hooks never do — only plugin-registered
  # hooks source it). So it always FIRES and appends one line. Registered in the
  # consumer project's settings.json under the SAME basename — that registration
  # is exactly what the plugin copy's shim detects to decide to defer.
  cat > "$proj/.claude/hooks/dualfire-probe.sh" <<CONSUMERHOOK
#!/usr/bin/env bash
# zskills-hook-version: 2026.05.0
# Synthetic dual-install probe — CONSUMER LANE copy. No shim source; always fires.
printf 'fired\n' >> "$marker"
exit 0
CONSUMERHOOK
  chmod +x "$proj/.claude/hooks/dualfire-probe.sh"

  cat > "$proj/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/dualfire-probe.sh\"", "timeout": 5 }
        ]
      }
    ]
  }
}
JSON

  local out="$TMP/attended-dual.out"
  # A single benign Bash tool call triggers the PreToolUse matcher on both
  # lanes. We use a harmless command (the fixtures only append a marker; they
  # never block), so the model just runs it. We do not depend on the prose.
  if run_isolated_claude -p \
       'Run this exact bash command and report the tool result verbatim: echo zskills-dualinstall-probe' \
       --plugin-dir "$synplug" --add-dir "$proj" --dangerously-skip-permissions >"$out" 2>&1; then
    :
  fi
  if grep -qiE 'not logged in|please run /login' "$out"; then
    skip "  [attended] dual-install: session not authed (no creds) — cannot observe shim defer"
    return
  fi
  # DETERMINISTIC count: marker-file lines, immune to model prose verbosity.
  # Exactly one = shim deferred the plugin copy (consumer copy fired alone).
  # Two = double-fire (shim failed to defer). Zero = neither fired (no matching
  # tool call ran, or both deferred — unexpected).
  local n
  n="$(grep -c 'fired' "$marker" 2>/dev/null || echo 0)"
  if [ "$n" -eq 1 ]; then
    pass "  [attended] dual-install: hook took effect EXACTLY ONCE — plugin copy deferred via real shim (marker count=1; prose-immune)"
  elif [ "$n" -ge 2 ]; then
    fail "  [attended] dual-install: hook DOUBLE-FIRED (marker count=$n) — shim did not defer the plugin copy"
    sed 's/^/      /' "$out"
  else
    fail "  [attended] dual-install: hook did not take effect at all (marker count=0) — no matching tool call ran, or both copies deferred (unexpected)"
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

# ── Isolation proof: real credential must be byte-identical (#956) ────────
# We assert the specific, concurrency-robust safety property: seeding a COPY of
# ~/.claude/.credentials.json into the isolated config dir did NOT rewrite or
# rotate the user's real credential. (The prior whole-tree snapshot false-
# BREACHed on any concurrent ~/.claude writer; the narrow content-hash of the
# single credential file is immune to that.) When the real credential is absent
# (CI), nothing was seeded and there is nothing to protect — skip cleanly.
if [ -z "$CRED_MD5_BEFORE" ]; then
  skip "(iso) no real ~/.claude/.credentials.json present — nothing seeded, isolation assertion not applicable"
else
  CRED_MD5_AFTER="$(cred_content_md5)"
  if [ "$CRED_MD5_BEFORE" = "$CRED_MD5_AFTER" ]; then
    pass "(iso) real ~/.claude/.credentials.json byte-identical across the run (seeded a copy; did not rewrite/rotate the user's credential)"
  else
    fail "(iso) real ~/.claude/.credentials.json CHANGED — the run rewrote/rotated the user's credential (isolation breach)"
  fi
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
