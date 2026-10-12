#!/usr/bin/env bash
# Shared by every hh-* executable. bash 3.2 compatible. Never reads plugin variables: settings arrive as arguments
# or HH_* environment set by hh-spawn.
# A command substitution does not stop its caller: write x=$(hh_project_root) || exit $?, never a bare x=$(...).
# ---- the names: each is spelled here and nowhere else in bin/ (tests/test_names.sh holds it to that); hooks/names.ts is the
# twin for the hub screen ------------------------------------------------------------------------------------------------
HH_PREFIX='hivehouse'                     # what a message to the user begins with: "<prefix>: ..."
HH_STATE_DIR='.hivehouse'                 # a project's state folder, under its root
HH_HUB_DIR='.hivehouse-hub'               # the hub's folder, under its work folder
HH_HOME_DIR='.hivehouse'                  # the per-user home (slot, registry, queue), under $HOME
HH_MAC_BASE='/Library/Application Support/hivehouse'   # the delegate files' folder, and the machine slot's, on macOS
HH_LINUX_BASE='/etc/hivehouse'            # the delegate files' folder on Linux
HH_LINUX_SLOT='/var/lib/hivehouse/slot'   # the machine slot on Linux
HH_DELEGATE_TAG='hivehouse-delegate'  # the delegate file's first word; the first line is the tag, a space and a version
HH_DELEGATE_VERSIONS=' 1 2 3 4 '      # the versions hh_delegate_read accepts (1: hub, until, mcp; 2: adds hosts and allow; 3: adds tools; 4: adds peers)
HH_DELEGATE_TOOLS=' Workflow WebFetch DesignSync ArtifactCheck PushNotification '   # the only extra tools an away session may be given (tools=)
HH_DELEGATE_WRITE=4                   # the version hh-hub away writes
HH_PEER_LOG='peers.jsonl'             # the hub's audit log of messages sent to a listed peer, in its $HH_HUB_DIR
HH_CUSTOM_DIR='custom'                    # the user's overrides of the plugin's roles, rules and brief template: under a project's state folder and under the per-user home
HH_WINDOW_DEFAULT=1000000                      # the one context window assumed when none was measured or given: Claude Code's own default, and plugin.json's three window_* defaults
hh_plugin_name() {  # use as x=$(hh_plugin_name) || exit $?. The plugin's name, read with built-ins from .claude-plugin/plugin.json (its top-level "name" line)
  local f l n="" pre='  "name": "'; f="$(dirname "${BASH_SOURCE[0]}")/../.claude-plugin/plugin.json"
  while IFS= read -r l; do
    case "$l" in "$pre"*) n=${l#"$pre"}; n=${n%%\"*}; break ;; esac
  done 2>/dev/null < "$f"
  case "$n" in ''|*[!a-z0-9-]*) echo "$HH_PREFIX: cannot read the plugin's name from $f" >&2; return 2 ;; esac
  printf '%s\n' "$n"
}
# A skill's ${user_config.X} reaches the session as written when no value of X was ever saved (Claude Code fills a placeholder only from a
# saved value, never from the plugin's default). hh_option_default is plugin.json's default for an option; hh_option_value is the value a
# skill passed, or that default when the value is missing, empty or still the placeholder. The one place either is decided.
hh_option_default() {  # hh_option_default <key>: prints the default; 4 when plugin.json declares no such option
  local f; f="$(dirname "${BASH_SOURCE[0]}")/../.claude-plugin/plugin.json"
  jq -e --arg k "$1" '.userConfig | has($k)' "$f" >/dev/null 2>&1 || return 4
  jq -r --arg k "$1" '.userConfig[$k] | if has("default") then (.default | tostring) else "" end' "$f"
}
hh_option_value() {  # hh_option_value <key> [<value the skill passed>]
  local k="$1" v="${2:-}"
  case "$v" in '${user_config.'*'}') k=${v#'${user_config.'}; k=${k%'}'}; v="" ;; esac
  [ -z "$v" ] || { printf '%s\n' "$v"; return 0; }
  hh_option_default "$k"
}
hh_die()  { echo "$HH_PREFIX: $2" >&2; exit "$1"; }
# A session hivehouse launched in bypass while the owner is away carries HH_AWAY_BYPASS=1. Whatever leaves the machine or ends the
# run for good is refused to it. This is a second layer: a Bash command can unset the variable for itself, so hh-away-hook is the guard.
hh_refuse_away() {  # hh_refuse_away <what>: exit 4 when this process is in a marked session
  [ "${HH_AWAY_BYPASS:-}" != 1 ] || hh_die 4 "hivehouse's away mode refuses $1 while the owner is away (HH_AWAY_BYPASS is set); tell the owner what you needed"
}
hh_home() { printf '%s\n' "${HIVEHOUSE_HOME:-$HOME/$HH_HOME_DIR}"; }
hh_now()  { /bin/date -u +%Y-%m-%dT%H:%M:%SZ; }
hh_project_root() {
  if [ -n "${HH_PROJECT:-}" ]; then
    [ -d "$HH_PROJECT" ] || hh_die 2 "HH_PROJECT is not a directory: $HH_PROJECT"
    (cd "$HH_PROJECT" && pwd -P); return
  fi
  local common; common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || hh_die 2 "not inside a git repository and HH_PROJECT is not set"
  case "$common" in */.git) (cd "${common%/.git}" && pwd -P) ;; *) hh_die 2 "unsupported repository layout: $common" ;; esac
}
# ---- where a project's team is: the home, then each worktree of its repository that has a team ------------------------------------------
# Read with built-ins only, from the two pointers git keeps: <home>/.git/worktrees/<name>/gitdir (one line, <worktree>/.git) and the worktree's
# own .git file (gitdir: <home>/.git/worktrees/<name>). A worktree counts only when both agree, each side compared after cd -P (git records a
# path as it was typed). git 2.48+ can write relative paths (worktree.useRelativePaths): a relative line is resolved against the folder of the
# file it is in, and one that cannot be resolved means that worktree is no root. These run on the grant path, so none runs the program named
# by the first word git on PATH, which an away session's own Bash command sets.
hh_repo_home() {  # hh_repo_home <dir>: the home of the repository <dir> is the top of: a .git folder is itself, a .git file the home it points to. Never walks up.
  local d line g gd home rest back b
  d=$(cd -P "$1" 2>/dev/null && pwd -P) || return 1
  if [ -d "$d/.git" ] && [ ! -L "$d/.git" ]; then printf '%s\n' "$d"; return 0; fi
  [ -f "$d/.git" ] && [ ! -L "$d/.git" ] || return 1
  IFS= read -r line < "$d/.git" || [ -n "$line" ] || return 1
  case "$line" in "gitdir: "*) g=${line#gitdir: } ;; *) return 1 ;; esac
  case "$g" in /*) ;; *) g="$d/$g" ;; esac
  gd=$(cd -P "$g" 2>/dev/null && pwd -P) || return 1
  home=${gd%/.git/worktrees/*}; rest=${gd#"$home/.git/worktrees/"}   # no match leaves $rest the whole path, which has a slash: a submodule's git folder is refused here too
  case "$rest" in ''|*/*) return 1 ;; esac
  IFS= read -r back < "$gd/gitdir" || [ -n "$back" ] || return 1
  case "$back" in */.git) ;; *) return 1 ;; esac
  case "$back" in /*) ;; *) back="$gd/$back" ;; esac
  b=$(cd -P "${back%/.git}" 2>/dev/null && pwd -P) || return 1
  [ "$b" = "$d" ] || return 1
  printf '%s\n' "$home"
}
hh_team_roots() {  # hh_team_roots <home>: the home, then each worktree of its repository with $HH_STATE_DIR/team.json, one per line
  local h d line wt r seen=""
  h=$(cd -P "$1" 2>/dev/null && pwd -P) || return 1
  printf '%s\n' "$h"
  [ -d "$h/.git/worktrees" ] && [ -d "$h/.git" ] && [ ! -L "$h/.git" ] || return 0
  for d in "$h"/.git/worktrees/*/; do
    d=${d%/}; [ -f "$d/gitdir" ] || continue
    IFS= read -r line < "$d/gitdir" || [ -n "$line" ] || continue
    case "$line" in */.git) ;; *) continue ;; esac
    case "$line" in /*) ;; *) line="$d/$line" ;; esac
    wt=$(cd -P "${line%/.git}" 2>/dev/null && pwd -P) || continue
    [ "$wt" != "$h" ] || continue
    r=$(hh_repo_home "$wt") || continue
    [ "$r" = "$h" ] || continue
    [ -f "$wt/$HH_STATE_DIR/team.json" ] || continue
    case "$seen" in *"|$wt|"*) continue ;; esac
    seen="$seen|$wt|"; printf '%s\n' "$wt"
  done
}
hh_project_home() {  # hh_project_home <root>: the home a team root takes its settings from; a folder that is no repository is its own
  hh_repo_home "$1" || (cd -P "$1" 2>/dev/null && pwd -P)
}
hh_project_key() {  # basename plus a short hash of the full path: app and app-impl never clash
  local p="$1"; printf '%s-%s\n' "$(basename "$p")" "$(printf '%s' "$p" | shasum | cut -c1-6)"
}
hh_state() { local root; root=$(hh_project_root) || exit $?; printf '%s/%s\n' "$root" "$HH_STATE_DIR"; }
# ---- custom/: the user's own roles, rules and brief template, which an update of the plugin never replaces ---------------------------
# hh_custom_file <rel>: prints the file to read for the plugin's <rel> (roles/<name>.md, rules/RULES.md, rules/brief-template.md, and the hub's rules/hub-pickup.md and rules/hub-handoff.md):
# the project's <state dir>/custom/<rel>, else the user's <home>/custom/<rel>, else the plugin's own. THE one place this is decided; every
# skill asks it through hh-resolve. A custom file is used only when it, its folder and custom/ are the user's own, not links and not
# writable by group or others (hh_path_trusted, as the delegate file's); otherwise a note names the file and why, and the next level
# answers. A note also says which level a used file came from. Exit 2 when no level has the file.
hh_custom_safe() {  # hh_custom_safe <custom dir> <rel> <uid>: 0 when every part of the path below the state folder is safe; HH_DELEGATE_WHY says what is not
  local base="$1" rel="$2" uid="$3"
  hh_path_trusted "$base" dir "$uid" strict || return 1
  hh_path_trusted "$base/${rel%/*}" dir "$uid" strict || return 1
  hh_path_trusted "$base/$rel" file "$uid" strict
}
hh_custom_file() {
  local rel="$1" plugin level base f root uid levels="project user"
  case "$rel" in roles/[${HH_LOWER}]*.md|rules/RULES.md|rules/brief-template.md|rules/hub-pickup.md|rules/hub-handoff.md) ;; *) return 4 ;; esac
  case "$rel" in *[!${HH_LOWER}${HH_UPPER}${HH_DIGITS}._/-]*|*..*) return 4 ;; esac
  plugin=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P) || return 2
  uid=$(hh_real_uid) || return 2
  # the hub reads no custom/ file while the owner is away: an away agent can write one, and the hub would follow it (rules, pickup line, handoff template)
  if hh_hub_root_here && hh_away_for_hub "$HH_HUB_ROOT_HERE"; then
    levels=""; echo "$HH_PREFIX: the owner is away, so the hub reads the plugin's own $rel and no custom file" >&2
  fi
  for level in $levels; do
    if [ "$level" = project ]; then root=$(hh_project_root 2>/dev/null) || continue; base="$root/$HH_STATE_DIR/$HH_CUSTOM_DIR"
    else base="$(hh_home)/$HH_CUSTOM_DIR"; fi
    f="$base/$rel"
    { [ -e "$f" ] || [ -L "$f" ]; } || continue
    if hh_custom_safe "$base" "$rel" "$uid"; then
      echo "$HH_PREFIX: using the $level's custom file $f" >&2
      printf '%s\n' "$f"; return 0
    fi
    echo "$HH_PREFIX: ignoring the $level's custom file $f: $HH_DELEGATE_WHY" >&2
  done
  f="$plugin/$rel"
  [ -f "$f" ] || return 2
  printf '%s\n' "$f"
}
hh_ensure_state() {  # creates $HH_STATE_DIR/, excludes it through info/exclude, refuses if any of it is tracked
  local root common excl
  root=$(hh_project_root) || exit $?
  common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir) || exit $?
  if [ -n "$(git -C "$root" ls-files -- "$HH_STATE_DIR")" ]; then
    hh_die 3 "files under $HH_STATE_DIR/ are tracked by git; untrack them before using hivehouse here"
  fi
  mkdir -p "$root/$HH_STATE_DIR" "$common/info"
  excl="$common/info/exclude"; touch "$excl"
  grep -qx "/$HH_STATE_DIR/" "$excl" || echo "/$HH_STATE_DIR/" >> "$excl"
}
hh_json_get() {  # hh_json_get <file> <jq path>: the root-owned jq (HH_JQ, set below) when there is one, else jq from PATH for scripts that decide nothing
  if [ -n "${HH_JQ:-}" ]; then "$HH_JQ" -r "$2 // empty" "$1" 2>/dev/null; else jq -r "$2 // empty" "$1" 2>/dev/null; fi
}
hh_registry_dir() { printf '%s/registry/panes\n' "$(hh_home)"; }
hh_pane_key() {  # hh_pane_key <socket> <pane id> -> filename-safe key
  printf '%s' "$1|$2" | shasum | cut -c1-16
}
hh_tmux() { if [ -n "${HH_TMUX_SOCKET:-}" ]; then tmux -S "$HH_TMUX_SOCKET" "$@"; else tmux "$@"; fi; }
HH_AWAY_VARS="HH_AWAY_BYPASS HH_AWAY_HUB HH_AWAY_MCP_ALLOW"
hh_tmux_unmarked() { if [ -n "${HH_TMUX_SOCKET:-}" ]; then /usr/bin/env -u HH_AWAY_BYPASS -u HH_AWAY_HUB -u HH_AWAY_MCP_ALLOW tmux -S "$HH_TMUX_SOCKET" "$@"; else /usr/bin/env -u HH_AWAY_BYPASS -u HH_AWAY_HUB -u HH_AWAY_MCP_ALLOW tmux "$@"; fi; }   # a tmux call whose client environment (copied into a new server) lacks the away variables
# hh_tmux_on <socket, or empty for hivehouse's own server> <tmux args>...: the one way to reach a session's pane on the server
# it was recorded on (team.json .socket), which is not always hivehouse's own
hh_tmux_on() { local s="$1"; shift; if [ -n "$s" ]; then tmux -S "$s" "$@"; else hh_tmux "$@"; fi; }
# A pane is identified by its process and that process's start time: a pane id alone is handed out again by a restarted
# tmux server. These three are the only place that is read and compared (the registry's writer and hook, the manifest
# and cleanup use them).
hh_pane_pid() { tmux -S "$1" display-message -p -t "$2" '#{pane_pid}' 2>/dev/null | grep -E '^[0-9]+$'; }   # hh_pane_pid <socket> <pane>: empty when the server has no such pane
hh_pane_identity() {  # hh_pane_identity <socket> <pane>: "<pid><TAB><start time>", or fails when the pane cannot be read
  local pid; pid=$(hh_pane_pid "$1" "$2") || return 1
  printf '%s\t%s\n' "$pid" "$(hh_lstart "$pid")"
}
hh_pane_is() {  # hh_pane_is <socket> <pane> <pid> <started>: 0 it is that pane, 1 the pane is another (or the record is empty), 2 the pane cannot be read
  local cur; cur=$(hh_pane_pid "$1" "$2") || return 2
  [ -n "$3" ] && [ -n "$4" ] && [ "$cur" = "$3" ] && hh_lstart_is "$cur" "$4"
}
hh_claude_ancestor() {  # hh_claude_ancestor [pid]: the nearest Claude process at or above pid (default: this process), or fails
  local p="${1:-$$}" i=0
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ "$i" -lt 64 ]; do
    hh_is_claude "$p" && { echo "$p"; return 0; }
    p=$(/bin/ps -o ppid= -p "$p" 2>/dev/null); p=${p//[[:space:]]/}; i=$((i + 1))
  done
  return 1
}
hh_claude_is() {  # hh_claude_is <pid> <started>: that very process (not a reused pid), still Claude
  [ -n "$1" ] && [ -n "$2" ] && hh_alive "$1" && hh_lstart_is "$1" "$2" && hh_is_claude "$1"
}
# The one place hivehouse stops a process it did not just start: a Claude whose working line has not moved for 15 minutes, by
# `hh-hub recover`, while the owner's delegate file is valid and the hub carries the away marker. It is never a pattern or a name:
# only the recorded pid, while that pid still has its recorded start time and is still Claude, and never a Claude above the caller
# (the hub's own), and only a Claude that has the pane's own process at or above it: the screen read is the pane's, so a record that ties
# one pane's frozen screen to another live Claude stops nothing. hh_stop_hung <pid> <started> <socket> <pane> <secs>: 0 stopped (or no
# longer that process); 1 not that process, or not under that pane, nothing sent; 2 the pane no longer shows a working line of <secs>,
# nothing sent; 3 still running after KILL. Before TERM the pid, the start time, the pane and the screen are read again; TERM, up to
# 10 s for it to end, then KILL only if the pid is still that process.
hh_under() {  # hh_under <pid> <ancestor pid>: 0 when the process is that one or has it above it
  local p="$1" i=0
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ "$i" -lt 64 ]; do
    [ "$p" = "$2" ] && return 0
    p=$(/bin/ps -o ppid= -p "$p" 2>/dev/null); p=${p//[[:space:]]/}; i=$((i + 1))
  done
  return 1
}
hh_stop_hung() {
  local pid="${1:-}" started="${2:-}" i pp
  hh_is_number "$pid" && [ "$pid" -gt 1 ] && hh_is_number "${5:-}" || return 1
  hh_claude_is "$pid" "$started" || return 1
  [ "$(hh_claude_ancestor "$$")" != "$pid" ] || return 1
  pp=$(hh_pane_pid "$3" "$4") && hh_under "$pid" "$pp" || return 1
  [ "$(hh_pane_text "$4" "$3" | hh_pane_working_seconds)" = "$5" ] || return 2
  kill -TERM "$pid" 2>/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do hh_alive "$pid" || return 0; /bin/sleep 0.5; done
  hh_claude_is "$pid" "$started" || return 0
  kill -KILL "$pid" 2>/dev/null; /bin/sleep 0.5
  hh_alive "$pid" && hh_lstart_is "$pid" "$started" && return 3
  return 0
}
hh_agent_is() {  # hh_agent_is <socket> <pane> <pane pid> <pane started> [<claude pid> <claude started>]: 0 the agent is still there, as recorded; 1 it is not; 2 the pane cannot be read
  hh_pane_is "$1" "$2" "$3" "$4"; local rc=$?; [ "$rc" -eq 0 ] || return "$rc"
  [ -z "${5:-}" ] || hh_claude_is "$5" "${6:-}"
}
# Is a team member still running as team.json recorded it? 0 yes; 1 no; 2 cannot tell (its process is alive but no tmux
# answers for its pane); 3 not on the team, or recorded with no identity. The one check hh-rotate, hh-context and
# hh-spawn --respawn make. The recorded process is read first: a missing pane reads to tmux as "cannot be read", the same
# as a server that does not answer, yet after a restart it is simply gone. A spawned agent's pane process is its Claude;
# the --self orchestrator's pane is the owner's shell, so its own Claude is what is checked.
hh_team_agent_is() {  # hh_team_agent_is <project root> <agent>
  local e socket pane ppid pstarted cpid cstarted
  # one read, fields joined by the unit separator: a whitespace separator would fold an empty field into its neighbour
  e=$(jq -r --arg a "$2" '[.agents[]? | select(.name == $a)][0] // empty
      | [.socket, .pane, .pane_pid, .pane_started, .claude_pid, .claude_started] | map(. // "" | tostring) | join("\u001f")' \
      "$1/$HH_STATE_DIR/team.json" 2>/dev/null)
  [ -n "$e" ] || return 3
  IFS=$'\x1f' read -r socket pane ppid pstarted cpid cstarted <<< "$e"
  [ -n "$pane" ] && [ -n "$ppid" ] && [ -n "$pstarted" ] || return 3
  [ -n "$cpid" ] || { hh_recorded_pane_is "$socket" "$pane" "$ppid" "$pstarted"; return; }
  hh_claude_is "$cpid" "$cstarted" || return 1
  hh_agent_is "$socket" "$pane" "$ppid" "$pstarted" "$cpid" "$cstarted"
}
# hh_recorded_pane_is <socket> <pane> <pid> <started>: is a recorded pane still that pane? 0 yes; 1 no; 2 cannot tell. Its
# process first: a missing pane reads to tmux as "cannot be read", the same as a server that does not answer, yet after a
# restart it is simply gone. hh_team_agent_is (a spawned agent) and hh-hub (a pane the hub started) both read it here.
hh_recorded_pane_is() {
  [ -n "$3" ] && hh_alive "$3" && hh_lstart_is "$3" "$4" || return 1
  hh_pane_is "$1" "$2" "$3" "$4"
}
hh_socket() { if [ -n "${HH_TMUX_SOCKET:-}" ]; then echo "$HH_TMUX_SOCKET"; else tmux display -p '#{socket_path}'; fi; }

# ---- mkdir locks (macOS has no flock). Used by hh-slot and hh-manifest. -------------------------------------------
# A lock is a directory holding holder.json {pid, lstart, created, ...}. A holder is stale when its pid is dead, when
# the pid is alive with another start time (pid reuse), or when holder.json is missing or empty and the directory is
# older than 10 s. A stale lock is taken over inside a guard directory "<lock>.takeover" (itself stale after 30 s),
# after re-reading the holder, so exactly one contender removes it. `kill -9` of a holder frees its lock.
hh_alive()  { /bin/ps -p "$1" >/dev/null 2>&1; }
# ps prints a start time in the caller's locale (mar.  6 oct. in fr_FR, Tue Oct  6 in C): one fixed format, or a time recorded under
# one locale never matches under another and a live session reads as gone
hh_lstart() { local s; s=$(LC_ALL=C /bin/ps -o lstart= -p "$1" 2>/dev/null); s=${s#"${s%%[![:space:]]*}"}; printf '%s\n' "${s%"${s##*[![:space:]]}"}"; }   # built-ins only: the away checks read it
# A start time recorded by 0.2.0 is in the caller's locale, one recorded now is C. hh_lstart_local reads the caller's form;
# hh_lstart_is <pid> <recorded>: 0 when the recorded time is that process's in the C form, else (one more ps, only then) in the
# caller's form. Pid reuse still needs the same second, so this is no looser than one fixed form. Every comparison uses it.
hh_lstart_local() { local s; s=$(/bin/ps -o lstart= -p "$1" 2>/dev/null); s=${s#"${s%%[![:space:]]*}"}; printf '%s\n' "${s%"${s##*[![:space:]]}"}"; }
hh_lstart_is() {
  local s
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  [ "$(hh_lstart "$1")" = "$2" ] && return 0
  s=$(hh_lstart_local "$1"); [ "$s" = "$2" ]
}
# hh_lstart_fp <time>: a recorded start time's language-free numbers, "HH:MM:SS YYYY D" (day without a leading zero), or nothing. Its
# one HH:MM:SS token, its one 4-digit year and its one standalone 1-2 digit day; exactly one of each, or there is no fingerprint (a
# day written "6." has none). Languages differ in the words and their order ("Tue  6 Oct", "mar  6 ott", "Tue Oct  6") but not in these.
hh_lstart_fp() {
  local w t="" y="" d="" nt=0 ny=0 nd=0 ws
  IFS=' ' read -r -a ws <<< "$1"
  for w in ${ws[@]+"${ws[@]}"}; do
    case "$w" in
      [0-9][0-9]:[0-9][0-9]:[0-9][0-9]) t=$w; nt=$((nt + 1)) ;;
      [0-9][0-9][0-9][0-9]) y=$w; ny=$((ny + 1)) ;;
      [0-9]|[0-9][0-9]) d=$((10#$w)); nd=$((nd + 1)) ;;
    esac
  done
  [ "$nt" = 1 ] && [ "$ny" = 1 ] && [ "$nd" = 1 ] && printf '%s %s %s\n' "$t" "$y" "$d"
}
hh_is_claude() {  # hh_is_claude <pid>: 0 when the process is Claude Code's, which hivehouse stops only in hh_stop_hung (below)
  local args first second   # by argv: macOS ps reports comm from argv0 as well, so it would be the same reading
  args=$(/bin/ps -o args= -p "$1" 2>/dev/null) || return 1
  first=${args%% *}; second=${args#* }; second=${second%% *}
  [ "${first##*/}" = claude ] && return 0
  case "${first##*/}" in node|bash|sh|zsh) [ "${second##*/}" = claude ] && return 0 ;; esac   # run by an interpreter
  case "$args" in *@anthropic-ai/claude-code/*) return 0 ;; esac
  return 1
}
hh_dir_age() {  # seconds since the directory was last modified
  local m; m=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || return 1
  echo $(( $(date +%s) - m ))
}
# A holder record names its process's start time twice: `lstart` in the caller's locale, as 0.2.0 reads it, and `lstart_c` in C. The
# slot is shared by every project on the machine, and a session keeps running the plugin version it was started with until it is
# restarted, so after any upgrade 0.2.0 and 0.3.0 meet in one lock: a 0.2.0 reader that finds a C-form lstart reads a live holder as
# gone and takes its lock. A 0.3.0 reader accepts either field.
hh_holder_json() {  # hh_holder_json <pid> [extra json object] -> the holder record
  local x="${2:-}"; [ -n "$x" ] || x='{}'
  jq -nc --argjson pid "$1" --arg l "$(hh_lstart_local "$1")" --arg lc "$(hh_lstart "$1")" --argjson c "$(date +%s)" --argjson x "$x" \
    '{pid:$pid,lstart:$l,lstart_c:$lc,created:$c} + $x'
}
# hh_lock_stale <lock>: 0 when the holder is gone. A dead pid is stale whatever the record says. A live pid is the holder when either
# record matches it exactly. Otherwise the record is judged by its language-free numbers (hh_lstart_fp): the holder when they equal
# the pid's own, stale (pid reuse) when they differ. A record with no fingerprint (junk, empty) is busy: not knowing is never a reason
# to take a live holder's lock. Words are not compared: en_GB, it_IT and pt_PT print the same shape in different languages.
hh_lock_stale() { hh_record_gone "$1/holder.json" "$1"; }
# hh_record_gone <record file> <path whose age judges a record with no pid>: 0 when the process the record names is gone (the
# rules above), 1 when it is there or cannot be told; a record with no pid is gone once the path is older than 10 s.
hh_record_gone() {
  local h="$1" pid ls lc age r fp cfp any=0
  pid=$(hh_json_get "$h" .pid); ls=$(hh_json_get "$h" .lstart); lc=$(hh_json_get "$h" .lstart_c)
  if [ -z "$pid" ]; then age=$(hh_dir_age "$2") || return 1; [ "$age" -gt 10 ]; return; fi
  hh_alive "$pid" || return 0
  hh_lstart_is "$pid" "$lc" && return 1
  hh_lstart_is "$pid" "$ls" && return 1
  cfp=$(hh_lstart_fp "$(hh_lstart "$pid")")
  for r in "$lc" "$ls"; do
    fp=$(hh_lstart_fp "$r"); [ -n "$fp" ] || continue
    [ "$fp" = "$cfp" ] && return 1
    any=1
  done
  [ "$any" = 1 ]
}
hh_lock_try() {  # hh_lock_try <lock> <holder json>: 0 taken, 1 busy
  local lock="$1" json="$2" guard age snap
  mkdir -p "$(dirname "$lock")"
  if mkdir "$lock" 2>/dev/null; then printf '%s\n' "$json" > "$lock/holder.json"; return 0; fi
  snap=$(cat "$lock/holder.json" 2>/dev/null)
  hh_lock_stale "$lock" || return 1
  guard="$lock.takeover"
  if ! mkdir "$guard" 2>/dev/null; then
    age=$(hh_dir_age "$guard") || return 1
    [ "$age" -gt 30 ] || return 1
    rmdir "$guard" 2>/dev/null; mkdir "$guard" 2>/dev/null || return 1
  fi
  if [ "$(cat "$lock/holder.json" 2>/dev/null)" != "$snap" ] || ! hh_lock_stale "$lock"; then
    rmdir "$guard" 2>/dev/null; return 1   # somebody else took it over first
  fi
  mv "$lock" "$lock.stale.$$" 2>/dev/null && rm -rf "$lock.stale.$$"
  if mkdir "$lock" 2>/dev/null; then
    printf '%s\n' "$json" > "$lock/holder.json"; rmdir "$guard" 2>/dev/null; return 0
  fi
  rmdir "$guard" 2>/dev/null; return 1
}
hh_lock_release() {  # hh_lock_release <lock> <pid>: removes the lock only when the record is that process's own
  local hp hl hc
  hp=$(hh_json_get "$1/holder.json" .pid); hl=$(hh_json_get "$1/holder.json" .lstart); hc=$(hh_json_get "$1/holder.json" .lstart_c)
  [ -n "$hp" ] && [ "$hp" = "$2" ] && { hh_lstart_is "$2" "$hc" || hh_lstart_is "$2" "$hl"; } || return 1
  rm -rf "$1"
}
# The one writer of a project's team.json (hh-spawn registers and closes agents, hh-hub window sets a window): under the file's own lock,
# read it (an empty team when there is none), run the jq filter over it with the given jq arguments, write a temporary file, mv it in.
# Returns jq's status, or 4 when the lock stays held by a live process (said on stderr).
hh_team_edit() {  # hh_team_edit <project root> <jq filter> [jq arguments]...
  local root="$1" filt="$2" f lock i=0 cur rc tmp
  shift 2
  f="$root/$HH_STATE_DIR/team.json"; lock="$f.lock"; tmp="$f.tmp$$"
  until hh_lock_try "$lock" "$(hh_holder_json $$)"; do
    i=$((i + 1)); [ "$i" -lt 50 ] || { echo "$HH_PREFIX: team.json is locked by another hivehouse command; nothing was written" >&2; return 4; }
    sleep 0.1
  done
  cur='{"agents":[]}'; [ ! -f "$f" ] || cur=$(cat "$f")
  printf '%s' "$cur" | jq "$@" "$filt" > "$tmp" && mv "$tmp" "$f"; rc=$?
  rm -f "$tmp"; hh_lock_release "$lock" $$
  return $rc
}

# ---- the slot's queue. A caller that waits files queue/<epoch seconds, 10 digits>-<pid>.json (a holder record) and takes the slot
# only as the oldest live ticket; tickets of one second are served by pid, as a number.
hh_queue_order() {  # hh_queue_order <queue dir>: the ticket names, oldest first
  local n
  for n in $(/bin/ls -1 "$1" 2>/dev/null); do
    case "$n" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*.json) ;; *) continue ;; esac
    case "${n%.json}" in *[!0-9-]*) continue ;; esac
    printf '%s\n' "$n"
  done | /usr/bin/sort -t- -k1,1 -k2,2n
}
hh_queue_live() {  # hh_queue_live <queue dir>: the live tickets, oldest first; a ticket whose process is gone is removed here
  local n
  for n in $(hh_queue_order "$1"); do
    if hh_record_gone "$1/$n" "$1/$n"; then rm -f "$1/$n"; else printf '%s\n' "$n"; fi
  done
}

# ---- idle detection ------------------------------------------------------------------------------------------------
# TIED TO THE CLAUDE CODE TERMINAL UI (checked against 2.1.x). When a release changes how the prompt box is drawn or how a
# dialog is worded, update HH_DIALOG_TEXT and hh_pane_idle_text. The prompt box is a rule, "❯", a no-break space and a dim
# placeholder (the placeholder comes back after C-u and /clear), a rule, and a footer. A pane is idle when it is still, its
# last lines show an empty prompt, and no dialog is up. Dialog wording is looked for from the box's top rule down only,
# so a dialog quoted in the conversation above is not mistaken for a live one; with fewer than two rules it is looked for
# everywhere (a refusal to type is the safe error).
HH_DIALOG_TEXT=("Do you trust" "Yes, proceed" "Esc to cancel" "Do you want to" "Allow this" "Press Enter to continue" "Enter to confirm" "I trust this folder")
# Claude Code's working line, above the prompt box while it works: a spinner glyph, a verb and an ellipsis, then the elapsed time
# and a detail in parentheses: "✳ Effecting… (3s · thinking)", "✽ Processing… (5m 29s · ↓ 7.2k tokens)" (hours as "1h 2m 3s",
# which no capture has shown yet). It starts at column 0: an indented line is reply text quoting one. Anything else is not a working
# line. What Claude Code may draw between the spinner and the prompt box is HH_WORKING_TRAILER_RE (a tip under the spinner, and the
# right-aligned notices seen in real captures); any other line there makes the screen unknown. Read by hh_pane_working_seconds.
HH_WORKING_RE='^(✳|✶|✻|✽|✢|·|\*) [A-Za-z-]+(…|\.\.\.) \(([0-9]+h )?([0-9]+m )?[0-9]+s( ·[^)]*)?\)[[:space:]]*$'
HH_WORKING_TRAILER_RE='^[[:space:]]*(⎿[[:space:]]+Tip: .*|Cursor disconnected|tmux focus-events off .*)$'
hh_pane_clean() {  # a pane captured with -e on stdin: drop dim runs (the placeholder), other escapes, and no-break spaces
  perl -pe 's/\e\[(?:[01];)?2m.*?(?:\e\[(?:0|22)?m|$)//g; s/\e\[[0-9;?]*[A-Za-z]//g; s/\xc2\xa0/ /g'
}
hh_pane_text() { hh_tmux_on "${2:-}" capture-pane -p -e -J -t "$1" 2>/dev/null | hh_pane_clean; }   # hh_pane_text <pane> [socket]
hh_pane_box() {  # a cleaned pane on stdin: the prompt box and what is below it (from the second-to-last rule), else all of it
  local text top
  text=$(cat)
  top=$(printf '%s\n' "$text" | grep -nE '^[[:space:]]*(─){4,}' | tail -2 | head -1 | cut -d: -f1)
  if [ "$(printf '%s\n' "$text" | grep -cE '^[[:space:]]*(─){4,}')" -ge 2 ] && [ -n "$top" ]; then
    printf '%s\n' "$text" | tail -n +"$top"
  else printf '%s\n' "$text"; fi
}
hh_pane_prompt_line() {  # a pane on stdin: the input line in its prompt box (the last line that starts with the prompt mark)
  hh_pane_clean | hh_pane_box | grep -E '^(│| )*(>|❯)' | tail -1
}
hh_pane_idle_text() {  # a cleaned pane on stdin: 0 an empty prompt and no dialog, 1 no empty prompt, 3 a dialog is up
  local text region p
  text=$(hh_pane_clean)   # idempotent: callers may hand it a cleaned pane or a raw one
  region=$(printf '%s\n' "$text" | hh_pane_box)
  for p in "${HH_DIALOG_TEXT[@]}"; do case "$region" in *"$p"*) return 3 ;; esac; done
  printf '%s\n' "$text" | grep -v '^[[:space:]]*$' | tail -6 | grep -Eq '^(│| )*(>|❯)( |│)*$'
}
hh_pane_working_seconds() {  # a pane on stdin: the elapsed seconds on Claude Code's working line, or fails ("unknown": no such line)
  # The working line must be the last non-blank line above the prompt box, apart from HH_WORKING_TRAILER_RE lines under it: a line
  # quoted in the conversation, one in the footer, or one with other text after it is not the session's own. Not seeing the box is
  # unknown too. An unknown screen is never working and never hung.
  local text top lines line ts t secs=0
  text=$(hh_pane_clean)
  [ "$(printf '%s\n' "$text" | grep -cE '^[[:space:]]*(─){4,}')" -ge 2 ] || return 1
  top=$(printf '%s\n' "$text" | grep -nE '^[[:space:]]*(─){4,}' | tail -2 | head -1 | cut -d: -f1)
  lines=$(printf '%s\n' "$text" | head -n "$((top - 1))" | grep -v '^[[:space:]]*$')
  while printf '%s\n' "$lines" | tail -1 | grep -qE "$HH_WORKING_TRAILER_RE"; do lines=$(printf '%s\n' "$lines" | sed '$d'); done
  line=$(printf '%s\n' "$lines" | tail -1 | grep -E "$HH_WORKING_RE")
  [ -n "$line" ] || return 1
  ts=$(printf '%s' "$line" | sed -E 's/^[^(]*\(([0-9hms ]*s)( ·[^)]*)?\)[[:space:]]*$/\1/')
  for t in $ts; do
    case "$t" in
      *h) secs=$((secs + ${t%h} * 3600)) ;;
      *m) secs=$((secs + ${t%m} * 60)) ;;
      *s) secs=$((secs + ${t%s})) ;;
    esac
  done
  printf '%s\n' "$secs"
}
# wait_idle <pane> <seconds still> <max seconds> [socket]: 0 idle, 1 timed out, 3 a dialog on screen (the caller tells the
# orchestrator; nothing here ever types into a pane). A dialog that has been still as long as idle must be is told then,
# not waited out: it does not go away by itself.
wait_idle() {
  local prev="" cur text still=0 waited=0 rc=1
  while [ "$waited" -lt "$3" ]; do
    hh_tmux_on "${4:-}" display-message -p -t "$1" '#{pane_id}' >/dev/null 2>&1 || return 1   # the pane is gone
    text=$(hh_pane_text "$1" "${4:-}")
    cur=$(printf '%s' "$text" | shasum)
    if [ "$cur" = "$prev" ]; then still=$((still + 1)); else still=0; fi
    prev="$cur"
    printf '%s\n' "$text" | hh_pane_idle_text; rc=$?
    [ "$still" -ge "$2" ] && [ "$rc" -eq 0 ] && return 0
    [ "$still" -ge "$2" ] && [ "$rc" -eq 3 ] && return 3
    sleep 1; waited=$((waited + 1))
  done
  [ "$rc" -eq 3 ] && return 3
  return 1
}

# THE one rotation of a pane, for hh-rotate (an agent) and hh-hub rotate (the hub): wait until the pane is idle, check it is still the
# one that was recorded, type /clear, wait, then the pickup line. Nothing is typed into a pane that is busy, shows a dialog, or is
# no longer the recorded one (a pane id is handed out again by a restarted tmux server, and an owner's shell outlives its Claude);
# the identity is checked again before every send, since the wait for an idle pane can last minutes.
#   hh_rotate_pane <pane> <socket, or empty> <still s> <max s> <settle s> <verify cmd> <pickup cmd>
# <verify cmd> returns 0 while the pane is still the recorded one (it says so itself when not); <pickup cmd> prints the line to send,
# asked after the clear. Returns 0 rotated; 1 never idle (nothing sent); 5 a dialog (nothing sent); 6 not the recorded pane (nothing
# sent); 7 cleared but never idle again (pickup line not sent).
hh_rotate_pane() {
  local pane="$1" sock="$2" still="$3" max="$4" settle="$5" verify="$6" pickup="$7" rc
  wait_idle "$pane" "$still" "$max" "$sock"; rc=$?
  case "$rc" in 0) ;; 3) return 5 ;; *) return 1 ;; esac
  "$verify" || return 6
  hh_tmux_on "$sock" send-keys -t "$pane" -l '/clear'; hh_tmux_on "$sock" send-keys -t "$pane" Enter
  sleep "$settle"
  # the UI left /clear on the input line (the last non-blank line of the pane is the footer): clear it and type it again, once
  if hh_pane_text "$pane" "$sock" | hh_pane_prompt_line | grep -Eq '^(│| )*(>|❯) */clear[[:space:]]*$'; then
    "$verify" || return 6
    hh_tmux_on "$sock" send-keys -t "$pane" C-u
    hh_tmux_on "$sock" send-keys -t "$pane" -l '/clear'; hh_tmux_on "$sock" send-keys -t "$pane" Enter
    sleep "$settle"
  fi
  wait_idle "$pane" 2 "$max" "$sock" || return 7
  "$verify" || return 6
  hh_tmux_on "$sock" send-keys -t "$pane" -l "$("$pickup")"
  hh_tmux_on "$sock" send-keys -t "$pane" Enter
}

