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
  local PERSONAL="${ZSINIT_PERSONAL:-skip}"   # personal A3.5: skip|accept|decline
  local CURE="${ZSINIT_CURE:-decline}"
  local VERIFY_CMD="${ZSINIT_VERIFY_CMD:-true}"
  local ZS_INIT_VERSION="$EXPECTED_VER"
  # Personal config lives under $HOME — sandbox it so the oracle never
  # touches the real home dir (mirrors the SKILL.md A3.5 fence, which keys
  # on $HOME). Each call may pin its own ZSINIT_HOME (a shared TMP_HOME
  # exercises the DA14 cross-project property).
  local HOME="${ZSINIT_HOME:-$PROJ/home}"
  mkdir -p "$HOME/.claude"

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
    # Update arm: conditional config offer(s) + verify + version-line refresh.
    if [ ! -f "$PROJ/.claude/zskills-config.json" ] \
       && [ "$ZS_REMOVED_CONFIG_THIS_RUN" = 0 ] \
       && ! zskills_config_declined project "$PROJ"; then
      if [ "$INTERVIEW" = accept ]; then
        oracle_seed_config "$PROJ" "$ZS_INIT_VERSION" || return 1
      elif [ "$INTERVIEW" = decline ]; then
        zskills_write_config_declined project "$PROJ" || return 1
      fi
    fi
    # A3.5 personal offer re-runs on the update arm too (self-gating).
    oracle_personal_config "$PERSONAL" || return 1
    # A6 HARD gate (Phase 6b): a verify FAIL stops the run before the
    # version-line refresh.
    $VERIFY_CMD || {
      echo "STOP: verify-install reported a FAIL" >&2
      return 1
    }
    # Capture the RECORDED version BEFORE refreshing it (for the nudge).
    local ZS_RECORDED_VER
    ZS_RECORDED_VER="$(sed -n 's/^version: //p' \
      "$PROJ/$ZSKILLS_INIT_DONE_REL" 2>/dev/null | head -n 1)"
    if [ -z "$ZS_RECORDED_VER" ] && [ -f "$PROJ/.claude/zskills-config.json" ]; then
      ZS_RECORDED_VER="$(sed -n 's/.*"zskills_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$PROJ/.claude/zskills-config.json" 2>/dev/null | head -n 1)"
    fi
    zskills_write_init_markers "$PROJ" "$ZS_INIT_VERSION" || return 1
    oracle_config_news_nudge "$ZS_RECORDED_VER"
    echo "arm: update"
    return 0
  fi
  echo "arm: init"

  # ── A2 — gitignore-first (mirrors the SKILL.md fence) ──
  local GI="$PROJ/.gitignore" zs_gi_match
  [ -f "$GI" ] || touch "$GI"
  # Non-git duplicate guard (#1150 NIT): in a non-git dir check-ignore
  # cannot run at all — grep-guard the append so re-runs before the STOP
  # don't stack duplicates. In a git repo the append stays UNCONDITIONAL
  # on not-ignored (last-match-wins self-heal, case 3g).
  if ! git -C "$PROJ" check-ignore -q .zskills/probe 2>/dev/null; then
    if git -C "$PROJ" rev-parse --git-dir >/dev/null 2>&1 \
       || ! grep -qxF ".zskills/" "$GI" 2>/dev/null; then
      echo ".zskills/" >> "$GI" 2>/dev/null
    fi
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

  # ── A2.5 — one-shot main-root marker migrate (Phase 8 root-turd
  # consolidation; mirrors the SKILL.md fence). Main root ONLY — never
  # walks sibling worktrees. Never-clobber: when the new path already
  # exists, both files are left untouched (dual-read prefers the new path).
  if [ -f "$PROJ/.zskills-tracked" ] && [ ! -e "$PROJ/.zskills/tracked" ]; then
    mkdir -p "$PROJ/.zskills"
    mv "$PROJ/.zskills-tracked" "$PROJ/.zskills/tracked" \
      || echo "WARN: could not migrate .zskills-tracked to .zskills/tracked (non-fatal; hooks dual-read the old path)" >&2
  fi

  # ── A3 — optional config interview (init arm) ──
  # The accept fence runs ONLY on the "no config exists" interview path —
  # a pre-existing config is review/keep (never clobbered, never restamped).
  # A decline records the PROJECT decline marker so the update arm stops
  # re-asking.
  if [ ! -f "$PROJ/.claude/zskills-config.json" ] \
     && [ "$ZS_REMOVED_CONFIG_THIS_RUN" = 0 ] \
     && ! zskills_config_declined project "$PROJ"; then
    if [ "$INTERVIEW" = accept ]; then
      oracle_seed_config "$PROJ" "$ZS_INIT_VERSION" || return 1
    elif [ "$INTERVIEW" = decline ]; then
      zskills_write_config_declined project "$PROJ" || return 1
    fi
  fi
  # skip / existing-config / removed-this-run / already-declined: write nothing.

  # ── A3.5 — optional PERSONAL (user-tier) config offer (#1160) ──
  oracle_personal_config "$PERSONAL" || return 1

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

