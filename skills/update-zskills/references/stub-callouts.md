# zskills consumer stub-callouts

This reference defines the **consumer stub-callout contract** between
zskills and a consuming project, the canonical-stubs inventory, the
sourceable dispatcher used at every callsite, and guidance for adding
new callouts.

A "consumer stub" is a script the consumer can place in its own
top-level `scripts/` directory to customize a specific zskills behavior.
zskills checks for the stub at a documented path, invokes it with
documented arguments, and consumes its stdout / exit code per the
contract below. When the stub is absent (or present but not executable),
zskills falls through to a documented default.

## Contract

> **zskills consumer stub-callout contract**
> 1. zskills checks for the consumer stub at
>    `$REPO_ROOT/scripts/<stub-name>.sh`.
> 2. The stub must be executable (`-x` test). If the file
>    exists but is not executable, zskills emits a one-line
>    warning to stderr (`zskills: scripts/<stub>.sh present
>    but not executable; ignoring (chmod +x to enable)`) and
>    treats it as absent.
> 3. zskills invokes the stub with documented positional
>    arguments (per-stub; see canonical table). The dispatcher
>    consumes a single `--` discriminator (required at every
>    callsite) before forwarding the remainder verbatim — a
>    literal `--` argument inside the stub's `$@` is preserved.
> 4. **stdout:** zskills captures stdout and uses it where
>    documented (per-stub; e.g. `dev-port.sh` expects a
>    numeric port).
> 5. **exit code:**
>    - `0` + non-empty stdout → honor stdout where applicable;
>      where not (e.g. `post-create-worktree.sh`), treat as
>      success.
>    - `0` + empty stdout → no-op; zskills falls through to
>      its built-in default.
>    - non-zero → propagate failure; zskills surfaces the
>      stub's stderr and exits non-zero with a propagation rc
>      (see per-callout phases for specific rc).
> 6. **First-run note:** zskills emits a one-line stderr note
>    the first time a stub is encountered in a project (gated
>    by absence of `.zskills/stub-notes/<stub>.noted`; the
>    file is touched after the first note). If the marker
>    write fails (read-only fs), the note is suppressed —
>    this avoids per-invocation noise on systems where the
>    marker can't be persisted.

### Stub non-zero rc contract (pinned)

If the stub exits non-zero, the dispatcher (a) sets
`ZSKILLS_STUB_RC` to the stub's exit code unchanged, (b) emits a single
stderr line `zskills: scripts/<name> exited <rc>`, (c) returns 0 itself
(the lib never propagates the stub's failure itself — the caller
decides). The stub's stdout (captured into `ZSKILLS_STUB_STDOUT`) is
preserved as-is; the stub's stderr is NOT captured (it passes through
to the caller's stderr). The caller inspects `ZSKILLS_STUB_RC` and
`ZSKILLS_STUB_INVOKED` and decides whether to abort, fall through, or
warn-and-continue.

### `--` discriminator

The dispatcher's `--` separator is **required** at every callsite. The
lib consumes only the first `--` and forwards subsequent tokens
verbatim, so a stub that legitimately needs a `--` in its own `$@` is
unaffected.

## Canonical stub inventory

| Stub                       | Caller                        | New / convert          | Behavior on absent        |
|----------------------------|-------------------------------|------------------------|---------------------------|
| `post-create-worktree.sh`  | `create-worktree.sh` (end)    | NEW                    | no-op (worktree completes)|
| `dev-port.sh`              | `port.sh` (post env-override) | NEW                    | built-in algorithm        |
| `start-dev.sh`             | (consumer-invoked)            | NEW (failing stub)     | n/a (stub IS the file)    |
| `stop-dev.sh`              | (consumer-invoked, hook help) | CONVERT to failing stub| n/a (stub IS the file)    |
| `test-all.sh`              | run-plan / verify-changes     | CONVERT to failing stub| `command not found` → `exit 1` with message |
| `briefing-extra.sh`        | `briefing.cjs`                | DEFERRED (Phase 6)     | n/a                        |

### `dev-port.sh`

Override the worktree port-derivation algorithm. The callsite is in
`skills/update-zskills/scripts/port.sh`, **after** the `DEV_PORT` env-var
override and **before** the built-in main-repo / worktree-hash branches —
so the env var still wins, but the stub overrides the built-in.

**Arguments (positional):**

| Position | Name            | Description                                            |
|----------|-----------------|--------------------------------------------------------|
| `$1`     | `PROJECT_ROOT`  | absolute path of the current project root              |
| `$2`     | `MAIN_REPO`     | configured `dev_server.main_repo_path` (may be empty)  |

**stdout contract:** print a positive integer (matches
`^[1-9][0-9]+$` after whitespace trim) to stdout to use as the port. A
bare `0` is rejected (invalid TCP port).

**Exit-code behavior:**

- `exit 0` + numeric stdout → port returned as-is.
- `exit 0` + empty stdout → silent fall-through to built-in algorithm
  (no stderr warning).
