#!/usr/bin/env python3
# scripts/porting/hooks-translate.py — Claude hooks.json → Codex hooks.json
# translator (CODEX_PORT_PLAN Phase 3, WI 3.4).
#
# Codex's hooks.json format is Claude-shaped (capability map: "hooks.json
# registration — ~/.codex/hooks.json, <repo>/.codex/hooks.json"), so the
# event/matcher/command structure passes through. Two transformations:
#
#   1. Plugin-root path rewrite (--plugin-root-style, REQUIRED — the porting
#      agent decides from the assumptions manifest):
#        alias   keep `CLAUDE_PLUGIN_ROOT` — valid ONLY when the probe
#                confirmed Codex's compat alias
#                (probe id plugins.env.claude-plugin-root-alias)
#        native  rewrite `${CLAUDE_PLUGIN_ROOT}` → `${PLUGIN_ROOT}` (and any
#                bare `CLAUDE_PLUGIN_ROOT` token → `PLUGIN_ROOT`)
#   2. DROP entries whose event/tool has no Codex substrate (the data tables
#      below), listing each drop in the stdout degradations section. A
#      matcher mixing live and dead tools (e.g. `Bash|CronCreate`) is
#      narrowed, with the narrowing reported.
#
# The stdout report always ends with the TRUST-REVIEW note: Codex requires
# explicit user trust-review before non-managed hooks first run — translated
# hooks are DEAD until the user trusts them, and the install recipe must say
# so.
#
# Python 3 stdlib only.
#
# USAGE
#   hooks-translate.py <hooks.json> --plugin-root-style {alias|native} --out <path>
#
# Exit codes: 0 = translated, 1 = input/parse error, 2 = usage.

import argparse
import json
import os
import sys

# ---------------------------------------------------------------------------
# Codex substrate tables — DATA (probe results are rework triggers: Phase 4's
# triage amends these when a probe falsifies a row).
#
# SUPPORTED_EVENTS: PreToolUse and SessionStart are probe-verified
# (hooks.pretooluse.*, hooks.sessionstart.* — "byte-for-byte the Claude
# contract"); PostToolUse/Stop/SubagentStop ride the same Claude-shaped
# lifecycle format per the capability map's hooks.json row.
#
# DROPPED_EVENTS / NO_SUBSTRATE_TOOLS: events/tools with NO Codex substrate.
# ---------------------------------------------------------------------------
SUPPORTED_EVENTS = ["PreToolUse", "PostToolUse", "SessionStart", "Stop",
                    "SubagentStop"]
DROPPED_EVENTS = {
    "UserPromptExpansion": "no Codex substrate — Codex skill invocation is "
                           "$-mention/implicit trigger, with no "
                           "prompt-expansion hook event",
    "PermissionRequest": "no Codex substrate — Codex permissioning is "
                         "approval_policy/sandbox_mode/execpolicy config, "
                         "not a hook event",
}
NO_SUBSTRATE_TOOLS = {
    "CronCreate": "no cron in the bare Codex CLI — the foreground runner "
                  "replaces scheduling (capability map: CronCreate → None)",
    "CronList": "no cron in the bare Codex CLI",
    "CronDelete": "no cron in the bare Codex CLI",
}

TRUST_NOTE = ("TRUST-REVIEW NOTE: Codex requires explicit user trust-review "
              "before non-managed hooks first run — the translated hooks "
              "are DEAD until the user trusts them; the install recipe must "
              "say so.")


def rewrite_plugin_root(command, style):
    if style == "alias":
        return command
    out = command.replace("${CLAUDE_PLUGIN_ROOT}", "${PLUGIN_ROOT}")
    return out.replace("CLAUDE_PLUGIN_ROOT", "PLUGIN_ROOT")


def describe_entry(event, matcher, entry):
    cmds = "; ".join(h.get("command", "<no command>")
                     for h in entry.get("hooks", []))
    where = "%s[matcher=%s]" % (event, matcher) if matcher else event
    return "%s: %s" % (where, cmds)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Translate a Claude hooks/hooks.json into a Codex "
                    ".codex/hooks.json.")
    parser.add_argument("input", help="path to the Claude hooks.json")
    parser.add_argument("--plugin-root-style", required=True,
                        choices=["alias", "native"],
                        help="alias = keep CLAUDE_PLUGIN_ROOT (only when the "
                             "probe confirmed the compat alias); native = "
                             "rewrite to ${PLUGIN_ROOT}")
    parser.add_argument("--out", required=True,
                        help="output path (e.g. <target>/.codex/hooks.json)")
    args = parser.parse_args(argv)

    try:
        with open(args.input, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, json.JSONDecodeError) as e:
        print("ERROR: cannot read %s: %s" % (args.input, e), file=sys.stderr)
        return 1

    hooks_by_event = doc.get("hooks")
    if not isinstance(hooks_by_event, dict):
        print("ERROR: %s carries no top-level 'hooks' object" % args.input,
              file=sys.stderr)
        return 1

    dropped = []
    out_events = {}

    for event, entries in hooks_by_event.items():
        if event in DROPPED_EVENTS:
            for entry in entries:
                dropped.append("%s — %s"
                               % (describe_entry(event,
                                                 entry.get("matcher", ""),
                                                 entry),
                                  DROPPED_EVENTS[event]))
            continue
        if event not in SUPPORTED_EVENTS:
            for entry in entries:
                dropped.append("%s — event '%s' is not in the Codex "
                               "substrate table" %
                               (describe_entry(event,
                                               entry.get("matcher", ""),
                                               entry), event))
            continue

        kept_entries = []
        for entry in entries:
            matcher = entry.get("matcher", "")
            new_entry = {}
            if matcher:
                tokens = matcher.split("|")
                dead = [t for t in tokens if t in NO_SUBSTRATE_TOOLS]
                live = [t for t in tokens if t not in NO_SUBSTRATE_TOOLS]
                if not live:
                    dropped.append("%s — %s"
                                   % (describe_entry(event, matcher, entry),
                                      NO_SUBSTRATE_TOOLS[dead[0]]))
                    continue
                if dead:
                    dropped.append("%s — matcher narrowed to '%s' (%s)"
                                   % (describe_entry(event, matcher, entry),
                                      "|".join(live),
                                      "; ".join(NO_SUBSTRATE_TOOLS[t]
                                                for t in dead)))
                new_entry["matcher"] = "|".join(live)
            new_hooks = []
            for h in entry.get("hooks", []):
                nh = dict(h)
                if "command" in nh:
                    nh["command"] = rewrite_plugin_root(
                        nh["command"], args.plugin_root_style)
                new_hooks.append(nh)
            new_entry["hooks"] = new_hooks
            kept_entries.append(new_entry)
        if kept_entries:
            out_events[event] = kept_entries

    out_doc = {"hooks": out_events}
    out_dir = os.path.dirname(os.path.abspath(args.out))
    os.makedirs(out_dir, exist_ok=True)
    tmp = args.out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(out_doc, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, args.out)

    print("translated %s -> %s (plugin-root-style=%s)"
          % (args.input, args.out, args.plugin_root_style))
    print("")
    if dropped:
        print("DROPPED (no Codex substrate) — record each in the "
              "degradations section of the port record:")
        for d in dropped:
            print("  - %s" % d)
    else:
        print("DROPPED: none")
    print("")
    print(TRUST_NOTE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
