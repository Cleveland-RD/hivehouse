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
idof() { printf '%s' "${1%%$'\t'*}"; }   # hm-hub task prints "<id><TAB><task file>"
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
bash "$T_TMP/cl/claude" --name 'my hub' >/dev/null 2>&1; assert_status "a hub name is one word: orchestrators are told to type it" $? 4
assert_eq "...the record stays" "$(jq -r .name "$P/hub.json")" "hub"

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
hub wake app --model opus >/dev/null 2>&1; assert_status "a resumed session keeps its own model" $? 64
hub wake app --mode bypassPermissions >/dev/null 2>&1; assert_status "never in bypass" $? 4
wp=$(hub wake app --mode auto --still 2 --max-wait 15 2>"$T_TMP/wake.err"); assert_status "wake" $? 0
[ ! -s "$T_TMP/wake.err" ] && ok "...nothing on stderr" || bad "stderr: $(cat "$T_TMP/wake.err")"
screen=$(hm_tmux capture-pane -p -J -S - -t "$wp")
assert_contains "...its own conversation" "$screen" "ARGV: --resume"
assert_contains "...that session" "$screen" "ARGV: sess-1"
assert_contains "...under its name" "$screen" "ARGV: app-orchestrator"
assert_contains "...in the hub's permission mode" "$screen" "ARGV: --permission-mode"
case "$screen" in *"ARGV: --model"*) bad "a model was forced on the resumed session" ;; *) ok "...with its own model" ;; esac
assert_contains "...and told it works through the hub, which survives a rotation" "$screen" "--hub hub"
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
t2=$(hub task two --text "Write the guide"); assert_eq "a task for the second project" "$(idof "$t2")" "two-1"
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

