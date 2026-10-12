-- Restores the historical constraint name fk_professionals_specialty
-- on the now-singular `professional` table. The constraint is re-added
-- with the same definition it had after changeset 003, so rolling back
-- ddl-alter-013 leaves the schema in the state that ddl-alter-012
-- expects.
ALTER TABLE professional_management.professional
    DROP CONSTRAINT IF EXISTS fk_professional_specialty;
ALTER TABLE professional_management.professional
    ADD CONSTRAINT fk_professionals_specialty
    FOREIGN KEY (specialty_id)
    REFERENCES professional_management.specialty (id)
    ON DELETE RESTRICT;
