#!/usr/bin/env bash
# tests/test-update-zskills-init.sh — INSTALL_REDESIGN Phase 6a item A8.
#
# The explicit plugin-lane init (/update-zskills Step 0.7 bare-call arm,
# items A0–A7) is prose+bash executed by an LLM orchestrator. As with
# test-update-zskills-agent-install.sh, we encode the documented init
# sequence as an executable bash ORACLE below (`run_init`) and drive it
# against fixtures. If SKILL.md's Step 0.7 init/update spec changes meaning,
# the oracle must be updated in lockstep.
#
# #1132 discipline: every path, sentinel, and seed shape used by fixtures is
# DERIVED by sourcing skills/update-zskills/scripts/init-state.sh (the
# single path definition) — never a re-typed literal. The oracle's A1.5 and
# A7 steps call init-state.sh's own functions (no duplication).
#
# Coverage (ports the materialiser-era assertions named by Phase 6a A8):
#   gitignore idempotent-append + ordering oracle + negative-override STOP;
#   config seed shape / schema sibling / version stamp / never-clobber;
#   atomic + 0-byte-heal marker writes (#1079); abort-mid-init no-leak;
#   init-done content carries version; lock-LAST ordering (setup-confirmed
#   before init-done; failure leaves re-runnable state); A1.5 case families
#   (sentinelled removal, un-sentinelled never removed, seeded-config cure
#   accept/decline/shape-mismatch, notice consumed exactly once, the
#   anti-#1132-mask foreign-zskills_version fixture); A6 HARD gate (Phase
#   6b: a failing verify-install STOPs init before the lock write).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

INIT_STATE="$REPO_ROOT/skills/update-zskills/scripts/init-state.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

WORK_BASE="/tmp/zskills-tests/$(basename "$REPO_ROOT")/uz-init"
rm -rf "$WORK_BASE"
mkdir -p "$WORK_BASE"

# Single path definition — paths, writers, frozen legacy-residue constants.
# shellcheck source=skills/update-zskills/scripts/init-state.sh
. "$INIT_STATE"

PYTHON="$(zskills_resolve_python || true)"
if [ -z "$PYTHON" ]; then
  echo "SKIP: no working Python 3 — cannot run init oracle" >&2
  exit 0
fi

EXPECTED_VER="$(bash "$REPO_ROOT/skills/update-zskills/scripts/resolve-repo-version.sh" "$REPO_ROOT" 2>/dev/null || echo "")"

# ── Fixture builders (everything derived from init-state.sh constants) ─────

new_proj() {  # new_proj <name> [nogit]
  local p="$WORK_BASE/$1"
  mkdir -p "$p"
  if [ "${2:-}" != nogit ]; then
    git -C "$p" init -q
  fi
  printf '%s\n' "$p"
}

# Write a sentinelled legacy artifact at <proj>/<rel> (form per extension,
# matching the retired materialiser's first-3-lines stamp; the prefix comes
# from the sourced constant — never re-typed).
write_legacy_artifact() {
  local proj="$1" rel="$2"
  local dest="$proj/$rel"
  mkdir -p "$(dirname "$dest")"
  case "$rel" in
    *.sh)
      printf '%s\n' '#!/usr/bin/env bash' "# $ZSKILLS_LEGACY_SENTINEL_PREFIX 2026.05.0" 'echo hi' > "$dest"
      ;;
    *agents*.md)
      printf '%s\n' '---' "# $ZSKILLS_LEGACY_SENTINEL_PREFIX 2026.05.0" 'name: x' '---' 'body' > "$dest"
      ;;
    *)
      printf '%s\n' "<!-- $ZSKILLS_LEGACY_SENTINEL_PREFIX 2026.05.0 -->" '# rules' > "$dest"
      ;;
  esac
}

# Build an untouched legacy seeded config (+ schema + notice) at <proj>.
# Derived from the FROZEN seed-shape constant; the stamped zskills_version /
# project_name args pin the excluded-keys comparison spec (anti-#1132-mask).
write_legacy_seeded_config() {  # <proj> [<zskills_version>] [<project_name>]
  local proj="$1" zver="${2:-2026.06.0}" pname="${3:-$(basename "$1")}"
  mkdir -p "$proj/.claude"
  ZS_SHAPE="$ZSKILLS_LEGACY_SEED_SHAPE_JSON" ZS_ZVER="$zver" ZS_PNAME="$pname" \
    "$PYTHON" - "$proj/.claude/zskills-config.json" <<'PY'
import json, os, sys
frozen = json.loads(os.environ["ZS_SHAPE"])
seed = {"$schema": "./zskills-config.schema.json",
        "project_name": os.environ["ZS_PNAME"]}
seed.update(frozen)
seed["zskills_version"] = os.environ["ZS_ZVER"]
with open(sys.argv[1], "w") as f:
    json.dump(seed, f, indent=2)
    f.write("\n")
PY
  cp "$REPO_ROOT/config/zskills-config.schema.json" "$proj/.claude/zskills-config.schema.json"
  mkdir -p "$proj/$(dirname "$ZSKILLS_LEGACY_SEED_NOTICE_REL")"
  : > "$proj/$ZSKILLS_LEGACY_SEED_NOTICE_REL"
}

