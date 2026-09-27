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
[`db/changelog/db.changelog-master.yaml`](db/changelog/db.changelog-master.yaml).

The initial specialty catalog remains in two seed changesets because the existing Liquibase
history is retained without destructive changes. The execution order is intentional:
`002-seed-specialties.sql` adds the first four specialties, `003-create-professionals.sql`
creates the dependent table, and `004-seed-additional-specialties.sql` completes the catalog
with the remaining three specialties. Together they provide the seven expected specialties
without duplicating seed data.

Specialty seed changesets record ownership only for rows they actually insert. Pre-existing
specialties skipped by `ON CONFLICT` are never claimed. Fresh databases can roll back seed-created
rows, while legacy rows remain unowned and are preserved because historical ownership cannot be
inferred. A complete reverse-order schema rollback eventually removes the catalog when changeset
001 drops the `specialties` table.

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
Liquibase actions are selected explicitly by the runner.

```powershell
.\tests\run-db-tests.ps1
```

The runner removes only the containers, network, and volume belonging to its generated project
in a `finally` block, including when a test fails. It restores the previous
`TEST_DB_PASSWORD` environment value. The test project does not publish a host port or reuse
resources from another run.

The permanent seed rollback test script validates ownership, collision handling, checksums, and
full rollback/reapplication:

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

```powershell
$env:TEST_DB_PASSWORD = [Guid]::NewGuid().ToString('N')
docker compose -p professional-db-debug -f docker-compose.test.yml up -d postgres
docker compose -p professional-db-debug -f docker-compose.test.yml run --rm liquibase update
docker compose -p professional-db-debug -f docker-compose.test.yml exec -T postgres psql -U test_user -d professional_management_test
docker compose -p professional-db-debug -f docker-compose.test.yml down --volumes --remove-orphans
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
