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

## Round 2 (review feedback from claude + codex)
Stripping single quotes and then double quotes with `sed` is wrong whenever one kind of quote sits inside the
other. These all pass `is_safe` today and must need a human (`main` already rejects the `;` one, so this is a regression):
16. `ls "'" ; rm -rf build "'"`
17. `ls "'" & rm -rf build "'"`
18. `ls "'" > out "'"`
19. `ls "it's" $(rm -rf build) 'x'`
20. `cat ~/.ssh/id_ecdsa` and `cat ~/.ssh/id_*` — treat `id_` followed by letters/digits/`*`, and anything under `.ssh/`, as secret.
21. A backslash outside single quotes (`ls a\;rm`) and an unterminated quote (`ls "abc`) → human.

Fix: replace the sed-based quote stripping with ONE left-to-right scanner in bash (a `while` loop over `${s:i:1}`)
that tracks the quote state (none / single / double):
- inside single quotes: everything is literal;
- inside double quotes: a backtick or `$(` → human;
- outside quotes: a backtick, `$(`, `<`, `>`, a lone `|` or `&`, or a backslash → human, except the exact tokens
  `2>/dev/null` and `2>&1`; `;`, `&&` and `||` split parts; quoted text becomes `Q` in the part text;
- ending inside a quote → human.
Then check each part against SAFE_RE and the dangerous-flag rules, as now. All 57 existing tests must still pass,
including `grep -rn "a|b" src`, `grep -rn "a & b" src` and `echo 'costs $(5)'` staying safe.
Commit, then handoff + release again.

## Round 3 (review feedback from claude; codex found nothing new)
The dangerous-flag checks run on the part text where quoted words became `Q`, so a quoted flag is invisible to
them. Confirmed by running: `git diff "--output=written.txt"` writes a file and `find . -name x '-delete'` deletes.
These exist on `main` too. All must need a human:
22. `git diff "--output=/tmp/x"`
23. `find . -name x '-delete'`
24. `rg "--pre=./x.sh" pat`
25. `git branch "-D" main`
26. `find . -name x -exe"c" rm {} ;`
27. `find . $'\x2ddelete'`        — `$'…'` / `$"…"` quoting
28. `find . -name v -{delete,print}` — brace expansion
29. `ls "${x:=/tmp/marker}"` and `ls $HOME` — any `$` outside single quotes, except `$` immediately before a closing
    double quote or at the end of a word inside double quotes (keep `grep -rn "foo$" src` safe: add it as a safe case).

Fix: in the scanner keep TWO texts per part: the masked text (quoted text → `Q`, used for structure, as now) and
a literal text (quote characters removed, quoted contents kept). Run SAFE_RE on the masked text and the
dangerous-flag regex on the literal text. Outside quotes, `{`, `}` and a `$` → human. Inside double quotes, `$`
followed by a letter, `_`, `{` or `(` → human. All 65 existing tests must still pass. Commit, then handoff + release.

## Round 4 (review feedback from claude + codex)
git's own option parser accepts abbreviated long options for `git branch` and `git grep`. Confirmed by running:
`git branch --del keep` deletes a branch. These must need a human:
30. `git branch --del x`, `git branch newbranch`, `git branch -u origin/x`, `git branch --edit-description`
    — only allow-list read-only forms: `git branch` followed only by any of `--show-current --list -a -r -v -vv
    --all --remotes --verbose` (or nothing). Everything else → human. Replaces the current `git branch` deny rule.
31. `git grep --open x` and `git grep --op x` — block any `--op…` prefix (keep `git grep --or` safe; add it as a safe case).
32. `tail -f log`, `tail -F log`, `tail --follow log` — never returns.
Keep: `git branch --show-current` and `git branch -a` safe (add `-a` as a safe case).
Also add one line to docs/appendix.md section F: `git diff/log/show` still run any textconv / external-diff program
configured in git config; the watcher cannot see that.
All 75 existing tests must still pass. Commit, then handoff + release.
