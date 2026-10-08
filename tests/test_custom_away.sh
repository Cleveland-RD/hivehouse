#!/usr/bin/env bash
# The hub reads no custom/ file while the owner is away (final delta review): a text an away agent could write must never reach the hub's own
# prompt or rules. hh_custom_file answers with the plugin's file for every kind when the caller is the hub's root and the owner is away for that hub
# (a valid delegate file naming it, or one that exists and is refused, which fails closed). A project's agents keep resolving custom/ as before.
# The delegate file is a fixture (t_delegate_bin: a scratch copy of bin/ that reads it as this user).
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
t_setup
H="$T_TMP/work"; mkdir -p "$H/$T_HUB"; H=$(cd "$H" && pwd -P)
printf '{"name":"hub1"}\n' > "$H/$T_HUB/hub.json"; printf '{"projects":[]}\n' > "$H/$T_HUB/projects.json"
proj=$(t_repo proj); mkdir -p "$proj/$T_STATE"
NOW=$(date +%s); ME=$(id -u); DD="$T_TMP/dg/area"; DF="$DD/delegate"
mkdel() {  # mkdel [hub] [until]: a version 1 delegate file
  mkdir -p "$DD"; chmod 755 "$DD" "$T_TMP/dg"
  printf "$T_DELEGATE_LINE1"'\nhub=%s\nuntil=%s\nmcp=\n' "${1:-$H}" "${2:-$((NOW + 3600))}" > "$DF"; chmod 644 "$DF"
}
mkdel
if ! hh_delegate_read "$DF" "$ME" "$NOW" >/dev/null 2>&1; then
  hh_delegate_read "$DF" "$ME" "$NOW" >/dev/null 2>&1
  echo "  SKIP the fixture folder is not eligible here: $HH_DELEGATE_WHY"; t_done; exit 0
fi
DB=$(t_delegate_bin "$DF")
PL=$(cd "$DB/.." && pwd -P); cp -R "$HH_REPO_ROOT/rules" "$HH_REPO_ROOT/roles" "$PL/"   # the scratch copy's own plugin folder: its files are the "plugin's own"
res() {  # res <project dir> <hh-resolve args>: from that project, with the delegate fixture; sets OUT, ERR, RC
  local p="$1"; shift
  OUT=$(cd "$p" && HH_PROJECT="$p" "$DB/hh-resolve" "$@" 2>"$T_TMP/err"); RC=$?; ERR=$(cat "$T_TMP/err")
}
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-custom}" > "$1"; chmod 644 "$1"; }
HC="$H/$T_STATE/$T_CUSTOM"; PC="$proj/$T_STATE/$T_CUSTOM"; UC="$HIVEHOUSE_HOME/$T_CUSTOM"
for f in rules/RULES.md rules/hub-pickup.md rules/hub-handoff.md rules/brief-template.md roles/implementer.md; do put "$HC/$f"; put "$PC/$f"; put "$UC/$f"; done
echo "-- the owner is away for this hub: the hub gets the plugin's own file for every kind"
res "$H" rules;        assert_eq "rules" "$OUT" "$PL/rules/RULES.md"
assert_contains "...with a note that says why" "$ERR" "away"
res "$H" hub-handoff;  assert_eq "hub-handoff" "$OUT" "$PL/rules/hub-handoff.md"
res "$H" hub-pickup;   assert_eq "hub-pickup" "$OUT" "$PL/rules/hub-pickup.md"
res "$H" brief;        assert_eq "brief" "$OUT" "$PL/rules/brief-template.md"
res "$H" role implementer; assert_eq "a role" "$OUT" "$PL/roles/implementer.md"
OUT=$(cd "$H" && env -u HH_PROJECT "$DB/hh-resolve" rules 2>/dev/null); assert_eq "...also with no HH_PROJECT, from the hub's own folder" "$OUT" "$PL/rules/RULES.md"
echo "-- a project's agents keep resolving custom/ while the owner is away"
res "$proj" rules;     assert_eq "a project's rules come from its custom file" "$OUT" "$PC/rules/RULES.md"
res "$proj" role implementer; assert_eq "...and its role too" "$OUT" "$PC/roles/implementer.md"
echo "-- a delegate file that exists and is refused fails closed for the hub"
chmod 666 "$DF"; res "$H" rules; assert_eq "a file anyone can write: the plugin's file" "$OUT" "$PL/rules/RULES.md"
res "$proj" rules;     assert_eq "...and the project still gets its own" "$OUT" "$PC/rules/RULES.md"
mkdel "$H" "$((NOW - 10))"; res "$H" hub-handoff; assert_eq "an expired file that names this hub: the plugin's file" "$OUT" "$PL/rules/hub-handoff.md"
echo "-- not away for this hub: custom/ as before"
mkdel "$T_TMP"; res "$H" rules; assert_eq "a file that names another hub" "$OUT" "$HC/rules/RULES.md"
assert_contains "...and the note says it is the project's custom file" "$ERR" "custom file"
H2="$T_TMP/work2"; mkdir -p "$H2/$T_HUB"; H2=$(cd "$H2" && pwd -P); cp "$H/$T_HUB/hub.json" "$H/$T_HUB/projects.json" "$H2/$T_HUB/"
mkdel "$H2"; hh_delegate_read "$DF" "$ME" "$NOW" >/dev/null 2>&1 && ok "(the second hub's file is valid)" || bad "the second hub's file is not valid: $HH_DELEGATE_WHY"
res "$H" rules; assert_eq "a VALID file that names another hub: this hub still reads its custom file" "$OUT" "$HC/rules/RULES.md"
res "$H2" rules; assert_eq "...and the hub it names gets the plugin's" "$OUT" "$PL/rules/RULES.md"
rm -f "$DF"; res "$H" rules; assert_eq "no delegate file at all" "$OUT" "$HC/rules/RULES.md"
res "$H" hub-pickup;   assert_eq "...hub-pickup too" "$OUT" "$HC/rules/hub-pickup.md"
ln -s "$H/$T_HUB" "$proj/$T_HUB"; mkdel "$proj"; res "$proj" rules; assert_eq "a project whose hub folder is a LINK is no hub (the refused file names it, and it still reads its own custom file)" "$OUT" "$PC/rules/RULES.md"; rm -f "$proj/$T_HUB"
rm -f "$HC/rules/RULES.md"; res "$H" rules; assert_eq "...and the user's file when the hub has none" "$OUT" "$UC/rules/RULES.md"
t_done
