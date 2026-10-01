#!/usr/bin/env bash
# Shared by every hm-* executable. bash 3.2 compatible. Never reads plugin variables: settings arrive as arguments
# or HM_* environment set by hm-spawn.
# A command substitution does not stop its caller: write x=$(hm_project_root) || exit $?, never a bare x=$(...).
hm_die()  { echo "hivemind: $2" >&2; exit "$1"; }
hm_home() { printf '%s\n' "${HIVEMIND_HOME:-$HOME/.hivemind}"; }
hm_now()  { date -u +%Y-%m-%dT%H:%M:%SZ; }
hm_project_root() {
  if [ -n "${HM_PROJECT:-}" ]; then
    [ -d "$HM_PROJECT" ] || hm_die 2 "HM_PROJECT is not a directory: $HM_PROJECT"
    (cd "$HM_PROJECT" && pwd -P); return
  fi
  local common; common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || hm_die 2 "not inside a git repository and HM_PROJECT is not set"
  case "$common" in */.git) (cd "${common%/.git}" && pwd -P) ;; *) hm_die 2 "unsupported repository layout: $common" ;; esac
}
hm_project_key() {  # basename plus a short hash of the full path: webapp and webapp-impl never clash
  local p="$1"; printf '%s-%s\n' "$(basename "$p")" "$(printf '%s' "$p" | shasum | cut -c1-6)"
}
hm_state() { local root; root=$(hm_project_root) || exit $?; printf '%s/.hivemind\n' "$root"; }
hm_ensure_state() {  # creates .hivemind/, excludes it through info/exclude, refuses if any of it is tracked
  local root common excl
  root=$(hm_project_root) || exit $?
  common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir) || exit $?
  if [ -n "$(git -C "$root" ls-files -- .hivemind)" ]; then
    hm_die 3 "files under .hivemind/ are tracked by git; untrack them before using hivemind here"
  fi
  mkdir -p "$root/.hivemind" "$common/info"
  excl="$common/info/exclude"; touch "$excl"
  grep -qx '/.hivemind/' "$excl" || echo '/.hivemind/' >> "$excl"
}
hm_json_get() { jq -r "$2 // empty" "$1" 2>/dev/null; }   # hm_json_get <file> <jq path>
hm_registry_dir() { printf '%s/registry/panes\n' "$(hm_home)"; }
hm_pane_key() {  # hm_pane_key <socket> <pane id> -> filename-safe key
  printf '%s' "$1|$2" | shasum | cut -c1-16
}
hm_tmux() { if [ -n "${HM_TMUX_SOCKET:-}" ]; then tmux -S "$HM_TMUX_SOCKET" "$@"; else tmux "$@"; fi; }
hm_socket() { if [ -n "${HM_TMUX_SOCKET:-}" ]; then echo "$HM_TMUX_SOCKET"; else tmux display -p '#{socket_path}'; fi; }

