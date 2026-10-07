#!/usr/bin/env bash
# The hub's screen and guard (hooks/hub.tsx) through Claude Code's own mod test kit: `claude plugin test` runs the
# *.test.ts files beside this one against the engine, with no model call. The real claude is found before lib.sh puts the
# fake one first on PATH; without it, or one too old to have the kit, the check is skipped and says so.
real=$(command -v claude 2>/dev/null)
. "$(dirname "$0")/lib.sh"
t_setup
# Claude Code refuses a command named as one of the plugin's own skills, which the kit cannot see: the name is held here
cmd=$(sed -n "s/^const COMMAND = '\\([^']*\\)'.*/\\1/p" "$HH_REPO_ROOT/hooks/hub.tsx")
[ -n "$cmd" ] && ok "the screen's command is declared once: /$cmd" || bad "no COMMAND in hooks/hub.tsx"
[ -e "$HH_REPO_ROOT/skills/$cmd" ] && bad "/$cmd is also a skill's name, which Claude Code refuses" || ok "...and is no skill's name"
if [ -z "$real" ] || ! "$real" plugin test --help >/dev/null 2>&1; then
  echo "  SKIP claude plugin test is not available here"; t_done; exit 0
fi
out=$(cd "$HH_REPO_ROOT" && CLAUDE_CONFIG_DIR="$HOME/.claude" "$real" plugin test . 2>&1); rc=$?
assert_status "claude plugin test" "$rc" 0
assert_contains "...ran the hub's screen tests" "$out" "hub_screen.test.ts"
assert_contains "...and the outside-the-hub test" "$out" "hub_elsewhere.test.ts"
assert_contains "...none failed" "$out" " 0 fail"
[ "$rc" -eq 0 ] || printf '%s\n' "$out" | grep -E '^\(fail\)|Error' | head -10
t_done
