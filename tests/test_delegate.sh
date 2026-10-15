#!/usr/bin/env bash
# The away switch (bin/hh-lib.sh): delegate mode is on exactly while a file only root can have written is valid. The
# predicate takes the path and the owner it requires; production passes only the fixed path and root, so these tests
# pass a fixture path and this user's own uid (and root, for the "a user wrote it" case).
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
ME=$(id -u); NOW=$(date +%s)
D="$T_TMP/dg/area"; F="$D/delegate"
mkf() {  # mkf [until] [hub line] [mcp list]: a valid file, then what the case changes
  mkdir -p "$D"; chmod 755 "$D" "$T_TMP/dg"
  printf "$T_DELEGATE_LINE1"'\n%s\nuntil=%s\nmcp=%s\n' "${2:-hub=/work}" "${1:-$((NOW + 3600))}" "${3:-}" > "$F"; chmod 644 "$F"
}
ok_() { hh_delegate_read "$F" "${1:-$ME}" "${2:-$NOW}" >/dev/null 2>&1; }
mkf
# a fixture under a world-writable folder (TMPDIR in /tmp) could never be valid: say so rather than fail every case
if ! ok_; then
  hh_delegate_read "$F" "$ME" "$NOW" >/dev/null 2>&1
  echo "  SKIP the fixture folder is not eligible here: $HH_DELEGATE_WHY"; t_done; exit 0
fi

# ---- the path and the one production line ----
REALUID=$(/usr/bin/id -u)
if [ -d /System/Library ]; then BASE="$T_MAC_BASE"; else BASE=$T_LINUX_BASE; fi
assert_eq "the path is <base>/delegate.d/<uid>, under /Library on macOS (/etc is a link there)" "$(hh_delegate_path)" "$BASE/delegate.d/$REALUID"
assert_eq "...chosen without $OSTYPE, which comes through the environment" "$(OSTYPE=linux-gnu hh_delegate_path)" "$(hh_delegate_path)"
# bash 3.2 (macOS /bin/bash) takes UID and EUID from the environment, even under -p: a path built from $UID would name root's file
assert_eq "...from the process's real uid, not UID, EUID, USER, LOGNAME or HOME" "$(env UID=0 EUID=0 USER=root LOGNAME=root HOME=/var/root /bin/bash -p -c ". '$HH_REPO_ROOT/bin/hh-lib.sh'; hh_delegate_path")" "$BASE/delegate.d/$REALUID"
assert_eq "...hh_real_uid is one exact line, which a test can rewrite" "$(grep -c '^hh_real_uid() { /usr/bin/id -u; }$' "$HH_REPO_ROOT/bin/hh-lib.sh")" "1"
hh_real_uid() { echo; }; assert_eq "...an uid that is not digits gives no path (fail closed)" "$(hh_delegate_path)" ""
hh_real_uid() { echo 12x; }; assert_eq "......with letters in it too" "$(hh_delegate_path)" ""
hh_real_uid() { return 1; }; assert_eq "......and when id fails" "$(hh_delegate_path)" ""
hh_real_uid() { /usr/bin/id -u; }
assert_eq "no bin/ script uses UID or EUID" "$(grep -rnE '\$\{?E?UID' "$HH_REPO_ROOT/bin" | wc -l | tr -d ' ')" "0"
assert_eq "production reads the delegate file at its fixed path as root, in one exact line" "$(grep -c '^hh_delegate_now() { hh_delegate_read "$(hh_delegate_path)" 0; }$' "$HH_REPO_ROOT/bin/hh-lib.sh")" "1"
assert_eq "...and hh_delegate_mine is its only caller in bin/" "$(grep -rn 'hh_delegate_now' "$HH_REPO_ROOT/bin" | grep -v 'hh_delegate_now() {' | grep -v '^[^:]*:[0-9]*:#' | sed 's/:[0-9]*:.*//' | sort | uniq -c | tr -s ' ' | tr '\n' ' ')" " 1 $HH_REPO_ROOT/bin/hh-lib.sh "
assert_eq "...inside hh_delegate_mine itself" "$(awk '/^hh_delegate_mine\(\) \{/{f=1} f&&/hh_delegate_now/{c++} f&&/^\}/{f=0} END{print c+0}' "$HH_REPO_ROOT/bin/hh-lib.sh")" "1"

