-- Restores the historical plural table names created by changesets 001 and 003.
-- The inverse of ddl-alter-012. Indexes, constraints, and seeds are owned by
-- their own changesets and are not touched here.
ALTER TABLE professional_management.professional RENAME TO professionals;
ALTER TABLE professional_management.specialty RENAME TO specialties;
