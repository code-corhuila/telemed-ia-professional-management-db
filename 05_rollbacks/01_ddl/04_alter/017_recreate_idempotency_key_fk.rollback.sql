ALTER TABLE professional_management.idempotency_key
    DROP CONSTRAINT fk_idempotency_key_professional;
ALTER TABLE professional_management.idempotency_key
    ADD CONSTRAINT fk_idempotency_key_professional
    FOREIGN KEY (professional_id)
    REFERENCES professional_management.professional (id)
    ON DELETE CASCADE;