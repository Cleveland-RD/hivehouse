#!/usr/bin/env bash
# The owner's hub: one session in the work folder that knows every project (a project can span several folders), routes
# the owner's tasks to each project's orchestrator, wakes an orchestrator a restart stopped and starts one where none is,
# and keeps a ledger of what was asked. It never touches a project's code.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
env -u HIVEMIND_HOME tmux -S "$HM_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P)
mk() { local d="$H/$1"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" config user.email t@t; git -C "$d" config user.name t
       echo x > "$d/README"; git -C "$d" add README; git -C "$d" commit -qm init; }
hub() { (cd "$H" && hm-hub "$@"); }
P="$H/.hivemind-hub"

# ---- no hub yet ----
hub status >/dev/null 2>&1; assert_status "status with no hub" $? 2
(cd "$(t_repo inrepo)" && hm-hub init >/dev/null 2>&1); assert_status "a hub is never made inside a repository" $? 4
hub init >/dev/null; assert_status "init" $? 0
[ -d "$P/memory" ] && [ -d "$P/tasks" ] && [ "$(jq -c . "$P/projects.json")" = '{"projects":[]}' ] && ok "init lays the hub out" || bad "hub layout"
hub init >/dev/null; assert_status "init again changes nothing" $? 0
mkdir -p "$H/back/deep"; mk back; mk front; mk solo; mkdir -p "$H/notes"
git -C "$H/back" worktree add -q "$H/back-wt" -b feat
(cd "$H/back/deep" && hm-hub status >/dev/null); assert_status "found from a folder below it" $? 0

# ---- discover: facts only ----
d=$(hub discover)
assert_eq "a repository" "$(printf '%s\n' "$d" | awk '$1=="back"{print $2}')" "repo"
assert_eq "a worktree names its repository" "$(printf '%s\n' "$d" | awk '$1=="back-wt"{print $2, $3, $4}')" "worktree of back"
assert_eq "a plain folder" "$(printf '%s\n' "$d" | awk '$1=="notes"{print $2}')" "folder"
case "$d" in *".hivemind-hub"*) bad "discover lists the hub itself" ;; *) ok "the hub is not listed" ;; esac

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
mkdir -p "$T_TMP/cl"; printf '#!/usr/bin/env bash\ncd "%s" && hm-hub self "$@"\n' "$H" > "$T_TMP/cl/claude"
bash "$T_TMP/cl/claude" --name hub >/dev/null; assert_status "self" $? 0
assert_eq "...its name" "$(jq -r .name "$P/hub.json")" "hub"
[ -n "$(jq -r '.claude_pid // empty' "$P/hub.json")" ] && ok "...and the Claude process" || bad "no claude pid"
bash "$T_TMP/cl/claude" --name 'hub;rm' >/dev/null 2>&1; assert_status "a name hivemind will not type" $? 4
assert_eq "...the record stays" "$(jq -r .name "$P/hub.json")" "hub"

# ---- tasks: a ledger of what the owner asked ----
id=$(hub task app --text "Add the export button"); assert_status "task" $? 0
assert_eq "...ids per project" "$id" "app-1"
tf="$P/tasks/app-1.md"
assert_contains "...the text is kept in its file" "$(cat "$tf")" "Add the export button"
assert_contains "...which says who it came through" "$(cat "$tf")" "through hub"
assert_contains "...and lists the project's folders" "$(cat "$tf")" "$H/front"
id2=$(printf 'Fix the totals\n' | hub task app); assert_eq "the text from stdin" "$id2" "app-2"
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
(cd "$H/back" && hm-spawn --agent impl --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 15 >/dev/null)
S="$H/back/.hivemind"
# the orchestrator's pane is the owner's own (the keep session's), its Claude long gone
kp=$(hm_tmux list-panes -t keep -F '#{pane_id}' | head -1); ki=$(hm_pane_identity "$HM_TMUX_SOCKET" "$kp")
jq --arg k "$HM_TMUX_SOCKET" --arg kp "$kp" --arg p "${ki%%$'\t'*}" --arg s "${ki#*$'\t'}" '.agents += [{name:"orchestrator", pane:$kp, socket:$k, pane_pid:$p, pane_started:$s, claude_pid:"99999", claude_started:"Mon Jan  1 00:00:00 2001", name_full:"app-orchestrator"}]' \
  "$S/team.json" > "$S/team.json.t" && mv "$S/team.json.t" "$S/team.json"
mkdir -p "$S/team/orchestrator"; jq -nc --arg t "$HM_REPO_ROOT/tests/fixtures/transcript.jsonl" '{session_id:"sess-1", transcript_path:$t}' > "$S/team/orchestrator/session.json"
s=$(hub status --json)
assert_eq "an orchestrator whose Claude is gone is stopped" "$(printf '%s' "$s" | jq -r '.projects[] | select(.name=="app") | .orchestrator.state')" "stopped"
assert_eq "...its session" "$(printf '%s' "$s" | jq -r '.projects[] | select(.name=="app") | .orchestrator.session_id')" "sess-1"
assert_eq "...its agents" "$(printf '%s' "$s" | jq -c '[.projects[] | select(.name=="app") | .agents[] | [.name,.state]]')" '[["impl","running"]]'
lv=$(cd "$H/back" && hm-context orchestrator)
assert_eq "...its context level, as hm-context reads it" "$(printf '%s' "$s" | jq -r '.projects[] | select(.name=="app") | .orchestrator | [.context, .context_assumed] | map(tostring) | join(" ")')" "${lv%% *} true"
assert_eq "...an agent with no level carries none" "$(printf '%s' "$s" | jq -r '.projects[] | select(.name=="app") | .agents[0] | has("context")')" "false"
t=$(hub status)
assert_contains "the plain status names the project" "$t" "app"
assert_contains "...and what is stopped" "$t" "stopped"

