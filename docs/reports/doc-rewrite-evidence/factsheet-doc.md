# Fact sheet — `docs/skills/doc.md`

Every factual claim in the rewritten `docs/skills/doc.md`, paired with the
verbatim source line that backs it. Format:
`doc sentence → skills/doc/SKILL.md:LINE: "<verbatim quoted text>"`.

---

## Header blurb

- Audits and fixes documentation gaps — block library, example models,
  getting-started guides, presentations, README updates — plus newsletter
  entries →
  skills/doc/SKILL.md:6: "  Audit and fix documentation gaps: block library entries, example models,"
  skills/doc/SKILL.md:7: "  getting-started guides, presentations, README updates. Also handles"
  skills/doc/SKILL.md:8: "  newsletter entries (/doc newsletter). Use when the user asks to \"write a"

- You pick what it covers with an argument →
  skills/doc/SKILL.md:4: "argument-hint: \"[blocks|examples|newsletter|<description>]\""

## "What it does" section

- `/doc` finds documentation that has fallen behind and fills it in →
  skills/doc/SKILL.md:16: "Finds documentation gaps and fills them. Can audit all blocks, all examples,"

- It knows where each kind of documentation lives and what complete looks like →
  skills/doc/SKILL.md:17: "or document a specific feature. Knows the project's documentation structure"
  skills/doc/SKILL.md:18: "and checklists for each type of documentation."

- It can spot a block registered but missing an explorer blurb →
  skills/doc/SKILL.md:166: "2. **Diff the lists** — which blocks are in the registry but missing"
  skills/doc/SKILL.md:167: "   from the component explorer or BLOCK_LIBRARY?"

- It can spot an example model with no README or screenshots →
  skills/doc/SKILL.md:188: "3. **Diff** — which directories lack README.md, screenshots/, or gallery"

- It can spot a README with stale block/test counts →
  skills/doc/SKILL.md:50: "- `/doc update README with current block count and test numbers`"

- No argument: scans recent commits and fixes those gaps →
  skills/doc/SKILL.md:32: "- No arguments: scan `git log` for recent blocks, features, and examples"
  skills/doc/SKILL.md:33: "  that lack documentation. Fix the gaps."

- Can audit a whole category — every block or every example →
  skills/doc/SKILL.md:34: "- `blocks`: comprehensive audit of all 121+ registered blocks against the"
  skills/doc/SKILL.md:36: "- `examples`: comprehensive audit of all 48+ example models against the"

- Can write a newsletter entry for recent work →
  skills/doc/SKILL.md:38: "- `newsletter`: write a NEWSLETTER.md entry for recent work."

- Can document one specific thing from a plain-English description →
  skills/doc/SKILL.md:39: "- Free-form description: document the specific thing described (e.g.,"

- Output is the documentation itself: explorer entries, example READMEs,
  screenshots, block-library entries, gallery entries, README/presentation edits →
  skills/doc/SKILL.md:294: "Created:"
  skills/doc/SKILL.md:295: "  - Explorer entries: 3 (Mass, Spring, Damper)"
  skills/doc/SKILL.md:296: "  - Example models: 1 (free-vibration/)"
  skills/doc/SKILL.md:297: "  - Example READMEs: 1"
  skills/doc/SKILL.md:298: "  - Screenshots: 4"
  skills/doc/SKILL.md:299: "  - BLOCK_LIBRARY entries: 3"
  skills/doc/SKILL.md:300: "  - Gallery entries: 1"

- Prints a short summary of what it created and remaining gaps with reasons →
  skills/doc/SKILL.md:291: "Summarize what was documented:"
  skills/doc/SKILL.md:303: "Remaining gaps:"
  skills/doc/SKILL.md:304: "  - [list any unfixed gaps with reasons]"

- Matches existing style/format rather than inventing new formats →
  skills/doc/SKILL.md:309: "- **Follow existing conventions** — match the style, format, and structure"
  skills/doc/SKILL.md:310: "  of existing documentation. Don't invent new formats."

- Keeps cross-references in sync; nothing left orphaned →
  skills/doc/SKILL.md:315: "- **Update all cross-references** — a new example needs entries in"
  skills/doc/SKILL.md:317: "  explorer entries. Don't create orphaned docs."

- Screenshots are real browser captures, not generated →
  skills/doc/SKILL.md:313: "- **Screenshots via playwright-cli** — real browser screenshots, not"
  skills/doc/SKILL.md:314: "  generated images. Use `/manual-testing` setup for auth bypass."

- Runs the test suite if code files were touched →
  skills/doc/SKILL.md:318: "- **`$FULL_TEST_CMD` before committing** (resolve via the dual-lane prelude in"
  skills/doc/SKILL.md:320: "  your environment) if code files were touched."

