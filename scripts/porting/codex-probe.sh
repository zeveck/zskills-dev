#!/usr/bin/env bash
# scripts/porting/codex-probe.sh — real-Codex capability probe kit
# (CODEX_PORT_PLAN Phase 0, WIs 0.1–0.3).
#
# Verifies every load-bearing Codex CLI capability claim from the port plan's
# capability map HANDS-ON against a real `codex` binary and emits a
# machine-readable results file (schema `zskills-codex-probe/v1`) — the seed
# of the porting guide's assumptions manifest. Phase 4 of the plan keys its
# triage table on the probe ids below; the ids are the contract.
#
# SELF-CONTAINED, ZERO INSTALL PREREQUISITES: runnable from a bare clone on
# the owner's machine. Needs only bash + Python 3 (+ a real Codex install for
# the run mode). BSD/macOS-safe AND Git-Bash/MSYS-safe: no GNU-only forms of
# the classic offenders (no `-f` canonicalize flags, no GNU-only temp-file
# suffix options, no GNU-only relative-date parsing), no direct
# terminal-device reads (plain `read -r` from stdin, mintty-safe), temp files
# under ${TMPDIR:-/tmp}, and probe-RUN binary resolution (accept `codex` or
# `codex.cmd` only when `<candidate> --version` exits 0 — never a bare
# `command -v`, which latches non-functional shims).
#
# USAGE
#   bash scripts/porting/codex-probe.sh --list
#       Enumerate the probe registry: exactly one probe id per line on
#       STDOUT; a count header goes to STDERR. Works WITHOUT codex.
#   bash scripts/porting/codex-probe.sh --out <path> [--codex-bin <bin>] [--only <id>[,<id>...]]
#       Run the probes against the real codex CLI and write the results JSON
#       atomically (.tmp + move) ONLY on completion. With --only, run just
#       the named subset (for re-verification at release time) — NOTE a
#       subset results file will NOT pass --validate's completeness check.
#   bash scripts/porting/codex-probe.sh --only <id>[,<id>...]
#       Run a subset without writing a results file (observations logged to
#       stderr, summary to stdout).
#   bash scripts/porting/codex-probe.sh --validate <file>
#       Schema-check an existing results file (used by tests and by Phase 4's
#       gate). Exit 0/1.
#
# The final stdout line of a probe run is always:
#   CODEX-PROBE-SUMMARY: probes=<N> pass=<P> fail=<F> skip=<S>
#
# ATTENDED BY DEFINITION. Some probes cannot be scripted end-to-end (Codex's
# trust-review for non-managed hooks is an interactive TUI flow) — those
# print numbered manual steps and read back the observed outcome. This kit
# NEVER tries to drive the Codex TUI from its own terminal. If the Codex TUI
# misbehaves under mintty (a known winpty-class problem), run the manual step
# in Windows Terminal / PowerShell — or run the whole kit inside WSL2, the
# likely zero-friction path on a Windows host — and enter the observed result
# at the prompt here.
#
# TRUST-ESTABLISHMENT ORDERING: the hook-behavior probes
# (hooks.pretooluse.*, hooks.sessionstart.*, hooks.stdin.*) exercise
# non-managed hooks under `codex exec`, and Codex requires explicit user
# trust-review before such hooks first run. The registry orders
# hooks.trust.non-managed-friction BEFORE them so the trust step establishes
# trust for the shared hook fixture project. When running hook probes via
# --only, include hooks.trust.non-managed-friction in the subset — a no-fire
# observed with trust unestablished is recorded `skip` with a reason (an
# ordering artifact), never `fail`.
#
# HONESTY RULE: this kit never FAKES a result. "Ran without error" is never a
# pass — every probe asserts a specific observable behavior (its `asserts`
# field), and a probe that cannot run records `skip` with a reason.
#
# Exit codes: 0 = mode completed (individual probe failures are recorded in
# the results, not the exit code); non-zero = the mode itself could not run
# (bad usage, codex not found, python not found, validation failure).

set -euo pipefail

# ---------------------------------------------------------------------------
# Python resolution — inlined verbatim from hooks/_lib/resolve-python.sh
# (source of truth; byte-equality enforced by tests/test-hook-helper-drift.sh,
# where this script is registered as a RESOLVE_PYTHON_CONSUMERS entry).
# ---------------------------------------------------------------------------

# zskills_resolve_python — print path to a working Python 3 interpreter, or
# empty if none. Probe-RUNS each candidate (existence is NOT enough: on Windows
# `command -v python3` finds the MS Store App-Execution-Alias stub, which exits
# non-zero when run). Honors ZSKILLS_PYTHON. Rejects python2.
zskills_resolve_python() {
  local cand
  for cand in "${ZSKILLS_PYTHON:-}" python3 python; do
    [ -n "$cand" ] || continue
    command -v "$cand" >/dev/null 2>&1 || continue
    if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
      command -v "$cand"; return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Probe registry (WI 0.2) — 25 ids. The ids are the contract: Phase 4 keys
# the assumptions manifest AND the triage table on them. Registry order is
# execution order; hooks.trust.non-managed-friction deliberately precedes the
# hook-behavior probes (trust-establishment ordering, see header).
# ---------------------------------------------------------------------------
PROBE_IDS=(
  skills.discovery.agents-dir
  skills.discovery.claude-skills-path-config
  skills.frontmatter.unknown-ignored
  skills.invocation.dollar-name
  skills.invocation.implicit
  skills.openai-yaml.implicit-invocation-off
  hooks.trust.non-managed-friction
  hooks.pretooluse.deny-envelope
  hooks.pretooluse.exit2-stderr
  hooks.pretooluse.updated-input
  hooks.sessionstart.additional-context
  hooks.stdin.permission-mode
  agents.toml.project-dispatch
  agents.limits.max-depth
  exec.json.thread-id
  exec.output-last-message
  exec.output-schema
  exec.resume.same-session
  exec.resume.prompt-and-json
  exec.resume.session-loss
  agentsmd.cap-32k
  agentsmd.project-doc-max-bytes-raise
  plugins.marketplace.claude-compat
  plugins.env.claude-plugin-root-alias
  sandbox.workspace-write.add-dir
)

# One-line load-bearing assertion per probe id. The load-bearing ones are
# pinned by the plan (Phase 0 WI 0.2) — do not reword them casually; Phase 4
# reads these to triage deviations.
probe_asserts() {
  case "$1" in
    skills.discovery.agents-dir)
      printf '%s' 'A fixture skill under .agents/skills is discovered AND invocable by $name (planted nonce echoed back).' ;;
    skills.discovery.claude-skills-path-config)
      printf '%s' 'A [[skills.config]] extra path pointing at .claude/skills makes a skill there discoverable and invocable.' ;;
    skills.frontmatter.unknown-ignored)
      printf '%s' 'Unknown (Claude-specific) frontmatter keys are silently ignored — the skill still parses and invokes.' ;;
    skills.invocation.dollar-name)
      printf '%s' 'A $skillname mention embedded in a longer prompt triggers the skill.' ;;
    skills.invocation.implicit)
      printf '%s' 'A description-matching prompt with no explicit mention auto-triggers the skill.' ;;
    skills.openai-yaml.implicit-invocation-off)
      printf '%s' 'Per-skill agents/openai.yaml policy.allow_implicit_invocation: false suppresses implicit auto-trigger.' ;;
    hooks.trust.non-managed-friction)
      printf '%s' 'Non-managed hooks require explicit user trust-review before their first run (owner-observed in the TUI).' ;;
    hooks.pretooluse.deny-envelope)
      printf '%s' "A deny envelope actually BLOCKS the tool call — the gated command's side effect does NOT occur." ;;
    hooks.pretooluse.exit2-stderr)
      printf '%s' 'Exit-2 + stderr blocks the tool call and the stderr text is surfaced to the model.' ;;
    hooks.pretooluse.updated-input)
      printf '%s' 'The MUTATED input is what executes — the side effect matches the mutated value, not the original.' ;;
    hooks.sessionstart.additional-context)
      printf '%s' 'Injected additionalContext is visible to the model — it can echo a planted nonce.' ;;
    hooks.stdin.permission-mode)
      printf '%s' "The hook's stdin JSON carries permission_mode, tool_name, tool_input." ;;
    agents.toml.project-dispatch)
      printf '%s' 'A project .codex/agents/*.toml subagent is dispatchable and its developer_instructions govern its reply.' ;;
    agents.limits.max-depth)
      printf '%s' 'Nested subagent dispatch is refused at the default max_depth=1 (depth-2 nonce absent from the reply).' ;;
    exec.json.thread-id)
      printf '%s' 'The thread.started JSONL event carries a thread id that a subsequent exec resume <ID> accepts.' ;;
    exec.output-last-message)
      printf '%s' 'The --output-last-message file contains the final message.' ;;
    exec.output-schema)
      printf '%s' 'A schema-violating self-report is surfaced (observed behavior recorded either way).' ;;
    exec.resume.same-session)
      printf '%s' 'Resume with an explicit <ID> reaches the SAME durable session: a nonce planted in turn 1 is visible to the resumed turn.' ;;
    exec.resume.prompt-and-json)
      printf '%s' 'codex exec resume <ID> --json "<new prompt>" accepts the positional prompt NON-interactively and emits JSONL for the resumed turn.' ;;
    exec.resume.session-loss)
      printf '%s' 'Resume of a bogus/deleted id fails with a non-zero, distinguishable error — NOT a silent fresh session.' ;;
    agentsmd.cap-32k)
      printf '%s' 'A nonce placed PAST the 32 KiB boundary of AGENTS.md is NOT visible to the model.' ;;
    agentsmd.project-doc-max-bytes-raise)
      printf '%s' 'After raising project_doc_max_bytes, the past-32-KiB nonce IS visible to the model.' ;;
    plugins.marketplace.claude-compat)
      printf '%s' "Codex's marketplace flow reads a legacy .claude-plugin/marketplace.json and can install the listed plugin." ;;
    plugins.env.claude-plugin-root-alias)
      printf '%s' 'A plugin hook script observes a non-empty CLAUDE_PLUGIN_ROOT equal to PLUGIN_ROOT.' ;;
    sandbox.workspace-write.add-dir)
      printf '%s' 'A write OUTSIDE the workspace at the added dir SUCCEEDS, and the same write WITHOUT --add-dir fails.' ;;
    *)
      printf '%s' 'unknown probe id' ;;
  esac
}

