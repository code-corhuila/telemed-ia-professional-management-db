-- DEC-010: the list goes from the most recently registered profile to the
-- oldest (Anexo C, Listados), so professional records when it was registered.
-- The column is added without a default so the backfill can choose the value:
-- a profile registered through POST /admin/register takes the creation time of
-- its Idempotency-Key; any other existing row takes the migration time. The
-- default and NOT NULL are set after the backfill, in the same transaction.
ALTER TABLE professional_management.professional
    ADD COLUMN created_at TIMESTAMPTZ;

UPDATE professional_management.professional p
SET created_at = COALESCE(
    (SELECT min(k.created_at)
     FROM professional_management.idempotency_key k
     WHERE k.professional_id = p.id),
    now());

ALTER TABLE professional_management.professional
    ALTER COLUMN created_at SET DEFAULT now();

ALTER TABLE professional_management.professional
    ALTER COLUMN created_at SET NOT NULL;
