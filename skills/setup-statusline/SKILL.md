---
name: setup-statusline
description: Configure the Claude Code status line — model name, context bar, window/weekly rate limits, customizable in natural language
disable-model-invocation: true
---

# /setup-statusline [description] — Configure Status Line

Set up the status line in one command. With no arguments, installs the
default format. With arguments, describe what you want in natural language.

**Default (bare `/setup-statusline`):**
`Opus 4 ██░░░░░░░░ 17% · 5% weekly` — light purple, model + context bar + weekly %.

## Available elements

- **model** — short model name ("Opus 4", "Sonnet 4")
- **context** — context usage percentage, optionally with a 10-char block
  bar (`█` filled, `░` empty)
- **window** — current rate limit window usage percentage, optionally with bar
- **weekly** — weekly rate limit usage percentage, optionally with bar

Any element can have a bar. Percentages that can't be determined show `?%`.

## Examples

```
/setup-statusline purple show model, context with bar and %, weekly%
```
→ `Opus 4 ██░░░░░░░░ 17% · 5% weekly` in purple

```
/setup-statusline show context with bar, window%, weekly%
```
→ `██░░░░░░░░ 17% · 42% window · 5% weekly` in default color

```
/setup-statusline blue show model, context%, window with bar
```
→ `Opus 4 17% · ████░░░░░░ 42% window` in blue

```
/setup-statusline show everything with bars
```
→ `Opus 4 ██░░░░░░░░ 17% · ████░░░░░░ 42% window · █░░░░░░░░░ 5% weekly`

```
/setup-statusline green show context with bar
```
→ `██░░░░░░░░ 17%` in green

Default color: `rgb(180,130,255)` (light purple).

## Implementation

Parse the user's description to determine:
1. **Color** — any color term, hex, or rgb value (default: `rgb(180,130,255)`)
2. **Which elements to show** and whether each gets a bar

Build a specification and spawn the `statusline-setup` agent:

```
Agent(subagent_type: "statusline-setup", prompt: <specification>)
```

Report the result when done.