# ---- a valid file ----
out=$(hh_delegate_read "$F" "$ME" "$NOW"); assert_status "a file as the root user would make it" $? 0
assert_eq "...prints the hub, the time and the (empty) MCP list" "$out" "$(printf '/work\t%s\t' "$((NOW + 3600))")"
mkf "" "" "docs,mcp__srv__tool"; out=$(hh_delegate_read "$F" "$ME" "$NOW"); assert_eq "...an MCP list is the fourth line, printed third" "${out##*$'\t'}" "docs,mcp__srv__tool"
mkf; printf "$T_DELEGATE_LINE1"'\nhub=/work\nuntil=%s\n' "$((NOW + 60))" > "$F"; ok_ && bad "the old three-line file is valid" || ok "a file with the old three lines is invalid"
mkf "" "" "docs;rm"; ok_ && bad "a bad character in mcp= is valid" || ok "a character outside the class in mcp= is invalid"
mkf "" "" 'a b'; ok_ && bad "a space in mcp= is valid" || ok "a space in mcp= is invalid"
mkf; printf "$T_DELEGATE_LINE1"'\nhub=/work\nuntil=%s\nmcp=\nmore\n' "$((NOW + 60))" > "$F"; ok_ && bad "a fifth line is valid" || ok "a fifth line is invalid"
mkf; printf "$T_DELEGATE_LINE1"'\nhub=/work\nuntil=%s\nnomcp\n' "$((NOW + 60))" > "$F"; ok_ && bad "a fourth line that is not mcp= is valid" || ok "a fourth line that is not mcp= is invalid"
mkf
ok_ "$((ME + 1))" && bad "a file owned by another user is valid" || ok "a file owned by someone else is refused"
ok_ 0 && bad "a file this user wrote counts as root's" || ok "a file the user wrote is refused when root is required"

# ---- the content is exactly as specified, and in the future, at most 7 days ahead ----
mkf; printf '%s\nhub=/work\nuntil=%s\nmcp=\n' "${T_DELEGATE_LINE1%1}3" "$((NOW + 60))" > "$F"; ok_ && bad "another version is valid" || ok "another version is refused"
mkf; printf 'hub=/work\n'"$T_DELEGATE_LINE1"'\nuntil=%s\n' "$((NOW + 60))" > "$F"; ok_ && bad "reordered lines are valid" || ok "reordered lines are refused"
mkf; printf "$T_DELEGATE_LINE1"'\nhub=/work\nuntil=%s\nmore\n' "$((NOW + 60))" > "$F"; ok_ && bad "an extra line is valid" || ok "an extra line is refused"
mkf; printf "$T_DELEGATE_LINE1"'\nhub=/work\n' > "$F"; ok_ && bad "a missing until is valid" || ok "a missing line is refused"
mkf "" "hub=work"; ok_ && bad "a relative hub is valid" || ok "a relative hub is refused"
mkf "" "hub=/work;x"; ok_ && bad "a hub path hivehouse would not type is valid" || ok "a hub path hivehouse would not type is refused"
mkf "soon"; ok_ && bad "a non-numeric until is valid" || ok "a non-numeric until is refused"
mkf "$((NOW - 1))"; ok_ && bad "an expired file is valid" || ok "an expired file counts as off"
mkf "$((NOW + 7 * 86400 + 1))"; ok_ && bad "more than 7 days ahead is valid" || ok "more than 7 days ahead is refused"
mkf "$((NOW + 7 * 86400))"; ok_ && ok "exactly 7 days ahead is valid" || bad "7 days ahead is refused"
mkf; printf "$T_DELEGATE_LINE1"'\r\nhub=/work\r\nuntil=%s\r\n' "$((NOW + 60))" > "$F"; ok_ && bad "carriage returns are valid" || ok "carriage returns are refused"
mkf; : > "$F"; ok_ && bad "an empty file is valid" || ok "an empty file is refused"
mkf; ok_ "$ME" "$((NOW + 3601))" && bad "the time is not read from the clock argument" || ok "...expiry is judged at the time given"

