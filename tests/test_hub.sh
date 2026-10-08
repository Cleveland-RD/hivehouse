#!/usr/bin/env bash
# The owner's hub: one session in the work folder that knows every project (a project can span several folders), routes
# the owner's tasks to each project's orchestrator, wakes an orchestrator a restart stopped and starts one where none is,
# and keeps a ledger of what was asked. It never touches a project's code.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
env -u HIVEHOUSE_HOME tmux -S "$HH_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P)
mk() { local d="$H/$1"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" config user.email t@t; git -C "$d" config user.name t
       echo x > "$d/README"; git -C "$d" add README; git -C "$d" commit -qm init; }
hub() { (cd "$H" && hh-hub "$@"); }
idof() { printf '%s' "${1%%$'\t'*}"; }   # hh-hub task prints "<id><TAB><task file>"
P="$H/$T_HUB"

# ---- no hub yet ----
hub status >/dev/null 2>&1; assert_status "status with no hub" $? 2
(cd "$(t_repo inrepo)" && hh-hub init >/dev/null 2>&1); assert_status "a hub is never made inside a repository" $? 4
hub init >/dev/null; assert_status "init" $? 0
[ -d "$P/memory" ] && [ -d "$P/tasks" ] && [ "$(jq -c . "$P/projects.json")" = '{"projects":[]}' ] && ok "init lays the hub out" || bad "hub layout"
hub init >/dev/null; assert_status "init again changes nothing" $? 0
mkdir -p "$H/back/deep"; mk back; mk front; mk solo; mkdir -p "$H/notes"
git -C "$H/back" worktree add -q "$H/back-wt" -b feat
(cd "$H/back/deep" && hh-hub status >/dev/null); assert_status "found from a folder below it" $? 0

# ---- discover: facts only ----
d=$(hub discover)
assert_eq "a repository" "$(printf '%s\n' "$d" | awk '$1=="back"{print $2}')" "repo"
assert_eq "a worktree names its repository" "$(printf '%s\n' "$d" | awk '$1=="back-wt"{print $2, $3, $4}')" "worktree of back"
assert_eq "a plain folder" "$(printf '%s\n' "$d" | awk '$1=="notes"{print $2}')" "folder"
case "$d" in *"$T_HUB"*) bad "discover lists the hub itself" ;; *) ok "the hub is not listed" ;; esac

# ---- add: a project is a home repository and the folders it spans ----
hub add app --home back --repo front --repo notes >/dev/null; assert_status "add a project over three folders" $? 0
assert_eq "...stored relative to the hub" "$(jq -c '.projects[0] | [.name,.home,.repos]' "$P/projects.json")" '["app","back",["back","front","notes"]]'
hub add app --home solo >/dev/null 2>&1; assert_status "a name is taken once" $? 4
hub add two --home front >/dev/null 2>&1; assert_status "a folder belongs to one project" $? 4
hub add two --home solo --repo notes >/dev/null 2>&1; assert_status "...as a further folder too" $? 4
hub add two --home back-wt >/dev/null 2>&1; assert_status "a worktree is never a home" $? 4
hub add two --home notes >/dev/null 2>&1; assert_status "a home is a repository" $? 4
hub add two --home gone >/dev/null 2>&1; assert_status "a folder that does not exist" $? 4
hub add 'Two' --home solo >/dev/null 2>&1; assert_status "a name in capitals" $? 4
hub add 'two;x' --home solo >/dev/null 2>&1; assert_status "a name with a shell character" $? 4
hub add two >/dev/null 2>&1; assert_status "--home is required" $? 64
assert_eq "nothing refused was written" "$(jq '.projects | length' "$P/projects.json")" "1"
hub add two --home solo >/dev/null; assert_status "a second project" $? 0

# ---- self: the hub records its own session, which every line it sends names ----
hub task app --text "x" >/dev/null 2>&1; assert_status "no task before the hub has recorded itself" $? 2
mkdir -p "$T_TMP/cl"; printf '#!/usr/bin/env bash\ncd "%s" && hh-hub self "$@"\n' "$H" > "$T_TMP/cl/claude"
bash "$T_TMP/cl/claude" --name hub >/dev/null; assert_status "self" $? 0
assert_eq "...its name" "$(jq -r .name "$P/hub.json")" "hub"
[ -n "$(jq -r '.claude_pid // empty' "$P/hub.json")" ] && ok "...and the Claude process" || bad "no claude pid"
bash "$T_TMP/cl/claude" --name 'hub;rm' >/dev/null 2>&1; assert_status "a name hivehouse will not type" $? 4
bash "$T_TMP/cl/claude" --name 'my hub' >/dev/null 2>&1; assert_status "a hub name is one word: orchestrators are told to type it" $? 4
assert_eq "...the record stays" "$(jq -r .name "$P/hub.json")" "hub"
hub name lead >/dev/null; out=$(bash "$T_TMP/cl/claude" 2>&1); assert_status "a session with no name is refused" $? 4
assert_contains "...the hint names the hub's chosen name to start with" "$out" "claude --name lead /$T_PLUGIN:hub"
assert_contains "...and to /rename to" "$out" "/rename lead"
rm -f "$P/name"

