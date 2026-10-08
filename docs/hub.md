# The hub

One Claude session in the owner's work folder, the folder above every project, is the owner's entry point:

- **Set up once.** Run `hh-hub init` in the work folder (it refuses inside a repository). An agent installing hivehouse
  does this for you; `/hivehouse:hub` in a session there offers it too, then asks you to start `claude` again, since a
  session started before the folder was the hub has no screen and no guard. From then on every session started in
  that folder, and only there, is the hub: a new, unnamed one names itself `hub` (`hub-2` beside another, since
  orchestrators reply to the hub by name) and opens the hub by itself, which takes one model turn. The `hub_auto_start`
  setting turns that off; then start it with `<installPath>/bin/hh-hub start`.
  The name belongs to the hub's folder: `hh-hub name <name>` keeps it in `.hivehouse-hub/name`, and the hub starts from it
  (`<name>-2` beside another). `ListAgents` shows sessions on other machines only while Remote Control is connected, and without it
  the check finds nothing; a hub that finds its name taken there says so once and never renames itself.
- **Projects span folders.** A project is its home, the repository its team works from, and any other folders it
  covers (`hh-hub add <project> --home <folder> --repo <folder>...`). The hub proposes the groups from `hh-hub discover`
  and adds only what the owner confirms. `hh-hub add <project> --repo <folder>...` adds folders to a project that exists,
  and `hh-hub drop <project> <folder>` takes one out (never the home); tasks and memory stay.
- **Teams in worktrees.** A project's team roots are its home, then each worktree of the home's repository that has a
  `.hivehouse/team.json`. `hh-hub status`, `wake`, `dialog`, `run` and `recover` look in every one (an orchestrator
  registered in two counts once; each agent is listed with its worktree), the away hook lets the marked hub message a
  worktree's orchestrator, and bypass is granted in a worktree team root exactly as in the home: the root and the home
  must both be the caller's, not links, and not writable by group or others. Every team root takes its settings from the
  home (a worktree's own `.hivehouse/settings.json` is not read). The worktrees are found without running git: from
  `<home>/.git/worktrees/<name>/gitdir` and the worktree's own `.git` file, which must point at each other (relative
  paths, as git 2.48 can write them, are resolved against the file they are in). git comes from `PATH`, which an away
  session's own Bash command sets, so it is never run on the grant path.
- **An orchestrator that ended unregistered** is found too. A live session named exactly like the project, running in its
  home, counts as its orchestrator. When nothing is recorded of its conversation, `hh-hub wake` looks in Claude Code's
  transcripts under the folder key of each team root (`<config dir>/projects/<key>/*.jsonl`, the 20 newest per root) for
  the newest one whose last `custom-title` is `<project>-orchestrator` and whose records' `cwd` is that root exactly (the
  key alone is not trusted: `/ . _ & space` all become `-`). It resumes that session by id, never by name, and
  `hh-hub status` shows it as `stopped, not registered (resumable)`. The transcript format is Claude Code's and
  undocumented: reading it is one function, `hh_resume_candidate` in `bin/hh-lib.sh`.
- **Handing work over.** The owner's words go to the ledger and a task file (`hh-hub task`), then to the project's
  orchestrator: a message when it runs; `hh-hub wake` when a restart stopped it, which resumes its own conversation (its
  own model) and tells it to register with the hub and bring its agents back; `hh-hub start` when there is none. An
  orchestrator already running outside hivehouse is found in Claude Code's own session records and never doubled. Each
  start asks the owner first, and runs in the owner's local permission mode (`permission_mode_local`, the one hivehouse's
  agents run in), made stricter where the project's own `.hivehouse/settings.json` says so. Start the hub in that mode
  too: sessions in different modes hold each other's messages for an approval nobody sees.
  Both launch the orchestrator with the same measuring statusLine a spawned agent has, so its context window is read from
  Claude Code and not guessed; one that then registers under another name than the one the start or wake line gives measures
  into the other name's folder, which does no harm.
- **Starting it: `<installPath>/bin/hh-hub start`.** Run in the work folder (`hh-hub` is not on your PATH in a terminal; the plugin's
  `installPath` is the one `claude plugin list --json` shows), it opens the hub in a tmux session named after it, running
  `claude` for the hub, and attaches; when that session already runs the hub it only attaches, and it never starts a
  second one. Inside tmux it starts nothing and prints the lines to start the hub beside your session. At every start the
  hub records its own pane (`hh-hub self`), as an orchestrator does with `hh-spawn --self`.
