-- Guard of the rollback of ddl-alter-024, run before its other statements. A
-- UUID generated after the swap has no numeric equivalent, so the rollback
-- refuses instead of inventing one. It runs as one statement
-- (splitStatements: false) because of the DO block.
DO $guard$
BEGIN
    IF EXISTS (SELECT 1 FROM professional_management.professional
               WHERE id::text NOT LIKE '00000000-0000-0000-0000-%'
                  OR identity_user_id::text NOT LIKE '00000000-0000-0000-0000-%') THEN
        RAISE EXCEPTION 'Rollback ddl-alter-024 refused: professional holds UUID identifiers with no numeric equivalent; remove those rows first.';
    END IF;
END
$guard$;
