---
name: add-example
description: >-
  Create an example model for one or more block types. Handles model file construction,
  registration, unit tests, codegen tests, screenshots, and verification.
  Usage: /add-example <block-type(s)> [concept hint]
argument-hint: "<block-type(s)> [concept hint]"
metadata:
  version: "2026.05.02+af97fa"
---

# Add Example Model

Create a complete example model that showcases one or more block types in a
real-world context. This skill covers the full workflow from research through
verification, distilled from real mistakes.

**Arguments:**
- `<block-type>` — which block(s) the example must feature (comma-separated for batch)
- `[concept hint]` — optional real-world model concept (e.g., "PID temperature control")

---

## Fulfillment Tracking

On entry, resolve `PIPELINE_ID` and `NAME_SLUG`, then create the
fulfillment marker so the parent skill (e.g., `/add-block`) knows this
delegation was accepted. `add-example` may run as a sub-skill (delegated
from `/add-block`) OR standalone (`/add-example` is registered as a
top-level slash command — see frontmatter and `block-diagram/README.md`).
Resolution is therefore 3-tier with a synthesized fallback so direct
invocation works. In delegated mode, tier-2 `.zskills-tracked` always
fires (the parent's worktree wrote it), so the synthesized fallback never
triggers and markers correctly land in the parent's subdir.

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# 3-tier PIPELINE_ID resolution: env → worktree .zskills-tracked
# (parent's PIPELINE_ID, written by add-block's create-worktree.sh
# --pipeline-id call) → synthesized fallback for standalone use.
# In delegated mode tier 2 always fires; tier 3 fires only when
# /add-example is invoked directly with no parent worktree.
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-}"
if [ -z "$PIPELINE_ID" ] && [ -f ".zskills-tracked" ]; then
  PIPELINE_ID=$(tr -d '[:space:]' < ".zskills-tracked")
fi
: "${PIPELINE_ID:=add-example.${NAME}}"
PIPELINE_ID=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
# Sanitised per-marker suffix slug — pairs with add-block's BLOCK_SLUG
# when invoked under delegation (orchestrator passes NAME == BLOCK_NAME).
NAME_SLUG=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "$NAME")
mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
printf 'skill: add-example\nname: %s\nstatus: started\ndate: %s\n' \
  "$NAME" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.add-example.${NAME_SLUG}"