# ---- tasks: a ledger of what the owner asked ----
out=$(hub task app --text "Add the export button"); assert_status "task" $? 0
assert_eq "...ids per project" "$(idof "$out")" "app-1"
tf="$P/tasks/app-1.md"
assert_eq "...and its file, absolute, so an orchestrator in another folder can read it" "${out#*$'\t'}" "$tf"
assert_contains "...the text is kept in its file" "$(cat "$tf")" "Add the export button"
assert_contains "...which says who it came through" "$(cat "$tf")" "through hub"
assert_contains "...and lists the project's folders" "$(cat "$tf")" "$H/front"
id2=$(printf 'Fix the totals\n' | hub task app); assert_eq "the text from stdin" "$(idof "$id2")" "app-2"
assert_contains "...kept" "$(cat "$P/tasks/app-2.md")" "Fix the totals"
hub task app --text "" >/dev/null 2>&1; assert_status "an empty task" $? 4
hub task nope --text x >/dev/null 2>&1; assert_status "a task for no project" $? 2
hub log app-1 done --note "shipped" >/dev/null; assert_status "log" $? 0
hub log app-1 shrug >/dev/null 2>&1; assert_status "an event nobody declared" $? 4
hub log app-9 done >/dev/null 2>&1; assert_status "a task nobody asked" $? 2
open=$(hub tasks --open)
case "$open" in *app-2*) ok "an open task is listed" ;; *) bad "open: $open" ;; esac
case "$open" in *app-1*) bad "a done task is listed as open" ;; *) ok "a done task is not open" ;; esac
assert_eq "--json carries the state" "$(hub tasks --json | jq -r '.[] | select(.id=="app-1") | .state')" "done"
hub log app-1 note --note "a remark" >/dev/null
assert_eq "...a note does not move it" "$(hub tasks --json | jq -r '.[] | select(.id=="app-1") | .state')" "done"
hub log app-2 plan >/dev/null; assert_status "a plan to approve" $? 0
assert_eq "...waits on the owner" "$(hub tasks --json | jq -r '.[] | select(.id=="app-2") | [.state, .needs_owner] | map(tostring) | join(" ")')" "plan true"
assert_eq "...a done task does not" "$(hub tasks --json | jq -r '.[] | select(.id=="app-1") | .needs_owner')" "false"

# ---- status: each project's orchestrator, agents, folders, open tasks ----
s=$(hub status --json)
assert_eq "no team yet" "$(printf '%s' "$s" | jq -r '.projects[] | select(.name=="app") | .orchestrator.state')" "none"
assert_eq "...its folders" "$(printf '%s' "$s" | jq -r '[.projects[] | select(.name=="app") | .repos[] | .kind] | join(",")')" "repo,repo,folder"
assert_eq "...one open task" "$(printf '%s' "$s" | jq -r '.projects[] | select(.name=="app") | .open_tasks')" "1"
assert_eq "...the hub's name" "$(printf '%s' "$s" | jq -r .hub.name)" "hub"
echo role > "$T_TMP/impl.md"; echo rules > "$T_TMP/RULES.md"
(cd "$H/back" && hh-spawn --agent impl --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 15 >/dev/null)
S="$H/back/$T_STATE"
# the orchestrator's pane is the owner's own (the keep session's), its Claude long gone
kp=$(hh_tmux list-panes -t keep -F '#{pane_id}' | head -1); ki=$(hh_pane_identity "$HH_TMUX_SOCKET" "$kp")
jq --arg k "$HH_TMUX_SOCKET" --arg kp "$kp" --arg p "${ki%%$'\t'*}" --arg s "${ki#*$'\t'}" '.agents += [{name:"orchestrator", pane:$kp, socket:$k, pane_pid:$p, pane_started:$s, claude_pid:"99999", claude_started:"Mon Jan  1 00:00:00 2001", name_full:"app-orchestrator"}]' \
  "$S/team.json" > "$S/team.json.t" && mv "$S/team.json.t" "$S/team.json"
mkdir -p "$S/team/orchestrator"; jq -nc --arg t "$HH_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"sess-1", transcript_path:$t}' > "$S/team/orchestrator/session.json"
s=$(hub status --json)
assert_eq "an orchestrator whose Claude is gone is stopped" "$(printf '%s' "$s" | jq -r '.projects[] | select(.name=="app") | .orchestrator.state')" "stopped"
assert_eq "...its session" "$(printf '%s' "$s" | jq -r '.projects[] | select(.name=="app") | .orchestrator.session_id')" "sess-1"
assert_eq "...its agents" "$(printf '%s' "$s" | jq -c '[.projects[] | select(.name=="app") | .agents[] | [.name,.state]]')" '[["impl","running"]]'
lv=$(cd "$H/back" && hh-context orchestrator)
assert_eq "...its context level, as hh-context reads it" "$(printf '%s' "$s" | jq -r '.projects[] | select(.name=="app") | .orchestrator | [.context, .context_assumed] | map(tostring) | join(" ")')" "${lv%% *} true"
assert_eq "...an agent with no level carries none" "$(printf '%s' "$s" | jq -r '.projects[] | select(.name=="app") | .agents[0] | has("context")')" "false"
t=$(hub status)
assert_contains "the plain status names the project" "$t" "app"
assert_contains "...and what is stopped" "$t" "stopped"

# ---- wake: a stopped orchestrator is resumed and sent back to its team ----
hub wake two >/dev/null 2>&1; assert_status "wake with no orchestrator recorded" $? 2
hub wake app --model opus >/dev/null 2>&1; assert_status "a resumed session keeps its own model" $? 64
hub wake app --mode bypassPermissions >/dev/null 2>&1; assert_status "never in bypass" $? 4
# the project's own settings make the owner's mode stricter on a wake too (hh-settings)
echo '{"permission_mode":"plan"}' > "$S/settings.json"
wp=$(hub wake app --mode auto --still 2 --max-wait 15 2>"$T_TMP/wake.err"); assert_status "wake" $? 0
[ ! -s "$T_TMP/wake.err" ] && ok "...nothing on stderr" || bad "stderr: $(cat "$T_TMP/wake.err")"
screen=$(hh_tmux capture-pane -p -J -S - -t "$wp")
assert_contains "...its own conversation" "$screen" "ARGV: --resume"
assert_contains "...that session" "$screen" "ARGV: sess-1"
assert_contains "...under its name" "$screen" "ARGV: app-orchestrator"
assert_contains "...with a permission mode" "$screen" "ARGV: --permission-mode"
assert_contains "...the one the project allows" "$screen" "ARGV: plan"
case "$screen" in *"ARGV: --model"*) bad "a model was forced on the resumed session" ;; *) ok "...with its own model" ;; esac
# W3b: the woken orchestrator gets the measuring statusLine a spawned agent gets, its agent folder in the command
wcmd=$(printf '%s\n' "$screen" | grep '^ARGV: {"statusLine"' | sed 's/^ARGV: //' | jq -r '.statusLine.command')
assert_contains "...with hh-statusline as its statusLine" "$wcmd" "/hh-statusline"
assert_contains "...writing into the folder of the agent the wake line registers" "$wcmd" "/$T_STATE/team/orchestrator"
assert_contains "...and told it works through the hub, which survives a rotation" "$screen" "--hub hub"
assert_contains "...told to register again" "$screen" "hh-spawn --self --agent orchestrator"
assert_contains "...and to report to the hub" "$screen" "send hub one line"
assert_eq "...in the project's tmux session" "$(hh_tmux display-message -p -t "$wp" '#{session_name}')" "app"
assert_eq "...in its home" "$(hh_tmux display-message -p -t "$wp" '#{pane_current_path}')" "$H/back"
rm "$S/settings.json"
hub wake app --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "never woken twice while the first is coming up" $? 4
assert_eq "...status says so" "$(hub status --json | jq -r '.projects[] | select(.name=="app") | .orchestrator.starting.pane')" "$wp"
# once it has registered again it runs: a live process named claude stands in for its Claude (the test shell is not one)
( exec -a claude sleep 30 ) & cp_=$!; disown "$cp_"; t_track "$cp_"; sleep 0.3
jq --arg p "$cp_" --arg s "$(hh_lstart "$cp_")" '(.agents[] | select(.name=="orchestrator")) |= (.claude_pid = $p | .claude_started = $s)' \
  "$S/team.json" > "$S/team.json.t" && mv "$S/team.json.t" "$S/team.json"