# ---- mkdir locks (macOS has no flock). Used by hm-slot and hm-manifest. -------------------------------------------
# A lock is a directory holding holder.json {pid, lstart, created, ...}. A holder is stale when its pid is dead, when
# the pid is alive with another start time (pid reuse), or when holder.json is missing or empty and the directory is
# older than 10 s. A stale lock is taken over inside a guard directory "<lock>.takeover" (itself stale after 30 s),
# after re-reading the holder, so exactly one contender removes it. `kill -9` of a holder frees its lock.
hm_alive()  { ps -p "$1" >/dev/null 2>&1; }
hm_lstart() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'; }
hm_dir_age() {  # seconds since the directory was last modified
  local m; m=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || return 1
  echo $(( $(date +%s) - m ))
}
hm_holder_json() {  # hm_holder_json <pid> [extra json object] -> the holder record
  local x="${2:-}"; [ -n "$x" ] || x='{}'
  jq -nc --argjson pid "$1" --arg l "$(hm_lstart "$1")" --argjson c "$(date +%s)" --argjson x "$x" \
    '{pid:$pid,lstart:$l,created:$c} + $x'
}
hm_lock_stale() {  # hm_lock_stale <lock>: 0 when the holder is gone
  local h="$1/holder.json" pid ls age
  pid=$(hm_json_get "$h" .pid); ls=$(hm_json_get "$h" .lstart)
  if [ -z "$pid" ]; then age=$(hm_dir_age "$1") || return 1; [ "$age" -gt 10 ]; return; fi
  hm_alive "$pid" || return 0
  [ "$(hm_lstart "$pid")" != "$ls" ]
}
hm_lock_try() {  # hm_lock_try <lock> <holder json>: 0 taken, 1 busy
  local lock="$1" json="$2" guard age snap
  mkdir -p "$(dirname "$lock")"
  if mkdir "$lock" 2>/dev/null; then printf '%s\n' "$json" > "$lock/holder.json"; return 0; fi
  snap=$(cat "$lock/holder.json" 2>/dev/null)
  hm_lock_stale "$lock" || return 1
  guard="$lock.takeover"
  if ! mkdir "$guard" 2>/dev/null; then
    age=$(hm_dir_age "$guard") || return 1
    [ "$age" -gt 30 ] || return 1
    rmdir "$guard" 2>/dev/null; mkdir "$guard" 2>/dev/null || return 1
  fi
  if [ "$(cat "$lock/holder.json" 2>/dev/null)" != "$snap" ] || ! hm_lock_stale "$lock"; then
    rmdir "$guard" 2>/dev/null; return 1   # somebody else took it over first
  fi
  mv "$lock" "$lock.stale.$$" 2>/dev/null && rm -rf "$lock.stale.$$"
  if mkdir "$lock" 2>/dev/null; then
    printf '%s\n' "$json" > "$lock/holder.json"; rmdir "$guard" 2>/dev/null; return 0
  fi
  rmdir "$guard" 2>/dev/null; return 1
}
hm_lock_release() {  # hm_lock_release <lock> <pid>: removes the lock only when the record is that process's own
  local hp hl
  hp=$(hm_json_get "$1/holder.json" .pid); hl=$(hm_json_get "$1/holder.json" .lstart)
  [ -n "$hp" ] && [ "$hp" = "$2" ] && [ "$hl" = "$(hm_lstart "$2")" ] || return 1
  rm -rf "$1"
}

