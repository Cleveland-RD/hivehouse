# Changelog

## 0.5.0

- **hivemind is now hivehouse.** A new user installs hivehouse and never meets the old name. This release knows only the new names: it reads nothing under an old name, so a machine that ran hivemind moves once, by hand, in this order: stop the teams, migrate each folder below (every project, the hub and `--home`), and only then reinstall the plugin and start sessions. A 0.5.0 session started before the migration creates the new folders, and the migration then refuses because both the old and the new exist.

  | What | Was | Is |
  |---|---|---|
  | Plugin and marketplace | `hivemind` | `hivehouse` |
  | Install | `hivemind@hivemind` | `hivehouse@hivehouse` |
  | Commands | `/hivemind:<skill>` | `/hivehouse:<skill>` (skill names unchanged) |
  | Executables | `bin/hm-*` | `bin/hh-*` |
  | Library functions | `hm_*` | `hh_*` |
  | Environment | `HM_*`, `HIVEMIND_HOME` | `HH_*`, `HIVEHOUSE_HOME` |
  | Hub protocol words | `HM-CLARIFY`, `HM-PLAN` | `HH-CLARIFY`, `HH-PLAN` |
  | Project state folder | `.hivemind/` | `.hivehouse/` |
  | Hub folder | `.hivemind-hub/` | `.hivehouse-hub/` |
  | Per-user home and slot | `~/.hivemind` | `~/.hivehouse` |
  | Delegate folder | `/Library/Application Support/hivemind`, `/etc/hivemind` | `/Library/Application Support/hivehouse`, `/etc/hivehouse` |
  | Delegate file's first line | `hivemind-delegate 1` | `hivehouse-delegate 1` |
  | Machine slot | `/Library/Application Support/hivemind/slot`, `/var/lib/hivemind/slot` | `/Library/Application Support/hivehouse/slot`, `/var/lib/hivehouse/slot` |
  | Hub screen pane | `hivemind-hub` | `hivehouse-hub` |
  | Message prefix | `hivemind: ` | `hivehouse: ` |
  | Repository | `Cleveland-RD/hivemind` | `Cleveland-RD/hivehouse` |

- **The hub screen's remembered state resets once.** Claude Code keeps a screen's state under the plugin's name, and the name must be the plugin's own, so what the screen remembered under `hivemind` (the view, a press in progress, the away period whose decisions you have seen) is not carried over.
- **Each name is spelled in one place.** The folder, path, prefix and delegate names are constants at the top of `bin/hh-lib.sh` (and `hooks/names.ts` for the hub screen); the plugin's name is read from `.claude-plugin/plugin.json` by `hh_plugin_name`, which every typed `/<plugin>:<skill>` command, the session hook's skill line and the remote-sync plugin check use. `tests/test_names.sh` holds the rest of the tree to it.
- **The 0.3.0 shared-file notice is gone.** `hh-hub away` and `back` no longer look for the old `<folder>/delegate` file or print the line that removes it: under the new folder it cannot exist.
- **The test suite is isolated from the session that starts it.** It keeps only an allowlist of environment variables and drops every other plugin's `bin/` from its `PATH`, so a suite started from a session that has another version of these tools can never reach them or their state. `tests/test_isolation.sh` proves it against a made-up foreign plugin and a canary.
- **A name used in two team roots is told apart by its root** (0.4.1). `hh-hub status`, `dialog`, `recover` and the screen's Resume, Continue and answer key an agent by its team root and its name, so two agents of one name in two worktrees of a project no longer answer for each other.
- **A name that matches two sessions** (0.4.1): `rules/RULES.md` says to send to the row on this machine, the one with a tmux pane, and never to stop and ask which.
- **The away hook no longer refuses `ListAgents`.** The hook's matcher in `hooks/hooks.json` is now anchored (`^(...)$`). Unanchored, a regular expression that Claude Code evidently reads as one matched `Agent` inside `ListAgents` (and `Write` inside `TodoWrite`), so the hub skill's first step was refused while the owner was away. Measured in tests (the matcher compiled as a JavaScript `RegExp` matches every tool it lists and none of `ListAgents`, `TodoWrite` and other names that contain a listed word); not checked live.
- **The printed `chown` and `chmod` lines run on macOS.** `hh-hub away` and `hh-slot setup` put `--` after the owner or the mode (`sudo chown root:wheel -- <path>`, `chmod go-w -- <path>`), and BSD `chown` and `chmod` read that `--` as a file name ("chown: --: No such file or directory", exit 1; the paths still changed). The options now come first (`sudo chown -- root:wheel <path>`, `chmod -- 0644 <file>`, `chmod -- go-w <path>`), which both BSD and GNU accept. The tests run every printed line, as the user on a scratch folder.
- **An agent can be messaged by the name `hh-spawn` gave it while the owner is away.** The away hook accepted only `<project>-<agent>`; the short name an orchestrator naturally uses (`outreach-round`) was refused. It now also accepts the short name of an agent in the caller's own team, resolved against that team's `team.json` and checked by process like the long name; the same short name for an agent of another team or project, the hub reaching an agent, and a short name a live session of another process also carries are still refused.

