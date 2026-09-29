--liquibase formatted sql

--changeset telemed:006-add-professional-type-and-status
ALTER TABLE professionals
    ADD COLUMN professional_type VARCHAR(30),
    ADD COLUMN status VARCHAR(20);

UPDATE professionals
SET professional_type = 'GENERAL_PRACTITIONER',
    status = 'ACTIVE';

ALTER TABLE professionals
    ALTER COLUMN professional_type SET NOT NULL,
    ALTER COLUMN status SET NOT NULL,
    ADD CONSTRAINT ck_professionals_professional_type
        CHECK (professional_type IN ('GENERAL_PRACTITIONER', 'SPECIALIST')),
    ADD CONSTRAINT ck_professionals_status
        CHECK (status IN ('ACTIVE', 'INACTIVE'));

--rollback ALTER TABLE professionals DROP COLUMN status;
--rollback ALTER TABLE professionals DROP COLUMN professional_type;