# ---- idle detection ------------------------------------------------------------------------------------------------
# TIED TO THE CLAUDE CODE TERMINAL UI (checked against 2.1.x). When a release changes how the prompt box is drawn or how a
# dialog is worded, update HM_DIALOG_TEXT and hm_pane_idle_text. The prompt box is a rule, "❯", a no-break space and a dim
# placeholder (the placeholder comes back after C-u and /clear), a rule, and a footer. A pane is idle when it is still, its
# last lines show an empty prompt, and no dialog is up. Dialog wording is looked for from the box's top rule down only,
# so a dialog quoted in the conversation above is not mistaken for a live one; with fewer than two rules it is looked for
# everywhere (a refusal to type is the safe error).
HM_DIALOG_TEXT=("Do you trust" "Yes, proceed" "Esc to cancel" "Do you want to" "Allow this" "Press Enter to continue" "Enter to confirm" "I trust this folder")
hm_pane_clean() {  # a pane captured with -e on stdin: drop dim runs (the placeholder), other escapes, and no-break spaces
  perl -pe 's/\e\[(?:[01];)?2m.*?(?:\e\[(?:0|22)?m|$)//g; s/\e\[[0-9;?]*[A-Za-z]//g; s/\xc2\xa0/ /g'
}
hm_pane_text() { hm_tmux capture-pane -p -e -J -t "$1" 2>/dev/null | hm_pane_clean; }   # hm_pane_text <pane>
hm_pane_box() {  # a cleaned pane on stdin: the prompt box and what is below it (from the second-to-last rule), else all of it
  local text top
  text=$(cat)
  top=$(printf '%s\n' "$text" | grep -nE '^[[:space:]]*(─){4,}' | tail -2 | head -1 | cut -d: -f1)
  if [ "$(printf '%s\n' "$text" | grep -cE '^[[:space:]]*(─){4,}')" -ge 2 ] && [ -n "$top" ]; then
    printf '%s\n' "$text" | tail -n +"$top"
  else printf '%s\n' "$text"; fi
}
hm_pane_prompt_line() {  # a pane on stdin: the input line in its prompt box (the last line that starts with the prompt mark)
  hm_pane_clean | hm_pane_box | grep -E '^(│| )*(>|❯)' | tail -1
}
hm_pane_idle_text() {  # a cleaned pane on stdin: 0 an empty prompt and no dialog, 1 no empty prompt, 3 a dialog is up
  local text region p
  text=$(hm_pane_clean)   # idempotent: callers may hand it a cleaned pane or a raw one
  region=$(printf '%s\n' "$text" | hm_pane_box)
  for p in "${HM_DIALOG_TEXT[@]}"; do case "$region" in *"$p"*) return 3 ;; esac; done
  printf '%s\n' "$text" | grep -v '^[[:space:]]*$' | tail -6 | grep -Eq '^(│| )*(>|❯)( |│)*$'
}
# wait_idle <pane> <seconds still> <max seconds>: 0 idle, 1 timed out, 3 timed out with a dialog on screen (the caller
# tells the orchestrator; nothing here ever types into a pane).
wait_idle() {
  local prev="" cur text still=0 waited=0 rc=1
  while [ "$waited" -lt "$3" ]; do
    hm_tmux display-message -p -t "$1" '#{pane_id}' >/dev/null 2>&1 || return 1   # the pane is gone
    text=$(hm_pane_text "$1")
    cur=$(printf '%s' "$text" | shasum)
    if [ "$cur" = "$prev" ]; then still=$((still + 1)); else still=0; fi
    prev="$cur"
    printf '%s\n' "$text" | hm_pane_idle_text; rc=$?
    [ "$still" -ge "$2" ] && [ "$rc" -eq 0 ] && return 0
    sleep 1; waited=$((waited + 1))
  done
  [ "$rc" -eq 3 ] && return 3
  return 1
}

# The line that starts (hm-spawn) or restarts (hm-rotate) an agent from its handoff: one text, so they cannot drift.
hm_pickup_line() {  # hm_pickup_line <project name> <project root> <agent>
  printf 'You are %s-%s. Read %s/.hivemind/handoffs/%s.md from the top: its START HERE block is your prompt, and %s/.hivemind/team/%s/ holds your role and the rules. Report to %s-orchestrator. Wait for its first message before any work.' \
    "$1" "$3" "$2" "$3" "$2" "$3" "$1"
}

# A gate's step name, the one rule hm-gate's steps and hm-gate-verify's expected names and lines are read by: letters,
# digits, '_', '.' and '-', with no '..' (A13). HM_STEP_NAME_CHARS is a bracket expression's contents, '-' last.
HM_STEP_NAME_CHARS='A-Za-z0-9_.-'
HM_STEP_NAME_RULE="letters, digits, '_', '.' and '-' with no '..'"
hm_is_step_name() {  # hm_is_step_name <name>: 0 when it is one
  printf '%s' "$1" | grep -Eq "^[${HM_STEP_NAME_CHARS}]+\$" || return 1
  case "$1" in *..*) return 1 ;; esac
  return 0
}

# An agent's name, the one rule hm-spawn and the session hook read: lower-case letters, digits, '_' and '-', not starting
# with '_' or '-'. The letters are listed, never a range: under bash 3.2 `[a-z]` follows the locale's collation, and in
# en_US.UTF-8 it takes capitals too.
hm_is_agent_name() {  # hm_is_agent_name <name>: 0 when it is one
  case "$1" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*|[-_]*) return 1 ;; esac
  return 0
}
