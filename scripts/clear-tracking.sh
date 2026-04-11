#!/bin/bash
# Clear all skill tracking files. Only the user should run this.
# Agents are blocked from invoking this script by the PreToolUse hook.

MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)
TRACKING_DIR="$MAIN_ROOT/.zskills/tracking"

if [ ! -d "$TRACKING_DIR" ]; then
  echo "No tracking directory found at $TRACKING_DIR"
  exit 0
fi

files=$(ls "$TRACKING_DIR" 2>/dev/null)
if [ -z "$files" ]; then
  echo "Tracking directory is empty."
  exit 0
fi

echo "Current tracking state:"
echo "========================"
for f in "$TRACKING_DIR"/*; do
  [ -f "$f" ] || continue
  echo ""
  echo "--- $(basename "$f") ---"
  cat "$f"
done
echo ""
echo "========================"
echo ""

read -p "Remove all tracking files? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy] ]]; then
  rm -f "$TRACKING_DIR"/*
  echo "Tracking files cleared."
else
  echo "Cancelled."
fi
