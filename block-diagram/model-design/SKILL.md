---
name: model-design
description: Design guidelines for creating well-laid-out block diagrams and state charts. Use when building or reviewing model files.
metadata:
  version: "2026.05.02+e45b5a"
---

# Model Design Guidelines

Follow these rules when creating or editing model files, placing blocks programmatically, or building state charts. Based on 80+ sources including MAAB v5/v6, NASA Orion, Michael Burke (MathWorks), UML/Agile Modeling, ELK, yFiles, and graph drawing literature.

---

## Block Diagram Layout

### Flow Direction
- **Signals flow left to right.** Inputs on the left, outputs on the right. (MAAB db_0141)
- **Parallel paths stack top to bottom.** (MAAB db_0141b)
- **Feedback loops** route right-to-left, **below** the forward path. (Convention)

### Block Positioning
- **Snap to 10px grid.** All block positions should be multiples of 10.
- **Minimum horizontal spacing between blocks:** 80px (between output port of one block and input port of the next). This leaves room for signal lines and labels.
- **Minimum vertical spacing between parallel blocks:** 40px edge-to-edge.
- **Align blocks vertically** when they share signal flow lanes. Blocks at the same pipeline stage should have the same x-coordinate.
- **Align equivalent blocks across parallel paths.** When two or more parallel paths contain blocks of the same type at the same pipeline stage (e.g., both paths have a Gain after a Demux), align them to the same x-coordinate (within 10px). This creates visual columns that make the parallel structure obvious. (ELK layered layer assignment, Sugiyama method)

### Block Sizing
- **Default block sizes** (from block-registry.js):
  - Standard blocks (Gain, Sum, etc.): 80x60
  - Scope: 60x60
  - Chart (state machine): 140x100
- **Size blocks to show their content.** Icons and parameter text must be readable. If parameter text is truncated, enlarge the block. (MAAB jm_0002)
- **Show key parameters on the block.** Gain values, constant values, transfer function coefficients, and other defining parameters should be visible on the block icon. (MAAB db_0140)
- **Use consistent sizes** for blocks of the same type in a model.

### Block Names
- **Block names go below the block.** (MAAB db_0142)
- Names must not overlap other blocks, lines, or labels. (MAAB jc_0903)

### Block Orientation
- **Outputs to the right.** All blocks shall have their output ports on the right side. (MAAB jc_0110)
- **Exception -- feedback delays:** A Delay or Unit Delay block in a feedback loop may be flipped so its output faces left, matching the right-to-left feedback flow. (MAAB jc_0110 exception)
- **No other flipping or rotation.** Inconsistent orientation breaks the left-to-right reading convention.

### Signal Lines
- **Orthogonal routing only** -- horizontal and vertical segments, 90-degree bends. Diagonal (slanting) lines are prohibited. (MAAB db_0032, db_0032b)
- **Zero crossings** as the target. Lines must not cross over blocks. If crossings are unavoidable, use line hops (small arcs) to distinguish a crossing from a connection. (MAAB db_0032c, jc_0903b2)
- **Lines must not overlap** other lines, blocks, or labels. (MAAB jc_0903b)
- **20px minimum clearance from unrelated blocks.** A line that routes adjacent to or behind a block it is not connected to creates a false visual connection -- proximity implies relationship. Re-route with waypoints, increase block spacing, or use Goto/From blocks. 20px = 2 grid units, the smallest readable gap given a 10px grid snap. (ELK `spacing.edgeNode` default: 10 from edge center, yFiles `minimumNodeToEdgeDistance` default: 10, LabVIEW "do not wire under objects", Gestalt proximity principle)
- **10px minimum between parallel signal lines.** Parallel lines running closer than 10px (1 grid unit) become visually indistinguishable. (ELK `spacing.edgeEdge` default: 10, yFiles `minimumEdgeDistance`)
- **Minimize bends.** Every bend must be justified by an obstacle or routing constraint. Prefer 0 bends (straight line) when ports are aligned; accept 1--2 bends for typical routing; investigate re-layout if a line requires 3+ bends. (MAAB db_0032c)
- **Prefer zero-bend connections.** Position connected blocks so that the source output port and destination input port are at the same Y coordinate, producing a straight horizontal line. (auto-routing best practice: shortest path, fewest turns)
- **Maximum 2 sub-lines at a single branch point.** For 3+ destinations, use cascaded branch points (each splitting into 2). Branch near the source block. (MAAB db_0032d)

