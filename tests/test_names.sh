#!/usr/bin/env bash
# Each name is spelled in one place (the rename plan's phase 1): a folder or path name only in its constant (bin/hh-lib.sh,
# hooks/names.ts) or its test helper (tests/lib.sh, tests/names.ts); the plugin's name only in .claude-plugin/plugin.json,
# read by hh_plugin_name. Docs (README, skills, roles, rules, workflows, evals) and comments are not held to this.
. "$(dirname "$0")/lib.sh"
t_setup
cd "$HH_REPO_ROOT"
# ---- the grep: what is left once the allowed places and the comments are taken away ----
NAMES='\.hivehouse|hivehouse-(hub|delegate)|/hivehouse($|[^a-z-])|["'"'"'`]hivehouse: |hivehouse:[a-z]|hivehouse@'
stray() {  # stray <file>...: the lines of those files that spell a name outside a comment; a constants line is allowed
  local f
  for f in "$@"; do
    sed -e 's/^[[:space:]]*#.*$//' -e 's/^[[:space:]]*\/\/.*$//' -e 's/[[:space:]]#[[:space:]].*$//' -e 's/[[:space:]]\/\/[[:space:]].*$//' "$f" \
      | grep -nE "$NAMES" | grep -vE '^[0-9]+:(HH_[A-Z_0-9]+|T_[A-Z_0-9]+)=|^[0-9]+:export const [A-Z_]+ =' | sed "s|^|$f:|"
  done
}
prod=$(stray bin/hh-* hooks/*.tsx hooks/hooks.json)
assert_eq "bin/ and hooks/ spell no folder, path or command name outside their constants" "$prod" ""
tests=$(stray tests/test_*.sh tests/*.test.ts tests/bin/* | grep -v '^tests/test_names.sh:')
assert_eq "the tests spell none outside tests/lib.sh and tests/names.ts" "$tests" ""
# the one other place the plugin's name is a literal: the key of the atoms' types, which TypeScript cannot take from a constant
assert_eq "types/index.d.ts keys the atoms by the plugin's name" "$(sed -n 's/^    \([a-z-]*\): { hubView.*/\1/p' types/index.d.ts)" "$T_PLUGIN"
# ...and the atoms' plugin, a literal the engine reads from the source of hooks/hub.tsx
assert_eq "hooks/hub.tsx declares 3 atoms" "$(grep -c "atom({ plugin: '" hooks/hub.tsx)" "3"
assert_eq "...each in the plugin's name" "$(grep -o "atom({ plugin: '[^']*'" hooks/hub.tsx | sort -u)" "atom({ plugin: '$T_PLUGIN'"
# the constants are where the grep says they are, once each
for c in HH_PREFIX HH_STATE_DIR HH_HUB_DIR HH_HOME_DIR HH_MAC_BASE HH_LINUX_BASE HH_LINUX_SLOT HH_DELEGATE_TAG HH_DELEGATE_VERSIONS HH_DELEGATE_WRITE HH_CUSTOM_DIR; do
  assert_eq "bin/hh-lib.sh defines $c once" "$(grep -c "^$c=" bin/hh-lib.sh)" "1"
done
for c in PLUGIN PREFIX HUB_DIR PANE; do
  assert_eq "hooks/names.ts exports $c once" "$(grep -c "^export const $c " hooks/names.ts)" "1"
done
# every name stated twice (bin/ or hooks/ against the test helper) agrees, and the plugin's name is the one in plugin.json
tsval() {  # tsval <file> <export name>: the string a `export const NAME = '...'` line gives
  sed -n "s/^export const $2\( as const\)\{0,1\} = '\([^']*\)'.*/\2/p" "$1"
}
assert_eq "hooks/names.ts PLUGIN is plugin.json's name" "$(tsval hooks/names.ts PLUGIN)" "$T_PLUGIN"
assert_eq "tests/names.ts PLUGIN is plugin.json's name" "$(tsval tests/names.ts PLUGIN)" "$T_PLUGIN"
assert_eq "hooks/names.ts PREFIX is the helper's" "$(tsval hooks/names.ts PREFIX)" "$T_PREFIX"
assert_eq "tests/names.ts PREFIX is the helper's" "$(tsval tests/names.ts PREFIX)" "$T_PREFIX"
assert_eq "hooks/names.ts HUB_DIR is the helper's" "$(tsval hooks/names.ts HUB_DIR)" "$T_HUB"
assert_eq "tests/names.ts HUB_DIR is the helper's" "$(tsval tests/names.ts HUB_DIR)" "$T_HUB"
assert_eq "hooks/names.ts PANE is the helper's" "$(tsval hooks/names.ts PANE)" "$T_PANE"
assert_eq "tests/names.ts PANE_ID is the helper's" "$(tsval tests/names.ts PANE_ID)" "$T_PANE"
for pair in HH_PREFIX:T_PREFIX HH_STATE_DIR:T_STATE HH_HUB_DIR:T_HUB HH_HOME_DIR:T_HOMEDIR HH_MAC_BASE:T_MAC_BASE HH_LINUX_BASE:T_LINUX_BASE HH_LINUX_SLOT:T_LINUX_SLOT HH_DELEGATE_TAG:T_DELEGATE_TAG HH_WINDOW_DEFAULT:T_WINDOW; do
  v=$(bash -c '. "$1/bin/hh-lib.sh"; eval "printf %s \"\$$2\""' _ "$HH_REPO_ROOT" "${pair%%:*}"); w=$(eval "printf %s \"\$${pair##*:}\"")
  assert_eq "${pair%%:*} is the helper ${pair##*:}" "$v" "$w"
done
# ---- plugin.json's three window defaults are the one default window ----
for k in window_orchestrator window_builder window_reviewer; do
  assert_eq "plugin.json $k default is the one window" "$(jq -r --arg k "$k" '.userConfig[$k].default' "$HH_REPO_ROOT/.claude-plugin/plugin.json")" "$T_WINDOW"
done
# ---- the plugin's name is read, not spelled: a plugin folder whose name is zz speaks of /zz: ----
P="$T_TMP/zz-plugin"; mkdir -p "$P/.claude-plugin"; cp -R "$HH_REPO_ROOT/bin" "$P/bin"
jq '.name = "zz"' "$HH_REPO_ROOT/.claude-plugin/plugin.json" > "$P/.claude-plugin/plugin.json"
assert_eq "hh_plugin_name reads .claude-plugin/plugin.json" "$(bash -c '. "$1/bin/hh-lib.sh"; hh_plugin_name' _ "$P")" "zz"
HUBF="$T_TMP/hubf"; mkdir -p "$HUBF/$T_HUB"
out=$(printf '{"cwd":"%s","session_id":"x","source":"startup"}' "$HUBF" | "$P/bin/hh-session-hook")
assert_contains "the session hook names the hub skill by the plugin's name" "$out" "invoke the zz:hub skill"
out=$("$P/bin/hh-disk" --hook --min-gb 99999999)
assert_contains "the low-disk line names the cleanup skill by the plugin's name" "$out" "Run /zz:cleanup"
rm "$P/.claude-plugin/plugin.json"
out=$(bash -c '. "$1/bin/hh-lib.sh"; hh_plugin_name' _ "$P" 2>&1); rc=$?
assert_status "...and an unreadable plugin.json is an error, not an empty name" "$rc" 2
assert_contains "...that says so" "$out" "cannot read the plugin's name"
t_done
