-- DEC-006: indexes the UUID foreign-key column of idempotency_key before
-- ddl-alter-024 swaps it in, so the swap only renames the index. The table may
-- hold rows, so the index is built CONCURRENTLY (Anexo A rule 14) and
-- ddl-alter-023 runs with runInTransaction: false.
CREATE INDEX CONCURRENTLY idx_idempotency_key_professional_id_uuid
    ON professional_management.idempotency_key (professional_id_uuid);
