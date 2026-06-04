# /manual-testing

> **An internal helper — you don't call this one directly.** `/manual-testing`
> is marked `user-invocable: false`, so typing it at the slash prompt gets you
> nowhere. Other skills — most often [`/verify-changes`](verify-changes.md) —
> dispatch it behind the scenes when they need to confirm a UI change works by
> driving the real interface the way a person would.

<details class="flow-cmd" open>
<summary>How it runs — browser-driven UI checks</summary>

<div class="flow">
<div class="flow-step"><p>The <strong>agent</strong> starts the dev server and bypasses auth</p></div>
<div class="flow-step"><p>It drives the UI with real mouse and keyboard events</p></div>
<div class="flow-step"><p>It documents workarounds where playwright-cli falls short</p></div>
</div>

</details>

## What it does

`/manual-testing` helps playwright-cli interact with a UI the way a user would —
clicking menus, click-and-dragging elements on canvases, typing into inputs,
using keyboard shortcuts — and documents workarounds where playwright-cli is too
limited to mimic a particular user action.

## Prerequisites

1. Start the dev server
2. Open the browser with playwright-cli
3. Bypass the auth gate (if the app has one)

## Workflow

The skill guides playwright-cli to behave like a user with real
mouse/keyboard events:

- Use menus by clicking them (not by JS-evaluating the bound command)
- Move elements on a canvas by click-and-drag
- Type into inputs by focusing and typing
- Drive keyboard-driven actions with real key presses
- Document workarounds where playwright-cli's API can't mimic a given user
  action (gesture-based interactions, hover-only menus, native OS dialogs,
  timing-sensitive drags)

## Common Patterns

- **After UI changes:** a verification caller uses these recipes to confirm
  the interface still works the way a user expects.
- **Verification complement:** used alongside automated tests for
  visual/interactive verification.

## Tips & Gotchas

- Uses **real mouse/keyboard events** (`click`, `type`, `press`, `drag`,
  `mousemove`) -- never `page.evaluate()` to simulate user actions
- `eval`/JS is only for setup and assertions (auth bypass, reading state,
  querying DOM coordinates) -- never for clicking, dragging, or typing
- Requires the dev server to be running and playwright-cli to be available
- The auth gate must be bypassed before testing (if the app has one)
- Where playwright-cli can't mimic a gesture, take the closest faithful
  workaround and flag it in the verification report
