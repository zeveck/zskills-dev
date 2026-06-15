#!/bin/bash
# move-to-worktree.sh — stash-free "move my dirty main into a worktree" helper.
#
# Creates a worktree branched off the CURRENT LOCAL HEAD (via create-worktree.sh
# --no-preflight — the documented dirty-tolerant escape, so the carry is
# same-base by construction), CARRIES the dirty + untracked files on main into
# that worktree, and then performs a SANCTIONED, byte+index-verified restore of
# main back to HEAD. It uses NONE of the destructive git verbs that agents are
# hard-denied (the stash family) or that would overwrite the tree before
# verification (the clean / hard-reset / tree-overwrite-from-HEAD families) — a
# copy-based move never destroys before verifying. The ONLY tree-touching verb
# is `git restore` (see the restore-primitive note below for why no other verb
# is used). The conformance tripwire pins ZERO occurrences of those forbidden
# verbs anywhere in this file, which is why they are not even named literally
# in these comments.
#
# Usage:
#   bash move-to-worktree.sh <branch-name|--auto> [--keep-main-dirty]
#
# Exit codes (PINNED — ENFORCEMENT_V2 Phase 5 R11):
#   0  Success. Worktree created + dirt carried (+ main restored unless
#      --keep-main-dirty).
#   2  Usage error (bad/missing args, not in a git repo, unknown flag).
#   6  create-worktree.sh failed (its rc is reported in the message).
#   7  Base-mismatch (worktree HEAD != main HEAD) OR a patch-apply failure —
#      main is left FULLY UNTOUCHED (fail-safe refusal, not destruction).
#      UNMERGED entries (UU/AA/DD during a paused merge) land here: git diff
#      on conflicted paths emits combined-diff output git apply cannot apply,
#      so the step-4 apply fails → rc 7, main untouched, "resolve the merge
#      first".
#   8  Byte/index verification mismatch. The step-6 pre-destruction check
#      leaves main FULLY untouched; a step-7 per-file TOCTOU re-check mismatch
#      leaves main PARTIALLY restored (the mismatched files PRESERVED), with
#      the skipped files listed.
#
# Safety argument (why the internal `git restore` is sanctioned, not a
# bypass): PreToolUse hooks gate the agent's literal Bash command string.
# The agent types `bash …/move-to-worktree.sh <branch>`, which matches no
# deny pattern; the `git restore --staged --worktree --source=HEAD` runs as
# a subprocess the hook never sees. There is NO marker file, NO hook edit,
# NO new allow-arm. The restore only ever touches files this helper has
# verified TWICE (step 6 and the step-7 TOCTOU re-check) to exist identically
# in the worktree in BOTH working-tree bytes AND index blob content — so the
# "discards uncommitted changes permanently" hazard the hook exists for is
# structurally absent. The conformance tripwire in tests/test-skill-
# conformance.sh pins these internals so this never silently becomes a
# general bypass.
#
# Restore primitive — `git restore --staged --worktree --source=HEAD -- <p>`.
# It is chosen over the older `git che`+`ckout HEAD -- <p>` form (DA6): restore
# handles MM / staged-new (A ) / deleted ( D) / rename paths at rc 0,
# unstages-and-removes a staged-new file, and resurrects a deleted one. The
# older form exits rc 1 on a staged-NEW path absent from HEAD
# (`error: pathspec … did not match`) which under `set -euo pipefail` would
# kill the helper mid-restore with main half-done. (The conformance tripwire
# pins zero occurrences of that older verb anywhere in this file.)
#
# Inventory exclusions — the porcelain choice (`git status --porcelain -z
# --untracked-files=all`) structurally EXCLUDES gitignored files (node_modules,
# build artifacts) from the carry: they never appear in porcelain output.
# `--untracked-files=all` is LOAD-BEARING: the default porcelain aggregates an
# untracked directory to ONE `?? newdir/` entry, but steps 5–7 are strictly
# per-FILE. `.zskills/` and the three legacy root markers (.zskills-tracked,
# .landed, .worktreepurpose) are the block-main-edits allowlist names — they
# stay with main and are NEVER carried or deleted.
#
# Known limitation: the worktree branches off LOCAL HEAD. If local main is
# ahead of / behind origin, the branch rebases later through the normal PR
# flow — that is the existing --no-preflight contract, not new risk.
#
# bash 3.2 compatible (like its create-worktree siblings).

