#!/usr/bin/env python3
# migrate-strip-settings.py — companion helper for switch-install-path.sh
# (W5.6, D25).
#
# Strips zskills-installed hook entries from a consumer's
# .claude/settings.json. A zskills hook entry is any
# `hooks.<event>[].hooks[]` record whose `command` path-token lives under
# `.claude/hooks/` (the directory the /update-zskills lane installs into).
# Matching is on the LITERAL token (settings.json stores
# `$CLAUDE_PROJECT_DIR` / `${CLAUDE_PROJECT_DIR}` unexpanded), so the
# `/.claude/hooks/` substring is checked without env-var substitution —
# symmetric to detect-install-state.sh's settings.json probe.
#
# After removing matching hook records, any matcher object whose `hooks`
# array becomes empty is dropped, and any event array that becomes empty is
# dropped; an emptied top-level `hooks` object is removed entirely. All
# other settings keys are preserved verbatim.
#
# Per `## Python is required` — stdlib json only, no jq.
#
# Usage:
#   migrate-strip-settings.py <settings.json path>
#
# Idempotent: a settings.json with no `.claude/hooks/` entries is rewritten
# byte-for-byte equivalent (formatting may normalise, but content is
# unchanged). Exits 0 on success, 0 if the file is absent (nothing to
# strip), 1 on parse error.

import json
import os
import sys


def is_zskills_hook(cmd):
    if not isinstance(cmd, str) or not cmd.strip():
        return False
    token = cmd.split()[-1].strip('"').strip("'")
    return "/.claude/hooks/" in token or token.startswith(".claude/hooks/")


def strip(data):
    """Return (new_data, removed_count)."""
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return data, 0
    removed = 0
    new_hooks = {}
    for event, matchers in hooks.items():
        if not isinstance(matchers, list):
            new_hooks[event] = matchers
            continue
        new_matchers = []
        for matcher in matchers:
            if not isinstance(matcher, dict):
                new_matchers.append(matcher)
                continue
            inner = matcher.get("hooks")
            if not isinstance(inner, list):
                new_matchers.append(matcher)
                continue
            kept = []
            for h in inner:
                if isinstance(h, dict) and is_zskills_hook(h.get("command", "")):
                    removed += 1
                    continue
                kept.append(h)
            if not kept:
                # Whole matcher block became empty → drop it.
                continue
            new_matcher = dict(matcher)
            new_matcher["hooks"] = kept
            new_matchers.append(new_matcher)
        if new_matchers:
            new_hooks[event] = new_matchers
        # else: event array emptied → drop it.
    if new_hooks:
        data["hooks"] = new_hooks
    else:
        # Top-level hooks object emptied → remove it entirely.
        data.pop("hooks", None)
    return data, removed


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: migrate-strip-settings.py <settings.json>\n")
        return 2
    path = sys.argv[1]
    if not os.path.exists(path):
        # Nothing to strip — plugin-only / fresh consumer.
        return 0
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception as e:
        sys.stderr.write(f"ERROR: cannot parse {path}: {e}\n")
        return 1
    if not isinstance(data, dict):
        sys.stderr.write(f"ERROR: {path} is not a JSON object\n")
        return 1

    data, removed = strip(data)

    # Atomic write via tmpfile + rename.
    tmp = path + ".zskills-tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)

    sys.stderr.write(f"migrate-strip-settings: removed {removed} zskills hook entr"
                     f"{'y' if removed == 1 else 'ies'} from {path}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