# The owner's statusLine as Claude Code picks it for a session started in <dir>: managed settings, then the project's
# local file, then the project's own, then the user's (checked against Claude Code 2.1.286). Prints the statusLine object,
# or nothing when none is set. HH_MANAGED_SETTINGS names the managed file (tests point it elsewhere).
hh_managed_settings() {
  if [ -n "${HH_MANAGED_SETTINGS:-}" ]; then echo "$HH_MANAGED_SETTINGS"
  elif [ "$(uname)" = Darwin ]; then echo "/Library/Application Support/ClaudeCode/managed-settings.json"
  else echo "/etc/claude-code/managed-settings.json"; fi
}
hh_owner_statusline() {  # hh_owner_statusline <session cwd>
  local f
  for f in "$(hh_managed_settings)" "$1/.claude/settings.local.json" "$1/.claude/settings.json" "$(hh_claude_dir)/settings.json"; do
    [ -f "$f" ] && jq -ce '.statusLine | select(type == "object")' "$f" 2>/dev/null && return 0
  done
  return 0
}

# The --settings value every session hivehouse starts (an agent, an orchestrator the hub starts) is launched with: its statusLine is
# hh-statusline, which keeps Claude Code's own window reading in <agent dir>/context.json for hh-context, then runs the owner's
# statusLine. The owner's command rides in the value as one quoted argument; it is never kept in a file an away session can write, and
# a statusline.json left in the folder (0.5.2 wrote one) is removed. The owner's other statusLine keys (padding and the like) are kept.
hh_agent_settings() {  # hh_agent_settings <bin dir> <session cwd> <agent dir>
  local o; o=$(hh_owner_statusline "$2")
  rm -f "$3/statusline.json" "$3/context.json"
  jq -nc --argjson o "${o:-null}" --arg bin "$(cd "$1" && pwd -P)/hh-statusline" --arg dir "$3" \
    '{statusLine: (($o // {}) + {type: "command", command: ([$bin, $dir] + (if (($o // {}).command | type) == "string" then [$o.command] else [] end) | map(@sh) | join(" "))})}'
}

