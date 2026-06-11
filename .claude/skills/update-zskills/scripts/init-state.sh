#!/bin/bash
# init-state.sh — THE single path definition for the plugin-lane explicit-init
# state (#1132 single-path-definition rule; INSTALL_REDESIGN Phase 6a item A0).
#
# Sourceable, side-effect-free (defines variables + functions only). Defines:
#   - the init-done / setup-confirmed marker paths (project-root-relative),
#   - the presence predicate + the ONLY marker writers (atomic tmp+mv,
#     lock-LAST per the #394 contract, #1079 0-byte-healable),
#   - the FROZEN legacy-residue detection constants (the D20 sentinel prefix,
#     the seeded-config notice path, the 5 project-side paths the retired
#     materialiser ever wrote, and the frozen legacy config-seed shape) plus
#     the mechanical A1.5 cleanup helpers that consume them.
#
# Consumers (all SOURCE this file; none re-types the paths/literals):
#   - skills/update-zskills/SKILL.md Step 0.7 init/update fences (the writer),
#   - skills/update-zskills/scripts/zskills-resolve-config.sh's
#     ZSKILLS_VERSION fallback (reader),
#   - [Phase 6b] the block-unmaterialised-skill gate + verify-install,
#   - [Phase 7] the SessionStart greeting hook,
#   - every test fixture that fakes or asserts this state
#     (tests/test-update-zskills-init.sh and friends).
#
# LITERAL-STRING DISCIPLINE (Phase 6a A0): the frozen legacy-residue literals
# below appear NOWHERE else in live files — not in fences, not in prose, not
# in comments, not in fixtures. Every other surface refers to them
# referentially ("the D20 sentinel prefix constant", "$ZSKILLS_LEGACY_*").
# (Mid-window exception, dies in Phase 7: the still-live materialiser and its
# own pre-existing tests carry their original copies until they are deleted.)

# ── Live init-state paths (relative to the project root) ───────────────────
# Single definition; every writer/gate/fixture derives from these two vars.
ZSKILLS_INIT_DONE_REL=".zskills/init-done"
ZSKILLS_SETUP_CONFIRMED_REL=".zskills/setup-confirmed"

# zskills_init_done_present <project-root>
#   True (0) when the init-done marker exists AND is non-empty. A 0-byte
#   marker is a partial leftover (#1079) — treated as NOT initialised so a
#   re-run of init heals it (the atomic writers below can never produce one;
#   only an external abort can).
zskills_init_done_present() {
  local root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  [ -f "$root/$ZSKILLS_INIT_DONE_REL" ] && [ -s "$root/$ZSKILLS_INIT_DONE_REL" ]
}

# zskills_write_setup_confirmed <project-root>
#   Atomic (tmp+mv) write of the setup-confirmed marker (one ISO timestamp
#   line, #1119 semantics). Also used standalone by the legacy-lane
#   /update-zskills Step G.5 / update-path fences — the legacy lane writes
#   ONLY this marker, never init-done (init-done is the plugin-lane init
#   lock; the legacy lane is mirror-keyed).
zskills_write_setup_confirmed() {
  local root="$1" tmp
  mkdir -p "$root/$(dirname "$ZSKILLS_SETUP_CONFIRMED_REL")" || return 1
  tmp="$root/$ZSKILLS_SETUP_CONFIRMED_REL.zskills-tmp.${BASHPID:-$$}"
  if ! date -Iseconds > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  if ! mv "$tmp" "$root/$ZSKILLS_SETUP_CONFIRMED_REL"; then
    rm -f "$tmp"
    return 1
  fi
  return 0
}