# load_bearing = true for every id named in Phase 4's triage table (WI 4.0b)
# — exactly the ids whose assertions the plan pins verbatim.
probe_load_bearing() {
  case "$1" in
    skills.discovery.agents-dir|\
    hooks.pretooluse.deny-envelope|\
    hooks.pretooluse.exit2-stderr|\
    hooks.pretooluse.updated-input|\
    hooks.sessionstart.additional-context|\
    hooks.stdin.permission-mode|\
    exec.json.thread-id|\
    exec.output-last-message|\
    exec.output-schema|\
    exec.resume.same-session|\
    exec.resume.prompt-and-json|\
    exec.resume.session-loss|\
    agentsmd.cap-32k|\
    agentsmd.project-doc-max-bytes-raise|\
    plugins.env.claude-plugin-root-alias|\
    sandbox.workspace-write.add-dir)
      printf 'true' ;;
    *)
      printf 'false' ;;
  esac
}

# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------
usage() {
  sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'
}

MODE=""
OUT_PATH=""
ONLY=""
VALIDATE_FILE=""
CODEX_BIN_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --list) MODE="list" ;;
    --out)
      [ $# -ge 2 ] || { echo "ERROR: --out requires a path argument" >&2; exit 2; }
      OUT_PATH="$2"; shift ;;
    --only)
      [ $# -ge 2 ] || { echo "ERROR: --only requires a comma-separated id list" >&2; exit 2; }
      ONLY="$2"; shift ;;
    --validate)
      [ $# -ge 2 ] || { echo "ERROR: --validate requires a file argument" >&2; exit 2; }
      MODE="validate"; VALIDATE_FILE="$2"; shift ;;
    --codex-bin)
      [ $# -ge 2 ] || { echo "ERROR: --codex-bin requires an argument" >&2; exit 2; }
      CODEX_BIN_OVERRIDE="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

# --list: works without codex AND without python.
if [ "$MODE" = "list" ]; then
  printf 'codex-probe registry: %d probes\n' "${#PROBE_IDS[@]}" >&2
  for _id in "${PROBE_IDS[@]}"; do
    printf '%s\n' "$_id"
  done
  exit 0
fi

if [ "$MODE" != "validate" ] && [ -z "$OUT_PATH" ] && [ -z "$ONLY" ]; then
  echo "ERROR: nothing to do — pass --list, --out <path>, --only <ids>, or --validate <file> (see --help)" >&2
  exit 2
fi

# Python is required for --validate and for probe runs (JSON handling; per
# zskills convention there is no jq).
PYTHON="$(zskills_resolve_python || true)"
if [ -z "$PYTHON" ]; then
  echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# --validate (WI 0.3): schema tag, non-empty codex_version, every registry id
# present, every status in the pass/fail/skip enum.
# ---------------------------------------------------------------------------
if [ "$MODE" = "validate" ]; then
  if [ ! -f "$VALIDATE_FILE" ]; then
    echo "VALIDATE FAIL: no such file: $VALIDATE_FILE" >&2
    exit 1
  fi
  if P_IDS="$(printf '%s\n' "${PROBE_IDS[@]}")" "$PYTHON" - "$VALIDATE_FILE" <<'PY'
import json, os, sys

path = sys.argv[1]
ids = [i for i in os.environ["P_IDS"].splitlines() if i]
ok = True

def bad(msg):
    global ok
    ok = False
    print("VALIDATE FAIL: " + msg)

try:
    with open(path) as f:
        doc = json.load(f)
except Exception as e:
    print("VALIDATE FAIL: not parseable JSON: %s" % e)
    sys.exit(1)

if not isinstance(doc, dict):
    print("VALIDATE FAIL: top level is not a JSON object")
    sys.exit(1)

if doc.get("schema") != "zskills-codex-probe/v1":
    bad("schema tag is %r, want 'zskills-codex-probe/v1'" % (doc.get("schema"),))

cv = doc.get("codex_version")
if not (isinstance(cv, str) and cv.strip()):
    bad("codex_version missing or empty")

results = doc.get("results")
if not isinstance(results, dict):
    bad("results missing or not an object")
    results = {}

for pid in ids:
    if pid not in results:
        bad("missing probe id: %s" % pid)

allowed = ("pass", "fail", "skip")
for pid in sorted(results):
    entry = results[pid]
    if not isinstance(entry, dict):
        bad("result for %s is not an object" % pid)
        continue
    st = entry.get("status")
    if st not in allowed:
        bad("status for %s is %r, not one of pass/fail/skip" % (pid, st))

sys.exit(0 if ok else 1)
PY
  then
    echo "VALIDATE OK: $VALIDATE_FILE"
    exit 0
  else
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Run mode — resolve the codex binary FIRST (WI 0.1): probe-RUN candidates,
# accept only one where `<candidate> --version` exits 0. Refuse (non-zero,
# write NOTHING) when none resolves.
# ---------------------------------------------------------------------------
resolve_codex() {
  local cand
  for cand in "${CODEX_BIN_OVERRIDE:-}" codex codex.cmd; do
    [ -n "$cand" ] || continue
    command -v "$cand" >/dev/null 2>&1 || continue
    if "$cand" --version >/dev/null 2>&1; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 1
}

CODEX="$(resolve_codex || true)"
if [ -z "$CODEX" ]; then
  echo "ERROR: codex CLI not found — this kit must run on a machine with Codex installed" >&2
  exit 1
fi
CODEX_VERSION="$("$CODEX" --version 2>/dev/null | sed -n '1p')"
PLATFORM="$(uname -srm 2>/dev/null || uname -s)"
PROBED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Validate the --only subset against the registry before doing anything.
want_probe() {
  # $1 = id. True when no --only filter, or the id is in the filter list.
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in
    *",$1,"*) return 0 ;;
  esac
  return 1
}
if [ -n "$ONLY" ]; then
  _rest="$ONLY"
  while [ -n "$_rest" ]; do
    _tok="${_rest%%,*}"
    if [ "$_rest" = "$_tok" ]; then _rest=""; else _rest="${_rest#*,}"; fi
    [ -n "$_tok" ] || continue
    _found=0
    for _id in "${PROBE_IDS[@]}"; do
      [ "$_id" = "$_tok" ] && { _found=1; break; }
    done
    if [ "$_found" -ne 1 ]; then
      echo "ERROR: --only names an unknown probe id: $_tok (see --list)" >&2
      exit 2
    fi
  done
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zskills-codex-probe.XXXXXX")"
RESULTS_DIR="$WORK/results"
mkdir -p "$RESULTS_DIR"

log() { printf '%s\n' "$*" >&2; }

log "codex-probe: codex = $CODEX ($CODEX_VERSION)"
log "codex-probe: fixtures under $WORK (kept for inspection)"

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
new_nonce() { printf '%s%s%s' "$$" "$(date -u +%H%M%S)" "$RANDOM"; }

new_proj() {
  # $1 = subdir name; prints the absolute fixture project path. git-inits it
  # when git is available (codex prefers running inside a repo).
  local d="$WORK/$1"
  mkdir -p "$d"
  if command -v git >/dev/null 2>&1; then
    (cd "$d" && git init -q) >/dev/null 2>&1 || true
  fi
  printf '%s\n' "$d"
}

