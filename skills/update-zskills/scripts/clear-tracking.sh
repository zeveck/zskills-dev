#!/bin/bash
# Clear skill tracking bookkeeping. Preserves fulfilled.run-plan.*
# (completion history). Refuses to run if an active pipeline is detected
# (recent requires.* without a matching complete fulfilled.*); --force
# overrides.
#
# Only the user should run this — agents are blocked by the PreToolUse hook.

set -e

MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)
TRACKING_DIR="$MAIN_ROOT/.zskills/tracking"
ACTIVE_WINDOW_HOURS=6
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=1 ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--force|-f]

Clears .zskills/tracking/* EXCEPT fulfilled.run-plan.* (completion history).
Refuses if a requires.* marker < ${ACTIVE_WINDOW_HOURS}h old has no matching complete
fulfilled.* (looks like an in-flight pipeline). --force overrides.
EOF
      exit 0
      ;;
  esac
done

if [ ! -d "$TRACKING_DIR" ]; then
  echo "No tracking directory at $TRACKING_DIR."
  exit 0
fi

shopt -s nullglob

# Tracking markers live in per-pipeline subdirs (.zskills/tracking/$PIPELINE_ID/)
# per the tracking naming scheme; a handful of legacy flat-layout
# fulfilled.run-plan.* files may also sit at the top level. `find -type f`
# catches both without the subdir-blind glob that shipped originally.
preserve_count=0
c_requires=0; c_step=0; c_verify=0; c_draft=0; c_refine=0; c_vpa=0; c_other=0

while IFS= read -r f; do
  base=$(basename "$f")
  case "$base" in
    fulfilled.run-plan.*)       preserve_count=$((preserve_count+1)) ;;
    fulfilled.verify-changes.*) c_verify=$((c_verify+1)) ;;
    fulfilled.draft-plan.*)     c_draft=$((c_draft+1)) ;;
    fulfilled.refine-plan.*)    c_refine=$((c_refine+1)) ;;
    requires.*)                 c_requires=$((c_requires+1)) ;;
    step.*|phasestep.*)         c_step=$((c_step+1)) ;;
    verify-pending-attempts.*)  c_vpa=$((c_vpa+1)) ;;
    *)                          c_other=$((c_other+1)) ;;
  esac
done < <(find "$TRACKING_DIR" -type f)

clear_count=$((c_requires + c_step + c_verify + c_draft + c_refine + c_vpa + c_other))

if [ "$preserve_count" -eq 0 ] && [ "$clear_count" -eq 0 ]; then
  echo "Tracking directory is empty."
  exit 0
fi

# Active pipeline detection. Scan requires.* wherever they live (top level
# or per-pipeline subdir) and look for a matching fulfilled.* in the same
# directory. "Active" = requires exists but fulfilled is missing or
# status != complete.
NOW=$(date +%s)
active_list=()
while IFS= read -r req; do
  base=$(basename "$req")
  reqdir=$(dirname "$req")
  tail="${base#requires.}"
  fulfilled="$reqdir/fulfilled.$tail"

  is_active=0
  if [ ! -f "$fulfilled" ]; then
    is_active=1
  elif ! grep -q '^status: complete' "$fulfilled" 2>/dev/null; then
    is_active=1
  fi

  [ "$is_active" -eq 1 ] || continue

  mtime=$(stat -c %Y "$req" 2>/dev/null || stat -f %m "$req" 2>/dev/null || echo 0)
  age_s=$((NOW - mtime))
  age_h=$((age_s / 3600))
  if [ "$age_h" -lt "$ACTIVE_WINDOW_HOURS" ]; then
    if [ "$age_h" -lt 1 ]; then
      age_str="$((age_s / 60))m"
    else
      age_str="${age_h}h"
    fi
    active_list+=( "$tail  (${age_str} old)" )
  fi
done < <(find "$TRACKING_DIR" -type f -name 'requires.*')

echo "Tracking dir: $TRACKING_DIR"
echo ""
echo "Preserving: $preserve_count"
printf "  fulfilled.run-plan.*             %d\n" "$preserve_count"
echo ""
echo "Clearing: $clear_count"
printf "  requires.*                       %d\n" "$c_requires"
printf "  step.* + phasestep.*             %d\n" "$c_step"
printf "  fulfilled.verify-changes.*       %d\n" "$c_verify"
printf "  fulfilled.draft-plan.*           %d\n" "$c_draft"
printf "  fulfilled.refine-plan.*          %d\n" "$c_refine"
printf "  verify-pending-attempts.*        %d\n" "$c_vpa"
[ "$c_other" -gt 0 ] && printf "  (other)                          %d\n" "$c_other"
echo ""

if [ ${#active_list[@]} -gt 0 ] && [ "$FORCE" -ne 1 ]; then
  echo "REFUSING: ${#active_list[@]} pipeline(s) look ACTIVE (requires.* without complete fulfilled, < ${ACTIVE_WINDOW_HOURS}h old):"
  for line in "${active_list[@]}"; do
    echo "  - $line"
  done
  echo ""
  echo "Wait for them to finish, or re-run with --force."
  exit 1
fi

if [ ${#active_list[@]} -gt 0 ]; then
  echo "NOTE: --force set; overriding active-pipeline check for:"
  for line in "${active_list[@]}"; do
    echo "  - $line"
  done
  echo ""
fi

cleared=0
while IFS= read -r f; do
  base=$(basename "$f")
  case "$base" in
    fulfilled.run-plan.*) ;;
    *) rm -f "$f"; cleared=$((cleared+1)) ;;
  esac
done < <(find "$TRACKING_DIR" -type f)

# Remove now-empty per-pipeline subdirs (avoid leaving stub directories
# from pipelines whose last non-preserved file was just cleared). The
# top-level $TRACKING_DIR is itself preserved.
find "$TRACKING_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true

# Post-clear sanity: count surviving bookkeeping-class files (anything that
# should have been cleared). Must be zero.
residual=$(find "$TRACKING_DIR" -type f \
  \( -name 'requires.*' \
     -o -name 'step.*' -o -name 'phasestep.*' \
     -o -name 'fulfilled.verify-changes.*' \
     -o -name 'fulfilled.draft-plan.*' \
     -o -name 'fulfilled.refine-plan.*' \
     -o -name 'verify-pending-attempts.*' \) \
  | wc -l | tr -d ' ')

echo "Cleared $cleared bookkeeping markers. Preserved $preserve_count completion records."
if [ "$residual" -ne 0 ]; then
  echo "WARN: $residual bookkeeping file(s) still present after clearing — clear-tracking.sh scope may need updating:" >&2
  find "$TRACKING_DIR" -type f \
    \( -name 'requires.*' \
       -o -name 'step.*' -o -name 'phasestep.*' \
       -o -name 'fulfilled.verify-changes.*' \
       -o -name 'fulfilled.draft-plan.*' \
       -o -name 'fulfilled.refine-plan.*' \
       -o -name 'verify-pending-attempts.*' \) >&2
  exit 2
fi
