#!/usr/bin/env bash
# The plugin directory's validator cannot place a here-document (<<WORD) in bin/: none may be written there (here-strings, <<<, are fine).
# And the one text that used to sit in a here-document, the Perl program in hh-lib.sh, must be byte for byte what it was (length and sha-256 of the 0.5.5 text).
. "$(dirname "$0")/lib.sh"
t_setup
hits=$(grep -rnE "(^|[^<\"])<<-?[ ]*[\\\\\"'A-Za-z_]" "$HH_REPO_ROOT/bin" | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#')
assert_eq "no here-document in bin/ (a comment line is not one)" "$hits" ""
( . "$HH_REPO_ROOT/bin/hh-lib.sh" >/dev/null 2>&1; printf '%s' "$HH_DIALOG_PERL" | wc -c | tr -d ' ' ) > "$T_TMP/len"
( . "$HH_REPO_ROOT/bin/hh-lib.sh" >/dev/null 2>&1; printf '%s' "$HH_DIALOG_PERL" | shasum -a 256 | cut -d' ' -f1 ) > "$T_TMP/sha"
assert_eq "HH_DIALOG_PERL has the same length as the here-document had" "$(cat "$T_TMP/len")" "2582"
assert_eq "HH_DIALOG_PERL has the same bytes as the here-document had" "$(cat "$T_TMP/sha")" "600502066c22fc671900567f9c5f4c0e63260a03b8161fbc15f539ae287a942e"
t_done