# ── The ORACLE: encodes SKILL.md Step 0.7's bare-call init/update arms ──────
# Env knobs:
#   ZSINIT_INTERVIEW   skip (default; the non-interactive arm) | accept | decline
#   ZSINIT_CURE        decline (default; also the non-interactive arm) | accept
#   ZSINIT_VERIFY_CMD  command run as the A6 verify step (default: true)
#   ZSINIT_ABORT_AFTER_A2  1 -> simulate an abort between A2 and A7 (rc 99)
# Stdout: oracle trace lines, e.g. `removed: <rel>` / `seed-offer: 0|1`.
run_init() {
  local PROJ="$1"
  local INTERVIEW="${ZSINIT_INTERVIEW:-skip}"
  local CURE="${ZSINIT_CURE:-decline}"
  local VERIFY_CMD="${ZSINIT_VERIFY_CMD:-true}"
  local ZS_INIT_VERSION="$EXPECTED_VER"

  # ── A1.5(a) — sentinelled-artifact removal (init-state.sh function) ──
  local removed
  removed="$(zskills_legacy_remove_sentinelled "$PROJ")"
  [ -n "$removed" ] && printf '%s\n' "$removed" | sed 's/^/removed: /'

  # ── A1.5(b) — seeded-config cure ──
  local ZS_SEED_OFFER=0 ZS_REMOVED_CONFIG_THIS_RUN=0
  if zskills_legacy_seed_notice_present "$PROJ" \
     && zskills_legacy_seed_config_matches "$PROJ/.claude/zskills-config.json"; then
    ZS_SEED_OFFER=1
  fi
  printf 'seed-offer: %s\n' "$ZS_SEED_OFFER"
  if [ "$ZS_SEED_OFFER" = 1 ] && [ "$CURE" = accept ]; then
    rm -f "$PROJ/.claude/zskills-config.json" "$PROJ/.claude/zskills-config.schema.json"
    zskills_legacy_consume_seed_notice "$PROJ"
    ZS_REMOVED_CONFIG_THIS_RUN=1
  elif zskills_legacy_seed_notice_present "$PROJ"; then
    # decline / non-interactive / shape-mismatch: keep config, consume notice.
    zskills_legacy_consume_seed_notice "$PROJ"
  fi

  # ── A1 route ──
  if zskills_init_done_present "$PROJ"; then
    # Update arm: conditional config offer + verify + version-line refresh.
    if [ ! -f "$PROJ/.claude/zskills-config.json" ] \
       && [ "$ZS_REMOVED_CONFIG_THIS_RUN" = 0 ] \
       && [ "$INTERVIEW" = accept ]; then
      oracle_seed_config "$PROJ" "$ZS_INIT_VERSION" || return 1
    fi
    # A6 HARD gate (Phase 6b): a verify FAIL stops the run before the
    # version-line refresh.
    $VERIFY_CMD || {
      echo "STOP: verify-install reported a FAIL" >&2
      return 1
    }
    zskills_write_init_markers "$PROJ" "$ZS_INIT_VERSION" || return 1
    echo "arm: update"
    return 0
  fi
  echo "arm: init"

  # ── A2 — gitignore-first (mirrors the SKILL.md fence) ──
  local GI="$PROJ/.gitignore" zs_gi_match
  [ -f "$GI" ] || touch "$GI"
  if ! git -C "$PROJ" check-ignore -q .zskills/probe 2>/dev/null; then
    echo ".zskills/" >> "$GI" 2>/dev/null
  fi
  zs_gi_match=$(git -C "$PROJ" check-ignore -v .zskills/probe 2>/dev/null) || {
    echo "STOP: .zskills/ is not effectively ignored" >&2
    return 1
  }
  case "$zs_gi_match" in
    *!*)
      echo "STOP: negative .gitignore rule overrides the .zskills/ ignore: $zs_gi_match" >&2
      return 1 ;;
  esac

  if [ "${ZSINIT_ABORT_AFTER_A2:-0}" = 1 ]; then
    return 99   # simulated abort between A2 and A7
  fi

  # ── A3 — optional config interview (init arm) ──
  # The accept fence runs ONLY on the "no config exists" interview path —
  # a pre-existing config is review/keep (never clobbered, never restamped).
  if [ "$INTERVIEW" = accept ] && [ ! -f "$PROJ/.claude/zskills-config.json" ] \
     && [ "$ZS_REMOVED_CONFIG_THIS_RUN" = 0 ]; then
    oracle_seed_config "$PROJ" "$ZS_INIT_VERSION" || return 1
  fi
  # decline / skip / existing-config / removed-this-run: write nothing.

  # ── A4 / A5 — no-ops on the landed 1A + T-A + R-b branches ──

  # ── A6 — verify, HARD GATE (Phase 6b): a FAIL STOPs init BEFORE the A7
  # lock write (no init-done — lock-LAST; consumer fixes and re-runs). The
  # real fence invokes verify-install.sh with ZSKILLS_VI_PRE_LOCK=1 (the
  # markers are expected-absent pre-A7); the oracle abstracts the verifier
  # as $VERIFY_CMD and pins the CONTROL FLOW.
  $VERIFY_CMD || {
    echo "STOP: verify-install reported a FAIL" >&2
    return 1
  }

  # ── A7 — lock-LAST (init-state.sh's single writer) ──
  zskills_write_init_markers "$PROJ" "$ZS_INIT_VERSION" || {
    echo "STOP: failed to write the init markers" >&2
    return 1
  }
  return 0
}