# zskills_write_init_markers <project-root> [<version>]
#   THE lock-LAST init-marker writer (#394 contract): setup-confirmed FIRST,
#   init-done LAST, each atomic (tmp+mv — no observable partial state, #1079).
#   init-done content is `version:` + `date:` lines — the version record for
#   config-less consumers, read by zskills-resolve-config.sh's
#   ZSKILLS_VERSION fallback. Re-running on an initialised consumer is the
#   documented refresh path (the A1 update arm re-stamps the version line).
#
#   Empty-version clobber guard (#1150): when <version> is EMPTY (the
#   caller's resolve-repo-version.sh failed) and an existing init-done
#   marker already carries a non-empty `version:` value, the OLD value is
#   kept — a failed resolve on the update arm must never downgrade a good
#   version record to empty. Empty + no prior marker (or a prior empty
#   value) still writes empty, and a non-empty <version> always overwrites.
zskills_write_init_markers() {
  local root="$1" version="${2:-}" tmp prior
  if [ -z "$version" ] && [ -s "$root/$ZSKILLS_INIT_DONE_REL" ]; then
    prior="$(sed -n 's/^version: //p' "$root/$ZSKILLS_INIT_DONE_REL" 2>/dev/null | head -n 1)"
    [ -n "$prior" ] && version="$prior"
  fi
  zskills_write_setup_confirmed "$root" || return 1
  tmp="$root/$ZSKILLS_INIT_DONE_REL.zskills-tmp.${BASHPID:-$$}"
  if ! {
    printf 'version: %s\n' "$version"
    printf 'date: %s\n' "$(date -Iseconds)"
  } > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  if ! mv "$tmp" "$root/$ZSKILLS_INIT_DONE_REL"; then
    rm -f "$tmp"
    return 1
  fi
  return 0
}

# ── Working-Python-3 resolver (needed by the seed-shape matcher below) ─────
# Body maintained in hooks/_lib/resolve-python.sh; inlined VERBATIM here per
# the tests/test-hook-helper-drift.sh byte-equality gate (skill scripts run
# from contexts where _lib is not on a reliable relative path).

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

# ── FROZEN legacy-residue detection constants (Phase 6a A1.5) ──────────────
# These describe what PRE-REDESIGN releases (the retired SessionStart
# materialiser) actually wrote into consumer repos. They are FROZEN:
# residue detection must match what old releases ACTUALLY wrote, forever
# (upgraded consumers arrive carrying this residue indefinitely — end-state
# item 3's deliberate carve-out), and must NEVER be re-derived from live
# defaults (zskills-defaults.json drifts as defaults evolve; these do not).
# Consumed ONLY by the /update-zskills A1.5 residue cleanup and its fixtures.
# legacy-residue-detection-only — do not reuse for any live mechanism.

# The D20 sentinel prefix the retired materialiser stamped into every
# artifact it wrote (first-3-lines, `# <prefix> <ver>` or `<!-- <prefix> <ver> -->`).
ZSKILLS_LEGACY_SENTINEL_PREFIX="zskills-materialised:"

# The one-time seeded-config review-notice marker the retired materialiser
# touched after seeding a default config (project-root-relative).
ZSKILLS_LEGACY_SEED_NOTICE_REL=".zskills/config-seeded-notice"

# The 5 project-side paths the retired materialiser ever wrote, across ALL
# pre-redesign releases (the 5th, verify-response-validate.sh, stopped being
# written mid-redesign — old consumers may still carry it).
ZSKILLS_LEGACY_MATERIALISED_PATHS=(
  ".claude/agents/verifier.md"
  ".claude/agents/implementer.md"
  ".claude/hooks/inject-bash-timeout.sh"
  ".claude/hooks/verify-response-validate.sh"
  ".claude/rules/zskills/managed.md"
)

# The frozen legacy config-seed shape: the exact VALUE-BEARING key/value set
# the pre-redesign materialiser's config seed wrote. Deliberately EXCLUDES
# the three per-install dynamic keys ($schema, project_name, zskills_version)
# — the matcher below strips them from the candidate before comparing, so an
# untouched seed matches regardless of which version stamped it (the
# anti-#1132-mask comparison spec). Older releases that seeded a SUBSET of
# these keys fail the match and are conservatively kept as user-owned (the
# cure never deletes on a mismatch).
ZSKILLS_LEGACY_SEED_SHAPE_JSON='{
  "timezone": "UTC",
  "execution": {
    "landing": "direct",
    "main_protected": false,
    "branch_prefix": "feat/"
  },
  "commit": {
    "co_author": ""
  },
  "testing": {
    "unit_cmd": "",
    "full_cmd": "",
    "output_file": ".test-results.txt",
    "file_patterns": []
  },
  "dev_server": {
    "cmd": "",
    "default_port": 8080
  },
  "ui": {
    "file_patterns": "",
    "auth_bypass": ""
  },
  "ci": {
    "auto_fix": true,
    "max_fix_attempts": 2
  },
  "agents": {
    "min_model": "auto"
  },
  "output": {
    "plans_dir": "docs/plans",
    "issues_dir": "docs/issues",
    "reports_dir": "docs/reports"
  }
}'

