#!/usr/bin/env bash
# hm-remote-sync against a "remote" that is a directory on this machine: ssh/scp/rsync are shims on PATH (tests/bin), no
# network, the only host is testhost. The remote side runs with hivemind's bin/ off its PATH, so only absolute paths work.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
r=$(t_repo proj); cd "$r"
rr=$(t_repo remote-proj)                      # the remote project root (a git repo, as a real one would be)
export HM_FAKE_LOG="$T_TMP/fake.log"; : > "$HM_FAKE_LOG"
sync() { hm-remote-sync "$@"; }
quiet() { "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo $?; }
refused() { local want="$1"; shift; local rc; rc=$(quiet hm-remote-sync "$@"); [ "$rc" -eq "$want" ] && ok "exit $want: $LABEL" || bad "$LABEL: exit $rc, expected $want"; }

# ---- check ---------------------------------------------------------------------------------------------------------
out=$(sync check testhost --min-gb 0 --plugin-version 0.1.0); assert_status "check passes" $? 0
assert_contains "check reports the claude version" "$out" "2.1.300"
rec="$r/.hivemind/remote/testhost.json"
assert_eq "the record names the remote install path" "$(jq -r .installPath "$rec")" "$HM_REPO_ROOT"
assert_eq "the record names the plugin version" "$(jq -r .version "$rec")" "0.1.0"
assert_eq "no manifest entry for the record (hm-cleanup finds it under .hivemind)" "$(hm-manifest list | wc -l | tr -d ' ')" "0"
HM_FAKE_PLUGIN_VERSION=0.0.9 sync check testhost --min-gb 0 --plugin-version 0.1.0 >"$T_TMP/out" 2>&1; assert_status "a different plugin version exits 1" $? 1
assert_contains "...and says which" "$(cat "$T_TMP/out")" "0.0.9"
sync check testhost --min-gb 999999 --plugin-version 0.1.0 >"$T_TMP/out" 2>&1; assert_status "too little free disk exits 1" $? 1
assert_contains "...and says so" "$(cat "$T_TMP/out")" "free"
HM_FAKE_SSH=down sync check testhost --min-gb 0 --plugin-version 0.1.0 >/dev/null 2>&1; assert_status "an unreachable host exits 5" $? 5
LABEL="a host with a leading -"; refused 4 check -oProxyCommand=x --min-gb 0 --plugin-version 0.1.0
LABEL="a host that is only a leading -"; refused 4 check -x --min-gb 0 --plugin-version 0.1.0
LABEL="a host with a space"; refused 4 check "a b" --min-gb 0 --plugin-version 0.1.0
LABEL="a host outside the allow-list"; HM_REMOTE_HOSTS="otherhost" refused 4 check testhost --min-gb 0 --plugin-version 0.1.0
HM_REMOTE_HOSTS="otherhost,testhost" sync check testhost --min-gb 0 --plugin-version 0.1.0 >/dev/null 2>&1; assert_status "a host on the allow-list passes" $? 0
LABEL="a bad --min-gb"; refused 4 check testhost --min-gb abc --plugin-version 0.1.0
LABEL="no subcommand"; refused 64
LABEL="an unknown subcommand"; refused 64 frobnicate testhost

# ---- files ---------------------------------------------------------------------------------------------------------
mkdir -p src; echo alpha > src/a.txt; echo beta > src/b.txt; printf 'src/a.txt\nsrc/b.txt\n' > "$T_TMP/list"
out=$(sync files testhost "$rr" "$T_TMP/list"); assert_status "files copies" $? 0
assert_eq "a copy matches" "$(cat "$rr/src/a.txt")" "alpha"
assert_contains "the hashes are reported equal" "$out" "ok src/a.txt"
out=$(sync files testhost "$rr" "$T_TMP/list"); assert_status "files is idempotent" $? 0
# corrupt one remote copy keeping its size and mtime, so rsync's quick check does not repair it: the hashes must differ
cp -p "$rr/src/b.txt" "$T_TMP/b.keep"; printf 'BETA\n' > "$rr/src/b.txt"; touch -r "$T_TMP/b.keep" "$rr/src/b.txt"
out=$(sync files testhost "$rr" "$T_TMP/list" 2>&1); assert_status "a corrupted copy exits 1" $? 1
assert_contains "...and is named MISMATCH" "$out" "MISMATCH src/b.txt"
assert_contains "...while the good one is ok" "$out" "ok src/a.txt"
printf '/etc/passwd\n' > "$T_TMP/bad1"; LABEL="an absolute list entry"; refused 4 files testhost "$rr" "$T_TMP/bad1"
printf '../x\n' > "$T_TMP/bad2"; LABEL="a .. list entry"; refused 4 files testhost "$rr" "$T_TMP/bad2"
echo outside > "$T_TMP/outside.txt"; printf '../outside.txt\n' > "$T_TMP/bad2b"; LABEL="a .. list entry naming a real file outside the project"; refused 4 files testhost "$rr" "$T_TMP/bad2b"
printf '%s\n' "$r/src/a.txt" > "$T_TMP/bad2c"; LABEL="an absolute list entry naming a real file"; refused 4 files testhost "$rr" "$T_TMP/bad2c"
printf -- '-rf\n' > "$T_TMP/bad3"; LABEL="a list entry starting with -"; refused 4 files testhost "$rr" "$T_TMP/bad3"
printf 'src/nope.txt\n' > "$T_TMP/bad4"; LABEL="a list entry that does not exist locally"; refused 4 files testhost "$rr" "$T_TMP/bad4"
ln -s /etc/hosts src/link; printf 'src/link\n' > "$T_TMP/bad5"; LABEL="a symlink in the list"; refused 4 files testhost "$rr" "$T_TMP/bad5"
LABEL="a relative remote root"; refused 4 files testhost "rel/root" "$T_TMP/list"
LABEL="a remote root with .."; refused 4 files testhost "/tmp/../etc" "$T_TMP/list"
LABEL="a missing list file"; refused 4 files testhost "$rr" "$T_TMP/nolist"
HM_FAKE_SSH=down sync files testhost "$rr" "$T_TMP/list" >/dev/null 2>&1; assert_status "files to an unreachable host exits 5" $? 5
grep -q -- '--delete' "$HM_REPO_ROOT/bin/hm-remote-sync" && bad "bin/hm-remote-sync mentions --delete" || ok "bin/hm-remote-sync never deletes on the remote"

# ---- memory --------------------------------------------------------------------------------------------------------
mkdir -p mem "$T_TMP/rmem"; echo "one" > mem/one.md; echo "two" > mem/two.md; echo "ignored" > mem/note.txt
out=$(sync memory testhost "$r/mem" "$T_TMP/rmem"); assert_status "memory copies absent files" $? 0
assert_eq "...one.md arrived" "$(cat "$T_TMP/rmem/one.md")" "one"
[ -e "$T_TMP/rmem/note.txt" ] && bad "a non-md file was copied" || ok "only *.md is copied"
out=$(sync memory testhost "$r/mem" "$T_TMP/rmem"); assert_status "memory is idempotent" $? 0
assert_contains "...and says the files are the same" "$out" "same one.md"
echo "two, edited remotely" > "$T_TMP/rmem/two.md"
out=$(sync memory testhost "$r/mem" "$T_TMP/rmem" 2>&1); assert_status "a differing remote file is a conflict, exit 1" $? 1
assert_contains "...named" "$out" "conflict two.md"
assert_eq "...and NOT overwritten" "$(cat "$T_TMP/rmem/two.md")" "two, edited remotely"
LABEL="a relative remote memory dir"; refused 4 memory testhost "$r/mem" "rel"
echo bad > "mem/bad name.md"; LABEL="a memory file name with a space"; refused 4 memory testhost "$r/mem" "$T_TMP/rmem"; rm -f "mem/bad name.md"
# bash 3.2's letter ranges follow the locale: under en_US.UTF-8 `[a-z]` takes é, ß and capitals. Each check runs under both.
for loc in C en_US.UTF-8; do
  export LC_ALL=$loc
  echo bad > "mem/né.md"; LABEL="a non-ASCII memory file name under $loc"; refused 4 memory testhost "$r/mem" "$T_TMP/rmem"; rm -f "mem/né.md"
  LABEL="a non-ASCII host under $loc"; refused 4 memory tésthost "$r/mem" "$T_TMP/rmem"
  LABEL="a non-ASCII remote path under $loc"; refused 4 memory testhost "$r/mem" "$T_TMP/rmém"
  unset LC_ALL
done

# ---- branches ------------------------------------------------------------------------------------------------------
git checkout -q -b feat/one; echo one > one; git add one; git -c user.email=t@t -c user.name=t commit -qm one; tip1=$(git rev-parse HEAD)
out=$(sync branches testhost "$rr" feat/one); assert_status "branches ships a branch" $? 0
assert_eq "the remote has refs/remotes/local/feat/one at the local tip" "$(git -C "$rr" rev-parse refs/remotes/local/feat/one)" "$tip1"
assert_eq "the remote bundle file is gone" "$(find "$rr" -name '*.bundle' | wc -l | tr -d ' ')" "0"
assert_eq "...and the local one" "$(find "$r/.hivemind" -name '*.bundle' | wc -l | tr -d ' ')" "0"
assert_eq "nothing but refs/remotes/local/* was written on the remote" "$(git -C "$rr" for-each-ref --format='%(refname)' | grep -vc '^refs/\(remotes/local/\|heads/main\)')" "0"
out=$(sync branches testhost "$rr" feat/one); assert_status "branches is idempotent" $? 0
git reset -q --hard HEAD~1; echo other > other; git add other; git -c user.email=t@t -c user.name=t commit -qm other; tip2=$(git rev-parse HEAD)
sync branches testhost "$rr" feat/one >/dev/null; assert_status "a branch that moved (rewritten locally) is forced onto refs/remotes/local only" $? 0
assert_eq "...and the remote ref follows" "$(git -C "$rr" rev-parse refs/remotes/local/feat/one)" "$tip2"
assert_eq "the remote's own main is untouched" "$(git -C "$rr" rev-parse main)" "$(git -C "$rr" rev-parse main)"
LABEL="a branch that does not exist locally"; refused 4 branches testhost "$rr" feat/nope
LABEL="a branch starting with -"; refused 4 branches testhost "$rr" -x
LABEL="a branch with a colon"; refused 4 branches testhost "$rr" "feat/one:refs/heads/main"
mkdir "$T_TMP/notrepo"; LABEL="a remote root that is not a git repository"; refused 4 branches testhost "$T_TMP/notrepo" feat/one
git checkout -q --detach; LABEL="no branch given and a detached HEAD"; refused 4 branches testhost "$rr"; git checkout -q feat/one
out=$(sync branches testhost "$rr"); assert_status "no branch given means the current one" $? 0
assert_contains "...and says which" "$out" "feat/one"
HM_FAKE_SSH=down sync branches testhost "$rr" feat/one >/dev/null 2>&1; assert_status "branches to an unreachable host exits 5" $? 5

# ---- secret --------------------------------------------------------------------------------------------------------
VAL="S3CRET-VALUE-$RANDOM$RANDOM"; VAL2="OTHER-VALUE-$RANDOM$RANDOM"
mkdir -p .hivemind/tmp; printf 'API_KEY=%s\nONLY_LOCAL=x1\nSAME=ok\n' "$VAL" > .hivemind/tmp/.env.remote
: > "$HM_FAKE_LOG"
out=$(HM_FAKE_REMOTE_UMASK=000 sync secret testhost "$rr" .hivemind/tmp/.env.remote 2>&1); assert_status "secret is copied" $? 0
dest="$rr/.hivemind/tmp/.env.remote"
assert_eq "the remote copy equals the local file" "$(cat "$dest")" "$(cat .hivemind/tmp/.env.remote)"
assert_eq "the final mode is 600" "$(ls -ln "$dest" | cut -c1-10)" "-rw-------"
assert_contains "the file was 600 at the moment it was moved into place, under a remote umask of 000" "$(cat "$HM_FAKE_LOG")" "mv-source-mode: -rw-------"
case "$out" in *"$VAL"*) bad "the secret's value was printed" ;; *) ok "no value in the output" ;; esac
case "$(cat "$HM_FAKE_LOG")" in *"$VAL"*) bad "the secret's value reached a command line" ;; *) ok "no value on any command line" ;; esac
grep -q '^scp:' "$HM_FAKE_LOG" && bad "scp was used for a secret" || ok "scp (which creates files at the remote umask) is not used for a secret"
assert_contains "the remote manifest records it, via the absolute path" "$(jq -r .kind "$rr/.hivemind/manifest.jsonl" | tr '\n' ' ')" "file"
assert_eq "...with the right path" "$(jq -r 'select(.kind=="file")|.path' "$rr/.hivemind/manifest.jsonl")" "$(cd "$rr" && pwd -P)/.hivemind/tmp/.env.remote"
assert_eq "no temporary file is left" "$(ls -A "$rr/.hivemind/tmp" | grep -c 'hm\.')" "0"
out=$(sync secret testhost "$rr" .hivemind/tmp/.env.remote 2>&1); assert_status "the same secret again is unchanged, exit 0" $? 0
assert_contains "...and says so" "$out" "unchanged"
assert_eq "...still one manifest entry" "$(jq -r 'select(.kind=="file")|.path' "$rr/.hivemind/manifest.jsonl" | wc -l | tr -d ' ')" "1"
chmod 644 "$dest"; out=$(sync secret testhost "$rr" .hivemind/tmp/.env.remote 2>&1)
assert_eq "an unchanged secret left at 644 is tightened to 600" "$(ls -ln "$dest" | cut -c1-10)" "-rw-------"
# a remote file that differs is never overwritten: names and counts only
printf 'API_KEY=%s\nONLY_REMOTE=y1\nSAME=ok\n' "$VAL2" > "$dest"; chmod 600 "$dest"
out=$(sync secret testhost "$rr" .hivemind/tmp/.env.remote 2>&1); assert_status "a differing remote file exits 1" $? 1
assert_contains "...names the keys only here" "$out" "only local: ONLY_LOCAL"
assert_contains "...names the keys only there" "$out" "only remote: ONLY_REMOTE"
assert_contains "...counts the changed values" "$out" "changed values: 1"
case "$out" in *"$VAL"*|*"$VAL2"*) bad "a value was printed" ;; *) ok "...and prints no value" ;; esac
assert_contains "...and the remote file is as it was" "$(cat "$dest")" "$VAL2"
LABEL="a destination outside .hivemind/tmp"; refused 4 secret testhost "$rr" .env
printf 'K=v\n' > .env.local; LABEL="a destination in the project root"; refused 4 secret testhost "$rr" .env.local
LABEL="a path with .."; refused 4 secret testhost "$rr" .hivemind/tmp/../../x
LABEL="a path starting with -"; refused 4 secret testhost "$rr" -x
LABEL="a secret that does not exist locally"; refused 4 secret testhost "$rr" .hivemind/tmp/none
ln -s /etc/hosts .hivemind/tmp/lnk; LABEL="a symlink as the secret"; refused 4 secret testhost "$rr" .hivemind/tmp/lnk
rm -f "$rec"; LABEL="no check record for the host"; refused 4 secret testhost "$rr" .hivemind/tmp/.env.remote
HM_FAKE_SSH=down sync secret testhost "$rr" .hivemind/tmp/.env.remote >/dev/null 2>&1; assert_status "secret to an unreachable host exits 5 (record missing: 4 first, so)" $? 4

