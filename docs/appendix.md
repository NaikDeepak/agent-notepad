# Appendix

You don't need any of this for normal use: install, then talk to Claude Code. This page is for when you want to
know what's happening underneath, change the setup, or fix something.

- [A. What the install added](#a-what-the-install-added)
- [B. Using other names or roles](#b-using-other-names-or-roles)
- [C. What Claude does for each task](#c-what-claude-does-for-each-task)
- [D. Doing it by hand](#d-doing-it-by-hand)
- [E. Permissions](#e-permissions)
- [F. Safety rules built in](#f-safety-rules-built-in)
- [G. Command reference](#g-command-reference)
- [H. Troubleshooting](#h-troubleshooting)
- [I. Repository layout](#i-repository-layout)

## A. What the install added

`install.sh` never overwrites anything; running it twice changes nothing.

| File in your project | What it is |
|---|---|
| `scripts/collab.sh` | the notepad script all agents write through |
| `scripts/watch-agent.sh` | the tmux watcher that approves safe commands |
| `scripts/prices.tsv` | token prices per model, used by `collab.sh cost` |
| `AGENTS.md` | the shared protocol (Codex and Antigravity read this file automatically) |
| `CLAUDE.md` | the lead instructions: how Claude starts agy, sends tasks, watches, reviews |
| `GEMINI.md` | a pointer to `AGENTS.md` |
| `docs/tasks/_template.md` | the spec template Claude fills for each task |
| `.gitignore` | adds `.collab/`, so the notepad never gets committed |

Commit them: `git add -A && git commit -m "chore: add agent-notepad"`.

## B. Using other names or roles

The defaults are `claude` (lead), `agy` (builder), `codex` (reviewer) and `human` (you). To change them:

1. Edit the table at the top of the protocol in `AGENTS.md`.
2. Set the valid names, either in `scripts/collab.sh`:
   ```bash
   AGENTS="${COLLAB_AGENTS:-claude agy codex human}"
   ```
   or with `export COLLAB_AGENTS="claude agy codex alice"` in your shell profile. `all` is always valid.
3. If the builder's tmux session has another name, change `agy` in the lead section of `CLAUDE.md`.

Two agents work fine too, for example Claude plus Codex only. Remove the one you don't use from the table.

## C. What Claude does for each task

```
1. spec      docs/tasks/<date>-<name>.md: goal, exact files, numbered test cases, done-when
2. assign    collab.sh post claude agy "TASK: …"  +  tmux send-keys to agy
3. watch     scripts/watch-agent.sh agy agy claude 40  (in the background)
4. handoff   agy: collab.sh handoff agy claude "feat/x · done · 42 tests pass" → release
5. review    git diff main...feat/x: only the spec's files? Feedback goes back via notepad + tmux
6. 2nd look  codex exec --sandbox read-only "review git diff main...feat/x …"
7. merge     full test suite, PR, tells you. Production stays your call.
```

More on why it's done this way, and prompts that worked: [`workflow.md`](workflow.md).

## D. Doing it by hand

If you'd rather run the pieces yourself:

```bash
git worktree add ../myproject-wt-agy -b feat/first-task             # builder's own checkout
tmux new-session -d -s agy -c ../myproject-wt-agy agy                # start agy in tmux
tmux send-keys -t agy 'Read AGENTS.md, then do docs/tasks/…' Enter    # give it work
scripts/watch-agent.sh agy agy claude 40                             # auto-approve safe commands
scripts/collab.sh status                                             # who's doing what
codex exec --sandbox read-only -o review.txt "Review git diff main...feat/first-task for bugs"
```

## E. Permissions

Short version: the builder can change only its own worktree, the reviewer can change nothing, and only the lead
merges, with you watching. Only you approve production.

- **Claude Code:** must be allowed to run `scripts/collab.sh`, `git`, `tmux`, `codex` and your test command.
- **Antigravity:** interactive in tmux; the watcher answers safe prompts. Never `--dangerously-skip-permissions`.
- **Codex:** always `--sandbox read-only` for reviews.

Exact settings for each CLI: [`permissions.md`](permissions.md).

## F. Safety rules built in

- The notepad is gitignored and local. The protocol forbids secrets and personal data in it.
- Appends take a `mkdir` lock: 20 agents writing at once lose nothing (tested).
- The watcher auto-approves only when **every** part of a `&&` / `||` / `;` chain is on the read-only list.
  Pipes, redirects (`<`, `>`), `$(…)`, backticks, lone `&`, `find -delete/-exec/-fls`, `git branch -D`,
  dangerous flags (`rg --pre`, `git grep -O`, `git diff/log --ext-diff`), multi-line or wrapped commands,
  and anything naming secret files (`.env`, keys) wait for a decision. Inside double quotes `&`, `|`, `;`
  are plain text, but `$…` and backticks still need a human; inside single quotes everything is plain text.
- Git commands (including `git status`, via `core.fsmonitor`, and `git diff/log/show` via textconv / external-diff)
  can run programs set in git config; the watcher cannot see that.
- It picks the approval option by reading its text: "this conversation" first, never "persist to settings" or "No".
- Builders work in their own worktree on their own branch. Only the lead merges; only you say "deploy".

## G. Command reference

```bash
scripts/collab.sh status                              # claims + latest entry per agent
scripts/collab.sh read 30                             # last 30 entries
scripts/collab.sh claim   <me> "<branch> · <files>"   # before editing
scripts/collab.sh post    <me> <to|all> "<text>"
scripts/collab.sh handoff <me> <to> "<branch> · <done> · <next>"
scripts/collab.sh release <me> ["<note>"]
scripts/collab.sh agents                              # valid names
scripts/collab.sh usage   <me> <model> [in out [cache_read [cache_write]]] [--note "<task>"]
scripts/collab.sh usage-import <agent> claude-code <session.jsonl|latest> [--since <ISO UTC>] [--note "<task>"]
scripts/collab.sh usage-import <agent> codex-json  <events.jsonl> [--model <m>] [--note "<task>"]
scripts/collab.sh cost [--since "YYYY-MM-DD HH:MM"] [--grep "<task>"]   # tokens + USD per agent and model
#   env: COLLAB_PRICES (price table, default scripts/prices.tsv), CLAUDE_PROJECTS_DIR (default ~/.claude/projects)

scripts/watch-agent.sh <tmux-session> <agent> <lead> [minutes]
#   env: SAFE_RE (auto-approvable command prefixes), PROMPT_RE / CMD_AFTER / QUESTION_RE (another CLI's prompt format),
#        WATCH_INTERVAL (seconds, default 15), COLLAB_DIR, COLLAB_AGENTS
```

### Usage and cost tracking

Every `usage` or `usage-import` adds a `USAGE` line to the notepad: who, which model, and token counts.
`cost` sums them per agent and model and prices them from `scripts/prices.tsv`.

| Agent | Where the numbers come from |
|---|---|
| Claude Code | its session log, `~/.claude/projects/<project>/<session>.jsonl` (plus the session's subagent logs). One entry per model. Messages logged twice are counted once. |
| Codex | `codex exec --json` events: the `usage` of each `turn.completed`. Codex counts cached tokens inside input; the import separates them. |
| Antigravity / others | what the agent records with `usage`. Model only is fine; tokens show as `+?` until known. |

Importing the same log again replaces the earlier import instead of adding to it, so re-run it as a session grows.
`--since` limits a Claude Code import to one task (timestamps in the log are UTC). Use the same `--note`
for every entry of a task, then `cost --grep "<task>"` gives that task's bill.

USD is the pay-as-you-go API price. On a subscription you pay a flat fee; the number shows what the same
tokens would cost on the API, which is still useful for comparing models and tasks. Models without a price show `n/a`.

## H. Troubleshooting

| Symptom | Fix |
|---|---|
| The builder's messages don't appear in `status` | It's in a worktree with an old `collab.sh`. Reinstall; the current script finds the main checkout through git. |
| Headless `agy -p` denies every command | Expected. Use interactive `agy` in tmux (the default here), or see `permissions.md`. |
| The builder explores for 20+ minutes without writing code | The spec is too loose. Ask Claude for exact files and test cases, or nudge: "you've explored enough, write the failing tests now". |
| The builder sits idle after a permission prompt | Something pressed the wrong option. This watcher reads the option text; an older one may not. |
| Agents start replies with your name, or copy another agent's style | They read each other's instruction files. Keep personal rules in `CLAUDE.md` only, and only the protocol in `AGENTS.md`. |
| `codex exec` verdict is cut off | Don't pipe it through `head`. Use `-o <file>`. |

All 42 lessons from the pilot: [`lessons.md`](lessons.md).

## I. Repository layout

```
install.sh               installs the kit into a repo
scripts/collab.sh        notepad CLI (also usage and cost tracking)
scripts/watch-agent.sh   tmux watcher / safe auto-approver
templates/               AGENTS.md protocol, CLAUDE.md lead section, task-spec template
docs/                    this appendix, workflow, permissions, lessons
examples/                a sample notepad and a sample task spec
tests/run.sh             self-tests (bash + git; tmux for the end-to-end test)
```