### Signal Branching
- **Primary path straight, branch bends.** When a signal fans out to multiple destinations, position the source block so the most important connection is a straight horizontal line. Let the secondary branch be the one that introduces a bend. The "primary" path is typically the longest run, the path to the final output (Scope/Display), or the forward path in a control loop. Straight lines draw the eye first — make the signal the reader most needs to trace the easy one.
- **Clear branch visibility.** When two layouts are otherwise comparable in line quality, prefer the one where the branch point and all outgoing lines are fully visible — no occlusion by blocks, ports, or other lines. Even a small overlap at a branch point makes it harder to see where the signal splits.
- **Forward-path alignment.** After resolving branch layout, align blocks in the same signal chain to the same vertical center, creating an unbroken horizontal line through the forward path. Branch layout changes often enable better forward-path alignment (e.g., raising a source to align with a Scope may free a downstream block to align with the rest of the chain).
- **Source proximity.** Source blocks that feed a mid-chain block (not the first block in the chain) should be positioned near that downstream block, not forced to the leftmost column. Only the primary signal chain starts at the left margin. Secondary sources go below (or above) the forward path, near their first connection point. This keeps lines short and the layout compact. Example: a carrier SineWave feeding a Product block mid-chain belongs under the preceding processing block, not at x=100 alongside the chain's primary source.
- **Compute exact port positions for alignment.** "Close enough" is not good enough — even a 2px vertical misalignment between a source port and destination port creates a visible kink, and at branch points it causes doubled-stroke rendering artifacts. Use the port position formula: `portY = block.y + block.height * (portIndex + 1) / (portCount + 1)`. Match source and destination portY values exactly, then snap the block position to the nearest grid point that achieves this.

### Signal Labeling
- **Signal labels** go below the line, at the origin (source end) of the connection. (MAAB db_0097a/b)
- **Label signals from interface blocks.** Signals originating from Inport, From, Subsystem, Constant, and Selector blocks should be labeled. Signals entering Outport, Goto, and Subsystem blocks should be labeled. (MAAB na_0008, jc_0008)
- **Waypoints** in model files should route signals cleanly around obstacles.

### Unconnected Ports
- **Every port must be connected.** No block shall have unconnected input or output ports, and no signal line shall have a dangling end. (MAAB db_0081)
- **Use Terminator for unused outputs** and **Ground for unused inputs** when a port is intentionally unused. This makes the intent explicit and prevents simulation warnings.

### Subsystem Port Ordering
- **Inport blocks on the left, Outport blocks on the right** of the subsystem diagram. May be repositioned to prevent signal crossings. (MAAB db_0042a/b)
- **No duplicate Inports.** Each input signal gets exactly one Inport block. Use signal branching inside the subsystem. (MAAB db_0042c)
- **Port ordering matches vertical position.** Inport/Outport numbering should reflect the top-to-bottom order of ports on the parent Subsystem block.
- **Reorder ports on the parent** to minimize line crossings at the subsystem boundary rather than accepting crossing lines. (Michael Burke)

### Mitigations for Tight Layouts
When a line cannot maintain 20px clearance from an unrelated block without creating an awkward route:
1. **Increase block spacing** -- move the unrelated block further away from the line's path.
2. **Add waypoints** -- route the line around the block with explicit waypoints that maintain clearance.
3. **Use Goto/From blocks** -- replace the physical line entirely with a Goto/From pair. This eliminates the routing problem at the cost of less visible signal flow. (MAAB na_0011)

### Annotations
- **Place annotations in unoccupied space** near the elements they describe. Annotations must not overlap blocks, lines, labels, or other annotations. (MAAB jc_0903a)
- **Keep annotations concise.** Detailed design rationale belongs in external documentation, not on the diagram canvas.

### Model Complexity
- Max ~40 active blocks per subsystem level. (Michael Burke)
- Max ~5 used inputs and ~2 calculated outputs per subsystem. (Michael Burke)
- Max 3 levels of hierarchy depth; 30--60 total subsystems per model. (Michael Burke)

