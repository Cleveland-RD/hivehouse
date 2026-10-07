#!/usr/bin/env bash
# Where a project's team is: its home, then each worktree of the home's repository that has .hivemind/team.json. Read without git (git comes
# from PATH, which an away session's own Bash command sets), from the two pointers git keeps: <home>/.git/worktrees/<name>/gitdir and the
# worktree's own .git file; a worktree counts only when both agree. hm_repo_home maps a team root to its repository's home.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
home=$(t_repo proj); home=$(cd "$home" && pwd -P)
wt1="$T_TMP/wt1"; wt2="$T_TMP/wt2"
git -C "$home" worktree add -q "$wt1" -b b1; git -C "$home" worktree add -q "$wt2" -b b2
wt1=$(cd "$wt1" && pwd -P); wt2=$(cd "$wt2" && pwd -P)
mkdir -p "$wt1/$T_STATE" "$home/sub" "$wt1/sub"; echo '{"agents":[]}' > "$wt1/$T_STATE/team.json"   # wt2 has no team
lines() { tr '\n' ' '; }

echo "-- hm_repo_home"
assert_eq "a repository is its own home" "$(hm_repo_home "$home")" "$home"
assert_eq "a worktree maps to the home its .git file points to" "$(hm_repo_home "$wt1")" "$home"
hm_repo_home "$home/sub" >/dev/null; assert_status "a subfolder is not a root: it does not walk up" $? 1
hm_repo_home "$T_TMP" >/dev/null; assert_status "a folder that is no repository" $? 1
hm_repo_home "$T_TMP/nothing" >/dev/null; assert_status "a folder that does not exist" $? 1
stranger="$T_TMP/stranger"; mkdir -p "$stranger"; cp "$wt1/.git" "$stranger/.git"
hm_repo_home "$stranger" >/dev/null; assert_status "a .git file copied to another folder: the pointer back names wt1, so it is refused" $? 1
mkdir -p "$home/.git/modules/x"; echo "$T_TMP/subm/.git" > "$home/.git/modules/x/gitdir"   # a submodule's git folder exists, and points back
sub="$T_TMP/subm"; mkdir -p "$sub"; echo "gitdir: $home/.git/modules/x" > "$sub/.git"
hm_repo_home "$sub" >/dev/null; assert_status "a submodule's .git file is no worktree" $? 1
mkdir -p "$home/.git/worktrees/deep/inner"; echo "$T_TMP/deepwt/.git" > "$home/.git/worktrees/deep/inner/gitdir"; mkdir -p "$T_TMP/deepwt"; echo "gitdir: $home/.git/worktrees/deep/inner" > "$T_TMP/deepwt/.git"
hm_repo_home "$T_TMP/deepwt" >/dev/null; assert_status "a git folder two levels below worktrees/ is no worktree's" $? 1
rm -rf "$home/.git/worktrees/deep"
badg="$T_TMP/badg"; mkdir -p "$badg"; echo "not a pointer" > "$badg/.git"; hm_repo_home "$badg" >/dev/null; assert_status "a .git file that is no pointer" $? 1

