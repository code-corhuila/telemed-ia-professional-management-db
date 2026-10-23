-- Re-creates the catalog and its ledger exactly as they stood after
-- ddl-indexes-003: names, constraints, the ON DELETE CASCADE ledger foreign key,
-- the ledger index and the specialties_id_seq sequence. The seven seeds are
-- inserted again with their ledger rows, so the rollbacks of
-- 004-seed-additional-specialties and 002-seed-specialties still remove exactly
-- the rows they own. Specialties created by an administrator before DEC-005 are
-- not recoverable.
--
-- The tables are created by the role that applied 001-grants, so its default
-- privileges grant them to the reader and writer roles again.
CREATE SEQUENCE professional_management.specialties_id_seq;

CREATE TABLE professional_management.specialty (
    id BIGINT NOT NULL DEFAULT nextval('professional_management.specialties_id_seq'),
    name TEXT NOT NULL,
    description TEXT,
    CONSTRAINT pk_specialties PRIMARY KEY (id),
    CONSTRAINT uq_specialties_name UNIQUE (name),
    CONSTRAINT chk_specialties_name_length CHECK (char_length(name) <= 100),
    CONSTRAINT chk_specialties_description_length CHECK (description IS NULL OR char_length(description) <= 500)
);

ALTER SEQUENCE professional_management.specialties_id_seq OWNED BY professional_management.specialty.id;

CREATE TABLE professional_management.specialty_seed_ownership (
    changeset_id TEXT NOT NULL,
    specialty_id BIGINT NOT NULL,
    CONSTRAINT pk_specialty_seed_ownership PRIMARY KEY (changeset_id, specialty_id),
    CONSTRAINT fk_specialty_seed_ownership_specialty
        FOREIGN KEY (specialty_id)
        REFERENCES professional_management.specialty (id)
        ON DELETE CASCADE
);

CREATE INDEX idx_specialty_seed_ownership_specialty_id
    ON professional_management.specialty_seed_ownership (specialty_id);

WITH inserted_specialties AS (
    INSERT INTO professional_management.specialty (name, description)
    VALUES
        ('Medicina General', 'Atención médica general y orientación inicial.'),
        ('Pediatría', 'Atención integral de población pediátrica.'),
        ('Dermatología', 'Atención de enfermedades de piel, cabello y uñas.'),
        ('Cardiología', 'Atención de enfermedades cardiovasculares.')
    RETURNING id
)
INSERT INTO professional_management.specialty_seed_ownership (changeset_id, specialty_id)
SELECT '002-seed-specialties', id FROM inserted_specialties;

WITH inserted_specialties AS (
    INSERT INTO professional_management.specialty (name, description)
    VALUES
        ('Neurología', 'Atención de enfermedades y trastornos del sistema nervioso.'),
        ('Ginecología', 'Atención de la salud del sistema reproductivo femenino.'),
        ('Ortopedia', 'Atención de enfermedades y lesiones del sistema musculoesquelético.')
    RETURNING id
)
INSERT INTO professional_management.specialty_seed_ownership (changeset_id, specialty_id)
SELECT '004-seed-additional-specialties', id FROM inserted_specialties;
