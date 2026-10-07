#!/usr/bin/env bash
# Phase 5: folders added to or dropped from an existing project, and the hub's own name (one per hub folder, so a second
# machine's hub need not also be `hub`).
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P)
mk() { local d="$H/$1"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" config user.email t@t; git -C "$d" config user.name t
       echo x > "$d/README"; git -C "$d" add README; git -C "$d" commit -qm init; }
hub() { (cd "$H" && hm-hub "$@"); }
P="$H/.hivemind-hub"
repos() { jq -c ".projects[] | select(.name == \"$1\") | .repos" "$P/projects.json"; }
hub init >/dev/null
mk back; mk front; mk extra; mk solo; mkdir -p "$H/notes"
hub add app --home back --repo front >/dev/null; hub add other --home solo >/dev/null

# ---- add a folder to an existing project ----
before=$(cat "$P/projects.json")
assert_eq "add --repo to an existing project prints its name" "$(hub add app --repo extra)" "app"
assert_eq "...the folder joins its folders" "$(repos app)" '["back","front","extra"]'
assert_eq "...the home is unchanged" "$(jq -r '.projects[] | select(.name == "app") | .home' "$P/projects.json")" "back"
assert_eq "...the other project is unchanged" "$(repos other)" '["solo"]'
hub add app --repo notes --repo extra >/dev/null; assert_status "several at once, one already there" $? 0
assert_eq "...each joins once" "$(repos app)" '["back","front","extra","notes"]'
hub add app --repo extra >/dev/null; assert_status "a folder the project already has: nothing to do" $? 0
assert_eq "...and nothing changed" "$(repos app)" '["back","front","extra","notes"]'
cp "$P/projects.json" "$T_TMP/pj.saved"
hub add app --repo solo >/dev/null 2>&1; assert_status "a folder another project owns is refused" $? 4
cmp -s "$P/projects.json" "$T_TMP/pj.saved" && ok "...and projects.json is untouched" || bad "projects.json changed after a refusal"
mkdir "$H/fresh"; hub add app --repo fresh --repo solo >/dev/null 2>&1; assert_status "one bad folder refuses the whole call" $? 4
assert_eq "...so the good one did not join either" "$(repos app)" '["back","front","extra","notes"]'
hub add app --repo gone >/dev/null 2>&1; assert_status "a folder that does not exist is refused" $? 4
hub add nosuch --repo fresh >/dev/null 2>&1; assert_status "a project that does not exist is not made by --repo alone" $? 2
hub add app >/dev/null 2>&1; assert_status "a project with nothing to add is a usage error" $? 64
hub add app --home fresh --repo notes >/dev/null 2>&1; assert_status "--home for a project that exists is still refused" $? 4
# ---- the lock: add and drop run under the hub's one lock ----
sleep 30 & lp=$!; t_track $lp
mkdir "$P/lock"; hm_holder_json "$lp" > "$P/lock/holder.json"
hub add app --repo fresh >/dev/null 2>&1; assert_status "add waits for the hub's lock and gives up" $? 4
hub drop app extra >/dev/null 2>&1; assert_status "drop waits for the hub's lock and gives up" $? 4
assert_eq "...nothing changed" "$(repos app)" '["back","front","extra","notes"]'
rm -rf "$P/lock"; kill $lp; wait $lp 2>/dev/null

# ---- drop a folder ----
hub task app --text "a task" >/dev/null; echo "kept" > "$P/memory/app.md"
tasks_before=$(cat "$P/tasks.jsonl"); ls "$P/tasks" > "$T_TMP/tasks.before"
assert_eq "drop prints the project's name" "$(hub drop app extra)" "app"
assert_eq "...the folder is gone from the project" "$(repos app)" '["back","front","notes"]'
assert_eq "...tasks and memory are untouched" "$(cat "$P/tasks.jsonl")|$(ls "$P/tasks" | diff - "$T_TMP/tasks.before" | wc -l | tr -d ' ')|$(cat "$P/memory/app.md")" "$tasks_before|0|kept"
[ -d "$H/extra/.git" ] && ok "...and the folder itself is untouched" || bad "the dropped folder was touched"
hub drop app back >/dev/null 2>&1; assert_status "the home is never dropped" $? 4
assert_eq "...it is still there" "$(repos app)" '["back","front","notes"]'
hub drop app extra >/dev/null 2>&1; assert_status "a folder the project does not have" $? 4
hub drop app solo >/dev/null 2>&1; assert_status "...nor one that belongs to another project" $? 4
hub drop nosuch front >/dev/null 2>&1; assert_status "a project that does not exist" $? 2
hub drop app >/dev/null 2>&1; assert_status "drop without a folder is a usage error" $? 64
hub drop app front notes >/dev/null 2>&1; assert_status "one folder at a time" $? 64
rm -rf "$H/notes"; assert_eq "a folder that no longer exists can still be dropped" "$(hub drop app notes)" "app"
assert_eq "...and is gone" "$(repos app)" '["back","front"]'
hub add app --repo front >/dev/null; assert_eq "a dropped folder can be added back; a kept one stays once" "$(repos app)" '["back","front"]'
hub drop app front >/dev/null; hub add other --repo front >/dev/null; assert_status "a dropped folder can join another project" $? 0
assert_eq "...there" "$(repos other)" '["solo","front"]'

