-- Locking note: ADD CONSTRAINT ... CHECK without NOT VALID takes an ACCESS
-- EXCLUSIVE lock and scans every existing row before the transaction commits.
-- At this stage the domain tables are small and the lock window is on the
-- order of milliseconds. If the tables grow, split each CHECK into two
-- changesets: NOT VALID first, then VALIDATE CONSTRAINT in a separate
-- changeset, so the scan does not block concurrent traffic.


-- The standard requires unconstrained text columns with an explicit CHECK of
-- the maximum length instead of a typed VARCHAR(n). Widening to text is
-- lossless for every stored value because the current data already satisfies
-- the lengths the CHECKs below re-encode.
ALTER TABLE professional_management.specialties
    ALTER COLUMN name TYPE text,
    ALTER COLUMN description TYPE text;

ALTER TABLE professional_management.specialties
    ADD CONSTRAINT chk_specialties_name_length CHECK (char_length(name) <= 100),
    ADD CONSTRAINT chk_specialties_description_length CHECK (description IS NULL OR char_length(description) <= 500);

-- Changing the status column type alone leaves the stored default expression
-- as 'ACTIVE'::character varying, so the default is restated as a text
-- constant to keep it consistent with the new column type.
ALTER TABLE professional_management.professionals
    ALTER COLUMN license_number TYPE text,
    ALTER COLUMN professional_type TYPE text,
    ALTER COLUMN status TYPE text,
    ALTER COLUMN status SET DEFAULT 'ACTIVE'::text;

ALTER TABLE professional_management.professionals
    ADD CONSTRAINT chk_professionals_license_number_length CHECK (char_length(license_number) <= 80),
    ADD CONSTRAINT chk_professionals_professional_type_length CHECK (professional_type IS NULL OR char_length(professional_type) <= 30),
    ADD CONSTRAINT chk_professionals_status_length CHECK (char_length(status) <= 20);
