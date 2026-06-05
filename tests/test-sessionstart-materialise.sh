#!/usr/bin/env bash
# tests/test-sessionstart-materialise.sh
#
# Phase 2 (W2.1, D11, D20, A3) — the SessionStart materialiser writes the
# five consumer-side artifacts into a fresh fixture project's .claude/.
#
# Assertions (>= 9):
#   1-5. All five destinations are written.
#   6.   Materialised *.sh hooks are executable.
#   7.   managed.md carries the rendered substitution tokens (project name).
#   8.   Each artifact carries a kind-appropriate materialiser sentinel
#        (frontmatter YAML-comment / shell-comment line 2 / HTML-comment).
#   9.   mtime is STABLE on a no-change re-run (idempotency).
#   10.  Cross-version upgrade rewrites the artifact (mtime advances) when
#        the plugin version changes.
#   11.  Frontmatter survives — verifier.md still parses as `---`-delimited
#        with its `name:` field intact below the injected sentinel.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MAT="hooks/session-start-materialise.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a FRESH fixture project: a .claude/zskills-config.json + a root
# CLAUDE_TEMPLATE.md (so the materialiser renders managed.md from the live
# template). Fresh = no pre-existing .claude artifacts (lane=fresh).
PROJ="$TMP/proj"
mkdir -p "$PROJ/.claude"
cp "$REPO_ROOT/.claude/zskills-config.json" "$PROJ/.claude/"
cp "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$PROJ/"

PROJECT_NAME="$(python3 -c 'import json;print(json.load(open("'"$PROJ"'/.claude/zskills-config.json")).get("project_name",""))')"

run_mat() {
  env CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/$MAT"
}

echo "=== SessionStart materialiser (fresh fixture) ==="

run_mat

V="$PROJ/.claude/agents/verifier.md"
I="$PROJ/.claude/agents/implementer.md"
H1="$PROJ/.claude/hooks/inject-bash-timeout.sh"
H2="$PROJ/.claude/hooks/verify-response-validate.sh"
M="$PROJ/.claude/rules/zskills/managed.md"

# 1-5. Destinations written.
[ -f "$V" ]  && pass "1. verifier.md written"               || fail "1. verifier.md missing"
[ -f "$I" ]  && pass "2. implementer.md written"            || fail "2. implementer.md missing"
[ -f "$H1" ] && pass "3. inject-bash-timeout.sh written"    || fail "3. inject-bash-timeout.sh missing"
[ -f "$H2" ] && pass "4. verify-response-validate.sh written" || fail "4. verify-response-validate.sh missing"
[ -f "$M" ]  && pass "5. managed.md written"                || fail "5. managed.md missing"

# 6. Hooks executable.
if [ -x "$H1" ] && [ -x "$H2" ]; then
  pass "6. materialised hooks are executable"
else
  fail "6. materialised hooks not executable"
fi

# 7. Substitution token present in managed.md.
if [ -n "$PROJECT_NAME" ] && grep -qF "$PROJECT_NAME" "$M" 2>/dev/null; then
  pass "7. managed.md contains the substituted project name ($PROJECT_NAME)"
elif [ -z "$PROJECT_NAME" ]; then
  # Empty project name in config — assert no unrendered placeholder remains.
  if ! grep -q '{{' "$M" 2>/dev/null; then
    pass "7. managed.md has no unrendered {{...}} placeholders"
  else
    fail "7. managed.md has unrendered placeholders"
  fi
else
  fail "7. managed.md missing the substituted project name"
fi

# 8. Sentinels — kind-appropriate.
if head -n 3 "$V" | grep -Eq '^# zskills-materialised:' \
   && head -n 1 "$V" | grep -q '^---$'; then
  pass "8a. verifier.md sentinel is a YAML-comment inside frontmatter"
else
  fail "8a. verifier.md frontmatter sentinel malformed"
  head -3 "$V" | sed 's/^/      /'
fi
if head -n 2 "$H1" | grep -Eq '^# zskills-materialised:' \
   && head -n 1 "$H1" | grep -q '^#!'; then
  pass "8b. inject-bash-timeout.sh sentinel is a shell-comment on line 2"
else
  fail "8b. hook shell-comment sentinel malformed"
  head -2 "$H1" | sed 's/^/      /'
fi
if head -n 1 "$M" | grep -Eq '^<!-- zskills-materialised: .* -->$'; then
  pass "8c. managed.md sentinel is an HTML-comment on line 1"
else
  fail "8c. managed.md HTML-comment sentinel malformed"
  head -1 "$M" | sed 's/^/      /'
fi

