#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj)
assert_eq "home is HIVEHOUSE_HOME" "$(hm_home)" "$HIVEHOUSE_HOME"
( unset HIVEHOUSE_HOME; assert_eq "home defaults" "$(hm_home)" "$HOME/$T_STATE" )
assert_eq "root from repo" "$(cd "$r" && hm_project_root)" "$r"
git -C "$r" worktree add -q "$T_TMP/proj-wt" -b wt
assert_eq "root from a worktree is the main repo" "$(cd "$T_TMP/proj-wt" && hm_project_root)" "$r"
assert_eq "HM_PROJECT wins" "$(cd "$T_TMP" && HM_PROJECT="$r" hm_project_root)" "$r"
# A1: a missing HM_PROJECT or no repo fails with 2, and the failure propagates through a substitution
(cd "$T_TMP" && HM_PROJECT="$T_TMP/nope" hm_project_root >/dev/null 2>&1); assert_status "missing HM_PROJECT dir is exit 2" $? 2
mkdir "$T_TMP/norepo"; (cd "$T_TMP/norepo" && hm_project_root >/dev/null 2>&1); assert_status "outside a repo is exit 2" $? 2
(cd "$T_TMP/norepo" && x=$(hm_state) || exit $?; echo "reached" >"$T_TMP/reached") >/dev/null 2>&1; assert_status "hm_state failure propagates" $? 2
[ -e "$T_TMP/reached" ] && bad "caller stopped after a failed substitution" || ok "caller stopped after a failed substitution"
(cd "$T_TMP/norepo" && hm_ensure_state >/dev/null 2>&1); assert_status "ensure_state outside a repo is exit 2" $? 2
[ -e "$T_TMP/norepo/$T_STATE" ] || [ -e /$T_STATE ] && bad "no state written outside a repo" || ok "no state written outside a repo"
(cd "$r" && hm_ensure_state) ; assert_contains "state excluded" "$(cat "$r/.git/info/exclude")" "/$T_STATE/"
(cd "$T_TMP/proj-wt" && hm_ensure_state); assert_eq "exclude written once" "$(grep -c "/$T_STATE/" "$r/.git/info/exclude")" "1"
assert_eq "state dir path" "$(cd "$T_TMP/proj-wt" && hm_state)" "$r/$T_STATE"
mkdir -p "$r/$T_STATE"; echo x > "$r/$T_STATE/leak"; git -C "$r" add -f $T_STATE/leak
(cd "$r" && hm_ensure_state 2>/dev/null); assert_status "refuses tracked $T_STATE" $? 3
k1=$(hm_project_key "$r"); k2=$(hm_project_key "$T_TMP/proj2")
[ "$k1" != "$k2" ] && ok "project keys differ by path" || bad "project keys differ by path"
assert_eq "pane key is stable" "$(hm_pane_key /s %1)" "$(hm_pane_key /s %1)"
[ "$(hm_pane_key /s %1)" != "$(hm_pane_key /s %2)" ] && ok "pane keys differ by pane" || bad "pane keys differ by pane"
assert_eq "json_get reads a field" "$(echo '{"a":{"b":7}}' > "$T_TMP/j"; hm_json_get "$T_TMP/j" .a.b)" "7"
assert_eq "json_get empty when absent" "$(hm_json_get "$T_TMP/j" .zz)" ""
# wait_idle: still, an empty prompt and no dialog; a pane that is still but not idle is never reported idle
new_pane() {  # new_pane <fake claude behaviour> -> pane id running the fake claude
  hm_tmux new-session -d -s "t$RANDOM" -x 200 -y 50 -P -F '#{pane_id}' -e "HM_FAKE_CLAUDE=$1" "claude --name probe"
}
pane=$(new_pane idle); wait_idle "$pane" 2 20; assert_status "idle pane is idle" $? 0
assert_contains "fake claude printed its argv" "$(hm_tmux capture-pane -p -t "$pane")" "ARGV: --name"
pane=$(new_pane dialog); wait_idle "$pane" 2 6; assert_status "a dialog is never idle, and is told apart" $? 3
# a dialog does not go away by itself: once it has been still, it is told at once rather than waited out
pane=$(new_pane dialog); t0=$(date +%s); wait_idle "$pane" 2 60; rc=$?; took=$(( $(date +%s) - t0 ))
assert_status "a still dialog is told" "$rc" 3
[ "$took" -lt 20 ] && ok "...as soon as it is still (${took}s of 60)" || bad "a still dialog was waited out: ${took}s of 60"
pane=$(new_pane bare); wait_idle "$pane" 2 6; assert_status "still with no prompt is not idle" $? 1
pane=$(new_pane dialogprompt); wait_idle "$pane" 2 6; assert_status "a dialog above an empty prompt is not idle" $? 3
pane=$(new_pane ticking); wait_idle "$pane" 2 5; assert_status "an empty prompt that keeps changing is not idle" $? 1
pane=$(new_pane quotesdialog); wait_idle "$pane" 2 20; assert_status "dialog words quoted above the prompt box are not a dialog" $? 0
pane=$(new_pane idle); wait_idle "$pane" 2 20
assert_contains "the real prompt is a rule, a bullet and a non-breaking space" "$(hm_tmux capture-pane -p -t "$pane" | LC_ALL=C grep -c $'\xe2\x9d\xaf\xc2\xa0')" "1"
printf '%s\n' '──────── r ────────' $'❯\xc2\xa0\033[2mTry "x"\033[0m' '──────── r ────────' 'footer' | hm_pane_idle_text; assert_status "an escaped dim placeholder after a no-break space is an empty prompt" $? 0
printf '%s\n' '──────── r ────────' $'❯\xc2\xa0typed words' '──────── r ────────' 'footer' | hm_pane_idle_text; assert_status "typed words are not an empty prompt" $? 1
printf '%s\n' '──────── r ────────' $'❯\xc2\xa0' '──────── r ────────' 'footer' | hm_pane_idle_text; assert_status "a bare prompt with a no-break space is empty" $? 0
printf '%s\n' '──────── r ────────' $'❯ \033[38;5;2mx\033[0m' '──────── r ────────' | hm_pane_idle_text; assert_status "a colour 2 in the 256 palette is not a dim run" $? 1
printf '%s\n' 'Enter to confirm' | hm_pane_idle_text; assert_status "the trust dialog's own words are a dialog" $? 3
printf '%s\n' 'Yes, I trust this folder' | hm_pane_idle_text; assert_status "I trust this folder is a dialog" $? 3
printf '%s\n' 'said: Esc to cancel' '──────── r ────────' $'❯\xc2\xa0' '──────── r ────────' 'footer' | hm_pane_idle_text; assert_status "words above the prompt box's top rule are not scanned" $? 0
printf '%s\n' '──────── r ────────' 'Esc to cancel' $'❯\xc2\xa0' '──────── r ────────' 'footer' | hm_pane_idle_text; assert_status "words inside the prompt box are scanned" $? 3
printf '%s\n' '──────── r ────────' $'❯\xc2\xa0/clear' '──────── r ────────' 'footer' | hm_pane_prompt_line | grep -q '/clear' && ok "the prompt line is found inside the box, not by the last line" || bad "prompt line not found"
printf '%s\n' 'old: ❯ /clear' '──────── r ────────' $'❯\xc2\xa0\033[2mTry "x"\033[0m' '──────── r ────────' 'footer' | hm_pane_prompt_line | grep -q '/clear' && bad "an echo above the box was taken for the input line" || ok "an echo above the box is not the input line"
printf '%s\n' '──────── r ────────' $'❯\xc2\xa0older line' $'❯\xc2\xa0/clear' '──────── r ────────' 'footer' | hm_pane_prompt_line | grep -q '/clear' && ok "the last prompt-marked line in the box is the input line" || bad "the input line is the last prompt-marked line in the box"
pane=$(new_pane busy); wait_idle "$pane" 2 5; assert_status "a busy pane is not idle" $? 1
# bash 3.2's letter ranges follow the locale: under en_US.UTF-8 `[a-z]` takes é, ß and capitals. Each check runs under both.
for loc in C en_US.UTF-8; do
  for n in impl orchestrator a-b_c 9x; do (export LC_ALL=$loc; hm_is_agent_name "$n"); assert_status "agent name $n under $loc" $? 0; done
  for n in Upper é ß ｈ ı -x _x "" "a b" a.b; do (export LC_ALL=$loc; hm_is_agent_name "$n"); assert_status "not an agent name: [$n] under $loc" $? 1; done
  for n in main feat/x-1 Release_2.0; do (export LC_ALL=$loc; hm_is_branch_name "$n"); assert_status "branch name $n under $loc" $? 0; done
  for n in feat/é maiß -x "" "a b" "a;b"; do (export LC_ALL=$loc; hm_is_branch_name "$n"); assert_status "not a branch name: [$n] under $loc" $? 1; done
  for n in testhost user@Box-1.local; do (export LC_ALL=$loc; hm_is_host_name "$n"); assert_status "host name $n under $loc" $? 0; done
  for n in tésthost -oProxyCommand=x "" "a b" a/b; do (export LC_ALL=$loc; hm_is_host_name "$n"); assert_status "not a host name: [$n] under $loc" $? 1; done
