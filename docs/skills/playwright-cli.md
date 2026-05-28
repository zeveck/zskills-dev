# /playwright-cli

> Browser automation with playwright-cli. Navigate websites, interact with pages, fill forms, take screenshots, test web applications, and extract information.

## Usage

```
/playwright-cli
```

The skill provides the `playwright-cli` tool for browser automation.

## Commands

### Core

```
playwright-cli open                        # Open new browser
playwright-cli open https://example.com    # Open and navigate
playwright-cli goto https://playwright.dev # Navigate to URL
playwright-cli type "search query"         # Type text
playwright-cli click e3                    # Click element by ref
playwright-cli dblclick e7                 # Double-click
playwright-cli fill e5 "user@example.com" # Fill input field
playwright-cli drag e2 e8                 # Drag element
playwright-cli hover e4                   # Hover over element
playwright-cli press Enter                # Press key
playwright-cli screenshot                 # Take screenshot
playwright-cli close                      # Close browser
```

### Navigation

```
playwright-cli goto <url>     # Navigate to URL
playwright-cli back           # Go back
playwright-cli forward        # Go forward
playwright-cli reload         # Reload page
```

### Interaction

```
playwright-cli click <ref>       # Click element
playwright-cli dblclick <ref>    # Double-click
playwright-cli type <text>       # Type text
playwright-cli fill <ref> <text> # Fill input
playwright-cli press <key>       # Press key
playwright-cli drag <from> <to>  # Drag element
playwright-cli hover <ref>       # Hover
```

## Examples

```
playwright-cli open https://example.com
playwright-cli click e15
playwright-cli type "page.click"
playwright-cli press Enter
playwright-cli screenshot
playwright-cli close
```

## Tips & Gotchas

- Use `playwright-cli screenshot` without `--filename` to save to the configured output directory (`.playwright/output/`)
- Using `--filename` bypasses the output directory and saves to the working directory
- Element references (e.g., `e3`, `e15`) come from the page snapshot
- This is a tool allowlist skill -- it enables `Bash(playwright-cli:*)` commands
