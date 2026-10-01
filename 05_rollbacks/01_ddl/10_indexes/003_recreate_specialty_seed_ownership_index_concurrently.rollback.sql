-- Restores the index to the state changeset ddl-indexes-001 left it.
-- CONCURRENTLY is used on both sides for symmetry with the forward
-- migration.
DROP INDEX CONCURRENTLY IF EXISTS
    professional_management.idx_specialty_seed_ownership_specialty_id;
CREATE INDEX CONCURRENTLY idx_specialty_seed_ownership_specialty_id
    ON professional_management.specialty_seed_ownership (specialty_id);