# An agent's session record, .hivehouse/team/<agent>/session.json {session_id, transcript_path, source, at}: hh-context reads
# it. The one writer, for the SessionStart hook and for hh-spawn --self. Never writes for a bad agent name or into a tracked
# .hivehouse; the write is atomic. Returns 1 when nothing was written.
hh_write_session() {  # hh_write_session <project root> <agent> <session id> <transcript path> <source>
  local dir="$1/$HH_STATE_DIR/team/$2"
  hh_is_agent_name "$2" && [ -n "$3" ] || return 1
  [ -z "$(git -C "$1" ls-files -- "$HH_STATE_DIR" 2>/dev/null)" ] || return 1
  mkdir -p "$dir" 2>/dev/null || return 1
  jq -nc --arg s "$3" --arg t "$4" --arg src "$5" --arg at "$(hh_now)" '{session_id:$s, transcript_path:$t, source:$src, at:$at}' \
    > "$dir/session.json.tmp$$" 2>/dev/null && mv "$dir/session.json.tmp$$" "$dir/session.json" || { rm -f "$dir/session.json.tmp$$"; return 1; }
}

# What a session has used of its context, read from its transcript (Claude Code's own format, undocumented: this is the one place it is read
# for this): the last main-conversation assistant line that carries usage (a sidechain's or a synthetic line would read as another agent's,
# or as zero), its input, cache and output tokens added. Prints nothing when there is none. hh-context and hh-hub context both read it here.
hh_transcript_used() {  # hh_transcript_used <transcript file>
  jq -c 'select(.type == "assistant" and .message.model != "<synthetic>" and (.isSidechain // false) == false)
      | .message.usage | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.output_tokens // 0)
      | select(. > 0)' "$1" 2>/dev/null | tail -1
}
# A reading against a window nobody measured: tokens over a window that was only assumed are no percent (a 1M session read 158-188).
hh_assumed_level() {  # hh_assumed_level <used tokens> <assumed window>
  [ "$1" -le "$2" ] || { echo "$1 tokens (window unknown)"; return 0; }
  echo "$(( $1 * 100 / $2 )) (window assumed $2)"
}
# The handoff an agent is sent back to: the path hh-spawn recorded with --handoff (a project that keeps it elsewhere), else the default
# under the state folder. A recorded path that is not an absolute path hivehouse will type is ignored, never typed.
hh_handoff_path() {  # hh_handoff_path <project root> <agent>
  local p; p=$(jq -r --arg a "$2" '[.agents[]? | select(.name == $a) | .handoff][0] // empty' "$1/$HH_STATE_DIR/team.json" 2>/dev/null)
  [ -z "$p" ] || { p=$(hh_handoff_resolve "$1" "$p" 2>/dev/null) && { printf '%s\n' "$p"; return 0; }; }
  printf '%s/%s/handoffs/%s.md\n' "$1" "$HH_STATE_DIR" "$2"
}
# hh_handoff_resolve <project root> <path>: the handoff path as it is typed and recorded: absolute (a relative one is taken from the project
# root), with no .., a path hivehouse will type, in a folder that exists, and inside the project (its root or one of its worktrees, links
# resolved). Prints it, or fails with the reason in HH_HANDOFF_WHY.
HH_HANDOFF_WHY=""; HH_HANDOFF_OUT=""
hh_handoff_resolve() {
  local root="$1" p="$2" dir real t
  HH_HANDOFF_WHY=""; HH_HANDOFF_OUT=""
  case "$p" in /*) ;; *) p="$root/$p" ;; esac
  case "/$p/" in */../*|*/./*) HH_HANDOFF_WHY="a handoff path has no . or .. in it: $2"; return 1 ;; esac
  [ ! -L "$p" ] || { HH_HANDOFF_WHY="the last part is a link (the template would be written through it): $p"; return 1; }
  hh_is_typed_path "$p" || { HH_HANDOFF_WHY="not a path hivehouse will type (letters, digits, / . _ - and space, at most 256): $p"; return 1; }
  dir=${p%/*}; [ -d "$dir" ] || { HH_HANDOFF_WHY="the folder does not exist: $dir"; return 1; }
  real="$(cd -P "$dir" && pwd -P)/${p##*/}"
  while IFS= read -r t; do
    t=$(cd -P "$t" 2>/dev/null && pwd -P) || continue   # git writes a worktree's path as it was typed: /var is /private/var
    case "$real" in "$t"/*) HH_HANDOFF_OUT=$real; printf '%s\n' "$real"; return 0 ;; esac
  done < <(printf '%s\n' "$(cd -P "$root" && pwd -P)"; git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  HH_HANDOFF_WHY="a handoff lives inside the project (its folder or one of its worktrees): $real"; return 1
}
# The hooks' one question: is this process the Claude hivehouse registered for the tmux pane it runs in? The project and agent come from the
# registry hh-spawn wrote, never from the cwd. 0 with HK_PROJECT and HK_AGENT set; 1 otherwise, and nothing is said. The registry file must
# still describe THIS pane: a restarted tmux server hands out pane ids again, and a file with no identity (an older format) proves nothing.
# Another pane, or no identity, removes the stale file; a tmux that cannot answer proves nothing either way, so the file stays. The nearest
# Claude above the caller must be the recorded one (--self recorded the Claude that called it, the pane's own process being the owner's
# shell; a spawned agent's pane runs claude itself, so its pane process is the record). A recorded Claude that is gone makes the file
# stale and it is removed. One that is alive but is not the nearest is a nested run (a `claude -p` from the agent's own Bash, which
# inherits the pane): nothing is written and the file stays, for the session it belongs to. /clear keeps the process.
HK_PROJECT=""; HK_AGENT=""
hh_hook_session() {
  local socket reg same cpid cstart anc
  HK_PROJECT=""; HK_AGENT=""
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 1
  socket="${TMUX%%,*}"
  reg="$(hh_registry_dir)/$(hh_pane_key "$socket" "$TMUX_PANE").json"
  [ -f "$reg" ] || return 1
  HK_PROJECT=$(hh_json_get "$reg" .project); HK_AGENT=$(hh_json_get "$reg" .agent)
  [ -n "$HK_PROJECT" ] && [ -n "$HK_AGENT" ] && [ -d "$HK_PROJECT" ] || { HK_PROJECT=""; HK_AGENT=""; return 1; }
  hh_pane_is "$socket" "$TMUX_PANE" "$(hh_json_get "$reg" .pane_pid)" "$(hh_json_get "$reg" .pane_started)"; same=$?
  [ "$same" -ne 2 ] || { HK_PROJECT=""; HK_AGENT=""; return 1; }
  [ "$same" -eq 0 ] || { rm -f "$reg"; HK_PROJECT=""; HK_AGENT=""; return 1; }
  cpid=$(hh_json_get "$reg" .claude_pid); cstart=$(hh_json_get "$reg" .claude_started)
  [ -n "$cpid" ] || { cpid=$(hh_json_get "$reg" .pane_pid); cstart=$(hh_json_get "$reg" .pane_started); }
  hh_claude_is "$cpid" "$cstart" || { rm -f "$reg"; HK_PROJECT=""; HK_AGENT=""; return 1; }
  anc=$(hh_claude_ancestor) && [ "$anc" = "$cpid" ] || { HK_PROJECT=""; HK_AGENT=""; return 1; }
  return 0
}
# The line that starts (hh-spawn) or restarts (hh-rotate) an agent from its handoff: one text, so they cannot drift. The
# orchestrator itself (hh-self-rotate) reports to nobody, waits for nobody, and --self gives it no role or rules dir.
hh_pickup_line() {  # hh_pickup_line <project name> <project root> <agent>
  if [ "$(hh_self_entry "$2" | jq -r '.name // empty' 2>/dev/null)" = "$3" ]; then
    printf 'You are %s. Read %s from the top: its START HERE block is your prompt.' "$(hh_orchestrator_name "$2")" "$(hh_handoff_path "$2" "$3")"
    # registered with --hub: the owner talks to it through the hub, which a /clear would otherwise forget
    local hub; hub=$(hh_self_entry "$2" | jq -r '.hub // empty' 2>/dev/null)
    if [ -n "$hub" ] && hh_is_session_name "$hub"; then
      printf ' The owner talks to you only through %s: send it your questions, plans, blockers and finished work with SendMessage, and take its OWNER replies as the owner'"'"'s words.' "$hub"
    fi
    # the owner's output style, when installed, is read again after every clear (a /clear wipes it with the rest)
    local style; style=$(hh_adhd_skill 2>/dev/null) || return 0
    if hh_is_typed_path "$style"; then printf ' Read %s and follow it for every message to the owner.' "$style"
    else echo "$HH_PREFIX: the i-have-adhd path is not one hivehouse will type, so the pickup line leaves it out: $style" >&2; fi
    return
  fi
  printf 'You are %s-%s. Read %s from the top: its START HERE block is your prompt, and %s/%s/team/%s/ holds your role and the rules. Report to %s. Wait for its first message before any work.' \
    "$1" "$3" "$(hh_handoff_path "$2" "$3")" "$2" "$HH_STATE_DIR" "$3" "$(hh_orchestrator_name "$2")"
}
# What an agent resumed with its own session (hh-spawn --respawn --resume) is typed instead of the pickup line: its session
# already holds the work, so it is told only why it was restarted and where its handoff is.
hh_resume_line() {  # hh_resume_line <project root> <agent>
  printf 'You were restarted by hivehouse after your session stopped responding. Carry on where you were; your handoff is %s.' "$(hh_handoff_path "$1" "$2")"
}

# The ASCII letters and digits, listed and never written as a range: under bash 3.2 a bracket range follows the locale's
# collation, and in en_US.UTF-8 `[a-z]` takes capitals, é, ß and fullwidth letters too. Every check of a name builds its
# bracket expression from these, unquoted inside the brackets (the lists hold no pattern character).
HH_LOWER='abcdefghijklmnopqrstuvwxyz'
HH_UPPER='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
HH_DIGITS='0123456789'

# A session name hivehouse will type into a pane (it goes through send-keys): one line of letters, digits, space, '-', '_',
# '.', '(' and ')', at most 64 characters.
HH_SESSION_NAME_CHARS="${HH_LOWER}${HH_UPPER}${HH_DIGITS} ._()-"
hh_is_session_name() {  # hh_is_session_name <name>: 0 when it is one
  case "$1" in ''|*[!$HH_SESSION_NAME_CHARS]*) return 1 ;; esac
  [ "${#1}" -le 64 ]
}
# Claude Code's own record of a running session, <config dir>/sessions/<pid>.json (undocumented, checked against
# 2.1.286): prints the field when the record is that pid's, else nothing. A missing file or field, another pid or a file
# that is not JSON is no answer, never an error.
hh_session_record() {  # hh_session_record <pid> <jq path>
  case "$1" in ''|*[!0-9]*) return 0 ;; esac
  "${HH_JQ:-jq}" -j --arg p "$1" "select((.pid | tostring) == \$p) | $2 // empty" "$(hh_claude_dir)/sessions/$1.json" 2>/dev/null
}
# A live Claude process already holding a conversation, from Claude Code's own session records: prints its pid, or fails when none
# is. Records of dead processes, of processes that are not Claude, and files that are not JSON are no answer.
hh_session_holder() {  # hh_session_holder <session id>
  local f p
  for f in "$(hh_claude_dir)"/sessions/*.json; do
    [ -f "$f" ] || continue
    p=$(jq -r --arg s "$1" 'select(.sessionId == $s) | .pid // empty' "$f" 2>/dev/null) || continue
    hh_is_claude "$p" && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}
hh_session_transcript() {  # hh_session_transcript <session id>: the one <id>.jsonl under <config dir>/projects/*/, else fails
  local m n
  case "$1" in ''|*[!${HH_LOWER}${HH_UPPER}${HH_DIGITS}-]*) return 1 ;; esac
  m=$(find "$(hh_claude_dir)/projects" -mindepth 2 -maxdepth 2 -type f -name "$1.jsonl" 2>/dev/null)
  n=$(printf '%s' "$m" | grep -c .)
  [ "$n" -eq 1 ] && printf '%s\n' "$m"
}
# A conversation that ended without registering: Claude Code's transcripts, <config dir>/projects/<key>/<session id>.jsonl (the format is Claude
# Code's and undocumented; this is the one place it is read for this). <key> is the folder with / . _ & and space each turned into '-', so
# a/b, a_b and a-b share one: the key alone proves nothing, and the records' own cwd must be the team root, exactly and alone. A root whose key
# folder is not there (Claude Code shortens a long path in a way not measured) is skipped, never guessed. Of the newest 20 transcripts per root,
# the newest whose last custom-title record is <title> and whose every cwd is the root wins. Sets HH_RESUME_SID and HH_RESUME_ROOT, else fails.
HH_RESUME_SID=""; HH_RESUME_ROOT=""
hh_mtime() {  # hh_mtime <path>: modification time, epoch seconds
  if /usr/bin/stat --version >/dev/null 2>&1; then /usr/bin/stat -c %Y -- "$1"; else /usr/bin/stat -f %m "$1"; fi
}
hh_dir_fingerprint() {  # hh_dir_fingerprint <file>...: a hash of each file's name, time and size
  if /usr/bin/stat --version >/dev/null 2>&1; then /usr/bin/stat -c '%n %Y %s' -- "$@" 2>/dev/null; else /usr/bin/stat -f '%N %m %z' "$@" 2>/dev/null; fi | /usr/bin/shasum | cut -d' ' -f1
}
# What a root's newest transcripts said is kept in <home>/cache/resume-<hash of the root and the title> with a fingerprint of those 20 files
# (name, time, size): the screen asks every 20 seconds, and reading a real folder of transcripts takes most of a second per project. The
# kept answer is used only while the fingerprint is the same; a file that grew, a new file or a removed one reads again.
hh_resume_root() {  # hh_resume_root <title> <root>: prints "<session id><TAB><mtime>" of the best match under that root, or nothing
  local title="$1" r="$2" key dir f id t last cwds n=0 files=() fp ck kept
  key=$(printf '%s' "$r" | tr '/._& ' '-----')
  dir="$(hh_claude_dir)/projects/$key"
  [ -d "$dir" ] || return 0
  while IFS= read -r f; do files+=("$f"); done < <(ls -t "$dir"/*.jsonl 2>/dev/null | head -20)
  [ ${#files[@]} -gt 0 ] || return 0
  fp=$(hh_dir_fingerprint "${files[@]}")
  ck="$(hh_home)/cache/resume-$(printf '%s|%s' "$r" "$title" | /usr/bin/shasum | cut -c1-24)"
  # a kept answer is trusted no further than a fresh one: the same id rule, and a numeric time ("-", no match, stays valid)
  if { IFS= read -r kept; } 2>/dev/null < "$ck" && [ "${kept%%$'\t'*}" = "$fp" ]; then
    kept=${kept#*$'\t'}; id=${kept%%$'\t'*}; t=${kept#*$'\t'}
    if [ "$kept" = - ]; then return 0; fi
    case "$id" in ''|*[!${HH_LOWER}${HH_UPPER}${HH_DIGITS}-]*) ;; *)
      case "$t" in ''|*[!0-9]*) ;; *) printf '%s\n' "$kept"; return 0 ;; esac ;;
    esac
  fi
  kept=-
  for f in "${files[@]}"; do
    id=${f##*/}; id=${id%.jsonl}
    case "$id" in ''|*[!${HH_LOWER}${HH_UPPER}${HH_DIGITS}-]*) continue ;; esac
    last=$(grep -a '"type":"custom-title"' "$f" 2>/dev/null | tail -1 | jq -r '.customTitle // empty' 2>/dev/null)
    [ "$last" = "$title" ] || continue
    cwds=$(jq -r '.cwd // empty' "$f" 2>/dev/null | sort -u)
    [ "$cwds" = "$r" ] || continue
    t=$(hh_mtime "$f") || continue
    kept="$id"$'\t'"$t"; break   # the newest match of this root
  done
  { mkdir -p "$(hh_home)/cache" && printf '%s\t%s\n' "$fp" "$kept" > "$ck.tmp$$" && mv "$ck.tmp$$" "$ck"; } 2>/dev/null || rm -f "$ck.tmp$$" 2>/dev/null
  [ "$kept" = - ] || printf '%s\n' "$kept"
}
hh_resume_candidate() {  # hh_resume_candidate <title> <team root>...
  local title="$1" r got id t best=0
  HH_RESUME_SID=""; HH_RESUME_ROOT=""; shift
  for r in "$@"; do
    got=$(hh_resume_root "$title" "$r"); [ -n "$got" ] || continue
    id=${got%%$'\t'*}; t=${got#*$'\t'}
    if [ "$t" -gt "$best" ]; then best=$t; HH_RESUME_SID=$id; HH_RESUME_ROOT=$r; fi
  done
  [ -n "$HH_RESUME_SID" ]
}
# The i-have-adhd output style (an optional companion plugin): its SKILL.md when Claude Code lists a plugin of that name,
# from any marketplace, as enabled and the file is there. Reads `claude plugin list --json` and tests the file, nothing
# else; never installs, enables or switches it on. When its always-on flag exists the plugin already applies itself to
# every session, so it is not loaded a second time. Prints the path, or fails.
hh_adhd_skill() {
  local flag="$(hh_claude_dir)/.i-have-adhd-always" d
  if [ -e "$flag" ]; then echo "$HH_PREFIX: i-have-adhd is always on ($flag) and applies itself; not loaded again" >&2; return 1; fi
  while IFS= read -r d; do
    [ -n "$d" ] && [ -f "$d/skills/i-have-adhd/SKILL.md" ] && { printf '%s\n' "$d/skills/i-have-adhd/SKILL.md"; return 0; }
  done <<EOF2
$(claude plugin list --json 2>/dev/null | jq -r '.[]? | select(((.id // "") | startswith("i-have-adhd@")) and .enabled == true) | .installPath // empty' 2>/dev/null)
EOF2
  return 1
}
# A path hivehouse will type into a pane: one line of letters, digits, '/', '.', '_', '-' and space, at most 256 characters.
hh_is_typed_path() {  # hh_is_typed_path <path>: 0 when it is one
  local chars="${HH_LOWER}${HH_UPPER}${HH_DIGITS}/._ -"
  case "$1" in ''|*[!$chars]*) return 1 ;; esac
  [ "${#1}" -le 256 ]
}
hh_self_entry() {  # hh_self_entry <project root>: the team.json entry hh-spawn --self wrote (only it records a Claude process), or nothing
  "${HH_JQ:-jq}" -c '[.agents[]? | select((.claude_pid // "") != "")][0] // empty' "$1/$HH_STATE_DIR/team.json" 2>/dev/null
}
# The name agents report to: the --self orchestrator's session name as Claude Code has it now (a /rename after --self is
# followed), else the name recorded at --self, else <project>-orchestrator. One helper for every text that names it.
hh_orchestrator_name() {  # hh_orchestrator_name <project root>
  local o pid started live="" full n
  o=$(hh_self_entry "$1")
  pid=$(printf '%s' "$o" | jq -r '.claude_pid // empty' 2>/dev/null); started=$(printf '%s' "$o" | jq -r '.claude_started // empty' 2>/dev/null)
  full=$(printf '%s' "$o" | jq -r '.name_full // empty' 2>/dev/null)
  if [ -n "$pid" ] && hh_claude_is "$pid" "$started"; then
    live=$(hh_session_record "$pid" .name)
  fi
  for n in "$live" "$full"; do
    [ -n "$n" ] || continue
    hh_is_session_name "$n" && { printf '%s\n' "$n"; return 0; }
    echo "$HH_PREFIX: the orchestrator's session name is not one hivehouse will type; using another" >&2
  done
  printf '%s-orchestrator\n' "$(basename "$1")"
}

