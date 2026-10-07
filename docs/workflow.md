# The lead pattern

## Why one lead instead of peers
Peers that all plan, all edit and all review need a lot of coordination, and you end up as the switchboard. With
one lead, you talk to one agent. The lead turns your intent into specs, hands them out, holds the quality bar,
and comes back with a PR and a short summary. You make the decisions only you can make: priorities, anything
that needs a password, and "ship it".

| Role | Does | Never does |
|---|---|---|
| **Owner (you)** | priorities, secrets, approvals, "deploy" | relay messages between agents |
| **Lead** (e.g. Claude Code) | plan, specs, assign, review, integrate, run the full suite, PR, deploy on your word | merge unreviewed work; touch a branch a builder has claimed |
| **Builder** (e.g. Antigravity) | one spec at a time in its own worktree: tests first, code, handoff | push, merge, deploy, edit outside the spec's file list |
| **Reviewer** (e.g. Codex) | read-only review or audit of a diff or a module | edit anything (unless explicitly given a build task) |

Pick roles by **strength and plan limits**: the tool on the most generous plan builds; a different model family
reviews, because it misses different things than the builder and the lead.

## One task, end to end
```
lead:    writes docs/tasks/<date>-<name>.md   (goal · files · runtime boundary · numbered test cases · done-when)
lead:    collab.sh post claude agy "TASK: … branch feat/x, worktree ../repo-wt-agy"
lead:    tmux send-keys -t agy "Read AGENTS.md, then do docs/tasks/…" Enter
lead:    scripts/watch-agent.sh agy agy claude 40 &      (lead sleeps; watcher wakes it)
builder: collab.sh claim agy "feat/x · <files>"
builder: failing tests → code → full suite → commit
builder: collab.sh handoff agy claude "feat/x · done · 57 tests pass · unsure about X"
builder: collab.sh release agy
lead:    git diff main...feat/x --stat           (only the spec's files?)
lead:    read the diff; feedback → post + tmux nudge; repeat
lead:    codex exec --sandbox read-only -o review.txt "Review git diff main...feat/x …"
lead:    triage findings (fix / accept with reason / ask owner); full suite; PR
owner:   "merge" / "deploy"
```

## Running work in parallel
- **Split by files, not by idea.** Two agents may work at once if their claims don't overlap. If they must share a
  file, one writes the code and the other only the tests.
- **Leave seams.** The builder leaves `// HOOK: … (wired by lead)` where the two pieces meet; integration is a one-line change.
- **Audit in parallel with building.** While the builder works on A, the reviewer audits module B read-only and the
  lead triages the findings into fixes.

## Writing specs that finish fast
Measured in the pilot: a loose spec meant ~25 minutes of exploring before the first line of code; a tight one
(exact file, exact mocks, numbered cases, "full suite 3 runs in a row") meant ~40 minutes total with no nudges.
Always include:
- the **exact files** the builder may touch;
- the **runtime boundary** (server / browser / build time) for each piece;
- **numbered test cases**, including edge cases and, for refactors, exact-text tests from the old version (`git show main:<file>`);
- the **done-when** checklist ending with `handoff` and `release`.

## Prompts that worked
**Codex audit (read-only):**
```text
Audit <module/paths> read-only. For each finding: file:line, the quoted line, a concrete input that breaks it,
and severity. Concerns: auth on every entry point, input validation (lengths, numbers ≥ 0, dates), ownership checks,
upload type/size limits, error messages leaking data, missing tests. Max 25 findings, no style nits.
```

**Codex review of a branch:**
```text
Review `git diff main...feat/x` for bugs only. Quote the line and give a concrete failing input. If nothing is
wrong, say "No issues found". Max 10 findings.
```

**Nudging an over-exploring builder:**
```text
You've explored enough. Write the failing tests from the spec now, using file tools. One command per call.
```

**Asking an agent about itself:**
```text
Do not use any tools. Which model are you running, and what is your context window?
```