assert_eq "a registered orchestrator runs" "$(hub status --json | jq -r '.projects[] | select(.name=="app") | .orchestrator.state')" "running"
hub wake app >/dev/null 2>&1; assert_status "a running orchestrator is not woken" $? 4
hh_tmux kill-pane -t "$wp"   # it has registered: the pane this hub started is no longer what stops a second start

# ---- start: a project with no orchestrator gets one, on a task ----
t2=$(hub task two --text "Write the guide"); assert_eq "a task for the second project" "$(idof "$t2")" "two-1"
hub start two app-2 >/dev/null 2>&1; assert_status "a task of another project" $? 4
hub start two two-9 >/dev/null 2>&1; assert_status "a task nobody asked" $? 2
echo '{"statusLine":{"type":"command","command":"echo OWNERSL"}}' > "$CLAUDE_CONFIG_DIR/settings.json"
sp=$(hub start two two-1 --still 2 --max-wait 15 2>"$T_TMP/start.err"); assert_status "start" $? 0
screen=$(hh_tmux capture-pane -p -J -S - -t "$sp")
assert_contains "...a new orchestrator by name" "$screen" "ARGV: two-orchestrator"
assert_contains "...started on the task's file" "$screen" "GOT: /$T_PLUGIN:start Task two-1: read $P/tasks/two-1.md"
assert_eq "...in its home" "$(hh_tmux display-message -p -t "$sp" '#{pane_current_path}')" "$H/solo"
scmd=$(printf '%s\n' "$screen" | grep '^ARGV: {"statusLine"' | sed 's/^ARGV: //' | jq -r '.statusLine.command')
assert_contains "...with hh-statusline as its statusLine" "$scmd" "/hh-statusline"
assert_eq "...and the owner's statusLine as the command's one quoted argument" "$(/bin/sh -c "set -- $scmd; printf %s \"\$3\"")" "echo OWNERSL"
[ -d "$H/solo/$T_STATE/team/orchestrator" ] && ok "...its agent folder exists before the launch" || bad "no agent folder for the new orchestrator"
[ ! -e "$H/solo/$T_STATE/team/orchestrator/statusline.json" ] && ok "...and no statusline.json is written there" || bad "a statusline.json was written for the orchestrator"
assert_eq "the task is marked handed" "$(hub tasks --json | jq -r '.[] | select(.id=="two-1") | .state')" "handed"
hub start two two-1 --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "never started twice while the first is coming up" $? 4
hh_tmux kill-pane -t "$sp"; sleep 0.5   # it died before registering (a restart, say): it no longer holds the project
sp2=$(hub start two two-1 --still 2 --max-wait 15 2>/dev/null); assert_status "a start whose pane is gone can be made again" $? 0
[ -n "$sp2" ] && [ "$sp2" != "$sp" ] && ok "...in a new pane" || bad "no new pane: '$sp2'"
hub start app app-2 --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "never started where an orchestrator is recorded" $? 4
hub log two-1 done >/dev/null
hub start two two-1 >/dev/null 2>&1; assert_status "never started on a closed task" $? 4

# ---- an orchestrator already running outside hivehouse is found, never doubled ----
# Claude Code keeps a record of every running session (<config>/sessions/<pid>.json: its name, folder and tmux pane)
mk tri; hub add tri --home tri >/dev/null; t3=$(idof "$(hub task tri --text "Fix it")")
live() {  # live <name> <cwd> [<tmux value>]: a running process named claude, with Claude Code's record of it
  ( exec -a claude sleep 60 ) >/dev/null 2>&1 & local p=$!; disown "$p"; t_track "$p"; sleep 0.2   # its output never holds the \$(...)
  mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
  jq -nc --argjson p "$p" --arg n "$1" --arg c "$2" --arg t "${3:-work:@3.%77}" '{pid:$p, name:$n, cwd:$c, tmux:$t, kind:"interactive"}' > "$CLAUDE_CONFIG_DIR/sessions/$p.json"
  echo "$p"
}
# this hub's own session is never a project's orchestrator, whatever it is called
hp=$(live tri-orchestrator "$H/tri"); cp "$P/hub.json" "$T_TMP/hub.json.saved"
jq --arg p "$hp" '.claude_pid = $p' "$T_TMP/hub.json.saved" > "$P/hub.json"
assert_eq "the hub's own session is not taken for an orchestrator" "$(hub status tri --json | jq -r '.projects[0].orchestrator.state')" "none"
kill "$hp" 2>/dev/null; cp "$T_TMP/hub.json.saved" "$P/hub.json"; sleep 0.3
lp=$(live tri-builder "$H/tri")
assert_eq "a session that is no orchestrator is not one" "$(hub status tri --json | jq -r '.projects[0].orchestrator.state')" "none"
lp=$(live tri-orchestrator "$H/tri")
s=$(hub status tri --json)
assert_eq "a running orchestrator hivehouse never registered is found" "$(printf '%s' "$s" | jq -r '.projects[0].orchestrator.state')" "unregistered"
assert_eq "...by its name, process and pane" "$(printf '%s' "$s" | jq -r '.projects[0].orchestrator | [.name, .pid, .pane] | map(tostring) | join(" ")')" "tri-orchestrator $lp %77"
hub start tri "$t3" --still 2 --max-wait 15 >/dev/null 2>"$T_TMP/tri.err"; assert_status "...and never started a second time" $? 4
assert_contains "...the refusal says how it joins" "$(cat "$T_TMP/tri.err")" "hh-spawn --self"
assert_contains "the plain status says so" "$(hub status tri)" "not registered"
kill "$lp" 2>/dev/null; sleep 0.3
assert_eq "...gone once it ends" "$(hub status tri --json | jq -r '.projects[0].orchestrator.state')" "none"

