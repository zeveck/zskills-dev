#!/bin/bash
# gh-host.sh — resolve the GitHub host from `origin` and export GH_HOST.
#
# Owner: /land-pr (skills/land-pr). Shared by the gh-using land-pr scripts
# (pr-monitor.sh, pr-merge.sh, pr-push-and-create.sh) and recommended for
# any gh call in the land-pr / commit / fix-issues flows.
#
# WHY (issue #1162): `gh` defaults every subcommand to github.com unless
# told otherwise. On an enterprise-GitHub repo whose `origin` points at
# (e.g.) github.example.com, a bare `gh auth status` / branch-protection
# query answers for github.com — a false "authed, no protection" green-
# light that has merged a PR overnight on the wrong host. `gh` honors the
# `GH_HOST` environment variable GLOBALLY for ALL subcommands, so the
# robust, minimal fix is to derive the host ONCE from the repo's actual
# remote and export it — no need to thread `--hostname` through every call.
#
# USAGE — source it (so the export reaches the caller's gh invocations):
#   . "$(dirname "$0")/gh-host.sh"     # or via $ZSKILLS_SKILLS_ROOT
# After sourcing, $GH_HOST is exported (when a host could be resolved).
#
# BEHAVIOR:
#   - Parses `git remote get-url origin` and extracts the host from the
#     common URL shapes:
#       * SSH scp-like:  git@HOST:owner/repo.git
#       * SSH URL:       ssh://git@HOST[:port]/owner/repo.git
#       * HTTPS/HTTP:    https://HOST/owner/repo(.git)  (strips userinfo)
#   - github.com remotes resolve to host `github.com` (no behavior change).
#   - If GH_HOST is ALREADY set in the environment, it is respected and
#     NOT overwritten (explicit caller override wins).
#   - If origin is absent / unparseable, GH_HOST is left UNSET (gh keeps
#     its own default) — fail-open, never abort the caller.
#
# This script is SOURCED, so it must not `exit` on the no-resolve path and
# must not leave `set -e`/`set -u` side effects in the caller.

# Honor an explicit caller-provided GH_HOST — do not clobber it.
if [ -n "${GH_HOST:-}" ]; then
  : # already set; respect it
else
  _zsk_ghhost_url=""
  _zsk_ghhost_host=""
  # `git remote get-url origin` — tolerate absence (no remote, not a repo).
  _zsk_ghhost_url=$(git remote get-url origin 2>/dev/null || true)

  if [ -n "$_zsk_ghhost_url" ]; then
    case "$_zsk_ghhost_url" in
      ssh://*|git+ssh://*)
        # ssh://[user@]HOST[:port]/path  → strip scheme, userinfo, port, path
        _zsk_ghhost_host="${_zsk_ghhost_url#*://}"   # drop scheme
        _zsk_ghhost_host="${_zsk_ghhost_host#*@}"    # drop userinfo
        _zsk_ghhost_host="${_zsk_ghhost_host%%/*}"   # drop /path
        _zsk_ghhost_host="${_zsk_ghhost_host%%:*}"   # drop :port
        ;;
      http://*|https://*)
        # http(s)://[user[:pass]@]HOST[:port]/path
        _zsk_ghhost_host="${_zsk_ghhost_url#*://}"   # drop scheme
        _zsk_ghhost_host="${_zsk_ghhost_host#*@}"    # drop userinfo
        _zsk_ghhost_host="${_zsk_ghhost_host%%/*}"   # drop /path
        _zsk_ghhost_host="${_zsk_ghhost_host%%:*}"   # drop :port
        ;;
      *@*:*)
        # scp-like: [user@]HOST:owner/repo(.git)
        _zsk_ghhost_host="${_zsk_ghhost_url#*@}"     # drop user@
        _zsk_ghhost_host="${_zsk_ghhost_host%%:*}"   # drop :owner/repo
        ;;
      *)
        _zsk_ghhost_host=""
        ;;
    esac
  fi

  if [ -n "$_zsk_ghhost_host" ]; then
    export GH_HOST="$_zsk_ghhost_host"
  fi

  unset _zsk_ghhost_url _zsk_ghhost_host
fi
