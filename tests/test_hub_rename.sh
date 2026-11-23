#!/usr/bin/env bash
# hh-hub rename <old> <new>: the project's entry and its ledger lines move to the new name, every task id stays as it was, the
# records keyed by the name follow, and the next new task continues the count under the new name. Scratch hub only.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
env -u HIVEHOUSE_HOME tmux -S "$HH_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P); P="$H/$T_HUB"
mk() { local d="$H/$1"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" config user.email t@t; git -C "$d" config user.name t
       echo x > "$d/README"; git -C "$d" add README; git -C "$d" commit -qm init; }
hub() { (cd "$H" && hh-hub "$@"); }
ME=$(id -u); NOW=$(date +%s)
DD="$T_TMP/dg/area"; DF="$DD/delegate"
mkdir -p "$DD"; chmod 755 "$DD" "$T_TMP/dg"
printf "$T_DELEGATE_LINE1"'\nhub=%s\nuntil=%s\nmcp=%s\n' "$H" "$((NOW + 3600))" "" > "$DF"; chmod 644 "$DF"
hub init >/dev/null
for n in alpha beta; do mk "$n"; hub add "$n" --home "$n" >/dev/null; done
bash -c 'cd "$1" && hh-hub self --name hub' _ "$H" >/dev/null 2>&1 || true
for i in 1 2 3; do hub task alpha --text "alpha work $i" >/dev/null; done
hub task beta --text "beta work" >/dev/null
hub log alpha-2 question --note "which one?" >/dev/null; hub log alpha-3 done >/dev/null
echo "notes on alpha" > "$P/memory/alpha.md"; mkdir -p "$P/holds"; : > "$P/holds/alpha"
printf '{"epoch":%s,"action":"wake","item":"alpha"}\n{"epoch":%s,"action":"blocked-restart","item":"alpha/dev"}\n{"epoch":%s,"action":"wake","item":"beta"}\n' "$NOW" "$NOW" "$NOW" > "$P/recovery.jsonl"
printf '{"alpha":{"dev":"running"},"beta":{"dev":"stopped"}}\n' > "$P/recovery-state.json"
printf '{"alpha/dev":{"pid":"1"},"beta/dev":{"pid":"2"}}\n' > "$P/hung-state.json"
pj() { jq -c '.projects' "$P/projects.json"; }
snap() { cp "$P/projects.json" "$T_TMP/pj.saved"; cp "$P/tasks.jsonl" "$T_TMP/tj.saved"; }
unchanged() { cmp -s "$P/projects.json" "$T_TMP/pj.saved" && cmp -s "$P/tasks.jsonl" "$T_TMP/tj.saved" && ok "$1: projects.json and tasks.jsonl untouched" || bad "$1: a record changed after a refusal"; }
snap

# ---- the refusals ----
hub rename alpha >/dev/null 2>&1; assert_status "one name is a usage error" $? 64
hub rename alpha gamma extra >/dev/null 2>&1; assert_status "three names are a usage error" $? 64
hub rename alpha 'Bad Name' >/dev/null 2>&1; assert_status "a new name that fails the name rule is refused" $? 4; unchanged "bad new name"
hub rename nosuch gamma >/dev/null 2>&1; assert_status "a project that does not exist is refused" $? 2; unchanged "unknown project"
hub rename alpha beta >/dev/null 2>&1; assert_status "a new name that is already a project is refused" $? 4; unchanged "name taken"
hub rename alpha alpha >/dev/null 2>&1; assert_status "the same name is refused" $? 4; unchanged "same name"
mkdir -p "$P/memory"; echo stale > "$P/memory/gamma.md"
hub rename alpha gamma >/dev/null 2>&1; assert_status "a leftover note under the new name is refused" $? 4; unchanged "leftover note"
rm -f "$P/memory/gamma.md"
DB=$(t_delegate_bin "$DF")
if (cd "$H" && "$DB/hh-hub" status >/dev/null 2>&1) && [ -n "$(cd "$H" && "$DB/hh-hub" status --json | jq -r '.hub.away // empty')" ]; then
  (cd "$H" && "$DB/hh-hub" rename alpha gamma >/dev/null 2>&1); assert_status "while the owner is away it is refused" $? 4; unchanged "away"
else echo "  SKIP the delegate fixture is not eligible here: the away refusal is not run"; fi
dp=$(hh_open_window alpha orchestrator "$H/alpha" "exec sleep 600" -e "HIVEHOUSE_HOME=$HIVEHOUSE_HOME" -e "HH_TMUX_SOCKET=$HH_TMUX_SOCKET"); sleep 1
di=$(hh_pane_identity "$HH_TMUX_SOCKET" "$dp"); mkdir -p "$P/panes"
jq -nc --arg p "$dp" --arg s "$HH_TMUX_SOCKET" --arg i "${di%%$'\t'*}" --arg t "${di#*$'\t'}" '{pane:$p, socket:$s, pane_pid:$i, pane_started:$t, kind:"wake", line:"x", typed:true, sender_pid:"1", sender_started:"x", at:"2026-10-06T00:00:00Z"}' > "$P/panes/alpha.json"
hub rename alpha gamma >/dev/null 2>&1; assert_status "a pane this hub started for it, still running, is refused" $? 4; unchanged "running pane"
rm -f "$P/panes/alpha.json"
mkdir -p "$P/runs"; jq -nc --arg p "$dp" --arg s "$HH_TMUX_SOCKET" --arg i "${di%%$'\t'*}" --arg t "${di#*$'\t'}" '{pane:$p, socket:$s, pane_pid:$i, pane_started:$t, kind:"overnight", line:"x", typed:false, sender_pid:"1", sender_started:"x", at:"2026-10-06T00:00:00Z"}' > "$P/runs/alpha.json"
hub rename alpha gamma >/dev/null 2>&1; assert_status "a line still being typed into its orchestrator's pane is refused" $? 4; unchanged "running run"
hh_tmux kill-pane -t "$dp"
sleep 30 & lp=$!; t_track $lp
mkdir "$P/lock"; hh_holder_json "$lp" > "$P/lock/holder.json"
hub rename alpha gamma >/dev/null 2>&1; assert_status "rename waits for the hub's lock and gives up" $? 4; unchanged "locked"
rm -rf "$P/lock"; kill $lp; wait $lp 2>/dev/null