# Mirrors the SKILL.md A3 accept fence (seed from canonical defaults, atomic,
# never-clobber; schema sibling + version stamp only-when-config-exists).
oracle_seed_config() {
  local PROJ="$1" ZS_INIT_VERSION="$2"
  local ZS_CONFIG="$PROJ/.claude/zskills-config.json"
  local ZS_DEFAULTS="$REPO_ROOT/skills/update-zskills/scripts/zskills-defaults.json"
  if [ ! -f "$ZS_CONFIG" ]; then
    mkdir -p "$PROJ/.claude"
    local zs_cfg_tmp="$ZS_CONFIG.zskills-tmp.$$"
    PROJECT_NAME="$(basename "$PROJ")" "$PYTHON" - "$ZS_DEFAULTS" "$zs_cfg_tmp" <<'PY'
import json, os, sys
with open(sys.argv[1]) as f:
    defaults = json.load(f)
defaults.pop("_comment", None)
seed = {"$schema": "./zskills-config.schema.json",
        "project_name": os.environ["PROJECT_NAME"]}
seed.update(defaults)
with open(sys.argv[2], "w") as f:
    json.dump(seed, f, indent=2)
    f.write("\n")
PY
    if [ -s "$zs_cfg_tmp" ]; then
      mv "$zs_cfg_tmp" "$ZS_CONFIG"
    else
      rm -f "$zs_cfg_tmp"
    fi
  fi
  if [ -f "$ZS_CONFIG" ]; then
    local ZS_SCHEMA_SRC="$REPO_ROOT/config/zskills-config.schema.json"
    local ZS_SCHEMA_DEST="$PROJ/.claude/zskills-config.schema.json"
    if [ -f "$ZS_SCHEMA_SRC" ] && [ ! -f "$ZS_SCHEMA_DEST" ]; then
      cp "$ZS_SCHEMA_SRC" "$ZS_SCHEMA_DEST"
    fi
    if [ -n "$ZS_INIT_VERSION" ]; then
      bash "$REPO_ROOT/skills/update-zskills/scripts/json-set-string-field.sh" \
        "$ZS_CONFIG" zskills_version "$ZS_INIT_VERSION"
    fi
  fi
}

cfg_field() {  # cfg_field <config> <python-expr over d>
  "$PYTHON" -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1" 2>/dev/null
}

echo "=== /update-zskills explicit init (Phase 6a A0–A8 oracle) ==="

# ── 1. Fresh non-interactive init: gitignore + markers, nothing else ───────
P="$(new_proj fresh-skip)"
run_init "$P" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "1a. fresh non-interactive init completes (rc=0)" \
  || fail "1a. init rc=$rc"
grep -qx '.zskills/' "$P/.gitignore" \
  && pass "1b. umbrella .zskills/ entry appended to .gitignore" \
  || fail "1b. .zskills/ entry missing from .gitignore"
git -C "$P" check-ignore -q .zskills/probe \
  && pass "1c. .zskills/ paths effectively ignored (check-ignore)" \
  || fail "1c. .zskills/ not effectively ignored"
zskills_init_done_present "$P" \
  && pass "1d. init-done marker present after init" \
  || fail "1d. init-done marker missing"
[ -s "$P/$ZSKILLS_SETUP_CONFIRMED_REL" ] \
  && pass "1e. setup-confirmed marker present after init" \
  || fail "1e. setup-confirmed marker missing"
