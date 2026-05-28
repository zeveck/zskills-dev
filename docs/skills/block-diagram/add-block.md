# /add-block

> Step-by-step guide for adding new block types. Use when the user asks to "add a block", "create a new block", or "implement a block".

## Usage

```
/add-block
```

No arguments -- the skill guides you through the interactive workflow after you provide the block name.

## Workflow

All implementation happens in a pre-created worktree (set up via `ensure-worktree.sh`). Every new block must complete all steps (0--12). Steps 0--10 are the implementation workflow; steps 11--12 are verification and landing:

0. **Pre-flight: Check for a Plan** -- look for an existing plan file under `plans/blocks/{category}/`; if none, spawn an Explore agent to research the block and write a plan (9 required sections) before proceeding
1. **Runtime Implementation** -- create the block class file in `src/engine/blocks/{category}/{Name}Block.js`
2. **Runtime Registration** -- register the block class in `src/engine/blocks/register/{category}.js`
3. **UI Definition** -- add a block definition in `src/library/block-registry.js` (plus face text and dynamic ports if needed)
4. **Block library panel Data** -- add an entry in `src/library/block-explorer-data.js`
5. **Documentation Issues** -- do NOT write docs yourself; create GitHub tracking issues and add entries to `DOC_ISSUES.md`
6. **Unit Tests** -- add tests in `tests/blocks/{category}.test.js` covering metadata, output, and defaults
7. **Example Model** -- delegate to `/add-example` to build a real-world model showcasing the block(s)
8. **Rust Code Generation** -- add a Rust emitter in `src/codegen/block-emitter.js` (and runtime support where feasible)
9. **Manual Testing** -- use `/manual-testing` with `playwright-cli` to verify the block end-to-end in the browser
10. **Completion Report** -- write `new-blocks-{slug}.md` for user review, then run the mandatory Step 10b self-audit
11. **Verification (separate agent)** -- dispatch a fresh verification agent (or run `/verify-changes` inline) against the worktree
12. **Land** -- cherry-pick worktree commits to main (do NOT auto-land if UI sign-off checkboxes remain unchecked)

## Examples

```
/add-block
```

Then provide the block name when prompted (e.g., "PID Controller", "Integrator", "Derivative").

## Common Patterns

- **Single block:** `/add-block` then specify one block type
- **Batch mode:** add multiple blocks at once -- per-block work (steps 0--6, 8) runs for each block, while the example model (step 7) is built once for the whole group after all blocks are implemented
- **After adding:** use `/add-example` to create additional example models for the new block

## Tips & Gotchas

- All 13 steps (0--12) must be completed -- no partial implementations; steps 0--10 are implementation, 11--12 are verification and landing
- The implementation agent runs in a worktree with `FIRST: cd $WORKTREE_PATH` as a mandatory first action
- Step 5 creates documentation tracking issues rather than writing docs inline; step 7 delegates the example model to `/add-example`
- Step 10b is a mandatory self-audit with a tracking-file gate -- do not proceed past it without all step markers present
- The worktree is created via `ensure-worktree.sh`, not manual `git worktree add`