echo "-- hm_team_roots"
assert_eq "the home first, then each worktree with a team.json" "$(hm_team_roots "$home" | lines)" "$home $wt1 "
mkdir -p "$wt2/$T_STATE"; echo '{}' > "$wt2/$T_STATE/team.json"
assert_eq "a second worktree with a team is listed too" "$(hm_team_roots "$home" | lines)" "$home $wt1 $wt2 "
rm -rf "$wt2/$T_STATE"
assert_eq "a home with no worktrees is its own only root" "$(hm_team_roots "$(t_repo solo)" | sed "s|.*/||" | lines)" "solo "
# a worktree entry whose own .git file does not point back is not a team root
mkdir -p "$home/.git/worktrees/fake" "$stranger/$T_STATE"; echo "$stranger/.git" > "$home/.git/worktrees/fake/gitdir"; echo '{}' > "$stranger/$T_STATE/team.json"
assert_eq "an entry whose folder's .git does not point back is not a root" "$(hm_team_roots "$home" | lines)" "$home $wt1 "
echo "gitdir: $home/.git/worktrees/fake" > "$stranger/.git"
assert_eq "...and one that does point back is (listed in the order of the entries' names)" "$(hm_team_roots "$home" | lines)" "$home $stranger $wt1 "
rm -rf "$home/.git/worktrees/fake" "$stranger/.git"
# a fake git first on PATH that names a stranger's folder as a worktree changes nothing
mkdir -p "$T_TMP/fakegit"; printf '#!/bin/sh\nprintf "worktree %s\\n" "%s"\necho "$@" > "%s/git.called"\n' '%s' "$T_TMP/other" "$T_TMP" > "$T_TMP/fakegit/git"; chmod +x "$T_TMP/fakegit/git"
mkdir -p "$T_TMP/other/$T_STATE"; echo '{}' > "$T_TMP/other/$T_STATE/team.json"
assert_eq "a fake git on PATH naming another folder changes nothing" "$(PATH="$T_TMP/fakegit:$PATH" hm_team_roots "$home" | lines)" "$home $wt1 "
assert_eq "...and it was never called" "$([ -e "$T_TMP/git.called" ] && echo called || echo not)" "not"
assert_eq "...nor in hm_repo_home" "$(PATH="$T_TMP/fakegit:$PATH" hm_repo_home "$wt1")" "$home"
assert_eq "...nor in hm_project_home" "$(PATH="$T_TMP/fakegit:$PATH" hm_project_home "$wt1")" "$home"
assert_eq "...git was never called" "$([ -e "$T_TMP/git.called" ] && echo called || echo not)" "not"

echo "-- worktrees recorded with relative paths (git 2.48+ worktree.useRelativePaths)"
wtr="$T_TMP/wtrel"; mkdir -p "$wtr/$T_STATE" "$home/.git/worktrees/wtrel"; echo '{}' > "$wtr/$T_STATE/team.json"
echo "../../../../wtrel/.git" > "$home/.git/worktrees/wtrel/gitdir"; echo "gitdir: ../proj/.git/worktrees/wtrel" > "$wtr/.git"
assert_eq "a relative pair is found" "$(hm_team_roots "$home" | lines)" "$home $wt1 $(cd "$wtr" && pwd -P) "
assert_eq "...and hm_repo_home resolves the relative line against the .git file's folder" "$(hm_repo_home "$wtr")" "$home"
echo "../../../../nowhere/.git" > "$home/.git/worktrees/wtrel/gitdir"
assert_eq "a relative line that does not resolve is not a team root" "$(hm_team_roots "$home" | lines)" "$home $wt1 "
hm_repo_home "$wtr" >/dev/null; assert_status "...and the worktree's pointer back fails with it" $? 1
rm -rf "$home/.git/worktrees/wtrel"

echo "-- hm_project_home and hm_project_root"
assert_eq "a root maps to its home" "$(hm_project_home "$wt1")" "$home"
assert_eq "a home maps to itself" "$(hm_project_home "$home")" "$home"
assert_eq "a folder with no repository maps to itself" "$(hm_project_home "$T_TMP")" "$(cd "$T_TMP" && pwd -P)"
assert_eq "hm_project_root from a subfolder of the repository is the home" "$(cd "$home/sub" && env -u HM_PROJECT bash -c ". '$HM_REPO_ROOT/bin/hm-lib.sh'; hm_project_root")" "$home"
assert_eq "...and from a subfolder of a worktree too: the common dir <home>/.git maps to the home" "$(cd "$wt1/sub" && env -u HM_PROJECT bash -c ". '$HM_REPO_ROOT/bin/hm-lib.sh'; hm_project_root")" "$home"

echo "-- no git on the grant path"
body() {  # body <function>: its code in hm-lib.sh, comments dropped
  awk -v f="$1" '$0 ~ "^"f"\\(\\) \\{" {p=1} p {print} p && /^}/ {p=0}' "$HM_REPO_ROOT/bin/hm-lib.sh" | sed 's/#.*//'
}
for f in hm_team_roots hm_repo_home hm_project_home hm_delegate_for_project hm_delegate_mine hm_check_mode hm_bypass_launch; do
  [ -n "$(body $f)" ] || { bad "$f was not found in hm-lib.sh"; continue; }
  assert_eq "no git call in $f" "$(body $f | grep -cE '(^|[[:space:];(|&`])git([[:space:]]|$)')" "0"
done
t_done
