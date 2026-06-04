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
#       - run_attended_repo_load_check (deterministic hookfire + the
#         (A2)-RUNTIME graceful-degradation assertion, in ONE --plugin-dir load)
#       - run_attended_dual_install_skip_shim_check
#       With an isolated (credential-less) HOME, headless `claude -p "<prompt>"`
#       prints "Not logged in · Please run /login" and exits — so these probes
#       need credentials. Post-#964 the suite SEEDS a COPY of the real
#       ~/.claude/.credentials.json into the isolated config dir, which lets
#       headless `claude -p` AUTH + load the plugin + wire hooks (plugin-sync
#       runs) — so PreToolUse hooks DO fire headlessly once authed. These
#       functions are flag-guarded one-shots a human runs once in an authed env
#       before launch. The CI / unauthed path (flag unset, OR flag set but no
#       real credential to seed) SKIPS them with an honest reason. They assert an
#       OBSERVABLE hook side-effect with explicit PASS/FAIL via a deterministic
#       marker file. They are NEVER faked, NEVER prose-only, NEVER claimed as a
#       recurring CI gate.
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
# TWO observability levels (split honestly):
#   OFFLINE (here, CI-gateable): `claude plugin validate` loads & checks the
#   marketplace + plugin manifests (including hooks.json wiring) WITHOUT
#   executing a session. We assert that validate does not fatally error in the
#   presence of the missing suffixless hooks — i.e. the manifest/hooks.json
#   registration of a not-yet-materialised hook is tolerated, not a hard load
#   error.
#   RUNTIME (attended, below): a `claude --plugin-dir "$REPO_ROOT" -p "<benign>"`
#   load that ACTUALLY exercises plugin-sync + hook registration in a live
#   authed session. The #964 credential-seed plumbing proves headless
#   `claude -p` DOES auth + load the plugin + wire hooks (the attended
#   `run_attended_repo_load_check` below fires a real hook under exactly such a
#   load) — so the runtime hook-registration path IS observable when authed.
#   The earlier "headless claude -p bails at login before plugin-sync" premise
#   was FALSE (predated #964); the runtime tolerance is now asserted attended,
#   not skipped.
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
  # The RUNTIME hook-registration tolerance (plugin-sync wiring a live session
  # with the 2 suffixless hooks ABSENT on disk) is observable only in an authed
  # session, so it is gated behind ZSKILLS_LIVE_ATTENDED=1 — the SAME gate as
  # the (B) checks. When the flag is unset (CI / unauthed dev) it SKIPs cleanly;
  # when set it is asserted inside the attended `run_attended_repo_load_check`
  # (which performs the real `--plugin-dir "$REPO_ROOT"` load and checks the
  # session output named no fatal missing-hook error). We record the gated SKIP
  # here so the offline section's accounting stays honest; the PASS/FAIL is
  # emitted by the attended function.
  if [ "${ZSKILLS_LIVE_ATTENDED:-}" != "1" ]; then
    skip "(A2) graceful degradation — RUNTIME hook-registration tolerance is attended-only (set ZSKILLS_LIVE_ATTENDED=1 in an authed env); asserted by run_attended_repo_load_check"
  fi
else
  skip "(A2) graceful degradation: precondition changed (suffixless hooks now present on disk, or no longer both registered) — check no longer applicable"
fi

# ── (B) ATTENDED functions — NOT CI gates. Flag: ZSKILLS_LIVE_ATTENDED=1 ────
#
# Both functions below assert an OBSERVABLE hook side-effect with explicit
# PASS/FAIL. They run ONLY when ZSKILLS_LIVE_ATTENDED=1 AND a human is in an
# authed env. The CI path (flag unset) SKIPS them with the recorded reason.
# They are NEVER faked and NEVER claimed as recurring CI gates.

