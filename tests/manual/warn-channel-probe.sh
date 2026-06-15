#!/bin/bash
# tests/manual/warn-channel-probe.sh — GATING (decide-then-pin) warn-channel
# visibility probe for ENFORCEMENT_V2_PLAN Phase 1 (Settled decision 2).
#
# WHAT THIS DECIDES: the enforcement lib's opt-in `"warn"` value emits warnings
# via zskills_enforcement_flush_warnings. Two emission forms were pre-specced:
#   W-A: exit 0 + bare {"systemMessage":"…"} stdout JSON (decision-less)
#   W-B: token to stderr + exit 0 (the warn-config-drift.sh shape)
# Whether a DECISION-LESS systemMessage surfaces to a user on PreToolUse is
# UNDOCUMENTED — this probe decides it empirically and PINS one form.
#
# IMPORTANT — this is a MANUAL probe, NOT a test suite. It is deliberately NOT
# registered in tests/run-all.sh (exempt from triplet-registration Invariant 7
# by design). It is a drift canary: RE-RUN IT after any claude-cli upgrade,
# because the envelope semantics it pins are harness behavior, not a documented
# contract. The headless stream is a PROXY for interactive rendering — the
# Phase 7 attended check is the live-session confirmation.
#
# Pinned result (see the lib header for the dated assumption note):
#   Form W-A is shipped, pinned against claude-cli 2.1.177 on 2026-06-15.
#
# Usage:  bash tests/manual/warn-channel-probe.sh
# Requires: the `claude` CLI on PATH (headless `claude -p`). Every probe run
# uses DEFAULT permission-mode — never bypassPermissions (which would falsify
# the watched-leg evidence AND flip the predicate input later phases stage).

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_OUT="${TEST_OUT:-/tmp/zskills-tests/$(basename "$REPO_ROOT")}"
mkdir -p "$TEST_OUT"

if ! command -v claude >/dev/null 2>&1; then
  echo "FAIL: claude CLI not on PATH — cannot run the GATING warn-channel probe."
  echo "      Surface to the orchestrator (Failure-Protocol STOP per Settled decision 2)."
  exit 2
fi
echo "claude version: $(claude --version 2>&1 | head -1)"

PY="$(command -v python3 || command -v python)"

WORK="$(mktemp -d /tmp/zskills-warn-probe-XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

TOKEN="ZSKILLS_WARN_PROBE_TOKEN"
TOKEN2="ZSKILLS_WARN_PROBE_TOKEN2"

# ── Scratch consumer with a one-off PreToolUse/Bash probe hook ──────────────
mkdir -p "$WORK/.claude/hooks"

# Form W-A probe hook: decision-less systemMessage + exit 0. Writes a sentinel
# so we can DECOUPLE "did the hook fire" from "did its output surface" — a
# headless non-surface with a fired sentinel is INCONCLUSIVE (proxy limitation),
# NOT proof the channel is invisible interactively.
cat > "$WORK/.claude/hooks/warn-probe-a.sh" <<HOOK
#!/bin/bash
echo fired >> "$WORK/fired-a.log"
printf '{"systemMessage":"$TOKEN"}'
exit 0
HOOK
chmod +x "$WORK/.claude/hooks/warn-probe-a.sh"

# Form W-B probe hook: token to stderr + exit 0.
cat > "$WORK/.claude/hooks/warn-probe-b.sh" <<HOOK
#!/bin/bash
echo fired >> "$WORK/fired-b.log"
printf '%s\n' "$TOKEN" >&2
exit 0
HOOK
chmod +x "$WORK/.claude/hooks/warn-probe-b.sh"

# Second W-A hook (composition leg) + a byte-copy of inject-bash-timeout.sh.
cat > "$WORK/.claude/hooks/warn-probe-a2.sh" <<HOOK
#!/bin/bash
printf '{"systemMessage":"$TOKEN2"}'
exit 0
HOOK
chmod +x "$WORK/.claude/hooks/warn-probe-a2.sh"
cp "$REPO_ROOT/hooks/inject-bash-timeout.sh" "$WORK/.claude/hooks/inject-bash-timeout.sh"
chmod +x "$WORK/.claude/hooks/inject-bash-timeout.sh"

# Denying sibling (composition leg b).
cat > "$WORK/.claude/hooks/warn-probe-deny.sh" <<HOOK
#!/bin/bash
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"PROBE_DENY"}}'
exit 0
HOOK
chmod +x "$WORK/.claude/hooks/warn-probe-deny.sh"

