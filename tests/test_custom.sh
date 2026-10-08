#!/usr/bin/env bash
# 0.5.1 section E: the custom/ override layer. A role, the rules or the brief template come from the project's custom/ folder,
# else the user's, else the plugin's, through ONE resolver (hh_custom_file in bin/hh-lib.sh, reached by `hh-resolve`), and every
# skill that names one of those files asks it. A custom file that is a link, not the user's own or writable by others is ignored
# with a note. The README keeps its promise line, lists every option, and says what an away agent can and cannot change.
. "$(dirname "$0")/lib.sh"
t_setup
proj=$(t_repo proj); mkdir -p "$proj/$T_STATE"
cd "$proj"
PCUST="$proj/$T_STATE/$T_CUSTOM"; UCUST="$HIVEHOUSE_HOME/$T_CUSTOM"
res() {  # res <hh-resolve args>: sets OUT (the path), ERR (the notes) and RC
  OUT=$(hh-resolve "$@" 2>"$T_TMP/err"); RC=$?; ERR=$(cat "$T_TMP/err")
}
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-custom}" > "$1"; chmod 644 "$1"; }

echo "-- the plugin level: nothing in custom/"
res role implementer;  assert_status "a role resolves" "$RC" 0; assert_eq "...to the plugin's file" "$OUT" "$HH_REPO_ROOT/roles/implementer.md"
res rules;             assert_eq "the rules resolve to the plugin's file" "$OUT" "$HH_REPO_ROOT/rules/RULES.md"
res brief;             assert_eq "the brief template resolves to the plugin's file" "$OUT" "$HH_REPO_ROOT/rules/brief-template.md"
assert_eq "...and says nothing when nothing is overridden" "$ERR" ""

echo "-- the user level, then the project level, and which wins"
put "$UCUST/roles/implementer.md" user
res role implementer;  assert_eq "a user file beats the plugin's" "$OUT" "$UCUST/roles/implementer.md"
assert_contains "...and the note says which level it is" "$ERR" "user"
put "$PCUST/roles/implementer.md" project
res role implementer;  assert_eq "a project file beats the user's" "$OUT" "$PCUST/roles/implementer.md"
assert_contains "...and the note says which level it is" "$ERR" "project"
rm "$PCUST/roles/implementer.md"
res role implementer;  assert_eq "a missing project file falls back to the user's" "$OUT" "$UCUST/roles/implementer.md"
rm "$UCUST/roles/implementer.md"
res role implementer;  assert_eq "a missing user file falls back to the plugin's" "$OUT" "$HH_REPO_ROOT/roles/implementer.md"
put "$PCUST/rules/RULES.md" project-rules
res rules;             assert_eq "the rules are overridden the same way" "$OUT" "$PCUST/rules/RULES.md"
res role reviewer;     assert_eq "another role is not affected by a file for a different one" "$OUT" "$HH_REPO_ROOT/roles/reviewer.md"
put "$PCUST/rules/brief-template.md" project-brief
res brief;             assert_eq "the brief template is overridden the same way" "$OUT" "$PCUST/rules/brief-template.md"
put "$UCUST/roles/security.md" mine
res role security;     assert_eq "a role only the user has resolves" "$OUT" "$UCUST/roles/security.md"
rm -rf "$PCUST" "$UCUST"
res role security;     assert_status "a role nobody has is not found" "$RC" 2

echo "-- the project is the repository's home, from a worktree too; outside a project only the user and the plugin count"
put "$PCUST/roles/implementer.md" project
git -C "$proj" worktree add -q "$T_TMP/wt" -b wtbranch
( cd "$T_TMP/wt" && OUT=$(hh-resolve role implementer 2>/dev/null); [ "$OUT" = "$PCUST/roles/implementer.md" ] ) && ok "from a worktree the home's custom file is used" || bad "from a worktree the home's custom file is used"
mkdir -p "$T_TMP/nogit"; put "$UCUST/roles/implementer.md" user
OUT=$( cd "$T_TMP/nogit" && env -u HH_PROJECT hh-resolve role implementer 2>/dev/null ); assert_eq "outside any repository the user's file is used" "$OUT" "$UCUST/roles/implementer.md"
OUT=$( cd "$T_TMP/nogit" && HH_PROJECT="$proj" hh-resolve role implementer 2>/dev/null ); assert_eq "HH_PROJECT names the project, as for every tool" "$OUT" "$PCUST/roles/implementer.md"
rm -rf "$PCUST" "$UCUST"

