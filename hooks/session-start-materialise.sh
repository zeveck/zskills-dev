#!/usr/bin/env bash
# zskills-hook-version: 2026.05.0
# session-start-materialise.sh — W2.1 SessionStart materialiser (D11, D20, D27).
#
# Plugins cannot write to the consumer repo at install time (research §10),
# and a plugin-root CLAUDE.md is NOT loaded as context (research §12). So the
# five artifacts the /update-zskills lane installs into a consumer's
# `.claude/` must be materialised at runtime by this SessionStart hook:
#
#   1. .claude/agents/verifier.md
#   2. .claude/agents/implementer.md
#   3. .claude/hooks/inject-bash-timeout.sh
#   4. .claude/hooks/verify-response-validate.sh
#   5. .claude/rules/zskills/managed.md   (RENDERED via render-managed-rules.py)
#
# D27 — the dual-install detection probe runs FIRST (before any write). On
# lane=update-zskills or lane=dual the materialiser emits the documented
# WARN (once per session, gated by .zskills/dual-install-warned) and exits
# WITHOUT materialising, so /update-zskills install state is never clobbered.
#
# D20(a) — overwrite guard: each artifact is written WITH a materialiser
# sentinel (detect-by-prefix `^(#|<!--) zskills-materialised: <version>`),
# frontmatter-aware (YAML-comment inside `---` for frontmatter .md;
# HTML-comment for plain .md; shell-comment on line 2 for *.sh). On a
# subsequent session the guard only overwrites a destination that EITHER is
# absent OR carries a zskills sentinel — a consumer-authored file (no
# sentinel) is never clobbered. Idempotency: identical content (modulo the
# sentinel version) is not rewritten, so mtime only advances on a real
# upgrade.

set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-}"
PLUGIN="${CLAUDE_PLUGIN_ROOT:-}"

# Without a project dir we cannot materialise anywhere. Without a plugin
# root we cannot find the source artifacts. Fail-open (exit 0) — a missing
# env var means we are not running as a plugin hook.
[ -n "$PROJ" ] || exit 0
[ -n "$PLUGIN" ] || exit 0

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || exit 0

CONFIG="$PROJ/.claude/zskills-config.json"
PLUGIN_VERSION="$("$PYTHON" -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)"

# ── D27 — Dual-install detection runs FIRST (before any write) ────────────
. "$PLUGIN/hooks/_lib/detect-install-state.sh"
LANE="$(detect_install_state "$PROJ")"
case "$LANE" in
  fresh|plugin) ;;
  update-zskills)
    if [ ! -f "$PROJ/.zskills/dual-install-warned" ]; then
      mkdir -p "$PROJ/.zskills"
      echo "zskills: plugin loaded but install lane is /update-zskills. Run /update-zskills --switch-install-path=to-plugin to switch, or /plugin uninstall zs@zskills to remove the plugin." >&2
      touch "$PROJ/.zskills/dual-install-warned"
    fi
    exit 0  # Do NOT materialise — would clobber /update-zskills install state.
    ;;
  dual)
    if [ ! -f "$PROJ/.zskills/dual-install-warned" ]; then
      mkdir -p "$PROJ/.zskills"
      echo "zskills: dual install detected (/update-zskills AND plugin). Run bash scripts/switch-install-path.sh --to-plugin to consolidate." >&2
      touch "$PROJ/.zskills/dual-install-warned"
    fi
    # Conditional-skip shim handles double-fire on hooks; we still skip the
    # materialiser here too (would clobber /update-zskills install state).
    exit 0
    ;;
esac

# ── Source-tree resolution ────────────────────────────────────────────────
# A released plugin ships agents under ${PLUGIN}/agents/ and hooks under
# ${PLUGIN}/hooks/. The source worktree (dogfood via `claude --plugin-dir .`)
# keeps agents under .claude/agents/. Resolve each source with a fallback.
resolve_src() {
  # $1 = released-plugin-relative path; $2 = source-tree fallback path.
  if [ -f "$PLUGIN/$1" ]; then
    printf '%s\n' "$PLUGIN/$1"
  elif [ -f "$PLUGIN/$2" ]; then
    printf '%s\n' "$PLUGIN/$2"
  else
    return 1
  fi
}

# ── Sentinel + overwrite-guard helpers (D20(a)) ──────────────────────────
SENTINEL_TAG="zskills-materialised:"

# safe_to_write <dest> — true (0) when dest is absent OR carries a zskills
# materialiser sentinel in its first 3 lines. A sentinel-less existing file
# is consumer-authored → do NOT overwrite (return 1).
safe_to_write() {
  local dest="$1"
  [ -f "$dest" ] || return 0
  if head -n 3 "$dest" 2>/dev/null | grep -Eq "^(#|<!--)[[:space:]]+${SENTINEL_TAG}[[:space:]]"; then
    return 0
  fi
  return 1
}

