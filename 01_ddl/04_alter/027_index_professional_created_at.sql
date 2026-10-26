-- DEC-010: serves GET / ordered by created_at DESC, id DESC; id breaks ties so
-- the order is stable between pages. The table may hold rows, so the index is
-- built CONCURRENTLY (Anexo A rule 14) and ddl-alter-027 runs with
-- runInTransaction: false.
CREATE INDEX CONCURRENTLY idx_professional_created_at_id
    ON professional_management.professional (created_at DESC, id DESC);
