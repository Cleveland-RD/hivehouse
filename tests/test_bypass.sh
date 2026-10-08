#!/usr/bin/env bash
# Bypass permissions, granted only while the owner is away: hh-settings resolve, hh-spawn and
# hh-hub give bypassPermissions only when the owner's delegate file is valid, the project's home is listed in the hub it names, and the
# caller's own Claude carries the away marker in its launch environment (read by ps -E, so the stand-in is a node script named claude).
# A session started in bypass gets the marker, the hook's variables and only the MCP servers the owner allowed; any other mode gets none.
# The delegate file is a fixture (t_delegate_bin); the real one, owned by root, is a live check.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
ME=$(id -u); NOW=$(date +%s)
NODEBIN=$(command -v node || true); READABLE=0
ep=$(t_env_probe HH_PROBE=1) || ep=""
if [ -n "$ep" ]; then t_track "$ep"; sleep 0.5; hh_env_has "$ep" HH_PROBE=1 && READABLE=1; kill "$ep" 2>/dev/null; fi
if [ "$READABLE" != 1 ]; then echo "  SKIP only Apple platform binaries were found (no node): a Claude's launch environment cannot be read here, and bypass is refused without that"; t_done; exit 0; fi
env -u HIVEHOUSE_HOME tmux -S "$HH_TMUX_SOCKET" new-session -d -x 200 -y 56 -s keep 'sleep 600'
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P); P="$H/$T_HUB"
mk() { local d="$H/$1"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" config user.email t@t; git -C "$d" config user.name t
       echo x > "$d/README"; git -C "$d" add README; git -C "$d" commit -qm init; }
DD="$T_TMP/dg/area"; DF="$DD/delegate"
mkdel() {  # mkdel [until] [mcp list]: the owner's delegate file naming this hub, as root would have made it
  mkdir -p "$DD"; chmod 755 "$DD" "$T_TMP/dg"
  printf "$T_DELEGATE_LINE1"'\nhub=%s\nuntil=%s\nmcp=%s\n' "$H" "${1:-$((NOW + 3600))}" "${2-docs}" > "$DF"; chmod 644 "$DF"
}
mkdel
if ! hh_delegate_read "$DF" "$ME" "$NOW" >/dev/null 2>&1; then hh_delegate_read "$DF" "$ME" "$NOW" >/dev/null 2>&1; echo "  SKIP the fixture folder is not eligible here: $HH_DELEGATE_WHY"; t_done; exit 0; fi
DB=$(t_delegate_bin "$DF")
mk app; mk other; (cd "$H" && hh-hub init >/dev/null && hh-hub add app --home app >/dev/null)   # "other" is no project of the hub
printf '{"name":"hub"}\n' > "$P/hub.json"   # a hub that recorded itself (hh-hub self): the delegate check requires hub.json to be this user's
printf '{"mcpServers":{"docs":{"command":"docs-mcp"},"extra":{"command":"extra-mcp"}}}\n' > "$CLAUDE_CONFIG_DIR/.claude.json"
NCP=$(t_node_claude "$H/app"); NCO=$(t_node_claude "$H/other"); NCH=$(t_node_claude "$H" "$DB/hh-hub")
echo role > "$T_TMP/role.md"; echo rules > "$T_TMP/RULES.md"
M=(env HH_AWAY_BYPASS=1)   # a marked caller; an unmarked one is the same without it

