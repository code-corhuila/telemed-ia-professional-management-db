ALTER TABLE professional_management.professionals
    DROP CONSTRAINT chk_professionals_status_length,
    DROP CONSTRAINT chk_professionals_professional_type_length,
    DROP CONSTRAINT chk_professionals_license_number_length;

ALTER TABLE professional_management.professionals
    ALTER COLUMN status TYPE varchar(20),
    ALTER COLUMN status SET DEFAULT 'ACTIVE'::character varying,
    ALTER COLUMN professional_type TYPE varchar(30),
    ALTER COLUMN license_number TYPE varchar(80);

ALTER TABLE professional_management.specialties
    DROP CONSTRAINT chk_specialties_description_length,
    DROP CONSTRAINT chk_specialties_name_length;

ALTER TABLE professional_management.specialties
    ALTER COLUMN description TYPE varchar(500),
    ALTER COLUMN name TYPE varchar(100);
