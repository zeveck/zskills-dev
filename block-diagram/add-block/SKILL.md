---
name: add-block
description: >-
  Step-by-step guide for adding new block types. Use when the user asks
  to "add a block", "create a new block", "implement a block", or mentions
  adding a block type to the library.
---

# Adding Block Types

Every new block must complete all steps (0–12). Steps 0–10 are the
implementation workflow. Steps 11–12 are verification and landing.

**All implementation happens in a worktree.** Dispatch the implementation
agent with `isolation: "worktree"`. Include the verbatim plan text and the
worktree test recipe in the agent prompt:

> **Worktree test recipe:**
> 1. Start a dev server FIRST: `npm start &`
> 2. Wait for it: `sleep 3`
> 3. Then run tests: `npm run test:all` — no piping (`| tail`, `| head`).
> 4. If tests fail, read the output, diagnose, fix, run again. Max 2
>    attempts at the same error.

---

## Batch Mode (multiple blocks)

When adding **multiple blocks at once**, change the step ordering:

1. **For each block:** Steps 0–4, 5, 6, 8 (plan, implement, register, UI, explorer, doc issues, tests, Rust)
2. **For each block:** Step 9 (manual-test individually with parameter variation)
3. **Once for the group:** Step 7 (research and build one real-world example model)
4. **Once for the model:** Step 9 again (manual-test the example model end-to-end)
5. **Once:** Steps 10–12 (report, verification, landing)

Do NOT do step 7 per-block when batching. Defer it until all blocks are implemented and tested.

---

## Step 0 — Pre-flight: Check for a Plan

Look in `plans/blocks/{category}/` for an existing plan file for this block.

- **If a plan exists:** read it and use it as the specification.
- **If no plan exists:** STOP implementation. Spawn an Explore agent to research the block thoroughly — reference documentation, textbooks, behavior, edge cases, parameter semantics — and write a plan file before proceeding.

### Plan file convention

- **Path:** `plans/blocks/{category}/{number}-{block-name}.md`
- **Numbering:** check the highest existing number across all categories and increment
- **9 required sections:**
  1. Overview (block number, category, purpose)
  2. Behavior (mathematical formulation, modes, signal handling)
  3. Ports (input/output tables with dimensions and types)
  4. Parameters (table: name, type, default, description)
  5. Simulation Characteristics (direct feedthrough, sample time, states, zero crossings)
  6. Algorithm (pseudocode for initialize, output, update, derivatives, terminate)
  7. Edge Cases & Error Handling (table of cases and handling)
  8. UI Representation (icon, port layout, label, display)
  9. Implementation Notes (data model JSON, key methods, test cases)

Reference: `plans/blocks/math/12-gain.md` or `plans/blocks/continuous/34-integrator.md` for format.

---

## Step 1 — Runtime Implementation

Create the block class file:

```
src/engine/blocks/{category}/{NameBlock}.js
```

### Template

```javascript
import { Block } from '../Block.js';

export class NameBlock extends Block {
  static blockType = 'Name';
  static sampleTime = [-1, 0];       // see cheatsheet below
  static directFeedthrough = [true];  // per input port
  static numContinuousStates = 0;
  static numDiscreteStates = 0;
  static numZeroCrossings = 0;
  static needsUpdate = false;        // set true if update() needed without discrete states
  static numOutputPorts = 1;
  // static numInputPorts = null;     // null = infer from directFeedthrough.length

  output(ctx, t) {
    const input = this.getInput(0);
    const param = this.params.paramName ?? defaultValue;
    this.setOutput(0, /* computed value */);
  }

  // Override as needed:
  // initialize(ctx) {}       — set initial conditions in ctx.xc / ctx.xd
  // derivatives(ctx, t) {}   — write to ctx.dxc[this.continuousStateOffset + i]
  // update(ctx, t) {}        — update ctx.xd[this.discreteStateOffset + i]
  // zeroCrossings(ctx, t) {} — write to ctx.zcSignals[this.zeroCrossingOffset + i]
  // onZeroCrossing(ctx, t, zcIndex) {} — handle detected crossing
  // terminate(ctx) {}        — cleanup
}
```

### Rules

