# Fact sheet — `docs/skills/plans.md`

Every factual claim in the rewritten `docs/skills/plans.md`, paired with the
verbatim source line that backs it. Format:
`doc sentence → skills/plans/SKILL.md:LINE: "<verbatim quoted text>"`.
Companion/usage citations use `COMPANIONS.md:LINE` / `USAGE_MAP.md:LINE`.

R5 note: the rewrite strips the implementer-voice internals present in the
prior doc — "Phase 4 Python aggregator (`collect.py`)", "the aggregator is the
canonical classifier", "this skill is a thin renderer", `render-index`, and
"idempotent". `grep -nEf banned-terms.txt docs/skills/plans.md` returns no hits.

---

## "What it does" section

- `/plans` is a read-only dashboard over your plan files →
  skills/plans/SKILL.md:12: "# /plans [rebuild | next | details] — Plan Dashboard"

- It is read-only / never changes plan files →
  skills/plans/SKILL.md:368: "- **Never modify plan files** — the index is read-only metadata. It"

- It only reads plans to build the dashboard →
  skills/plans/SKILL.md:369: "  reads plans (via the aggregator) but never changes them."

- Shows which plans exist with classification, status, and priority →
  skills/plans/SKILL.md:14: "Maintains `$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md` — a structured index of all plan files with"

- (cont.) classification, status, and priority →
  skills/plans/SKILL.md:15: "their classification, status, and priority."

- The plain `/plans` view displays the current index →
  skills/plans/SKILL.md:19: "- **bare** `/plans` — display the current index (highlights top-priority ready plan)"

- It highlights the top-priority ready plan with a suggested `/run-plan` command →
  skills/plans/SKILL.md:181: "   the top-priority ready plan with a suggested `/run-plan` command. The"

- It groups plans into sections (Ready to Run, In Progress, Needs Review, Complete, Canaries, Reference) →
  skills/plans/SKILL.md:89: "| Section | Selector |"
  (section names: skills/plans/SKILL.md:91 "Ready to Run", :92 "In Progress", :93 "Needs Review", :94 "Complete", :95 "Canaries", :96 "Reference (not executable)")

- Plans in progress show how far along they are (e.g. four of eight phases done) →
  skills/plans/SKILL.md:169: "     FEATURE_PLAN.md                  Phase 4b   4/8 done"

- It refreshes automatically whenever plans have changed, so status is never stale →
  skills/plans/SKILL.md:107: "   against `$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md`'s mtime. If the index is"
  skills/plans/SKILL.md:108: "   missing OR the source is newer, **auto-run Mode: Rebuild** before"

- (cont.) no staleness warning because the auto-refresh guarantees current source →
  skills/plans/SKILL.md:109: "   reading. There is no staleness warning — the source-staleness check"
  skills/plans/SKILL.md:110: "   guarantees the index reflects current source on every Mode: Show"

- If it can't read your plans, it reports the error and stops →
  skills/plans/SKILL.md:77: "If `python3` is missing, the module fails to import, or the CLI exits"
  skills/plans/SKILL.md:78: "non-zero, every mode below reports the error to the user verbatim and"
  skills/plans/SKILL.md:79: "exits non-zero. **There is no bash fallback** — the prose classifier was"

## "Typical usage" section

- Bare `/plans` surveys the landscape / displays the dashboard →
  skills/plans/SKILL.md:19: "- **bare** `/plans` — display the current index (highlights top-priority ready plan)"

- `/plans next` prints the highest-priority ready plan with its `/run-plan` command →
  skills/plans/SKILL.md:21: "- **next** `/plans next` — show the highest-priority ready-to-run plan with command"

- (cont.) the next-mode output includes the exact run command →
  skills/plans/SKILL.md:344: "   > Run with: `/run-plan plans/EXAMPLE_PLAN.md`"

- `/plans details` lists every plan with a one-line description →
  skills/plans/SKILL.md:22: "- **details** `/plans details` — show every plan with a one-line description"

- (cont.) details is useful when you have many plans and can't remember each →
  skills/plans/SKILL.md:198: "when you have many plans and can't remember what each one is about."

- `/plans rebuild` forces a rescan; you don't normally need it by hand →
  skills/plans/SKILL.md:20: "- **rebuild** `/plans rebuild` — scan all plans, classify, regenerate"