[ ! -f "$P/.claude/zskills-config.json" ] \
  && pass "1f. non-interactive arm wrote NO config (defaults flow from cascade)" \
  || fail "1f. non-interactive arm unexpectedly wrote a config"

# init-done content carries version + date (the config-less version record).
if grep -q "^version: $EXPECTED_VER\$" "$P/$ZSKILLS_INIT_DONE_REL" \
   && grep -q '^date: ' "$P/$ZSKILLS_INIT_DONE_REL"; then
  pass "1g. init-done carries 'version: $EXPECTED_VER' + 'date:' lines"
else
  fail "1g. init-done content wrong: $(cat "$P/$ZSKILLS_INIT_DONE_REL" 2>/dev/null)"
fi
# And the resolver's ZSKILLS_VERSION fallback reads it (A0 retarget, #1132).
RESOLVED_VER=$(
  HOME="$WORK_BASE/empty-home" CLAUDE_PROJECT_DIR="$P" \
  bash -c '. "'"$REPO_ROOT"'/skills/update-zskills/scripts/zskills-resolve-config.sh" && printf "%s" "$ZSKILLS_VERSION"'
)
[ "$RESOLVED_VER" = "$EXPECTED_VER" ] \
  && pass "1h. zskills-resolve-config.sh fallback reads init-done via init-state.sh ($RESOLVED_VER)" \
  || fail "1h. resolver fallback got '$RESOLVED_VER', expected '$EXPECTED_VER'"

# ── 2. Idempotent append: pre-existing entry not duplicated ────────────────
P="$(new_proj gi-idempotent)"
printf '%s\n' '.zskills/' > "$P/.gitignore"
run_init "$P" >/dev/null 2>&1
[ "$(grep -cx '\.zskills/' "$P/.gitignore")" -eq 1 ] \
  && pass "2a. already-covered .gitignore: no duplicate .zskills/ line" \
  || fail "2a. duplicate .zskills/ lines: $(grep -c '\.zskills/' "$P/.gitignore")"

# Re-running init (now the update arm) never re-appends either.
run_init "$P" >/dev/null 2>&1
[ "$(grep -cx '\.zskills/' "$P/.gitignore")" -eq 1 ] \
  && pass "2b. re-run (update arm): still exactly one .zskills/ line" \
  || fail "2b. re-run duplicated the .zskills/ line"

# ── 3. Gitignore STOP paths: verification failure blocks the lock ──────────
# (a) Not a git repo -> check-ignore cannot verify -> STOP, no markers.
P="$(new_proj gi-nogit nogit)"
run_init "$P" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && pass "3a. non-git project: gitignore verify STOPs init (rc=$rc)" \
  || fail "3a. non-git project did not STOP"
! zskills_init_done_present "$P" \
  && pass "3b. STOP wrote NO init-done (lock-LAST honored)" \
  || fail "3b. init-done written despite STOP"
[ ! -e "$P/$ZSKILLS_SETUP_CONFIRMED_REL" ] \
  && pass "3c. STOP wrote NO setup-confirmed" \
  || fail "3c. setup-confirmed written despite STOP"

# (b) Negative-override that the idempotent append cannot cure (read-only
# .gitignore carrying `.zskills/` + `!.zskills/`) -> STOP. Last-match-wins
# means a WRITABLE .gitignore is self-healed by the append (also asserted).
if [ "$(id -u)" != 0 ]; then
  P="$(new_proj gi-override)"
  printf '%s\n' '.zskills/' '!.zskills/' > "$P/.gitignore"
  chmod 444 "$P/.gitignore"
  run_init "$P" >/dev/null 2>&1; rc=$?
  chmod 644 "$P/.gitignore"
  [ "$rc" -ne 0 ] && pass "3d. uncurable negative-override (!.zskills/) STOPs init" \
    || fail "3d. negative-override did not STOP init"
  ! zskills_init_done_present "$P" \
    && pass "3e. override STOP wrote no init-done" \
    || fail "3e. init-done written despite override STOP"
  # Ordering oracle: the STOP happened BEFORE any other init write — even
  # with the interview set to accept, no config was seeded.
  P="$(new_proj gi-order)"
  printf '%s\n' '.zskills/' '!.zskills/' > "$P/.gitignore"
  chmod 444 "$P/.gitignore"
  ZSINIT_INTERVIEW=accept run_init "$P" >/dev/null 2>&1; rc=$?
  chmod 644 "$P/.gitignore"
  if [ "$rc" -ne 0 ] && [ ! -f "$P/.claude/zskills-config.json" ] \
     && [ ! -e "$P/$ZSKILLS_SETUP_CONFIRMED_REL" ]; then
    pass "3f. ordering oracle: gitignore verified BEFORE any other write (no config, no markers on STOP)"
  else
    fail "3f. a write preceded the gitignore verification (rc=$rc)"
  fi