done
# hm_is_claude: Claude Code's own processes are never stopped by cleanup, however they were started. Every probe is one
# process (perl rather than bash -c, whose child would outlive a kill and hold the test's output open).
ln -s /bin/sleep "$T_TMP/claude"; "$T_TMP/claude" 300 & c1=$!
bash -c 'exec -a claude sleep 300' & c2=$!
HM_FAKE_CLAUDE=busy bash "$HM_REPO_ROOT/tests/bin/claude" --name probe >/dev/null & c3=$!
perl -e 'sleep 300' -- "$T_TMP/node_modules/@anthropic-ai/claude-code/cli.js" & c4=$!
sleep 300 & n1=$!
perl -e 'sleep 300' -- --name claude-notes & n2=$!
bash -c 'exec -a -c sleep 300' & n3=$!   # an argv word that looks like an option (a login shell's -zsh)
sleep 0.5
for p in $c1 $c2 $c3 $c4; do hm_is_claude "$p" && ok "seen as claude: $(ps -o args= -p $p | cut -c1-50)" || bad "not seen as claude: $p $(ps -o args= -p $p)"; done
for p in $n1 $n2 $n3; do hm_is_claude "$p" && bad "mistaken for claude: $(ps -o args= -p $p)" || ok "not claude: $(ps -o args= -p $p | cut -c1-50)"; done
[ -z "$(hm_is_claude $n3 2>&1)" ] && ok "an option-like argv word prints nothing" || bad "hm_is_claude printed an error for an option-like argv word"
hm_is_claude 999999 && bad "a dead pid is claude" || ok "a dead pid is not claude"
kill $c1 $c2 $c3 $c4 $n1 $n2 $n3 2>/dev/null; wait $c1 $c2 $c3 $c4 $n1 $n2 $n3 2>/dev/null
# a process's start time is read in one fixed format: recorded under one locale, it matches under another (ps prints it in the caller's own:
# fr_FR "mar.  6 oct.", en_GB "Tue  6 Oct", de_DE "Di.  6 Okt.", C "Tue Oct  6")
c=$(LC_ALL=C /bin/ps -o lstart= -p $$ | sed 's/^ *//;s/ *$//'); tested=0
for loc in fr_FR.UTF-8 en_GB.UTF-8 de_DE.UTF-8; do
  if locale -a 2>/dev/null | grep -qix "$loc"; then
    raw=$(LC_ALL=$loc /bin/ps -o lstart= -p $$ | sed 's/^ *//;s/ *$//'); tested=1
    [ "$raw" != "$c" ] && ok "(ps itself prints this time differently under $loc: $raw / $c)" || bad "$loc prints the same time as C: the test below proves nothing for it"
    assert_eq "hm_lstart reads the same under $loc and C" "$(LC_ALL=$loc hm_lstart $$)" "$(LC_ALL=C hm_lstart $$)"
  else echo "  SKIP the $loc locale is not installed"; fi
done
[ "$tested" = 1 ] || echo "  SKIP no locale other than C is installed: the start time's fixed format cannot be tested here"
t_done
