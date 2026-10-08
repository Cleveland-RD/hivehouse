# Customise hivehouse

The principle, stated once: setup-specific behaviour is configuration, never a code change. Anything specific to one machine, project or person is met by an option, a file in `custom/` or an allowance in the delegate file, not by editing the plugin. Anything that loosens away mode is root-owned: it lives in the delegate file only you can write.

Ask Claude to customise anything: roles, rules, skills' behaviour, options. The one exception is loosening delegate (away) mode, which takes one sudo paste from you. This part is what Claude reads when you ask.

**Where each change goes**

- **A role, the rules or the brief template: `custom/`.** The plugin cache holds the installed plugin as a copy that is replaced by the next plugin update, so an edit inside it is lost; Claude never edits it (and an away session is refused if it tries). A file under `<project>/.hivehouse/custom/` (this project) or `${HIVEHOUSE_HOME:-~/.hivehouse}/custom/` (you, every project) takes the place of the plugin's file of the same path, the project's before yours before the plugin's:
  - `custom/roles/<role>.md` replaces `roles/<role>.md` (`implementer`, `fixer`, `reviewer`, `architect`, `product`), and `custom/roles/<new name>.md` adds a role of your own;
  - `custom/rules/RULES.md` replaces `rules/RULES.md`, which every skill and every agent reads first;
  - `custom/rules/brief-template.md` replaces `rules/brief-template.md`.
  - One resolver decides this for every skill: `hh-resolve role <name>`, `hh-resolve rules` and `hh-resolve brief` print the file to read, and a note on stderr says when a custom file is used or ignored. A custom file that is a link, that you do not own or that group or others can write is ignored with that note. `custom/` sits inside `.hivehouse/`, which git never tracks, so the project's files stay on this machine. A role file is copied into the team's folder when an agent is spawned, so a change reaches agents spawned afterwards. The project level follows `hh_project_root`, which honours `HH_PROJECT`; the away hub's start line sets `HH_PROJECT=<the hub's folder>`, so for the hub `<hub folder>/.hivehouse/custom/` is read (and a repository's `custom/` when the hub folder sits inside a repository), then your own `custom/`, then the plugin's.
- **A skill's behaviour.** A skill's own text is the plugin's, and an update replaces it. Everything a skill does is bound by the rules it reads first, so a change in how skills behave goes into `custom/rules/RULES.md` (or a role); a fact about one project goes in that project's `CLAUDE.md`.
- **Roles and rules for a team you spawn by hand.** `hh-spawn --role <file> --rules <file>` takes any two files: point them at your own copies.
- **Options.** The plugin options below, set in Claude Code's plugin settings.
- **Project safety settings.** `<project>/.hivehouse/settings.json` may tighten `permission_mode`, `overnight_ceiling_usd`, `allow_attribution` and `files_per_commit`, never loosen them.
- **What away mode allows.** `hh-hub away --until <time> [--mcp-allow <list>] [--remote-allow <hosts>]` prints the lines that write the delegate file (`--allow` is reserved and refuses; see [Customising what away mode allows](away-mode.md#customising-what-away-mode-allows)). When you ask Claude to loosen away mode, it prints those lines for you to paste and never edit anything to get round it.

**Every plugin option** (`.claude-plugin/plugin.json`, `userConfig`)

| Option | What it does | Default |
|---|---|---|
| `commit_style` | Commit subject style: conventional (type(scope): summary) or free | `conventional` |
| `allow_attribution` | Allow AI attribution trailers in commits: When off, gates refuse commits carrying Co-Authored-By or similar trailers | `false` |
| `files_per_commit` | Most files per commit: Gates warn or refuse commits touching more files than this | `5` |
| `model_orchestrator` | Orchestrator model: Model alias for the orchestrator session | `opus` |
| `model_builder` | Implementer/fixer model: Model alias for builder agents | `sonnet` |
| `model_reviewer` | Reviewer/architect/product model: Model alias for reviewing agents | `opus` |
| `effort_builder` | Builder effort: Reasoning effort for builder agents | `medium` |
| `effort_reviewer` | Reviewer effort: Reasoning effort for reviewing agents | `high` |
| `window_orchestrator` | Orchestrator context window (tokens): Used only when Claude Code's own reading of the window is missing (always for the orchestrator); never inferred from a model name | `200000` |
| `window_builder` | Builder context window (tokens): Used only when Claude Code's own reading of the window is missing; never inferred from a model name | `200000` |
| `window_reviewer` | Reviewer context window (tokens): Used only when Claude Code's own reading of the window is missing; never inferred from a model name | `200000` |
| `permission_mode_local` | Agents' permission mode on this machine: Bypass permissions is never used locally, except while the hub is in delegate mode (the owner is away): that needs this set to auto | `auto` |
| `remote_hosts` | Known remote hosts (comma-separated ssh names): ssh host names hivehouse may run overnight work on | `empty` |
| `dedicated_hosts` | Remote hosts dedicated to agents (bypass allowed): Comma-separated ssh names where bypass permissions may be used, asked again each time | `empty` |
| `rotate_at_percent` | Context level that triggers a handoff: Percent of the context window at which an agent hands off and is cleared | `50` |
| `overnight_ceiling_usd` | Spending ceiling per overnight run (USD): A project may only lower this | `50` |
| `heartbeat_minutes` | Overnight heartbeat interval (minutes): How often the orchestrator checks context, disk, queue and spend | `30` |
| `hub_auto_start` | Hub names itself and greets: A plain claude started in the hub's folder names itself hub (or hub-2...) and opens the hub, which takes one model turn; when off, start it with claude --name hub /hivehouse:hub | `true` |
| `hub_max_starts_per_day` | Hub: sessions started or woken per day while away: Delegate mode: the most sessions the hub starts or wakes in 24 hours before it keeps the rest for you. A guideline the hub passes to hh-hub recover, not a guard | `10` |
| `away_mcp_allow` | Away: MCP servers an away hub may use: Comma-separated MCP server names, or mcp__<server>__<tool>, loaded for the hub started by hh-hub away (none by default). Allowing a server allows its write tools too | `empty` |
| `min_free_gb` | Free disk (GB) below which cleanup runs: Below this, sessions get a low-disk warning and cleanup runs | `20` |

## Optional: i-have-adhd

[i-have-adhd](https://github.com/ayghri/i-have-adhd) shapes output for an ADHD reader. It is not a dependency: when it
is installed and enabled, the orchestrator reads its rules at the start and after every rotation and follows them in
every message to the owner; when it is not, nothing changes. hivehouse never installs, enables or switches it on.

```
claude plugin marketplace add ayghri/i-have-adhd
claude plugin install i-have-adhd@i-have-adhd
```

In any other session, `/i-have-adhd` turns it on. Its INSTALL.md also describes an always-on mode; with that on, the
plugin applies itself everywhere and hivehouse does not load it a second time.
