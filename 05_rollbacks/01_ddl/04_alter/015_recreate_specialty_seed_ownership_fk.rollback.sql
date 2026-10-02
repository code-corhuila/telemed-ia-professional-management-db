-- Restores the constraint to the state it had after changeset 005.
-- Uses the same expand/contract pattern as the forward migration so
-- the rollback does not reintroduce the ACCESS EXCLUSIVE full-table
-- scan that ADD CONSTRAINT without NOT VALID would take:
--   1. DROP takes ACCESS EXCLUSIVE for a catalog update (brief).
--   2. ADD ... NOT VALID takes SHARE UPDATE EXCLUSIVE.
--   3. VALIDATE CONSTRAINT takes SHARE UPDATE EXCLUSIVE.
ALTER TABLE professional_management.specialty_seed_ownership
    DROP CONSTRAINT IF EXISTS fk_specialty_seed_ownership_specialty;
ALTER TABLE professional_management.specialty_seed_ownership
    ADD CONSTRAINT fk_specialty_seed_ownership_specialty
    FOREIGN KEY (specialty_id)
    REFERENCES professional_management.specialty (id)
    ON DELETE CASCADE
    NOT VALID;
ALTER TABLE professional_management.specialty_seed_ownership
    VALIDATE CONSTRAINT fk_specialty_seed_ownership_specialty;
