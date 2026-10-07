import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { HubAgent, HubDialog, HubProject, HubTask, HubView } from '../types'

// The owner's hub (bin/hm-hub, skills/hub): in the session started in the hub's own folder, and only there, a screen of
// what waits on the owner and of every project's orchestrator, and a guard that keeps the hub off the projects' files.
// Everything shown is read from hm-hub; the only things done here are the Resume and Continue presses, which run
// `hm-hub wake` and `hm-hub continue`.
const PANE = 'hivemind-hub'
// The command that opens the screen. Never a skill's name: Claude Code refuses a command named as one of the plugin's own
// skills (/hub is the skill, /hivemind:hub), and tests/test_hub_screen.sh holds it to that.
const COMMAND = 'hub-screen'
const EVERY_MS = 20_000
const WAKE_TIMEOUT_MS = 150_000 // hm-hub waits up to 90 s for a started session to be idle
const ANSWER_TIMEOUT_MS = 30_000 // hm-hub answer sends its keys and then watches a few seconds

const EMPTY: HubView = { root: '', hubName: '', projects: [], tasks: [], dialogs: {}, away: null, lastAway: null, updatedAt: 0, error: '' }
const view = atom({ plugin: 'hivemind', key: 'hubView' } as const, EMPTY)
// the project a press is acting on, one at a time
const acting = atom({ plugin: 'hivemind', key: 'hubResuming' } as const, '')
// the start of the away period whose decisions the owner has marked seen (a newer away starts unseen)
const seenAway = atom({ plugin: 'hivemind', key: 'hubSeenAway' } as const, '')

// The session is the hub when its own folder holds .hivemind-hub/ (a folder, not a link): hm-session-hook's rule.
let hubRootOnce: Promise<string | null> | null = null
function hubRoot($: EngineInterface): Promise<string | null> {
  hubRootOnce ??= (async () => {
    try {
      const cwd = await $.session.cwd()
      const st = await $.fs.stat(`${cwd}/.hivemind-hub`)
      return st.kind === 'dir' && !st.isLink ? cwd : null
    } catch {
      return null
    }
  })()
  return hubRootOnce
}

const hmHub = ($: EngineInterface) => `${$.plugin.root}/bin/hm-hub`

async function refresh($: EngineInterface): Promise<void> {
  const root = await hubRoot($)
  if (!root) return
  try {
    const [status, tasks] = await Promise.all([
      $.process.run([hmHub($), 'status', '--json'], { cwd: root, timeoutMs: 30_000 }),
      $.process.run([hmHub($), 'tasks', '--json'], { cwd: root, timeoutMs: 30_000 }),
    ])
    if (status.exitCode !== 0) throw new Error(lastLine(status.stderr) || `hm-hub status exited ${status.exitCode}`)
    const s = JSON.parse(status.stdout) as { hub?: { root?: string; name?: string; away?: { until: number; since?: string }; last_away?: { since: string; until: number } }; projects?: HubProject[] }
    const t = tasks.exitCode === 0 ? (JSON.parse(tasks.stdout) as HubTask[]) : []
    const projects = s.projects ?? []
    const next: HubView = {
      root: s.hub?.root ?? root,
      hubName: s.hub?.name ?? '',
      projects,
      tasks: t,
      dialogs: await readDialogs($, root, projects),
      away: s.hub?.away ?? null,
      lastAway: s.hub?.last_away ?? null,
      updatedAt: await $.clock.now(),
      // the projects still draw when only the ledger could not be read, and the screen says so
      error: tasks.exitCode === 0 ? '' : `tasks not read: ${lastLine(tasks.stderr) || `hm-hub tasks exited ${tasks.exitCode}`}`,
    }
    await update($, view, () => next)
  } catch (err) {
    const error = err instanceof Error ? err.message : String(err)
    await update($, view, v => ({ ...(v ?? EMPTY), error, updatedAt: v?.updatedAt ?? 0 }))
  }
}

// The dialogs on the screens hm-hub reports a question on: each session's text and options, as `hm-hub dialog` reads them
// (the screen's buttons answer with the fingerprint shown here). A dialog hm-hub cannot read is left out: the screen then
// says to answer it in the pane.
async function readDialogs($: EngineInterface, root: string, projects: HubProject[]): Promise<Record<string, HubDialog>> {
  const asks: { key: string; args: string[] }[] = []
  for (const p of projects) {
    const o = p.orchestrator
    if (o?.question || o?.starting?.question) asks.push({ key: p.name, args: ['dialog', p.name] })
    for (const a of (p.agents ?? []).filter(a => a.question)) asks.push({ key: `${p.name}/${a.name}`, args: ['dialog', p.name, a.name] })
  }
  const out: Record<string, HubDialog> = {}
  await Promise.all(
    asks.map(async ask => {
      try {
        const r = await $.process.run([hmHub($), ...ask.args], { cwd: root, timeoutMs: 30_000 })
        if (r.exitCode === 0) out[ask.key] = JSON.parse(r.stdout) as HubDialog
      } catch {
        // unreadable: the screen says to answer it in the pane
      }
    }),
  )
  return out
}

