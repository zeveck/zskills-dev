#!/usr/bin/env bash
# tests/test-sessionstart-greeting.sh
#
# The SessionStart setup greeting (#1119, reworked by INSTALL_REDESIGN
# Phase 7 onto the slim hooks/session-start-greeting.sh — the retired
# materialiser's greeting tail is gone with the materialiser). The hook is
# READ-ONLY (zero project writes) and emits a user-visible `systemMessage`
# JSON on STDOUT nudging an un-initialised plugin consumer toward the
# one-time `/zs:update-zskills` init. It fires on every SessionStart where
# the legacy mirror is ABSENT and the `.zskills/init-done` marker is ABSENT,
# and goes silent permanently once init writes the marker.
#
# Critical contract points:
#   - stdout carries ONLY the greeting JSON (nothing else is ever printed).
#   - ZERO WRITES: the project tree is byte-untouched by a greeting run.
#   - The init-done path comes from init-state.sh's writer (#1132 single
#     path definition) — fixtures never re-type the marker path.
#
# Cases:
#   (a) fresh project, no init-done            -> valid JSON with a non-empty
#       systemMessage carrying the /zs:update-zskills nudge on stdout.
#   (a2) the greeting run wrote NOTHING into the project (read-only).
#   (b) init-done present (via the init-state.sh writer) -> no stdout.
#   (c) legacy mirror present                  -> no stdout (silent).
#   (d) mirror present + plugin loaded (dual)  -> no stdout (silent).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

GREET="hooks/session-start-greeting.sh"

# Resolve a working Python 3 for the JSON-shape assertions.
PY=""
for cand in "${ZSKILLS_PYTHON:-}" python3 python; do
  [ -n "$cand" ] || continue
  command -v "$cand" >/dev/null 2>&1 || continue
  if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
    PY="$(command -v "$cand")"; break
  fi
done

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# #1132 — the init-done marker is created via init-state.sh's OWN writer,
# never a re-typed path.
# shellcheck source=skills/update-zskills/scripts/init-state.sh
. "$REPO_ROOT/skills/update-zskills/scripts/init-state.sh"

# Write an update-zskills-installed (zskills-owned, anchor-named) skill
# mirror — the legacy-mirror evidence detect-install-state.sh keys on.
write_mirror_skill() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '---' 'name: x' '---' 'body' > "$1"
}

# run_greet <proj> <stderr-path> — runs the greeting hook; stdout via the
# surrounding command substitution, stderr into the given file. The plugin
# root env var is set the way the harness sets it (BASH_SOURCE self-location
# makes it redundant, but real sessions carry it).
run_greet() {
  env CLAUDE_PROJECT_DIR="$1" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/$GREET" 2>"$2"
}

GREET_MARK="run /zs:update-zskills"

echo "=== SessionStart setup greeting (slim hook, Phase 7) ==="

# ── (a) fresh + no init-done -> greeting JSON on stdout ──────────────────────
PA="$TMP/proj_a"
mkdir -p "$PA"
SNAP_BEFORE="$(find "$PA" | sort)"
ERRA="$TMP/err_a"
OUT_A="$(run_greet "$PA" "$ERRA")"

if [ -z "$PY" ]; then
  fail "a. no Python 3 available to validate greeting JSON"
else
  A_RESULT="$(ZS_OUT="$OUT_A" GREET_MARK="$GREET_MARK" "$PY" - <<'PYCHK'
import os, json
raw = os.environ.get("ZS_OUT", "")
try:
    d = json.loads(raw)
except Exception as e:
    print("NOTJSON:%s" % e); raise SystemExit(0)
sm = d.get("systemMessage")
if not isinstance(sm, str) or not sm.strip():
    print("NOSYSMSG"); raise SystemExit(0)
if os.environ["GREET_MARK"] not in sm:
    print("MARKMISSING"); raise SystemExit(0)
print("OK")
PYCHK
)"
  case "$A_RESULT" in
    OK)
      pass "a. fresh + no init-done: valid JSON with non-empty systemMessage carrying the /zs:update-zskills nudge on stdout" ;;
    NOTJSON:*)
      fail "a. greeting stdout is not valid JSON ($A_RESULT)"
      printf '      stdout: %s\n' "$OUT_A" ;;
    NOSYSMSG)
      fail "a. greeting JSON has no non-empty top-level systemMessage"
      printf '      stdout: %s\n' "$OUT_A" ;;
    MARKMISSING)
      fail "a. systemMessage present but missing the nudge text (\"$GREET_MARK\")"
      printf '      stdout: %s\n' "$OUT_A" ;;
    *)
      fail "a. unexpected JSON-check result: $A_RESULT"
      printf '      stdout: %s\n' "$OUT_A" ;;
  esac
fi

# ── (a2) zero writes: the project tree is byte-untouched by the greeting ────
SNAP_AFTER="$(find "$PA" | sort)"
if [ "$SNAP_BEFORE" = "$SNAP_AFTER" ]; then
  pass "a2. greeting run wrote NOTHING into the project (read-only)"
else
  fail "a2. greeting run created files:"
  diff <(printf '%s\n' "$SNAP_BEFORE") <(printf '%s\n' "$SNAP_AFTER") | sed 's/^/      /'
fi

# ── (b) init-done present -> silent permanently ──────────────────────────────
# Re-run against the SAME $PA after writing the markers via init-state.sh's
# OWN lock-LAST writer (#1132 — never a re-typed path).
zskills_write_init_markers "$PA" "test-version" \
  || fail "b-pre. zskills_write_init_markers failed on the fixture"
ERRB="$TMP/err_b"
OUT_B="$(run_greet "$PA" "$ERRB")"
if [ -z "$OUT_B" ]; then
  pass "b. init-done present: no greeting on stdout (silent permanently)"
else
  fail "b. init-done present: greeting still emitted"
  printf '      stdout: %s\n' "$OUT_B"
fi

# ── (c) legacy mirror present -> silent ──────────────────────────────────────
PC="$TMP/proj_c"
mkdir -p "$PC"
write_mirror_skill "$PC/.claude/skills/update-zskills/SKILL.md"
ERRC="$TMP/err_c"
OUT_C="$(run_greet "$PC" "$ERRC")"
if [ -z "$OUT_C" ]; then
  pass "c. legacy mirror present: no greeting on stdout (mirrored repo is initialised by definition)"
else
  fail "c. legacy mirror present: greeting unexpectedly emitted"
  printf '      stdout: %s\n' "$OUT_C"
fi

# ── (d) mirror present + plugin loaded (the dogfood/dual shape) -> silent ────
# Same mirror evidence; CLAUDE_PLUGIN_ROOT is set by run_greet, so whichever
# lane detect resolves (update-zskills or dual), the greeting must stay
# silent — assert silence, not the exact lane.
PD="$TMP/proj_d"
mkdir -p "$PD"
write_mirror_skill "$PD/.claude/skills/update-zskills/SKILL.md"
write_mirror_skill "$PD/.claude/skills/run-plan/SKILL.md"
ERRD="$TMP/err_d"
OUT_D="$(run_greet "$PD" "$ERRD")"
if [ -z "$OUT_D" ]; then
  pass "d. mirror + plugin loaded: no greeting on stdout (silent)"
else
  fail "d. mirror + plugin loaded: greeting unexpectedly emitted"
  printf '      stdout: %s\n' "$OUT_D"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
