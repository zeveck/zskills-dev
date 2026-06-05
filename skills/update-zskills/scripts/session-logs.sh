#!/bin/bash
# session-logs.sh -- resolve / read the zskills session-log directory(ies).
#
# Tier-1, owned by `update-zskills`. Models its shape on the sibling
# port.sh: a tiny resolver around the same precedence the session-logging
# hooks (hooks/log-session-stop.sh, hooks/log-permission-request.sh) use.
#
# Usage:
#   bash session-logs.sh            # print the resolved log dir(s) to stdout
#   bash session-logs.sh <dest>     # copy the session logs to <dest>
#
# PUBLISH-WHERE-IT-WROTE REGISTRY (issue #1059). The old design had this
# helper re-resolve the log dir independently via Python
# tempfile.gettempdir(), which honors per-context $TMPDIR. Claude Code sets
# TMPDIR differently per context, so the reader (here) and the writer (the
# Stop hook) diverged and logs became unfindable. The fix: the Stop hook
# RECORDS each resolved absolute log dir into a shared registry at
# <main-repo-root>/.zskills/session-log-dirs (main root =
# `git rev-parse --git-common-dir`/.., shared across all worktrees). This
# helper READS that registry FIRST and unions logs across every recorded
# dir that STILL EXISTS. It falls back to its own per-OS resolution ONLY
# when the registry is absent (run outside a repo, or before the first Stop
# fired).
#
# Fallback log-dir resolution precedence (MUST match the hooks):
#   ZSKILLS_LOG_DIR env
#     > logging.dir   (from .claude/zskills-config.json)
#     > per-OS cache default:
#         Linux/other : ${XDG_CACHE_HOME:-$HOME/.cache}/zskills-session-logs/<p>
#         macOS       : $HOME/Library/Caches/zskills-session-logs/<p>
#         Windows     : %LOCALAPPDATA%\zskills-session-logs\<p>
# <project> = the project-dir basename (path-separator-safe). The per-OS
# default replaces the old tempfile.gettempdir() so it is a STABLE,
# self-cleaning cache root rather than a per-context TMPDIR.

set -u

# PROJECT_ROOT from invocation context (git toplevel; fall back to PWD).
# CLAUDE_PROJECT_DIR, when set by the harness, takes precedence so the
# config + <project> basename match the hooks' view of the project.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"

# Resolve Python (per `## Python is required`).
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
PYTHON="$(zskills_resolve_python || true)"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

# Emit, one per line, the log dir(s) to use:
#   1. The registry's recorded dirs that STILL EXIST (union), if the
#      registry is present and non-empty.
#   2. Otherwise the per-OS fallback resolution (single dir).
# The resolution logic below is KEPT IDENTICAL to the hooks (issue #1059).
LOG_DIRS="$(
  ZSKILLS_LOG_DIR="${ZSKILLS_LOG_DIR:-}" \
  ZSKILLS_PROJECT_DIR="$PROJECT_ROOT" \
  "$PYTHON" - <<'PY'
import json, os, platform, subprocess, sys

project_dir = os.environ.get("ZSKILLS_PROJECT_DIR", os.getcwd())


# ── SHARED RESOLUTION (issue #1059) ──────────────────────────────────────
# KEEP IDENTICAL to hooks/log-session-stop.sh + hooks/log-permission-request.sh.
def sanitize_segment(seg):
    """Make a string safe as a SINGLE cross-platform path segment. Replace
    os.sep, /, \\, the Windows-reserved chars (: * ? " < > |) and whitespace
    with _, strip leading/trailing dots/spaces; empty -> 'unknown'."""
    if not seg:
        return "unknown"
    bad = set(os.sep) | {"/", "\\", ":", "*", "?", '"', "<", ">", "|"}
    out = []
    for ch in seg:
        if ch in bad or ch.isspace():
            out.append("_")
        else:
            out.append(ch)
    result = "".join(out).strip(". ")
    return result or "unknown"


