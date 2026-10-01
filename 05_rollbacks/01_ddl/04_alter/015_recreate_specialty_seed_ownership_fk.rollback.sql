-- Restores the constraint to the state it had after changeset 005.
-- No UNVALIDATE exists in PostgreSQL, so this rollback leaves the
-- constraint as-is if it was already validated; dropping and
-- re-adding it restores the exact FK definition.
ALTER TABLE professional_management.specialty_seed_ownership
    DROP CONSTRAINT fk_specialty_seed_ownership_specialty;
ALTER TABLE professional_management.specialty_seed_ownership
    ADD CONSTRAINT fk_specialty_seed_ownership_specialty
    FOREIGN KEY (specialty_id)
    REFERENCES professional_management.specialty (id)
    ON DELETE CASCADE;