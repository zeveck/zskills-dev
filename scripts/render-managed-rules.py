#!/usr/bin/env python3
"""render-managed-rules.py — thin CLI wrapper over managed_rules_substitution.

Renders ``CLAUDE_TEMPLATE.md`` against a ``.claude/zskills-config.json`` into
``.claude/rules/zskills/managed.md`` (or any ``--out`` path). It is the ONE
canonical renderer (D24), invoked by:

  - the plugin SessionStart rules hook (``hooks/session-rules-context.sh``,
    R-b — renders to a mktemp and emits ``additionalContext``), and
  - ``/update-zskills`` Step B §2 / Step D §2 (W2.7).

Because both callers route through ``managed_rules_substitution.build_substitutions``
+ ``apply``, byte-equality across render paths is structural.

Usage:
    render-managed-rules.py [--config <cfg.json>] --template <tmpl.md> \\
        --out <out.md> [--defaults <defaults.json>]

``--config`` is OPTIONAL (INSTALL_REDESIGN Phase 4 — the redesign's
consumers are config-optional). When omitted, the renderer loads the
canonical built-in defaults from ``--defaults`` (default: the single
checked-in defaults artifact
``skills/update-zskills/scripts/zskills-defaults.json``, resolved relative
to this script — valid in the dev tree, the released plugin tree, and the
legacy portable tree alike). The legacy ``/update-zskills`` Step B/D call
shape (explicit ``--config``) is unchanged.

(The former ``--sentinel`` flag — the D20 materialiser-sentinel injection —
was deleted in INSTALL_REDESIGN Phase 7 with the SessionStart materialiser:
no caller stamps rendered output any more.)
"""

import argparse
import json
import os
import sys

# Import the single source-of-truth substitution module that lives next to
# this wrapper, regardless of the current working directory.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from managed_rules_substitution import build_substitutions, apply  # noqa: E402

# Canonical built-in defaults (INSTALL_REDESIGN Phase 4 — THE single defaults
# artifact; every later defaults copy pins to it). Resolved relative to this
# script so the same path works in the dev tree, the released plugin tree
# (${CLAUDE_PLUGIN_ROOT}/scripts/ -> ${CLAUDE_PLUGIN_ROOT}/skills/...), and
# the legacy portable tree ($PORTABLE/scripts/ -> $PORTABLE/skills/...).
CANONICAL_DEFAULTS = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "skills", "update-zskills", "scripts", "zskills-defaults.json",
)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Render managed.md from template + config.")
    parser.add_argument(
        "--config",
        default=None,
        help="path to .claude/zskills-config.json (optional; when omitted the "
             "canonical built-in defaults are loaded instead)",
    )
    parser.add_argument("--template", required=True, help="path to CLAUDE_TEMPLATE.md")
    parser.add_argument("--out", required=True, help="output path for rendered managed.md")
    parser.add_argument(
        "--defaults",
        default=CANONICAL_DEFAULTS,
        help="path to the canonical built-in defaults JSON, used only when "
             "--config is omitted (default: the checked-in "
             "skills/update-zskills/scripts/zskills-defaults.json)",
    )
    args = parser.parse_args(argv)

    try:
        with open(args.template) as f:
            template = f.read()
    except OSError as e:
        print(f"ERROR: cannot read template {args.template}: {e}", file=sys.stderr)
        return 1
    cfg_path = args.config if args.config is not None else args.defaults
    try:
        with open(cfg_path) as f:
            cfg = json.load(f)
    except OSError as e:
        print(f"ERROR: cannot read config {cfg_path}: {e}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"ERROR: invalid JSON in {cfg_path}: {e}", file=sys.stderr)
        return 1

    subs = build_substitutions(cfg)
    try:
        rendered = apply(template, subs)
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    out_dir = os.path.dirname(os.path.abspath(args.out))
    os.makedirs(out_dir, exist_ok=True)
    # Atomic-rename write (per CLAUDE.md `## Migration scripts` — the
    # rendered managed.md IS the lock and is written LAST/atomically).
    tmp = args.out + ".tmp"
    with open(tmp, "w") as f:
        f.write(rendered)
    os.replace(tmp, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