# inject_sentinel <kind> <version> < raw-content > sentinelled-content
# kind ∈ {sh, frontmatter-md, plain-md}. Frontmatter-aware injection:
#   sh            → shell-comment on line 2 (after the shebang).
#   frontmatter-md→ YAML-comment as the first line INSIDE the leading `---`.
#   plain-md      → HTML-comment as the very first line.
#
# The raw content arrives on stdin. We stage it to a temp file and pass the
# path as argv so the Python program (a heredoc, which itself consumes the
# process stdin) can read the content separately.
inject_sentinel() {
  local kind="$1" version="$2" content_tmp
  content_tmp="$(mktemp)"
  cat > "$content_tmp"
  KIND="$kind" VERSION="$version" SENTINEL_TAG="$SENTINEL_TAG" "$PYTHON" - "$content_tmp" <<'PY'
import os, sys
kind = os.environ["KIND"]
version = os.environ["VERSION"]
tag = os.environ["SENTINEL_TAG"]
with open(sys.argv[1]) as f:
    text = f.read()
lines = text.split("\n")

if kind == "sh":
    sentinel = f"# {tag} {version}"
    if lines and lines[0].startswith("#!"):
        out = [lines[0], sentinel] + lines[1:]
    else:
        out = [sentinel] + lines
elif kind == "frontmatter-md":
    sentinel = f"# {tag} {version}"
    # Insert as first line inside the leading `---` block.
    if lines and lines[0].strip() == "---":
        out = [lines[0], sentinel] + lines[1:]
    else:
        # No frontmatter present — fall back to HTML comment at top.
        out = [f"<!-- {tag} {version} -->"] + lines
elif kind == "plain-md":
    out = [f"<!-- {tag} {version} -->"] + lines
else:
    out = lines
sys.stdout.write("\n".join(out))
PY
  rm -f "$content_tmp"
}

# Strip a leading sentinel line (any kind) so two artifacts can be compared
# for content-equality ignoring the version stamp. Used for mtime-stable
# idempotency.
strip_sentinel() {
  local content_tmp
  content_tmp="$(mktemp)"
  cat > "$content_tmp"
  SENTINEL_TAG="$SENTINEL_TAG" "$PYTHON" - "$content_tmp" <<'PY'
import os, re, sys
tag = re.escape(os.environ["SENTINEL_TAG"])
with open(sys.argv[1]) as f:
    text = f.read()
lines = text.split("\n")
out = []
pat = re.compile(rf"^(#|<!--)\s+{tag}\s")
for ln in lines:
    if pat.match(ln):
        continue
    out.append(ln)
sys.stdout.write("\n".join(out))
PY
  rm -f "$content_tmp"
}

# materialise_static <kind> <dest> < sentinelled-content
# Atomic-rename write with mtime-stable idempotency: if the destination
# already exists, is safe to overwrite, and its sentinel-stripped content
# matches the new sentinel-stripped content, the file is left untouched (no
# mtime bump). Otherwise the new content is written atomically.
materialise_static() {
  local kind="$1" dest="$2" new
  new="$(cat)"

  if ! safe_to_write "$dest"; then
    # Consumer-authored (no sentinel) — never clobber.
    return 0
  fi

  if [ -f "$dest" ]; then
    local old_stripped new_stripped
    old_stripped="$(strip_sentinel < "$dest")"
    new_stripped="$(printf '%s' "$new" | strip_sentinel)"
    if [ "$old_stripped" = "$new_stripped" ]; then
      # Content unchanged (modulo version) → leave mtime alone (idempotent).
      return 0
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  local tmp="$dest.zskills-tmp.$$"
  printf '%s' "$new" > "$tmp"
  mv "$tmp" "$dest"
}

# ── Materialise the 4 static artifacts ────────────────────────────────────
# Agents (frontmatter .md).
for agent in verifier implementer; do
  if src="$(resolve_src "agents/$agent.md" ".claude/agents/$agent.md")"; then
    dest="$PROJ/.claude/agents/$agent.md"
    inject_sentinel frontmatter-md "$PLUGIN_VERSION" < "$src" \
      | materialise_static frontmatter-md "$dest"
  fi
done

# Hooks (*.sh — shell-comment on line 2). The materialised copies must be
# executable so the verifier/implementer frontmatter `hooks:` reference
# (`bash $CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh`) resolves.
for hook in inject-bash-timeout verify-response-validate; do
  if src="$(resolve_src "hooks/$hook.sh" "hooks/$hook.sh")"; then
    dest="$PROJ/.claude/hooks/$hook.sh"
    inject_sentinel sh "$PLUGIN_VERSION" < "$src" \
      | materialise_static sh "$dest"
    [ -f "$dest" ] && chmod +x "$dest" 2>/dev/null || true
  fi
done