- Content-only changes skip the test suite →
  skills/doc/SKILL.md:321: "- **Content-only changes skip tests** — if only markdown/images were"
  skills/doc/SKILL.md:322: "  changed, no test run needed."

## "Typical usage" section

- Bare command audits whatever changed recently →
  skills/doc/SKILL.md:25: "/doc                      — audit recent changes for missing docs"

- Example invocation shapes →
  skills/doc/SKILL.md:43: "Examples:"
  skills/doc/SKILL.md:44: "- `/doc` — what's missing since last commit?"
  skills/doc/SKILL.md:45: "- `/doc blocks` — which blocks lack explorer entries, examples, or docs?"
  skills/doc/SKILL.md:46: "- `/doc examples` — which examples lack READMEs or screenshots?"
  skills/doc/SKILL.md:47: "- `/doc newsletter` — write a newsletter entry for recent features"
  skills/doc/SKILL.md:48: "- `/doc the new thermal blocks`"
  skills/doc/SKILL.md:49: "- `/doc update the presentation with recent results`"
  skills/doc/SKILL.md:50: "- `/doc update README with current block count and test numbers`"

  (Note: USAGE_MAP.md lists `/doc` under "Never observed in the `Run /<skill>`
  cron form" — it is not cron-driven in the sample, so typical-usage examples
  are drawn from the skill's own Examples block per R7, not from the usage map.)

## "Companion skills" section

- `/manual-testing` is the companion →
  source: COMPANIONS.md per-skill graph, `doc` row:
  "`doc` | `manual-testing` | Content/documentation skill; references
  `/manual-testing` for UI doc verification."
  Backed in source by →
  skills/doc/SKILL.md:314: "  generated images. Use `/manual-testing` setup for auth bypass."

- `/manual-testing` is a helper used by other skills rather than typed directly →
  source: COMPANIONS.md "Peer families": "Internal (typed directly won't work):
  `land-pr` (today); `manual-testing` joins once #1012 merges." (Stated as a
  plain "helper other skills use" clause; no internal-issue-number leaked per R5.)

## "Arguments" section

- Single optional argument selecting what to document; forms are mutually exclusive →
  skills/doc/SKILL.md:4: "argument-hint: \"[blocks|examples|newsletter|<description>]\""
  skills/doc/SKILL.md:24: "```"
  skills/doc/SKILL.md:25-29 (the `/doc` argument grid, one form per line)

- (none) → scan recent commits for undocumented new work and fix it →
  skills/doc/SKILL.md:32: "- No arguments: scan `git log` for recent blocks, features, and examples"
  skills/doc/SKILL.md:33: "  that lack documentation. Fix the gaps."

- `blocks` → comprehensive audit of every block against a checklist →
  skills/doc/SKILL.md:35: "  block documentation checklist."

- `examples` → comprehensive audit of every example against a checklist →
  skills/doc/SKILL.md:37: "  example documentation checklist."

- `newsletter` → write a new entry in NEWSLETTER.md for recent work →
  skills/doc/SKILL.md:197: "Write a new entry for `getting-started/NEWSLETTER.md`. Newest entries go"
  skills/doc/SKILL.md:198: "at the top, right after the intro paragraph and `---` separator."

- newsletter entry leads with what the user gets, technical/factual, one screenshot →
  skills/doc/SKILL.md:213: "  - **Opening sentence:** lead with what the user gets, not what was"
  skills/doc/SKILL.md:218: "  - **Screenshot:** one image per entry showing the feature in its"
  skills/doc/SKILL.md:239: "7. **Tone:** technical and factual, written for developers. Read like"

- `<description>` → document exactly that one thing, applying relevant checklists →
  skills/doc/SKILL.md:242: "**Free-form description:**"
  skills/doc/SKILL.md:244: "2. Identify which checklists apply"

---

## Verification notes

- Banned-term scan is clean:
  `grep -nEf docs/reports/doc-rewrite-evidence/banned-terms.txt docs/skills/doc.md`
  returns no hits.
- `/model-design` is referenced in skills/doc/SKILL.md:311 and :256 but is NOT a
  real skill under `skills/` (it is a consumer-specific reference), so per R6 it
  is deliberately omitted from the companion-skills section — COMPANIONS.md's
  `doc` row lists only `manual-testing`.
- `/doc` has no landing modes (no worktree/PR/direct axis), no triage redirect,
  and no cron subcommands — so R4 (modes-as-thin-axis) and the mode narration
  are not applicable; the only axis is the single argument selecting scope.