# ---- wake: a stopped orchestrator is resumed and sent back to its team ----
hub wake two >/dev/null 2>&1; assert_status "wake with no orchestrator recorded" $? 2
wp=$(hub wake app --still 2 --max-wait 15 2>"$T_TMP/wake.err"); assert_status "wake" $? 0
[ ! -s "$T_TMP/wake.err" ] && ok "...nothing on stderr" || bad "stderr: $(cat "$T_TMP/wake.err")"
screen=$(hm_tmux capture-pane -p -J -S - -t "$wp")
assert_contains "...its own conversation" "$screen" "ARGV: --resume"
assert_contains "...that session" "$screen" "ARGV: sess-1"
assert_contains "...under its name" "$screen" "ARGV: app-orchestrator"
assert_contains "...told to register again" "$screen" "hm-spawn --self --agent orchestrator"
assert_contains "...and to report to the hub" "$screen" "send hub one line"
assert_eq "...in the project's tmux session" "$(hm_tmux display-message -p -t "$wp" '#{session_name}')" "app"
assert_eq "...in its home" "$(hm_tmux display-message -p -t "$wp" '#{pane_current_path}')" "$H/back"
hub wake app --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "never woken twice while the first is coming up" $? 4
assert_eq "...status says so" "$(hub status --json | jq -r '.projects[] | select(.name=="app") | .orchestrator.starting.pane')" "$wp"
# once it has registered again it runs: a live process named claude stands in for its Claude (the test shell is not one)
( exec -a claude sleep 30 ) & cp_=$!; disown "$cp_"; t_track "$cp_"; sleep 0.3
jq --arg p "$cp_" --arg s "$(hm_lstart "$cp_")" '(.agents[] | select(.name=="orchestrator")) |= (.claude_pid = $p | .claude_started = $s)' \
  "$S/team.json" > "$S/team.json.t" && mv "$S/team.json.t" "$S/team.json"
assert_eq "a registered orchestrator runs" "$(hub status --json | jq -r '.projects[] | select(.name=="app") | .orchestrator.state')" "running"
hub wake app >/dev/null 2>&1; assert_status "a running orchestrator is not woken" $? 4
hm_tmux kill-pane -t "$wp"   # it has registered: the pane this hub started is no longer what stops a second start

# ---- start: a project with no orchestrator gets one, on a task ----
t2=$(hub task two --text "Write the guide"); assert_eq "a task for the second project" "$t2" "two-1"
hub start two app-2 >/dev/null 2>&1; assert_status "a task of another project" $? 4
hub start two two-9 >/dev/null 2>&1; assert_status "a task nobody asked" $? 2
sp=$(hub start two two-1 --still 2 --max-wait 15 2>"$T_TMP/start.err"); assert_status "start" $? 0
screen=$(hm_tmux capture-pane -p -J -S - -t "$sp")
assert_contains "...a new orchestrator by name" "$screen" "ARGV: two-orchestrator"
assert_contains "...started on the task's file" "$screen" "GOT: /hivemind:start Task two-1: read $P/tasks/two-1.md"
assert_eq "...in its home" "$(hm_tmux display-message -p -t "$sp" '#{pane_current_path}')" "$H/solo"
assert_eq "the task is marked handed" "$(hub tasks --json | jq -r '.[] | select(.id=="two-1") | .state')" "handed"
hub start two two-1 --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "never started twice while the first is coming up" $? 4
hm_tmux kill-pane -t "$sp"; sleep 0.5   # it died before registering (a restart, say): it no longer holds the project
sp2=$(hub start two two-1 --still 2 --max-wait 15 2>/dev/null); assert_status "a start whose pane is gone can be made again" $? 0
[ -n "$sp2" ] && [ "$sp2" != "$sp" ] && ok "...in a new pane" || bad "no new pane: '$sp2'"
hub start app app-2 --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "never started where an orchestrator is recorded" $? 4
hub log two-1 done >/dev/null
hub start two two-1 >/dev/null 2>&1; assert_status "never started on a closed task" $? 4

# ---- the session hook: the hub's folder makes the session the hub, and only that folder ----
hk() { printf '{"cwd":"%s","session_id":"x","source":"%s"}' "$1" "${2:-startup}" | hm-session-hook; }
out=$(hk "$H"); assert_status "hook in the hub's folder" $? 0
assert_contains "...says the session is the hub" "$out" "hivemind:hub"
out=$(hk "$H" clear); assert_contains "...again after a clear" "$out" "hivemind:hub"
out=$(hk "$H/back"); assert_eq "nothing in a project below it" "$out" ""
out=$(hk "$T_TMP"); assert_eq "nothing elsewhere" "$out" ""

# ---- remove ----
hub remove two >/dev/null; assert_status "remove" $? 0
hub remove two >/dev/null 2>&1; assert_status "remove what is not there" $? 2
assert_eq "...the other stays" "$(jq -r '[.projects[].name] | join(",")' "$P/projects.json")" "app"
cd /; t_teardown; t_done
