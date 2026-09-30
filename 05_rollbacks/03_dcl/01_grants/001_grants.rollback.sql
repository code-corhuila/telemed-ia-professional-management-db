ALTER DEFAULT PRIVILEGES IN SCHEMA professional_management REVOKE USAGE ON SEQUENCES FROM professional_management_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA professional_management REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM professional_management_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA professional_management REVOKE SELECT ON TABLES FROM professional_management_reader;
REVOKE USAGE ON ALL SEQUENCES IN SCHEMA professional_management FROM professional_management_writer;
REVOKE SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA professional_management FROM professional_management_writer;
REVOKE SELECT ON ALL TABLES IN SCHEMA professional_management FROM professional_management_reader;
REVOKE USAGE ON SCHEMA professional_management FROM professional_management_writer;
REVOKE USAGE ON SCHEMA professional_management FROM professional_management_reader;