write_settings() {
  # $1 = newline-joined list of hook script basenames to register on Bash.
  local hooks_json="" b first=1
  for b in $1; do
    [ "$first" = 1 ] || hooks_json="$hooks_json,"
    first=0
    hooks_json="$hooks_json{\"type\":\"command\",\"command\":\"\$CLAUDE_PROJECT_DIR/.claude/hooks/$b\"}"
  done
  cat > "$WORK/.claude/settings.json" <<JSON
{
  "permissions": { "allow": ["Bash(echo:*)", "Bash(true)"] },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ $hooks_json ] }
    ]
  }
}
JSON
}

run_probe() {
  # $1 = stdout capture file, $2 = stderr capture file
  ( cd "$WORK" && CLAUDE_PROJECT_DIR="$WORK" claude -p 'Run exactly: echo probe-ran' \
      --output-format stream-json --verbose ) >"$1" 2>"$2"
}

# Stream-json record walker — PASS iff $TOKEN appears in a record whose
# top-level "type" is "system" OR the final "result" record, and NOT merely
# inside an assistant/user tool_use/tool_result payload (the vacuous-pass trap).
visibility_check() {
  # $1 = stream-json file, $2 = token
  "$PY" - "$1" "$2" <<'PYEOF'
import json, sys
path, token = sys.argv[1], sys.argv[2]
hit = None
for raw in open(path, encoding="utf-8", errors="replace"):
    raw = raw.strip()
    if not raw:
        continue
    try:
        rec = json.loads(raw)
    except Exception:
        continue
    t = rec.get("type")
    if t in ("system", "result"):
        blob = json.dumps(rec)
        if token in blob:
            hit = (t, "top-level system/result record")
            break
if hit:
    print("VISIBLE\t%s\t%s" % hit)
    sys.exit(0)
print("NOT-VISIBLE")
sys.exit(1)
PYEOF
}

echo "=== Step 1-3: Form W-A leg ==="
write_settings "warn-probe-a.sh"
run_probe "$TEST_OUT/warn-probe-a.json" "$TEST_OUT/warn-probe-a.stderr"
echo "--- stdout head ---"; head -40 "$TEST_OUT/warn-probe-a.json"
echo "--- model-saw (assistant turns containing token) ---"
grep -c "$TOKEN" "$TEST_OUT/warn-probe-a.json" || true
PINNED=""
if visibility_check "$TEST_OUT/warn-probe-a.json" "$TOKEN"; then
  echo ">> W-A VISIBLE — pin Form W-A."
  PINNED="W-A"
else
  echo ">> W-A NOT visible in a user-facing stream record."
  echo "=== Step 4: Form W-B fallback leg ==="
  write_settings "warn-probe-b.sh"
  run_probe "$TEST_OUT/warn-probe-b.json" "$TEST_OUT/warn-probe-b.stderr"
  if visibility_check "$TEST_OUT/warn-probe-b.json" "$TOKEN"; then
    echo ">> W-B VISIBLE in a user-facing stream record — pin Form W-B."
    PINNED="W-B"
  elif grep -q "$TOKEN" "$TEST_OUT/warn-probe-b.stderr" 2>/dev/null; then
    echo ">> W-B token only in CLI stderr (process-level propagation, NOT"
    echo "   proof of interactive visibility). W-B may be pinned ONLY after a"
    echo "   one-time ATTENDED confirmation (probe spec step 4b):"
    echo "   surface to the user; have them run one watched 'git add .' in a"
    echo "   scratch consumer with hooks.git_discipline.git_add_all: \"warn\""
    echo "   set, and confirm the warning renders."
    PINNED="W-B-NEEDS-ATTENDED"
  else
    # DECOUPLE: did the hooks actually FIRE? A fired-sentinel + no surface in
    # the HEADLESS stream is the proxy limitation (Settled decision 2: the
    # headless stream is a PROXY for interactive rendering), NOT proof the
    # channel is invisible interactively. Route to ATTENDED confirmation, not a
    # hard STOP — only a NON-FIRING hook (a real registration/config failure)
    # or an attended-confirmed non-render is the Failure-Protocol STOP.
    _fired_a=0; _fired_b=0
    [ -f "$WORK/fired-a.log" ] && _fired_a=1
    [ -f "$WORK/fired-b.log" ] && _fired_b=1
    echo ">> NEITHER form surfaced in the HEADLESS stream-json output."
    echo "   W-A hook fired: $_fired_a   W-B hook fired: $_fired_b"
    if [ "$_fired_a" = 1 ] || [ "$_fired_b" = 1 ]; then
      echo "   The hook(s) FIRED (sentinel written) but their output did not"
      echo "   appear in the headless stream. The headless stream is a PROXY"
      echo "   for interactive rendering — this is INCONCLUSIVE, not a proof of"
      echo "   invisibility. ATTENDED confirmation REQUIRED before the opt-in"
      echo "   \"warn\" value is accepted (probe spec step 4b + Phase 7 live"
      echo "   check): surface to the user; have them run one watched command"
      echo "   with a \"warn\" toggle set and confirm the warning renders. The"
      echo "   SILENT default and the deny arm are unaffected and ship now."
      PINNED="NEEDS-ATTENDED"
    else
      echo ">> The probe hooks did NOT fire (no sentinel) — this is a"
      echo "   registration/config failure, a Failure-Protocol STOP: the probe"
      echo "   could not be run, surface to the orchestrator."
      PINNED="NONE"
    fi
  fi