# ---- a rename ----
lines=$(wc -l < "$P/tasks.jsonl" | tr -d ' ')
ids_before=$(jq -r '.id' "$P/tasks.jsonl" | tr '\n' ' ')
beta_before=$(jq -c 'select(.project == "beta")' "$P/tasks.jsonl")
# a run record whose pane is gone is stale: the rename removes it
out=$(hub rename alpha gamma); assert_status "rename" $? 0
assert_eq "...prints one line saying what moved" "$out" "renamed alpha to gamma: 5 task records moved (ids unchanged)"
assert_eq "...the project entry has the new name, its home and repos unchanged" "$(jq -c '.projects[] | select(.name == "gamma")' "$P/projects.json")" '{"name":"gamma","home":"alpha","repos":["alpha"]}'
assert_eq "...no project is left under the old name" "$(jq -r '[.projects[].name] | join(",")' "$P/projects.json")" "gamma,beta"
assert_eq "...the ledger has the same number of lines" "$(wc -l < "$P/tasks.jsonl" | tr -d ' ')" "$lines"
assert_eq "...every id is as it was" "$(jq -r '.id' "$P/tasks.jsonl" | tr '\n' ' ')" "$ids_before"
assert_eq "...none of the old project's lines is left" "$(jq -r 'select(.project == "alpha") | .id' "$P/tasks.jsonl" | wc -l | tr -d ' ')" "0"
assert_eq "...its lines carry the new project" "$(jq -r 'select(.project == "gamma") | .id' "$P/tasks.jsonl" | sort -u | tr '\n' ' ')" "alpha-1 alpha-2 alpha-3 "
assert_eq "...the other project's lines are untouched" "$(jq -c 'select(.project == "beta")' "$P/tasks.jsonl")" "$beta_before"
assert_eq "...the other project's entry is untouched" "$(jq -c '.projects[] | select(.name == "beta")' "$P/projects.json")" '{"name":"beta","home":"beta","repos":["beta"]}'
assert_eq "...task files keep their names" "$(ls "$P/tasks" | tr '\n' ' ')" "alpha-1.md alpha-2.md alpha-3.md beta-1.md "
assert_eq "...the hub's notes follow" "$(cat "$P/memory/gamma.md" 2>/dev/null)|$([ -e "$P/memory/alpha.md" ] && echo left)" "notes on alpha|"
assert_eq "...so does the hold" "$([ -f "$P/holds/gamma" ] && echo yes)|$([ -e "$P/holds/alpha" ] && echo left)" "yes|"
assert_eq "...a stale run record is gone" "$([ -e "$P/runs/alpha.json" ] && echo left)" ""
assert_eq "...recovery.jsonl items follow, another project's do not" "$(jq -r '.item' "$P/recovery.jsonl" | tr '\n' ' ')" "gamma gamma/dev beta "
assert_eq "...recovery-state.json is rekeyed" "$(jq -c . "$P/recovery-state.json")" '{"beta":{"dev":"stopped"},"gamma":{"dev":"running"}}'
assert_eq "...so is hung-state.json" "$(jq -c 'keys' "$P/hung-state.json")" '["beta/dev","gamma/dev"]'
ls "$P" | grep -q 'tmp' && bad "a temp file was left in the hub folder" || ok "...no temp file is left"

# ---- what still works after it ----
assert_eq "tasks by the new name lists the old ids" "$(hub tasks gamma | cut -f1 | tr '\n' ' ')" "alpha-1 alpha-2 alpha-3 "
assert_eq "tasks by the old name lists nothing" "$(hub tasks alpha | wc -l | tr -d ' ')" "0"
assert_eq "status by the new name shows 2 open tasks" "$(hub status gamma --json | jq -r '.projects[0].open_tasks')" "2"
hub status alpha >/dev/null 2>&1; assert_status "status by the old name is not found" $? 2
assert_eq "a log by an old id still lands on the new project" "$(hub log alpha-1 note --note hi; jq -r 'select(.id == "alpha-1" and .event == "note") | .project' "$P/tasks.jsonl")" "alpha-1 note
gamma"
nt=$(hub task gamma --text "after the rename"); assert_eq "the next new task takes the next number under the new name" "${nt%%$'\t'*}" "gamma-4"
assert_eq "...and is the new project's" "$(jq -r 'select(.id == "gamma-4") | .project' "$P/tasks.jsonl")" "gamma"
assert_eq "...beta's own count is unaffected" "$(hub task beta --text more | cut -f1)" "beta-2"
assert_eq "an old id's state is read as before" "$(hub tasks gamma | grep '^alpha-2' | cut -f2)" "question"

# ---- and back again ----
hub rename gamma alpha >/dev/null; assert_status "a rename back" $? 0
assert_eq "...the ledger has the old project name and every id again" "$(jq -r 'select(.project == "alpha") | .id' "$P/tasks.jsonl" | sort -u | tr '\n' ' ')" "alpha-1 alpha-2 alpha-3 gamma-4 "
cd /; t_done
