# /doc

> Audit and fix documentation gaps: block library entries, example models, getting-started guides, presentations, README updates. Also handles newsletter entries.

## Usage

```
/doc [blocks|examples|newsletter|<description>]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| (no args) | -- | Scan recent changes for missing docs and fix gaps |
| `blocks` | No | Comprehensive audit of all blocks for doc completeness |
| `examples` | No | Comprehensive audit of all examples for doc completeness |
| `newsletter` | No | Write a NEWSLETTER.md entry for recent work |
| `description` | No | Document a specific thing |

## Examples

```
/doc
/doc blocks
/doc examples
/doc newsletter
/doc the new thermal blocks
/doc update the presentation with recent results
/doc update README with current block count and test numbers
```

## Common Patterns

- **Post-feature audit:** `/doc` -- what documentation is missing since the last commit?
- **Block audit:** `/doc blocks` -- which blocks lack explorer entries, examples, or docs?
- **Example audit:** `/doc examples` -- which examples lack READMEs or screenshots?
- **Newsletter:** `/doc newsletter` -- write a newsletter entry for recent features
- **Targeted docs:** `/doc the new physics blocks` -- document a specific feature area

## Tips & Gotchas

- The no-argument mode scans `git log` for recent changes that lack documentation
- Block audit checks all registered blocks against a documentation checklist
- Example audit checks all example models against a documentation checklist
- Free-form descriptions can target any documentation task (presentations, READMEs, guides)
