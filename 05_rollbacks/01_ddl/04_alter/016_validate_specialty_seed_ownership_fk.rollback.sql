-- Irreversible. PostgreSQL has no UNVALIDATE CONSTRAINT. To fully
-- revert the FK, roll back ddl-alter-015 instead, which drops the
-- constraint.
SELECT 1;