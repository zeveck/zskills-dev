#!/bin/bash
# migrate-paths.sh — Deterministic file relocation for ZSKILLS_PATH_CONFIG.
# Usage: bash migrate-paths.sh <main-root>
# Exit 0 = migration applied or no-op; non-zero = mid-migration failure.
#
# The deterministic step orders write-of-config-keys LAST so any mid-failure
# leaves the consumer recovering via the helper's legacy-`plans/` fallback.
#
# Algorithm (Phase 5a, ZSKILLS_PATH_CONFIG.md):
#   1.  Detection — inventory existing artifacts; refuse if already migrated.
#   2.  Resolve target dirs in memory only (no config write yet).
#   2.5 Trigger --rerender BEFORE any moves so the broadened recursive-delete
#       hook regex is in place protecting the migration's own filesystem
#       actions.
#   3.  Move forensic + narrative reports → .zskills/audit/.
#   4.  Move plans → $TARGET_PLANS (default docs/plans).
#   4b. Move plans/PLAN_INDEX.md → .zskills/audit/.
#   5.  Move issue trackers → $TARGET_ISSUES (default .zskills/issues).
#   6.  Move var/ runtime files → .zskills/dev-server.{pid,log}.
#   7.  Update .gitignore (idempotent).
#   8.  (reserved — was --rerender step before round-2 plan hoisted to 2.5).
#   9.  Write .pre-paths-migration manifest (write-once).
#   10. Write config keys output.plans_dir + output.issues_dir (BOTH or NEITHER).
#   11. Print summary.
#
# Per CLAUDE.md "Never suppress errors on operations you need to verify":
# every git mv / mv is followed by explicit if/then/else echo FAIL >&2;
# exit 1, never `&& echo "moved"`, never `2>/dev/null`.

set -u

# ─── Argument parsing ──────────────────────────────────────────────────────
# Optional `--rewrite-only` flag (Phase 5b) before the positional <main-root>.
# Behavior under --rewrite-only:
#   (a) Precondition — `.pre-paths-migration` MUST already exist.
#   (b) Skip steps 1–7 entirely.
#   (c) Resolve TARGET_PLANS from the existing config's output.plans_dir.
#   (d) Execute ONLY the cross-ref rewrite over plan files (decision tree).
#   (e) Append a `rewrite-only:` trailer line to .pre-paths-migration.
#   (f) Skip the config-key write (step 10).
#   (g) Print a summary; exit 0 on success.
REWRITE_ONLY=0
if [ "${1:-}" = "--rewrite-only" ]; then
  REWRITE_ONLY=1
  shift
fi

MAIN_ROOT="${1:-}"
[ -z "$MAIN_ROOT" ] && {
  echo "usage: migrate-paths.sh [--rewrite-only] <main-root>" >&2
  exit 1
}
cd "$MAIN_ROOT" || exit 1

# Manifest accumulator: each entry is "from\tto" appended with $'\n'.
MANIFEST=""

manifest_add() {
  # Args: $1 = from, $2 = to. Appends a tab-separated entry.
  MANIFEST="${MANIFEST}${1}	${2}
"
}

