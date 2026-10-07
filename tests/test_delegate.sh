#!/usr/bin/env bash
# The away switch (bin/hm-lib.sh): delegate mode is on exactly while a file only root can have written is valid. The
# predicate takes the path and the owner it requires; production passes only the fixed path and root, so these tests
# pass a fixture path and this user's own uid (and root, for the "a user wrote it" case).
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
ME=$(id -u); NOW=$(date +%s)
D="$T_TMP/dg/area"; F="$D/delegate"
mkf() {  # mkf [until] [hub line] [mcp list]: a valid file, then what the case changes
  mkdir -p "$D"; chmod 755 "$D" "$T_TMP/dg"
  printf 'hivemind-delegate 1\n%s\nuntil=%s\nmcp=%s\n' "${2:-hub=/work}" "${1:-$((NOW + 3600))}" "${3:-}" > "$F"; chmod 644 "$F"
}
ok_() { hm_delegate_read "$F" "${1:-$ME}" "${2:-$NOW}" >/dev/null 2>&1; }
mkf
# a fixture under a world-writable folder (TMPDIR in /tmp) could never be valid: say so rather than fail every case
if ! ok_; then
  hm_delegate_read "$F" "$ME" "$NOW" >/dev/null 2>&1
  echo "  SKIP the fixture folder is not eligible here: $HM_DELEGATE_WHY"; t_done; exit 0
fi

# ---- the path and the one production line ----
REALUID=$(/usr/bin/id -u)
if [ -d /System/Library ]; then BASE='/Library/Application Support/hivemind'; else BASE=/etc/hivemind; fi
assert_eq "the path is <base>/delegate.d/<uid>, under /Library on macOS (/etc is a link there)" "$(hm_delegate_path)" "$BASE/delegate.d/$REALUID"
assert_eq "...chosen without $OSTYPE, which comes through the environment" "$(OSTYPE=linux-gnu hm_delegate_path)" "$(hm_delegate_path)"
# bash 3.2 (macOS /bin/bash) takes UID and EUID from the environment, even under -p: a path built from $UID would name root's file
assert_eq "...from the process's real uid, not UID, EUID, USER, LOGNAME or HOME" "$(env UID=0 EUID=0 USER=root LOGNAME=root HOME=/var/root /bin/bash -p -c ". '$HM_REPO_ROOT/bin/hm-lib.sh'; hm_delegate_path")" "$BASE/delegate.d/$REALUID"
assert_eq "...hm_real_uid is one exact line, which a test can rewrite" "$(grep -c '^hm_real_uid() { /usr/bin/id -u; }$' "$HM_REPO_ROOT/bin/hm-lib.sh")" "1"
hm_real_uid() { echo; }; assert_eq "...an uid that is not digits gives no path (fail closed)" "$(hm_delegate_path)" ""
hm_real_uid() { echo 12x; }; assert_eq "......with letters in it too" "$(hm_delegate_path)" ""
hm_real_uid() { return 1; }; assert_eq "......and when id fails" "$(hm_delegate_path)" ""
hm_real_uid() { /usr/bin/id -u; }
assert_eq "no bin/ script uses UID or EUID" "$(grep -rnE '\$\{?E?UID' "$HM_REPO_ROOT/bin" | wc -l | tr -d ' ')" "0"
assert_eq "production reads the delegate file at its fixed path as root, in one exact line" "$(grep -c '^hm_delegate_now() { hm_delegate_read "$(hm_delegate_path)" 0; }$' "$HM_REPO_ROOT/bin/hm-lib.sh")" "1"
assert_eq "...and hm_delegate_mine is its only caller in bin/" "$(grep -rn 'hm_delegate_now' "$HM_REPO_ROOT/bin" | grep -v 'hm_delegate_now() {' | grep -v '^[^:]*:[0-9]*:#' | sed 's/:[0-9]*:.*//' | sort | uniq -c | tr -s ' ' | tr '\n' ' ')" " 1 $HM_REPO_ROOT/bin/hm-lib.sh "
assert_eq "...inside hm_delegate_mine itself" "$(awk '/^hm_delegate_mine\(\) \{/{f=1} f&&/hm_delegate_now/{c++} f&&/^\}/{f=0} END{print c+0}' "$HM_REPO_ROOT/bin/hm-lib.sh")" "1"

