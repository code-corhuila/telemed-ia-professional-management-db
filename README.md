# telemed-ia-professional-management-db

> TeleMed IA Professional Management bounded context: database schema, migrations, seed
> data, and database tests.

This repository belongs to the **TeleMed IA** distributed system and contains only the
database implementation for the Professional Management bounded context. Project
documentation and governance live in [`telemed-ia-docs`](https://github.com/code-corhuila/telemed-ia-docs).

## Database scope

This repository contains the PostgreSQL schema, Liquibase migrations/changelog, initial seed data,
and database tests for the Professional Management bounded context. It contains the `specialties`
and `professionals` tables;
`identity_user_id` is
an external reference to Identity & Access and intentionally has no foreign key to a local
`users` table.

An existing `professionals` row represents an active professional. This bounded context does
not currently define professional lifecycle states, soft deletion, or normal administrator
deletion of professionals. The catalog administration scope is `specialties`.

Migrations use Liquibase and are defined in
[`changelog/changelog-master.yaml`](changelog/changelog-master.yaml), the single entry point.
Family changelogs organize DDL, DML, DCL, and TCL while retaining each moved migration's original
logical file path (`changes/<migration-file>`) and `DATABASECHANGELOG` identity.

The fresh-database order is `001`, `001a`, `002`, `004`, `003`, `005`. Both seed changesets need
only `specialties` and the ownership ledger; creating `professionals` after both seed groups makes
reverse-order rollback safe with its restrictive specialty foreign key. DCL and TCL remain empty
scaffolding because this schema needs no roles, grants, or transaction changes.

The initial specialty catalog remains in two seed changesets because the existing Liquibase
history is retained without destructive changes. In a fresh database,
`002-seed-specialties.sql` adds the first four specialties and
`004-seed-additional-specialties.sql` adds the remaining three before
`003-create-professionals.sql` creates the dependent table. Together the seed changesets provide
the seven expected specialties without duplicating seed data.

Seed changesets record ownership only for specialty rows they actually insert. Pre-existing
specialties skipped by `ON CONFLICT` are never claimed. Fresh databases can roll back seed-created
rows, while legacy rows remain unowned and are preserved because historical ownership cannot be
inferred. Legacy seed rollback removes Liquibase history but preserves unowned rows; a complete
rollback drops the catalog when changeset 001 removes `specialties`.

The deployment configuration is [`deploy/compose.yml`](deploy/compose.yml). Copy `.env.example`
to `.env` and set the database name, user, password, and optional port before starting; `.env` is
ignored by Git.

## Specialty lifecycle and delete policy

An administrator may create and edit specialties. An administrator may delete a specialty only when no professionals are associated with it.
This is a hard delete, not a soft delete. If professionals reference the specialty, PostgreSQL
rejects the deletion through the `professionals.specialty_id -> specialties.id` foreign key.
The FK explicitly uses `ON DELETE RESTRICT`; deleting a specialty can never delete professionals
automatically. The seed ownership FK uses `ON DELETE CASCADE` only to remove its metadata row when
an unused specialty is deleted; seed rollback then has no ownership record for that row and cannot
delete a later administrator-created specialty with the same name.

This repository does not implement an API delete operation.

## Running schema tests

Docker Desktop is required. Liquibase and `psql` run inside PostgreSQL/Liquibase containers, so
they do not need to be installed locally. Each execution creates a unique Compose project and a
fresh database with a generated disposable password. The runner prints the project name when it
starts. It applies the Liquibase changelog, checks a second update is a no-op, performs a complete
rollback, verifies the database state, and reapplies the changesets with schema assertions.
The runner explicitly selects every Liquibase action. PostgreSQL and Liquibase receive the
generated password through environment variables, and test `psql` connects over TCP.

```powershell
.\tests\run-db-tests.ps1
```

The runner removes only the containers, network, and volume belonging to its generated project
in a `finally` block, including when a test fails. It restores the previous
`TEST_DB_PASSWORD` environment value. The test project does not publish a host port or reuse
resources from another run.

If the runner is interrupted with Ctrl+C, PowerShell's `finally` block is not reliably invoked
while the main thread is blocked inside a synchronous `docker` call. The runner also registers a
`Console.CancelKeyPress` handler as a best-effort safety net: it runs `docker compose down
--volumes --remove-orphans` for the same generated project and restores `TEST_DB_PASSWORD`. This
handler does not interrupt a `docker` command that is already running; PowerShell dispatches
Ctrl+C once control returns to the engine, typically after the in-progress `docker` call finishes
or is itself stopped, and the handler's cleanup runs at that point. It does not take control of
the interrupt or force the process to exit; it only runs this cleanup and then lets the host's
normal Ctrl+C behavior continue afterward. This is not an absolute guarantee: a forced kill (Task
Manager, `taskkill /F`, closing the terminal, or a second interrupt before cleanup finishes)
bypasses all user-mode handlers and can still leave the project's containers, network, or volume
behind. If that happens, use the project name the runner printed at startup to remove it
manually:

```powershell
docker compose -p <printed-project-name> -f docker-compose.test.yml down --volumes --remove-orphans
```

The permanent seed rollback tests validate ownership collisions, legacy Liquibase checksums,
staged and full rollback, and reapplication:

```powershell
.\tests\run-seed-rollback-tests.ps1
```

The automated runner cleans up its generated project when it exits. If a separate environment
was started manually with the `professional-management-db-test` project name, stop that named
environment with:

```powershell
docker compose -p professional-management-db-test -f docker-compose.test.yml down
```

## Manual debugging

While the automated test is running, use the generated project name printed by the runner to
inspect that run's database. The runner cleans it up when it exits. To keep a separate database
available for manual inspection, use the `professional-db-debug` project below. Run the commands
in order, exit the interactive `psql` session with `\q`, then run the cleanup commands.

The Compose file and script do not reference production or monolith databases.

```powershell
$debugProject = "professional-db-debug-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$env:TEST_DB_PASSWORD = [Guid]::NewGuid().ToString('N')
docker compose -p $debugProject -f docker-compose.test.yml up -d postgres
docker compose -p $debugProject -f docker-compose.test.yml run --rm liquibase update
docker compose -p $debugProject -f docker-compose.test.yml exec -T -e "PGPASSWORD=$env:TEST_DB_PASSWORD" postgres psql -U test_user -d professional_management_test
docker compose -p $debugProject -f docker-compose.test.yml down --volumes --remove-orphans
Remove-Item Env:\TEST_DB_PASSWORD
```

## Branching

Three permanent branches. **None of them accepts a direct commit** — you enter through a child
branch and leave through a Pull Request.

```
develop  <--PR--  feat/... fix/... chore/...
qa       <--PR--  qa/...
main     <--PR--  release/...  hotfix/...
```

Promotion happens **by re-application** (`git cherry-pick -x`), never by merging one permanent
branch into another: `merge develop -> qa` and `merge qa -> main` do not exist in this model.

`main` requires **1 approval from `ariel5253`**. On `develop` and `qa` the team sets its own review
rule.

Full policy: `00-governance/branching-policy.md` in `telemed-ia-docs`.
