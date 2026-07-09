#!/bin/bash
# tests/test-porting-probe-kit.sh — container-runnable suite for the Codex
# porting probe kit (CODEX_PORT_PLAN Phase 0, WI 0.5). No codex binary is
# required: the suite exercises --list purity, the absent-codex refusal, the
# --validate schema gate (sample fixture + mutated copies), the summary-line
# format (via a full run against a no-op fake codex — which also proves the
# kit never fabricates a `pass` without positive evidence), and a static
# portability self-check (Git-Bash/BSD discipline, mechanically pinned).
#
# pass/fail inline (mirrors tests/test-resolve-python.sh:23-24).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KIT="$REPO_ROOT/scripts/porting/codex-probe.sh"
SAMPLE="$REPO_ROOT/tests/fixtures/porting/probe-results-sample.json"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

PYTHON="$(command -v python3 || command -v python || true)"
if [ -z "$PYTHON" ]; then
  echo "SKIP: no python3/python available (required by the kit's --validate mode)" >&2
  echo "Results: 0 passed, 0 failed (of 0)"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zskills-probe-kit-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

if [ ! -f "$KIT" ]; then
  fail "kit not found at $KIT"
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
  exit 1
fi

# ── 1. --list stdout purity ─────────────────────────────────────────────────
# Exactly one probe id per line on STDOUT; the count header goes to STDERR
# and carries the same count. Works without codex. The >= 25 floor is the
# plan's anti-vacuous minimum (WI 0.2's pinned minimum set).
LIST_OUT="$WORK/list.out"
LIST_ERR="$WORK/list.err"
bash "$KIT" --list >"$LIST_OUT" 2>"$LIST_ERR"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "--list exits 0"
else
  fail "--list exited $rc"
fi

STDOUT_N="$(grep -c '' "$LIST_OUT" 2>/dev/null || echo 0)"
HEADER_N=""
if [[ "$(cat "$LIST_ERR")" =~ ([0-9]+)[[:space:]]+probes ]]; then
  HEADER_N="${BASH_REMATCH[1]}"
fi
if [ -n "$HEADER_N" ] && [ "$STDOUT_N" -eq "$HEADER_N" ]; then
  pass "--list stdout line count ($STDOUT_N) equals the stderr header count ($HEADER_N)"
else
  fail "--list stdout line count ($STDOUT_N) != stderr header count ('${HEADER_N:-none}')"
fi
if [ "$STDOUT_N" -ge 25 ]; then
  pass "--list registry size $STDOUT_N >= 25 (WI 0.2 minimum set)"
else
  fail "--list registry size $STDOUT_N < 25"
fi
if grep -qEv '^[a-z0-9][a-z0-9.-]*$' "$LIST_OUT"; then
  fail "--list stdout is not pure: non-id line(s): $(grep -Ev '^[a-z0-9][a-z0-9.-]*$' "$LIST_OUT" | sed -n '1p')"
else
  pass "--list stdout is pure (every line is a probe id)"
fi
if sort "$LIST_OUT" | uniq -d | grep -q .; then
  fail "--list contains duplicate ids: $(sort "$LIST_OUT" | uniq -d | tr '\n' ' ')"
else
  pass "--list ids are unique"
fi

# ── 2. absent-codex refusal ─────────────────────────────────────────────────
# Hermetic even on a box that HAS codex: a stub dir with `codex`/`codex.cmd`
# that FAIL their --version probe-run is prepended to PATH — the resolver
# must reject them (probe-RUN doctrine: existence on PATH is not enough) and
# refuse: non-zero exit, the pinned stderr message, and NO output file.
STUB="$WORK/stubbin"
mkdir -p "$STUB"
for name in codex codex.cmd; do
  printf '#!/bin/sh\necho "stub: not a working codex" >&2\nexit 1\n' > "$STUB/$name"
  chmod +x "$STUB/$name"
done
REFUSAL_OUT="$WORK/refusal-results.json"
rm -f "$REFUSAL_OUT"
PATH="$STUB:$PATH" bash "$KIT" --out "$REFUSAL_OUT" \
  >"$WORK/refusal.stdout" 2>"$WORK/refusal.stderr" </dev/null
rc=$?
if [ "$rc" -ne 0 ]; then
  pass "absent-codex refusal exits non-zero (rc=$rc)"
else
  fail "absent-codex refusal exited 0"
fi
if grep -q 'codex CLI not found' "$WORK/refusal.stderr"; then
  pass "refusal stderr carries 'codex CLI not found'"
else
  fail "refusal stderr missing 'codex CLI not found': $(sed -n '1,2p' "$WORK/refusal.stderr")"
fi
if [ ! -e "$REFUSAL_OUT" ]; then
  pass "refusal wrote NOTHING (output file does not exist)"