# ---- a start stopped at a question: shown, kept, and continued once the owner answers ----
# the project's own settings make the owner's mode stricter, never looser (hh-settings): the orchestrator gets the result
mkdir -p "$H/tri/$T_STATE"; echo '{"permission_mode":"plan"}' > "$H/tri/$T_STATE/settings.json"
hh_tmux set-environment -g HH_FAKE_CLAUDE dialoganswer
qp=$(hub start tri "$t3" --mode auto --still 2 --max-wait 30 2>"$T_TMP/q.err"); assert_status "a question stops the start" $? 5
assert_contains "...and says how to go on" "$(cat "$T_TMP/q.err")" "hh-hub continue tri"
hh_tmux set-environment -g -u HH_FAKE_CLAUDE
st=$(hub status tri --json | jq -c '.projects[0].orchestrator.starting')
assert_eq "...status shows it waiting on the owner" "$(printf '%s' "$st" | jq -r '[.typed, .question] | map(tostring) | join(" ")')" "false true"
qp=$(printf '%s' "$st" | jq -r .pane)
assert_contains "...in the mode the project allows" "$(hh_tmux capture-pane -p -J -S - -t "$(hub status tri --json | jq -r '.projects[0].orchestrator.starting.pane')")" "ARGV: plan"
hub start tri "$t3" --still 2 --max-wait 15 >/dev/null 2>"$T_TMP/q2.err"; assert_status "...never started again" $? 4
assert_contains "...it points at continue" "$(cat "$T_TMP/q2.err")" "hh-hub continue tri"
hub continue tri --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "continue while the question is still there" $? 5
hh_tmux send-keys -t "$qp" 1 Enter; sleep 0.5   # the owner answers it
cp2=$(hub continue tri --still 2 --max-wait 15 2>"$T_TMP/c.err"); assert_status "continue" $? 0
assert_eq "...in the same pane" "$cp2" "$qp"
assert_contains "...the start's line is typed" "$(hh_tmux capture-pane -p -J -S - -t "$qp")" "GOT: /$T_PLUGIN:start Task $t3: read $P/tasks/$t3.md"
assert_eq "...the task is handed" "$(hub tasks --json | jq -r --arg i "$t3" '.[] | select(.id==$i) | .state')" "handed"
hub continue tri --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "nothing left to continue" $? 4
hub continue app >/dev/null 2>&1; assert_status "continue where this hub started nothing" $? 2

# ---- a start still being sent is coming up, not waiting on the owner, and continue never sends its line twice ----
mk five; hub add five --home five >/dev/null; t5=$(idof "$(hub task five --text "Ship it")")
( cd "$H" && hh-hub start five "$t5" --still 6 --max-wait 30 >"$T_TMP/five.out" 2>&1; echo "rc=$?" >> "$T_TMP/five.out" ) &
fs=$!; t_track "$fs"; sleep 3
st=$(hub status five --json | jq -c '.projects[0].orchestrator.starting')
assert_eq "while its line is on the way it is being sent, not waiting" "$(printf '%s' "$st" | jq -r '[.typed, .sending] | map(tostring) | join(" ")')" "false true"
case "$(hub status five)" in *"hh-hub continue"*) bad "the plain status offers continue for a start still being sent" ;; *) ok "...the plain status offers no continue" ;; esac
# A83: a record 0.2.0 wrote (the sender's start time in the caller's locale) names the same sender
spf="$P/panes/five.json"; spid=$(jq -r .sender_pid "$spf")
jq --arg s "$(/bin/ps -o lstart= -p "$spid" | sed 's/^ *//;s/ *$//')" '.sender_started = $s' "$spf" > "$spf.t" && mv "$spf.t" "$spf"
assert_eq "...also when its record is in the caller's locale" "$(hub status five --json | jq -r '.projects[0].orchestrator.starting.sending')" "true"
hub continue five --still 1 --max-wait 5 >/dev/null 2>"$T_TMP/c5.err"; assert_status "...and continue refuses it" $? 4
wait "$fs"
assert_contains "the start itself finished" "$(cat "$T_TMP/five.out")" "rc=0"
fp=$(head -1 "$T_TMP/five.out")
assert_eq "...its line typed once" "$(hh_tmux capture-pane -p -J -S - -t "$fp" | grep -c "GOT: /$T_PLUGIN:start Task $t5")" "1"
assert_eq "...and handed once" "$(jq -r --arg i "$t5" 'select(.id == $i and .event == "handed") | .id' "$P/tasks.jsonl" | grep -c .)" "1"

