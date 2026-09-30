CREATE TABLE professional_management.idempotency_key (
    key             TEXT        CONSTRAINT chk_idempotency_key_length
                                CHECK (length(key) BETWEEN 8 AND 128)
                                NOT NULL,
    professional_id BIGINT      NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_idempotency_key PRIMARY KEY (key),
    CONSTRAINT fk_idempotency_key_professional
        FOREIGN KEY (professional_id)
        REFERENCES professional_management.professionals (id)
        ON DELETE CASCADE
);

CREATE INDEX idx_idempotency_key_professional_id
    ON professional_management.idempotency_key (professional_id);
