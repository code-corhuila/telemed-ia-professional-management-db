-- Drops the expand columns of ddl-alter-022. The bigint identifiers were never
-- changed by it, so nothing else needs restoring.
ALTER TABLE professional_management.idempotency_key
    DROP COLUMN professional_id_uuid;

ALTER TABLE professional_management.professional
    DROP COLUMN identity_user_id_uuid,
    DROP COLUMN id_uuid;
