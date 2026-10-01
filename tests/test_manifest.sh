#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
t_setup
r=$(t_repo proj); cd "$r"
id=$(hm-manifest add dir path="$T_TMP/scratch"); assert_status "add dir" $? 0
assert_eq "one entry" "$(hm-manifest list | wc -l | tr -d ' ')" "1"
assert_eq "kind recorded" "$(hm-manifest list | jq -r .kind)" "dir"
assert_eq "path recorded resolved" "$(hm-manifest list | jq -r .path)" "$T_TMP/scratch"
hm-manifest add dir path=relative 2>/dev/null; assert_status "refuses relative path" $? 4
hm-manifest add dir path="$HOME" 2>/dev/null; assert_status "refuses HOME" $? 4
hm-manifest add dir path="$r" 2>/dev/null; assert_status "refuses project root" $? 4
hm-manifest add dir path="$T_TMP/x" command="rm -rf /" 2>/dev/null; assert_status "refuses a command field" $? 4
hm-manifest add bogus path=/x 2>/dev/null; assert_status "refuses unknown kind" $? 4
hm-manifest add dir path="$T_TMP/nl
x" 2>/dev/null; assert_status "refuses a newline" $? 4
hm-manifest add dir "$T_TMP/x" 2>/dev/null; assert_status "refuses an argument without =" $? 4
hm-manifest add tmux socket="$T_TMP/s" pane=bad agent=a 2>/dev/null; assert_status "refuses a bad pane id" $? 4
hm-manifest add process pid=abc 2>/dev/null; assert_status "refuses a non-numeric pid" $? 4
hm-manifest add remote host=-oProxyCommand=x path=/home/u/x/y 2>/dev/null; assert_status "refuses an option-like host" $? 4
sleep 300 & p=$!
hm-manifest add process pid=$p port=3002 >/dev/null
line=$(hm-manifest list --kind process)
assert_contains "process start time captured" "$line" '"started":'
assert_contains "process command captured" "$line" 'sleep 300'
assert_eq "process group captured" "$(printf '%s' "$line" | jq -r .pgid)" "$(ps -o pgid= -p $p | tr -d ' ')"
kill $p; wait $p 2>/dev/null
hm-manifest add process pid=$p 2>/dev/null; assert_status "refuses a dead pid" $? 4
hm-manifest drop "$id"; assert_eq "drop removes" "$(hm-manifest list --kind dir | wc -l | tr -d ' ')" "0"
hm-manifest drop nosuchid 2>/dev/null; assert_status "drop of an unknown id is refused" $? 4

# A5: path safety
hm-manifest add dir path="$T_TMP" 2>/dev/null; assert_status "refuses the project's parent" $? 4
hm-manifest add dir path=/tmp 2>/dev/null; assert_status "refuses /tmp" $? 4
# the refusal's reason, not only its status: on macOS /private/tmp is root-owned and /tmp is a symlink, so either would
# refuse these paths on its own and hide a dropped entry in the protected list
out=$(hm-manifest add dir path=/private/tmp 2>&1); assert_contains "/private/tmp is refused as a protected directory" "$out" "protected directory"
mkdir "$T_TMP/tmpd"; TMPDIR="$T_TMP/tmpd" hm-manifest add dir path="$T_TMP/tmpd" 2>/dev/null; assert_status "refuses TMPDIR itself" $? 4
hm-manifest add dir path="$HOME//" 2>/dev/null; assert_status "refuses HOME with trailing slashes" $? 4
hm-manifest add dir path="/tmp/..$HOME" 2>/dev/null; assert_status "refuses a .. segment" $? 4
mkdir -p "$T_TMP/scratch"; hm-manifest add dir path="$T_TMP/scratch/../harmless" 2>/dev/null; assert_status "refuses a .. segment even when harmless" $? 4
hm-manifest add dir path="$T_TMP/d1" path="$T_TMP/d2" 2>/dev/null; assert_status "refuses a field given twice" $? 4
mkdir "$T_TMP/elsewhere"; ln -s "$T_TMP/elsewhere" "$T_TMP/link"
hm-manifest add dir path="$T_TMP/link" 2>/dev/null; assert_status "refuses a symlink" $? 4
hm-manifest add file path=/etc/hosts 2>/dev/null; assert_status "refuses a file not owned by the caller" $? 4
hm-manifest add dir path="$T_TMP/no/such/parent" 2>/dev/null; assert_status "refuses a path whose parent is missing" $? 4

