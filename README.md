# telemed-ia-professional-management-db

> professional-management bounded context: database (schema, seeds, migrations)

Part of the **LMS Library** distributed system — team `lms-library`, Grupo 2.
Governance and documentation live in [`library-docs`](https://github.com/code-corhuila/library-docs).

## Database scope

This repository contains only the PostgreSQL schema and initial catalog seeds for the Professional
Management bounded context. It contains the `specialties` and `professionals` tables;
`identity_user_id` is
an external reference to Identity & Access and intentionally has no foreign key to a local
`users` table.

Migrations use Liquibase and are defined in
[`db/changelog/db.changelog-master.yaml`](db/changelog/db.changelog-master.yaml).

## Running schema tests

Docker Desktop is required. The test Compose file starts PostgreSQL 16 with the database
`professional_management_test`, user `test_user`, and password `test_password`. Liquibase and
`psql` both run inside containers, so they do not need to be installed locally.

```powershell
.\tests\run-db-tests.ps1
```

The script uses the Compose project `professional-management-db-test`, starts only its own
PostgreSQL container, runs Liquibase, and executes the SQL tests with the PostgreSQL image's
`psql`. If local port 5432 is occupied, it automatically exposes the test database on 55432
instead; container-to-container communication always uses the private Compose network.

To stop and remove only this testing environment:

```powershell
docker compose -p professional-management-db-test -f docker-compose.test.yml down
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

Full policy: `00-governance/branching-policy.md` in `library-docs`.
