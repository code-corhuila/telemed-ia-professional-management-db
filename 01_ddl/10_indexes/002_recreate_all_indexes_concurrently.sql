-- Anexo A rule 3 requires every index to be declared in 01_ddl/10_indexes/, and
-- rule 14 requires CREATE INDEX CONCURRENTLY on a table that already holds rows.
-- The three indexes below were created inside other changesets instead
-- (003-create-professionals, 006-add-professional-type-and-status, and
-- 004_create_idempotency_key). Those changesets are frozen, so the indexes are
-- dropped and re-created here with names that match the renamed singular tables.
--
-- Both sides of the swap use CONCURRENTLY. A plain DROP INDEX takes an
-- ACCESS EXCLUSIVE lock and blocks every concurrent read and write on the table
-- for the duration of the operation, which on a large `professional` table is a
-- visible outage; DROP INDEX CONCURRENTLY avoids that on the way out exactly as
-- CREATE INDEX CONCURRENTLY does on the way in. The forward and the reverse
-- direction are now symmetric, so neither the migration nor its rollback ever
-- holds an ACCESS EXCLUSIVE lock on a domain table.
--
-- CONCURRENTLY cannot run inside a transaction block, which is why the
-- ddl-indexes-002 changeset is registered with runInTransaction: false. The same
-- setting applies to the rollback, which is declared in the same changeSet block.
--
-- IF EXISTS is used on both sides so this changeset is safe when a source index
-- is already absent. idx_idempotency_key_professional_id keeps its historical
-- name: the idempotency_key table was never renamed, so no rename is required.
DROP INDEX CONCURRENTLY IF EXISTS professional_management.idx_professionals_specialty_id;
DROP INDEX CONCURRENTLY IF EXISTS professional_management.idx_professionals_status;
DROP INDEX CONCURRENTLY IF EXISTS professional_management.idx_idempotency_key_professional_id;

CREATE INDEX CONCURRENTLY idx_professional_specialty_id
    ON professional_management.professional (specialty_id);

CREATE INDEX CONCURRENTLY idx_professional_status
    ON professional_management.professional (status);

CREATE INDEX CONCURRENTLY idx_idempotency_key_professional_id
    ON professional_management.idempotency_key (professional_id);
