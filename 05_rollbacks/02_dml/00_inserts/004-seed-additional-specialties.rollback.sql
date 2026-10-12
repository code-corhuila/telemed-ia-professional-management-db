-- External mirror of the inline rollback declared in
-- 02_dml/00_inserts/004-seed-additional-specialties.sql.
DO $rollback$
BEGIN
    IF to_regclass('professional_management.specialty_seed_ownership') IS NOT NULL THEN
        WITH removed_ownership AS (
            DELETE FROM professional_management.specialty_seed_ownership
            WHERE changeset_id = '004-seed-additional-specialties'
            RETURNING specialty_id
        )
        DELETE FROM professional_management.specialties s
        USING removed_ownership o
        WHERE s.id = o.specialty_id;
    END IF;
END;
$rollback$;
