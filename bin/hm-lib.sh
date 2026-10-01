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
# A pane is identified by its process and that process's start time: a pane id alone is handed out again by a restarted
# tmux server. These three are the only place that is read and compared (the registry's writer and hook, the manifest
# and cleanup use them).
hm_pane_pid() { tmux -S "$1" display-message -p -t "$2" '#{pane_pid}' 2>/dev/null | grep -E '^[0-9]+$'; }   # hm_pane_pid <socket> <pane>: empty when the server has no such pane
hm_pane_identity() {  # hm_pane_identity <socket> <pane>: "<pid><TAB><start time>", or fails when the pane cannot be read
  local pid; pid=$(hm_pane_pid "$1" "$2") || return 1
  printf '%s\t%s\n' "$pid" "$(hm_lstart "$pid")"
}
hm_pane_is() {  # hm_pane_is <socket> <pane> <pid> <started>: 0 it is that pane, 1 the pane is another (or the record is empty), 2 the pane cannot be read
  local cur; cur=$(hm_pane_pid "$1" "$2") || return 2
  [ -n "$3" ] && [ -n "$4" ] && [ "$cur" = "$3" ] && [ "$(hm_lstart "$cur")" = "$4" ]
}
hm_claude_ancestor() {  # hm_claude_ancestor [pid]: the nearest Claude process at or above pid (default: this process), or fails
  local p="${1:-$$}" i=0
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ "$i" -lt 64 ]; do
    hm_is_claude "$p" && { echo "$p"; return 0; }
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); i=$((i + 1))
  done
  return 1
}
hm_claude_is() {  # hm_claude_is <pid> <started>: that very process (not a reused pid), still Claude
  [ -n "$1" ] && [ -n "$2" ] && hm_alive "$1" && [ "$(hm_lstart "$1")" = "$2" ] && hm_is_claude "$1"
}
hm_agent_is() {  # hm_agent_is <socket> <pane> <pane pid> <pane started> [<claude pid> <claude started>]: 0 the agent is still there, as recorded; 1 it is not; 2 the pane cannot be read
  hm_pane_is "$1" "$2" "$3" "$4"; local rc=$?; [ "$rc" -eq 0 ] || return "$rc"
  [ -z "${5:-}" ] || hm_claude_is "$5" "${6:-}"
}
hm_socket() { if [ -n "${HM_TMUX_SOCKET:-}" ]; then echo "$HM_TMUX_SOCKET"; else tmux display -p '#{socket_path}'; fi; }