# ---- hh-settings resolve: bypass only for a marked caller, while the owner is away, for a listed project ----
st() { local who=$1 proj=$2 owner=$3; shift 3; "$@" HH_PROJECT="$H/$proj" node "$who" "$DB/hh-settings" resolve permission_mode "$owner" 2>"$T_TMP/st.err"; }
assert_eq "a marked caller, the owner away, the project listed, the owner's mode auto: bypassPermissions" "$(st "$NCP" app auto "${M[@]}")" "bypassPermissions"
assert_eq "...an unmarked Claude gets the owner's mode" "$(st "$NCP" app auto env)" "auto"
assert_eq "...a plain shell too" "$(HH_PROJECT="$H/app" "$DB/hh-settings" resolve permission_mode auto 2>/dev/null)" "auto"
assert_eq "...a marked caller whose launch environment shows no variables at all (cannot be read)" "$(env -i HH_AWAY_BYPASS=1 HH_PROJECT="$H/app" "$NODEBIN" "$NCP" "$DB/hh-settings" resolve permission_mode auto 2>"$T_TMP/st.err")" "auto"
assert_contains "......says so" "$(cat "$T_TMP/st.err")" "cannot be read"
assert_eq "...an owner mode that is not auto is never raised" "$(st "$NCP" app acceptEdits "${M[@]}")" "acceptEdits"
assert_eq "...a project that is not one of the hub's" "$(st "$NCO" other auto "${M[@]}")" "auto"
mkdir -p "$H/app/$T_STATE"; echo '{"permission_mode":"default"}' > "$H/app/$T_STATE/settings.json"
assert_eq "...a project's own stricter mode keeps its team out of bypass" "$(st "$NCP" app auto "${M[@]}")" "default"
echo '{"permission_mode":"auto"}' > "$H/app/$T_STATE/settings.json"
assert_eq "...a project value equal to the owner's does not" "$(st "$NCP" app auto "${M[@]}")" "bypassPermissions"
echo '{"permission_mode":"bypassPermissions"}' > "$H/app/$T_STATE/settings.json"
assert_eq "...a project that names bypass itself gets the owner's rule, not its own word" "$(st "$NCP" app auto env)" "auto"
rm -f "$H/app/$T_STATE/settings.json"
# a team in a worktree of the project's home: bypass on the same terms, and the settings are the home's, never the worktree's own
git -C "$H/app" worktree add -q "$H/app-wt" -b wt-team; mkdir -p "$H/app-wt/$T_STATE"; echo '{"agents":[]}' > "$H/app-wt/$T_STATE/team.json"
assert_eq "a worktree team root of the project: bypassPermissions" "$(st "$NCP" app-wt auto "${M[@]}")" "bypassPermissions"
echo '{"permission_mode":"default"}' > "$H/app-wt/$T_STATE/settings.json"
assert_eq "...the worktree's own stricter file changes nothing" "$(st "$NCP" app-wt auto "${M[@]}")" "bypassPermissions"
rm -f "$H/app-wt/$T_STATE/settings.json"
echo '{"permission_mode":"default"}' > "$H/app/$T_STATE/settings.json"
assert_eq "...the home's stricter mode holds for the worktree" "$(st "$NCP" app-wt auto "${M[@]}")" "default"
rm -f "$H/app/$T_STATE/settings.json"
chmod 775 "$H/app-wt"; assert_eq "...a group-writable worktree root gets no bypass" "$(st "$NCP" app-wt auto "${M[@]}")" "auto"; chmod 755 "$H/app-wt"
git -C "$H/other" worktree add -q "$H/other-wt" -b wt-other; mkdir -p "$H/other-wt/$T_STATE"; echo '{"agents":[]}' > "$H/other-wt/$T_STATE/team.json"
assert_eq "...a worktree of an unlisted repository gets none" "$(st "$NCO" other-wt auto "${M[@]}")" "auto"
mkdel "$((NOW - 10))"; assert_eq "...an expired delegate file: no bypass" "$(st "$NCP" app auto "${M[@]}")" "auto"
mkdel; chmod 666 "$DF"; assert_eq "...a delegate file anyone could write: no bypass" "$(st "$NCP" app auto "${M[@]}")" "auto"; mkdel
"$DB/hh-settings" resolve permission_mode bypassPermissions >/dev/null 2>&1; assert_status "an owner value of bypassPermissions is refused" $? 4

