#!/usr/bin/env bash
# The away hook and every check that grants away powers take their jq from one resolver (hh_jq_fixed): a jq that root owns, at one of three
# fixed paths, with every folder above it root's too. Nothing a session controls (PATH, the environment, a jq in its own folder) can stand
# in for it, and with none the hook denies and bypass is refused.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
REAL=""; for c in /usr/bin/jq /usr/local/bin/jq /opt/homebrew/bin/jq; do hh_path_trusted "$c" file 0 loose && REAL=$c && break; done
[ -n "$REAL" ] || { echo "  SKIP no root-owned jq on this machine: the resolver has nothing to find"; t_done; exit 0; }
NB=$(t_jq_bin nb "/nonexistent/a /nonexistent/b /nonexistent/c")
proj=$(t_repo proj); hub="$T_TMP/hub"; mkdir -p "$hub/$T_HUB" "$proj/$T_STATE"
hook() {  # hook <hook script> <json> [env]...: the hook as a marked session; sets RC and ERR
  local h=$1 j=$2; shift 2
  ERR=$(printf '%s' "$j" | env "$@" HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$h" 2>&1 >/dev/null); RC=$?
}
tc() { jq -nc --arg c "$1" --arg d "$proj" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }

# ---- the resolver ----
assert_eq "nothing is resolved when the library loads: HH_JQ is empty and not done" "$(env HH_JQ=/tmp/evil HH_JQ_DONE=1 /bin/bash -p -c ". '$HH_REPO_ROOT/bin/hh-lib.sh'; echo \"[\$HH_JQ] \$HH_JQ_DONE\"")" "[] 0"
assert_eq "...whatever the environment held, even under bash -p" "$(env HH_JQ=/tmp/evil HH_JQ_DONE=1 /bin/bash -p -c ". '$HH_REPO_ROOT/bin/hh-lib.sh'; hh_jq_resolve; echo \"\$HH_JQ \$HH_JQ_DONE\"")" "$REAL 1"
hh_jq_resolve
assert_eq "hh_jq_resolve sets HH_JQ to the resolver's answer" "$HH_JQ" "$(hh_jq_fixed)"
assert_eq "...a root-owned jq, found" "$(hh_path_trusted "$HH_JQ" file 0 loose && echo yes)" "yes"
HH_JQ=/changed; hh_jq_resolve; assert_eq "...once: a later call leaves it" "$HH_JQ" "/changed"; HH_JQ=$(hh_jq_fixed)
mkdir -p "$T_TMP/ujq"; chmod 755 "$T_TMP/ujq"; cp "$REAL" "$T_TMP/ujq/jq"; chmod 755 "$T_TMP/ujq/jq"
UB=$(t_jq_bin ub "$T_TMP/ujq/jq"); r=$(. "$UB/hh-lib.sh"; hh_jq_resolve; echo "[$HH_JQ]"); assert_eq "a jq the user owns, at a candidate path, is refused" "$r" "[]"
UB2=$(t_jq_bin ub2 "/nonexistent/a /nonexistent/b $REAL"); r=$(. "$UB2/hh-lib.sh"; hh_jq_resolve; echo "[$HH_JQ]"); assert_eq "...the next candidate that is root's is taken" "$r" "[$REAL]"
assert_eq "the three paths are the ones the plan names" "$(grep '^hh_jq_candidates() { echo ' "$HH_REPO_ROOT/bin/hh-lib.sh")" "hh_jq_candidates() { echo '/usr/bin/jq /usr/local/bin/jq /opt/homebrew/bin/jq'; }"
mkdir -p "$T_TMP/ujq2/sub"; chmod 777 "$T_TMP/ujq2"; cp "$REAL" "$T_TMP/ujq2/sub/jq"
# a root-owned file in a folder the user can write is no better: only a file whose every folder above is root's passes (here the owner check stops it first)
UB3=$(t_jq_bin ub3 "$T_TMP/ujq2/sub/jq"); r=$(. "$UB3/hh-lib.sh"; hh_jq_resolve; echo "[$HH_JQ]"); assert_eq "a jq in a folder the user controls is refused" "$r" "[]"

