#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
# The moved-in docs-health-check workflow: the default is the current project, report only; named groups only by args.
W="$HH_REPO_ROOT/workflows/docs-health-check.workflow.js"
H="$HH_REPO_ROOT/tests/fixtures/docs-health-harness.mjs"
run() { node "$H" "$W" "$1" "${2-}"; }
field() { printf '%s' "$1" | jq -r "$2"; }

out=$(run undefined /some/proj)
assert_eq "no args: runs" "$(field "$out" .ok)" "true"
assert_eq "no args: report only" "$(field "$out" .mode)" "report"
assert_eq "no args: the current project, named by its folder" "$(field "$out" '.groups|join(",")')" "proj"
assert_contains "no args: one small agent finds the root" "$(field "$out" '.calls|join(",")')" "find-project-root"
prompt=$(field "$out" .reportPrompt)
assert_contains "no args: the report goes under $T_STATE/reports, not docs/" "$prompt" "write the report to /some/proj/$T_STATE/reports/docs-health-report-<date>.md"
case "$prompt" in */some/proj/docs/*) bad "no args: nothing is written under docs/" ;; *) ok "no args: nothing is written under docs/" ;; esac
assert_contains "no args: the report agent makes git ignore $T_STATE/ first" "$prompt" "grep -qx '/$T_STATE/' \"\$common/info/exclude\" || echo '/$T_STATE/' >> \"\$common/info/exclude\""
assert_contains "no args: that is the line hh_ensure_state writes" "$(grep -n "grep -qx" "$HH_REPO_ROOT/bin/hh-lib.sh")" 'grep -qx "/$HH_STATE_DIR/" "$excl" || echo "/$HH_STATE_DIR/" >> "$excl"'
assert_contains "no args: it appends only when absent and refuses to write into a tracked $T_STATE/" "$prompt" "ls-files -- $T_STATE"
out=$(run '{"reportPath":"/elsewhere/report.md"}' /some/proj)
prompt=$(field "$out" .reportPrompt)
assert_contains "a given reportPath is used as it is" "$prompt" "Write the report to /elsewhere/report.md"
case "$prompt" in *"info/exclude"*) bad "a given reportPath touches no git exclude" ;; *) ok "a given reportPath touches no git exclude" ;; esac
case "$(field "$out" '.calls|join(",")')" in *xref:*) bad "a single repo gets no cross-repo agent" ;; *) ok "a single repo gets no cross-repo agent" ;; esac
case "$(field "$out" '.calls|join(",")')" in *apply:*) bad "report mode applies nothing" ;; *) ok "report mode applies nothing" ;; esac

out=$(run '"apply 60"' /some/proj)
assert_eq "apply by text" "$(field "$out" .mode)" "apply"
assert_contains "apply runs the apply agent" "$(field "$out" '.calls|join(",")')" "apply:proj"
out=$(run '{"mode":"apply"}' /some/proj); assert_eq "apply by object" "$(field "$out" .mode)" "apply"
out=$(run '{"mode":"nonsense"}' /some/proj); assert_eq "an unknown mode is report" "$(field "$out" .mode)" "report"

out=$(run undefined ""); assert_eq "outside a git repo: refused" "$(field "$out" .ok)" "false"
assert_contains "outside a git repo: says so" "$(field "$out" .err)" "not inside a git repository"
out=$(run undefined "relative/path"); assert_eq "a root that is not absolute is refused" "$(field "$out" .ok)" "false"

out=$(run '{"group":"X"}' /some/proj); assert_eq "a group name without groups is refused" "$(field "$out" .ok)" "false"
out=$(run '"Backend"' /some/proj); assert_eq "a group name in text without groups is refused" "$(field "$out" .ok)" "false"

out=$(run '{"groups":[{"name":"A","repos":["/a","/b"]},{"name":"B","repos":["/c"]}]}' /never)
assert_eq "named groups: every group" "$(field "$out" '.groups|join(",")')" "A,B"
case "$(field "$out" '.calls|join(",")')" in *find-project-root*) bad "named groups do not look for the current project" ;; *) ok "named groups do not look for the current project" ;; esac
assert_contains "a group of two repos is compared across" "$(field "$out" '.calls|join(",")')" "xref:A"
out=$(run '{"groups":[{"name":"A","repos":["/a"]},{"name":"B","repos":["/c"]}],"group":"b"}' /never)
assert_eq "one named group, case-insensitive" "$(field "$out" '.groups|join(",")')" "B"
out=$(run '{"groups":[{"name":"A","repos":["/a"]}],"group":"zzz"}' /never); assert_eq "no group matched is refused" "$(field "$out" .ok)" "false"

# the write line is conditional on the tracked check, which comes first; nothing writes to .hivehouse/reports unconditionally (S1)
out=$(run undefined /some/proj); prompt=$(field "$out" .reportPrompt)
before_tracked=${prompt%%those files are tracked*}; before_cond=${prompt%%'Unless the check above sent the report to'*}
if [ "$before_tracked" != "$prompt" ] && [ "$before_cond" != "$prompt" ] && [ ${#before_tracked} -lt ${#before_cond} ]; then ok "the tracked-$T_STATE sentence comes before the conditional write line"; else bad "the tracked-$T_STATE sentence comes before the conditional write line"; fi
assert_contains "the write line is conditional" "$prompt" 'Unless the check above sent the report to ${TMPDIR:-/tmp}, write the report to /some/proj/'"$T_STATE"'/reports/docs-health-report-<date>.md'
case "$prompt" in *"Write the report to /some/proj/$T_STATE"*) bad "no unconditional write line to $T_STATE/reports" ;; *) ok "no unconditional write line to $T_STATE/reports" ;; esac
case "$prompt" in *"the path above"*) bad "no ambiguous 'the path above'" ;; *) ok "no ambiguous 'the path above'" ;; esac
assert_contains "the only in-repo exception is named by its path" "$prompt" 'anywhere but at /some/proj/'"$T_STATE"'/reports/docs-health-report-<date>.md, and never under '"$T_STATE"'/ when the check above found it tracked'
out=$(run '{"reportPath":"/elsewhere/report.md"}' /some/proj); prompt=$(field "$out" .reportPrompt)
assert_contains "a given path is written unconditionally" "$prompt" 'Write the report to /elsewhere/report.md (create the file'
case "$prompt" in *"Unless the check above"*|*"never under $T_STATE/"*) bad "a given path has no tracked-check wording" ;; *) ok "a given path has no tracked-check wording" ;; esac

# a report that cannot go under .hivehouse/ goes outside every repository, never into the working directory (S1 again)
for spec in undefined '{"reportPath":"/elsewhere/report.md"}'; do
  out=$(run "$spec" /some/proj); prompt=$(field "$out" .reportPrompt)
  assert_contains "fallback ($spec): outside every repository, in TMPDIR" "$prompt" 'OUTSIDE every repository, to '
  assert_contains "fallback ($spec): the TMPDIR path is written for the agent to resolve" "$prompt" '${TMPDIR:-/tmp}/docs-health-report-<date>.md'
  assert_contains "fallback ($spec): it says so in the returned path and the summary" "$prompt" 'say so in the reportPath you return and in the summary'
  case "$prompt" in *"current directory"*) bad "fallback ($spec): never the current directory" ;; *) ok "fallback ($spec): never the current directory" ;; esac
done
out=$(run undefined /some/proj); prompt=$(field "$out" .reportPrompt)
assert_contains "a tracked $T_STATE/ is never written to" "$prompt" 'those files are tracked, so do not write under '"$T_STATE"'/ at all'

# args.groups is shape-checked: the workflow's own message, never a TypeError
for bad_groups in '[{"name":"A"}]' '[{"name":"A","repos":[]}]' '[{"name":"A","repos":[7]}]' '[{"name":"A","repos":["relative/path"]}]' '[{"repos":["/a"]}]' '[null]' '[]' '"A"' '{"name":"A","repos":["/a"]}'; do
  out=$(run "{\"groups\":$bad_groups}" /never)
  assert_eq "bad groups $bad_groups: refused" "$(field "$out" .ok)" "false"
  assert_contains "bad groups $bad_groups: the workflow's own message" "$(field "$out" .err)" "docs-health-check: args.groups"
  case "$(field "$out" .err)" in *TypeError*|*"Cannot read"*) bad "bad groups $bad_groups: not a TypeError" ;; *) ok "bad groups $bad_groups: not a TypeError" ;; esac
done

# the file itself
if grep -nE '/Users/' "$W" >/dev/null; then bad "the workflow names no user path"; else ok "the workflow names no user path"; fi
assert_contains "meta names the workflow" "$(sed -n '/^export const meta/,/^}/p' "$W")" "name: 'docs-health-check'"
[ ! -e "$HH_REPO_ROOT/skills/docs-health-check" ] && ok "no wrapper skill (A8)" || bad "no wrapper skill (A8)"
t_done
