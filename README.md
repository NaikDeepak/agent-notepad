# agent-notepad

**Make Claude Code the tech lead of your other AI coding agents.** You describe what to build. Claude plans it,
hands the building to Antigravity, asks Codex for a second review, checks the result and opens a pull request.
You watch, and decide what ships.

No servers or API keys: just a shared notes file, a small script, and the CLIs you already pay for.

```
   you ── "build X" ──▶  Claude Code (lead)   plans · reviews · opens the PR
                           │            │
                   builds  ▼            ▼  reviews (read-only)
                     Antigravity     Codex
                           │            │
                           ▼            ▼
                .collab/notepad.md  (who's doing what, in order)
```

## Setup

### 1. Prerequisites
- macOS or Linux (Windows: WSL), `git`, and `tmux` (`brew install tmux` or `apt install tmux`)
- [Claude Code](https://claude.com/claude-code), signed in
- [Antigravity CLI](https://antigravity.google) (`agy`): run `agy` once to sign in
- [Codex CLI](https://github.com/openai/codex), optional, for reviews: `npm i -g @openai/codex`, then `codex login`

### 2. Install

```bash
git clone https://github.com/NaikDeepak/agent-notepad.git
./agent-notepad/install.sh /path/to/your/project
```

This adds a few files to your project and never overwrites anything. Commit them.

## Use

Open Claude Code in your project and ask for something:

> Add a CSV export of the customer list. Have agy build it and codex review it.

Claude writes the task, starts Antigravity in a tmux session, and keeps track of everything in the notepad.

**To watch Antigravity work**, in another terminal:

```bash
tmux attach -t agy          # detach again with Ctrl-b, then d
```

**To see who's doing what:** `scripts/collab.sh status`

That's all you need. When the work is done, Claude tells you and opens a PR. Merging and deploying stay your decision.

---

- **[Appendix](docs/appendix.md):** what the install added, other names or roles, doing it by hand, permissions, safety rules, troubleshooting
- **[How the lead works](docs/workflow.md)** · **[Permissions per CLI](docs/permissions.md)** · **[42 lessons from the pilot](docs/lessons.md)**
- **Examples:** [a day in the notepad](examples/notepad-sample.md) · [a task spec](examples/task-spec-csv-export.md)

Each tool runs under your own account. Check each vendor's current terms for scripted use of its CLI.
Contributions welcome; run `tests/run.sh` before opening a PR. MIT licensed.
