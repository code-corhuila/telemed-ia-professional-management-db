# Data Dictionary — Professional Management

Authoritative data dictionary for the `professional_management` schema.
Tables, columns, types, constraints, indexes, and their meaning. Derived
from the Liquibase changesets in this repository; the changesets are the
source of truth and this document reflects their current state.

**Schema:** `professional_management`
**Engine:** PostgreSQL 16
**Liquibase version:** 4.31

---

## Conventions

- Table and column names: singular, `snake_case`.
- Constraint prefixes: `pk_` (primary key), `fk_` (foreign key), `uq_`
  (unique), `chk_` (check). Every constraint has an explicit name so a
  later migration can reference it.
- Constraint prefix `nn_` for NOT NULL is declared in some historical
  changesets (001a, 003) but PostgreSQL does not materialize a column-
  level `CONSTRAINT nn_... NOT NULL` as an entry in `pg_constraint`:
  the name is discarded and the constraint lives in
  `pg_attribute.attnotnull`. New migrations should not use `nn_` and
  should rely on the `NOT NULL` keyword alone, or declare the constraint
  via `ALTER TABLE ... ALTER COLUMN ... SET NOT NULL` if a name is
  required for later reference.

  Changesets 001a and 003 still contain `nn_` in their source; they
  are frozen by rule 12 and cannot be edited. The prefix is harmless
  (PostgreSQL discards the name), so there is no urgency to clean it
  up. A future migration may drop and re-add those NOT NULL
  constraints without a name if full consistency with this convention
  is wanted.
- Index prefixes: `idx_<table>_<columns>`.
- Text columns are `text` with an explicit `CHECK (char_length(...) <= n)`
  where the business fixes a limit; not `VARCHAR(n)`.
- Money, when present, is stored in minor units as `bigint`; never floating
  point.
- No closed value set uses the `ENUM` type; they use `CHECK` or a lookup
  table.

---

## Table: `professional_management.specialty`

**Purpose:** Catalog of medical specialties administered by Professional
Management. Reference data used by `professional.specialty_id`.

**Naming history:** this table was created as `specialties` by the frozen changeset
`001-create-specialties` and renamed to the singular `specialty` by
`ddl-alter-012`, to satisfy Anexo A rule 1. The applied changesets were not edited
(database standard, rule 12); the rename is a new migration.

