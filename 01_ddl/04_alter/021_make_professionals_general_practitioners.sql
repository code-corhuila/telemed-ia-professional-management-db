-- DEC-005: every professional is a general practitioner. professional_type stays
-- in the profile with GENERAL_PRACTITIONER as its only value and its default, so
-- an insert that omits it registers a general practitioner.
--
-- The backfill and the constraints run in one transaction: NOT NULL and the new
-- CHECK only hold once every row, including the ones left NULL by changeset 006
-- and any SPECIALIST, is a general practitioner.
UPDATE professional_management.professional
SET professional_type = 'GENERAL_PRACTITIONER'
WHERE professional_type IS DISTINCT FROM 'GENERAL_PRACTITIONER';

ALTER TABLE professional_management.professional
    ALTER COLUMN professional_type SET DEFAULT 'GENERAL_PRACTITIONER';

ALTER TABLE professional_management.professional
    ALTER COLUMN professional_type SET NOT NULL;

ALTER TABLE professional_management.professional
    DROP CONSTRAINT chk_professionals_professional_type;

ALTER TABLE professional_management.professional
    ADD CONSTRAINT chk_professionals_professional_type
    CHECK (professional_type = 'GENERAL_PRACTITIONER');
