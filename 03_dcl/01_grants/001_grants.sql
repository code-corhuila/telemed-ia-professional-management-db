GRANT USAGE ON SCHEMA professional_management TO professional_management_reader;
GRANT USAGE ON SCHEMA professional_management TO professional_management_writer;

GRANT SELECT ON ALL TABLES IN SCHEMA professional_management TO professional_management_reader;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA professional_management TO professional_management_writer;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA professional_management TO professional_management_writer;

ALTER DEFAULT PRIVILEGES IN SCHEMA professional_management
    GRANT SELECT ON TABLES TO professional_management_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA professional_management
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO professional_management_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA professional_management
    GRANT USAGE ON SEQUENCES TO professional_management_writer;
