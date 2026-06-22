#!/bin/bash
# tests/test-zskills-enforcement-lib.sh — unit suite for
# hooks/_lib/zskills-enforcement.sh (ENFORCEMENT_V2_PLAN Phase 1, #1159).
#
# Covers: the watched/enforce PREDICATE (permission_mode parse incl. spoof
# cases + pipeline-live marker/sentinel arms), config_root resolution, the
# MODE resolver (hard/demotable × predicate values, the OWNER-AMENDMENT silent
# default, the config_hooks_tamper warn-when-watched NAMED EXCEPTION, explicit
# overrides, the group-enabled ceiling + the tamper ceiling-exemption),
# _ZSK_ENF_SOURCE strings, fail-closed toggle loading, warn accumulation +
# flush, the decision-less-warn HARD INVARIANT (Settled decision 2),
# json_escape, the pinned tag literal, and the KNOWN_CHECKS registry shape.
#
# HOME is sandboxed to a tmp dir for ALL cases (modeled on
# tests/test-zskills-resolve-config.sh) so the host's real config never leaks.
# pass/fail inline (mirrors tests/test-hook-helper-drift.sh).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/hooks/_lib/zskills-enforcement.sh"

PASS=0
FAIL=0
pass() { printf '  PASS %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  FAIL %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# HOME sandbox: an empty home so no user-tier file ever leaks into a case.
SANDBOX_HOME=$(mktemp -d /tmp/zskills-enf-home-XXXXXX)
export HOME="$SANDBOX_HOME"

# A clean workspace root for marker/config fixtures.
WORK=$(mktemp -d /tmp/zskills-enf-work-XXXXXX)
cleanup() { rm -rf "$SANDBOX_HOME" "$WORK"; }
trap cleanup EXIT

# Source the lib once into THIS shell. Each case resets the per-fire globals
# (_ZSK_ENF_TOGGLES*, _ZSK_ENF_SOURCE, _ZSK_ENF_WARNINGS) it touches.
# shellcheck source=hooks/_lib/zskills-enforcement.sh
. "$LIB"

reset_state() {
  _ZSK_ENF_TOGGLES=""
  _ZSK_ENF_TOGGLES_LOADED=1   # treat as "already loaded, empty" unless a case loads
  _ZSK_ENF_SOURCE=""
  _ZSK_ENF_WARNINGS=""
}

assert_eq() {
  # $1=label $2=expected $3=actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2] got [$3]"; fi
}

# ── PREDICATE ─────────────────────────────────────────────────────────────
echo "── predicate: permission_mode parse ──"
# bypassPermissions is ATTENDED: it's a permission-convenience flag, not an
# attendance signal. With no live pipeline marker it resolves to watched (same
# as default/acceptEdits/plan). Autonomy is detected by the pipeline-live arms;
# hard enforcement stays available via the per-check "block" toggle.
assert_eq "predicate bypassPermissions (no markers) → watched" "watched" \
  "$(zskills_enforcement_predicate '{"permission_mode":"bypassPermissions"}' /nope /nope)"
assert_eq "predicate default (no markers) → watched" "watched" \
  "$(zskills_enforcement_predicate '{"permission_mode":"default"}' /nope /nope)"
assert_eq "predicate acceptEdits (no markers) → watched" "watched" \
  "$(zskills_enforcement_predicate '{"permission_mode":"acceptEdits"}' /nope /nope)"
assert_eq "predicate plan (no markers) → watched" "watched" \
  "$(zskills_enforcement_predicate '{"permission_mode":"plan"}' /nope /nope)"
assert_eq "predicate absent → enforce-autonomous (fail-safe)" "enforce-autonomous" \
  "$(zskills_enforcement_predicate '{"tool_input":{"command":"x"}}' /nope /nope)"
assert_eq "predicate garbage value → enforce-autonomous (fail-safe)" "enforce-autonomous" \
  "$(zskills_enforcement_predicate '{"permission_mode":"banana"}' /nope /nope)"

echo "── predicate: SPOOF cases ──"
# Counterfeit escaped "permission_mode":"default" embedded in command content,
# real top-level field is bypassPermissions → parser must take the REAL field
# (now attended → watched, no markers), NOT leak the embedded literal.
assert_eq "spoof embedded default + real bypass → watched" "watched" \
  "$(zskills_enforcement_predicate '{"tool_input":{"command":"echo \"permission_mode\":\"default\""},"permission_mode":"bypassPermissions"}' /nope /nope)"