```

Where `$NAME` is derived from the block type(s) or model name (e.g.,
`Gain`, `math-batch`).

`/add-example` runs as a sub-skill inside its parent's worktree (Claude
Code subagents cannot dispatch their own subagents). Do **not** write
`.zskills-tracked` here — the worktree's existing file (written by the
parent's `create-worktree.sh --pipeline-id` call) defines the active
pipeline ID, and overwriting it would corrupt the parent's tracking
scope.

## Before You Start

```bash
ls examples/
```

Check if an example already exists that features the target block(s). If so,
just add the example key to the block's `examples` array in
`block-explorer-data.js` and stop.

---

## Phase 1 — Research & Design

### 1a. Read block-registry.js for EXACT param names

```bash
# Find the block definition — get param keys, port counts, defaults
grep -A 30 "type: 'YourBlockType'" src/library/block-registry.js
```

**Use the exact `key` values from `param()` calls in your model file.**
Past failure: used `expression` instead of `expr` because param name was not
checked against block-registry.js. The model loaded but produced wrong output.

### 1b. Research a real-world model concept

Find a model from textbooks, reference examples, control theory papers, or
engineering tutorials that naturally uses the target block(s). Do NOT invent a
toy model from scratch — real-world models produce better examples.

### 1c. Choose the right solver

Match solver to model characteristics:
- **Fixed-step** (`ode4`, `ode1`): piecewise data, simple dynamics, FromWorkspace
- **Variable-step** (`ode45`): smooth nonlinear dynamics
- **Stiff solvers** (`ode15s`): stiff systems, high-gain feedback

Past failure: used `ode45` on piecewise FromWorkspace data — solver wasted steps
at discontinuities.

### 1d. Plan signal flow

- Left-to-right. Feedback loops below the forward path.
- Identify the primary signal path (longest run or path to Scope).
- Secondary sources go near their first downstream connection, NOT at x=100.

Past failure: carrier SineWave placed at x=100 instead of near the Product block
it feeds — created a long diagonal line across the diagram.

### 1e. Size blocks to fit their content

If a block shows parameter text (Fcn expression, Transfer Function coefficients),
size it wide enough to display the full text.

Past failure: 80px-wide Fcn block with a 35-character expression — text was
truncated and unreadable.

---

## Phase 2 — Build

### 2a. Create the model file

Create `examples/<name>/<name>.model` following `/model-design` rules:
- Snap all positions to 10px grid
- 80px minimum horizontal gap between blocks
- Orthogonal routing only
- Block names below blocks, no overlaps
- Every port connected (use Ground/Terminator for unused)

### 2b. Compute exact port positions

Use the formula — never eyeball:

```
portY = block.y + block.height * (portIndex + 1) / (portCount + 1)
```

Match source output portY to destination input portY exactly. Even 2px
misalignment creates visible kinks and doubled-stroke rendering artifacts at
branch points.

**Example:** A block at y=100, height=60, with 1 output port:
- portY = 100 + 60 * (0 + 1) / (1 + 1) = 130

The downstream block's input port must also be at y=130. If the downstream block
is at y=?, height=60, with 2 input ports and you need port index 0:
- 130 = y + 60 * 1 / 3 → y = 110

### 2c. Signal branching

- Primary path stays straight (horizontal); branch bends.
- Secondary sources go near their first downstream connection.
- Max 2 sub-lines at a single branch point; cascade for 3+.

### 2d. Create the README

Create `examples/<name>/README.md`:
- Model description and what it demonstrates
- Blocks table (type, purpose in this model)
- How to open and run
- Key concepts illustrated

### 2e. Create screenshots directory

```bash
mkdir -p examples/<name>/screenshots
```

### Post-build tracking

After Phase 2 (build) is complete:
```bash
printf 'name: %s\ncompleted: %s\n' "$NAME" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.add-example.${NAME_SLUG}.build"
```

---

## Phase 3 — Register

### 3a. Add to EXAMPLE_MODELS in block-explorer-data.js

```javascript
'model-key': {
  path: 'examples/model-name/model-name.model',
  name: 'Human-Readable Name',
  difficulty: 'Beginner',  // or 'Intermediate', 'Advanced'
  description: 'One sentence describing what the model demonstrates.',
},
```

### 3b. Add to the featured block's examples array

In `BLOCK_EXPLORER_DATA` in the same file, add `'model-key'` to the `examples`
array of every block type the example is designed to showcase.

### 3c. Add to codegen compile test

In `tests/codegen-compile.test.js`, add the model to the appropriate tier:
- **TIER1** — simple models, tight tolerances (tol: 1e-6, maxMismatch: 0.05)
- **TIER2** — moderate complexity (tol: 0.05, maxMismatch: 0.15)
- **TIER3** — models with relay/zero-crossing events

```javascript
{ name: 'model-name', tol: 1e-6, maxMismatch: 0.05 },
```

### Post-register tracking

After Phase 3 (register) is complete:
```bash
printf 'name: %s\ncompleted: %s\n' "$NAME" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.add-example.${NAME_SLUG}.register"
```

---

## Phase 4 — Verify

### 4a. Load and run in the browser

Start dev server if not running:
```bash
npm start &
```

Use `playwright-cli` to:
1. Open the model (File > Open or drag-and-drop)
2. Run the simulation (click Run button)
3. Verify Scope output shows expected behavior

### 4b. Take screenshot

```bash
playwright-cli screenshot
# Then rename to something descriptive:
mv .playwright/output/screenshot-*.png examples/<name>/screenshots/01-model-with-results.png
```

### Post-screenshot tracking

After Phase 4b (screenshot) is complete:
```bash
printf 'name: %s\ncompleted: %s\n' "$NAME" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.add-example.${NAME_SLUG}.screenshot"
```

### 4c. Write unit tests

Add tests in `tests/example-models.test.js`. Tests must verify **key output
values that prove the featured block works** — not just "runs without errors."

```javascript
it('model-name produces correct output', async () => {
  // Build model, compile, simulate
  // Assert specific output values at specific times
  // e.g., assert that Gain output = input * gainValue
});
```

Past failure: tests only checked `engine.status === 'completed'`, missed that a
wrong param name produced wrong output. The test passed but the model was broken.

### 4d. Run all test suites

```bash
npm run test:all
```

All 3 suites must pass (unit, e2e, codegen). Report each suite's result.

### Post-tests tracking

After Phase 4c/4d (tests pass):
```bash
printf 'name: %s\ncompleted: %s\n' "$NAME" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.add-example.${NAME_SLUG}.tests"
```

---

## Phase 5 — Final Check

### 5a. Dispatch verification agent

Send a verification agent (or do it yourself) to check:
- JSON validity of the model file (parse it with `JSON.parse`)
- Every param name in the model file matches the `key` in the block registry
- All port references (srcPort, dstPort) are correct indices
- EXAMPLE_MODELS registration is present
- Block's `examples` array references the model key
- Codegen compile test entry is present
- Unit test verifies output values, not just completion

### Post-verify tracking

After Phase 5a (verification) is complete:
```bash
printf 'name: %s\ncompleted: %s\n' "$NAME" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.add-example.${NAME_SLUG}.verify"
```

Update the fulfillment marker to reflect completion:
```bash
printf 'skill: add-example\nname: %s\nstatus: completed\ndate: %s\n' \
  "$NAME" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.add-example.${NAME_SLUG}"
```

### 5b. Retake screenshot if needed

If any layout adjustments were made during verification, retake the screenshot.
The screenshot must always reflect the final layout.

Past failure: screenshot showed the old layout before a branch-point fix. The
README referenced a screenshot that did not match the actual model.

---

## Key Rules Summary

1. **Always read the block registry** for exact param names before writing the model file
2. **Compute exact port positions** with the formula — never eyeball
3. **Match solver to model characteristics** — fixed-step for piecewise, variable-step for smooth
4. **Tests must verify output values** that prove the featured block works
5. **Screenshot is always the VERY LAST step** — after all layout adjustments
6. **Follow `/model-design`** for all layout rules
7. **Check `ls examples/` first** — an example may already exist
8. **Source proximity** — secondary sources near their downstream connection, not at x=100
9. **Size blocks to fit content** — truncated parameter text is unreadable
10. **Primary path straight, branch bends** — the most important signal path gets the straight line
