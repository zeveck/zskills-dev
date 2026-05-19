#!/bin/bash
# migrate-paths.sh — Deterministic file relocation for ZSKILLS_PATH_CONFIG.
# Usage: bash migrate-paths.sh <main-root>
# Exit 0 = migration applied or no-op; non-zero = mid-migration failure.
#
# INVARIANT: idempotency lock (.pre-paths-migration) writes LAST. Any earlier
# step that fails leaves the consumer in a re-runnable state — config write
# is atomic-or-skipped, file moves are atomic-per-file with early exit, and
# the manifest is the lock claim that says "all of the above succeeded."
# See #394 for the bug fixed by this contract.
#
# Algorithm (Phase 5a, ZSKILLS_PATH_CONFIG.md; reordered for #394):
#   1.  Detection — inventory existing artifacts; refuse if already migrated.
#   2.  Resolve target dirs in memory only (no config write yet).
#   2.5 Trigger --rerender BEFORE any moves so the broadened recursive-delete
#       hook regex is in place protecting the migration's own filesystem
#       actions.
#   3.  Write config keys output.plans_dir + output.issues_dir +
#       output.reports_dir (BOTH-OR-ALL-OR-NEITHER 3-tuple atomic write).
#       Runs BEFORE file moves so an awk failure aborts cleanly with NO
#       files touched and NO manifest written (re-runnable state).
#   4.  Move forensic + narrative reports → .zskills/audit/.
#   5.  Move plans → $TARGET_PLANS (default docs/plans).
#   5b. Move plans/PLAN_INDEX.md → .zskills/audit/.
#   6.  Move issue trackers → $TARGET_ISSUES (default .zskills/issues).
#   7.  Move var/ runtime files → .zskills/dev-server.{pid,log}.
#   8.  Update .gitignore (idempotent).
#   9.  Cross-reference rewrite (Phase 5b) inside the moved plan files.
#   10. Write .pre-paths-migration manifest (LOCK CLAIM — written LAST so an
#       earlier failure leaves the consumer re-runnable; on success this
#       short-circuits future invocations at Step 1).
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
  local re_slash='/(run-plan|draft-plan|refine-plan|draft-tests|work-on-plans|research-and-plan|research-and-go)[[:space:]]+'"$re_token"
  # Migration-documentation guard (PR #211 follow-up). The original 4-
  # enclosure rule blindly rewrote tokens inside instruction prose like
  # "Replace `plans/X.md` with `$ZSKILLS_DIR/X.md`" and inside bash fences
  # documenting the migration's own `git mv plans/X.md ...` command. That
  # damaged the plan that DOCUMENTS the migration (PR #211 Phase 6 surfaced
  # 13 corrupted sites in ZSKILLS_PATH_CONFIG.md alone). The fix:
  # (a) drop the over-aggressive shell-line rule (Enclosure 3); shell-form
  #     invocations against plan files in active plans are rare and
  #     manually-upgradable via path-config-upgrade.md task 3;
  # (b) detect migration-documentation lines via the verbs/markers below
  #     and skip rewriting them entirely (preserve the legacy form so
  #     instruction prose continues to make sense).
  local re_migration_doc='([Rr]eplace|[Ss]ubstitute|[Rr]ewrite|[Mm]oved?:|git[[:space:]]+mv|wrong[[:space:]]path|legacy[[:space:]]token|pre-migration|post-migration|skipped:|MATCH[[:space:]]*\(|NON-MATCH[[:space:]]*\(|→)'
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
    # Decide if line is a structural reference. PR-#211-follow-up rules:
    # (1) skip migration-documentation lines (preserve the legacy form
    #     so instruction prose remains intelligible);
    # (2) shell-line rule dropped (used to be Enclosures 3 + 3' — too
    #     aggressive against bash fences documenting `git mv` etc.);
    # (3) only rewrite high-confidence forms: markdown link, backtick,
    #     slash-command. These have low false-positive rates.
    local rewrite=0
    # Migration-doc guard — never rewrite. Examples this catches:
    #   "Replace `plans/X.md` with ..."     (instruction prose)
    #   "git mv plans/X.md docs/plans/..."  (the migration's own cmd)
    #   "moved: plans/X.md → .zskills/..."  (migration stdout)
    #   "MATCH (markdown link)"             (example tables before/after)
    #   "(wrong path)"                      (annotation on legacy refs)
    if [[ "$line" =~ $re_migration_doc ]]; then
      printf '%s\n' "$line" >> "$out_file"
      continue
    fi
    # Enclosure 1: markdown link [...](TOKEN)
    if [[ "$line" =~ $re_link ]]; then rewrite=1; fi
    # Enclosure 2: backticked code-span containing TOKEN
    if [[ "$line" =~ $re_backtick ]]; then rewrite=1; fi
    # Enclosure 3: slash-command invocation.
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
# lines to .zskills/audit/migration-warnings.md (user-discoverable
# review surface, alongside other audit-dir reports). Pre-create
# the file with a header on first write so a markdown viewer treats
# it as a document rather than a stream of bare WARN lines.
cross_ref_scan_warn() {
  local file="$1"
  local warnings_file=".zskills/audit/migration-warnings.md"
  local line_no=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    if [[ "$line" =~ (plans/[A-Za-z][A-Za-z0-9_-]*\.md|reports/(plan|verify|briefing|new-blocks)-[a-z0-9-]+\.md) ]]; then
      local token="${BASH_REMATCH[1]}"
      local msg="WARN $file:$line_no: legacy token '$token' preserved (frozen plan; see path-config-upgrade.md)"
      printf '%s\n' "$msg" >&2
      if [ ! -s "$warnings_file" ]; then
        mkdir -p "$(dirname "$warnings_file")"
        printf '# Migration warnings — preserved legacy tokens in frozen plans\n\nGenerated by `migrate-paths.sh` cross_ref_scan_warn. Each line lists a `plans/X.md` or `reports/Y.md` token that was preserved (not rewritten) because its containing plan has `status: complete` and is non-canary, OR is otherwise frozen. Review each entry and decide whether to manually upgrade per `.claude/skills/update-zskills/references/path-config-upgrade.md` task 3.\n\n' > "$warnings_file"
      fi
      printf '%s\n' "$msg" >> "$warnings_file"
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
  local hits warnings_file=".zskills/audit/migration-warnings.md"
  hits=$(grep -rnE '(\$MAIN_ROOT|\$WORKTREE_PATH|/workspaces/zskills)/plans/[A-Za-z]' "$target_plans" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    while IFS= read -r hit; do
      local msg="WARN absolute-path legacy token: $hit (review and rewrite manually; see path-config-upgrade.md)"
      printf '%s\n' "$msg" >&2
      if [ ! -s "$warnings_file" ]; then
        mkdir -p "$(dirname "$warnings_file")"
        printf '# Migration warnings — preserved legacy tokens in frozen plans\n\nGenerated by `migrate-paths.sh` cross_ref_scan_warn. Each line lists a `plans/X.md` or `reports/Y.md` token that was preserved (not rewritten) because its containing plan has `status: complete` and is non-canary, OR is otherwise frozen. Review each entry and decide whether to manually upgrade per `.claude/skills/update-zskills/references/path-config-upgrade.md` task 3.\n\n' > "$warnings_file"
      fi
      printf '%s\n' "$msg" >> "$warnings_file"
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
HAS_REPORTS_KEY=0
EXISTING_PLANS=""
EXISTING_ISSUES=""
EXISTING_REPORTS=""
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
  if [[ "$CFG_BODY" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"reports_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
    HAS_REPORTS_KEY=1
    EXISTING_REPORTS="${BASH_REMATCH[1]}"
  fi
  unset CFG_BODY
fi

# Nothing to migrate AND no config keys missing → no-op.
if [ "$HAS_LEGACY" -eq 0 ] && [ "$HAS_PLANS_KEY" -eq 1 ] && [ "$HAS_ISSUES_KEY" -eq 1 ] && [ "$HAS_REPORTS_KEY" -eq 1 ]; then
  echo "no-op (no legacy artifacts and config already has output.plans_dir + output.issues_dir + output.reports_dir)"
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
  TARGET_ISSUES="docs/issues"
fi
if [ "$HAS_REPORTS_KEY" -eq 1 ] && [ -n "$EXISTING_REPORTS" ]; then
  TARGET_REPORTS="$EXISTING_REPORTS"
else
  TARGET_REPORTS="docs/reports"
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

# ─── Step 3 — Write the config keys FIRST (atomic-or-skipped) ─────────────
# Per the #394 reorder: config write runs BEFORE any file moves so that an
# awk failure here aborts cleanly — NO files have been touched, NO manifest
# has been written, and the consumer's re-run hits the SAME detection state
# (legacy artifacts still on disk, idempotency guard not yet armed).
#
# Atomicity: `write_output_block` writes to a `mktemp` tmp file and only
# replaces `$CFG` via a final `cat "$tmp" > "$CFG"` (no rename/clobber if
# the awk pipeline failed). awk failure → tmp is rm'd, `$CFG` untouched.
#
# If config is missing entirely, create an empty {} object.
if [ ! -f "$CFG" ]; then
  mkdir -p .claude
  printf '{\n}\n' > "$CFG"
fi

# Re-read current state (something may have changed via rerender? — no: rerender
# does NOT touch config. Re-reading is defensive).
CFG_BODY=$(cat "$CFG")

write_output_block() {
  # Writes BOTH plans_dir AND issues_dir AND reports_dir under "output".
  # If "output" object is absent, inserts a new one before the outer closing
  # brace (apply-preset awk pattern). If "output" object is present, splices
  # all three keys atomically (3-tuple BOTH-OR-ALL-OR-NEITHER).
  #
  # Trailing-comma handling (d-bis): when preserved keys are streamed inline
  # before missing-key injections at the `}`, the LAST preserved key may
  # have been originally written WITHOUT a trailing comma (valid JSON when
  # it was the last key in the object). If injections follow, that key now
  # needs a comma. Solution: buffer the most-recent preserved-key line and
  # only flush it when (a) a new preserved key arrives — comma-forcing flush,
  # since something follows it; (b) the closing brace arrives — apply comma
  # only if missing-key injections are about to be emitted.
  local plans="$1" issues="$2" reports="$3" tmp
  tmp=$(mktemp)
  if grep -q '"output"[[:space:]]*:[[:space:]]*{' "$CFG"; then
    # Existing output object — replace keys (or add missing ones).
    plans="$plans" issues="$issues" reports="$reports" awk '
      BEGIN {
        plans = ENVIRON["plans"]
        issues = ENVIRON["issues"]
        reports = ENVIRON["reports"]
        in_output = 0
        depth = 0
        wrote_plans = 0
        wrote_issues = 0
        wrote_reports = 0
        buffered = 0       # 1 iff buf_line holds a pending preserved-key line
        buf_line = ""
      }
      function flush_buffered(force_comma,    line_out, has_comma) {
        if (!buffered) return
        if (force_comma) {
          # Add a comma if not already present.
          line_out = buf_line
          if (match(line_out, /,[[:space:]]*$/)) {
            print line_out
          } else {
            sub(/[[:space:]]*$/, "", line_out)
            print line_out ","
          }
        } else {
          print buf_line
        }
        buffered = 0
        buf_line = ""
      }
      {
        line = $0
        if (in_output) {
          # Track brace depth inside the output object.
          # Simple counter — assumes no braces inside string values (config
          # keys are paths, no braces).
          n_open = gsub(/\{/, "{", line); line = $0
          n_close = gsub(/\}/, "}", line); line = $0
          # Preserved-key matchers: rewrite VALUE only, buffer line so the
          # trailing-comma policy can be decided when the next line arrives.
          if (match(line, /"plans_dir"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
            flush_buffered(1)   # something follows the previously buffered key
            indent = ""
            if (match(line, /^[[:space:]]*/)) indent = substr(line, 1, RLENGTH)
            tc = ""
            if (match(line, /,[[:space:]]*$/)) tc = ","
            buf_line = indent "\"plans_dir\": \"" plans "\"" tc
            buffered = 1
            wrote_plans = 1
            depth = depth + n_open - n_close
            if (depth < 0) {
              flush_buffered(0)
              in_output = 0
            }
            next
          }
          if (match(line, /"issues_dir"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
            flush_buffered(1)
            indent = ""
            if (match(line, /^[[:space:]]*/)) indent = substr(line, 1, RLENGTH)
            tc = ""
            if (match(line, /,[[:space:]]*$/)) tc = ","
            buf_line = indent "\"issues_dir\": \"" issues "\"" tc
            buffered = 1
            wrote_issues = 1
            depth = depth + n_open - n_close
            if (depth < 0) {
              flush_buffered(0)
              in_output = 0
            }
            next
          }
          if (match(line, /"reports_dir"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
            flush_buffered(1)
            indent = ""
            if (match(line, /^[[:space:]]*/)) indent = substr(line, 1, RLENGTH)
            tc = ""
            if (match(line, /,[[:space:]]*$/)) tc = ","
            buf_line = indent "\"reports_dir\": \"" reports "\"" tc
            buffered = 1
            wrote_reports = 1
            depth = depth + n_open - n_close
            if (depth < 0) {
              flush_buffered(0)
              in_output = 0
            }
            next
          }
          # Detect closing brace of output object — flush any buffered
          # preserved key (with comma iff injections follow), then inject
          # missing keys with comma-between-not-after-last semantics.
          if (match(line, /^[[:space:]]*\}[[:space:]]*,?[[:space:]]*$/) && depth + n_open - n_close <= 0) {
            indent = "    "
            # Build canonical-order list of missing keys.
            n_missing = 0
            if (!wrote_plans)   { n_missing++; missing[n_missing] = "\"plans_dir\": \"" plans "\"" }
            if (!wrote_issues)  { n_missing++; missing[n_missing] = "\"issues_dir\": \"" issues "\"" }
            if (!wrote_reports) { n_missing++; missing[n_missing] = "\"reports_dir\": \"" reports "\"" }
            # Flush buffered preserved-key: needs trailing comma iff any
            # missing-key injection will follow.
            flush_buffered(n_missing > 0 ? 1 : 0)
            for (i = 1; i <= n_missing; i++) {
              suffix = (i < n_missing) ? "," : ""
              print indent missing[i] suffix
            }
            print line
            in_output = 0
            depth = 0
            next
          }
          # Non-matching line inside output (e.g., other future keys —
          # flush buffer first, then emit as-is).
          flush_buffered(1)
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
          # Single-line "output": {...} edge case (depth==0 means the whole
          # object opens AND closes on this line) — expand and merge.
          if (depth == 0 && match(line, /"output"[[:space:]]*:[[:space:]]*\{.*\}/)) {
            indent = "  "
            if (match(line, /^[[:space:]]*/)) indent = substr(line, 1, RLENGTH)
            # Preserve trailing comma after the closing brace if any.
            tc = ""
            if (match(line, /\}[[:space:]]*,[[:space:]]*$/)) tc = ","
            # Extract inner body between the matched { and matching }.
            body = line
            sub(/^.*"output"[[:space:]]*:[[:space:]]*\{/, "", body)
            sub(/\}[[:space:]]*,?[[:space:]]*$/, "", body)
            # Re-parse the body for existing known keys (preserve values).
            seen_plans = ""; seen_issues = ""; seen_reports = ""
            have_plans = 0; have_issues = 0; have_reports = 0
            if (match(body, /"plans_dir"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
              s = substr(body, RSTART, RLENGTH)
              if (match(s, /"[^"]*"[[:space:]]*$/)) {
                v = substr(s, RSTART + 1, RLENGTH - 2); sub(/[[:space:]]*$/, "", v)
                seen_plans = v; have_plans = 1
              }
            }
            if (match(body, /"issues_dir"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
              s = substr(body, RSTART, RLENGTH)
              if (match(s, /"[^"]*"[[:space:]]*$/)) {
                v = substr(s, RSTART + 1, RLENGTH - 2); sub(/[[:space:]]*$/, "", v)
                seen_issues = v; have_issues = 1
              }
            }
            if (match(body, /"reports_dir"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
              s = substr(body, RSTART, RLENGTH)
              if (match(s, /"[^"]*"[[:space:]]*$/)) {
                v = substr(s, RSTART + 1, RLENGTH - 2); sub(/[[:space:]]*$/, "", v)
                seen_reports = v; have_reports = 1
              }
            }
            print indent "\"output\": {"
            # Emit any preserved keys first (in encountered canonical order
            # plans, issues, reports), then the missing keys after, with
            # comma-between-not-after-last.
            n_emit = 0
            if (have_plans)   { emit[++n_emit] = "\"plans_dir\": \"" seen_plans "\"" }
            if (have_issues)  { emit[++n_emit] = "\"issues_dir\": \"" seen_issues "\"" }
            if (have_reports) { emit[++n_emit] = "\"reports_dir\": \"" seen_reports "\"" }
            # Now emit missing ones (rewritten with target values).
            if (!have_plans)   { emit[++n_emit] = "\"plans_dir\": \"" plans "\"" }
            if (!have_issues)  { emit[++n_emit] = "\"issues_dir\": \"" issues "\"" }
            if (!have_reports) { emit[++n_emit] = "\"reports_dir\": \"" reports "\"" }
            for (i = 1; i <= n_emit; i++) {
              suffix = (i < n_emit) ? "," : ""
              print indent "  " emit[i] suffix
            }
            print indent "}" tc
            wrote_plans = 1; wrote_issues = 1; wrote_reports = 1
            in_output = 0
            next
          }
          print line
          next
        }
        print line
      }
      END {
        # Defensive: if we somehow exit while still buffered (malformed
        # input, no closing brace), flush without comma so nothing is
        # silently dropped.
        flush_buffered(0)
      }
    ' "$CFG" > "$tmp"
  else
    # No output object — insert one before the outer closing brace.
    plans="$plans" issues="$issues" reports="$reports" awk '
      BEGIN {
        plans = ENVIRON["plans"]
        issues = ENVIRON["issues"]
        reports = ENVIRON["reports"]
      }
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
        print "    \"issues_dir\": \"" issues "\","
        print "    \"reports_dir\": \"" reports "\""
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

# Decision: if ANY of the three keys is missing, write ALL THREE. Per
# Locked Decision 4 + 3-tuple atomic both-or-all-or-neither extension.
# Per #394: this runs BEFORE file moves so awk failure aborts cleanly with
# no manifest, no moved files, and the consumer's re-run hits the same
# detection state.
if [ "$HAS_PLANS_KEY" -eq 0 ] || [ "$HAS_ISSUES_KEY" -eq 0 ] || [ "$HAS_REPORTS_KEY" -eq 0 ]; then
  if ! write_output_block "$TARGET_PLANS" "$TARGET_ISSUES" "$TARGET_REPORTS"; then
    echo "FAIL: cannot write output.plans_dir / output.issues_dir / output.reports_dir to $CFG" >&2
    exit 1
  fi
  WROTE_KEYS=1
else
  WROTE_KEYS=0
fi

# ─── Step 4 — Move forensic + narrative reports → .zskills/audit/ ─────────
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

# ─── Step 5 — Move plans → $TARGET_PLANS ──────────────────────────────────
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

  # Move any remaining plans/*.md not matched above (covers kebab-case
  # plans like cross-platform-hooks.md and SCREAMING_SNAKE_CASE without
  # _PLAN suffix like EXECUTION_MODES.md). Skip PLAN_INDEX.md — Step 5b
  # routes it to .zskills/audit/ instead of $TARGET_PLANS.
  for src in plans/*.md; do
    [ -e "$src" ] || continue
    base=$(basename "$src")
    [ "$base" = "PLAN_INDEX.md" ] && continue
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

# ─── Step 5b — Move PLAN_INDEX.md → .zskills/audit/ ────────────────────────
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

# ─── Step 6 — Move issue trackers → $TARGET_ISSUES ────────────────────────
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

# ─── Step 7 — Move var/ runtime files ─────────────────────────────────────
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

# ─── Step 8 — Update .gitignore (idempotent) ──────────────────────────────
GI=".gitignore"
[ -f "$GI" ] || touch "$GI"

# Add .zskills/audit/ if not already present.
if ! grep -qE '^\.zskills/audit/$' "$GI"; then
  echo ".zskills/audit/" >> "$GI"
fi

# Note: .zskills/issues/ is no longer auto-appended. The new default
# (docs/issues/) is tracked, and the broader .zskills/ umbrella ignore
# (if present in the consumer's .gitignore) already covers any opt-in
# .zskills/issues/ override without needing a per-subdir entry here.

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

# ─── Step 9 — Cross-reference rewrite (Phase 5b) ──────────────────────────
# Rewrites legacy `plans/` and `reports/` structural references inside the
# moved plan files (active / proposal / no-frontmatter REWRITE; canary
# self-invocations REWRITE; status:complete non-canary PRESERVE + warn).
# Runs BEFORE manifest write so a mid-rewrite abort leaves the idempotent
# guard inactive (re-run resumes cleanly).
if [ -d "$TARGET_PLANS" ]; then
  pass_out=$(run_cross_ref_pass "$TARGET_PLANS") || {
    echo "FAIL: cross-ref rewrite pass failed (step 9)" >&2
    exit 1
  }
  CR_REWROTE=$(echo "$pass_out" | awk '{print $1}')
  CR_PRESERVED=$(echo "$pass_out" | awk '{print $2}')
  CR_SEEN=$(echo "$pass_out" | awk '{print $3}')
  echo "cross-ref rewrite: rewrote $CR_REWROTE files; preserved $CR_PRESERVED; scanned $CR_SEEN"
else
  CR_REWROTE=0; CR_PRESERVED=0; CR_SEEN=0
fi

# ─── Step 10 — Write .pre-paths-migration manifest (LOCK CLAIM — LAST) ────
# Per the #394 invariant: the idempotency lock writes LAST. Once on disk,
# Step 1's guard short-circuits any future invocation. Any failure in
# Steps 3-9 above must NOT reach this point — config write aborts cleanly
# (atomic-or-skipped, awk failure → exit 1 with no $CFG change); file moves
# use atomic per-file `git mv` / `mv` with `exit 1` on failure; the cross-
# ref pass propagates non-zero via `|| { exit 1; }`. By construction, if
# we reach Step 10 every prior step succeeded.
if [ -e .pre-paths-migration ]; then
  echo "FAIL: .pre-paths-migration already exists; refusing to overwrite manifest" >&2
  exit 1
fi
# Strip trailing newline by writing without -n (printf gives byte-control).
# MANIFEST already ends with one trailing newline per entry; preserve as-is.
printf '%s' "$MANIFEST" > .pre-paths-migration
MANIFEST_LINES=$(grep -c '	' .pre-paths-migration 2>/dev/null || echo 0)

# ─── (Step 10 historical note) ────────────────────────────────────────────
# `write_output_block` and its invocation previously lived AFTER the
# manifest write here (old "Step 10"). Per #394 both were hoisted to
# NEW Step 3 above — config write runs BEFORE file moves so an awk
# failure aborts the migration before any state-mutating action,
# preventing the strand-by-stranded-manifest bug from re-emerging.


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
  echo "Wrote output.plans_dir = \"$TARGET_PLANS\", output.issues_dir = \"$TARGET_ISSUES\", and output.reports_dir = \"$TARGET_REPORTS\"."
else
  echo "Config keys output.plans_dir / output.issues_dir / output.reports_dir already present — preserved."
fi
echo "For start-dev.sh / stop-dev.sh customizations, see"
echo ".claude/skills/update-zskills/references/path-config-upgrade.md."

exit 0
