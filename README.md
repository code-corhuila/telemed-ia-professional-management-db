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
Family changelogs organize DDL, DML, DCL, and TCL. The master changelog explicitly orders the
initial DDL phase, DML phase, and post-DML DDL phase; the `01_ddl` family is intentionally split
around DML, so its files do not all run before `02_dml`.

`logicalFilePath` is used only for historical changesets moved during the repository reorganization,
to preserve their historical Liquibase identity in `DATABASECHANGELOG`. New changesets must use
their normal current file paths and must not copy `logicalFilePath` just because a historical
changeset has it.

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

Docker Desktop is required. Liquibase and `psql` run in containers. Each run uses a unique Compose
project and generated disposable credentials; the runner passes `PGPASSWORD` only to `psql` and
does not publish a host port.

```powershell
.\tests\run-db-tests.ps1
```

The script accepts `-ComposeCommand` or `COMPOSE_CMD` and performs a fresh update, schema
assertions, no-op second update, full rollback and empty-state checks, then reapplication and
final schema assertions. It restores prior `TEST_DB_PASSWORD`/`TEST_DB_USER` values and cleans up
its containers, network, and volume in a `finally` block.

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

The permanent seed rollback test script validates ownership, collision handling, checksums, and
full rollback/reapplication:


```powershell
.\tests\run-seed-rollback-tests.ps1
```

The Compose file and script do not reference production or monolith databases.

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