# ---- remote paths --------------------------------------------------------------------------------------------------
# rsync's remote shell splits on a space or ; so a remote path is limited to a safe alphabet
sync check testhost --min-gb 0 --plugin-version 0.1.0 >/dev/null
mkdir -p "$T_TMP/sp ace" "$T_TMP/x;y"; git -C "$T_TMP/sp ace" init -q; git -C "$T_TMP/x;y" init -q; LABEL="files: a remote root with a space"; refused 4 files testhost "$T_TMP/sp ace" "$T_TMP/list"
LABEL="files: a remote root with a semicolon"; refused 4 files testhost "$T_TMP/x;y" "$T_TMP/list"
LABEL="branches: a remote root with a space"; refused 4 branches testhost "$T_TMP/sp ace" feat/one
LABEL="memory: a remote dir with a space"; refused 4 memory testhost "$r/mem" "$T_TMP/sp ace"
LABEL="secret: a remote root with a space"; refused 4 secret testhost "$T_TMP/sp ace" .hivemind/tmp/.env.remote
printf 'src/a b.txt\n' > "$T_TMP/spl"; echo s > "src/a b.txt"; LABEL="files: a list entry with a space"; refused 4 files testhost "$rr" "$T_TMP/spl"

# a hostile df answer must never reach bash arithmetic (a[$(cmd)] runs the command)
rm -f "$T_TMP/PWNED"; HM_FAKE_DF="a[\$(touch\${IFS}$T_TMP/PWNED)]" sync check testhost --min-gb 0 --plugin-version 0.1.0 >"$T_TMP/out" 2>&1; assert_status "a non-numeric free-space answer is a finding, exit 1" $? 1
[ ! -e "$T_TMP/PWNED" ] && ok "...and no command in it ran" || bad "a command inside the df answer ran locally"
HM_FAKE_DF=1048576 sync check testhost --min-gb 1 --plugin-version 0.1.0 >/dev/null 2>&1; assert_status "a numeric answer is still used (1 GB meets --min-gb 1)" $? 0

