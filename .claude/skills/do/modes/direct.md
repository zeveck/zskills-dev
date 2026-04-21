# /do — Direct Mode (Path C)

Work directly on main; the verification agent commits after tests pass, one logical unit per commit.
### Path C: Direct (`LANDING_MODE="direct"`)

Selected when the user passes `direct` explicitly, when `execution.landing`
in `.claude/zskills-config.json` is `"direct"`, or as the fallback when
no config is present. Work directly on main.

**Follow existing conventions in all paths:**
- Example models → `/model-design` skill guidelines
- Newsletter entries → existing NEWSLETTER.md format
- Documentation → existing doc style in the repo
- Code → existing patterns in the codebase

**Commit discipline (Paths B and C):**
- **On main (Path C):** commit when the work is complete. Clean, descriptive
  message. `npm run test:all` before committing if code was touched.
  If tests fail after two fix attempts on the same error, STOP — report
  what you tried and let the user decide.
- **In worktree (Path B):** the verification agent commits after tests pass.
  One logical unit per commit.

