-- Historical changeset: originally moved the domain tables from public to
-- professional_management. After the schema-qualification refactor of
-- changesets 001, 001a, 002, 003, 004, 005 and 006, the tables are created
-- directly in professional_management, so this migration has nothing to do.
--
-- Kept as a changeset (not deleted) because it is already applied in qa;
-- removing it would break Liquibase's history.
SELECT 1;
