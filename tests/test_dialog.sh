#!/usr/bin/env bash
# hh_dialog_parse (bin/hh-lib.sh): what a dialog on a Claude Code screen says, as the hub shows it, and the options it
# offers, read from real captures of Claude Code 2.1.291 (tests/fixtures/dialogs/*.ansi, capture-pane -p -e -J).
. "$(dirname "$0")/lib.sh"
. "$HH_REPO_ROOT/bin/hh-lib.sh"
F="$HH_REPO_ROOT/tests/fixtures/dialogs"
dlg() { hh_dialog_parse < "$F/$1.ansi"; }
j() { printf '%s' "$1" | jq -r "$2"; }

# ---- a numbered permission dialog ----
d=$(dlg 03-bash-permission); assert_status "a Bash permission dialog is read" $? 0
assert_eq "...numbered" "$(j "$d" .kind)" "numbered"
assert_eq "...three options, by their digits" "$(j "$d" '[.options[].n] | join(",")')" "1,2,3"
assert_eq "...each as Claude Code words it" "$(j "$d" '[.options[].label] | join("|")')" "Yes|Yes, and always allow access to /tmp/work from|No"
assert_eq "...a wrapped option keeps its second line" "$(j "$d" '.options[1].detail')" "this project"
assert_eq "...only the one that saves a rule says so" "$(j "$d" '[.options[].saves_rule] | map(tostring) | join(",")')" "false,true,false"
assert_eq "...all are offered" "$(j "$d" '[.options[].offered] | map(tostring) | join(",")')" "true,true,true"
assert_eq "...the cursor is on the first" "$(j "$d" .cursor)" "1"
assert_eq "...Escape is offered" "$(j "$d" .esc)" "true"
assert_contains "...the text holds the command" "$(j "$d" .text)" "touch made-by-test.txt"
assert_contains "...and the question" "$(j "$d" .text)" "Do you want to proceed?"
case "$(j "$d" .text)" in *"Run exactly this shell command"*) bad "the conversation above the dialog is in its text" ;; *) ok "...not the conversation above it" ;; esac
fp=$(j "$d" .fingerprint)
assert_eq "...a fingerprint of 40 hex digits" "$(printf '%s' "$fp" | grep -Ec '^[0-9a-f]{40}$')" "1"
assert_eq "...the same screen gives the same fingerprint" "$(j "$(dlg 03-bash-permission)" .fingerprint)" "$fp"
assert_eq "...padding does not change it" "$(j "$(sed 's/$/   /' "$F/03-bash-permission.ansi" | hh_dialog_parse; )" .fingerprint)" "$fp"
assert_eq "...nor blank lines after the screen" "$(j "$( (cat "$F/03-bash-permission.ansi"; printf '\n\n\n') | hh_dialog_parse)" .fingerprint)" "$fp"
d=$(dlg 04-write-permission)
assert_eq "an edit permission dialog: three options" "$(j "$d" '[.options[].n] | join(",")')" "1,2,3"
assert_eq "...the one that switches to accept edits saves a rule" "$(j "$d" '[.options[].saves_rule] | map(tostring) | join(",")')" "false,true,false"
assert_contains "...its text names the file" "$(j "$d" .text)" "notes.txt"
[ "$(j "$d" .fingerprint)" != "$fp" ] && ok "...another dialog, another fingerprint" || bad "two dialogs share a fingerprint"

# a rule in the conversation above (a markdown rule, a tool's output) is not the dialog's own top rule
assert_eq "...a rule in the conversation above does not move its start" "$(j "$( (printf '%s\n' '──────────────────────────'; cat "$F/03-bash-permission.ansi") | hh_dialog_parse)" .fingerprint)" "$fp"

# ---- AskUserQuestion: the owner's own text is never offered ----
d=$(dlg 05-ask-user-question)
assert_eq "an AskUserQuestion dialog: four options" "$(j "$d" '[.options[].label] | join("|")')" "Red|Blue|Type something.|Chat about this"
assert_eq "...the first two are offered, the two that need the owner's own text are not" "$(j "$d" '[.options[].offered] | map(tostring) | join(",")')" "true,true,false,false"
assert_eq "...an option's description" "$(j "$d" '.options[0].detail')" "The colour red"
assert_contains "...the question is in the text" "$(j "$d" .text)" "Which colour do you prefer?"
case "$(j "$d" .text)" in *"Use the AskUserQuestion tool"*) bad "the user's earlier line is in the text" ;; *) ok "...not the conversation above it" ;; esac

# ---- the folder-trust dialog has no digits: a menu with a cursor ----
d=$(dlg 01-trust-folder)
assert_eq "an unnumbered menu" "$(j "$d" .kind)" "menu"
assert_eq "...its rows, top down" "$(j "$d" '[.options[].label] | join("|")')" "No, exit|Yes, I trust this folder"
assert_eq "...the cursor is on the first" "$(j "$d" .cursor)" "1"
assert_eq "...Escape is offered" "$(j "$d" .esc)" "true"
fp1=$(j "$d" .fingerprint)
d2=$(dlg 01c-trust-after-down)
assert_eq "...after one Down the cursor is on the second" "$(j "$d2" .cursor)" "2"
[ "$(j "$d2" .fingerprint)" != "$fp1" ] && ok "...and the fingerprint moved" || bad "the fingerprint did not change with the cursor"

# ---- no dialog ----
for n in 02-working-1s 07-idle-after-answer 03b-bash-after-digit-1; do
  dlg "$n" >/dev/null; assert_status "$n is no dialog" $? 3
done
# a dialog whose options cannot be read: no options, and the hub says to answer in the pane
d=$(printf '%s\n' '────────────────────────' ' Do you want to proceed?' ' something new' '' ' Esc to cancel' | hh_dialog_parse); assert_status "an unreadable dialog is still a dialog" $? 0
assert_eq "...of no kind" "$(j "$d" .kind)" "none"
assert_eq "...with no options" "$(j "$d" '.options | length')" "0"
t_done
