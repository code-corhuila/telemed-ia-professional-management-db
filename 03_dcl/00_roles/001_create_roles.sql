-- -------------------------------------------------------------------------
-- Non-login roles for the professional_management domain.
--
-- Under Anexo J, these roles are created by telemed-ia-infra-postgres
-- during the instance bootstrap (postgres/init/01-instance.sh). This
-- changeset keeps them as idempotent insurance for environments where
-- the bootstrap has not run (for example, the ephemeral Postgres
-- container that db-ci.yml starts for the reconstruction test). On the
-- shared instance the roles already exist, so the DO block below is a
-- no-op and only the nested GRANT runs.
--
-- The application user (professional_management_app) is created and
-- granted both roles by infra; this changeset never touches it.
-- -------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'professional_management_reader') THEN
        CREATE ROLE professional_management_reader NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'professional_management_writer') THEN
        CREATE ROLE professional_management_writer NOLOGIN;
    END IF;
END
$$;

-- The writer inherits every privilege the reader has. The reverse is not
-- true: the reader never gains write access through this hierarchy.
GRANT professional_management_reader TO professional_management_writer;