# ---- run: the two owner-only skills, typed into a running orchestrator's own pane (on the server it is recorded on) ----
mk ru; hub add ru --home ru >/dev/null; RU="$H/ru/$T_STATE"; mkdir -p "$RU"
SB="$T_TMP/b.sock"   # a second tmux server: a registered orchestrator's pane is not always on hivehouse's own
ru_pane() {  # ru_pane <fake claude mode> [capture to draw]: a fresh pane on that server, recorded as ru's orchestrator (a stand-in process for its Claude)
  tmux -S "$SB" kill-server 2>/dev/null; sleep 0.3
  RUPANE=$(env -u HIVEHOUSE_HOME tmux -S "$SB" new-session -d -x 200 -y 56 -P -F '#{pane_id}' -s rub -c "$H/ru" -e "HH_FAKE_CLAUDE=$1" -e "HH_FAKE_DIALOG=${2:-}" 'exec claude --name ru-orchestrator') || return 1
  t_track "$(tmux -S "$SB" display -p '#{pid}')"
  ( exec -a claude sleep 300 ) >/dev/null 2>&1 & RUCLAUDE=$!; disown "$RUCLAUDE"; t_track "$RUCLAUDE"; sleep 0.3
  local i; i=$(hh_pane_identity "$SB" "$RUPANE")
  jq -nc --arg k "$SB" --arg p "$RUPANE" --arg pp "${i%%$'\t'*}" --arg ps "${i#*$'\t'}" --arg c "$RUCLAUDE" --arg cs "$(hh_lstart "$RUCLAUDE")" \
    '{agents:[{name:"orchestrator", pane:$p, socket:$k, pane_pid:$pp, pane_started:$ps, claude_pid:$c, claude_started:$cs, name_full:"ru-orchestrator"}]}' > "$RU/team.json"
  mkdir -p "$RU/team/orchestrator"; jq -nc --arg t "$HH_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"sess-ru", transcript_path:$t}' > "$RU/team/orchestrator/session.json"
}
rscreen() { tmux -S "$SB" capture-pane -p -J -S - -t "$RUPANE"; }
r1=$(idof "$(hub task ru --text "Work the queue")")
hub run ru bogus "$r1" >/dev/null 2>&1; assert_status "run: only the two owner-only skills" $? 64
hub run ru start "$r1" >/dev/null 2>&1; assert_status "...start is not one" $? 64
hub run ru overnight >/dev/null 2>&1; assert_status "...a task id is required" $? 64
hub run ru overnight "$r1" --disk >/dev/null 2>&1; assert_status "...--disk is cleanup's" $? 64
hub run ru overnight "$r1" --mode auto >/dev/null 2>&1; assert_status "...no mode: the session is already running" $? 64
hub run ru overnight ru-9 >/dev/null 2>&1; assert_status "...a task nobody asked" $? 2
hub run tri cleanup "$t3" >/dev/null 2>"$T_TMP/r.err"; assert_status "...no orchestrator is recorded" $? 4
assert_contains "......it says to start one" "$(cat "$T_TMP/r.err")" "hh-hub start tri"
lp=$(live tri-orchestrator "$H/tri")
hub run tri overnight "$t3" >/dev/null 2>"$T_TMP/r.err"; assert_status "...an orchestrator outside hivehouse" $? 4
assert_contains "......it says to register it" "$(cat "$T_TMP/r.err")" "hh-spawn --self"
kill "$lp" 2>/dev/null; sleep 0.3
ru_pane idle
jq '.agents[0].claude_pid = "99999"' "$RU/team.json" > "$RU/team.json.t" && mv "$RU/team.json.t" "$RU/team.json"
hub run ru overnight "$r1" --still 2 --max-wait 10 >/dev/null 2>"$T_TMP/r.err"; assert_status "...a stopped orchestrator" $? 4
assert_contains "......it says to wake it" "$(cat "$T_TMP/r.err")" "hh-hub wake ru"
ru_pane idle
hub run ru overnight "$t3" --still 2 --max-wait 10 >/dev/null 2>&1; assert_status "...a task of another project, even for a running orchestrator" $? 4
hub log "$r1" plan >/dev/null
hub run ru overnight "$r1" --still 2 --max-wait 10 >/dev/null 2>&1; assert_status "...a task waiting on the owner is never hidden" $? 4
hub log "$r1" answered >/dev/null
assert_eq "...nothing was typed by any refusal" "$(rscreen | grep -c 'GOT:')" "0"
# a start record left from when this hub started the orchestrator is not a start in progress: it never blocks a run
mkdir -p "$P/panes"; ri=$(hh_pane_identity "$SB" "$RUPANE")
jq -nc --arg p "$RUPANE" --arg s "$SB" --arg i "${ri%%$'\t'*}" --arg t "${ri#*$'\t'}" \
  '{pane:$p, socket:$s, pane_pid:$i, pane_started:$t, kind:"start", line:"x", typed:true, at:"2026-10-06T00:00:00Z"}' > "$P/panes/ru.json"
rp=$(hub run ru overnight "$r1" --still 2 --max-wait 15 2>"$T_TMP/r.err"); assert_status "run overnight" $? 0
assert_eq "...into the orchestrator's pane, on its own server" "$rp" "$RUPANE"
assert_contains "...the fixed line" "$(rscreen)" "GOT: /$T_PLUGIN:overnight Task $r1: read $P/tasks/$r1.md. It came from the owner through hub."
assert_eq "...typed once" "$(rscreen | grep -c "GOT: /$T_PLUGIN:overnight")" "1"
assert_eq "...the task is in an overnight run, not waiting on the owner" "$(hub tasks --json | jq -r --arg i "$r1" '.[] | select(.id==$i) | [.state, .needs_owner] | map(tostring) | join(" ")')" "overnight false"
assert_eq "...and still open" "$(hub tasks --open | grep -c "^$r1")" "1"
hub run ru overnight "$r1" --still 2 --max-wait 10 >/dev/null 2>&1; assert_status "a task already in an overnight run is not run again" $? 4
assert_eq "...nothing more was typed" "$(rscreen | grep -c "GOT: /$T_PLUGIN:overnight")" "1"
hub run ru cleanup "$r1" --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "run cleanup" $? 0
assert_eq "...its fixed line" "$(rscreen | grep -c "GOT: /$T_PLUGIN:cleanup\$")" "1"
assert_eq "...the task's state" "$(hub tasks --json | jq -r --arg i "$r1" '.[] | select(.id==$i) | .state')" "cleanup"
hub run ru cleanup "$r1" --disk --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "run cleanup --disk" $? 0
assert_eq "...its fixed line" "$(rscreen | grep -c "GOT: /$T_PLUGIN:cleanup --disk\$")" "1"
# a dialog on the screen: nothing typed, and continue goes on once the owner has answered it
r2=$(idof "$(hub task ru --text "Second")"); ru_pane dialoganswer
hub run ru overnight "$r2" --still 2 --max-wait 30 >/dev/null 2>"$T_TMP/r.err"; assert_status "a dialog on the orchestrator's screen" $? 5
assert_contains "...it says how to go on" "$(cat "$T_TMP/r.err")" "hh-hub continue ru"
assert_eq "...nothing was typed" "$(rscreen | grep -c 'GOT:')" "0"
assert_eq "...nothing was logged" "$(hub tasks --json | jq -r --arg i "$r2" '.[] | select(.id==$i) | .state')" "asked"
tmux -S "$SB" send-keys -t "$RUPANE" 1 Enter; sleep 0.5   # the owner answers it
hub continue ru --still 2 --max-wait 15 >/dev/null 2>"$T_TMP/r.err"; assert_status "continue" $? 0
assert_eq "...the line is typed once" "$(rscreen | grep -c "GOT: /$T_PLUGIN:overnight Task $r2")" "1"
assert_eq "...and logged" "$(hub tasks --json | jq -r --arg i "$r2" '.[] | select(.id==$i) | .state')" "overnight"
hub continue ru >/dev/null 2>&1; assert_status "...nothing left to continue" $? 2
# two runs at once: the second is refused while the first is still sending, so the line is typed once
r3=$(idof "$(hub task ru --text "Third")"); ru_pane idle
( cd "$H" && hh-hub run ru overnight "$r3" --still 6 --max-wait 30 >"$T_TMP/run3.out" 2>&1; echo "rc=$?" >> "$T_TMP/run3.out" ) &
fs=$!; t_track "$fs"; sleep 3
hub run ru overnight "$r3" --still 1 --max-wait 5 >/dev/null 2>"$T_TMP/r.err"; assert_status "a second run while the first is sending" $? 4
wait "$fs"
assert_contains "...the first finished" "$(cat "$T_TMP/run3.out")" "rc=0"
assert_eq "...its line typed once" "$(rscreen | grep -c "GOT: /$T_PLUGIN:overnight Task $r3")" "1"
r4=$(idof "$(hub task ru --text "Fourth")"); hub log "$r4" done >/dev/null
hub run ru overnight "$r4" --still 2 --max-wait 10 >/dev/null 2>&1; assert_status "a closed task" $? 4
tmux -S "$SB" kill-server 2>/dev/null