# Mirrors the SKILL.md A3.5 PERSONAL-config offer fence (#1160). $HOME is the
# sandbox set by run_init. accept → EMPTY scaffold (never seeded) +
# refresh-on-update schema sibling, both never-clobber on the config; decline
# → user-scope decline marker. Self-gates: the offer fires only when the user
# config is ABSENT and no personal decline marker exists.
oracle_personal_config() {
  local CHOICE="$1"
  local ZS_USER_DIR="$HOME/.claude"
  local ZS_USER_CONFIG="$ZS_USER_DIR/zskills-config.json"
  local ZS_USER_SCHEMA="$ZS_USER_DIR/zskills-config.schema.json"
  # Self-gate: existing user file OR a prior decline suppresses the offer.
  if [ -f "$ZS_USER_CONFIG" ] || zskills_config_declined personal "$HOME"; then
    return 0
  fi
  case "$CHOICE" in
    accept)
      mkdir -p "$ZS_USER_DIR"
      if [ ! -f "$ZS_USER_CONFIG" ]; then   # never-clobber
        local zs_user_cfg_tmp="$ZS_USER_CONFIG.zskills-tmp.$$"
        cat > "$zs_user_cfg_tmp" <<'PERSONALCFG'
{
  "$schema": "./zskills-config.schema.json",
  "_comment": "zskills personal config (v2 contract): unset keys track shipped defaults; workflow keys (execution.landing, execution.branch_prefix, execution.max_concurrent_worktrees, plus the cascadable string keys) apply wherever the project config does not override them; safety keys (execution.main_protected, agents.min_model) are raise-only floors — they can raise a project's protection, never lower it."
}
PERSONALCFG
        [ -s "$zs_user_cfg_tmp" ] && mv "$zs_user_cfg_tmp" "$ZS_USER_CONFIG" \
          || rm -f "$zs_user_cfg_tmp"
      fi
      # Schema sibling — refresh-on-update (rewrite when it differs).
      local ZS_USER_SCHEMA_SRC="$REPO_ROOT/config/zskills-config.schema.json"
      if [ -f "$ZS_USER_SCHEMA_SRC" ] \
         && ! cmp -s "$ZS_USER_SCHEMA_SRC" "$ZS_USER_SCHEMA" 2>/dev/null; then
        local zs_user_schema_tmp="$ZS_USER_SCHEMA.zskills-tmp.$$"
        cp "$ZS_USER_SCHEMA_SRC" "$zs_user_schema_tmp" \
          && mv "$zs_user_schema_tmp" "$ZS_USER_SCHEMA" \
          || rm -f "$zs_user_schema_tmp"
      fi
      ;;
    decline)
      zskills_write_config_declined personal "$HOME" || return 1
      ;;
    skip|*) : ;;
  esac
  return 0
}

# Mirrors the SKILL.md update-arm new-config-surface nudge (#1160). Emits one
# `news:` trace line per TSV key whose introduced-version is NEWER than the
# recorded version (NUMERIC dot-segment compare). Empty recorded → silent.
oracle_config_news_nudge() {
  local recorded="$1"
  local tsv="$REPO_ROOT/skills/update-zskills/references/config-key-versions.tsv"
  [ -n "$recorded" ] && [ -f "$tsv" ] && [ -n "$PYTHON" ] || return 0
  local zs_key zs_introduced zs_default zs_where
  while IFS=$'\t' read -r zs_key zs_introduced zs_default zs_where; do
    case "$zs_key" in ''|'#'*) continue ;; esac
    [ -n "$zs_introduced" ] || continue
    if "$PYTHON" -c 'import sys; a,b=(tuple(int(x) for x in v.split("+")[0].split(".")) for v in sys.argv[1:3]); sys.exit(0 if a>b else 1)' \
         "$zs_introduced" "$recorded" 2>/dev/null; then
      printf 'news: %s — default %s — set in %s\n' "$zs_key" "${zs_default:-(unset)}" "$zs_where"
    fi
  done < "$tsv"
  return 0
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

