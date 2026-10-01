#!/usr/bin/env bash
# The eval cases, checked without running Claude (running them is paid): every case loads by the documented schema, every
# scaffold builds its workspace as an eval run would, the markers the graders look for are written by no instruction a
# run loads, and the documented run grants nothing the start skill does not. A missing ruby, node or skills/ is a failure,
# never a skip: a check that did not run must not read as one that passed.
. "$(dirname "$0")/lib.sh"
t_setup
EVALS="${HM_EVALS_DIR:-$HM_REPO_ROOT/evals}"
SKILLS="${HM_SKILLS_DIR:-$HM_REPO_ROOT/skills}"
export T_TMP

# ---- schema: the keys and values https://code.claude.com/docs/en/plugin-evals documents ---------------------------
if command -v ruby >/dev/null 2>&1; then
  out=$(ruby -ryaml -rjson - "$EVALS" <<'RUBY'
evals = ARGV[0]
PROMPT_KEYS = %w[schema_version name description tags plugins runs expected_outcome model max_turns timeout_seconds allowed_tools append_system_prompt env]
CASE_KEYS = %w[schema_version name description tags plugins runs expected_outcome execution context graders]
CONTEXT_KEYS = %w[scaffold_script history_file add_dirs]
COMMON = %w[type weight arm]
TYPES = { 'regex' => %w[pattern flags match target], 'tool_used' => %w[tool input_match min max],
          'tool_order' => %w[before after], 'file_exists' => %w[path exists], 'llm' => %w[criteria focus],
          'baseline' => %w[baseline_file criteria] }
TARGETS = %w[last_message trace files mock_calls]
def say(ok, label); puts("#{ok ? 'ok' : 'FAIL'}\t#{label}"); end
def front(path)
  text = File.read(path)
  m = text.match(/\A---\n(.*?)\n---\n?(.*)\z/m) or return [nil, text]
  [YAML.safe_load(m[1]) || {}, m[2]]
end
cases = Dir.children(evals).sort.map { |d| File.join(evals, d) }.select { |d| File.exist?("#{d}/prompt.md") || File.exist?("#{d}/case.yaml") }
say(!cases.empty?, 'at least one case')
regexes = []
cases.each do |dir|
  c = File.basename(dir)
  y = File.exist?("#{dir}/case.yaml") ? (YAML.safe_load(File.read("#{dir}/case.yaml")) || {}) : {}
  say(y.empty? || y['schema_version'] == '1.1', "#{c}: case.yaml schema_version is \"1.1\"")
  say(y.empty? || y['name'] == c, "#{c}: case.yaml name is the directory's")
  say((y.keys - CASE_KEYS).empty?, "#{c}: case.yaml keys are documented#{(y.keys - CASE_KEYS).empty? ? '' : ' ' + (y.keys - CASE_KEYS).inspect}")
  ctx = y['context'] || {}
  say((ctx.keys - CONTEXT_KEYS).empty?, "#{c}: context keys are documented")
  say(ctx['scaffold_script'].nil? || File.file?("#{dir}/#{ctx['scaffold_script']}"), "#{c}: the scaffold script is in the case directory")
  fm, body = File.exist?("#{dir}/prompt.md") ? front("#{dir}/prompt.md") : [{}, (y.dig('execution', 'prompt') || '')]
  say(!fm.nil?, "#{c}: prompt.md frontmatter parses")
  fm ||= {}
  say((fm.keys - PROMPT_KEYS).empty?, "#{c}: prompt.md keys are documented#{(fm.keys - PROMPT_KEYS).empty? ? '' : ' ' + (fm.keys - PROMPT_KEYS).inspect}")
  say(!body.strip.empty?, "#{c}: the prompt is not empty")
  say(fm['max_turns'].nil? || fm['max_turns'].between?(1, 200), "#{c}: max_turns is within 200")
  say(fm['timeout_seconds'].nil? || fm['timeout_seconds'].between?(1, 3600), "#{c}: timeout_seconds is within 3600")
  graders = (y['graders'] || []).map { |g| [g['name'], g] }
  Dir.glob("#{dir}/graders/*.md").sort.each { |f| g, b = front(f); g ||= {}; g['criteria'] ||= b unless b.to_s.strip.empty?; graders << [File.basename(f, '.md'), g] }
  say(!graders.empty?, "#{c}: at least one grader")
  graders.each do |name, g|
    t = g['type']
    say(TYPES.key?(t), "#{c}/#{name}: type #{t.inspect} is one of the six")
    next unless TYPES.key?(t)
    extra = g.keys - COMMON - TYPES[t] - ['name']
    say(extra.empty?, "#{c}/#{name}: keys are documented for #{t}#{extra.empty? ? '' : ' ' + extra.inspect}")
    say(g['arm'].nil? || %w[with-only both].include?(g['arm']), "#{c}/#{name}: arm is with-only or both")
    if t == 'regex'
      say(g['target'].nil? || TARGETS.include?(g['target']) || g['target'].is_a?(Hash), "#{c}/#{name}: target is documented")
      say(g['match'].nil? || g['match'] == 'not_contains' || g['match'].to_s.match?(/\Acount:\d+\z/), "#{c}/#{name}: match is not_contains or count:N")
      regexes << { label: "#{c}/#{name}", pattern: g['pattern'].to_s, flags: g['flags'].to_s }
    end
    if t == 'tool_used'
      regexes << { label: "#{c}/#{name}", pattern: g['input_match'].to_s, flags: '' } if g['input_match']
      say(g['min'].nil? || g['max'].nil? || g['min'] <= g['max'], "#{c}/#{name}: min is not above max")
    end
  end
end
# What each case's run may and may not do with a tool, as [tool, min, max] (nil: unbounded); a grader dropped or loosened
# is a failure here before it is a run that passes for the wrong reason.
TOOL_RULES = {
  'start-asks-nothing' => [['AskUserQuestion', 0, 0]],
  'start-asks-open-point' => [['AskUserQuestion', 1, nil]],
  'start-plans-and-waits' => [['Edit', 0, 0], ['Write', 0, 0], ['SendMessage', 0, 0]],
}
TOOL_RULES.each do |c, rules|
  y = File.exist?("#{evals}/#{c}/case.yaml") ? (YAML.safe_load(File.read("#{evals}/#{c}/case.yaml")) || {}) : {}
  used = (y['graders'] || []).select { |g| g['type'] == 'tool_used' && g['input_match'].nil? }
  rules.each do |tool, min, max|
    g = used.find { |u| u['tool'] == tool }
    say(!g.nil? && (g['min'] || 1) == min && g['max'] == max, "#{c}: #{tool} is graded with min #{min} and max #{max.nil? ? 'none' : max}")
  end
end
File.write(File.join(ENV['T_TMP'], 'regexes.json'), JSON.generate(regexes))
RUBY
  ) || bad "the schema check ran"
  while IFS=$'\t' read -r verdict label; do
    [ "$verdict" = ok ] && ok "$label" || bad "$label"
  done <<< "$out"
  # JavaScript regex syntax, which the graders use: compiled by node when it is here
  if command -v node >/dev/null 2>&1; then
    js=$(node -e 'for (const r of JSON.parse(require("fs").readFileSync(process.argv[1]))) {
      try { new RegExp(r.pattern, r.flags); console.log("ok\t" + r.label + ": the pattern compiles as JavaScript"); }
      catch (e) { console.log("FAIL\t" + r.label + ": " + e.message); } }' "$T_TMP/regexes.json")
    while IFS=$'\t' read -r verdict label; do [ "$verdict" = ok ] && ok "$label" || bad "$label"; done <<< "$js"
    # nothing-spawned counts a spawn and only a spawn, on the JSON a Bash call's input is encoded as
    js=$(node -e 'const rs = JSON.parse(require("fs").readFileSync(process.argv[1])).filter(r => r.label.endsWith("/nothing-spawned"));
      console.log((rs.length > 0 ? "ok" : "FAIL") + "\tevery case has a nothing-spawned grader");
      const spawns = ["hm-spawn --agent impl --role r.md", "cd /w && hm-spawn --agent impl", "/p/bin/hm-spawn --agent impl", "hm-slot status; hm-spawn --agent a",
        "echo a\nhm-spawn --agent b", "  hm-spawn --agent a", "HM_X=1 hm-spawn --agent a", "env A=1 hm-spawn --agent a", "timeout 60 hm-spawn --agent a",
        "nohup hm-spawn --agent a &", "`hm-spawn --agent a`", "{ hm-spawn --agent a; }", "bash -c \"hm-spawn --agent a\""];
      const not = ["hm-spawn --self --agent orch", "hm-spawn --self --agent o && echo ok", "command -v hm-spawn", "which hm-spawn", "echo \"run hm-spawn\"",
        "echo a\\nhm-spawn --agent b", "hm-spawn-x --agent a"];
      for (const r of rs) {
        const re = new RegExp(r.pattern, r.flags);
        for (const c of spawns) console.log((re.test(JSON.stringify({ command: c, description: "d" })) ? "ok" : "FAIL") + "\t" + r.label + " counts " + JSON.stringify(c));
        for (const c of not) console.log((re.test(JSON.stringify({ command: c, description: "d" })) ? "FAIL" : "ok") + "\t" + r.label + " does not count " + JSON.stringify(c));
      }' "$T_TMP/regexes.json")
    while IFS=$'\t' read -r verdict label; do [ "$verdict" = ok ] && ok "$label" || bad "$label"; done <<< "$js"
  else bad "node is installed, which compiles the graders' JavaScript patterns"; fi
else bad "ruby is installed, which reads the cases' YAML"; fi

# ---- every scaffold is the shared one: two lines sourcing evals/scaffold-records.sh -------------------------------
wrapper='#!/usr/bin/env bash
. "$(dirname "$0")/../scaffold-records.sh"'
for script in "$EVALS"/*/scaffold.sh; do
  [ -f "$script" ] || continue
  assert_eq "$(basename "$(dirname "$script")"): scaffold.sh is the two-line wrapper" "$(cat "$script")" "$wrapper"
done

# ---- every scaffold builds its workspace as a run would: an empty directory, a minimal environment, 120 s ---------
for script in "$EVALS"/*/scaffold.sh; do
  [ -f "$script" ] || continue
  c=$(basename "$(dirname "$script")"); ws="$T_TMP/ws-$c"; mkdir -p "$ws" "$T_TMP/home-$c"
  (cd "$ws" && env -i PATH="$PATH" HOME="$T_TMP/home-$c" TMPDIR="$T_TMP" TERM=dumb bash "$script" >"$T_TMP/scaffold-$c.log" 2>&1) & p=$!
  waited=0; while kill -0 $p 2>/dev/null && [ $waited -lt 120 ]; do sleep 1; waited=$((waited + 1)); done
  if kill -0 $p 2>/dev/null; then kill $p; wait $p 2>/dev/null; bad "$c: the scaffold ends within 120 s"; continue; fi
  wait $p; assert_status "$c: the scaffold exits 0" $? 0
  if [ -d "$ws/.git" ]; then
    assert_eq "$c: it leaves a clean tree, which first-run.md checks" "$(git -C "$ws" status --porcelain)" ""
  fi
  if [ -f "$ws/Makefile" ] && [ -f "$ws/CLAUDE.md" ] && grep -q 'make test' "$ws/CLAUDE.md"; then
    (cd "$ws" && make -s test >/dev/null 2>&1); assert_status "$c: the gate CLAUDE.md records passes" $? 0
  fi
done

# ---- the markers: no instruction a run loads writes one at a line start -------------------------------------------
# The graders match `HM-PLAN:` and `HM-CLARIFY:` at the start of a text or after a newline in the trace. The skill's
# instructions and the case prompts are in the trace too, so neither may have a line that starts with a marker.
loaded=$(ls "$EVALS"/*/prompt.md 2>/dev/null)
if [ -d "$SKILLS" ]; then loaded="$loaded"$'\n'$(find "$SKILLS" -name '*.md'); else bad "the skills are here (on a branch without skills/, set HM_SKILLS_DIR to an export of them)"; fi
hits=$(printf '%s\n' "$loaded" | grep -v '^$' | xargs grep -nE '^HM-(PLAN|CLARIFY):' 2>/dev/null)
assert_eq "no loaded instruction starts a line with a marker" "$hits" ""

# ---- the documented run grants only what the start skill grants ---------------------------------------------------
if [ -f "$SKILLS/start/SKILL.md" ]; then
  skill=$(sed -n 's/^allowed-tools: //p' "$SKILLS/start/SKILL.md" | head -1)
  grants=$(sed -n '/claude plugin eval \. /,/^```/p' "$EVALS/README.md" | grep -oE '"[A-Za-z]+\([^"]*\)"' | tr -d '"')
  [ -n "$grants" ] && ok "the documented run names its grants" || bad "the documented run names its grants"
  for g in $(printf '%s\n' "$grants" | tr ' ' '\001'); do
    g=$(printf '%s' "$g" | tr '\001' ' ')
    case " $skill " in *" $g "*) ok "the start skill grants $g" ;; *) bad "the documented run grants $g, which the start skill does not" ;; esac
  done
  # the orchestrator registers and rotates itself under a bare agent name: the project is added where a name is shown
  names=$(grep -oE '`(hm-spawn --self --agent|hm-self-rotate) [^` ]+' "$SKILLS/start/SKILL.md" | awk '{print $NF}')
  [ "$(printf '%s\n' "$names" | grep -c .)" -ge 2 ] && ok "the start skill names its own agent for --self and hm-self-rotate" \
    || bad "the start skill names its own agent for --self and hm-self-rotate"
  for n in $names; do
    case "$n" in *[!abcdefghijklmnopqrstuvwxyz0123456789_-]*|[-_]*) bad "the start skill's own agent name is bare: $n" ;;
      *) ok "the start skill's own agent name is bare: $n" ;; esac
  done
  for g in "Bash(hm-spawn *)" "Bash(hm-rotate *)" "Bash(hm-self-rotate *)"; do
    case "$grants" in *"$g"*) bad "the documented run must not grant $g" ;; *) ok "the documented run does not grant $g" ;; esac
  done
else bad "the start skill is at $SKILLS/start/SKILL.md, which the documented grants are checked against"; fi
t_done