else
  pass "3d. (skipped as root: chmod 444 cannot block writes)"
  pass "3e. (skipped as root)"
  pass "3f. (skipped as root)"
fi
# Writable override fixture: the append self-heals (last match wins) — the
# documented idempotent-append behavior, not a STOP.
P="$(new_proj gi-selfheal)"
printf '%s\n' '.zskills/' '!.zskills/' > "$P/.gitignore"
run_init "$P" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && git -C "$P" check-ignore -q .zskills/probe; then
  pass "3g. writable negative-override is self-healed by the append (last match wins)"
else
  fail "3g. self-heal failed: rc=$rc"
fi

# ── 4. A3 interview: accept-path seed shape (ports materialise 13/13b/13c/13d/19/20)
P="$(new_proj seed-accept)"
ZSINIT_INTERVIEW=accept run_init "$P" >/dev/null 2>&1
CFG="$P/.claude/zskills-config.json"
[ -f "$CFG" ] && pass "4a. accept: config seeded" || fail "4a. accept: config NOT seeded"
if [ -f "$CFG" ]; then
  [ "$(cfg_field "$CFG" 'd["execution"]["landing"]')" = direct ] \
    && [ "$(cfg_field "$CFG" 'd["execution"]["main_protected"]')" = False ] \
    && [ "$(cfg_field "$CFG" 'd["project_name"]')" = seed-accept ] \
    && pass "4b. seed is the casual default (landing=direct, main_protected=false, project_name)" \
    || fail "4b. seed wrong: landing=$(cfg_field "$CFG" 'd["execution"]["landing"]') prot=$(cfg_field "$CFG" 'd["execution"]["main_protected"]') name=$(cfg_field "$CFG" 'd["project_name"]')"
  [ "$(cfg_field "$CFG" 'd["output"]["plans_dir"]')" = docs/plans ] \
    && [ "$(cfg_field "$CFG" 'd["output"]["issues_dir"]')" = docs/issues ] \
    && [ "$(cfg_field "$CFG" 'd["output"]["reports_dir"]')" = docs/reports ] \
    && pass "4c. seed output block = docs/{plans,issues,reports}" \
    || fail "4c. seed output block wrong"
  [ "$(cfg_field "$CFG" 'd.get("agents",{}).get("min_model","")')" = auto ] \
    && pass "4d. seed carries agents.min_model=auto (#1136)" \
    || fail "4d. agents.min_model wrong"
  [ -z "$(cfg_field "$CFG" 'd["commit"]["co_author"]')" ] \
    && pass "4e. seed commit.co_author empty (#1069)" \
    || fail "4e. co_author not empty"
  [ "$(cfg_field "$CFG" 'd.get("zskills_version","")')" = "$EXPECTED_VER" ] \
    && pass "4f. zskills_version stamped = $EXPECTED_VER (F.5 reuse, #1137)" \
    || fail "4f. zskills_version wrong: $(cfg_field "$CFG" 'd.get("zskills_version","")')"
  # Seed values ≡ canonical zskills-defaults.json (derived, never re-typed).
  SEED_OK=$("$PYTHON" - "$CFG" "$REPO_ROOT/skills/update-zskills/scripts/zskills-defaults.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
defaults = json.load(open(sys.argv[2]))
defaults.pop("_comment", None)
for k in ("$schema", "project_name", "zskills_version"):
    cfg.pop(k, None)
print("ok" if cfg == defaults else "bad")
PY
)
  [ "$SEED_OK" = ok ] \
    && pass "4g. seed value-bearing keys ≡ canonical zskills-defaults.json" \
    || fail "4g. seed drifted from zskills-defaults.json"
fi
cmp -s "$P/.claude/zskills-config.schema.json" "$REPO_ROOT/config/zskills-config.schema.json" \
  && pass "4h. schema sibling copied (byte-equal to repo source)" \
  || fail "4h. schema sibling missing or differs"

# ── 5. A3 decline + never-clobber ───────────────────────────────────────────
P="$(new_proj seed-decline)"
ZSINIT_INTERVIEW=decline run_init "$P" >/dev/null 2>&1
[ ! -f "$P/.claude/zskills-config.json" ] && [ ! -f "$P/.claude/zskills-config.schema.json" ] \
  && pass "5a. decline: no config, no schema written" \
  || fail "5a. decline wrote config/schema"
zskills_init_done_present "$P" \
  && pass "5b. decline still completes init (markers written)" \
  || fail "5b. decline blocked init"