else
  fail "refusal left an output file at $REFUSAL_OUT"
fi
if [ ! -e "$REFUSAL_OUT.tmp" ]; then
  pass "refusal left no .tmp partial either"
else
  fail "refusal left a partial at $REFUSAL_OUT.tmp"
fi

# ── 3. --validate: sample fixture passes ────────────────────────────────────
if [ ! -f "$SAMPLE" ]; then
  fail "sample fixture not found at $SAMPLE"
else
  if bash "$KIT" --validate "$SAMPLE" >"$WORK/validate-sample.out" 2>&1; then
    pass "--validate passes the shipped sample fixture"
  else
    fail "--validate rejected the sample fixture: $(sed -n '1,3p' "$WORK/validate-sample.out")"
  fi
  if grep -q 'SAMPLE' "$SAMPLE"; then
    pass "sample fixture is clearly marked as SAMPLE"
  else
    fail "sample fixture carries no SAMPLE marking"
  fi
fi

# ── 4. --validate: mutated copies fail ──────────────────────────────────────
# 4a. one probe id deleted → non-zero, and the output NAMES the missing id.
MUT_MISSING="$WORK/mutated-missing-id.json"
DELETED_ID="$("$PYTHON" -c '
import json, sys
doc = json.load(open(sys.argv[1]))
pid = sorted(doc["results"])[0]
del doc["results"][pid]
json.dump(doc, open(sys.argv[2], "w"), indent=2)
print(pid)
' "$SAMPLE" "$MUT_MISSING")"
if bash "$KIT" --validate "$MUT_MISSING" >"$WORK/validate-missing.out" 2>&1; then
  fail "--validate accepted a copy with probe id '$DELETED_ID' deleted"
else
  pass "--validate rejects a copy with a probe id deleted"
fi
if grep -q "$DELETED_ID" "$WORK/validate-missing.out"; then
  pass "--validate names the missing id ($DELETED_ID)"
else
  fail "--validate did not name the missing id ($DELETED_ID): $(sed -n '1,3p' "$WORK/validate-missing.out")"
fi

# 4b. bad status enum → non-zero.
MUT_STATUS="$WORK/mutated-bad-status.json"
"$PYTHON" -c '
import json, sys
doc = json.load(open(sys.argv[1]))
pid = sorted(doc["results"])[0]
doc["results"][pid]["status"] = "bogus"
json.dump(doc, open(sys.argv[2], "w"), indent=2)
' "$SAMPLE" "$MUT_STATUS"
if bash "$KIT" --validate "$MUT_STATUS" >"$WORK/validate-status.out" 2>&1; then
  fail "--validate accepted a status outside the pass/fail/skip enum"
else
  pass "--validate rejects a status outside the pass/fail/skip enum"
fi

# 4c. missing codex_version → non-zero.
MUT_CV="$WORK/mutated-no-codex-version.json"
"$PYTHON" -c '
import json, sys
doc = json.load(open(sys.argv[1]))
del doc["codex_version"]
json.dump(doc, open(sys.argv[2], "w"), indent=2)
' "$SAMPLE" "$MUT_CV"
if bash "$KIT" --validate "$MUT_CV" >"$WORK/validate-cv.out" 2>&1; then
  fail "--validate accepted a copy with codex_version missing"
else
  pass "--validate rejects a copy with codex_version missing"
fi

# 4d. empty codex_version → non-zero (the check is non-EMPTY, not just present).
MUT_CVE="$WORK/mutated-empty-codex-version.json"
"$PYTHON" -c '
import json, sys
doc = json.load(open(sys.argv[1]))
doc["codex_version"] = ""
json.dump(doc, open(sys.argv[2], "w"), indent=2)
' "$SAMPLE" "$MUT_CVE"
if bash "$KIT" --validate "$MUT_CVE" >"$WORK/validate-cve.out" 2>&1; then
  fail "--validate accepted an EMPTY codex_version"
else
  pass "--validate rejects an empty codex_version"
fi

# 4e. wrong schema tag → non-zero.
MUT_SCHEMA="$WORK/mutated-schema-tag.json"
"$PYTHON" -c '
import json, sys
doc = json.load(open(sys.argv[1]))
doc["schema"] = "zskills-codex-probe/v0"
json.dump(doc, open(sys.argv[2], "w"), indent=2)
' "$SAMPLE" "$MUT_SCHEMA"
if bash "$KIT" --validate "$MUT_SCHEMA" >"$WORK/validate-schema.out" 2>&1; then
  fail "--validate accepted a wrong schema tag"
else
  pass "--validate rejects a wrong schema tag"
fi

