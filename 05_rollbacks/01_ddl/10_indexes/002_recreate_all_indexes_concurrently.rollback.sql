-- Restores the three index definitions exactly as the frozen changesets 003,
-- 004, and 006 created them, including the historical plural index names.
--
-- The three DROP statements are the mirror image of ddl-indexes-002 and also use
-- CONCURRENTLY, so reverting the index swap does not take an ACCESS EXCLUSIVE
-- lock on a domain table either. This is safe because the rollback inherits
-- runInTransaction: false from the same changeSet block, which CONCURRENTLY
-- requires.
DROP INDEX CONCURRENTLY IF EXISTS professional_management.idx_professional_specialty_id;
DROP INDEX CONCURRENTLY IF EXISTS professional_management.idx_professional_status;
DROP INDEX CONCURRENTLY IF EXISTS professional_management.idx_idempotency_key_professional_id;

CREATE INDEX CONCURRENTLY idx_professionals_specialty_id 
    ON professional_management.professional (specialty_id);

CREATE INDEX CONCURRENTLY idx_professionals_status
    ON professional_management.professional (status);

CREATE INDEX CONCURRENTLY idx_idempotency_key_professional_id
    ON professional_management.idempotency_key (professional_id);
