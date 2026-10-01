\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    actual_count INTEGER;
    protected_specialty_id BIGINT;
    test_professional_id BIGINT;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r'
          AND c.relname IN ('specialties', 'professionals', 'specialty_seed_ownership'))
    THEN RAISE EXCEPTION 'Domain tables must not live in public'; END IF;

    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r'
          AND c.relname NOT IN ('databasechangelog', 'databasechangeloglock'))
    THEN RAISE EXCEPTION 'Unexpected public tables exist'; END IF;

    IF to_regclass('professional_management.specialty') IS NULL
       OR to_regclass('professional_management.professional') IS NULL
       OR to_regclass('professional_management.specialty_seed_ownership') IS NULL
    THEN RAISE EXCEPTION 'Expected specialty and professional tables'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'professional_management_reader' AND NOT rolcanlogin) THEN
        RAISE EXCEPTION 'professional_management_reader NOLOGIN role is missing';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'professional_management_writer' AND NOT rolcanlogin) THEN
        RAISE EXCEPTION 'professional_management_writer NOLOGIN role is missing';
    END IF;
    IF NOT pg_has_role('professional_management_writer', 'professional_management_reader', 'MEMBER') THEN
        RAISE EXCEPTION 'professional_management_writer must inherit the reader role';
    END IF;
    IF NOT has_schema_privilege('professional_management_reader', 'professional_management', 'USAGE') THEN
        RAISE EXCEPTION 'professional_management_reader lacks USAGE on professional_management schema';
    END IF;
    IF NOT has_schema_privilege('professional_management_writer', 'professional_management', 'USAGE') THEN
        RAISE EXCEPTION 'professional_management_writer lacks USAGE on professional_management schema';
    END IF;
    IF NOT has_table_privilege('professional_management_reader', 'professional_management.professional', 'SELECT') THEN
        RAISE EXCEPTION 'professional_management_reader lacks SELECT on professional';
    END IF;
    IF has_table_privilege('professional_management_reader', 'professional_management.professional', 'INSERT') THEN
        RAISE EXCEPTION 'professional_management_reader unexpectedly has INSERT on professional';
    END IF;
    IF NOT has_table_privilege('professional_management_writer', 'professional_management.professional', 'SELECT,INSERT,UPDATE,DELETE') THEN
        RAISE EXCEPTION 'professional_management_writer lacks CRUD privileges on professional';
    END IF;
    IF NOT has_sequence_privilege('professional_management_writer',
        pg_get_serial_sequence('professional_management.professional', 'id'), 'USAGE') THEN
        RAISE EXCEPTION 'professional_management_writer lacks USAGE on professional sequences';
    END IF;

    EXECUTE 'CREATE TABLE professional_management.grant_default_probe (id integer)';
    IF NOT has_table_privilege('professional_management_reader', 'professional_management.grant_default_probe', 'SELECT')
       OR has_table_privilege('professional_management_reader', 'professional_management.grant_default_probe', 'INSERT')
       OR NOT has_table_privilege('professional_management_writer', 'professional_management.grant_default_probe', 'SELECT,INSERT,UPDATE,DELETE') THEN
        RAISE EXCEPTION 'Default table privileges were not applied to a new table';
    END IF;
    EXECUTE 'CREATE SEQUENCE professional_management.grant_default_probe_seq';
    IF NOT has_sequence_privilege('professional_management_writer', 'professional_management.grant_default_probe_seq', 'USAGE') THEN
        RAISE EXCEPTION 'Default sequence privileges were not applied to a new sequence';
    END IF;
    EXECUTE 'DROP SEQUENCE professional_management.grant_default_probe_seq';
    EXECUTE 'DROP TABLE professional_management.grant_default_probe';

    SELECT COUNT(*) INTO actual_count
    FROM professional_management.specialty
    WHERE (name, description) IN (
        ('Medicina General', 'Atención médica general y orientación inicial.'),
        ('Pediatría', 'Atención integral de población pediátrica.'),
        ('Dermatología', 'Atención de enfermedades de piel, cabello y uñas.'),
        ('Cardiología', 'Atención de enfermedades cardiovasculares.'),
        ('Neurología', 'Atención de enfermedades y trastornos del sistema nervioso.'),
        ('Ginecología', 'Atención de la salud del sistema reproductivo femenino.'),
        ('Ortopedia', 'Atención de enfermedades y lesiones del sistema musculoesquelético.')
    );
    IF actual_count <> 7 OR (SELECT COUNT(*) FROM professional_management.specialty) <> 7
    THEN RAISE EXCEPTION 'Expected exactly seven specialty seeds'; END IF;

    IF (SELECT COUNT(*) FROM information_schema.columns
        WHERE table_schema = 'professional_management' AND table_name = 'professional'
          AND column_name = 'specialty_id' AND is_nullable = 'NO') <> 1
    THEN RAISE EXCEPTION 'Expected professional.specialty_id to be NOT NULL'; END IF;

    IF (SELECT COUNT(*) FROM information_schema.columns
        WHERE table_schema = 'professional_management' AND table_name = 'professional'
          AND column_name = 'professional_type' AND data_type = 'text'
          AND is_nullable = 'YES') <> 1
    THEN RAISE EXCEPTION 'Expected nullable professional.professional_type text'; END IF;

    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conrelid = 'professional_management.professional'::regclass
          AND conname = 'chk_professionals_professional_type_length' AND contype = 'c' AND convalidated) <> 1
    THEN RAISE EXCEPTION 'Expected chk_professionals_professional_type_length CHECK'; END IF;

    IF (SELECT COUNT(*) FROM information_schema.columns
        WHERE table_schema = 'professional_management' AND table_name = 'professional'
          AND column_name = 'status' AND data_type = 'text'
          AND is_nullable = 'NO') <> 1
    THEN RAISE EXCEPTION 'Expected professional.status text NOT NULL'; END IF;

    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conrelid = 'professional_management.professional'::regclass
          AND conname = 'chk_professionals_status_length' AND contype = 'c' AND convalidated) <> 1
    THEN RAISE EXCEPTION 'Expected chk_professionals_status_length CHECK'; END IF;

    IF (SELECT column_default FROM information_schema.columns
        WHERE table_schema = 'professional_management' AND table_name = 'professional'
          AND column_name = 'status') <> '''ACTIVE''::text'
    THEN RAISE EXCEPTION 'Expected professional.status DEFAULT ACTIVE'; END IF;

    IF (SELECT COUNT(*) FROM information_schema.columns
        WHERE table_schema = 'professional_management' AND table_name = 'professional'
          AND column_name IN ('active', 'is_active', 'deleted_at')) <> 0
    THEN RAISE EXCEPTION 'Unexpected professional lifecycle columns exist'; END IF;

    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conrelid = 'professional_management.professional'::regclass
          AND conname = 'chk_professionals_years_experience_nonnegative' AND contype = 'c' AND convalidated) <> 1
    THEN RAISE EXCEPTION 'Expected validated nonnegative years_experience CHECK constraint'; END IF;

    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conrelid = 'professional_management.professional'::regclass
          AND conname = 'chk_professionals_professional_type' AND contype = 'c' AND convalidated) <> 1
    THEN RAISE EXCEPTION 'Expected validated professional_type CHECK constraint'; END IF;

    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conrelid = 'professional_management.professional'::regclass
          AND conname = 'chk_professionals_status' AND contype = 'c' AND convalidated) <> 1
    THEN RAISE EXCEPTION 'Expected validated status CHECK constraint'; END IF;

    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conname = 'uq_specialties_name' AND contype = 'u') <> 1
    THEN RAISE EXCEPTION 'Expected uq_specialties_name'; END IF;

    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conname = 'uq_professionals_identity_user_id' AND contype = 'u') <> 1
    THEN RAISE EXCEPTION 'Expected uq_professionals_identity_user_id'; END IF;

    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conname = 'uq_professionals_license_number' AND contype = 'u') <> 1
    THEN RAISE EXCEPTION 'Expected uq_professionals_license_number'; END IF;

    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conrelid = 'professional_management.professional'::regclass
          AND conname = 'fk_professional_specialty'
          AND contype = 'f'
          AND convalidated = true
          AND confrelid = 'professional_management.specialty'::regclass
          AND pg_get_constraintdef(oid) ILIKE '%ON DELETE RESTRICT%') <> 1
    THEN RAISE EXCEPTION 'Expected validated fk_professional_specialty with ON DELETE RESTRICT'; END IF;

    -- ddl-alter-013 drops the historical plural constraint, so it must no longer
    -- exist anywhere after the full update. This catches a partially applied
    -- migration in which the new FK was added but the old one was left behind.
    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conname = 'fk_professionals_specialty') <> 0
    THEN RAISE EXCEPTION 'Historical fk_professionals_specialty must be gone after ddl-alter-013'; END IF;

    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conrelid = 'professional_management.professional'::regclass AND contype = 'f'
          AND confrelid <> 'professional_management.specialty'::regclass) <> 0
    THEN RAISE EXCEPTION 'Unexpected cross-database foreign key'; END IF;

    IF (SELECT COUNT(*) FROM pg_indexes
        WHERE schemaname = 'professional_management' AND tablename = 'professional'
          AND indexname = 'idx_professional_specialty_id') <> 1
    THEN RAISE EXCEPTION 'Expected specialty_id index'; END IF;

    IF (SELECT COUNT(*) FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid
                           AND a.attname = 'status'
                           AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = 'professional_management.professional'::regclass AND i.indisvalid) <> 1
       OR (SELECT COUNT(*) FROM pg_indexes
           WHERE schemaname = 'professional_management' AND tablename = 'professional'
             AND indexname = 'idx_professional_status'
             AND indexdef ILIKE '%(status)%') <> 1
    THEN RAISE EXCEPTION 'Expected exactly one status index named idx_professional_status'; END IF;

    IF (SELECT COUNT(*) FROM pg_indexes
        WHERE schemaname = 'professional_management' AND tablename = 'specialty_seed_ownership'
          AND indexname = 'idx_specialty_seed_ownership_specialty_id'
          AND indexdef ILIKE '%(specialty_id)%') <> 1
    THEN RAISE EXCEPTION 'Expected specialty_seed_ownership specialty_id index'; END IF;

    -- The UNIQUE constraints renamed by ddl-alter-010 must still reject
    -- duplicates. Each block raises a plain exception when the insert is
    -- wrongly accepted; only unique_violation is swallowed, so an accepted
    -- duplicate fails the run instead of passing silently.
    BEGIN
        INSERT INTO professional_management.specialty (name, description)
        VALUES ('Medicina General', 'dup');
        RAISE EXCEPTION 'Duplicate specialty name should be rejected';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    -- The two professional duplicates need a stored row to collide with, so
    -- the baseline professional is created outside the assertion block.
    INSERT INTO professional_management.professional
        (identity_user_id, license_number, specialty_id, years_experience)
    SELECT 999999991, 'DUP-LICENSE', id, 0
    FROM professional_management.specialty WHERE name = 'Pediatría';

    BEGIN
        INSERT INTO professional_management.professional
            (identity_user_id, license_number, specialty_id, years_experience)
        SELECT 999999992, 'DUP-LICENSE', id, 0
        FROM professional_management.specialty WHERE name = 'Pediatría';
        RAISE EXCEPTION 'Duplicate license_number should be rejected';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO professional_management.professional
            (identity_user_id, license_number, specialty_id, years_experience)
        SELECT 999999991, 'DUP-IDENTITY', id, 0
        FROM professional_management.specialty WHERE name = 'Pediatría';
        RAISE EXCEPTION 'Duplicate identity_user_id should be rejected';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    DELETE FROM professional_management.professional WHERE license_number = 'DUP-LICENSE';
    IF EXISTS (SELECT 1 FROM professional_management.professional
               WHERE license_number = 'DUP-LICENSE' OR identity_user_id = 999999991)
    THEN RAISE EXCEPTION 'Rejected duplicates must not create a professional'; END IF;

    INSERT INTO professional_management.specialty (name, description)
    VALUES ('Prueba eliminación libre', 'Delete test');
    DELETE FROM professional_management.specialty WHERE name = 'Prueba eliminación libre';
    IF EXISTS (SELECT 1 FROM professional_management.specialty WHERE name = 'Prueba eliminación libre')
    THEN RAISE EXCEPTION 'Unreferenced specialty should be deletable'; END IF;

    INSERT INTO professional_management.specialty (name, description)
    VALUES ('Prueba eliminación protegida', 'Delete protection test')
    RETURNING id INTO protected_specialty_id;
    INSERT INTO professional_management.professional
        (identity_user_id, license_number, specialty_id, years_experience, professional_type, status)
    VALUES (900000001, 'TEST-SAFE-DELETE-001', protected_specialty_id, 0,
            'GENERAL_PRACTITIONER', 'ACTIVE');

    INSERT INTO professional_management.professional
        (identity_user_id, license_number, specialty_id, years_experience)
    VALUES (900000002, 'TEST-API-INSERT-001', protected_specialty_id, 0);
    IF NOT EXISTS (SELECT 1 FROM professional_management.professional
                   WHERE license_number = 'TEST-API-INSERT-001'
                     AND professional_type IS NULL AND status = 'ACTIVE')
    THEN RAISE EXCEPTION 'API-compatible insert must default status and retain null professional_type'; END IF;

    UPDATE professional_management.professional
    SET professional_type = 'SPECIALIST', status = 'INACTIVE'
    WHERE license_number = 'TEST-SAFE-DELETE-001';
    IF NOT EXISTS (SELECT 1 FROM professional_management.professional
                   WHERE license_number = 'TEST-SAFE-DELETE-001'
                     AND professional_type = 'SPECIALIST' AND status = 'INACTIVE')
    THEN RAISE EXCEPTION 'Expected the allowed professional_type and status values'; END IF;

    UPDATE professional_management.professional SET professional_type = 'GENERAL_PRACTITIONER'
    WHERE license_number = 'TEST-SAFE-DELETE-001';
    UPDATE professional_management.professional SET status = 'ACTIVE'
    WHERE license_number = 'TEST-SAFE-DELETE-001';

    BEGIN
        UPDATE professional_management.professional SET professional_type = 'INVALID'
        WHERE license_number = 'TEST-SAFE-DELETE-001';
        RAISE EXCEPTION 'Invalid professional_type should be rejected';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE professional_management.professional SET status = 'PENDING'
        WHERE license_number = 'TEST-SAFE-DELETE-001';
        RAISE EXCEPTION 'Invalid status should be rejected';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        DELETE FROM professional_management.specialty WHERE id = protected_specialty_id;
        RAISE EXCEPTION 'Referenced specialty should not be deletable';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    IF NOT EXISTS (SELECT 1 FROM professional_management.professional
                   WHERE license_number = 'TEST-SAFE-DELETE-001')
    THEN RAISE EXCEPTION 'Professional must remain after rejected delete'; END IF;

    DELETE FROM professional_management.professional WHERE license_number = 'TEST-SAFE-DELETE-001';
    DELETE FROM professional_management.professional WHERE license_number = 'TEST-API-INSERT-001';
    DELETE FROM professional_management.specialty WHERE id = protected_specialty_id;

    IF to_regclass('professional_management.idempotency_key') IS NULL THEN
        RAISE EXCEPTION 'Expected table professional_management.idempotency_key';
    END IF;

    IF (SELECT COUNT(*) FROM pg_constraint WHERE conname = 'pk_idempotency_key' AND contype = 'p') <> 1 THEN
        RAISE EXCEPTION 'Expected primary key pk_idempotency_key';
    END IF;

    IF (SELECT COUNT(*) FROM pg_constraint WHERE conname = 'fk_idempotency_key_professional' AND contype = 'f' AND confdeltype = 'c') <> 1 THEN
        RAISE EXCEPTION 'Expected foreign key fk_idempotency_key_professional with ON DELETE CASCADE';
    END IF;

    IF (SELECT COUNT(*) FROM information_schema.columns
        WHERE table_schema = 'professional_management'
          AND table_name = 'idempotency_key'
          AND column_name = 'request_hash'
          AND data_type = 'text'
          AND is_nullable = 'YES') <> 1 THEN
        RAISE EXCEPTION 'Expected nullable text column professional_management.idempotency_key.request_hash';
    END IF;

    IF NOT has_table_privilege('professional_management_reader', 'professional_management.idempotency_key', 'SELECT') THEN
        RAISE EXCEPTION 'professional_management_reader lacks SELECT on idempotency_key';
    END IF;

    IF NOT has_table_privilege('professional_management_writer', 'professional_management.idempotency_key', 'INSERT') THEN
        RAISE EXCEPTION 'professional_management_writer lacks INSERT on idempotency_key';
    END IF;

    -- A real professional is required so that the key length CHECK is the only
    -- constraint that can reject the negative cases below. Inserting a NULL
    -- professional_id would be refused by the NOT NULL constraint instead, and
    -- the test would pass without ever exercising chk_idempotency_key_length.
    INSERT INTO professional_management.professional
        (identity_user_id, license_number, specialty_id, years_experience)
    SELECT 999999999, 'TEST-IDEMP-LEN', id, 0
    FROM professional_management.specialty WHERE name = 'Medicina General';

    SELECT id INTO test_professional_id FROM professional_management.professional
    WHERE license_number = 'TEST-IDEMP-LEN';

    IF test_professional_id IS NULL THEN
        RAISE EXCEPTION 'Expected a test professional for the idempotency_key length checks';
    END IF;

    -- CHECK length: reject keys shorter than 8 characters
    BEGIN
        INSERT INTO professional_management.idempotency_key (key, professional_id)
        VALUES ('1234567', test_professional_id);
        RAISE EXCEPTION 'CHECK should reject a 7-char key';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    -- CHECK length: reject keys longer than 128 characters
    BEGIN
        INSERT INTO professional_management.idempotency_key (key, professional_id)
        VALUES (repeat('x', 129), test_professional_id);
        RAISE EXCEPTION 'CHECK should reject a 129-char key';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    -- Boundary values 8 and 128 characters are accepted
    INSERT INTO professional_management.idempotency_key (key, professional_id)
    VALUES ('12345678', test_professional_id);
    INSERT INTO professional_management.idempotency_key (key, professional_id)
    VALUES (repeat('x', 128), test_professional_id);

    IF NOT EXISTS (SELECT 1 FROM professional_management.idempotency_key
                   WHERE professional_id = test_professional_id)
    THEN RAISE EXCEPTION 'Boundary-length keys must be accepted'; END IF;

    -- Cleanup. A CASCADE delete also proves the FK really cascades.
    DELETE FROM professional_management.professional WHERE license_number = 'TEST-IDEMP-LEN';
    IF EXISTS (SELECT 1 FROM professional_management.idempotency_key
               WHERE professional_id = test_professional_id)
    THEN RAISE EXCEPTION 'idempotency_key rows must be removed by ON DELETE CASCADE'; END IF;
END;
$$;

ROLLBACK;
