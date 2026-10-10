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
#   scripts/collab.sh usage <agent> <model> [in out [cache_read [cache_write]]] [--note "<text>"]
#   scripts/collab.sh usage-import <agent> claude-code <session.jsonl|latest> [--since <ISO-UTC>] [--note "<text>"]
#   scripts/collab.sh usage-import <agent> codex-json <events.jsonl> [--model <m>] [--note "<text>"]
#   scripts/collab.sh cost [--since "YYYY-MM-DD HH:MM"] [--grep <text>]   tokens and cost per agent and model
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
PRICES="${COLLAB_PRICES:-$(cd "$(dirname "$0")" && pwd)/prices.tsv}"
isnum() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "not a token count: '$1'" >&2; exit 2; }; }
model_ok() { [[ "$1" =~ ^[A-Za-z0-9._:/@*-]+$ ]] || { echo "bad model name: '$1'" >&2; exit 2; }; }
# One USAGE entry: model=M in=N out=N cr=N cw=N cw1h=N [src=S] [· note]. "?" means not reported.
usage_line() { # agent model in out cr cw cw1h src note
  append "$1 → all | USAGE | model=$2 in=$3 out=$4 cr=$5 cw=$6 cw1h=$7${8:+ src=$8}${9:+ · $(oneline "$9")}"
}

