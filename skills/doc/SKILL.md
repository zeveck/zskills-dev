---
name: doc
disable-model-invocation: true
argument-hint: "[blocks|examples|newsletter|<description>]"
description: >-
  Audit and fix documentation gaps: block library panel entries, example models,
  getting-started guides, block library, presentations, README updates.
  Also handles newsletter entries (/doc newsletter). Use when the user asks
  to "write a newsletter entry", "add to the newsletter", or "update the newsletter".
  Usage: /doc [blocks|examples|newsletter|<description>]
---

# /doc [blocks|examples|\<description>] — Documentation Audit & Fix

Finds documentation gaps and fills them. Can audit all blocks, all examples,
or document a specific feature. Knows the project's documentation structure
and checklists for each type of documentation.

**Ultrathink throughout.**

## Arguments

```
/doc                      — audit recent changes for missing docs
/doc blocks               — audit ALL blocks for doc completeness
/doc examples             — audit ALL examples for doc completeness
/doc newsletter           — write a NEWSLETTER.md entry for recent work
/doc <description>        — document a specific thing
```

- No arguments: scan `git log` for recent blocks, features, and examples
  that lack documentation. Fix the gaps.
- `blocks`: comprehensive audit of all 121+ registered blocks against the
  block documentation checklist.
- `examples`: comprehensive audit of all 48+ example models against the
  example documentation checklist.
