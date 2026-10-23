-- DEC-005 (telemed-ia-docs, 09-microservices/services/04-professional-service/
-- decisions.md): every professional is a general practitioner and there is no
-- specialty catalog. Dropping the column also drops fk_professional_specialty
-- and idx_professional_specialty_id, which depend on it; every other column of
-- each professional is kept.
ALTER TABLE professional_management.professional DROP COLUMN specialty_id;
