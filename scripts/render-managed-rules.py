#!/usr/bin/env python3
"""render-managed-rules.py — thin CLI wrapper over managed_rules_substitution.

Renders ``CLAUDE_TEMPLATE.md`` against a ``.claude/zskills-config.json`` into
``.claude/rules/zskills/managed.md`` (or any ``--out`` path). It is the ONE
canonical renderer (D24), invoked by:

  - the plugin SessionStart materialiser (W2.1), and
  - ``/update-zskills`` Step B §2 / Step D §2 (W2.7).

Because both callers route through ``managed_rules_substitution.build_substitutions``
+ ``apply``, byte-equality across render paths is structural;
``tests/test-managed-md-renderer-equivalence.sh`` is the canary.

Usage:
    render-managed-rules.py --config <cfg.json> --template <tmpl.md> \\
        --out <out.md> [--sentinel <version>]

``--sentinel <version>`` prepends an HTML-comment materialiser sentinel line
matching the D20(a) detect-by-prefix regex ``^(#|<!--) zskills-materialised: ``
to the rendered output. ``managed.md`` is a plain (no-frontmatter) ``.md``
file, so the sentinel is an HTML comment. Omit ``--sentinel`` on the
``/update-zskills`` lane (where the file is checked in unsentinelled).
"""

import argparse
import json
import os
import sys

# Import the single source-of-truth substitution module that lives next to
# this wrapper, regardless of the current working directory.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from managed_rules_substitution import build_substitutions, apply  # noqa: E402

# The materialiser-sentinel prefix per D20(a). Detection is by the regex
# ``^(#|<!--) zskills-materialised: `` — for a plain .md file (no
# frontmatter) the sentinel is an HTML comment.
SENTINEL_PREFIX = "<!-- zskills-materialised:"


def main(argv=None):
    parser = argparse.ArgumentParser(description="Render managed.md from template + config.")
    parser.add_argument("--config", required=True, help="path to .claude/zskills-config.json")
    parser.add_argument("--template", required=True, help="path to CLAUDE_TEMPLATE.md")
    parser.add_argument("--out", required=True, help="output path for rendered managed.md")
    parser.add_argument(
        "--sentinel",
        default=None,
        help="if set, prepend an HTML-comment materialiser sentinel carrying this version",
    )
    args = parser.parse_args(argv)

    try:
        with open(args.template) as f:
            template = f.read()
    except OSError as e:
        print(f"ERROR: cannot read template {args.template}: {e}", file=sys.stderr)
        return 1
    try:
        with open(args.config) as f:
            cfg = json.load(f)
    except OSError as e:
        print(f"ERROR: cannot read config {args.config}: {e}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"ERROR: invalid JSON in {args.config}: {e}", file=sys.stderr)
        return 1

    subs = build_substitutions(cfg)
    try:
        rendered = apply(template, subs)
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    if args.sentinel is not None:
        rendered = f"{SENTINEL_PREFIX} {args.sentinel} -->\n" + rendered

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
