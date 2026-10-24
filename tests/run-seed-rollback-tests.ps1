[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$id = [Guid]::NewGuid().ToString('N').Substring(0, 12)
$network = "seed-rollback-$id"
$container = "$network-postgres"
$kinds = @('fresh', 'full', 'collision002', 'collision004', 'fk', 'admindelete', 'transition', 'generalpractice', 'uuid')
$databases = @($kinds | ForEach-Object { "seed_${_}_$id" })
if ($databases.Count -ne $kinds.Count -or
    @($databases | Where-Object { $_ -notmatch "^seed_.+_$id$" }).Count -ne 0 -or
    @($databases | Select-Object -Unique).Count -ne $kinds.Count) {
    throw 'Test database names must be unique and include this run identifier.'
}
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) $network
$passwordBytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($passwordBytes) } finally { $rng.Dispose() }
$password = [Convert]::ToBase64String($passwordBytes)
$fixture = 'pre-existing audit fixture'
$neurology = "U&'Neurolog\00EDa'"
$networkCreated = $false
$containerCreated = $false

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker is required.' }

function D([string[]]$DockerArgs) {
    # Windows PowerShell 5.1 does not redirect native stderr with *> $null or 2>$null.
    # A benign NOTICE/WARNING from docker/psql would be treated as a fatal error under
    # $ErrorActionPreference = 'Stop'. Flip to 'Continue' for the native call, merge
    # stderr into stdout, print it, and evaluate $LASTEXITCODE ourselves.
    $previousEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & docker @DockerArgs 2>&1 | ForEach-Object { Write-Host $_ }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousEap
    }
    if ($exitCode -ne 0) { throw "Docker failed: $($DockerArgs -join ' ')" }
}
function P([string]$Db, [string]$Sql, [string[]]$Options = @()) {
    D (@('exec', $container, 'psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1',
        '-U', 'test_user', '-d', $Db) + $Options + @('-c', $Sql))
}
function Schema([string]$Db) {
    D @('exec', $container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U',
        'test_user', '-d', $Db, '--file=/tests/professional-schema-tests.sql')
}
function L([string]$Db, [string[]]$Command) {
    $source = $root
    $target = '/workspace'
    $work = $target
    $file = 'changelog/changelog-master.yaml'
    $mount = "type=bind,source=$source,target=$target,readonly"
    D (@('run', '--rm', '--network', $network, '--workdir', $work, '--mount', $mount,
        'liquibase/liquibase:4.31', "--url=jdbc:postgresql://${container}:5432/$Db",
        '--username=test_user', "--password=$password", "--changelog-file=$file") + $Command)
}
function A([string]$Db, [string]$Condition, [string]$Message) {
    $message = $Message.Replace("'", "''")
    P $Db "DO `$`$ BEGIN IF NOT ($Condition) THEN RAISE EXCEPTION '$message'; END IF; END; `$`$;"
}
function DomainSchema([string]$Db) {
    # The domain schema is considered present whenever either the singular
    # (after ddl-alter-012) or the plural (before it, or after it was
    # rolled back) table exists in professional_management. Since the
    # schema-qualification refactor, the tables never live in public.
    $inDomain = Scalar $Db "SELECT CASE WHEN to_regclass('professional_management.specialty') IS NOT NULL OR to_regclass('professional_management.specialties') IS NOT NULL THEN 1 ELSE 0 END"
    if ($inDomain -eq 1) {
        return 'professional_management'
    }
    return 'public'
}
# The table is singular after ddl-alter-012 has been applied, and plural
# before it, or after it has been rolled back. Both variants live in
# professional_management since the schema-qualification refactor. The
# test chooses the name based on which physical table exists, not on the
# schema alone.
function SpecialtyTable([string]$Db) {
    if ((Scalar $Db "SELECT CASE WHEN to_regclass('professional_management.specialty') IS NOT NULL THEN 1 ELSE 0 END") -eq 1) { return 'specialty' }
    return 'specialties'
}
function ProfessionalTable([string]$Db) {
    if ((Scalar $Db "SELECT CASE WHEN to_regclass('professional_management.professional') IS NOT NULL THEN 1 ELSE 0 END") -eq 1) { return 'professional' }
    return 'professionals'
}
function Own([string]$Db, [string]$Change, [int]$Count) {
    $schema = DomainSchema $Db
    A $Db "(SELECT count(*) FROM $schema.specialty_seed_ownership WHERE changeset_id='$Change')=$Count" "Ownership mismatch: $Change"
}
function FixtureRow([string]$Db, [long]$SpecialtyId) {
    $schema = DomainSchema $Db
    A $Db "EXISTS (SELECT 1 FROM $schema.$(SpecialtyTable $Db) WHERE id=$SpecialtyId AND description='$fixture')" "Fixture row changed: $SpecialtyId"
}
function Scalar([string]$Db, [string]$Sql) {
    # Same PowerShell 5.1 caveat as D: capture stdout of a native command without
    # letting a stderr line trip $ErrorActionPreference = 'Stop'.
    $previousEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $out = & docker exec $container psql -X -q -t -A -v ON_ERROR_STOP=1 -U test_user -d $Db -c $Sql 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousEap
    }
    if ($exitCode -ne 0) { throw "Could not query $Db." }
    return [long](($out | Where-Object { "$_".Trim() -match '^\d+$' } | Select-Object -Last 1).Trim())
}
function NewDb([string]$Db) {
    foreach ($candidate in $databases) {
        if ($candidate -eq $Db) { continue }
        D @('exec', $container, 'psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1',
            '-U', 'test_user', '-d', 'postgres',
            '-c', "DROP DATABASE IF EXISTS $candidate WITH (FORCE)")
    }
    P 'postgres' 'DROP ROLE IF EXISTS professional_management_writer; DROP ROLE IF EXISTS professional_management_reader;'
    P 'postgres' "CREATE DATABASE $Db;"
}
# DEC-005: after a full update the specialty catalog is gone and every
# professional is a general practitioner.
function GeneralPractice([string]$Db) {
    A $Db "to_regclass('professional_management.specialty') IS NULL AND to_regclass('professional_management.specialty_seed_ownership') IS NULL AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='professional_management' AND table_name='professional' AND column_name='specialty_id')" 'A full update must leave no specialty catalog (DEC-005).'
}
function Seven([string]$Db) {
    $schema = DomainSchema $Db
    A $Db "(SELECT count(*) FROM $schema.$(SpecialtyTable $Db))=7" 'Expected seven specialties.'
}
function Collision([string]$Db, [string]$Name, [string]$NameSql, [string]$Change, [int]$ExpectedOwned, [int]$ExpectedRows, [int]$PrefixCount) {
    NewDb $Db
    L $Db @('update-count', '--count', "$PrefixCount")
    $schema = DomainSchema $Db
    $specialtyId = Scalar $Db "INSERT INTO $schema.$(SpecialtyTable $Db)(name,description) VALUES ($NameSql,'$fixture') RETURNING id"
    L $Db @('update-count', '--count', '1')
    FixtureRow $Db $specialtyId
    A $Db "NOT EXISTS (SELECT 1 FROM $schema.specialty_seed_ownership WHERE changeset_id='$Change' AND specialty_id=$specialtyId)" "Pre-existing $Name was claimed."
    Own $Db $Change $ExpectedOwned
    L $Db @('rollback-count', '--count', '1')
    FixtureRow $Db $specialtyId
    A $Db "(SELECT count(*) FROM $schema.$(SpecialtyTable $Db))=$ExpectedRows" "$Name rollback left unexpected rows."
    Own $Db $Change 0
    Write-Host "PASS $Change collision preserves pre-existing row and removes owned rows."
}

