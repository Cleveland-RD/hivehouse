// The hub's screen and guard (hooks/hub.tsx) in the hub's own session. Run with `claude plugin test <plugin folder>`.
// hm-hub itself is stood in for beneath the plugin: its answers are the shapes tests/test_hub.sh pins.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const ROOT = '/work'
const NOW = Date.parse('2026-10-05T12:00:00Z')
const STATUS = {
  hub: { root: ROOT, name: 'hub' },
  projects: [
    {
      name: 'app',
      home: `${ROOT}/back`,
      repos: [
        { folder: 'back', kind: 'repo', branch: 'main', changed: 0 },
        { folder: 'site', kind: 'folder' },
      ],
      orchestrator: { state: 'stopped', question: false, name: 'app-orchestrator', session_id: 'sess-1', context: 51, context_assumed: false },
      agents: [
        { name: 'impl', state: 'stopped', question: false },
        { name: 'rev', state: 'running', question: true },
        // hm-spawn --respawn refuses an agent whose state cannot be told: it is no session Resume brings back
        { name: 'odd', state: 'unknown', question: false },
      ],
      open_tasks: 2,
    },
    { name: 'two', home: `${ROOT}/solo`, repos: [{ folder: 'solo', kind: 'repo', branch: 'main', changed: 3 }], orchestrator: { state: 'none', question: false }, agents: [], open_tasks: 0 },
    {
      name: 'tri',
      home: '/elsewhere/tri',
      repos: [{ folder: '/elsewhere/tri', kind: 'repo', branch: 'main', changed: 0 }],
      orchestrator: { state: 'unregistered', question: false, name: 'tri-orchestrator', pid: 4242, pane: '%9' },
      agents: [],
      open_tasks: 1,
    },
    {
      name: 'four',
      home: `${ROOT}/four`,
      repos: [{ folder: 'four', kind: 'repo', branch: 'main', changed: 0 }],
      orchestrator: { state: 'none', question: false, starting: { pane: '%12', kind: 'start', at: '2026-10-05T11:59:00Z', typed: false, sending: false, question: true, task: 'four-1' } },
      agents: [],
      open_tasks: 1,
    },
    {
      // a start whose line is still on the way: coming up, nothing for the owner to do
      name: 'five',
      home: `${ROOT}/five`,
      repos: [{ folder: 'five', kind: 'repo', branch: 'main', changed: 0 }],
      orchestrator: { state: 'none', question: false, starting: { pane: '%14', kind: 'start', at: '2026-10-05T11:59:50Z', typed: false, sending: true, question: false, task: 'five-1' } },
      agents: [],
      open_tasks: 1,
    },
    {
      // nothing recorded, but a transcript of its conversation: wake resumes it by id
      name: 'six',
      home: `${ROOT}/six`,
      repos: [{ folder: 'six', kind: 'repo', branch: 'main', changed: 0 }],
      orchestrator: { state: 'resumable', question: false, name: 'six-orchestrator', session_id: 'sess-6' },
      agents: [],
      open_tasks: 0,
    },
    {
      // tokens over a window that is only assumed: no percent
      name: 'seven',
      home: `${ROOT}/seven`,
      repos: [{ folder: 'seven', kind: 'repo', branch: 'main', changed: 0 }],
      orchestrator: { state: 'running', question: false, name: 'seven-orchestrator', context_unknown: true, context_tokens: 300000 },
      agents: [],
      open_tasks: 0,
    },
  ],
}
const PROJECTS = {
  projects: [
    { name: 'app', home: 'back', repos: ['back', 'site'] },
    { name: 'tri', home: '/elsewhere/tri', repos: ['/elsewhere/tri'] },
  ],
}
const TASKS = [
  { id: 'app-1', project: 'app', asked: '2026-10-05T11:00:00Z', state: 'plan', updated: '2026-10-05T11:58:00Z', last_note: null, needs_owner: true },
  { id: 'app-2', project: 'app', asked: '2026-10-05T11:10:00Z', state: 'handed', updated: '2026-10-05T11:20:00Z', last_note: null, needs_owner: false, decisions: [{ at: '2026-10-05T11:30:00Z', reason: 'matches the existing pages' }, { at: '2026-10-04T09:00:00Z', reason: 'decided before you left' }] },
  { id: 'app-3', project: 'app', asked: '2026-10-05T11:15:00Z', state: 'overnight', updated: '2026-10-05T11:30:00Z', last_note: null, needs_owner: false },
  { id: 'app-4', project: 'app', asked: '2026-10-05T11:16:00Z', state: 'cleanup', updated: '2026-10-05T11:31:00Z', last_note: null, needs_owner: false },
]
// What `hm-hub dialog` reads on a screen with a question: a permission dialog on the agent rev's, a menu with no digits on
// the first screen of a start (four), and, for the tests to change, what `hm-hub answer` replies
const FP = 'a'.repeat(40)
const DIALOGS: Record<string, unknown> = {
  'app rev': {
    project: 'app', session: 'rev', pane: '%3', kind: 'numbered', esc: true, cursor: 1, fingerprint: FP,
    text: '──────\n Bash command\n touch made-by-test.txt\n Do you want to proceed?\n ❯ 1. Yes\n   2. Yes, and always allow access to /tmp/work from\n   3. No\n Esc to cancel · Tab to amend',
    options: [
      { n: 1, label: 'Yes', detail: '', offered: true, saves_rule: false },
      { n: 2, label: 'Yes, and always allow access to /tmp/work from', detail: 'this project', offered: true, saves_rule: true },
      { n: 3, label: 'Type something.', detail: '', offered: false, saves_rule: false },
    ],
  },
  four: {
    project: 'four', session: 'four-orchestrator', pane: '%12', kind: 'menu', esc: true, cursor: 1, fingerprint: 'b'.repeat(40),
    text: ' Accessing workspace:\n /tmp/work\n ❯ No, exit\n   Yes, I trust this folder\n Enter to confirm · Esc to cancel',
    options: [
      { n: 1, label: 'No, exit', detail: '', offered: true, saves_rule: false },
      { n: 2, label: 'Yes, I trust this folder', detail: '', offered: true, saves_rule: false },
    ],
  },
}
const AWAY = { on: false, ended: false, since: '2026-10-05T10:00:00Z' }
const ANSWER = { code: 0, stdout: '{"answered":true,"session":"rev","choice":"1","option":"Yes","dialog_gone":true}', stderr: '' }
const TOASTS: string[] = []
const PANE = {
  plugin: 'hivemind',
  component: 'Pane',
  requestId: 'hivemind-hub',
  props: { title: 'Hub', isFocused: true, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 80 }, view: {} },
} as const

