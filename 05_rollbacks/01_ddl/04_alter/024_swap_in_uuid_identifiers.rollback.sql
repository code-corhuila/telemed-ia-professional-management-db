-- Puts the bigint identifiers back, recovered from the reversible mapping of
-- ddl-alter-022, and moves the UUID columns back to their expand names, as they
-- stood after ddl-alter-023. professionals_id_seq is re-created and continues
-- after the highest restored id; the validated foreign key and the constraint
-- names are those left by ddl-alter-018. The bigint idempotency index is
-- re-created by the rollback of ddl-alter-023.
--
-- The guard in 024_swap_in_uuid_identifiers.rollback-guard.sql runs first.

ALTER TABLE professional_management.idempotency_key
    DROP CONSTRAINT fk_idempotency_key_professional;

ALTER INDEX professional_management.idx_idempotency_key_professional_id
    RENAME TO idx_idempotency_key_professional_id_uuid;

ALTER TABLE professional_management.idempotency_key
    RENAME COLUMN professional_id TO professional_id_uuid;

ALTER TABLE professional_management.idempotency_key
    ALTER COLUMN professional_id_uuid DROP NOT NULL,
    ADD COLUMN professional_id BIGINT;

UPDATE professional_management.idempotency_key
SET professional_id = ('x' || right(replace(professional_id_uuid::text, '-', ''), 12))::bit(48)::bigint;

ALTER TABLE professional_management.idempotency_key
    ALTER COLUMN professional_id SET NOT NULL;

ALTER TABLE professional_management.professional
    DROP CONSTRAINT pk_professionals,
    DROP CONSTRAINT uq_professionals_identity_user_id;

ALTER TABLE professional_management.professional
    RENAME COLUMN id TO id_uuid;

ALTER TABLE professional_management.professional
    RENAME COLUMN identity_user_id TO identity_user_id_uuid;

ALTER TABLE professional_management.professional
    ALTER COLUMN id_uuid DROP DEFAULT,
    ALTER COLUMN id_uuid DROP NOT NULL,
    ALTER COLUMN identity_user_id_uuid DROP NOT NULL,
    ADD COLUMN id BIGINT,
    ADD COLUMN identity_user_id BIGINT;

UPDATE professional_management.professional
SET id = ('x' || right(replace(id_uuid::text, '-', ''), 12))::bit(48)::bigint,
    identity_user_id = ('x' || right(replace(identity_user_id_uuid::text, '-', ''), 12))::bit(48)::bigint;

CREATE SEQUENCE professional_management.professionals_id_seq
    OWNED BY professional_management.professional.id;

SELECT setval('professional_management.professionals_id_seq',
              COALESCE((SELECT max(id) FROM professional_management.professional), 0) + 1,
              false);

ALTER TABLE professional_management.professional
    ALTER COLUMN id SET DEFAULT nextval('professional_management.professionals_id_seq'),
    ALTER COLUMN id SET NOT NULL,
    ALTER COLUMN identity_user_id SET NOT NULL;

ALTER TABLE professional_management.professional
    ADD CONSTRAINT pk_professionals PRIMARY KEY (id),
    ADD CONSTRAINT uq_professionals_identity_user_id UNIQUE (identity_user_id);

ALTER TABLE professional_management.idempotency_key
    ADD CONSTRAINT fk_idempotency_key_professional
    FOREIGN KEY (professional_id)
    REFERENCES professional_management.professional (id)
    ON DELETE CASCADE;