try {
    D @('network', 'create', $network)
    $networkCreated = $true
    D @('run', '-d', '--name', $container, '--network', $network,
        '-e', 'POSTGRES_USER=test_user', '-e', "POSTGRES_PASSWORD=$password",
        '-e', 'POSTGRES_DB=postgres', '--mount',
        "type=bind,source=$root/tests/sql,target=/tests,readonly", 'postgres:16-alpine')
    $containerCreated = $true
    $ready = $false
    for ($i=0; $i -lt 60; $i++) {
        $previousEap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & docker exec $container pg_isready -U test_user -d postgres 2>&1 | Out-Null
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousEap
        }
        if ($exitCode -eq 0) { $ready = $true; break }
        Start-Sleep 2
    }
    if (-not $ready) { throw 'Disposable PostgreSQL did not become ready.' }

    $fresh = $databases[0]; NewDb $fresh; L $fresh @('update'); L $fresh @('validate')
    A $fresh "(SELECT count(*) FROM databasechangelog WHERE id IN ('ddl-schemas-001','001-create-specialties','001a-create-specialty-seed-ownership','002-seed-specialties','003-create-professionals','004-seed-additional-specialties','005-cascade-deleted-specialty-ownership','006-add-professional-type-and-status','ddl-alter-007','ddl-alter-008','ddl-alter-010','ddl-alter-011','ddl-tables-004','ddl-alter-009','ddl-indexes-001','ddl-alter-012','ddl-alter-013','ddl-alter-014','ddl-alter-015','ddl-alter-016','ddl-alter-017','ddl-alter-018','ddl-indexes-002','ddl-indexes-003','001-create-roles','001-grants','dcl-grants-002','ddl-alter-019','ddl-alter-020','ddl-alter-021','ddl-alter-022','ddl-alter-023','ddl-alter-024','ddl-alter-025'))=34" 'Expected thirty-four changesets.'
    GeneralPractice $fresh
    Schema $fresh
    L $fresh @('update')
    A $fresh '(SELECT count(*) FROM databasechangelog)=34' 'Second update applied additional changesets.'
    GeneralPractice $fresh
    Write-Host 'PASS second update is idempotent.'

    # The DEC-006 and DEC-005 changesets run after the grants, so they are the
    # first ones to roll back.
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_constraint WHERE conname='fk_idempotency_key_professional' AND confdeltype='c' AND convalidated)=1" 'Rollback of ddl-alter-025 is a no-op and must keep the validated idempotency FK.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM information_schema.columns WHERE table_schema='professional_management' AND ((table_name='professional' AND column_name IN ('id','identity_user_id')) OR (table_name='idempotency_key' AND column_name='professional_id')) AND data_type='bigint')=3 AND (SELECT count(*) FROM information_schema.columns WHERE table_schema='professional_management' AND column_name IN ('id_uuid','identity_user_id_uuid','professional_id_uuid') AND data_type='uuid')=3 AND pg_get_serial_sequence('professional_management.professional','id') IS NOT NULL AND (SELECT count(*) FROM pg_constraint WHERE conname IN ('pk_professionals','uq_professionals_identity_user_id','fk_idempotency_key_professional'))=3" 'Rollback ddl-alter-024 must restore the bigint identifiers, their sequence and constraints, next to the expand columns.'
    A $fresh "has_sequence_privilege('professional_management_writer', pg_get_serial_sequence('professional_management.professional','id'), 'USAGE')" 'Rollback ddl-alter-024 must leave the re-created sequence granted.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_indexes WHERE schemaname='professional_management' AND tablename='idempotency_key' AND indexname='idx_idempotency_key_professional_id' AND indexdef ILIKE '%(professional_id)%')=1 AND NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='professional_management' AND indexname='idx_idempotency_key_professional_id_uuid')" 'Rollback ddl-alter-023 must leave only the bigint idempotency index.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='professional_management' AND column_name IN ('id_uuid','identity_user_id_uuid','professional_id_uuid'))" 'Rollback ddl-alter-022 must drop the expand columns.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM information_schema.columns WHERE table_schema='professional_management' AND table_name='professional' AND column_name='professional_type' AND is_nullable='YES' AND column_default IS NULL)=1 AND (SELECT count(*) FROM pg_constraint WHERE conname='chk_professionals_professional_type' AND convalidated AND pg_get_constraintdef(oid) ILIKE '%SPECIALIST%')=1" 'Rollback ddl-alter-021 must restore the nullable professional_type and its two-value CHECK.'
    L $fresh @('rollback-count','--count','1')
    Seven $fresh; Own $fresh '002-seed-specialties' 4; Own $fresh '004-seed-additional-specialties' 3
    A $fresh "(SELECT count(*) FROM pg_constraint WHERE conname IN ('pk_specialties','uq_specialties_name','chk_specialties_name_length','chk_specialties_description_length','pk_specialty_seed_ownership'))=5 AND (SELECT count(*) FROM pg_constraint WHERE conname='fk_specialty_seed_ownership_specialty' AND confdeltype='c' AND convalidated)=1 AND (SELECT count(*) FROM pg_indexes WHERE schemaname='professional_management' AND indexname='idx_specialty_seed_ownership_specialty_id')=1" 'Rollback ddl-alter-020 must re-create the catalog, its ledger, their constraints and index.'
    A $fresh "has_table_privilege('professional_management_writer','professional_management.specialty','INSERT') AND has_table_privilege('professional_management_reader','professional_management.specialty_seed_ownership','SELECT')" 'Rollback ddl-alter-020 must leave the re-created tables granted.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM information_schema.columns WHERE table_schema='professional_management' AND table_name='professional' AND column_name='specialty_id' AND is_nullable='NO')=1 AND (SELECT count(*) FROM pg_constraint WHERE conname='fk_professional_specialty' AND confdeltype='r' AND convalidated)=1 AND (SELECT count(*) FROM pg_indexes WHERE schemaname='professional_management' AND indexname='idx_professional_specialty_id')=1" 'Rollback ddl-alter-019 must restore specialty_id, its validated RESTRICT FK and its index.'

    L $fresh @('rollback-count','--count','1')
    A $fresh "to_regclass('professional_management.idempotency_key') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM databasechangelog WHERE id='dcl-grants-002')" 'Explicit grant rollback must remove its changeset history and keep the table.'
    A $fresh "has_table_privilege('professional_management_writer','professional_management.professional','INSERT') AND has_table_privilege('professional_management_reader','professional_management.professional','SELECT')" 'Explicit grant rollback must not disturb the grants applied by 001-grants.'

    L $fresh @('rollback-count','--count','1')
    A $fresh "NOT has_schema_privilege('professional_management_reader','professional_management','USAGE') AND NOT has_table_privilege('professional_management_writer','professional_management.professional','INSERT')" 'Grant rollback must revoke current schema and table privileges.'
    A $fresh "NOT has_table_privilege('professional_management_reader','professional_management.idempotency_key','SELECT')" 'Grant rollback must also remove the idempotency_key grants granted by ON ALL TABLES.'
    P $fresh 'CREATE TABLE professional_management.grant_rollback_probe (id integer)'
    A $fresh "NOT has_table_privilege('professional_management_reader','professional_management.grant_rollback_probe','SELECT') AND NOT has_table_privilege('professional_management_writer','professional_management.grant_rollback_probe','INSERT')" 'Grant rollback must remove default privileges for future tables.'
    P $fresh 'DROP TABLE professional_management.grant_rollback_probe'
    L $fresh @('rollback-count','--count','1')
    A $fresh "NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname IN ('professional_management_reader','professional_management_writer'))" 'Role rollback must remove both DCL roles.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_indexes WHERE schemaname='professional_management' AND tablename='specialty_seed_ownership' AND indexname='idx_specialty_seed_ownership_specialty_id' AND indexdef ILIKE '%(specialty_id)%')=1" 'Rollback ddl-indexes-003 must leave a usable specialty_id index.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_indexes WHERE schemaname='professional_management' AND indexname IN ('idx_professionals_specialty_id','idx_professionals_status','idx_idempotency_key_professional_id'))=3 AND (SELECT count(*) FROM pg_indexes WHERE schemaname='professional_management' AND indexname IN ('idx_professional_specialty_id','idx_professional_status'))=0" 'Rollback ddl-indexes-002 must re-create the historical index names.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='professional_management' AND tablename='specialty_seed_ownership' AND indexname='idx_specialty_seed_ownership_specialty_id')" 'Rollback of ddl-indexes-001 must remove its ownership index.'
    # ddl-alter-018 is the no-op rollback: PostgreSQL has no UNVALIDATE
    # CONSTRAINT, so the validated fk_idempotency_key_professional must survive
    # unchanged until ddl-alter-017 drops and re-adds it in the next rollback.
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_constraint WHERE conname='fk_idempotency_key_professional' AND conrelid='professional_management.idempotency_key'::regclass AND confdeltype='c' AND convalidated)=1" 'Rollback of ddl-alter-018 must keep the validated fk_idempotency_key_professional in place.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_constraint WHERE conname='fk_idempotency_key_professional' AND conrelid='professional_management.idempotency_key'::regclass AND confdeltype='c' AND convalidated)=1" 'Rollback ddl-alter-017 must re-add the idempotency FK with ON DELETE CASCADE and it validated.'
    # ddl-alter-016 is the no-op half of the ownership FK pair, for the same reason.
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_constraint WHERE conname='fk_specialty_seed_ownership_specialty' AND conrelid='professional_management.specialty_seed_ownership'::regclass AND confdeltype='c' AND convalidated)=1" 'Rollback of ddl-alter-016 must keep the validated fk_specialty_seed_ownership_specialty in place.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_constraint WHERE conname='fk_specialty_seed_ownership_specialty' AND conrelid='professional_management.specialty_seed_ownership'::regclass AND confdeltype='c' AND convalidated)=1" 'Rollback ddl-alter-015 must re-add the ownership FK with ON DELETE CASCADE and it validated.'
    L $fresh @('rollback-count','--count','1')
    # ddl-alter-014 is the no-op rollback: PostgreSQL has no UNVALIDATE
    # CONSTRAINT, so the validated fk_professional_specialty must survive
    # unchanged until ddl-alter-013 drops it in the next rollback.
    A $fresh "(SELECT count(*) FROM pg_constraint WHERE conname='fk_professional_specialty' AND conrelid='professional_management.professional'::regclass AND confdeltype='r' AND convalidated)=1" 'Rollback of ddl-alter-014 must keep the validated fk_professional_specialty in place.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_constraint WHERE conname='fk_professionals_specialty' AND conrelid='professional_management.professional'::regclass AND confdeltype='r')=1 AND (SELECT count(*) FROM pg_constraint WHERE conname='fk_professional_specialty')=0" 'Rollback ddl-alter-013 must restore the historical fk_professionals_specialty name on the singular table.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "to_regclass('professional_management.specialties') IS NOT NULL AND to_regclass('professional_management.specialty') IS NULL AND to_regclass('professional_management.professionals') IS NOT NULL AND to_regclass('professional_management.professional') IS NULL" 'Rollback ddl-alter-012 must restore the historical plural table names.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "to_regclass('professional_management.idempotency_key') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='professional_management' AND table_name='idempotency_key' AND column_name='request_hash')" 'Rollback 009 must drop only the request_hash column and keep the idempotency_key table.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "to_regclass('professional_management.idempotency_key') IS NULL AND to_regclass('professional_management.professionals') IS NOT NULL" 'Rollback of the idempotency_key table must drop only that table.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM information_schema.columns WHERE table_schema='professional_management' AND ((table_name='specialties' AND column_name IN ('name','description')) OR (table_name='professionals' AND column_name IN ('license_number','professional_type','status'))) AND data_type='character varying')=5 AND (SELECT count(*) FROM pg_constraint WHERE conname IN ('chk_specialties_name_length','chk_specialties_description_length','chk_professionals_license_number_length','chk_professionals_professional_type_length','chk_professionals_status_length'))=0" 'Rollback 011 must drop the length CHECKs and restore the five VARCHAR(n) types.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_constraint WHERE conname IN ('uq_specialties_name','uq_professionals_identity_user_id','uq_professionals_license_number'))=0 AND (SELECT count(*) FROM pg_constraint WHERE conname IN ('specialties_name_key','professionals_identity_user_id_key','professionals_license_number_key'))=3" 'Rollback 010 must restore the autogenerated UNIQUE constraint names.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_constraint WHERE conrelid='professional_management.professionals'::regclass AND conname IN ('ck_professionals_years_experience_nonnegative','ck_professionals_professional_type','ck_professionals_status'))=3" 'Rollback 008 must restore the historical CHECK names.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "to_regclass('professional_management.specialties') IS NOT NULL AND to_regclass('professional_management.professionals') IS NOT NULL AND to_regclass('professional_management.specialty_seed_ownership') IS NOT NULL AND to_regclass('public.specialties') IS NULL AND to_regclass('public.professionals') IS NULL" 'Rollback 007 must leave the domain tables in professional_management (007 is a no-op after the schema-qualification refactor).'
    L $fresh @('rollback-count','--count','1')
    A $fresh "NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='professional_management' AND table_name='professionals' AND column_name IN ('professional_type','status')) AND to_regclass('professional_management.professionals') IS NOT NULL" 'Rollback 006 must remove its columns but retain professionals.'
    A $fresh "NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='professional_management' AND tablename='professionals' AND indexname='idx_professionals_status')" 'Rollback 006 must remove its status index.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_constraint WHERE conname='fk_specialty_seed_ownership_specialty' AND confdeltype='a')=1" 'Rollback 005 must restore the ownership FK behavior.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "to_regclass('professional_management.professionals') IS NULL AND (SELECT count(*) FROM professional_management.specialties)=7" 'Rollback 003 must remove professionals before seed rollback.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM professional_management.specialties)=4" 'Rollback 004 did not retain 002 rows.'
    Own $fresh '004-seed-additional-specialties' 0; Own $fresh '002-seed-specialties' 4
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM professional_management.specialties)=0" '002-owned rows remain.'
    Own $fresh '002-seed-specialties' 0
    L $fresh @('rollback-count','--count','1')
    A $fresh "to_regclass('professional_management.specialty_seed_ownership') IS NULL" 'Ownership table remains.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "to_regclass('professional_management.specialties') IS NULL" '001 did not remove specialties.'
    P $fresh 'CREATE TABLE professional_management.rollback_guard_probe (id integer)'
    $rollbackPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $rollbackFailure = & docker run --rm --network $network --workdir /workspace --mount "type=bind,source=$root,target=/workspace,readonly" `
            liquibase/liquibase:4.31 "--url=jdbc:postgresql://${container}:5432/$fresh" --username=test_user "--password=$password" `
            --changelog-file=changelog/changelog-master.yaml rollback-count --count 1 2>&1
        $rollbackExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $rollbackPreference }
    if ($rollbackExitCode -eq 0 -or ($rollbackFailure -join "`n") -notmatch 'Rollback of schema creation refused: professional_management still contains objects') {
        throw 'Schema rollback must refuse to drop a non-empty professional_management schema.'
    }
    A $fresh "to_regclass('professional_management.rollback_guard_probe') IS NOT NULL AND EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='professional_management')" 'Rejected schema rollback must preserve the schema and its object.'
    P $fresh 'DROP TABLE professional_management.rollback_guard_probe'
    L $fresh @('rollback-count','--count','1')
    A $fresh "NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='professional_management')" 'Schema changeset rollback must remove the empty domain schema.'
    L $fresh @('update'); GeneralPractice $fresh
    A $fresh "(SELECT count(*) FROM databasechangelog WHERE id='006-add-professional-type-and-status')=1" 'Reapplication after empty-table rollback must restore 006.'
    L $fresh @('update')
    A $fresh "(SELECT count(*) FROM databasechangelog WHERE id='006-add-professional-type-and-status')=1" 'A second update after reapplication must leave 006 unchanged.'
    Schema $fresh
    Write-Host 'PASS fresh apply, ownership, staged rollbacks, reapply, and schema tests.'

    $full = $databases[1]; NewDb $full; L $full @('update'); L $full @('rollback-count','--count','34')
    A $full "to_regclass('public.specialties') IS NULL AND to_regclass('public.professionals') IS NULL AND to_regclass('public.specialty_seed_ownership') IS NULL AND to_regclass('professional_management.specialty') IS NULL AND to_regclass('professional_management.professional') IS NULL AND to_regclass('professional_management.specialty_seed_ownership') IS NULL" 'Full rollback left domain tables.'
    A $full "NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='professional_management')" 'Full rollback left the domain schema.'
    A $full "(SELECT count(*) FROM databasechangelog WHERE id IN ('ddl-schemas-001','001-create-specialties','001a-create-specialty-seed-ownership','002-seed-specialties','003-create-professionals','004-seed-additional-specialties','005-cascade-deleted-specialty-ownership','006-add-professional-type-and-status','ddl-alter-007','ddl-alter-008','ddl-alter-010','ddl-alter-011','ddl-tables-004','ddl-alter-009','ddl-indexes-001','ddl-alter-012','ddl-alter-013','ddl-alter-014','ddl-alter-015','ddl-alter-016','ddl-alter-017','ddl-alter-018','ddl-indexes-002','ddl-indexes-003','001-create-roles','001-grants','dcl-grants-002','ddl-alter-019','ddl-alter-020','ddl-alter-021','ddl-alter-022','ddl-alter-023','ddl-alter-024','ddl-alter-025'))=0" 'Full rollback left changeset history.'
    L $full @('update'); GeneralPractice $full
    Schema $full
    Write-Host 'PASS rollback-count=34, table/schema/history removal, reapply, and schema tests.'

    Collision $databases[2] 'Medicina General' "'Medicina General'" '002-seed-specialties' 3 1 3
    Collision $databases[3] 'Neurología' $neurology '004-seed-additional-specialties' 2 5 4

    # Stops at the 27 changesets applied before DEC-005, while the catalog exists.
    $fk = $databases[4]; NewDb $fk; L $fk @('update-count', '--count', '27')
    $generalId = Scalar $fk "SELECT id FROM professional_management.specialty WHERE name='Medicina General'"
    P $fk "INSERT INTO professional_management.professional(identity_user_id,license_number,specialty_id,years_experience,professional_type,status) VALUES (900000001,'TEST-ROLLBACK-002-001',$generalId,0,'GENERAL_PRACTITIONER','ACTIVE')"
    # Rolls back the 19 most recent changesets, stopping just before 006. That set
    # includes ddl-alter-012, which renames the domain tables from singular back to
    # their historical plural names. ddl-alter-007 is also in that set, but it is
    # now a no-op: after the schema-qualification refactor, the tables never left
    # professional_management. The tables stay in professional_management under
    # their historical plural names, with the professional row still present. 006
    # stays applied on purpose: the single rollback below must be refused while
    # that row exists.
    L $fk @('rollback-count', '--count', '19')
    A $fk "to_regclass('professional_management.professionals') IS NOT NULL AND to_regclass('professional_management.professional') IS NULL AND EXISTS (SELECT 1 FROM professional_management.professionals WHERE license_number='TEST-ROLLBACK-002-001')" 'Rollback of ddl-alter-012 must restore the plural table name in professional_management (007 is a no-op after the schema-qualification refactor).'
    $rollbackPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $rollbackFailure = & docker run --rm --network $network --workdir /workspace --mount "type=bind,source=$root,target=/workspace,readonly" `
            liquibase/liquibase:4.31 "--url=jdbc:postgresql://${container}:5432/$fk" --username=test_user "--password=$password" `
            --changelog-file=changelog/changelog-master.yaml rollback-count --count 1 2>&1
        $rollbackExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $rollbackPreference }
    if ($rollbackExitCode -eq 0 -or ($rollbackFailure -join "`n") -notmatch 'Rollback 006 refused') {
        throw 'Rollback 006 must be blocked while professionals exist.'
    }
    A $fk "EXISTS (SELECT 1 FROM professional_management.professionals WHERE license_number='TEST-ROLLBACK-002-001') AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='professional_management' AND table_name='professionals' AND column_name='professional_type')" 'Rejected rollback must preserve the professional and columns.'
    P $fk "DELETE FROM professional_management.professionals WHERE license_number='TEST-ROLLBACK-002-001'"
    L $fk @('rollback-count', '--count', '1')
    A $fk "NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='professional_management' AND table_name='professionals' AND column_name='professional_type') AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='professional_management' AND table_name='professionals' AND column_name='status')" 'Rollback 006 must remove both lifecycle columns.'
    L $fk @('rollback-count', '--count', '1')
    A $fk "(SELECT count(*) FROM pg_constraint WHERE conname='fk_specialty_seed_ownership_specialty' AND confdeltype='a')=1" 'Rollback 005 must restore the ownership FK behavior.'
    L $fk @('rollback-count', '--count', '1')
    A $fk "to_regclass('professional_management.professionals') IS NULL AND (SELECT count(*) FROM professional_management.specialties)=7" 'Rollback 003 must remove professionals before seed rollback.'
    L $fk @('rollback-count', '--count', '1')
    A $fk "NOT EXISTS (SELECT 1 FROM professional_management.specialties WHERE name='Neurología') AND EXISTS (SELECT 1 FROM professional_management.specialties WHERE id=$generalId)" 'Rollback 004 changed the 002 specialty.'
    L $fk @('rollback-count', '--count', '1')
    A $fk "NOT EXISTS (SELECT 1 FROM professional_management.specialties WHERE id=$generalId)" 'Rollback 002 did not remove its owned specialty.'
    Write-Host 'PASS professional referencing a 002 specialty is removed before seed rollback.'

    $adminDelete = $databases[5]; NewDb $adminDelete; L $adminDelete @('update-count', '--count', '6')
    L $adminDelete @('update-count', '--count', '21')
    A $adminDelete "(SELECT count(*) FROM pg_constraint WHERE conname='fk_specialty_seed_ownership_specialty' AND confdeltype='c')=1" 'Ownership FK must cascade only its metadata row.'
    A $adminDelete "(SELECT count(*) FROM pg_constraint WHERE conname='fk_professional_specialty' AND confdeltype='r')=1" 'Professional FK must remain restrictive.'
    $ownedId = Scalar $adminDelete "SELECT id FROM professional_management.specialty WHERE name=$neurology"
    P $adminDelete "DELETE FROM professional_management.specialty WHERE id=$ownedId"
    Own $adminDelete '004-seed-additional-specialties' 2
    A $adminDelete "NOT EXISTS (SELECT 1 FROM professional_management.specialty WHERE id=$ownedId)" 'Administrator-deleted specialty remains.'
    $adminId = Scalar $adminDelete "INSERT INTO professional_management.specialty(name,description) VALUES ($neurology,'administrator replacement') RETURNING id"
    if ($adminId -eq $ownedId) { throw 'Replacement specialty unexpectedly reused the deleted ID.' }

    # Rolls back 20 changesets: the three DCL changesets, all three index
    # changesets, ddl-alter-018, ddl-alter-017, ddl-alter-016, ddl-alter-015,
    # ddl-alter-014, ddl-alter-013, ddl-alter-012, ddl-alter-009, ddl-tables-004,
    # ddl-alter-011, ddl-alter-010, ddl-alter-008, ddl-alter-007 and 006. That
    # reverts 012, which restores the historical plural table names, and 007, which
    # is a no-op. The tables stay in professional_management under their historical
    # plural names. 006 reverts cleanly here because the professionals table is
    # empty: the scenario deleted the only seed-created row and the replacement
    # specialty is unreferenced. The rollback of 006 also drops
    # idx_professionals_status, so the assertion below checks the historical name
    # is gone, not present.
    L $adminDelete @('rollback-count','--count','20')
    A $adminDelete "NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='professional_management' AND table_name='professionals' AND column_name IN ('professional_type','status')) AND NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='professional_management' AND tablename='professionals' AND indexname='idx_professionals_status') AND to_regclass('professional_management.professionals') IS NOT NULL AND to_regclass('professional_management.professional') IS NULL" 'Rollbacks through 006 must leave the plural tables in professional_management and drop the lifecycle columns and their index.'
    L $adminDelete @('rollback-count','--count','1')
    A $adminDelete "(SELECT count(*) FROM pg_constraint WHERE conname='fk_specialty_seed_ownership_specialty' AND confdeltype='a')=1" 'Ownership FK rollback must restore NO ACTION.'
    L $adminDelete @('rollback-count','--count','1')
    L $adminDelete @('rollback-count','--count','1'); Own $adminDelete '004-seed-additional-specialties' 0
    A $adminDelete "EXISTS (SELECT 1 FROM professional_management.specialties WHERE id=$adminId AND name=$neurology AND description='administrator replacement')" 'Seed rollback deleted the administrator replacement.'
    A $adminDelete "(SELECT count(*) FROM professional_management.specialties)=5" 'Seed rollback left unexpected specialty rows.'
    Write-Host 'PASS unused specialty deletion cascades metadata only; seed rollback preserves administrator replacement.'

    $transition = $databases[6]; NewDb $transition; L $transition @('update-count','--count','7')
    $transitionSpecialtyId = Scalar $transition "SELECT id FROM professional_management.specialties WHERE name='Medicina General'"
    P $transition "INSERT INTO professional_management.professionals(identity_user_id,license_number,specialty_id,years_experience) VALUES (900000099,'TEST-MIGRATION-TRANSITION-006',$transitionSpecialtyId,0)"
    L $transition @('update-count', '--count', '20')
    A $transition "EXISTS (SELECT 1 FROM professional_management.professional WHERE license_number='TEST-MIGRATION-TRANSITION-006' AND professional_type IS NULL AND status='ACTIVE')" 'Migration 006 must preserve unknown professional_type and default status to ACTIVE.'

    # Rolls back 19 changesets, leaving 006-add-professional-type-and-status as
    # the next one to revert so its refusal guard can be exercised.
    L $transition @('rollback-count', '--count', '19')

    $rollbackPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $rollbackFailure = & docker run --rm --network $network --workdir /workspace --mount "type=bind,source=$root,target=/workspace,readonly" `
            liquibase/liquibase:4.31 "--url=jdbc:postgresql://${container}:5432/$transition" --username=test_user "--password=$password" `
            --changelog-file=changelog/changelog-master.yaml rollback-count --count 1 2>&1
        $rollbackExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $rollbackPreference }
    if ($rollbackExitCode -eq 0 -or ($rollbackFailure -join "`n") -notmatch 'professionals contains records; removing professional_type and status could lose lifecycle data') {
        throw 'Rollback 006 must refuse to remove columns while any professional record exists.'
    }
    A $transition "EXISTS (SELECT 1 FROM professional_management.professionals WHERE license_number='TEST-MIGRATION-TRANSITION-006' AND professional_type IS NULL AND status='ACTIVE') AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='professional_management' AND table_name='professionals' AND column_name='professional_type') AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='professional_management' AND table_name='professionals' AND column_name='status') AND EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='professional_management' AND tablename='professionals' AND indexname='idx_professionals_status')" 'Rejected rollback must preserve the professional, columns, and status index.'
    Write-Host 'PASS migration 006 rollback is blocked without changing a professional or schema object.'

    # DEC-005 with data: professionals registered while the catalog existed keep
    # their profile, become general practitioners and lose only the specialty.
    $generalPractice = $databases[7]; NewDb $generalPractice; L $generalPractice @('update-count', '--count', '27')
    $pediatricsId = Scalar $generalPractice "SELECT id FROM professional_management.specialty WHERE name=U&'Pediatr\00EDa'"
    P $generalPractice "INSERT INTO professional_management.professional(identity_user_id,license_number,specialty_id,years_experience,professional_type,status) VALUES (900000201,'TEST-DEC-005-SPECIALIST',$pediatricsId,4,'SPECIALIST','INACTIVE'),(900000202,'TEST-DEC-005-UNCLASSIFIED',$pediatricsId,1,NULL,'ACTIVE')"
    L $generalPractice @('update')
    GeneralPractice $generalPractice
    A $generalPractice "(SELECT count(*) FROM professional_management.professional WHERE license_number IN ('TEST-DEC-005-SPECIALIST','TEST-DEC-005-UNCLASSIFIED') AND professional_type='GENERAL_PRACTITIONER')=2 AND EXISTS (SELECT 1 FROM professional_management.professional WHERE license_number='TEST-DEC-005-SPECIALIST' AND years_experience=4 AND status='INACTIVE')" 'DEC-005 must keep every professional and make it a general practitioner.'
    # Rolls back DEC-006 (four changesets) and DEC-005 (three).
    L $generalPractice @('rollback-count', '--count', '7')
    $restoredGeneralId = Scalar $generalPractice "SELECT id FROM professional_management.specialty WHERE name='Medicina General'"
    A $generalPractice "(SELECT count(*) FROM professional_management.professional WHERE license_number IN ('TEST-DEC-005-SPECIALIST','TEST-DEC-005-UNCLASSIFIED') AND specialty_id=$restoredGeneralId)=2" 'Rollback of DEC-005 must assign the restored Medicina General to every professional.'
    Seven $generalPractice
    A $generalPractice "(SELECT count(*) FROM professional_management.professional WHERE identity_user_id IN (900000201,900000202))=2" 'Rolling back DEC-006 must restore the original numeric account references.'
    Write-Host 'PASS DEC-005 keeps professionals as general practitioners and rolls back to the seeded catalog.'

    # DEC-006 with data: identifiers become UUID with a reversible mapping, a new
    # professional gets a generated UUID, and the rollback refuses to invent a
    # number for a real UUID.
    $uuid = $databases[8]; NewDb $uuid; L $uuid @('update-count', '--count', '30')
    $oldId = Scalar $uuid "INSERT INTO professional_management.professional(identity_user_id,license_number,years_experience) VALUES (900000301,'TEST-DEC-006-001',2) RETURNING id"
    P $uuid "INSERT INTO professional_management.idempotency_key(key,professional_id,request_hash) VALUES ('dec-006-key-0001',$oldId,'hash')"
    L $uuid @('update')
    $mapped = "('00000000-0000-0000-0000-' || lpad(to_hex($oldId::bigint), 12, '0'))::uuid"
    A $uuid "EXISTS (SELECT 1 FROM professional_management.professional WHERE id=$mapped AND identity_user_id='00000000-0000-0000-0000-' || lpad(to_hex(900000301), 12, '0') AND license_number='TEST-DEC-006-001' AND years_experience=2)" 'DEC-006 must map the bigint identifiers to UUID without losing the profile.'
    A $uuid "EXISTS (SELECT 1 FROM professional_management.idempotency_key WHERE key='dec-006-key-0001' AND professional_id=$mapped AND request_hash='hash')" 'DEC-006 must keep each idempotency key on its professional.'
    P $uuid "INSERT INTO professional_management.professional(identity_user_id,license_number,years_experience) VALUES ('b0000000-0000-4000-8000-000000000301','TEST-DEC-006-002',0)"
    A $uuid "(SELECT count(*) FROM professional_management.professional WHERE license_number='TEST-DEC-006-002' AND id IS NOT NULL AND id::text NOT LIKE '00000000-0000-0000-0000-%')=1" 'A new professional must get a generated UUID.'
    $rollbackPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $rollbackFailure = & docker run --rm --network $network --workdir /workspace --mount "type=bind,source=$root,target=/workspace,readonly" `
            liquibase/liquibase:4.31 "--url=jdbc:postgresql://${container}:5432/$uuid" --username=test_user "--password=$password" `
            --changelog-file=changelog/changelog-master.yaml rollback-count --count 2 2>&1
        $rollbackExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $rollbackPreference }
    if ($rollbackExitCode -eq 0 -or ($rollbackFailure -join "`n") -notmatch 'Rollback ddl-alter-024 refused') {
        throw 'Rollback ddl-alter-024 must refuse while a UUID has no numeric equivalent.'
    }
    A $uuid "(SELECT count(*) FROM professional_management.professional)=2 AND (SELECT data_type FROM information_schema.columns WHERE table_schema='professional_management' AND table_name='professional' AND column_name='id')='uuid'" 'A refused rollback must leave the UUID schema and its rows.'
    P $uuid "DELETE FROM professional_management.professional WHERE license_number='TEST-DEC-006-002'"
    L $uuid @('rollback-count', '--count', '4')
    A $uuid "EXISTS (SELECT 1 FROM professional_management.professional WHERE id=$oldId AND identity_user_id=900000301) AND EXISTS (SELECT 1 FROM professional_management.idempotency_key WHERE key='dec-006-key-0001' AND professional_id=$oldId)" 'Rollback of DEC-006 must restore the original bigint identifiers.'
    $nextId = Scalar $uuid "INSERT INTO professional_management.professional(identity_user_id,license_number,years_experience) VALUES (900000302,'TEST-DEC-006-003',0) RETURNING id"
    if ($nextId -le $oldId) { throw 'The re-created sequence must continue after the highest restored id.' }
    Write-Host 'PASS DEC-006 maps identifiers to UUID reversibly and refuses an irreversible rollback.'
} finally {
    $oldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        if ($containerCreated) { & docker rm -fv $container *> $null }
        if ($networkCreated) { & docker network rm $network *> $null }
        if (Test-Path $scratchRoot) { Remove-Item $scratchRoot -Recurse -Force }
    } finally { $ErrorActionPreference = $oldEap }
}

Write-Host 'PASS all seed rollback integration scenarios.'
