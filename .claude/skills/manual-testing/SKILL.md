---
name: manual-testing
user-invocable: false
argument-hint: ""
description: >-
  Support skill that helps playwright-cli interact with a UI the way a
  user would — clicking menus, click-and-dragging elements on canvases,
  typing into inputs, using keyboard shortcuts — and documents workarounds
  where playwright-cli is too limited to mimic a particular user action.
  Dispatched when a caller (e.g. /verify-changes) needs to verify a UI
  change. Use when told to "test manually", "test in the browser", or
  "verify with playwright-cli".
metadata:
  version: "2026.06.03+0f8b27"
---

# Manual Testing with playwright-cli

This is a **support skill**: it does not run on its own. Other skills
(most often `/verify-changes`) lean on it when they need to confirm a UI
change works by driving the real interface the way a person would. The
goal throughout is to make `playwright-cli` **behave like a user** —
clicking, dragging, typing, and using the keyboard — rather than reaching
into the page's internals to fake the outcome.

## Prerequisites

1. Start the dev server (if not already running):

   ```bash
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   if [ -z "$DEV_SERVER_CMD" ]; then
     echo "ERROR: dev_server.cmd not configured. Run /update-zskills." >&2
     exit 1
   fi
   # Get the correct port for this project root (configured via dev_server.default_port for main; unique per worktree; consumer dev-port.sh stub may override)
   $DEV_SERVER_CMD &
   ```

2. Open the browser:

   ```bash
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   PORT=$(bash "$ZSKILLS_SKILLS_ROOT/update-zskills/scripts/port.sh")
   playwright-cli open http://localhost:$PORT
   ```

3. Bypass the auth gate (if the app has one):

   ```bash
   playwright-cli localstorage-set auth-token \
     {{AUTH_BYPASS_VALUE}}
   playwright-cli reload
   ```

4. Take a snapshot to confirm the page loaded:

   ```bash
   playwright-cli snapshot
   ```

## Core Workflow

Every manual test follows this cycle:

1. **Snapshot** — get current page state and element refs
2. **Interact** — use real mouse/keyboard commands (click, type, press, drag, mousemove, etc.)
3. **Snapshot** — verify the UI updated as expected
4. **Screenshot** — capture visual evidence when needed

**Golden rule:** Never use `eval` or `run-code` to *simulate* user actions.
Real events only. `eval` is reserved for setup (auth, localStorage) and
assertions (reading the page's state to confirm an interaction worked) —
never for clicking, typing, dragging, or otherwise standing in for the
user.

## Act like a user

The whole point of this skill is to exercise the UI through the same
surface a person uses. A few core patterns:

### Use menus by clicking them

Open menus, submenus, and toolbar items by **clicking** them — never by
calling the underlying command through `eval`. A menu item that is
unreachable by clicking (disabled, behind a hover, off-screen) is a real
finding about the UI; routing around it with `eval` hides the bug.

```bash
# 1. Snapshot to find the menu trigger
playwright-cli snapshot

# 2. Click to open the menu
playwright-cli click <menu-trigger-ref>

# 3. Snapshot to see the menu items
playwright-cli snapshot

# 4. Click the item you want
playwright-cli click <menu-item-ref>
```

### Move elements on a canvas by click-and-drag

To reposition something on a canvas (or anywhere drag is the user
gesture), use real mouse events — press down on the element, move through
intermediate points, then release. Intermediate `mousemove` steps help the
app render drag feedback (rubber lines, drop targets) the same way it would
for a person.

```bash
# 1. Snapshot / read the element's screen coordinates
playwright-cli snapshot

# 2. Press down on the element's center
playwright-cli mousemove <start-x> <start-y>
playwright-cli mousedown

# 3. Move through an intermediate point toward the target
playwright-cli mousemove <mid-x> <mid-y>

# 4. Move to the target and release
playwright-cli mousemove <end-x> <end-y>
playwright-cli mouseup

# 5. Snapshot to confirm the element moved
playwright-cli snapshot
```

It is fine to use `eval` + `getBoundingClientRect()` to *read* an element's
screen coordinates before a drag — that is reading state, not simulating an
action. The drag itself must be real mouse events.

### Type into inputs

Click the field to focus it, clear it, then type — exactly as a user
would.

```bash
playwright-cli click <field-ref>
playwright-cli press Control+a    # select existing content
playwright-cli type "new value"
playwright-cli press Enter        # or click an Apply/Save control
```

### Use the keyboard for keyboard-driven actions

When the UI exposes a keyboard shortcut or keyboard navigation, drive it
with real key presses rather than invoking the bound handler directly.

```bash
playwright-cli press Control+z       # undo
playwright-cli press Escape          # cancel / deselect
playwright-cli press Tab             # move focus
```

## Workarounds where playwright-cli is too limited

`playwright-cli` cannot perfectly reproduce every user gesture. When you
hit a wall, **document the limitation** and use the closest faithful
approximation — but keep it as close to a real user action as the tool
allows, and note in your report that you worked around a tooling gap (so it
isn't mistaken for verified-as-a-user behavior). Common cases:

- **Gesture-based interactions** (pinch-zoom, two-finger pan, momentum
  scroll): `playwright-cli` has no multi-touch. Approximate with the
  closest single-pointer or keyboard equivalent the app also supports
  (e.g. a zoom button or `Ctrl+scroll`), and note the gesture itself was
  not exercised.
- **Hover-only menus / tooltips**: if a menu only appears on hover and a
  plain `click` doesn't trigger it, move the mouse over the trigger first
  (`mousemove` to its coordinates), snapshot to confirm the hover content
  appeared, then click. If the hover content still won't render under the
  tool, that is a finding — report it rather than calling the handler via
  `eval`.
- **Drag-and-drop that depends on precise timing or pointer capture**: add
  extra intermediate `mousemove` steps and a brief settle before
  `mouseup`. See "Canvas / SVG gotchas" below.
- **Native OS dialogs** (file pickers, print): these are outside the page
  and not drivable as a user. Bypass only the OS-native portion (e.g. set
  the file input's value), and clearly note the native step was skipped.

When you take a workaround, prefer one that still goes through the app's
real UI surface; reserve `eval`-driven shortcuts for genuinely
undrivable steps and always flag them in your verification report.

## Canvas / SVG gotchas

These trip up drag-and-position interactions on `<canvas>` / SVG surfaces:

1. **Pointer capture:** Elements may call `setPointerCapture()` during
   drags. After release, `e.target` can still point at the capture element;
   apps that use `document.elementFromPoint()` for post-release hit
   detection are behaving correctly, not buggily.

2. **Double-click reliability:** `dblclick` can be flaky on SVG elements in
   some browsers. If a `dblclick` doesn't produce the expected result, try
   `click` to select followed by the keyboard action that opens the same
   thing (often `Enter`).

3. **Coordinate systems:** Element positions are often in the canvas's own
   coordinate space, but `mousemove`/`mousedown` use **screen**
   coordinates. When reading positions via `eval`, use
   `getBoundingClientRect()` — it returns screen coordinates matching what
   `playwright-cli` expects.

4. **Zoom / transform level matters:** If the surface is zoomed or panned,
   its internal coordinates diverge from screen coordinates. Always derive
   click/drag targets from `getBoundingClientRect()` rather than the
   element's logical position. If interactions seem to miss their targets,
   inspect the current transform:

   ```bash
   playwright-cli eval \
     "document.querySelector('{{VIEWPORT_SELECTOR}}').getAttribute('transform')"
   ```
