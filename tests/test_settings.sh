#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
t_setup
r=$(t_repo proj); cd "$r"; mkdir -p $T_STATE
set_project() { printf '%s\n' "$1" > $T_STATE/settings.json; }
res() { hh-settings resolve "$1" "$2" 2>/dev/null; }

# no project file: the owner's value, for every key
rm -f $T_STATE/settings.json
assert_eq "no file: mode" "$(res permission_mode auto)" "auto"
assert_eq "no file: ceiling" "$(res overnight_ceiling_usd 50)" "50"
assert_eq "no file: attribution" "$(res allow_attribution false)" "false"
assert_eq "no file: files" "$(res files_per_commit 5)" "5"

# permission_mode: lower wins, plan = dontAsk < default < acceptEdits < auto
set_project '{"permission_mode":"default"}'; assert_eq "mode tighter" "$(res permission_mode auto)" "default"
set_project '{"permission_mode":"auto"}';    assert_eq "mode looser keeps owner" "$(res permission_mode default)" "default"
hh-settings resolve permission_mode default >/dev/null 2>"$T_TMP/err"; assert_contains "looser says so" "$(cat "$T_TMP/err")" "looser"
set_project '{"permission_mode":"acceptEdits"}'; assert_eq "acceptEdits beats auto" "$(res permission_mode auto)" "acceptEdits"
set_project '{"permission_mode":"auto"}';        assert_eq "auto does not beat acceptEdits" "$(res permission_mode acceptEdits)" "acceptEdits"
set_project '{"permission_mode":"plan"}';    assert_eq "plan beats acceptEdits" "$(res permission_mode acceptEdits)" "plan"
set_project '{"permission_mode":"dontAsk"}';    assert_eq "dontAsk beats acceptEdits" "$(res permission_mode acceptEdits)" "dontAsk"
set_project '{"permission_mode":"dontAsk"}';    assert_eq "dontAsk beats auto" "$(res permission_mode auto)" "dontAsk"
set_project '{"permission_mode":"auto"}';       assert_eq "auto does not beat dontAsk" "$(res permission_mode dontAsk)" "dontAsk"
set_project '{"permission_mode":"default"}';    assert_eq "default does not beat plan" "$(res permission_mode plan)" "plan"
set_project '{"permission_mode":"bypassPermissions"}'; assert_eq "project bypass never effective" "$(res permission_mode acceptEdits)" "acceptEdits"
set_project '{}'; hh-settings resolve permission_mode bypassPermissions >/dev/null 2>&1; assert_status "owner bypass refused" $? 4
set_project '{"permission_mode":"yolo"}'; hh-settings resolve permission_mode auto >/dev/null 2>&1; assert_status "unknown project mode refused" $? 4
set_project '{}'; hh-settings resolve permission_mode yolo >/dev/null 2>&1; assert_status "unknown owner mode refused" $? 4

# overnight_ceiling_usd: lower wins
set_project '{"overnight_ceiling_usd":20}';  assert_eq "ceiling tighter" "$(res overnight_ceiling_usd 50)" "20"
set_project '{"overnight_ceiling_usd":80}';  assert_eq "ceiling looser keeps owner" "$(res overnight_ceiling_usd 50)" "50"
set_project '{"overnight_ceiling_usd":2.5}'; assert_eq "ceiling decimal" "$(res overnight_ceiling_usd 50)" "2.5"
set_project '{"overnight_ceiling_usd":"lots"}'; hh-settings resolve overnight_ceiling_usd 50 >/dev/null 2>&1; assert_status "non-number refused" $? 4

# allow_attribution: false wins
set_project '{"allow_attribution":false}'; assert_eq "attribution tighter" "$(res allow_attribution true)" "false"
set_project '{"allow_attribution":true}';  assert_eq "attribution looser keeps owner" "$(res allow_attribution false)" "false"
set_project '{"allow_attribution":true}';  assert_eq "both true" "$(res allow_attribution true)" "true"
set_project '{"allow_attribution":"yes"}'; hh-settings resolve allow_attribution true >/dev/null 2>&1; assert_status "non-boolean refused" $? 4

# files_per_commit: lower wins
set_project '{"files_per_commit":3}';  assert_eq "files tighter" "$(res files_per_commit 5)" "3"
set_project '{"files_per_commit":9}';  assert_eq "files looser keeps owner" "$(res files_per_commit 5)" "5"
set_project '{"files_per_commit":0}';  hh-settings resolve files_per_commit 5 >/dev/null 2>&1; assert_status "zero refused" $? 4
set_project '{"files_per_commit":2.5}'; hh-settings resolve files_per_commit 5 >/dev/null 2>&1; assert_status "fraction refused" $? 4

# an empty project value is a refusal, not an absent key
set_project '{"files_per_commit":""}'; hh-settings resolve files_per_commit 5 >/dev/null 2>&1; assert_status "empty project value refused" $? 4

# unknown keys
hh-settings resolve nosuch 1 >/dev/null 2>&1; assert_status "unknown key refused" $? 4
set_project '{"allow_attributon":false}'; hh-settings resolve allow_attribution true >/dev/null 2>&1; assert_status "unknown key in the file refused" $? 4
set_project '{not json'; hh-settings resolve files_per_commit 5 >/dev/null 2>&1; assert_status "bad json refused" $? 4
hh-settings resolve >/dev/null 2>&1; assert_status "usage" $? 64

# a tracked .hivehouse is refused, with no value printed
set_project '{"files_per_commit":1}'; git add -f $T_STATE/settings.json; git -c user.email=t@t -c user.name=t commit -qm track
out=$(hh-settings resolve files_per_commit 5 2>/dev/null); assert_status "tracked refused" $? 3
assert_eq "tracked prints nothing" "$out" ""

# outside any repo: exit 2, nothing written
cd /; other=$(mktemp -d "$T_TMP/o.XXXXXX"); cd "$other"
hh-settings resolve files_per_commit 5 >/dev/null 2>&1; assert_status "outside a repo" $? 2
[ ! -e "$other/$T_STATE" ] && ok "nothing written" || bad "wrote $T_STATE outside a repo"
cd /; t_teardown; t_done
