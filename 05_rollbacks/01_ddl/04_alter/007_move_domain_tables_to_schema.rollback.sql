-- Symmetric with the forward change: since 007 is now a no-op, the rollback
-- is also a no-op. Moving the tables back to public would break the rollback
-- of changesets 001-006, which expect the tables in professional_management.
SELECT 1;