# A gate's step name, the one rule hh-gate's steps and hh-gate-verify's expected names and lines are read by: letters,
# digits, '_', '.' and '-', with no '..'. HH_STEP_NAME_CHARS is a bracket expression's contents, built from the lists
# above with '-' last, so no reader (grep -E, sed -E or a case) can take it as a range.
HH_STEP_NAME_CHARS="${HH_UPPER}${HH_LOWER}${HH_DIGITS}_.-"
HH_STEP_NAME_RULE="letters, digits, '_', '.' and '-' with no '..'"
hh_is_step_name() {  # hh_is_step_name <name>: 0 when it is one
  printf '%s' "$1" | grep -Eq "^[${HH_STEP_NAME_CHARS}]+\$" || return 1
  case "$1" in *..*) return 1 ;; esac
  return 0
}

# An agent's name, the one rule hh-spawn and the session hook read: lower-case letters, digits, '_' and '-', not starting
# with '_' or '-'.
hh_is_agent_name() {  # hh_is_agent_name <name>: 0 when it is one
  case "$1" in ''|*[!${HH_LOWER}${HH_DIGITS}_-]*|[-_]*) return 1 ;; esac
  return 0
}

# How strict a permission mode is, for "only ever stricter": plan and dontAsk are the same, bypassPermissions the loosest. Fails for
# anything else. (hh-settings wraps it and refuses bypassPermissions as a local value.)
hh_mode_rank() {  # hh_mode_rank <mode>
  case "$1" in plan|dontAsk) echo 0 ;; default) echo 1 ;; acceptEdits) echo 2 ;; auto) echo 3 ;; bypassPermissions) echo 4 ;; *) return 1 ;; esac
}

