REVOKE SELECT, INSERT, UPDATE, DELETE ON professional_management.idempotency_key FROM professional_management_writer;
REVOKE SELECT ON professional_management.idempotency_key FROM professional_management_reader;
