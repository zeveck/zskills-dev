#!/usr/bin/env bash
# tests/test-agents-parity.sh
#
# INSTALL_REDESIGN Phase 2 (branch 1A) — plugin-native agents parity.
#
# The plugin lane ships verifier/implementer as checked-in root agents/
# files, auto-loaded from the plugin root (NEVER via a manifest `agents`
# field — the Phase-1 claim-1 probe confirmed `claude plugin validate`
# REJECTS the field AND it breaks agent load). Plugin agents IGNORE
# frontmatter `hooks:` declarations, so the root copies carry NO hooks:
# block — plugin-lane Layer-0 timeout injection is the hooks/hooks.json
# PreToolUse entry instead. The legacy /update-zskills lane keeps the
# .claude/agents/ copies WITH the frontmatter hooks: block (Invariant 10 —
# legacy Layer-0 delivery is frontmatter).
#
# This suite pins, for each of {verifier, implementer}:
#   1. root agents/<name>.md exists
#   2. .claude/agents/<name>.md exists
#   3. the .claude/agents copy STILL carries the frontmatter hooks: block
#      referencing inject-bash-timeout.sh (legacy Layer-0 — Invariant 10)
#   4. the root copy carries NO hooks: block (plugin agents ignore it;
#      a hooks: block here would silently mask a missing hooks.json entry)
#   5. the two files are byte-identical MODULO the frontmatter hooks: block
#      (strip the hooks: block from the .claude copy → must equal the root
#      copy exactly — frontmatter keys AND body both pinned)
#
# If 5 ever fails, the two lanes are dispatching agents with diverged
# instructions — fix the drift by re-deriving the root copy from the
# .claude/agents source (or vice versa), never by relaxing this test.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# strip_hooks_block <file> — print the file with the frontmatter `hooks:`
# block removed. Only lines INSIDE the first ---...--- frontmatter block are
# candidates: from a top-level `hooks:` key through the last following
# indented (or list-item) line. Body content is passed through verbatim.
strip_hooks_block() {
  awk '
    /^---$/ { fm++; print; next }
    fm == 1 {
      if ($0 ~ /^hooks:/) { inhooks = 1; next }
      if (inhooks && $0 ~ /^[[:space:]]/) { next }
      inhooks = 0
      print; next
    }
    { print }
  ' "$1"
}

echo "=== root agents/ vs .claude/agents parity (1A) ==="

for name in verifier implementer; do
  ROOT="agents/$name.md"
  LEGACY=".claude/agents/$name.md"

  # 1. root copy exists.
  if [ -f "$ROOT" ]; then
    pass "[$name] 1. root $ROOT present"
  else
    fail "[$name] 1. root $ROOT MISSING"
    continue
  fi

  # 2. legacy copy exists.
  if [ -f "$LEGACY" ]; then
    pass "[$name] 2. legacy $LEGACY present"
  else
    fail "[$name] 2. legacy $LEGACY MISSING"
    continue
  fi

  # Frontmatter extraction (between the first two --- lines).
  root_fm="$(awk '/^---$/{c++; if (c==2) exit; next} c==1' "$ROOT")"
  legacy_fm="$(awk '/^---$/{c++; if (c==2) exit; next} c==1' "$LEGACY")"

  # 3. legacy frontmatter STILL carries hooks: + inject-bash-timeout.sh
  #    (Invariant 10 — the legacy lane's Layer-0 delivery is frontmatter).
  if printf '%s\n' "$legacy_fm" | grep -q '^hooks:' \
     && printf '%s\n' "$legacy_fm" | grep -q 'inject-bash-timeout.sh'; then
    pass "[$name] 3. legacy copy keeps frontmatter hooks: block (inject-bash-timeout.sh)"
  else
    fail "[$name] 3. legacy copy LOST its frontmatter hooks: block (Invariant 10 violation)"
  fi

  # 4. root frontmatter carries NO hooks: block and NO inject reference.
  if printf '%s\n' "$root_fm" | grep -q '^hooks:'; then
    fail "[$name] 4. root copy carries a frontmatter hooks: block (plugin agents ignore it — remove; Layer-0 is hooks.json)"
  elif printf '%s\n' "$root_fm" | grep -q 'inject-bash-timeout'; then
    fail "[$name] 4. root copy frontmatter references inject-bash-timeout (should not)"
  else
    pass "[$name] 4. root copy frontmatter has NO hooks: block"
  fi

  # 5. byte-identical modulo the frontmatter hooks: block.
  if diff -u <(strip_hooks_block "$LEGACY") "$ROOT" > /tmp/.agents-parity-diff 2>&1; then
    pass "[$name] 5. root copy == legacy copy modulo frontmatter hooks: block"
  else
    fail "[$name] 5. root and legacy copies DIVERGE beyond the hooks: block"
    head -20 /tmp/.agents-parity-diff | sed 's/^/      /'
  fi
  rm -f /tmp/.agents-parity-diff

  # 6. name: field sanity on both copies.
  if printf '%s\n' "$root_fm" | grep -q "^name: $name$" \
     && printf '%s\n' "$legacy_fm" | grep -q "^name: $name$"; then
    pass "[$name] 6. both copies declare name: $name"
  else
    fail "[$name] 6. name: $name missing from a copy's frontmatter"
  fi
done

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