# ---- version 2: hosts= and allow= (0.5.1) ----
mk2() {  # mk2 <hosts line> <allow line> [until]: a version 2 file
  mkf; printf "$T_DELEGATE_LINE2"'\nhub=/work\nuntil=%s\nmcp=\n%s\n%s\n' "${3:-$((NOW + 3600))}" "$1" "$2" > "$F"
}
mk2 "hosts=" "allow="; ok_ && ok "v2 with empty hosts= and allow= is valid" || bad "v2 empty is refused: $HH_DELEGATE_WHY"
mk2 "hosts=night.example.org,ops@10.0.0.7,a_b-c" "allow="; hh_delegate_read "$F" "$ME" "$NOW" > "$T_TMP/dg.out"; assert_status "v2 with hosts (and the empty allow=) is valid" $? 0
assert_eq "...still prints hub, time and mcp (three columns)" "$(cat "$T_TMP/dg.out")" "$(printf '/work\t%s\t' "$((NOW + 3600))")"
assert_eq "...HH_DR_HOSTS holds the hosts" "$HH_DR_HOSTS" "night.example.org,ops@10.0.0.7,a_b-c"
mkf; hh_delegate_read "$F" "$ME" "$NOW" >/dev/null; assert_eq "a v1 file has no hosts" "$HH_DR_HOSTS" ""
for w in scp rsync sftp scp,sftp,rsync claude tmux hh-push hh-remote-sync vercel netlify ssh bash zzz SCP "scp rsync"; do
  mk2 "hosts=" "allow=$w"; ok_ && bad "allow=$w is valid" || assert_contains "allow=$w makes the file invalid: reserved" "$HH_DELEGATE_WHY" "allow= is reserved; no command is allowable in this version"
done
mk2 "hosts=" "allow=scp,claude"; ok_ && bad "one forbidden word among good ones is valid" || ok "one forbidden word among good ones makes the file invalid"
mk2 "hosts=" "allow=scp,,sftp"; ok_ && bad "an empty entry in allow= is valid" || ok "an empty entry in allow= is invalid"
for h in -x -o ops@-x u@-o a/b "a b" 'a;b' 'a$b' 'a`b' "a:b" "@h" "u@" "a@b@c" "a,,b" ",a" "a,"; do
  mk2 "hosts=$h" "allow="; ok_ && bad "hosts=$h is valid" || ok "hosts=$h is invalid"
done
mk2 "hosts=ok,-bad" "allow="; ok_ && bad "a host starting with - after a good one is valid" || ok "a later host starting with - is invalid"
mk2 "host=a" "allow="; ok_ && bad "line 5 not hosts= is valid" || ok "line 5 that is not hosts= is invalid"
mk2 "hosts=" "permit="; ok_ && bad "line 6 not allow= is valid" || ok "line 6 that is not allow= is invalid"
mk2 "hosts=" "allow="; printf 'extra\n' >> "$F"; ok_ && bad "a v2 file with 7 lines is valid" || ok "a v2 file with 7 lines is invalid"
mkf; printf "$T_DELEGATE_LINE2"'\nhub=/work\nuntil=%s\nmcp=\nhosts=\n' "$((NOW + 60))" > "$F"; ok_ && bad "a v2 file with 5 lines is valid" || ok "a v2 file with 5 lines is invalid"
mkf; printf "$T_DELEGATE_LINE1"'\nhub=/work\nuntil=%s\nmcp=\nhosts=\nallow=\n' "$((NOW + 60))" > "$F"; ok_ && bad "a v1 file with 6 lines is valid" || ok "a v1 file with 6 lines is invalid"
mkf; printf "$T_DELEGATE_LINE1"'\nhub=/work\nuntil=%s\nmcp=\nhosts=a\n' "$((NOW + 60))" > "$F"; ok_ && bad "a v1 file with 5 lines is valid" || ok "a v1 file with 5 lines is still refused"
mk2 "hosts=a" "allow="; printf '%s\r\n' x >> "$F"; ok_ && bad "carriage return in a v2 file is valid" || ok "a carriage return in a v2 file is invalid"
mkf; printf "$T_DELEGATE_LINE2"'\r\nhub=/work\r\nuntil=%s\r\nmcp=\r\nhosts=\r\nallow=\r\n' "$((NOW + 60))" > "$F"; ok_ && bad "a v2 file with carriage returns in lines 5 and 6 is valid" || ok "carriage returns in a v2 file are refused"