# 9. Idempotency — mtime stable on no-change re-run.
m_before="$(stat -c %Y "$V")"
sleep 1
run_mat
m_after="$(stat -c %Y "$V")"
if [ "$m_before" = "$m_after" ]; then
  pass "9. mtime stable on no-change re-run (idempotent)"
else
  fail "9. mtime advanced on no-change re-run (before=$m_before after=$m_after)"
fi

# 10. Cross-version upgrade — bump the plugin version stamp inside the
#     destination's sentinel so content stays equal-modulo-version (no
#     rewrite expected, mtime stable), THEN change actual body to force a
#     rewrite. Simulate an upgrade by corrupting the sentinelled copy's body
#     but keeping the sentinel; a re-run must restore canonical content.
#     We assert the materialiser overwrites a sentinelled-but-stale file.
{
  # Replace body below the frontmatter sentinel with garbage, keep sentinel.
  printf '%s\n' '---' '# zskills-materialised: 0.0.0' 'GARBAGE BODY' > "$V"
}
sleep 1
run_mat
if grep -q '^name: verifier' "$V" && ! grep -q 'GARBAGE BODY' "$V"; then
  pass "10. cross-version/stale sentinelled artifact is overwritten with canonical content"
else
  fail "10. stale sentinelled artifact was NOT refreshed"
  head -5 "$V" | sed 's/^/      /'
fi

# 11. Frontmatter survival — verifier.md is still a valid `---` block with
#     name: verifier reachable.
if [ "$(head -n 1 "$V")" = "---" ] && grep -q '^name: verifier' "$V"; then
  pass "11. verifier.md frontmatter survives sentinel injection"
else
  fail "11. verifier.md frontmatter broken"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Config seeding: fresh project with NO config ==="

# A truly fresh plugin install has NO .claude/zskills-config.json. The
# materialiser must seed a default (locked-main-pr) config, then the render
# gate passes and all 5 artifacts materialise. Previously this case left the
# consumer with no config and no managed.md, silently.
SEED="$TMP/seedproj"
mkdir -p "$SEED"
# Provide the template at the project root so the renderer has something to
# render (mirrors dogfooding inside the zskills repo).
cp "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$SEED/"

SEED_ERR="$TMP/seed.stderr"
env CLAUDE_PROJECT_DIR="$SEED" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
  bash "$REPO_ROOT/$MAT" 2>"$SEED_ERR"

SEED_CFG="$SEED/.claude/zskills-config.json"

# 12. Config seeded at all.
if [ -f "$SEED_CFG" ]; then
  pass "12. fresh project: default zskills-config.json seeded"
else
  fail "12. fresh project: config NOT seeded"
fi

# 13. Seeded preset is locked-main-pr (landing=pr, main_protected=true).
if [ -f "$SEED_CFG" ]; then
  seed_landing=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["execution"]["landing"])' "$SEED_CFG" 2>/dev/null)
  seed_prot=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["execution"]["main_protected"])' "$SEED_CFG" 2>/dev/null)
  seed_name=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["project_name"])' "$SEED_CFG" 2>/dev/null)
  if [ "$seed_landing" = "pr" ] && [ "$seed_prot" = "True" ] && [ "$seed_name" = "seedproj" ]; then
    pass "13. seeded config is locked-main-pr (landing=pr, main_protected=true, project_name=seedproj)"
  else
    fail "13. seeded config wrong: landing=$seed_landing main_protected=$seed_prot project_name=$seed_name"
  fi
else
  fail "13. seeded config wrong: no config file"
fi

# 13b. Fresh seed defaults output.{plans,issues,reports}_dir to docs/ so a
# brand-new consumer's dashboard + plan-skills find plans in docs/plans out of
# the box (NOT the legacy plans/ fallback the resolver applies to an absent
# output block). This seed MUST stay byte-identical to the /update-zskills
# install scaffold in skills/update-zskills/SKILL.md (asserted symmetric in
# tests/test-skill-conformance.sh).
if [ -f "$SEED_CFG" ]; then
  seed_plans=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["output"]["plans_dir"])' "$SEED_CFG" 2>/dev/null)
  seed_issues=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["output"]["issues_dir"])' "$SEED_CFG" 2>/dev/null)
  seed_reports=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["output"]["reports_dir"])' "$SEED_CFG" 2>/dev/null)
  if [ "$seed_plans" = "docs/plans" ] && [ "$seed_issues" = "docs/issues" ] && [ "$seed_reports" = "docs/reports" ]; then
    pass "13b. seeded config output block = docs/{plans,issues,reports}"
  else
    fail "13b. seeded config output wrong: plans=$seed_plans issues=$seed_issues reports=$seed_reports"
  fi
else
  fail "13b. seeded config output check skipped: no config file"
fi