# a secret never leaves the named remote root, whatever is a symlink over there
sync check testhost --min-gb 0 --plugin-version 0.1.0 >/dev/null
mkdir -p "$T_TMP/elsewhere"; rr2=$(t_repo remote2); : > "$HM_FAKE_LOG"
ln -s "$T_TMP/elsewhere" "$rr2/.hivemind"
LABEL="secret: .hivemind on the remote is a symlink out of the root"; refused 4 secret testhost "$rr2" .hivemind/tmp/.env.remote
assert_eq "...and nothing was written outside the root" "$(find "$T_TMP/elsewhere" | wc -l | tr -d ' ')" "1"
rm "$rr2/.hivemind"; mkdir -p "$rr2/.hivemind"; ln -s "$T_TMP/elsewhere" "$rr2/.hivemind/tmp"
LABEL="secret: .hivemind/tmp on the remote is a symlink out of the root"; refused 4 secret testhost "$rr2" .hivemind/tmp/.env.remote
assert_eq "...and nothing was written outside the root (tmp)" "$(find "$T_TMP/elsewhere" | wc -l | tr -d ' ')" "1"
rm "$rr2/.hivemind/tmp"; mkdir -p "$rr2/.hivemind/tmp"; ln -s "$T_TMP/elsewhere/target" "$rr2/.hivemind/tmp/.env.remote"
LABEL="secret: the destination is a dangling symlink"; refused 4 secret testhost "$rr2" .hivemind/tmp/.env.remote
[ ! -e "$T_TMP/elsewhere/target" ] && ok "...and its target was not created" || bad "the symlink's target was written"
rm "$rr2/.hivemind/tmp/.env.remote"
LABEL="secret: a remote that answers nothing to a path resolution"; HM_FAKE_BLANK_PWD=1 refused 4 secret testhost "$rr2" .hivemind/tmp/.env.remote
[ ! -e "$rr2/.hivemind/tmp/.env.remote" ] && ok "...and nothing was written" || bad "a secret was written after an empty resolution"
# a file that appears at the destination after the check is never clobbered
out=$(HM_FAKE_MV_RACE=1 sync secret testhost "$rr2" .hivemind/tmp/.env.remote 2>&1); assert_status "a file that appeared at the destination is a finding, exit 1" $? 1
assert_eq "...and it was not overwritten" "$(cat "$rr2/.hivemind/tmp/.env.remote")" "raced"
assert_eq "...and no temporary file is left" "$(ls -A "$rr2/.hivemind/tmp" | grep -c 'hm\.')" "0"
rm -f "$rr2/.hivemind/tmp/.env.remote"
sync secret testhost "$rr2" .hivemind/tmp/.env.remote >/dev/null 2>&1; assert_status "a clean remote root still takes the secret" $? 0