def project_base(project_dir):
    base = os.path.basename(os.path.normpath(project_dir)) or "project"
    return sanitize_segment(base)


def resolve_user():
    """Precedence: ZSKILLS_LOG_USER env > git config user.email >
    getpass.getuser() > 'unknown'. Resolved at RUNTIME, never stored in
    config. KEEP IDENTICAL to the hooks."""
    user = os.environ.get("ZSKILLS_LOG_USER", "")
    if not user:
        try:
            out = subprocess.run(
                ["git", "config", "user.email"],
                capture_output=True, text=True, timeout=5)
            if out.returncode == 0:
                user = out.stdout.strip()
        except Exception:
            user = ""
    if not user:
        try:
            import getpass
            user = getpass.getuser()
        except Exception:
            user = ""
    return sanitize_segment(user)


def default_cache_base(project_dir):
    """Per-OS stable cache BASE (replaces tempfile.gettempdir()). The <repo>
    segment is a composition step, not baked in here. KEEP IDENTICAL to the
    hooks."""
    system = platform.system()
    if system == "Windows":
        root = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    elif system == "Darwin":
        root = os.path.join(os.path.expanduser("~"), "Library", "Caches")
    else:
        root = (os.environ.get("XDG_CACHE_HOME")
                or os.path.join(os.path.expanduser("~"), ".cache"))
    return os.path.join(root, "zskills-session-logs")


def read_compose_cfg(project_dir):
    """Return (cfg_dir, include_repo, include_user) from logging.*. Defaults:
    "", True, False — preserve today's composed path byte-for-byte. KEEP
    IDENTICAL defaults to the hooks' read_config."""
    cfg_dir = ""
    include_repo = True
    include_user = False
    try:
        cfg_path = os.path.join(project_dir, ".claude", "zskills-config.json")
        with open(cfg_path) as f:
            cfg = json.load(f)
        logging = cfg.get("logging", {})
        if isinstance(logging, dict):
            d = logging.get("dir", "")
            if isinstance(d, str):
                cfg_dir = d
            if "include_repo" in logging:
                include_repo = bool(logging.get("include_repo"))
            if "include_user" in logging:
                include_user = bool(logging.get("include_user"))
    except Exception:
        pass
    return cfg_dir, include_repo, include_user


def compose_log_dir(project_dir, base, include_repo, include_user):
    """Compose <base>/[<repo>]/[<user>]. KEEP IDENTICAL to the hooks."""
    path = base
    if include_repo:
        path = os.path.join(path, project_base(project_dir))
    if include_user:
        path = os.path.join(path, resolve_user())
    return path


def fallback_dir(project_dir):
    """Precedence: ZSKILLS_LOG_DIR env > logging.dir config > per-OS cache
    base, then compose <base>/[<repo>]/[<user>]. KEEP IDENTICAL to the
    hooks."""
    cfg_dir, include_repo, include_user = read_compose_cfg(project_dir)
    env_dir = os.environ.get("ZSKILLS_LOG_DIR", "")
    if env_dir:
        base = env_dir
    elif cfg_dir:
        base = cfg_dir
    else:
        base = default_cache_base(project_dir)
    return compose_log_dir(project_dir, base, include_repo, include_user)


def main_repo_root(project_dir):
    """main root = `git rev-parse --git-common-dir`/.. (shared across all
    worktrees). KEEP IDENTICAL to the hook."""
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--git-common-dir"],
            cwd=project_dir, capture_output=True, text=True, timeout=5)
        if out.returncode == 0:
            common = out.stdout.strip()
            if common:
                if not os.path.isabs(common):
                    common = os.path.join(project_dir, common)
                return os.path.abspath(os.path.join(common, ".."))
    except Exception:
        pass
    return os.path.abspath(project_dir)


