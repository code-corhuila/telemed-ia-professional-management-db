-- -------------------------------------------------------------------------
-- Rollback for the role changeset.
--
-- The forward changeset is idempotent: if infra has already created
-- the roles, the DO block is a no-op. This rollback must be symmetric:
-- on the shared instance the roles are owned by infra and used by
-- professional_management_app, so they must not be dropped. On the
-- ephemeral CI database there is no other member, so the drop still
-- happens and the CI rebuild path remains clean.
--
-- Detection: a role with no members in pg_auth_members other than the
-- nested reader->writer pair is treated as "owned by this changeset"
-- and can be safely dropped. If infra owns it, professional_management_app
-- or another role appears as a member and the DROP is skipped.
-- -------------------------------------------------------------------------

REVOKE professional_management_reader FROM professional_management_writer;

DO $$
DECLARE
    reader_has_external_members boolean;
    writer_has_external_members boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r ON r.oid = m.roleid
        WHERE r.rolname = 'professional_management_reader'
          AND NOT EXISTS (
            SELECT 1 FROM pg_roles rr
            WHERE rr.oid = m.member AND rr.rolname = 'professional_management_writer'
          )
    ) INTO reader_has_external_members;

    SELECT EXISTS (
        SELECT 1 FROM pg_auth_members m
        JOIN pg_roles r ON r.oid = m.roleid
        WHERE r.rolname = 'professional_management_writer'
    ) INTO writer_has_external_members;

    IF NOT reader_has_external_members AND NOT writer_has_external_members THEN
        DROP ROLE IF EXISTS professional_management_writer;
        DROP ROLE IF EXISTS professional_management_reader;
    END IF;
END
$$;
