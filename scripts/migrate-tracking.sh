#!/bin/bash
# scripts/migrate-tracking.sh [TRACKING_DIR]
# Migrate flat tracking markers into per-pipeline subdirectories.
# Idempotent — re-running is safe. Invoke manually or in CI one-shot.
# Does NOT run from the hook (latency-sensitive).
set -eu
TRACKING_DIR="${1:-$(pwd)/.zskills/tracking}"
if [ ! -d "$TRACKING_DIR" ]; then
  echo "no tracking dir at $TRACKING_DIR — nothing to migrate"
  exit 0
fi
cd "$TRACKING_DIR"
moved=0
skipped=0
requires_skipped=0
# NOTE: `requires.*` is deliberately EXCLUDED from the glob below.
# Delegation semantics (see docs/tracking/TRACKING_NAMING.md §"Delegation semantics"):
# a `requires.<skill>.<id>` marker is written BY the parent pipeline requesting
# fulfillment FROM <skill>. The marker's <skill> field is the DELEGATEE, not the
# pipeline owner — so we cannot infer PIPELINE_ID from the basename the way we
# can for `fulfilled.*` and `step.*` markers. Leaving `requires.*` flat is safe
# because the Phase 2 hook rewrite dual-reads flat paths during the migration
# window. Any `requires.*` still found at the flat path after that window can
# be hand-migrated by an operator who knows the parent pipeline.
for f in fulfilled.* step.*.implement step.*.verify pipeline.* meta.* verify-pending-attempts.* phasestep.*; do
  [ -e "$f" ] || continue
  [ -d "$f" ] && { skipped=$((skipped+1)); continue; }  # already a subdir (directory)
  # Derive pipeline-ID-like suffix from basename.
  # Strategy: the "old" flat naming scheme was <category>.<skill>.<suffix>[.<stage>]
  # The new layout wants: $PIPELINE_ID/<category>.<skill>.<suffix>[.<stage>]
  # We cannot always recover PIPELINE_ID from the basename — the suffix might be
  # $TRACKING_ID (a plan slug) OR a literal (sprint, meta). Best-effort:
  #   - If the category is `fulfilled` or `step` AND the writer-skill uses
  #     $TRACKING_ID-as-slug, then PIPELINE_ID = "<skill>.<suffix>".
  #   - Otherwise skip; operator can hand-migrate.
  #
  # Implementer note: this is intentionally conservative — we prefer leaving a
  # marker in place (dual-read still finds it in the flat path) over mis-migrating.
  base_no_ext="${f%.implement}"
  base_no_ext="${base_no_ext%.verify}"
  # basename pattern: <category>.<skill>.<suffix>
  suffix="${base_no_ext##*.}"
  skill_part="${base_no_ext%.*}"
  skill="${skill_part##*.}"
  # Heuristic: infer PIPELINE_ID = "<skill>.<suffix>" only for writers that use
  # $TRACKING_ID-as-slug (run-plan, draft-plan, refine-plan, verify-changes).
  # Other writers' markers are left flat; dual-read covers them.
  case "$skill" in
    run-plan|draft-plan|refine-plan|verify-changes)
      pipeline_id="${skill}.${suffix}"
      mkdir -p "./$pipeline_id"
      mv "./$f" "./$pipeline_id/$f"
      moved=$((moved+1))
      ;;
    *)
      skipped=$((skipped+1))
      ;;
  esac
done
# Count any `requires.*` files still present so the operator sees them.
# They also roll into the overall `skipped` count so the summary reflects
# every marker that was examined-but-not-moved.
for f in requires.*; do
  [ -e "$f" ] || continue
  [ -d "$f" ] && continue
  requires_skipped=$((requires_skipped+1))
  skipped=$((skipped+1))
done
if [ "$requires_skipped" -gt 0 ]; then
  echo "migrate-tracking: moved=$moved skipped=$skipped requires-skipped=$requires_skipped"
else
  echo "migrate-tracking: moved=$moved skipped=$skipped"
fi
