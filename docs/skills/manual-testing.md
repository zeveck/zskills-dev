# /manual-testing

> Block-diagram editor manual testing recipes for playwright-cli using real mouse/keyboard events (add blocks, connect ports, run simulations, edit parameters).

## Usage

```
/manual-testing
```

No arguments -- the skill provides testing recipes for the block-diagram editor.

## Prerequisites

1. Start the dev server
2. Open the browser with playwright-cli
3. Bypass the auth gate

## Workflow

The skill provides recipes for testing with real mouse/keyboard events:

- Adding blocks to the canvas
- Connecting ports between blocks
- Running simulations
- Editing block parameters
- Verifying UI behavior

## Examples

```
/manual-testing
```

## Common Patterns

- **After UI changes:** use `/manual-testing` recipes to verify the editor works correctly
- **Verification complement:** used alongside automated tests for visual/interactive verification

## Tips & Gotchas

- Uses **real mouse/keyboard events** (`click`, `type`, `press`, `drag`) -- never `page.evaluate()` for user actions
- `eval`/JS is only for setup and assertions (auth bypass, reading state, querying DOM)
- Requires the dev server to be running and playwright-cli to be available
- The auth gate must be bypassed before testing
