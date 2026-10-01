-- Anexo A rule 14: an index on a populated table is created with
-- CREATE INDEX CONCURRENTLY, in its own migration. The index
-- idx_specialty_seed_ownership_specialty_id was originally created by
-- ddl-indexes-001 without CONCURRENTLY. The table has rows after the
-- seeds (4 + 3 ownership rows), so it is re-created here with
-- CONCURRENTLY. The changeset is registered with
-- runInTransaction: false, which is mandatory for CONCURRENTLY.
DROP INDEX CONCURRENTLY IF EXISTS
    professional_management.idx_specialty_seed_ownership_specialty_id;
CREATE INDEX CONCURRENTLY idx_specialty_seed_ownership_specialty_id
    ON professional_management.specialty_seed_ownership (specialty_id);