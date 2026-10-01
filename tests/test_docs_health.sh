#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
# The moved-in docs-health-check workflow: the default is the current project, report only; named groups only by args.
W="$HM_REPO_ROOT/workflows/docs-health-check.workflow.js"
H="$HM_REPO_ROOT/tests/fixtures/docs-health-harness.mjs"
run() { node "$H" "$W" "$1" "${2-}"; }
field() { printf '%s' "$1" | jq -r "$2"; }

out=$(run undefined /some/proj)
assert_eq "no args: runs" "$(field "$out" .ok)" "true"
assert_eq "no args: report only" "$(field "$out" .mode)" "report"
assert_eq "no args: the current project, named by its folder" "$(field "$out" '.groups|join(",")')" "proj"
assert_contains "no args: one small agent finds the root" "$(field "$out" '.calls|join(",")')" "find-project-root"
assert_contains "no args: the report is written under the project's docs" "$(field "$out" '.calls|join(",")')" "/some/proj/docs/docs-health-report-<date>.md"
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

# the file itself
if grep -nE '/Users/|discourse' "$W" >/dev/null; then bad "the workflow names no project and no user path"; else ok "the workflow names no project and no user path"; fi
assert_contains "meta names the workflow" "$(sed -n '/^export const meta/,/^}/p' "$W")" "name: 'docs-health-check'"
[ ! -e "$HM_REPO_ROOT/skills/docs-health-check" ] && ok "no wrapper skill (A8)" || bad "no wrapper skill (A8)"
t_done