# ── 11. A2.5 — one-shot main-root marker migrate (Phase 8) ─────────────────
# 11a. Legacy root .zskills-tracked at the MAIN root migrates to
# .zskills/tracked during init (between A2 and the lock write).
P="$(new_proj a25-migrate)"
printf 'run-plan.legacy-pipeline\n' > "$P/.zskills-tracked"
run_init "$P" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$P/.zskills-tracked" ] \
   && [ -f "$P/.zskills/tracked" ] \
   && grep -qx 'run-plan.legacy-pipeline' "$P/.zskills/tracked"; then
  pass "11a. A2.5 migrates root .zskills-tracked to .zskills/tracked (content intact)"
else
  fail "11a. A2.5 migrate: rc=$rc root-present=$([ -e "$P/.zskills-tracked" ] && echo yes || echo no) new-content='$(cat "$P/.zskills/tracked" 2>/dev/null)'"
fi

# 11b. Never-clobber: when .zskills/tracked already exists, BOTH files are
# left untouched (dual-read prefers the new path; the stale root file is
# inert).
P="$(new_proj a25-noclobber)"
mkdir -p "$P/.zskills"
printf 'run-plan.new-pipeline\n' > "$P/.zskills/tracked"
printf 'run-plan.stale-pipeline\n' > "$P/.zskills-tracked"
run_init "$P" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -qx 'run-plan.new-pipeline' "$P/.zskills/tracked" \
   && [ -f "$P/.zskills-tracked" ] \
   && grep -qx 'run-plan.stale-pipeline' "$P/.zskills-tracked"; then
  pass "11b. A2.5 never-clobber: existing .zskills/tracked wins; both files untouched"
else
  fail "11b. A2.5 never-clobber violated: new='$(cat "$P/.zskills/tracked" 2>/dev/null)' old='$(cat "$P/.zskills-tracked" 2>/dev/null)'"
fi

# 11c. No legacy marker → no-op (nothing created at either path).
P="$(new_proj a25-absent)"
run_init "$P" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$P/.zskills/tracked" ] && [ ! -e "$P/.zskills-tracked" ]; then
  pass "11c. A2.5 no-op when no legacy marker exists (no marker fabricated)"
else
  fail "11c. A2.5 fabricated a marker: new=$([ -e "$P/.zskills/tracked" ] && echo yes || echo no) old=$([ -e "$P/.zskills-tracked" ] && echo yes || echo no)"
fi

# ── 12. Writer empty-version clobber guard (#1150 item 3) ──────────────────
# When resolve-repo-version.sh fails the update arm calls the writer with an
# EMPTY version. The writer must never downgrade a good `version:` record.
# (a) empty new version + prior good version ⇒ preserved.
P="$(new_proj ver-guard-preserve)"
zskills_write_init_markers "$P" "2026.06.0" || fail "12a-pre. seed write failed"
zskills_write_init_markers "$P" ""
if grep -q '^version: 2026\.06\.0$' "$P/$ZSKILLS_INIT_DONE_REL"; then
  pass "12a. empty resolve + prior good version ⇒ old value preserved"
else
  fail "12a. good version clobbered: $(head -1 "$P/$ZSKILLS_INIT_DONE_REL")"
fi
# (b) empty new version + no prior marker ⇒ empty version line (first-init
# behavior unchanged).
P="$(new_proj ver-guard-empty)"
zskills_write_init_markers "$P" ""
if grep -q '^version: $' "$P/$ZSKILLS_INIT_DONE_REL"; then
  pass "12b. empty resolve + no prior marker ⇒ empty version line (unchanged first-init behavior)"
else
  fail "12b. unexpected content: $(head -1 "$P/$ZSKILLS_INIT_DONE_REL")"
fi
# (b2) empty new version + prior EMPTY version ⇒ still empty (guard keys on
# a NON-empty prior value only).
zskills_write_init_markers "$P" ""
if grep -q '^version: $' "$P/$ZSKILLS_INIT_DONE_REL"; then
  pass "12c. empty resolve + prior empty version ⇒ stays empty (no fabrication)"
else
  fail "12c. unexpected content: $(head -1 "$P/$ZSKILLS_INIT_DONE_REL")"
