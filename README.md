# agent-notepad

**Let Claude Code, Antigravity and Codex work on the same repo as a team, with one lead, a shared notepad, and no servers.**

You probably pay for more than one AI coding tool. Each one is good on its own; together they step on each other:
two agents edit the same file, nobody knows who is doing what, and reviews happen only when you remember.
`agent-notepad` is a small kit that fixes that with things you already have:

- **one append-only notepad file** (`.collab/notepad.md`, never committed) and a 60-line bash CLI to write to it;
- **a protocol in `AGENTS.md`** that every agent already reads (claim → work → hand off → release);
- **a lead agent** that plans, writes task specs, delegates, reviews and merges, so you make decisions instead of relaying messages;
- **one git worktree per agent**, so nobody edits your checkout;
- **a tmux watcher** that approves safe read-only commands for the builder and wakes the lead on a handoff or a risky prompt;
- **least-privilege permission recipes** for each CLI.

It came out of a real project where Claude Code (lead), Antigravity CLI (builder) and Codex CLI (reviewer) shipped
features in parallel for several weeks. The 40+ dated gotchas from that pilot are in [`docs/lessons.md`](docs/lessons.md).

```
                 you (owner: priorities, secrets, "deploy")
                                  │
                       ┌──────────▼──────────┐
                       │  Claude Code: LEAD   │  plans · writes specs · reviews · merges
                       └──┬────────────────┬──┘
           task spec +    │                │   "review this diff, read-only"
           tmux send-keys │                │   codex exec / /codex:review
                ┌─────────▼───────┐  ┌─────▼───────────┐
                │ Antigravity:    │  │ Codex:          │
                │ BUILDER         │  │ REVIEWER        │
                │ own worktree    │  │ read-only       │
                └─────────┬───────┘  └─────┬───────────┘
                          │   claim / post / handoff / release
                          ▼                ▼
                 ┌──────────────────────────────────────┐
                 │ .collab/notepad.md (scripts/collab.sh)│  one file, locked appends, shared by all worktrees
                 └──────────────────────────────────────┘
```

Works with any subset: two agents is fine. The names and roles are just a table in `AGENTS.md`.

---

## Step-by-step setup

Allow about 30 minutes the first time. Every step is a command you can copy.

### Step 0: Prerequisites

| You need | Check | Install |
|---|---|---|
| git ≥ 2.38, bash, a POSIX shell (macOS or Linux; Windows via WSL) | `git --version` | your package manager |
| tmux (to run the builder interactively and watch it) | `tmux -V` | `brew install tmux` / `apt install tmux` |
| **Claude Code** (lead) | `claude --version` | <https://claude.com/claude-code> |
| **Antigravity CLI** `agy` (builder), optional | `agy --help` | Google Antigravity; sign in once with `agy` |
| **Codex CLI** (reviewer), optional | `codex --version` | `npm i -g @openai/codex` then `codex login` |

> Each tool runs under **your own account and plan**. Read each vendor's current terms for scripted or automated use
> of their CLI before you rely on this setup. This kit only types into the CLIs the way you would; it doesn't share
> accounts or call private APIs.

### Step 1: Install the kit into your project

```bash
git clone https://github.com/NaikDeepak/agent-notepad.git
cd agent-notepad
tests/run.sh                         # optional: self-tests, need only bash + git
./install.sh /path/to/your/project
```

`install.sh` never overwrites anything. It adds:

| File in your project | What it is |
|---|---|
| `scripts/collab.sh` | the notepad CLI |
| `scripts/watch-agent.sh` | the tmux watcher |
| `AGENTS.md` | the protocol section (appended, or created) |
| `CLAUDE.md`, `GEMINI.md` | a 3-line pointer to `AGENTS.md` (appended, or created) |
| `docs/tasks/_template.md` | task-spec template for the lead |
| `.gitignore` | `.collab/` so the notepad never gets committed |

Commit those files: `git add -A && git commit -m "chore: add agent-notepad"`.

### Step 2: Name your agents

Edit the table at the top of the protocol in `AGENTS.md` (names, who leads, who builds, who reviews). Then make the
names valid for the CLI, either by editing the default line in `scripts/collab.sh`

```bash
AGENTS="${COLLAB_AGENTS:-claude agy codex human}"
```

or by exporting `COLLAB_AGENTS="claude agy codex alice"` in your shell profile. `all` is always a valid recipient.

Try it:

```bash
scripts/collab.sh post human all "hello team"
scripts/collab.sh status
```

### Step 3: Give each agent only the permissions it needs

Details and reasons are in [`docs/permissions.md`](docs/permissions.md). The short version:

- **Claude Code (lead):** normal interactive permissions. It must be allowed to run `scripts/collab.sh`, `git`, `tmux`, `codex`, and your test command.
- **Antigravity (builder):** run it **interactively in tmux** (Step 5). It asks before each command, and the watcher answers safe ones. Never use `--dangerously-skip-permissions`.
- **Codex (reviewer):** always `--sandbox read-only` for reviews and audits.

### Step 4: Give each builder its own worktree

```bash
cd /path/to/your/project
git worktree add ../myproject-wt-agy -b feat/first-task
```

The notepad is shared across worktrees automatically: `collab.sh` finds the main checkout through git.

### Step 5: Start the builder in tmux

```bash
tmux new-session -d -s agy -c ../myproject-wt-agy
tmux send-keys -t agy 'agy' Enter          # sign in on first run
tmux attach -t agy                          # watch it live; detach with Ctrl-b then d
```

You (or the lead) talk to it by typing into that session:

```bash
tmux send-keys -t agy 'Read AGENTS.md, then do the task in docs/tasks/2026-01-01-first-task.md' Enter
```

