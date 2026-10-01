-- Irreversible: PostgreSQL has no UNVALIDATE CONSTRAINT. The rollback
-- of ddl-alter-014 is documented as a no-op; to fully revert the FK,
-- roll back ddl-alter-013 instead, which drops the constraint.
SELECT 1;
