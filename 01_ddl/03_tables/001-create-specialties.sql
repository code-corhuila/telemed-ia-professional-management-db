--liquibase formatted sql

--changeset telemed:001-create-specialties
--validCheckSum: 9:a9c684eb3af7a9b111c4e180f6da3804
CREATE TABLE professional_management.specialties (
    id BIGSERIAL CONSTRAINT pk_specialties PRIMARY KEY,
    name VARCHAR(100) CONSTRAINT uq_specialties_name NOT NULL UNIQUE,
    description VARCHAR(500)
);

--rollback DROP TABLE professional_management.specialties;
