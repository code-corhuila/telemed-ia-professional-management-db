--liquibase formatted sql

--changeset telemed:004-seed-additional-specialties splitStatements:false rollbackSplitStatements:false
--validCheckSum: 9:3df6ef3fc67dc17d4114f63e16325e7a
WITH inserted_specialties AS (
    INSERT INTO specialties (name, description)
    VALUES
        ('Neurología', 'Atención de enfermedades y trastornos del sistema nervioso.'),
        ('Ginecología', 'Atención de la salud del sistema reproductivo femenino.'),
        ('Ortopedia', 'Atención de enfermedades y lesiones del sistema musculoesquelético.')
    ON CONFLICT (name) DO NOTHING
    RETURNING id
)
INSERT INTO specialty_seed_ownership (changeset_id, specialty_id)
SELECT '004-seed-additional-specialties', id
FROM inserted_specialties;

--rollback DO $rollback$
--rollback BEGIN
--rollback     IF to_regclass('public.specialty_seed_ownership') IS NOT NULL THEN
--rollback         WITH removed_ownership AS (
--rollback             DELETE FROM specialty_seed_ownership
--rollback             WHERE changeset_id = '004-seed-additional-specialties'
--rollback             RETURNING specialty_id
--rollback         )
--rollback         DELETE FROM specialties s
--rollback         USING removed_ownership o
--rollback         WHERE s.id = o.specialty_id;
--rollback     END IF;
--rollback END;
--rollback $rollback$;