# a root-owned file in a folder the group can write is refused for the folder, not the file (only the parents decide here)
gf=$(find /Applications /Library -maxdepth 1 -type f -user root 2>/dev/null | head -1)
if [ -n "$gf" ] && ! hh_path_trusted "${gf%/*}" dir 0 loose; then
  GB=$(t_jq_bin gb "$gf"); r=$(. "$GB/hh-lib.sh"; hh_jq_resolve; echo "[$HH_JQ]"); assert_eq "a root-owned file under a folder the group can write is refused" "$r" "[]"
else echo "  SKIP no root-owned file under a group-writable folder to use as a candidate here"; fi

# ---- the grant functions never call a bare jq, and hh_delegate_for_project's read of projects.json is pinned to the root-owned one ----
body() {  # body <function>: its code in hh-lib.sh, comments dropped
  awk -v f="$1" '$0 ~ "^"f"\\(\\) \\{" {p=1} p {print} p && /^}/ {p=0}' "$HH_REPO_ROOT/bin/hh-lib.sh" | sed 's/#.*//; s/"[^"]*"//g'   # comments and quoted text (messages) are no call
}
for f in hh_delegate_mine hh_delegate_for_project hh_hub_records_trusted hh_check_mode hh_bypass_launch hh_team_roots hh_repo_home hh_self_entry hh_session_record; do
  [ -n "$(body $f)" ] || { bad "$f was not found in hh-lib.sh"; continue; }
  assert_eq "no bare jq in $f" "$(body $f | grep -cE '(^|[^A-Za-z_$"-])jq[[:space:]]')" "0"
done
# a jq first on PATH that lists a stranger's folder as a project of the hub: the listing is read with the root-owned jq, so it changes nothing
FP="$T_TMP/fakeproj"; mkdir -p "$FP"
printf '#!/bin/sh\ncase "$*" in *projects*) printf "fake\\t%%s\\n" "$FAKE_HOME" ;; esac\n' > "$FP/jq"; chmod +x "$FP/jq"
# ---- no root-owned jq: the hook denies and bypass is refused ----
# a complete fixture hub and a valid file, read as this user (the seam t_delegate_bin gives the executables): only the jq differs
DG="$T_TMP/dg/area"; mkdir -p "$DG" "$T_TMP/fh/$T_HUB"; chmod 755 "$T_TMP/dg" "$DG" "$T_TMP/fh" "$T_TMP/fh/$T_HUB"
printf '{"projects":[]}\n' > "$T_TMP/fh/$T_HUB/projects.json"; printf '{"name":"hub"}\n' > "$T_TMP/fh/$T_HUB/hub.json"; chmod 644 "$T_TMP/fh/$T_HUB/"*.json
printf "$T_DELEGATE_LINE1"'\nhub=%s\nuntil=%s\nmcp=\n' "$(cd "$T_TMP/fh" && pwd -P)" "$(( $(date +%s) + 3600 ))" > "$DG/delegate"; chmod 644 "$DG/delegate"
mine_with() {  # mine_with <hh-lib.sh>: hh_delegate_mine on the fixture, in a shell of its own: "<status> <reason>"
  ( . "$1"; hh_delegate_now() { hh_delegate_read "$DG/delegate" "$(id -u)"; }; hh_delegate_mine; echo "$? $HH_DELEGATE_WHY" )
}
if hh_path_trusted "$DG/delegate" file "$(id -u)" strict; then
  assert_eq "the fixture is a valid file of a complete hub" "$(mine_with "$HH_REPO_ROOT/bin/hh-lib.sh")" "0 "
  r=$(mine_with "$(t_jq_bin nb0 "/nonexistent/a")/hh-lib.sh"); assert_contains "...and with no root-owned jq it is refused" "$r" "1 no root-owned jq"
  fp_with() {  # fp_with <hh-lib.sh> <root> [PATH]: hh_delegate_for_project on the fixture hub (which lists no project): its status
    ( . "$1"; hh_delegate_now() { hh_delegate_read "$DG/delegate" "$(id -u)"; }; PATH="${3:-$PATH}"; FAKE_HOME="$2" hh_delegate_for_project "$2"; echo $? )
  }
  assert_eq "a home the fixture hub does not list is refused" "$(fp_with "$HH_REPO_ROOT/bin/hh-lib.sh" "$proj")" "1"
  assert_eq "...and still is with a jq on PATH that says it is listed" "$(fp_with "$HH_REPO_ROOT/bin/hh-lib.sh" "$proj" "$FP:$PATH")" "1"
