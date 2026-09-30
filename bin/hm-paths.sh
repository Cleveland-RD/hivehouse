#!/usr/bin/env bash
# Path guards shared by hm-manifest (when a path is recorded) and hm-cleanup (when it is acted on, judged again,
# since a manifest line is only as safe as the check made when it is read). bash 3.2 compatible.
# Each function prints its result on stdout and returns 0, or prints the reason on stdout and returns 1:
#   rp=$(hm_resolve_path "$p") || hm_die 4 "$rp"
hm_resolve_path() {  # absolute, no . or .. segment, parent resolved with pwd -P
  local p="$1" d b
  case "$p" in /*) ;; *) echo "path must be absolute: $p"; return 1 ;; esac
  case "/$p/" in */../*|*/./*) echo "'.' or '..' segment in path: $p"; return 1 ;; esac
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  [ "$p" = / ] && { echo "refused path: /"; return 1; }
  d=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P) || { echo "parent directory does not exist: $p"; return 1; }
  b=$(basename "$p")
  if [ "$d" = / ]; then printf '/%s\n' "$b"; else printf '%s/%s\n' "$d" "$b"; fi
}
hm_check_path_safe() {  # hm_check_path_safe <resolved> <project root>: never a protected place, a symlink or another user's
  local rp="$1" root="$2" q
  for q in / "$HOME" "$root" /tmp /private/tmp "${TMPDIR:-}"; do
    [ -n "$q" ] && [ -d "$q" ] || continue
    q=$(cd "$q" && pwd -P)
    case "$q/" in "$rp"/*) echo "refused path (is or contains a protected directory): $rp"; return 1 ;; esac
  done
  [ "$rp" = "$root/.hivemind" ] && { echo "refused path: $rp"; return 1; }
  if [ -L "$rp" ]; then echo "refused: $rp is a symlink"; return 1; fi
  if [ -e "$rp" ] && [ ! -O "$rp" ]; then echo "refused: $rp is not owned by the caller"; return 1; fi
  return 0
}
hm_check_path_outside() {  # hm_check_path_outside <resolved> <project root> <manifest file>: file and dir entries
  local rp="$1" root="$2" w
  case "$rp/" in "$root/.hivemind/tmp/"*) ;; "$root/"*) echo "refused: $rp is inside the project"; return 1 ;; esac
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    case "$rp/" in "$w/"*) echo "refused: $rp is inside the recorded worktree $w"; return 1 ;; esac
  done < <(jq -r 'select(.kind == "worktree") | .path' "$3")
  return 0
}