fi

echo ""
echo "=== Step 6a: multi-hook composition (two warn hooks + inject-bash-timeout) ==="
if [ "$PINNED" = "W-A" ]; then
  write_settings "warn-probe-a.sh warn-probe-a2.sh inject-bash-timeout.sh"
  run_probe "$TEST_OUT/warn-probe-compose.json" "$TEST_OUT/warn-probe-compose.stderr"
  v1=1; v2=1
  visibility_check "$TEST_OUT/warn-probe-compose.json" "$TOKEN"  >/dev/null && v1=0
  visibility_check "$TEST_OUT/warn-probe-compose.json" "$TOKEN2" >/dev/null && v2=0
  echo "token1 visible: $([ $v1 = 0 ] && echo YES || echo NO)"
  echo "token2 visible: $([ $v2 = 0 ] && echo YES || echo NO)"
  # updatedInput applied-evidence ladder: (i) stream record shows injected
  # timeout 600000? else (ii) behavioral check. Document either way.
  if grep -q '600000' "$TEST_OUT/warn-probe-compose.json"; then
    echo "updatedInput timeout 600000 VISIBLE in stream — quote it from the json."
  else
    echo "updatedInput timeout NOT visible in stream (INVISIBLE, not clobbered)."
    echo "  Behavioral fallback: a 'sleep 130'-class probe is the gating check;"
    echo "  see probe spec step 6a(ii). Only a VISIBLY-clobbered merge is a STOP."
  fi
elif [ "$PINNED" = "W-B" ]; then
  write_settings "warn-probe-b.sh warn-probe-a2.sh inject-bash-timeout.sh"
  # NB: under W-B no warn envelopes co-fire on stdout — assert both tokens in
  # the stderr capture instead (step-6a note).
  run_probe "$TEST_OUT/warn-probe-compose.json" "$TEST_OUT/warn-probe-compose.stderr"
  grep -c "$TOKEN" "$TEST_OUT/warn-probe-compose.stderr" || true
else
  echo "(skipped — no pinned form or attended-confirmation pending)"
fi

echo ""
echo "=== Step 6b: warn hook + denying sibling (deny must win) ==="
if [ "$PINNED" = "W-A" ] || [ "$PINNED" = "W-B" ]; then
  if [ "$PINNED" = "W-A" ]; then
    write_settings "warn-probe-a.sh warn-probe-deny.sh"
  else
    write_settings "warn-probe-b.sh warn-probe-deny.sh"
  fi
  run_probe "$TEST_OUT/warn-probe-deny-leg.json" "$TEST_OUT/warn-probe-deny-leg.stderr"
  echo "--- deny-leg stdout head ---"; head -40 "$TEST_OUT/warn-probe-deny-leg.json"
  echo "(RECORD whether the warn's systemMessage still surfaced — document, do"
  echo " not gate. If dropped, the lib's deny-path append rule preserves it.)"
fi

echo ""
echo "=== PINNED FORM: ${PINNED:-UNDECIDED} ==="
case "$PINNED" in
  W-A|W-B) echo "Probe PASS — ship $PINNED."; exit 0 ;;
  W-B-NEEDS-ATTENDED|NEEDS-ATTENDED)
    echo "Probe PARTIAL — hooks fire but headless stream did not surface their"
    echo "output (proxy limitation). Attended confirmation required before the"
    echo "opt-in \"warn\" value is accepted as user-visible. W-A is provisionally"
    echo "pinned in the lib (cleaner decision-less channel); silent default +"
    echo "deny arm are unaffected and ship now."
    exit 3 ;;
  *) echo "Probe FAIL — Failure-Protocol STOP (hooks did not fire)."; exit 1 ;;
esac
