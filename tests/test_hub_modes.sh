#!/usr/bin/env bash
# The modes of the hub's records. hh-hub runs with umask 022 and takes group and others' write off .hivehouse-hub/, so a hub made under
# umask 002 (775 / 664, the default where every user has their own group) is not left in a state the delegate check refuses. `hh-hub away`
# checks the hub's records and each project home first, and prints no sudo line for a hub that would be refused unseen.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
H="$T_TMP/work"; mkdir -p "$H"; H=$(cd "$H" && pwd -P); P="$H/$T_HUB"
hub() { (cd "$H" && hh-hub "$@"); }
mk() { local d="$H/$1"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" config user.email t@t; git -C "$d" config user.name t
       echo x > "$d/README"; git -C "$d" add README; git -C "$d" commit -qm init; }
mode() { /usr/bin/stat -f '%Lp' "$1" 2>/dev/null || /usr/bin/stat -c '%a' "$1"; }
mkdir -p "$T_TMP/cl"; printf '#!/usr/bin/env bash\ncd "%s" && hh-hub self "$@"\n' "$H" > "$T_TMP/cl/claude"
chmod 755 "$H"; mk alpha; mk beta

# ---- under umask 002 the hub is still made at 755 and 644 ----
( umask 002; cd "$H" && hh-hub init >/dev/null ); assert_status "init under umask 002" $? 0
assert_eq "...the folder is 755" "$(mode "$P")" "755"
assert_eq "...projects.json is 644" "$(mode "$P/projects.json")" "644"
assert_eq "...a folder inside it too" "$(mode "$P/memory")" "755"
( umask 002; cd "$H" && hh-hub add alpha --home alpha >/dev/null ); assert_status "add under umask 002" $? 0
assert_eq "...projects.json stays 644 after the rewrite" "$(mode "$P/projects.json")" "644"
( umask 002; bash "$T_TMP/cl/claude" --name hub >/dev/null ); assert_status "self under umask 002" $? 0
assert_eq "...hub.json is 644" "$(mode "$P/hub.json")" "644"
( umask 002; cd "$H" && hh-hub remove alpha >/dev/null; hh-hub add alpha --home alpha >/dev/null )
assert_eq "...and after remove and add" "$(mode "$P/projects.json")" "644"

# ---- a hub made group-writable beforehand is put right by the next add ----
mkdir -p "$P/holds" "$P/decisions"; : > "$P/holds/alpha"; : > "$P/decisions/x.md"
chmod -R g+w "$P"; chmod g+w "$P/tasks.jsonl"
assert_eq "(group-writable now: the folder)" "$(mode "$P")" "775"
hub add beta --home beta >/dev/null; assert_status "add" $? 0
assert_eq "...the folder is 755 again" "$(mode "$P")" "755"
assert_eq "...projects.json" "$(mode "$P/projects.json")" "644"
assert_eq "...tasks.jsonl, which add does not write" "$(mode "$P/tasks.jsonl")" "644"
assert_eq "...holds/" "$(mode "$P/holds")" "755"
assert_eq "...and a file inside holds/" "$(mode "$P/holds/alpha")" "644"
assert_eq "...decisions/" "$(mode "$P/decisions/x.md")" "644"
assert_eq "...hub.json too" "$(mode "$P/hub.json")" "644"

# ---- what hh-hub writes between seals is at most 644 too: umask 022 ----
( umask 002; cd "$H" && hh-hub task alpha --text x >/dev/null ); assert_status "a task under umask 002" $? 0
assert_eq "...its task file is 644" "$(mode "$P/tasks/alpha-1.md")" "644"
assert_eq "...and the ledger" "$(mode "$P/tasks.jsonl")" "644"

