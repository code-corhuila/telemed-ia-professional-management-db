# Rollbacks

This directory mirrors the migration families so that every new changeset can
declare an external rollback file, as required by the database standard.

## Layout

```
05_rollbacks/
├── 01_ddl/
├── 02_dml/
├── 03_dcl/
└── 04_tcl/
```

Each subfolder mirrors the corresponding subfolder in `01_ddl/`, `02_dml/`,
`03_dcl/`, and `04_tcl/`. The file name of a rollback matches the changeset
file name with the extension `.rollback.sql`:

```
01_ddl/03_tables/001_create_x.sql
        ↕
05_rollbacks/01_ddl/03_tables/001_create_x.rollback.sql
```

## Historical rollbacks are inline

Changesets `001`, `001a`, `002`, `003`, `004`, `005`, and `006` were applied
before this directory existed. Their rollbacks remain inline inside each SQL
file (`--rollback ...`). They are not moved here because editing an already
applied changeset would change its checksum and break every environment that
has applied it (database standard, rule 12).

**New changesets** must declare their rollback as an external file inside
`05_rollbacks/`, referenced from the changeset with a relative path such as:

```yaml
rollback:
  - sqlFile:
      path: ../../05_rollbacks/01_ddl/04_alter/007_rename_constraints.rollback.sql
      relativeToChangelogFile: true
      splitStatements: false
```
