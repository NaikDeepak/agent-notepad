#!/usr/bin/env bash
# agent-notepad: a shared, append-only notepad for several coding agents (and you) working in one git repo.
# Zero infrastructure: one markdown file (.collab/notepad.md, gitignored) + this script. Protocol: AGENTS.md.
#
#   scripts/collab.sh read [N]                    last N entries (default 30)
#   scripts/collab.sh status                      active claims + latest entry addressed to each agent
#   scripts/collab.sh post <from> <to> "<text>"   message
#   scripts/collab.sh claim <agent> "<branch · area/files>"
#   scripts/collab.sh release <agent> ["<note>"]
#   scripts/collab.sh handoff <from> <to> "<branch · what's done · what's next>"
#   scripts/collab.sh agents                      list valid names
#
# Agent names: set COLLAB_AGENTS (space separated), or edit the default below. "all" is always valid as a recipient.
set -euo pipefail

AGENTS="${COLLAB_AGENTS:-claude agy codex human}"

# One notepad per repo, even across git worktrees: resolve the MAIN checkout through git's common dir.
# (Resolving "repo root" from the script's own path would give every worktree its own notepad.)
COMMON="$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [[ -n "$COMMON" ]]; then ROOT="$(dirname "$COMMON")"; else ROOT="$(cd "$(dirname "$0")/.." && pwd)"; fi
DIR="${COLLAB_DIR:-$ROOT/.collab}"
PAD="$DIR/notepad.md"
LOCK="$DIR/.lock"
mkdir -p "$DIR"
[[ -f "$PAD" ]] || printf '# Agent notepad (append-only; newest at the bottom)\n# time | from → to | KIND | text\n\n' > "$PAD"

valid() { local a; for a in $AGENTS all; do [[ "$a" == "$1" ]] && return 0; done; echo "Unknown agent '$1' (use: $AGENTS all)" >&2; exit 2; }
append() { # one line, under a mkdir lock (atomic on every filesystem) so two agents can't interleave writes
  local tries=0
  until mkdir "$LOCK" 2>/dev/null; do
    tries=$((tries + 1)); [[ $tries -gt 50 ]] && { echo "notepad is locked (stale $LOCK? remove it)" >&2; exit 1; }
    sleep 0.1
  done
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
  printf '%s | %s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" >> "$PAD"
  rmdir "$LOCK"; trap - EXIT
}
oneline() { printf '%s' "$*" | tr '\n' ' '; }

cmd="${1:-read}"; shift || true
case "$cmd" in
  read)
    grep -v '^#' "$PAD" | grep -v '^$' | tail -n "${1:-30}" || true ;;
  status)
    echo "Active claims:"
    awk -F' \\| ' '$3 ~ /^CLAIM/ { split($2, p, " "); c[p[1]] = $1 " — " $4 }
                   $3 ~ /^RELEASE/ { split($2, p, " "); delete c[p[1]] }
                   END { n = 0; for (a in c) { print "  " a ": " c[a]; n++ } if (!n) print "  (none)" }' "$PAD"
    for a in $AGENTS; do
      n=$(grep -c " → \(${a}\|all\) |" "$PAD" || true)
      echo "Entries to $a (or all): $n — last: $(grep " → \(${a}\|all\) |" "$PAD" | tail -n1 | cut -c1-120 || true)"
    done ;;
  post)
    [[ $# -ge 3 ]] || { echo "usage: post <from> <to> \"<text>\"" >&2; exit 2; }
    valid "$1"; valid "$2"; append "$1 → $2 | MSG | $(oneline "${@:3}")" ;;
  claim)
    [[ $# -ge 2 ]] || { echo "usage: claim <agent> \"<branch · area>\"" >&2; exit 2; }
    valid "$1"; append "$1 → all | CLAIM | $(oneline "${@:2}")" ;;
  release)
    [[ $# -ge 1 ]] || { echo "usage: release <agent> [\"<note>\"]" >&2; exit 2; }
    valid "$1"; append "$1 → all | RELEASE | $(oneline "${@:2}")" ;;
  handoff)
    [[ $# -ge 3 ]] || { echo "usage: handoff <from> <to> \"<branch · done · next>\"" >&2; exit 2; }
    valid "$1"; valid "$2"; append "$1 → $2 | HANDOFF | $(oneline "${@:3}")" ;;
  agents)
    echo "$AGENTS all" ;;
  *) sed -n '2,13p' "$0"; exit 2 ;;
esac