else echo "  SKIP the fixture folder is not eligible here"; fi
hook "$HH_REPO_ROOT/bin/hh-away-hook" "$(tc 'ls')"; assert_status "the hook allows a harmless command with a root-owned jq" $RC 0
hook "$NB/hh-away-hook" "$(tc 'ls')"; assert_status "the hook denies with no root-owned jq" $RC 2
assert_contains "...and says why" "$ERR" "jq"
r=$(. "$NB/hh-lib.sh"; hh_delegate_mine; echo "$? $HH_DELEGATE_WHY"); assert_contains "hh_delegate_mine refuses with no root-owned jq" "$r" "1 "
assert_contains "...and says so" "$r" "root-owned jq"
r=$(. "$NB/hh-lib.sh"; hh_check_mode bypassPermissions test "$proj" 2>&1); rc=$?; assert_status "bypass is refused with no root-owned jq" $rc 4

# ---- a fake jq and a fake cat first on PATH change nothing the hook decides ----
FB="$T_TMP/fake"; mkdir -p "$FB"
cat > "$FB/jq" <<'J'
#!/bin/sh
# permissive answers: a Bash tool call of `ls`, in a folder, whatever the real input is
case "$*" in
  *tool_name*) echo Bash ;;
  *tool_input.command*) echo ls ;;
  *.cwd*) echo / ;;
esac
J
printf '#!/bin/sh\necho %s\n' "'{\"tool_name\":\"Bash\",\"cwd\":\"/\",\"tool_input\":{\"command\":\"ls\"}}'" > "$FB/cat"
chmod +x "$FB/jq" "$FB/cat"
hook "$HH_REPO_ROOT/bin/hh-away-hook" "$(tc 'git push origin main')" PATH="$FB:$PATH"; assert_status "a fake jq and cat first on PATH: git push is still denied" $RC 2
assert_contains "...for the real reason" "$ERR" "git push"
hook "$HH_REPO_ROOT/bin/hh-away-hook" "$(tc 'git push origin main')" PATH="$FB:$PATH" HH_JQ="$FB/jq"; assert_status "...and HH_JQ in the environment changes nothing" $RC 2

# ---- what the hook runs ----
H="$HH_REPO_ROOT/bin/hh-away-hook"
assert_eq "the PATH line is the hook's first command" "$(grep -v '^[[:space:]]*#' "$H" | grep -v '^[[:space:]]*$' | head -1 | awk '{print $1}')" "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
assert_eq "no 'command jq' in the hook" "$(grep -cE 'command[[:space:]]+jq' "$H")" "0"
assert_eq "no 'xargs jq' in the hook" "$(grep -cE 'xargs[[:space:]]+jq' "$H")" "0"
assert_eq "no 'command -v jq' in the hook" "$(grep -cE 'command[[:space:]]+-v[[:space:]]+jq' "$H")" "0"
assert_eq "no bare jq call in the hook: every one is \"\$HH_JQ\"" "$(grep -v '^[[:space:]]*#' "$H" | grep -E '(\||<\(|\$\()[[:space:]]*jq[[:space:]]' | wc -l | tr -d ' ')" "0"
t_done
