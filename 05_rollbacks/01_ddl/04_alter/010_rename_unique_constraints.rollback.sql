ALTER TABLE professional_management.professionals
    RENAME CONSTRAINT uq_professionals_license_number TO professionals_license_number_key;

ALTER TABLE professional_management.professionals
    RENAME CONSTRAINT uq_professionals_identity_user_id TO professionals_identity_user_id_key;

ALTER TABLE professional_management.specialties
    RENAME CONSTRAINT uq_specialties_name TO specialties_name_key;