# ── Mechanical A1.5 helpers (judgment stays in SKILL.md prose) ─────────────

# zskills_legacy_sentinelled <file>
#   True (0) when <file> exists, is non-empty, and carries the D20 sentinel
#   in its first 3 lines (the retired materialiser's detect-by-prefix rule).
#   User-owned and legacy-lane-installed files never carry the sentinel.
zskills_legacy_sentinelled() {
  local f="$1"
  [ -f "$f" ] && [ -s "$f" ] || return 1
  head -n 3 "$f" 2>/dev/null \
    | grep -Eq "^(#|<!--)[[:space:]]+${ZSKILLS_LEGACY_SENTINEL_PREFIX}[[:space:]]"
}

# zskills_legacy_remove_sentinelled <project-root>
#   The A1.5(a) unconditional, deterministic sentinelled-artifact removal:
#   for each of the legacy materialiser paths, delete the file IFF it carries
#   the sentinel. Prints each removed project-relative path on stdout (for
#   the init/update summary). Never touches sentinel-less files. Returns 0.
zskills_legacy_remove_sentinelled() {
  local root="$1" rel f
  for rel in "${ZSKILLS_LEGACY_MATERIALISED_PATHS[@]}"; do
    f="$root/$rel"
    if zskills_legacy_sentinelled "$f"; then
      if rm -f "$f"; then
        printf '%s\n' "$rel"
      else
        echo "WARN: failed to remove legacy artifact $rel" >&2
      fi
    fi
  done
  return 0
}

# zskills_legacy_seed_notice_present <project-root>
zskills_legacy_seed_notice_present() {
  local root="$1"
  [ -e "$root/$ZSKILLS_LEGACY_SEED_NOTICE_REL" ]
}

# zskills_legacy_consume_seed_notice <project-root>
#   Removes the notice marker. A1.5(b) consumes it exactly once — on EVERY
#   resolution path (accept, decline, non-interactive, shape-mismatch) — so
#   the offer never repeats (W6.3 no-nag lesson; mid-window the still-live
#   materialiser re-seeds + re-touches it, a documented known-transient).
zskills_legacy_consume_seed_notice() {
  local root="$1"
  rm -f "$root/$ZSKILLS_LEGACY_SEED_NOTICE_REL"
}

# zskills_legacy_seed_config_matches <config-path>
#   The A1.5(b) untouched-seed discriminator. True (0) when <config-path>
#   parses as JSON and, after dropping the three excluded dynamic keys
#   ($schema, project_name, zskills_version — stamped per-install, never
#   part of the value-bearing shape), equals the frozen legacy seed shape.
#   Unreadable/missing config, no working python, or any key/value drift
#   (a user customization) → false (1): the cure KEEPS the config.
zskills_legacy_seed_config_matches() {
  local cfg="$1" py
  [ -f "$cfg" ] || return 1
  py="$(zskills_resolve_python || true)"
  [ -n "$py" ] || return 1
  ZSKILLS_LEGACY_SEED_SHAPE_JSON="$ZSKILLS_LEGACY_SEED_SHAPE_JSON" "$py" - "$cfg" <<'PY'
import json, os, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
except Exception:
    sys.exit(1)
if not isinstance(cfg, dict):
    sys.exit(1)
frozen = json.loads(os.environ["ZSKILLS_LEGACY_SEED_SHAPE_JSON"])
for key in ("$schema", "project_name", "zskills_version"):
    cfg.pop(key, None)
sys.exit(0 if cfg == frozen else 1)
PY
}