# ---- a valid file ----
out=$(hm_delegate_read "$F" "$ME" "$NOW"); assert_status "a file as the root user would make it" $? 0
assert_eq "...prints the hub, the time and the (empty) MCP list" "$out" "$(printf '/work\t%s\t' "$((NOW + 3600))")"
mkf "" "" "docs,mcp__srv__tool"; out=$(hm_delegate_read "$F" "$ME" "$NOW"); assert_eq "...an MCP list is the fourth line, printed third" "${out##*$'\t'}" "docs,mcp__srv__tool"
mkf; printf 'hivemind-delegate 1\nhub=/work\nuntil=%s\n' "$((NOW + 60))" > "$F"; ok_ && bad "the old three-line file is valid" || ok "a file with the old three lines is invalid"
mkf "" "" "docs;rm"; ok_ && bad "a bad character in mcp= is valid" || ok "a character outside the class in mcp= is invalid"
mkf "" "" 'a b'; ok_ && bad "a space in mcp= is valid" || ok "a space in mcp= is invalid"
mkf; printf 'hivemind-delegate 1\nhub=/work\nuntil=%s\nmcp=\nmore\n' "$((NOW + 60))" > "$F"; ok_ && bad "a fifth line is valid" || ok "a fifth line is invalid"
mkf; printf 'hivemind-delegate 1\nhub=/work\nuntil=%s\nnomcp\n' "$((NOW + 60))" > "$F"; ok_ && bad "a fourth line that is not mcp= is valid" || ok "a fourth line that is not mcp= is invalid"
mkf
ok_ "$((ME + 1))" && bad "a file owned by another user is valid" || ok "a file owned by someone else is refused"
ok_ 0 && bad "a file this user wrote counts as root's" || ok "a file the user wrote is refused when root is required"

# ---- the content is exactly as specified, and in the future, at most 7 days ahead ----
mkf; printf 'hivemind-delegate 2\nhub=/work\nuntil=%s\n' "$((NOW + 60))" > "$F"; ok_ && bad "another version is valid" || ok "another version is refused"
mkf; printf 'hub=/work\nhivemind-delegate 1\nuntil=%s\n' "$((NOW + 60))" > "$F"; ok_ && bad "reordered lines are valid" || ok "reordered lines are refused"
mkf; printf 'hivemind-delegate 1\nhub=/work\nuntil=%s\nmore\n' "$((NOW + 60))" > "$F"; ok_ && bad "an extra line is valid" || ok "an extra line is refused"
mkf; printf 'hivemind-delegate 1\nhub=/work\n' > "$F"; ok_ && bad "a missing until is valid" || ok "a missing line is refused"
mkf "" "hub=work"; ok_ && bad "a relative hub is valid" || ok "a relative hub is refused"
mkf "" "hub=/work;x"; ok_ && bad "a hub path hivemind would not type is valid" || ok "a hub path hivemind would not type is refused"
mkf "soon"; ok_ && bad "a non-numeric until is valid" || ok "a non-numeric until is refused"
mkf "$((NOW - 1))"; ok_ && bad "an expired file is valid" || ok "an expired file counts as off"
mkf "$((NOW + 7 * 86400 + 1))"; ok_ && bad "more than 7 days ahead is valid" || ok "more than 7 days ahead is refused"
mkf "$((NOW + 7 * 86400))"; ok_ && ok "exactly 7 days ahead is valid" || bad "7 days ahead is refused"
mkf; printf 'hivemind-delegate 1\r\nhub=/work\r\nuntil=%s\r\n' "$((NOW + 60))" > "$F"; ok_ && bad "carriage returns are valid" || ok "carriage returns are refused"
mkf; : > "$F"; ok_ && bad "an empty file is valid" || ok "an empty file is refused"
mkf; ok_ "$ME" "$((NOW + 3601))" && bad "the time is not read from the clock argument" || ok "...expiry is judged at the time given"