echo "-- a custom file that is not safe to read is ignored, with a note, and the next level answers"
put "$T_TMP/elsewhere.md" other
mkdir -p "$PCUST/roles"; ln -s "$T_TMP/elsewhere.md" "$PCUST/roles/implementer.md"
res role implementer
assert_eq "a symlink is ignored" "$OUT" "$HH_REPO_ROOT/roles/implementer.md"
assert_contains "...with a note naming the file" "$ERR" "$PCUST/roles/implementer.md"
assert_contains "...and the reason" "$ERR" "link"
rm -f "$PCUST/roles/implementer.md"; put "$PCUST/roles/implementer.md" project; chmod 664 "$PCUST/roles/implementer.md"
res role implementer
assert_eq "a file the group can write is ignored" "$OUT" "$HH_REPO_ROOT/roles/implementer.md"
assert_contains "...with the reason" "$ERR" "writable by group or others"
chmod 646 "$PCUST/roles/implementer.md"; res role implementer
assert_eq "a file anyone can write is ignored" "$OUT" "$HH_REPO_ROOT/roles/implementer.md"
chmod 644 "$PCUST/roles/implementer.md"
mv "$PCUST" "$T_TMP/real-custom"; ln -s "$T_TMP/real-custom" "$PCUST"
res role implementer
assert_eq "a custom/ folder that is a link is ignored" "$OUT" "$HH_REPO_ROOT/roles/implementer.md"
assert_contains "...with the reason" "$ERR" "link"
rm -f "$PCUST"; mv "$T_TMP/real-custom" "$PCUST"
chmod 777 "$PCUST/roles"; res role implementer
assert_eq "a roles/ folder the others can write is ignored" "$OUT" "$HH_REPO_ROOT/roles/implementer.md"
chmod 755 "$PCUST/roles"
res role implementer; assert_eq "restored, the file is used again" "$OUT" "$PCUST/roles/implementer.md"
# a file the user does not own: the resolver reads the real uid through hh_real_uid, which this test makes another user
( . "$HH_REPO_ROOT/bin/hh-lib.sh"; hh_real_uid() { echo 99999; }; hh_custom_file roles/implementer.md 2>"$T_TMP/err" >"$T_TMP/out" )
assert_eq "a file the user does not own is ignored" "$(cat "$T_TMP/out")" "$HH_REPO_ROOT/roles/implementer.md"
assert_contains "...with the reason" "$(cat "$T_TMP/err")" "owned by uid"
rm -rf "$PCUST"

echo "-- the executable's arguments"
res;                    assert_status "no argument" "$RC" 64
res nothing;            assert_status "an unknown kind" "$RC" 64
res role;               assert_status "role without a name" "$RC" 64
res rules extra;        assert_status "rules takes no name" "$RC" 64
res role ../x;          assert_status "a name with .. is refused" "$RC" 4
res brief extra;        assert_status "brief takes no name" "$RC" 64
res role 'a/b';         assert_status "a name with a slash is refused" "$RC" 4
res role '-x';          assert_status "a name starting with a dash is refused" "$RC" 4; assert_contains "...by the executable's own rule" "$ERR" "starts with a lowercase letter"
res role 'Impl';        assert_status "a name with a capital is refused" "$RC" 4; assert_contains "...by the executable's own rule" "$ERR" "starts with a lowercase letter"
res role 'a/b';          assert_contains "a slash is refused by the executable's own rule" "$ERR" "lowercase letters, digits"

echo "-- the resolver itself refuses a path that is not one of the three kinds (hh-resolve cannot send one, a caller of the function could)"
for bad_rel in '../../etc/passwd' 'roles/../../x.md' 'roles/a/../../x.md' 'roles/a..b.md' 'rules/other.md' 'roles/Implementer.md' 'roles/.md' '/etc/passwd' 'roles/a b.md'; do
  ( . "$HH_REPO_ROOT/bin/hh-lib.sh"; hh_custom_file "$bad_rel" >/dev/null 2>&1 ); assert_status "hh_custom_file refuses $bad_rel" "$?" 4
done

echo "-- the folder's name is one constant"
assert_eq "bin/hh-lib.sh defines HH_CUSTOM_DIR once" "$(grep -c '^HH_CUSTOM_DIR=' "$HH_REPO_ROOT/bin/hh-lib.sh")" 1
assert_eq "...and the test helper agrees" "$T_CUSTOM" "$(sed -n "s/^HH_CUSTOM_DIR='\([^']*\)'.*/\1/p" "$HH_REPO_ROOT/bin/hh-lib.sh")"

t_done
