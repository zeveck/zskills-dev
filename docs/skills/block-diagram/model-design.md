# /model-design

> Design guidelines for creating well-laid-out block diagrams and state charts. Use when building or reviewing model files.

## Usage

```
/model-design
```

This skill is a reference guide -- consult it when creating or editing model files, placing blocks programmatically, or building state charts. It takes no arguments.

## What it does

Provides layout rules distilled from 80+ sources (MAAB v5/v6, NASA Orion, Michael Burke / MathWorks, UML/Agile Modeling, ELK, yFiles, and graph drawing literature) for producing readable, standards-conformant models. Coverage includes:

- **Block diagram layout** -- flow direction (signals left-to-right, feedback loops below the forward path), block positioning (10px grid snap, 80px minimum horizontal spacing, 40px vertical spacing, column alignment of equivalent parallel blocks), block sizing and parameter display, block names below blocks, and right-facing block orientation.
- **Signal lines** -- orthogonal (90-degree) routing only, no diagonal lines, 20px minimum clearance from unrelated blocks, 10px minimum between parallel lines, bend minimization (prefer zero-bend straight connections), and a maximum of 2 sub-lines per branch point.
- **Signal branching and labeling** -- primary path straight / branch bends, exact port-position computation (`portY = block.y + block.height * (portIndex + 1) / (portCount + 1)`), and where signal labels go (below the line, at the source end).
- **Subsystems and complexity** -- Inport-left / Outport-right ordering, no duplicate Inports, and Michael Burke complexity limits (~40 blocks per level, max 3 hierarchy levels).
- **State chart layout** -- state positioning and sizing, arrangement patterns (left-to-right flow, hub-and-spoke, grid), junction placement, default and bidirectional transitions, transition-label direction rules, and hierarchy/nesting limits.
- **Coordinate cheat sheets** for a typical 3-block model and for the Smart Thermostat state-chart pattern.
- A **verification checklist** to run before finalizing any model.

Most rules cite the specific MAAB/standard reference they derive from (e.g., signals flow left-to-right per MAAB db_0141; orthogonal routing per db_0032).

## Common Patterns

- **While building a model:** apply the block-diagram layout and signal-line rules as you place blocks and route connections programmatically.
- **While building a state chart:** apply the state-positioning, junction, and transition-label rules.
- **Before finalizing:** run through the verification checklist to catch overlaps, dangling ports, diagonal lines, and misaligned parallel blocks.

## Tips & Gotchas

- All positions snap to a **10px grid** -- block and state x/y should be multiples of 10.
- "Close enough" port alignment is not good enough -- even a 2px vertical misalignment creates a visible kink and can cause doubled-stroke artifacts at branch points. Use the port-position formula.
- Diagonal signal lines are prohibited; routing is orthogonal only, with line hops where crossings are unavoidable.
- The only blocks that may face left are Delay / Unit Delay blocks inside a feedback loop.
- The Sources section of the SKILL.md links the underlying MAAB, ELK, yFiles, and Michael Burke references for deeper reading.
