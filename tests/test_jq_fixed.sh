#!/usr/bin/env bash
# The away hook and every check that grants away powers take their jq from one resolver (hm_jq_fixed): a jq that root owns, at one of three
# fixed paths, with every folder above it root's too. Nothing a session controls (PATH, the environment, a jq in its own folder) can stand
# in for it, and with none the hook denies and bypass is refused.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
REAL=""; for c in /usr/bin/jq /usr/local/bin/jq /opt/homebrew/bin/jq; do hm_path_trusted "$c" file 0 loose && REAL=$c && break; done
[ -n "$REAL" ] || { echo "  SKIP no root-owned jq on this machine: the resolver has nothing to find"; t_done; exit 0; }
NB=$(t_jq_bin nb "/nonexistent/a /nonexistent/b /nonexistent/c")
proj=$(t_repo proj); hub="$T_TMP/hub"; mkdir -p "$hub/.hivemind-hub" "$proj/.hivemind"
hook() {  # hook <hook script> <json> [env]...: the hook as a marked session; sets RC and ERR
  local h=$1 j=$2; shift 2
  ERR=$(printf '%s' "$j" | env "$@" HM_AWAY_BYPASS=1 HM_PROJECT="$proj" HM_AWAY_HUB="$hub" HM_AWAY_MCP_ALLOW= "$h" 2>&1 >/dev/null); RC=$?
}
tc() { jq -nc --arg c "$1" --arg d "$proj" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }

# ---- the resolver ----
assert_eq "nothing is resolved when the library loads: HM_JQ is empty and not done" "$(env HM_JQ=/tmp/evil HM_JQ_DONE=1 /bin/bash -p -c ". '$HM_REPO_ROOT/bin/hm-lib.sh'; echo \"[\$HM_JQ] \$HM_JQ_DONE\"")" "[] 0"
assert_eq "...whatever the environment held, even under bash -p" "$(env HM_JQ=/tmp/evil HM_JQ_DONE=1 /bin/bash -p -c ". '$HM_REPO_ROOT/bin/hm-lib.sh'; hm_jq_resolve; echo \"\$HM_JQ \$HM_JQ_DONE\"")" "$REAL 1"
hm_jq_resolve
assert_eq "hm_jq_resolve sets HM_JQ to the resolver's answer" "$HM_JQ" "$(hm_jq_fixed)"
assert_eq "...a root-owned jq, found" "$(hm_path_trusted "$HM_JQ" file 0 loose && echo yes)" "yes"
HM_JQ=/changed; hm_jq_resolve; assert_eq "...once: a later call leaves it" "$HM_JQ" "/changed"; HM_JQ=$(hm_jq_fixed)
mkdir -p "$T_TMP/ujq"; chmod 755 "$T_TMP/ujq"; cp "$REAL" "$T_TMP/ujq/jq"; chmod 755 "$T_TMP/ujq/jq"
UB=$(t_jq_bin ub "$T_TMP/ujq/jq"); r=$(. "$UB/hm-lib.sh"; hm_jq_resolve; echo "[$HM_JQ]"); assert_eq "a jq the user owns, at a candidate path, is refused" "$r" "[]"
UB2=$(t_jq_bin ub2 "/nonexistent/a /nonexistent/b $REAL"); r=$(. "$UB2/hm-lib.sh"; hm_jq_resolve; echo "[$HM_JQ]"); assert_eq "...the next candidate that is root's is taken" "$r" "[$REAL]"
assert_eq "the three paths are the ones the plan names" "$(grep '^hm_jq_candidates() { echo ' "$HM_REPO_ROOT/bin/hm-lib.sh")" "hm_jq_candidates() { echo '/usr/bin/jq /usr/local/bin/jq /opt/homebrew/bin/jq'; }"
mkdir -p "$T_TMP/ujq2/sub"; chmod 777 "$T_TMP/ujq2"; cp "$REAL" "$T_TMP/ujq2/sub/jq"
# a root-owned file in a folder the user can write is no better: only a file whose every folder above is root's passes (here the owner check stops it first)
UB3=$(t_jq_bin ub3 "$T_TMP/ujq2/sub/jq"); r=$(. "$UB3/hm-lib.sh"; hm_jq_resolve; echo "[$HM_JQ]"); assert_eq "a jq in a folder the user controls is refused" "$r" "[]"

