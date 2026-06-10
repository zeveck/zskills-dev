"""managed_rules_substitution — single source-of-truth substitution map.

This module is the ONE substitution map for rendering
`CLAUDE_TEMPLATE.md` -> `.claude/rules/zskills/managed.md` (D24). It is
consumed via ``scripts/render-managed-rules.py`` — the thin CLI wrapper
invoked by the plugin SessionStart hooks (the materialiser, and the R-b
``session-rules-context.sh`` rules-delivery hook) AND by ``/update-zskills``
Step B/D — and by ``tests/test-managed-md-up-to-date.sh`` through that same
wrapper. Because every caller routes through ``build_substitutions`` +
``apply`` here, byte-equality across render paths is structural;
``tests/test-managed-md-renderer-equivalence.sh`` is the canary.

INSTALL_REDESIGN Phase 4 — the template is fully DE-PARAMETERIZED: the
managed rules are install-level, carrying no per-project ``{{TOKEN}}``
placeholders (project-specific values are resolved from
``.claude/zskills-config.json`` at point of use via the canonical prelude).
The substitution map therefore shrank to EMPTY and the render is a
structural pass-through. The module survives (D24 — one renderer, both
lanes) for two reasons:

  1. ``apply``'s leftover-placeholder guard still fails the render loudly
     if a ``{{TOKEN}}`` ever reappears (a regression in the shipped
     template, or a consumer-authored template still carrying retired
     tokens) — a broken ``{{...}}`` must never ship silently.
  2. The renderer's call shape (``--config`` / no-config defaults) stays
     stable for both lanes and for future map growth.
"""

import re


def build_substitutions(cfg):
    """Return the placeholder -> value substitution map for ``cfg``.

    ``cfg`` is the parsed config dict (project config, or the canonical
    built-in defaults from ``zskills-defaults.json`` in no-config mode).
    Post de-parameterization (INSTALL_REDESIGN Phase 4) the map is EMPTY —
    the template carries no ``{{TOKEN}}`` placeholders. The ``cfg``
    parameter is retained so the D24 caller contract (config in, map out)
    is stable.
    """
    del cfg  # de-parameterized template: no config-derived placeholders
    return {}


def apply(template, subs):
    """Render ``template`` by substituting every ``{{KEY}}`` from ``subs``.

    Raises ``ValueError`` if any ``{{PLACEHOLDER}}`` remains unsubstituted
    after applying the map — this keeps a render from silently shipping a
    broken ``{{...}}`` token.
    """
    rendered = template
    for k, v in subs.items():
        rendered = rendered.replace("{{" + k + "}}", v)

    leftover = re.findall(r"\{\{[A-Z_]+\}\}", rendered)
    if leftover:
        raise ValueError(
            f"render left unsubstituted placeholders: {leftover}"
        )
    return rendered
