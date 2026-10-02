-- Anexo A rule 1 requires table names in the singular. `specialties` and
-- `professionals` were created in the plural by the historical changesets 001
-- and 003, which are frozen (database standard, rule 12). Renaming the tables
-- is therefore a new migration instead of an edit to the applied changesets.
-- `specialty_seed_ownership` and `idempotency_key` already follow the rule and
-- are left untouched.
--
-- Renaming a table does not rename its indexes or constraints, so the objects
-- declared by 001, 003, 006, and 004 keep their historical names here. The
-- indexes are re-created with conforming names by ddl-indexes-002, and the
-- fk_professionals_specialty foreign key is re-declared by ddl-alter-013.
ALTER TABLE professional_management.specialties RENAME TO specialty;
ALTER TABLE professional_management.professionals RENAME TO professional;
