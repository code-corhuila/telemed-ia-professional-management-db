-- -------------------------------------------------------------------------
-- Object-level privileges for the professional_management schema.
--
-- The roles professional_management_reader and
-- professional_management_writer are created and assigned to the
-- application user (professional_management_app) by
-- telemed-ia-infra-postgres during the instance bootstrap. This
-- changeset only wires those roles to the objects created by the DDL
-- changesets of this domain.
--
-- The ALTER DEFAULT PRIVILEGES statements run as the domain's
-- application user, which owns the professional_management schema
-- (infra creates it with AUTHORIZATION professional_management_app).
-- They ensure future tables and sequences created in the schema
-- inherit the same grants automatically.
-- -------------------------------------------------------------------------

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