// The plugin's skills, whose names Claude Code refuses to a command the plugin registers (it refused /hub for /hivemind:hub)
const SKILLS = ['bubble-review', 'cleanup', 'doc-updater', 'gate', 'handoff', 'hub', 'overnight', 'review-plan', 'start']
const ran = (exitCode: number, stdout: string, stderr = '') => ({ value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false } })

// The hub's folder holds .hivemind-hub/; every other path is itself, except one record that is a link into a project.
// opened: the panes asked for; commands: the names registered, refused as Claude Code refuses them (all of them when
// refuseAll is set).
// shown: whether Claude Code lists the screen as open and shown (its own record of the plugin's panes). session: what
// Claude Code records of this session (hm-hub naming) and how many turns it has had; slash: the slash commands run.
type Session = { turns: number; naming?: { found: boolean; name: string; source: string; free: string }; namingFails?: string }
function world(on: On, runs: string[][], opened: string[] = [], commands: string[] = [], refuseAll = false, shown = { now: true },
  session: Session = { turns: 3 }, slash: string[][] = []) {
  on('session.turns', async () => ({ value: session.turns }))
  on('session.id', async () => ({ value: 'sess-hub' }))
  on('command.run', async (_$, e) => {
    slash.push([e.command, e.args ?? ''])
    return { text: '' } as never
  })
  on('session.cwd', async () => ({ value: ROOT }))
  on('fs.stat', async (_$, e) => {
    if (e.path === `${ROOT}/.hivemind-hub`) return { value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, realPath: e.path } }
    if (e.path === `${ROOT}/.hivemind-hub/memory/link.md`) return { value: { kind: 'file', size: 0, mtimeMs: 0, isLink: true, realPath: `${ROOT}/back/src/a.ts` } }
    if (e.path.endsWith('/new.md')) return { deny: 'ENOENT: no such file or directory' }
    return { value: { kind: 'file', size: 0, mtimeMs: 0, isLink: false, realPath: e.path } }
  })
  on('fs.read', async (_$, e) => (e.path === `${ROOT}/.hivemind-hub/projects.json` ? { value: JSON.stringify(PROJECTS) } : { deny: 'ENOENT' }))
  on('process.run', async (_$, e) => {
    runs.push([...e.argv])
    const sub = e.argv[1]
    if (sub === 'status') {
      const hub = AWAY.on ? { ...STATUS.hub, away: { until: NOW / 1000 + 5 * 3600, since: AWAY.since } } : AWAY.ended ? { ...STATUS.hub, last_away: { since: AWAY.since, until: NOW / 1000 - 3600 } } : STATUS.hub
      return ran(0, JSON.stringify({ ...STATUS, hub }))
    }
    if (sub === 'tasks') return ran(0, JSON.stringify(TASKS))
    if (sub === 'wake' || sub === 'continue') return ran(0, '%7\n')
    if (sub === 'dialog') {
      const d = DIALOGS[e.argv.slice(2).join(' ')]
      return d ? ran(0, JSON.stringify(d)) : ran(4, '', 'hivemind: no dialog is on that screen')
    }
    if (sub === 'answer') return ran(ANSWER.code, ANSWER.stdout, ANSWER.stderr)
    if (sub === 'naming' && session.namingFails) return ran(4, '', session.namingFails)
    if (sub === 'naming' && session.naming) return ran(0, JSON.stringify(session.naming))
    return ran(64, '', 'hivemind: usage')
  })
  on('tool.call', async () => ({ result: 'ran' }) as never)
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  on('command.register', async (_$, e) => {
    if (refuseAll || SKILLS.includes(e.name)) return { deny: `"/${e.name}" refused: it is the plugin's /hivemind:${e.name}` }
    commands.push(e.name)
    return { value: { command: e.name } }
  })
  on('ui.open', async (_$, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.panes', async () => ({ value: shown.now ? [{ id: 'hivemind-hub', title: 'Hub', isShown: true, isFocused: false, isPlaced: true }] : [] }))
  on('ui.toast', async (_$, e) => {
    TOASTS.push(e.text)
    return { value: undefined }
  })
}

test('the hub keeps off the projects, and off nothing else', async ($, on) => {
  const runs: string[][] = []
  world(on, runs)
  const edit = (file_path: string) => $.tool.call({ tool: 'Edit', tool_use_id: 't', file_path, old_string: 'a', new_string: 'b' } as never)
  expect((await edit(`${ROOT}/back/src/a.ts`)).deny).toContain('the hub never changes a project')
  expect((await edit(`${ROOT}/.hivemind-hub/memory/app.md`)).deny).toBeUndefined()
  expect((await edit(`${ROOT}/.hivemind-hub/memory/link.md`)).deny).toContain('the hub never changes a project')
  const write = (file_path: string) => $.tool.call({ tool: 'Write', tool_use_id: 't', file_path, content: 'x' } as never)
  expect((await write(`${ROOT}/.hivemind-hub/memory/new.md`)).deny).toBeUndefined()
  expect((await write(`${ROOT}/back/new.md`)).deny).toContain('the hub never changes a project')
  // anything else in the work folder, and a project's folder outside it
  expect((await write(`${ROOT}/notes.txt`)).deny).toContain('the hub never changes a project')
  expect((await write('/elsewhere/tri/a.ts')).deny).toContain('the hub never changes a project')
  // Claude Code's own memory and plans, and scratch files, are the session's, not a project's
  expect((await write('/home/u/.claude/projects/-work/memory/MEMORY.md')).deny).toBeUndefined()
  expect((await write('/tmp/scratch/notes.md')).deny).toBeUndefined()
  const nb = (notebook_path: string) => $.tool.call({ tool: 'NotebookEdit', tool_use_id: 't', notebook_path, new_source: 'x' } as never)
  expect((await nb(`${ROOT}/back/n.ipynb`)).deny).toContain('the hub never changes a project')
  const bash = (command: string) => $.tool.call({ tool: 'Bash', tool_use_id: 't', command } as never)
  expect((await bash('git -C back commit -m x')).deny).toContain('changes a repository')
  expect((await bash('cd back && git push origin main')).deny).toContain('changes a repository')
  expect((await bash('git -C back status --short')).deny).toBeUndefined()
  expect((await bash('hm-hub status')).deny).toBeUndefined()
  // the owner's own words, carried word for word, are never read as a command
  expect((await bash("hm-hub task app <<'EOF'\nafter git pull on main, fix the totals\ngit push when done\nEOF")).deny).toBeUndefined()
  expect((await bash('hm-hub log app-1 done --note "landed, git push done"')).deny).toBeUndefined()
  expect((await bash("hm-hub log app-1 note --note 'run git commit -m x first'")).deny).toBeUndefined()
  expect((await bash("hm-hub task app <<'EOF'\nx\nEOF\ngit push origin main")).deny).toContain('changes a repository')
  // git worktree changes a repository only with add, remove, move, prune, repair, lock or unlock
  expect((await bash('git -C back worktree list')).deny).toBeUndefined()
  expect((await bash('git worktree list --porcelain')).deny).toBeUndefined()
  for (const sub of ['add ../wt -b x', 'remove ../wt', 'move a b', 'prune', 'repair', 'lock ../wt', 'unlock ../wt']) {
    expect((await bash(`git -C back worktree ${sub}`)).deny, `worktree ${sub}`).toContain('changes a repository')
  }
  // quoted text follows the shell's own quoting: the '\'' idiom for an apostrophe inside single quotes, $'..' with an escaped quote, an escaped
  // quote inside double quotes. A sed -i on the hub's own memory file whose note holds a git command passes.
  expect((await bash("sed -i '' '1a\\ do'\\''nt run `git worktree add` here' .hivemind-hub/memory/app.md")).deny).toBeUndefined()
  expect((await bash("hm-hub log app-1 note --note $'it\\'s fine: git commit -m x'")).deny).toBeUndefined()
  expect((await bash('hm-hub log app-1 note --note "say \\"hi\\" then git push"')).deny).toBeUndefined()
  expect((await bash('hm-hub log app-1 note --note "the user\'s note: git worktree add x"')).deny).toBeUndefined()
  expect((await bash("sed -i '' '1a\\ it'\\''s done' .hivemind-hub/memory/app.md; git commit -m x")).deny).toContain('changes a repository')
  // a real command after a quote, in $( ), in backticks, or after an escaped separator still counts
  expect((await bash("echo 'a'; git commit -m x")).deny).toContain('changes a repository')
  // inside double quotes and an unquoted heredoc the shell still runs $( ) and backtick spans; single quotes and a quoted heredoc never
  expect((await bash('echo "$(git commit -m x)"')).deny).toContain('changes a repository')
  expect((await bash('echo "`git push`"')).deny).toContain('changes a repository')
  expect((await bash('echo "say $(echo \\"hi\\") and $(git push)"')).deny).toContain('changes a repository')
  expect((await bash('hm-hub task app <<EOF\nnote\n$(git push)\nEOF')).deny).toContain('changes a repository')
  expect((await bash('hm-hub task app <<EOF\nnote: git push later\nEOF')).deny).toBeUndefined()
  expect((await bash("hm-hub task app <<'EOF'\nnote\n$(git push)\nEOF")).deny).toBeUndefined()
  expect((await bash('hm-hub task app <<"EOF"\nnote\n`git push`\nEOF')).deny).toBeUndefined()
  expect((await bash("echo '$(git push)'")).deny).toBeUndefined()
  expect((await bash('echo "$(echo hi)"')).deny).toBeUndefined()
  expect((await bash('echo $(git commit -m x)')).deny).toContain('changes a repository')
  expect((await bash('echo `git push`')).deny).toContain('changes a repository')
  expect((await bash("echo it\\'s; git commit -m x")).deny).toContain('changes a repository')
  expect((await bash("echo 'unterminated; git commit -m x")).deny).toBeUndefined()
})

test('the guard reads quotes inside $( ) and here-strings and partly quoted heredoc words as the shell does', async ($, on) => {
  world(on, [])
  const bash = (command: string) => $.tool.call({ tool: 'Bash', tool_use_id: 't', command } as never)
  const refused = async (why: string, command: string) => expect((await bash(command)).deny, why).toContain('changes a repository')
  const passes = async (why: string, command: string) => expect((await bash(command)).deny, why).toBeUndefined()
  // a ) or a quote or a backtick inside quotes within $( ) does not end the span: the shell still runs the git push
  await refused('a ) in single quotes inside $( )', `echo "$(printf ')' ; git push)"`)
  await refused('a ) in double quotes inside $( )', `echo "$(printf ")" ; git push)"`)
  await refused('a ) in backticks inside $( )', 'echo "$(printf `echo )` ; git push)"')
  await refused('an escaped ) inside $( )', 'echo "$(printf \\) ; git push)"')
  await refused('a " inside single quotes inside $( )', `echo "$(printf '"' ; git push)"`)
  await refused('a backtick inside single quotes inside $( )', "echo \"$(printf '`' ; git push)\"")
  await refused('the same unquoted', `echo $(printf ')' ; git push)`)
  await refused('a nested $( ) with its own quotes', 'echo "$(echo "$(printf \')\' ; git push)")"')
  await passes('a ) in quotes inside $( ), and no git write', `echo "$(printf ')' ; echo done)"`)
  await refused('a $( ) with its own quotes and a ) inside double quotes inside $( ), then a real git push', `echo "$(echo "$(printf "%s)" a)" ; git push)"`)
  // the span ends at the right paren, so the words after it in the outer quotes are text, not a command
  await passes('a ) in double quotes inside $( ), then git push as plain quoted text', `echo "$(printf ")" ; echo x) git push"`)
  await passes('a ) in backticks inside $( ), then git push as plain quoted text', 'echo "$(printf `echo )` ; echo x) git push"')
  await passes('a $( ) inside double quotes inside $( ), then git push as plain quoted text', `echo "$(echo "$(echo a)" ; echo b) git push"`)
  await passes('a $( ) with its own quotes inside double quotes inside $( ), then git push as quoted text', `echo "$(echo "$(printf "%s)" a)" ; echo b) git push"`)
  await passes('a git push only in a quoted string inside $( )', `echo "$(echo 'git push')"`)
  // a heredoc starts only where the shell would start one: not in arithmetic, not in quotes, and its delimiter starts with a letter,
  // an underscore, a quote or a backslash; a quoted delimiter is the whole quoted string, spaces included
  await refused('<< in $(( )) is a shift', 'echo $((1<<2))\ngit push')
  await refused('<< in an assignment of $(( )) is a shift', 'x=$((a<<b))\ngit commit -m y')
  await refused('<< in a (( )) command is a shift', '(( x<<y ))\ngit push')
  await refused('an opener in double quotes is text', 'echo "x <<EOF y"\ngit push')
  await refused('an opener in single quotes is text', "echo 'x <<EOF y'\ngit push")
  await refused('an opener in $\'..\' is text', "echo $'x <<EOF y'\ngit push")
  await refused('an opener after an escaped quote inside $\'..\' is still text', "echo $'it\\'s <<EOF y'\ngit push")
  await refused('an opener in a quote that began on an earlier line is text', 'echo "a\nb <<EOF y"\ngit push')
  await refused('a delimiter that starts with a digit is no delimiter', 'cat <<2\ngit push')
  await refused('a quoted delimiter with a space, then a command after its end line', 'cat <<"E O F"\nbody\nE O F\ngit push')
  await passes('a quoted delimiter with a space: the body is quoted text', 'cat <<"E O F"\n$(git push)\nE O F')
  await passes('a quoted delimiter with a space: the body, by its end line', 'cat <<"E O F"\nnote: git push later\nE O F')
  await refused('an unquoted opener after a quote closed on the same line is still one', 'echo "a" <<EOF\n$(git push)\nEOF')
  // a here-string is no heredoc: the lines after it are commands
  await refused('a here-string <<<"x" then a command', 'cat <<<"hello"\ngit commit -m y')
  await refused("a here-string <<<'x' then a command", "cat <<<'hello'\ngit commit -m y")
  await passes("a here-string alone", "cat <<<'git push'")
  await passes('a here-string with a git word in it', 'cat <<<"git push later"')
  // a partly quoted delimiter is the whole word, quotes removed, and any quote or backslash makes the body unexpanded
  await refused('<<E"OF": a command after the real EOF line', 'cat <<E"OF"\nbody\nEOF\ngit push')
  await refused("<<E'OF': a command after the real EOF line", "cat <<E'OF'\nbody\nEOF\ngit push")
  await refused('<<"E"OF: a command after the real EOF line', 'cat <<"E"OF\nbody\nEOF\ngit push')
  await passes('<<E"OF": a $( ) in the body is quoted text, not run', 'cat <<E"OF"\n$(git push)\nEOF')
  await passes("<<E\\OF: a backtick in the body is quoted text", 'cat <<E\\OF\n`git push`\nEOF')
  await refused('<<EOF unquoted: a $( ) in the body is run', 'cat <<EOF\n$(git push)\nEOF')
  await passes('<<-EOF with a tab-indented end', 'cat <<-EOF\nnote: git push later\n\tEOF')
})

test('the screen: what needs the owner first, then each project, and Resume wakes a stopped orchestrator', async ($, on) => {
  const runs: string[][] = []
  const opened: string[] = []
  const commands: string[] = []
  const clock = mock.clock(on, { now: NOW })
  mock.env(on, { HOME: '/home' })
  world(on, runs, opened, commands)
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await clock.settle()
  expect(runs.map(r => r[1])).toEqual(expect.arrayContaining(['status', 'tasks']))
  expect(commands).toEqual(['hub-screen'])
  expect(opened).toEqual(['hivemind-hub'])

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: 'NEEDS YOU' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /plan to approve/ })).toBeDefined()
  // a question nobody watches: an agent's, and a start stopped at one
  // (each line is the project or agent in bold, then what it waits for)
  expect(await ui.find({ type: 'Text', text: 'app · rev' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^ +a question on its screen$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /a question on the screen of pane %12/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'APP' })).toBeDefined()
  // an overnight run and a cleanup the hub started are shown on the project's task row, and wait on nobody
  expect(await ui.find({ type: 'Text', text: /1 overnight run · 1 cleanup/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /stopped/ })).toBeDefined()
  // a dialog on an agent's screen: its text, and a button for each option the hub may answer with, Esc where it is offered
  expect(await ui.find({ type: 'Text', text: /Do you want to proceed\?/ })).toBeDefined()
  expect((await ui.find({ key: 'answer-app/rev-1' }))?.text).toContain('1 Yes')
  expect((await ui.find({ key: 'answer-app/rev-2' }))?.text).toContain('(saves a rule)')
  // a wrapped option's second line is shown under the buttons, whole
  expect(await ui.find({ type: 'Text', text: /2\. Yes, and always allow access to \/tmp\/work from this project/ })).toBeDefined()
  expect(await ui.find({ key: 'answer-app/rev-esc' })).toBeDefined()
  // an option that needs the owner's own text has no button: it is answered in the pane
  expect(await ui.find({ key: 'answer-app/rev-3' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /Type something\.: answer it in the pane/ })).toBeDefined()
  // the first dialog of a start: a menu with no digits, and Continue stays beside it
  expect((await ui.find({ key: 'answer-four-2' }))?.text).toContain('Yes, I trust this folder')
  expect(await ui.find({ key: 'continue-four' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /51%/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /no team/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /not registered/ })).toBeDefined()
  // the orchestrator and the one stopped agent come back; an agent that cannot be told about is not counted
  expect((await ui.find({ key: 'resume-app' }))?.text).toContain('Resume · 2 sessions')
  // an orchestrator that ended unregistered but has a transcript: named as such, and Resume is there for it
  expect(await ui.find({ type: 'Text', text: /stopped, not registered/ })).toBeDefined()
  expect((await ui.find({ key: 'resume-six' }))?.text).toContain('Resume · 1 session')
  // tokens over an assumed window: unknown, never a percent
  expect(await ui.find({ type: 'Text', text: /context unknown/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /300000%|30000000%/ })).toBeUndefined()
  expect(await ui.find({ key: 'resume-two' })).toBeUndefined()
  expect(await ui.find({ key: 'resume-tri' })).toBeUndefined()
  // a start still sending its line is coming up: no Continue, nothing waiting on the owner
  expect(await ui.find({ key: 'continue-five' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /coming up/ })).toBeDefined()

  await ui.press({ key: 'resume-app' })
  const wake = runs.find(r => r[1] === 'wake')
  expect(wake?.slice(1)).toEqual(['wake', 'app', '--mode', 'auto'])
  expect(wake?.[0]).toMatch(/\/bin\/hm-hub$/)

  await ui.press({ key: 'resume-six' })
  expect(runs.filter(r => r[1] === 'wake').pop()?.slice(1)).toEqual(['wake', 'six', '--mode', 'auto'])

  await ui.press({ key: 'continue-four' })
  expect(runs.find(r => r[1] === 'continue')?.slice(1)).toEqual(['continue', 'four'])

  // a press answers with the option's number and the fingerprint the screen showed, for that session only
  await ui.press({ key: 'answer-app/rev-1' })
  expect(runs.find(r => r[1] === 'answer')?.slice(1)).toEqual(['answer', 'app', 'rev', '--choice', '1', '--seen', FP])
  expect(TOASTS.some(t => t.includes('answered "Yes"'))).toBe(true)
  await ui.press({ key: 'answer-four-2' })
  expect(runs.filter(r => r[1] === 'answer').pop()?.slice(1)).toEqual(['answer', 'four', '--choice', '2', '--seen', 'b'.repeat(40)])
  await ui.press({ key: 'answer-app/rev-esc' })
  expect(runs.filter(r => r[1] === 'answer').pop()?.slice(1)).toEqual(['answer', 'app', 'rev', '--choice', 'esc', '--seen', FP])

  // a refusal (the screen changed under the owner) is told, and the screen reads hm-hub again
  ANSWER.code = 4
  ANSWER.stdout = ''
  ANSWER.stderr = 'hivemind: the dialog changed; look again: nothing was sent'
  const reads = runs.filter(r => r[1] === 'status').length
  await ui.press({ key: 'answer-app/rev-2' })
  expect(TOASTS.some(t => t.includes('the dialog changed; look again'))).toBe(true)
  expect(runs.filter(r => r[1] === 'status').length).toBeGreaterThan(reads)
  await ui.unmount()
})

