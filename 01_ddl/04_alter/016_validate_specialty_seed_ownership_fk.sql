-- Validates the FK added NOT VALID by ddl-alter-015. VALIDATE
-- CONSTRAINT takes SHARE UPDATE EXCLUSIVE, so it does not block
-- concurrent reads or writes on specialty_seed_ownership.
ALTER TABLE professional_management.specialty_seed_ownership
    VALIDATE CONSTRAINT fk_specialty_seed_ownership_specialty;