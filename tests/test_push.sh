#!/usr/bin/env bash
# hh-push, against a local bare repository registered as the only remote. No network, no origin.
. "$(dirname "$0")/lib.sh"
t_setup
r=$(t_repo proj); cd "$r" || exit 2
bare="$T_TMP/remote.git"; git init -q --bare -b main "$bare"
git remote add up "$bare"
git config remote.up.push 'refs/heads/*:refs/heads/*' 2>/dev/null   # a configured push refspec must not widen the push
h1=$(git rev-parse HEAD)
echo two > two; git add two; git -c user.email=t@t -c user.name=t commit -qm two; h2=$(git rev-parse HEAD)
echo three > three; git add three; git -c user.email=t@t -c user.name=t commit -qm three; h3=$(git rev-parse HEAD)
tip() { git --git-dir="$bare" rev-parse --verify -q "refs/heads/$1" 2>/dev/null; }
refused() { hh-push "$@" >"$T_TMP/out" 2>"$T_TMP/err"; local rc=$?; [ "$rc" -eq 4 ] && ok "refused: $LABEL" || bad "$LABEL: exit $rc, expected 4"; }
nothing_pushed() { [ -z "$(git --git-dir="$bare" for-each-ref refs/heads)" ] && ok "...and nothing reached the remote" || bad "something reached the remote after: $LABEL"; }

LABEL="short hash"; refused up "${h1:0:12}" feat/x; nothing_pushed
LABEL="41 characters"; refused up "${h1}0" feat/x
LABEL="non-hex 40 characters"; refused up "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz" feat/x
LABEL="a hash that is not in the repo"; refused up "0123456789012345678901234567890123456789" feat/x
tree=$(git rev-parse "$h1^{tree}"); LABEL="a tree, not a commit"; refused up "$tree" feat/x
LABEL="an extra --force"; refused up "$h1" feat/x --force; nothing_pushed
LABEL="an extra argument"; refused up "$h1" feat/x extra
LABEL="a URL as the remote"; refused "$bare" "$h1" feat/x; nothing_pushed
LABEL="a remote that is not configured"; refused nosuch "$h1" feat/x
LABEL="a remote starting with -"; refused --mirror "$h1" feat/x
LABEL="a branch with a colon"; refused up "$h1" "feat/x:refs/heads/main"; nothing_pushed
LABEL="a branch starting with -"; refused up "$h1" -x
LABEL="a branch with .."; refused up "$h1" "a..b"
LABEL="a branch with a space"; refused up "$h1" "a b"
cur=$(git rev-parse --abbrev-ref HEAD); git checkout -q -b prev-branch; git checkout -q "$cur"   # so @{-1} names a real branch
LABEL="@{-1}, which --branch would expand to another branch"; refused up "$h1" "@{-1}"
LABEL="refs/heads/ prefixed twice"; refused up "$h1" "refs/heads/x:y"
LABEL="a branch ending in .lock"; refused up "$h1" "feat/x.lock"
hh-push up "$h1" >/dev/null 2>&1; assert_status "too few arguments is a usage error" $? 64

# a good push lands, as a new branch and then as a fast-forward
out=$(hh-push up "$h1" feat/x); assert_status "a new branch is pushed" $? 0
assert_eq "the remote branch equals the hash" "$(tip feat/x)" "$h1"
assert_contains "the range is printed" "$out" "feat/x"
out=$(hh-push up "$h3" feat/x); assert_status "a fast-forward is pushed" $? 0
assert_eq "the remote moved to the new hash" "$(tip feat/x)" "$h3"
assert_contains "the pushed range is old..new" "$out" "${h1:0:7}..${h3:0:7}"
out=$(hh-push up "$h3" feat/x); assert_status "pushing what is already there is fine" $? 0
assert_contains "...and says so" "$out" "up to date"
assert_eq "...and changes nothing" "$(tip feat/x)" "$h3"
# only the named branch moved, though a push refspec is configured for the remote
assert_eq "no other branch reached the remote" "$(git --git-dir="$bare" for-each-ref --format='%(refname)' refs/heads)" "refs/heads/feat/x"

