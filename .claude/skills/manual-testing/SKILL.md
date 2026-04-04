---
name: manual-testing
description: >-
  Block-diagram editor manual testing recipes for playwright-cli. Covers
  common UI operations (adding blocks, connecting ports, running simulations,
  editing parameters) using real mouse/keyboard events. Use when told to
  "test manually", "test in the browser", or "verify with playwright-cli".
---

# Manual Testing with playwright-cli

## Prerequisites

1. Start the dev server (if not already running):

   ```bash
   # Get the correct port for this project root (8080 for main, unique per worktree)
   npm start &
   ```

2. Open the browser:

   ```bash
   PORT=$(bash scripts/port.sh)
   playwright-cli open http://localhost:$PORT
   ```

3. Bypass the auth gate:

   ```bash
   playwright-cli localstorage-set auth-token \
     {{AUTH_BYPASS_VALUE}}
   playwright-cli reload
   ```

4. Take a snapshot to confirm the editor loaded:

   ```bash
   playwright-cli snapshot
   ```

## Core Workflow

Every manual test follows this cycle:

1. **Snapshot** — get current page state and element refs
2. **Interact** — use real mouse/keyboard commands (click, type, drag, mousemove, etc.)
3. **Snapshot** — verify the UI updated as expected
4. **Screenshot** — capture visual evidence when needed

**Golden rule:** Never use `eval` or `run-code` to simulate user actions. Real events
only. `eval` is reserved for setup (auth, localStorage) and assertions (reading model
state).

## Adding a Block

### Method A: Drag from Library Panel

```bash
# 1. Snapshot to find the library panel and category refs
playwright-cli snapshot

# 2. Click a category to expand it (e.g., "Sources")
playwright-cli click <category-ref>

# 3. Snapshot to see block items
playwright-cli snapshot

# 4. Drag the block item to the canvas
#    Find the ref for the block type (e.g., "Step")
#    Drag it to target canvas coordinates
playwright-cli drag <block-item-ref> --x=400 --y=300
```

### Method B: quick-add dialog (double-click canvas)

```bash
# 1. Double-click the canvas to open quick-add dialog
playwright-cli dblclick "{{CANVAS_SELECTOR}}" --x=400 --y=300

# 2. Type the block name
playwright-cli type "Gain"

# 3. Snapshot to see results
playwright-cli snapshot

# 4. Press Enter to place the selected block at center
playwright-cli press Enter

# 5. Snapshot to confirm placement
playwright-cli snapshot
```

**Tip:** Pick a method at random to exercise different code paths each time.

## Copying an Existing Block

### Method A: Ctrl+D (Duplicate)

```bash
# 1. Click the block to select it
playwright-cli click <block-ref>

# 2. Duplicate it
playwright-cli press Control+d
```

### Method B: Ctrl+C / Ctrl+V (Copy-Paste)

```bash
# 1. Click the block to select it
playwright-cli click <block-ref>

# 2. Copy, then paste
playwright-cli press Control+c
playwright-cli press Control+v
```

### Method C: Right-click Drag

```bash
# 1. Mousedown with right button on the block
playwright-cli mousemove <block-x> <block-y>
playwright-cli mousedown right

# 2. Drag to new position
playwright-cli mousemove <new-x> <new-y>

# 3. Release
playwright-cli mouseup right
```

## Connecting Two Blocks

Connect output port of Block A to input port of Block B:

```bash
# 1. Snapshot to find block positions and port locations
playwright-cli snapshot

# 2. Find the output port of Block A
#    Ports are small circles on the block edges.
#    Output ports are on the right side of a block.
#    Use eval to get exact port coordinates if needed:
playwright-cli eval "(() => {
  const sel = '[data-block-id=\"BLOCK_A_ID\"] \
    {{PORT_SELECTOR}}[data-port-side=\"out\"]';
  const p = document.querySelector(sel);
  const r = p.getBoundingClientRect();
  return { x: r.x + r.width/2, y: r.y + r.height/2 };
})()"

# 3. Move to the output port center and start the drag
playwright-cli mousemove <out-x> <out-y>
playwright-cli mousedown

# 4. Move through intermediate points toward the input port
#    (intermediate moves help the rubber line render correctly)
playwright-cli mousemove <midpoint-x> <midpoint-y>

# 5. Move to the input port of Block B
#    Input ports are on the left side of a block.
playwright-cli eval "(() => {
  const sel = '[data-block-id=\"BLOCK_B_ID\"] \
    {{PORT_SELECTOR}}[data-port-side=\"in\"]';
  const p = document.querySelector(sel);
  const r = p.getBoundingClientRect();
  return { x: r.x + r.width/2, y: r.y + r.height/2 };
})()"

# 6. Move to the input port and release
playwright-cli mousemove <in-x> <in-y>
playwright-cli mouseup

# 7. Snapshot to verify the connection was made
playwright-cli snapshot
```

**Note:** Using `eval` to read port coordinates is fine — it's reading DOM state,
not simulating user actions. The actual connection happens through real mouse events.

## Editing Block Parameters

```bash
# 1. Double-click the block to open the property panel
playwright-cli dblclick <block-ref>

# 2. Snapshot to see the property fields
playwright-cli snapshot

# 3. Clear and fill a parameter field
#    Fields have data-key attributes matching param names
playwright-cli click <field-ref>
playwright-cli press Control+a
playwright-cli type "5"

# 4. Click Apply
playwright-cli click <apply-btn-ref>

# 5. Snapshot to verify the block updated
playwright-cli snapshot
```

