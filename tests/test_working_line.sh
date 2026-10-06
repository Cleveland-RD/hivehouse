#!/usr/bin/env bash
# hm_pane_working_seconds (bin/hm-lib.sh): Claude Code's working line ("✳ Effecting… (3s · thinking)") read from a pane, as the
# elapsed seconds. Anything it does not recognise is unknown (the function fails), never working and never hung (A10, A27).
# Fixtures: tests/fixtures/working/06-working-4s and -7s are REAL captures (Claude Code 2.1.291, capture-pane -p -e -J, scrubbed per
# A67), as is tests/fixtures/dialogs/02-working-1s. The minutes and hours forms are HAND-BUILT here from the 7s capture by replacing
# its working line, because no capture of a long run was taken; they follow the lines seen in panes: "✽ Processing… (5m 29s ·
# ↓ 7.2k tokens)" and "✻ Booping… (36m 18s · ↓ 75.0k tokens)". The hours form is a guess at the format, so it is hand-built too.
. "$(dirname "$0")/lib.sh"
. "$HM_REPO_ROOT/bin/hm-lib.sh"
t_setup
W="$HM_REPO_ROOT/tests/fixtures/working"; D="$HM_REPO_ROOT/tests/fixtures/dialogs"
secs() { hm_pane_working_seconds < "$1"; }
# built <line> -> a file: the 7s capture with its working line replaced (hand-built)
built() { hm_pane_clean < "$W/06-working-7s.ansi" | sed "s/✶ Effecting… (6s · thinking)/$1/" > "$T_TMP/built.ansi"; echo "$T_TMP/built.ansi"; }

echo "-- real captures"
assert_eq "0s (real: Elucidating)" "$(secs "$D/02-working-1s.ansi")" "0"
assert_eq "3s (real: Effecting)" "$(secs "$W/06-working-4s.ansi")" "3"
assert_eq "6s (real: Effecting, another glyph)" "$(secs "$W/06-working-7s.ansi")" "6"
echo "-- hand-built"
assert_eq "minutes and seconds" "$(secs "$(built '✽ Processing… (5m 29s · ↓ 7.2k tokens)')")" "329"
assert_eq "minutes with a token count" "$(secs "$(built '✻ Booping… (36m 18s · ↓ 75.0k tokens)')")" "2178"
assert_eq "hours" "$(secs "$(built '✻ Booping… (1h 36m 18s · ↓ 75.0k tokens)')")" "5778"
assert_eq "an exact minute" "$(secs "$(built '✳ Thinking… (2m 0s · thinking)')")" "120"
assert_eq "no detail after the time" "$(secs "$(built '✢ Thinking… (45s)')")" "45"
assert_eq "an asterisk glyph" "$(secs "$(built '* Thinking… (4s · thinking)')")" "4"
assert_eq "an ellipsis written as three dots" "$(secs "$(built '✳ Thinking... (8s · thinking)')")" "8"
assert_eq "a hyphenated verb" "$(secs "$(built '✳ Cross-checking… (11s · thinking)')")" "11"
assert_eq "a middle-dot glyph" "$(secs "$(built '· Thinking… (9s · thinking)')")" "9"
echo "-- unknown: the function fails and prints nothing"
for f in "$D/07-idle-after-answer.ansi" "$W/06-working-10s.ansi" "$D/03-bash-permission.ansi" "$D/01-trust-folder.ansi"; do
  out=$(secs "$f"); rc=$?
  [ "$rc" -ne 0 ] && [ -z "$out" ] && ok "a screen with no working line: $(basename "$f")" || bad "$(basename "$f"): rc $rc out [$out]"
done
for l in '✳ Effecting… (soon)' '✳ Effecting…' '✳ Effecting (3s)' 'Effecting… (3s · thinking)' '✳ Effecting… (3 s)' '✳ Effecting… (-3s)' '✳ Effecting… (3s'; do
  out=$(secs "$(built "$l")"); rc=$?
  [ "$rc" -ne 0 ] && [ -z "$out" ] && ok "unrecognised line is unknown: $l" || bad "$l: rc $rc out [$out]"
done
out=$(printf '' | hm_pane_working_seconds); [ $? -ne 0 ] && [ -z "$out" ] && ok "an empty pane is unknown" || bad "empty pane: [$out]"
out=$(printf '✳ Effecting… (3s · thinking)\n' | hm_pane_working_seconds); [ $? -ne 0 ] && ok "no prompt box on the screen is unknown" || bad "no box: [$out]"
echo "-- only the line above the prompt box counts"
# hand-built: a working line quoted in the conversation, far above the box, on an idle screen
{ printf '✳ Effecting… (3s · thinking)\n'; for i in 1 2 3 4 5 6; do printf 'conversation line %s\n' $i; done; cat "$D/07-idle-after-answer.ansi"; } > "$T_TMP/quoted.ansi"
out=$(secs "$T_TMP/quoted.ansi"); [ $? -ne 0 ] && [ -z "$out" ] && ok "a quoted working line far above the box is unknown" || bad "quoted line read as working: [$out]"
# hand-built: a working line inside the footer, below the box's top rule
{ cat "$D/07-idle-after-answer.ansi"; printf '✳ Effecting… (3s · thinking)\n'; } > "$T_TMP/footer.ansi"
out=$(secs "$T_TMP/footer.ansi"); [ $? -ne 0 ] && [ -z "$out" ] && ok "a working line below the box is unknown" || bad "footer line read as working: [$out]"
echo "-- it reads a raw or a cleaned pane alike"
assert_eq "a cleaned pane" "$(hm_pane_clean < "$W/06-working-4s.ansi" | hm_pane_working_seconds)" "3"
echo "-- the pattern sits beside HM_DIALOG_TEXT"
a=$(grep -n '^HM_DIALOG_TEXT=' "$HM_REPO_ROOT/bin/hm-lib.sh" | cut -d: -f1); b=$(grep -n '^HM_WORKING_RE=' "$HM_REPO_ROOT/bin/hm-lib.sh" | cut -d: -f1)
[ -n "$a" ] && [ -n "$b" ] && [ "$((b - a))" -le 4 ] && [ "$b" -ge "$a" ] && ok "HM_WORKING_RE is within four lines of HM_DIALOG_TEXT" || bad "HM_WORKING_RE ($b) is not beside HM_DIALOG_TEXT ($a)"
t_done