// One poller per module, which reads hm-hub only while the screen is open and shown (Claude Code's own record of this
// plugin's panes, so a pane the owner closed or tabbed away from costs nothing until it is back).
let poller: { cancel: () => void } | null = null
function startPolling($: EngineInterface): void {
  if (poller) return
  poller = $.clock.every(EVERY_MS, () => {
    void tick($)
  })
}
async function tick($: EngineInterface): Promise<void> {
  if ((await $.ui.panes()).some(pane => pane.id === PANE && pane.isShown)) await refresh($)
}

function lastLine(text: string): string {
  return (text.trim().split('\n').pop() ?? '').replace(/^hivemind: /, '')
}

// A press is the owner's own word for that one action: Resume wakes a stopped orchestrator (hm-hub wake), Continue sends
// a started one its first line once the owner has answered the question on its screen (hm-hub continue).
async function act($: EngineInterface, project: string, args: string[], done: string): Promise<void> {
  const root = await hubRoot($)
  if (!root || (await read($, acting))) return
  await update($, acting, () => project)
  try {
    const r = await $.process.run([hmHub($), ...args], { cwd: root, timeoutMs: WAKE_TIMEOUT_MS })
    $.ui.toast(r.exitCode === 0 ? `${project}: ${done} (pane ${r.stdout.trim()})` : `${project}: ${lastLine(r.stderr)}`)
  } finally {
    await update($, acting, () => '')
    await refresh($)
  }
}

// A press on a dialog's option is the owner's own word for that one answer: hm-hub answer checks the screen is still the one
// shown (its fingerprint) and sends the one key. A refusal (the dialog changed) is told, and the screen reads again.
async function answerDialog($: EngineInterface, project: string, agent: string, choice: string, seen: string): Promise<void> {
  const root = await hubRoot($)
  if (!root || (await read($, acting))) return
  const who = agent ? `${project} · ${agent}` : project
  await update($, acting, () => (agent ? `${project}/${agent}` : project))
  try {
    const r = await $.process.run([hmHub($), 'answer', project, ...(agent ? [agent] : []), '--choice', choice, '--seen', seen], { cwd: root, timeoutMs: ANSWER_TIMEOUT_MS })
    if (r.exitCode === 0) {
      let option = choice
      let gone = true
      try {
        const a = JSON.parse(r.stdout) as { option?: string; dialog_gone?: boolean }
        option = a.option ?? choice
        gone = a.dialog_gone !== false
      } catch {
        // the key was sent; only its words are unknown
      }
      $.ui.toast(`${who}: answered "${option}"${gone ? '' : ' (the dialog is still on its screen)'}`)
    } else $.ui.toast(`${who}: ${lastLine(r.stderr)}`)
  } finally {
    await update($, acting, () => '')
    await refresh($)
  }
}

// A plain claude in the hub's folder becomes the hub: named (orchestrators reply to the hub by name, and Claude Code lets
// only a slash command name a session) and greeted. Only a fresh session Claude Code records as unnamed: a name the owner
// gave is theirs, a resumed or reloaded session has had turns, and a session with no record, or with nobody at its prompt
// (`claude -p`, the SDK), is left as it is.
// The name this hub's folder starts from (`hm-hub name`, default hub): the one the owner is told to /rename to.
async function chosenName($: EngineInterface, root: string): Promise<string> {
  try {
    const r = await $.process.run([hmHub($), 'name'], { cwd: root, timeoutMs: 10_000 })
    const n = r.stdout.trim()
    return r.exitCode === 0 && n ? n : 'hub'
  } catch {
    return 'hub'
  }
}

async function nameAndGreet($: EngineInterface, root: string): Promise<void> {
  try {
    if ((await $.session.turns()) > 0) return
    const r = await $.process.run([hmHub($), 'naming', '--session', await $.session.id()], { cwd: root, timeoutMs: 30_000 })
    if (r.exitCode !== 0) {
      $.ui.toast(`hub: no name chosen (${lastLine(r.stderr) || `hm-hub naming exited ${r.exitCode}`}); type /rename ${await chosenName($, root)}`)
      return
    }
    const n = JSON.parse(r.stdout) as { found?: boolean; source?: string; free?: string }
    if (!n.found || n.source === 'user' || !n.free) return
    await $.command.run({ command: 'rename', args: n.free })
    await $.command.run({ command: 'hivemind:hub' })
  } catch (err) {
    $.ui.toast(`hub: this session could not name itself (${err instanceof Error ? err.message : String(err)}); type /rename ${await chosenName($, root)}`)
  }
}

