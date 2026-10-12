-- External mirror of the inline rollback declared in
-- 01_ddl/04_alter/006-add-professional-type-and-status.sql. The inline
-- version refuses to run when professionals has records; this file
-- mirrors that guard.
DO $rollback$
BEGIN
    IF EXISTS (SELECT 1 FROM professional_management.professionals) THEN
        RAISE EXCEPTION 'Rollback 006 refused: professionals contains records.';
    END IF;
    DROP INDEX IF EXISTS professional_management.idx_professionals_status;
    ALTER TABLE professional_management.professionals
        DROP COLUMN IF EXISTS status,
        DROP COLUMN IF EXISTS professional_type;
END;
$rollback$;