# non-fast-forward: the remote has a commit the hash does not contain
git checkout -q -b other "$h1"; echo x > x; git add x; git -c user.email=t@t -c user.name=t commit -qm diverge; hd=$(git rev-parse HEAD)
LABEL="a non-fast-forward"; refused up "$hd" feat/x
assert_eq "...the remote is where it was" "$(tip feat/x)" "$h3"
git checkout -q -
# a stale local tracking ref does not fool the check: the remote's real tip decides
git update-ref refs/remotes/up/feat/x "$h1"
LABEL="a non-fast-forward with a stale tracking ref"; refused up "$hd" feat/x
# an older commit than the remote tip is a rewind, also refused
LABEL="a rewind to an ancestor"; refused up "$h2" feat/x
assert_eq "...the remote did not rewind" "$(tip feat/x)" "$h3"

# an unreadable remote pushes nothing and says so (exit 5)
git remote add gone "$T_TMP/does-not-exist.git"
hh-push gone "$h1" feat/x >/dev/null 2>&1; assert_status "an unreadable remote is exit 5" $? 5

# the arguments reach it unchanged from zsh (the $h:r modifier trap): a braced refspec, and text shaped like one
if command -v zsh >/dev/null 2>&1; then
  zsh -c 'h=$(git rev-parse '"$h2"'); hh-push up "$h" feat/z' >/dev/null 2>&1; assert_status "from zsh -c with a computed hash" $? 0
  assert_eq "zsh pushed the right hash" "$(tip feat/z)" "$h2"
  zsh -c 'h='"$h3"'; hh-push up "$h:refs/heads/q" feat/q' >/dev/null 2>&1; assert_status "a zsh-modified-looking hash is refused, not mangled into a push" $? 4
  [ -z "$(tip feat/q)" ] && ok "...and nothing landed" || bad "feat/q landed"
else ok "zsh not installed: zsh cases skipped"; fi
# bash 3.2 and zsh both mangle an unbraced "$var:" followed by a letter in a double-quoted string
if grep -nE '\$[A-Za-z_][A-Za-z0-9_]*:[A-Za-z]' "$HH_REPO_ROOT/bin/hh-push" >/dev/null; then bad "bin/hh-push has an unbraced \$var: in it"; else ok "no unbraced \$var: in bin/hh-push"; fi
pushes=$(grep -E '^[^#]*git (-c [^ ]+ )*push' "$HH_REPO_ROOT/bin/hh-push")
assert_eq "bin/hh-push has exactly one push, with no option but -q" "$(printf '%s\n' "$pushes" | wc -l | tr -d ' ')" "1"
case "$pushes" in *force*|*--mirror*|*--delete*|*" +"*|*" -f"*) bad "the push line carries a forcing option: $pushes" ;; *) ok "the push line carries no forcing option" ;; esac

# the away marker: a second layer behind hh-away-hook, which is the guard (a Bash command can unset the variable for itself)
before=$(git --git-dir="$bare" for-each-ref refs/heads)
HH_AWAY_BYPASS=1 hh-push up "$h1" away-blocked >"$T_TMP/out" 2>"$T_TMP/err"; assert_status "the away marker refuses a valid push" $? 4
assert_contains "...saying it is hivehouse's away mode" "$(cat "$T_TMP/err")" "away mode"
assert_eq "...and nothing reached the remote" "$(git --git-dir="$bare" for-each-ref refs/heads)" "$before"
HH_AWAY_BYPASS=1 hh-push >/dev/null 2>&1; assert_status "...even with no arguments" $? 4
HH_AWAY_BYPASS=0 hh-push up "$h1" away-ok >/dev/null 2>&1; assert_status "a marker other than 1 does not refuse" $? 0

# outside a repository: exit 2
mkdir "$T_TMP/norepo"; (cd "$T_TMP/norepo" && hh-push up "$h1" feat/x >/dev/null 2>&1); assert_status "outside a repo" $? 2
cd /; t_teardown; t_done