codex_exec() {
  # $1 = project dir; rest = args to `codex exec`. Non-interactive: stdin is
  # /dev/null so a prompting codex can never hang the kit.
  local proj="$1"; shift
  ( cd "$proj" && "$CODEX" exec --skip-git-repo-check "$@" ) </dev/null
}

codex_exec_resume() {
  # $1 = project dir, $2 = thread/session id; rest = args. No extra flags
  # before the `resume` subcommand (flag placement there is unverified).
  local proj="$1" tid="$2"; shift 2
  ( cd "$proj" && "$CODEX" exec resume "$tid" "$@" ) </dev/null
}

out_contains() { [ -f "$1" ] && grep -q -- "$2" "$1" 2>/dev/null; }

ask_owner() {
  # $1 = prompt. Prints the owner's answer (empty on EOF — non-interactive
  # runs make interactive probes record `skip`). Plain read -r from the
  # kit's stdin: mintty-safe, no direct terminal-device read.
  local ans=""
  printf '%s' "$1" >&2
  if ! read -r ans; then ans=""; fi
  printf '%s\n' "$ans"
}

make_skill() {
  # $1 = skill dir, $2 = skill name, $3 = nonce. The description mentions the
  # "probe nonce token" so implicit-invocation probes have a matchable hook.
  mkdir -p "$1"
  cat > "$1/SKILL.md" <<EOF
---
name: $2
description: Reports the zskills probe nonce token when the user asks for the probe nonce token.
---

When this skill is invoked, reply with exactly this token and nothing else:
ZSKILLS-SKILL-NONCE-$3
EOF
}

# ---------------------------------------------------------------------------
# Shared hook fixture project. ONE project carries all hook fixtures so ONE
# trust-review (interactive TUI step) covers every hook-behavior probe. The
# PreToolUse hook is a dispatcher whose behavior is switched per-probe via a
# mode file — the hook FILES never change after trust is established.
# ---------------------------------------------------------------------------
TRUST_ESTABLISHED=0
HOOK_PROJ=""
STDERR_NONCE=""
CTX_NONCE=""

ensure_hook_project() {
  [ -n "$HOOK_PROJ" ] && return 0
  HOOK_PROJ="$(new_proj hook-proj)"
  STDERR_NONCE="$(new_nonce)"
  CTX_NONCE="$(new_nonce)"
  mkdir -p "$HOOK_PROJ/.codex/hooks"

  # PreToolUse dispatcher: always dumps its stdin and drops a fired marker,
  # then behaves per the mode file (allow / deny / exit2 / mutate).
  cat > "$HOOK_PROJ/.codex/hooks/pretool.sh" <<HOOK
#!/usr/bin/env bash
IN="\$(cat)"
printf '%s' "\$IN" > "$HOOK_PROJ/hook-stdin.json"
: > "$HOOK_PROJ/hook-fired"
MODE="\$(cat "$HOOK_PROJ/hookmode" 2>/dev/null || echo allow)"
case "\$MODE" in
  deny)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"zskills codex-probe deny fixture"}}'
    ;;
  exit2)
    echo "ZSKILLS-PROBE-STDERR-$STDERR_NONCE" >&2
    exit 2
    ;;
  mutate)
    printf '%s' "\$IN" | "$PYTHON" -c '
import json, sys
env = json.load(sys.stdin)
ti = env.get("tool_input", env)
if not isinstance(ti, dict):
    ti = {}
cmd = ti.get("command", "")
ti["command"] = cmd.replace("probe-orig", "probe-mutated")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": ti}}))
'
    ;;
  *)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    ;;
esac
HOOK
  chmod +x "$HOOK_PROJ/.codex/hooks/pretool.sh"

  # SessionStart hook: drops a fired marker and injects a nonce as
  # additionalContext.
  cat > "$HOOK_PROJ/.codex/hooks/sessionstart.sh" <<HOOK
#!/usr/bin/env bash
cat >/dev/null
: > "$HOOK_PROJ/ss-fired"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Planted probe context token: ZSKILLS-PROBE-CONTEXT-$CTX_NONCE"}}'
HOOK
  chmod +x "$HOOK_PROJ/.codex/hooks/sessionstart.sh"

  printf 'allow\n' > "$HOOK_PROJ/hookmode"

  # hooks.json (Claude-contract shape) — written via python for quoting
  # safety on paths with spaces.
  HP="$HOOK_PROJ" "$PYTHON" - <<'PY'
import json, os
hp = os.environ["HP"]
doc = {
    "hooks": {
        "PreToolUse": [
            {"hooks": [{"type": "command",
                        "command": 'bash "%s"' % (hp + "/.codex/hooks/pretool.sh")}]}
        ],
        "SessionStart": [
            {"hooks": [{"type": "command",
                        "command": 'bash "%s"' % (hp + "/.codex/hooks/sessionstart.sh")}]}
        ],
    }
}
with open(hp + "/.codex/hooks.json", "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
}

# Common skip/fail classification for a hook probe whose hook did not fire:
# with trust unestablished that is an ordering artifact → skip, never fail.
hook_no_fire() {
  # $1 = human description of the missing evidence
  if [ "$TRUST_ESTABLISHED" = 1 ]; then
    PROBE_STATUS=fail
    PROBE_OBSERVED="$1 (trust was established, so this is a real no-fire)"
  else
    PROBE_STATUS=skip
    PROBE_OBSERVED="$1"
    PROBE_NOTES="trust unestablished — ordering artifact, not a capability verdict; run hooks.trust.non-managed-friction first (include it in any --only subset)"
  fi
}

# ---------------------------------------------------------------------------
# Plugin fixture (marketplace + env-alias probes)
# ---------------------------------------------------------------------------
PLUGIN_INSTALLED=0
PLUGIN_MKT=""
PLUGIN_ENV_DUMP=""

ensure_plugin_fixture() {
  [ -n "$PLUGIN_MKT" ] && return 0
  PLUGIN_MKT="$WORK/marketplace"
  PLUGIN_ENV_DUMP="$WORK/plugin-env-dump"
  mkdir -p "$PLUGIN_MKT/.claude-plugin" \
           "$PLUGIN_MKT/zskills-probe-plugin/.codex-plugin" \
           "$PLUGIN_MKT/zskills-probe-plugin/hooks"
  MKT="$PLUGIN_MKT" DUMP="$PLUGIN_ENV_DUMP" "$PYTHON" - <<'PY'
import json, os
mkt = os.environ["MKT"]
dump = os.environ["DUMP"]

# LEGACY manifest — this is exactly what the claude-compat probe probes.
marketplace = {
    "name": "zskills-probe-marketplace",
    "owner": {"name": "zskills-probe"},
    "plugins": [
        {"name": "zskills-probe-plugin",
         "source": "./zskills-probe-plugin",
         "description": "zskills codex-probe fixture plugin"}
    ],
}
with open(mkt + "/.claude-plugin/marketplace.json", "w") as f:
    json.dump(marketplace, f, indent=2)
    f.write("\n")

plugin = {
    "name": "zskills-probe-plugin",
    "version": "0.0.1",
    "description": "zskills codex-probe fixture plugin",
}
with open(mkt + "/zskills-probe-plugin/.codex-plugin/plugin.json", "w") as f:
    json.dump(plugin, f, indent=2)
    f.write("\n")

# SessionStart hook dumps both env vars inline (no plugin-root path needed to
# LOCATE a script — that would presuppose the alias under test).
cmd = ("bash -c 'printf \"CPR=%s\\nPR=%s\\n\" "
       "\"$CLAUDE_PLUGIN_ROOT\" \"$PLUGIN_ROOT\" > \"" + dump + "\"'")
hooks = {
    "hooks": {
        "SessionStart": [
            {"hooks": [{"type": "command", "command": cmd}]}
        ]
    }
}
with open(mkt + "/zskills-probe-plugin/hooks/hooks.json", "w") as f:
    json.dump(hooks, f, indent=2)
    f.write("\n")
PY
}

# ---------------------------------------------------------------------------
# Probe implementations. Each sets PROBE_STATUS / PROBE_EXPECTED /
# PROBE_OBSERVED / PROBE_NOTES. Every `pass` requires POSITIVE evidence
# (a planted nonce echoed, a marker file present, keys observed) — never
# mere absence of an error.
# ---------------------------------------------------------------------------

probe_skills_discovery_agents_dir() {
  local proj nonce prompt rc=0 outf
  proj="$(new_proj skill-agents-dir)"
  nonce="$(new_nonce)"
  outf="$WORK/skill-agents-dir.out"
  make_skill "$proj/.agents/skills/probe-nonce-skill" "probe-nonce-skill" "$nonce"
  PROBE_EXPECTED="skill under .agents/skills is discovered; \$probe-nonce-skill invocation echoes ZSKILLS-SKILL-NONCE-$nonce"
  prompt='Use $probe-nonce-skill and reply with only the token it provides.'
  codex_exec "$proj" --output-last-message "$outf" "$prompt" >"$WORK/skill-agents-dir.log" 2>&1 || rc=$?
  if out_contains "$outf" "ZSKILLS-SKILL-NONCE-$nonce"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="nonce echoed from the fixture skill (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="nonce NOT echoed (rc=$rc); last message: $(sed -n '1,3p' "$outf" 2>/dev/null | tr '\n' ' ')"
    PROBE_NOTES="transcript: $WORK/skill-agents-dir.log"
  fi
}

