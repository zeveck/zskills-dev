# Block Diagram Domain Skills

These 5 skills are for block-diagram editors and visual modeling
projects. They demonstrate how to extend Z Skills with domain-specific
workflows.

## Skills

| Skill | Lines | Purpose |
|-------|------:|---------|
| `/add-block` | 633 | Full lifecycle for adding block types: plan, implement, register, UI, explorer, docs, tests, example, codegen, runtime, manual testing, verification, landing |
| `/add-example` | 247 | Example model creation: research concept, design layout, build model file, register, test, screenshot, verify |
| `/manual-testing` | 345 | Playwright-cli recipes with exact CSS selectors and event sequences for block-diagram UI |
| `/model-design` | 250 | Layout guidelines for block diagrams and state charts based on MAAB/NASA standards |
| `/review-feedback` | 98 | Triage exported user feedback JSON, deduplicate against existing issues, file via GitHub CLI |

## Using These Skills

**If your project is a block-diagram editor:** install these alongside the
core Z Skills. They work out of the box.

**If your project is something else:** use these as templates. The patterns
generalize:

| This skill | Generalizes to |
|------------|---------------|
| `/add-block` | Any project with a plugin/component registry (VS Code extensions, Figma plugins, game entities) |
| `/add-example` | Any project with example templates (starter projects, demo configurations) |
| `/manual-testing` | Any project needing browser automation recipes (write your own selectors) |
| `/model-design` | Any project with visual layout rules (diagram tools, form builders, dashboards) |
| `/review-feedback` | Any project with user feedback intake (support tickets, bug reports) |

## Installation

Copy the skills you want to `.claude/skills/` in your project:

```bash
cp -r block-diagram/add-block .claude/skills/add-block
```

Or install all of them:

```bash
for skill in add-block add-example manual-testing model-design review-feedback; do
  cp -r block-diagram/$skill .claude/skills/$skill
done
```
