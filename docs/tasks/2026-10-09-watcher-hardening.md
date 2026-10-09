# Task: watcher hardening (close auto-approve bypasses)

**Assigned to:** agy  **Lead / reviewer:** claude  **Second review:** codex (read-only)
**Branch:** `feat/watcher-hardening`  **Worktree:** `../agent-notepad-wt-agy`

## Goal
`scripts/watch-agent.sh` auto-approves commands that `is_safe` calls read-only. Today several dangerous commands
pass as "safe". After this task every one of them waits for a human, and every currently-safe case stays safe.

## Files you may touch (nothing else)
- `scripts/watch-agent.sh`
- `scripts/collab.sh` (only the `valid()` function)
- `tests/run.sh`
- `docs/appendix.md` (section F only: describe the new rules in one or two bullets)

## Runtime boundary
Pure bash 3.2+ (macOS default) and BSD/GNU sed+grep. No new tools. `is_safe` is unit-tested by sourcing the script
with `WATCH_AGENT_LIB=1`; the end-to-end test uses a fake agent in tmux (see the bottom of `tests/run.sh`).

## Test cases (add to tests/run.sh first, watch them fail, then implement)
Under "watcher rules", these must be `unsafe` (need a human):
1. `ls & rm -rf build`            — a lone `&` (background / chain). Any `&` that is not `&&` and not part of `2>&1`.
2. `ls "$(rm -rf build)"`         — `$(…)` inside DOUBLE quotes still runs. Only single-quoted text is inert.
3. ``ls "`rm -rf build`"``        — same for backticks inside double quotes.
4. `cat <(rm -rf build)`          — process substitution; also block any `<` outside single quotes.
5. `rg --pre ./x.sh pat` and `rg --pre=./x.sh pat` — rg runs the preprocessor.
6. `git grep -O x` and `git grep --open-files-in-pager x` — runs a pager program.
7. `git diff --ext-diff` and `git log -p --ext-diff` — runs an external diff program.
8. `find . -fls out`              — writes a file.
9. A command containing a newline, e.g. `$'ls\nrm -rf build'` — multi-line is never auto-approved.

These must stay `safe`:
10. `grep -rn "a & b" src`   (quoted `&`)
11. `echo 'costs $(5)'`      (single-quoted `$(` is literal)
12. `ls x 2>&1`
13. every case already marked `safe` in the file.

Wrapped commands (end-to-end, tmux): the watcher currently reads only ONE line after the prompt marker, so a long
command that wraps on screen is judged by its first line only.
14. Add a second fake-agent run whose prompt prints the command over two lines:
    `   ls src` then `   && rm -rf build`. The watcher must stop with `PROMPT (needs decision)` and must NOT type an
    option. Implement by collecting every line after `CMD_AFTER` up to (not including) the first blank line or the
    first line that is a question (`?` at end) or an option (`^[> ]*[0-9]+\.`), joined with newlines, so case 9's
    rule sends it to a human. Keep the single-line case (existing e2e test) working.

collab.sh:
15. `scripts/collab.sh post "claude agy" all hi` must be rejected (exit 2). Today a multi-word name passes `valid()`.
    Names must be one word and exactly in the list.

## Done when
- [ ] All cases above pass; `tests/run.sh` passes 3 runs in a row.
- [ ] `bash -n` clean on every script you touched. Comments match the existing terse style.
- [ ] Commit on `feat/watcher-hardening` (no push).
- [ ] `scripts/collab.sh handoff agy claude "feat/watcher-hardening · <done> · <test result> · <anything unsure>"`
- [ ] `scripts/collab.sh release agy`

## Don'ts
- No new dependencies. No changes outside the file list. No background commands. One command per call.
- Don't loosen any existing rule to make a test pass. When unsure, send it to a human.