# ---- version 3: tools= (0.5.2) ----
mk3() {  # mk3 <tools line> [until]: a version 3 file
  mkf; printf "$T_DELEGATE_LINE3"'\nhub=/work\nuntil=%s\nmcp=\nhosts=\nallow=\n%s\n' "${2:-$((NOW + 3600))}" "$1" > "$F"
}
mk3 "tools="; ok_ && ok "v3 with an empty tools= is valid" || bad "v3 empty is refused: $HH_DELEGATE_WHY"
assert_eq "...and allows none" "$HH_DR_TOOLS" ""
mk3 "tools=Workflow,WebFetch,DesignSync,ArtifactCheck,PushNotification"; ok_ && ok "v3 with all five tools is valid" || bad "v3 with five tools is refused: $HH_DELEGATE_WHY"
assert_eq "...HH_DR_TOOLS holds them" "$HH_DR_TOOLS" "Workflow,WebFetch,DesignSync,ArtifactCheck,PushNotification"
mk3 "tools=WebFetch"; hh_delegate_read "$F" "$ME" "$NOW" > "$T_TMP/dg.out"; assert_eq "...the three columns are unchanged" "$(cat "$T_TMP/dg.out")" "$(printf '/work\t%s\t' "$((NOW + 3600))")"
for w in Bash CronCreate ScheduleWakeup workflow WORKFLOW Agent mcp__x Workflow,Bash "Workflow WebFetch" Workflow,,WebFetch ,Workflow Workflow, 'a;b' 'Work*'; do
  mk3 "tools=$w"; ok_ && bad "tools=$w is valid" || assert_contains "tools=$w makes the file invalid" "$HH_DELEGATE_WHY" "tools="
done
mk3 "tool=Workflow"; ok_ && bad "line 7 not tools= is valid" || ok "line 7 that is not tools= is invalid"
mk3 "tools="; printf 'extra\n' >> "$F"; ok_ && bad "a v3 file with 8 lines is valid" || ok "a v3 file with 8 lines is invalid"
mk3 "tools="; printf '\n' >> "$F"; ok_ && bad "a v3 file with a blank 8th line is valid" || ok "a v3 file with a blank 8th line is invalid"
mkf; printf "$T_DELEGATE_LINE3"'\nhub=/work\nuntil=%s\nmcp=\nhosts=\nallow=\n' "$((NOW + 60))" > "$F"; ok_ && bad "a v3 file with 6 lines is valid" || ok "a v3 file with 6 lines is invalid"
mk3 "tools=WebFetch"; sed -i.bak 's/$/\r/' "$F"; rm -f "$F.bak"; ok_ && bad "a v3 file with carriage returns is valid" || ok "a v3 file with carriage returns is invalid"
# ---- version 4: peers= (0.5.4, S6) ----
mk4() {  # mk4 <peers line> [until]: a version 4 file
  mkf; printf "$T_DELEGATE_LINE4"'\nhub=/work\nuntil=%s\nmcp=\nhosts=\nallow=\ntools=\n%s\n' "${2:-$((NOW + 3600))}" "$1" > "$F"
}
mk4 "peers="; ok_ && ok "v4 with an empty peers= is valid" || bad "v4 empty is refused: $HH_DELEGATE_WHY"
assert_eq "...and lists none" "$HH_DR_PEERS" ""
mk4 "peers=far-orchestrator,far-agent.2_x"; ok_ && ok "v4 with two peers is valid" || bad "v4 with peers is refused: $HH_DELEGATE_WHY"
assert_eq "...and lists both" "$HH_DR_PEERS" "far-orchestrator,far-agent.2_x"
for w in "a b" "a,,b" ",a" "a," "far[x]" "far*" "a/b" "-x" "a\$b"; do
  mk4 "peers=$w"; ok_ && bad "peers=$w is valid" || assert_contains "peers=$w makes the file invalid" "$HH_DELEGATE_WHY" "peers="
done
mk4 "peer=far"; ok_ && bad "line 8 not peers= is valid" || ok "line 8 that is not peers= is invalid"
mk4 "peers="; printf 'extra\n' >> "$F"; ok_ && bad "a v4 file with 9 lines is valid" || ok "a v4 file with 9 lines is invalid"
mk4 "peers="; printf '\n' >> "$F"; ok_ && bad "a v4 file with a blank 9th line is valid" || ok "a v4 file with a blank 9th line is invalid"
mkf; printf "$T_DELEGATE_LINE4"'\nhub=/work\nuntil=%s\nmcp=\nhosts=\nallow=\ntools=\n' "$((NOW + 60))" > "$F"; ok_ && bad "a v4 file with 7 lines is valid" || ok "a v4 file with 7 lines is invalid"
mk3 "tools="; printf 'peers=far\n' >> "$F"; ok_ && bad "a v3 file with a peers= line is valid" || ok "a v3 file with an eighth line (peers=) is invalid"
mk3 "tools=WebFetch"; ok_ && assert_eq "a v3 file means no peers" "$HH_DR_PEERS" "" || bad "v3 refused: $HH_DELEGATE_WHY"
mk2 "hosts=" "allow="; hh_delegate_read "$F" "$ME" "$NOW" >/dev/null; assert_eq "a v2 file allows no tools" "$HH_DR_TOOLS" ""
mkf; hh_delegate_read "$F" "$ME" "$NOW" >/dev/null; assert_eq "a v1 file allows no tools" "$HH_DR_TOOLS" ""
mk2 "hosts=" "allow="; printf 'tools=Workflow\n' >> "$F"; ok_ && bad "a v2 file with a tools= line is valid" || ok "a v2 file with a seventh line (tools=) is invalid"

