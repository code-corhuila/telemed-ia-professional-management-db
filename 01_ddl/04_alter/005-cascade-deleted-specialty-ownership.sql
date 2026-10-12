--liquibase formatted sql

--changeset telemed:005-cascade-deleted-specialty-ownership
--validCheckSum: 9:e34d968646061963b6696c02cc7d6218
ALTER TABLE professional_management.specialty_seed_ownership
    DROP CONSTRAINT fk_specialty_seed_ownership_specialty;
ALTER TABLE professional_management.specialty_seed_ownership
    ADD CONSTRAINT fk_specialty_seed_ownership_specialty
    FOREIGN KEY (specialty_id) REFERENCES professional_management.specialties (id) ON DELETE CASCADE;

--rollback ALTER TABLE professional_management.specialty_seed_ownership DROP CONSTRAINT fk_specialty_seed_ownership_specialty;
--rollback ALTER TABLE professional_management.specialty_seed_ownership ADD CONSTRAINT fk_specialty_seed_ownership_specialty FOREIGN KEY (specialty_id) REFERENCES professional_management.specialties (id);
