--liquibase formatted sql

--changeset telemed:001-create-specialties logicalFilePath:changes/001-create-specialties.sql
CREATE TABLE specialties (
    id BIGSERIAL CONSTRAINT pk_specialties PRIMARY KEY,
    name VARCHAR(100) CONSTRAINT uq_specialties_name NOT NULL UNIQUE,
    description VARCHAR(500)
);

--rollback DROP TABLE specialties;