probe_skills_discovery_claude_skills_path_config() {
  local proj nonce prompt rc=0 outf
  proj="$(new_proj skill-claude-path)"
  nonce="$(new_nonce)"
  outf="$WORK/skill-claude-path.out"
  make_skill "$proj/.claude/skills/probe-claude-skill" "probe-claude-skill" "$nonce"
  mkdir -p "$proj/.codex"
  cat > "$proj/.codex/config.toml" <<EOF
[[skills.config]]
path = ".claude/skills"
EOF
  PROBE_EXPECTED="[[skills.config]] extra path .claude/skills makes probe-claude-skill invocable; nonce echoed"
  prompt='Use $probe-claude-skill and reply with only the token it provides.'
  codex_exec "$proj" --output-last-message "$outf" "$prompt" >"$WORK/skill-claude-path.log" 2>&1 || rc=$?
  if out_contains "$outf" "ZSKILLS-SKILL-NONCE-$nonce"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="nonce echoed from the .claude/skills-path skill (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="nonce NOT echoed (rc=$rc)"
    PROBE_NOTES="config shape is best-effort ([[skills.config]] path=... in <proj>/.codex/config.toml); on fail, verify the config key/location by hand before triage. transcript: $WORK/skill-claude-path.log"
  fi
}

probe_skills_frontmatter_unknown_ignored() {
  local proj nonce prompt rc=0 outf
  proj="$(new_proj skill-frontmatter)"
  nonce="$(new_nonce)"
  outf="$WORK/skill-frontmatter.out"
  mkdir -p "$proj/.agents/skills/probe-frontmatter-skill"
  # Claude-specific keys Codex does not know — the claim is they are ignored.
  cat > "$proj/.agents/skills/probe-frontmatter-skill/SKILL.md" <<EOF
---
name: probe-frontmatter-skill
description: Reports the zskills probe nonce token when the user asks for the probe nonce token.
user-invocable: true
disable-model-invocation: false
allowed-tools: Read, Grep
metadata:
  version: "0.0.0"
---

When this skill is invoked, reply with exactly this token and nothing else:
ZSKILLS-SKILL-NONCE-$nonce
EOF
  PROBE_EXPECTED="skill with unknown Claude frontmatter keys still parses and invokes; nonce echoed"
  prompt='Use $probe-frontmatter-skill and reply with only the token it provides.'
  codex_exec "$proj" --output-last-message "$outf" "$prompt" >"$WORK/skill-frontmatter.log" 2>&1 || rc=$?
  if out_contains "$outf" "ZSKILLS-SKILL-NONCE-$nonce"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="nonce echoed despite unknown frontmatter keys (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="nonce NOT echoed (rc=$rc) — unknown frontmatter may have broken discovery/parse"
    PROBE_NOTES="transcript: $WORK/skill-frontmatter.log"
  fi
}

probe_skills_invocation_dollar_name() {
  local proj nonce prompt rc=0 outf
  proj="$(new_proj skill-dollar)"
  nonce="$(new_nonce)"
  outf="$WORK/skill-dollar.out"
  make_skill "$proj/.agents/skills/probe-dollar-skill" "probe-dollar-skill" "$nonce"
  PROBE_EXPECTED="\$probe-dollar-skill mention embedded mid-prompt triggers the skill; nonce echoed"
  prompt='I am testing skill invocation. Somewhere in this longer request, please use $probe-dollar-skill to fetch the token, then reply with just that token and nothing else.'
  codex_exec "$proj" --output-last-message "$outf" "$prompt" >"$WORK/skill-dollar.log" 2>&1 || rc=$?
  if out_contains "$outf" "ZSKILLS-SKILL-NONCE-$nonce"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="nonce echoed via embedded \$name mention (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="nonce NOT echoed (rc=$rc)"
    PROBE_NOTES="transcript: $WORK/skill-dollar.log"
  fi
}

probe_skills_invocation_implicit() {
  local proj nonce prompt rc=0 outf
  proj="$(new_proj skill-implicit)"
  nonce="$(new_nonce)"
  outf="$WORK/skill-implicit.out"
  make_skill "$proj/.agents/skills/probe-implicit-skill" "probe-implicit-skill" "$nonce"
  PROBE_EXPECTED="description-matching prompt (no mention) auto-triggers the skill; nonce echoed"
  prompt='What is the zskills probe nonce token? Reply with only the token, or NO-TOKEN if you do not know it.'
  codex_exec "$proj" --output-last-message "$outf" "$prompt" >"$WORK/skill-implicit.log" 2>&1 || rc=$?
  if out_contains "$outf" "ZSKILLS-SKILL-NONCE-$nonce"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="nonce echoed with no explicit mention (implicit auto-trigger observed, rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="nonce NOT echoed (rc=$rc); implicit auto-trigger not observed"
    PROBE_NOTES="implicit triggering is model-mediated and may be flaky — on fail, retry once via --only skills.invocation.implicit before triage. transcript: $WORK/skill-implicit.log"
  fi
}

probe_skills_openai_yaml_implicit_invocation_off() {
  local proj nonce prompt rc=0 outf
  proj="$(new_proj skill-yaml-off)"
  nonce="$(new_nonce)"
  outf="$WORK/skill-yaml-off.out"
  make_skill "$proj/.agents/skills/probe-yamloff-skill" "probe-yamloff-skill" "$nonce"
  mkdir -p "$proj/.agents/skills/probe-yamloff-skill/agents"
  cat > "$proj/.agents/skills/probe-yamloff-skill/agents/openai.yaml" <<EOF
policy:
  allow_implicit_invocation: false
EOF
  PROBE_EXPECTED="with allow_implicit_invocation: false, the description-matching prompt does NOT surface the nonce; model answers NO-TOKEN"
  prompt='What is the zskills probe nonce token? Reply with only the token, or NO-TOKEN if you do not know it.'
  codex_exec "$proj" --output-last-message "$outf" "$prompt" >"$WORK/skill-yaml-off.log" 2>&1 || rc=$?
  if out_contains "$outf" "ZSKILLS-SKILL-NONCE-$nonce"; then
    PROBE_STATUS=fail
    PROBE_OBSERVED="nonce WAS echoed — implicit invocation fired despite allow_implicit_invocation: false (rc=$rc)"
  elif out_contains "$outf" "NO-TOKEN"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="model answered NO-TOKEN; nonce suppressed (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="no usable reply (rc=$rc); cannot distinguish suppression from a dead run"
    PROBE_NOTES="transcript: $WORK/skill-yaml-off.log"
  fi
}

probe_hooks_trust_non_managed_friction() {
  ensure_hook_project
  PROBE_EXPECTED="codex TUI demands an explicit trust-review for the non-managed .codex/hooks.json before the hooks first run"
  log ""
  log "MANUAL STEP — hooks.trust.non-managed-friction (this kit never drives the Codex TUI from its own terminal):"
  log "  1) Open a SEPARATE terminal. If the Codex TUI misbehaves under mintty (a known winpty-class"
  log "     problem), use Windows Terminal / PowerShell — or run the whole kit inside WSL2 — and"
  log "     enter the observed result at the prompt below."
  log "  2) cd \"$HOOK_PROJ\""
  log "  3) Run: codex   (interactive TUI). Ask it anything trivial that runs a shell command,"
  log "     e.g. 'run the shell command: true'. Note whether codex asks you to trust/review the"
  log "     non-managed hooks registered in .codex/hooks.json before they run."
  log "  4) If prompted, APPROVE the trust review (this also establishes trust for the later"
  log "     hook-behavior probes). Then exit the TUI."
  local ans
  ans="$(ask_owner 'Did codex require an explicit trust-review for the fixture hooks? [y = prompted & approved / n = no prompt, hooks just ran / s or Enter = skip] ')"
  case "$ans" in
    y|Y)
      PROBE_STATUS=pass
      PROBE_OBSERVED="owner observed a trust-review prompt and approved it"
      TRUST_ESTABLISHED=1
      ;;
    n|N)
      PROBE_STATUS=fail
      PROBE_OBSERVED="owner observed NO trust-review prompt — the friction claim is falsified on this codex version"
      PROBE_NOTES="hooks evidently run without trust-review here; downstream hook probes proceed"
      TRUST_ESTABLISHED=1
      ;;
    *)
      PROBE_STATUS=skip
      PROBE_OBSERVED="owner skipped the manual trust step (answer: '${ans:-<empty>}')"
      PROBE_NOTES="hook-behavior probes that see no hook fire will record skip (ordering artifact)"
      ;;
  esac
}