def read_registry(project_dir):
    """Return the list of recorded log dirs (in file order, deduped) from
    <main-repo-root>/.zskills/session-log-dirs, or [] when the registry is
    absent/empty. Comment (#) and blank lines are skipped; each data line
    is `<iso-ts>\\t<abs-path>`."""
    registry = os.path.join(main_repo_root(project_dir), ".zskills",
                            "session-log-dirs")
    dirs = []
    seen = set()
    try:
        with open(registry) as f:
            for raw in f:
                line = raw.rstrip("\n")
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                # Split on the first tab; tolerate space-separated too.
                if "\t" in line:
                    path = line.split("\t", 1)[1].strip()
                else:
                    parts = line.split(None, 1)
                    path = parts[1].strip() if len(parts) == 2 else line.strip()
                if path and path not in seen:
                    seen.add(path)
                    dirs.append(path)
    except OSError:
        return []
    return dirs


# Precedence: an explicit pin (ZSKILLS_LOG_DIR env / logging.dir config)
# is deterministic and chosen by the user — writer and reader both resolve
# to it identically (including the <repo>/<user> composition), so there is no
# drift to solve and the pin wins over the registry. The registry exists to
# fix the BLANK-default drift only. So:
#   ZSKILLS_LOG_DIR > logging.dir > registry-union > per-OS default.
# An explicit pin is still COMPOSED (<base>/[<repo>]/[<user>]) so the helper
# resolves to the SAME composed dir the hooks wrote to.
env_dir = os.environ.get("ZSKILLS_LOG_DIR", "")
cfg_dir, include_repo, include_user = read_compose_cfg(project_dir)

if env_dir:
    print(compose_log_dir(project_dir, env_dir, include_repo, include_user))
elif cfg_dir:
    print(compose_log_dir(project_dir, cfg_dir, include_repo, include_user))
else:
    regdirs = read_registry(project_dir)
    existing = [d for d in regdirs if os.path.isdir(d)]
    if existing:
        for d in existing:
            print(d)
    else:
        # Registry absent, or present but none of its dirs still exist:
        # fall back to per-OS resolution so a caller still gets a sane
        # (possibly empty) target rather than nothing.
        print(fallback_dir(project_dir))
PY
)"

if [ -z "$LOG_DIRS" ]; then
  echo "session-logs.sh: failed to resolve log dir" >&2
  exit 1
fi

# Read the resolved dirs into an array (newline-separated).
mapfile -t DIR_ARRAY <<< "$LOG_DIRS"

# No args: print the resolved dir(s), one per line.
if [ "$#" -eq 0 ]; then
  printf '%s\n' "${DIR_ARRAY[@]}"
  exit 0
fi

# One dest arg: copy the logs there from EVERY resolved dir (union).
# Literal-safe cp (no rm -rf on a variable path, per the repo's
# block-unsafe rules). Create the destination, then copy contents in.
DEST="$1"
mkdir -p "$DEST" || { echo "session-logs.sh: cannot create $DEST" >&2; exit 1; }

COPIED_ANY=0
COPY_FAILED=0
for SRC in "${DIR_ARRAY[@]}"; do
  [ -d "$SRC" ] || continue
  # cp -a preserves modes/timestamps; trailing /. copies contents (not the
  # dir itself). No recursive delete is performed. Across multiple recorded
  # dirs the later copies overlay the earlier ones (union by filename).
  if cp -a "$SRC/." "$DEST/"; then
    echo "session-logs.sh: copied logs from $SRC to $DEST"
    COPIED_ANY=1
  else
    echo "session-logs.sh: copy from $SRC to $DEST failed" >&2
    COPY_FAILED=1
  fi
done

if [ "$COPIED_ANY" -eq 0 ]; then
  echo "session-logs.sh: no existing log dir to copy (resolved: $LOG_DIRS)" >&2
  exit 1
fi
[ "$COPY_FAILED" -eq 0 ] || exit 1
exit 0
