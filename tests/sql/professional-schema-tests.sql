\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    actual_count INTEGER;
    protected_specialty_id BIGINT;
BEGIN
    IF (SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r'
          AND c.relname NOT IN ('specialties', 'professionals',
                                'specialty_seed_ownership',
                                'databasechangelog', 'databasechangeloglock')) <> 0
    THEN RAISE EXCEPTION 'Unexpected public domain tables exist'; END IF;

    IF to_regclass('public.specialties') IS NULL
       OR to_regclass('public.professionals') IS NULL
    THEN RAISE EXCEPTION 'Expected specialties and professionals tables'; END IF;

    SELECT COUNT(*) INTO actual_count
    FROM specialties
    WHERE (name, description) IN (
        ('Medicina General', 'Atención médica general y orientación inicial.'),
        ('Pediatría', 'Atención integral de población pediátrica.'),
        ('Dermatología', 'Atención de enfermedades de piel, cabello y uñas.'),
        ('Cardiología', 'Atención de enfermedades cardiovasculares.'),
        ('Neurología', 'Atención de enfermedades y trastornos del sistema nervioso.'),
        ('Ginecología', 'Atención de la salud del sistema reproductivo femenino.'),
        ('Ortopedia', 'Atención de enfermedades y lesiones del sistema musculoesquelético.')
    );
    IF actual_count <> 7 OR (SELECT COUNT(*) FROM specialties) <> 7
    THEN RAISE EXCEPTION 'Expected exactly seven specialty seeds'; END IF;

    IF (SELECT COUNT(*) FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'professionals'
          AND column_name = 'specialty_id' AND is_nullable = 'NO') <> 1
    THEN RAISE EXCEPTION 'Expected professionals.specialty_id to be NOT NULL'; END IF;

    IF (SELECT COUNT(*) FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'professionals'
          AND column_name IN ('status', 'active', 'is_active', 'deleted_at')) <> 0
    THEN RAISE EXCEPTION 'Unexpected professional lifecycle columns exist'; END IF;

    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conrelid = 'public.professionals'::regclass AND contype = 'f'
          AND confrelid = 'public.specialties'::regclass
          AND pg_get_constraintdef(oid) ILIKE '%ON DELETE RESTRICT%') <> 1
    THEN RAISE EXCEPTION 'Expected restrictive specialty foreign key'; END IF;

    IF (SELECT COUNT(*) FROM pg_constraint
        WHERE conrelid = 'public.professionals'::regclass AND contype = 'f'
          AND confrelid <> 'public.specialties'::regclass) <> 0
    THEN RAISE EXCEPTION 'Unexpected cross-database foreign key'; END IF;

    IF (SELECT COUNT(*) FROM pg_indexes
        WHERE schemaname = 'public' AND tablename = 'professionals'
          AND indexname = 'idx_professionals_specialty_id') <> 1
    THEN RAISE EXCEPTION 'Expected specialty_id index'; END IF;

    INSERT INTO specialties (name, description)
    VALUES ('Prueba eliminación libre', 'Delete test');
    DELETE FROM specialties WHERE name = 'Prueba eliminación libre';
    IF EXISTS (SELECT 1 FROM specialties WHERE name = 'Prueba eliminación libre')
    THEN RAISE EXCEPTION 'Unreferenced specialty should be deletable'; END IF;

    INSERT INTO specialties (name, description)
    VALUES ('Prueba eliminación protegida', 'Delete protection test')
    RETURNING id INTO protected_specialty_id;
    INSERT INTO professionals (identity_user_id, license_number, specialty_id, years_experience)
    VALUES (900000001, 'TEST-SAFE-DELETE-001', protected_specialty_id, 0);

    BEGIN
        DELETE FROM specialties WHERE id = protected_specialty_id;
        RAISE EXCEPTION 'Referenced specialty should not be deletable';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    IF NOT EXISTS (SELECT 1 FROM professionals
                   WHERE license_number = 'TEST-SAFE-DELETE-001')
    THEN RAISE EXCEPTION 'Professional must remain after rejected delete'; END IF;

    DELETE FROM professionals WHERE license_number = 'TEST-SAFE-DELETE-001';
    DELETE FROM specialties WHERE id = protected_specialty_id;
END;
$$;

ROLLBACK;
