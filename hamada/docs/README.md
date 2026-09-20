# Foundation developer guide
Start with `ARCHITECTURE.md`, then `MODULE_CONTRACT.md`, `REGISTRIES.md`, `PATHS.md`, `HEALTH_TESTING.md`, `COMPATIBILITY.md`, and `BUG_BACKLOG.md`.

Developer validation from repository root:
`python3 -m hamada.core validate`

Run tests:
`python3 -m unittest discover -s hamada/tests -p 'test_*.py' -v`

The CLI is developer-only in Phase 1 and is not installed into `/usr/bin` or invoked by setup/update/menu flows.
