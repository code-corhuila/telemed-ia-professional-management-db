--liquibase formatted sql

--changeset telemed:006-add-professional-type-and-status rollbackSplitStatements:false
--validCheckSum: 9:1f2c039c7f0d5fa01f20f0139a48479b
ALTER TABLE professional_management.professionals
    ADD COLUMN professional_type VARCHAR(30),
    ADD COLUMN status VARCHAR(20) DEFAULT 'ACTIVE';

ALTER TABLE professional_management.professionals
    ALTER COLUMN status SET NOT NULL,
    ADD CONSTRAINT ck_professionals_professional_type
        CHECK (professional_type IN ('GENERAL_PRACTITIONER', 'SPECIALIST')),
    ADD CONSTRAINT ck_professionals_status
        CHECK (status IN ('ACTIVE', 'INACTIVE'));

CREATE INDEX idx_professionals_status
    ON professional_management.professionals (status);

--rollback DO $rollback$ BEGIN IF EXISTS (SELECT 1 FROM professional_management.professionals) THEN RAISE EXCEPTION 'Rollback 006 refused: professionals contains records; removing professional_type and status could lose lifecycle data.'; END IF; DROP INDEX professional_management.idx_professionals_status; ALTER TABLE professional_management.professionals DROP COLUMN status, DROP COLUMN professional_type; END; $rollback$;
