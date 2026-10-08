# Development

## Tests

`bash tests/run.sh` runs every `tests/test_*.sh`, or the files it is given. `test_cleanup.sh` stops real processes, so
it is skipped, named or not, unless `HH_CLEANUP_TEST=1` is set: the owner runs it, watching. `test_hub_screen.sh` runs
the hub screen's own tests (`tests/*.test.ts`) through `claude plugin test`, with no model call, and says SKIP where
that is not available.

## Evals

Running the evals costs model usage.