probe_hooks_pretooluse_deny_envelope() {
  local rc=0
  ensure_hook_project
  PROBE_EXPECTED="PreToolUse hook fires; deny envelope blocks the touch; evidence file absent"
  printf 'deny\n' > "$HOOK_PROJ/hookmode"
  rm -f "$HOOK_PROJ/hook-fired" "$HOOK_PROJ/evidence-deny"
  codex_exec "$HOOK_PROJ" --full-auto \
    "Run exactly this shell command and nothing else: touch \"$HOOK_PROJ/evidence-deny\"" \
    >"$WORK/deny.log" 2>&1 || rc=$?
  if [ ! -f "$HOOK_PROJ/hook-fired" ]; then
    hook_no_fire "PreToolUse hook did not fire (no marker; rc=$rc)"
    return 0
  fi
  if [ -e "$HOOK_PROJ/evidence-deny" ]; then
    PROBE_STATUS=fail
    PROBE_OBSERVED="deny envelope did NOT block: the gated command's side effect occurred (rc=$rc)"
  else
    PROBE_STATUS=pass
    PROBE_OBSERVED="hook fired and the gated command's side effect did NOT occur (rc=$rc)"
  fi
  PROBE_NOTES="transcript: $WORK/deny.log"
}

probe_hooks_pretooluse_exit2_stderr() {
  local rc=0 outf
  ensure_hook_project
  PROBE_EXPECTED="exit-2 hook blocks the touch AND the model surfaces the stderr text ZSKILLS-PROBE-STDERR-$STDERR_NONCE"
  printf 'exit2\n' > "$HOOK_PROJ/hookmode"
  rm -f "$HOOK_PROJ/hook-fired" "$HOOK_PROJ/evidence-e2"
  outf="$WORK/exit2-last.out"
  codex_exec "$HOOK_PROJ" --full-auto --output-last-message "$outf" \
    "Run exactly this shell command: touch \"$HOOK_PROJ/evidence-e2\" — then reply with any error text the command attempt produced, verbatim." \
    >"$WORK/exit2.log" 2>&1 || rc=$?
  if [ ! -f "$HOOK_PROJ/hook-fired" ]; then
    hook_no_fire "PreToolUse hook did not fire (no marker; rc=$rc)"
    return 0
  fi
  if [ -e "$HOOK_PROJ/evidence-e2" ]; then
    PROBE_STATUS=fail
    PROBE_OBSERVED="exit-2 did NOT block: side effect occurred (rc=$rc)"
  elif out_contains "$outf" "ZSKILLS-PROBE-STDERR-$STDERR_NONCE" \
       || out_contains "$WORK/exit2.log" "ZSKILLS-PROBE-STDERR-$STDERR_NONCE"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="blocked AND the stderr nonce was surfaced (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="blocked, but the stderr text was NOT surfaced to the model (rc=$rc)"
  fi
  PROBE_NOTES="transcript: $WORK/exit2.log"
}

probe_hooks_pretooluse_updated_input() {
  local rc=0
  ensure_hook_project
  PROBE_EXPECTED="updatedInput rewrites the command: probe-mutated is created, probe-orig is NOT"
  printf 'mutate\n' > "$HOOK_PROJ/hookmode"
  rm -f "$HOOK_PROJ/hook-fired" "$HOOK_PROJ/probe-orig" "$HOOK_PROJ/probe-mutated"
  codex_exec "$HOOK_PROJ" --full-auto \
    "Run exactly this shell command and nothing else: touch \"$HOOK_PROJ/probe-orig\"" \
    >"$WORK/mutate.log" 2>&1 || rc=$?
  if [ ! -f "$HOOK_PROJ/hook-fired" ]; then
    hook_no_fire "PreToolUse hook did not fire (no marker; rc=$rc)"
    return 0
  fi
  if [ -e "$HOOK_PROJ/probe-mutated" ] && [ ! -e "$HOOK_PROJ/probe-orig" ]; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="the MUTATED input executed (probe-mutated exists, probe-orig absent; rc=$rc)"
  elif [ -e "$HOOK_PROJ/probe-orig" ]; then
    PROBE_STATUS=fail
    PROBE_OBSERVED="the ORIGINAL input executed — updatedInput was not applied (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="neither file exists — command blocked or never executed (rc=$rc)"
  fi
  PROBE_NOTES="transcript: $WORK/mutate.log"
}

probe_hooks_sessionstart_additional_context() {
  local rc=0 outf
  ensure_hook_project
  PROBE_EXPECTED="SessionStart additionalContext nonce ZSKILLS-PROBE-CONTEXT-$CTX_NONCE is visible to the model"
  printf 'allow\n' > "$HOOK_PROJ/hookmode"
  rm -f "$HOOK_PROJ/ss-fired"
  outf="$WORK/ss-last.out"
  codex_exec "$HOOK_PROJ" --output-last-message "$outf" \
    "Your context may include an injected line containing a token that starts with ZSKILLS-PROBE-CONTEXT-. Reply with ONLY that full token, or NONE if no such token is present." \
    >"$WORK/ss.log" 2>&1 || rc=$?
  if out_contains "$outf" "ZSKILLS-PROBE-CONTEXT-$CTX_NONCE"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="model echoed the injected context nonce (rc=$rc)"
    return 0
  fi
  if [ ! -f "$HOOK_PROJ/ss-fired" ]; then
    hook_no_fire "SessionStart hook did not fire (no marker; rc=$rc)"
    return 0
  fi
  PROBE_STATUS=fail
  PROBE_OBSERVED="hook fired but the model did NOT echo the injected nonce (rc=$rc)"
  PROBE_NOTES="transcript: $WORK/ss.log"
}

probe_hooks_stdin_permission_mode() {
  local rc=0 missing
  ensure_hook_project
  PROBE_EXPECTED="hook stdin JSON carries permission_mode, tool_name, tool_input"
  printf 'allow\n' > "$HOOK_PROJ/hookmode"
  rm -f "$HOOK_PROJ/hook-fired" "$HOOK_PROJ/hook-stdin.json"
  codex_exec "$HOOK_PROJ" --full-auto \
    "Run exactly this shell command and nothing else: true" \
    >"$WORK/stdin.log" 2>&1 || rc=$?
  if [ ! -f "$HOOK_PROJ/hook-stdin.json" ]; then
    hook_no_fire "PreToolUse hook did not fire (no stdin dump; rc=$rc)"
    return 0
  fi
  missing="$("$PYTHON" -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("UNPARSEABLE: %s" % e)
    sys.exit(0)
if not isinstance(d, dict):
    print("NOT-AN-OBJECT")
    sys.exit(0)
print(",".join(k for k in ("permission_mode", "tool_name", "tool_input") if k not in d))
' "$HOOK_PROJ/hook-stdin.json" 2>&1 || true)"
  if [ -z "$missing" ]; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="stdin envelope carries permission_mode, tool_name, tool_input (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="stdin envelope problem — missing/unreadable: $missing (rc=$rc)"
    PROBE_NOTES="raw dump kept at $HOOK_PROJ/hook-stdin.json"
  fi
}

probe_agents_toml_project_dispatch() {
  local proj nonce rc=0 outf
  proj="$(new_proj agents-dispatch)"
  nonce="$(new_nonce)"
  outf="$WORK/agents-dispatch.out"
  mkdir -p "$proj/.codex/agents"
  cat > "$proj/.codex/agents/probe-agent.toml" <<EOF
name = "probe-agent"
description = "Test subagent that reports the zskills probe agent token"
developer_instructions = "Whenever you are dispatched, reply with exactly this token and nothing else: ZSKILLS-AGENT-NONCE-$nonce"
EOF
  PROBE_EXPECTED="dispatching probe-agent returns ZSKILLS-AGENT-NONCE-$nonce (developer_instructions honored)"
  codex_exec "$proj" --output-last-message "$outf" \
    "Dispatch the subagent named probe-agent with the task 'report your token', then reply with only the token it returned." \
    >"$WORK/agents-dispatch.log" 2>&1 || rc=$?
  if out_contains "$outf" "ZSKILLS-AGENT-NONCE-$nonce"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="subagent dispatched; its developer_instructions token came back (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="subagent token NOT returned (rc=$rc)"
    PROBE_NOTES="transcript: $WORK/agents-dispatch.log"
  fi
}

