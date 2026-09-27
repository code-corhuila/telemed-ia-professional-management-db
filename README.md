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
they do not need to be installed locally. Each execution uses a unique Compose project, an empty
database volume, and a generated disposable password. It validates a fresh migration, a no-op
second update, complete rollback, and reapplication with the schema assertions.

```powershell
.\tests\run-db-tests.ps1
```

This script uses the Compose project `professional-management-db-test`, starts only its own
PostgreSQL container, runs Liquibase, and executes the SQL tests with the PostgreSQL image's
`psql`. If local port 5432 is occupied, it automatically exposes the test database on 55432
instead; container-to-container communication always uses the private Compose network.

The permanent seed rollback test script validates ownership, collision handling, checksums, and
full rollback/reapplication:

```powershell
.\tests\run-seed-rollback-tests.ps1
```

The runner removes only the containers, network, and volume belonging to its unique Compose
project in a finally block, including when a test fails. It does not publish a host port or
reuse Docker resources from previous executions. The Compose file and script do not reference
production or monolith databases.

Containers, networks, and volumes created by this script are disposable and are cleaned up when
the test run finishes. The separate schema test environment can be stopped with:

docker compose -p professional-management-db-test -f docker-compose.test.yml down

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