# A git branch as hivehouse takes one (hh-spawn's --branch and --base, the manifest's base): letters, digits, '.', '_',
# '/' and '-', not starting with '-', which git would read as an option.
hh_is_branch_name() {  # hh_is_branch_name <name>: 0 when it is one
  case "$1" in ''|-*|*[!${HH_LOWER}${HH_UPPER}${HH_DIGITS}._/-]*) return 1 ;; esac
  return 0
}

# A remote host as hivehouse takes one (hh-remote-sync's host, the manifest's host): letters, digits, '.', '_', '@' and
# '-', not starting with '-', which ssh would read as an option.
hh_is_host_name() {  # hh_is_host_name <name>: 0 when it is one
  case "$1" in ''|-*|*[!${HH_LOWER}${HH_UPPER}${HH_DIGITS}._@-]*) return 1 ;; esac
  return 0
}

# ---- reading a dialog (the hub shows it to the owner, who answers through hh-hub answer) ------------------------------
# TIED TO THE CLAUDE CODE TERMINAL UI (captured from 2.1.291; tests/fixtures/dialogs/). A dialog replaces the prompt box: a
# rule, its text, then options and a footer line ("Esc to cancel", "Enter to confirm", "Enter to select"). Permission and
# AskUserQuestion dialogs number their options "1. Yes", and a digit selects and confirms; the folder-trust dialog does not:
# its rows are moved to with the arrow keys and confirmed with Enter, the "❯" marking the row the cursor is on. The region is
# found from the footer up to the topmost rule above it, stopping at what the conversation looks like (a tool line, the
# user's echoed prompt); lines are right-trimmed, so a screen's padding never changes its fingerprint.
HH_DIALOG_FOOTER='Esc to cancel|Enter to confirm|Enter to select|Press Enter to continue'
# options the hub never offers: they need the owner's own text, or are keys rather than choices
HH_DIALOG_NOT_OFFERED='^(Type something\.?|Chat about this)$'
IFS= read -r -d '' HH_DIALOG_PERL <<'PERL' || true
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
hh_dialog_parse() {  # a pane captured with -e on stdin: JSON {kind, text, options, cursor, esc, fingerprint}; 3 when no dialog is up
  local text json fp
  text=$(perl -pe 's/\e\][^\a\e]*(?:\a|\e\\)//g' | hh_pane_clean)
  printf '%s\n' "$text" | hh_pane_idle_text; [ $? -eq 3 ] || return 3
  json=$(printf '%s\n' "$text" | perl -e "$HH_DIALOG_PERL" -- "$HH_DIALOG_FOOTER" "$HH_DIALOG_NOT_OFFERED") || return 3
  fp=$(printf '%s' "$json" | jq -r '.text' | shasum | cut -d' ' -f1)
  printf '%s' "$json" | jq -c --arg f "$fp" '. + {fingerprint:$f}'
}
hh_pane_dialog() {  # hh_pane_dialog <socket, or empty for hivehouse's own server> <pane>: hh_dialog_parse of that pane; 1 when it cannot be read
  local t
  t=$(hh_tmux_on "$1" capture-pane -p -e -J -t "$2" 2>/dev/null) || return 1
  printf '%s\n' "$t" | hh_dialog_parse
}