# ---- hh-spawn: an agent in bypass gets the marker, the hook's variables and the allowed MCP servers; nothing else does ----
sp() {  # sp <caller> <agent> <mode> [more hh-spawn args]: the pane it prints
  local who=$1 a=$2 m=$3; shift 3
  HH_PROJECT="$H/${PROJ:-app}" "${M[@]}" node "$who" "$DB/hh-spawn" --agent "$a" --role "$T_TMP/role.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode "$m" --still 2 --max-wait 15 "$@" 2>"$T_TMP/sp.err"
}
screen() { hh_tmux capture-pane -p -J -S - -t "$1"; }
sp0() { local who=$1 a=$2 m=$3; shift 3; HH_PROJECT="$H/app" env node "$who" "$DB/hh-spawn" --agent "$a" --role "$T_TMP/role.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode "$m" --still 2 --max-wait 15 "$@" 2>"$T_TMP/sp.err"; }
p=$(sp "$NCP" b1 bypassPermissions); assert_status "hh-spawn in bypass, for a marked caller, while away" $? 0
sc=$(screen "$p")
assert_contains "...the agent runs in bypass" "$sc" "ARGV: bypassPermissions"
assert_contains "...with only the MCP file the owner's list allows" "$sc" "ARGV: --strict-mcp-config"
assert_contains "......its file" "$sc" "ARGV: $H/app/$T_STATE/team/b1/away-mcp.json"
assert_contains "...and no Chrome" "$sc" "ARGV: --no-chrome"
assert_contains "...the marker and the hook's variables, in its launch environment" "$sc" "ENV2: HH_AWAY_BYPASS=1 HH_AWAY_HUB=$H HH_AWAY_MCP_ALLOW=docs"
assert_contains "...its project" "$sc" "HH_PROJECT=$H/app"
assert_eq "...the MCP file holds the allowed server and not the other" "$(jq -c '.mcpServers | keys' "$H/app/$T_STATE/team/b1/away-mcp.json")" '["docs"]'
assert_eq "...at mode 0600" "$(stat -f '%Lp' "$H/app/$T_STATE/team/b1/away-mcp.json" 2>/dev/null || stat -c '%a' "$H/app/$T_STATE/team/b1/away-mcp.json")" "600"
sp "$NCP" b2 bypassPermissions >/dev/null 2>&1; true
sp0 "$NCP" b3 bypassPermissions >/dev/null; assert_status "...an unmarked Claude is refused" $? 4
assert_contains "......says why" "$(cat "$T_TMP/sp.err")" "away marker"
env -i HH_AWAY_BYPASS=1 HH_PROJECT="$H/app" "$NODEBIN" "$NCP" "$DB/hh-spawn" --agent b7 --role "$T_TMP/role.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode bypassPermissions --still 2 --max-wait 10 >/dev/null 2>"$T_TMP/sp.err"; assert_status "...a marked Claude whose environment cannot be read is refused" $? 4
assert_contains "......says so" "$(cat "$T_TMP/sp.err")" "cannot be read"
PROJ=other sp "$NCO" b4 bypassPermissions >/dev/null; assert_status "...a project that is not the hub's is refused" $? 4
mkdel "$((NOW - 10))"; sp "$NCP" b5 bypassPermissions >/dev/null; assert_status "...an expired delegate file is refused" $? 4
assert_contains "......says why" "$(cat "$T_TMP/sp.err")" "delegate file"; mkdel
(cd "$H/app" && HH_AWAY_BYPASS=1 "$DB/hh-spawn" --agent b6 --role "$T_TMP/role.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode bypassPermissions --still 2 --max-wait 10 >/dev/null 2>&1); assert_status "...a plain shell naming the marker itself is refused (only a Claude's launch environment counts)" $? 4
assert_eq "the marker of a bypass agent is not left in its tmux session's environment" "$(hh_tmux show-environment -t "hh-$(hh_project_key "$H/app")" HH_AWAY_BYPASS 2>&1 | grep -c '^HH_AWAY_BYPASS=1')" "0"
# a marked caller that starts the tmux server: tmux copies its whole environment into the server's GLOBAL one, and every later pane would carry the marker
FS="$T_TMP/fresh.sock"
fp=$(HH_TMUX_SOCKET="$FS" sp "$NCP" f1 auto); assert_status "a marked caller starting the tmux server with an agent that is not in bypass" $? 0
assert_contains "...that agent has no marker" "$(HH_TMUX_SOCKET="$FS" screen "$fp")" "ENV2: HH_AWAY_BYPASS= HH_AWAY_HUB= HH_AWAY_MCP_ALLOW="
assert_eq "...the server's global environment holds none of the three" "$(tmux -S "$FS" show-environment -g 2>/dev/null | grep -c '^HH_AWAY_')" "0"
fp=$(HH_TMUX_SOCKET="$FS" sp "$NCP" f2 auto); assert_contains "...a later window of that server has no marker" "$(HH_TMUX_SOCKET="$FS" screen "$fp")" "ENV2: HH_AWAY_BYPASS= HH_AWAY_HUB= HH_AWAY_MCP_ALLOW="
fp=$(HH_TMUX_SOCKET="$FS" PROJ=other sp "$NCO" f3 auto); assert_contains "...nor a new session of it, for another project" "$(HH_TMUX_SOCKET="$FS" screen "$fp")" "ENV2: HH_AWAY_BYPASS= HH_AWAY_HUB= HH_AWAY_MCP_ALLOW="
fp=$(HH_TMUX_SOCKET="$FS" sp "$NCP" f4 bypassPermissions); assert_contains "...and a bypass agent on it still gets its own" "$(HH_TMUX_SOCKET="$FS" screen "$fp")" "ENV2: HH_AWAY_BYPASS=1 HH_AWAY_HUB=$H HH_AWAY_MCP_ALLOW=docs"
tmux -S "$FS" kill-server 2>/dev/null
p=$(sp "$NCP" a1 auto); sc=$(screen "$p")
assert_contains "any other mode: the agent runs in it" "$sc" "ARGV: auto"
assert_contains "...with no marker and no hook variables" "$sc" "ENV2: HH_AWAY_BYPASS= HH_AWAY_HUB= HH_AWAY_MCP_ALLOW="
# a server that ALREADY holds the variables in its global environment (started before the fix, or from a marked shell): a window opened on it is cleaned
hh_tmux set-environment -g HH_AWAY_BYPASS 1; hh_tmux set-environment -g HH_AWAY_HUB "$H"; hh_tmux set-environment -g HH_AWAY_MCP_ALLOW docs
p=$(sp0 "$NCP" g1 auto); assert_contains "a server that already holds the away variables: an agent opened on it still has none" "$(screen "$p")" "ENV2: HH_AWAY_BYPASS= HH_AWAY_HUB= HH_AWAY_MCP_ALLOW="
assert_eq "...and the server's global environment is cleaned" "$(hh_tmux show-environment -g 2>/dev/null | grep -c '^HH_AWAY_')" "0"
case "$sc" in *--strict-mcp-config*|*--no-chrome*) bad "a session not in bypass got the away MCP flags" ;; *) ok "...and no away MCP flags" ;; esac
[ ! -e "$H/app/$T_STATE/team/a1/away-mcp.json" ] && ok "...and no MCP file" || bad "a session not in bypass has an MCP file"
# a respawn: out of bypass when the owner is back, the same bypass while away
hh_tmux kill-pane -t "$(jq -r '.agents[] | select(.name=="b1") | .pane' "$H/app/$T_STATE/team.json")"; sleep 0.5
mkdel "$((NOW - 10))"
HH_PROJECT="$H/app" "${M[@]}" node "$NCP" "$DB/hh-spawn" --respawn b1 --still 2 --max-wait 15 >/dev/null 2>"$T_TMP/sp.err"; assert_status "respawning a bypass agent after away has ended is refused" $? 4
rp=$(HH_PROJECT="$H/app" "${M[@]}" node "$NCP" "$DB/hh-spawn" --respawn b1 --mode auto --still 2 --max-wait 15 2>/dev/null); assert_status "...unless it comes back in a stricter mode" $? 0
[ ! -e "$H/app/$T_STATE/team/b1/away-mcp.json" ] && ok "......and the away MCP file of its bypass days is gone" || bad "a stale away MCP file stays for an agent no longer in bypass"
sc=$(screen "$rp"); assert_contains "......in that mode" "$sc" "ARGV: auto"
assert_contains "......with no marker" "$sc" "ENV2: HH_AWAY_BYPASS= HH_AWAY_HUB= HH_AWAY_MCP_ALLOW="
mkdel
p=$(sp "$NCP" c1 bypassPermissions); hh_tmux kill-pane -t "$p"; sleep 0.5
rp=$(HH_PROJECT="$H/app" "${M[@]}" node "$NCP" "$DB/hh-spawn" --respawn c1 --still 2 --max-wait 15 2>/dev/null); assert_status "respawning a bypass agent while the owner is away" $? 0
assert_contains "...carries the marker again" "$(screen "$rp")" "ENV2: HH_AWAY_BYPASS=1 HH_AWAY_HUB=$H HH_AWAY_MCP_ALLOW=docs"
# a hub-launched orchestrator's MCP file moves under the team when it registers
mkdir -p "$P/panes"; printf '{"mcpServers":{"docs":{}}}\n' > "$P/panes/app-mcp.json"; chmod 600 "$P/panes/app-mcp.json"
kp=$(hh_tmux list-panes -t keep -F '#{pane_id}' | head -1)
TMUX_PANE="$kp" HH_PROJECT="$H/app" "${M[@]}" node "$NCP" "$DB/hh-spawn" --self --agent orchestrator >/dev/null 2>"$T_TMP/sp.err"; assert_status "an orchestrator registering with --self" $? 0
[ -f "$H/app/$T_STATE/team/orchestrator/away-mcp.json" ] && [ ! -e "$P/panes/app-mcp.json" ] && ok "...takes the MCP file the hub gave it into its team folder" || bad "the hub-launched orchestrator's MCP file did not move"
# the delegate file expired before it registered: the hub's copy (it may hold server secrets) is removed, not left behind
printf '{"mcpServers":{"docs":{}}}\n' > "$P/panes/app-mcp.json"; chmod 600 "$P/panes/app-mcp.json"; mkdel "$((NOW - 10))"
TMUX_PANE="$kp" HH_PROJECT="$H/app" HH_AWAY_HUB="$H" "${M[@]}" node "$NCP" "$DB/hh-spawn" --self --agent orchestrator >/dev/null 2>"$T_TMP/sp.err"; assert_status "registering with --self after the delegate file expired" $? 0
[ ! -e "$P/panes/app-mcp.json" ] && ok "...removes the hub's MCP file" || bad "an expired start left the hub's MCP file"
mkdel

# ---- hh-hub: only the hub the owner's file names, in its own marked Claude, and never through --mode ----
rm -f "$H/app/$T_STATE/team.json"; rm -rf "$H/app/$T_STATE/team"
hh() { local who=$1; shift; (cd "$H" && "${M[@]}" HH_PROJECT="$H" node "$who" "$DB/hh-hub" "$@" 2>"$T_TMP/hh.err"); }
# a delegate file that names ANOTHER hub, which also lists this project: the hub that runs this hh-hub is not the one the owner meant
H2="$T_TMP/work2"; mkdir -p "$H2/$T_HUB"; H2=$(cd "$H2" && pwd -P)
jq -nc --arg h "$H/app" '{projects:[{name:"app", home:$h, repos:[$h]}]}' > "$H2/$T_HUB/projects.json"
printf '{"name":"hub2"}\n' > "$H2/$T_HUB/hub.json"   # a complete hub of this user's: only the name it is given differs
hh0() { (cd "$H" && env node "$NCH" "$DB/hh-hub" "$@" 2>"$T_TMP/hh.err"); }
t1=$(hh "$NCH" task app --text "First"); t1=${t1%%$'\t'*}
hh "$NCH" start app "$t1" --mode bypassPermissions --still 2 --max-wait 15 >/dev/null; assert_status "hh-hub start --mode bypassPermissions is refused, whoever asks" $? 4
assert_contains "...by its own rule, not by the check that follows it" "$(cat "$T_TMP/hh.err")" "never given with --mode"
hh "$NCH" start nope "$t1" --mode bypassPermissions >/dev/null; assert_status "...before the project is even looked up" $? 4
up=$(hh0 start app "$t1" --mode auto --still 2 --max-wait 15); assert_status "a hub that was not started with the marker starts in the owner's mode, as today" $? 0
sc=$(screen "$up"); assert_contains "...auto" "$sc" "ARGV: auto"
assert_contains "...with no marker" "$sc" "ENV2: HH_AWAY_BYPASS= HH_AWAY_HUB= HH_AWAY_MCP_ALLOW="
hh_tmux kill-pane -t "$up"; sleep 0.5
printf "$T_DELEGATE_LINE1"'\nhub=%s\nuntil=%s\nmcp=docs\n' "$H2" "$((NOW + 3600))" > "$DF"
hh "$NCH" start app "$t1" --mode auto --still 2 --max-wait 15 >/dev/null; assert_status "a delegate file that names another hub gives this hub no bypass" $? 4
assert_contains "...says so" "$(cat "$T_TMP/hh.err")" "does not name this hub"
mkdel
hh "$NCP" start app "$t1" --mode auto --still 2 --max-wait 15 >/dev/null; assert_status "a marked Claude that is not the hub's, running hh-hub start while the owner is away" $? 4
assert_contains "...is refused as another session" "$(cat "$T_TMP/hh.err")" "another session"
assert_eq "...and no orchestrator was launched" "$(hh_tmux list-windows -a -F '#{window_name}' 2>/dev/null | grep -c '^orchestrator$')" "0"
hp=$(hh "$NCH" start app "$t1" --mode auto --still 2 --max-wait 15); assert_status "a marked hub starts an orchestrator while the owner is away" $? 0
sc=$(screen "$hp")
assert_contains "...in bypass" "$sc" "ARGV: bypassPermissions"
assert_contains "...with the marker and the hook's variables" "$sc" "ENV2: HH_AWAY_BYPASS=1 HH_AWAY_HUB=$H HH_AWAY_MCP_ALLOW=docs"
assert_contains "...its project, as every hub launch carries" "$sc" "HH_PROJECT=$H/app"
assert_contains "...with only the allowed MCP servers, in a file beside its pane record" "$sc" "ARGV: $P/panes/app-mcp.json"
assert_eq "......at mode 0600" "$(stat -f '%Lp' "$P/panes/app-mcp.json" 2>/dev/null || stat -c '%a' "$P/panes/app-mcp.json")" "600"
assert_contains "...and no Chrome" "$sc" "ARGV: --no-chrome"
# a second start while that pane lives is refused, and writes no MCP file (it may hold server secrets)
rm -f "$P/panes/app-mcp.json"
hh "$NCH" start app "$t1" --mode auto --still 2 --max-wait 15 >/dev/null; assert_status "a start refused because the first pane still lives" $? 4
[ ! -e "$P/panes/app-mcp.json" ] && ok "...leaves no MCP file behind" || bad "a refused start left an MCP file"
hh_tmux kill-pane -t "$hp"; sleep 0.5
mkdel "$((NOW - 10))"
printf '{"mcpServers":{"docs":{}}}\n' > "$P/panes/app-mcp.json"; chmod 600 "$P/panes/app-mcp.json"
hp=$(hh "$NCH" start app "$t1" --mode auto --still 2 --max-wait 15); assert_status "the owner back (the file expired): the same start runs in the owner's mode" $? 0
[ ! -e "$P/panes/app-mcp.json" ] && ok "...and the MCP file of the earlier bypass start is removed" || bad "a start not in bypass left an earlier MCP file"
sc=$(screen "$hp")
assert_contains "...auto" "$sc" "ARGV: auto"
assert_contains "...with no marker" "$sc" "ENV2: HH_AWAY_BYPASS= HH_AWAY_HUB= HH_AWAY_MCP_ALLOW="
assert_contains "...and still its project" "$sc" "HH_PROJECT=$H/app"
hh_tmux kill-pane -t "$hp"; sleep 0.5; mkdel
# a stopped orchestrator woken while the owner is away: resumed in its own conversation, in bypass, marked
S="$H/app/$T_STATE"; mkdir -p "$S/team/orchestrator"
kp=$(hh_tmux list-panes -t keep -F '#{pane_id}' | head -1); ki=$(hh_pane_identity "$HH_TMUX_SOCKET" "$kp")
jq -nc --arg k "$HH_TMUX_SOCKET" --arg kp "$kp" --arg p "${ki%%$'\t'*}" --arg s "${ki#*$'\t'}" '{agents:[{name:"orchestrator", pane:$kp, socket:$k, pane_pid:$p, pane_started:$s, claude_pid:"99999", claude_started:"Mon Jan  1 00:00:00 2001", name_full:"app-orchestrator"}]}' > "$S/team.json"
jq -nc --arg t "$HH_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"sess-x", transcript_path:$t}' > "$S/team/orchestrator/session.json"
# a live Claude that already holds the orchestrator's recorded conversation: nothing is started, whatever the state reads
( exec -a claude sleep 120 ) >/dev/null 2>&1 & holder=$!; disown "$holder"; t_track "$holder"; sleep 0.3
mkdir -p "$CLAUDE_CONFIG_DIR/sessions"; jq -nc --argjson p "$holder" --arg c "$T_TMP" '{pid:$p, name:"someone-else", cwd:$c, sessionId:"sess-x", kind:"interactive"}' > "$CLAUDE_CONFIG_DIR/sessions/$holder.json"
hh "$NCH" wake app --mode auto --still 2 --max-wait 15 >/dev/null; assert_status "a wake while a live Claude already holds the orchestrator's conversation" $? 4
assert_contains "...says it is running, and whose pid" "$(cat "$T_TMP/hh.err")" "conversation is already open in a live session (pid $holder): it is running; nothing was started."
assert_eq "...nothing was started" "$(hh_tmux list-windows -a -F '#{window_name}' 2>/dev/null | grep -c '^orchestrator$')" "0"
kill "$holder" 2>/dev/null; rm -f "$CLAUDE_CONFIG_DIR/sessions/$holder.json"; sleep 0.3
hh "$NCP" wake app --mode auto --still 2 --max-wait 15 >/dev/null; assert_status "a marked Claude that is not the hub's, running hh-hub wake while the owner is away" $? 4
assert_contains "...is refused as another session" "$(cat "$T_TMP/hh.err")" "another session"
wp=$(hh "$NCH" wake app --mode auto --still 2 --max-wait 15); assert_status "a wake while the owner is away" $? 0
sc=$(screen "$wp")
assert_contains "...resumes its own conversation" "$sc" "ARGV: --resume"
assert_contains "...in bypass" "$sc" "ARGV: bypassPermissions"
assert_contains "...with the marker" "$sc" "ENV2: HH_AWAY_BYPASS=1 HH_AWAY_HUB=$H HH_AWAY_MCP_ALLOW=docs"
# while the owner is away the hub never answers a screen dialog
hh "$NCH" answer app --choice 1 --seen aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >/dev/null; assert_status "hh-hub answer while the owner is away" $? 4
assert_contains "...is refused, the dialog being the owner's" "$(cat "$T_TMP/hh.err")" "owner is away"
mkdel "$((NOW - 10))"; hh "$NCH" answer app --choice 1 --seen aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >/dev/null
case "$(cat "$T_TMP/hh.err")" in *"owner is away"*) bad "answer is refused with the owner home" ;; *) ok "...and not refused for that reason once the owner is back" ;; esac
t_done