- Review the queue with `/plans`, then run via `/run-plan` or `/work-on-plans` →
  skills/plans/SKILL.md:23: "- **For batch execution:** see `/work-on-plans`."

- `/plans` is realistically invoked bare / low-ceremony (usage shape) →
  USAGE_MAP.md:56: "| `/plans` | 7 |"
  USAGE_MAP.md:131: "\"typical usage\" examples from the skill's own `argument-hint` + body and"
  (per R7 / USAGE_MAP guidance, `/plans` argument shapes are pulled from the
  SKILL.md body + argument-hint, not from the low cron count)

## "Companion skills" section

- Companions are `/run-plan`, `/work-on-plans`, `/zskills-dashboard`; relationship →
  COMPANIONS.md:88: "| `plans` | `run-plan`, `work-on-plans`, `zskills-dashboard`, `update-zskills` | The plan-catalog index; `/work-on-plans` and `/run-plan` consume the queue it builds. |"

- `/run-plan` executes one plan; `/plans next` hands you its command →
  skills/plans/SKILL.md:21: "- **next** `/plans next` — show the highest-priority ready-to-run plan with command"
  skills/plans/SKILL.md:344: "   > Run with: `/run-plan plans/EXAMPLE_PLAN.md`"

- `/work-on-plans` runs the ready plans in a batch; check `/plans` first →
  skills/plans/SKILL.md:23: "- **For batch execution:** see `/work-on-plans`."

- `/draft-plan` produces plan files that `/plans` then surfaces →
  COMPANIONS.md:81: "| `draft-plan` | `run-plan` (next step), `refine-plan`, `research-and-plan`, `research-and-go`, `do`, `quickfix`, `plans`, `create-worktree` | Produces a plan file `/run-plan` executes; `/refine-plan` adjusts it mid-flight. |"

- `/zskills-dashboard` is the interactive status UI; `/plans` ranking is independent of it →
  skills/plans/SKILL.md:186: "   > Note: this ranking is independent of the monitor dashboard's Ready"
  skills/plans/SKILL.md:187: "   > queue. For interactive prioritization, open /zskills-dashboard."
  (COMPANIONS edge: COMPANIONS.md:99: "| `zskills-dashboard` | `work-on-plans`, `create-worktree`, `update-zskills` | The status UI for in-flight pipelines; reads what `/work-on-plans` and others write. |")

## "Arguments" section

- Argument-hint lists the three optional modes →
  skills/plans/SKILL.md:4: "argument-hint: \"[rebuild | next | details]\""

- No-args displays the dashboard, highlighting top-priority ready plan →
  skills/plans/SKILL.md:19: "- **bare** `/plans` — display the current index (highlights top-priority ready plan)"

- `rebuild` rescans, reclassifies, regenerates →
  skills/plans/SKILL.md:20: "- **rebuild** `/plans rebuild` — scan all plans, classify, regenerate"

- `next` shows the highest-priority ready-to-run plan with command →
  skills/plans/SKILL.md:21: "- **next** `/plans next` — show the highest-priority ready-to-run plan with command"

- `details` shows every plan with a one-line description, grouped by status →
  skills/plans/SKILL.md:22: "- **details** `/plans details` — show every plan with a one-line description"
  skills/plans/SKILL.md:218: "3. Display grouped by status (Ready, In Progress, Complete, Canaries,"

## "Tips & gotchas" section

- You rarely need `/plans rebuild`; bare `/plans` refreshes itself →
  skills/plans/SKILL.md:190: "No 24-hour staleness warning is emitted — Step 1's source-staleness"
  skills/plans/SKILL.md:191: "auto-rebuild guarantees the index is never stale at display time. If"

- Canaries are a count, never promoted into Ready / In Progress →
  skills/plans/SKILL.md:182: "   Canaries count comes from the index's Canaries section; never promote"
  skills/plans/SKILL.md:183: "   a canary into Ready/In Progress in the dashboard view."

- Canary state is tracker bookkeeping, not actual run history →
  skills/plans/SKILL.md:174: "   Canaries: 6 total (tracker state — not actual run history)"

- To run plans (not just view), use `/run-plan` or `/work-on-plans` →
  skills/plans/SKILL.md:23: "- **For batch execution:** see `/work-on-plans`."
