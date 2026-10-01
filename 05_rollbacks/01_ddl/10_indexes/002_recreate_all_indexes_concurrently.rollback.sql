-- Restores the three index definitions exactly as the frozen changesets 003,
-- 004, and 006 created them, including the historical plural index names.
-- No CONCURRENTLY is used here: the rollback is the reverse of ddl-indexes-002
-- and must re-create the indexes under the names the applied changesets expect.
DROP INDEX IF EXISTS professional_management.idx_professional_specialty_id;
DROP INDEX IF EXISTS professional_management.idx_professional_status;
DROP INDEX IF EXISTS professional_management.idx_idempotency_key_professional_id;

CREATE INDEX idx_professionals_specialty_id
    ON professional_management.professional (specialty_id);

CREATE INDEX idx_professionals_status
    ON professional_management.professional (status);

CREATE INDEX idx_idempotency_key_professional_id
    ON professional_management.idempotency_key (professional_id);