# Claude Code session log (~/.claude/projects/<dir>/<session>.jsonl): sum usage per model.
# A message is logged once per content block with the same id, so keep one record per message id.
claude_usage() { # since files... → "model in out cache_read cache_write_5m cache_write_1h messages"
  local since="$1"; shift
  awk -v since="$since" '
    function num(k,   s) { if (match(u, "\"" k "\":[0-9]+")) { s = substr(u, RSTART, RLENGTH); sub(/.*:/, "", s); return s + 0 } return 0 }
    !/"type":"assistant"/ || !/[^\\]"usage":\{/ { next }
    {
      if (since != "" && match($0, /"timestamp":"[^"]+"/) && substr($0, RSTART + 13, RLENGTH - 14) < since) next
      if (!match($0, /[^\\]"model":"[^"]+"/)) next
      m = substr($0, RSTART + 10, RLENGTH - 11); if (m ~ /synthetic/) next
      id = FILENAME ":" FNR; if (match($0, /[^\\]"id":"msg_[^"]+"/)) id = substr($0, RSTART + 7, RLENGTH - 8)
      match($0, /[^\\]"usage":\{/); u = substr($0, RSTART + 1, 2000)
      w = num("cache_creation_input_tokens"); h = num("ephemeral_1h_input_tokens")
      M[id] = m; I[id] = num("input_tokens"); O[id] = num("output_tokens"); R[id] = num("cache_read_input_tokens")
      W[id] = w - h; H[id] = h
    }
    END {
      for (id in M) { m = M[id]; i[m] += I[id]; o[m] += O[id]; r[m] += R[id]; w5[m] += W[id]; w1[m] += H[id]; n[m]++ }
      for (m in n) printf "%s %.0f %.0f %.0f %.0f %.0f %d\n", m, i[m], o[m], r[m], w5[m], w1[m], n[m]
    }' "$@"
}

# `codex exec --json` event stream: sum the usage of every turn.completed event.
# OpenAI counts cached tokens inside input_tokens, so input here = input_tokens - cached_input_tokens.
codex_usage() { # file → "in out cache_read turns"
  awk '
    function num(k,   s) { if (match(u, "\"" k "\":[0-9]+")) { s = substr(u, RSTART, RLENGTH); sub(/.*:/, "", s); return s + 0 } return 0 }
    /"turn\.completed"/ && match($0, /"usage":\{[^}]*\}/) {
      u = substr($0, RSTART, RLENGTH); c = num("cached_input_tokens")
      i += num("input_tokens") - c; r += c; o += num("output_tokens"); n++
    }
    END { printf "%.0f %.0f %.0f %d\n", i, o, r, n }' "$1"
}

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
  usage)
    [[ $# -ge 2 ]] || { echo "usage: usage <agent> <model> [in out [cache_read [cache_write]]] [--note \"<text>\"]" >&2; exit 2; }
    valid "$1"; model_ok "$2"; agent="$1" model="$2"; shift 2
    note=""; nums=()
    while [[ $# -gt 0 ]]; do
      case "$1" in --note) note="${2:-}"; shift 2 || shift ;; *) isnum "$1"; nums+=("$1"); shift ;; esac
    done
    [[ ${#nums[@]} -le 4 && ${#nums[@]} -ne 1 ]] || { echo "give input and output tokens together (or neither)" >&2; exit 2; }
    usage_line "$agent" "$model" "${nums[0]:-?}" "${nums[1]:-?}" "${nums[2]:-0}" "${nums[3]:-0}" 0 "" "$note" ;;
  usage-import)
    [[ $# -ge 3 ]] || { echo "usage: usage-import <agent> <claude-code|codex-json> <file|latest> [--since ISO] [--model m] [--note text]" >&2; exit 2; }
    valid "$1"; agent="$1" fmt="$2" file="$3"; shift 3
    since="" model="" note=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --since) since="${2:-}"; shift 2 || shift ;;
        --model) model="${2:-}"; shift 2 || shift ;;
        --note)  note="${2:-}";  shift 2 || shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
      esac
    done
    # Claude Code logs use ISO UTC ("2026-10-09T13:00"); a notepad-style "2026-10-09 18:58" would compare wrongly.
    [[ -z "$since" || "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2} ]] || { echo "--since must be ISO UTC, e.g. 2026-10-09T13:00" >&2; exit 2; }
    files=()
    if [[ "$fmt" == claude-code && "$file" == latest ]]; then
      # Claude Code keeps each project's sessions in ~/.claude/projects/<cwd with non-alphanumerics as ->/
      pdir="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}/$(pwd | sed 's/[^A-Za-z0-9]/-/g')"
      file="$(ls -t "$pdir"/*.jsonl 2>/dev/null | head -n1 || true)"
      [[ -n "$file" ]] || { echo "no Claude Code session found in $pdir" >&2; exit 1; }
    fi
    [[ -f "$file" ]] || { echo "no such file: $file" >&2; exit 1; }
    files=("$file")
    if [[ "$fmt" == claude-code && -d "${file%.jsonl}/subagents" ]]; then # subagent transcripts of that session
      for f in "${file%.jsonl}"/subagents/*.jsonl; do [[ -f "$f" ]] && files+=("$f"); done
    fi
    # src lets a later import of the same (growing) log replace an earlier one instead of adding to it.
    src="$(basename "$file")${since:+@$since}"; src="${src// /_}"
    case "$fmt" in
      claude-code)
        out="$(claude_usage "$since" "${files[@]}")"
        [[ -n "$out" ]] || { echo "no usage found in $file" >&2; exit 1; }
        while read -r m i o r w h n; do
          model_ok "$m"; usage_line "$agent" "$m" "$i" "$o" "$r" "$w" "$h" "$src" "$note"
          echo "$agent  $m  in=$i out=$o cache_read=$r cache_write=$((w + h))  ($n messages)"
        done <<< "$out" ;;
      codex-json)
        if [[ -z "$model" ]]; then # codex's events don't name the model; fall back to its config
          model="$(sed -n 's/^[[:space:]]*model[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null | head -n1)"
          model="${model:-codex-default}"
        fi
        model_ok "$model"
        read -r i o r n <<< "$(codex_usage "$file")"
        [[ "$n" -gt 0 ]] || { echo "no turn.completed usage in $file (was codex run with --json?)" >&2; exit 1; }
        usage_line "$agent" "$model" "$i" "$o" "$r" 0 0 "$src" "$note"
        echo "$agent  $model  in=$i out=$o cache_read=$r  ($n turns)" ;;
      *) echo "unknown format '$fmt' (use claude-code or codex-json)" >&2; exit 2 ;;
    esac ;;
  cost)
    since="" g=""
    while [[ $# -gt 0 ]]; do
      case "$1" in --since) since="${2:-}"; shift 2 || shift ;; --grep) g="${2:-}"; shift 2 || shift ;;
        *) echo "usage: cost [--since \"YYYY-MM-DD HH:MM\"] [--grep <text>]" >&2; exit 2 ;; esac
    done
    [[ -f "$PRICES" ]] || echo "(no price table at $PRICES: showing tokens only)" >&2
    awk -v since="$since" -v g="$g" -v prices="$PRICES" '
      BEGIN {
        while ((getline line < prices) > 0) {
          sub(/#.*/, "", line); k = split(line, f, /[ \t]+/); if (f[1] == "") { for (j = 1; j < k; j++) f[j] = f[j + 1]; k-- }
          if (k >= 3) { P[f[1]] = f[2] + 0 " " f[3] + 0 " " f[4] + 0 " " f[5] + 0 " " f[6] + 0 }
        }
      }
      function price(m,   p, best, bl) {
        if (m in P) return P[m]
        best = ""; bl = -1
        for (p in P) if (p ~ /\*$/ && index(m, substr(p, 1, length(p) - 1)) == 1 && length(p) > bl) { best = P[p]; bl = length(p) }
        return best
      }
      function add(key, i, o, r, w, h) { if (i == "?" || o == "?") U[key] = 1; I[key] += i; O[key] += o; R[key] += r; W[key] += w; H[key] += h; K[key] = 1 }
      / \| USAGE \| / {
        t = substr($0, 1, 16); if (since != "" && t < since) next; if (g != "" && !index($0, g)) next
        split($0, f, / \| /); if (f[3] != "USAGE") next   # a MSG that merely quotes "| USAGE |" is not usage
        split(f[2], a, " "); agent = a[1]
        rest = substr($0, index($0, " | USAGE | ") + 11); sub(/ · .*/, "", rest)
        delete v; n = split(rest, kv, " "); for (j = 1; j <= n; j++) { e = index(kv[j], "="); if (e) v[substr(kv[j], 1, e - 1)] = substr(kv[j], e + 1) }
        key = agent SUBSEP v["model"]
        if ("src" in v) { s = key SUBSEP v["src"]; S[s] = v["in"] " " v["out"] " " v["cr"] " " v["cw"] " " v["cw1h"]; SK[s] = key }
        else add(key, v["in"], v["out"], v["cr"], v["cw"], v["cw1h"])
      }
      END {
        for (s in S) { split(S[s], x, " "); add(SK[s], x[1], x[2], x[3], x[4], x[5]) }
        for (key in K) rows++
        if (!rows) { print "(no USAGE entries" (since != "" || g != "" ? " match" : " yet") ")"; exit }
        printf "%-8s %-22s %12s %10s %12s %11s %10s\n", "agent", "model", "input", "output", "cache_read", "cache_write", "usd"
        for (key in K) {
          split(key, km, SUBSEP); p = price(km[2])
          q = (key in U) ? "+?" : ""
          if (p == "") { c = "n/a"; unpriced = unpriced " " km[1] "/" km[2] }
          else { split(p, pr, " "); usd = (I[key] * pr[1] + O[key] * pr[2] + R[key] * pr[3] + W[key] * pr[4] + H[key] * pr[5]) / 1e6; tot += usd; c = sprintf("%.2f", usd) }
          printf "%-8s %-22s %12.0f%-2s %8.0f%-2s %12.0f %11.0f %10s\n", km[1], km[2], I[key], q, O[key], q, R[key], W[key] + H[key], c | "sort"
          if (q != "") anyq = 1
        }
        close("sort")
        printf "%-8s %-22s %62s\n", "total", "", sprintf("%.2f", tot)
        if (unpriced != "") print "n/a: no price for" unpriced " (add it to " prices "); the total leaves these out."
        if (anyq) print "+?: some entries named the model but not the token counts."
        print "USD is the pay-as-you-go API price. On a subscription plan you were not billed this per token."
      }' "$PAD" ;;
  *) sed -n '2,17p' "$0"; exit 2 ;;
esac
