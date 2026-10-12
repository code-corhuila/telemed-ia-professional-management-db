--liquibase formatted sql

--changeset telemed:003-create-professionals
--validCheckSum: 9:313730182926c79dd61ea3f3fc200924
CREATE TABLE professional_management.professionals (
    id BIGSERIAL CONSTRAINT pk_professionals PRIMARY KEY,
    identity_user_id BIGINT CONSTRAINT uq_professionals_identity_user_id NOT NULL UNIQUE,
    license_number VARCHAR(80) CONSTRAINT uq_professionals_license_number NOT NULL UNIQUE,
    specialty_id BIGINT CONSTRAINT nn_professionals_specialty_id NOT NULL,
    years_experience INTEGER CONSTRAINT nn_professionals_years_experience NOT NULL DEFAULT 0,
    CONSTRAINT ck_professionals_years_experience_nonnegative CHECK (years_experience >= 0),
    CONSTRAINT fk_professionals_specialty
        FOREIGN KEY (specialty_id) REFERENCES professional_management.specialties (id) ON DELETE RESTRICT
);

CREATE INDEX idx_professionals_specialty_id
    ON professional_management.professionals (specialty_id);

--rollback DROP TABLE professional_management.professionals;
