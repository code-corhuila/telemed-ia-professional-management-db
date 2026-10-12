--liquibase formatted sql

--changeset telemed:004-seed-additional-specialties splitStatements:false rollbackSplitStatements:false
--validCheckSum: 9:3df6ef3fc67dc17d4114f63e16325e7a
--validCheckSum: 9:3dd748afe4605bdc5fde90251a1bbcda
WITH inserted_specialties AS (
    INSERT INTO professional_management.specialties (name, description)
    VALUES
        ('Neurología', 'Atención de enfermedades y trastornos del sistema nervioso.'),
        ('Ginecología', 'Atención de la salud del sistema reproductivo femenino.'),
        ('Ortopedia', 'Atención de enfermedades y lesiones del sistema musculoesquelético.')
    ON CONFLICT (name) DO NOTHING
    RETURNING id
)
INSERT INTO professional_management.specialty_seed_ownership (changeset_id, specialty_id)
SELECT '004-seed-additional-specialties', id
FROM inserted_specialties;

--rollback DO $rollback$
--rollback BEGIN
--rollback     IF to_regclass('professional_management.specialty_seed_ownership') IS NOT NULL THEN
--rollback         WITH removed_ownership AS (
--rollback             DELETE FROM professional_management.specialty_seed_ownership
--rollback             WHERE changeset_id = '004-seed-additional-specialties'
--rollback             RETURNING specialty_id
--rollback         )
--rollback         DELETE FROM professional_management.specialties s
--rollback         USING removed_ownership o
--rollback         WHERE s.id = o.specialty_id;
--rollback     END IF;
--rollback END;
--rollback $rollback$;