# ─── cross_ref_rewrite() — Phase 5b structural-reference rewriter ──────────
# Scans a plan file line-by-line maintaining fence state (mirrors the
# conformance-scanner idiom in tests/test-skill-conformance.sh:1066-1124).
# A line is rewritten iff a path token (`plans/X.md` or
# `reports/(plan|verify|briefing|new-blocks)-Y.md`) is enclosed by ONE of:
#   1. Markdown link  [...](...)
#   2. Backtick code-span  `...`
#   3. Bash/shell command-line (inside bash/sh/shell/empty-lang fence,
#      OR starts with "$ ", OR ends with shell metachar |, >, <, ;)
#   4. Slash-command invocation  /run-plan, /draft-plan, /refine-plan,
#      /draft-tests, /work-on-plans, /research-and-plan, /research-and-go
# Substitution:
#   plans/X.md           → <TARGET_PLANS>/X.md
#   reports/Y.md         → .zskills/audit/Y.md  (only plan/verify/briefing/
#                                                new-blocks prefix slugs)
# Mode preservation: chmod --reference (Linux); fall back to chmod 644 on
# macOS (round-2 DA D2). Symlinked plans are defensively skipped.
cross_ref_rewrite() {
  local file="$1"
  local target_plans="$2"
  if [ -L "$file" ]; then
    echo "WARN: cross_ref_rewrite skipping symlink: $file" >&2
    return 0
  fi
  # Bash `[[ =~ ]]` only handles backslash-escaped metachars correctly when
  # the regex is in a variable (inline-quoted backslashes get pre-processed
  # by the shell). Store every regex used below in a variable.
  local re_fence='^[[:space:]]*```([a-zA-Z0-9_+-]*)[[:space:]]*$'
  local re_token='(plans/[A-Za-z][A-Za-z0-9_-]*\.md|reports/(plan|verify|briefing|new-blocks)-[a-z0-9-]+\.md)'
  local re_link='\[[^]]*\]\('"$re_token"
  local re_backtick='`[^`]*'"$re_token"'[^`]*`'
  local re_dollar_prefix='^\$[[:space:]]'
  local re_meta_suffix='[|><;][[:space:]]*$'
  local re_slash='/(run-plan|draft-plan|refine-plan|draft-tests|work-on-plans|research-and-plan|research-and-go)[[:space:]]+'"$re_token"
  # Idempotency guard — if `target_plans` already contains `plans/` (e.g.,
  # `docs/plans`), a naive `${line//plans\//.../}` replace will double-
  # rewrite an already-migrated path. Build a "negative-prefix" guard: a
  # line is only rewritten if its `plans/X.md` token is NOT already
  # preceded by the target_plans prefix.
  local in_fence=0
  local fence_lang=""
  local out_file
  out_file=$(mktemp)
  while IFS= read -r line || [ -n "$line" ]; do
    # Fence open/close detection.
    if [[ "$line" =~ $re_fence ]]; then
      if [ "$in_fence" -eq 0 ]; then
        in_fence=1
        fence_lang="${BASH_REMATCH[1]}"
      else
        in_fence=0
        fence_lang=""
      fi
      printf '%s\n' "$line" >> "$out_file"
      continue
    fi
    # Decide if line is a structural reference (4 enclosure types).
    local rewrite=0
    # Enclosure 1: markdown link [...](TOKEN)
    if [[ "$line" =~ $re_link ]]; then rewrite=1; fi
    # Enclosure 2: backticked code-span containing TOKEN
    if [[ "$line" =~ $re_backtick ]]; then rewrite=1; fi
    # Enclosure 3: bash/shell command-line — fence-anchored.
    if [ "$in_fence" -eq 1 ] && { [ "$fence_lang" = "bash" ] || [ "$fence_lang" = "sh" ] || [ "$fence_lang" = "shell" ] || [ -z "$fence_lang" ]; }; then
      if [[ "$line" =~ $re_token ]]; then rewrite=1; fi
    fi
    # Enclosure 3': prose-line shell heuristic ($ prefix or trailing metachars).
    if [[ "$line" =~ $re_dollar_prefix ]] || [[ "$line" =~ $re_meta_suffix ]]; then
      if [[ "$line" =~ $re_token ]]; then rewrite=1; fi
    fi
    # Enclosure 4: slash-command invocation.
    if [[ "$line" =~ $re_slash ]]; then rewrite=1; fi
    if [ "$rewrite" -eq 1 ]; then
      # Substitute `plans/X.md` → `<TARGET_PLANS>/X.md`; `reports/Y.md` → `.zskills/audit/Y.md`.
      # Idempotency: only substitute `plans/` when NOT preceded by the target prefix.
      # Use sed with a negative lookbehind-equivalent: anchor on a character
      # class that excludes the path-character set (and start-of-line).
      # Pattern: `(^|[^A-Za-z0-9_/.-])plans/` — matches plans/ only when
      # preceded by a non-path char or line start. Exception: target_plans
      # itself ends with plans/, e.g., `docs/plans/` — but then the prior
      # char is `/`, which is in the exclusion set, so the negative-prefix
      # holds and we don't double-rewrite.
      line=$(printf '%s\n' "$line" \
        | sed -E "s#(^|[^A-Za-z0-9_/.-])plans/#\\1${target_plans}/#g")
      line=$(printf '%s\n' "$line" \
        | sed -E "s#(^|[^A-Za-z0-9_/.-])reports/(plan|verify|briefing|new-blocks)-#\\1.zskills/audit/\\2-#g")
    fi
    printf '%s\n' "$line" >> "$out_file"
  done < "$file"
  # Preserve original file mode across the swap. mktemp produces 0600;
  # markdown plans are 0644 in tracked state. `chmod --reference` is Linux-
  # only; fall back to explicit `chmod 644` on macOS (round-2 DA D2).
  chmod --reference="$file" "$out_file" 2>/dev/null \
    || chmod 644 "$out_file"
  if mv "$out_file" "$file"; then
    return 0
  else
    rm -f "$out_file"
    return 1
  fi
}

# Scan a plan file and emit one stderr WARN line per legacy-token hit
# (preserved-frozen plans; round-3 DA F13/F16). Also append the same
# lines to .pre-paths-migration-warnings at $MAIN_ROOT.
cross_ref_scan_warn() {
  local file="$1"
  local line_no=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    if [[ "$line" =~ (plans/[A-Za-z][A-Za-z0-9_-]*\.md|reports/(plan|verify|briefing|new-blocks)-[a-z0-9-]+\.md) ]]; then
      local token="${BASH_REMATCH[1]}"
      local msg="WARN $file:$line_no: legacy token '$token' preserved (frozen plan; see path-config-upgrade.md)"
      printf '%s\n' "$msg" >&2
      printf '%s\n' "$msg" >> .pre-paths-migration-warnings
    fi
  done < "$file"
}

