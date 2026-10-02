-- Anexo A rule 14: an index on a populated table is created with
-- CREATE INDEX CONCURRENTLY, in its own migration. The index
-- idx_specialty_seed_ownership_specialty_id was originally created by
-- ddl-indexes-001 without CONCURRENTLY. The table has rows after the
-- seeds (4 + 3 ownership rows), so it is re-created here with
-- CONCURRENTLY. The changeset is registered with
-- runInTransaction: false, which is mandatory for CONCURRENTLY.
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