# ---- who can write it ----
mkf; chmod 664 "$F"; ok_ && bad "a group-writable file is valid" || ok "a group-writable file is refused"
mkf; chmod 666 "$F"; ok_ && bad "a world-writable file is valid" || ok "a world-writable file is refused"
mkf; chmod 775 "$D"; ok_ && bad "a group-writable folder is valid" || ok "a group-writable folder is refused"
mkf; chmod 757 "$D"; ok_ && bad "a world-writable folder is valid" || ok "a world-writable folder is refused"
mkf; chmod 777 "$T_TMP/dg"; ok_ && bad "a world-writable folder above is valid" || ok "a world-writable folder above it is refused"
mkf; chmod 775 "$T_TMP/dg"; ok_ && bad "a group-writable folder above is valid" || ok "a group-writable folder above it is refused"
mkf; chmod 755 "$T_TMP/dg"

# ---- links, however they sit ----
mkf; mv "$F" "$D/real"; ln -s "$D/real" "$F"; ok_ && bad "a link to a valid file is valid" || ok "a link in place of the file is refused"
rm -f "$F" "$D/real"; mkf
rm -rf "$T_TMP/lk"; mkdir -p "$T_TMP/lk"; mv "$D" "$T_TMP/lk/real"; ln -s "$T_TMP/lk/real" "$D"
ok_ && bad "a link in place of the folder is valid" || ok "a link in place of its folder is refused"
rm -f "$D"; mv "$T_TMP/lk/real" "$D"
ln -s "$T_TMP/dg" "$T_TMP/dglink"
hm_delegate_read "$T_TMP/dglink/area/delegate" "$ME" "$NOW" >/dev/null 2>&1 && bad "a path through a link is valid" || ok "a path through a link above is refused"
hm_delegate_read "area/delegate" "$ME" "$NOW" >/dev/null 2>&1 && bad "a relative path is valid" || ok "a relative path is refused"
hm_delegate_read "$D/nothing" "$ME" "$NOW" >/dev/null 2>&1 && bad "a missing file is valid" || ok "a missing file is refused"
mkf; ok_ && ok "...and the valid file is valid again" || bad "the valid file stopped being valid"