# Read YAML frontmatter `status:` value (best-effort).
read_frontmatter_status() {
  local file="$1"
  awk '
    BEGIN { in_fm = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^[[:space:]]*status[[:space:]]*:/ {
      sub(/^[[:space:]]*status[[:space:]]*:[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      print
      exit
    }
  ' "$file"
}

# Apply the frontmatter decision tree to one plan file. Echoes
# "REWROTE", "REWROTE_CANARY", or "PRESERVED".
apply_decision_tree() {
  local file="$1"
  local target_plans="$2"
  local status base
  status=$(read_frontmatter_status "$file")
  base=$(basename "$file")
  case "$status" in
    active|proposal|"")
      if cross_ref_rewrite "$file" "$target_plans"; then
        echo "REWROTE"
      else
        echo "FAIL: cross_ref_rewrite on $file" >&2
        return 1
      fi
      ;;
    complete)
      if [[ "$base" =~ ^CANARY ]]; then
        if cross_ref_rewrite "$file" "$target_plans"; then
          echo "REWROTE_CANARY"
        else
          echo "FAIL: cross_ref_rewrite on $file" >&2
          return 1
        fi
      else
        cross_ref_scan_warn "$file"
        echo "PRESERVED"
      fi
      ;;
    *)
      cross_ref_scan_warn "$file"
      echo "PRESERVED"
      ;;
  esac
}

# Iterate every *.md under <TARGET_PLANS>, apply decision tree, emit
# post-rewrite SCAN-and-warn fallback for $MAIN_ROOT/, $WORKTREE_PATH/,
# /workspaces/zskills/ absolute-path forms (round-2 DA F5).
# Echoes "<rewrote_count> <preserved_count> <files_seen>".
run_cross_ref_pass() {
  local target_plans="$1"
  local rewrote=0
  local preserved=0
  local seen=0
  if [ ! -d "$target_plans" ]; then
    echo "0 0 0"
    return 0
  fi
  while IFS= read -r -d '' f; do
    seen=$((seen + 1))
    local result
    result=$(apply_decision_tree "$f" "$target_plans") || return 1
    case "$result" in
      REWROTE|REWROTE_CANARY) rewrote=$((rewrote + 1)) ;;
      PRESERVED)              preserved=$((preserved + 1)) ;;
    esac
  done < <(find "$target_plans" -type f -name '*.md' -print0)
  # Post-rewrite SCAN-and-warn fallback for absolute-path forms.
  local hits
  hits=$(grep -rnE '(\$MAIN_ROOT|\$WORKTREE_PATH|/workspaces/zskills)/plans/[A-Za-z]' "$target_plans" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    while IFS= read -r hit; do
      local msg="WARN absolute-path legacy token: $hit (review and rewrite manually; see path-config-upgrade.md)"
      printf '%s\n' "$msg" >&2
      printf '%s\n' "$msg" >> .pre-paths-migration-warnings
    done <<< "$hits"
  fi
  echo "$rewrote $preserved $seen"
}