# ---- version 5: hook=on|off (0.5.7) ----
mk5() {  # mk5 <hook line> [until]: a version 5 file
  mkf; printf "$T_DELEGATE_LINE5"'\nhub=/work\nuntil=%s\nmcp=\nhosts=\nallow=\ntools=\npeers=\n%s\n' "${2:-$((NOW + 3600))}" "$1" > "$F"
}
mk5 "hook=on"; ok_ && ok "v5 with hook=on is valid" || bad "v5 hook=on is refused: $HH_DELEGATE_WHY"
assert_eq "...and the hook is on" "$HH_DR_HOOK" "on"
mk5 "hook=off"; ok_ && ok "v5 with hook=off is valid" || bad "v5 hook=off is refused: $HH_DELEGATE_WHY"
assert_eq "...and the hook is off" "$HH_DR_HOOK" "off"
for w in "hook=" "hook=ON" "hook=Off" "hook=yes" "hook=off " "hook=on,off" "hooks=off" "off" ""; do
  mk5 "$w"; ok_ && bad "line 9 [$w] is valid" || assert_contains "line 9 [$w] makes the file invalid" "$HH_DELEGATE_WHY" "line 9 is not hook=on or hook=off"
done
mkf; printf "$T_DELEGATE_LINE5"'\nhub=/work\nuntil=%s\nmcp=\nhosts=\nallow=\ntools=\npeers=\n' "$((NOW + 60))" > "$F"; ok_ && bad "a v5 file with 8 lines is valid" || assert_contains "a v5 file with line 9 missing is invalid" "$HH_DELEGATE_WHY" "line 9"
mk5 "hook=off"; printf 'extra\n' >> "$F"; ok_ && bad "a v5 file with a 10th line is valid" || assert_contains "a v5 file with a 10th line is invalid" "$HH_DELEGATE_WHY" "more than 9 lines"
mk5 "hook=off"; printf '\n' >> "$F"; ok_ && bad "a v5 file with a blank 10th line is valid" || ok "a v5 file with a blank 10th line is invalid"
mk5 "hook=off"; printf 'hook=on\n' >> "$F"; ok_ && bad "a v5 file with two hook lines is valid" || ok "a v5 file with a second hook line is invalid"
mk5 "hook=off"; sed -i.bak 's/$/\r/' "$F"; rm -f "$F.bak"; ok_ && bad "a v5 file with carriage returns is valid" || ok "a v5 file with carriage returns is invalid"
mk4 "peers="; printf 'hook=off\n' >> "$F"; ok_ && bad "a v4 file with a hook= line is valid" || ok "a v4 file with a ninth line (hook=off) is invalid"
mk5 "hook=on"; sed -i.bak '1s/ 5$/ 4/' "$F"; rm -f "$F.bak"; ok_ && bad "a file tagged 4 with a hook= line is valid" || ok "...the tag decides the line count"
mk5 "hook=off"; sed -i.bak '1s/ 5$/ 6/' "$F"; rm -f "$F.bak"; ok_ && bad "version 6 is valid" || ok "version 6 is not read"
mk4 "peers="; ok_; assert_eq "a v4 file reads as hook on" "$HH_DR_HOOK" "on"
mk3 "tools="; ok_; assert_eq "a v3 file reads as hook on" "$HH_DR_HOOK" "on"
mk2 "hosts=" "allow="; ok_; assert_eq "a v2 file reads as hook on" "$HH_DR_HOOK" "on"
mkf; ok_; assert_eq "a v1 file reads as hook on" "$HH_DR_HOOK" "on"
mk5 "hook=off"; ok_; mk5 "hook=zzz"; ok_ || assert_eq "an invalid file leaves no hook value behind" "$HH_DR_HOOK" ""
assert_eq "HH_DELEGATE_WRITE is 5" "$HH_DELEGATE_WRITE" "5"