# ---- the records stay at most 755/644 (a hub made group-writable is put right by the next write) ----
mode() { stat -f %Lp "$1"; }
mkdir "$H/notes2"
chmod 664 "$P/projects.json"; chmod 775 "$P"; hub add app --repo notes2 >/dev/null
assert_eq "add --repo seals the hub's records" "$(mode "$P/projects.json") $(mode "$P")" "644 755"
chmod 664 "$P/projects.json"; chmod 775 "$P"; hub drop app notes2 >/dev/null
assert_eq "drop seals the hub's records" "$(mode "$P/projects.json") $(mode "$P")" "644 755"
chmod 775 "$P"; hub name keepme >/dev/null
assert_eq "name seals the hub's folder" "$(mode "$P")" "755"; rm -f "$P/name"

# ---- the hub's name ----
live() {  # live <name> <cwd>: a running process named claude, with Claude Code's record of it
  ( exec -a claude sleep 60 ) >/dev/null 2>&1 & local p=$!; disown "$p"; t_track "$p"; sleep 0.2
  mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
  jq -nc --argjson p "$p" --arg n "$1" --arg c "$2" '{pid:$p, name:$n, cwd:$c, tmux:"work:@3.%77", kind:"interactive"}' > "$CLAUDE_CONFIG_DIR/sessions/$p.json"
  echo "$p"
}
mine=$(live "Read the docs" "$H"); jq '.sessionId = "sess-hub" | .nameSource = "auto"' "$CLAUDE_CONFIG_DIR/sessions/$mine.json" > "$T_TMP/m.json" && mv "$T_TMP/m.json" "$CLAUDE_CONFIG_DIR/sessions/$mine.json"
assert_eq "no name file: the default name is hub" "$(hub name)" "hub"
assert_eq "...and naming offers hub" "$(hub naming --session sess-hub | jq -r .free)" "hub"
assert_eq "name <name> prints it" "$(hub name studio)" "studio"
assert_eq "...it is kept in the hub's own folder" "$(cat "$P/name")" "studio"
assert_eq "...name with no argument shows it" "$(hub name)" "studio"
assert_eq "naming starts from the hub's name" "$(hub naming --session sess-hub | jq -r .free)" "studio"
other=$(live studio "$T_TMP")
assert_eq "...and counts up from it when a session has it" "$(hub naming --session sess-hub | jq -r .free)" "studio-2"
kill "$other" 2>/dev/null; sleep 0.3
hub name 'Bad Name' >/dev/null 2>&1; assert_status "a name with capitals and a space is refused" $? 4
hub name 'x;y' >/dev/null 2>&1; assert_status "a name with a shell character is refused" $? 4
hub name a b >/dev/null 2>&1; assert_status "two names are a usage error" $? 64
assert_eq "...a refused name leaves the file alone" "$(cat "$P/name")" "studio"
printf 'x;y\n' > "$P/name"; hub naming --session sess-hub >/dev/null 2>&1; assert_status "naming refuses a name file with a bad value" $? 4
printf '\n' > "$P/name"; hub naming --session sess-hub >/dev/null 2>&1; assert_status "...an empty one too" $? 4
rm -f "$P/name"; assert_eq "...and without the file it is hub again" "$(hub naming --session sess-hub | jq -r .free)" "hub"
kill "$mine" 2>/dev/null
# ---- the hub skill names the commands and the clash check ----
S="$HM_REPO_ROOT/skills/hub/SKILL.md"
grep -q 'hm-hub drop' "$S" && grep -q 'hm-hub add <project> --repo <folder>`' "$S" && ok "the hub skill names add --repo and drop" || bad "the hub skill does not name add --repo and drop"
grep -q 'run `ListAgents`' "$S" && grep -q 'hm-hub name <name>' "$S" && ok "the hub skill names the ListAgents name check and hm-hub name" || bad "the hub skill does not name the name check"
for f in skills/hub/SKILL.md README.md; do
  tr '\n' ' ' < "$HM_REPO_ROOT/$f" | tr -s ' ' | grep -q 'other machines only while Remote Control is connected' && ok "$f: other machines show only with Remote Control" || bad "$f does not say it sees other machines only while Remote Control is connected"
done
cd /; t_done