- `exit 0` + non-numeric / invalid stdout → fall-through to built-in
  algorithm; stderr warning `zskills: dev-port.sh returned
  non-numeric/invalid stdout '<stdout>'; falling through to built-in`.
- `exit non-zero` → fall-through to built-in algorithm; the dispatcher
  (lib) emits `zskills: scripts/dev-port.sh exited <rc>`. Port
  resolution is upstream of every dev-server operation, so non-zero
  stub exits never break the user's workflow — they degrade gracefully
  to the built-in.

## Sourceable dispatcher

The dispatcher lives at
`skills/update-zskills/scripts/zskills-stub-lib.sh` (mirrored to
`.claude/skills/update-zskills/scripts/zskills-stub-lib.sh`). Callers
**source** the file (not exec) so the function executes in the caller's
shell and the `ZSKILLS_STUB_*` variables are visible after the call.

Production callers (other skills' scripts) source via
`$CLAUDE_PROJECT_DIR`:

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-stub-lib.sh"
```

Tests source via the absolute repo-root form:

```bash
. "$REPO_ROOT/skills/update-zskills/scripts/zskills-stub-lib.sh"
```

This keeps tests independent of `.claude/skills/` mirror state so
fresh `tests/run-all.sh` runs work without first running
`mirror-skill.sh`.

### Function source (verbatim)

```bash
#!/bin/bash
# zskills-stub-lib.sh -- sourceable dispatcher for consumer
# stub-callouts. See
# .claude/skills/update-zskills/references/stub-callouts.md.
#
# Usage:
#   source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-stub-lib.sh"
#   zskills_dispatch_stub <stub-name> <repo-root> -- arg1 arg2 ...
#
# Sets:
#   ZSKILLS_STUB_RC          - exit code from stub (or 0 if absent)
#   ZSKILLS_STUB_STDOUT      - captured stdout (or "" if absent)
#   ZSKILLS_STUB_INVOKED     - "1" iff the stub ran
zskills_dispatch_stub() {
  local name=$1
  local repo_root=$2
  shift 2
  [ "$1" = "--" ] && shift
  local stub="$repo_root/scripts/$name"
  ZSKILLS_STUB_RC=0
  ZSKILLS_STUB_STDOUT=""
  ZSKILLS_STUB_INVOKED=0
  if [ ! -e "$stub" ]; then
    return 0
  fi
  if [ ! -x "$stub" ]; then
    echo "zskills: scripts/$name present but not executable; ignoring (chmod +x to enable)" >&2
    return 0
  fi
  local notes_dir="$repo_root/.zskills/stub-notes"
  local marker="$notes_dir/$name.noted"
  if [ ! -f "$marker" ]; then
    # Suppress the note when marker write fails (e.g. read-only fs)
    # to avoid per-invocation noise on systems that can't persist.
    if mkdir -p "$notes_dir" 2>/dev/null && touch "$marker" 2>/dev/null; then
      echo "zskills: invoking consumer stub scripts/$name (one-time note; see .claude/skills/update-zskills/references/stub-callouts.md)" >&2
    fi
  fi
  ZSKILLS_STUB_INVOKED=1
  ZSKILLS_STUB_STDOUT=$(bash "$stub" "$@")
  ZSKILLS_STUB_RC=$?
  if [ "$ZSKILLS_STUB_RC" -ne 0 ]; then
    echo "zskills: scripts/$name exited $ZSKILLS_STUB_RC" >&2
  fi
  return 0
}
```

## When to add a new callout

A new consumer stub-callout is justified when:

- A zskills behavior has natural per-project variance that cannot be
  expressed via existing settings/env-vars (e.g. "which port to use for
  the dev server" — already covered by `dev-port.sh`).
- The default zskills behavior is correct for most projects, so the
  stub is opt-in (consumer adds the file to override).
- The customization point has a single, well-typed answer (a port
  number, a path, a numeric exit code) that fits the contract above.

When adding a new stub:

1. Pick a stable name (`<verb>-<noun>.sh`) and add a row to the
   canonical inventory table above with its caller, new/convert
   classification, and absent-behavior.
2. Implement the callsite using the sourceable dispatcher — never
   inline `bash scripts/<name>.sh`. If the dispatcher is missing
   (e.g. `update-zskills` not yet installed), emit a stderr warning
   and fall through to the built-in default.
3. Add tests in `tests/test-stub-callouts.sh` covering at minimum:
   absent, present-with-output, present-empty-stdout, non-executable,
   non-zero exit.
4. Document the new stub's positional arguments and stdout contract
   in this file.

## Related

- `skills/update-zskills/references/script-ownership.md` — Tier-1
  (skill-machinery) vs Tier-2 (consumer-customizable) classification.
  All stubs in the inventory are Tier-2.
- `feedback_no_jq_in_skills.md` — the dispatcher does no JSON parsing;
  bash regex only.