# Counterfeit escaped attended literal embedded, real top-level field is GARBAGE
# → parser must take the real (unrecognized) field → fail-safe enforce-autonomous.
# This is the discriminating spoof case: embedded "default" would map to watched,
# but the real "banana" is unrecognized, so the result proves the embedded
# literal was NOT parsed.
assert_eq "spoof embedded default + real garbage → enforce-autonomous" "enforce-autonomous" \
  "$(zskills_enforcement_predicate '{"tool_input":{"command":"echo \"permission_mode\":\"default\""},"permission_mode":"banana"}' /nope /nope)"
# Counterfeit embedded default, real field ABSENT → fail-safe enforce.
assert_eq "spoof embedded default + real absent → enforce-autonomous" "enforce-autonomous" \
  "$(zskills_enforcement_predicate '{"tool_input":{"command":"echo \"permission_mode\":\"default\""}}' /nope /nope)"

echo "── predicate: pipeline-live marker arms ──"
# DA1: .zskills/tracked at the LOCAL root ($3), MAIN root ($2) clean — the
# production marker placement (worktree agents).
LR=$(mktemp -d "$WORK/local-XXXXXX"); MR=$(mktemp -d "$WORK/main-XXXXXX")
mkdir -p "$LR/.zskills"; touch "$LR/.zskills/tracked"
assert_eq "DA1 local .zskills/tracked, main clean → enforce-pipeline" "enforce-pipeline" \
  "$(zskills_enforcement_predicate '{"permission_mode":"default"}' "$MR" "$LR")"
# bypassPermissions is attended, but a LIVE pipeline marker still forces
# enforce-pipeline — genuine zskills autonomy under bypass is caught here.
assert_eq "bypassPermissions + live pipeline marker → enforce-pipeline" "enforce-pipeline" \
  "$(zskills_enforcement_predicate '{"permission_mode":"bypassPermissions"}' "$MR" "$LR")"
# Legacy .zskills-tracked at the local root.
rm -f "$LR/.zskills/tracked"; touch "$LR/.zskills-tracked"
assert_eq "legacy local .zskills-tracked → enforce-pipeline" "enforce-pipeline" \
  "$(zskills_enforcement_predicate '{"permission_mode":"default"}' "$MR" "$LR")"
rm -f "$LR/.zskills-tracked"
# Main-root tracked only (OR-arm; local clean).
LR2=$(mktemp -d "$WORK/local2-XXXXXX")
mkdir -p "$MR/.zskills"; touch "$MR/.zskills/tracked"
assert_eq "main-root .zskills/tracked only → enforce-pipeline" "enforce-pipeline" \
  "$(zskills_enforcement_predicate '{"permission_mode":"default"}' "$MR" "$LR2")"
rm -f "$MR/.zskills/tracked"; touch "$MR/.zskills-tracked"
assert_eq "legacy main-root .zskills-tracked → enforce-pipeline" "enforce-pipeline" \
  "$(zskills_enforcement_predicate '{"permission_mode":"default"}' "$MR" "$LR2")"
rm -f "$MR/.zskills-tracked"

echo "── predicate: inflight sentinel arm ──"
MR3=$(mktemp -d "$WORK/main3-XXXXXX"); LR3=$(mktemp -d "$WORK/local3-XXXXXX")
mkdir -p "$MR3/.zskills/inflight/skill"; echo '{"started_at":"now"}' > "$MR3/.zskills/inflight/skill/pid.json"
assert_eq "fresh inflight sentinel → enforce-pipeline" "enforce-pipeline" \
  "$(zskills_enforcement_predicate '{"permission_mode":"default"}' "$MR3" "$LR3")"