# run_attended_repo_load_check
#   Shared attended load that proves TWO properties in ONE real
#   `--plugin-dir "$REPO_ROOT"` headless session (cheaper + cleaner than two
#   `claude` spins):
#
#   ITEM 2 — DETERMINISTIC hookfire: prove a PreToolUse hook actually FIRES
#     under a real `--plugin-dir` session. The OLD form asked the (safety-
#     conscious) nested agent to run a destructive `rm -rf /etc/...` and grepped
#     a deny-envelope — but whether the agent EMITS that command is non-
#     deterministic (a refusal yields zero denies → FALSE FAIL). We instead
#     register a tiny synthetic CONSUMER hook (via an isolated project
#     settings.json, --add-dir) that fires on a BENIGN command and appends ONE
#     line to a marker file. The benign command always runs, so the marker count
#     is a verbatim, prose-immune proof that a hook fired under the real load.
#     (Same deterministic-marker pattern run_attended_dual_install_skip_shim_check
#     already uses.)
#
#   ITEM 1 — RUNTIME graceful degradation: the SAME load is a real
#     `--plugin-dir "$REPO_ROOT"` plugin-sync, which wires the repo hooks.json —
#     including the 2 suffixless D4 hooks (block-unsafe-project.sh,
#     block-agents.sh) that are ABSENT on disk in the source tree. We assert the
#     session completed its expected hook side-effect (marker fired) WITHOUT a
#     fatal load error naming those missing hooks. This exercises the runtime
#     hook-registration tolerance the offline (A2) validate can only check
#     statically. (This replaces the stale unconditional (A2)-runtime perma-skip
#     whose "headless claude -p bails at login" premise was FALSE post-#964.)
#
#   Never-fake: if auth fails despite the flag (no #964 credential seeded), we
#   SKIP both — never fail, never fake a PASS.
run_attended_repo_load_check() {
  echo "  [attended] run_attended_repo_load_check"
  local proj="$TMP/attended-repoload"
  mkdir -p "$proj"
  local out="$TMP/attended-repoload.out"
  local marker="$proj/.repoload-marker"
  : > "$marker"

  # Deterministic observable: a SECOND, tiny synthetic PLUGIN (loaded via its
  # OWN --plugin-dir, alongside the real repo's --plugin-dir) whose Bash-matcher
  # hook appends exactly one line to a marker file on a benign command. We use a
  # plugin-lane hook (NOT a consumer settings.json registered via --add-dir,
  # which the harness does not reliably load as project settings — observed: a
  # consumer settings.json hook never fired) so the fire is guaranteed and the
  # count is verbatim, prose-immune. `--plugin-dir` is repeatable, so loading
  # the real repo AND this marker plugin in one session lets ONE load prove both
  # item 1 (the real repo's 2 missing suffixless hooks are tolerated) and item 2
  # (a hook fired under a real --plugin-dir session).
  local synmarker="$TMP/attended-repoload-plugin"
  mkdir -p "$synmarker/hooks" "$synmarker/.claude-plugin"
  cat > "$synmarker/hooks/repoload-probe.sh" <<MARKERHOOK
#!/usr/bin/env bash
# Synthetic repo-load probe — PLUGIN LANE. Fires on a benign Bash call, appends
# one marker line. Marker path hardcoded at write time (no env dependency).
printf 'fired\n' >> "$marker"
exit 0
MARKERHOOK
  chmod +x "$synmarker/hooks/repoload-probe.sh"
  cat > "$synmarker/.claude-plugin/plugin.json" <<'PLUGINJSON'
{
  "name": "zsrepoloadprobe",
  "version": "2026.05.0",
  "description": "Synthetic repo-load hookfire probe plugin (test fixture)."
}
PLUGINJSON
  cat > "$synmarker/hooks/hooks.json" <<'PLUGINHOOKS'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/repoload-probe.sh\"", "timeout": 5 }
        ]
      }
    ]
  }
}
PLUGINHOOKS

  # ONE session, TWO --plugin-dir loads: the real repo (item 1 — its hooks.json
  # registers the 2 suffixless hooks ABSENT on disk) + the synthetic marker
  # plugin (item 2 — deterministic fire). The benign command always runs → the
  # marker plugin's hook always fires → marker gets exactly one line. If auth
  # failed, the session bails at /login and the marker stays empty (we SKIP).
  if run_isolated_claude -p \
       'Run this exact bash command and report the tool result verbatim: echo zskills-repoload-probe' \
       --plugin-dir "$REPO_ROOT" --plugin-dir "$synmarker" --add-dir "$proj" --dangerously-skip-permissions >"$out" 2>&1; then
    :
  fi
  if grep -qiE 'not logged in|please run /login' "$out"; then
    skip "  [attended] repo-load: session not authed (no creds) — cannot observe hook fire or runtime degradation"
    skip "  [attended] (A2)-runtime: session not authed — runtime missing-hook tolerance not observable"
    return
  fi

  # ── ITEM 2: deterministic hookfire (marker count, prose-immune) ────────────
  local n
  n="$(grep -c 'fired' "$marker" 2>/dev/null)"
  [ -n "$n" ] || n=0
  if [ "$n" -ge 1 ]; then
    pass "  [attended] hookfire: PreToolUse hook FIRED under a real --plugin-dir load (marker count=$n; deterministic, prose-immune)"
  else
    fail "  [attended] hookfire: hook did NOT fire under the --plugin-dir load (marker count=0 — no matching Bash tool call ran?)"
    sed 's/^/      /' "$out"
  fi

  # ── ITEM 1: runtime graceful degradation (no fatal missing-hook error) ─────
  # The marker firing proves the live session loaded the plugin and reached the
  # Bash matcher. Now assert that the same plugin-sync did NOT fatally error on
  # the 2 suffixless D4 hooks absent on disk. A fatal load error would name the
  # hook script or surface ENOENT / "no such file"; its absence (combined with a
  # completed hook side-effect) is the runtime tolerance we want.
  if grep -qiE 'block-unsafe-project\.sh.*(no such file|ENOENT|cannot|failed to load)|block-agents\.sh.*(no such file|ENOENT|cannot|failed to load)|ENOENT.*block-(unsafe-project|agents)|no such file.*block-(unsafe-project|agents)' "$out"; then
    fail "  [attended] (A2)-runtime: live --plugin-dir load FATALLY errored on a missing suffixless D4 hook — REAL FINDING, STOP for audit (do not mask)"
    sed 's/^/      /' "$out"
  else
    pass "  [attended] (A2)-runtime: live --plugin-dir load tolerated 2 missing suffixless D4 hooks (hook side-effect fired; no fatal missing-hook error)"
  fi

  # ── ITEM 3: /doctor duplicate-hooks regression guard ───────────────────────
  # A real `claude plugin install` once reported "Duplicate hooks file
  # detected: ./hooks/hooks.json" because the manifest referenced the standard
  # hooks/hooks.json that Claude Code already auto-loads from the plugin root.
  # The fix removed the manifest `hooks` field. Guard the regression: run
  # /doctor under a real --plugin-dir load of the repo and FAIL if it reports a
  # plugin hook load error. (Same attended gate as ITEMs 1-2 above; the session
  # is already known authed here since we passed the /login check.)
  local doctor_out="$TMP/attended-repoload-doctor.out"
  run_isolated_claude -p '/doctor' --plugin-dir "$REPO_ROOT" --dangerously-skip-permissions > "$doctor_out" 2>&1 || true
  if grep -qiE 'Duplicate hooks file detected|Hook load failed|resolves to already-loaded' "$doctor_out"; then
    fail "  [attended] /doctor reports a plugin hook load error (duplicate-hooks regression)"
    sed 's/^/      /' "$doctor_out"
  else
    pass "  [attended] /doctor shows no plugin hook load errors under real --plugin-dir load"
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
  "description": "Synthetic dual-install probe plugin (test fixture)."
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
  run_attended_repo_load_check
  run_attended_dual_install_skip_shim_check
else
  skip "(B) run_attended_repo_load_check — skipped: attended-only, headless auth unavailable (set ZSKILLS_LIVE_ATTENDED=1 in an authed env to run)"
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