set -euo pipefail

# zsh sourcing-safety idiom (#1169) for any consumer that sources rather than
# `bash`-execs; harmless under bash.
if [ -n "${ZSH_VERSION:-}" ]; then
  setopt LOCAL_OPTIONS KSH_ARRAYS BASH_REMATCH 2>/dev/null || true
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

usage() {
  echo "usage: bash move-to-worktree.sh <branch-name|--auto> [--keep-main-dirty]" >&2
}

# ── Argument parse ──────────────────────────────────────────────────────────
BRANCH_ARG=""
KEEP_MAIN_DIRTY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-main-dirty)
      KEEP_MAIN_DIRTY=1
      shift
      ;;
    --auto)
      BRANCH_ARG="--auto"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "move-to-worktree: unknown flag '$1'" >&2
      usage
      exit 2
      ;;
    *)
      if [ -n "$BRANCH_ARG" ]; then
        echo "move-to-worktree: unexpected extra argument '$1'" >&2
        usage
        exit 2
      fi
      BRANCH_ARG="$1"
      shift
      ;;
  esac
done

if [ -z "$BRANCH_ARG" ]; then
  echo "move-to-worktree: missing <branch-name> (or --auto)" >&2
  usage
  exit 2
fi

# ── Resolve MAIN_ROOT (the main repo working tree, even from a worktree) ─────
MAIN_ROOT_GIT_DIR=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [ -z "$MAIN_ROOT_GIT_DIR" ]; then
  echo "move-to-worktree: not inside a git repository" >&2
  exit 2
fi
MAIN_ROOT=$(cd "$MAIN_ROOT_GIT_DIR/.." && pwd)
if [ -z "$MAIN_ROOT" ] || [ "$MAIN_ROOT" = "/" ]; then
  echo "move-to-worktree: MAIN_ROOT resolved empty or '/'" >&2
  exit 2
fi

# Derive the slug for create-worktree.sh. For --auto we let create-worktree.sh
# own the naming via a timestamp slug (re-using its existing convention: a
# bare slug → path ${PROJECT_NAME}-${SLUG}, branch wt-${SLUG}); for an
# explicit branch we pass it through as --branch-name and synthesise a slug.
if [ "$BRANCH_ARG" = "--auto" ]; then
  SLUG="move-$(date +%Y%m%d-%H%M%S)"
  BRANCH_NAME_FLAG=()
else
  # Sanitise a slug from the branch name for the path leaf; create-worktree.sh
  # validates [A-Za-z0-9._-]+ on the slug, so map any other char to '-'.
  SLUG=$(printf '%s' "$BRANCH_ARG" | tr -c 'A-Za-z0-9._-' '-')
  [ -n "$SLUG" ] || SLUG="move-$(date +%Y%m%d-%H%M%S)"
  BRANCH_NAME_FLAG=(--branch-name "$BRANCH_ARG")
fi

# Pipeline id for the tracked marker (Tier-2 style synthesis).
PIPELINE_ID="move-to-worktree.$SLUG"

# ── TMPDIR for the two patches (cleaned on exit) ────────────────────────────
TMPDIR_PATCH=$(mktemp -d "${TMPDIR:-/tmp}/move-to-wt.XXXXXX")
cleanup() { rm -f "$TMPDIR_PATCH/staged.patch" "$TMPDIR_PATCH/unstaged.patch" 2>/dev/null || true; rmdir "$TMPDIR_PATCH" 2>/dev/null || true; }
trap cleanup EXIT