- `newsletter`: write a NEWSLETTER.md entry for recent work.
- Free-form description: document the specific thing described (e.g.,
  "the new physics blocks", "update the presentation", "update README
  with Phase 4 progress").

Examples:
- `/doc` — what's missing since last commit?
- `/doc blocks` — which blocks lack explorer entries, examples, or docs?
- `/doc examples` — which examples lack READMEs or screenshots?
- `/doc newsletter` — write a newsletter entry for recent features
- `/doc the new thermal blocks`
- `/doc update the presentation with recent results`
- `/doc update README with current block count and test numbers`

## Documentation Structure (where things live)

### Block documentation
| What | Where | Format |
|------|-------|--------|
| Block registration | Registry file | `BlockRegistry.registerBlock({...})` |
| Explorer metadata | Component explorer file | `BLOCK_EXPLORER_DATA[type] = {blurb, related, examples}` |
| Example model registry | Component explorer file | `EXAMPLE_MODELS[key] = {path, name, difficulty, description}` |
| Block reference | `getting-started/BLOCK_LIBRARY.md` | Markdown — all blocks with params and usage |
| Block specs | `plans/blocks/<category>/` | Markdown — 14 category directories |
| Docs app catalog | UI docs registry | Central registry for the docs app |

### Example documentation
| What | Where | Format |
|------|-------|--------|
| Example model | `examples/<name>/<name>.model` | Model file |
| Example README | `examples/<name>/README.md` | Markdown walkthrough |
| Screenshots | `examples/<name>/screenshots/` | Numbered PNGs: `01-model-overview.png`, `02-simulation-results.png` |
| Gallery index | `examples/README.md` | Markdown — all examples with images and descriptions |
| App dropdown | UI examples dropdown | Categorized dropdown by module |

### High-level documentation
| What | Where | Format |
|------|-------|--------|
| Project README | `README.md` | Block count, test count, feature summary, status |
| Getting-started guides | `getting-started/` | 22 markdown files — tutorials and references |
| Newsletter | `getting-started/NEWSLETTER.md` | Chronological feature announcements |
| Presentations | `presentations/` | Markdown + HTML (4 presentations) |
| Docs app | `docs/` | JS app reading from docs-registry.js |
| Viewer | `viewer/` | Standalone markdown viewer |
| Plans | `plans/` | 37 plan and issue tracking files |

## Block Documentation Checklist

When auditing or documenting blocks, check each against this list:

- [ ] **Registered** in registry file — type, name, category,
  description, keywords, ports, params, defaults, defaultSize
- [ ] **Explorer entry** in component explorer — blurb (when/why to
  use), related blocks, example model links
- [ ] **Example model** demonstrating the block — model file in
  `examples/<name>/`, registered in `EXAMPLE_MODELS`
- [ ] **Example README** — walkthrough explaining what the model does, key
  blocks used, expected behavior, screenshots
- [ ] **Example screenshots** — numbered PNGs in `screenshots/` folder
  (`01-model-overview.png`, `02-simulation-results.png`)
- [ ] **Block reference entry** in `getting-started/BLOCK_LIBRARY.md` —
  description, parameters table, usage notes
- [ ] **Gallery entry** in `examples/README.md` — description, image,
  blocks used, solver info, download link
- [ ] **Doc issue tracked** — entry in doc issues tracker (open or closed)

## Example Documentation Checklist

When auditing or documenting examples, check each against this list:

- [ ] **Model file** exists and loads correctly
- [ ] **README.md** exists with:
  - What this demonstrates (1-2 paragraphs)
  - Blocks used (list with brief descriptions)
  - Expected behavior / simulation results
  - Loading instructions
  - Key concepts (if tutorial-style)
- [ ] **Screenshots** in `screenshots/` folder:
  - `01-model-overview.png` (the block diagram)
  - `02-simulation-results.png` (scope output)
  - Additional screenshots for complex models
- [ ] **Gallery entry** in `examples/README.md`
- [ ] **Explorer links** — block entries in component explorer link to
  this example where relevant
- [ ] **Category assignment** in `examples-dropdown.js` — categorized by
  module

### README styles (match existing conventions)

- **Tutorial style** (motor-controller): step-by-step with substeps,
  screenshots at each step, parameter tables, key concepts summary
- **Model-focused style** (feedback-loop): model overview, block list,
  expected behavior, files table
- **Chart design style** (state-machine-demo): states table, transitions table,
  data section, simulation trace
- **Visual style** (signal-filter): minimal text, physics equations,
  screenshot-driven

Match the style to the example's complexity and purpose.

## Workflow

### Phase 1 — Audit

Based on the argument:

**No argument (recent changes):**
1. Check recent commits: `git log --oneline -20`
2. Identify new blocks (search for `registerBlock` in recent diffs)
3. Identify new examples (new directories in `examples/`)
4. Identify new features (new getting-started guides, plan completions)
5. Cross-reference against checklists above

**`blocks`:**

Don't try to eyeball 121+ blocks across 2,700 lines — extract lists
mechanically first, then diff:

1. **Extract block type lists** from each source:
   ```bash
   grep "type:" src/library/registry.js | sed "s/.*type: '//;s/'.*//"
   ```
   ```bash
   grep -oP '^\s+\w+:' src/library/explorer-data.js | sed 's/[: ]//g'
   ```
   ```bash
   grep '###' getting-started/BLOCK_LIBRARY.md
   ```
2. **Diff the lists** — which blocks are in the registry but missing
   from the component explorer or BLOCK_LIBRARY?
3. **Only read full entries** for blocks in the gap set — don't read all
   121 entries, just the ones that need attention
4. Present a gap table:
   | Block | Explorer | BLOCK_LIBRARY | Example | Screenshots |
   |-------|----------|---------------|---------|-------------|

**`examples`:**

Extract the list mechanically, then check each:

1. **List all example directories and their contents:**
   ```bash
   for d in examples/*/; do
     echo "$(basename $d): $(ls $d | tr '\n' ' ')"
   done
   ```
2. **Check gallery coverage:**
   ```bash
   grep '##' examples/README.md | sed 's/## //'
   ```
3. **Diff** — which directories lack README.md, screenshots/, or gallery
   entries?
4. **Only inspect gaps** in detail — don't read all 48 READMEs
5. Present a gap table:
   | Example | Model | README | Screenshots | Gallery |
   |---------|------|--------|-------------|---------|

**`newsletter`:**

Write a new entry for `getting-started/NEWSLETTER.md`. Newest entries go
at the top, right after the intro paragraph and `---` separator.

1. **Check recent work** — read `git log --oneline -20` and identify what
   was built since the last newsletter entry
2. **Write the entry** following this structure:
   ```markdown
   ---

   ## Mon DD — Short Descriptive Title
   ```
   - **Opening sentence:** lead with what the user gets, not what was
     implemented. **Bold the key capability.** Good: "You can now **share
     a model by sending a link**." Bad: "Added a ShareManager module."
   - **Body:** pick the format that fits:
     - *User-facing feature:* opening paragraph → how to start (numbered
       steps) → how it works (bullets) → optional architecture note
     - *Block additions:* "Expanded from X to **Y blocks**" → bullet list
       of new blocks → new examples → updated counts
     - *QE/bugfix batch:* scope summary → notable fixes → deferred count
     - *Multi-feature drop:* bold sub-headers → bullet lists under each
   - **Screenshot:** one image per entry showing the feature in its
     finished state. Save to `getting-started/screenshots/newsletter/`
     with kebab-case filename.
3. **Formatting conventions:**
   - **Bold** for feature names, UI elements, shortcuts, block names
   - `Backtick` for values, expressions, file names, parameters, code
   - Parenthetical categories: (Sources), (Logic), (Discrete)
   - Issue references: (#34, #105) when relevant
   - No emojis, no marketing language, no exclamation marks
   - Concrete numbers: old→new block counts, test counts, line counts
4. **Update Project Stats** section at the bottom of the newsletter if
   counts changed (source lines, test count, block count)
5. **Architecture notes** (include sparingly, at the end):
   - Standalone: `**Module:** \`src/codegen/\` — 11 files, ~4,900 lines.`
   - Inline: `**Architecture:** Single new module \`MobileController.js\` (619 lines).`
   Pick the interesting bits — don't list every file changed.
6. **What to avoid:**
   - Don't describe the implementation journey ("first we tried X, then Y")
   - Don't pad with filler ("This is a great improvement that users will love")
   - Don't list every file changed
   - Don't use exclamation marks or marketing tone
7. **Tone:** technical and factual, written for developers. Read like
   well-written release notes, not a blog post.

**Free-form description:**
1. Understand what needs documenting
2. Identify which checklists apply
3. Check current state of relevant docs

### Phase 2 — Create Missing Documentation

For each gap found:

1. **Missing explorer entry** — read the block's implementation and
   registration, write a blurb, identify related blocks and examples.
   Add to the component explorer file.

2. **Missing example model** — create a model file following
   `/model-design` guidelines. Place in `examples/<name>/`. Register
   in `EXAMPLE_MODELS`.

3. **Missing example README** — write using the appropriate style
   (see README styles above). Include blocks used, expected behavior,
   screenshots.

4. **Missing screenshots** — use playwright-cli to:
   - Load the example model
   - Take screenshot of the block diagram (`01-model-overview.png`)
   - Run the simulation
   - Take screenshot of scope output (`02-simulation-results.png`)

5. **Missing BLOCK_LIBRARY entry** — add to the appropriate category
   section with description, parameter table, usage notes.

6. **Missing gallery entry** — add to `examples/README.md` with
   description, image reference, blocks used.

7. **README/presentation updates** — update block counts, test counts,
   feature lists, status sections as needed.

### Phase 3 — Verify

- Check all markdown formatting (links, images, tables)
- Verify image references point to existing files
- Verify model files load without errors (if dev server is up)
- `npm run test:all` if any code files were touched (component explorer,
  registry file, docs-registry.js, examples-dropdown.js)

### Phase 4 — Report

Summarize what was documented:
```
Documentation audit complete.

Created:
  - Explorer entries: 3 (Mass, Spring, Damper)
  - Example models: 1 (free-vibration/)
  - Example READMEs: 1
  - Screenshots: 4
  - BLOCK_LIBRARY entries: 3
  - Gallery entries: 1

Remaining gaps:
  - [list any unfixed gaps with reasons]
```

## Key Rules

- **Follow existing conventions** — match the style, format, and structure
  of existing documentation. Don't invent new formats.
- **Use `/model-design` guidelines** for model files — LTR signal flow,
  10px grid snap, orthogonal routing, no overlapping.
- **Screenshots via playwright-cli** — real browser screenshots, not
  generated images. Use `/manual-testing` setup for auth bypass.
- **Update all cross-references** — a new example needs entries in
  component explorer, `examples/README.md`, and relevant block
  explorer entries. Don't create orphaned docs.
- **`npm run test:all` before committing** if code files were touched.
- **Content-only changes skip tests** — if only markdown/images were
  changed, no test run needed.