# ---- start --overnight: a project with no orchestrator starts on the overnight line ----
mk ov; hub add ov --home ov >/dev/null; to=$(idof "$(hub task ov --text "Run the night")")
op=$(hub start ov "$to" --overnight --still 2 --max-wait 15 2>/dev/null); assert_status "start --overnight" $? 0
assert_contains "...its first line is the overnight line" "$(hh_tmux capture-pane -p -J -S - -t "$op")" "GOT: /$T_PLUGIN:overnight Task $to: read $P/tasks/$to.md. It came from the owner through hub."
case "$(hh_tmux capture-pane -p -J -S - -t "$op")" in *"/$T_PLUGIN:start"*) bad "an overnight start also typed the start line" ;; *) ok "...not the start line" ;; esac
assert_eq "...the task is handed" "$(hub tasks --json | jq -r --arg i "$to" '.[] | select(.id==$i) | .state')" "handed"

# ---- dialog and answer: a dialog on a session's screen is read, and answered with the one key the owner chose ----
FX="$HH_REPO_ROOT/tests/fixtures/dialogs"
jj() { printf '%s' "$1" | jq -r "$2"; }
nkeys() { rscreen | grep -c '^KEY:'; }          # every key that reached the orchestrator's pane
seq_of() { rscreen | grep '^KEY:' | tr '\n' ' '; }
ZERO=0000000000000000000000000000000000000000
ru_pane dialogfile "$FX/03-bash-permission.ansi"; sleep 1
dj=$(hub dialog ru); assert_status "dialog" $? 0
assert_eq "...the session it is on" "$(jj "$dj" .session)" "ru-orchestrator"
assert_eq "...its pane" "$(jj "$dj" .pane)" "$RUPANE"
assert_eq "...its options" "$(jj "$dj" '[.options[].n] | join(",")')" "1,2,3"
assert_contains "...its text" "$(jj "$dj" .text)" "touch made-by-test.txt"
dfp=$(jj "$dj" .fingerprint)
hub dialog nope >/dev/null 2>&1; assert_status "dialog for no project" $? 2
hub dialog ru ghost >/dev/null 2>&1; assert_status "...an agent that is not on the team" $? 2
hub answer ru --choice 1 >/dev/null 2>&1; assert_status "answer needs the fingerprint it was shown" $? 64
hub answer ru --seen "$dfp" >/dev/null 2>&1; assert_status "...and a choice" $? 64
hub answer ru --choice x --seen "$dfp" >/dev/null 2>&1; assert_status "...a choice that is a digit or esc" $? 64
hub answer ru --choice 1 --seen abc >/dev/null 2>&1; assert_status "...a fingerprint that is one" $? 64
hub answer ru ghost --choice 1 --seen "$dfp" >/dev/null 2>&1; assert_status "an agent that is not in team.json" $? 2
hub answer ru --choice 7 --seen "$dfp" >/dev/null 2>&1; assert_status "an option the dialog does not have" $? 64
hub answer ru --choice 1.0 --seen "$dfp" >/dev/null 2>&1; assert_status "a choice that is not one digit or esc (1.0)" $? 64
hub answer ru --choice ' 1' --seen "$dfp" >/dev/null 2>&1; assert_status "...( 1)" $? 64
hub answer ru --choice 11 --seen "$dfp" >/dev/null 2>&1; assert_status "...(11)" $? 64
assert_eq "...nothing was sent by any of them" "$(nkeys)" "0"
hub answer ru --choice 1 --seen "$ZERO" >/dev/null 2>"$T_TMP/a.err"; assert_status "a screen that is not the one the owner saw" $? 4
assert_contains "...says to look again" "$(cat "$T_TMP/a.err")" "the dialog changed"
assert_eq "...nothing was sent by any refusal" "$(nkeys)" "0"
ao=$(hub answer ru --choice 1 --seen "$dfp" 2>"$T_TMP/a.err"); assert_status "answer" $? 0
assert_eq "...exactly one key, the digit" "$(seq_of)" "KEY: 1 "
assert_eq "...and says the dialog went away" "$(jj "$ao" .dialog_gone)" "true"
assert_eq "...with the option's text" "$(jj "$ao" .option)" "Yes"
assert_eq "...logged with the session and the option" "$(jq -r '[.event, .project, .session, .option] | join("|")' "$P/answers.jsonl" | tail -1)" "answered-dialog|ru|ru-orchestrator|Yes"
hub answer ru --choice 1 --seen "$dfp" >/dev/null 2>"$T_TMP/a.err"; assert_status "answering again, with no dialog on the screen" $? 4
assert_contains "...says there is none, not that it changed" "$(cat "$T_TMP/a.err")" "no dialog is on"
hub dialog ru >/dev/null 2>&1; assert_status "...dialog says so too" $? 4
assert_eq "...nothing more was sent" "$(nkeys)" "1"
# Escape, where the dialog offers it
ru_pane dialogfile "$FX/04-write-permission.ansi"; sleep 1
efp=$(jj "$(hub dialog ru)" .fingerprint)
hub answer ru --choice esc --seen "$efp" >/dev/null 2>&1; assert_status "esc" $? 0
assert_eq "...one Escape" "$(seq_of)" "KEY: ESC "
# a question that needs the owner's own text is never answered by the hub
ru_pane dialogfile "$FX/05-ask-user-question.ansi"; sleep 1
qfp=$(jj "$(hub dialog ru)" .fingerprint)
hub answer ru --choice 3 --seen "$qfp" >/dev/null 2>"$T_TMP/a.err"; assert_status "an option that needs the owner's own text" $? 4
assert_contains "...says to answer in the pane" "$(cat "$T_TMP/a.err")" "in the pane"
hub answer ru --choice 4 --seen "$qfp" >/dev/null 2>&1; assert_status "...nor the chat option" $? 4
assert_eq "...nothing was sent" "$(nkeys)" "0"
hub answer ru --choice 2 --seen "$qfp" >/dev/null 2>&1; assert_status "an offered option" $? 0
assert_eq "...its digit" "$(seq_of)" "KEY: 2 "
# an unnumbered menu: arrow keys to the chosen row, then Enter as the last key
ru_pane dialogfile "$FX/01-trust-folder.ansi"; sleep 1
tfp=$(jj "$(hub dialog ru)" .fingerprint)
hub answer ru --choice 2 --seen "$tfp" >/dev/null 2>&1; assert_status "a menu: the second row" $? 0
assert_eq "...one Down, then Enter" "$(seq_of)" "KEY: DOWN KEY: ENTER "
ru_pane dialogfile "$FX/01-trust-folder.ansi"; sleep 1
hub answer ru --choice 1 --seen "$tfp" >/dev/null 2>&1; assert_status "a menu: the row the cursor is on" $? 0
assert_eq "...Enter only" "$(seq_of)" "KEY: ENTER "
ru_pane dialogfile "$FX/01c-trust-after-down.ansi"; sleep 1
hub answer ru --choice 1 --seen "$(jj "$(hub dialog ru)" .fingerprint)" >/dev/null 2>&1; assert_status "a menu: a row above the cursor" $? 0
assert_eq "...one Up, then Enter" "$(seq_of)" "KEY: UP KEY: ENTER "
# a dialog on an agent's screen: the same, on that agent's pane
ru_pane idle
APANE=$(env -u HIVEHOUSE_HOME tmux -S "$SB" new-window -d -P -F '#{pane_id}' -t rub: -n impl -e "HH_FAKE_CLAUDE=dialogfile" -e "HH_FAKE_DIALOG=$FX/03-bash-permission.ansi" 'exec claude')
ai=$(hh_pane_identity "$SB" "$APANE")
jq --arg k "$SB" --arg p "$APANE" --arg pp "${ai%%$'\t'*}" --arg ps "${ai#*$'\t'}" '.agents += [{name:"impl", pane:$p, socket:$k, pane_pid:$pp, pane_started:$ps}]' "$RU/team.json" > "$RU/team.json.t" && mv "$RU/team.json.t" "$RU/team.json"
sleep 1
hub dialog ru >/dev/null 2>&1; assert_status "an orchestrator with no dialog" $? 4
adj=$(hub dialog ru impl); assert_status "an agent's dialog" $? 0
assert_eq "...its session and pane" "$(jj "$adj" '[.session, .pane] | join(" ")')" "impl $APANE"
hub answer ru impl --choice 1 --seen "$(jj "$adj" .fingerprint)" >/dev/null 2>&1; assert_status "answered on the agent's pane" $? 0
assert_eq "...its digit arrived there" "$(tmux -S "$SB" capture-pane -p -J -S - -t "$APANE" | grep -c '^KEY: 1$')" "1"
assert_eq "...and not on the orchestrator's" "$(nkeys)" "0"
tmux -S "$SB" kill-server 2>/dev/null

