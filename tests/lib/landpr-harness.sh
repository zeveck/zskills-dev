# tests/lib/landpr-harness.sh — shared /land-pr extract-and-run harness
# (SEAM_HARDENING_HIGH Phase 1).
#
# SOURCEABLE LIBRARY, NOT A SUITE. Do NOT register in run-all.sh.
#
# Extract-and-run a real /land-pr fence costs more than copying it: the fence
# reads INPUT variables set in sibling fences (under `set -u` it aborts unless
# they are seeded) and calls external commands (`git`, `gh`, `pr-monitor.sh`).
# This harness provides the three pieces every such test needs:
#
#   mkshim                  — the git/realpath PATH-shim (ported verbatim from
#                             tests/test-fix-issues-sprint-land-pr.sh:104+).
#   prepare_result_file     — pre-stage a $RESULT_FILE with key=value lines.
#   patch_caller_loop       — neuter the `. …zskills-{paths,resolve-config}.sh`
#                             sources and rewrite `RESULT_FILE=$(mktemp)` (and
#                             `BODY_FILE=$(mktemp)`) to pre-staged paths.
#   seed_caller_loop_inputs — export the input-prelude a caller-loop / Step-6b /
#                             Step-7c/7d fence reads from sibling fences.
#
# Keep this THIN: extraction lives in tests/lib/extract-fence.sh; per-test
# assertions and fixtures live in each test file. Only `seed_caller_loop_inputs`
# is expected to GROW (additively) as later phases consume more fences.

# ── mkshim — git + realpath PATH shim ────────────────────────────────
# Ported from tests/test-fix-issues-sprint-land-pr.sh (the canonical shim).
# Usage: mkshim <dir> <worktree-path> <main-root> <status-dirty 0|1> \
#               <realpath-mode gnu|fallback> <branch>
# Writes executables into "<dir>/bin"; prepend that to PATH to activate.
mkshim() {
  local dir="$1" wt="$2" main="$3" status_dirty="$4" realpath_mode="$5" branch="$6"
  mkdir -p "$dir/bin"

  # git shim — minimal subset.
  cat > "$dir/bin/git" <<EOF
#!/usr/bin/env bash
set -u
WT_PATH_FIX="$wt"
MAIN_ROOT_FIX="$main"
STATUS_DIRTY="$status_dirty"
BRANCH_FIX="$branch"

# Strip a leading "-C <dir>" pair so the rest looks like a normal git invocation.
if [ "\${1:-}" = "-C" ]; then shift 2; fi

case "\$1" in
  rev-parse)
    case "\${2:-}" in
      --show-toplevel) echo "\$WT_PATH_FIX" ;;
      --git-common-dir) echo "\$MAIN_ROOT_FIX/.git" ;;
      --abbrev-ref)
        if [ "\${3:-}" = "HEAD" ]; then echo "\$BRANCH_FIX"; fi
        ;;
      *) exit 0 ;;
    esac
    ;;
  add)
    if [ "\${2:-}" = "-A" ]; then
      if [ "\$STATUS_DIRTY" = "1" ]; then
        echo "tracker_change.txt" > "\$WT_PATH_FIX/.staged"
      fi
    else
      if [ -n "\${2:-}" ]; then echo "\$2" > "\$WT_PATH_FIX/.staged"; fi
    fi
    ;;
  diff)
    if [ "\${2:-}" = "--cached" ] && [ "\${3:-}" = "--name-only" ]; then
      if [ -f "\$WT_PATH_FIX/.staged" ]; then cat "\$WT_PATH_FIX/.staged"; fi
    fi
    ;;
  commit)
    rm -f "\$WT_PATH_FIX/.staged"
    echo "[fake-commit] ok" >&2
    ;;
  status)
    if [ "\$STATUS_DIRTY" = "1" ]; then
      echo " M tracker_change.txt"
    fi
    ;;
  worktree)
    if [ "\${2:-}" = "remove" ]; then
      echo "[fake-worktree-remove] \${4:-}" >&2
    fi
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$dir/bin/git"

  # realpath shim — either echoes a GNU-style rel path or exits 1
  # (forcing the bash-fallback `case "\$ABS_FILE_CANON"` branch).
  cat > "$dir/bin/realpath" <<EOF
#!/usr/bin/env bash
# Mode: $realpath_mode (gnu|fallback)
if [ "$realpath_mode" = "fallback" ]; then
  exit 1
fi
# GNU-style: --relative-to=BASE PATH
BASE=""
FILE=""
while [ "\${1:-}" != "" ]; do
  case "\$1" in
    --relative-to=*) BASE="\${1#--relative-to=}"; shift ;;
    --relative-to) BASE="\$2"; shift 2 ;;
    -*) shift ;;
    *) FILE="\$1"; shift ;;
  esac
