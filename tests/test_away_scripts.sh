#!/usr/bin/env bash
# The second layer behind hm-away-hook (A31, A8, A25): hm-push, hm-remote-sync and hm-cleanup --finish refuse with exit 4 when
# HM_AWAY_BYPASS=1 is in their environment, and hm-cleanup --disk stays allowed. A Bash command can unset the variable for itself,
# so the hook is the guard and this is a backstop. (hm-push and hm-remote-sync are tested in test_push.sh and test_remote_sync.sh;
# hm-cleanup --finish is never run here without the marker: it signals real processes, which test_cleanup.sh does for the owner.)
# Also: these three scripts run in bash's privileged mode (#!/bin/bash -p), which ignores BASH_ENV and inherited functions.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj); cd "$r"
echo "-- hm-cleanup"
for a in "--finish" "--finish --dry-run" "--dry-run --finish"; do
  HM_AWAY_BYPASS=1 hm-cleanup $a >"$T_TMP/out" 2>"$T_TMP/err"; assert_status "the away marker refuses: hm-cleanup $a" $? 4
done
assert_contains "...saying it is hivehouse's away mode" "$(cat "$T_TMP/err")" "away mode"
assert_contains "...and to tell the owner" "$(cat "$T_TMP/err")" "owner"
[ ! -e "$r/$T_STATE" ] && ok "...before anything is written" || bad "the refused --finish wrote $T_STATE"
HM_AWAY_BYPASS=1 hm-cleanup --disk >"$T_TMP/out" 2>"$T_TMP/err"; assert_status "hm-cleanup --disk stays allowed with the marker" $? 0
HM_AWAY_BYPASS=1 hm-cleanup --bogus >/dev/null 2>&1; assert_status "a usage error is still a usage error" $? 64
HM_AWAY_BYPASS=1 hm-cleanup >/dev/null 2>&1; assert_status "...and no mode too" $? 64
HM_AWAY_BYPASS=0 hm-cleanup --disk >/dev/null 2>&1; assert_status "a marker other than 1 changes nothing" $? 0
echo "-- the shebang and what it ignores"
for s in hm-push hm-remote-sync hm-cleanup; do
  assert_eq "$s starts with #!/bin/bash -p" "$(head -1 "$HM_REPO_ROOT/bin/$s")" "#!/bin/bash -p"
done
printf 'touch "%s/benv-ran"\n' "$T_TMP" > "$T_TMP/benv.sh"
dirname() { echo /nonexistent; }; export -f dirname
for s in hm-push hm-remote-sync; do
  BASH_ENV="$T_TMP/benv.sh" "$s" >/dev/null 2>&1; rc=$?
  [ ! -e "$T_TMP/benv-ran" ] && ok "$s ignores BASH_ENV" || { bad "$s ran BASH_ENV"; rm -f "$T_TMP/benv-ran"; }
  assert_eq "$s ignores an inherited function that would hide its library (usage error, not a failure to load)" "$rc" "64"
done
BASH_ENV="$T_TMP/benv.sh" hm-cleanup >/dev/null 2>&1; rc=$?
[ ! -e "$T_TMP/benv-ran" ] && ok "hm-cleanup ignores BASH_ENV" || bad "hm-cleanup ran BASH_ENV"
assert_eq "hm-cleanup ignores an inherited function too" "$rc" "64"
unset -f dirname
echo "-- a fake dirname executable first on PATH changes nothing (the scripts find their library by parameter expansion)"
mkdir -p "$T_TMP/fakebin"; printf '#!/bin/sh\necho called >> "%s/dirname.log"\necho /nonexistent\n' "$T_TMP" > "$T_TMP/fakebin/dirname"; chmod +x "$T_TMP/fakebin/dirname"
for s in hm-push hm-remote-sync hm-cleanup; do
  PATH="$T_TMP/fakebin:$PATH" "$s" >/dev/null 2>&1; assert_status "$s with a fake dirname on PATH still reaches its usage error" $? 64
  PATH="$T_TMP/fakebin:$PATH" HM_AWAY_BYPASS=1 "$s" --finish >/dev/null 2>&1; rc=$?
  assert_status "$s with a fake dirname on PATH still refuses in a marked session" $rc 4
done
for s in hm-push hm-remote-sync hm-cleanup; do
  (cd "$HM_REPO_ROOT/bin" && bash "$s" >/dev/null 2>&1); assert_status "$s run as 'bash $s' from its own folder (no slash in \$0) finds its library" $? 64
done
[ ! -e "$T_TMP/dirname.log" ] && ok "...and the fake dirname was never called at start-up" || bad "a fake dirname on PATH was called: $(cat "$T_TMP/dirname.log" | wc -l) times"
cd /; t_teardown; t_done
