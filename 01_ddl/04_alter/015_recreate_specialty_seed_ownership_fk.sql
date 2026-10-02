-- Anexo A rule 2: foreign keys are added from 04_alter, not inline in
-- 03_tables. Changeset 001a is frozen and declares
-- fk_specialty_seed_ownership_specialty inline, so the constraint is
-- dropped and re-added here.
--
-- Lock profile:
--   - DROP CONSTRAINT takes ACCESS EXCLUSIVE, but only for a catalog
--     update, so the lock is milliseconds.
--   - ADD CONSTRAINT ... NOT VALID takes only SHARE UPDATE EXCLUSIVE.
--   - VALIDATE CONSTRAINT (in the next changeset) also takes only
--     SHARE UPDATE EXCLUSIVE.
-- The expand/contract split avoids the ACCESS EXCLUSIVE full-table scan
-- that a plain ADD CONSTRAINT would take to validate the FK.
ALTER TABLE professional_management.specialty_seed_ownership
    DROP CONSTRAINT IF EXISTS fk_specialty_seed_ownership_specialty;
ALTER TABLE professional_management.specialty_seed_ownership
    ADD CONSTRAINT fk_specialty_seed_ownership_specialty
    FOREIGN KEY (specialty_id)
    REFERENCES professional_management.specialty (id)
    ON DELETE CASCADE
    NOT VALID;
