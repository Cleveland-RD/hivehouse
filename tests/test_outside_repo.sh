#!/usr/bin/env bash
# A1: every executable that needs a project, run outside any repository with no HM_PROJECT, exits 2 and writes nothing.
# The ones that do not need a project say so here: hm-slot and hm-disk work anywhere (the slot is machine-wide), and the
# SessionStart hook never fails a session, so it exits 0 and stays silent.
. "$(dirname "$0")/lib.sh"
t_setup
echo role > "$T_TMP/role.md"; echo rules > "$T_TMP/RULES.md"
out="$T_TMP/norepo"; mkdir "$out"; cd "$out"
before_home=$(find "$HIVEMIND_HOME" | sort)
home_before=$(ls -A "$HOME" | grep -c '^\'"$T_STATE"'$')
check() {  # check <label> <expected status> <command...>
  local label="$1" want="$2"; shift 2
  "$@" </dev/null >/dev/null 2>&1; assert_status "$label outside a repo" $? "$want"
}
check "hm-manifest list" 2 hm-manifest list
check "hm-manifest add" 2 hm-manifest add dir path="$T_TMP/x"
check "hm-settings resolve" 2 hm-settings resolve files_per_commit 5
check "hm-context" 2 hm-context impl
check "hm-context --all" 2 hm-context --all
check "hm-rotate" 2 hm-rotate impl
check "hm-self-rotate" 2 hm-self-rotate impl
check "hm-spawn" 2 hm-spawn --agent impl --role "$T_TMP/role.md" --rules "$T_TMP/RULES.md" --model m --effort e --mode auto
check "hm-spawn --self" 2 hm-spawn --self --agent orchestrator
check "hm-slot status (machine-wide)" 0 hm-slot status
check "hm-disk (no project needed)" 0 hm-disk --path "$T_TMP" --min-gb 0
check "hm-session-hook (never fails a session)" 0 hm-session-hook
# the same with HM_PROJECT naming a directory that does not exist
export HM_PROJECT="$T_TMP/nope"
check "hm-manifest list with a missing HM_PROJECT" 2 hm-manifest list
check "hm-context with a missing HM_PROJECT" 2 hm-context impl
check "hm-rotate with a missing HM_PROJECT" 2 hm-rotate impl
check "hm-settings with a missing HM_PROJECT" 2 hm-settings resolve files_per_commit 5
check "hm-spawn with a missing HM_PROJECT" 2 hm-spawn --agent impl --role "$T_TMP/role.md" --rules "$T_TMP/RULES.md" --model m --effort e --mode auto
unset HM_PROJECT
# nothing was written anywhere
[ ! -e "$out/$T_STATE" ] && [ ! -e /$T_STATE ] && ok "no $T_STATE in the cwd or at /" || bad "a $T_STATE appeared outside a repo"
assert_eq "no $T_STATE appeared in HOME" "$(ls -A "$HOME" | grep -c "^\\$T_STATE\$")" "$home_before"
assert_eq "nothing appeared in the machine home" "$(find "$HIVEMIND_HOME" | sort)" "$before_home"
assert_eq "nothing appeared in the cwd" "$(ls -A "$out")" ""
[ ! -e "$T_TMP/nope" ] && ok "a missing HM_PROJECT was not created" || bad "a missing HM_PROJECT was created"
cd /; t_teardown; t_done
