--liquibase formatted sql

--changeset telemed:002-seed-specialties splitStatements:false rollbackSplitStatements:false
--validCheckSum: 9:f5719d18ef7771621c69be4f04fb4e73
--validCheckSum: 9:099cf6e9aa0594cd801ca9d0308f8d36
WITH inserted_specialties AS (
    INSERT INTO professional_management.specialties (name, description)
    VALUES
        ('Medicina General', 'Atención médica general y orientación inicial.'),
        ('Pediatría', 'Atención integral de población pediátrica.'),
        ('Dermatología', 'Atención de enfermedades de piel, cabello y uñas.'),
        ('Cardiología', 'Atención de enfermedades cardiovasculares.')
    ON CONFLICT (name) DO NOTHING
    RETURNING id
)
INSERT INTO professional_management.specialty_seed_ownership (changeset_id, specialty_id)
SELECT '002-seed-specialties', id
FROM inserted_specialties;

--rollback DO $rollback$
--rollback BEGIN
--rollback     IF to_regclass('professional_management.specialty_seed_ownership') IS NOT NULL THEN
--rollback         WITH removed_ownership AS (
--rollback             DELETE FROM professional_management.specialty_seed_ownership
--rollback             WHERE changeset_id = '002-seed-specialties'
--rollback             RETURNING specialty_id
--rollback         )
--rollback         DELETE FROM professional_management.specialties s
--rollback         USING removed_ownership o
--rollback         WHERE s.id = o.specialty_id;
--rollback     END IF;
--rollback END;
--rollback $rollback$;
