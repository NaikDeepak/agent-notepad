#!/usr/bin/env bash
# Watch an interactive agent running in a tmux session, so the lead agent (or you) doesn't have to.
#
#   scripts/watch-agent.sh <tmux-session> <agent-name> <lead-name> [minutes]
#   e.g. scripts/watch-agent.sh agy agy claude 40
#
# Every 15 s it looks at the agent's screen and the notepad, and exits (so the lead wakes up) when:
#   - the agent wrote a HANDOFF to the lead in the notepad          → "HANDOFF"
#   - the agent asks permission for something not on the safe list  → "PROMPT (needs decision): <command>"
#   - time is up                                                    → "TIMEOUT"
# Safe read-only/test commands are approved automatically and logged to .collab/approvals.log.
#
# The approval option is chosen by READING THE OPTION TEXT, never by a hard-coded number: some prompts are
# "1 Yes / 2 No", others "1 Yes / 2 Yes, always this conversation / 3 … / 4 No". Pressing "2" blindly once
# declined a test run and left the agent idle.
#
# Tuned for the Antigravity CLI prompt ("Requesting permission for:"). For another CLI set PROMPT_RE and
# CMD_AFTER (the line after which the command is printed). Extend SAFE_RE for your stack's test commands.
set -euo pipefail

SAFE_RE="${SAFE_RE:-^(ls|cat|head|tail|wc|find|grep|rg|pwd|echo|git status|git diff|git log|git show|git grep|git branch|npm test|npm run test|npm run typecheck|npm run lint|npx vitest run|npx tsc --noEmit|pytest|go test|cargo test|scripts/collab\.sh|\./scripts/collab\.sh)( |$)}"
PROMPT_RE="${PROMPT_RE:-Requesting permission for:}"
CMD_AFTER="${CMD_AFTER:-Requesting permission for:}"

COMMON="$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [[ -n "$COMMON" ]]; then ROOT="$(dirname "$COMMON")"; else ROOT="$(cd "$(dirname "$0")/.." && pwd)"; fi
PAD="${COLLAB_DIR:-$ROOT/.collab}/notepad.md"
LOG="${COLLAB_DIR:-$ROOT/.collab}/approvals.log"

handoffs() { grep -c "$AGENT → $LEAD | HANDOFF" "$PAD" || true; }

