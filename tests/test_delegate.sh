#!/usr/bin/env bash
# The away switch (bin/hm-lib.sh): delegate mode is on exactly while a file only root can have written is valid. The
# predicate takes the path and the owner it requires; production passes only the fixed path and root, so these tests
# pass a fixture path and this user's own uid (and root, for the "a user wrote it" case).
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
ME=$(id -u); NOW=$(date +%s)
D="$T_TMP/dg/area"; F="$D/delegate"
mkf() {  # mkf [until] [hub line]: a valid file, then what the case changes
  mkdir -p "$D"; chmod 755 "$D" "$T_TMP/dg"
  printf 'hivemind-delegate 1\n%s\nuntil=%s\n' "${2:-hub=/work}" "${1:-$((NOW + 3600))}" > "$F"; chmod 644 "$F"
}
ok_() { hm_delegate_read "$F" "${1:-$ME}" "${2:-$NOW}" >/dev/null 2>&1; }
mkf
# a fixture under a world-writable folder (TMPDIR in /tmp) could never be valid: say so rather than fail every case
if ! ok_; then
  hm_delegate_read "$F" "$ME" "$NOW" >/dev/null 2>&1
  echo "  SKIP the fixture folder is not eligible here: $HM_DELEGATE_WHY"; t_done; exit 0
fi

# ---- the path and the one production line ----
case "$(uname -s)" in
  Darwin) assert_eq "the macOS path is under /Library (/etc is a link there)" "$(hm_delegate_path)" "/Library/Application Support/hivemind/delegate" ;;
  *)      assert_eq "the Linux path" "$(hm_delegate_path)" "/etc/hivemind/delegate" ;;
esac
assert_eq "production reads the fixed path as root, and nothing else" "$(grep -c '^hm_delegate_now() { hm_delegate_read "$(hm_delegate_path)" 0; }$' "$HM_REPO_ROOT/bin/hm-lib.sh")" "1"

# ---- a valid file ----
out=$(hm_delegate_read "$F" "$ME" "$NOW"); assert_status "a file as the root user would make it" $? 0
assert_eq "...prints the hub and the time" "$out" "$(printf '/work\t%s' "$((NOW + 3600))")"
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