# Never-clobber: pre-existing config preserved byte-identical through init.
P="$(new_proj keep-config)"
mkdir -p "$P/.claude"
cat > "$P/.claude/zskills-config.json" <<'KEEPCFG'
{
  "$schema": "./zskills-config.schema.json",
  "project_name": "my-existing-project",
  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "feat/"
  }
}
KEEPCFG
cp "$P/.claude/zskills-config.json" "$WORK_BASE/keep-config.before"
ZSINIT_INTERVIEW=accept run_init "$P" >/dev/null 2>&1
cmp -s "$P/.claude/zskills-config.json" "$WORK_BASE/keep-config.before" \
  && pass "5c. existing config NEVER clobbered (byte-identical through init)" \
  || fail "5c. existing config was modified by init"

# ── 6. A1.5(a) — sentinelled-artifact removal ───────────────────────────────
P="$(new_proj cleanup-sentinel)"
for rel in "${ZSKILLS_LEGACY_MATERIALISED_PATHS[@]}"; do
  write_legacy_artifact "$P" "$rel"
done
OUT="$(run_init "$P" 2>/dev/null)"
ALL_GONE=1
for rel in "${ZSKILLS_LEGACY_MATERIALISED_PATHS[@]}"; do
  [ -e "$P/$rel" ] && ALL_GONE=0
done
[ "$ALL_GONE" -eq 1 ] \
  && pass "6a. all ${#ZSKILLS_LEGACY_MATERIALISED_PATHS[@]} sentinelled legacy artifacts removed" \
  || fail "6a. sentinelled artifact(s) survived cleanup"
REMOVED_N="$(printf '%s\n' "$OUT" | grep -c '^removed: ' || true)"
printf '%s\n' "$OUT" | grep -q '^removed: ' \
  && pass "6b. removals reported for the summary (lines=$REMOVED_N)" \
  || fail "6b. no removal report emitted"

# Un-sentinelled (user-owned) files at the same paths are NEVER removed.
P="$(new_proj cleanup-userowned)"
for rel in "${ZSKILLS_LEGACY_MATERIALISED_PATHS[@]}"; do
  mkdir -p "$P/$(dirname "$rel")"
  printf '%s\n' 'user-authored content, no sentinel' > "$P/$rel"
done
run_init "$P" >/dev/null 2>&1
ALL_KEPT=1
for rel in "${ZSKILLS_LEGACY_MATERIALISED_PATHS[@]}"; do
  [ -f "$P/$rel" ] || ALL_KEPT=0
done
[ "$ALL_KEPT" -eq 1 ] \
  && pass "6c. un-sentinelled (user-owned) files at the same paths never removed" \
  || fail "6c. a user-owned file was removed"

# Update arm runs A1.5 too: sentinelled artifact + init-done present.
P="$(new_proj cleanup-update-arm)"
run_init "$P" >/dev/null 2>&1   # initialise first
write_legacy_artifact "$P" "${ZSKILLS_LEGACY_MATERIALISED_PATHS[0]}"
OUT="$(run_init "$P" 2>/dev/null)"
if printf '%s\n' "$OUT" | grep -q '^arm: update$' \
   && [ ! -e "$P/${ZSKILLS_LEGACY_MATERIALISED_PATHS[0]}" ]; then
  pass "6d. A1.5 cleanup runs on the UPDATE arm too"
else
  fail "6d. update arm did not clean residue (out: $OUT)"
fi

# ── 7. A1.5(b) — seeded-config cure case family ─────────────────────────────
# (accept) config+schema+notice all deleted; A3 does NOT re-offer this run.
P="$(new_proj cure-accept)"
write_legacy_seeded_config "$P"
OUT="$(ZSINIT_CURE=accept ZSINIT_INTERVIEW=accept run_init "$P" 2>/dev/null)"
printf '%s\n' "$OUT" | grep -q '^seed-offer: 1$' \
  && pass "7a. untouched seed + notice -> removal offered" \
  || fail "7a. offer not fired (out: $OUT)"
if [ ! -f "$P/.claude/zskills-config.json" ] && [ ! -f "$P/.claude/zskills-config.schema.json" ] \
   && ! zskills_legacy_seed_notice_present "$P"; then
  pass "7b. accept: config + schema + notice deleted"
else
  fail "7b. accept left residue behind"
fi
[ ! -f "$P/.claude/zskills-config.json" ] \
  && pass "7c. A1.5-removed config NOT re-offered/re-seeded the same run (zero-config choice respected)" \
  || fail "7c. config re-seeded in the same run despite accepted removal"
zskills_init_done_present "$P" \
  && pass "7d. cure-accept init still completes (markers written)" \
  || fail "7d. init did not complete after cure"