# Backdate past the 120-min TTL → watched.
touch -d '3 hours ago' "$MR3/.zskills/inflight/skill/pid.json" 2>/dev/null || touch -t "$(date -d '3 hours ago' +%Y%m%d%H%M 2>/dev/null || echo 202001010000)" "$MR3/.zskills/inflight/skill/pid.json"
assert_eq "backdated inflight sentinel (past TTL) → watched" "watched" \
  "$(zskills_enforcement_predicate '{"permission_mode":"default"}' "$MR3" "$LR3")"

echo "── predicate: DA2 stale tracking dir must NOT enforce ──"
MR4=$(mktemp -d "$WORK/main4-XXXXXX"); LR4=$(mktemp -d "$WORK/local4-XXXXXX")
mkdir -p "$MR4/.zskills/tracking/finished-pipeline"
touch "$MR4/.zskills/tracking/finished-pipeline/requires.x.123" \
      "$MR4/.zskills/tracking/finished-pipeline/step.1.123"
assert_eq "DA2 stale tracking subdir, no tracked file → watched" "watched" \
  "$(zskills_enforcement_predicate '{"permission_mode":"default"}' "$MR4" "$LR4")"

echo "── predicate: bypassPermissions-as-attended REGRESSION PIN ──"
# REGRESSION PIN for the bypassPermissions=attended recategorization: a
# bypass-mode human with NO live pipeline and an unset per-check toggle must
# resolve to a SILENT demotable check (no nag, no block). This pins the whole
# attended path end-to-end: predicate → watched, then a demotable check
# (main_edit) with the toggle unset → silent.
MR5=$(mktemp -d "$WORK/main5-XXXXXX"); LR5=$(mktemp -d "$WORK/local5-XXXXXX")
PIN_PRED="$(zskills_enforcement_predicate '{"permission_mode":"bypassPermissions"}' "$MR5" "$LR5")"
assert_eq "PIN: bypass + no pipeline + unset toggle → predicate watched" "watched" "$PIN_PRED"
reset_state
assert_eq "PIN: bypass-watched + demotable main_edit (unset) → silent" "silent" \
  "$(zskills_enforcement_mode main_protection main_edit demotable "$PIN_PRED")"

# ── CONFIG_ROOT ───────────────────────────────────────────────────────────
echo "── config_root resolution ──"
# ZSKILLS_ENF_CONFIG_ROOT override wins.
assert_eq "config_root: ZSKILLS_ENF_CONFIG_ROOT override wins" "/tmp/some-root" \
  "$(ZSKILLS_ENF_CONFIG_ROOT=/tmp/some-root zskills_enforcement_config_root)"
# Inside a main git checkout → the checkout root.
GITMAIN=$(mktemp -d "$WORK/gitmain-XXXXXX")
( cd "$GITMAIN" && git init -q && git config user.email t@t && git config user.name t )
GITMAIN_REAL=$(cd "$GITMAIN" && pwd -P)
assert_eq "config_root: inside main checkout → checkout root" "$GITMAIN_REAL" \
  "$(cd "$GITMAIN" && env -u ZSKILLS_ENF_CONFIG_ROOT bash -c ". '$LIB'; zskills_enforcement_config_root")"
# Inside a LINKED worktree → echoes the MAIN root, not the worktree.
( cd "$GITMAIN" && git commit -q --allow-empty -m init && git worktree add -q "$WORK/wt-link" -b wtbranch >/dev/null 2>&1 )
if [ -d "$WORK/wt-link" ]; then
  assert_eq "config_root: inside linked worktree → MAIN root" "$GITMAIN_REAL" \
    "$(cd "$WORK/wt-link" && env -u ZSKILLS_ENF_CONFIG_ROOT bash -c ". '$LIB'; zskills_enforcement_config_root")"
else
  fail "config_root: linked worktree setup" "git worktree add did not create $WORK/wt-link"
fi
# Non-git dir with CLAUDE_PROJECT_DIR.
NONGIT=$(mktemp -d "$WORK/nongit-XXXXXX")
assert_eq "config_root: non-git dir → CLAUDE_PROJECT_DIR" "/tmp/cpd-root" \
  "$(cd "$NONGIT" && env -u ZSKILLS_ENF_CONFIG_ROOT CLAUDE_PROJECT_DIR=/tmp/cpd-root bash -c ". '$LIB'; zskills_enforcement_config_root")"

