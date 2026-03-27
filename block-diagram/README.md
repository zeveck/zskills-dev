# Block Diagram Domain Skills

3 skills for block-diagram editors and visual modeling projects.
They demonstrate how to extend Z Skills with domain-specific workflows.

## Skills

| Skill | Lines | Purpose |
|-------|------:|---------|
| `/add-block` | 633 | Full lifecycle for adding block types: plan, implement, register, UI, docs, tests, example, codegen, runtime, verification, landing |
| `/add-example` | 247 | Example model creation: research concept, design layout, build model file, register, test, screenshot, verify |
| `/model-design` | 250 | Layout guidelines for block diagrams and state charts based on MAAB/NASA standards |

## Using These Skills

**If your project is a block-diagram editor:** these skills encode proven
workflows and layout standards. You'll need to adapt file paths and
selectors to your project's architecture, but the patterns are ready to use.

**If your project is something else:** use these as templates:

| This skill | Generalizes to |
|------------|---------------|
| `/add-block` | Any project with a plugin/component registry (VS Code extensions, game entities) |
| `/add-example` | Any project with example templates (starter projects, demo configurations) |
| `/model-design` | Any project with visual layout rules (diagram tools, form builders, dashboards) |

## Installation

These skills depend on the core Z Skills infrastructure (CLAUDE.md rules,
hooks, scripts). Install everything together:

```bash
git clone https://github.com/zeveck/zskills.git zskills
/setup-zskills install --with-block-diagram-addons
```

Or if you already have the core skills installed:

```bash
/setup-zskills install --with-block-diagram-addons
```

Once installed, `/setup-zskills update` keeps these updated alongside
the core skills.