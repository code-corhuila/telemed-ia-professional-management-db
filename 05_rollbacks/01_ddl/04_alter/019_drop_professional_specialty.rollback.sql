-- Restores professional.specialty_id as it was after ddl-indexes-002 and
-- ddl-alter-014: NOT NULL, the validated fk_professional_specialty with
-- ON DELETE RESTRICT, and idx_professional_specialty_id. The rollback of
-- ddl-alter-020 runs first and re-creates the seeded catalog, so every existing
-- professional is assigned Medicina General, the only care the platform offered
-- under DEC-005.
--
-- The index is created CONCURRENTLY because professional may hold rows (Anexo A
-- rule 14), which is why ddl-alter-019 is registered with runInTransaction: false.
ALTER TABLE professional_management.professional ADD COLUMN specialty_id BIGINT;

UPDATE professional_management.professional
SET specialty_id = (SELECT id FROM professional_management.specialty WHERE name = 'Medicina General');

ALTER TABLE professional_management.professional ALTER COLUMN specialty_id SET NOT NULL;

ALTER TABLE professional_management.professional
    ADD CONSTRAINT fk_professional_specialty
    FOREIGN KEY (specialty_id)
    REFERENCES professional_management.specialty (id)
    ON DELETE RESTRICT;

CREATE INDEX CONCURRENTLY idx_professional_specialty_id
    ON professional_management.professional (specialty_id);