# ─── --rewrite-only short-circuit ──────────────────────────────────────────
if [ "$REWRITE_ONLY" -eq 1 ]; then
  # (a) Precondition.
  if [ ! -f .pre-paths-migration ]; then
    echo "no prior migration to rewrite — run \`migrate-paths.sh <main-root>\` first." >&2
    exit 1
  fi
  # (c) Resolve TARGET_PLANS from existing config.
  CFG=".claude/zskills-config.json"
  TARGET_PLANS=""
  if [ -f "$CFG" ]; then
    CFG_BODY=$(cat "$CFG" 2>/dev/null || true)
    if [[ "$CFG_BODY" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"plans_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
      TARGET_PLANS="${BASH_REMATCH[1]}"
    fi
    unset CFG_BODY
  fi
  if [ -z "$TARGET_PLANS" ]; then
    echo "config missing output.plans_dir; rewrite cannot proceed." >&2
    exit 1
  fi
  # (d) Execute ONLY the cross-ref rewrite.
  pass_out=$(run_cross_ref_pass "$TARGET_PLANS") || {
    echo "FAIL: cross-ref rewrite pass failed" >&2
    exit 1
  }
  # parse counts
  rewrote=$(echo "$pass_out" | awk '{print $1}')
  preserved=$(echo "$pass_out" | awk '{print $2}')
  seen=$(echo "$pass_out" | awk '{print $3}')
  # (e) Append manifest trailer.
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf 'rewrite-only:\t%s\t%s\n' "$ts" "$rewrote" >> .pre-paths-migration
  # (f/g) skip config write; print summary.
  echo
  echo "── Rewrite-only summary ────────────────────────────────────────────"
  echo "REWROTE: $rewrote structural references in $seen plan files"
  echo "(--rewrite-only — manifest preserved; config unchanged)"
  echo "PRESERVED (frozen): $preserved"
  exit 0
fi

# ─── Step 1 — Detection ────────────────────────────────────────────────────
# Idempotent guard: if .pre-paths-migration already exists, refuse re-run.
if [ -f .pre-paths-migration ]; then
  echo "already migrated (.pre-paths-migration exists); no-op"
  exit 0
fi

# Detection scan — true if anything to migrate.
HAS_LEGACY=0

# Forensic + narrative top-level reports (Tier 2).
TOP_REPORTS=( SPRINT_REPORT.md FIX_REPORT.md PLAN_REPORT.md
              VERIFICATION_REPORT.md NEW_BLOCKS_REPORT.md )
for f in "${TOP_REPORTS[@]}"; do
  [ -e "$f" ] && HAS_LEGACY=1
done
[ -d reports ] && HAS_LEGACY=1
[ -d plans ] && HAS_LEGACY=1
[ -d var ] && HAS_LEGACY=1

# Read existing config to detect whether path-config keys are already set.
CFG=".claude/zskills-config.json"
HAS_PLANS_KEY=0
HAS_ISSUES_KEY=0
EXISTING_PLANS=""
EXISTING_ISSUES=""
if [ -f "$CFG" ]; then
  CFG_BODY=$(cat "$CFG" 2>/dev/null || true)
  if [[ "$CFG_BODY" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"plans_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
    HAS_PLANS_KEY=1
    EXISTING_PLANS="${BASH_REMATCH[1]}"
  fi
  if [[ "$CFG_BODY" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"issues_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
    HAS_ISSUES_KEY=1
    EXISTING_ISSUES="${BASH_REMATCH[1]}"
  fi
  unset CFG_BODY
fi

# Nothing to migrate AND no config keys missing → no-op.
if [ "$HAS_LEGACY" -eq 0 ] && [ "$HAS_PLANS_KEY" -eq 1 ] && [ "$HAS_ISSUES_KEY" -eq 1 ]; then
  echo "no-op (no legacy artifacts and config already has output.plans_dir + output.issues_dir)"
  exit 0
fi

if [ "$HAS_LEGACY" -eq 0 ]; then
  echo "no-op (no legacy artifacts to migrate)"
  exit 0
fi

# ─── Step 2 — Resolve target dirs (in memory ONLY) ─────────────────────────
if [ "$HAS_PLANS_KEY" -eq 1 ] && [ -n "$EXISTING_PLANS" ]; then
  TARGET_PLANS="$EXISTING_PLANS"
else
  TARGET_PLANS="docs/plans"
fi
if [ "$HAS_ISSUES_KEY" -eq 1 ] && [ -n "$EXISTING_ISSUES" ]; then
  TARGET_ISSUES="$EXISTING_ISSUES"
else
  TARGET_ISSUES=".zskills/issues"
fi

# ─── Step 2.5 — Trigger --rerender BEFORE any file moves ───────────────────
# Hook strengthens BEFORE filesystem changes, so a mid-migration agent
# invoking `rm -rf .zskills/audit` for cleanup is BLOCKED by the broadened
# hook. Re-render only mutates .claude/rules/zskills/managed.md AND
# .claude/hooks/block-unsafe-project.sh; it does NOT depend on
# output.plans_dir / output.issues_dir keys (CI guard in Phase 5a.4 Case 1
# enforces this invariant).
#
# Locate $PORTABLE: prefer $PORTABLE env var, else fall back to common
# tiers (mirror Step 0 of update-zskills/SKILL.md, but a minimal subset
# sufficient for hook re-copy). Source-of-truth for the broadened hook
# regex is hooks/block-unsafe-project.sh.template.
PORTABLE="${PORTABLE:-}"
if [ -z "$PORTABLE" ]; then
  for cand in zskills-portable zskills /tmp/zskills "$PWD/../zskills" "$PWD/../../zskills" \
              "$HOME/src/zskills" "$HOME/code/zskills" "$HOME/projects/zskills" "$HOME/zskills"; do
    if [ -d "$cand" ] && [ -f "$cand/CLAUDE_TEMPLATE.md" ] && [ -d "$cand/hooks" ] \
       && [ -d "$cand/scripts" ] && [ -d "$cand/skills" ]; then
      PORTABLE="$cand"
      break
    fi
  done
fi
if [ -z "$PORTABLE" ]; then
  echo "FAIL: cannot locate zskills source for --rerender step 2.5 (set \$PORTABLE)" >&2
  exit 1
fi

# Re-copy block-unsafe-project.sh from the portable source. The template
# carries the broadened recursive-delete fence (matching `rm -r ... .zskills`)
# that protects subsequent .zskills/audit + .zskills/issues filesystem moves.
mkdir -p .claude/hooks
HOOK_SRC="$PORTABLE/hooks/block-unsafe-project.sh.template"
HOOK_DST=".claude/hooks/block-unsafe-project.sh"
if [ -f "$HOOK_SRC" ]; then
  if cp "$HOOK_SRC" "$HOOK_DST"; then
    chmod +x "$HOOK_DST"
    echo "rerender: copied block-unsafe-project.sh (broadened recursive-delete fence — applied EARLY)"
  else
    echo "FAIL: cannot copy $HOOK_SRC → $HOOK_DST during step 2.5 rerender" >&2
    exit 1
  fi
else
  echo "FAIL: $HOOK_SRC missing — cannot rerender hook before moves" >&2
  exit 1
fi

# ─── Step 3 — Move forensic + narrative reports → .zskills/audit/ ─────────
mkdir -p .zskills/audit

for f in "${TOP_REPORTS[@]}"; do
  [ -e "$f" ] || continue
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    git mv "$f" ".zskills/audit/$f"
  else
    mv "$f" ".zskills/audit/$f"
  fi
  if [ -e ".zskills/audit/$f" ] && [ ! -e "$f" ]; then
    echo "moved: $f → .zskills/audit/$f"
    manifest_add "$f" ".zskills/audit/$f"
  else
    echo "FAIL: move $f → .zskills/audit/$f did not complete" >&2
    exit 1
  fi
done

# Move every file under reports/ (if dir present).
if [ -d reports ]; then
  while IFS= read -r -d '' src; do
    rel="${src#reports/}"
    dst=".zskills/audit/$rel"
    mkdir -p "$(dirname "$dst")"
    if git ls-files --error-unmatch "$src" >/dev/null 2>&1; then
      git mv "$src" "$dst"
    else
      mv "$src" "$dst"
    fi
    if [ -e "$dst" ] && [ ! -e "$src" ]; then
      echo "moved: $src → $dst"
      manifest_add "$src" "$dst"
    else
      echo "FAIL: move $src → $dst did not complete" >&2
      exit 1
    fi
  done < <(find reports -type f -print0)
  # Remove empty reports/ if possible.
  if [ -d reports ] && [ -z "$(ls -A reports 2>/dev/null)" ]; then
    if rmdir reports; then
      echo "removed empty: reports/"
    else
      echo "FAIL: rmdir reports/ failed" >&2
      exit 1
    fi
  fi
fi

# ─── Step 4 — Move plans → $TARGET_PLANS ──────────────────────────────────
mkdir -p "$TARGET_PLANS"

if [ -d plans ]; then
  # Move *_PLAN.md files.
  for src in plans/*_PLAN.md; do
    [ -e "$src" ] || continue
    base=$(basename "$src")
    dst="$TARGET_PLANS/$base"
    if git ls-files --error-unmatch "$src" >/dev/null 2>&1; then
      git mv "$src" "$dst"
    else
      mv "$src" "$dst"
    fi
    if [ -e "$dst" ] && [ ! -e "$src" ]; then
      echo "moved: $src → $dst"
      manifest_add "$src" "$dst"
    else
      echo "FAIL: move $src → $dst did not complete" >&2
      exit 1
    fi
  done

  # Move CANARY*.md files.
  for src in plans/CANARY*.md; do
    [ -e "$src" ] || continue
    base=$(basename "$src")
    dst="$TARGET_PLANS/$base"
    if git ls-files --error-unmatch "$src" >/dev/null 2>&1; then
      git mv "$src" "$dst"
    else
      mv "$src" "$dst"
    fi
    if [ -e "$dst" ] && [ ! -e "$src" ]; then
      echo "moved: $src → $dst"
      manifest_add "$src" "$dst"
    else
      echo "FAIL: move $src → $dst did not complete" >&2
      exit 1
    fi
  done

  # Recursively move plans/blocks/ → $TARGET_PLANS/blocks/.
  if [ -d plans/blocks ]; then
    mkdir -p "$TARGET_PLANS/blocks"
    while IFS= read -r -d '' src; do
      rel="${src#plans/blocks/}"
      dst="$TARGET_PLANS/blocks/$rel"
      mkdir -p "$(dirname "$dst")"
      if git ls-files --error-unmatch "$src" >/dev/null 2>&1; then
        git mv "$src" "$dst"
      else
        mv "$src" "$dst"
      fi
      if [ -e "$dst" ] && [ ! -e "$src" ]; then
        echo "moved: $src → $dst"
        manifest_add "$src" "$dst"
      else
        echo "FAIL: move $src → $dst did not complete" >&2
        exit 1
      fi
    done < <(find plans/blocks -type f -print0)
    # Remove empty plans/blocks/ if possible.
    find plans/blocks -type d -empty -delete 2>/dev/null || true
  fi
fi

# ─── Step 4b — Move PLAN_INDEX.md → .zskills/audit/ ────────────────────────
if [ -e plans/PLAN_INDEX.md ]; then
  if git ls-files --error-unmatch plans/PLAN_INDEX.md >/dev/null 2>&1; then
    git mv plans/PLAN_INDEX.md .zskills/audit/PLAN_INDEX.md
  else
    mv plans/PLAN_INDEX.md .zskills/audit/PLAN_INDEX.md
  fi
  if [ -e .zskills/audit/PLAN_INDEX.md ] && [ ! -e plans/PLAN_INDEX.md ]; then
    echo "moved: plans/PLAN_INDEX.md → .zskills/audit/PLAN_INDEX.md"
    manifest_add "plans/PLAN_INDEX.md" ".zskills/audit/PLAN_INDEX.md"
  else
    echo "FAIL: move plans/PLAN_INDEX.md → .zskills/audit/ did not complete" >&2
    exit 1
  fi
else
  echo "skipped: plans/PLAN_INDEX.md absent (will be regenerated via /plans rebuild)"
fi

# ─── Step 5 — Move issue trackers → $TARGET_ISSUES ────────────────────────
mkdir -p "$TARGET_ISSUES"

ISSUE_FILES=( ISSUES_PLAN.md BUILD_ISSUES.md DOC_ISSUES.md QE_ISSUES.md )
for base in "${ISSUE_FILES[@]}"; do
  src="plans/$base"
  [ -e "$src" ] || continue
  dst="$TARGET_ISSUES/$base"
  if git ls-files --error-unmatch "$src" >/dev/null 2>&1; then
    git mv "$src" "$dst"
  else
    mv "$src" "$dst"
  fi
  if [ -e "$dst" ] && [ ! -e "$src" ]; then
    echo "moved: $src → $dst"
    manifest_add "$src" "$dst"
  else
    echo "FAIL: move $src → $dst did not complete" >&2
    exit 1
  fi
done

# Remove empty plans/ directory if possible.
if [ -d plans ] && [ -z "$(ls -A plans 2>/dev/null)" ]; then
  if rmdir plans; then
    echo "removed empty: plans/"
  else
    echo "FAIL: rmdir plans/ failed" >&2
    exit 1
  fi
fi

# ─── Step 6 — Move var/ runtime files ─────────────────────────────────────
declare -A VAR_MAP=(
  [var/dev.pid]=".zskills/dev-server.pid"
  [var/dev.log]=".zskills/dev-server.log"
)

DEFER_STUBS=0
for src in var/dev.pid var/dev.log; do
  [ -e "$src" ] || continue
  dst="${VAR_MAP[$src]}"
  mkdir -p "$(dirname "$dst")"
  if git ls-files --error-unmatch "$src" >/dev/null 2>&1; then
    git mv "$src" "$dst"
  else
    mv "$src" "$dst"
  fi
  if [ -e "$dst" ] && [ ! -e "$src" ]; then
    echo "moved: $src → $dst"
    manifest_add "$src" "$dst"
    DEFER_STUBS=1
  else
    echo "FAIL: move $src → $dst did not complete" >&2
    exit 1
  fi
done

# Remove empty var/ if present.
if [ -d var ] && [ -z "$(ls -A var 2>/dev/null)" ]; then
  if rmdir var; then
    echo "removed empty: var/"
  else
    echo "FAIL: rmdir var/ failed" >&2
    exit 1
  fi
fi

# Stub-script deferral notice (always print when var/ files moved; agent-
# runnable upgrade prompt in Phase 5b handles auto-edit of start-dev.sh /
# stop-dev.sh).
if [ "$DEFER_STUBS" -eq 1 ]; then
  echo "DEFER: scripts/start-dev.sh and scripts/stop-dev.sh may reference var/dev.pid / var/dev.log; agent-runnable upgrade prompt will rewrite them (see references/path-config-upgrade.md after Phase 5b)."
fi

# ─── Step 7 — Update .gitignore (idempotent) ──────────────────────────────
GI=".gitignore"
[ -f "$GI" ] || touch "$GI"

# Add .zskills/audit/ if not already present.
if ! grep -qE '^\.zskills/audit/$' "$GI"; then
  echo ".zskills/audit/" >> "$GI"
fi

# Add .zskills/issues/ ONLY if $TARGET_ISSUES is under .zskills/.
case "$TARGET_ISSUES" in
  .zskills/*|"$MAIN_ROOT/.zskills/"*)
    if ! grep -qE '^\.zskills/issues/$' "$GI"; then
      echo ".zskills/issues/" >> "$GI"
    fi
    ;;
esac

# Remove obsolete var/ line if present (no-op if absent).
if grep -qE '^var/$' "$GI"; then
  if sed -i.bak '\|^var/$|d' "$GI"; then
    rm -f "$GI.bak"
  else
    echo "FAIL: sed remove var/ line from .gitignore failed" >&2
    exit 1
  fi
fi

# Verify effective ignore via git check-ignore -v.
mkdir -p .zskills/audit
touch .zskills/audit/.tmp-ignore-check
match=$(git check-ignore -v .zskills/audit/.tmp-ignore-check 2>/dev/null) || {
  echo "FAIL: .zskills/audit/ not effectively ignored" >&2
  rm -f .zskills/audit/.tmp-ignore-check
  exit 1
}
case "$match" in
  *!\.zskills/audit*|*!\.zskills/*)
    echo "FAIL: positive include rule overrides .zskills ignore: $match" >&2
    rm -f .zskills/audit/.tmp-ignore-check
    exit 1 ;;
esac
rm -f .zskills/audit/.tmp-ignore-check

# ─── Step 7.5 — Cross-reference rewrite (Phase 5b) ────────────────────────
# Rewrites legacy `plans/` and `reports/` structural references inside the
# moved plan files (active / proposal / no-frontmatter REWRITE; canary
# self-invocations REWRITE; status:complete non-canary PRESERVE + warn).
# Runs BEFORE manifest write so a mid-rewrite abort leaves the idempotent
# guard inactive (re-run resumes cleanly).
if [ -d "$TARGET_PLANS" ]; then
  pass_out=$(run_cross_ref_pass "$TARGET_PLANS") || {
    echo "FAIL: cross-ref rewrite pass failed (step 7.5)" >&2
    exit 1
  }
  CR_REWROTE=$(echo "$pass_out" | awk '{print $1}')
  CR_PRESERVED=$(echo "$pass_out" | awk '{print $2}')
  CR_SEEN=$(echo "$pass_out" | awk '{print $3}')
  echo "cross-ref rewrite: rewrote $CR_REWROTE files; preserved $CR_PRESERVED; scanned $CR_SEEN"
else
  CR_REWROTE=0; CR_PRESERVED=0; CR_SEEN=0
fi

# ─── Step 8 — (reserved; --rerender step hoisted to 2.5) ──────────────────

# ─── Step 9 — Write .pre-paths-migration manifest (write-once) ────────────
if [ -e .pre-paths-migration ]; then
  echo "FAIL: .pre-paths-migration already exists; refusing to overwrite manifest" >&2
  exit 1
fi
# Strip trailing newline by writing without -n (printf gives byte-control).
# MANIFEST already ends with one trailing newline per entry; preserve as-is.
printf '%s' "$MANIFEST" > .pre-paths-migration
MANIFEST_LINES=$(grep -c '	' .pre-paths-migration 2>/dev/null || echo 0)

# ─── Step 10 — Write the config keys (LAST; atomic both-or-neither) ───────
# If config is missing entirely, create an empty {} object.
if [ ! -f "$CFG" ]; then
  mkdir -p .claude
  printf '{\n}\n' > "$CFG"
fi

# Re-read current state (something may have changed via rerender? — no: rerender
# does NOT touch config. Re-reading is defensive).
CFG_BODY=$(cat "$CFG")

write_output_block() {
  # Writes BOTH plans_dir AND issues_dir under "output". If "output" object
  # is absent, inserts a new one before the outer closing brace (apply-preset
  # awk pattern). If "output" object is present, splices both keys atomically.
  local plans="$1" issues="$2" tmp
  tmp=$(mktemp)
  if grep -q '"output"[[:space:]]*:[[:space:]]*{' "$CFG"; then
    # Existing output object — replace BOTH keys (or add missing ones).
    plans="$plans" issues="$issues" awk '
      BEGIN {
        plans = ENVIRON["plans"]
        issues = ENVIRON["issues"]
        in_output = 0
        depth = 0
        wrote_plans = 0
        wrote_issues = 0
      }
      {
        line = $0
        if (in_output) {
          # Track brace depth inside the output object.
          # Simple counter — assumes no braces inside string values (config
          # keys are paths, no braces).
          n_open = gsub(/\{/, "{", line); line = $0
          n_close = gsub(/\}/, "}", line); line = $0
          # Update existing plans_dir or issues_dir.
          if (match(line, /"plans_dir"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
            indent = ""
            if (match(line, /^[[:space:]]*/)) indent = substr(line, 1, RLENGTH)
            # Preserve trailing comma if present.
            tc = ""
            if (match(line, /,[[:space:]]*$/)) tc = ","
            print indent "\"plans_dir\": \"" plans "\"" tc
            wrote_plans = 1
            depth = depth + n_open - n_close
            if (depth < 0) in_output = 0
            next
          }
          if (match(line, /"issues_dir"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
            indent = ""
            if (match(line, /^[[:space:]]*/)) indent = substr(line, 1, RLENGTH)
            tc = ""
            if (match(line, /,[[:space:]]*$/)) tc = ","
            print indent "\"issues_dir\": \"" issues "\"" tc
            wrote_issues = 1
            depth = depth + n_open - n_close
            if (depth < 0) in_output = 0
            next
          }
          # Detect closing brace of output object — inject any missing keys
          # immediately before it.
          if (match(line, /^[[:space:]]*\}[[:space:]]*,?[[:space:]]*$/) && depth + n_open - n_close <= 0) {
            indent = "    "
            if (!wrote_plans)  print indent "\"plans_dir\": \"" plans "\","
            if (!wrote_issues) print indent "\"issues_dir\": \"" issues "\","
            print line
            in_output = 0
            depth = 0
            next
          }
          depth = depth + n_open - n_close
          print line
          next
        }
        # Detect start of "output" object.
        if (match(line, /"output"[[:space:]]*:[[:space:]]*\{/)) {
          in_output = 1
          n_open = gsub(/\{/, "{", line); line = $0
          n_close = gsub(/\}/, "}", line); line = $0
          depth = n_open - n_close
          # Single-line "output": {} edge case — handle by re-emitting expanded.
          if (depth == 0 && match(line, /"output"[[:space:]]*:[[:space:]]*\{[[:space:]]*\}/)) {
            indent = "  "
            if (match(line, /^[[:space:]]*/)) indent = substr(line, 1, RLENGTH)
            # Preserve trailing comma if any.
            tc = ""
            if (match(line, /,[[:space:]]*$/)) tc = ","
            print indent "\"output\": {"
            print indent "  \"plans_dir\": \"" plans "\","
            print indent "  \"issues_dir\": \"" issues "\""
            print indent "}" tc
            wrote_plans = 1; wrote_issues = 1
            in_output = 0
            next
          }
          print line
          next
        }
        print line
      }
    ' "$CFG" > "$tmp"
  else
    # No output object — insert one before the outer closing brace.
    plans="$plans" issues="$issues" awk '
      BEGIN { plans = ENVIRON["plans"]; issues = ENVIRON["issues"] }
      { buf[NR] = $0 }
      END {
        last_close = 0
        for (i = NR; i >= 1; i--) {
          if (buf[i] ~ /^[[:space:]]*\}[[:space:]]*$/) { last_close = i; break }
        }
        if (last_close == 0) {
          for (i = 1; i <= NR; i++) print buf[i]
          exit 2
        }
        preceding = 0
        for (i = last_close - 1; i >= 1; i--) {
          if (buf[i] !~ /^[[:space:]]*$/) { preceding = i; break }
        }
        for (i = 1; i < preceding; i++) print buf[i]
        if (preceding > 0) {
          if (buf[preceding] ~ /\{[[:space:]]*$/) {
            print buf[preceding]
          } else if (buf[preceding] ~ /,[[:space:]]*$/) {
            print buf[preceding]
          } else {
            line = buf[preceding]
            sub(/[[:space:]]*$/, "", line)
            print line ","
          }
        }
        print "  \"output\": {"
        print "    \"plans_dir\": \"" plans "\","
        print "    \"issues_dir\": \"" issues "\""
        print "  }"
        for (i = preceding + 1; i < last_close; i++) print buf[i]
        for (i = last_close; i <= NR; i++) print buf[i]
      }
    ' "$CFG" > "$tmp" || {
      rm -f "$tmp"
      echo "FAIL: cannot locate outer closing brace in $CFG" >&2
      return 2
    }
  fi
  if [ -s "$tmp" ]; then
    cat "$tmp" > "$CFG"
    rm -f "$tmp"
    return 0
  else
    rm -f "$tmp"
    echo "FAIL: empty output from awk config-write" >&2
    return 2
  fi
}

