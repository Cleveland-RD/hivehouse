#!/usr/bin/env bash
# The narrow rule: while the owner is away, quoted text is data ONLY for echo, printf and the free-text flag of hh-hub log, task and
# decide, ONLY when the quote holds no $, backtick or backslash, and ONLY when the call has no redirect (and, for echo and printf, no pipe after
# the quote). Everything else takes the strict path. The cases come from a table (command x quote style x payload x what follows), and bash is
# the oracle: each line is run with every command word a stub function that records its name, so the words bash EXECUTES are known, and
#   - blanking never changes them (the blanked line runs the same command words as the line), and
#   - a line that really runs the danger word (ssh) is always refused, and a line that does not is refused only when the strict path refuses it.
# The runs are safe by construction: a subshell with PATH=/nonexistent, HOME and the cwd in a scratch folder, every word of the fixed list a
# stub function, no `.`, source, eval, exec, command, builtin, enable or trap in the list, and relative scratch names only as redirect targets.
. "$(dirname "$0")/lib.sh"
t_setup
proj=$(t_repo proj); hub="$T_TMP/hub"; mkdir -p "$hub/$T_HUB" "$proj/$T_STATE"
HOOK="$HH_REPO_ROOT/bin/hh-away-hook"
sd="$T_TMP/oracle"; mkdir -p "$sd"; : > "$sd/in"; : > "$sd/out"

# the hook's own blanking function, taken from the hook as written (it needs nothing but awk)
eval "$(sed -n '/^data_blank() {/,/^}/p' "$HOOK")"
[ "$(type -t data_blank)" = function ] && ok "data_blank was read from the hook" || bad "data_blank was not found in the hook"

STUBS="echo printf hh-hub ls cat ssh"   # the fixed list of command words a table line may run; nothing else is defined
for w in . source eval exec command builtin enable trap; do case " $STUBS " in *" $w "*) bad "the stub list holds $w" ;; esac; done

# run_line <line> <stub status>: prints the command words the line runs, one run, in the scratch subshell
run_line() {
  (
    cd "$sd" || exit 99
    export PATH=/nonexistent HOME="$sd"
    W="$sd/words"; : > "$W"; RC=$2
    for c in $STUBS; do eval "$c() { builtin printf '%s\n' $c >> \"\$W\"; return \$RC; }"; done
    eval "$1"
    wait
  ) > /dev/null 2>&1
  tr '\n' ' ' < "$sd/words"
}
# words <line>: the words of both runs (stubs that succeed, stubs that fail, so both sides of && and || run), sorted and unique
words() { { run_line "$1" 0; run_line "$1" 1; } | tr ' ' '\n' | sort -u | grep . | tr '\n' ' '; }

echo "-- the oracle's own safety checks"
rm -f "$sd/sentinel"; words 'touch sentinel' > /dev/null
[ ! -e "$sd/sentinel" ] && ok "a word that is not a stub is not found (PATH=/nonexistent): touch made no file" || bad "a real program ran inside the oracle"
assert_eq "type -t echo says function inside the oracle" "$( (cd "$sd"; PATH=/nonexistent; for c in $STUBS; do eval "$c() { return 0; }"; done; type -t echo) 2>/dev/null)" "function"
assert_eq "~ lands in the scratch folder" "$( (cd "$sd"; export HOME="$sd" PATH=/nonexistent; builtin printf '%s' ~) )" "$sd"
assert_eq "the oracle records the words of a list" "$(words 'echo a && ls || cat b')" "cat echo ls "
assert_eq "the oracle sees a command inside a substitution" "$(words 'echo "$(ls)"')" "echo ls "
assert_eq "the oracle sees a backgrounded command" "$(words 'echo a & ls')" "echo ls "
d=$(bash -c 'f() { echo "a; b"; }; declare -f f' 2>&1) && ok "declare -f prints bash's own parse" || bad "declare -f failed: $d"