# a blank line past the version's count is a line (the content is exactly 4 or 6 lines, a blank one included)
mkf; printf "$T_DELEGATE_LINE1"'\nhub=/work\nuntil=%s\nmcp=\n\n' "$((NOW + 60))" > "$F"; ok_ && bad "a v1 file with a blank 5th line is valid" || ok "a v1 file with a blank 5th line is refused"
mk2 "hosts=" "allow="; printf '\n' >> "$F"; ok_ && bad "a v2 file with a blank 7th line is valid" || ok "a v2 file with a blank 7th line is refused"
mkf; printf "$T_DELEGATE_LINE1"'\nhub=/work\nuntil=%s\nmcp=\n\n\n\n\n\n' "$((NOW + 60))" > "$F"; ok_ && bad "a v1 file with many blank lines is valid" || ok "...and with many blank lines"
mk2 "hosts=" "allow="; ok_ && ok "(a v2 file of exactly 6 lines is still valid)" || bad "v2 refused: $HH_DELEGATE_WHY"
mk2 "hosts=" "allow="; printf '%s' "$(cat "$F")" > "$F"; ok_ && ok "...and without a final newline" || bad "no final newline refused: $HH_DELEGATE_WHY"
# a carriage return in line 5 or 6 reaches the carriage-return check first
mkf; printf "$T_DELEGATE_LINE2"'\nhub=/work\nuntil=%s\nmcp=\nhosts=\r\nallow=\n' "$((NOW + 60))" > "$F"; ok_ && bad "a CR in hosts= is valid" || assert_contains "a carriage return in line 5 is refused as one" "$HH_DELEGATE_WHY" "carriage"
mkf; printf "$T_DELEGATE_LINE2"'\nhub=/work\nuntil=%s\nmcp=\nhosts=\nallow=\r\n' "$((NOW + 60))" > "$F"; ok_ && bad "a CR in allow= is valid" || assert_contains "...and in line 6" "$HH_DELEGATE_WHY" "carriage"

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
hh_delegate_read "$T_TMP/dglink/area/delegate" "$ME" "$NOW" >/dev/null 2>&1 && bad "a path through a link is valid" || ok "a path through a link above is refused"
hh_delegate_read "area/delegate" "$ME" "$NOW" >/dev/null 2>&1 && bad "a relative path is valid" || ok "a relative path is refused"
hh_delegate_read "$D/nothing" "$ME" "$NOW" >/dev/null 2>&1 && bad "a missing file is valid" || ok "a missing file is refused"
mkf; ok_ && ok "...and the valid file is valid again" || bad "the valid file stopped being valid"

