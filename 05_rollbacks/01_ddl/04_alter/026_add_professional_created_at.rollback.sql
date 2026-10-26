-- Removes the registration time added by ddl-alter-026. ddl-alter-027 is
-- rolled back first, so no index depends on the column.
ALTER TABLE professional_management.professional
    DROP COLUMN created_at;
