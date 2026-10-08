#!/usr/bin/env bash
# every executable that needs a project, run outside any repository with no HH_PROJECT, exits 2 and writes nothing.
# The ones that do not need a project say so here: hh-slot and hh-disk work anywhere (the slot is machine-wide), and the
# SessionStart hook never fails a session, so it exits 0 and stays silent.
. "$(dirname "$0")/lib.sh"
t_setup
echo role > "$T_TMP/role.md"; echo rules > "$T_TMP/RULES.md"
out="$T_TMP/norepo"; mkdir "$out"; cd "$out"
before_home=$(find "$HIVEHOUSE_HOME" | sort)
home_before=$(ls -A "$HOME" | grep -c '^\'"$T_STATE"'$')
check() {  # check <label> <expected status> <command...>
  local label="$1" want="$2"; shift 2
  "$@" </dev/null >/dev/null 2>&1; assert_status "$label outside a repo" $? "$want"
}
check "hh-manifest list" 2 hh-manifest list
check "hh-manifest add" 2 hh-manifest add dir path="$T_TMP/x"
check "hh-settings resolve" 2 hh-settings resolve files_per_commit 5
check "hh-context" 2 hh-context impl
check "hh-context --all" 2 hh-context --all
check "hh-rotate" 2 hh-rotate impl
check "hh-self-rotate" 2 hh-self-rotate impl
check "hh-spawn" 2 hh-spawn --agent impl --role "$T_TMP/role.md" --rules "$T_TMP/RULES.md" --model m --effort e --mode auto
check "hh-spawn --self" 2 hh-spawn --self --agent orchestrator
check "hh-slot status (machine-wide)" 0 hh-slot status
check "hh-disk (no project needed)" 0 hh-disk --path "$T_TMP" --min-gb 0
check "hh-session-hook (never fails a session)" 0 hh-session-hook
# the same with HH_PROJECT naming a directory that does not exist
export HH_PROJECT="$T_TMP/nope"
check "hh-manifest list with a missing HH_PROJECT" 2 hh-manifest list
check "hh-context with a missing HH_PROJECT" 2 hh-context impl
check "hh-rotate with a missing HH_PROJECT" 2 hh-rotate impl
check "hh-settings with a missing HH_PROJECT" 2 hh-settings resolve files_per_commit 5
check "hh-spawn with a missing HH_PROJECT" 2 hh-spawn --agent impl --role "$T_TMP/role.md" --rules "$T_TMP/RULES.md" --model m --effort e --mode auto
unset HH_PROJECT
# nothing was written anywhere
[ ! -e "$out/$T_STATE" ] && [ ! -e /$T_STATE ] && ok "no $T_STATE in the cwd or at /" || bad "a $T_STATE appeared outside a repo"
assert_eq "no $T_STATE appeared in HOME" "$(ls -A "$HOME" | grep -c "^\\$T_STATE\$")" "$home_before"
assert_eq "nothing appeared in the machine home" "$(find "$HIVEHOUSE_HOME" | sort)" "$before_home"
assert_eq "nothing appeared in the cwd" "$(ls -A "$out")" ""
[ ! -e "$T_TMP/nope" ] && ok "a missing HH_PROJECT was not created" || bad "a missing HH_PROJECT was created"
cd /; t_teardown; t_done