# ---- an orchestrator already running outside hivemind is found, never doubled ----
# Claude Code keeps a record of every running session (<config>/sessions/<pid>.json: its name, folder and tmux pane)
mk tri; hub add tri --home tri >/dev/null; t3=$(idof "$(hub task tri --text "Fix it")")
live() {  # live <name> <cwd>: a running process named claude, with Claude Code's record of it
  ( exec -a claude sleep 60 ) >/dev/null 2>&1 & local p=$!; disown "$p"; t_track "$p"; sleep 0.2   # its output never holds the \$(...)
  mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
  jq -nc --argjson p "$p" --arg n "$1" --arg c "$2" '{pid:$p, name:$n, cwd:$c, tmux:"work:@3.%77", kind:"interactive"}' > "$CLAUDE_CONFIG_DIR/sessions/$p.json"
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
assert_eq "a running orchestrator hivemind never registered is found" "$(printf '%s' "$s" | jq -r '.projects[0].orchestrator.state')" "unregistered"
assert_eq "...by its name, process and pane" "$(printf '%s' "$s" | jq -r '.projects[0].orchestrator | [.name, .pid, .pane] | map(tostring) | join(" ")')" "tri-orchestrator $lp %77"
hub start tri "$t3" --still 2 --max-wait 15 >/dev/null 2>"$T_TMP/tri.err"; assert_status "...and never started a second time" $? 4
assert_contains "...the refusal says how it joins" "$(cat "$T_TMP/tri.err")" "hm-spawn --self"
assert_contains "the plain status says so" "$(hub status tri)" "not registered"
kill "$lp" 2>/dev/null; sleep 0.3
assert_eq "...gone once it ends" "$(hub status tri --json | jq -r '.projects[0].orchestrator.state')" "none"

# ---- a start stopped at a question: shown, kept, and continued once the owner answers ----
# the project's own settings make the owner's mode stricter, never looser (hm-settings): the orchestrator gets the result
mkdir -p "$H/tri/.hivemind"; echo '{"permission_mode":"plan"}' > "$H/tri/.hivemind/settings.json"
hm_tmux set-environment -g HM_FAKE_CLAUDE dialoganswer
qp=$(hub start tri "$t3" --mode auto --still 2 --max-wait 30 2>"$T_TMP/q.err"); assert_status "a question stops the start" $? 5
assert_contains "...and says how to go on" "$(cat "$T_TMP/q.err")" "hm-hub continue tri"
hm_tmux set-environment -g -u HM_FAKE_CLAUDE
st=$(hub status tri --json | jq -c '.projects[0].orchestrator.starting')
assert_eq "...status shows it waiting on the owner" "$(printf '%s' "$st" | jq -r '[.typed, .question] | map(tostring) | join(" ")')" "false true"
qp=$(printf '%s' "$st" | jq -r .pane)
assert_contains "...in the mode the project allows" "$(hm_tmux capture-pane -p -J -S - -t "$(hub status tri --json | jq -r '.projects[0].orchestrator.starting.pane')")" "ARGV: plan"
hub start tri "$t3" --still 2 --max-wait 15 >/dev/null 2>"$T_TMP/q2.err"; assert_status "...never started again" $? 4
assert_contains "...it points at continue" "$(cat "$T_TMP/q2.err")" "hm-hub continue tri"
hub continue tri --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "continue while the question is still there" $? 5
hm_tmux send-keys -t "$qp" 1 Enter; sleep 0.5   # the owner answers it
cp2=$(hub continue tri --still 2 --max-wait 15 2>"$T_TMP/c.err"); assert_status "continue" $? 0
assert_eq "...in the same pane" "$cp2" "$qp"
assert_contains "...the start's line is typed" "$(hm_tmux capture-pane -p -J -S - -t "$qp")" "GOT: /hivemind:start Task $t3: read $P/tasks/$t3.md"
assert_eq "...the task is handed" "$(hub tasks --json | jq -r --arg i "$t3" '.[] | select(.id==$i) | .state')" "handed"
hub continue tri --still 2 --max-wait 15 >/dev/null 2>&1; assert_status "nothing left to continue" $? 4
hub continue app >/dev/null 2>&1; assert_status "continue where this hub started nothing" $? 2

# ---- a start still being sent is coming up, not waiting on the owner, and continue never sends its line twice ----
mk five; hub add five --home five >/dev/null; t5=$(idof "$(hub task five --text "Ship it")")
( cd "$H" && hm-hub start five "$t5" --still 6 --max-wait 30 >"$T_TMP/five.out" 2>&1; echo "rc=$?" >> "$T_TMP/five.out" ) &
fs=$!; t_track "$fs"; sleep 3
st=$(hub status five --json | jq -c '.projects[0].orchestrator.starting')
assert_eq "while its line is on the way it is being sent, not waiting" "$(printf '%s' "$st" | jq -r '[.typed, .sending] | map(tostring) | join(" ")')" "false true"
case "$(hub status five)" in *"hm-hub continue"*) bad "the plain status offers continue for a start still being sent" ;; *) ok "...the plain status offers no continue" ;; esac
hub continue five --still 1 --max-wait 5 >/dev/null 2>"$T_TMP/c5.err"; assert_status "...and continue refuses it" $? 4
wait "$fs"
assert_contains "the start itself finished" "$(cat "$T_TMP/five.out")" "rc=0"
fp=$(head -1 "$T_TMP/five.out")
assert_eq "...its line typed once" "$(hm_tmux capture-pane -p -J -S - -t "$fp" | grep -c "GOT: /hivemind:start Task $t5")" "1"
assert_eq "...and handed once" "$(jq -r --arg i "$t5" 'select(.id == $i and .event == "handed") | .id' "$P/tasks.jsonl" | grep -c .)" "1"

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
hm_tmux set-environment -g HM_FAKE_CLAUDE dialog
(cd "$H/back" && hm-spawn --agent dlg --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 6 >/dev/null 2>&1)
hm_tmux set-environment -g -u HM_FAKE_CLAUDE
s=$(hub status app --json)
assert_eq "an agent with a question on its screen" "$(printf '%s' "$s" | jq -r '.projects[0].agents[] | select(.name=="dlg") | .question')" "true"
assert_eq "...one without has none" "$(printf '%s' "$s" | jq -r '.projects[0].agents[] | select(.name=="impl") | .question')" "false"
assert_contains "the plain status says so" "$(hub status app)" "question"

# ---- the words orchestrators and the hub exchange: declared once in hm-hub, held to both skills ----
for v in HUB_REPLIES HUB_ASKS; do
  words=$(sed -n "s/^$v=\"\(.*\)\"$/\1/p" "$HM_REPO_ROOT/bin/hm-hub")
  [ -n "$words" ] && ok "$v is declared" || bad "$v is not declared in bin/hm-hub"
  for w in $words; do
    for sk in hub start; do
      grep -q -- "$w" "$HM_REPO_ROOT/skills/$sk/SKILL.md" && ok "$w is in the $sk skill" || bad "$w ($v) is missing from skills/$sk/SKILL.md"
    done
  done
done

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
assert_eq "...the others stay" "$(jq -r '[.projects[].name] | join(",")' "$P/projects.json")" "app,tri,five"
cd /; t_teardown; t_done
