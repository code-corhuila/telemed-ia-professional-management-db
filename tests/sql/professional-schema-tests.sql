\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    actual_count INTEGER;
BEGIN
    IF to_regclass('public.specialties') IS NULL THEN
        RAISE EXCEPTION 'Expected table public.specialties to exist';
    END IF;
    IF to_regclass('public.professionals') IS NULL THEN
        RAISE EXCEPTION 'Expected table public.professionals to exist';
    END IF;

    SELECT COUNT(*) INTO actual_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relname NOT IN (
          'specialties',
          'professionals',
          'databasechangelog',
          'databasechangeloglock'
      );
    IF actual_count <> 0 THEN
        RAISE EXCEPTION 'Unexpected public domain tables exist';
    END IF;

    SELECT COUNT(*) INTO actual_count
    FROM pg_constraint
    WHERE conrelid = 'public.specialties'::regclass
      AND contype = 'p'
      AND conname = 'pk_specialties';
    IF actual_count <> 1 THEN
        RAISE EXCEPTION 'Expected primary key pk_specialties';
    END IF;

    SELECT COUNT(*) INTO actual_count
    FROM pg_constraint
    WHERE conrelid = 'public.professionals'::regclass
      AND contype = 'p'
      AND conname = 'pk_professionals';
    IF actual_count <> 1 THEN
        RAISE EXCEPTION 'Expected primary key pk_professionals';
    END IF;

    SELECT COUNT(*) INTO actual_count
    FROM pg_constraint
    WHERE conrelid = 'public.specialties'::regclass
      AND contype = 'u'
      AND pg_get_constraintdef(oid) ILIKE '%(name)%';
    IF actual_count <> 1 THEN
        RAISE EXCEPTION 'Expected a unique constraint on specialties.name';
    END IF;

    SELECT COUNT(*) INTO actual_count
    FROM pg_constraint
    WHERE conrelid = 'public.professionals'::regclass
      AND contype = 'u'
      AND (
          pg_get_constraintdef(oid) ILIKE '%(identity_user_id)%'
          OR
          pg_get_constraintdef(oid) ILIKE '%(license_number)%'
      );
    IF actual_count <> 2 THEN
        RAISE EXCEPTION 'Expected unique constraints on identity_user_id and license_number';
    END IF;

    SELECT COUNT(*) INTO actual_count
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'specialties'
      AND column_name IN ('id', 'name')
      AND is_nullable = 'NO';
    IF actual_count <> 2 THEN
        RAISE EXCEPTION 'Expected specialties.id and specialties.name to be NOT NULL';
    END IF;

    SELECT COUNT(*) INTO actual_count
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'professionals'
      AND column_name IN ('id', 'identity_user_id', 'license_number', 'specialty_id', 'years_experience')
      AND is_nullable = 'NO';
    IF actual_count <> 5 THEN
        RAISE EXCEPTION 'Expected all required professionals columns to be NOT NULL';
    END IF;

    SELECT COUNT(*) INTO actual_count
    FROM pg_constraint
    WHERE conrelid = 'public.professionals'::regclass
      AND conname = 'ck_professionals_years_experience_nonnegative'
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%years_experience >= 0%';
    IF actual_count <> 1 THEN
        RAISE EXCEPTION 'Expected nonnegative years_experience check constraint';
    END IF;

    SELECT COUNT(*) INTO actual_count
    FROM pg_constraint
    WHERE conrelid = 'public.professionals'::regclass
      AND conname = 'fk_professionals_specialty'
      AND contype = 'f'
      AND confrelid = 'public.specialties'::regclass;
    IF actual_count <> 1 THEN
        RAISE EXCEPTION 'Expected professionals.specialty_id foreign key to specialties.id';
    END IF;

    SELECT COUNT(*) INTO actual_count
    FROM pg_constraint
    WHERE conrelid = 'public.professionals'::regclass
      AND contype = 'f'
      AND confrelid = to_regclass('public.users');
    IF actual_count <> 0 THEN
        RAISE EXCEPTION 'Unexpected foreign key from professionals to users';
    END IF;

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
    IF actual_count <> 7 THEN
        RAISE EXCEPTION 'Expected all seven specialties seeds';
    END IF;

    SELECT COUNT(*) INTO actual_count
    FROM specialties;
    IF actual_count <> 7 THEN
        RAISE EXCEPTION 'Expected no specialties beyond the seven bounded-context seeds';
    END IF;
END;
$$;

ROLLBACK;
