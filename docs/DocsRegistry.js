/**
 * Stub catalog for the DOC_VIEWER Phase 2a viewer shell.
 *
 * Five hand-picked entries that smoke the lift + render path end-to-end.
 * Phase 4 replaces this body with the full generated catalog (sourced from
 * the repo's docs/**\/*.md tree).
 *
 * Shape: array of { section: string, items: [{ name, path }] }
 * Paths are repo-root-relative; the viewer (served at /docs/index.html)
 * prepends '../' before fetching, so 'docs/README.md' resolves to
 * '/docs/README.md' on disk under GitHub Pages / python3 -m http.server.
 */
export const DOCS_CATALOG = [
  { section: 'Start here', items: [
    { name: 'Z Skills Docs',           path: 'docs/README.md' },
    { name: 'Workflows',               path: 'docs/guides/WORKFLOWS.md' },
    { name: 'Plugin install',          path: 'docs/guides/PLUGIN_INSTALL.md' },
    { name: 'All skills',              path: 'docs/skills/README.md' },
    { name: 'Inspecting & monitoring', path: 'docs/guides/INSPECTING_AND_MONITORING.md' },
  ] },
];