// ---- the guard ------------------------------------------------------------------------------------------------------
// The hub changes no project: in the hub's session an edit inside its work folder (apart from its own records) or inside
// any project's folder is refused. A path is judged by where it really is (links and `..` resolved); a file that does
// not exist yet, by its folder. Everything else (Claude Code's own memory and plans, scratch files) is the session's.
async function realPath($: EngineInterface, path: string): Promise<string | null> {
  try {
    return (await $.fs.stat(path, { resolve: true })).realPath ?? null
  } catch {
    const cut = path.lastIndexOf('/')
    if (cut <= 0) return null
    const dir = await realPath($, path.slice(0, cut))
    return dir === null ? null : `${dir}/${path.slice(cut + 1)}`
  }
}

async function projectFolders($: EngineInterface, root: string): Promise<string[]> {
  try {
    const text = await $.fs.read(`${root}/.hivemind-hub/projects.json`)
    const list = (JSON.parse(typeof text === 'string' ? text : '{}') as { projects?: { home?: string; repos?: string[] }[] }).projects ?? []
    return list.flatMap(p => [p.home ?? '', ...(p.repos ?? [])]).filter(f => f !== '').map(f => (f.startsWith('/') ? f : `${root}/${f}`))
  } catch {
    return []
  }
}

const inside = (path: string, dir: string | null) => dir !== null && (path === dir || path.startsWith(`${dir}/`))

const KEEP_OFF = 'the hub never changes a project: hand this to the project\'s orchestrator'

// Why an edit of this path is refused in the hub, or null when it may go on.
async function editRefusal($: EngineInterface, path: string): Promise<string | null> {
  const root = await hubRoot($)
  if (!root) return null
  const abs = path.startsWith('/') ? path : `${root}/${path}`
  const real = (await realPath($, abs)) ?? abs
  if (inside(real, await realPath($, `${root}/.hivemind-hub`))) return null
  const folders = await Promise.all([root, ...(await projectFolders($, root))].map(f => realPath($, f)))
  return folders.some(f => inside(real, f)) ? `${KEEP_OFF} (${path})` : null
}

