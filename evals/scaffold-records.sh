#!/usr/bin/env bash
# A small project whose every fact first-run.md looks for is recorded and checks out, so /hivemind:start has nothing to
# ask about the project and goes on to its plan. Files and git state only: the eval loads no configuration it writes.
# Every case's scaffold.sh is the same two lines sourcing this file (tests/test_evals.sh keeps them so).
set -eu
git init -q -b main
git config user.email eval@example.com; git config user.name eval
mkdir -p src tests
cat > src/records.sh <<'SH'
#!/usr/bin/env bash
# Prints the records, one per line: id,name
printf '%s\n' '1,alpha' '2,beta' '3,gamma'
SH
cat > tests/test_records.sh <<'SH'
#!/usr/bin/env bash
[ "$(bash src/records.sh | wc -l | tr -d ' ')" = 3 ] || { echo "expected 3 records"; exit 1; }
SH
printf 'test:\n\tbash tests/test_records.sh\n.PHONY: test\n' > Makefile
cat > CLAUDE.md <<'MD'
# records

A shell script that prints the project's records (`src/records.sh`).

- Gate: `make test` must pass before anything lands. It is the only check; it runs in under a second and is not heavy.
- One test: `bash tests/test_records.sh`.
- Dev server: none. Nothing is served, so there is no port, host or health check.
- Database: none.
- A push triggers nothing: no CI, no deploys, no migrations.
- Paid steps: none. Nothing here calls a paid service, so there is no spend to read.
- Commits: Conventional Commits, one-line subject, no body, no attribution trailer.
- Base branch: main. Agents work in their own worktrees beside the project.
MD
git add -A; git commit -qm "chore: start the records project"
echo '# records' > README.md; git add README.md; git commit -qm "docs: add the readme"
chmod +x src/records.sh; git add -A; git commit -qm "fix(records): make the script executable"
