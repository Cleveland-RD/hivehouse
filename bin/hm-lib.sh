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
# hm_tmux_on <socket, or empty for hivemind's own server> <tmux args>...: the one way to reach a session's pane on the server
# it was recorded on (team.json .socket), which is not always hivemind's own
hm_tmux_on() { local s="$1"; shift; if [ -n "$s" ]; then tmux -S "$s" "$@"; else hm_tmux "$@"; fi; }
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
# Is a team member still running as team.json recorded it? 0 yes; 1 no; 2 cannot tell (its process is alive but no tmux
# answers for its pane); 3 not on the team, or recorded with no identity. The one check hm-rotate, hm-context and
# hm-spawn --respawn make. The recorded process is read first: a missing pane reads to tmux as "cannot be read", the same
# as a server that does not answer, yet after a restart it is simply gone. A spawned agent's pane process is its Claude;
# the --self orchestrator's pane is the owner's shell, so its own Claude is what is checked.
hm_team_agent_is() {  # hm_team_agent_is <project root> <agent>
  local e socket pane ppid pstarted cpid cstarted
  # one read, fields joined by the unit separator: a whitespace separator would fold an empty field into its neighbour
  e=$(jq -r --arg a "$2" '[.agents[]? | select(.name == $a)][0] // empty
      | [.socket, .pane, .pane_pid, .pane_started, .claude_pid, .claude_started] | map(. // "" | tostring) | join("\u001f")' \
      "$1/.hivemind/team.json" 2>/dev/null)
  [ -n "$e" ] || return 3
  IFS=$'\x1f' read -r socket pane ppid pstarted cpid cstarted <<< "$e"
  [ -n "$pane" ] && [ -n "$ppid" ] && [ -n "$pstarted" ] || return 3
  [ -n "$cpid" ] || { hm_recorded_pane_is "$socket" "$pane" "$ppid" "$pstarted"; return; }
  hm_claude_is "$cpid" "$cstarted" || return 1
  hm_agent_is "$socket" "$pane" "$ppid" "$pstarted" "$cpid" "$cstarted"
}
# hm_recorded_pane_is <socket> <pane> <pid> <started>: is a recorded pane still that pane? 0 yes; 1 no; 2 cannot tell. Its
# process first: a missing pane reads to tmux as "cannot be read", the same as a server that does not answer, yet after a
# restart it is simply gone. hm_team_agent_is (a spawned agent) and hm-hub (a pane the hub started) both read it here.
hm_recorded_pane_is() {
  [ -n "$3" ] && hm_alive "$3" && [ "$(hm_lstart "$3")" = "$4" ] || return 1
  hm_pane_is "$1" "$2" "$3" "$4"
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
hm_pane_text() { hm_tmux_on "${2:-}" capture-pane -p -e -J -t "$1" 2>/dev/null | hm_pane_clean; }   # hm_pane_text <pane> [socket]
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
# wait_idle <pane> <seconds still> <max seconds> [socket]: 0 idle, 1 timed out, 3 a dialog on screen (the caller tells the
# orchestrator; nothing here ever types into a pane). A dialog that has been still as long as idle must be is told then,
# not waited out: it does not go away by itself.
wait_idle() {
  local prev="" cur text still=0 waited=0 rc=1
  while [ "$waited" -lt "$3" ]; do
    hm_tmux_on "${4:-}" display-message -p -t "$1" '#{pane_id}' >/dev/null 2>&1 || return 1   # the pane is gone
    text=$(hm_pane_text "$1" "${4:-}")
    cur=$(printf '%s' "$text" | shasum)
    if [ "$cur" = "$prev" ]; then still=$((still + 1)); else still=0; fi
    prev="$cur"
    printf '%s\n' "$text" | hm_pane_idle_text; rc=$?
    [ "$still" -ge "$2" ] && [ "$rc" -eq 0 ] && return 0
    [ "$still" -ge "$2" ] && [ "$rc" -eq 3 ] && return 3
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
    # registered with --hub: the owner talks to it through the hub, which a /clear would otherwise forget
    local hub; hub=$(hm_self_entry "$2" | jq -r '.hub // empty' 2>/dev/null)
    if [ -n "$hub" ] && hm_is_session_name "$hub"; then
      printf ' The owner talks to you only through %s: send it your questions, plans, blockers and finished work with SendMessage, and take its OWNER replies as the owner'"'"'s words.' "$hub"
    fi
    # the owner's output style, when installed, is read again after every clear (a /clear wipes it with the rest)
    local style; style=$(hm_adhd_skill 2>/dev/null) || return 0
    if hm_is_typed_path "$style"; then printf ' Read %s and follow it for every message to the owner.' "$style"
    else echo "hivemind: the i-have-adhd path is not one hivemind will type, so the pickup line leaves it out: $style" >&2; fi
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
# The i-have-adhd output style (an optional companion plugin): its SKILL.md when Claude Code lists a plugin of that name,
# from any marketplace, as enabled and the file is there. Reads `claude plugin list --json` and tests the file, nothing
# else; never installs, enables or switches it on. When its always-on flag exists the plugin already applies itself to
# every session, so it is not loaded a second time. Prints the path, or fails.
hm_adhd_skill() {
  local flag="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.i-have-adhd-always" d
  if [ -e "$flag" ]; then echo "hivemind: i-have-adhd is always on ($flag) and applies itself; not loaded again" >&2; return 1; fi
  while IFS= read -r d; do
    [ -n "$d" ] && [ -f "$d/skills/i-have-adhd/SKILL.md" ] && { printf '%s\n' "$d/skills/i-have-adhd/SKILL.md"; return 0; }
  done <<EOF2
$(claude plugin list --json 2>/dev/null | jq -r '.[]? | select(((.id // "") | startswith("i-have-adhd@")) and .enabled == true) | .installPath // empty' 2>/dev/null)
EOF2
  return 1
}
# A path hivemind will type into a pane: one line of letters, digits, '/', '.', '_', '-' and space, at most 256 characters.
hm_is_typed_path() {  # hm_is_typed_path <path>: 0 when it is one
  local chars="${HM_LOWER}${HM_UPPER}${HM_DIGITS}/._ -"
  case "$1" in ''|*[!$chars]*) return 1 ;; esac
  [ "${#1}" -le 256 ]
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

# ---- reading a dialog (the hub shows it to the owner, who answers through hm-hub answer) ------------------------------
# TIED TO THE CLAUDE CODE TERMINAL UI (captured from 2.1.291; tests/fixtures/dialogs/). A dialog replaces the prompt box: a
# rule, its text, then options and a footer line ("Esc to cancel", "Enter to confirm", "Enter to select"). Permission and
# AskUserQuestion dialogs number their options "1. Yes", and a digit selects and confirms; the folder-trust dialog does not:
# its rows are moved to with the arrow keys and confirmed with Enter, the "❯" marking the row the cursor is on. The region is
# found from the footer up to the topmost rule above it, stopping at what the conversation looks like (a tool line, the
# user's echoed prompt); lines are right-trimmed, so a screen's padding never changes its fingerprint.
HM_DIALOG_FOOTER='Esc to cancel|Enter to confirm|Enter to select|Press Enter to continue'
# options the hub never offers: they need the owner's own text, or are keys rather than choices
HM_DIALOG_NOT_OFFERED='^(Type something\.?|Chat about this)$'
IFS= read -r -d '' HM_DIALOG_PERL <<'PERL' || true
use strict; use warnings; use utf8; use JSON::PP;
binmode(STDIN, ':utf8'); binmode(STDOUT, ':utf8');
my ($footer_re, $not_offered_re) = @ARGV;
my @l = map { my $s = $_; $s =~ s/\s+$//; $s } <STDIN>;
my $last = $#l; $last-- while $last >= 0 && $l[$last] eq '';
my $F = -1;
for my $i (reverse 0 .. $last) { if ($l[$i] =~ /(?:$footer_re)/) { $F = $i; last } }
$F = $last if $F < 0;
exit 3 if $F < 0;
my ($start, $seen_rule) = (-1, 0);
for (my $i = $F - 1; $i >= 0; $i--) {
  my $s = $l[$i];
  if ($s =~ /^\s*─{4,}/) { $start = $i; $seen_rule = 1; next }
  last if $seen_rule && ($s =~ /^\s*(?:⏺|✻|✳|✽|⎿)/ || $s =~ /^❯ (?!\d\.\s)/);
}
$start = ($F - 12 > 0 ? $F - 12 : 0) if $start < 0;
my @r = @l[$start .. $F];
my (@runs, $run);
for my $i (0 .. $#r) {
  next unless $r[$i] =~ /^\s*(❯)?\s*(\d)\.\s+(\S.*)$/;
  my ($cur, $n, $label) = ($1, $2, $3);
  if ($n == 1) { $run = []; push @runs, $run }
  elsif (!$run || $n != $run->[-1]{n} + 1) { next }
  push @$run, { n => $n + 0, label => $label, line => $i, cursor => ($cur ? 1 : 0) };
}
my ($kind, @opts, $cursor) = ('none');
if (@runs) {
  $kind = 'numbered';
  for my $o (@{ $runs[-1] }) {
    my @detail;
    for (my $k = $o->{line} + 1; $k <= $#r; $k++) {
      last if $r[$k] eq '' || $r[$k] =~ /^\s*─{4,}/ || $r[$k] =~ /^\s*(?:❯\s*)?\d\.\s/ || $k == $#r;
      last unless $r[$k] =~ /^\s{4,}\S/;
      (my $t = $r[$k]) =~ s/^\s+//; push @detail, $t;
    }
    my $detail = join(' ', @detail);
    $cursor = $o->{n} if $o->{cursor};
    push @opts, { n => $o->{n}, label => $o->{label}, detail => $detail,
      offered => ($o->{label} =~ /$not_offered_re/i ? JSON::PP::false : JSON::PP::true),
      saves_rule => (("$o->{label} $detail" =~ /always allow|don't ask again|switch to accept edits/i) ? JSON::PP::true : JSON::PP::false) };
  }
} else {
  my $ci = -1;
  for my $i (reverse 0 .. $#r) { if ($r[$i] =~ /^\s*❯\s+\S/) { $ci = $i; last } }
  if ($ci >= 0) {
    my ($a, $b) = ($ci, $ci);
    $a-- while $a > 0 && $r[$a - 1] =~ /^   \S/;
    $b++ while $b < $#r && $r[$b + 1] =~ /^   \S/;
    $kind = 'menu';
    for my $i ($a .. $b) {
      (my $t = $r[$i]) =~ s/^\s*(?:❯\s*)?//;
      push @opts, { n => $i - $a + 1, label => $t, detail => '', offered => JSON::PP::true, saves_rule => JSON::PP::false };
      $cursor = $i - $a + 1 if $i == $ci;
    }
  }
}
my $esc = ($l[$F] =~ /Esc to cancel/) ? JSON::PP::true : JSON::PP::false;
print JSON::PP->new->canonical->encode({ kind => $kind, text => join("\n", @r), options => \@opts,
  cursor => (defined $cursor ? $cursor + 0 : undef), esc => $esc });
PERL
hm_dialog_parse() {  # a pane captured with -e on stdin: JSON {kind, text, options, cursor, esc, fingerprint}; 3 when no dialog is up
  local text json fp
  text=$(perl -pe 's/\e\][^\a\e]*(?:\a|\e\\)//g' | hm_pane_clean)
  printf '%s\n' "$text" | hm_pane_idle_text; [ $? -eq 3 ] || return 3
  json=$(printf '%s\n' "$text" | perl -e "$HM_DIALOG_PERL" -- "$HM_DIALOG_FOOTER" "$HM_DIALOG_NOT_OFFERED") || return 3
  fp=$(printf '%s' "$json" | jq -r '.text' | shasum | cut -d' ' -f1)
  printf '%s' "$json" | jq -c --arg f "$fp" '. + {fingerprint:$f}'
}
hm_pane_dialog() {  # hm_pane_dialog <socket, or empty for hivemind's own server> <pane>: hm_dialog_parse of that pane; 1 when it cannot be read
  local t
  t=$(hm_tmux_on "$1" capture-pane -p -e -J -t "$2" 2>/dev/null) || return 1
  printf '%s\n' "$t" | hm_dialog_parse
}

# ---- the away switch: a file only root can have written ----------------------------------------------------------------
# Delegate mode (the hub decides for the owner while they are away) is on exactly while this file is valid. It sits where
# a session running as the owner's user cannot have written it, and the owner makes it with sudo from lines `hm-hub away`
# prints (hivemind never runs sudo). The predicate takes the path and the owner it requires; production passes only the
# fixed path and root (hm_delegate_now), and nothing in the environment or a setting changes the path, the owner or the
# content: a way to change them would be a way round the check. Valid means: the file, its folder and every folder above it
# are not links (lstat) and not writable by group or others; the file and its folder are owned by the required user, the
# folders above by the required user or root (with root required, root alone); the content is exactly
#   hivemind-delegate 1 / hub=<absolute path> / until=<epoch seconds>
# with `until` in the future and at most 7 days ahead (a CronCreate heartbeat does not outlive that). HM_DELEGATE_WHY is set
# to the first check that failed.
hm_delegate_path() {  # the fixed path: under /Library on macOS (/etc is a link there), /etc on Linux
  case "$(uname -s)" in Darwin) echo '/Library/Application Support/hivemind/delegate' ;; *) echo '/etc/hivemind/delegate' ;; esac
}
hm_stat3() {  # hm_stat3 <path>: "<uid> <octal mode> <type>" of the path itself (lstat, /usr/bin/stat in either form), or fails
  local out
  if /usr/bin/stat --version >/dev/null 2>&1; then out=$(/usr/bin/stat -c '%u %a %F' -- "$1" 2>/dev/null)
  else out=$(/usr/bin/stat -f '%u %Lp %HT' "$1" 2>/dev/null); fi
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}
hm_path_trusted() {  # hm_path_trusted <path> <file|dir> <uid> <strict|loose>: not a link, the right kind, owned (loose: or by root), not group- or world-writable
  local st u m t g o
  st=$(hm_stat3 "$1") || { HM_DELEGATE_WHY="$1 cannot be read"; return 1; }
  read -r u m t <<< "$st"
  case "$t" in *[Ss]ymbolic*) HM_DELEGATE_WHY="$1 is a link"; return 1 ;; esac
  case "$2:$t" in file:*[Rr]egular*|dir:*[Dd]irectory*) ;; *) HM_DELEGATE_WHY="$1 is not a $2"; return 1 ;; esac
  if [ "$u" != "$3" ] && { [ "$4" != loose ] || [ "$u" != 0 ]; }; then HM_DELEGATE_WHY="$1 is owned by uid $u"; return 1; fi
  m=${m: -3}; g=${m:1:1}; o=${m:2:1}
  if [ $((g & 2)) -ne 0 ] || [ $((o & 2)) -ne 0 ]; then HM_DELEGATE_WHY="$1 is writable by group or others (mode $m)"; return 1; fi
  return 0
}
hm_delegate_read() {  # hm_delegate_read <path> <uid> [<now>]: prints "<hub><TAB><until>" when the file is valid; 1 when it is not
  local f="$1" want="$2" now="${3:-$(date +%s)}" d p hub until i
  HM_DELEGATE_WHY=""
  case "$f" in /*) ;; *) HM_DELEGATE_WHY="the path is not absolute"; return 1 ;; esac
  hm_is_number "$want" && hm_is_number "$now" || { HM_DELEGATE_WHY="bad uid or time"; return 1; }
  hm_path_trusted "$f" file "$want" strict || return 1
  d=$(dirname "$f"); hm_path_trusted "$d" dir "$want" strict || return 1
  p=$(dirname "$d"); i=0
  while :; do
    hm_path_trusted "$p" dir "$want" loose || return 1
    [ "$p" = / ] && break
    p=$(dirname "$p"); i=$((i + 1)); [ "$i" -lt 64 ] || { HM_DELEGATE_WHY="the path is too deep"; return 1; }
  done
  if [ "$(grep -c '' "$f")" -ne 3 ] || grep -q $'\r' "$f"; then HM_DELEGATE_WHY="the content is not three lines"; return 1; fi
  [ "$(sed -n 1p "$f")" = 'hivemind-delegate 1' ] || { HM_DELEGATE_WHY="the first line is not 'hivemind-delegate 1'"; return 1; }
  hub=$(sed -n 2p "$f"); until=$(sed -n 3p "$f")
  case "$hub" in hub=/*) hub=${hub#hub=} ;; *) HM_DELEGATE_WHY="line 2 is not hub=<absolute path>"; return 1 ;; esac
  hm_is_typed_path "$hub" || { HM_DELEGATE_WHY="the hub path is not one hivemind will type"; return 1; }
  case "$until" in until=*) until=${until#until=} ;; *) HM_DELEGATE_WHY="line 3 is not until=<epoch>"; return 1 ;; esac
  hm_is_number "$until" || { HM_DELEGATE_WHY="until is not a number"; return 1; }
  [ "$until" -gt "$now" ] || { HM_DELEGATE_WHY="the file has expired"; return 1; }
  [ "$until" -le $((now + 604800)) ] || { HM_DELEGATE_WHY="until is more than 7 days ahead"; return 1; }
  printf '%s\t%s\n' "$hub" "$until"
}
hm_delegate_now() { hm_delegate_read "$(hm_delegate_path)" 0; }
# hm_env_has <pid> <NAME=value>: 0 the process was launched with it; 1 its environment is visible and lacks it; 2 no
# environment is visible at all (the caller says so and does not pretend to have checked). Linux reads /proc/<pid>/environ,
# which is exact. macOS `ps -E` prints the arguments and the environment on one line: an argument that spells the marker
# could fool it, so it is matched as a whole word, and only after the command's own words. macOS shows no environment for
# Apple platform binaries (bash, sleep), so a non-platform process is needed to read one: Claude Code is one.
hm_env_has() {
  local pid="$1" want="$2" env
  if [ -r "/proc/$pid/environ" ]; then
    tr '\0' '\n' < "/proc/$pid/environ" | grep -qxF -- "$want"; return $(( $? == 0 ? 0 : 1 ))
  fi
  env=$(ps -E -ww -p "$pid" -o command= 2>/dev/null | tr ' ' '\n')
  printf '%s\n' "$env" | grep -qE '^(PATH|HOME|USER|SHELL)=' || return 2
  printf '%s\n' "$env" | grep -qxF -- "$want"; return $(( $? == 0 ? 0 : 1 ))
}

# A permission mode hivemind starts a session in (hm-spawn's and hm-hub's --mode): never bypassPermissions.
HM_PERMISSION_MODES="plan dontAsk default acceptEdits auto"
hm_check_mode() {  # hm_check_mode <mode> <who>: exits 4 unless hivemind may start a session in that mode
  [ "$1" = bypassPermissions ] && hm_die 4 "bypassPermissions is never started by $2"
  case " $HM_PERMISSION_MODES " in *" $1 "*) return 0 ;; esac
  hm_die 4 "unknown permission mode: $1"
}
hm_is_number() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }   # hm_is_number <value>: digits only
# A model or an effort as hivemind passes one to claude: letters, digits, '.', '_', '[', ']' and '-', not starting with '-'.
hm_is_model_name() {  # hm_is_model_name <value>: 0 when it is one
  case "$1" in ''|-*|*[!${HM_LOWER}${HM_UPPER}${HM_DIGITS}._\[\]-]*) return 1 ;; esac
  return 0
}
# hm_open_window <tmux session> <window name> <cwd> <command> [-e VAR=value]...: a window in that session, which is made when
# it does not exist; prints the new pane. The one place hm-spawn and hm-hub open a pane.
hm_open_window() {
  local s="$1" n="$2" c="$3" cmd="$4"; shift 4
  if hm_tmux has-session -t "=$s" 2>/dev/null; then
    hm_tmux new-window -d -P -F '#{pane_id}' -t "=$s:" -n "$n" -c "$c" "$@" "$cmd"
  else
    hm_tmux new-session -d -P -F '#{pane_id}' -s "$s" -n "$n" -c "$c" "$@" "$cmd"
  fi
}
hm_pane_question() {  # hm_pane_question <socket, or empty for hivemind's own server> <pane>: 0 when a dialog waits on its screen
  local t
  [ -n "$2" ] || return 1
  t=$(hm_tmux_on "$1" capture-pane -p -e -J -t "$2" 2>/dev/null) || return 1
  printf '%s\n' "$t" | hm_pane_idle_text; [ $? -eq 3 ]
}