# 14. All 5 artifacts materialised now that the render gate passes.
if [ -f "$SEED/.claude/agents/verifier.md" ] \
   && [ -f "$SEED/.claude/agents/implementer.md" ] \
   && [ -f "$SEED/.claude/hooks/inject-bash-timeout.sh" ] \
   && [ -f "$SEED/.claude/hooks/verify-response-validate.sh" ] \
   && [ -f "$SEED/.claude/rules/zskills/managed.md" ]; then
  pass "14. all 5 artifacts materialised after config seed"
else
  fail "14. not all artifacts materialised after seed"
fi

# 15. One-time review notice emitted to stderr + marker written.
if grep -q "created a default .claude/zskills-config.json" "$SEED_ERR" \
   && [ -f "$SEED/.zskills/config-seeded-notice" ]; then
  pass "15. one-time config-seeded review notice emitted (+ marker written)"
else
  fail "15. config-seeded notice missing (stderr: $(cat "$SEED_ERR"))"
fi

# 16. Notice is ONE-TIME: a re-run does not re-emit it (marker gate).
SEED_ERR2="$TMP/seed.stderr2"
env CLAUDE_PROJECT_DIR="$SEED" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
  bash "$REPO_ROOT/$MAT" 2>"$SEED_ERR2"
if ! grep -q "created a default .claude/zskills-config.json" "$SEED_ERR2"; then
  pass "16. config-seeded notice is one-time (not re-emitted on re-run)"
else
  fail "16. config-seeded notice re-emitted on re-run"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Config seeding: existing config is NEVER clobbered ==="

# A project that already has a config (any values) must keep it verbatim —
# the materialiser only seeds when ABSENT.
KEEP="$TMP/keepproj"
mkdir -p "$KEEP/.claude"
cp "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$KEEP/"
# A deliberately differently-valued config (cherry-pick / main_protected
# false) — opposite of the locked-main-pr default the seeder would write.
cat > "$KEEP/.claude/zskills-config.json" <<'KEEPCFG'
{
  "$schema": "./zskills-config.schema.json",
  "project_name": "my-existing-project",
  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "feat/"
  }
}
KEEPCFG
KEEP_BEFORE=$(cat "$KEEP/.claude/zskills-config.json")

env CLAUDE_PROJECT_DIR="$KEEP" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
  bash "$REPO_ROOT/$MAT" 2>/dev/null

KEEP_AFTER=$(cat "$KEEP/.claude/zskills-config.json")
if [ "$KEEP_BEFORE" = "$KEEP_AFTER" ]; then
  pass "17. existing config left byte-identical (never clobbered)"
else
  fail "17. existing config was modified by the materialiser"
fi
# 18. And no spurious seed notice for the existing-config case.
if [ ! -f "$KEEP/.zskills/config-seeded-notice" ]; then
  pass "18. no config-seeded notice when config already present"
else
  fail "18. config-seeded notice emitted despite existing config"
fi

echo ""
echo "=== Config seeding: schema copied + co_author empty (#1069) ==="

# A fresh seed must (a) copy zskills-config.schema.json alongside the seeded
# config so the seeded "$schema": "./zskills-config.schema.json" ref resolves
# rather than dangling, and (b) leave commit.co_author empty (the resolver
# fills it) rather than a hardcoded stale model literal.
SEED_SCHEMA="$SEED/.claude/zskills-config.schema.json"
REPO_SCHEMA="$REPO_ROOT/config/zskills-config.schema.json"

# 19. Schema file copied AND byte-equal to the repo source.
if [ -f "$SEED_SCHEMA" ] && cmp -s "$SEED_SCHEMA" "$REPO_SCHEMA"; then
  pass "19. seeded project: zskills-config.schema.json copied (byte-equal to repo source)"
else
  fail "19. seeded schema missing or differs from repo source ($SEED_SCHEMA)"
fi

# 20. Seeded commit.co_author is empty (no hardcoded model literal).
if [ -f "$SEED_CFG" ]; then
  seed_coauthor=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["commit"]["co_author"])' "$SEED_CFG" 2>/dev/null)
  if [ -z "$seed_coauthor" ]; then
    pass "20. seeded commit.co_author is empty"
  else
    fail "20. seeded commit.co_author is not empty: '$seed_coauthor'"
  fi
else
  fail "20. seeded commit.co_author check skipped: no config file"
fi

echo ""
echo "=== Atomic write: injector abort leaves no partial/0-byte artifact (#1079) ==="

