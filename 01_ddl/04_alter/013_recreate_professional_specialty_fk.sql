-- Anexo A rule 2 requires foreign keys to be added from 04_alter, not declared
-- inside the CREATE TABLE of 03_tables. Changeset 003 is frozen and declares
-- fk_professionals_specialty inline, so the constraint is dropped and re-added
-- here. The resulting definition is byte-for-byte equivalent to the one created
-- by 003, except that it now points at the renamed professional_management.specialty
-- table (ddl-alter-012) instead of the historical specialties table.
--
-- ON DELETE RESTRICT is preserved: deleting a specialty that a professional
-- references must still be rejected, and must never cascade to professionals.
ALTER TABLE professional_management.professional
    DROP CONSTRAINT fk_professionals_specialty;
ALTER TABLE professional_management.professional
    ADD CONSTRAINT fk_professionals_specialty
    FOREIGN KEY (specialty_id)
    REFERENCES professional_management.specialty (id)
    ON DELETE RESTRICT;
