--liquibase formatted sql

--changeset telemed:002-seed-specialties splitStatements:false rollbackSplitStatements:false
--validCheckSum: 9:f5719d18ef7771621c69be4f04fb4e73
WITH inserted_specialties AS (
    INSERT INTO specialties (name, description)
    VALUES
        ('Medicina General', 'Atención médica general y orientación inicial.'),
        ('Pediatría', 'Atención integral de población pediátrica.'),
        ('Dermatología', 'Atención de enfermedades de piel, cabello y uñas.'),
        ('Cardiología', 'Atención de enfermedades cardiovasculares.')
    ON CONFLICT (name) DO NOTHING
    RETURNING id
)
INSERT INTO specialty_seed_ownership (changeset_id, specialty_id)
SELECT '002-seed-specialties', id
FROM inserted_specialties;

--rollback DO $rollback$
--rollback BEGIN
--rollback     IF to_regclass('public.specialty_seed_ownership') IS NOT NULL THEN
--rollback         WITH removed_ownership AS (
--rollback             DELETE FROM specialty_seed_ownership
--rollback             WHERE changeset_id = '002-seed-specialties'
--rollback             RETURNING specialty_id
--rollback         )
--rollback         DELETE FROM specialties s
--rollback         USING removed_ownership o
--rollback         WHERE s.id = o.specialty_id;
--rollback     END IF;
--rollback END;
--rollback $rollback$;