# ---- the file belongs to the user who reads it: hm_delegate_mine, in this shell, with the hub's records checked ----
# the production read is one fixed path as root; here it reads the fixture, as this user (the seam t_delegate_bin gives the executables)
hm_delegate_now() { hm_delegate_read "$F" "$ME"; }
HB="$T_TMP/dg/hub"; HP="$T_TMP/dg/homes"
mkhub() {  # mkhub: a complete hub of this user's, and a file naming it
  rm -rf "$HB" "$HP"; mkdir -p "$HB/.hivemind-hub" "$HP/mine"; chmod 755 "$HB" "$HB/.hivemind-hub" "$HP" "$HP/mine"
  printf '{"projects":[{"name":"mine","home":"%s","repos":[]}]}\n' "$HP/mine" > "$HB/.hivemind-hub/projects.json"
  printf '{"name":"hub"}\n' > "$HB/.hivemind-hub/hub.json"; chmod 644 "$HB/.hivemind-hub/projects.json" "$HB/.hivemind-hub/hub.json"
  mkf "" "hub=$HB"
}
mine() { hm_delegate_mine; }   # never inside $(...): the point is that it sets its variables in this shell
mkhub; mine; assert_status "a complete hub of this user's, named by a valid file" $? 0
assert_eq "...sets the hub, resolved" "$HM_DG_HUB" "$(cd "$HB" && pwd -P)"
assert_eq "...and when it ends" "$HM_DG_UNTIL" "$((NOW + 3600))"
mkhub; mine >/dev/null; mkf "$((NOW - 1))" "hub=$HB"; mine; rc=$?
assert_status "an expired file is refused" $rc 1
assert_contains "...for its own reason, seen in this shell" "$HM_DELEGATE_WHY" "the file has expired"
assert_eq "...and sets no hub" "$HM_DG_HUB" ""
mkhub; hm_real_uid() { echo $((ME + 1)); }; mine; assert_status "a hub that belongs to another uid is refused" $? 1
assert_contains "...for the owner reason" "$HM_DELEGATE_WHY" "$HB is owned by uid $ME"
hm_real_uid() { /usr/bin/id -u; }
mkhub; hm_real_uid() { echo; }; mine; assert_status "no readable uid, no valid file (fail closed)" $? 1
assert_contains "...for its own reason" "$HM_DELEGATE_WHY" "this user's id cannot be read"
hm_real_uid() { echo 5x; }; mine; assert_status "an uid with a letter in it too" $? 1
hm_real_uid() { /usr/bin/id -u; }
mkhub; chmod 775 "$HB"; mine; assert_status "a group-writable hub folder is refused" $? 1
assert_contains "...for its own reason" "$HM_DELEGATE_WHY" "$HB is writable by group or others"
mkhub; chmod 775 "$HB/.hivemind-hub"; mine; assert_status "a group-writable .hivemind-hub is refused" $? 1
assert_contains "...for its own reason" "$HM_DELEGATE_WHY" "$HB/.hivemind-hub is writable by group or others"
mkhub; chmod 664 "$HB/.hivemind-hub/projects.json"; mine; assert_status "a group-writable projects.json is refused" $? 1
assert_contains "...for its own reason" "$HM_DELEGATE_WHY" "projects.json is writable by group or others"
mkhub; chmod 664 "$HB/.hivemind-hub/hub.json"; mine; assert_status "a group-writable hub.json is refused" $? 1
assert_contains "...for its own reason" "$HM_DELEGATE_WHY" "hub.json is writable by group or others"
mkhub; rm "$HB/.hivemind-hub/hub.json"; mine; assert_status "a hub that never recorded itself (no hub.json) is refused" $? 1
assert_contains "...for its own reason" "$HM_DELEGATE_WHY" "hub.json cannot be read"
mkhub; mv "$HB/.hivemind-hub/projects.json" "$HB/.hivemind-hub/p.real"; ln -s "$HB/.hivemind-hub/p.real" "$HB/.hivemind-hub/projects.json"; mine; assert_status "a link in place of projects.json is refused" $? 1
assert_contains "...for its own reason" "$HM_DELEGATE_WHY" "projects.json is a link"
# a project's home: owned by the caller, not a link, not writable by group or others (a session working in another user's folder loads their CLAUDE.md, hooks and .mcp.json)
mkhub; mkdir -p "$HP/grp"; chmod 775 "$HP/grp"
printf '{"projects":[{"name":"mine","home":"%s","repos":[]},{"name":"grp","home":"%s","repos":[]},{"name":"sys","home":"/usr","repos":[]}]}\n' "$HP/mine" "$HP/grp" > "$HB/.hivemind-hub/projects.json"
hm_delegate_for_project "$HP/mine"; assert_status "a project home of the caller's is accepted" $? 0
assert_eq "...and names the project" "$HM_DG_PROJECT" "mine"
hm_delegate_for_project "$HP/grp"; assert_status "a group-writable project home is refused" $? 1
assert_contains "...for its own reason" "$HM_DELEGATE_WHY" "$HP/grp is writable by group or others"
hm_delegate_for_project /usr; assert_status "a project home owned by root is refused" $? 1
assert_contains "...for the owner reason" "$HM_DELEGATE_WHY" "/usr is owned by uid 0"
assert_eq "...a refused project sets nothing" "$HM_DG_HUB$HM_DG_PROJECT" ""
hm_delegate_for_project "$HP/mine"; assert_status "...while the caller's own project still is accepted" $? 0