### Step 6: Make Claude Code the lead

Open Claude Code in your **main** checkout and paste this once (adjust names):

```text
You lead the agents on this repo. Read "Working with other agents" in AGENTS.md.
- agy (Antigravity) builds. It runs interactively in tmux session "agy", in worktree ../myproject-wt-agy.
  Send it work with `tmux send-keys -t agy '<text>' Enter`, read its screen with `tmux capture-pane -t agy -p`.
- codex reviews, read-only: `codex exec --sandbox read-only -o /tmp/codex-review.txt "<prompt>"`.
- For each task: write a spec from docs/tasks/_template.md, commit it, claim nothing the builder needs,
  send agy the task, run `scripts/watch-agent.sh agy agy claude 40` in the background, review the handoff,
  ask codex for an independent review, run the full test suite yourself, then open a PR.
- Never deploy or run production migrations unless I say so. Keep secrets and personal data out of the notepad.
```

To keep it permanent, put the same text in the lead section of your `CLAUDE.md`.

### Step 7: Run your first task

What a normal loop looks like (the lead does all of it; you watch and decide):

1. **Spec.** The lead copies `docs/tasks/_template.md` to `docs/tasks/<date>-<name>.md`: goal, exact files, numbered test cases, done-criteria.
2. **Assign.** `scripts/collab.sh post claude agy "TASK: docs/tasks/... on branch feat/x in ../myproject-wt-agy"`, plus the `tmux send-keys` nudge.
3. **Watch.** `scripts/watch-agent.sh agy agy claude 40 &`. It approves read-only and test commands, logs each one to `.collab/approvals.log`, and exits on a HANDOFF, an unsafe prompt, or timeout.
4. **Handoff.** The builder writes `scripts/collab.sh handoff agy claude "feat/x · done · 42 tests pass"` and `release`.
5. **Review.** The lead reads the diff (`git diff main...feat/x`) and checks it only touched the spec's files. Fixes go back via `post` and a tmux nudge.
6. **Second opinion.** `codex exec --sandbox read-only -o /tmp/review.txt "Review git diff main...feat/x for bugs. Quote the line and a concrete failing input. Max 10 findings."` A different model family catches different bugs.
7. **Merge.** The lead runs the full suite itself, opens the PR, and tells you. Production stays your call.

A real notepad from such a loop is in [`examples/notepad-sample.md`](examples/notepad-sample.md).

---

## Command reference

```bash
scripts/collab.sh status                              # claims + latest entry per agent
scripts/collab.sh read 30                             # last 30 entries
scripts/collab.sh claim   <me> "<branch> · <files>"   # before editing
scripts/collab.sh post    <me> <to|all> "<text>"
scripts/collab.sh handoff <me> <to> "<branch> · <done> · <next>"
scripts/collab.sh release <me> ["<note>"]
scripts/collab.sh agents                              # valid names

scripts/watch-agent.sh <tmux-session> <agent> <lead> [minutes]
#   env: SAFE_RE (auto-approvable command prefixes), PROMPT_RE / CMD_AFTER (another CLI's prompt format),
#        COLLAB_DIR (notepad location), COLLAB_AGENTS (names)
```

## Safety rules built in

- The notepad is **gitignored and local**. The protocol forbids secrets and personal data in it.
- Appends take a `mkdir` lock, so 20 agents writing at once lose nothing (tested).
- The watcher auto-approves **only** when every part of a `&&` / `||` / `;` chain is on the read-only list. Pipes, redirects, `$(…)`, backticks, `find -delete/-exec` and `git branch -D` always wait for a decision.
- It chooses the approval option **by reading its text**, preferring "this conversation" and never "persist to settings" or "No".
- Builders work in their own worktree on their own branch. Only the lead merges; only you say "deploy".

## Troubleshooting (the top 6; all 40+ in [`docs/lessons.md`](docs/lessons.md))

| Symptom | Fix |
|---|---|
| Builder's messages don't show up in `status` | It's in a worktree with an old `collab.sh`. Reinstall; the current script resolves the main checkout via `git rev-parse --git-common-dir`. |
| Headless `agy -p` denies every command | Expected. Use interactive `agy` in tmux, or add a narrow allow-rule (see `docs/permissions.md`). |
| Builder explores for 20+ minutes without writing code | The spec is too loose. List exact files and test cases, and send one nudge: "you've explored enough, write the failing tests now". |
| Builder sits idle after a permission prompt | An auto-approver pressed the wrong number (some prompts are only Yes/No). Use this watcher, which reads the option text. |
| Agents start replies with your name or adopt another agent's style | They read each other's instruction files. Keep personal and style rules in the per-agent file, and only the protocol in `AGENTS.md`. |
| `codex exec` verdict cut off | Don't pipe it through `head`. Use `-o <file>` to save the final message. |

## Repository layout

```
scripts/collab.sh        notepad CLI
scripts/watch-agent.sh   tmux watcher / safe auto-approver
install.sh               installs the kit into a repo
templates/AGENTS.md      the protocol
templates/task-spec.md   spec template for delegated tasks
docs/workflow.md         the lead pattern in detail: roles, review loop, parallel work
docs/permissions.md      least-privilege recipes per CLI
docs/lessons.md          dated gotchas from the pilot
examples/                a sample notepad and a sample task spec
tests/run.sh             self-tests (bash + git only)
```

## Contributing

Adapters for other CLIs (Gemini CLI, Cursor, Aider), better prompt detection for the watcher, and new lessons are
welcome. Run `tests/run.sh` before opening a PR; CI runs it on macOS and Linux.

## License

MIT