fi
# (c) non-empty new version ⇒ always overwrites (the documented refresh).
P="$(new_proj ver-guard-overwrite)"
zskills_write_init_markers "$P" "0.0.1"
zskills_write_init_markers "$P" "2026.06.5"
if grep -q '^version: 2026\.06\.5$' "$P/$ZSKILLS_INIT_DONE_REL"; then
  pass "12d. non-empty new version overwrites the prior value (refresh unchanged)"
else
  fail "12d. refresh broken: $(head -1 "$P/$ZSKILLS_INIT_DONE_REL")"
fi

# ── 13. A2 non-git duplicate-append guard (#1150 NIT) ──────────────────────
# A non-git project STOPs at the A2 verify (case 3a), but each re-run used
# to append another `.zskills/` line first. The grep guard caps it at one,
# without touching the git-repo self-heal behavior (case 3g still passes).
P="$(new_proj gi-nogit-dup nogit)"
run_init "$P" >/dev/null 2>&1
run_init "$P" >/dev/null 2>&1
run_init "$P" >/dev/null 2>&1
DUP_COUNT="$(grep -cxF '.zskills/' "$P/.gitignore" 2>/dev/null)"
if [ "$DUP_COUNT" = "1" ]; then
  pass "13a. non-git re-runs append exactly one .zskills/ line (no duplicate stacking)"
else
  fail "13a. duplicate .zskills/ lines in non-git project: $DUP_COUNT"
fi

# ── 14. A3.5 PERSONAL config offer — accept path (ENFORCEMENT_V2 P6 #1160) ─
# Personal accept writes the EMPTY scaffold (never seeded) + a schema sibling,
# both under a sandboxed $HOME/.claude. The scaffold is byte-pinned to the
# exact v2-contract JSON (the freeze-trap is the empty scaffold).
EXPECTED_PERSONAL_CFG="$WORK_BASE/expected-personal-config.json"
cat > "$EXPECTED_PERSONAL_CFG" <<'PERSONALCFG'
{
  "$schema": "./zskills-config.schema.json",
  "_comment": "zskills personal config (v2 contract): unset keys track shipped defaults; workflow keys (execution.landing, execution.branch_prefix, execution.max_concurrent_worktrees, plus the cascadable string keys) apply wherever the project config does not override them; safety keys (execution.main_protected, agents.min_model) are raise-only floors — they can raise a project's protection, never lower it."
}
PERSONALCFG

P="$(new_proj personal-accept)"
H14="$WORK_BASE/home-personal-accept"
rm -rf "$H14"; mkdir -p "$H14"
ZSINIT_HOME="$H14" ZSINIT_PERSONAL=accept run_init "$P" >/dev/null 2>&1
UCFG="$H14/.claude/zskills-config.json"
USCHEMA="$H14/.claude/zskills-config.schema.json"
[ -f "$UCFG" ] && pass "14a. personal accept: ~/.claude/zskills-config.json written" \
  || fail "14a. personal accept: user config NOT written"
if [ -f "$UCFG" ]; then
  # byte-pin assertion (plan AC: "quote the scaffold byte-pin assertion")
  cmp -s "$UCFG" "$EXPECTED_PERSONAL_CFG" \
    && pass "14b. personal scaffold byte-identical to the pinned v2-contract JSON (empty — never seeded)" \
    || fail "14b. personal scaffold drifted from the pinned JSON: $(cat "$UCFG")"
  # The scaffold has NO value-bearing keys (only $schema + _comment).
  EMPTY_OK=$("$PYTHON" - "$UCFG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("ok" if set(d.keys()) == {"$schema", "_comment"} else "bad")
PY
)
  [ "$EMPTY_OK" = ok ] \
    && pass "14c. scaffold carries ONLY \$schema + _comment (no seeded values — freeze-trap avoided)" \
    || fail "14c. scaffold has unexpected keys (seeded?)"
fi
cmp -s "$USCHEMA" "$REPO_ROOT/config/zskills-config.schema.json" \
  && pass "14d. personal schema sibling copied (byte-equal to shipped schema)" \
  || fail "14d. personal schema sibling missing or differs"

# ── 15. A3.5 personal DECLINE — user-scope marker + cross-project suppress ──
# Declining the personal offer writes ~/.claude/zskills-config.declined and
# suppresses the question in EVERY project sharing that $HOME (DA14 property).
P1="$(new_proj personal-decline-1)"
H15="$WORK_BASE/home-personal-decline"
rm -rf "$H15"; mkdir -p "$H15"
ZSINIT_HOME="$H15" ZSINIT_PERSONAL=decline run_init "$P1" >/dev/null 2>&1
[ -f "$H15/.claude/zskills-config.declined" ] \
  && pass "15a. personal decline wrote the USER-scope marker (~/.claude/zskills-config.declined)" \
  || fail "15a. personal decline marker not written"
