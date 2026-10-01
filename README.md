# telemed-ia-professional-management-db

> TeleMed IA Professional Management bounded context: database schema, migrations, seed
> data, and database tests.

This repository belongs to the **TeleMed IA** distributed system and contains only the
database implementation for the Professional Management bounded context. Project
documentation and governance live in [`telemed-ia-docs`](https://github.com/code-corhuila/telemed-ia-docs).

## Database scope

This repository contains the PostgreSQL schema, Liquibase migrations/changelog, initial seed data,
and database tests for the Professional Management bounded context. It contains the `specialty`
and `professional` tables;
`identity_user_id` is
an external reference to Identity & Access and intentionally has no foreign key to a local
`users` table.

All domain tables live in the `professional_management` schema. Liquibase's own
`databasechangelog` and `databasechangeloglock` tables stay in `public` because
Liquibase creates them there by default; this is the only exception to the rule
that nothing lives in `public`.

Each `professional` row represents a professional registered in Professional Management. The
`status` field expresses the profile lifecycle: `ACTIVE` means the professional is active and
available within this bounded context; `INACTIVE` means the record remains registered while the
professional is inactive. `status` is independent of `professional_type`. A professional may
initially be created with `professional_type` set to `NULL`; an administrator later classifies the
profile as `GENERAL_PRACTITIONER` or `SPECIALIST`. This bounded context does not currently define
soft deletion or normal administrator deletion of professionals. The catalog administration scope
is `specialty`.

The `specialty` and `professional` tables were created as `specialties` and `professionals` by the
frozen changesets `001` and `003`. Changeset `ddl-alter-012` renames them to the singular required
by Anexo A rule 1 without editing the applied history.

Migrations use Liquibase and are defined in
[`changelog/changelog-master.yaml`](changelog/changelog-master.yaml), the single entry point.
The four migration families are `01_ddl`, `02_dml`, `03_dcl`, and `04_tcl`. The `01_ddl` family
intentionally has two changelog fragments: `01_ddl/changelog.yaml` and
`01_ddl/changelog-post-dml.yaml`. The root changelog coordinates the DDL phases around `02_dml` to
preserve the historical execution and rollback order: `001` → `001a` → `002` → `004` → `003` →
`005` → `006`. Contributors must not assume that all DDL runs before all DML; this split is intentional.

## Schema migration

Changeset `ddl-schemas-001` in `01_schemas` creates the `professional_management` schema.
Changeset `ddl-alter-007` in `04_alter` moves `specialties`, `professionals`, and
`specialty_seed_ownership` from `public` into `professional_management`, along with their
owned sequences. Changeset `ddl-alter-008` in `04_alter` renames the professional CHECK
constraints from `ck_*` to `chk_*`. Changeset `ddl-indexes-001` in `10_indexes` adds the
missing index on `specialty_seed_ownership.specialty_id`.

Four later changesets align the schema with the database standard without editing any
already-applied changeset (database standard, rule 12). `ddl-alter-012` renames `specialties`
to `specialty` and `professionals` to `professional` (Anexo A rule 1, singular names).
`ddl-alter-013` drops and re-adds the specialty foreign key as `fk_professional_specialty`
so it is declared from `04_alter` (Anexo A rule 2 and norma 5.2.2); it is added `NOT VALID`
so the change takes only a `SHARE UPDATE EXCLUSIVE` lock instead of `ACCESS EXCLUSIVE`.
`ddl-alter-014` then runs `VALIDATE CONSTRAINT` on that same foreign key, completing the
expand/contract pair without ever holding an `ACCESS EXCLUSIVE` lock on `professional`.
`ddl-indexes-002` re-creates the
three domain indexes in `10_indexes` with `CONCURRENTLY` and singular names (Anexo A
rules 3 and 14); it is registered with `runInTransaction: false` because
`CREATE INDEX CONCURRENTLY` cannot run inside a transaction block. Its three
`DROP INDEX CONCURRENTLY` statements do the same on the way out, so neither the
migration nor its rollback blocks concurrent reads and writes on a domain table.

The actual application order is `ddl-schemas-001` → `001` → `001a` → `002` → `004` →
`003` → `005` → `006` → `ddl-alter-007` → `ddl-alter-008` → `ddl-alter-010` →
`ddl-alter-011` → `ddl-tables-004` → `ddl-alter-009` → `ddl-indexes-001` →
`ddl-alter-012` → `ddl-alter-013` → `ddl-alter-014` →
`ddl-indexes-002` → `001-create-roles` → `001-grants` →
`dcl-grants-002`.

`ddl-alter-012`, `ddl-alter-013`, and `ddl-alter-014` are registered in
`01_ddl/03_tables/changelog-post-alter.yaml` rather than in `04_alter/changelog.yaml`, because
`ddl-tables-004` still references the historical name `professional_management.professionals`.
That fragment is included after `04_alter/changelog.yaml`, so registering the renames in
`04_alter` would make `ddl-tables-004` fail. This is the same ordering rule already used by
`ddl-alter-009`.

Use `logicalFilePath` only for historical changesets whose physical SQL path changed during
repository reorganization. Its value must preserve the exact historical logical path used by
Liquibase, and existing values must not be changed. New changesets should normally use their current
physical path; do not copy `logicalFilePath` as a template. Use a different logical path only for an
explicit, documented compatibility reason.

Both seed changesets need only `specialty` and the ownership ledger; creating `professional`
after both seed groups makes reverse-order rollback safe with its restrictive specialty foreign key.
Migration `006` adds `professional_type` (`GENERAL_PRACTITIONER` or `SPECIALIST`) and `status`
(`ACTIVE` or `INACTIVE`) to `professional`. During this transition, `professional_type` is nullable
because historical data does not establish each existing professional's type; the migration does
not backfill or default it. `status` defaults to `ACTIVE` so inserts using the current Professional
API contract, which omits both new fields, remain compatible. Rolling back changeset 006 drops both
columns and its status index only when no professional records exist. If any row exists, rollback
fails before removing anything because `professional_type` or `status` may contain a later domain
decision; the schema cannot distinguish `ACTIVE` supplied by the default from `ACTIVE` chosen
subsequently. No historical professional type is backfilled. An empty `professional` table is
therefore required to roll back 006 safely.

## Access control

The DCL changesets create two `NOLOGIN` roles and grant them the minimum
privileges needed to use `professional_management`:

- `professional_management_reader`: `USAGE` on the schema and `SELECT` on all tables.
- `professional_management_writer`: `USAGE` on the schema, `SELECT`/`INSERT`/`UPDATE`/
  `DELETE` on all tables, and `USAGE` on sequences. It is a member of the reader role.

Infrastructure creates login users and assigns them to these roles using credentials
from environment secrets. No password is stored in the repository. Default privileges
ensure that future tables and sequences created in `professional_management` receive
the same grants automatically.

`04_tcl` is reserved for transaction-control changes when required and is currently
empty because the Professional Management database has no such requirement.

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
rollback drops the catalog when changeset 001 removes the specialty table.

The deployment configuration is [`deploy/compose.yml`](deploy/compose.yml). Copy `.env.example`
to `.env` and set the database name, user, password, and optional port before starting; `.env` is
ignored by Git.

## Repository structure alignment

The repository follows the database standard structure. Every migration family
under `01_ddl`, `02_dml`, `03_dcl`, and `04_tcl` carries a `changelog.yaml` in
each subfolder; subfolders without objects yet carry an empty changelog so the
execution order is fixed from the start.

The historical DDL split is preserved: `01_ddl/changelog.yaml` runs the
catalog table and ownership ledger before the seeds; `01_ddl/changelog-post-dml.yaml`
runs the professional table, its constraints, and its indexes after the seeds.
This keeps reverse-order rollback safe with the restrictive foreign key from
`professional.specialty_id` to `specialty.id`.

### Rollback layout

Rollbacks for **new** changesets live as external files under `05_rollbacks/`,
mirroring the migration families. Historical changesets `001` through `006`
were applied before this layout existed and keep their inline `--rollback`
blocks; editing them would change their Liquibase checksum and break every
environment that has applied them (database standard, rule 12).

See [`05_rollbacks/README.md`](05_rollbacks/README.md) for details.

### Continuous integration

`.github/workflows/db-ci.yml` runs on every pull request and push to `develop`,
`qa`, and `main`. It exercises the full rebuild cycle against an empty database:

1. `liquibase update` — builds the schema.
2. `liquibase update` again — must apply zero changesets.
3. `liquibase rollback-count 999` — reverts every changeset.
4. Verifies no domain tables remain in `public`.
5. `liquibase update` — reapplies the full set.

## Specialty lifecycle and delete policy

An administrator may create and edit specialties. An administrator may delete a specialty only when no professionals are associated with it.
This is a hard delete, not a soft delete. If professionals reference the specialty, PostgreSQL
rejects the deletion through the `professional.specialty_id -> specialty.id` foreign key.
The FK explicitly uses `ON DELETE RESTRICT`; deleting a specialty can never delete professionals
automatically. The seed ownership FK uses `ON DELETE CASCADE` only to remove its metadata row when
an unused specialty is deleted; seed rollback then has no ownership record for that row and cannot
delete a later administrator-created specialty with the same name.

This repository does not implement an API delete operation.

## Idempotency

The `idempotency_key` table stores the `Idempotency-Key` HTTP header for
professional creation requests. The service writes the professional and its
idempotency key in the same transaction. If the same key is received again,
the service reverts and returns the originally created professional. The `key`
column is constrained to 8-128 characters, matching the database standard.

### Request fingerprint

`idempotency_key.request_hash` stores the hash of the request body. When a retry arrives with an existing key, the API compares the incoming request's hash with the stored one. If they differ, the API rejects the retry with `422 BUSINESS_RULE_VIOLATION` instead of silently returning the original resource. The hash algorithm and encoding are chosen by the API implementation and must be consistent across retries.

## Schema qualification

Domain tables live in `professional_management`, not in `public`. Consumers
of this database must either:

- qualify table names (`professional_management.professional`), or
- set `search_path = professional_management, public` in the connection.

Relying on the default `search_path = public` and unqualified names will fail
with `relation does not exist`. The `-api` repository is responsible for its
own connection configuration; this repository cannot set it.

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

### Test runners

- `tests/run-db-tests.ps1`: reconstructs the schema, verifies the second
  update is a no-op, rolls back completely, verifies empty, and reapplies.
  Runs in CI and locally.
- `tests/run-seed-rollback-tests.ps1` exercises nine integration scenarios
  (seed ownership ledger, legacy checksums, staged rollback ordering). It
  runs both locally and in CI: the workflow executes it on `pwsh` over
  `ubuntu-latest`. The script uses cross-platform path construction
  (`[System.IO.Path]::GetTempPath()` and forward slashes) so the same file
  works on Windows and Linux.
- `tests/sql/professional-schema-tests.sql`: schema, constraints, roles,
  privileges, and seed assertions. Runs in CI (via psql) and locally.

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

## User story traceability

The schema in this repository implements **HU-005 — Professional Management**
from `telemed-ia-docs`. The mapping between the user story requirements and
the schema objects is documented below.

| Requirement | Schema object | Changeset |
|---|---|---|
| Administer the medical specialty catalog | Table `specialty` | `001-create-specialties` (renamed by `ddl-alter-012`) |
| Initial catalog with seven specialties | Seed rows in `specialty` | `002-seed-specialties`, `004-seed-additional-specialties` |
| Register healthcare professionals | Table `professional` | `003-create-professionals` (renamed by `ddl-alter-012`) |
| Classify professionals as general practitioner or specialist | `professional_type` column with CHECK | `006-add-professional-type-and-status` |
| Professional lifecycle status within Professional Management | `status` column with CHECK | `006-add-professional-type-and-status` |
| Delete a specialty only when unreferenced | FK `fk_professional_specialty` `ON DELETE RESTRICT` | `003-create-professionals`, re-declared by `ddl-alter-013` and validated by `ddl-alter-014` |
| Seed data that can be rolled back without affecting administrator rows | Table `specialty_seed_ownership` | `001a-create-specialty-seed-ownership`, `005-cascade-deleted-specialty-ownership` |
| Idempotent HTTP creation of professionals | Table `idempotency_key` | `ddl-tables-004` |
| Detect a retry with the same key but different body | Column `idempotency_key.request_hash` | `ddl-alter-009` |

**Status:** all requirements are implemented in the 22 changesets of this
repository. The full data dictionary is in [`DATA-DICTIONARY.md`](DATA-DICTIONARY.md).

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
