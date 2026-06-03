# How tracking keeps pipelines safe

zskills skills like `/run-plan`, `/fix-issues`, and `/research-and-go` work in
several stages: an agent writes code, a separate agent verifies it, and only
then does the work land. "Tracking" is the mechanism that makes those stages
mandatory. It does two jobs for you:

- **It stops unverified code from landing.** A skill that writes code but skips
  the verification step cannot commit, cherry-pick, or push that code — a git
  hook blocks the operation until verification has actually run.
- **It keeps concurrent pipelines from stepping on each other.** Two skills
  running at once each have their own tracking state, so one pipeline's
  half-finished work never blocks the other's commit.

You normally never touch any of this. The skills set it up, the hook enforces
it, and it cleans itself up when a pipeline finishes. This page explains what
you'd see if you ever ran into it.

## What you'd observe

Tracking is invisible until something is out of order. When it does fire, you
see a `BLOCKED:` message from the git hook explaining what is missing. The two
most common ones:

```
BLOCKED: Required skill invocation 'verify-changes.<pipeline>' not yet
fulfilled. Invoke the required skill via the Skill tool.
```

This means a pipeline declared that verification must run before its code can
land, and verification has not happened yet. If the pipeline is still running,
this clears on its own once the verification agent finishes.

```
BLOCKED: <pipeline> has implementation but no verification. Run verification
before committing.
```

This means code was implemented but the verification stage never recorded that
it ran. Same cause, same resolution: let the verification step complete, or
clear stale state (below) if a pipeline crashed and left markers behind.

A commit, cherry-pick, or push that touches **only** non-code files (markdown,
images, and similar) is exempt — tracking checks are skipped for content-only
changes.

## When tracking applies to you

The hook only enforces tracking when your session is part of a running
pipeline. It decides that two ways:

- **Inside a worktree:** the skill writes a small `.zskills-tracked` file at the
  worktree root naming the pipeline. If that file is present, the session is
  part of that pipeline.
- **On the main checkout:** the skill prints a `ZSKILLS_PIPELINE_ID=<id>` line
  early in the session, which the hook reads back from the session transcript.

If neither is present, the hook treats your session as unrelated to any pipeline
and skips enforcement entirely. That is why an ordinary commit you make by hand,
or an unrelated agent in another session, can commit freely even while a
pipeline is mid-run.

## Where the markers live

Tracking markers are small text files under `.zskills/tracking/` in your
project. They are grouped into one subdirectory per pipeline, named after that
pipeline's ID:

```
.zskills/tracking/
  run-plan.thermal-domain/
    requires.draft-plan.thermal-domain     # a skill that must be invoked
    fulfilled.draft-plan.thermal-domain    # recorded once that skill ran
    step.phase2.implement                  # implementation started
    step.phase2.verify                     # verification ran
    step.phase2.report                     # report written — commit now allowed
```

The per-pipeline subdirectory is what keeps pipelines isolated: two pipelines
live in two different directories, so the hook checking one pipeline's
commit never sees the other pipeline's markers. If a second pipeline runs at the
same time, it simply gets its own directory:

```
.zskills/tracking/
  run-plan.thermal-domain/      # one pipeline
    ...
  fix-issues.sprint-20260417-152301-foobar/   # another, fully isolated
    ...
```

`.zskills/` is not committed to git — these markers are short-lived process
state, not part of your project's history.

The marker files themselves are plain key-value text recording which skill
created them and when, so you can read them directly if you ever need to see
what a pipeline is waiting on.

## When the checks run

The hook applies the same tracking checks at three points where code could
otherwise reach a branch — `git commit`, `git cherry-pick`, and `git push`. At
each, if your session belongs to a pipeline and the change includes code files,
the hook looks for unfulfilled requirements or an implementation that was never
verified, and blocks the operation if it finds one. (Separately, when your
project sets `main_protected: true`, the hook also refuses any commit,
cherry-pick, or push directly to `main` — that is a different rule from
tracking, but you may see both kinds of `BLOCKED:` message.)

## Clearing stale tracking

If a pipeline crashes or is interrupted, it can leave markers behind that block
later commits in that same pipeline. Clearing them is a user-only action — the
hook deliberately blocks agents from running the cleanup script, so you run it
yourself:

```
! bash .claude/skills/update-zskills/scripts/clear-tracking.sh
```

The leading `!` runs it as you rather than as the agent. The script lists every
tracking file with its contents, asks you to confirm, and only then removes
them. For the same safety reason, the hook also refuses any recursive delete
that reaches inside `.zskills/` — so an agent cannot wipe the tracking tree (or
the audit and issues state that lives alongside it) by accident.

## Related concepts

- **`.landed`** is *not* a tracking marker. It is a separate file written at a
  worktree's root after that worktree's commits are confirmed on `main`, used by
  cleanup tools to tell which worktrees are safe to remove. It does not affect
  commit gating.
- **Claiming work items** is a related but distinct mechanism: before a pipeline
  works an issue or plan, it claims it so two pipelines don't pick up the same
  item. That is separate from the commit-gating tracking described here.