# ── Seed a default zskills-config.json when ABSENT (plugin lane) ──────────
# Plugins cannot write at install time, and the managed.md render below is
# gated on [ -f "$CONFIG" ]. A fresh plugin install therefore used to leave
# the consumer with NO config and NO managed.md — silently. Seed a default
# headless config here so the render gate passes and all 5 artifacts
# materialise. The preset is locked-main-pr (landing=pr, main_protected=true)
# — the safe default for a fresh consumer.
#
# Idempotent: ONLY create when the config is absent. An existing config (any
# values) is NEVER clobbered. We track whether we seeded this run so the
# one-time review notice below fires only on a real seed.
CONFIG_SEEDED=0
if [ ! -f "$CONFIG" ]; then
  mkdir -p "$PROJ/.claude"
  CONFIG_PROJECT_NAME="$(basename "$PROJ")"
  config_tmp="$(mktemp)"
  PROJECT_NAME="$CONFIG_PROJECT_NAME" "$PYTHON" - "$config_tmp" <<'PY'
import json, os, sys
cfg = {
    "$schema": "./zskills-config.schema.json",
    "project_name": os.environ["PROJECT_NAME"],
    "timezone": "UTC",
    "execution": {
        "landing": "pr",
        "main_protected": True,
        "branch_prefix": "feat/",
    },
    "commit": {
        "co_author": "Claude Opus 4.7 (1M context) <noreply@anthropic.com>",
    },
    "testing": {
        "unit_cmd": "",
        "full_cmd": "",
        "output_file": ".test-results.txt",
        "file_patterns": [],
    },
    "dev_server": {
        "cmd": "",
        "default_port": 8080,
    },
    "ui": {
        "file_patterns": "",
        "auth_bypass": "",
    },
    "ci": {
        "auto_fix": True,
        "max_fix_attempts": 2,
    },
}
with open(sys.argv[1], "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
  if [ -s "$config_tmp" ]; then
    mv "$config_tmp" "$CONFIG"
    CONFIG_SEEDED=1
  else
    rm -f "$config_tmp"
    echo "zskills: failed to seed default zskills-config.json — managed.md will NOT be rendered" >&2
  fi
fi

# ── Materialise the rendered managed.md (5th artifact, D24 renderer) ──────
# W2.3 — read CLAUDE_TEMPLATE.md from the consumer repo first (dogfood the
# live template inside the zskills repo), else the bundled plugin copy.
TEMPLATE=""
if [ -f "$PROJ/CLAUDE_TEMPLATE.md" ]; then
  TEMPLATE="$PROJ/CLAUDE_TEMPLATE.md"
elif [ -f "$PLUGIN/CLAUDE_TEMPLATE.md" ]; then
  TEMPLATE="$PLUGIN/CLAUDE_TEMPLATE.md"
fi

RENDERER=""
if [ -f "$PLUGIN/scripts/render-managed-rules.py" ]; then
  RENDERER="$PLUGIN/scripts/render-managed-rules.py"
fi

# Surface-not-silent: if any precondition for rendering managed.md is
# missing, say so on stderr instead of slipping past to exit 0. (Before this
# the render simply didn't happen and the consumer got no managed.md and no
# explanation.)
if [ -z "$TEMPLATE" ]; then
  echo "zskills: managed.md NOT rendered — CLAUDE_TEMPLATE.md not found (looked in \$PROJ and \$PLUGIN)" >&2
elif [ -z "$RENDERER" ]; then
  echo "zskills: managed.md NOT rendered — renderer scripts/render-managed-rules.py not found under \$PLUGIN" >&2
elif [ ! -f "$CONFIG" ]; then
  echo "zskills: managed.md NOT rendered — zskills-config.json absent (seed failed?)" >&2
else
  managed_dest="$PROJ/.claude/rules/zskills/managed.md"
  if safe_to_write "$managed_dest"; then
    # Render into a temp file with the sentinel, then run it through the
    # same idempotent materialise path so mtime only advances on a real
    # content change.
    render_tmp="$(mktemp)"
    if "$PYTHON" "$RENDERER" \
        --config "$CONFIG" \
        --template "$TEMPLATE" \
        --out "$render_tmp" \
        --sentinel "$PLUGIN_VERSION"; then
      materialise_static plain-md "$managed_dest" < "$render_tmp"
    else
      echo "zskills: managed.md NOT rendered — render-managed-rules.py failed (config=$CONFIG template=$TEMPLATE)" >&2
    fi
    rm -f "$render_tmp"
  fi
fi

# ── One-time seed notice (gated by a marker, same pattern as D27 probe) ───
# Emit ONLY when we actually seeded a default config this run. Tells the
# consumer to review the generated config (test commands + landing mode).
if [ "$CONFIG_SEEDED" -eq 1 ] && [ ! -f "$PROJ/.zskills/config-seeded-notice" ]; then
  mkdir -p "$PROJ/.zskills"
  echo "zskills: created a default .claude/zskills-config.json (locked-main-pr: landing=pr, main_protected=true). Review it — especially testing.unit_cmd/full_cmd and execution.landing — and adjust for this project." >&2
  touch "$PROJ/.zskills/config-seeded-notice"
fi

exit 0
