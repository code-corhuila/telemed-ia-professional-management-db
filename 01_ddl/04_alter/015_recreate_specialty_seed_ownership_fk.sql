-- Anexo A rule 2: foreign keys are added from 04_alter, not inline in
-- 03_tables. Changeset 001a is frozen and declares
-- fk_specialty_seed_ownership_specialty inline, so the constraint is
-- dropped and re-added here with the same definition that changeset
-- 005-cascade-deleted-specialty-ownership later applied (ON DELETE
-- CASCADE). Re-created with NOT VALID to avoid ACCESS EXCLUSIVE; the
-- validation runs in ddl-alter-016.
ALTER TABLE professional_management.specialty_seed_ownership
    DROP CONSTRAINT fk_specialty_seed_ownership_specialty;
ALTER TABLE professional_management.specialty_seed_ownership
    ADD CONSTRAINT fk_specialty_seed_ownership_specialty
    FOREIGN KEY (specialty_id)
    REFERENCES professional_management.specialty (id)
    ON DELETE CASCADE
    NOT VALID;