// git commands that change a repository; read-only ones (status, log, diff, show) pass. Best effort: a shell can always
// spell a command another way, which is why the skill says so too.
const GIT_WRITES =
  /(^|[;&|(`]|\s)git(\s+-C\s+\S+)?\s+(commit|push|merge|rebase|reset|checkout|switch|restore|stash|cherry-pick|revert|tag|am|apply|clean|rm|mv|add|worktree\s+(?:add|remove|move|prune|repair|lock|unlock)|pull|branch\s+-[dDmMf])\b/

// A command with the words it only carries taken out: a quoted string or a heredoc body is the owner's text, passed word for
// word (a task, a note), never a command the shell runs. What the shell does run inside text it otherwise leaves alone: single
// quotes and $'...' never; double quotes and an unquoted heredoc (<<EOF) only their $(...) and backtick spans, which are kept
// for the match; a quoted heredoc (<<'EOF', <<"EOF", <<\EOF, <<E"OF": a quote or backslash anywhere in the delimiter word makes
// it quoted, and the delimiter is the whole word with them removed) not at all. A here-string (<<<) is no heredoc. Quoting
// follows the shell's own: '...' has no escapes (an apostrophe inside it is written '\'' : close, escaped apostrophe, open),
// "..." and $'...' take a backslash escape, and a backslash outside quotes escapes the next character, so an escaped quote
// opens nothing. A quote that never closes holds the rest. A heredoc opens only in unquoted command text, outside $(( )) and (( ))
// arithmetic, and its delimiter starts with a letter, an underscore, a quote or a backslash; when unsure, the lines after it are read as commands. Inside $( ) the same rules decide where the span ends: a ) in quotes,
// backticks or after a backslash is no closing paren.

// Where a quoted span that opened just before text[j] ends (just past its closing mark), or the end of the text. In "..." a
// backslash escapes the next character and a $(...) or backtick span is the shell's own, so its quotes are not this span's.
function skipSingle(text: string, j: number): number {
  const k = text.indexOf("'", j)
  return k < 0 ? text.length : k + 1
}
function skipAnsi(text: string, j: number): number {
  while (j < text.length && text.charAt(j) !== "'") j += text.charAt(j) === '\\' ? 2 : 1
  return Math.min(j + 1, text.length)
}
function skipBacktick(text: string, j: number): number {
  while (j < text.length && text.charAt(j) !== '`') j += text.charAt(j) === '\\' ? 2 : 1
  return Math.min(j + 1, text.length)
}
function skipDouble(text: string, j: number): number {
  while (j < text.length && text.charAt(j) !== '"') {
    const c = text.charAt(j)
    if (c === '\\') j += 2
    else if (c === '`') j = skipBacktick(text, j + 1)
    else if (c === '$' && text.charAt(j + 1) === '(') {
      const k = closeParen(text, j + 2)
      j = k < 0 ? text.length : k + 1
    } else j++
  }
  return Math.min(j + 1, text.length)
}
// The position of the ) that closes a $( whose body starts at text[from], or -1: parens count only outside quotes and escapes.
function closeParen(text: string, from: number): number {
  let depth = 1
  for (let j = from; j < text.length; ) {
    const c = text.charAt(j)
    if (c === '\\') j += 2
    else if (c === "'") j = skipSingle(text, j + 1)
    else if (c === '$' && text.charAt(j + 1) === "'") j = skipAnsi(text, j + 2)
    else if (c === '"') j = skipDouble(text, j + 1)
    else if (c === '`') j = skipBacktick(text, j + 1)
    else {
      if (c === '(') depth++
      else if (c === ')' && --depth === 0) return j
      j++
    }
  }
  return -1
}

// The $(...) or `...` span that starts at text[i], as the shell would run it, and where it ends; null when none starts there.
function expansionAt(text: string, i: number): [string, number] | null {
  if (text.charAt(i) === '$' && text.charAt(i + 1) === '(') {
    const k = closeParen(text, i + 2)
    const end = k < 0 ? text.length : k
    return [`$(${commandsOnly(text.slice(i + 2, end))}) `, k < 0 ? text.length : k + 1]
  }
  if (text.charAt(i) === '`') {
    let j = i + 1
    while (j < text.length && text.charAt(j) !== '`') j += text.charAt(j) === '\\' ? 2 : 1
    return [`\`${commandsOnly(text.slice(i + 1, j))}\` `, j + 1]
  }
  return null
}

// Only the spans of text that the shell runs although it is quoted text: what an unquoted heredoc's body carries.
function expansionsOf(text: string): string {
  let out = ''
  for (let i = 0; i < text.length; ) {
    if (text.charAt(i) === '\\') i += 2
    else {
      const span = expansionAt(text, i)
      if (span) {
        out += span[0]
        i = span[1]
      } else i++
    }
  }
  return out
}

// The delimiter word that starts at line[k], as the shell reads it: it starts with a letter, an underscore, a quote or a backslash;
// quoted strings are taken whole (spaces included) and a backslash takes the next character; an unquoted word ends at a space or
// one of ; & | < > ( ). null when it is none (a heredoc is then not assumed: the lines after it are read as commands).
function delimiterAt(line: string, k: number): { word: string; quoted: boolean; end: number } | null {
  if (!/[A-Za-z_'"\\]/.test(line.charAt(k))) return null
  let word = ''
  let quoted = false
  let i = k
  while (i < line.length && !/[\s;&|<>()]/.test(line.charAt(i))) {
    const c = line.charAt(i)
    if (c === '\\') {
      if (i + 1 >= line.length) return null
      word += line.charAt(i + 1)
      quoted = true
      i += 2
    } else if (c === "'" || c === '"') {
      let j = i + 1
      let part = ''
      while (j < line.length && line.charAt(j) !== c) {
        if (c === '"' && line.charAt(j) === '\\' && j + 1 < line.length) j++
        part += line.charAt(j)
        j++
      }
      if (j >= line.length) return null
      word += part
      quoted = true
      i = j + 1
    } else {
      word += c
      i++
    }
  }
  return { word, quoted, end: i }
}

// Where a heredoc opens on this line, if one does, and the quote still open at its end (a quote can run over several lines). Only
// unquoted command text counts: not text in quotes, not << inside $(( )) or (( )) arithmetic (a shift), not a here-string (<<<).
function openerIn(line: string, open: string): { opens: { word: string; quoted: boolean } | null; open: string } {
  let q = open
  for (let i = 0; i < line.length; i++) {
    const c = line.charAt(i)
    if (q === "'") {
      if (c === "'") q = ''
    } else if (q === 'a') {
      if (c === '\\') i++
      else if (c === "'") q = ''
    } else if (q === '"') {
      if (c === '\\') i++
      else if (c === '"') q = ''
    } else if (c === '\\') i++
    else if (c === "'") q = "'"
    else if (c === '"') q = '"'
    else if (c === '$' && line.charAt(i + 1) === "'") {
      q = 'a'
      i++
    } else if ((c === '$' && line.startsWith('((', i + 1)) || (c === '(' && line.charAt(i + 1) === '(')) {
      const k = line.indexOf('))', i + 2)
      if (k < 0) return { opens: null, open: q }
      i = k + 1
    } else if (c === '#' && (i === 0 || /[\s;&|()]/.test(line.charAt(i - 1)))) {
      return { opens: null, open: '' }   // a # that starts a word is a comment: it runs to the end of the line and holds no opener
    } else if (c === '<' && line.charAt(i + 1) === '<') {
      // a here-string (<<<) is no heredoc: its third < is no delimiter, and the pair is skipped
      let k = i + 2
      if (line.charAt(k) === '-') k++
      while (line.charAt(k) === ' ' || line.charAt(k) === '\t') k++
      const d = delimiterAt(line, k)
      if (d) return { opens: { word: d.word, quoted: d.quoted }, open: '' }
      i++
    }
  }
  return { opens: null, open: q }
}

function commandsOnly(command: string): string {
  const kept: string[] = []
  let ran = ''
  let until: string | null = null
  let unquoted = false
  let open = ''
  for (const line of command.split('\n')) {
    if (until !== null) {
      if (line.trim() === until) until = null
      else if (unquoted) ran += expansionsOf(line) + '\n'
      continue
    }
    const r = openerIn(line, open)
    open = r.open
    if (r.opens) {
      until = r.opens.word
      unquoted = !r.opens.quoted
    }
    kept.push(line)
  }
  const text = kept.join('\n')
  let out = ''
  for (let i = 0; i < text.length; i++) {
    const c = text.charAt(i)
    if (c === '\\') {
      out += text.charAt(i + 1)
      i++
    } else if (c === "'" || c === '"' || (c === '$' && text.charAt(i + 1) === "'")) {
      const ansi = c === '$'
      const quote = ansi ? "'" : c
      let run = ''
      i += ansi ? 2 : 1
      while (i < text.length && text.charAt(i) !== quote) {
        const span = quote === '"' ? expansionAt(text, i) : null
        if (span) {
          run += span[0]
          i = span[1]
        } else i += text.charAt(i) === '\\' && (ansi || quote === '"') ? 2 : 1
      }
      out += ansi ? "$''" : quote + run + quote
    } else out += c
  }
  return out + '\n' + ran
}

export const register: Register = (on, options) => {
  // the mode orchestrators run in, as the hub's own sessions do: cross-session messages wait for approval across modes
  const mode = typeof options.permission_mode_local === 'string' ? options.permission_mode_local : ''
  // the level at which hivemind rotates a session: a level at or above it is drawn as a warning
  const rotateAt = typeof options.rotate_at_percent === 'number' ? options.rotate_at_percent : 50
  const autoStart = options.hub_auto_start !== false

  // A guard that fails lets the call go on (its .catch): it is best effort, and a broken guard must not stop the work.
  on('tool.call', { tool: 'Edit' }, async ($, e, next) => {
    const deny = await editRefusal($, e.file_path)
    return deny ? { deny } : next(e)
  }).catch(($, e, next) => next(e))
  on('tool.call', { tool: 'Write' }, async ($, e, next) => {
    const deny = await editRefusal($, e.file_path)
    return deny ? { deny } : next(e)
  }).catch(($, e, next) => next(e))
  on('tool.call', { tool: 'NotebookEdit' }, async ($, e, next) => {
    const deny = await editRefusal($, e.notebook_path)
    return deny ? { deny } : next(e)
  }).catch(($, e, next) => next(e))
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const root = await hubRoot($)
    if (!root || !GIT_WRITES.test(commandsOnly(e.command))) return next(e)
    return { deny: `${KEEP_OFF} (a git command that changes a repository)` }
  }).catch(($, e, next) => next(e))

  // ---- the screen ---------------------------------------------------------------------------------------------------
  on('session.start', async ($, e, next) => {
    const root = await hubRoot($)
    if (root) {
      // queued: a slash command runs once the session is idle, after this start
      if (autoStart && e.isInteractive) void nameAndGreet($, root)
      // a refused command must not keep the screen shut: it opens anyway, and says why the command is missing
      try {
        await $.command.register({ name: COMMAND, description: 'Show the hub: what waits on you, and every project' })
      } catch (err) {
        $.ui.toast(`hub screen: /${COMMAND} is not available (${err instanceof Error ? err.message : String(err)})`)
      }
      void refresh($)
      startPolling($)
      void $.ui.open({ id: PANE, title: 'Hub' })
    }
    return next(e)
  })

  on('command.run', { command: COMMAND }, async $ => {
    void refresh($)
    startPolling($)
    await $.ui.open({ id: PANE, title: 'Hub' })
    return { text: 'Hub screen opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const v = { ...EMPTY, ...((await read($, view)) ?? {}) } // a hot reload can hand back an older shape
    const busy = (await read($, acting)) ?? ''
    const now = await $.clock.now()
    const body = Math.max(36, e.props.bodyColumns ?? 60)
    const inner = body - 2
    const home = (await $.env.get('HOME')) ?? ''
    const where = home && v.root.startsWith(home) ? `~${v.root.slice(home.length)}` : v.root
    const rule = <Text color="gray">{'─'.repeat(inner)}</Text>
    const resumeArgs = (p: string) => ['wake', p, ...(mode ? ['--mode', mode] : [])]

    // What waits on the owner: tasks hm-hub marks so, and questions on screens nobody watches.
    type Need = { key: string; glyph: string; color: string; who: string; words: string; when: string; action?: JSX.Element; dialog?: JSX.Element | null }
    // A dialog's text, and one button per option the hub may answer with. An option that needs the owner's own text, and a
    // dialog hm-hub could not read, are answered in the pane.
    const dialogBlock = (key: string, project: string, agent: string): JSX.Element | null => {
      const d = v.dialogs[key]
      if (!d) return null
      const lines = d.text.split('\n').filter(l => !/^[\s─╌]*$/.test(l)).slice(-14)
      const offered = d.options.filter(o => o.offered)
      const answer = (choice: string) => () => void answerDialog($, project, agent, choice, d.fingerprint)
      return (
        <Box flexDirection="column" paddingLeft={3}>
          {lines.map((l, i) => (
            <Text key={`dl-${key}-${i}`} color="gray" wrap="truncate-end">
              {l}
            </Text>
          ))}
          {offered.length > 0 || d.esc ? (
            <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
              {offered.map(o => (
                <Button key={`answer-${key}-${o.n}`} onPress={answer(String(o.n))}>
                  {`${o.n} ${o.label}${o.saves_rule ? ' (saves a rule)' : ''}`}
                </Button>
              ))}
              {d.esc ? (
                <Button key={`answer-${key}-esc`} onPress={answer('esc')}>
                  Esc
                </Button>
              ) : null}
            </Box>
          ) : null}
          {offered
            .filter(o => o.detail !== '')
            .map(o => (
              <Text key={`dd-${key}-${o.n}`} color="gray" wrap="truncate-end">
                {`${o.n}. ${o.label} ${o.detail}`}
              </Text>
            ))}
          {d.options.some(o => !o.offered) || offered.length === 0 ? (
            <Text color="yellow">
              {d.options.length === 0 ? 'answer it in the pane' : `${d.options.filter(o => !o.offered).map(o => o.label).join(', ') || 'this dialog'}: answer it in the pane`}
            </Text>
          ) : null}
        </Box>
      )
    }
    const needs: Need[] = []
    if (v.updatedAt && !v.hubName) {
      needs.push({ key: 'hub', glyph: '!', color: 'red', who: 'hub', words: 'has not recorded its session, so nobody can reply to it', when: '' })
    }
    for (const t of v.tasks.filter(t => t.needs_owner)) {
      const w = waitLook(t.state)
      needs.push({ key: t.id, glyph: w.glyph, color: w.color, who: t.id, words: w.words, when: ago(t.updated, now) })
    }
    for (const p of v.projects) {
      const o = p.orchestrator ?? { state: 'none' }
      if (o.question) needs.push({ key: `q-${p.name}`, glyph: '?', color: 'yellow', who: p.name, words: 'its orchestrator has a question on its screen', when: '', dialog: dialogBlock(p.name, p.name, '') })
      for (const a of (p.agents ?? []).filter(a => a.question)) {
        needs.push({ key: `q-${p.name}-${a.name}`, glyph: '?', color: 'yellow', who: `${p.name} · ${a.name}`, words: 'a question on its screen', when: '', dialog: dialogBlock(`${p.name}/${a.name}`, p.name, a.name) })
      }
      const s = o.starting
      if (s && !s.typed && !s.sending) {
        needs.push({
          key: `s-${p.name}`,
          glyph: '?',
          color: 'yellow',
          who: p.name,
          words: s.question ? `a question on the screen of pane ${s.pane}: answer it, then Continue` : `waiting in pane ${s.pane} for its first line`,
          when: ago(s.at, now),
          dialog: s.question ? dialogBlock(p.name, p.name, '') : null,
          action:
            busy === p.name ? (
              <Text color="cyan">continuing…</Text>
            ) : (
              <Button key={`continue-${p.name}`} onPress={() => void act($, p.name, ['continue', p.name], 'its first line was sent')}>
                Continue
              </Button>
            ),
        })
      }
    }

    // what the hub decided for the owner since they left, newest first
    // while away, and after it until the owner marks them seen (a newer away period starts unseen)
    const awaySince = v.away?.since ?? v.lastAway?.since ?? ''
    const seen = (await read($, seenAway)) ?? ''
    const showDecided = Boolean(v.away) || (Boolean(v.lastAway) && awaySince !== seen)
    const decided = (v.tasks ?? [])
      .flatMap(t => (t.decisions ?? []).map(d => ({ id: t.id, ...d })))
      .filter(d => !awaySince || d.at >= awaySince)
      .sort((a, b) => (a.at < b.at ? 1 : -1))
      .slice(0, 8)

    const row = (label: string, ...lines: JSX.Element[]) => (
      <Box flexDirection="row" paddingLeft={1}>
        <Box width={14} flexShrink={0}>
          <Text color="gray">{label}</Text>
        </Box>
        <Box flexDirection="column" flexShrink={1}>
          {lines}
        </Box>
      </Box>
    )

    const card = (p: HubProject) => {
      const look = orchestratorLook(p)
      const o = p.orchestrator ?? { state: 'none' }
      const agents = p.agents ?? []
      const up = agents.filter(a => a.state === 'running').length
      const away = agents.filter(a => a.state !== 'running')
      // what Resume brings back: the orchestrator, and each agent hm-spawn --respawn takes (one proven stopped)
      const back = 1 + agents.filter(a => a.state === 'stopped').length
      const doneToday = v.tasks.filter(t => t.project === p.name && t.state === 'done' && sameDay(t.updated, now)).length
      // a task the hub sent into an overnight run or a cleanup stays open and waits on nobody: say it is running
      const inState = (s: string) => v.tasks.filter(t => t.project === p.name && t.state === s).length
      const nightly = inState('overnight')
      const cleaning = inState('cleanup')
      const canResume = (o.state === 'stopped' || o.state === 'resumable') && Boolean(o.session_id) && !o.starting
      return (
        <Box key={`p-${p.name}`} flexDirection="column" marginTop={1}>
          <Box flexDirection="row" justifyContent="space-between">
            <Text bold color="white">
              {p.name.toUpperCase()}
            </Text>
            <Text color={look.color}>{`${look.dot} ${look.word}`}</Text>
          </Box>
          {row(
            'orchestrator',
            <Box flexDirection="row">
              <Text color="white">{o.name ?? (o.state === 'none' ? 'none yet' : '?')}</Text>
              {o.state === 'unregistered' && o.pane ? <Text color="gray">{`  pane ${o.pane}`}</Text> : null}
              {typeof o.context === 'number' ? (
                <Text color={o.context_assumed ? 'gray' : o.context >= rotateAt ? 'yellow' : 'green'}>{`  ${o.context}%`}</Text>
              ) : null}
              {o.context_unknown ? <Text color="gray">{'  context unknown'}</Text> : null}
            </Box>,
          )}
          {row(
            'agents',
            agents.length === 0 ? (
              <Text color="gray">none</Text>
            ) : (
              <Box flexDirection="row">
                {agents.map(a => (
                  // a space after each: two hollow dots side by side read as one wide sign
                  <Text key={`a-${p.name}-${a.name}`} color={agentColor(a)}>
                    {`${a.state === 'running' ? '●' : a.state === 'stopped' ? '○' : '?'} `}
                  </Text>
                ))}
                <Text color="white">{` ${up} of ${agents.length}`}</Text>
              </Box>
            ),
            ...(away.length > 0
              ? [<Text key={`away-${p.name}`} color="yellow">{away.map(a => `${a.name} ${a.state}`).join(', ')}</Text>]
              : []),
          )}
          {row(
            'tasks',
            <Text color="white">{`${p.open_tasks ?? 0} open${nightly > 0 ? ` · ${nightly} overnight run${nightly === 1 ? '' : 's'}` : ''}${cleaning > 0 ? ` · ${cleaning} cleanup` : ''}${doneToday > 0 ? ` · ${doneToday} done today` : ''}`}</Text>,
          )}
          {row(
            'folders',
            ...(p.repos ?? []).map(f => (
              <Text key={`f-${p.name}-${f.folder}`} color="white" wrap="truncate-end">
                {f.folder}
                {f.changed ? `  ${f.changed} changed` : ''}
              </Text>
            )),
          )}
          {busy === p.name && canResume ? (
            <Box paddingLeft={15}>
              <Text color="cyan">resuming…</Text>
            </Box>
          ) : canResume ? (
            <Box paddingLeft={15}>
              <Button
                key={`resume-${p.name}`}
                variant="primary"
                onPress={() => void act($, p.name, resumeArgs(p.name), 'its orchestrator is coming up; it reports back when its team is up')}
              >
                {`Resume · ${back} session${back === 1 ? '' : 's'}`}
              </Button>
            </Box>
          ) : null}
        </Box>
      )
    }

    // the engine's pane background is grey in an ANSI theme: paint the whole body in the terminal's own black
    return (
      <Box flexDirection="column" backgroundColor="black" width={body} minHeight={e.viewport?.rows ?? 0} paddingX={1}>
        {/* the folder gives way from its left, so the time always shows */}
        <Box flexDirection="row" justifyContent="space-between">
          <Box flexDirection="row" flexShrink={1}>
            <Text bold color="white">
              HUB
            </Text>
            <Text color="gray" wrap="truncate-start">
              {where ? `  ·  ${where}` : ''}
            </Text>
          </Box>
          <Box flexShrink={0} paddingLeft={2}>
            <Text color={v.away ? 'magenta' : 'gray'}>{v.away ? `away until ${untilLabel(v.away.until * 1000, now)}  ` : v.updatedAt ? 'relay  ' : ''}</Text>
            <Text color="gray">{v.updatedAt ? clock(v.updatedAt) : 'reading…'}</Text>
          </Box>
        </Box>
        {rule}
        {v.error ? <Text color="red">{v.error}</Text> : null}
        {needs.length > 0 ? (
          <Box flexDirection="column" marginTop={1}>
            <Text bold color="magenta">
              NEEDS YOU
            </Text>
            {needs.map(n => (
              <Box key={`n-${n.key}`} flexDirection="column" paddingLeft={1}>
                <Box flexDirection="row" justifyContent="space-between">
                  <Box flexDirection="row" flexShrink={1}>
                    <Text color={n.color}>{`${n.glyph} `}</Text>
                    <Text bold color="white">
                      {n.who}
                    </Text>
                    <Text color="white" wrap="wrap">{`  ${n.words}`}</Text>
                  </Box>
                  <Text color="gray">{n.when}</Text>
                </Box>
                {n.dialog ?? null}
                {n.action ? <Box paddingLeft={2}>{n.action}</Box> : null}
              </Box>
            ))}
          </Box>
        ) : null}
        {showDecided && decided.length > 0 ? (
          <Box flexDirection="column" marginTop={1}>
            <Box flexDirection="row" justifyContent="space-between">
              <Text bold color="cyan">
                DECIDED WHILE YOU WERE AWAY
              </Text>
              {v.away ? null : (
                <Button key="seen-away" plain onPress={() => void update($, seenAway, () => awaySince)}>
                  Seen
                </Button>
              )}
            </Box>
            {decided.map(d => (
              <Box key={`d-${d.id}-${d.at}`} flexDirection="row" justifyContent="space-between" paddingLeft={1}>
                <Box flexDirection="row" flexShrink={1}>
                  <Text bold color="white">
                    {d.id}
                  </Text>
                  <Text color="white" wrap="wrap">{`  ${d.reason}`}</Text>
                </Box>
                <Text color="gray">{ago(d.at, now)}</Text>
              </Box>
            ))}
          </Box>
        ) : null}
        {v.updatedAt && v.projects.length === 0 && !v.error ? (
          <Box marginTop={1}>
            <Text color="gray">No projects yet: tell the hub which folders make up a project.</Text>
          </Box>
        ) : null}
        {v.projects.map(card)}
        <Box marginTop={1}>{rule}</Box>
        <Box flexDirection="row" justifyContent="space-between">
          <Text color="gray">● running  ○ stopped  ◌ no team</Text>
          <Button key="refresh" plain hotkey="r" onPress={() => void refresh($)}>
            refresh
          </Button>
        </Box>
      </Box>
    )
  })
}

// ---- looks ------------------------------------------------------------------------------------------------------------
function orchestratorLook(p: HubProject): { dot: string; word: string; color: string } {
  const o = p.orchestrator ?? { state: 'none' }
  if (o.starting && o.state !== 'running') {
    return o.starting.typed || o.starting.sending ? { dot: '◐', word: 'coming up', color: 'cyan' } : { dot: '◐', word: 'waiting on you', color: 'magenta' }
  }
  const looks: Record<HubProject['orchestrator']['state'], { dot: string; word: string; color: string }> = {
    running: { dot: '●', word: 'running', color: 'green' },
    stopped: { dot: '○', word: 'stopped', color: 'yellow' },
    unknown: { dot: '?', word: 'cannot tell', color: 'red' },
    none: { dot: '◌', word: 'no team', color: 'gray' },
    unregistered: { dot: '◑', word: 'not registered', color: 'magenta' },
    resumable: { dot: '○', word: 'stopped, not registered', color: 'yellow' },
  }
  return looks[o.state] ?? looks.unknown
}

function agentColor(a: HubAgent): string {
  return a.state === 'running' ? 'green' : a.state === 'stopped' ? 'yellow' : 'red'
}

// What a waiting task asks of the owner. hm-hub decides which states wait (needs_owner); this only words them, and a
// state it does not know is shown by its own name.
function waitLook(state: string): { glyph: string; words: string; color: string } {
  const looks: Record<string, { glyph: string; words: string; color: string }> = {
    plan: { glyph: '▲', words: 'plan to approve', color: 'magenta' },
    question: { glyph: '?', words: 'question', color: 'yellow' },
    blocked: { glyph: '✖', words: 'blocked', color: 'red' },
  }
  return looks[state] ?? { glyph: '•', words: state, color: 'white' }
}

function clock(ms: number): string {
  return new Date(ms).toTimeString().slice(0, 5)
}

// When the owner is away until: the time today, else the weekday and the time
function untilLabel(ms: number, now: number): string {
  return sameDay(new Date(ms).toISOString(), now) ? clock(ms) : `${new Date(ms).toDateString().slice(0, 3)} ${clock(ms)}`
}

function sameDay(iso: string, now: number): boolean {
  return new Date(iso).toDateString() === new Date(now).toDateString()
}

function ago(iso: string, now: number): string {
  const s = Math.max(0, Math.round((now - Date.parse(iso)) / 1000))
  if (!Number.isFinite(s)) return ''
  if (s < 60) return 'now'
  if (s < 3600) return `${Math.floor(s / 60)}m`
  if (s < 86_400) return `${Math.floor(s / 3600)}h`
  return `${Math.floor(s / 86_400)}d`
}