- Always use `this.params.key ?? defaultValue` — never assume params is complete
- Use `this.getInput(portIndex)` — returns 0 for unconnected ports
- Use `this.setOutput(portIndex, value)` to write outputs
- For vector math, import helpers from `../vectorOps.js` (`vMap`, `vAdd`, etc.)
- For continuous states: read `ctx.xc[this.continuousStateOffset + i]`, write derivatives to `ctx.dxc[this.continuousStateOffset + i]`
- For discrete states: read/write `ctx.xd[this.discreteStateOffset + i]` in `update()` only
- If state count depends on params, override per-instance in constructor (see `StateSpaceBlock.js` for proxy pattern)

---

## Step 2 — Runtime Registration

Add the block class to the appropriate register file:

```
src/engine/blocks/register/{category}.js
```

**Pattern:**
```javascript
import { NameBlock } from '../{category}/NameBlock.js';
// ... (existing imports)

export function register{Category}Blocks() {
  // ... (existing registrations)
  RuntimeRegistry.register('Name', NameBlock);
}
```

### Category → register file mapping

| Category | File |
|----------|------|
| continuous | `register/continuous.js` |
| discrete | `register/discrete.js` |
| math | `register/math.js` |
| sources | `register/sources.js` |
| sinks | `register/sinks.js` |
| signal-flow | `register/signalFlow.js` |
| logic-discontinuities | `register/logic.js` |
| data-handling | `register/dataHandling.js` |
| lookup-tables | `register/lookupTables.js` |
| user-defined | `register/userDefined.js` |
| structural | `register/structural.js` |
| model-verification | `register/modelVerification.js` |

---

## Step 3 — UI Definition

Add a block definition in `src/library/BlockDefinitions.js` inside the appropriate category section.

### Face text (BlockRenderer.js)

If the block should display text on its face (like "≥", "≤", "If", "Switch",
"1/s"), add a case in `src/editor/BlockRenderer.js` → `_getBlockFaceText()`.
Check sibling blocks in the same category — if they have face text, yours
probably should too.

### Template

```javascript
BlockRegistry.registerBlock({
  type: 'Name',
  name: 'Name',
  category: 'category-key',
  description: 'One sentence describing what the block does',
  keywords: ['synonym1', 'synonym2'],
  inputs: [port('u', 'In')],
  outputs: [port('y', 'Out')],
  params: [
    param('paramName', 'Label', 'number', 1),
    // param('mode', 'Mode', 'enum', 'default', { options: ['default', 'alt'] }),
  ],
  defaults: { paramName: 1 },
  // defaultSize: { width: 80, height: 60 },  // only if non-standard
});
```

### Helper signatures

```javascript
port(name, label, type = 'signal')
param(key, label, type, defaultVal, extra = {})
```

### Parameter types

`'number'`, `'string'`, `'text'`, `'code'`, `'boolean'`, `'enum'`, `'array'`

### Extra options for params

- `{ min, max, step }` — for number
- `{ options: ['a', 'b'] }` — for enum

### Dynamic ports

If port count depends on parameters, add a case in `src/editor/dynamicPorts.js` → `computeDynamicPorts()`:

```javascript
case 'Name': {
  const n = p.numInputs ?? 2;
  const inputs = [];
  for (let i = 0; i < n; i++) inputs.push({ name: `in${i + 1}`, label: `In${i + 1}` });
  return { inputs, outputs: [{ name: 'out', label: 'Out' }] };
}
```

### Category keys

| Key | Order | Name |
|-----|-------|------|
| `common` | 0 | Commonly Used |
| `signal-flow` | 1 | Signal Routing |
| `math` | 2 | Math Operations |
| `sources` | 3 | Sources |
| `sinks` | 4 | Sinks |
| `continuous` | 5 | Continuous |
| `discrete` | 6 | Discrete |
| `logic-discontinuities` | 7 | Logic & Discontinuities |
| `data-handling` | 8 | Data Handling |
| `lookup-tables` | 9 | Lookup Tables |
| `state-machine` | 10 | State Machine |
| `structural` | 11 | Structural |
| `model-verification` | 12 | Model Verification |

---

## Step 4 — Block Explorer Data

Add an entry in `src/library/BlockExplorerData.js` under the appropriate category comment:

```javascript
Name: {
  blurb: '2-3 sentences: what this block does and when/why you would use it.',
  related: ['RelatedBlock1', 'RelatedBlock2'],
  examples: ['example-model-key'],
},
```

---

## Step 5 — Documentation Issues

Do NOT write the documentation yourself. Instead, create tracking issues for the docs work.