**Alternative:** Select the block, then press Enter to open properties.

## Running a Simulation

```bash
# 1. Set the stop time (if needed)
playwright-cli click <stop-time-ref>
playwright-cli press Control+a
playwright-cli type "10"
playwright-cli press Enter

# 2. Click the Run button
playwright-cli click <run-btn-ref>

# 3. Wait for simulation to complete, then screenshot
#    The Run button changes back when done
playwright-cli screenshot

# 4. Snapshot to read results / check for errors
playwright-cli snapshot
```

**Tip:** After running, look for Scope blocks — they open popup windows showing
output graphs. Screenshot those for visual verification.

## Keyboard Shortcuts

| Shortcut              | Action                           |
| --------------------- | -------------------------------- |
| `Ctrl+Z`              | Undo                             |
| `Ctrl+Shift+Z`        | Redo                             |
| `Delete`/`Backspace`  | Delete selected                  |
| `Ctrl+A`              | Select all                       |
| Double-click canvas   | quick-add dialog (add block)         |
| `Ctrl+G`              | Group into Subsystem             |
| `Ctrl+D`              | Duplicate selected               |
| `Ctrl+C`/`Ctrl+V`    | Copy / Paste                     |
| `F2`                  | Rename selected block            |
| `Enter`               | Open properties (block selected) |
| `Escape`              | Cancel current action / deselect |
| `Ctrl+S`              | Save model                       |

## Example Models

**Always check `examples/` before building test models from scratch.**
Run `ls examples/` to see available models. Load them via URL:
```
http://localhost:<port>/?file=examples/<name>/<name>.model
```

Available examples include: `amplifier-circuit`, `motor-controller`,
`signal-filter`, `feedback-loop`, and more. Check the directory — don't guess.

## Common Selectors

Use these to locate elements when snapshot refs aren't sufficient:

### Canvas & Viewport

| Selector       | Description             |
| -------------- | ----------------------- |
| `{{CANVAS_SELECTOR}}`   | Main SVG canvas         |
| `{{VIEWPORT_SELECTOR}}` | Pan/zoom viewport group |

### Blocks & Ports

| Selector                                | Description          |
| --------------------------------------- | -------------------- |
| `[data-block-id="ID"]`                  | Block by UUID        |
| `{{BLOCK_BODY_SELECTOR}}`                        | Block rectangle      |
| `{{BLOCK_LABEL_SELECTOR}}`                       | Block name label     |
| `{{PORT_SELECTOR}}[data-port-side="out"]` | Output port circle   |
| `{{PORT_SELECTOR}}[data-port-side="in"]`  | Input port circle    |
| `[data-port-index="0"]`                 | First port           |
| `{{SELECTED_SELECTOR}}`                          | Any selected element |

### Lines

| Selector              | Description         |
| --------------------- | ------------------- |
| `[data-line-id="ID"]` | Signal line by UUID |
| `{{LINE_SELECTOR}}`            | Any signal line     |

### Library Panel

| Selector                    | Description             |
| --------------------------- | ----------------------- |
| `{{LIBRARY_SELECTOR}}`               | Library sidebar         |
| `[data-category="sources"]` | Category by name        |
| `[data-block-type="Gain"]`  | Block item by type name |
| `{{LIBRARY_SEARCH_SELECTOR}} input`  | Library search input    |

### Toolbar

| Selector            | Description     |
| ------------------- | --------------- |
| `{{RUN_BTN_SELECTOR}}`       | Run simulation  |
| `{{STOP_BTN_SELECTOR}}`      | Stop simulation |
| `{{PAUSE_BTN_SELECTOR}}`     | Pause simulation |
| `{{SIM_TIME_SELECTOR}}` | Stop time input |

### Property Panel

| Selector                  | Description       |
| ------------------------- | ----------------- |
| `{{PROPERTY_PANEL_SELECTOR}}`      | Properties dialog |
| `[data-key="Gain"]`       | Parameter by key  |
| `{{PROPERTY_APPLY_SELECTOR}}`  | Apply button      |
| `{{PROPERTY_CANCEL_SELECTOR}}` | Cancel button     |

### quick-add dialog

| Selector                 | Description       |
| ------------------------ | ----------------- |
| `{{QUICK_INSERT_SELECTOR}}`       | quick-add dialog popup |
| `{{QUICK_INSERT_INPUT_SELECTOR}}` | Search text field |
| `{{QUICK_INSERT_ITEM_SELECTOR}}`  | Result item       |

## SVG Gotchas

1. **Pointer capture:** SVG elements use `setPointerCapture()` during drags. After
   release, `e.target` may still point to the capture element. The app uses
   `document.elementFromPoint()` for hit detection after release — this is correct
   behavior, not a bug.

2. **Double-click on SVG:** `dblclick` events can be unreliable on SVG elements in
   some browsers. If `dblclick` on a block ref doesn't open properties, try selecting
   the block first (`click`), then pressing `Enter`.

3. **Coordinate systems:** Block positions are in SVG viewport coordinates, but
   `mousemove`/`mousedown` use screen coordinates. When using `eval` to read element
   positions, use `getBoundingClientRect()` which returns screen coordinates matching
   what playwright-cli expects.

4. **Zoom level matters:** If the canvas is zoomed, screen coordinates and SVG
   coordinates diverge. Use `getBoundingClientRect()` for screen coords. If tests
   seem to miss targets, check zoom level with:

   ```bash
   playwright-cli eval \
     "document.querySelector('{{VIEWPORT_SELECTOR}}').getAttribute('transform')"
   ```
