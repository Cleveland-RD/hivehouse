# Security

## Supported version

Only the latest release is supported. Update to it before reporting something you found.

## Reporting a vulnerability

Report it privately through GitHub: <https://github.com/Cleveland-RD/hivehouse/security/advisories/new>. Please do not open a public issue for a security problem.

Include:

- the hivehouse version (`plugin.json`) and your Claude Code version;
- what you ran and what you expected, with the smallest steps that reproduce it;
- what an attacker gains: a command or write that away mode should have refused, a file outside the project that changed, a message that reached a session it should not have, or a secret that leaked;
- whether it needs the owner's delegate file, a marked session or a particular platform.

## What counts

Away mode (delegate mode) keeps a hook, `bin/hh-away-hook`, in front of the tools of a session the owner is away from. It is a guard against mistakes, not a sandbox: it reads the words of a command, and its own documentation says the list of what it catches is not complete ([What away mode guards, and what it does not](docs/away-mode.md#what-away-mode-guards-and-what-it-does-not)). A command that gets past the hook is worth reporting, and so is one the documentation says it refuses and does not; one the documentation already lists as not caught is a known gap, not a new finding.

hivehouse never runs `sudo` itself and keeps its own state in the project's `.hivehouse/` folder and the hub's `.hivehouse-hub/` folder. A report about code you run yourself with `bypassPermissions` outside away mode is about Claude Code, not hivehouse.