If `plans/DOC_ISSUES.md` does not exist, create it first using `plans/RUST_ISSUES.md` as a format reference (summary table at top, entries with GitHub issue cross-references). Use D-numbering: D1, D2, D3...

### For each new block

1. **Create a GitHub issue:**
   ```bash
   gh issue create --title "docs: add BlockName to block reference" \
     --body "Add BlockName to getting-started/blocks/{category}.md with description, parameter table, and usage notes." \
     --label "documentation"
   ```

2. **Add an entry to `plans/DOC_ISSUES.md`:**
   ```markdown
   ### D{next_number}: BlockName block reference

   | Field | Value |
   |-------|-------|
   | **GitHub** | #{issue_number} |
   | **File** | `getting-started/blocks/{category}.md` |
   | **Status** | OPEN |

   **Scope:** Add BlockName section — description, parameter table, usage notes, related blocks.
   ```

### For each new example model

1. **Create a GitHub issue:**
   ```bash
   gh issue create --title "docs: add {model-name} example walkthrough" \
     --body "Write a README walkthrough for examples/{model-name}/ explaining the model, what it demonstrates, and how to modify it." \
     --label "documentation"
   ```

2. **Add an entry to `plans/DOC_ISSUES.md`** following the same format.

### DOC_ISSUES.md convention

- **Path:** `plans/DOC_ISSUES.md`
- **Numbering:** D1, D2, D3... — check existing entries and increment

---

## Step 6 — Unit Tests