# ---- the file belongs to the user who reads it: hh_delegate_mine, in this shell, with the hub's records checked ----
# the production read is one fixed path as root; here it reads the fixture, as this user (the seam t_delegate_bin gives the executables)
hh_delegate_now() { hh_delegate_read "$F" "$ME"; }
HB="$T_TMP/dg/hub"; HP="$T_TMP/dg/homes"
mkhub() {  # mkhub: a complete hub of this user's, and a file naming it
  rm -rf "$HB" "$HP"; mkdir -p "$HB/$T_HUB" "$HP/mine"; chmod 755 "$HB" "$HB/$T_HUB" "$HP" "$HP/mine"
  printf '{"projects":[{"name":"mine","home":"%s","repos":[]}]}\n' "$HP/mine" > "$HB/$T_HUB/projects.json"
  printf '{"name":"hub"}\n' > "$HB/$T_HUB/hub.json"; chmod 644 "$HB/$T_HUB/projects.json" "$HB/$T_HUB/hub.json"
  mkf "" "hub=$HB"
}
mine() { hh_delegate_mine; }   # never inside $(...): the point is that it sets its variables in this shell
mkhub; mine; assert_status "a complete hub of this user's, named by a valid file" $? 0
assert_eq "...sets the hub, resolved" "$HH_DG_HUB" "$(cd "$HB" && pwd -P)"
assert_eq "...and when it ends" "$HH_DG_UNTIL" "$((NOW + 3600))"
mkhub; mine >/dev/null; mkf "$((NOW - 1))" "hub=$HB"; mine; rc=$?
assert_status "an expired file is refused" $rc 1
assert_contains "...for its own reason, seen in this shell" "$HH_DELEGATE_WHY" "the file has expired"
assert_eq "...and sets no hub" "$HH_DG_HUB" ""
mkhub; hh_real_uid() { echo $((ME + 1)); }; mine; assert_status "a hub that belongs to another uid is refused" $? 1
assert_contains "...for the owner reason" "$HH_DELEGATE_WHY" "$HB is owned by uid $ME"
hh_real_uid() { /usr/bin/id -u; }
mkhub; hh_real_uid() { echo; }; mine; assert_status "no readable uid, no valid file (fail closed)" $? 1
assert_contains "...for its own reason" "$HH_DELEGATE_WHY" "this user's id cannot be read"
hh_real_uid() { echo 5x; }; mine; assert_status "an uid with a letter in it too" $? 1
hh_real_uid() { /usr/bin/id -u; }
mkhub; chmod 775 "$HB"; mine; assert_status "a group-writable hub folder is refused" $? 1
assert_contains "...for its own reason" "$HH_DELEGATE_WHY" "$HB is writable by group or others"
mkhub; chmod 775 "$HB/$T_HUB"; mine; assert_status "a group-writable $T_HUB is refused" $? 1
assert_contains "...for its own reason" "$HH_DELEGATE_WHY" "$HB/$T_HUB is writable by group or others"
mkhub; chmod 664 "$HB/$T_HUB/projects.json"; mine; assert_status "a group-writable projects.json is refused" $? 1
assert_contains "...for its own reason" "$HH_DELEGATE_WHY" "projects.json is writable by group or others"
mkhub; chmod 664 "$HB/$T_HUB/hub.json"; mine; assert_status "a group-writable hub.json is refused" $? 1
assert_contains "...for its own reason" "$HH_DELEGATE_WHY" "hub.json is writable by group or others"
mkhub; rm "$HB/$T_HUB/hub.json"; mine; assert_status "a hub that never recorded itself (no hub.json) is refused" $? 1
assert_contains "...for its own reason" "$HH_DELEGATE_WHY" "hub.json cannot be read"
mkhub; mv "$HB/$T_HUB/projects.json" "$HB/$T_HUB/p.real"; ln -s "$HB/$T_HUB/p.real" "$HB/$T_HUB/projects.json"; mine; assert_status "a link in place of projects.json is refused" $? 1
assert_contains "...for its own reason" "$HH_DELEGATE_WHY" "projects.json is a link"
# a project's home: owned by the caller, not a link, not writable by group or others (a session working in another user's folder loads their CLAUDE.md, hooks and .mcp.json)
mkhub; mkdir -p "$HP/grp"; chmod 775 "$HP/grp"
printf '{"projects":[{"name":"mine","home":"%s","repos":[]},{"name":"grp","home":"%s","repos":[]},{"name":"sys","home":"/usr","repos":[]}]}\n' "$HP/mine" "$HP/grp" > "$HB/$T_HUB/projects.json"
hh_delegate_for_project "$HP/mine"; assert_status "a project home of the caller's is accepted" $? 0
assert_eq "...and names the project" "$HH_DG_PROJECT" "mine"
hh_delegate_for_project "$HP/grp"; assert_status "a group-writable project home is refused" $? 1
assert_contains "...for its own reason" "$HH_DELEGATE_WHY" "$HP/grp is writable by group or others"
hh_delegate_for_project /usr; assert_status "a project home owned by root is refused" $? 1
assert_contains "...for the owner reason" "$HH_DELEGATE_WHY" "/usr is owned by uid 0"
assert_eq "...a refused project sets nothing" "$HH_DG_HUB$HH_DG_PROJECT" ""
hh_delegate_for_project "$HP/mine"; assert_status "...while the caller's own project still is accepted" $? 0