# ── MODE RESOLVER ─────────────────────────────────────────────────────────
echo "── mode: hard check (never silent) ──"
reset_state
assert_eq "hard unset + enforce-autonomous → block" "block" \
  "$(zskills_enforcement_mode git_destructive reset_hard hard enforce-autonomous)"
assert_eq "hard unset + enforce-pipeline → block" "block" \
  "$(zskills_enforcement_mode git_destructive reset_hard hard enforce-pipeline)"
assert_eq "hard unset + watched → block (never silent)" "block" \
  "$(zskills_enforcement_mode git_destructive reset_hard hard watched)"

echo "── mode: demotable (OWNER-AMENDMENT silent default) ──"
reset_state
assert_eq "demotable git_add_all + enforce-autonomous → block" "block" \
  "$(zskills_enforcement_mode git_discipline git_add_all demotable enforce-autonomous)"
assert_eq "demotable git_add_all + enforce-pipeline → block" "block" \
  "$(zskills_enforcement_mode git_discipline git_add_all demotable enforce-pipeline)"
# Run without command substitution so _ZSK_ENF_SOURCE is set in THIS shell.
RES="$(zskills_enforcement_mode git_discipline git_add_all demotable watched)"
zskills_enforcement_mode git_discipline git_add_all demotable watched >/dev/null
assert_eq "demotable git_add_all + watched → SILENT (not warn)" "silent" "$RES"
assert_eq "  → _ZSK_ENF_SOURCE = attended default (silent)" "attended default (silent)" "$_ZSK_ENF_SOURCE"

echo "── mode: config_hooks_tamper NAMED EXCEPTION (DA4) ──"
reset_state
assert_eq "tamper unset + enforce-autonomous → block" "block" \
  "$(zskills_enforcement_mode main_protection config_hooks_tamper demotable enforce-autonomous)"
assert_eq "tamper unset + enforce-pipeline → block" "block" \
  "$(zskills_enforcement_mode main_protection config_hooks_tamper demotable enforce-pipeline)"
RES="$(zskills_enforcement_mode main_protection config_hooks_tamper demotable watched)"
zskills_enforcement_mode main_protection config_hooks_tamper demotable watched >/dev/null
assert_eq "tamper unset + watched → WARN (not silent)" "warn" "$RES"
assert_eq "  → _ZSK_ENF_SOURCE = attended default (warn — tamper exception)" \
  "attended default (warn — tamper exception)" "$_ZSK_ENF_SOURCE"

echo "── mode: explicit per-check overrides (Settled decision 6) ──"
reset_state; _ZSK_ENF_TOGGLES="git_discipline.git_add_all=warn"
RES="$(zskills_enforcement_mode git_discipline git_add_all demotable watched)"
zskills_enforcement_mode git_discipline git_add_all demotable watched >/dev/null
assert_eq "explicit warn on demotable + watched → warn (opt-in coaching)" "warn" "$RES"
assert_eq "  → _ZSK_ENF_SOURCE = project config: warn" "project config: warn" "$_ZSK_ENF_SOURCE"
reset_state; _ZSK_ENF_TOGGLES="git_discipline.git_add_all=off"
assert_eq "explicit off on demotable → off" "off" \
  "$(zskills_enforcement_mode git_discipline git_add_all demotable watched)"
reset_state; _ZSK_ENF_TOGGLES="git_discipline.git_add_all=block"
assert_eq "explicit block on demotable + watched → block (strict)" "block" \
  "$(zskills_enforcement_mode git_discipline git_add_all demotable watched)"
reset_state; _ZSK_ENF_TOGGLES="git_destructive.reset_hard=warn"
assert_eq "explicit warn on HARD check honored → warn" "warn" \
  "$(zskills_enforcement_mode git_destructive reset_hard hard watched)"