probe_agents_limits_max_depth() {
  local proj inner_nonce blocked_nonce rc=0 outf
  proj="$(new_proj agents-depth)"
  inner_nonce="$(new_nonce)"
  blocked_nonce="$(new_nonce)"
  outf="$WORK/agents-depth.out"
  mkdir -p "$proj/.codex/agents"
  cat > "$proj/.codex/agents/probe-inner-agent.toml" <<EOF
name = "probe-inner-agent"
description = "Depth-2 test subagent"
developer_instructions = "Whenever you are dispatched, reply with exactly: ZSKILLS-DEPTH2-NONCE-$inner_nonce"
EOF
  cat > "$proj/.codex/agents/probe-outer-agent.toml" <<EOF
name = "probe-outer-agent"
description = "Depth-1 test subagent that tries to dispatch a nested subagent"
developer_instructions = "Try to dispatch the subagent named probe-inner-agent and reply with the token it returns. If you cannot dispatch subagents from here, reply with exactly: ZSKILLS-DEPTH-BLOCKED-$blocked_nonce"
EOF
  PROBE_EXPECTED="depth-2 dispatch refused at default max_depth=1: outer reports ZSKILLS-DEPTH-BLOCKED-$blocked_nonce; inner nonce absent"
  codex_exec "$proj" --output-last-message "$outf" \
    "Dispatch the subagent named probe-outer-agent and reply with its answer verbatim." \
    >"$WORK/agents-depth.log" 2>&1 || rc=$?
  if out_contains "$outf" "ZSKILLS-DEPTH2-NONCE-$inner_nonce"; then
    PROBE_STATUS=fail
    PROBE_OBSERVED="depth-2 nonce came back — nested dispatch was NOT refused at the default depth (rc=$rc)"
  elif out_contains "$outf" "ZSKILLS-DEPTH-BLOCKED-$blocked_nonce"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="outer agent ran and reported nested dispatch unavailable; depth-2 nonce absent (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="ambiguous — neither the depth-2 nonce nor the blocked marker came back (rc=$rc)"
    PROBE_NOTES="transcript: $WORK/agents-depth.log"
  fi
}

extract_thread_id() {
  # $1 = JSONL file. Prints the thread id from the thread.started event, or
  # nothing.
  [ -f "$1" ] || return 0
  "$PYTHON" -c '
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except Exception:
        continue
    if not isinstance(ev, dict):
        continue
    if ev.get("type") == "thread.started":
        for k in ("thread_id", "id", "thread"):
            v = ev.get(k)
            if isinstance(v, str) and v:
                print(v)
                sys.exit(0)
sys.exit(0)
' "$1" 2>/dev/null || true
}

jsonl_has_event() {
  # $1 = JSONL file, $2 = event type. True when an event of that type exists.
  [ -f "$1" ] || return 1
  T="$2" "$PYTHON" -c '
import json, os, sys
want = os.environ["T"]
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except Exception:
        continue
    if isinstance(ev, dict) and ev.get("type") == want:
        sys.exit(0)
sys.exit(1)
' "$1" 2>/dev/null
}

probe_exec_json_thread_id() {
  local proj rc=0 rc2=0 tid jsonl
  proj="$(new_proj exec-thread)"
  jsonl="$WORK/exec-thread.jsonl"
  PROBE_EXPECTED="thread.started JSONL event carries a thread id; exec resume <ID> accepts it (exit 0)"
  codex_exec "$proj" --json "Reply with exactly: OK" >"$jsonl" 2>"$WORK/exec-thread.err" || rc=$?
  tid="$(extract_thread_id "$jsonl")"
  if [ -z "$tid" ]; then
    PROBE_STATUS=fail
    PROBE_OBSERVED="no thread id found in the JSONL stream (rc=$rc)"
    PROBE_NOTES="stream kept at $jsonl"
    return 0
  fi
  codex_exec_resume "$proj" "$tid" --json "Reply with exactly: OK again" \
    >"$WORK/exec-thread-resume.jsonl" 2>&1 || rc2=$?
  if [ "$rc2" -eq 0 ]; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="thread id '$tid' extracted from thread.started and accepted by exec resume (rc=$rc2)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="thread id '$tid' extracted, but exec resume rejected it (rc=$rc2)"
    PROBE_NOTES="resume output kept at $WORK/exec-thread-resume.jsonl"
  fi
}

probe_exec_output_last_message() {
  local proj nonce rc=0 outf
  proj="$(new_proj exec-olm)"
  nonce="$(new_nonce)"
  outf="$WORK/exec-olm.out"
  PROBE_EXPECTED="--output-last-message file contains the final message token ZSKILLS-LAST-$nonce"
  codex_exec "$proj" --output-last-message "$outf" \
    "Reply with exactly: ZSKILLS-LAST-$nonce" >"$WORK/exec-olm.log" 2>&1 || rc=$?
  if out_contains "$outf" "ZSKILLS-LAST-$nonce"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="final message present in the -o file (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="-o file missing or does not carry the final message (rc=$rc)"
    PROBE_NOTES="transcript: $WORK/exec-olm.log"
  fi
}

probe_exec_output_schema() {
  local proj nonce rc=0 outf sch verdict
  proj="$(new_proj exec-schema)"
  nonce="$(new_nonce)"
  outf="$WORK/exec-schema.out"
  sch="$WORK/exec-schema.schema.json"
  "$PYTHON" -c '
import json, sys
schema = {"type": "object",
          "properties": {"answer": {"type": "string"}},
          "required": ["answer"],
          "additionalProperties": False}
json.dump(schema, open(sys.argv[1], "w"))
' "$sch"
  PROBE_EXPECTED="output conforms to the supplied schema (JSON object with string key 'answer'); deviations surfaced/recorded"
  codex_exec "$proj" --output-schema "$sch" --output-last-message "$outf" \
    "Reply with a JSON object with a single key answer whose value is the string PROBE-OS-$nonce." \
    >"$WORK/exec-schema.log" 2>&1 || rc=$?
  if [ ! -s "$outf" ]; then
    PROBE_STATUS=fail
    PROBE_OBSERVED="no structured output produced (rc=$rc)"
    PROBE_NOTES="transcript: $WORK/exec-schema.log"
    return 0
  fi
  verdict="$("$PYTHON" -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("UNPARSEABLE: %s" % e)
    sys.exit(0)
if isinstance(d, dict) and isinstance(d.get("answer"), str):
    print("CONFORMS: answer=%s" % d["answer"])
else:
    print("NONCONFORMING: %r" % (d,))
' "$outf" 2>&1 || true)"
  case "$verdict" in
    CONFORMS:*)
      PROBE_STATUS=pass
      PROBE_OBSERVED="schema-conforming output ($verdict; rc=$rc)"
      ;;
    *)
      PROBE_STATUS=fail
      PROBE_OBSERVED="output did not conform to the schema — $verdict (rc=$rc)"
      PROBE_NOTES="recorded either way per the pinned assertion; output kept at $outf"
      ;;
  esac
}

probe_exec_resume_same_session() {
  local proj nonce rc=0 rc2=0 tid jsonl outf
  proj="$(new_proj exec-resume-same)"
  nonce="$(new_nonce)"
  jsonl="$WORK/resume-same.jsonl"
  outf="$WORK/resume-same.out"
  PROBE_EXPECTED="a nonce planted in turn 1 is visible to the exec resume <ID> turn"
  codex_exec "$proj" --json \
    "Remember this nonce for later in this session: ZSKILLS-RESUME-NONCE-$nonce. Reply with exactly: OK" \
    >"$jsonl" 2>"$WORK/resume-same.err" || rc=$?
  tid="$(extract_thread_id "$jsonl")"
  if [ -z "$tid" ]; then
    PROBE_STATUS=skip
    PROBE_OBSERVED="could not obtain a thread id for turn 1 (rc=$rc) — resume unprobeable this run"
    PROBE_NOTES="see exec.json.thread-id; stream kept at $jsonl"
    return 0
  fi
  codex_exec_resume "$proj" "$tid" --output-last-message "$outf" \
    "Reply with ONLY the nonce I asked you to remember earlier in this session." \
    >"$WORK/resume-same.log" 2>&1 || rc2=$?
  if out_contains "$outf" "ZSKILLS-RESUME-NONCE-$nonce"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="resumed turn recalled the turn-1 nonce (rc=$rc2)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="resumed turn did NOT recall the turn-1 nonce (rc=$rc2) — resume may not reach the same durable session"
    PROBE_NOTES="transcript: $WORK/resume-same.log"
  fi
}

probe_exec_resume_prompt_and_json() {
  local proj rc=0 rc2=0 tid jsonl jsonl2
  proj="$(new_proj exec-resume-json)"
  jsonl="$WORK/resume-json-t1.jsonl"
  jsonl2="$WORK/resume-json-t2.jsonl"
  PROBE_EXPECTED="exec resume <ID> --json '<prompt>' runs NON-interactively (stdin /dev/null), exit 0, JSONL turn.completed present"
  codex_exec "$proj" --json "Reply with exactly: OK" >"$jsonl" 2>"$WORK/resume-json.err" || rc=$?
  tid="$(extract_thread_id "$jsonl")"
  if [ -z "$tid" ]; then
    PROBE_STATUS=skip
    PROBE_OBSERVED="could not obtain a thread id for turn 1 (rc=$rc) — resume unprobeable this run"
    PROBE_NOTES="see exec.json.thread-id; stream kept at $jsonl"
    return 0
  fi
  codex_exec_resume "$proj" "$tid" --json "Reply with exactly: RESUMED" \
    >"$jsonl2" 2>&1 || rc2=$?
  if [ "$rc2" -eq 0 ] && jsonl_has_event "$jsonl2" "turn.completed"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="positional prompt accepted non-interactively; JSONL turn.completed emitted (rc=$rc2)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="resume-with-prompt did not complete as JSONL (rc=$rc2; turn.completed $(jsonl_has_event "$jsonl2" "turn.completed" && echo present || echo absent))"
    PROBE_NOTES="this is every-mode's exact invocation shape — a fail here is substrate-level; stream kept at $jsonl2"
  fi
}

