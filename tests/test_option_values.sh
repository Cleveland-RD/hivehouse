#!/usr/bin/env bash
# plugin.json lists no values for commit_style, effort_builder, effort_reviewer or permission_mode_local, so each tool that takes one
# refuses a bad value itself: hh-spawn and hh-remote-sync (effort), hh-gate-verify (style), hh-settings option and resolve.
. "$(dirname "$0")/lib.sh"
t_setup
r=$(t_repo proj); cd "$r" || exit 2; echo role > "$T_TMP/impl.md"; echo rules > "$T_TMP/RULES.md"

echo "-- plugin.json declares no options list"
assert_eq "no option lists" "$(jq '[.userConfig[] | select(has("options"))] | length' "$HH_REPO_ROOT/.claude-plugin/plugin.json")" 0

echo "-- hh-spawn: effort is exactly one of five (the mode is unknown on purpose, so a good effort stops there, after the effort check)"
sp() { hh-spawn --agent x --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort "$1" --mode nosuchmode 2>&1; }
for e in low medium high xhigh max; do
  assert_contains "effort $e passes the effort check" "$(sp "$e")" "unknown permission mode"
done
for e in extreme Medium "medium " "low;x" "-x" "opus[1m]" xhigh2; do
  out=$(sp "$e"); assert_contains "effort '$e' refused" "$out" "bad effort"
done

echo "-- hh-remote-sync start-agent: the same five"
for e in extreme High "-x"; do
  out=$(hh-remote-sync start-agent testhost "$r" impl1 --model sonnet --effort "$e" --mode auto 2>&1); rc=$?
  assert_status "remote effort '$e' refused" $rc 4; assert_contains "...and says so" "$out" "bad effort"
done

echo "-- hh-settings option"
opt() { hh-settings option "$@" 2>&1; }
for e in low medium high xhigh max; do assert_eq "effort_builder $e" "$(opt effort_builder "$e")" "$e"; assert_eq "effort_reviewer $e" "$(opt effort_reviewer "$e")" "$e"; done
for e in extreme Max ultra; do
  opt effort_builder "$e" >/dev/null; assert_status "effort_builder $e refused" $? 4
  opt effort_reviewer "$e" >/dev/null; assert_status "effort_reviewer $e refused" $? 4
done
for s in conventional free; do assert_eq "commit_style $s" "$(opt commit_style "$s")" "$s"; done
opt commit_style loose >/dev/null; assert_status "commit_style loose refused" $? 4
for m in plan dontAsk default acceptEdits auto; do assert_eq "permission_mode_local $m" "$(opt permission_mode_local "$m")" "$m"; done
for m in yolo bypassPermissions Auto; do opt permission_mode_local "$m" >/dev/null; assert_status "permission_mode_local $m refused" $? 4; done
assert_eq "an unsaved placeholder reads the default" "$(opt effort_builder '${user_config.effort_builder}')" "medium"
assert_eq "...for the style" "$(opt commit_style '${user_config.commit_style}')" "conventional"

echo "-- hh-gate-verify --style and hh-settings resolve"
base=$(git rev-parse HEAD); echo x > f.txt; git add f.txt; git -c user.name=t -c user.email=t@example.org commit -qm "feat: add f" || exit 2
hh-gate-verify commits "$base..HEAD" --max-files 5 --style loose --attribution deny >/dev/null 2>&1; assert_status "style loose refused" $? 64
hh-gate-verify commits "$base..HEAD" --max-files 5 --style Free --attribution deny >/dev/null 2>&1; assert_status "style Free refused" $? 64
for s in conventional free; do hh-gate-verify commits "$base..HEAD" --max-files 5 --style "$s" --attribution deny >/dev/null 2>&1; assert_status "style $s accepted" $? 0; done
hh-settings resolve permission_mode yolo >/dev/null 2>&1; assert_status "resolve refuses an unknown mode" $? 4
hh-settings resolve permission_mode bypassPermissions >/dev/null 2>&1; assert_status "resolve refuses bypass as the owner's value" $? 4
cd /; t_teardown; t_done
