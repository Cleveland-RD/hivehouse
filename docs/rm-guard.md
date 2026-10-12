# The delete guard

Three small programs in `bin/guard/` stand in front of the real `rm`, `find` and `rsync`. They refuse a call that would delete a
folder nobody means to delete, and otherwise hand the call, unchanged, to the real tool. It is always on, in relay mode and in
delegate (away) mode alike, and it is separate from away mode's hook.

## Where it runs

`bin/guard` is first in `PATH` for the Bash commands of every session where the plugin is enabled: a `SessionStart` hook
(`bin/hh-guard-env`) appends one `export PATH=...` line to the file Claude Code runs before each Bash command, which also holds after
`/clear`, after `--resume` and inside a subagent. Sessions that `hh-spawn` and the hub start get the same prefix in the command that
launches Claude, because a shell's startup files can rewrite `PATH` before the command runs.

## What it refuses

Every operand is resolved first: `~` and `$HOME` expanded, dot segments collapsed, links followed (a link is judged as itself, unless
the operand ends in `/`, which follows it). If any operand is one of these, the whole call is refused, nothing is deleted, and the
message names the operand and the reason (exit 1):

- `/`, or an empty operand;
- a folder fewer than 3 levels deep (`/Users`, `/Users/name`, `/home/name`, `/System/...`);
- your home folder, or a folder that holds it; `~/.claude`;
- the root of a synced cloud folder: `~/Library/CloudStorage` and each folder directly in it, `~/Library/Mobile Documents`, iCloud
  Drive, `~/Dropbox` and `~/Dropbox (anything)`. What is inside them can still be deleted;
- a git repository root (a folder whose `.git` is a folder; a linked worktree, whose `.git` is a file, can be removed);
- a hub folder (one that holds `.hivehouse-hub`) or a project home (one that holds `.hivehouse`);
- hivehouse's own plugin folder, or a folder that holds it;
- a temporary folder itself: `$TMPDIR`, `/tmp`, `/private/tmp`, `/var/tmp`.

Anything inside a temporary folder passes, a git repository there included (tests make and delete temporary repositories). `$TMPDIR` counts
as a temporary folder only when it lies inside a system temp location (`/private/var/folders`, `/private/tmp`, `/var/tmp`, `/tmp`); a
wrong `TMPDIR` does not widen what may be deleted.

`rm` judges every operand. `find` is judged only when it deletes (`-delete`, or `-exec`, `-execdir`, `-ok` or `-okdir` running `rm`), by
its starting points, or the current folder when it names none. `rsync` is judged only with a `--delete` option, by its destination, and a
remote destination (`host:path`, `rsync://`) is not judged here.

## No switch

There is no option, setting or variable that turns it off. To delete one of these on purpose, do it yourself in your own terminal, where
`bin/guard` is not in `PATH`.

## What it does not stop

A `PATH` guard stops `rm`, `find` and `rsync` called by name. It does not stop:

- `rm` called by its path (`/bin/rm`), `command -p rm`, or a session that replaces `PATH`;
- a program that deletes files itself (Python's `shutil.rmtree`, Node's `fs.rm`, a compiled tool), `git clean`, `unlink`, `rmdir`,
  `shred`, or `find -exec sh -c '...'` with an `rm` inside the script;
- `rsync --remove-source-files`;
- a project's `<state>/tmp` folder, which `hh-cleanup` treats as temporary but the guard does not: a git repository placed directly there is
  refused, and `hh-cleanup` then reports it could not remove it and skips it.

`rsync` finds its destination as the last operand, skipping the values of the options that take one; an option the guard does not know that
takes a separate value, placed last, can hide it. A full guard is an operating-system sandbox, which is outside hivehouse. For scripts an
agent writes, `rules/RULES.md` asks for `set -euo pipefail` and `${VAR:?}` on every variable operand of `rm -r`.

## For tests

`HH_GUARD_ROOT=<folder>` makes the guard judge paths as if that folder were `/`, and `HH_GUARD_REAL=<program>` replaces the real tool. The
tests use both, with a stub that only records its arguments, so nothing real is ever named or deleted. `HH_GUARD_ROOT` is honoured only
inside a system temp location.
