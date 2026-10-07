#!/usr/bin/env bash
# Folder trust (KI-7): Claude Code trusts a plain folder through any folder above it, but a git repository only through its own entry in
# .claude.json, and a worktree through its MAIN repository's entry. hh_claude_trusts says which; hh-spawn warns before an agent is
# launched into a worktree that would stop at the dialog.
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
T="$T_TMP/trust"; mkdir -p "$T/plain/deeper" "$T/other"; T=$(cd "$T" && pwd -P)
mkrepo() { mkdir -p "$1"; git -C "$1" init -q -b main; git -C "$1" config user.email t@t; git -C "$1" config user.name t; echo x > "$1/R"; git -C "$1" add R; git -C "$1" commit -qm init; }
mkrepo "$T/repo"; mkdir -p "$T/repo/sub"; git -C "$T/repo" worktree add -q -b wt "$T/wt"
CJ="$CLAUDE_CONFIG_DIR/.claude.json"
trust() { local a=() p; for p in "$@"; do a+=("$p"); done; printf '%s\n' "${a[@]}" | jq -Rn '{projects: ([inputs] | map({(.): {hasTrustDialogAccepted: true}}) | add // {})}' > "$CJ"; }
no() { hh_claude_trusts "$1"; assert_status "$2" $? 1; }
yes() { hh_claude_trusts "$1"; assert_status "$2" $? 0; }
rm -f "$CJ"; no "$T/plain" "no config file: nothing is trusted"
trust "$T"; yes "$T/plain/deeper" "a plain folder under a trusted folder is trusted"
yes "$T" "...and the trusted folder itself"
no "$T/repo" "a git repository does not inherit a trusted folder above it"
assert_eq "...its own entry is the one that decides" "$HH_TRUST_KEY" "$T/repo"
no "$T/wt" "a worktree of an untrusted main repository is not trusted"
assert_eq "...the key is the MAIN repository's, not the worktree's" "$HH_TRUST_KEY" "$T/repo"
trust "$T/wt"; no "$T/wt" "an entry for the worktree itself does not make it trusted"
trust "$T/repo"; yes "$T/repo" "a repository with its own entry is trusted"
yes "$T/repo/sub" "...and a folder inside it"
yes "$T/wt" "...and its worktree, through the main repository's entry"
jq -n --arg p "$T/repo" '{projects:{($p):{hasTrustDialogAccepted:false}}}' > "$CJ"; no "$T/repo" "an entry that says false is not trusted"
trust "$T/other"; no "$T/plain" "a folder beside a trusted one is not trusted"
no "$T/missing" "a folder that does not exist is not trusted"
echo '{not json' > "$CJ"; no "$T/plain" "an unreadable config trusts nothing"

# hh-spawn: the warning before a launch into a worktree
env -u HIVEHOUSE_HOME tmux -S "$HH_TMUX_SOCKET" new-session -d -s keep 'sleep 600'
r=$(t_repo proj); cd "$r"; echo role > "$T_TMP/impl.md"; echo rules > "$T_TMP/RULES.md"
spawn() { hh-spawn --agent "$1" --role "$T_TMP/impl.md" --rules "$T_TMP/RULES.md" --model sonnet --effort medium --mode auto --still 2 --max-wait 15 "${@:2}"; }
rm -f "$CJ"
spawn w1 --worktree "$T_TMP/proj-w1" --branch feat/w1 --base main >/dev/null 2>"$T_TMP/sp.err"; assert_status "spawn into a worktree of an untrusted main repository still runs" $? 0
assert_contains "...and says the agent will stop at the folder-trust dialog" "$(cat "$T_TMP/sp.err")" "will stop at Claude Code's folder-trust dialog"
assert_contains "...naming the main repository to trust" "$(cat "$T_TMP/sp.err")" "Start claude once in $(cd "$r" && pwd -P) and accept it"
trust "$(cd "$r" && pwd -P)"
spawn w2 --worktree "$T_TMP/proj-w2" --branch feat/w2 --base main >/dev/null 2>"$T_TMP/sp.err"; assert_status "...with the main repository trusted" $? 0
case "$(cat "$T_TMP/sp.err")" in *"folder-trust"*) bad "a trusted main repository is warned about" ;; *) ok "......no warning" ;; esac
t_done