# (decline) config kept, notice consumed.
P="$(new_proj cure-decline)"
write_legacy_seeded_config "$P"
OUT="$(ZSINIT_CURE=decline run_init "$P" 2>/dev/null)"
printf '%s\n' "$OUT" | grep -q '^seed-offer: 1$' \
  && pass "7e. decline fixture: offer fired" \
  || fail "7e. offer not fired"
if [ -f "$P/.claude/zskills-config.json" ] && ! zskills_legacy_seed_notice_present "$P"; then
  pass "7f. decline: config KEPT as user-owned; notice consumed anyway"
else
  fail "7f. decline mishandled (config present: $(test -f "$P/.claude/zskills-config.json" && echo yes || echo no))"
fi
# Notice consumed exactly once: a second run must NOT re-offer.
OUT="$(ZSINIT_CURE=accept run_init "$P" 2>/dev/null)"
if printf '%s\n' "$OUT" | grep -q '^seed-offer: 0$' && [ -f "$P/.claude/zskills-config.json" ]; then
  pass "7g. notice consumed exactly once — offer never repeats (W6.3 no-nag)"
else
  fail "7g. offer repeated after the notice was consumed"
fi

# (shape-mismatch) customized config + notice: offer NOT fired; config kept;
# notice still consumed.
P="$(new_proj cure-mismatch)"
write_legacy_seeded_config "$P"
"$PYTHON" - "$P/.claude/zskills-config.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
cfg["testing"]["unit_cmd"] = "make test"   # the user customized the seed
with open(sys.argv[1], "w") as f:
    json.dump(cfg, f, indent=2)
PY
OUT="$(ZSINIT_CURE=accept run_init "$P" 2>/dev/null)"
if printf '%s\n' "$OUT" | grep -q '^seed-offer: 0$' \
   && [ -f "$P/.claude/zskills-config.json" ] \
   && ! zskills_legacy_seed_notice_present "$P"; then
  pass "7h. shape-mismatch (customized): no offer, config kept, notice consumed"
else
  fail "7h. shape-mismatch mishandled (out: $OUT)"
fi

# (anti-#1132-mask) a seed stamped with a FOREIGN zskills_version and an
# arbitrary project_name must STILL match — pins the excluded-keys spec
# ($schema/project_name/zskills_version are dynamic, not value-bearing).
P="$(new_proj cure-foreign-ver)"
write_legacy_seeded_config "$P" "9999.99.9" "completely-unrelated-name"
OUT="$(ZSINIT_CURE=decline run_init "$P" 2>/dev/null)"
printf '%s\n' "$OUT" | grep -q '^seed-offer: 1$' \
  && pass "7i. anti-mask: FOREIGN zskills_version + arbitrary project_name still matches the frozen seed shape" \
  || fail "7i. excluded-keys comparison spec broken — foreign-stamped untouched seed did not match"

# ── 8. Atomicity, 0-byte heal, abort-mid-init, lock-LAST ────────────────────
# (a) 0-byte init-done is a partial leftover -> NOT initialised -> init arm
#     re-runs and heals it (#1079).
P="$(new_proj heal-0byte)"
mkdir -p "$P/$(dirname "$ZSKILLS_INIT_DONE_REL")"
: > "$P/$ZSKILLS_INIT_DONE_REL"
OUT="$(run_init "$P" 2>/dev/null)"
if printf '%s\n' "$OUT" | grep -q '^arm: init$' && zskills_init_done_present "$P" \
   && grep -q '^version: ' "$P/$ZSKILLS_INIT_DONE_REL"; then
  pass "8a. 0-byte init-done treated as NOT initialised and healed by re-init (#1079)"
else
  fail "8a. 0-byte init-done not healed (out: $OUT)"
fi

# (b) abort between A2 and A7: no markers, no tmp leftovers, re-run succeeds.
P="$(new_proj abort-mid)"
ZSINIT_ABORT_AFTER_A2=1 run_init "$P" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 99 ] || fail "8b-pre. abort simulation rc=$rc (expected 99)"
if ! zskills_init_done_present "$P" && [ ! -e "$P/$ZSKILLS_SETUP_CONFIRMED_REL" ]; then
  pass "8b. abort-mid-init leaves NO init-done and NO setup-confirmed"
else
  fail "8b. abort leaked a marker"
fi
LEFTOVER="$(find "$P/.zskills" -name '*.zskills-tmp.*' 2>/dev/null | wc -l)"
[ "$LEFTOVER" -eq 0 ] \
  && pass "8c. abort leaves no partial tmp poison (re-runnable)" \
  || fail "8c. $LEFTOVER tmp leftovers found"
