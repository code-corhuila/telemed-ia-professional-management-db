-- Validates the FK added by ddl-alter-013. VALIDATE CONSTRAINT takes
-- SHARE UPDATE EXCLUSIVE, so it does not block concurrent reads or
-- writes on `professional`. This is the second half of the expand/
-- contract pattern that avoids an ACCESS EXCLUSIVE full-table scan.
ALTER TABLE professional_management.professional
    VALIDATE CONSTRAINT fk_professional_specialty;
