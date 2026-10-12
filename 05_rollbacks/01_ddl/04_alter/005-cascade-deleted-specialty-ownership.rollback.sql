-- External mirror of the inline rollback declared in
-- 01_ddl/04_alter/005-cascade-deleted-specialty-ownership.sql.
ALTER TABLE professional_management.specialty_seed_ownership
    DROP CONSTRAINT IF EXISTS fk_specialty_seed_ownership_specialty;
ALTER TABLE professional_management.specialty_seed_ownership
    ADD CONSTRAINT fk_specialty_seed_ownership_specialty
    FOREIGN KEY (specialty_id) REFERENCES professional_management.specialties (id);
