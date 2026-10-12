-- Restores the index to the state changeset ddl-indexes-001 left it.
-- CONCURRENTLY is used on both sides for symmetry with the forward
-- migration.
--
-- Note on the brief window: between the DROP INDEX CONCURRENTLY and the
-- CREATE INDEX CONCURRENTLY, the specialty_id column has no index. On
-- this table (7 seed rows) the gap is milliseconds and harmless. On a
-- table with real volume, the correct pattern would be to create a
-- shadow index with a new name, then RENAME it and drop the old one in
-- a separate changeset. That is deferred until the table grows.
DROP INDEX CONCURRENTLY IF EXISTS
    professional_management.idx_specialty_seed_ownership_specialty_id;
CREATE INDEX CONCURRENTLY idx_specialty_seed_ownership_specialty_id
    ON professional_management.specialty_seed_ownership (specialty_id);
