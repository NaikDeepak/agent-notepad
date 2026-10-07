# Permissions: least privilege per CLI

Rule of thumb: **the builder can change its own worktree and nothing else; the reviewer can change nothing; only
the lead (with you watching) touches `main`, pushes, or opens PRs; only you approve production.**

## Claude Code (lead)
Runs in your main checkout with its normal interactive permission prompts. Allow (in `.claude/settings.json` or
when prompted):

```json
{ "permissions": { "allow": [
  "Bash(scripts/collab.sh:*)", "Bash(scripts/watch-agent.sh:*)",
  "Bash(tmux send-keys:*)", "Bash(tmux capture-pane:*)",
  "Bash(codex exec --sandbox read-only:*)",
  "Bash(git diff:*)", "Bash(git log:*)", "Bash(npm test:*)"
] } }
```

Keep deploy and production-migration commands **not** allowed, so they always prompt you.

## Antigravity CLI `agy` (builder)

**Recommended: interactive in tmux.** Each command prompts; `scripts/watch-agent.sh` answers only safe ones, and
logs them to `.collab/approvals.log`. Everything else stops and wakes the lead (or you).

- Start it in the builder's worktree: `tmux new-session -d -s agy -c ../<repo>-wt-agy` then `tmux send-keys -t agy 'agy' Enter`.
- Answer "this conversation" (not "persist to settings") so approvals end with the session.
- Never start it with `--dangerously-skip-permissions`.

**Headless (`agy -p "<task>"`)** can't ask, so it denies everything that isn't allowed in
`~/.gemini/antigravity-cli/settings.json`. Minimal rule set for "may use the notepad":

```json
{ "permissions": { "allow": ["command(scripts/collab.sh)", "command(./scripts/collab.sh)"] } }
```

For a headless build task you'd also add `write_file(<absolute path>)` per file in the spec, and remove them after.
Chained commands stay blocked even when each part is allowed. In the pilot, headless mode was fine for questions and
small reviews, and interactive tmux mode was better for building.

Back up the settings file before editing: `cp ~/.gemini/antigravity-cli/settings.json{,.bak}`.

## Codex CLI (reviewer / auditor)

```bash
codex exec --sandbox read-only -o /tmp/codex-review.txt "<prompt>"
```

- `--sandbox read-only` for every review and audit. Use `workspace-write` only for an explicit build task, in its own worktree.
- `-o` saves the final message to a file; don't pipe through `head` (it cuts the verdict off).
- From inside Claude Code you can also use OpenAI's plugin:
  `/plugin marketplace add openai/codex-plugin-cc` and `/plugin install codex@openai-codex`, then `/codex:review`, `/codex:adversarial-review`, `/codex:rescue`.
- Never `--dangerously-bypass-approvals-and-sandbox`.

## Secrets
- Agents may list environment variable **names** (`vercel env ls`, `printenv | cut -d= -f1`), never print values.
- `.env*` files: keep them out of the builder's task file list. The watcher never auto-approves a command that names
  a secret-looking file (`.env`, `.pem`, `.key`, `id_rsa`, `credentials`, `secret`, `.npmrc`, `.netrc`), even a
  plain `cat`, because whatever the builder reads goes to its model provider.
- Nothing secret or personal goes in the notepad, task specs, or commit messages.
