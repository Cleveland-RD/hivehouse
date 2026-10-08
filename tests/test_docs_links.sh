#!/usr/bin/env bash
# README.md and docs/*.md: every relative link points at a file that exists, every #anchor at a heading of that file, and no
# em or en dash is left. Anchors are made as GitHub makes them: lowercase, punctuation dropped, spaces to hyphens.
. "$(dirname "$0")/lib.sh"
t_setup
R="$HH_REPO_ROOT"
slugs() {  # slugs <file>: the anchor of each heading outside a code fence
  awk '/^```/{f=!f; next} !f && /^#+ /' "$1" | sed -E 's/^#+ +//' | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9 _-]//g; s/ /-/g'
}
n=0
for f in "$R/README.md" "$R"/docs/*.md; do
  rel=${f#"$R"/}; dir=$(dirname "$f")
  while IFS= read -r link; do
    case "$link" in http*|mailto:*) continue ;; esac
    n=$((n + 1)); path=${link%%#*}; anchor=""; case "$link" in *'#'*) anchor=${link#*#} ;; esac
    if [ -z "$path" ]; then target=$f; else target="$dir/$path"; fi
    if [ ! -f "$target" ]; then bad "$rel: $link points at no file"; continue; fi
    if [ -n "$anchor" ] && ! slugs "$target" | grep -qxF -- "$anchor"; then bad "$rel: $link points at no heading"; continue; fi
    ok "$rel: $link"
  done < <(awk '/^```/{f=!f; next} !f' "$f" | grep -o '\]([^)]*)' | sed -E 's/^\]\((.*)\)$/\1/')
done
[ "$n" -gt 0 ] && ok "links were checked ($n)" || bad "no link was found to check"
for f in "$R/README.md" "$R"/docs/*.md; do
  assert_eq "${f#"$R"/}: no em or en dash" "$(grep -c $'\xe2\x80\x94\|\xe2\x80\x93' "$f")" 0
done
# small public-copy facts
assert_contains "the README says the userConfig notice needs no action" "$(cat "$R/README.md")" "needs no action"
assert_eq "docs/away-mode.md says no sudo line is written by --allow" "$(grep -c 'and `--allow` write them' "$R/docs/away-mode.md")" "0"
assert_eq "...and that --allow never applies to the remote list is gone" "$(grep -c '`--allow` never applies' "$R/docs/away-mode.md")" "0"
for d in docs/plans/ docs/specs/; do assert_eq ".gitignore lists $d" "$(grep -cx "$d" "$R/.gitignore")" "1"; done
t_done
