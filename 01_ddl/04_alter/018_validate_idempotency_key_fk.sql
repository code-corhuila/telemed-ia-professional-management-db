-- Validates the FK added NOT VALID by ddl-alter-017. VALIDATE
-- CONSTRAINT takes SHARE UPDATE EXCLUSIVE, so it does not block
-- concurrent reads or writes on idempotency_key.
ALTER TABLE professional_management.idempotency_key
    VALIDATE CONSTRAINT fk_idempotency_key_professional;