probe_exec_resume_session_loss() {
  local proj rc=0 bogus errf
  proj="$(new_proj exec-resume-loss)"
  bogus="00000000-0000-4000-8000-000000000000"
  errf="$WORK/resume-loss.err"
  PROBE_EXPECTED="resume of bogus id exits non-zero with a distinguishable error on stderr"
  codex_exec_resume "$proj" "$bogus" --json "Reply with exactly: OK" \
    >"$WORK/resume-loss.out" 2>"$errf" || rc=$?
  if [ "$rc" -ne 0 ] && [ -s "$errf" ]; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="non-zero exit (rc=$rc) with error text: $(sed -n '1p' "$errf" | cut -c1-160)"
  elif [ "$rc" -ne 0 ]; then
    PROBE_STATUS=fail
    PROBE_OBSERVED="non-zero exit (rc=$rc) but NO error text — not clearly distinguishable"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="resume of a bogus id exited 0 — silent fresh session suspected"
    PROBE_NOTES="output kept at $WORK/resume-loss.out"
  fi
}

build_agentsmd() {
  # $1 = project dir, $2 = nonce. Writes AGENTS.md with the nonce PAST the
  # 32 KiB boundary (filler first crosses 33 KiB, then the nonce line).
  AM_PROJ="$1" AM_NONCE="$2" "$PYTHON" - <<'PY'
import os
proj = os.environ["AM_PROJ"]
nonce = os.environ["AM_NONCE"]
parts = []
total = 0
i = 0
while total < 33 * 1024:
    s = "Project guidance filler line %d: follow the standard conventions.\n" % i
    parts.append(s)
    total += len(s)
    i += 1
parts.append("The probe token is ZSKILLS-AGENTSMD-NONCE-%s\n" % nonce)
with open(os.path.join(proj, "AGENTS.md"), "w") as f:
    f.write("".join(parts))
PY
}

probe_agentsmd_cap_32k() {
  local proj nonce rc=0 outf
  proj="$(new_proj agentsmd-cap)"
  nonce="$(new_nonce)"
  outf="$WORK/agentsmd-cap.out"
  build_agentsmd "$proj" "$nonce"
  PROBE_EXPECTED="nonce past the 32 KiB AGENTS.md boundary is NOT visible; model answers NONE"
  codex_exec "$proj" --output-last-message "$outf" \
    "If your project instructions contain a token starting with ZSKILLS-AGENTSMD-NONCE-, reply with ONLY that full token; otherwise reply with exactly: NONE" \
    >"$WORK/agentsmd-cap.log" 2>&1 || rc=$?
  if [ ! -s "$outf" ]; then
    PROBE_STATUS=fail
    PROBE_OBSERVED="no reply produced (rc=$rc) — cannot evaluate the cap"
    PROBE_NOTES="transcript: $WORK/agentsmd-cap.log"
  elif out_contains "$outf" "ZSKILLS-AGENTSMD-NONCE-$nonce"; then
    PROBE_STATUS=fail
    PROBE_OBSERVED="nonce past 32 KiB WAS visible — default cap not in effect (rc=$rc)"
  elif out_contains "$outf" "NONE"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="model answered NONE; past-cap nonce invisible (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="ambiguous reply — neither the nonce nor NONE (rc=$rc)"
    PROBE_NOTES="reply kept at $outf"
  fi
}

probe_agentsmd_project_doc_max_bytes_raise() {
  local proj nonce rc=0 outf
  proj="$(new_proj agentsmd-raise)"
  nonce="$(new_nonce)"
  outf="$WORK/agentsmd-raise.out"
  build_agentsmd "$proj" "$nonce"
  PROBE_EXPECTED="with project_doc_max_bytes raised to 131072, the past-32-KiB nonce IS visible"
  codex_exec "$proj" -c project_doc_max_bytes=131072 --output-last-message "$outf" \
    "If your project instructions contain a token starting with ZSKILLS-AGENTSMD-NONCE-, reply with ONLY that full token; otherwise reply with exactly: NONE" \
    >"$WORK/agentsmd-raise.log" 2>&1 || rc=$?
  if out_contains "$outf" "ZSKILLS-AGENTSMD-NONCE-$nonce"; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="nonce visible after the raise (rc=$rc)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="nonce still invisible after the raise (rc=$rc)"
    PROBE_NOTES="raise applied via -c project_doc_max_bytes=131072; on fail, verify the config key/mechanism by hand before triage. transcript: $WORK/agentsmd-raise.log"
  fi
}

probe_plugins_marketplace_claude_compat() {
  local rc=0 addout instout ans
  ensure_plugin_fixture
  PROBE_EXPECTED="marketplace add reads the LEGACY .claude-plugin/marketplace.json; the listed plugin installs"
  addout="$("$CODEX" plugin marketplace add "$PLUGIN_MKT" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && "$CODEX" plugin marketplace list 2>/dev/null | grep -q "zskills-probe-marketplace"; then
    rc=0
    instout="$("$CODEX" plugin install "zskills-probe-plugin@zskills-probe-marketplace" 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ]; then
      PROBE_STATUS=pass
      PROBE_OBSERVED="scripted: marketplace add + list + plugin install succeeded from the legacy manifest"
      PLUGIN_INSTALLED=1
      return 0
    fi
    PROBE_NOTES="scripted install failed: $(printf '%s' "$instout" | sed -n '1p' | cut -c1-160)"
  else
    PROBE_NOTES="scripted marketplace add unavailable: $(printf '%s' "$addout" | sed -n '1p' | cut -c1-160)"
  fi
  log ""
  log "MANUAL STEP — plugins.marketplace.claude-compat (scripted attempt did not confirm):"
  log "  1) In a SEPARATE terminal (Windows Terminal / PowerShell — or WSL2 — if mintty misbehaves):"
  log "  2) Add the fixture marketplace: codex plugin marketplace add \"$PLUGIN_MKT\""
  log "     (or use the codex TUI's plugin flow against that path)."
  log "  3) Install the plugin zskills-probe-plugin from marketplace zskills-probe-marketplace."
  log "  4) The manifest is the LEGACY .claude-plugin/marketplace.json — confirm codex read it."
  ans="$(ask_owner 'Did the marketplace add + plugin install succeed from the legacy manifest? [y/n/s or Enter = skip] ')"
  case "$ans" in
    y|Y)
      PROBE_STATUS=pass
      PROBE_OBSERVED="owner confirmed marketplace add + install from the legacy manifest (manual)"
      PLUGIN_INSTALLED=1
      ;;
    n|N)
      PROBE_STATUS=fail
      PROBE_OBSERVED="owner reports codex could NOT use the legacy .claude-plugin/marketplace.json"
      ;;
    *)
      PROBE_STATUS=skip
      PROBE_OBSERVED="not confirmed (answer: '${ans:-<empty>}')"
      ;;
  esac
}

probe_plugins_env_claude_plugin_root_alias() {
  local proj rc=0 cpr pr
  ensure_plugin_fixture
  PROBE_EXPECTED="the fixture plugin's SessionStart hook observes non-empty CLAUDE_PLUGIN_ROOT == PLUGIN_ROOT"
  if [ "$PLUGIN_INSTALLED" != 1 ]; then
    PROBE_STATUS=skip
    PROBE_OBSERVED="fixture plugin not installed (plugins.marketplace.claude-compat did not confirm an install)"
    PROBE_NOTES="install zskills-probe-plugin from $PLUGIN_MKT and re-run: --only plugins.marketplace.claude-compat,plugins.env.claude-plugin-root-alias"
    return 0
  fi
  rm -f "$PLUGIN_ENV_DUMP"
  proj="$(new_proj plugin-env-proj)"
  codex_exec "$proj" "Reply with exactly: OK" >"$WORK/plugin-env.log" 2>&1 || rc=$?
  if [ ! -f "$PLUGIN_ENV_DUMP" ]; then
    PROBE_STATUS=skip
    PROBE_OBSERVED="plugin SessionStart hook did not fire (no env dump; rc=$rc) — plugin hooks may need their own trust/enable step"
    PROBE_NOTES="enable the plugin's hooks and re-run --only plugins.env.claude-plugin-root-alias; transcript: $WORK/plugin-env.log"
    return 0
  fi
  cpr="$(sed -n 's/^CPR=//p' "$PLUGIN_ENV_DUMP" | sed -n '1p')"
  pr="$(sed -n 's/^PR=//p' "$PLUGIN_ENV_DUMP" | sed -n '1p')"
  if [ -n "$cpr" ] && [ "$cpr" = "$pr" ]; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="CLAUDE_PLUGIN_ROOT non-empty and equal to PLUGIN_ROOT ($cpr)"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="alias mismatch — CLAUDE_PLUGIN_ROOT='$cpr' PLUGIN_ROOT='$pr'"
  fi
  # Best-effort fixture cleanup; never let cleanup affect the verdict.
  "$CODEX" plugin uninstall zskills-probe-plugin >/dev/null 2>&1 || true
  "$CODEX" plugin marketplace remove zskills-probe-marketplace >/dev/null 2>&1 || true
  log "NOTE: if the fixture plugin/marketplace was installed manually, remove it manually too (zskills-probe-plugin / zskills-probe-marketplace)."
}