Add tests in `tests/blocks/{category}.test.js` (create the file if the category doesn't have one yet).

### Template

```javascript
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { makeCtx, wire } from './_helpers.js';
import { NameBlock } from '../../src/engine/blocks/{category}/NameBlock.js';

describe('NameBlock', () => {
  it('has correct static metadata', () => {
    assert.strictEqual(NameBlock.blockType, 'Name');
    assert.deepStrictEqual(NameBlock.sampleTime, [-1, 0]);
    assert.deepStrictEqual(NameBlock.directFeedthrough, [true]);
    assert.strictEqual(NameBlock.numContinuousStates, 0);
    assert.strictEqual(NameBlock.numDiscreteStates, 0);
  });

  it('computes output correctly', () => {
    const block = new NameBlock('b1', 'Name1', { paramName: 2 });
    const ctx = makeCtx();
    wire(block, ctx, ['input:0'], 1);
    ctx.signals.set('input:0', 5);
    block.output(ctx, 0);
    assert.strictEqual(ctx.signals.get('b1:0'), 10);
  });

  it('uses default param when not specified', () => {
    const block = new NameBlock('b2', 'Name2', {});
    const ctx = makeCtx();
    wire(block, ctx, ['input:0'], 1);
    ctx.signals.set('input:0', 5);
    block.output(ctx, 0);
    assert.strictEqual(ctx.signals.get('b2:0'), /* expected with default */);
  });

  // Add tests for: initialize, derivatives, update, edge cases, unconnected ports
});
```

### Run tests

```bash
npm run test:all
```

All existing tests must continue to pass (unit, E2E, and codegen suites).

---

## Step 7 — Example Model

Use the `/add-example` skill to create an example model for this block
(or the batch of blocks). Pass all block types from this batch:

```
/add-example <block-type(s)> [concept hint]
```

In batch mode, invoke `/add-example` once after all blocks are implemented,
passing all block types as a comma-separated list. One model that showcases
all the blocks together is better than N separate trivial models.

The `/add-example` skill handles: model file construction with exact port
alignment, registration in BlockExplorerData.js, codegen compile tests,
unit tests with value assertions, browser verification, and screenshots.

---

## Step 8 — Rust Code Generation

Add a Rust emitter for the block in `src/codegen/BlockEmitter.js`.

### Steps

1. Add a case in the `emit()` dispatch:
   ```javascript
   case 'Name': return this._emitName(block, analysis);
   ```

2. Implement the emitter method:
   ```javascript
   static _emitName(block, analysis) {
     const out = analysis.getOutputVar(block);
     const input = analysis.getInputSignal(block, 0);
     const param = analysis.getParamField(block, 'paramName');
     return {
       ...empty(),
       output: withComment(block.path, 'Name',
         `let ${out} = ${param} * ${input};\n`),
     };
   }
   ```

3. Add parameter defaults in `BLOCK_PARAM_DEFAULTS` (same file) if the block has params:
   ```javascript
   Name: { paramName: defaultValue },
   ```

4. Add any codegen-only params to `CODEGEN_ONLY_PARAMS` if they shouldn't appear in the Rust `Params` struct.

### Analysis helpers

| Helper | Returns |
|--------|---------|
| `analysis.getInputSignal(block, portIndex)` | Rust expression for input value |
| `analysis.getOutputVar(block)` | Signal variable name for output |
| `analysis.getParamField(block, key)` | `self.params.field_name` expression |
| `analysis.getDWorkField(block, suffix)` | Discrete state field reference |
| `analysis.getContinuousStateField(block, suffix)` | Continuous state field reference |
| `analysis.getSignalField(block, name)` | Cached signal field reference |

### Runtime support

The codegen path (source generation) and the runtime path (pre-built binary)
are **separate implementations**. Adding a codegen emitter here does NOT make
the block work in deployed binaries. The runtime has its own block dispatch
in `runtime/src/blocks/mod.rs` with implementations across category files
(`math.rs`, `continuous.rs`, etc.).

Add the block to the runtime if feasible:
1. Add a case in `runtime/src/blocks/mod.rs` `compute_output()` dispatch
2. Implement the block logic in the appropriate category file
3. Run `cargo test` in `runtime/` to verify

If runtime support cannot be added now, file a `RUST_ISSUES.md` entry (same
format as the codegen deferral below) noting it's a **runtime gap**, not a
codegen gap.

### Verify

Test the emitter by running `npm run test:all` — codegen tests exercise
all registered emitters. The example model's codegen compile test is
handled by `/add-example` (Step 7), not here.

### If Rust codegen cannot be implemented now

Create a GitHub issue and add an entry to `plans/RUST_ISSUES.md` following the existing format. Check the file first to find the highest R-number and increment it.

```markdown
### R{next_number}: {Title}

| Field | Value |
|-------|-------|
| **GitHub** | #{issue_number} |
| **File** | `src/codegen/BlockEmitter.js` |
| **Severity** | Medium |
| **Status** | OPEN |

**Description:** {Why this block can't be emitted yet and what's needed.}
```

---

## Step 9 — Manual Testing

Use the `/manual-testing` skill with `playwright-cli` to verify the block works end-to-end in the browser. **When adding multiple blocks**, do this for each block individually, then again for the example model after Step 7 (see Batch Mode above).

### Required test sequence

1. **Add the block** to a diagram — use Quick Insert (double-click the canvas, type the block name, press Enter) or drag from Block Explorer
2. **Connect it** — wire source blocks to its inputs and sinks (Scope/Display) to its outputs
3. **Run a simulation** — click the Run button, verify output is correct
4. **Vary each parameter one at a time** — double-click the block to open the parameter dialog, change one parameter, apply, re-run, and verify the change has the intended effect on simulation results. Repeat for every parameter.
5. **Test edge cases** — unconnected ports, extreme parameter values (0, negative, very large), vector inputs if applicable

### What to verify

- Block appears correctly in the Block Explorer and Quick Insert search
- Block renders with correct ports and parameter display on the canvas
- Simulation produces expected output values
- Each parameter independently affects behavior as documented in the plan
- No console errors during any of the above

---

## Step 10 — Completion Report

Write `reports/new-blocks-{slug}.md` where `{slug}` is derived from the
block name(s) (e.g., `new-blocks-resistor`, `new-blocks-math-batch`).
APPEND if the file exists — never overwrite.

The report is for the user reviewing the new blocks, not for developers.
Same pattern as `/run-plan` reports: features to verify first, details
collapsed.

**Image paths must be absolute:** `/.playwright/output/` not `.playwright/output/`.

```markdown
# New Blocks — {Block Name(s)}

{1-2 sentence summary. Test count.}

---

## Blocks to Verify

### {BlockName}
- [ ] **Sign off**

1. Add via Quick Insert, connect to a Scope
2. Run simulation — verify output is correct
3. Change each parameter — verify effect

![screenshot](/.playwright/output/{slug}-{block}.png)

---

## What Was Added
| Block | Category | Params | Codegen |
|-------|----------|--------|---------|

## Test Results
Command: `npm run test:all`
Suites: unit N pass, E2E N pass, codegen N pass
```

After writing, regenerate `NEW_BLOCKS_REPORT.md` in the repo root as an
index of all new-blocks reports (same pattern as PLAN_REPORT.md).

---

## Step 10b — Self-Audit (MANDATORY — do NOT proceed without this)

Before reporting completion or dispatching verification, run these checks
for EACH block added. Fix any failures — do not "note" them as gaps.

```bash
# 1. Block registered?
grep "type: 'BlockType'" src/library/BlockDefinitions.js

# 2. Engine registered? (quotes prevent matching SubstringBlockType)
grep "'BlockType'" src/engine/blocks/register/*.js

# 3. Explorer entry? (anchor to line start to avoid substring matches)
grep "^  BlockType:" src/library/BlockExplorerData.js

# 4. Face text? (conditional — check if sibling blocks have it)
grep -A5 "case 'BlockType'" src/editor/BlockRenderer.js

# 5. Unit tests exist? (quotes prevent substring matches)
grep -r "'BlockType'" tests/blocks/

# 6. Codegen emitter?
grep "'BlockType'" src/codegen/BlockEmitter.js

# 7. Example model features this block? (model files use JSON double quotes)
grep -rl '"BlockType"' examples/ || echo "NO EXAMPLE FOUND"

# 8. Runtime support OR tracking issue? (Rust uses double quotes)
grep '"BlockType"' runtime/src/blocks/mod.rs || \
grep "BlockType" plans/RUST_ISSUES.md

# 9. Tests pass?
npm run test:all
```

If ANY check returns nothing (except #4 which is conditional and #8 which
has an OR), go back and complete the missing step. Past failure: Block
Expansion Phase 1 skipped Steps 7, 9, and 12 — verifier accepted "gaps
noted" instead of failing. These checks prevent that.

---

## Step 11 — Verification (separate agent)

Dispatch a **fresh verification agent** targeting the worktree. The agent
that implemented the blocks must NOT verify them.

Give the verification agent:
- The **worktree path** and **branch name**
- The **plan file(s)** for each block (verbatim)
- Instruction to run `/verify-changes worktree`
- The **block names** to check against registration, UI, tests, codegen

The verifier checks:
- Every block is registered, has UI definition, has tests, has codegen
- Tests cover output computation, default params, edge cases
- Example model runs and produces correct results
- Manual testing screenshots exist and look correct
- No stubs, TODOs, or placeholder implementations

**Agent timeout: 45 minutes.** If exceeded, declare failed.

If verification fails: dispatch a fix agent (max 2 fix+verify rounds).

---

## Step 12 — Land

Cherry-pick worktree commits to main. Same process as `/run-plan` Phase 6:

1. Check `reports/new-blocks-{slug}.md` exists with sign-off items
2. If UI sign-off items have `[ ]` checkboxes: **do NOT auto-land.** Report
   to the user for review.
3. If no sign-off items or all signed off: cherry-pick to main, run
   `npm run test:all`, update report as landed.

---

## Quick Reference

### Sample time cheatsheet

| Value | Meaning |
|-------|---------|
| `[0, 0]` | Continuous — integrated by ODE solver |
| `[-1, 0]` | Inherited — takes rate from driving block |
| `[Ts, 0]` | Discrete — updates every Ts seconds |
| `[Inf, 0]` | Constant — output never changes |

### Direct feedthrough rules

- `[true]` — output depends on current input (combinatorial: Gain, Sum, Product)
- `[false]` — output depends only on state (stateful: Integrator, UnitDelay)
- Array length must match input port count

### File checklist

| Step | Files |
|------|-------|
| 0 | `plans/blocks/{category}/{num}-{name}.md` |
| 1 | `src/engine/blocks/{category}/{Name}Block.js` |
| 2 | `src/engine/blocks/register/{category}.js` |
| 3 | `src/library/BlockDefinitions.js`, optionally `src/editor/dynamicPorts.js` |
| 4 | `src/library/BlockExplorerData.js` |
| 5 | GitHub issues + `plans/DOC_ISSUES.md` |
| 6 | `tests/blocks/{category}.test.js` |
| 7 | `examples/{model}/`, `src/library/BlockExplorerData.js` (EXAMPLE_MODELS) |
| 8 | `src/codegen/BlockEmitter.js`, optionally GitHub issue + `plans/RUST_ISSUES.md` |
| 9 | (manual testing — no files) |
| 10 | `reports/new-blocks-{slug}.md`, `NEW_BLOCKS_REPORT.md` |
| 11 | (verification — no files) |
| 12 | (landing — cherry-pick to main) |
