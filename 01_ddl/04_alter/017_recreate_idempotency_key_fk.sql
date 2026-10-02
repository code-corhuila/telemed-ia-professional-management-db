-- Anexo A rule 2: foreign keys are added from 04_alter, not inline in
-- 03_tables. Changeset ddl-tables-004 is frozen and declares
-- fk_idempotency_key_professional
-- inline, so the constraint is dropped and re-added here.
--
-- Lock profile:
--   - DROP CONSTRAINT takes ACCESS EXCLUSIVE, but only for a catalog
--     update, so the lock is milliseconds.
--   - ADD CONSTRAINT ... NOT VALID takes only SHARE UPDATE EXCLUSIVE.
--   - VALIDATE CONSTRAINT (in the next changeset) also takes only
--     SHARE UPDATE EXCLUSIVE.
-- The expand/contract split avoids the ACCESS EXCLUSIVE full-table scan
-- that a plain ADD CONSTRAINT would take to validate the FK.
ALTER TABLE professional_management.idempotency_key
    DROP CONSTRAINT IF EXISTS fk_idempotency_key_professional;
ALTER TABLE professional_management.idempotency_key
    ADD CONSTRAINT fk_idempotency_key_professional
    FOREIGN KEY (professional_id)
    REFERENCES professional_management.professional (id)
    ON DELETE CASCADE
    NOT VALID;