reset_state; _ZSK_ENF_TOGGLES="main_protection.config_hooks_tamper=off"
assert_eq "explicit off on tamper (named exception overridable) → off" "off" \
  "$(zskills_enforcement_mode main_protection config_hooks_tamper demotable watched)"

echo "── mode: group-enabled ceiling + tamper ceiling-exemption ──"
reset_state; _ZSK_ENF_TOGGLES="tracking.enabled=false
tracking.issue_unclaimed=block"
assert_eq "group enabled:false beats per-check block → off" "off" \
  "$(zskills_enforcement_mode tracking issue_unclaimed demotable enforce-autonomous)"
# main_protection.enabled:false → siblings off, but config_hooks_tamper EXEMPT.
reset_state; _ZSK_ENF_TOGGLES="main_protection.enabled=false"
assert_eq "ceiling: main_edit (sibling) → off" "off" \
  "$(zskills_enforcement_mode main_protection main_edit demotable watched)"
reset_state; _ZSK_ENF_TOGGLES="main_protection.enabled=false"
RES="$(zskills_enforcement_mode main_protection config_hooks_tamper demotable watched)"
assert_eq "ceiling-EXEMPT: tamper unset + watched survives → warn" "warn" "$RES"
reset_state; _ZSK_ENF_TOGGLES="main_protection.enabled=false"
assert_eq "ceiling-EXEMPT: tamper unset + autonomous survives → block" "block" \
  "$(zskills_enforcement_mode main_protection config_hooks_tamper demotable enforce-autonomous)"
# Self-protection: ceiling false but explicit tamper off still turns it off.
reset_state; _ZSK_ENF_TOGGLES="main_protection.enabled=false
main_protection.config_hooks_tamper=off"
assert_eq "explicit tamper off under ceiling → off" "off" \
  "$(zskills_enforcement_mode main_protection config_hooks_tamper demotable watched)"

echo "── _ZSK_ENF_SOURCE strings ──"
reset_state
zskills_enforcement_mode git_discipline git_add_all demotable enforce-autonomous >/dev/null
assert_eq "source: autonomous default" "autonomous default" "$_ZSK_ENF_SOURCE"
reset_state
zskills_enforcement_mode git_discipline git_add_all demotable enforce-pipeline >/dev/null
assert_eq "source: pipeline-active default" "pipeline-active default" "$_ZSK_ENF_SOURCE"
reset_state
zskills_enforcement_mode git_discipline git_add_all demotable watched >/dev/null
assert_eq "source: attended default (silent)" "attended default (silent)" "$_ZSK_ENF_SOURCE"
reset_state
zskills_enforcement_mode main_protection config_hooks_tamper demotable watched >/dev/null
assert_eq "source: attended default (warn — tamper exception)" "attended default (warn — tamper exception)" "$_ZSK_ENF_SOURCE"
reset_state; _ZSK_ENF_TOGGLES="git_discipline.git_add_all=block"
zskills_enforcement_mode git_discipline git_add_all demotable watched >/dev/null
assert_eq "source: project config: block" "project config: block" "$_ZSK_ENF_SOURCE"
reset_state; _ZSK_ENF_TOGGLES="git_discipline.enabled=false"
zskills_enforcement_mode git_discipline git_add_all demotable watched >/dev/null
assert_eq "source: group disabled in project config" "group disabled in project config" "$_ZSK_ENF_SOURCE"

# ── TOGGLE LOADER (lazy + fail-closed) ────────────────────────────────────
echo "── toggle loader ──"
CFGDIR=$(mktemp -d "$WORK/cfg-XXXXXX"); mkdir -p "$CFGDIR/.claude"
cat > "$CFGDIR/.claude/zskills-config.json" <<'JSON'
{
  "hooks": {
    "git_discipline": { "git_add_all": "off", "tests_not_run": "block" },
    "main_protection": { "enabled": true, "main_edit": "warn" },
    "tracking": { "enabled": false }
  }
}
JSON
_ZSK_ENF_TOGGLES=""; _ZSK_ENF_TOGGLES_LOADED=0
zskills_enforcement_load_toggles "$CFGDIR/.claude/zskills-config.json"
LOADED_SORTED="$(printf '%s\n' "$_ZSK_ENF_TOGGLES" | sort | tr '\n' '|')"
assert_eq "loader parses hooks block" \
  "git_discipline.git_add_all=off|git_discipline.tests_not_run=block|main_protection.enabled=true|main_protection.main_edit=warn|tracking.enabled=false|" \
  "$LOADED_SORTED"