test('the screen says relay or away in its header, and lists what the hub decided only while away', async ($, on) => {
  const runs: string[][] = []
  const clock = mock.clock(on, { now: NOW })
  mock.env(on, { HOME: '/home' })
  world(on, runs)
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /relay/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /away until/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'DECIDED WHILE YOU WERE AWAY' })).toBeUndefined()
  await ui.unmount()
  AWAY.on = true
  try {
    await clock.advance(20_000) // the next beat reads the status again
    const away = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await away.find({ type: 'Text', text: /away until \d\d:\d\d/ })).toBeDefined()
    expect(await away.find({ type: 'Text', text: 'DECIDED WHILE YOU WERE AWAY' })).toBeDefined()
    expect(await away.find({ type: 'Text', text: /matches the existing pages/ })).toBeDefined()
    // a decision made before the owner left is not "while away"
    expect(await away.find({ type: 'Text', text: /decided before you left/ })).toBeUndefined()
    await away.unmount()
  } finally {
    AWAY.on = false
  }
  // the owner is back: what was decided stays until they have seen it, and a newer away period starts unseen
  AWAY.ended = true
  try {
    await clock.advance(20_000)
    const back = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await back.find({ type: 'Text', text: /away until/ })).toBeUndefined()
    expect(await back.find({ type: 'Text', text: 'DECIDED WHILE YOU WERE AWAY' })).toBeDefined()
    expect(await back.find({ type: 'Text', text: /matches the existing pages/ })).toBeDefined()
    await back.press({ key: 'seen-away' })
    await clock.advance(20_000)
    expect(await back.find({ type: 'Text', text: 'DECIDED WHILE YOU WERE AWAY' })).toBeUndefined()
    AWAY.since = '2026-10-05T11:00:00Z' // a newer away period (the decision at 11:30 is inside it): unseen again
    await clock.advance(20_000)
    expect(await back.find({ type: 'Text', text: 'DECIDED WHILE YOU WERE AWAY' })).toBeDefined()
    await back.unmount()
  } finally {
    AWAY.ended = false
    AWAY.since = '2026-10-05T10:00:00Z'
  }
})

