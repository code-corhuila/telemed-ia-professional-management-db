-- Anexo A rule 2 requires foreign keys to be added from 04_alter, not
-- declared inside the CREATE TABLE of 03_tables. Changeset 003 is frozen
-- and declares fk_professionals_specialty inline, so the constraint is
-- dropped and re-added here.
--
-- Two improvements over the historical definition:
--   1. The constraint is renamed to `fk_professional_specialty` so its
--      name matches the singular table created by ddl-alter-012. The
--      historical pk_/uq_/chk_ names on `professional` stay plural because
--      they are frozen in changesets 003 and 006 and Anexo A rule 1
--      applies to table names, not constraint names.
--   2. The new constraint is added with NOT VALID, which takes only a
--      SHARE UPDATE EXCLUSIVE lock and does not scan the table. A separate
--      changeset (ddl-alter-014) runs VALIDATE CONSTRAINT, which also
--      uses SHARE UPDATE EXCLUSIVE and does not block concurrent reads or
--      writes. Re-adding the FK with plain ADD CONSTRAINT would take
--      ACCESS EXCLUSIVE for the duration of the full-table validation.
--
-- ON DELETE RESTRICT is preserved: deleting a specialty that a
-- professional references must still be rejected, and must never cascade
-- to professionals.
ALTER TABLE professional_management.professional
    DROP CONSTRAINT fk_professionals_specialty;
ALTER TABLE professional_management.professional
    ADD CONSTRAINT fk_professional_specialty
    FOREIGN KEY (specialty_id)
    REFERENCES professional_management.specialty (id)
    ON DELETE RESTRICT
    NOT VALID;