probe_sandbox_workspace_write_add_dir() {
  local proj outside rc1=0 rc2=0 with_ok without_blocked
  proj="$(new_proj sandbox-proj)"
  outside="$WORK/sandbox-outside"
  mkdir -p "$outside"
  PROBE_EXPECTED="write at the --add-dir path succeeds; the same write WITHOUT --add-dir does not happen"
  rm -f "$outside/added-ok" "$outside/no-adddir"
  codex_exec "$proj" --sandbox workspace-write --add-dir "$outside" \
    "Run exactly this shell command and nothing else: touch \"$outside/added-ok\"" \
    >"$WORK/sandbox-with.log" 2>&1 || rc1=$?
  codex_exec "$proj" --sandbox workspace-write \
    "Run exactly this shell command and nothing else: touch \"$outside/no-adddir\"" \
    >"$WORK/sandbox-without.log" 2>&1 || rc2=$?
  with_ok=no;        [ -e "$outside/added-ok" ] && with_ok=yes
  without_blocked=yes; [ -e "$outside/no-adddir" ] && without_blocked=no
  if [ "$with_ok" = yes ] && [ "$without_blocked" = yes ]; then
    PROBE_STATUS=pass
    PROBE_OBSERVED="write with --add-dir succeeded; write without --add-dir did not occur (rc=$rc1/$rc2)"
  elif [ "$with_ok" = no ]; then
    PROBE_STATUS=fail
    PROBE_OBSERVED="write at the added dir did NOT succeed (rc=$rc1)"
    PROBE_NOTES="transcript: $WORK/sandbox-with.log"
  else
    PROBE_STATUS=fail
    PROBE_OBSERVED="write OUTSIDE the workspace succeeded even WITHOUT --add-dir (rc=$rc2) — sandbox not enforcing"
    PROBE_NOTES="transcript: $WORK/sandbox-without.log"
  fi
}

run_probe() {
  local id="$1"
  PROBE_STATUS=skip
  PROBE_EXPECTED=""
  PROBE_OBSERVED="probe did not complete"
  PROBE_NOTES=""
  case "$id" in
    skills.discovery.agents-dir)                probe_skills_discovery_agents_dir ;;
    skills.discovery.claude-skills-path-config) probe_skills_discovery_claude_skills_path_config ;;
    skills.frontmatter.unknown-ignored)         probe_skills_frontmatter_unknown_ignored ;;
    skills.invocation.dollar-name)              probe_skills_invocation_dollar_name ;;
    skills.invocation.implicit)                 probe_skills_invocation_implicit ;;
    skills.openai-yaml.implicit-invocation-off) probe_skills_openai_yaml_implicit_invocation_off ;;
    hooks.trust.non-managed-friction)           probe_hooks_trust_non_managed_friction ;;
    hooks.pretooluse.deny-envelope)             probe_hooks_pretooluse_deny_envelope ;;
    hooks.pretooluse.exit2-stderr)              probe_hooks_pretooluse_exit2_stderr ;;
    hooks.pretooluse.updated-input)             probe_hooks_pretooluse_updated_input ;;
    hooks.sessionstart.additional-context)      probe_hooks_sessionstart_additional_context ;;
    hooks.stdin.permission-mode)                probe_hooks_stdin_permission_mode ;;
    agents.toml.project-dispatch)               probe_agents_toml_project_dispatch ;;
    agents.limits.max-depth)                    probe_agents_limits_max_depth ;;
    exec.json.thread-id)                        probe_exec_json_thread_id ;;
    exec.output-last-message)                   probe_exec_output_last_message ;;
    exec.output-schema)                         probe_exec_output_schema ;;
    exec.resume.same-session)                   probe_exec_resume_same_session ;;
    exec.resume.prompt-and-json)                probe_exec_resume_prompt_and_json ;;
    exec.resume.session-loss)                   probe_exec_resume_session_loss ;;
    agentsmd.cap-32k)                           probe_agentsmd_cap_32k ;;
    agentsmd.project-doc-max-bytes-raise)       probe_agentsmd_project_doc_max_bytes_raise ;;
    plugins.marketplace.claude-compat)          probe_plugins_marketplace_claude_compat ;;
    plugins.env.claude-plugin-root-alias)       probe_plugins_env_claude_plugin_root_alias ;;
    sandbox.workspace-write.add-dir)            probe_sandbox_workspace_write_add_dir ;;
    *)
      PROBE_STATUS=skip
      PROBE_OBSERVED="no implementation for probe id $id"
      ;;
  esac
}

record_result() {
  # $1 = id. Serializes the PROBE_* globals to $RESULTS_DIR/<id>.json via
  # python (env-passed — arbitrary text round-trips safely).
  P_ID="$1" \
  P_STATUS="$PROBE_STATUS" \
  P_EXPECTED="$PROBE_EXPECTED" \
  P_OBSERVED="$PROBE_OBSERVED" \
  P_NOTES="$PROBE_NOTES" \
  P_ASSERTS="$(probe_asserts "$1")" \
  P_LB="$(probe_load_bearing "$1")" \
  P_FILE="$RESULTS_DIR/$1.json" \
  "$PYTHON" - <<'PY'
import json, os
entry = {
    "status": os.environ["P_STATUS"],
    "expected": os.environ["P_EXPECTED"],
    "observed": os.environ["P_OBSERVED"],
    "notes": os.environ["P_NOTES"],
    "asserts": os.environ["P_ASSERTS"],
    "load_bearing": os.environ["P_LB"] == "true",
}
with open(os.environ["P_FILE"], "w") as f:
    json.dump(entry, f)
PY
}

# ---------------------------------------------------------------------------
# Main probe loop
# ---------------------------------------------------------------------------
TOTAL=0
N_PASS=0
N_FAIL=0
N_SKIP=0

for _id in "${PROBE_IDS[@]}"; do
  want_probe "$_id" || continue
  TOTAL=$((TOTAL + 1))
  log ""
  log "── probe $TOTAL: $_id"
  run_probe "$_id" || true
  case "$PROBE_STATUS" in
    pass) N_PASS=$((N_PASS + 1)) ;;
    fail) N_FAIL=$((N_FAIL + 1)) ;;
    *)    PROBE_STATUS=skip; N_SKIP=$((N_SKIP + 1)) ;;
  esac
  record_result "$_id"
  log "   $PROBE_STATUS — $PROBE_OBSERVED"
done

# Assemble + atomically publish the results file (only when --out was given,
# and only now — on completion; a crash above leaves no partial output file).
if [ -n "$OUT_PATH" ]; then
  OUT_TMP="${OUT_PATH}.tmp"
  P_PROBED_AT="$PROBED_AT" \
  P_CODEX_VERSION="$CODEX_VERSION" \
  P_PLATFORM="$PLATFORM" \
  "$PYTHON" - "$RESULTS_DIR" "$OUT_TMP" <<'PY'
import json, os, sys
results_dir, out_tmp = sys.argv[1], sys.argv[2]
results = {}
for fn in sorted(os.listdir(results_dir)):
    if fn.endswith(".json"):
        with open(os.path.join(results_dir, fn)) as f:
            results[fn[:-5]] = json.load(f)
doc = {
    "schema": "zskills-codex-probe/v1",
    "probed_at": os.environ["P_PROBED_AT"],
    "codex_version": os.environ["P_CODEX_VERSION"],
    "platform": os.environ["P_PLATFORM"],
    "results": results,
}
with open(out_tmp, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
  mv -- "$OUT_TMP" "$OUT_PATH"
  log ""
  log "codex-probe: results written to $OUT_PATH"
  if [ -n "$ONLY" ]; then
    log "codex-probe: NOTE — subset run (--only): this file will NOT pass --validate's completeness check"
  fi
fi

printf 'CODEX-PROBE-SUMMARY: probes=%d pass=%d fail=%d skip=%d\n' \
  "$TOTAL" "$N_PASS" "$N_FAIL" "$N_SKIP"
exit 0