# a root-owned file in a folder the group can write is refused for the folder, not the file (only the parents decide here)
gf=$(find /Applications /Library -maxdepth 1 -type f -user root 2>/dev/null | head -1)
if [ -n "$gf" ] && ! hm_path_trusted "${gf%/*}" dir 0 loose; then
  GB=$(t_jq_bin gb "$gf"); r=$(. "$GB/hm-lib.sh"; hm_jq_resolve; echo "[$HM_JQ]"); assert_eq "a root-owned file under a folder the group can write is refused" "$r" "[]"
else echo "  SKIP no root-owned file under a group-writable folder to use as a candidate here"; fi

# ---- the grant functions never call a bare jq, and hm_delegate_for_project's read of projects.json is pinned to the root-owned one ----
body() {  # body <function>: its code in hm-lib.sh, comments dropped
  awk -v f="$1" '$0 ~ "^"f"\\(\\) \\{" {p=1} p {print} p && /^}/ {p=0}' "$HM_REPO_ROOT/bin/hm-lib.sh" | sed 's/#.*//; s/"[^"]*"//g'   # comments and quoted text (messages) are no call
}
for f in hm_delegate_mine hm_delegate_for_project hm_hub_records_trusted hm_write_away_mcp hm_check_mode hm_bypass_launch hm_team_roots hm_repo_home hm_self_entry hm_session_record; do
  [ -n "$(body $f)" ] || { bad "$f was not found in hm-lib.sh"; continue; }
  assert_eq "no bare jq in $f" "$(body $f | grep -cE '(^|[^A-Za-z_$"-])jq[[:space:]]')" "0"
done
# a jq first on PATH that lists a stranger's folder as a project of the hub: the listing is read with the root-owned jq, so it changes nothing
FP="$T_TMP/fakeproj"; mkdir -p "$FP"
printf '#!/bin/sh\ncase "$*" in *projects*) printf "fake\\t%%s\\n" "$FAKE_HOME" ;; esac\n' > "$FP/jq"; chmod +x "$FP/jq"
# ---- no root-owned jq: the hook denies and bypass is refused ----
r=$(. "$NB/hm-lib.sh"; hm_write_away_mcp "$T_TMP/mcp.json" docs "$proj" 2>&1); rc=$?; assert_status "the MCP file a bypass session gets is not written with no root-owned jq" $rc 1
[ ! -e "$T_TMP/mcp.json" ] && ok "...and no file is left" || bad "an MCP file was written without a root-owned jq"
r=$(. "$HM_REPO_ROOT/bin/hm-lib.sh"; hm_write_away_mcp "$T_TMP/mcp.json" "" "$proj" 2>&1); assert_status "...while with one it is" $? 0
# a complete fixture hub and a valid file, read as this user (the seam t_delegate_bin gives the executables): only the jq differs
DG="$T_TMP/dg/area"; mkdir -p "$DG" "$T_TMP/fh/.hivemind-hub"; chmod 755 "$T_TMP/dg" "$DG" "$T_TMP/fh" "$T_TMP/fh/.hivemind-hub"
printf '{"projects":[]}\n' > "$T_TMP/fh/.hivemind-hub/projects.json"; printf '{"name":"hub"}\n' > "$T_TMP/fh/.hivemind-hub/hub.json"; chmod 644 "$T_TMP/fh/.hivemind-hub/"*.json
printf 'hivemind-delegate 1\nhub=%s\nuntil=%s\nmcp=\n' "$(cd "$T_TMP/fh" && pwd -P)" "$(( $(date +%s) + 3600 ))" > "$DG/delegate"; chmod 644 "$DG/delegate"
mine_with() {  # mine_with <hm-lib.sh>: hm_delegate_mine on the fixture, in a shell of its own: "<status> <reason>"
  ( . "$1"; hm_delegate_now() { hm_delegate_read "$DG/delegate" "$(id -u)"; }; hm_delegate_mine; echo "$? $HM_DELEGATE_WHY" )
}
if hm_path_trusted "$DG/delegate" file "$(id -u)" strict; then
  assert_eq "the fixture is a valid file of a complete hub" "$(mine_with "$HM_REPO_ROOT/bin/hm-lib.sh")" "0 "
  r=$(mine_with "$(t_jq_bin nb0 "/nonexistent/a")/hm-lib.sh"); assert_contains "...and with no root-owned jq it is refused" "$r" "1 no root-owned jq"
  fp_with() {  # fp_with <hm-lib.sh> <root> [PATH]: hm_delegate_for_project on the fixture hub (which lists no project): its status
    ( . "$1"; hm_delegate_now() { hm_delegate_read "$DG/delegate" "$(id -u)"; }; PATH="${3:-$PATH}"; FAKE_HOME="$2" hm_delegate_for_project "$2"; echo $? )
  }
  assert_eq "a home the fixture hub does not list is refused" "$(fp_with "$HM_REPO_ROOT/bin/hm-lib.sh" "$proj")" "1"
  assert_eq "...and still is with a jq on PATH that says it is listed" "$(fp_with "$HM_REPO_ROOT/bin/hm-lib.sh" "$proj" "$FP:$PATH")" "1"
