DO $rollback$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'professional_management'
    ) THEN
        RAISE EXCEPTION 'Rollback of schema creation refused: professional_management still contains objects.';
    END IF;
    DROP SCHEMA IF EXISTS professional_management;
END;
$rollback$;