## 0.4.0

- **Away mode for each user.** The delegate file is now one file per user, `<base>/delegate.d/<uid>` (`/Library/Application Support/hivemind` on macOS, `/etc/hivemind` on Linux), named by the user's real id, so several people on one machine can each be away on their own. The hub it names, its `.hivemind-hub/`, `projects.json` and `hub.json`, and each project home that gets bypass must belong to that user and not be writable by group or others.
- **A 0.3.0 delegate file stops working.** Run `hm-hub away` again: it prints the new lines, and says that the old shared file is no longer read and prints the line that removes it (`hm-hub back` does too).
- **The hub sees every orchestrator and team.** A project's team roots are its home and each worktree of its repository with a `team.json` (`hm_team_roots`, read without git from the two pointers git keeps; relative worktree paths work). `hm-hub status`, `wake`, `dialog`, `run` and `recover` use them, the away hook lets the hub message a worktree's orchestrator, bypass reaches a worktree team root on the same terms as the home, and every team root takes its settings from the home. A live session named just like the project, in its home, counts as its orchestrator, and `hm-hub wake` resumes an orchestrator that ended unregistered from Claude Code's transcript (by id, only when the last `custom-title` and every `cwd` match), shown by `status` as `stopped, not registered (resumable)`.
- **The away hook and the away checks use a root-owned `jq`.** The hook fixes its `PATH` first, and `hm_jq_fixed` resolves `/usr/bin/jq`, `/usr/local/bin/jq` or `/opt/homebrew/bin/jq` only when root owns it and every folder above it; `hm_delegate_mine`, `hm_delegate_for_project`, `hm_write_away_mcp` and the hook use it. The hook finds a root-owned `jq` in any of the three places, so a hub can still message its orchestrators on a machine whose `jq` is in `/usr/local/bin` or `/opt/homebrew/bin`. A fake `jq` or `cat` on `PATH` can no longer answer for a hub or a call. With no root-owned `jq` (a Homebrew-only machine before macOS 15) the hook denies and bypass is refused: install one root-owned.
- `hm-hub` runs with `umask 022` and takes group and others' write off `.hivemind-hub/`. `hm-hub away` checks the hub's records, each project home and each project's worktree team roots first, and prints the reason and a `chmod go-w` line instead of `sudo` lines for an away that would be refused. `hm-hub status` shows `away_refused` and why (`hub.away_refused` in `--json`), the hub's screen header shows "away refused: <reason>" when a delegate file exists but is refused, and the hub skill tells the hub to pass the reasons and the `chmod` lines to the owner word for word.
- The delegate file is mode 0644, so other users on the machine can read whether you are away and where your hub is. A project home cloned under `umask 002` (775) is refused while away until you run `chmod go-w` on it; `hm-hub away` prints that line.
- **The heavy-job slot has a queue.** `hm-slot run --wait [<seconds>] <label> -- <command>` and `hm-slot acquire <label> --pid <pid> --wait [<seconds>]` wait for the slot in the order callers asked, instead of each one retrying and whoever retries first winning; the wait is unbounded without a time, and 75 when the time runs out. Without `--wait` the answer is still 75 at once, also while others wait. `hm-gate` waits, and the gate, start and review skills and `rules/RULES.md` say to use `--wait` instead of retrying. A `--wait` under a slot its own parent holds is refused at once, since it could never end. `hm-slot status` shows the queue.
- **One slot for the whole machine (optional).** `hm-slot setup` prints the lines an administrator runs once to make a machine slot folder (`/Library/Application Support/hivemind/slot` on macOS, `/var/lib/hivemind/slot` on Linux); every user then shares one slot. It is used only while the folder passes its checks (root-owned, not a link, mode 2775, trusted parents) and falls back to the user's own slot otherwise, and `hm-slot status` says why. `HM_SLOT_LOCAL=1` opts out. The slot is coordination, not a security boundary.
- **Add or drop a project's folders.** `hm-hub add <project> --repo <folder>...` adds folders to an existing project and `hm-hub drop <project> <folder>` removes one (never the home); tasks and memory stay.
- **The hub's name across machines.** `hm-hub name <name>` sets the name the hub's folder starts from (default `hub`), and the hub skill tells the owner once when another live session already has its name.
- **The hub's git guard.** Read-only `git worktree` commands (`list`) pass, and only `add`, `remove`, `move`, `prune`, `repair`, `lock` and `unlock` are refused. Quoted text follows the shell's own quoting, so a note that holds a git command is no longer refused; the guard reads quotes and parentheses inside `$(...)`, here-strings (`<<<`), partly quoted heredoc words, arithmetic (`<<` as a shift) and `#` comments as the shell does, so fewer git writes slip past it. What the shell does run inside quoted text is still checked: `$(...)` and backtick spans in double quotes and in a heredoc with an unquoted delimiter. Single quotes, `$'...'` and a quoted heredoc (`<<'EOF'`) are the owner's words and pass.
- **No context level over 100%.** `hm-spawn --self` records the window Claude Code reported for the session, else none (`--window` still wins). A reading over an assumed window prints as `<tokens> tokens (window unknown)`, never as a percent, and the hub's screen and `hm-hub status` show it as unknown.
- **`hm-hub status` is quicker.** It keeps what a project's transcripts said while the newest 20 of a root are unchanged, and reads each root's context levels once. A kept answer is checked like a fresh one (a bad session id or time is read again), and a cache miss is silent.
- **One orchestrator when two are registered.** When a project's home holds a stale orchestrator entry and a worktree's team holds a live one, the live one is the orchestrator: `hm-hub status` shows it running, `wake` and the screen's Resume refuse to start a second one on the old conversation, and `recover` checks it for a hang. Only the orchestrator's own entry leaves the agent list; a spawned agent that shares its name in another root stays listed.
- **`hm-hub recover` wakes a resumable orchestrator.** An orchestrator that ended unregistered but left a transcript, with an open task, is woken like a stopped one, within the same daily caps.
- **The hub's chosen name is used everywhere.** `hm-hub away`'s and `back`'s start lines, the hint `hm-hub self` gives when a session has no name, and the screen's naming toasts say the name `hm-hub name` shows, not always `hub`.
- **Sessions the hub starts keep your umask.** `hm-hub` writes its own records under `umask 022`, but a pane it starts (`start`, `wake`) now runs under the umask of the shell that asked, so an owner on `umask 077` no longer gets world-readable agent files.