### Anti-Patterns to Avoid
- Blocks overlapping each other
- Spaghetti wiring (unorganized signal routing)
- Wires passing through blocks
- **Lines routing adjacent to unrelated blocks** -- creates false visual connections even without overlap
- **Signal lines with 3+ bends** when a simpler route exists
- **Dangling (unconnected) ports or lines** -- ambiguous: incomplete model or intentional?
- Labels overlapping anything
- Inconsistent flow direction without feedback justification
- Flipped blocks outside of feedback loops

---

## Coordinate Cheat Sheet

For a typical 3-block model (Source -> Processing -> Sink):

```
Source block:     x=80,   y=120,  w=80,  h=60
Processing block: x=280,  y=100,  w=140, h=100
Sink block:       x=520,  y=110,  w=60,  h=60
```

Key formulas:
- **Horizontal gap:** `nextBlock.x >= prevBlock.x + prevBlock.width + 80`
- **Vertical center alignment:** align blocks so their vertical centers are roughly equal when on the same signal path
- **Port Y position:** `block.y + block.height * (portIndex + 1) / (portCount + 1)`

For branch lines (one source to two destinations), use waypoints:
```json
"waypoints": [
  {"x": branchX, "y": srcPortY},
  {"x": branchX, "y": dstPortY},
  {"x": dstBlockX, "y": dstPortY}
]
```

Where `branchX` is a convenient midpoint X between the source and destination blocks.

---

## State Chart Layout

### State Positioning
- **Snap positions to 10px grid.** State x, y should be multiples of 10.
- **Size states to fit their label text** with at least 20px padding on each side and 30px top padding (for the name header area).
- **Minimum state size:** 160x100 for states with entry/during/exit actions.
- **Consistent sizing:** States at the same hierarchy level should be the same size when possible.
- **Minimum gap between states:** 60px edge-to-edge (allows room for transition lines and labels).

### State Arrangement Patterns
- **Left-to-right flow** for sequential state progressions (e.g., Init -> Running -> Done).
- **Hub-and-spoke** for a central state with transitions to/from peripheral states:
  - Place the hub state center-left
  - Spoke states arranged in an arc to the right
- **Grid layout** for states without a clear flow direction:
  - Max 3 columns, wrap to next row
  - Use the formula: `col = i % 3`, `row = floor(i / 3)`

### Junction Placement
- Place the **default transition junction** in the **top-left** area of the chart. (Agile Modeling)
- Position junctions **between** the states they connect, biased toward the source.
- Use junctions **only when functionally needed** (branching/merging), not decoratively. (MAAB db_0129)

### Default Transition
- Points into the junction or initial state.
- Placed above/left of its target with a short arrow.

### Transition Labels
- Place at the **midpoint** of the transition line by default.
- **Direction-based placement** to avoid overlap:
  - Left-to-right: label **above** the line
  - Right-to-left: label **below** the line
  - Downward: label to the **right**
  - Upward: label to the **left**
- Labels must **never overlap** states, other transitions, or other labels.
- Use `labelOffset: {dx, dy}` in the model file to adjust:
  - `dy: -15` for above, `dy: 15` for below
  - `dx: 15` for right, `dx: -15` for left

### Bidirectional Transitions
- Offset using `midpointOffset` so the two transitions don't overlap:
  - Forward transition: `midpointOffset: {dx: -20, dy: 0}` or `{dx: 0, dy: -20}`
  - Reverse transition: `midpointOffset: {dx: 20, dy: 0}` or `{dx: 0, dy: 20}`
- Place labels on opposite sides of their respective transitions.

### Hierarchy
- **Initial/default state:** top-left corner of the parent. (Agile Modeling)
- Composite states must be large enough to contain substates with 20px side padding, 55px top padding.
- Max 3 levels of nesting depth; use subcharts beyond that. (Michael Burke)

---

## State Chart Coordinate Cheat Sheet

For the Smart Thermostat pattern (1 junction + 4 states):

```
Junction:   x=80,  y=60   (top-left, entry point)
State 1:    x=80,  y=220  (center-left, default/idle)
State 2:    x=340, y=80   (upper-right)
State 3:    x=340, y=370  (lower-right)
State 4:    x=600, y=80   (far-right, extension of state 2)
```