# ---- away checks the records first ----
chmod 664 "$P/projects.json"
out=$(hub away --until +1h 2>"$T_TMP/away.err"); rc=$?
assert_status "away with a group-writable projects.json is refused" $rc 4
case "$out" in *sudo*) bad "away printed a sudo line for a hub that would be refused" ;; *) ok "...and prints no sudo line" ;; esac
assert_contains "...the reason is named" "$(cat "$T_TMP/away.err")$out" "$P/projects.json is writable by group or others"
assert_contains "...with the line that fixes it, which needs no sudo" "$(cat "$T_TMP/away.err")$out" "chmod -- go-w $P/projects.json"
t_run_printed "$(printf '%s\n' "$(cat "$T_TMP/away.err")$out" | grep '^chmod ')"; assert_status "...and that line runs (BSD chmod reads a -- after the mode as a file)" $? 0
chmod 644 "$P/projects.json"
chmod 775 "$H/alpha"
out=$(hub away --until +1h 2>"$T_TMP/away.err"); rc=$?
assert_status "a group-writable project home is refused too" $rc 4
case "$out" in *sudo*) bad "a sudo line was printed for a group-writable home" ;; *) ok "...no sudo line" ;; esac
assert_contains "...the home is named, with its fix" "$(cat "$T_TMP/away.err")$out" "chmod -- go-w $H/alpha"
t_run_printed "$(printf '%s\n' "$(cat "$T_TMP/away.err")$out" | grep '^chmod ')"; assert_status "...and that line runs (BSD chmod reads a -- after the mode as a file)" $? 0
chmod 755 "$H/alpha"
# a team root in a worktree of a listed home is checked as the bypass check checks it, so a group-writable one is refused here, seen, with its fix
git -C "$H/alpha" worktree add -q "$H/alpha-wt" -b wt; mkdir -p "$H/alpha-wt/$T_STATE"; echo '{"agents":[]}' > "$H/alpha-wt/$T_STATE/team.json"
git -C "$H/alpha" worktree add -q "$H/alpha-plain" -b plain
chmod 775 "$H/alpha-plain"
out=$(hub away --until +1h 2>"$T_TMP/away.err"); rc=$?
assert_status "a group-writable worktree that holds no team is no team root: not refused" $rc 0
chmod 755 "$H/alpha-plain"
chmod 775 "$H/alpha-wt"
out=$(hub away --until +1h 2>"$T_TMP/away.err"); rc=$?
assert_status "a group-writable worktree team root of a listed home is refused" $rc 4
case "$out" in *sudo*) bad "a sudo line was printed for a group-writable team root" ;; *) ok "...no sudo line" ;; esac
assert_contains "...the team root is named, with its fix" "$(cat "$T_TMP/away.err")$out" "chmod -- go-w $H/alpha-wt"
chmod 755 "$H/alpha-wt"
out=$(hub away --until +1h 2>/dev/null); assert_status "...and once it is put right, away prints its lines" $? 0
rm -f "$P/away.json"
# a home owned by root is refused too (strict, not "or root"), and no chmod line is offered for what this user does not own
cp "$P/projects.json" "$T_TMP/projects.saved"
jq '.projects += [{name:"sys",home:"/usr",repos:[]}]' "$T_TMP/projects.saved" > "$P/projects.json"
out=$(hub away --until +1h 2>"$T_TMP/away.err"); rc=$?
assert_status "a project home owned by root is refused" $rc 4
assert_contains "...with the owner reason" "$(cat "$T_TMP/away.err")$out" "/usr is owned by uid 0"
gw=$(find /Applications /Library /usr/local /var -maxdepth 0 -type d -perm -g+w -user root 2>/dev/null | head -1)
if [ -n "$gw" ]; then
  jq --arg h "$gw" '.projects += [{name:"sys",home:$h,repos:[]}]' "$T_TMP/projects.saved" > "$P/projects.json"
  out=$(hub away --until +1h 2>"$T_TMP/away.err")
  assert_contains "a root-owned home the group can write is refused, for its owner" "$out" "$gw is owned by uid 0"
  case "$out" in *"chmod -- go-w $gw"*) bad "a chmod line for a folder this user does not own" ;; *) ok "...with no chmod line: it is not this user's to change" ;; esac
else echo "  SKIP no root-owned, group-writable folder to use as a home here"; fi
cp "$T_TMP/projects.saved" "$P/projects.json"; chmod 644 "$P/projects.json"
chmod 775 "$H"
out=$(hub away --until +1h 2>"$T_TMP/away.err"); rc=$?
assert_status "a group-writable hub folder is refused" $rc 4
assert_contains "...named with its fix" "$(cat "$T_TMP/away.err")$out" "chmod -- go-w $H"
t_run_printed "$(printf '%s\n' "$(cat "$T_TMP/away.err")$out" | grep '^chmod ')"; assert_status "...and that line runs (BSD chmod reads a -- after the mode as a file)" $? 0
chmod 755 "$H"
rm "$P/hub.json"
out=$(hub away --until +1h 2>"$T_TMP/away.err"); rc=$?
assert_status "a hub that has not recorded itself is refused" $rc 4
assert_contains "...says hub.json is missing" "$(cat "$T_TMP/away.err")$out" "hub.json cannot be read"
case "$(cat "$T_TMP/away.err")$out" in *"chmod -- go-w $P/hub.json"*) bad "a chmod line for a file that is not there" ;; *) ok "...with no chmod line, since there is nothing to change" ;; esac
bash "$T_TMP/cl/claude" --name hub >/dev/null
chmod -R g+w "$P/holds" "$P/decisions"; chmod g+w "$P/tasks.jsonl"
out=$(hub away --until +1h 2>/dev/null); assert_status "a complete hub: away prints its lines" $? 0
assert_contains "...with sudo lines" "$out" "sudo tee -- "
assert_eq "...and puts the records it does not check right: tasks.jsonl" "$(mode "$P/tasks.jsonl")" "644"
assert_eq "...holds/" "$(mode "$P/holds")" "755"
assert_eq "...decisions/" "$(mode "$P/decisions")" "755"
# with no root-owned jq the delegate check cannot read anything, so away says that, before it seals or prints a line
NJ=$(t_jq_bin nojq "/nonexistent/jq")
chmod -R g+w "$P/holds"
out=$(cd "$H" && "$NJ/hh-hub" away --until +1h 2>"$T_TMP/nj.err"); rc=$?
assert_status "away with no root-owned jq is refused" $rc 4
assert_contains "...naming the real cause" "$(cat "$T_TMP/nj.err")" "no root-owned jq"
case "$out" in *sudo*) bad "a sudo line was printed with no root-owned jq" ;; *) ok "...and no sudo line" ;; esac
assert_eq "...and nothing was sealed first" "$(mode "$P/holds")" "775"
case "$(cat "$T_TMP/nj.err")" in *"command not found"*) bad "a shell error leaked: $(cat "$T_TMP/nj.err")" ;; *) ok "...with no shell error beside it" ;; esac
t_done
