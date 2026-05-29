"""managed_rules_substitution — single source-of-truth substitution map.

This module is the ONE substitution map for rendering
`CLAUDE_TEMPLATE.md` -> `.claude/rules/zskills/managed.md`. It is consumed
by THREE callers (D24, F-DA2-2):

  1. ``scripts/render-managed-rules.py`` — the thin CLI wrapper invoked by
     the plugin SessionStart materialiser (W2.1) AND by ``/update-zskills``
     Step B/D (W2.7).
  2. ``tests/test-managed-md-up-to-date.sh`` — refactored (W2.7) to invoke
     the renderer rather than carrying its own inlined ``subs = {...}``
     dict.
  3. The plugin SessionStart materialiser, via caller (1).

Because all three callers route through ``build_substitutions`` + ``apply``
here, byte-equality across render paths is structurally guaranteed;
``tests/test-managed-md-renderer-equivalence.sh`` is the canary that catches
refactor regressions.

The ``subs`` dict construction below was lifted VERBATIM from the inlined
``subs = {...}`` Python block that previously lived in
``tests/test-managed-md-up-to-date.sh`` (the 10-placeholder map). No
behavioural change — just relocation into a single importable module.
"""

import re


def _empty_or(value, fallback):
    """Return ``fallback`` when ``value`` is None or the empty string."""
    if value is None or value == "":
        return fallback
    return value


def build_substitutions(cfg):
    """Return the placeholder -> value substitution map for ``cfg``.

    ``cfg`` is the parsed ``.claude/zskills-config.json`` dict. The returned
    dict keys are bare placeholder names (e.g. ``PROJECT_NAME``); ``apply``
    wraps each in ``{{...}}`` before substituting.
    """
    ds = cfg.get("dev_server", {})
    testing = cfg.get("testing", {})
    ui = cfg.get("ui", {})
    patterns = testing.get("file_patterns", [])
    patterns_md = (
        "\n".join(f"- `{p}`" for p in patterns)
        if patterns
        else "<!-- TODO: testing.file_patterns is empty -->"
    )

    return {
        "PROJECT_NAME": cfg.get("project_name", ""),
        "TIMEZONE": cfg.get("timezone", ""),
        "DEFAULT_PORT": str(ds.get("default_port", "")),
        "MAIN_REPO_PATH": ds.get("main_repo_path", ""),
        "UNIT_TEST_CMD": testing.get("unit_cmd", ""),
        "FULL_TEST_CMD": testing.get("full_cmd", ""),
        "TEST_FILE_PATTERNS": patterns_md,
        "DEV_SERVER_CMD": _empty_or(
            ds.get("cmd", ""),
            "<!-- TODO: dev_server.cmd not set in .claude/zskills-config.json -->",
        ),
        "AUTH_BYPASS": _empty_or(
            ui.get("auth_bypass", ""),
            "<!-- TODO: ui.auth_bypass not set in .claude/zskills-config.json -->",
        ),
        "SOURCE_LAYOUT": "<!-- TODO: SOURCE_LAYOUT has no config field; fill in project's architecture summary -->",
    }


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