## 0.3.0

- The owner can do everything from the hub, so never has to go to a project's own tmux window.
  - **Overnight and cleanup through the hub:** `hm-hub run <project> overnight|cleanup <task id>` types the owner-only skill's fixed line into the project's running orchestrator, on the owner's yes for that run. `overnight` and `cleanup` are task states, open and not waiting on the owner.
  - **Dialogs through the hub:** `hm-hub dialog` shows a dialog on an orchestrator's or agent's screen with its options; `hm-hub answer --choice <1-9|esc> --seen <fingerprint>` sends the one key, or moves the cursor and presses Enter for a menu with no numbers, after checking the screen is the one the owner saw. Answers are logged to `.hivemind-hub/answers.jsonl`, not to the task ledger. While the owner is away the hub never answers a dialog.
- **Delegate (away) mode.** `hm-hub away --until <time> [--mcp-allow <list>]` prints the `sudo` lines that create a root-owned file (`/Library/Application Support/hivemind/delegate` on macOS, `/etc/hivemind/delegate` on Linux) and the hub's own start line (the file's fourth line, `mcp=`, names the MCP servers the owner allowed); `hm-hub back` prints the line that ends it. Away is at most 7 days. While the file is valid the hub decides internal work, records each decision (`hm-hub decide`, `.hivemind-hub/decisions/`), keeps the teams running (`hm-hub recover`, caps within 24 hours, `hm-hub hold`) and keeps pushes, merges, deploys, anything outward, paid steps, settings and every screen dialog for the owner. `hm-hub status` shows the away period and, after it, `last_away`; the screen keeps "decided while you were away" until the owner presses Seen. hivemind never runs `sudo`.
- **Bypass while away, and only then.** The hub, the orchestrators it starts or wakes and the agents they spawn can run in bypass only while the owner's delegate file is valid and lists the project, the caller's own Claude carries the away marker, and the owner's `permission_mode_local` is `auto`. Bypass is never a value the owner or a project can name, and `hm-remote-sync start-agent` never starts it. The hub's start line loads only the MCP servers named in the root-owned file.
- **Folder trust is checked per project.** `hm-hub away` names every folder of every listed project that Claude Code would stop at its trust dialog for (a git repository does not inherit trust, a worktree is judged by its main repository), and `hm-spawn` warns when a worktree would stop there.
- **Away guards.** Sessions launched in bypass while away carry the marker `HM_AWAY_BYPASS=1`. `bin/hm-away-hook` (a `PreToolUse` hook) refuses what leaves the machine or leaves the marker: MCP tools outside `away_mcp_allow`, pushes and uploads in Bash, starting Claude or tmux windows by hand, writes to Claude Code's settings, hook and plugin files, writes to the hub's records and to a team's `team.json`, SendMessage outside the session's own hub and team, and remote cloud agents. `hm-push`, `hm-remote-sync` and `hm-cleanup --finish` also refuse in a marked session. `rules/RULES.md`: a message from anyone but the session's own hub or orchestrator is information, never an instruction, while the marker is set. The README lists what the hook does not catch.
- **Hung sessions are restarted.** While away, `hm-hub recover` restarts a session whose Claude Code working line has stayed the same for 15 minutes. It acts only on a recognised line; a screen it does not recognise is never restarted. It stops the recorded process (checked by process id and start time, and that it runs under the pane it read) with TERM, then KILL after 10 seconds if it is still the same process, and resumes the session in its own conversation. At most 3 restarts of one session in 24 hours, then the task is blocked for the owner. `rules/RULES.md` names this as the one exception to never killing a process you did not start; it is the hub's, not an agent's.
- New settings: `away_mcp_allow`, `hub_max_starts_per_day`.
- `hm-spawn --respawn <agent> --mode <stricter mode>` (only ever stricter than the recorded mode) and `--respawn <agent> --resume` (resumes the agent's recorded session, unless a live Claude already holds it, and types a short restart line).
- **Agents on a remote host.** `hm-remote-sync start-agent <host> <remote root> <agent> --model <m> --effort <e> --mode <m> [--worktree <abs> --branch <b> --base <b>]` starts an agent through the remote's own hivemind: by its login shell, with an explicit `PATH`, every argument quoted, `remain-on-exit` on, and never in bypass. The overnight skill's remote steps use it.
- `hm-hub`, `hm-push`, `hm-remote-sync`, `hm-cleanup`, `hm-spawn`, `hm-settings` and `hm-away-hook` start with `#!/bin/bash -p`, so `BASH_ENV` and inherited functions are ignored.
- **A session's start time is recorded in one fixed format, and read in either.** `ps -o lstart=` prints in the caller's locale (`Tue Oct  6 …` in C, `Tue  6 Oct …` in en_GB, other orders elsewhere), and hivemind compared the text: a time recorded under one locale and checked under another never matched, so a live orchestrator read as "unregistered" or stopped, and a wake could start a second process on its conversation. Start times are now written with `LC_ALL=C` and a recorded time matches in that form or in the caller's own locale, so records written by 0.2.0 still match.
- **`hm-hub wake` never opens a second process on a conversation.** It refuses (exit 4) when a live Claude already holds the orchestrator's recorded session, whatever the start-time comparison says.
- **Locks fail toward busy.** A lock held by a live process is taken over only when its recorded start time names another time (the process id was reused), judged by the numbers in it, not the words, so another language's record of the live holder keeps the lock. The slot's busy message names the lock's path, so a stuck lock can be found.
- `hm-hub recover` counts each wake against the daily cap as it decides it, so two stopped orchestrators and room for one wake one.
- **Upgrade notes.**
  - Restart every hivemind session after updating. A running session keeps the old plugin's programs until it restarts, so for a while 0.2.0 and 0.3.0 programs share the machine's slot. 0.3.0 writes the slot's holder record with the start time in both forms (`lstart` in the caller's locale, as 0.2.0 reads it, and `lstart_c` in C), so a 0.2.0 session in the same locale reads 0.3.0's lock, and 0.3.0 reads 0.2.0's.
  - Records written before 0.3.0 under another locale are still read, so a live session no longer reads as gone. A record in a form that is neither the fixed one nor the reader's own locale reads as gone until it is recorded again: `hm-hub self` (the hub, at every start) and `hm-spawn --self` (an orchestrator) do that.