| Column | Type | Nullable | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` (BIGSERIAL) | No | nextval | Primary key. |
| `name` | `text` | No | — | Specialty name. Unique across the catalog. |
| `description` | `text` | Yes | — | Optional human-readable description. |

**Constraints:**

| Name | Type | Definition |
|---|---|---|
| `pk_specialties` | Primary key | `(id)` |
| `uq_specialties_name` | Unique | `(name)` |
| `chk_specialties_name_length` | Check | `char_length(name) <= 100` |
| `chk_specialties_description_length` | Check | `description IS NULL OR char_length(description) <= 500` |

**Indexes:** none explicit besides the implicit ones created by the primary
key and the unique constraint.

**Seeded values (initial catalog):** seven specialties inserted by the seed
changesets `002-seed-specialties` and `004-seed-additional-specialties`:
Medicina General, Pediatría, Dermatología, Cardiología, Neurología,
Ginecología, Ortopedia.

---

## Table: `professional_management.professional`

**Purpose:** Stores a registered healthcare professional profile. One row per
professional.

**Naming history:** this table was created as `professionals` by the frozen changeset
`003-create-professionals` and renamed to the singular `professional` by
`ddl-alter-012`, to satisfy Anexo A rule 1. The applied changesets were not edited
(database standard, rule 12); the rename is a new migration.

| Column | Type | Nullable | Default | Meaning |
|---|---|---|---|---|
| `id` | `bigint` (BIGSERIAL) | No | nextval | Primary key. |
| `identity_user_id` | `bigint` | No | — | External reference to the Identity & Access account. No cross-database foreign key. Unique. |
| `license_number` | `text` | No | — | Professional license number. Unique. |
| `specialty_id` | `bigint` | No | — | Foreign key to `specialty.id`. |
| `years_experience` | `integer` | No | `0` | Years of professional experience. |
| `professional_type` | `text` | Yes | — | Domain classification. `NULL` during the registration-to-administration transition. |
| `status` | `text` | No | `'ACTIVE'` | Profile lifecycle status within Professional Management. |

**Constraints:**

| Name | Type | Definition |
|---|---|---|
| `pk_professionals` | Primary key | `(id)` |
| `uq_professionals_identity_user_id` | Unique | `(identity_user_id)` |
| `uq_professionals_license_number` | Unique | `(license_number)` |
| `fk_professional_specialty` | Foreign key | `specialty_id` → `specialty.id` `ON DELETE RESTRICT` |
| `chk_professionals_years_experience_nonnegative` | Check | `years_experience >= 0` |
| `chk_professionals_professional_type` | Check | `professional_type IN ('GENERAL_PRACTITIONER','SPECIALIST')` |
| `chk_professionals_status` | Check | `status IN ('ACTIVE','INACTIVE')` |
| `chk_professionals_license_number_length` | Check | `char_length(license_number) <= 80` |
| `chk_professionals_professional_type_length` | Check | `professional_type IS NULL OR char_length(professional_type) <= 30` |
| `chk_professionals_status_length` | Check | `char_length(status) <= 20` |

**Constraint naming:** the foreign key is the only constraint on this table whose
name follows the singular table. `pk_professionals`, `uq_professionals_*`, and
`chk_professionals_*` keep the historical plural `professionals` because they are
frozen inside changesets `003` and `006` and were not renamed by `ddl-alter-012`.
Anexo A rule 1 governs *table* names, not constraint names, and Anexo A rule 4 only
requires every constraint to have an explicit name, which these already do. Renaming
them is out of scope for this migration and is left to a separate PR.

**Indexes:**

| Name | Columns | Justification |
|---|---|---|
| `idx_professional_specialty_id` | `(specialty_id)` | Covers the foreign-key column. |
| `idx_professional_status` | `(status)` | Filter by lifecycle status. |

**Notes:**

- `identity_user_id` is an external reference to Identity & Access. It is
  intentionally NOT a foreign key: the referenced data lives in a different
  database (numeral 7.4 of the standard).
- `professional_type` is intentionally nullable. Historical professionals
  are not backfilled; an administrator classifies each profile after
  registration. The CHECK constraint evaluates NULL as unknown and does not
  reject unclassified rows.
- `status` defaults to `ACTIVE` so inserts from the current API contract,
  which omits the field, remain compatible.

---

## Table: `professional_management.specialty_seed_ownership`

**Purpose:** Tracks which specialty rows were inserted by which seed
changeset, so that rolling back a seed removes only the rows it created.
Pre-existing administrator-created rows are preserved across seed rollbacks.

| Column | Type | Nullable | Default | Meaning |
|---|---|---|---|---|
| `changeset_id` | `text` | No | — | Identifier of the seeding changeset that created the row. |
| `specialty_id` | `bigint` | No | — | Reference to the seeded specialty. |

**Constraints:**

| Name | Type | Definition |
|---|---|---|
| `pk_specialty_seed_ownership` | Primary key | `(changeset_id, specialty_id)` |
| `fk_specialty_seed_ownership_specialty` | Foreign key | `specialty_id` → `specialty.id` `ON DELETE CASCADE` |

**Indexes:**

| Name | Columns | Justification |
|---|---|---|
| `idx_specialty_seed_ownership_specialty_id` | `(specialty_id)` | Covers the foreign-key column. |

**Notes:** the `ON DELETE CASCADE` on this FK removes only the ownership
metadata row when an unreferenced specialty is deleted. It does NOT delete
professionals or specialties.

---

## Table: `professional_management.idempotency_key`

**Purpose:** Stores the `Idempotency-Key` HTTP header for professional
creation requests. The service writes the professional and its key in the
same transaction; a repeated key returns the originally created resource
instead of creating a new one.

| Column | Type | Nullable | Default | Meaning |
|---|---|---|---|---|
| `key` | `text` | No | — | The idempotency key from the HTTP request. Primary key. |
| `professional_id` | `bigint` | No | — | Foreign key to the professional created by this request. |
| `created_at` | `timestamptz` | No | `now()` | Row creation timestamp. |
| `request_hash` | `text` | Yes | — | Hash of the request body. Used to detect a retry with the same key but a different payload. |

**Constraints:**

| Name | Type | Definition |
|---|---|---|
| `pk_idempotency_key` | Primary key | `(key)` |
| `fk_idempotency_key_professional` | Foreign key | `professional_id` → `professional.id` `ON DELETE CASCADE` |
| `chk_idempotency_key_length` | Check | `length(key) BETWEEN 8 AND 128` |

**Indexes:**

| Name | Columns | Justification |
|---|---|---|
| `idx_idempotency_key_professional_id` | `(professional_id)` | Covers the foreign-key column. |

**Notes:** the key length (8-128) matches the database standard for
idempotent HTTP resource creation (Anexo C, numeral 5.3.8).

---

## Schema-level objects

### Schema

- `professional_management` — created by `ddl-schemas-001`. All domain
  tables live here.
- `public` — reserved for Liquibase's own bookkeeping tables
  (`databasechangelog`, `databasechangeloglock`). No domain table lives in
  `public`. This is the only exception to the rule that nothing lives in
  `public`.

### Roles

| Role | Login | Membership | Purpose |
|---|---|---|---|
| `professional_management_reader` | No (`NOLOGIN`) | — | Read access. USAGE on the schema, SELECT on all tables. |
| `professional_management_writer` | No (`NOLOGIN`) | Member of `professional_management_reader` | Write access. USAGE on the schema, SELECT/INSERT/UPDATE/DELETE on all tables, USAGE on sequences. |

The infrastructure creates the login users and assigns them to these roles
using credentials from environment secrets. No password is stored in the
repository.

### Default privileges

The grants changeset configures `ALTER DEFAULT PRIVILEGES` so tables and
sequences created in `professional_management` in the future inherit the
same grants automatically.

---

## Changeset to object mapping

| Changeset ID | Object created or modified |
|---|---|
| `ddl-schemas-001` | Schema `professional_management` |
| `001-create-specialties` | Table `specialties` (later renamed to `specialty` by `ddl-alter-012`) |
| `001a-create-specialty-seed-ownership` | Table `specialty_seed_ownership` |
| `002-seed-specialties` | Seed rows in `specialty` (Medicina General, Pediatría, Dermatología, Cardiología) |
| `004-seed-additional-specialties` | Seed rows in `specialty` (Neurología, Ginecología, Ortopedia) |
| `003-create-professionals` | Table `professionals` (later renamed to `professional` by `ddl-alter-012`) |
| `005-cascade-deleted-specialty-ownership` | FK `fk_specialty_seed_ownership_specialty` changed to `ON DELETE CASCADE` |
| `006-add-professional-type-and-status` | Columns `professional_type`, `status`, their CHECKs, index `idx_professional_status` |
| `ddl-alter-007` | Move all domain tables from `public` to `professional_management` |
| `ddl-alter-008` | Rename CHECK constraints from `ck_*` to `chk_*` |
| `ddl-tables-004` | Table `idempotency_key` |
| `ddl-alter-009` | Column `idempotency_key.request_hash` |
| `ddl-alter-010` | Rename UNIQUE constraints to `uq_*` |
| `ddl-alter-011` | Convert `VARCHAR(n)` columns to `text` with CHECK length |
| `ddl-indexes-001` | Index `idx_specialty_seed_ownership_specialty_id` |
| `001-create-roles` | Roles `professional_management_reader`, `professional_management_writer` |
| `001-grants` | Schema and table grants; default privileges |
| `dcl-grants-002` | Explicit grants on `idempotency_key` |
| `ddl-alter-012` | Rename `specialties` → `specialty` and `professionals` → `professional` (Anexo A rule 1) |
| `ddl-alter-013` | Re-declare `fk_professional_specialty` from `04_alter` on the renamed tables, added `NOT VALID` to avoid an `ACCESS EXCLUSIVE` full-table scan (Anexo A rule 2, norma 5.2.2) |
| `ddl-alter-014` | `VALIDATE CONSTRAINT fk_professional_specialty` under `SHARE UPDATE EXCLUSIVE`; completes the expand/contract pair |
| `ddl-indexes-002` | Re-create `idx_professional_specialty_id`, `idx_professional_status` and `idx_idempotency_key_professional_id` in `10_indexes` with `CONCURRENTLY` (Anexo A rules 3 and 14) |

---

## Not in this schema (owned by other domains)

| Data | Owned by |
|---|---|
| User credentials, login, tokens | Identity & Access |
| Appointment availability | Appointment Scheduling |
| Appointment lifecycle | Appointment Scheduling |
| Clinical content, consultation notes | Medical / Consultation |

The `professional.identity_user_id` column holds a reference to data owned
by Identity & Access. It is stored as a plain `bigint` with a UNIQUE
constraint and no foreign key, per numeral 7.4 of the standard (integrity
between domains is enforced by contract, not by the database engine).

---

## Notes on review findings

These notes answer the automated review findings left on the data
dictionary when it was introduced (PR #17).

- **Idempotency enforcement.** The `key` column of `idempotency_key`
  is a PRIMARY KEY (`pk_idempotency_key`), which is the mechanism that
  enforces single-row-per-key at the database level. The application
  logic (lookup-before-insert, return cached response on collision)
  lives in the `-api` repository, not here.
- **Changeset ID scheme.** The two ID schemes visible in this
  dictionary (`NNN-description` for historical changesets 001-006 and
  `ddl-<family>-NNN` for changesets 007 onwards) are intentional.
  Historical checksums are frozen (rule 12) and cannot be renamed
  without breaking every environment that applied them.
- **Cascade semantics.** Two foreign keys use `ON DELETE CASCADE`:
  - `fk_specialty_seed_ownership_specialty` removes the ownership
    metadata row when an unreferenced specialty is deleted. It
    does not delete professionals or specialties. Deleting a
    referenced specialty is blocked by `fk_professional_specialty`
    (`ON DELETE RESTRICT`). The metadata row only records which
    seed changeset inserted the specialty, so losing it on cascade
    does not lose business data. The rollback of
    `005-cascade-deleted-specialty-ownership` restores the FK to
    NO ACTION.
  - `fk_idempotency_key_professional` removes the stored
    idempotency key when the referenced professional is deleted.
    In normal operation professionals are not deleted: the
    Professional Management aggregate has no delete operation,
    and no soft-delete column is defined. If a professional were
    deleted out of band, the key would be removed with it and a
    later request reusing the same key would create a new record
    instead of returning the original. There is no audit trail
    and no soft-delete for either cascade; that is a deliberate
    choice for this domain, not an oversight. If the business
    later requires retention, the recovery path is a forward
    migration that adds a retention table or a soft-delete
    column, never a schema edit of a frozen changeset.
- **Completeness check.** The CI workflow
  (`.github/workflows/db-ci.yml`) catches drift between the
  migrations and a fresh database: every merge to `develop`, `qa`,
  or `main` runs `liquibase update` from an empty database, verifies
  idempotency, runs full rollback, and reapplies. It does **not**
  compare the text of this dictionary or the README against the
  live schema; documentation is synchronized manually. A
  doc-vs-schema check is not implemented, and its absence is
  exactly why PR #17 and PR #18 drifted undetected and why PR #19
  exists to correct that drift. Adding such a check is tracked as
  future work.
