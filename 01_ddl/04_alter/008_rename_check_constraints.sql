-- Note: this domain has exactly three CHECK constraints, all on
-- professionals. specialties and specialty_seed_ownership have no CHECK
-- constraints (only PRIMARY KEY, UNIQUE, and FOREIGN KEY), so this
-- migration completes the ck_ to chk_ rename for the entire domain.
ALTER TABLE professional_management.professionals
    RENAME CONSTRAINT ck_professionals_years_experience_nonnegative
    TO chk_professionals_years_experience_nonnegative;

ALTER TABLE professional_management.professionals
    RENAME CONSTRAINT ck_professionals_professional_type
    TO chk_professionals_professional_type;

ALTER TABLE professional_management.professionals
    RENAME CONSTRAINT ck_professionals_status
    TO chk_professionals_status;