# a worktree of a listed home is a team root, and gets bypass on the same terms: the caller's own, not a link, not writable by group or others
mkhub; rm -rf "$HP/repo" "$HP/wt" "$HP/wtg" "$HP/wtx"; mkdir -p "$HP/repo"; chmod 755 "$HP/repo"
git -C "$HP/repo" init -q -b main; git -C "$HP/repo" config user.email t@t; git -C "$HP/repo" config user.name t; echo x > "$HP/repo/f"; git -C "$HP/repo" add f; git -C "$HP/repo" commit -qm i
git -C "$HP/repo" worktree add -q "$HP/wt" -b wt; git -C "$HP/repo" worktree add -q "$HP/wtg" -b wtg; git -C "$HP/repo" worktree add -q "$HP/wtx" -b wtx
for w in wt wtg wtx; do mkdir -p "$HP/$w/$T_STATE"; echo '{}' > "$HP/$w/$T_STATE/team.json"; chmod 755 "$HP/$w"; done
printf '{"projects":[{"name":"repo","home":"%s","repos":[]}]}\n' "$HP/repo" > "$HB/$T_HUB/projects.json"
hh_delegate_for_project "$HP/repo"; assert_status "a listed home is accepted (a git repository)" $? 0
hh_delegate_for_project "$HP/wt"; assert_status "a worktree of a listed home with a team is accepted" $? 0
assert_eq "...as that project" "$HH_DG_PROJECT" "repo"
chmod 775 "$HP/wtg"; hh_delegate_for_project "$HP/wtg"; assert_status "a group-writable worktree root is refused" $? 1
assert_contains "...for its own reason" "$HH_DELEGATE_WHY" "$HP/wtg is writable by group or others"
cp "$HP/wtx/.git" "$T_TMP/wtx.git.saved"; echo "gitdir: $HP/repo/.git/worktrees/wt" > "$HP/wtx/.git"
hh_delegate_for_project "$HP/wtx"; assert_status "a worktree whose .git file does not point back is refused" $? 1
cp "$T_TMP/wtx.git.saved" "$HP/wtx/.git"
other="$T_TMP/dg/other"; rm -rf "$other"; mkdir -p "$other"; chmod 755 "$other"; git -C "$other" init -q -b main; git -C "$other" config user.email t@t; git -C "$other" config user.name t; echo x > "$other/f"; git -C "$other" add f; git -C "$other" commit -qm i
git -C "$other" worktree add -q "$T_TMP/dg/otherwt" -b ow; mkdir -p "$T_TMP/dg/otherwt/$T_STATE"; echo '{}' > "$T_TMP/dg/otherwt/$T_STATE/team.json"; chmod 755 "$T_TMP/dg/otherwt"
hh_delegate_for_project "$T_TMP/dg/otherwt"; assert_status "a worktree of a repository that is not listed is refused" $? 1
hh_delegate_for_project "$HP/wt"; assert_status "...while the listed one still is accepted" $? 0
mv "$HP/wt/$T_STATE/team.json" "$T_TMP/team.saved"; hh_delegate_for_project "$HP/wt"; assert_status "a worktree with no team.json is no team root" $? 1
mv "$T_TMP/team.saved" "$HP/wt/$T_STATE/team.json"
chmod 775 "$HP/repo"; hh_delegate_for_project "$HP/wt"; assert_status "a group-writable home refuses its worktrees too" $? 1
assert_contains "...for the home" "$HH_DELEGATE_WHY" "$HP/repo is writable by group or others"
chmod 755 "$HP/repo"

# ---- the launch environment of a process (the marker's check) ----
pp=$(t_env_probe HH_PROBE_TEST=1) || pp=""
[ -n "$pp" ] || { ( HH_PROBE_TEST=1 bash -c 'exec -a claude sleep 30' ) & pp=$!; }   # a platform binary: readable on Linux only
t_track "$pp"; sleep 0.5
hh_env_has "$pp" HH_PROBE_TEST=1; rc=$?
if [ "$rc" -eq 2 ]; then
  echo "  SKIP only Apple platform binaries were found (no node): macOS shows no environment for them in ps -E, so the marker's check cannot be tested here"
  assert_eq "an environment that cannot be read is told apart from an absent variable" "$rc" "2"
else
  assert_eq "a variable the process was launched with is found" "$rc" "0"
  hh_env_has "$pp" HH_PROBE_TEST=2; assert_status "...another value is not" $? 1
  hh_env_has "$pp" HH_NOT_THERE=1; assert_status "...nor a variable it lacks" $? 1
fi
kill "$pp" 2>/dev/null
# a marker spelled in the process's own arguments is not one it was launched with
pa=$(t_env_probe HH_PROBE_OTHER=1 HH_PROBE_ARG=1) || pa=""
if [ -n "$pa" ]; then
  t_track "$pa"; sleep 0.5
  hh_env_has "$pa" HH_PROBE_OTHER=1; assert_status "a variable the process has is found beside an argument that looks like one" $? 0
  hh_env_has "$pa" HH_PROBE_ARG=1; assert_status "...a marker spelled only in its arguments is absent" $? 1
  kill "$pa" 2>/dev/null
else echo "  SKIP only Apple platform binaries were found (no node): the argument-spelled marker cannot be tested here"; fi
t_done
