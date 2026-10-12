-- Same expand/contract reasoning as the 015 rollback.
ALTER TABLE professional_management.idempotency_key
    DROP CONSTRAINT IF EXISTS fk_idempotency_key_professional;
ALTER TABLE professional_management.idempotency_key
    ADD CONSTRAINT fk_idempotency_key_professional
    FOREIGN KEY (professional_id)
    REFERENCES professional_management.professional (id)
    ON DELETE CASCADE
    NOT VALID;
ALTER TABLE professional_management.idempotency_key
    VALIDATE CONSTRAINT fk_idempotency_key_professional;
