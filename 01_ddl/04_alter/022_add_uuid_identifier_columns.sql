-- DEC-006 (telemed-ia-docs, 09-microservices/services/04-professional-service/
-- decisions.md), expand half: identifiers become UUID, as Anexo C and the shared
-- contract require. The UUID columns are added next to the bigint ones and
-- filled; ddl-alter-024 swaps them in.
--
-- Each bigint n maps to 00000000-0000-0000-0000-<n as 12 hex digits>. The
-- mapping is reversible, so the rollback of ddl-alter-024 restores the original
-- numbers, and each idempotency key keeps pointing at its professional. It
-- covers values below 2^48, which the guard checks before anything changes.
DO $guard$
BEGIN
    IF EXISTS (SELECT 1 FROM professional_management.professional
               WHERE id NOT BETWEEN 0 AND 281474976710655
                  OR identity_user_id NOT BETWEEN 0 AND 281474976710655) THEN
        RAISE EXCEPTION 'ddl-alter-022 refused: an identifier does not fit the 48-bit UUID mapping.';
    END IF;
END
$guard$;

ALTER TABLE professional_management.professional
    ADD COLUMN id_uuid UUID,
    ADD COLUMN identity_user_id_uuid UUID;

UPDATE professional_management.professional
SET id_uuid = ('00000000-0000-0000-0000-' || lpad(to_hex(id), 12, '0'))::uuid,
    identity_user_id_uuid = ('00000000-0000-0000-0000-' || lpad(to_hex(identity_user_id), 12, '0'))::uuid;

ALTER TABLE professional_management.idempotency_key
    ADD COLUMN professional_id_uuid UUID;

UPDATE professional_management.idempotency_key
SET professional_id_uuid = ('00000000-0000-0000-0000-' || lpad(to_hex(professional_id), 12, '0'))::uuid;
