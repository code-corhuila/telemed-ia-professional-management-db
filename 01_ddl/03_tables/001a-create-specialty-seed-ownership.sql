--liquibase formatted sql

--changeset telemed:001a-create-specialty-seed-ownership
--validCheckSum: 9:1456206b819fb703f2dba8f0463a0f9d
CREATE TABLE professional_management.specialty_seed_ownership (
    changeset_id TEXT CONSTRAINT nn_specialty_seed_ownership_changeset_id NOT NULL,
    specialty_id BIGINT CONSTRAINT nn_specialty_seed_ownership_specialty_id NOT NULL,
    CONSTRAINT pk_specialty_seed_ownership PRIMARY KEY (changeset_id, specialty_id),
    CONSTRAINT fk_specialty_seed_ownership_specialty
        FOREIGN KEY (specialty_id) REFERENCES professional_management.specialties (id)
);

--rollback DROP TABLE professional_management.specialty_seed_ownership;
