## User story

Reference the story in the documentation repository:

- `code-corhuila/telemed-ia-docs#NN`

## What changes and why

A short description of the change and the reason. One or two paragraphs.

## How it was tested

List the tests that cover this change and the result of the `ci.yml`
(or `db-ci.yml`) workflow. For this repository, the relevant checks are:

- `tests/run-db-tests.ps1` (reconstruction, idempotency, rollback,
  reapply) — local.
- `tests/run-seed-rollback-tests.ps1` (nine integration scenarios) —
  local and CI.
- `tests/sql/professional-schema-tests.sql` (schema, constraints,
  roles, privileges, seeds) — local and CI.

## Promotion trace

Only for Pull Requests targeting `qa` or `main`. List every commit
re-applied from the source branch, each one with its
`(cherry picked from commit <sha>)` line. See norm 10.

## Checklist

- [ ] No secrets, credentials, or `.env` files are versioned.
- [ ] No schema changes outside this `-db` repository.
- [ ] No changeset already applied is edited (norm 5.2.3 / rule 12).
- [ ] Every new changeset ships an external rollback under `05_rollbacks/`.
- [ ] The published contract is respected (if applicable).
- [ ] The `ci.yml` / `db-ci.yml` workflow is green.