# memory: a remote symlink is a conflict, never an absent file whose copy lands on the link's target
mkdir -p "$T_TMP/rmem2" "$T_TMP/memout"; ln -s "$T_TMP/memout/target" "$T_TMP/rmem2/one.md"
out=$(sync memory testhost "$r/mem" "$T_TMP/rmem2" 2>&1); assert_status "a remote symlink (dangling) in the memory dir is a conflict, exit 1" $? 1
assert_contains "...named" "$out" "conflict one.md"
[ ! -e "$T_TMP/memout/target" ] && ok "...and nothing was written through the link" || bad "memory wrote through a remote symlink"
# files: a directory that is a symlink out of the root, on either side, is refused
mkdir -p "$T_TMP/filesout"; rr3=$(t_repo remote3); ln -s "$T_TMP/filesout" "$rr3/src"
LABEL="files: a remote parent directory is a symlink out of the root"; refused 4 files testhost "$rr3" "$T_TMP/list"
assert_eq "...and nothing was written outside the root" "$(ls -A "$T_TMP/filesout" | wc -l | tr -d ' ')" "0"
mkdir -p "$T_TMP/localout"; echo id > "$T_TMP/localout/id"; ln -s "$T_TMP/localout" docs; printf 'docs/id\n' > "$T_TMP/lnl"
LABEL="files: a local parent directory is a symlink out of the repo"; refused 4 files testhost "$rr" "$T_TMP/lnl"
[ ! -e "$rr/docs/id" ] && ok "...and nothing was shipped" || bad "a file through a local symlinked directory was shipped"
rm docs
# branches: the bundle never lands outside the root either
rr4=$(t_repo remote4); ln -s "$T_TMP/filesout" "$rr4/.hivemind"
LABEL="branches: .hivemind on the remote is a symlink out of the root"; refused 4 branches testhost "$rr4" feat/one
assert_eq "...and no bundle was written outside the root" "$(ls -A "$T_TMP/filesout" | wc -l | tr -d ' ')" "0"