# A materialise whose sentinel-injection aborts mid-write must NOT truncate or
# partially write the destination. We point ZSKILLS_PYTHON at a stub that
# PASSES the interpreter version probe (`python -c '...'`, delegated to the
# real python3) but FAILS every other invocation — including the
# inject_sentinel `python - <tmpfile>` form. The materialiser must leave a
# pre-existing dest UNTOUCHED and never create a 0-byte file at an absent dest.
STUB_DIR="$TMP/pystub"
mkdir -p "$STUB_DIR"
REAL_PY="$(command -v python3)"
cat > "$STUB_DIR/python3" <<STUB
#!/usr/bin/env bash
# Delegate the version/-c probes to real python3 so zskills_resolve_python
# accepts this stub; fail (exit 1) on the inject_sentinel "- <tmpfile>" form.
if [ "\$1" = "-c" ]; then
  exec "$REAL_PY" "\$@"
fi
exit 1
STUB
chmod +x "$STUB_DIR/python3"

# (a-i) Pre-existing real artifact at a dest is NOT truncated on injector abort.
ABORT="$TMP/abortproj"
mkdir -p "$ABORT/.claude/agents"
cp "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$ABORT/"
# Seed a config so the materialiser does not early-exit on a missing config.
cp "$REPO_ROOT/.claude/zskills-config.json" "$ABORT/.claude/"
# A pre-existing sentinelled verifier.md (so safe_to_write would normally
# allow an overwrite — the point is the injector aborts BEFORE any write).
PRE_BODY="$(printf '%s\n' '---' '# zskills-materialised: 0.0.0' 'name: verifier' 'PRESERVE ME')"
printf '%s' "$PRE_BODY" > "$ABORT/.claude/agents/verifier.md"
PRE_SIZE="$(stat -c %s "$ABORT/.claude/agents/verifier.md")"

env ZSKILLS_PYTHON="$STUB_DIR/python3" \
    CLAUDE_PROJECT_DIR="$ABORT" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/$MAT" 2>/dev/null || true

AFTER_BODY="$(cat "$ABORT/.claude/agents/verifier.md" 2>/dev/null || echo MISSING)"
AFTER_SIZE="$(stat -c %s "$ABORT/.claude/agents/verifier.md" 2>/dev/null || echo -1)"
if [ "$AFTER_BODY" = "$PRE_BODY" ] && [ "$AFTER_SIZE" = "$PRE_SIZE" ]; then
  pass "21. injector abort leaves pre-existing artifact byte-identical (not truncated)"
else
  fail "21. injector abort truncated/altered the pre-existing artifact (size $PRE_SIZE -> $AFTER_SIZE)"
fi

# (a-ii) Absent dest stays absent (no 0-byte file created) on injector abort.
# The implementer hook dest had no pre-existing file in the abort fixture.
IMPL_DEST="$ABORT/.claude/agents/implementer.md"
if [ ! -e "$IMPL_DEST" ]; then
  pass "22. injector abort leaves an absent dest absent (no 0-byte file created)"
elif [ -f "$IMPL_DEST" ] && [ ! -s "$IMPL_DEST" ]; then
  fail "22. injector abort created a 0-byte implementer.md (partial leftover)"
else
  # A non-empty implementer.md would only appear if injection somehow
  # succeeded — unexpected with the failing stub, but not a partial leftover.
  pass "22. injector abort: implementer.md is non-empty (no partial leftover)"
fi

echo ""
echo "=== Self-heal: a pre-existing 0-byte artifact is overwritten (#1079) ==="

# A prior partial materialise can leave a 0-byte artifact. A subsequent working
# materialise must HEAL it — overwrite the empty file with real sentinelled
# content (safe_to_write treats a 0-byte file as overwritable).
HEAL="$TMP/healproj"
mkdir -p "$HEAL/.claude/agents"
cp "$REPO_ROOT/.claude/zskills-config.json" "$HEAL/.claude/"
cp "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$HEAL/"
# Plant a 0-byte verifier.md (the partial-materialise leftover).
: > "$HEAL/.claude/agents/verifier.md"
[ ! -s "$HEAL/.claude/agents/verifier.md" ] || fail "precondition: planted verifier.md not 0-byte"

env CLAUDE_PROJECT_DIR="$HEAL" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/$MAT" 2>/dev/null

HV="$HEAL/.claude/agents/verifier.md"
if [ -s "$HV" ] \
   && head -n 3 "$HV" | grep -Eq '^# zskills-materialised:' \
   && grep -q '^name: verifier' "$HV"; then
  pass "23. self-heal: 0-byte verifier.md overwritten with real sentinelled content"
else
  fail "23. self-heal: 0-byte verifier.md NOT healed"
  printf '      size=%s\n' "$(stat -c %s "$HV" 2>/dev/null || echo MISSING)"
  head -3 "$HV" 2>/dev/null | sed 's/^/      /'
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
