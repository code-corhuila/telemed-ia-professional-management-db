--liquibase formatted sql

--changeset telemed:005-cascade-deleted-specialty-ownership
ALTER TABLE specialty_seed_ownership
    DROP CONSTRAINT fk_specialty_seed_ownership_specialty;
ALTER TABLE specialty_seed_ownership
    ADD CONSTRAINT fk_specialty_seed_ownership_specialty
    FOREIGN KEY (specialty_id) REFERENCES specialties (id) ON DELETE CASCADE;

--rollback ALTER TABLE specialty_seed_ownership DROP CONSTRAINT fk_specialty_seed_ownership_specialty;
--rollback ALTER TABLE specialty_seed_ownership ADD CONSTRAINT fk_specialty_seed_ownership_specialty FOREIGN KEY (specialty_id) REFERENCES specialties (id);