# ---- mkdir locks (macOS has no flock). Used by hm-slot and hm-manifest. -------------------------------------------
# A lock is a directory holding holder.json {pid, lstart, created, ...}. A holder is stale when its pid is dead, when
# the pid is alive with another start time (pid reuse), or when holder.json is missing or empty and the directory is
# older than 10 s. A stale lock is taken over inside a guard directory "<lock>.takeover" (itself stale after 30 s),
# after re-reading the holder, so exactly one contender removes it. `kill -9` of a holder frees its lock.
hm_alive()  { ps -p "$1" >/dev/null 2>&1; }
hm_lstart() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'; }
hm_is_claude() {  # hm_is_claude <pid>: 0 when the process is Claude Code's, which hivemind never stops
  local args first second   # by argv: macOS ps reports comm from argv0 as well, so it would be the same reading
  args=$(ps -o args= -p "$1" 2>/dev/null) || return 1
  first=${args%% *}; second=${args#* }; second=${second%% *}
  [ "${first##*/}" = claude ] && return 0
  case "${first##*/}" in node|bash|sh|zsh) [ "${second##*/}" = claude ] && return 0 ;; esac   # run by an interpreter
  case "$args" in *@anthropic-ai/claude-code/*) return 0 ;; esac
  return 1
}
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

# The owner's statusLine as Claude Code picks it for a session started in <dir>: managed settings, then the project's
# local file, then the project's own, then the user's (checked against Claude Code 2.1.286). Prints the statusLine object,
# or nothing when none is set. HM_MANAGED_SETTINGS names the managed file (tests point it elsewhere).
hm_managed_settings() {
  if [ -n "${HM_MANAGED_SETTINGS:-}" ]; then echo "$HM_MANAGED_SETTINGS"
  elif [ "$(uname)" = Darwin ]; then echo "/Library/Application Support/ClaudeCode/managed-settings.json"
  else echo "/etc/claude-code/managed-settings.json"; fi
}
hm_owner_statusline() {  # hm_owner_statusline <session cwd>
  local f
  for f in "$(hm_managed_settings)" "$1/.claude/settings.local.json" "$1/.claude/settings.json" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; do
    [ -f "$f" ] && jq -ce '.statusLine | select(type == "object")' "$f" 2>/dev/null && return 0
  done
  return 0
}

# An agent's session record, .hivemind/team/<agent>/session.json {session_id, transcript_path, source, at}: hm-context reads
# it. The one writer, for the SessionStart hook and for hm-spawn --self. Never writes for a bad agent name or into a tracked
# .hivemind; the write is atomic. Returns 1 when nothing was written.
hm_write_session() {  # hm_write_session <project root> <agent> <session id> <transcript path> <source>
  local dir="$1/.hivemind/team/$2"
  hm_is_agent_name "$2" && [ -n "$3" ] || return 1
  [ -z "$(git -C "$1" ls-files -- .hivemind 2>/dev/null)" ] || return 1
  mkdir -p "$dir" 2>/dev/null || return 1
  jq -nc --arg s "$3" --arg t "$4" --arg src "$5" --arg at "$(hm_now)" '{session_id:$s, transcript_path:$t, source:$src, at:$at}' \
    > "$dir/session.json.tmp$$" 2>/dev/null && mv "$dir/session.json.tmp$$" "$dir/session.json" || { rm -f "$dir/session.json.tmp$$"; return 1; }
}

# The line that starts (hm-spawn) or restarts (hm-rotate) an agent from its handoff: one text, so they cannot drift. The
# orchestrator itself (hm-self-rotate) reports to nobody, waits for nobody, and --self gives it no role or rules dir.
hm_pickup_line() {  # hm_pickup_line <project name> <project root> <agent>
  if [ "$(hm_self_entry "$2" | jq -r '.name // empty' 2>/dev/null)" = "$3" ]; then
    printf 'You are %s. Read %s/.hivemind/handoffs/%s.md from the top: its START HERE block is your prompt.' "$(hm_orchestrator_name "$2")" "$2" "$3"
    return
  fi
  printf 'You are %s-%s. Read %s/.hivemind/handoffs/%s.md from the top: its START HERE block is your prompt, and %s/.hivemind/team/%s/ holds your role and the rules. Report to %s. Wait for its first message before any work.' \
    "$1" "$3" "$2" "$3" "$2" "$3" "$(hm_orchestrator_name "$2")"
}

# The ASCII letters and digits, listed and never written as a range: under bash 3.2 a bracket range follows the locale's
# collation, and in en_US.UTF-8 `[a-z]` takes capitals, é, ß and fullwidth letters too. Every check of a name builds its
# bracket expression from these, unquoted inside the brackets (the lists hold no pattern character).
HM_LOWER='abcdefghijklmnopqrstuvwxyz'
HM_UPPER='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
HM_DIGITS='0123456789'

# A session name hivemind will type into a pane (it goes through send-keys): one line of letters, digits, space, '-', '_',
# '.', '(' and ')', at most 64 characters.
HM_SESSION_NAME_CHARS="${HM_LOWER}${HM_UPPER}${HM_DIGITS} ._()-"
hm_is_session_name() {  # hm_is_session_name <name>: 0 when it is one
  case "$1" in ''|*[!$HM_SESSION_NAME_CHARS]*) return 1 ;; esac
  [ "${#1}" -le 64 ]
}
# Claude Code's own record of a running session, <config dir>/sessions/<pid>.json (undocumented, checked against
# 2.1.286): prints the field when the record is that pid's, else nothing. A missing file or field, another pid or a file
# that is not JSON is no answer, never an error.
hm_session_record() {  # hm_session_record <pid> <jq path>
  case "$1" in ''|*[!0-9]*) return 0 ;; esac
  jq -j --arg p "$1" "select((.pid | tostring) == \$p) | $2 // empty" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/$1.json" 2>/dev/null
}
hm_session_transcript() {  # hm_session_transcript <session id>: the one <id>.jsonl under <config dir>/projects/*/, else fails
  local m n
  case "$1" in ''|*[!${HM_LOWER}${HM_UPPER}${HM_DIGITS}-]*) return 1 ;; esac
  m=$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" -mindepth 2 -maxdepth 2 -type f -name "$1.jsonl" 2>/dev/null)
  n=$(printf '%s' "$m" | grep -c .)
  [ "$n" -eq 1 ] && printf '%s\n' "$m"
}
hm_self_entry() {  # hm_self_entry <project root>: the team.json entry hm-spawn --self wrote (only it records a Claude process), or nothing
  jq -c '[.agents[]? | select((.claude_pid // "") != "")][0] // empty' "$1/.hivemind/team.json" 2>/dev/null
}
# The name agents report to: the --self orchestrator's session name as Claude Code has it now (a /rename after --self is
# followed), else the name recorded at --self, else <project>-orchestrator. One helper for every text that names it.
hm_orchestrator_name() {  # hm_orchestrator_name <project root>
  local o pid started live="" full n
  o=$(hm_self_entry "$1")
  pid=$(printf '%s' "$o" | jq -r '.claude_pid // empty' 2>/dev/null); started=$(printf '%s' "$o" | jq -r '.claude_started // empty' 2>/dev/null)
  full=$(printf '%s' "$o" | jq -r '.name_full // empty' 2>/dev/null)
  if [ -n "$pid" ] && hm_claude_is "$pid" "$started"; then
    live=$(hm_session_record "$pid" .name)
  fi
  for n in "$live" "$full"; do
    [ -n "$n" ] || continue
    hm_is_session_name "$n" && { printf '%s\n' "$n"; return 0; }
    echo "hivemind: the orchestrator's session name is not one hivemind will type; using another" >&2
  done
  printf '%s-orchestrator\n' "$(basename "$1")"
}