[ ! -f "$H15/.claude/zskills-config.json" ] \
  && pass "15b. personal decline wrote NO user config" \
  || fail "15b. personal decline unexpectedly wrote a user config"
# Same TMP_HOME, a SECOND scratch project with accept requested → still
# suppressed (the marker is user-global, not per-project).
P2="$(new_proj personal-decline-2)"
ZSINIT_HOME="$H15" ZSINIT_PERSONAL=accept run_init "$P2" >/dev/null 2>&1
[ ! -f "$H15/.claude/zskills-config.json" ] \
  && pass "15c. DA14: a second project sharing the same HOME does NOT re-ask (decline is user-global)" \
  || fail "15c. DA14 violated: personal offer re-fired in a second project despite the decline marker"

# ── 16. A3.5 existing-user-file + never-clobber + schema refresh ────────────
# (a) An existing user config suppresses the offer WITHOUT a marker, and is
# NEVER clobbered.
P="$(new_proj personal-existing)"
H16="$WORK_BASE/home-personal-existing"
rm -rf "$H16"; mkdir -p "$H16/.claude"
printf '{"$schema":"./zskills-config.schema.json","execution":{"landing":"pr"}}\n' \
  > "$H16/.claude/zskills-config.json"
cp "$H16/.claude/zskills-config.json" "$WORK_BASE/personal-existing.before"
ZSINIT_HOME="$H16" ZSINIT_PERSONAL=accept run_init "$P" >/dev/null 2>&1
cmp -s "$H16/.claude/zskills-config.json" "$WORK_BASE/personal-existing.before" \
  && pass "16a. existing user config NEVER clobbered by the accept path" \
  || fail "16a. existing user config was modified"
[ ! -f "$H16/.claude/zskills-config.declined" ] \
  && pass "16b. existing user file suppresses the offer WITHOUT writing a decline marker" \
  || fail "16b. an unnecessary decline marker was written"
# (b) Schema-sibling refresh (DA13): on a fresh accept (no user config yet)
# a stale sibling differing from the shipped schema is rewritten. With an
# existing user CONFIG the offer self-gates before the schema refresh, so the
# refresh is exercised on the no-config accept path.
H16b="$WORK_BASE/home-personal-refresh"
rm -rf "$H16b"; mkdir -p "$H16b/.claude"
printf 'STALE-SCHEMA\n' > "$H16b/.claude/zskills-config.schema.json"
P="$(new_proj personal-refresh)"
ZSINIT_HOME="$H16b" ZSINIT_PERSONAL=accept run_init "$P" >/dev/null 2>&1
cmp -s "$H16b/.claude/zskills-config.schema.json" "$REPO_ROOT/config/zskills-config.schema.json" \
  && pass "16c. DA13: stale schema sibling rewritten to the shipped schema on accept" \
  || fail "16c. stale schema sibling NOT refreshed"

# ── 17. PROJECT decline marker suppresses the project re-offer ──────────────
P="$(new_proj project-decline)"
ZSINIT_INTERVIEW=decline run_init "$P" >/dev/null 2>&1
[ -f "$P/$ZSKILLS_CONFIG_DECLINED_REL" ] \
  && grep -q '^project:' "$P/$ZSKILLS_CONFIG_DECLINED_REL" \
  && pass "17a. project decline wrote the gitignored .zskills/config-offer-declined marker" \
  || fail "17a. project decline marker not written"
[ ! -f "$P/.claude/zskills-config.json" ] \
  && pass "17b. project decline wrote NO config" \
  || fail "17b. project decline unexpectedly wrote a config"
# Update arm with accept requested → STILL suppressed (the project declined).
ZSINIT_INTERVIEW=accept run_init "$P" >/dev/null 2>&1
[ ! -f "$P/.claude/zskills-config.json" ] \
  && pass "17c. project re-offer suppressed on the update arm after a decline" \
  || fail "17c. update arm re-seeded despite the project decline marker"

