-- Drops the UUID index and makes sure the bigint idempotency index exists again:
-- ddl-alter-024 dropped it with its column, and the rollback of ddl-alter-024
-- restores the column without it. Both statements are CONCURRENTLY (Anexo A
-- rule 14), which is why ddl-alter-023 runs with runInTransaction: false.
DROP INDEX CONCURRENTLY IF EXISTS professional_management.idx_idempotency_key_professional_id_uuid;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_idempotency_key_professional_id
    ON professional_management.idempotency_key (professional_id);
