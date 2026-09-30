ALTER TABLE professional_management.professionals
    RENAME CONSTRAINT ck_professionals_years_experience_nonnegative
    TO chk_professionals_years_experience_nonnegative;

ALTER TABLE professional_management.professionals
    RENAME CONSTRAINT ck_professionals_professional_type
    TO chk_professionals_professional_type;

ALTER TABLE professional_management.professionals
    RENAME CONSTRAINT ck_professionals_status
    TO chk_professionals_status;
