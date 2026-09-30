# First run: finding the project's facts

Look before asking. Order: what the project records, then what the code shows, then mechanical checks, then questions.

## 1. What the project records

`CLAUDE.md`, `CLAUDE.local.md`, the memory index, `README`, `docs/`, `.hivemind/` (an earlier run may have recorded
these already). Take a fact from here as recorded, but still run its check below.

## 2. What the code shows

| Fact | Where to look |
|---|---|
| Gate command (what must pass before landing) | `package.json` scripts (`test`, `lint`, `build`, `typecheck`), `Makefile`, CI workflow files, a `scripts/` directory |
| Dev server: start command, port | `package.json` `dev`/`start`, `manage.py runserver`, `Procfile`, `docker-compose.yml`, `Makefile` |
| How a server is reached in a browser (host, subdomain, HTTPS) | env examples (`.env.example`), framework config, allowed-hosts and cookie-domain settings, certificates in the repo |
| Health check | a `/health` or `/api/health` route, a docker healthcheck, the README |
| Database rules (local vs shared, migrations) | env examples, ORM config, migrations folder, CLAUDE.md |
| What a push triggers (deploys, migrations) | CI workflow files, `vercel.json`, `Procfile`, deploy scripts, the platform's git settings |
| What counts as a paid step and how spend is read | env examples naming model or payment providers; a ledger or usage table; CLAUDE.md. No ceiling can be enforced without a way to read spend. |
| Test runner and one-test command | `package.json`, `pytest.ini`, `vitest`/`jest` config |
| Commit style | `git log` (last 20 subjects), CLAUDE.md |
| Heavy jobs (suites, builds, browser runs) | the gate and dev-server commands above |

## 3. Mechanical checks (run them, do not assume)

- The start command's executable exists (`command -v`, or the script is present in `package.json`).
- The port is free, or a server already answers its health check (a plain read-only request).
- `git status` is clean, or you know why it is not; the base branch exists.
- `tmux -V` is 3.0 or later, and `jq` is installed.
- Free disk is enough: the skill passes the owner's minimum, `hm-disk --min-gb <n>`.

## 4. Ask only about what is left

What remains unknown, ambiguous (two start commands, which is the dev one), or failed its check. Show the finding next to
each question, multiple choice where possible, and ask where each answer is recorded: for everyone on the project in
`CLAUDE.md`; about this machine (ports, hosts, local URLs, the remote's name) in `CLAUDE.local.md` or `.hivemind/`, so a
committed file never publishes them. Write nothing until the owner says OK.

## Markers

Write `HM-CLARIFY:` on its own line before any clarifying question, and `HM-PLAN:` on its own line before the team plan.
They are distinct: the first asks, the second asks for approval of a plan.
