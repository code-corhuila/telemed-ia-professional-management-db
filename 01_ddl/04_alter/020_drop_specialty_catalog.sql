-- DEC-005: the specialty catalog and its seed ownership ledger are removed. The
-- ledger goes first because its foreign key references the catalog. The
-- specialties_id_seq sequence is owned by specialty.id and is dropped with it.
DROP TABLE professional_management.specialty_seed_ownership;
DROP TABLE professional_management.specialty;
