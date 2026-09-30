--liquibase formatted sql

--changeset telemed:006-add-professional-type-and-status rollbackSplitStatements:false
ALTER TABLE professionals
    ADD COLUMN professional_type VARCHAR(30),
    ADD COLUMN status VARCHAR(20) DEFAULT 'ACTIVE';

ALTER TABLE professionals
    ALTER COLUMN status SET NOT NULL,
    ADD CONSTRAINT ck_professionals_professional_type
        CHECK (professional_type IN ('GENERAL_PRACTITIONER', 'SPECIALIST')),
    ADD CONSTRAINT ck_professionals_status
        CHECK (status IN ('ACTIVE', 'INACTIVE'));

CREATE INDEX idx_professionals_status
    ON professionals (status);

--rollback DO $rollback$ BEGIN IF EXISTS (SELECT 1 FROM professionals) THEN RAISE EXCEPTION 'Rollback 006 refused: professionals contains records; removing professional_type and status could lose lifecycle data.'; END IF; DROP INDEX idx_professionals_status; ALTER TABLE professionals DROP COLUMN status, DROP COLUMN professional_type; END; $rollback$;
