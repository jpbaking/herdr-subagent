#!/usr/bin/env bash
# herdr-subagent.sh: run an interactive agent CLI as a visible herdr
# pseudo-subagent. Spawn it, prompt it with a fixed report contract, wait for
# the report, and close it after acceptance.
#
# Usage:
#   herdr-subagent.sh spawn  <name> <kind> [--layout split|tab] [--cwd DIR] [-- AGENT_ARGS...]
#   herdr-subagent.sh prompt <name> <prompt-file>     # prints the report path
#   herdr-subagent.sh wait   <name> <report-path> [timeout-seconds]
#   herdr-subagent.sh read   <name> [lines]
#   herdr-subagent.sh close  <name>
#   herdr-subagent.sh list
#
# Kinds: opencode, agy, codex, claude.
# wait exit codes: 0 success, 2 escalate, 3 failed, 4 blocked (prompt waiting
# in the pane), 5 idle without a report, 6 agent gone, 7 timeout.
set -euo pipefail

STATE_DIR="${HERDR_SUBAGENT_DIR:-${TMPDIR:-/tmp}/herdr-subagent}"
STATE_DIR="${STATE_DIR%/}"
STATE="$STATE_DIR/.state"
KINDS="opencode agy codex claude"

die() { echo "herdr-subagent: $*" >&2; exit 1; }

preflight() {
  command -v herdr >/dev/null || die "herdr not found on PATH"
  command -v jq >/dev/null || die "jq not found on PATH"
  [ -n "${HERDR_ENV:-}" ] || die "not running inside herdr (HERDR_ENV unset)"
  mkdir -p "$STATE"
}

state_get() { # name key
  [ -f "$STATE/$1" ] || die "no herdr-subagent named '$1' (see: list)"
  sed -n "s/^$2=//p" "$STATE/$1"
}

agent_status() { # name -> status or "gone"
  local out
  out=$(herdr agent get "$1" 2>/dev/null) || { echo gone; return; }
  jq -r '.result.agent.agent_status // "unknown"' <<<"$out"
}

cmd_spawn() {
  [ $# -ge 2 ] || die "usage: spawn <name> <kind> [--layout split|tab] [--cwd DIR] [-- AGENT_ARGS...]"
  local name=$1 kind=$2 layout=split cwd=$PWD out pane tab code i
  shift 2
  local -a args=()
  while [ $# -gt 0 ]; do
    case $1 in
      --layout) [ $# -ge 2 ] || die "--layout needs a value"; layout=$2; shift 2 ;;
      --cwd) [ $# -ge 2 ] || die "--cwd needs a value"; cwd=$2; shift 2 ;;
      --) shift; args=("$@"); break ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || die "name must match [A-Za-z0-9._-]+"
  case " $KINDS " in *" $kind "*) ;; *) die "unsupported kind '$kind' (supported: $KINDS)" ;; esac
  command -v "$kind" >/dev/null || die "'$kind' CLI not found on PATH"
  [ ! -f "$STATE/$name" ] || die "'$name' already exists; close it or pick another name"
  if herdr agent get "$name" >/dev/null 2>&1; then die "a herdr agent named '$name' already exists"; fi

  case $layout in
    split)
      out=$(herdr pane split --current --direction right --no-focus --cwd "$cwd")
      pane=$(jq -r '.result.pane.pane_id' <<<"$out")
      tab=$(jq -r '.result.pane.tab_id' <<<"$out") ;;
    tab)
      out=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$cwd" --label "$name" --no-focus)
      pane=$(jq -r '.result.root_pane.pane_id' <<<"$out")
      tab=$(jq -r '.result.tab.tab_id' <<<"$out") ;;
    *) die "layout must be split or tab" ;;
  esac
  [ -n "$pane" ] && [ "$pane" != null ] || die "could not create a pane: $out"
  printf 'pane=%s\ntab=%s\nlayout=%s\nkind=%s\n' "$pane" "$tab" "$layout" "$kind" >"$STATE/$name"

  # A new pane's shell is not ready at once; retry while herdr says it is busy.
  for i in $(seq 1 40); do
    if out=$(herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 90000 -- ${args[@]+"${args[@]}"} 2>&1); then
      break
    fi
    code=$(jq -r '.error.code // empty' <<<"$out" 2>/dev/null || true)
    [ "$code" = agent_pane_busy ] || break
    sleep 0.5
  done

  if [ "$(jq -r '.result.type // empty' <<<"$out" 2>/dev/null || true)" != agent_started ]; then
    echo "$out" >&2
    die "start failed after $i attempt(s); pane $pane left open for inspection (remove it with: close $name)"
  fi
  echo "spawned name=$name kind=$kind layout=$layout pane=$pane tab=$tab"
}