# ---- the away switch: a file only root can have written ----------------------------------------------------------------
# Delegate mode (the hub decides for the owner while they are away) is on exactly while this file is valid. It sits where
# a session running as the owner's user cannot have written it, and the owner makes it with sudo from lines `hh-hub away`
# prints (hivehouse never runs sudo). The predicate takes the path and the owner it requires; production passes only the
# fixed path and root (hh_delegate_now), and nothing in the environment or a setting changes the path, the owner or the
# content: a way to change them would be a way round the check. Valid means: the file, its folder and every folder above it
# are not links (lstat) and not writable by group or others; the file and its folder are owned by the required user, the
# folders above by the required user or root (with root required, root alone); the content is exactly
#   hivehouse-delegate <version> / hub=<absolute path> / until=<epoch seconds> / mcp=<comma-separated servers or tools, may be empty>
#   and, from version 2, hosts=<ssh hosts the away sessions may reach, may be empty> / allow=<scp, rsync or sftp, may be empty>
#   and, from version 3, tools=<extra tools the away sessions may use: Workflow, WebFetch, DesignSync, ArtifactCheck, PushNotification; may be empty>
#   (version 1 is exactly the first four lines, version 2 exactly the first six, version 3 exactly these seven)
# with `until` in the future and at most 7 days ahead (a CronCreate heartbeat does not outlive that). HH_DELEGATE_WHY is set
# to the first check that failed.
# the process's real uid, read by /usr/bin/id: bash 3.2 takes UID and EUID from the environment, even under -p. One exact line, which a test rewrites.
hh_real_uid() { /usr/bin/id -u; }
# the folder of the delegate files, under /Library on macOS (/etc is a link there), /etc on Linux: macOS has /System, and $OSTYPE would come through the environment
hh_delegate_base() { if [ -d /System/Library ]; then echo "$HH_MAC_BASE"; else echo "$HH_LINUX_BASE"; fi; }
hh_delegate_path() {  # one file per user: <base>/delegate.d/<uid>; no path when the uid is not digits
  local u; u=$(hh_real_uid) || return 1
  case "$u" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s/delegate.d/%s\n' "$(hh_delegate_base)" "$u"
}
# Nothing here is found through PATH: every outside command is called by absolute path, and the rest is built-ins, so a fake
# `date` or a function from BASH_ENV or the environment cannot revive an expired file (the executables that ask start with
# #!/bin/bash -p for the same reason).
hh_stat3() {  # hh_stat3 <path>: "<uid> <octal mode> <type>" of the path itself (lstat, /usr/bin/stat in either form), or fails
  local out
  if /usr/bin/stat --version >/dev/null 2>&1; then out=$(/usr/bin/stat -c '%u %a %F' -- "$1" 2>/dev/null)
  else out=$(/usr/bin/stat -f '%u %Lp %HT' "$1" 2>/dev/null); fi
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}
hh_path_trusted() {  # hh_path_trusted <path> <file|dir> <uid> <strict|loose>: not a link, the right kind, owned (loose: or by root), not group- or world-writable
  local st u m t g o
  st=$(hh_stat3 "$1") || { HH_DELEGATE_WHY="$1 cannot be read"; return 1; }
  read -r u m t <<< "$st"
  case "$t" in *[Ss]ymbolic*) HH_DELEGATE_WHY="$1 is a link"; return 1 ;; esac
  case "$2:$t" in file:*[Rr]egular*|dir:*[Dd]irectory*) ;; *) HH_DELEGATE_WHY="$1 is not a $2"; return 1 ;; esac
  if [ "$u" != "$3" ] && { [ "$4" != loose ] || [ "$u" != 0 ]; }; then HH_DELEGATE_WHY="$1 is owned by uid $u"; return 1; fi
  m=${m: -3}; g=${m:1:1}; o=${m:2:1}
  if [ $((g & 2)) -ne 0 ] || [ $((o & 2)) -ne 0 ]; then HH_DELEGATE_WHY="$1 is writable by group or others (mode $m)"; return 1; fi
  return 0
}
hh_stat4() {  # hh_stat4 <path>: the path's own mode as four octal digits (setgid and sticky kept), or fails. macOS %Lp drops them
  local m
  if /usr/bin/stat --version >/dev/null 2>&1; then m=$(/usr/bin/stat -c '%a' -- "$1" 2>/dev/null)
  else m=$(/usr/bin/stat -f '%Mp%Lp' "$1" 2>/dev/null); fi
  hh_pad4 "$m"
}
hh_pad4() {  # hh_pad4 <octal digits>: four digits (Linux %a prints 775, not 0775), or fails when it is no octal number
  local m="$1"
  case "$m" in ''|*[!0-7]*) return 1 ;; esac
  while [ "${#m}" -lt 4 ]; do m="0$m"; done
  printf '%s\n' "$m"
}
# hh_chain_trusted <folder> <uid>: the folder and every folder above it pass hh_path_trusted loose (owned by the uid or root, not a
# link, not writable by group or others); fails with the reason in HH_DELEGATE_WHY. One walk for the delegate file, the machine slot and jq.
hh_chain_trusted() {
  local p="$1" want="$2" i=0
  while :; do
    [ -n "$p" ] || p=/
    hh_path_trusted "$p" dir "$want" loose || return 1
    [ "$p" = / ] && return 0
    p=${p%/*}; i=$((i + 1)); [ "$i" -lt 64 ] || { HH_DELEGATE_WHY="the path is too deep"; return 1; }
  done
}
# ---- the machine's one slot (bin/hh-slot). One folder for every user, made once by an administrator (hh-slot setup prints
# the lines): slot/ and slot/queue/, owned by root, mode exactly 2775, under folders only root can write. Used only when all of
# that holds; HH_SLOT_LOCAL=1 opts out and nothing in the environment can name another folder. The two one-line functions are
# the tests' seams: a scratch copy of bin/ rewrites them to a fixture and to this user's uid.
hh_machine_slot_dir() { if [ -d /System/Library ]; then echo "$HH_MAC_BASE/slot"; else echo "$HH_LINUX_SLOT"; fi; }
hh_machine_slot_owner() { echo 0; }
# hh_machine_slot_ok <dir>: 0 when the folder may be used; otherwise 1 with the reason in HH_SLOT_WHY
hh_machine_slot_ok() {
  local d="$1" owner f st u m t
  owner=$(hh_machine_slot_owner)
  [ -d "$d" ] || { HH_SLOT_WHY="$d does not exist"; return 1; }
  for f in "$d" "$d/queue"; do
    st=$(hh_stat3 "$f") || { HH_SLOT_WHY="$f cannot be read"; return 1; }
    read -r u m t <<< "$st"
    case "$t" in *[Ss]ymbolic*) HH_SLOT_WHY="$f is a link"; return 1 ;; esac
    case "$t" in *[Dd]irectory*) ;; *) HH_SLOT_WHY="$f is not a folder"; return 1 ;; esac
    [ "$u" = "$owner" ] || { HH_SLOT_WHY="$f is owned by uid $u, not $owner"; return 1; }
    m=$(hh_stat4 "$f") || { HH_SLOT_WHY="$f cannot be read"; return 1; }
    [ "$m" = 2775 ] || { HH_SLOT_WHY="$f has mode $m, not 2775"; return 1; }
  done
  hh_chain_trusted "${d%/*}" "$owner" || { HH_SLOT_WHY="$HH_DELEGATE_WHY"; return 1; }
}
# The jq every check that grants away powers uses. A bare `jq` comes from PATH, which a session's own Bash command sets, so a fake one could
# answer for a hub it is not or a project that is not listed. This is the first of three fixed paths that is root's along its whole path (the
# file and every folder above it owned by root, not links, not writable by group or others): a Homebrew jq belongs to the user, so it never
# passes, and the user's own account is exactly the away session being guarded. macOS has /usr/bin/jq since 15.
hh_jq_candidates() { echo '/usr/bin/jq /usr/local/bin/jq /opt/homebrew/bin/jq'; }
hh_jq_fixed() {  # prints the path of the first root-owned jq, or fails
  local c
  for c in $(hh_jq_candidates); do
    hh_path_trusted "$c" file 0 loose || continue
    hh_chain_trusted "${c%/*}" 0 || continue
    printf '%s\n' "$c"; return 0
  done
  return 1
}
# HH_JQ and HH_JQ_DONE are set here, when the library loads, whatever the environment held (bash -p still imports variables): empty and not done.
# hh_jq_resolve then fills HH_JQ on first need. A check that grants away powers calls it first and refuses while HH_JQ is empty.
HH_JQ=""; HH_JQ_DONE=0
hh_jq_resolve() {  # sets HH_JQ once per process, on first need (the stats cost ~20 ms, which most scripts never need); call it in the caller's shell, since a $(...) would keep its answer to itself
  [ "$HH_JQ_DONE" = 1 ] && return 0
  HH_JQ=$(hh_jq_fixed) || HH_JQ=""; HH_JQ_DONE=1
}
# hh_delegate_check_list <hosts|allow|tools|peers> <list>: 0 when the list is valid, else 1 with HH_DELEGATE_WHY saying why. hosts: every comma-separated entry
# is [A-Za-z0-9._-]+ with at most one user@ in front, and no entry starts with - (ssh would read it as an option). allow: RESERVED in 0.5.1, so it
# must be empty. A listed scp, rsync or sftp would reach any host, read ~/.ssh/config like ssh, and offers routes that run a program (--rsync-path,
# sftp -b, scp -O); the push, sync and deploy words would be a standing grant of up to 7 days against "a word given for one run does not carry to
# the next". No command is allowable until a form that cannot do those things is designed.
hh_delegate_check_list() {
  local kind="$1" list="$2" e rest="$2"
  [ -n "$list" ] || return 0
  [ "$kind" != allow ] || { HH_DELEGATE_WHY="allow= is reserved; no command is allowable in this version"; return 1; }
  while :; do
    e=${rest%%,*}
    case "$kind" in
      tools) case "$e" in ''|*[!${HH_LOWER}${HH_UPPER}]*) HH_DELEGATE_WHY="tools= has an entry that is not one of${HH_DELEGATE_TOOLS}: '$e'"; return 1 ;; esac   # letters only: a space or a glob would match the list below
             case "$HH_DELEGATE_TOOLS" in *" $e "*) ;; *) HH_DELEGATE_WHY="tools= has an entry that is not one of${HH_DELEGATE_TOOLS}: '$e'"; return 1 ;; esac ;;
      peers) case "$e" in ''|*[!${HH_LOWER}${HH_UPPER}${HH_DIGITS}._-]*|-*) HH_DELEGATE_WHY="peers= has an entry that is not a plain session name (letters, digits, . _ -, no spaces, brackets, commas or wildcards): '$e'"; return 1 ;; esac ;;
      hosts) case "$e" in
               ''|@*|*@|*@*@*|*[!${HH_LOWER}${HH_UPPER}${HH_DIGITS}._@-]*) HH_DELEGATE_WHY="hosts= has an entry that is not a host name or user@host: '$e'"; return 1 ;;
             esac
             case "${e#*@}" in -*|'') HH_DELEGATE_WHY="hosts= has an entry that is not a host name or user@host: '$e'"; return 1 ;; esac ;;
    esac
    case "$rest" in *,*) rest=${rest#*,} ;; *) break ;; esac
  done
}
hh_delegate_read() {  # hh_delegate_read <path> <uid> [<now>]: prints "<hub><TAB><until><TAB><mcp>" when the file is valid; 1 when it is not
  local f="$1" want="$2" now="${3:-}" d hub until mcp l1="" l2="" l3="" l4="" l5="" l6="" l7="" l8="" nl line dl ver hosts="" allow="" tools="" peers="" want_lines
  HH_DELEGATE_WHY=""; HH_DR_HUB=""; HH_DR_UNTIL=""; HH_DR_MCP=""; HH_DR_HOSTS=""; HH_DR_TOOLS=""; HH_DR_PEERS=""; HH_DR_ABSENT=""
  [ -e "$f" ] || [ -L "$f" ] || HH_DR_ABSENT=1   # no file at all: not away, and nothing to explain
  [ -n "$now" ] || now=$(/bin/date +%s)
  case "$f" in /*) ;; *) HH_DELEGATE_WHY="the path is not absolute"; return 1 ;; esac
  hh_is_number "$want" && hh_is_number "$now" || { HH_DELEGATE_WHY="bad uid or time"; return 1; }
  hh_path_trusted "$f" file "$want" strict || return 1
  d=${f%/*}; [ -n "$d" ] || d=/
  hh_path_trusted "$d" dir "$want" strict || return 1
  hh_chain_trusted "${d%/*}" "$want" || return 1
  # up to 9 lines (one past the longest version), counted: a blank line is a line (comparing the text of the later lines to "" would let one through)
  dl=(); nl=0
  while [ "$nl" -lt 9 ] && { IFS= read -r line || [ -n "$line" ]; }; do dl[nl]=$line; nl=$((nl + 1)); line=""; done < "$f" 2>/dev/null
  l1=${dl[0]-}; l2=${dl[1]-}; l3=${dl[2]-}; l4=${dl[3]-}; l5=${dl[4]-}; l6=${dl[5]-}; l7=${dl[6]-}; l8=${dl[7]-}
  case "$l1$l2$l3$l4$l5$l6$l7$l8" in *$'\r'*) HH_DELEGATE_WHY="the content has carriage returns"; return 1 ;; esac
  ver=${l1#"$HH_DELEGATE_TAG "}
  case "$l1" in "$HH_DELEGATE_TAG "?*) ;; *) ver="" ;; esac
  case "$HH_DELEGATE_VERSIONS" in *" $ver "*) ;; *) HH_DELEGATE_WHY="the first line is not '$HH_DELEGATE_TAG <version>' with a version in:$HH_DELEGATE_VERSIONS"; return 1 ;; esac
  case "$ver" in 1) want_lines=4 ;; 2) want_lines=6 ;; 3) want_lines=7 ;; *) want_lines=8 ;; esac
  # the lines past the version's own count: none (a version 1 file has no fifth line, a version 2 file no seventh, a version 3 file no eighth, a version 4 file no ninth)
  [ "$nl" -le "$want_lines" ] || { HH_DELEGATE_WHY="the content is more than $want_lines lines (a version $ver file has exactly $want_lines)"; return 1; }
  hub=$l2; until=$l3
  case "$hub" in hub=/*) hub=${hub#hub=} ;; *) HH_DELEGATE_WHY="line 2 is not hub=<absolute path>"; return 1 ;; esac
  hh_is_typed_path "$hub" || { HH_DELEGATE_WHY="the hub path is not one hivehouse will type"; return 1; }
  case "$until" in until=*) until=${until#until=} ;; *) HH_DELEGATE_WHY="line 3 is not until=<epoch>"; return 1 ;; esac
  hh_is_number "$until" || { HH_DELEGATE_WHY="until is not a number"; return 1; }
  case "$l4" in mcp=*) mcp=${l4#mcp=} ;; *) HH_DELEGATE_WHY="line 4 is not mcp=<list>"; return 1 ;; esac
  case "$mcp" in *[!${HH_LOWER}${HH_UPPER}${HH_DIGITS}_,.:-]*) HH_DELEGATE_WHY="the mcp list has a character outside letters, digits and _ , . : -"; return 1 ;; esac
  if [ "$want_lines" -ge 6 ]; then
    case "$l5" in hosts=*) hosts=${l5#hosts=} ;; *) HH_DELEGATE_WHY="line 5 is not hosts=<list>"; return 1 ;; esac
    case "$l6" in allow=*) allow=${l6#allow=} ;; *) HH_DELEGATE_WHY="line 6 is not allow=<list>"; return 1 ;; esac
    hh_delegate_check_list hosts "$hosts" || return 1
    hh_delegate_check_list allow "$allow" || return 1
  fi
  if [ "$want_lines" -ge 7 ]; then
    case "$l7" in tools=*) tools=${l7#tools=} ;; *) HH_DELEGATE_WHY="line 7 is not tools=<list>"; return 1 ;; esac
    hh_delegate_check_list tools "$tools" || return 1
  fi
  if [ "$want_lines" = 8 ]; then
    case "$l8" in peers=*) peers=${l8#peers=} ;; *) HH_DELEGATE_WHY="line 8 is not peers=<list>"; return 1 ;; esac
    hh_delegate_check_list peers "$peers" || return 1
  fi
  [ "$until" -gt "$now" ] || { HH_DELEGATE_WHY="the file has expired"; return 1; }
  [ "$until" -le $((now + 604800)) ] || { HH_DELEGATE_WHY="until is more than 7 days ahead"; return 1; }
  HH_DR_HUB=$hub; HH_DR_UNTIL=$until; HH_DR_MCP=$mcp; HH_DR_HOSTS=$hosts; HH_DR_TOOLS=$tools; HH_DR_PEERS=$peers
  printf '%s\t%s\t%s\n' "$hub" "$until" "$mcp"
}
hh_delegate_now() { hh_delegate_read "$(hh_delegate_path)" 0; }
# hh_delegate_mine: 0 when this user's delegate file is valid and the hub it names is this user's; sets HH_DG_HUB (resolved), HH_DG_UNTIL,
# HH_DG_MCP and HH_DG_UID, else HH_DELEGATE_WHY says which check failed. It runs in the caller's shell, never inside $(...): the output of
# hh_delegate_now is dropped and its HH_DR_* variables are read instead. It is the only caller of hh_delegate_now. The hub, its
# .hivehouse-hub/, projects.json (which decides the homes that get bypass) and hub.json (the identity away_hub_caller checks) must belong to
# the caller and not be a link or writable by group or others: a user who could write them could name their own project, or the hub.
# hh_hub_records_trusted <hub root> <uid>: 0 when the hub folder, .hivehouse-hub/, projects.json and hub.json all belong to that user (hh_path_trusted
# strict); else 1, with HH_DELEGATE_WHY the first reason and HH_BAD_LIST every failing path as "<path><TAB><reason>" lines. The one list of what
# decides a hub, shared by hh_delegate_mine and the check `hh-hub away` runs before it prints anything.
HH_BAD_LIST=""
hh_hub_records_trusted() {
  local h="$1" u="$2" kind p first=""
  HH_BAD_LIST=""
  for kind in "dir:$h" "dir:$h/$HH_HUB_DIR" "file:$h/$HH_HUB_DIR/projects.json" "file:$h/$HH_HUB_DIR/hub.json"; do
    p=${kind#*:}
    hh_path_trusted "$p" "${kind%%:*}" "$u" strict && continue
    [ -n "$first" ] || first=$HH_DELEGATE_WHY
    HH_BAD_LIST="$HH_BAD_LIST$p"$'\t'"$HH_DELEGATE_WHY"$'\n'
  done
  [ -z "$HH_BAD_LIST" ] && return 0
  HH_DELEGATE_WHY=$first; return 1
}
HH_DG_UID=""
hh_delegate_mine() {
  HH_DG_HUB=""; HH_DG_UNTIL=""; HH_DG_MCP=""; HH_DG_HOSTS=""; HH_DG_TOOLS=""; HH_DG_PEERS=""; HH_DG_UID=$(hh_real_uid) || HH_DG_UID=""
  case "$HH_DG_UID" in ''|*[!0-9]*) HH_DG_UID=""; HH_DELEGATE_WHY="this user's id cannot be read"; return 1 ;; esac
  hh_jq_resolve
  [ -n "$HH_JQ" ] || { HH_DELEGATE_WHY="no root-owned jq was found (/usr/bin/jq, /usr/local/bin/jq or /opt/homebrew/bin/jq), so the hub's records cannot be read safely"; return 1; }
  hh_delegate_now >/dev/null || return 1
  HH_DG_HUB=$(cd "$HH_DR_HUB" 2>/dev/null && pwd -P) || { HH_DG_HUB=""; HH_DELEGATE_WHY="the hub folder $HH_DR_HUB cannot be entered"; return 1; }
  hh_hub_records_trusted "$HH_DG_HUB" "$HH_DG_UID" || { HH_DG_HUB=""; return 1; }
  HH_DG_UNTIL=$HH_DR_UNTIL; HH_DG_MCP=$HH_DR_MCP; HH_DG_HOSTS=$HH_DR_HOSTS; HH_DG_TOOLS=$HH_DR_TOOLS; HH_DG_PEERS=$HH_DR_PEERS
}
# hh_hub_root_here: 0 when the caller's project is a hub's root, setting HH_HUB_ROOT_HERE to it: HH_PROJECT when set, else the git root, else the cwd (never a
# parent folder: the projects of a hub live inside its folder). A hub's root is a folder holding a real (not linked) $HH_HUB_DIR/.
HH_HUB_ROOT_HERE=""
hh_hub_root_here() {
  local r
  HH_HUB_ROOT_HERE=""
  if [ -n "${HH_PROJECT:-}" ]; then r=$(cd -P "$HH_PROJECT" 2>/dev/null && pwd -P) || return 1
  else r=$(hh_project_root 2>/dev/null) || r=$(pwd -P); fi
  [ -d "$r/$HH_HUB_DIR" ] && [ ! -L "$r/$HH_HUB_DIR" ] || return 1
  HH_HUB_ROOT_HERE=$r
}
# hh_away_for_hub <hub root>: 0 when the owner is away for that hub: a valid delegate file that names it, or a delegate file that exists and is refused and
# names it or names no hub (fail closed: an unreadable file is not a licence to read custom/). No file at all, or a valid one naming another hub: 1.
hh_away_for_hub() {
  local hub
  hub=$(cd -P "$1" 2>/dev/null && pwd -P) || return 1
  HH_DR_ABSENT=""; HH_DR_HUB=""
  hh_jq_resolve; [ -n "$HH_JQ" ] || return 1   # no root-owned jq: away mode cannot have been switched on here, and the delegate file cannot be read
  if hh_delegate_mine; then [ "$HH_DG_HUB" = "$hub" ]; return; fi   # hh_delegate_mine is the one reader of the file (it sets HH_DR_ABSENT and HH_DR_HUB)
  [ "${HH_DR_ABSENT:-}" != 1 ] || return 1
  [ -z "${HH_DR_HUB:-}" ] || [ "$(cd "$HH_DR_HUB" 2>/dev/null && pwd -P)" = "$hub" ]
}
# hh_env_has <pid> <NAME=value>: 0 the process was launched with it; 1 its environment is visible and lacks it; 2 no
# environment is visible at all (the caller says so and does not pretend to have checked). Linux reads /proc/<pid>/environ,
# which is exact. macOS `ps -E` prints the arguments and the environment on one line: the process's own arguments are
# taken off the front first (so a marker spelled in an argument does not count), and the rest is matched as whole words. The
# variables are joined with spaces, so a marker spelled inside another variable's value (FOO="x HH_AWAY_BYPASS=1 y") counts:
# macOS cannot tell them apart. Linux /proc/<pid>/environ is exact.
# macOS shows no environment for Apple platform binaries (bash, sleep), so a non-platform process is needed to read one:
# Claude Code is one.
hh_env_has() {
  local pid="$1" want="$2" line args rest
  if [ -r "/proc/$pid/environ" ]; then
    while IFS= read -r -d '' line; do [ "$line" = "$want" ] && return 0; done < "/proc/$pid/environ"
    return 1
  fi
  line=$(/bin/ps -E -ww -p "$pid" -o command= 2>/dev/null); args=$(/bin/ps -ww -p "$pid" -o command= 2>/dev/null)
  [ -n "$args" ] || return 2
  case "$line" in "$args"*) rest=${line#"$args"} ;; *) return 2 ;; esac
  case " $rest " in *" PATH="*|*" HOME="*|*" USER="*|*" SHELL="*) ;; *) return 2 ;; esac
  case " $rest " in *" $want "*) return 0 ;; esac
  return 1
}

# ---- folder trust: what Claude Code asks before it works in a folder -------------------------------------------------------------
# hh_claude_trusts <dir>: 0 when Claude Code will not show its folder-trust dialog there; sets HH_TRUST_KEY to the folder whose entry in
# <config dir>/.claude.json (.projects[<folder>].hasTrustDialogAccepted) decides it. Measured on Claude Code 2.1.291: a plain folder is
# trusted when it or any folder above it is; a git repository does NOT inherit from a folder above it, and a worktree is judged by its
# MAIN repository's entry (accepting the dialog in a worktree writes that key, not the worktree's).
hh_claude_dir() { printf '%s\n' "${CLAUDE_CONFIG_DIR:-${HOME:-/}/.claude}"; }   # Claude Code's config folder: the one place it is resolved (the hook keeps its own, being a separate script)
hh_claude_json() { printf '%s\n' "${CLAUDE_CONFIG_DIR:-${HOME:-/}}/.claude.json"; }   # the user-level state file: inside the config folder when CLAUDE_CONFIG_DIR is set, else in the home folder
hh_claude_trusts() {
  local d common t cj; cj=$(hh_claude_json)
  d=$(cd "$1" 2>/dev/null && pwd -P) || d=$1
  HH_TRUST_KEY=$d
  if common=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && [ -n "$common" ]; then
    case "$common" in */.git) HH_TRUST_KEY=${common%/.git} ;; *) HH_TRUST_KEY=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || HH_TRUST_KEY=$d ;; esac
    [ "$(jq -r --arg p "$HH_TRUST_KEY" '.projects[$p].hasTrustDialogAccepted // false' "$cj" 2>/dev/null)" = true ]
    return
  fi
  t=$d
  while :; do
    [ "$(jq -r --arg p "$t" '.projects[$p].hasTrustDialogAccepted // false' "$cj" 2>/dev/null)" = true ] && return 0
    [ "$t" = / ] && return 1; t=${t%/*}; [ -n "$t" ] || t=/
  done
}

# ---- bypass: granted only while the owner is away -----------------------------------------------------------------------
# bypassPermissions is started by hivehouse only when ALL of these hold: the owner's root-owned delegate file is valid, the project's
# home is listed in the hub that file names, and the caller's own Claude carries the away marker in its launch environment
# (hh_away_caller). The owner's own unmarked sessions and a plain shell never get it. Nothing here is read from an argument or a
# setting the caller can write.
HH_DG_HUB=""; HH_DG_UNTIL=""; HH_DG_MCP=""; HH_DG_PROJECT=""
hh_delegate_for_project() {  # hh_delegate_for_project <project root>: 0 when delegate is valid and that root is a listed home or one of its team roots; sets HH_DG_*
  local hub r name home abs t
  HH_DG_PROJECT=""
  hh_delegate_mine || return 1
  hub=$HH_DG_HUB
  r=$(cd "$1" 2>/dev/null && pwd -P) || { HH_DG_HUB=""; HH_DG_UNTIL=""; HH_DG_MCP=""; return 1; }
  while IFS=$'\t' read -r name home; do
    case "$home" in /*) abs=$home ;; *) abs="$hub/$home" ;; esac
    abs=$(cd "$abs" 2>/dev/null && pwd -P) || continue
    while IFS= read -r t; do
      [ "$t" = "$r" ] || continue
      # the home and the team root must be the caller's: bypass sessions run as this user, and in another user's folder (or one the group can
      # write) they would load that folder's CLAUDE.md, .claude/settings.json hooks and .mcp.json. A worktree can sit anywhere.
      hh_path_trusted "$abs" dir "$HH_DG_UID" strict && hh_path_trusted "$t" dir "$HH_DG_UID" strict || break 2
      HH_DG_PROJECT=$name; return 0
    done < <(hh_team_roots "$abs")
  done < <("$HH_JQ" -r '.projects[]? | [.name, .home] | @tsv' "$hub/$HH_HUB_DIR/projects.json" 2>/dev/null)
  HH_DG_HUB=""; HH_DG_UNTIL=""; HH_DG_MCP=""
  return 1
}
hh_away_caller() {  # 0 the caller's Claude carries the away marker; 1 it does not (or there is no Claude: a plain shell); 2 its environment cannot be read
  local pid; pid=$(hh_claude_ancestor) || return 1
  hh_env_has "$pid" HH_AWAY_BYPASS=1
}
# A permission mode hivehouse starts a session in (hh-spawn's and hh-hub's --mode). bypassPermissions only as above, and so only with the
# project's root.
HH_PERMISSION_MODES="plan dontAsk default acceptEdits auto"
hh_check_mode() {  # hh_check_mode <mode> <who> [<project root>]: exits 4 unless hivehouse may start a session in that mode
  local mode="$1" who="$2" root="${3:-}"
  if [ "$mode" = bypassPermissions ]; then
    [ -n "$root" ] || hh_die 4 "bypassPermissions is never started by $who without a project to check it for"
    hh_delegate_for_project "$root" || hh_die 4 "bypassPermissions is started only while the owner's delegate file is valid for this project (hh-hub away prints how to make it)"
    hh_away_caller
    case $? in
      0) return 0 ;;
      2) hh_die 4 "this session's launch environment cannot be read, so the away marker cannot be checked: $who refuses bypassPermissions" ;;
      *) hh_die 4 "bypassPermissions is started only for a session carrying the away marker (HH_AWAY_BYPASS), which hh-hub away's start line sets" ;;
    esac
  fi
  case " $HH_PERMISSION_MODES " in *" $mode "*) return 0 ;; esac
  hh_die 4 "unknown permission mode: $mode"
}
# What a session started in bypass gets: the marker and the hook's three variables, and only the MCP servers the
# owner allowed (a file written from the user's .claude.json and the project's .mcp.json, mode 0600), with no Chrome. Never for any other mode.
HH_BP_ENVS=(); HH_BP_ARGS=(); HH_AWAY_MCP_MISSING=""
hh_write_away_mcp() {  # hh_write_away_mcp <file> <allow list> <project root>: the servers of the list, found; HH_AWAY_MCP_MISSING names the others. Only "$HH_JQ" writes it (with none, nothing runs and it returns 1)
  local f="$1" allow="$2" root="$3" cj e srv def
  hh_jq_resolve
  cj=$(hh_claude_json); HH_AWAY_MCP_MISSING=""
  ( umask 077; "$HH_JQ" -n '{mcpServers:{}}' > "$f.tmp$$" ) && mv "$f.tmp$$" "$f" && chmod 600 "$f" || return 1
  [ -n "$allow" ] || return 0
  for e in $(printf '%s' "$allow" | tr ',' ' '); do
    srv=$e; case "$e" in mcp__*__*) srv=${e#mcp__}; srv=${srv%%__*} ;; esac
    def=$("$HH_JQ" -c --arg s "$srv" --arg r "$root" '(.mcpServers[$s] // .projects[$r].mcpServers[$s]) // empty' "$cj" 2>/dev/null | head -1)
    [ -n "$def" ] || def=$("$HH_JQ" -c --arg s "$srv" '.mcpServers[$s] // empty' "$root/.mcp.json" 2>/dev/null | head -1)
    if [ -n "$def" ]; then
      ( umask 077; "$HH_JQ" --arg s "$srv" --argjson d "$def" '.mcpServers[$s] = $d' "$f" > "$f.tmp$$" ) && mv "$f.tmp$$" "$f" && chmod 600 "$f" || return 1
    else HH_AWAY_MCP_MISSING="$HH_AWAY_MCP_MISSING $srv"; fi
  done
}
hh_bypass_launch() {  # hh_bypass_launch <project root> <mcp file>: HH_BP_ENVS (tmux -e) and HH_BP_ARGS (claude flags) for a bypass launch; call only after hh_check_mode
  hh_delegate_for_project "$1" || return 1
  hh_write_away_mcp "$2" "$HH_DG_MCP" "$1" || return 1
  HH_BP_ENVS=(-e "HH_AWAY_BYPASS=1" -e "HH_AWAY_HUB=$HH_DG_HUB" -e "HH_AWAY_MCP_ALLOW=$HH_DG_MCP")
  HH_BP_ARGS=(--strict-mcp-config --mcp-config "$2" --no-chrome)
}
hh_is_number() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }   # hh_is_number <value>: digits only
# A model or an effort as hivehouse passes one to claude: letters, digits, '.', '_', '[', ']' and '-', not starting with '-'.
hh_is_model_name() {  # hh_is_model_name <value>: 0 when it is one
  case "$1" in ''|-*|*[!${HH_LOWER}${HH_UPPER}${HH_DIGITS}._\[\]-]*) return 1 ;; esac
  return 0
}
# hh_open_window <tmux session> <window name> <cwd> <command> [-e VAR=value]...: a window in that session, which is made when
# it does not exist; prints the new pane. The one place hh-spawn and hh-hub open a pane.
hh_open_window() {
  local s="$1" n="$2" c="$3" cmd="$4" pane a prev="" v; shift 4
  # A tmux server started by a marked caller copies that caller's whole environment into its GLOBAL environment, and every later pane
  # of any mode would inherit it: the server is started without the three away variables, a server already holding them is cleaned,
  # and a bypass agent gets its own through -e.
  for v in $HH_AWAY_VARS; do hh_tmux set-environment -g -u "$v" 2>/dev/null; done
  if hh_tmux has-session -t "=$s" 2>/dev/null; then
    hh_tmux new-window -d -P -F '#{pane_id}' -t "=$s:" -n "$n" -c "$c" "$@" "$cmd"
  else
    pane=$(hh_tmux_unmarked new-session -d -P -F '#{pane_id}' -s "$s" -n "$n" -c "$c" "$@" "$cmd") || return $?
    # -e on new-session sets the SESSION's environment, which every later window of it would inherit: the away marker of a bypass agent,
    # say, reaching an agent that is not in bypass. These variables belong to this one process, which already has them.
    for a in "$@"; do [ "$prev" = -e ] && hh_tmux set-environment -t "=$s" -u "${a%%=*}" 2>/dev/null; prev=$a; done
    printf '%s\n' "$pane"
  fi
}
hh_pane_question() {  # hh_pane_question <socket, or empty for hivehouse's own server> <pane>: 0 when a dialog waits on its screen
  local t
  [ -n "$2" ] || return 1
  t=$(hh_tmux_on "$1" capture-pane -p -e -J -t "$2" 2>/dev/null) || return 1
  printf '%s\n' "$t" | hh_pane_idle_text; [ $? -eq 3 ]
}
# ---- the delete guard's one predicate: bin/guard/{rm,find,rsync} and the rm hook both ask these two ---------------------------------------
# hh_rm_canon names a path one way: absolute, ~ and $HOME expanded, dot segments collapsed, every link resolved except the last, which is
# resolved only when the operand ends in / (what rm and the shell do). An empty path stays empty. HH_GUARD_ROOT (a test seam) makes
# hh_rm_protected judge paths as if that folder were /; nothing else reads it.
hh_rm_canon() {  # hh_rm_canon <path> <cwd>
  local p="$1" cur=/ queue seg next tgt trail="" n=0 last
  [ -n "$p" ] || { printf '\n'; return 0; }
  case "$p" in "~") p=$HOME ;; "~/"*) p="$HOME/${p#\~/}" ;; esac
  p=${p//\$\{HOME\}/$HOME}; p=${p//\$HOME/$HOME}
  case "$p" in /*) ;; *) p="${2:-/}/$p" ;; esac
  case "$p" in */) trail=1 ;; esac
  queue=${p#/}
  while [ -n "$queue" ]; do
    seg=${queue%%/*}
    case "$queue" in */*) queue=${queue#*/} ;; *) queue="" ;; esac
    case "$seg" in ''|.) continue ;; ..) cur=${cur%/*}; cur=${cur:-/}; continue ;; esac
    next="${cur%/}/$seg"
    last=0; case "$queue" in *[!/]*) ;; *) last=1 ;; esac
    if [ -L "$next" ] && { [ "$last" = 0 ] || [ -n "$trail" ]; } && [ "$n" -lt 40 ]; then
      n=$((n + 1)); tgt=$(readlink "$next")
      case "$tgt" in /*) cur=/ ;; esac
      queue="$tgt${queue:+/$queue}"; queue=${queue#/}
      continue
    fi
    cur=$next
  done
  printf '%s\n' "$cur"
}
hh_rm_map() {  # hh_rm_map <canonical path>: the name it has when HH_GUARD_ROOT is taken as /
  local r p="$1"; [ -n "${HH_GUARD_ROOT:-}" ] || { printf '%s\n' "$p"; return 0; }
  r=$(hh_rm_canon "$HH_GUARD_ROOT" /)
  case "$p" in "$r") printf '/\n' ;; "$r"/*) printf '%s\n' "${p#"$r"}" ;; *) printf '%s\n' "$p" ;; esac
}
hh_rm_protected() {  # hh_rm_protected <canonical path>: 0 and the reason on stdout when a delete may not touch it; 1 when it may
  local p="$1" q z c h r s pr tz
  [ -n "$p" ] || { echo "an empty operand"; return 0; }
  q=$(hh_rm_map "$p")
  [ "$q" != / ] || { echo "the root folder"; return 0; }
  # the temp zones: a temp root is refused, anything inside one passes (tests make and delete temp repositories there)
  tz=""; [ -z "${TMPDIR:-}" ] || tz=$(hh_rm_map "$(hh_rm_canon "$TMPDIR" /)")
  for z in "$tz" /private/tmp /tmp /var/tmp /private/var/tmp; do
    [ -n "$z" ] || continue
    for c in "$z" "$(hh_rm_canon "$z" /)"; do
      [ "$q" != "$c" ] || { echo "a temporary folder itself ($c)"; return 0; }
    done
  done
  for z in "$tz" /private/tmp /tmp /var/tmp /private/var/tmp; do
    [ -n "$z" ] || continue
    for c in "$z" "$(hh_rm_canon "$z" /)"; do
      case "$q" in "$c"/*) return 1 ;; esac
    done
  done
  s=${q//[!\/]/}
  [ "${#s}" -ge 3 ] || { echo "a folder fewer than 3 levels deep ($q)"; return 0; }
  h=$(hh_rm_map "$(hh_rm_canon "$HOME" /)")
  case "$h/" in "$q"/*) echo "the home folder, or a folder that holds it ($q)"; return 0 ;; esac
  for r in "$h/.claude" "$(hh_rm_map "$(hh_rm_canon "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" /)")"; do
    [ "$q" != "$r" ] || { echo "Claude Code's own folder ($q)"; return 0; }
  done
  pr=$(hh_rm_map "$(hh_rm_canon "$(dirname "${BASH_SOURCE[0]}")/.." /)")
  case "$pr/" in "$q"/*) echo "the plugin root, or a folder that holds it ($q)"; return 0 ;; esac
  [ ! -L "$p" ] || return 1   # a link is judged as itself, not as what it points at
  if [ -d "$p/.git" ]; then echo "a git repository root ($q)"; return 0; fi
  if [ -d "$p/$HH_HUB_DIR" ]; then echo "a hub folder ($q)"; return 0; fi
  if [ -d "$p/$HH_STATE_DIR" ]; then echo "a project home ($q)"; return 0; fi
  return 1
}