done
F="\$FILE"
B="\$BASE"
case "\$F" in
  "\$B"/*) echo "\${F#\$B/}" ;;
  *) echo "\$F" ;;
esac
EOF
  chmod +x "$dir/bin/realpath"
}

# ── prepare_result_file — pre-stage a $RESULT_FILE ───────────────────
# Usage: prepare_result_file <path> key=value [key=value ...]
prepare_result_file() {
  local path="$1"; shift
  : > "$path"
  local kv
  for kv in "$@"; do printf '%s\n' "$kv" >> "$path"; done
}

# ── patch_caller_loop — neuter sources + rewrite mktemp tmpfiles ─────
# Usage: patch_caller_loop <extracted-fence-file> <out-file>
# (1) replaces `. "$CLAUDE_PROJECT_DIR/.../zskills-{paths,resolve-config}.sh"`
#     (and the `${CLAUDE_PLUGIN_ROOT}` variant) with a no-op so the fence does
#     not source the real config resolver — the harness pre-sets env instead.
# (2) rewrites `RESULT_FILE=$(mktemp)` → `RESULT_FILE="$PREPARED_RESULT_FILE"`
#     and `BODY_FILE=$(mktemp)` → `BODY_FILE="$PREPARED_BODY_FILE"` so the
#     post-dispatch parser reads the pre-staged result file.
patch_caller_loop() {
  local src="$1" out="$2"
  awk '
    /^[[:space:]]*\.[[:space:]]+"[$]\{?CLAUDE_(PROJECT_DIR|PLUGIN_ROOT)\}?\/.*zskills-(paths|resolve-config)\.sh"/ {
      print ": # patched-out source: " $0
      next
    }
    {
      sub(/RESULT_FILE=\$\(mktemp\)/, "RESULT_FILE=\"$PREPARED_RESULT_FILE\"")
      sub(/BODY_FILE=\$\(mktemp\)/,   "BODY_FILE=\"$PREPARED_BODY_FILE\"")
      print
    }
  ' "$src" > "$out"
}

# ── seed_caller_loop_inputs — the input-prelude ──────────────────────
# Export the variables a /land-pr caller-loop / Step-6b / Step-7c / Step-7d
# fence reads from SIBLING fences. Seeding INPUTS is legitimate fixture setup
# (you control the scenario, then run the REAL logic fence); it is NOT
# re-implementing the logic.
#
# Every variable is set ONLY if not already set by the caller (`: "${X:=…}"`),
# so a test can override any single input before calling this, then run the
# real fence under `set -u` without an unbound-variable abort.
#
# This function is the additive growth point of the harness (the extract_*
# public contract is frozen; this is not). Later phases add inputs here.
seed_caller_loop_inputs() {
  # ── Caller-loop / arg-parse outputs (lines ~60-131,214) ──
  : "${STATUS:=}"
  : "${CI_STATUS:=}"
  : "${AUTO_FLAG:=false}"
  : "${PR_NUMBER:=}"
  : "${PR_URL:=}"
  : "${PR_EXISTING:=}"
  : "${BRANCH:=feat/seam-harness}"
  : "${BRANCH_SLUG:=${BRANCH//\//-}}"
  : "${BASE_BRANCH:=main}"
  : "${WORKTREE_PATH:=}"
  : "${CI_TIMEOUT:=600}"
  : "${TRACKING_ID:=}"
  : "${TITLE:=}"
  : "${LANDED_SOURCE:=land-pr}"
  : "${NO_MONITOR:=false}"
  : "${PR_RESUME:=}"
  : "${ISSUE_NUM:=}"

  # ── MAIN_ROOT family — Step 7b/7c copy-to-main resolution ──
  : "${MAIN_ROOT:=}"
  : "${COPY_MAIN_ROOT:=}"

  # ── config-derived ──
  : "${TIMEZONE:=UTC}"

  # ── Legacy-lane faithful resolution-fence input (root-resolution-fix) ──
  # The new lane-portable resolution idiom (`if [ -f "${CLAUDE_PLUGIN_ROOT}/…" ]`)
  # references a BARE ${CLAUDE_PLUGIN_ROOT} token. Production fences run WITHOUT
  # `set -u`, so on the legacy lane the unset token expands empty → the `-f`
  # test is false → else-branch (which `patch_caller_loop` neuters) → harness
  # pre-set env wins. Under the harness's `set -u`, BIND the token EMPTY (not a
  # real path) so the same legacy else path is taken without an unbound-variable
  # abort. Empty is the legacy-faithful value; a real path would mask the else.
  : "${CLAUDE_PLUGIN_ROOT:=}"

  # ── Merge/state — Step 6/7 ──
  : "${MERGE_REQUESTED:=false}"
  : "${PR_STATE:=not-checked}"
  : "${REASON:=}"

  # ── Step 6b auto-rebase loop inputs (proactive, m5) ──
  : "${REBASE_STDERR_FILE:=}"
  : "${UNKNOWN_POLL_MAX:=5}"

  # ── Step 7d terminal-drive inputs (proactive, m5) ──
  : "${TW_ITER:=0}"

  export STATUS CI_STATUS AUTO_FLAG PR_NUMBER PR_URL PR_EXISTING \
         BRANCH BRANCH_SLUG BASE_BRANCH WORKTREE_PATH CI_TIMEOUT TRACKING_ID \
         TITLE LANDED_SOURCE NO_MONITOR PR_RESUME ISSUE_NUM \
         MAIN_ROOT COPY_MAIN_ROOT TIMEZONE CLAUDE_PLUGIN_ROOT \
         MERGE_REQUESTED PR_STATE REASON \
         REBASE_STDERR_FILE UNKNOWN_POLL_MAX TW_ITER
}