test('the screen reads hm-hub only while it is open, and once per tick', async ($, on) => {
  const runs: string[][] = []
  const shown = { now: true }
  const clock = mock.clock(on, { now: NOW })
  world(on, runs, [], [], false, shown)
  const reads = () => runs.filter(r => r[1] === 'status').length
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true }) // a second start keeps one poller
  await clock.settle()
  const first = reads()
  await clock.advance(20_000)
  expect(reads()).toBe(first + 1)
  shown.now = false // the owner closed it
  await clock.advance(60_000)
  expect(reads()).toBe(first + 1)
  await $.command.run({ command: 'hub-screen', args: '', origin: 'person' } as never)
  shown.now = true
  await clock.settle()
  const reopened = reads()
  expect(reopened).toBe(first + 2)
  await clock.advance(20_000)
  expect(reads()).toBe(reopened + 1)
})

test('a command Claude Code refuses does not keep the screen shut', async ($, on) => {
  const runs: string[][] = []
  const opened: string[] = []
  const clock = mock.clock(on, { now: NOW })
  world(on, runs, opened, [], true)
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await clock.settle()
  expect(runs.map(r => r[1])).toEqual(expect.arrayContaining(['status', 'tasks']))
  expect(opened).toEqual(['hivemind-hub'])
})

