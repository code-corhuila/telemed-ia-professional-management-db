-- Anexo A rule 2: foreign keys are added from 04_alter, not inline in
-- 03_tables. Changeset ddl-tables-004 is frozen and declares
-- fk_idempotency_key_professional inline, so the constraint is
-- dropped and re-added here with the same definition (ON DELETE
-- CASCADE). Re-created with NOT VALID to avoid ACCESS EXCLUSIVE; the
-- validation runs in ddl-alter-018.
ALTER TABLE professional_management.idempotency_key
    DROP CONSTRAINT fk_idempotency_key_professional;
ALTER TABLE professional_management.idempotency_key
    ADD CONSTRAINT fk_idempotency_key_professional
    FOREIGN KEY (professional_id)
    REFERENCES professional_management.professional (id)
    ON DELETE CASCADE
    NOT VALID;