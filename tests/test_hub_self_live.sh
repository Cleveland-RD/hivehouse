#!/usr/bin/env bash
# R5: a second Claude in the hub's folder never takes the hub over from a live one. hh-hub self refuses (exit 4, naming the live hub) and
# leaves hub.json alone; the session hook tells such a session it is not the hub; a hub whose process is gone, or is no longer that process
# (another start time, or not Claude), is replaced; the hub's own process may record itself again.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
H="$T_TMP/work"; mkdir -p "$H/$T_HUB" "$T_TMP/cl"; HJ="$H/$T_HUB/hub.json"
# Stand-ins for Claude: a bash script named claude (what the ancestor walk reads as one). Each writes its pid to $2, and the rc of what it ran to $2.rc.
#   hold <f> <name>: records itself as the hub twice (the second is the same process), runs the session hook, then stays alive
#   self <f> <name>: tries to record itself as the hub, then ends
#   hook <f>: runs the session hook, then ends
cat > "$T_TMP/cl/claude" <<'CL'
#!/usr/bin/env bash
cd "$H" || exit 9
hook() { printf '{"cwd":"%s","source":"startup"}' "$H" | hh-session-hook > "$1.hook" 2>&1; }
case "$1" in
  hold) hh-hub self --name "$3" >/dev/null 2>"$2.err"; echo $? > "$2.rc"; hh-hub self --name "$3" >/dev/null 2>"$2.err2"; echo $? > "$2.rc2"; hook "$2"; echo $$ > "$2"; sleep 60 ;;
  self) echo $$ > "$2"; hh-hub self --name "$3" >/dev/null 2>"$2.err"; echo $? > "$2.rc" ;;
  hook) echo $$ > "$2"; hook "$2" ;;
esac
CL
chmod +x "$T_TMP/cl/claude"; export H
waitfile() { local i; for i in $(seq 100); do [ -s "$1" ] && return 0; sleep 0.1; done; return 1; }
hubpid() { jq -r .claude_pid "$HJ"; }
start_hold() {  # start_hold <tag> <name>: a live hub; sets HP to its pid
  "$T_TMP/cl/claude" hold "$T_TMP/$1" "$2" & t_track "$!"; waitfile "$T_TMP/$1" || bad "the stand-in $1 did not start"; HP=$(cat "$T_TMP/$1")
}

start_hold a hub1
assert_eq "the first Claude records itself as the hub" "$(hubpid)" "$HP"
assert_eq "...and may record itself again (the same process): exit 0" "$(cat "$T_TMP/a.rc"):$(cat "$T_TMP/a.rc2")" "0:0"
assert_contains "the hub's own session is told it is the hub" "$(cat "$T_TMP/a.hook")" "This session is the owner's hivehouse hub"

echo "-- a second Claude while the hub lives"
"$T_TMP/cl/claude" self "$T_TMP/b" hub2; assert_eq "hh-hub self from it is refused (exit 4)" "$(cat "$T_TMP/b.rc")" "4"
assert_contains "...naming the live hub" "$(cat "$T_TMP/b.err")" "a hub already runs here: hub1 (process $HP)"
assert_eq "...and hub.json still names the first" "$(hubpid):$(jq -r .name "$HJ")" "$HP:hub1"
"$T_TMP/cl/claude" hook "$T_TMP/c"
assert_contains "its session hook says a hub already runs" "$(cat "$T_TMP/c.hook")" "A hub already runs in this folder: hub1 (process $HP)"
case "$(cat "$T_TMP/c.hook")" in *"This session is the owner's hivehouse hub"*) bad "...but it was also told it is the hub" ;; *) ok "...and not told it is the hub" ;; esac

echo "-- a record that is not a live hub is replaced"
kill "$HP" 2>/dev/null; for i in $(seq 50); do kill -0 "$HP" 2>/dev/null || break; sleep 0.1; done
"$T_TMP/cl/claude" self "$T_TMP/d" hub3; assert_eq "once the hub's process is gone, a new Claude takes the hub: exit 0" "$(cat "$T_TMP/d.rc")" "0"
assert_eq "...and hub.json names it" "$(jq -r .name "$HJ")" "hub3"
start_hold e hub4; jq '.claude_started = "Mon Jan  1 00:00:00 2001"' "$HJ" > "$HJ.n" && mv "$HJ.n" "$HJ"
"$T_TMP/cl/claude" self "$T_TMP/f" hub5; assert_eq "a live Claude whose start time is not the recorded one is no hub: replaced" "$(cat "$T_TMP/f.rc"):$(jq -r .name "$HJ")" "0:hub5"
kill "$HP" 2>/dev/null
sleep 30 & SP=$!; t_track "$SP"; jq -nc --arg p "$SP" --arg s "$(hh_lstart "$SP")" '{name:"old",claude_pid:$p,claude_started:$s}' > "$HJ"
"$T_TMP/cl/claude" self "$T_TMP/g" hub6; assert_eq "a live process that is not Claude (a reused pid) is no hub: replaced" "$(cat "$T_TMP/g.rc"):$(jq -r .name "$HJ")" "0:hub6"
echo '{"name":"nopid"}' > "$HJ"
"$T_TMP/cl/claude" self "$T_TMP/h" hub7; assert_eq "a record with no process is replaced" "$(cat "$T_TMP/h.rc"):$(jq -r .name "$HJ")" "0:hub7"
cd /; t_teardown; t_done