# Lazy cache: a second call is a no-op (corrupt the file, assert no reload).
echo 'GARBAGE' > "$CFGDIR/.claude/zskills-config.json"
zskills_enforcement_load_toggles "$CFGDIR/.claude/zskills-config.json"
LOADED_SORTED2="$(printf '%s\n' "$_ZSK_ENF_TOGGLES" | sort | tr '\n' '|')"
assert_eq "loader is cached (no reload on 2nd call)" "$LOADED_SORTED" "$LOADED_SORTED2"

echo "── toggle loader: fail-closed ──"
# Missing file → empty toggles, loaded flag set.
_ZSK_ENF_TOGGLES="stale"; _ZSK_ENF_TOGGLES_LOADED=0
zskills_enforcement_load_toggles "$WORK/does-not-exist.json"
assert_eq "missing file → empty toggles" "" "$_ZSK_ENF_TOGGLES"
assert_eq "missing file → loaded flag set" "1" "$_ZSK_ENF_TOGGLES_LOADED"
# Malformed JSON → empty toggles (defaults).
echo '{ this is not json' > "$CFGDIR/.claude/zskills-config.json"
_ZSK_ENF_TOGGLES="stale"; _ZSK_ENF_TOGGLES_LOADED=0
zskills_enforcement_load_toggles "$CFGDIR/.claude/zskills-config.json"
assert_eq "malformed JSON → empty toggles (defaults)" "" "$_ZSK_ENF_TOGGLES"
# Python unavailable → empty toggles (defaults). Simulate by pointing PATH at
# an EMPTY dir (no python3/python resolvable) + a bogus ZSKILLS_PYTHON, while
# invoking bash by ABSOLUTE path (PATH has no bash either).
cat > "$CFGDIR/.claude/zskills-config.json" <<'JSON'
{ "hooks": { "git_discipline": { "git_add_all": "off" } } }
JSON
BASH_BIN="$(command -v bash)"
EMPTY_PATH_DIR=$(mktemp -d "$WORK/emptypath-XXXXXX")
NOPY_OUT="$(env -i HOME="$SANDBOX_HOME" PATH="$EMPTY_PATH_DIR" ZSKILLS_PYTHON=/bin/false \
  "$BASH_BIN" -c ". '$LIB'; _ZSK_ENF_TOGGLES=stale; _ZSK_ENF_TOGGLES_LOADED=0; zskills_enforcement_load_toggles '$CFGDIR/.claude/zskills-config.json'; printf '[%s]' \"\$_ZSK_ENF_TOGGLES\"")"
assert_eq "Python unavailable → empty toggles (defaults)" "[]" "$NOPY_OUT"

# ── WARN ACCUMULATION + FLUSH ─────────────────────────────────────────────
echo "── warn accumulation + flush ──"
reset_state
OUT="$(zskills_enforcement_flush_warnings)"
assert_eq "zero warns → flush emits nothing" "" "$OUT"
reset_state
zskills_enforcement_warn "first message"
zskills_enforcement_warn "second message"
OUT="$(zskills_enforcement_flush_warnings)"
# One flush emission containing both, each prefixed.
if printf '%s' "$OUT" | grep -q 'WARNING (not blocked by this check): first message' \
   && printf '%s' "$OUT" | grep -q 'WARNING (not blocked by this check): second message'; then
  pass "two warns → ONE flush emission containing both (prefixed)"
else
  fail "two warns flush" "missing one or both prefixed warnings: [$OUT]"
fi
# Exactly one systemMessage envelope (one flush).
N_ENV="$(printf '%s' "$OUT" | grep -o '"systemMessage"' | wc -l | tr -d ' ')"
assert_eq "flush emits exactly one systemMessage envelope" "1" "$N_ENV"