# the table
CMDS=("echo" "printf" "hh-hub log t1 note --note" "hh-hub task proj --text" "hh-hub decide t1 --reason" "hh-hub log t1 note" "hh-hub task proj" "hh-hub decide t1")
CMDELIG=(1 1 1 1 1 0 0 0)   # the last three put the quote where no free-text flag is: not data
QUOTES=(single double)
PAY=("x (y). z" "x; . y" "x | . y" 'x; . y $v' 'x\; . y' 'x; . y `ls`')
PAYPLAIN=(1 1 1 0 0 0)   # 1: no $, backtick or backslash inside
NL=$'\n'
SEPS=("" " ; ls" " && ls" " || ls" " & ls" "$NL ls" " | cat" " > out" " >> out" " < in" " ; ssh h" " && ssh h" " | ssh h" "$NL ssh h" " || ssh h" " & ssh h")
for sep in "${SEPS[@]}"; do   # redirect targets are relative scratch names, never a path
  case "$sep" in *"/"*|*".."*) bad "a table separator holds a path: [$sep]" ;; esac
  for t in $(printf '%s' "$sep" | grep -oE '[<>]+ *[^ ;&|]+' | sed -E 's/^[<>]+ *//'); do case "$t" in out|in) ;; *) bad "a redirect target is not a scratch name: $t" ;; esac; done
done
ok "the table's redirect targets are relative scratch names"

hook() {  # hook <command>: the hook as a marked project session; sets RC
  local j; j=$(jq -nc --arg c "$1" --arg d "$proj" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}')
  printf '%s' "$j" | HH_AWAY_BYPASS=1 HH_PROJECT="$proj" HH_AWAY_HUB="$hub" HH_AWAY_MCP_ALLOW= "$HOOK" >/dev/null 2>&1; RC=$?
}
quote() {  # quote <style> <text>
  if [ "$1" = single ]; then printf "'%s'" "$2"; else printf '"%s"' "$2"; fi
}
n=0; nbad=0; nallow=0; ndeny=0
for ci in "${!CMDS[@]}"; do
  c=${CMDS[$ci]}
  for qs in "${QUOTES[@]}"; do
    for pi in "${!PAY[@]}"; do
      for sep in "${SEPS[@]}"; do
        line="$c $(quote "$qs" "${PAY[$pi]}")$sep"
        n=$((n + 1))
        ow=$(words "$line")
        # blanking never changes what bash runs
        bl=$(printf '%s' "$line" | data_blank)
        bw=$(words "$bl")
        [ "$ow" = "$bw" ] || { bad "blanking changed the command words: [$line] runs [$ow], blanked [$bl] runs [$bw]"; nbad=$((nbad + 1)); }
        hook "$line"
        # what the narrow rule says
        elig=${PAYPLAIN[$pi]}; [ "${CMDELIG[$ci]}" = 1 ] || elig=0
        case "$sep" in *">"*|*"<"*) elig=0 ;; esac
        case "$c" in echo|printf) case "$sep" in *" | "*) elig=0 ;; esac ;; esac
        case " $ow" in *" ssh "*) want=2 ;; *) if [ "$elig" = 1 ]; then want=0; else want=2; fi ;; esac
        if [ "$RC" -ne "$want" ]; then bad "[$line] (runs: $ow) exit $RC, expected $want"; nbad=$((nbad + 1)); fi
        [ "$RC" -eq 0 ] && nallow=$((nallow + 1)) || ndeny=$((ndeny + 1))
      done
    done
  done
done
[ "$nbad" -eq 0 ] && ok "all $n table lines: blanking keeps bash's command words, and the hook allows ($nallow) or refuses ($ndeny) as the narrow rule says"
[ "$nallow" -gt 0 ] && [ "$ndeny" -gt 0 ] && ok "the table has both allowed and refused lines" || bad "the table is one-sided: $nallow allowed, $ndeny refused"
t_done