# the hub is not locked while answer waits to see the dialog go away
ru_pane dialog; sleep 1
sfp=$(jj "$(hub dialog ru)" .fingerprint)
( cd "$H" && hh-hub answer ru --choice 1 --seen "$sfp" > "$T_TMP/slow.out" 2>&1 ) & sa=$!; t_track "$sa"; sleep 1
t0=$(date +%s); hub log "$r1" note --note "while answer waits" >/dev/null 2>&1; lrc=$?; t1=$(date +%s)
assert_status "a log while answer waits for the dialog to go away" "$lrc" 0
[ $((t1 - t0)) -le 2 ] && ok "...is not held up by the wait" || bad "the log waited $((t1 - t0)) s for the lock"
wait "$sa"; assert_eq "...and the answer reports the dialog is still there" "$(jq -r .dialog_gone "$T_TMP/slow.out")" "false"
tmux -S "$SB" kill-server 2>/dev/null
# a session running outside hivehouse: its pane is read only where its record says it is
mk unr; hub add unr --home unr >/dev/null
hh_tmux set-option -g default-size 200x56   # the captures are 50 lines: a window of the default 24 would scroll the dialog away
up=$(hh_open_window unr orchestrator "$H/unr" "exec claude" -e "HH_FAKE_CLAUDE=dialogfile" -e "HH_FAKE_DIALOG=$FX/01-trust-folder.ansi"); sleep 1
utm=$(hh_tmux display-message -p -t "$up" '#{session_name}:#{window_id}.#{pane_id}')
upid=$(hh_tmux display-message -p -t "$up" '#{pane_pid}')   # the pane's own process is the session: its record names that pid
mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
jq -nc --argjson p "$upid" --arg n unr-orchestrator --arg c "$H/unr" --arg t "$utm" '{pid:$p, name:$n, cwd:$c, tmux:$t, kind:"interactive"}' > "$CLAUDE_CONFIG_DIR/sessions/$upid.json"
assert_eq "an orchestrator outside hivehouse, on hivehouse's own server, as its record says: its dialog is read" "$(jj "$(hub dialog unr)" .pane)" "$up"
assert_eq "...and status sees the question" "$(hub status unr --json | jq -r '.projects[0].orchestrator.question')" "true"
ufp=$(jj "$(hub dialog unr)" .fingerprint)
# the record names this very pane, but the process it names is not inside it (two tmux servers can both have a pane %0)
mv "$CLAUDE_CONFIG_DIR/sessions/$upid.json" "$T_TMP/upid.saved"; ulp=$(live unr-orchestrator "$H/unr" "$utm")
hub dialog unr >/dev/null 2>"$T_TMP/u.err"; assert_status "a record whose process is not inside the pane it names" $? 4
assert_eq "...status does not read it either" "$(hub status unr --json | jq -r '.projects[0].orchestrator.question')" "false"
kill "$ulp" 2>/dev/null; sleep 0.3; mv "$T_TMP/upid.saved" "$CLAUDE_CONFIG_DIR/sessions/$upid.json"
hub answer unr --choice 1 --seen "$ufp" >/dev/null 2>&1; assert_status "...and answered" $? 0
assert_eq "...with the key" "$(hh_tmux capture-pane -p -J -S - -t "$up" | grep -c '^KEY: ENTER')" "1"
kill "$ulp" 2>/dev/null; sleep 0.3; hh_tmux kill-pane -t "$up"
up=$(hh_open_window unr orchestrator "$H/unr" "exec claude" -e "HH_FAKE_CLAUDE=dialogfile" -e "HH_FAKE_DIALOG=$FX/01-trust-folder.ansi"); sleep 1
ulp=$(live unr-orchestrator "$H/unr" "elsewhere:@0.$up")
hub dialog unr >/dev/null 2>"$T_TMP/u.err"; assert_status "a record that names another session or window than the pane's" $? 4
assert_contains "...says to answer in the pane" "$(cat "$T_TMP/u.err")" "answer it in the pane"
assert_eq "...status does not read it" "$(hub status unr --json | jq -r '.projects[0].orchestrator.question')" "false"
hub answer unr --choice 1 --seen "$ufp" >/dev/null 2>&1; assert_status "...and nothing is sent to it" $? 4
assert_eq "...no key reached it" "$(hh_tmux capture-pane -p -J -S - -t "$up" | grep -c '^KEY:')" "0"
kill "$ulp" 2>/dev/null; sleep 0.3

