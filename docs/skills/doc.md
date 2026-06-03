# /doc

> Audit and fix documentation gaps — block library entries, example models, getting-started guides, presentations, README updates — and write newsletter entries. Pick what to cover with an argument; behavior is content-only.

## What it does

`/doc` finds places where the project's documentation has fallen behind the code and fills them in. It knows where each kind of documentation lives and what a complete entry looks like, so it can spot a block that was added to the registry but never got an explorer blurb, an example model with no README or screenshots, or a README whose block and test counts are stale.

What it covers depends on the argument you give it. With no argument it scans recent commits and fixes the gaps it finds in that recent work. You can instead point it at a whole category — every block, or every example — for a comprehensive completeness audit, ask it to write a newsletter entry for recent work, or hand it a plain-English description of one specific thing to document. In every form the output is the documentation itself: new or updated explorer entries, example READMEs, screenshots, block-library entries, gallery entries, README and presentation edits. When it finishes, `/doc` prints a short summary of what it created and any gaps it left unfixed, with reasons.

The work is content-first. `/doc` matches the style and structure of the documentation already in the project rather than inventing new formats, and it keeps cross-references in sync — a new example also gets its explorer links and gallery entry, so nothing is left orphaned. Screenshots are taken from the real running app in the browser, not generated. If the documentation pass also touches code files (a registry, the component explorer, a docs registry), `/doc` runs the test suite before finishing; a pass that changed only markdown and images skips the tests.

## Typical usage

The most common starting point is the bare command, which audits whatever changed recently:

```
/doc
```

Point it at a category for a full audit, ask for a newsletter entry, or describe one specific documentation task:

```
/doc blocks
/doc examples
/doc newsletter
/doc the new thermal blocks
/doc update the presentation with recent results
/doc update README with current block count and test numbers
```

## Companion skills

- **`/manual-testing`** — the browser-setup helper `/doc` relies on when it captures example screenshots, so it can bypass the auth gate and drive the real app. (`/manual-testing` is a helper other skills use rather than one you type directly.)

## Arguments

`/doc` takes a single optional argument that selects what to document. The forms are mutually exclusive — give one, or none.

| Argument | Required | Description |
|----------|----------|-------------|
| (none) | No | Scan recent commits for new blocks, examples, and features that lack documentation, and fix those gaps |
| `blocks` | No | Comprehensive audit of every registered block against the block documentation checklist |
| `examples` | No | Comprehensive audit of every example model against the example documentation checklist |
| `newsletter` | No | Write a new entry in `NEWSLETTER.md` for recent work |
| `<description>` | No | Document the specific thing you describe in plain English (a feature area, a presentation update, a README refresh) |

With no argument, `/doc` reads recent commit history to find the new work that still needs documenting and fixes it. The `blocks` and `examples` forms instead sweep the entire catalog, checking each entry against a fixed checklist and reporting which ones are incomplete. `newsletter` writes a release-notes-style entry — leading with what the user gets, technical and factual, with one screenshot — at the top of the newsletter file. A free-form description tells `/doc` to document exactly that one thing, applying whichever checklists are relevant.
