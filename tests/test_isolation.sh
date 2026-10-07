#!/usr/bin/env bash
# A suite started from a session that has another generation of these tools on its PATH and in its environment must reach
# neither (the 7 Oct leak: a fake claude called a tool by a name this repo's bin no longer had, and the tool on the caller's PATH
# wrote the real team state). The foreign generation is modelled with a made-up prefix, zz. Two defences, each held here:
# the PATH loses every other plugin's bin/ (by identity: a parent holding .claude-plugin/plugin.json), and the environment is an
# allowlist (nothing else the caller exported survives). A canary home and project must come out byte for byte as they went in.
. "$(dirname "$0")/lib.sh"
t_setup
F="$T_TMP/zz-plugin"; mkdir -p "$F/bin" "$F/.claude-plugin"; printf '{"name":"zz"}\n' > "$F/.claude-plugin/plugin.json"
CAN="$T_TMP/canary"; mkdir -p "$CAN/home/registry" "$CAN/proj"; printf 'keep\n' > "$CAN/home/registry/pane.json"; printf 'keep\n' > "$CAN/proj/team.json"
snap() { (cd "$CAN" && find . -type f | sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }
before=$(snap)
# a foreign plugin's tool: reachable only through a plugin bin/, and it would write the poisoned home and project
printf '#!/usr/bin/env bash\ntouch "%s/ran-foreign-plugin"\n[ -z "${ZZ_HOME:-}" ] || printf x >> "$ZZ_HOME/registry/pane.json"\n[ -z "${ZZ_PROJECT:-}" ] || printf x >> "$ZZ_PROJECT/team.json"\n' "$CAN" > "$F/bin/zz-spawn"
# a tool in an ordinary PATH folder: the PATH filter leaves it, so only the environment can keep the caller's variables from it
P="$T_TMP/plain/bin"; mkdir -p "$P"
printf '#!/usr/bin/env bash\n[ -z "${ZZ_HOME:-}" ] || printf x >> "$ZZ_HOME/registry/pane.json"\n[ -z "${GIT_DIR:-}" ] || touch "%s/saw-git-dir"\n[ -z "${HM_PROJECT:-}" ] || touch "%s/saw-own-project"\n[ -z "${TMUX:-}" ] || touch "%s/saw-tmux"\necho reached\n' "$CAN" "$CAN" "$CAN" > "$P/zz-reg"
chmod +x "$F/bin/zz-spawn" "$P/zz-reg"
# the probe: a test's own start (lib.sh, t_setup) inside the poisoned caller; the stand-in claude has the shape of the leaking one
cat > "$T_TMP/probe.sh" <<'PROBE'
. "$1/tests/lib.sh"
t_setup
echo "foreign-tool: $(command -v zz-spawn || echo none)"
echo "plain-tool: $(command -v zz-reg || echo none)"
printf '#!/usr/bin/env bash\nzz-spawn "$@"; echo rc=$?\nzz-reg\n' > "$T_TMP/standin"
echo "standin: $(bash "$T_TMP/standin" 2>&1 | tr '\n' ' ')"
echo "vars: $(env | grep -cE '^(ZZ_|GIT_DIR=|TMUX=|HM_PROJECT=|HM_AGENT=)')"
echo "home: $HOME"
echo "path-head: ${PATH%%:*}"
echo "own-bin: $(command -v $2)"
echo "tools: $(command -v git jq tmux | wc -l | tr -d ' ')"
echo "cleanup-switch: ${HM_CLEANUP_TEST:-unset}"
PROBE
out=$(env ZZ_HOME="$CAN/home" ZZ_PROJECT="$CAN/proj" ZZ_AGENT=orchestrator HM_PROJECT="$CAN/proj" HM_AGENT=orchestrator GIT_DIR="$CAN/proj/.git" TMUX=/tmp/zz,1,0 \
  HM_CLEANUP_TEST=1 PATH="$F/bin:$P:$PATH" bash "$T_TMP/probe.sh" "$HM_REPO_ROOT" hm-hub 2>&1)
field() { printf '%s\n' "$out" | sed -n "s/^$1: //p"; }
assert_eq "the foreign plugin's tool is not on the suite's PATH" "$(field foreign-tool)" "none"
assert_contains "...a stand-in claude that calls it finds nothing (127)" "$(field standin)" "rc=127"
assert_contains "...and the tool in an ordinary folder is still there" "$(field plain-tool)" "zz-reg"
assert_contains "...and runs" "$(field standin)" "reached"
assert_eq "none of the caller's variables survives (ZZ_*, the tool's own, GIT_DIR, TMUX)" "$(field vars)" "0"
assert_eq "the canary home and project are byte for byte as they were" "$(snap)" "$before"
[ ! -e "$CAN/ran-foreign-plugin" ] && ok "the foreign tool never ran" || bad "the foreign tool ran"
for m in saw-git-dir saw-own-project saw-tmux; do [ ! -e "$CAN/$m" ] && ok "the plain tool did not see $m" || bad "the plain tool saw $m"; done
assert_eq "HOME is kept" "$(field home)" "$HOME"
assert_eq "this repo's tests/bin stays first on PATH" "$(field path-head)" "$HM_REPO_ROOT/tests/bin"
assert_eq "this repo's own tools are the ones found" "$(field own-bin)" "$HM_REPO_ROOT/bin/hm-hub"
assert_eq "git, jq and tmux are still found" "$(field tools)" "3"
assert_eq "the opt-in switch of the cleanup test is kept" "$(field cleanup-switch)" "1"
t_done