# ── 5. summary-line format ──────────────────────────────────────────────────
# 5a. static: the kit's summary emitter uses the pinned format.
if grep -q "CODEX-PROBE-SUMMARY: probes=" "$KIT"; then
  pass "kit source carries the pinned CODEX-PROBE-SUMMARY format"
else
  fail "kit source missing the pinned CODEX-PROBE-SUMMARY format"
fi

# 5b. functional: a full run against a NO-OP fake codex (accepts --version,
# does nothing else) must complete, end stdout with a well-formed summary
# whose probes count equals the registry size, produce a results file that
# passes --validate — and, per the honesty rule, must fabricate ZERO passes
# (a no-op codex provides positive evidence for nothing).
FAKE="$WORK/fakebin"
mkdir -p "$FAKE"
printf '#!/bin/sh\nif [ "${1:-}" = "--version" ]; then echo "codex-cli 0.0.0-zskills-fake"; exit 0; fi\nexit 0\n' > "$FAKE/codex"
chmod +x "$FAKE/codex"
FAKE_OUT="$WORK/fake-results.json"
FAKE_TMPDIR="$WORK/fake-tmp"
mkdir -p "$FAKE_TMPDIR"
PATH="$FAKE:$PATH" TMPDIR="$FAKE_TMPDIR" bash "$KIT" --out "$FAKE_OUT" \
  </dev/null >"$WORK/fake-run.stdout" 2>"$WORK/fake-run.stderr"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "fake-codex full run completes (rc=0)"
else
  fail "fake-codex full run exited $rc: $(tail -3 "$WORK/fake-run.stderr" | tr '\n' ' ')"
fi
SUMMARY_LINE="$(tail -n 1 "$WORK/fake-run.stdout")"
if printf '%s\n' "$SUMMARY_LINE" | grep -Eq '^CODEX-PROBE-SUMMARY: probes=[0-9]+ pass=[0-9]+ fail=[0-9]+ skip=[0-9]+$'; then
  pass "final stdout line is a well-formed summary: $SUMMARY_LINE"
else
  fail "final stdout line is not a well-formed summary: '$SUMMARY_LINE'"
fi
if [[ "$SUMMARY_LINE" =~ probes=([0-9]+)\ pass=([0-9]+)\ fail=([0-9]+)\ skip=([0-9]+) ]]; then
  S_N="${BASH_REMATCH[1]}"; S_P="${BASH_REMATCH[2]}"; S_F="${BASH_REMATCH[3]}"; S_S="${BASH_REMATCH[4]}"
  if [ "$S_N" -eq "$STDOUT_N" ]; then
    pass "summary probes count ($S_N) equals the registry size ($STDOUT_N)"
  else
    fail "summary probes count ($S_N) != registry size ($STDOUT_N)"
  fi
  if [ $((S_P + S_F + S_S)) -eq "$S_N" ]; then
    pass "summary tallies are consistent (pass+fail+skip == probes)"
  else
    fail "summary tallies inconsistent: $S_P+$S_F+$S_S != $S_N"
  fi
  if [ "$S_P" -eq 0 ]; then
    pass "no fabricated passes against a no-op codex (pass=0)"
  else
    fail "kit fabricated $S_P pass(es) against a no-op codex — a pass must require positive evidence"
  fi
else
  fail "could not parse summary tallies from: '$SUMMARY_LINE'"
fi
if [ -f "$FAKE_OUT" ]; then
  pass "fake-codex run wrote the results file"
  if bash "$KIT" --validate "$FAKE_OUT" >"$WORK/validate-fake.out" 2>&1; then
    pass "fake-codex results file passes --validate"
  else
    fail "fake-codex results file fails --validate: $(sed -n '1,3p' "$WORK/validate-fake.out")"
  fi
else
  fail "fake-codex run left no results file at $FAKE_OUT"
fi

# ── 6. static portability self-check ────────────────────────────────────────
# Git-Bash/BSD discipline, mechanically pinned (WI 0.5): none of the GNU-only
# forms may appear in the kit.
if grep -En 'readlink -f|mktemp .*--suffix|date -d|realpath -m' "$REPO_ROOT/scripts/porting/codex-probe.sh" >"$WORK/portability-hits.txt"; then
  fail "portability self-check found GNU-only forms: $(tr '\n' ' ' < "$WORK/portability-hits.txt")"
else
  pass "portability self-check clean (no GNU-only forms in the kit)"
fi
# /dev/tty is a bashism MSYS lacks — the kit reads plain stdin.
if grep -qn '/dev/tty' "$REPO_ROOT/scripts/porting/codex-probe.sh"; then
  fail "kit reads /dev/tty (MSYS-unsafe); use plain read -r from stdin"
else
  pass "kit does not touch /dev/tty (mintty-safe prompts)"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
