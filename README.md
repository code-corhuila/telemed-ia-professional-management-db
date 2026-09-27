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
[`changelog/changelog-master.yaml`](changelog/changelog-master.yaml), the single changelog entry
point. DDL and DML are organized under `01_ddl/` and `02_dml/`; empty DCL and TCL changelogs keep
the family structure ready without defining unused roles, grants, or transaction operations.
Migration SQL retains inline rollback definitions, so no separate file-based rollback scripts
are currently needed.

The master changelog explicitly orders the migrations as `001`, `001a`, `002`, `004`, `003`,
then `005`. The initial DDL family creates `specialties` and its seed-ownership ledger; the DML
family inserts both specialty seed groups; the post-DML DDL changelog then creates `professionals`
and updates the ownership foreign key. Both seed changesets need only `specialties` and the
ownership ledger. Creating `professionals` after both seed groups ensures a reverse-order rollback
drops the professional table before rolling back seed rows, avoiding its restrictive foreign key.
Changeset `005` remains last so its rollback restores the original ownership FK before the earlier
changesets are rolled back.

This structural PR leaves migration SQL content as found in current `develop`; it only moves the
files into their DDL/DML families. Family changelogs assign the original Liquibase logical file
paths (`changes/<migration-file>`), preserving each historical `author:id`, checksum, and
`DATABASECHANGELOG.FILENAME` across the physical file move. Existing databases therefore
recognize the historical changesets instead of attempting to reapply them.

Seed changesets record ownership only for specialty rows they actually insert. Pre-existing
specialties skipped by `ON CONFLICT` are not claimed and are preserved by seed rollback. The
ownership foreign key cascades only when an unused specialty is deleted; the professional foreign
key remains restrictive. On legacy databases, ownership cannot be inferred for already-applied
seed rows, so the new ledger is intentionally not backfilled. Rolling back those legacy seed
changesets removes their Liquibase history but preserves the unowned rows; only a complete rollback
that drops `specialties` removes that legacy data.

The domain PostgreSQL deployment configuration is [`deploy/compose.yml`](deploy/compose.yml).
Copy `.env.example` to `.env` and set the database name, user, password, and optional port before
starting it. `.env` is ignored by Git.

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

Docker Desktop is required. The test Compose file starts PostgreSQL 16 with a generated,
disposable password. Liquibase and `psql` run in containers, so they do not need to be installed
locally. The runner generates a disposable password and supplies `TEST_DB_USER` and
`TEST_DB_PASSWORD` to Compose. PostgreSQL receives `POSTGRES_PASSWORD`, Liquibase receives its
credentials through its environment, and the runner passes `PGPASSWORD` directly to the `psql`
client invocation. The test database is not published on a host port.

```powershell
.\tests\run-db-tests.ps1
```

The script accepts `-ComposeCommand` or `COMPOSE_CMD`, uses a unique Compose project and generated
disposable credentials for each run, and executes the complete lifecycle: fresh update, schema
assertions, no-op second update, full rollback, empty-schema/changelog verification, reapplication,
and final schema assertions. The runner restores prior `TEST_DB_PASSWORD`/`TEST_DB_USER` values and
cleans up its containers, network, and volume in a `finally` block.

The permanent seed rollback tests validate ownership collisions, legacy Liquibase checksums,
staged and full rollback, and reapplication:
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
