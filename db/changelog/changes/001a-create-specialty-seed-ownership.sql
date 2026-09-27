--liquibase formatted sql

--changeset telemed:001a-create-specialty-seed-ownership
CREATE TABLE specialty_seed_ownership (
    changeset_id TEXT CONSTRAINT nn_specialty_seed_ownership_changeset_id NOT NULL,
    specialty_id BIGINT CONSTRAINT nn_specialty_seed_ownership_specialty_id NOT NULL,
    CONSTRAINT pk_specialty_seed_ownership PRIMARY KEY (changeset_id, specialty_id),
    CONSTRAINT fk_specialty_seed_ownership_specialty
        FOREIGN KEY (specialty_id) REFERENCES specialties (id)
);

--rollback DROP TABLE specialty_seed_ownership;
