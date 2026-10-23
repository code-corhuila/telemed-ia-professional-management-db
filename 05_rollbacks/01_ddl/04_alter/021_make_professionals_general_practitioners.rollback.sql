-- Restores the two-value CHECK, the nullable column and the absence of a
-- default, as left by ddl-alter-008. Rows keep GENERAL_PRACTITIONER: which ones
-- were NULL or SPECIALIST before DEC-005 is not recorded.
ALTER TABLE professional_management.professional
    DROP CONSTRAINT chk_professionals_professional_type;

ALTER TABLE professional_management.professional
    ADD CONSTRAINT chk_professionals_professional_type
    CHECK (professional_type IN ('GENERAL_PRACTITIONER', 'SPECIALIST'));

ALTER TABLE professional_management.professional
    ALTER COLUMN professional_type DROP NOT NULL;

ALTER TABLE professional_management.professional
    ALTER COLUMN professional_type DROP DEFAULT;
