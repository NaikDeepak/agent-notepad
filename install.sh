#!/usr/bin/env bash
# Install agent-notepad into an existing git repo.
#
#   ./install.sh /path/to/your/repo
#
# Adds (never overwrites existing files; safe to run twice):
#   scripts/collab.sh, scripts/watch-agent.sh   the notepad CLI and the tmux watcher
#   AGENTS.md                                   protocol section appended (created if missing)
#   CLAUDE.md, GEMINI.md                        a short pointer to AGENTS.md appended (created if missing)
#   docs/tasks/_template.md                     task-spec template for the lead
#   .gitignore                                  .collab/ (the notepad stays local)
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:?usage: ./install.sh /path/to/your/repo}"
DEST="$(cd "$DEST" && pwd)"
git -C "$DEST" rev-parse --git-dir >/dev/null 2>&1 || { echo "$DEST is not a git repo" >&2; exit 1; }
MARK="agent-notepad protocol"

copy() { # copy if absent
  if [[ -e "$DEST/$2" ]]; then echo "  skip   $2 (exists)"; else
    mkdir -p "$(dirname "$DEST/$2")"; cp "$SRC/$1" "$DEST/$2"; echo "  added  $2"; fi
}
append_once() { # append text to a file unless the marker is already there
  local file="$DEST/$1" text="$2"
  if [[ -f "$file" ]] && grep -q "$MARK" "$file"; then echo "  skip   $1 (already has the protocol)"; return; fi
  [[ -f "$file" && -s "$file" ]] && printf '\n' >> "$file"
  printf '%s\n' "$text" >> "$file"; echo "  updated $1"
}

echo "Installing agent-notepad into $DEST"
copy scripts/collab.sh scripts/collab.sh
copy scripts/watch-agent.sh scripts/watch-agent.sh
chmod +x "$DEST/scripts/collab.sh" "$DEST/scripts/watch-agent.sh"
copy templates/task-spec.md docs/tasks/_template.md
append_once AGENTS.md "$(cat "$SRC/templates/AGENTS.md")"
POINTER="## Working with other agents
<!-- $MARK -->
Several coding agents share this repo. Before any task, read **\"Working with other agents\" in AGENTS.md** and
follow it: run \`scripts/collab.sh status\`, claim before editing, hand off and release when done."
append_once CLAUDE.md "$POINTER"
append_once GEMINI.md "$POINTER"
if grep -qxF '.collab/' "$DEST/.gitignore" 2>/dev/null; then echo "  skip   .gitignore (.collab/ already ignored)"
else printf '\n# agent-notepad (local only)\n.collab/\n' >> "$DEST/.gitignore"; echo "  updated .gitignore"; fi

cat <<EOF

Done. Next:
  1. Edit the names/roles table in AGENTS.md and the default in scripts/collab.sh (or export COLLAB_AGENTS).
  2. cd "$DEST" && scripts/collab.sh status
  3. Follow README "Step 3" onwards to sign in each agent and give them permissions.
EOF