else echo "  SKIP the fixture folder is not eligible here"; fi
hook "$HM_REPO_ROOT/bin/hm-away-hook" "$(tc 'ls')"; assert_status "the hook allows a harmless command with a root-owned jq" $RC 0
hook "$NB/hm-away-hook" "$(tc 'ls')"; assert_status "the hook denies with no root-owned jq" $RC 2
assert_contains "...and says why" "$ERR" "jq"
r=$(. "$NB/hm-lib.sh"; hm_delegate_mine; echo "$? $HM_DELEGATE_WHY"); assert_contains "hm_delegate_mine refuses with no root-owned jq" "$r" "1 "
assert_contains "...and says so" "$r" "root-owned jq"
r=$(. "$NB/hm-lib.sh"; hm_check_mode bypassPermissions test "$proj" 2>&1); rc=$?; assert_status "bypass is refused with no root-owned jq" $rc 4

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
hook "$HM_REPO_ROOT/bin/hm-away-hook" "$(tc 'git push origin main')" PATH="$FB:$PATH"; assert_status "a fake jq and cat first on PATH: git push is still denied" $RC 2
assert_contains "...for the real reason" "$ERR" "git push"
hook "$HM_REPO_ROOT/bin/hm-away-hook" "$(tc 'git push origin main')" PATH="$FB:$PATH" HM_JQ="$FB/jq"; assert_status "...and HM_JQ in the environment changes nothing" $RC 2

# ---- what the hook runs ----
H="$HM_REPO_ROOT/bin/hm-away-hook"
assert_eq "the PATH line is the hook's first command" "$(grep -v '^[[:space:]]*#' "$H" | grep -v '^[[:space:]]*$' | head -1 | awk '{print $1}')" "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
assert_eq "no 'command jq' in the hook" "$(grep -cE 'command[[:space:]]+jq' "$H")" "0"
assert_eq "no 'xargs jq' in the hook" "$(grep -cE 'xargs[[:space:]]+jq' "$H")" "0"
assert_eq "no 'command -v jq' in the hook" "$(grep -cE 'command[[:space:]]+-v[[:space:]]+jq' "$H")" "0"
assert_eq "no bare jq call in the hook: every one is \"\$HM_JQ\"" "$(grep -v '^[[:space:]]*#' "$H" | grep -E '(\||<\(|\$\()[[:space:]]*jq[[:space:]]' | wc -l | tr -d ' ')" "0"
t_done