# ---- the hub names its own session: Claude Code's record of it, and a name no other running session has ----
mine=$(live "" "$H"); jq '.sessionId = "sess-hub" | .nameSource = "auto" | .name = "Read the docs"' "$CLAUDE_CONFIG_DIR/sessions/$mine.json" > "$T_TMP/m.json" && mv "$T_TMP/m.json" "$CLAUDE_CONFIG_DIR/sessions/$mine.json"
n=$(hub naming --session sess-hub); assert_status "naming" $? 0
assert_eq "...an unnamed session is offered hub" "$(printf '%s' "$n" | jq -r '[.found, .source, .free] | map(tostring) | join(" ")')" "true auto hub"
other=$(live hub "$T_TMP")
assert_eq "...hub-2 while another session is called hub" "$(hub naming --session sess-hub | jq -r .free)" "hub-2"
kill "$other" 2>/dev/null; sleep 0.3
assert_eq "...and found false when Claude Code keeps no record of it" "$(hub naming --session nosuch | jq -r .found)" "false"
hub naming --session 'x;y' >/dev/null 2>&1; assert_status "...a session id it will not read" $? 4
kill "$mine" 2>/dev/null

# ---- a question in an agent's window is shown, since nobody watches it ----
hh_tmux set-environment -g HH_FAKE_CLAUDE dialog
(cd "$H/back" && hh-spawn --agent dlg --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 6 >/dev/null 2>&1)
hh_tmux set-environment -g -u HH_FAKE_CLAUDE
s=$(hub status app --json)
assert_eq "an agent with a question on its screen" "$(printf '%s' "$s" | jq -r '.projects[0].agents[] | select(.name=="dlg") | .question')" "true"
assert_eq "...one without has none" "$(printf '%s' "$s" | jq -r '.projects[0].agents[] | select(.name=="impl") | .question')" "false"
assert_contains "the plain status says so" "$(hub status app)" "question"

# ---- the words orchestrators and the hub exchange: declared once in hh-hub, held to both skills ----
for v in HUB_REPLIES HUB_ASKS; do
  words=$(sed -n "s/^$v=\"\(.*\)\"$/\1/p" "$HH_REPO_ROOT/bin/hh-hub")
  [ -n "$words" ] && ok "$v is declared" || bad "$v is not declared in bin/hh-hub"
  for w in $words; do
    for sk in hub start; do
      grep -q -- "$w" "$HH_REPO_ROOT/skills/$sk/SKILL.md" && ok "$w is in the $sk skill" || bad "$w ($v) is missing from skills/$sk/SKILL.md"
    done
  done
done

# ---- the session hook: the hub's folder makes the session the hub, and only that folder ----
hk() { printf '{"cwd":"%s","session_id":"x","source":"%s"}' "$1" "${2:-startup}" | hh-session-hook; }
out=$(hk "$H"); assert_status "hook in the hub's folder" $? 0
assert_contains "...says the session is the hub" "$out" "$T_PLUGIN:hub"
out=$(hk "$H" clear); assert_contains "...again after a clear" "$out" "$T_PLUGIN:hub"
out=$(hk "$H/back"); assert_eq "nothing in a project below it" "$out" ""
out=$(hk "$T_TMP"); assert_eq "nothing elsewhere" "$out" ""

# ---- remove ----
hub remove two >/dev/null; assert_status "remove" $? 0
hub remove two >/dev/null 2>&1; assert_status "remove what is not there" $? 2
assert_eq "...the others stay" "$(jq -r '[.projects[].name] | join(",")' "$P/projects.json")" "app,tri,five,ru,ov,unr"
cd /; t_teardown; t_done
