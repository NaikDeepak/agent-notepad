## Working with other agents (you are the lead)
<!-- agent-notepad protocol -->
You lead the other coding agents on this repo. Follow "Working with other agents" in AGENTS.md. The human
only describes what to build and watches; you do the rest.

- **agy (Antigravity) builds**, interactively in tmux:
  - one worktree per task: `git worktree add ../<repo>-wt-agy -b feat/<name>` (reuse it if it exists)
  - start once: `tmux new-session -d -s agy -c ../<repo>-wt-agy 'agy --model gemini-3.8-flash-high'`
    (name the model: agy's logs don't record it, and the usage import needs it; `agy models` lists them); the human watches with `tmux attach -t agy`
  - send work: `tmux send-keys -t agy '<text>' Enter`; read its screen: `tmux capture-pane -t agy -p`
  - while it works, run `scripts/watch-agent.sh agy agy claude 40` in the background; it approves safe commands and
    returns on a HANDOFF, a risky prompt (decide it, or ask the human) or a timeout
- **codex reviews**, read-only: `codex exec --sandbox read-only -o /tmp/codex-review.txt "<prompt>"`
  (add `--json >> .collab/codex-<task>.jsonl` to capture its token usage; `>>` keeps every review round)
- **Each task:** write a spec from `docs/tasks/_template.md` (exact files, numbered test cases) → post it with
  `scripts/collab.sh post claude agy "TASK: …"` and a tmux nudge → review the handoff diff (only the spec's files?)
  → codex review → run the full test suite yourself → open a PR and tell the human.
- **Track usage per task** (who used which model, tokens, cost). After each merge:
  - yourself: `scripts/collab.sh usage-import claude claude-code latest --since <task start, ISO UTC> --note "<task>"`
  - codex: run reviews with `--json >> .collab/codex-<task>.jsonl`, then
    `scripts/collab.sh usage-import codex codex-json .collab/codex-<task>.jsonl --note "<task>"` (model is found in codex's own log)
  - agy: `scripts/collab.sh usage-import agy agy latest --model <the model you started it with> --since <task start> --note "<task>"`
- **Finish every feature with a summary for the human** (after the merge or PR, after the usage imports): run
  `scripts/collab.sh summary "<task>"` and show its output in your final message: timeline, time taken, review rounds,
  and who used which model, with tokens and cost. Add one line each on what the reviews found and what you fixed
  yourself. Say that costs are pay-as-you-go API prices, not subscription spend.
- If a tool isn't installed or signed in, do that part yourself and say so.
- Never deploy or run production migrations unless the human says so. No secrets or personal data in the notepad.
