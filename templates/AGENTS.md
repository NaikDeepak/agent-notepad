# Working with other agents (shared notepad)

<!-- agent-notepad protocol. Copy this section into your repo's AGENTS.md (Codex and Antigravity read AGENTS.md
     natively; point CLAUDE.md / GEMINI.md at it). Replace the names below with yours. -->

Several coding agents may work on this repo at the same time:

| Name | Who | Role |
|---|---|---|
| `claude` | Claude Code | **Lead.** Plans, writes task specs, assigns work, reviews, merges. Deploys only when the human asks. |
| `agy` | Antigravity CLI | Builder. Works only on a task the lead (or the human) assigned, on the branch named in the task. |
| `codex` | OpenAI Codex CLI | Reviewer / auditor. Read-only unless the task says otherwise. |
| `human` | You, the owner | Decides priorities, approves merges to production, owns secrets. |

Everyone coordinates through an append-only notepad, `.collab/notepad.md` (gitignored, local only).
**Always use `scripts/collab.sh`; never edit the notepad by hand.**

```bash
scripts/collab.sh status                          # active claims + latest entry for each agent
scripts/collab.sh read 30                         # last 30 entries
scripts/collab.sh claim <me> "<branch> · <files/area>"
scripts/collab.sh post <me> <claude|agy|codex|human|all> "<message>"
scripts/collab.sh handoff <me> <other> "<branch> · <done> · <next>"
scripts/collab.sh release <me> "<note>"
scripts/collab.sh usage <me> <model> [<input> <output>] --note "<task>"   # which model you used, and tokens
scripts/collab.sh cost                            # tokens and cost per agent and model
```

## Protocol
1. **Start of every task:** run `scripts/collab.sh status` and read anything addressed to you or to `all`.
2. **Claim before editing.** One claim per agent (a new claim replaces your previous one). Name the branch and the files or area.
3. **Never edit files, or push to a branch, that another agent has claimed.** Ask with `post` instead.
4. **Separate branches, ideally separate worktrees.** Never commit to `main` directly; changes go through a PR.
5. **Stay inside the task spec.** Touch only the files it lists. If you need more, `post` to the lead and wait.
6. **Ask, don't block silently.** Questions to the lead or the human go through `post`.
7. **Finishing or pausing:** write a `handoff` (branch, what's done, what's next, test result), then `release`.
   Before the handoff, record your model with `usage`. Add input and output tokens if your CLI shows them; never guess.
8. **Never write secrets, keys, connection strings or personal data in the notepad.**
9. **Production is the human's call.** Only the lead deploys or runs production migrations, and only when the human asks.

## Rules for builders (not the lead)
- Run shell commands **one per call** (no `&&` chains) and **in the foreground** (no background jobs).
- Write the failing test first, then the code. Run the full test suite before your handoff and quote the result.
- Commit on your branch; do not push or open PRs unless the task says so. The lead reviews and integrates.
- Where the task asks for a seam (e.g. `// HOOK: wired by lead`), leave exactly that comment and nothing else.