- **A window that reads wrong is set by the hub.** `hh-hub window <project> <agent>[@<team root>] <tokens>` records the agent's real
  context window in its team.json entry (a name used in two team roots of the project needs the root, as `hh-hub dialog` does) and
  prints it. Only the hub runs it: while the owner is away every marked session but the hub's is refused; with the owner here any
  session may, as with `hh-hub self`.
- **The hub rotates like an orchestrator.** At `rotate_at_percent` (the same level every session uses) the hub updates
  its handoff, `.hivehouse-hub/memory/hub-handoff.md`, and runs `hh-hub rotate`: it waits until its pane is idle, checks
  it is still the recorded pane and process, types `/clear`, then its pickup line. `hh-hub context` shows its level. The
  handoff template and the pickup line are `rules/hub-handoff.md` and `rules/hub-pickup.md`; a file of the same name
  under `custom/` overrides them (see [Customise](customise.md)). A hub started outside tmux cannot rotate. The away
  beat is recreated at every start (and after `/clear`) when the owner is still away.
- **Through the hub.** The orchestrator registers with `hh-spawn --self --hub <hub>`, so every pickup line, after each
  rotation too, says the owner talks through the hub. It sends its questions, plan, blockers and results there; the hub
  shows them word for word and carries the answer back. The ledger records each task's state; a plan, a question and a
  blocker wait on the owner.
- **Nothing stuck, nothing unseen.** A start that stops at a question on its screen is kept: once the owner answers it,
  `hh-hub continue` (or the screen's Continue) sends the line, and never while the start's own line is still on its way.
  A dialog waiting on any orchestrator's or agent's screen is shown to the owner.
- **Claude Code's session records.** Naming itself and finding orchestrators outside hivehouse read
  `~/.claude/sessions/<pid>.json`, which Claude Code keeps and does not document. Without them the hub names nothing
  (the person types `/rename hub`) and finds only orchestrators hivehouse registered; nothing else changes.
- **The screen.** `/hub-screen` (or a wide terminal, at start) opens a pane: what waits on the owner, then each
  project's orchestrator, agents, tasks and folders, with Resume and Continue buttons, and a button for each option of a dialog waiting on a session (a click carries the dialog's `Seen` fingerprint, so an answer to a screen that has changed is refused). It reads `hh-hub` only while shown.
- **Hands off the code.** The hub never reviews, builds, tests, commits or pushes. In the hub's session the module
  refuses an edit inside the work folder (apart from `.hivehouse-hub/`) or inside a project's folder, and a git command
  that changes a repository; quoted text and heredocs are the owner's words, never a command (best effort for shell).

## Overnight and cleanup through the hub

`/hivehouse:overnight` and `/hivehouse:cleanup` can only be started by a person typing them. The hub types them for the owner: `hh-hub run <project> overnight <task id>` and `hh-hub run <project> cleanup <task id> [--disk]`. Only these two skills, only a line `hh-hub` builds, only into the project's running, registered orchestrator, and only after the owner's yes for that one run. It refuses a task that waits on the owner, a task already in an overnight run, and a second run while one is being typed. The task then shows as `overnight` or `cleanup`, open and not waiting on the owner.

## Dialogs through the hub

A permission prompt or another dialog on an orchestrator's or agent's screen is shown to the owner with its options (`hh-hub dialog <project> [<agent>]`). The owner can answer it from the hub: `hh-hub answer <project> [<agent>] --choice <1-9|esc> --seen <fingerprint>`, which presses the one key (or, for a menu with no numbers, moves the cursor and presses Enter as the last key of that choice) after checking that the dialog is still the one the owner saw. The hub never offers the options that need the owner's own words, "Type something" and "Chat about this": those are answered in the pane. An option that saves a permission rule ("always allow…") is marked as such when it is shown. Every answer is logged to `.hivehouse-hub/answers.jsonl`, not to the task ledger, because a dialog belongs to no task. Limits: two identical dialogs in a row share a fingerprint, and the screen's one-press-at-a-time lock is what stops a repeat; multi-select and multi-question dialogs are untested.