# a worktree of a listed home is a team root, and gets bypass on the same terms: the caller's own, not a link, not writable by group or others
mkhub; rm -rf "$HP/repo" "$HP/wt" "$HP/wtg" "$HP/wtx"; mkdir -p "$HP/repo"; chmod 755 "$HP/repo"
git -C "$HP/repo" init -q -b main; git -C "$HP/repo" config user.email t@t; git -C "$HP/repo" config user.name t; echo x > "$HP/repo/f"; git -C "$HP/repo" add f; git -C "$HP/repo" commit -qm i
git -C "$HP/repo" worktree add -q "$HP/wt" -b wt; git -C "$HP/repo" worktree add -q "$HP/wtg" -b wtg; git -C "$HP/repo" worktree add -q "$HP/wtx" -b wtx
for w in wt wtg wtx; do mkdir -p "$HP/$w/.hivemind"; echo '{}' > "$HP/$w/.hivemind/team.json"; chmod 755 "$HP/$w"; done
printf '{"projects":[{"name":"repo","home":"%s","repos":[]}]}\n' "$HP/repo" > "$HB/.hivemind-hub/projects.json"
hm_delegate_for_project "$HP/repo"; assert_status "a listed home is accepted (a git repository)" $? 0
hm_delegate_for_project "$HP/wt"; assert_status "a worktree of a listed home with a team is accepted" $? 0
assert_eq "...as that project" "$HM_DG_PROJECT" "repo"
chmod 775 "$HP/wtg"; hm_delegate_for_project "$HP/wtg"; assert_status "a group-writable worktree root is refused" $? 1
assert_contains "...for its own reason" "$HM_DELEGATE_WHY" "$HP/wtg is writable by group or others"
cp "$HP/wtx/.git" "$T_TMP/wtx.git.saved"; echo "gitdir: $HP/repo/.git/worktrees/wt" > "$HP/wtx/.git"
hm_delegate_for_project "$HP/wtx"; assert_status "a worktree whose .git file does not point back is refused" $? 1
cp "$T_TMP/wtx.git.saved" "$HP/wtx/.git"
other="$T_TMP/dg/other"; rm -rf "$other"; mkdir -p "$other"; chmod 755 "$other"; git -C "$other" init -q -b main; git -C "$other" config user.email t@t; git -C "$other" config user.name t; echo x > "$other/f"; git -C "$other" add f; git -C "$other" commit -qm i
git -C "$other" worktree add -q "$T_TMP/dg/otherwt" -b ow; mkdir -p "$T_TMP/dg/otherwt/.hivemind"; echo '{}' > "$T_TMP/dg/otherwt/.hivemind/team.json"; chmod 755 "$T_TMP/dg/otherwt"
hm_delegate_for_project "$T_TMP/dg/otherwt"; assert_status "a worktree of a repository that is not listed is refused" $? 1
hm_delegate_for_project "$HP/wt"; assert_status "...while the listed one still is accepted" $? 0
mv "$HP/wt/.hivemind/team.json" "$T_TMP/team.saved"; hm_delegate_for_project "$HP/wt"; assert_status "a worktree with no team.json is no team root" $? 1
mv "$T_TMP/team.saved" "$HP/wt/.hivemind/team.json"
chmod 775 "$HP/repo"; hm_delegate_for_project "$HP/wt"; assert_status "a group-writable home refuses its worktrees too" $? 1
assert_contains "...for the home" "$HM_DELEGATE_WHY" "$HP/repo is writable by group or others"
chmod 755 "$HP/repo"

# ---- the launch environment of a process (the marker's check, A42) ----
pp=$(t_env_probe HM_PROBE_TEST=1) || pp=""
[ -n "$pp" ] || { ( HM_PROBE_TEST=1 bash -c 'exec -a claude sleep 30' ) & pp=$!; }   # a platform binary: readable on Linux only
t_track "$pp"; sleep 0.5
hm_env_has "$pp" HM_PROBE_TEST=1; rc=$?
if [ "$rc" -eq 2 ]; then
  echo "  SKIP only Apple platform binaries were found (no node): macOS shows no environment for them in ps -E, so the marker's check cannot be tested here"
  assert_eq "an environment that cannot be read is told apart from an absent variable" "$rc" "2"
else
  assert_eq "a variable the process was launched with is found" "$rc" "0"
  hm_env_has "$pp" HM_PROBE_TEST=2; assert_status "...another value is not" $? 1
  hm_env_has "$pp" HM_NOT_THERE=1; assert_status "...nor a variable it lacks" $? 1
fi
kill "$pp" 2>/dev/null
# a marker spelled in the process's own arguments is not one it was launched with
pa=$(t_env_probe HM_PROBE_OTHER=1 HM_PROBE_ARG=1) || pa=""
if [ -n "$pa" ]; then
  t_track "$pa"; sleep 0.5
  hm_env_has "$pa" HM_PROBE_OTHER=1; assert_status "a variable the process has is found beside an argument that looks like one" $? 0
  hm_env_has "$pa" HM_PROBE_ARG=1; assert_status "...a marker spelled only in its arguments is absent" $? 1
  kill "$pa" 2>/dev/null
else echo "  SKIP only Apple platform binaries were found (no node): the argument-spelled marker cannot be tested here"; fi
t_done