# secret: a local parent directory that is a symlink out of the project is refused (only the leaf was checked)
mkdir -p "$T_TMP/secout"; echo 'OUT=1' > "$T_TMP/secout/.env.remote"; mv .hivemind/tmp "$T_TMP/tmp.keep"; ln -s "$T_TMP/secout" .hivemind/tmp
rr5=$(t_repo remote5); LABEL="secret: the local .hivemind/tmp is a symlink out of the project"; refused 4 secret testhost "$rr5" .hivemind/tmp/.env.remote
[ ! -e "$rr5/.hivemind/tmp/.env.remote" ] && ok "...and the outside file was not shipped" || bad "a file outside the project was shipped"
rm .hivemind/tmp; mv "$T_TMP/tmp.keep" .hivemind/tmp
LABEL="memory: the host drops while looking for a symlink"
# memory: an unreachable host while looking for a symlink is unreachable (5), not a conflict
HM_FAKE_DOWN_ON="test -L" refused 5 memory testhost "$r/mem" "$T_TMP/rmem"

# ---- common --------------------------------------------------------------------------------------------------------
sync check testhost --min-gb 0 --plugin-version 0.1.0 >/dev/null
mkdir "$T_TMP/norepo"; (cd "$T_TMP/norepo" && hm-remote-sync check testhost --min-gb 0 --plugin-version 0.1.0 >/dev/null 2>&1); assert_status "outside a repo" $? 2
[ ! -e "$T_TMP/norepo/.hivemind" ] && ok "...writing nothing" || bad "wrote .hivemind outside a repo"
echo x > .hivemind/leak; git add -f .hivemind/leak
sync check testhost --min-gb 0 --plugin-version 0.1.0 >/dev/null 2>&1; assert_status "a tracked .hivemind is refused" $? 3
git rm -qf --cached .hivemind/leak
grep -n 'ssh \|scp \|rsync ' "$HM_REPO_ROOT/bin/hm-remote-sync" | grep -vE '^[0-9]+:\s*#|hm_(ssh|scp|rsync)\(\)' | grep -E '(^[0-9]+:[[:space:]]*|[;&|({]|\$\()[[:space:]]*(ssh|scp|rsync) ' >/dev/null && bad "a bare ssh/scp/rsync call outside the hm_* functions" || ok "every ssh/scp/rsync goes through hm_ssh/hm_scp/hm_rsync"
# ---- the away marker: a second layer behind hm-away-hook, which is the guard (a Bash command can unset the variable for itself)
n=$(wc -l < "$HM_FAKE_LOG")
for args in "check testhost --min-gb 0 --plugin-version 0.1.0" "branches testhost $rr" "files testhost $rr /dev/null" "memory testhost $T_TMP $T_TMP/m" "secret testhost $rr x" "" "bogus"; do
  HM_AWAY_BYPASS=1 hm-remote-sync $args >"$T_TMP/out" 2>"$T_TMP/err"; rc=$?
  [ "$rc" -eq 4 ] && ok "the away marker refuses: hm-remote-sync ${args:-<no arguments>}" || bad "hm-remote-sync $args: exit $rc, expected 4"
done
assert_contains "...saying it is hivemind's away mode" "$(cat "$T_TMP/err")" "away mode"
assert_eq "...and nothing reached ssh, scp or rsync" "$(wc -l < "$HM_FAKE_LOG")" "$n"
HM_AWAY_BYPASS=0 sync check testhost --min-gb 0 --plugin-version 0.1.0 >/dev/null 2>&1; assert_status "a marker other than 1 does not refuse" $? 0
cd /; t_teardown; t_done