# A18: inside the project root or a recorded worktree
mkdir "$r/src"; hm-manifest add file path="$r/src/x" 2>/dev/null; assert_status "refuses a file inside the project" $? 4
mkdir -p "$r/.hivemind/tmp"; hm-manifest add file path="$r/.hivemind/tmp/a" >/dev/null; assert_status "allows .hivemind/tmp" $? 0
hm-manifest add file path="$r/.hivemind/other" 2>/dev/null; assert_status "refuses the rest of .hivemind" $? 4
hm-manifest add worktree path="$T_TMP/wt1" base=main >/dev/null; assert_status "add worktree" $? 0
mkdir "$T_TMP/wt1"; hm-manifest add dir path="$T_TMP/wt1/sub" 2>/dev/null; assert_status "refuses a dir inside a recorded worktree" $? 4
hm-manifest add dir path="$T_TMP/wt1" 2>/dev/null; assert_status "refuses the worktree path itself as a dir" $? 4
hm-manifest add worktree path="$T_TMP/wt2" base=-x 2>/dev/null; assert_status "refuses an option-like base" $? 4

# A14: concurrent writers all land, under the lock
before=$(hm-manifest list | wc -l | tr -d ' ')
for i in 1 2 3 4 5 6 7 8 9 10; do hm-manifest add dir path="$T_TMP/c$i" >/dev/null & done; wait
assert_eq "10 concurrent adds all land" "$(( $(hm-manifest list | wc -l | tr -d ' ') - before ))" "10"
assert_eq "ids are distinct" "$(hm-manifest list | jq -r .id | sort -u | wc -l | tr -d ' ')" "$(hm-manifest list | wc -l | tr -d ' ')"
hm-manifest list | jq -e . >/dev/null; assert_status "every line is valid json" $? 0

# lock: stale holders are taken over, live ones are respected
L="$r/.hivemind/manifest.lock"
sleep 300 & live=$!; ls=$(ps -o lstart= -p $live | sed 's/^ *//;s/ *$//')
mkdir "$L"; jq -nc --argjson pid "$live" --arg l "$ls" '{pid:$pid,lstart:$l,created:0}' > "$L/holder.json"
HM_LOCK_WAIT_S=1 hm-manifest add dir path="$T_TMP/l1" 2>/dev/null; assert_status "a live holder blocks" $? 75
jq -nc --argjson pid "$live" '{pid:$pid,lstart:"Mon Jan  1 00:00:00 2001",created:0}' > "$L/holder.json"
hm-manifest add dir path="$T_TMP/l2" >/dev/null; assert_status "a live pid with another start time is stale (pid reuse)" $? 0
rm -rf "$L"; mkdir "$L"; jq -nc --argjson pid "$live" --arg l "$ls" '{pid:$pid,lstart:$l,created:0}' > "$L/holder.json"
kill $live; wait $live 2>/dev/null   # dead now, and its recorded start time still matches what it was
hm-manifest add dir path="$T_TMP/l3" >/dev/null; assert_status "a dead holder is stale" $? 0
mkdir "$L"; jq -nc --argjson pid "$live" '{pid:$pid,lstart:"",created:0}' > "$L/holder.json"
hm-manifest add dir path="$T_TMP/l3b" >/dev/null; assert_status "a dead holder with no recorded start time is stale" $? 0
mkdir "$L"; HM_LOCK_WAIT_S=1 hm-manifest add dir path="$T_TMP/l4" 2>/dev/null; assert_status "an empty fresh lock is busy" $? 75
touch -t 202001010000 "$L"; hm-manifest add dir path="$T_TMP/l4" >/dev/null; assert_status "an empty old lock is stale" $? 0
[ -e "$L" ] && bad "the lock is released after a write" || ok "the lock is released after a write"

# A1: outside any repo and with no HM_PROJECT: exit 2, nothing written
mkdir "$T_TMP/norepo"; cd "$T_TMP/norepo"
for c in "add dir path=$T_TMP/z" "list" "drop x"; do hm-manifest $c 2>/dev/null; assert_status "outside a repo: $c" $? 2; done
[ ! -e "$T_TMP/norepo/.hivemind" ] && [ ! -e /.hivemind ] && [ -z "$(find "$HIVEMIND_HOME" -type f)" ] && ok "nothing written outside a repo" || bad "nothing written outside a repo"
cd /; t_teardown; t_done