# Decision: if EITHER key is missing, write BOTH. Per Locked Decision 4 +
# spec acceptance criterion (atomic both-or-neither).
if [ "$HAS_PLANS_KEY" -eq 0 ] || [ "$HAS_ISSUES_KEY" -eq 0 ]; then
  if ! write_output_block "$TARGET_PLANS" "$TARGET_ISSUES"; then
    echo "FAIL: cannot write output.plans_dir / output.issues_dir to $CFG" >&2
    exit 1
  fi
  WROTE_KEYS=1
else
  WROTE_KEYS=0
fi

# ─── Step 11 — Print summary ──────────────────────────────────────────────
echo
echo "── Migration summary ────────────────────────────────────────────────"
# Re-emit MIGRATED: lines from manifest (canonical form).
while IFS=$'\t' read -r src dst; do
  [ -z "$src" ] && continue
  echo "MIGRATED: $src → $dst"
done <<< "$MANIFEST"
echo "Wrote .pre-paths-migration with $MANIFEST_LINES entries."
echo "Re-rendered hooks (broadened recursive-delete fence — applied EARLY)."
if [ "$WROTE_KEYS" -eq 1 ]; then
  echo "Wrote output.plans_dir = \"$TARGET_PLANS\" and output.issues_dir = \"$TARGET_ISSUES\"."
else
  echo "Config keys output.plans_dir / output.issues_dir already present — preserved."
fi
echo "For start-dev.sh / stop-dev.sh customizations, see"
echo ".claude/skills/update-zskills/references/path-config-upgrade.md."

exit 0