# Safe only if single-line and every part of a chain (&&, ||, ;) is on the safe list. Quotes other than single
# quotes are not inert. Pipes, redirects (<, >), backticks, $(…), lone &, and dangerous flags need a human.
is_safe() {
  local s="$1" len i=0 state="none" c c2
  local current_part="" parts=() part parts_checked=0

  [[ "$s" == *$'\n'* ]] && return 1
  [[ -z "${s//[[:space:]]/}" ]] && return 1
  # anything that names a secret-looking file is shown to a human, even a read: the agent's model would see it
  printf '%s' "$s" | grep -qiE '(\.env|\.pem|\.key|id_[a-zA-Z0-9*]|\.ssh/|credentials|secret|\.npmrc|\.netrc)' && return 1

  len=${#s}
  while (( i < len )); do
    c="${s:i:1}"
    c2="${s:i:2}"

    if [[ "$state" == "single" ]]; then
      if [[ "$c" == "'" ]]; then
        state="none"
        current_part="${current_part}Q"
      fi
      (( i++ ))
    elif [[ "$state" == "double" ]]; then
      if [[ "$c" == '"' ]]; then
        state="none"
        current_part="${current_part}Q"
        (( i++ ))
      elif [[ "$c" == '`' || "$c2" == '$(' ]]; then
        return 1
      else
        (( i++ ))
      fi
    else
      # state == "none" (outside quotes)
      if [[ "$c" == "'" ]]; then
        state="single"
        (( i++ ))
      elif [[ "$c" == '"' ]]; then
        state="double"
        (( i++ ))
      elif [[ "${s:i:11}" == "2>/dev/null" ]]; then
        current_part="${current_part} "
        (( i += 11 ))
      elif [[ "${s:i:4}" == "2>&1" ]]; then
        current_part="${current_part} "
        (( i += 4 ))
      elif [[ "$c" == '\' || "$c" == '`' || "$c2" == '$(' || "$c" == '<' || "$c" == '>' ]]; then
        return 1
      elif [[ "$c2" == '&&' || "$c2" == '||' ]]; then
        parts+=("$current_part")
        current_part=""
        (( i += 2 ))
      elif [[ "$c" == ';' ]]; then
        parts+=("$current_part")
        current_part=""
        (( i++ ))
      elif [[ "$c" == '&' || "$c" == '|' ]]; then
        return 1
      else
        current_part="${current_part}${c}"
        (( i++ ))
      fi
    fi
  done

  # ending inside a quote -> human
  [[ "$state" != "none" ]] && return 1
  parts+=("$current_part")

  for part in "${parts[@]}"; do
    part=$(printf '%s' "$part" | sed 's/^ *//; s/ *$//')
    [[ -z "$part" ]] && continue
    (( parts_checked++ ))
    printf '%s' "$part" | grep -qE "$SAFE_RE" || return 1
    # "safe" commands that can still write or delete
    printf '%s' "$part" | grep -qE '(^find .*-(exec|execdir|ok|delete|fprint|fls))|(^git branch( .*)? (-[a-zA-Z]*[dDmMcCf]|--(delete|move|copy|force))( |$))|(^git (diff|log|show) .*(--output|--ext-diff))|(^git grep .*(-[a-zA-Z]*O|--open-files-in-pager)( |$|=))|(^rg .*--pre(=| |$))' && return 1
  done

  [[ $parts_checked -eq 0 ]] && return 1
  return 0
}

# Collect command lines after CMD_AFTER up to the first blank line, question, or option.
extract_cmd() {
  local screen="$1" found=0 line trimmed res="" opt_re='^[> ]*[0-9]+\.'
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == *"$CMD_AFTER"* ]]; then
      found=1; res=""
      continue
    fi
    if [[ $found -eq 1 ]]; then
      trimmed=$(printf '%s' "$line" | sed 's/^ *//; s/ *$//')
      if [[ -z "$trimmed" || "$trimmed" == *'?' || "$line" =~ $opt_re ]]; then
        found=0
        continue
      fi
      if [[ -z "$res" ]]; then res="$trimmed"; else res="$res"$'\n'"$trimmed"; fi
    fi
  done < <(printf '%s\n' "$screen")
  printf '%s' "$res"
}

# Pick the option number to approve: prefer "this conversation/session", else plain "Yes". Never "always"
# persisted to settings, never "No".
pick_option() {
  local screen="$1" n
  n=$(printf '%s\n' "$screen" | grep -iE '^[> ]*[0-9]+\. .*yes.*(this conversation|this session)' | grep -viE 'persist|settings' | head -1 | sed -E 's/^[> ]*([0-9]+)\..*/\1/')
  [[ -z "$n" ]] && n=$(printf '%s\n' "$screen" | grep -iE '^[> ]*[0-9]+\. yes' | grep -viE 'always|persist' | head -1 | sed -E 's/^[> ]*([0-9]+)\..*/\1/')
  printf '%s' "$n"
}

screen_tail() { echo "--- screen:"; tmux capture-pane -t "$SESSION" -p 2>/dev/null | grep -v '^\s*$' | tail -14 || true; }

# Tests source this file with WATCH_AGENT_LIB=1 to check is_safe / pick_option without tmux.
[[ "${WATCH_AGENT_LIB:-}" == 1 ]] && return 0

SESSION="${1:?tmux session}"; AGENT="${2:?agent name}"; LEAD="${3:?lead name}"; MINUTES="${4:-40}"
mkdir -p "$(dirname "$PAD")"; touch "$PAD"
start=$(handoffs); approved=0
INTERVAL="${WATCH_INTERVAL:-15}"   # seconds between looks (tests use 1)
for _ in $(seq 1 $((MINUTES * 60 / INTERVAL))); do
  sleep "$INTERVAL"
  if [[ "$(handoffs)" -gt "$start" ]]; then echo "HANDOFF (auto-approved $approved)"; exit 0; fi
  screen=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null || true)
  if printf '%s' "$screen" | grep -q "$PROMPT_RE"; then
    cmd=$(extract_cmd "$screen")
    opt=$(pick_option "$screen")
    if is_safe "$cmd" && [[ -n "$opt" ]]; then
      tmux send-keys -t "$SESSION" "$opt"; sleep 1; tmux send-keys -t "$SESSION" Enter
      approved=$((approved + 1))
      printf '%s | %s | option %s | %s\n' "$(date '+%Y-%m-%d %H:%M')" "$AGENT" "$opt" "$cmd" >> "$LOG"
      sleep 3; continue
    fi
    echo "PROMPT (needs decision): $cmd"; screen_tail; exit 0
  fi
done
echo "TIMEOUT after $MINUTES min (auto-approved $approved)"; screen_tail