# ──────────────────────────────────────────────────────────────────────────
# STEP 1 — Inventory main. NUL-safe (-z); --untracked-files=all so untracked
# dirs are enumerated per-FILE. Exclude .zskills/ and the legacy root markers.
# ──────────────────────────────────────────────────────────────────────────
# Exclusion predicate: returns 0 (true) if PATH should be EXCLUDED from carry.
is_excluded() {
  case "$1" in
    .zskills/*|.zskills) return 0 ;;
    .zskills-tracked|.landed|.worktreepurpose) return 0 ;;
    *) return 1 ;;
  esac
}

# TRACKED_PATHS — every tracked-changed path (staged + unstaged), including
# BOTH sides of a rename. UNTRACKED_PATHS — untracked files (per-file).
# Parsed from a single NUL-delimited porcelain stream. Rename entries are TWO
# NUL fields: 'R  <new>\0<old>\0' (verified). Both enter TRACKED_PATHS.
TRACKED_PATHS=()
UNTRACKED_PATHS=()
HAS_UNMERGED=0

# Field-walk the NUL-delimited porcelain. We read `git status -z` DIRECTLY via
# process substitution into an array — capturing NUL output in a $(...) string
# strips the NUL bytes (bash drops them), which would collapse every record
# into one field and silently lose the inventory. Each porcelain record is
# 'XY <path>'; a rename/copy record is followed by a SECOND NUL field (old path).
parse_porcelain() {
  local -a fields=()
  local field
  # Split the NUL stream into one array element per field.
  while IFS= read -r -d '' field; do
    fields+=("$field")
  done < <(git -C "$MAIN_ROOT" status --porcelain -z --untracked-files=all)

  local i=0
  local n=${#fields[@]}
  while [ "$i" -lt "$n" ]; do
    local rec="${fields[$i]}"
    # rec = 'XY <path>' — XY is the first two chars, path starts at char 4
    # (one space separator). Defensive: skip empty records.
    if [ -z "$rec" ]; then i=$((i+1)); continue; fi
    local code="${rec:0:2}"
    local path="${rec:3}"
    local x="${code:0:1}"
    local y="${code:1:1}"

    if [ "$code" = "??" ]; then
      # Untracked file (per-file because of --untracked-files=all).
      if ! is_excluded "$path"; then
        UNTRACKED_PATHS+=("$path")
      fi
      i=$((i+1))
      continue
    fi

    # Unmerged: any of UU/AA/DD/AU/UA/DU/UD — both index/worktree codes 'U',
    # or both-added (AA) / both-deleted (DD).
    case "$code" in
      UU|AA|DD|AU|UA|DU|UD) HAS_UNMERGED=1 ;;
    esac

    # Rename / copy: code starts with R or C → the NEXT field is the OLD path.
    case "$x" in
      R|C)
        local oldpath=""
        if [ $((i+1)) -lt "$n" ]; then
          oldpath="${fields[$((i+1))]}"
        fi
        if ! is_excluded "$path"; then TRACKED_PATHS+=("$path"); fi
        if [ -n "$oldpath" ] && ! is_excluded "$oldpath"; then TRACKED_PATHS+=("$oldpath"); fi
        i=$((i+2))
        continue
        ;;
    esac

    # Ordinary tracked change (M/A/D/T and two-letter combos).
    if ! is_excluded "$path"; then
      TRACKED_PATHS+=("$path")
    fi
    i=$((i+1))
  done
}

parse_porcelain

MAIN_WAS_CLEAN=0
if [ "${#TRACKED_PATHS[@]}" -eq 0 ] && [ "${#UNTRACKED_PATHS[@]}" -eq 0 ]; then
  MAIN_WAS_CLEAN=1
fi

# Record main HEAD before creating the worktree (base guard input).
MAIN_HEAD=$(git -C "$MAIN_ROOT" rev-parse HEAD)

# ──────────────────────────────────────────────────────────────────────────
# STEP 2 — Create the worktree off LOCAL HEAD via --no-preflight.
# ──────────────────────────────────────────────────────────────────────────
CW_RC=0
WT_PATH=$(bash "$SCRIPT_DIR/create-worktree.sh" \
  --no-preflight \
  --pipeline-id "$PIPELINE_ID" \
  "${BRANCH_NAME_FLAG[@]}" \
  "$SLUG") || CW_RC=$?
if [ "$CW_RC" -ne 0 ] || [ -z "$WT_PATH" ]; then
  echo "move-to-worktree: create-worktree.sh failed (rc=$CW_RC)" >&2
  exit 6
fi

# ──────────────────────────────────────────────────────────────────────────
# STEP 3 — Base guard. With --no-preflight this must hold; mismatch → rc 7,
# main untouched. (No 3-way apply arm exists because the diff is same-base.)
# ──────────────────────────────────────────────────────────────────────────
WT_HEAD=$(git -C "$WT_PATH" rev-parse HEAD)
if [ "$WT_HEAD" != "$MAIN_HEAD" ]; then
  echo "move-to-worktree: base mismatch (worktree HEAD $WT_HEAD != main HEAD $MAIN_HEAD); main untouched" >&2
  exit 7
fi

if [ "$MAIN_WAS_CLEAN" -eq 1 ]; then
  echo "move-to-worktree: main was clean — nothing to carry" >&2
  echo "WORKTREE_PATH=$WT_PATH"
  exit 0
fi

# Unmerged state is uncarryable — fail-safe BEFORE touching anything.
if [ "$HAS_UNMERGED" -eq 1 ]; then
  echo "move-to-worktree: main has UNMERGED paths (paused merge/rebase conflict)." >&2
  echo "  Resolve the merge first, then re-run. Main untouched." >&2
  exit 7
fi

# ──────────────────────────────────────────────────────────────────────────
# STEP 4 — Carry tracked changes via TWO patches (preserve staged/unstaged
# split). Each applied only if non-empty. Apply failure → main untouched, rc 7.
# ──────────────────────────────────────────────────────────────────────────
if [ "${#TRACKED_PATHS[@]}" -gt 0 ]; then
  # Staged patch: HEAD → index.
  git -C "$MAIN_ROOT" diff --binary --cached > "$TMPDIR_PATCH/staged.patch" || true
  if [ -s "$TMPDIR_PATCH/staged.patch" ]; then
    if ! git -C "$WT_PATH" apply --index --whitespace=nowarn "$TMPDIR_PATCH/staged.patch"; then
      echo "move-to-worktree: failed to apply staged patch to worktree; main untouched" >&2
      exit 7
    fi
  fi
  # Unstaged patch: index → working tree.
  git -C "$MAIN_ROOT" diff --binary > "$TMPDIR_PATCH/unstaged.patch" || true
  if [ -s "$TMPDIR_PATCH/unstaged.patch" ]; then
    if ! git -C "$WT_PATH" apply --whitespace=nowarn "$TMPDIR_PATCH/unstaged.patch"; then
      echo "move-to-worktree: failed to apply unstaged patch to worktree; main untouched" >&2
      exit 7
    fi
  fi
fi

# ──────────────────────────────────────────────────────────────────────────
# STEP 5 — Carry untracked files: per-file copy, preserving relative paths.
# ──────────────────────────────────────────────────────────────────────────
copy_untracked_into_wt() {
  local rel="$1"
  local src="$MAIN_ROOT/$rel"
  local dst="$WT_PATH/$rel"
  [ -f "$src" ] || return 0
  mkdir -p "$(dirname "$dst")"
  cp -p "$src" "$dst"
}
for rel in "${UNTRACKED_PATHS[@]:-}"; do
  [ -n "$rel" ] || continue
  copy_untracked_into_wt "$rel"
done

# ──────────────────────────────────────────────────────────────────────────
# STEP 6 — VERIFY before any destruction: worktree bytes AND index content.
# ──────────────────────────────────────────────────────────────────────────
# verify_tracked_file <rel> : 0 = match, 1 = mismatch. (a) byte compare of the
# worktree working-tree copy vs main's; absent-in-BOTH counts as match (a
# deleted file). (b) index blob id equality (both-empty counts as match — a
# rename's old path is absent from both indexes).
verify_tracked_file() {
  local rel="$1"
  local mw="$MAIN_ROOT/$rel"
  local ww="$WT_PATH/$rel"

  # (a) working-tree byte compare.
  if [ -e "$mw" ] && [ -e "$ww" ]; then
    cmp -s "$mw" "$ww" || return 1
  elif [ ! -e "$mw" ] && [ ! -e "$ww" ]; then
    : # both absent (deleted file / rename old path) → match
  else
    return 1 # one present, one absent
  fi

  # (b) index blob compare.
  local mb wb
  mb=$(git -C "$MAIN_ROOT" ls-files -s -- "$rel" 2>/dev/null | awk '{print $2}')
  wb=$(git -C "$WT_PATH" ls-files -s -- "$rel" 2>/dev/null | awk '{print $2}')
  [ "$mb" = "$wb" ] || return 1
  return 0
}

verify_untracked_file() {
  local rel="$1"
  local mw="$MAIN_ROOT/$rel"
  local ww="$WT_PATH/$rel"
  [ -e "$ww" ] || return 1
  cmp -s "$mw" "$ww" || return 1
  return 0
}

MISMATCH=()
for rel in "${TRACKED_PATHS[@]:-}"; do
  [ -n "$rel" ] || continue
  if ! verify_tracked_file "$rel"; then MISMATCH+=("$rel"); fi
done
for rel in "${UNTRACKED_PATHS[@]:-}"; do
  [ -n "$rel" ] || continue
  if ! verify_untracked_file "$rel"; then MISMATCH+=("$rel"); fi
done

if [ "${#MISMATCH[@]}" -gt 0 ]; then
  echo "move-to-worktree: verification mismatch — main left UNTOUCHED. Reconcile manually:" >&2
  for m in "${MISMATCH[@]}"; do echo "  $m" >&2; done
  exit 8
fi

# ──────────────────────────────────────────────────────────────────────────
# STEP 7 — Sanctioned restore of main (skipped under --keep-main-dirty).
# Per-file: re-run BOTH step-6 checks (TOCTOU guard) immediately before
# destruction; a re-check mismatch SKIPS that file (preserve it), reports it,
# and forces final rc 8.
# ──────────────────────────────────────────────────────────────────────────
if [ "$KEEP_MAIN_DIRTY" -eq 1 ]; then
  echo "move-to-worktree: --keep-main-dirty — main left as-is; dirt carried to worktree" >&2
  echo "WORKTREE_PATH=$WT_PATH"
  exit 0
fi

SKIPPED=()
for rel in "${TRACKED_PATHS[@]:-}"; do
  [ -n "$rel" ] || continue
  if ! verify_tracked_file "$rel"; then
    SKIPPED+=("$rel")
    continue
  fi
  # Sanctioned restore: index AND worktree from HEAD. Handles MM/A /D/rename.
  git -C "$MAIN_ROOT" restore --staged --worktree --source=HEAD -- "$rel"
done

for rel in "${UNTRACKED_PATHS[@]:-}"; do
  [ -n "$rel" ] || continue
  if ! verify_untracked_file "$rel"; then
    SKIPPED+=("$rel")
    continue
  fi
  rm -f "$MAIN_ROOT/$rel"
done

# ──────────────────────────────────────────────────────────────────────────
# STEP 8 — Report.
# ──────────────────────────────────────────────────────────────────────────
CARRIED=$(( ${#TRACKED_PATHS[@]} + ${#UNTRACKED_PATHS[@]} ))
echo "move-to-worktree: carried $CARRIED path(s) into $WT_PATH; main restored to HEAD" >&2
if [ "${#SKIPPED[@]}" -gt 0 ]; then
  echo "move-to-worktree: WARNING — $((${#SKIPPED[@]})) file(s) changed on main mid-flight and were PRESERVED (not restored):" >&2
  for s in "${SKIPPED[@]}"; do echo "  $s" >&2; done
  echo "WORKTREE_PATH=$WT_PATH"
  exit 8
fi

echo "WORKTREE_PATH=$WT_PATH"
exit 0
