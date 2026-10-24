-- DEC-006, contract half: the UUID columns filled by ddl-alter-022 replace the
-- bigint ones under the same names and constraint names. Dropping the bigint
-- columns also drops professionals_id_seq and idx_idempotency_key_professional_id;
-- the UUID index of ddl-alter-023 takes that name. New professionals get a
-- generated UUID. The foreign key is added NOT VALID and validated by
-- ddl-alter-025, so no full-table scan runs under ACCESS EXCLUSIVE.
ALTER TABLE professional_management.idempotency_key
    DROP CONSTRAINT fk_idempotency_key_professional;

ALTER TABLE professional_management.idempotency_key
    DROP COLUMN professional_id;

ALTER TABLE professional_management.idempotency_key
    RENAME COLUMN professional_id_uuid TO professional_id;

ALTER TABLE professional_management.idempotency_key
    ALTER COLUMN professional_id SET NOT NULL;

ALTER INDEX professional_management.idx_idempotency_key_professional_id_uuid
    RENAME TO idx_idempotency_key_professional_id;

ALTER TABLE professional_management.professional
    DROP CONSTRAINT pk_professionals,
    DROP CONSTRAINT uq_professionals_identity_user_id;

ALTER TABLE professional_management.professional
    DROP COLUMN id,
    DROP COLUMN identity_user_id;

ALTER TABLE professional_management.professional
    RENAME COLUMN id_uuid TO id;

ALTER TABLE professional_management.professional
    RENAME COLUMN identity_user_id_uuid TO identity_user_id;

ALTER TABLE professional_management.professional
    ALTER COLUMN id SET DEFAULT gen_random_uuid(),
    ALTER COLUMN id SET NOT NULL,
    ALTER COLUMN identity_user_id SET NOT NULL;

ALTER TABLE professional_management.professional
    ADD CONSTRAINT pk_professionals PRIMARY KEY (id),
    ADD CONSTRAINT uq_professionals_identity_user_id UNIQUE (identity_user_id);

ALTER TABLE professional_management.idempotency_key
    ADD CONSTRAINT fk_idempotency_key_professional
    FOREIGN KEY (professional_id)
    REFERENCES professional_management.professional (id)
    ON DELETE CASCADE
    NOT VALID;
