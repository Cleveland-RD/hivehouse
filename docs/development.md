# Development

## Tests

`bash tests/run.sh` runs every `tests/test_*.sh`, or the files it is given. `test_cleanup.sh` stops real processes, so
it is skipped, named or not, unless `HH_CLEANUP_TEST=1` is set: the owner runs it, watching. `test_hub_screen.sh` runs
the hub screen's own tests (`tests/*.test.ts`) through `claude plugin test`, with no model call, and says SKIP where
that is not available.

Before asking for review, run `tests/test_names.sh` together with the tests of the area you changed. It reads every file in
`bin/`, `hooks/` and `tests/` for a folder, path or command name spelled outside its constants, so a change that passes its
own test file can still fail it: 0.5.3's first full suite went red on two literal folder names a branch had never tested
against it.

## Evals

Running the evals costs model usage.
