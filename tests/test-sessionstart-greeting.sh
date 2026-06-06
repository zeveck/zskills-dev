#!/usr/bin/env bash
# tests/test-sessionstart-greeting.sh
#
# #1119 — the SessionStart greeting. The materialiser emits a user-visible
# `systemMessage` JSON on STDOUT nudging a fresh plugin consumer toward
# /update-zskills. It fires on every SessionStart where the seeded config
# exists AND the `.zskills/setup-confirmed` marker is ABSENT (they have not
# run /update-zskills yet), and goes silent once that marker appears.
#
# Critical contract points:
#   - stdout carries ONLY the greeting JSON (stderr stays for diagnostics).
#   - The greeting fires on the fresh|plugin flow only — the early-exit
#     update-zskills/dual lanes stay SILENT on stdout (they only nag stderr).
#
# Cases:
#   (a) fresh + no setup-confirmed marker -> valid JSON with a non-empty
#       systemMessage on stdout.
#   (b) setup-confirmed marker present    -> no stdout.
#   (c) lane == update-zskills            -> no stdout (early exit, silent).
#   (d) lane == dual                      -> no stdout (early exit, silent).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MAT="hooks/session-start-materialise.sh"

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

# base_fixture <proj> — a fresh project with a root CLAUDE_TEMPLATE.md so the
# materialiser can seed a config + render managed.md (no pre-existing .claude
# artifacts → lane=fresh).
base_fixture() {
  local p="$1"
  mkdir -p "$p"
  cp "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$p/"
}
# Write an update-zskills-installed (UN-sentinelled) skill mirror.
write_unsentinelled_skill() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '---' 'name: x' '---' 'body' > "$1"
}
write_sentinelled_hook() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '#!/usr/bin/env bash' '# zskills-materialised: 2026.05.0' 'echo hi' > "$1"
}

# run_mat <proj> <stderr-path> — runs the materialiser, captures stdout via the
# surrounding command substitution and stderr into the given file.
run_mat() {
  env CLAUDE_PROJECT_DIR="$1" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/$MAT" 2>"$2"
}

GREET_MARK="Run /update-zskills"

echo "=== SessionStart greeting (#1119) ==="

# ── (a) fresh + no setup-confirmed marker -> greeting JSON on stdout ──────────
PA="$TMP/proj_a"
base_fixture "$PA"
ERRA="$TMP/err_a"
OUT_A="$(run_mat "$PA" "$ERRA")"

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
      pass "a. fresh + no marker: valid JSON with non-empty systemMessage carrying the /update-zskills nudge on stdout" ;;
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

# ── (b) setup-confirmed marker present -> silent ─────────────────────────────
# Re-run against the SAME $PA after writing the marker. The config now exists
# (seeded in case a), so the ONLY thing silencing the greeting is the marker.
mkdir -p "$PA/.zskills"
date -Iseconds > "$PA/.zskills/setup-confirmed"
ERRB="$TMP/err_b"
OUT_B="$(run_mat "$PA" "$ERRB")"
if [ -z "$OUT_B" ]; then
  pass "b. setup-confirmed marker present: no greeting on stdout (silent)"
else
  fail "b. marker present: greeting still emitted"
  printf '      stdout: %s\n' "$OUT_B"
fi

# ── (c) lane == update-zskills -> silent (early exit) ────────────────────────
PC="$TMP/proj_c"
base_fixture "$PC"
write_unsentinelled_skill "$PC/.claude/skills/update-zskills/SKILL.md"
ERRC="$TMP/err_c"
OUT_C="$(run_mat "$PC" "$ERRC")"
if [ -z "$OUT_C" ]; then
  pass "c. lane==update-zskills: no greeting on stdout (early exit, silent)"
else
  fail "c. lane==update-zskills: greeting unexpectedly emitted"
  printf '      stdout: %s\n' "$OUT_C"
fi
# The stderr dual/early-exit nag should still be present (sanity: it IS the
# update-zskills lane, not a no-op).
if grep -q "switch-install-path.sh" "$ERRC"; then
  pass "c2. lane==update-zskills: stderr nag still emitted (greeting did not displace it)"
else
  fail "c2. lane==update-zskills: expected stderr nag missing"
fi

# ── (d) lane == dual -> silent (early exit) ──────────────────────────────────
# Dual = a sentinelled plugin artifact AND an un-sentinelled zskills mirror.
PD="$TMP/proj_d"
base_fixture "$PD"
write_unsentinelled_skill "$PD/.claude/skills/update-zskills/SKILL.md"
write_sentinelled_hook "$PD/.claude/hooks/inject-bash-timeout.sh"
ERRD="$TMP/err_d"
OUT_D="$(run_mat "$PD" "$ERRD")"
if [ -z "$OUT_D" ]; then
  pass "d. lane==dual: no greeting on stdout (early exit, silent)"
else
  fail "d. lane==dual: greeting unexpectedly emitted"
  printf '      stdout: %s\n' "$OUT_D"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