State sizes: 180x110 (uniform)
Gap between states: 60-80px minimum

---

## Verification Checklist

Before finalizing any model:

- [ ] All blocks snap to 10px grid
- [ ] No blocks overlap
- [ ] No labels overlap blocks, lines, or other labels
- [ ] Signal flow is left-to-right
- [ ] All blocks face right (output to right) except Delay blocks in feedback loops
- [ ] All signal lines use orthogonal routing
- [ ] No signal lines cross (use line hops if unavoidable)
- [ ] No signal lines pass within 20px of unrelated blocks
- [ ] Parallel signal lines maintain at least 10px gap
- [ ] No signal line has more than 2 unnecessary bends
- [ ] No unconnected ports (use Ground/Terminator for intentionally unused)
- [ ] Max 2 sub-lines per branch point
- [ ] Block names are below blocks
- [ ] All subsystem input/output signals are labeled
- [ ] Inport/Outport vertical order inside subsystems matches parent port numbering
- [ ] Annotations do not overlap blocks, lines, or labels
- [ ] Equivalent blocks across parallel paths share x-coordinates (within 10px)
- [ ] States have uniform sizing at same hierarchy level
- [ ] Transition labels follow direction-based placement
- [ ] Junction is in top-left with default transition
- [ ] Minimum 60px gap between states
- [ ] Minimum 80px horizontal gap between block diagram blocks

---

## Sources

Key references (80+ total):
- [MAAB Guidelines v5 (PDF)](https://www.mathworks.com/content/dam/mathworks/mathworks-dot-com/solutions/mab/mab-control-algorithm-modeling-guidelines-using-matlab-simulink-and-stateflow-v5.pdf)
- [MAB Guidelines v6 (PDF)](https://www.mathworks.com/content/dam/mathworks/mathworks-dot-com/solutions/mab/mab-guidelines-v6.pdf)
- [MAAB jc_0110: Direction of block](https://www.mathworks.com/help/simulink/mdl_gd/maab/jc_0110directionofblock.html)
- [MAAB db_0042: Inport/Outport usage](https://www.mathworks.com/help/simulink/mdl_gd/maab/db_0042usageofinportandoutportblocks.html)
- [MAAB db_0081: Unconnected signals](https://www.mathworks.com/help/slcheck/ref/check-for-unconnected-signal-lines-and-blocks.html)
- [MAAB na_0008: Signal label display](https://www.mathworks.com/help/simulink/mdl_gd/maab/na_0008displayoflabelsonsignals.html)
- [MAAB db_0140: Block parameter display](https://www.mathworks.com/help/simulink/mdl_gd/maab/db_0140displayofblockparameters.html)
- [5 Tips for Readable Block Diagram Models](https://mburkeonmbd.com/2017/10/03/5-tips-for-more-readable-simulink-models/)
- [6 Tips for Readable Stateflow Charts](https://mburkeonmbd.com/2017/10/11/6-tips-for-readable-stateflow-charts/)
- [UML State Machine Diagramming Guidelines](https://agilemodeling.com/style/statechartdiagram.htm)
- [ELK Layered Algorithm](https://eclipse.dev/elk/reference/algorithms/org-eclipse-elk-layered.html)
- [ELK Spacing Documentation](https://eclipse.dev/elk/documentation/tooldevelopers/graphdatastructure/spacingdocumentation.html)
- [ELK spacing.edgeNode](https://eclipse.dev/elk/reference/options/org-eclipse-elk-spacing-edgeNode.html)
- [ELK spacing.edgeEdge](https://eclipse.dev/elk/reference/options/org-eclipse-elk-spacing-edgeEdge.html)
- [yFiles EdgeRouter](https://docs.yworks.com/yfiles-html/api/EdgeRouter.html)
- [LabVIEW Style Guide](https://labviewwiki.org/wiki/Style_Guide)
- [Simulink Smart Signal Routing](https://blogs.mathworks.com/simulink/2012/10/11/smart-signal-routing/)
- [Orthogonal Graph Drawing (Tamassia)](https://cs.brown.edu/people/rtamassi/gdhandbook/chapters/orthogonal.pdf)
