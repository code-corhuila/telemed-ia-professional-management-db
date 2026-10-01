-- Re-declares fk_professionals_specialty with the definition it must have after
-- ddl-alter-013 applied, so the rollback leaves the same constraint in place.
-- This is a semantic no-op: the forward migration also ends with this exact
-- constraint on the renamed table. It is declared explicitly to satisfy the
-- database standard requirement that every changeset ships a rollback.
ALTER TABLE professional_management.professional
    DROP CONSTRAINT fk_professionals_specialty;
ALTER TABLE professional_management.professional
    ADD CONSTRAINT fk_professionals_specialty
    FOREIGN KEY (specialty_id)
    REFERENCES professional_management.specialty (id)
    ON DELETE RESTRICT;