cmd_prompt() {
  [ $# -eq 2 ] || die "usage: prompt <name> <prompt-file>"
  local name=$1 file=$2 report text out
  [ -r "$file" ] || die "cannot read prompt file: $file"
  state_get "$name" pane >/dev/null
  report="$STATE_DIR/$name-$(date +%Y%m%d-%H%M%S).md"
  # One line: a newline typed into a TUI can submit the prompt early.
  text="$(tr '\n' ' ' <"$file") REPORT CONTRACT: when you finish or must stop, write a compact Markdown report to $report (this write is always allowed). Write it in the order: what you did, evidence (commands run and their results, file:line), open questions. Its last line must be exactly one of: 'STATUS: success', 'STATUS: escalate - <the exact question or blocker>', 'STATUS: failed - <reason>'. Escalate instead of guessing. Then reply with only: REPORTED $report"
  out=$(herdr agent prompt "$name" "$text" 2>&1) || die "prompt failed: $out"
  echo "$report"
}

cmd_wait() {
  [ $# -ge 2 ] || die "usage: wait <name> <report-path> [timeout-seconds]"
  local name=$1 report=$2 timeout=${3:-1800} start now st line seen_working=0 idle_since=0 blocked=0
  state_get "$name" pane >/dev/null
  start=$(date +%s)
  while :; do
    now=$(date +%s)
    st=$(agent_status "$name")
    [ "$st" = working ] && seen_working=1
    if [ -f "$report" ] && line=$(grep -E '^STATUS: ' "$report" | tail -n 1) && [ -n "$line" ]; then
      # Let the agent finish its turn before the planner reads or steers.
      if [ "$st" = working ] && [ $((now - start)) -lt "$timeout" ]; then
        sleep 3; continue
      fi
      echo "$line"
      case $line in
        "STATUS: success"*) exit 0 ;;
        "STATUS: escalate"*) exit 2 ;;
        *) exit 3 ;;
      esac
    fi
    [ "$st" = gone ] && { echo "GONE: agent $name no longer exists"; exit 6; }
    if [ "$st" = blocked ]; then
      blocked=$((blocked + 1))
      [ "$blocked" -ge 2 ] && { echo "BLOCKED: $name is waiting for input; read its pane"; exit 4; }
    else
      blocked=0
    fi
    if [ "$seen_working" = 1 ] && { [ "$st" = idle ] || [ "$st" = "done" ]; }; then
      [ "$idle_since" = 0 ] && idle_since=$now
      [ $((now - idle_since)) -ge 45 ] && { echo "IDLE-NO-REPORT: $name stopped without writing $report"; exit 5; }
    else
      idle_since=0
    fi
    [ $((now - start)) -ge "$timeout" ] && { echo "TIMEOUT: no report after ${timeout}s (status: $st)"; exit 7; }
    sleep 3
  done
}

cmd_read() {
  [ $# -ge 1 ] || die "usage: read <name> [lines]"
  herdr pane read "$(state_get "$1" pane)" --lines "${2:-40}" | grep -v '^[[:space:]]*$' || true
}

cmd_close() {
  [ $# -eq 1 ] || die "usage: close <name>"
  local name=$1 pane tab layout
  pane=$(state_get "$name" pane); tab=$(state_get "$name" tab); layout=$(state_get "$name" layout)
  if [ "$layout" = tab ]; then
    herdr tab close "$tab" >/dev/null 2>&1 || herdr pane close "$pane" >/dev/null 2>&1 || true
    echo "closed $name (tab $tab); reports kept in $STATE_DIR"
  else
    herdr pane close "$pane" >/dev/null 2>&1 || true
    echo "closed $name (pane $pane); reports kept in $STATE_DIR"
  fi
  rm -f "$STATE/$name"
}

cmd_list() {
  local f name
  for f in "$STATE"/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    printf '%s kind=%s layout=%s pane=%s status=%s\n' "$name" \
      "$(state_get "$name" kind)" "$(state_get "$name" layout)" \
      "$(state_get "$name" pane)" "$(agent_status "$name")"
  done
}

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; }

sub=${1:-}
[ $# -gt 0 ] && shift
case $sub in
  spawn) preflight; cmd_spawn "$@" ;;
  prompt) preflight; cmd_prompt "$@" ;;
  wait) preflight; cmd_wait "$@" ;;
  read) preflight; cmd_read "$@" ;;
  close) preflight; cmd_close "$@" ;;
  list) preflight; cmd_list ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 1 ;;
esac