const UNNAMED = { found: true, name: 'Read the docs', source: 'auto', free: 'hub' }

test('a plain claude in the hub folder names itself and opens the hub', async ($, on) => {
  const ran: string[][] = []
  const clock = mock.clock(on, { now: NOW })
  world(on, [], [], [], false, { now: true }, { turns: 0, naming: UNNAMED }, ran)
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await clock.settle()
  expect(ran).toEqual([['rename', 'hub'], ['hivemind:hub', '']])
})

// each test's world is its own: hooks a test registers stay for the rest of that test
const leftAlone = (why: string, session: Session, isInteractive = true) =>
  test(`a session ${why} is left as it is`, async ($, on) => {
    const ran: string[][] = []
    const clock = mock.clock(on, { now: NOW })
    world(on, [], [], [], false, { now: true }, session, ran)
    await $.session.start({ cwd: ROOT, surface: isInteractive ? 'terminal' : null, isInteractive })
    await clock.settle()
    expect(ran).toEqual([])
  })
leftAlone('the owner named', { turns: 0, naming: { ...UNNAMED, name: 'hub', source: 'user' } })
leftAlone('resumed or reloaded (it has had turns)', { turns: 4, naming: UNNAMED })
leftAlone('Claude Code keeps no record of', { turns: 0, naming: { ...UNNAMED, found: false } })
leftAlone('nobody is at the prompt of (claude -p, the SDK)', { turns: 0, naming: UNNAMED }, false)

test('a name the hub cannot take is said on the toast, not dropped', async ($, on) => {
  const ran: string[][] = []
  const clock = mock.clock(on, { now: NOW })
  world(on, [], [], [], false, { now: true }, { turns: 0, namingFails: 'hivemind: /work/.hivemind-hub/name holds no usable name' }, ran)
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await clock.settle()
  expect(ran).toEqual([])
  expect(TOASTS.some(t => t.includes('no name chosen') && t.includes('holds no usable name'))).toBe(true)
})

test('the setting turns the naming off', { options: { hub_auto_start: false } }, async ($, on) => {
  const ran: string[][] = []
  const clock = mock.clock(on, { now: NOW })
  world(on, [], [], [], false, { now: true }, { turns: 0, naming: UNNAMED }, ran)
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await clock.settle()
  expect(ran).toEqual([])
})