run_init "$P" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && zskills_init_done_present "$P" \
  && pass "8d. re-run after abort completes cleanly" \
  || fail "8d. re-run after abort failed (rc=$rc)"

# (c) lock-LAST ordering: shim `mv` to fail ONLY on the init-done rename.
#     setup-confirmed must already exist (written FIRST), init-done absent,
#     and the writer must report failure (re-runnable, no lock claimed).
P="$(new_proj lock-last)"
SHIM="$WORK_BASE/mv-shim"
mkdir -p "$SHIM"
cat > "$SHIM/mv" <<SHIMEOF
#!/usr/bin/env bash
case "\$*" in
  *init-done*) exit 1 ;;
esac
exec /bin/mv "\$@"
SHIMEOF
chmod +x "$SHIM/mv"
ORDER_OUT="$(PATH="$SHIM:$PATH" bash -c '
  . "'"$INIT_STATE"'"
  zskills_write_init_markers "'"$P"'" "1.2.3"; echo "writer-rc=$?"
')"
if printf '%s\n' "$ORDER_OUT" | grep -q '^writer-rc=1$' \
   && [ -s "$P/$ZSKILLS_SETUP_CONFIRMED_REL" ] \
   && ! zskills_init_done_present "$P"; then
  pass "8e. lock-LAST: setup-confirmed written FIRST; failed init-done write claims no lock"
else
  fail "8e. lock-LAST ordering broken ($ORDER_OUT)"
fi

# ── 9. A6 HARD GATE (Phase 6b): a failing verify-install BLOCKS the lock ────
# (Intended behavior re-spec of the Phase 6a interim: the old 9a asserted
# report-only and named this exact flip as Phase 6b's.)
P="$(new_proj verify-hardgate)"
ZSINIT_VERIFY_CMD=false run_init "$P" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ] && ! zskills_init_done_present "$P" \
   && [ ! -e "$P/$ZSKILLS_SETUP_CONFIRMED_REL" ]; then
  pass "9a. failing verify-install BLOCKS the init-done write (A6 hard gate — no markers, lock-LAST)"
else
  fail "9a. hard gate broken: rc=$rc init-done=$(zskills_init_done_present "$P" && echo yes || echo no)"
fi
# Re-runnable: the same project completes cleanly once verify passes.
run_init "$P" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && zskills_init_done_present "$P"; then
  pass "9b. re-run after a verify FAIL completes cleanly (consumer fixes, re-runs)"
else
  fail "9b. re-run after verify FAIL did not complete (rc=$rc)"
fi
# The update arm gates too: a verify FAIL stops before the version refresh.
P="$(new_proj verify-update-gate)"
run_init "$P" >/dev/null 2>&1
"$PYTHON" - "$P/$ZSKILLS_INIT_DONE_REL" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    f.write("version: 0.0.1\ndate: 2020-01-01T00:00:00+00:00\n")
PY
ZSINIT_VERIFY_CMD=false run_init "$P" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ] && grep -q '^version: 0.0.1$' "$P/$ZSKILLS_INIT_DONE_REL"; then
  pass "9c. update arm: verify FAIL stops the run BEFORE the version-line refresh"
else
  fail "9c. update-arm gate broken (rc=$rc, version line: $(head -1 "$P/$ZSKILLS_INIT_DONE_REL"))"
fi

# ── 10. Update arm: version-line refresh + conditional config offer ────────
P="$(new_proj update-refresh)"
run_init "$P" >/dev/null 2>&1
# Simulate an older install: rewrite init-done with a stale version.
"$PYTHON" - "$P/$ZSKILLS_INIT_DONE_REL" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    f.write("version: 0.0.1\ndate: 2020-01-01T00:00:00+00:00\n")
PY
OUT="$(run_init "$P" 2>/dev/null)"
if printf '%s\n' "$OUT" | grep -q '^arm: update$' \
   && grep -q "^version: $EXPECTED_VER\$" "$P/$ZSKILLS_INIT_DONE_REL"; then
  pass "10a. update arm refreshes the init-done version line ($EXPECTED_VER)"
else
  fail "10a. version line not refreshed: $(head -1 "$P/$ZSKILLS_INIT_DONE_REL")"
fi
# Conditional config offer on the update arm (no config, none removed this
# run, interactive accept) -> seeded.
[ ! -f "$P/.claude/zskills-config.json" ] || fail "10b-pre. fixture unexpectedly has a config"
ZSINIT_INTERVIEW=accept run_init "$P" >/dev/null 2>&1
[ -f "$P/.claude/zskills-config.json" ] \
  && pass "10b. update arm offers config creation when none exists (A3 promise kept)" \
  || fail "10b. update arm did not seed on accept"

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