## 0.2.0

- Requires Claude Code 2.1.291 or later.
- The owner's hub: one session in the work folder, above every project, hands each task to that project's
  orchestrator and carries the owner's words both ways (`hm-hub`, `/hivemind:hub`). Once `hm-hub init` has set the
  folder up, a plain interactive `claude` there names itself `hub` and opens the hub (`hub_auto_start`). A project can
  span several folders. The hub wakes an orchestrator a restart stopped, resuming its own conversation, and starts one
  where none is, each on the owner's word, in the owner's local permission mode made stricter by the project's
  settings. An orchestrator running outside hivemind is found from Claude Code's session records, never doubled.
- `hm-spawn --self --hub <hub>`: the orchestrator's pickup line names the hub, so the link survives a rotation; a later
  registration keeps it (`--no-hub` drops it).
- A start stopped at a question on its screen is kept and continued (`hm-hub continue`) once the owner answers it; a
  dialog on any orchestrator's or agent's screen is reported.
- The hub's screen (`/hub-screen`): what waits on the owner, then every project's orchestrator, agents, tasks and
  folders, with Resume and Continue. In the hub's session, edits inside the work folder or a project are refused.
- A dialog that has been still is reported at once instead of after the whole wait.
- README: a section for an agent installing hivemind from its link.

## 0.1.2

- After a restart: `hm-context` marks a session that is no longer running, keeping its last level, and
  `hm-spawn --respawn <agent>` starts a stopped agent again from its own record and sends it back to its handoff.
- One check decides whether a team member still runs as recorded, read from its process first: `hm-rotate`,
  `hm-context` and `hm-spawn --respawn` all use it.

## 0.1.1

- Context levels use Claude Code's own window for spawned agents; a guessed window is marked as assumed.
- Agents report to the orchestrator's real session name; the orchestrator's own pickup line waits for nobody.
- `hm-spawn --self` records the orchestrator's session, so its context level reads from the start.
- An agent spawned without `--session` goes beside the calling pane.
- Commit before the gate: `hm-gate` warns on a dirty tree, and an unchecked GREEN says so; `hm-gate` is never wrapped
  in `hm-slot run`.
- Every message to the owner ends with "Nothing needed from you." or what is needed.
- The optional i-have-adhd plugin's rules are used when it is installed and enabled; hivemind never installs it.

## 0.1.0

- First version.