# ── 18. New-config-surface nudge (ENFORCEMENT_V2 P6 #1160) ─────────────────
# A consumer recorded at an OLD version sees the newer keys listed; a current
# consumer sees nothing (silence, not noise).
P="$(new_proj nudge-old)"
HNUDGE="$WORK_BASE/home-nudge"
rm -rf "$HNUDGE"; mkdir -p "$HNUDGE/.claude"
# decline personal so it doesn't interfere
printf '%s\n' "(declined)" > "$HNUDGE/.claude/zskills-config.declined"
ZSINIT_HOME="$HNUDGE" run_init "$P" >/dev/null 2>&1   # initialise
# Rewrite init-done with an OLD recorded version (older than the hooks.* rows).
"$PYTHON" - "$P/$ZSKILLS_INIT_DONE_REL" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    f.write("version: 2026.06.0\ndate: 2020-01-01T00:00:00+00:00\n")
PY
OUT="$(ZSINIT_HOME="$HNUDGE" run_init "$P" 2>/dev/null)"
if printf '%s\n' "$OUT" | grep -q '^news: hooks\.main_protection ' \
   && printf '%s\n' "$OUT" | grep -q '^news: execution\.max_concurrent_worktrees '; then
  pass "18a. nudge lists keys introduced after the recorded version (hooks.* + max_concurrent_worktrees)"
else
  fail "18a. nudge did not surface the new keys (out: $(printf '%s' "$OUT" | grep '^news:' | tr '\n' '|'))"
fi
# The nudge must NOT list keys already present at the recorded version.
if printf '%s\n' "$OUT" | grep -q '^news: timezone '; then
  fail "18b. nudge wrongly listed a key the consumer already had (timezone @ 2026.06.0)"
else
  pass "18b. nudge does NOT list keys present at the recorded version (numeric compare correct)"
fi
# A consumer recorded at a version newer than every TSV row → no news section.
P="$(new_proj nudge-current)"
ZSINIT_HOME="$HNUDGE" run_init "$P" >/dev/null 2>&1
"$PYTHON" - "$P/$ZSKILLS_INIT_DONE_REL" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    f.write("version: 9999.99.9\ndate: 2020-01-01T00:00:00+00:00\n")
PY
OUT="$(ZSINIT_HOME="$HNUDGE" run_init "$P" 2>/dev/null)"
if printf '%s\n' "$OUT" | grep -q '^news: '; then
  fail "18c. up-to-date consumer wrongly got a config-news section"
else
  pass "18c. up-to-date consumer gets NO config-news section (silence, not noise)"
fi
# Numeric (not lexical) dot-segment compare: 2026.06.10 recorded must NOT
# flag a 2026.06.2-introduced key (lexical would wrongly flag it).
NUM_OK=$("$PYTHON" -c 'import sys; a,b=(tuple(int(x) for x in v.split("+")[0].split(".")) for v in ["2026.06.2","2026.06.10"]); sys.exit(0 if a>b else 1)' && echo flagged || echo silent)
[ "$NUM_OK" = silent ] \
  && pass "18d. numeric dot-segment compare: 2026.06.2 NOT newer than 2026.06.10 (lexical bug avoided)" \
  || fail "18d. version compare is lexical, not numeric"

# ── 19. TSV conformance (anti-drift + anti-vacuous) ────────────────────────
# Every leaf key in zskills-defaults.json has a TSV row; total rows >= 20.
TSV="$REPO_ROOT/skills/update-zskills/references/config-key-versions.tsv"
[ -f "$TSV" ] && pass "19a. config-key-versions.tsv present" || fail "19a. TSV missing"
TSV_ROWS="$(awk 'NF && $0 !~ /^[[:space:]]*#/' "$TSV" | wc -l | tr -d ' ')"
[ "${TSV_ROWS:-0}" -ge 20 ] \
  && pass "19b. TSV has >= 20 data rows (anti-vacuous): $TSV_ROWS" \
  || fail "19b. TSV has only $TSV_ROWS data rows (< 20)"
MISSING_KEYS="$(
  "$PYTHON" - "$REPO_ROOT/skills/update-zskills/scripts/zskills-defaults.json" "$TSV" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d.pop("_comment", None)
leaves = []
def walk(prefix, obj):
    for k, v in obj.items():
        kk = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict): walk(kk, v)
        else: leaves.append(kk)
walk("", d)
rows = set()
for line in open(sys.argv[2]):
    if line.strip() and not line.lstrip().startswith("#"):
        rows.add(line.split("\t", 1)[0].strip())
missing = [k for k in leaves if k not in rows]
print(" ".join(missing))
PY
)"
[ -z "$MISSING_KEYS" ] \
  && pass "19c. every zskills-defaults.json leaf key has a TSV row (anti-drift)" \
  || fail "19c. TSV missing rows for leaf keys: $MISSING_KEYS"

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