echo "── warn-path DECISION-LESS invariant (Settled decision 2) ──"
reset_state
zskills_enforcement_warn $'hostile "quoted" \\ multi\nline\twith\tcontrol'$'\x01'$' byte'
OUT="$(zskills_enforcement_flush_warnings)"
N_PD="$(printf '%s' "$OUT" | grep -c 'permissionDecision' || true)"
assert_eq "flush output contains NO permissionDecision" "0" "$N_PD"
# W-A form must round-trip through json.load (locks escape path vs hostile prose).
PY="$(command -v python3 || command -v python)"
if printf '%s' "$OUT" | "$PY" -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  pass "flush W-A output round-trips through json.load"
else
  fail "flush W-A json validity" "json.load rejected the flush output: [$OUT]"
fi

# ── JSON_ESCAPE ───────────────────────────────────────────────────────────
echo "── json_escape ──"
assert_eq "json_escape: quote" 'a\"b' "$(zskills_enforcement_json_escape 'a"b')"
assert_eq "json_escape: backslash" 'a\\b' "$(zskills_enforcement_json_escape 'a\b')"
assert_eq "json_escape: newline" 'a\nb' "$(zskills_enforcement_json_escape $'a\nb')"
assert_eq "json_escape: tab" 'a\tb' "$(zskills_enforcement_json_escape $'a\tb')"
# Raw control byte 0x01 stripped; result still valid JSON when wrapped.
ESC="$(zskills_enforcement_json_escape $'a\x01b')"
assert_eq "json_escape: raw 0x01 stripped" 'ab' "$ESC"
if printf '{"x":"%s"}' "$ESC" | "$PY" -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  pass "json_escape: 0x01-stripped output is valid JSON"
else
  fail "json_escape valid JSON" "wrapping the escaped 0x01 output failed json.load"
fi

# ── TAG (pinned literal regex) ────────────────────────────────────────────
echo "── tag pinned literal ──"
_ZSK_ENF_SOURCE="attended default (silent)"
TAG="$(zskills_enforcement_tag git_discipline git_add_all)"
# The pinned regex from the lib spec.
if printf '%s' "$TAG" | grep -Eq '^\[hooks\.[a-z_]+\.[a-z0-9_]+ — block\|warn\|off in \.claude/zskills-config\.json; currently: .+\]$'; then
  pass "tag matches the pinned literal regex"
else
  fail "tag pinned regex" "tag did not match: [$TAG]"
fi

# ── KNOWN_CHECKS registry shape ───────────────────────────────────────────
echo "── KNOWN_CHECKS registry ──"
KC="$(printf '%s\n' "$_ZSK_ENF_KNOWN_CHECKS" | grep -E ':(hard|demotable)$')"
N_TOTAL="$(printf '%s\n' "$KC" | grep -c .)"
assert_eq "KNOWN_CHECKS has 37 entries" "37" "$N_TOTAL"
N_DEMOTABLE="$(printf '%s\n' "$KC" | grep -c ':demotable$')"
assert_eq "KNOWN_CHECKS has 16 demotable keys" "16" "$N_DEMOTABLE"
N_HARD="$(printf '%s\n' "$KC" | grep -c ':hard$')"
assert_eq "KNOWN_CHECKS has 21 hard keys" "21" "$N_HARD"
# Every key's group ∈ the 7 named groups.
BAD_GROUP="$(printf '%s\n' "$KC" | sed 's/\..*//' | sort -u \
  | grep -vxE 'git_destructive|fs_destructive|process_kill|git_discipline|main_protection|pr_discipline|tracking' || true)"
assert_eq "every KNOWN_CHECKS group ∈ the 7 named groups" "" "$BAD_GROUP"
# config_hooks_tamper is present and classed demotable.
if printf '%s\n' "$KC" | grep -qx 'main_protection.config_hooks_tamper:demotable'; then
  pass "main_protection.config_hooks_tamper:demotable present"
else
  fail "tamper key present" "main_protection.config_hooks_tamper:demotable not in KNOWN_CHECKS"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed (of $((PASS + FAIL)))"
exit "$FAIL"