# A gate's step name, the one rule hm-gate's steps and hm-gate-verify's expected names and lines are read by: letters,
# digits, '_', '.' and '-', with no '..' (A13). HM_STEP_NAME_CHARS is a bracket expression's contents, built from the lists
# above with '-' last, so no reader (grep -E, sed -E or a case) can take it as a range.
HM_STEP_NAME_CHARS="${HM_UPPER}${HM_LOWER}${HM_DIGITS}_.-"
HM_STEP_NAME_RULE="letters, digits, '_', '.' and '-' with no '..'"
hm_is_step_name() {  # hm_is_step_name <name>: 0 when it is one
  printf '%s' "$1" | grep -Eq "^[${HM_STEP_NAME_CHARS}]+\$" || return 1
  case "$1" in *..*) return 1 ;; esac
  return 0
}

# An agent's name, the one rule hm-spawn and the session hook read: lower-case letters, digits, '_' and '-', not starting
# with '_' or '-'.
hm_is_agent_name() {  # hm_is_agent_name <name>: 0 when it is one
  case "$1" in ''|*[!${HM_LOWER}${HM_DIGITS}_-]*|[-_]*) return 1 ;; esac
  return 0
}

# A git branch as hivemind takes one (hm-spawn's --branch and --base, the manifest's base): letters, digits, '.', '_',
# '/' and '-', not starting with '-', which git would read as an option.
hm_is_branch_name() {  # hm_is_branch_name <name>: 0 when it is one
  case "$1" in ''|-*|*[!${HM_LOWER}${HM_UPPER}${HM_DIGITS}._/-]*) return 1 ;; esac
  return 0
}

# A remote host as hivemind takes one (hm-remote-sync's host, the manifest's host): letters, digits, '.', '_', '@' and
# '-', not starting with '-', which ssh would read as an option.
hm_is_host_name() {  # hm_is_host_name <name>: 0 when it is one
  case "$1" in ''|-*|*[!${HM_LOWER}${HM_UPPER}${HM_DIGITS}._@-]*) return 1 ;; esac
  return 0
}
