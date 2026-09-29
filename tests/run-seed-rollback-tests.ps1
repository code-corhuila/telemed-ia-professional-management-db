[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$id = [Guid]::NewGuid().ToString('N').Substring(0, 12)
$network = "seed-rollback-$id"
$container = "$network-postgres"
$kinds = @('fresh', 'full', 'collision002', 'collision004', 'legacy', 'fk', 'admindelete', 'legacyfk')
$databases = @($kinds | ForEach-Object { "seed_${_}_$id" })
if ($databases.Count -ne $kinds.Count -or
    @($databases | Where-Object { $_ -notmatch "^seed_.+_$id$" }).Count -ne 0 -or
    @($databases | Select-Object -Unique).Count -ne $kinds.Count) {
    throw 'Test database names must be unique and include this run identifier.'
}
$scratchRoot = Join-Path $env:TEMP $network
$legacyRoot = Join-Path $scratchRoot 'legacy'
$passwordBytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($passwordBytes) } finally { $rng.Dispose() }
$password = [Convert]::ToBase64String($passwordBytes)
$fixture = 'pre-existing audit fixture'
$neurology = "U&'Neurolog\00EDa'"
$legacyMode = $false
$networkCreated = $false
$containerCreated = $false

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker is required.' }

function D([string[]]$DockerArgs) {
    & docker @DockerArgs
    if ($LASTEXITCODE -ne 0) { throw "Docker failed: $($DockerArgs -join ' ')" }
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
    if ($legacyMode) {
        $source = Join-Path $legacyRoot 'db\changelog'
        $target = '/liquibase/changelog'
        $work = $target
        $file = 'db.changelog-master.yaml'
    } else {
        $source = $root
        $target = '/workspace'
        $work = $target
        $file = 'changelog/changelog-master.yaml'
    }
    $mount = "type=bind,source=$source,target=$target,readonly"
    D (@('run', '--rm', '--network', $network, '--workdir', $work, '--mount', $mount,
        'liquibase/liquibase:4.31', "--url=jdbc:postgresql://${container}:5432/$Db",
        '--username=test_user', "--password=$password", "--changelog-file=$file") + $Command)
}
function A([string]$Db, [string]$Condition, [string]$Message) {
    $message = $Message.Replace("'", "''")
    P $Db "DO `$`$ BEGIN IF NOT ($Condition) THEN RAISE EXCEPTION '$message'; END IF; END; `$`$;"
}
function Own([string]$Db, [string]$Change, [int]$Count) {
    A $Db "(SELECT count(*) FROM specialty_seed_ownership WHERE changeset_id='$Change')=$Count" "Ownership mismatch: $Change"
}
function FixtureRow([string]$Db, [long]$SpecialtyId) {
    A $Db "EXISTS (SELECT 1 FROM specialties WHERE id=$SpecialtyId AND description='$fixture')" "Fixture row changed: $SpecialtyId"
}
function Scalar([string]$Db, [string]$Sql) {
    $out = & docker exec $container psql -X -q -t -A -v ON_ERROR_STOP=1 -U test_user -d $Db -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "Could not query $Db." }
    return [long](($out | Where-Object { "$_".Trim() -match '^\d+$' } | Select-Object -Last 1).Trim())
}
function NewDb([string]$Db) { P 'postgres' "CREATE DATABASE $Db;" }
function Seven([string]$Db) { A $Db '(SELECT count(*) FROM specialties)=7' 'Expected seven specialties.' }
function Collision([string]$Db, [string]$Name, [string]$NameSql, [string]$Change, [int]$ExpectedOwned, [int]$ExpectedRows, [int]$PrefixCount) {
    NewDb $Db
    L $Db @('update-count', '--count', "$PrefixCount")
    $specialtyId = Scalar $Db "INSERT INTO specialties(name,description) VALUES ($NameSql,'$fixture') RETURNING id"
    L $Db @('update-count', '--count', '1')
    FixtureRow $Db $specialtyId
    A $Db "NOT EXISTS (SELECT 1 FROM specialty_seed_ownership WHERE changeset_id='$Change' AND specialty_id=$specialtyId)" "Pre-existing $Name was claimed."
    Own $Db $Change $ExpectedOwned
    L $Db @('rollback-count', '--count', '1')
    FixtureRow $Db $specialtyId
    A $Db "(SELECT count(*) FROM specialties)=$ExpectedRows" "$Name rollback left unexpected rows."
    Own $Db $Change 0
    Write-Host "PASS $Change collision preserves pre-existing row and removes owned rows."
}

try {
    D @('network', 'create', $network)
    $networkCreated = $true
    D @('run', '-d', '--name', $container, '--network', $network,
        '-e', 'POSTGRES_USER=test_user', '-e', "POSTGRES_PASSWORD=$password",
        '-e', 'POSTGRES_DB=postgres', '--mount',
        "type=bind,source=$root\tests\sql,target=/tests,readonly", 'postgres:16-alpine')
    $containerCreated = $true
    $ready = $false
    for ($i=0; $i -lt 60; $i++) {
        & docker exec $container pg_isready -U test_user -d postgres *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep 2
    }
    if (-not $ready) { throw 'Disposable PostgreSQL did not become ready.' }

    $fresh = $databases[0]; NewDb $fresh; L $fresh @('update'); L $fresh @('validate')
    A $fresh "(SELECT count(*) FROM databasechangelog WHERE id IN ('001-create-specialties','001a-create-specialty-seed-ownership','002-seed-specialties','003-create-professionals','004-seed-additional-specialties','005-cascade-deleted-specialty-ownership','006-add-professional-type-and-status'))=7" 'Expected seven changesets.'
    Seven $fresh; Own $fresh '002-seed-specialties' 4; Own $fresh '004-seed-additional-specialties' 3
    Schema $fresh
    L $fresh @('update')
    A $fresh '(SELECT count(*) FROM databasechangelog)=7' 'Second update applied additional changesets.'
    Seven $fresh; Own $fresh '002-seed-specialties' 4; Own $fresh '004-seed-additional-specialties' 3
    Write-Host 'PASS second update is idempotent.'

    L $fresh @('rollback-count','--count','1')
    A $fresh "EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='professionals' AND column_name='professional_type')=false AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='professionals' AND column_name='status')=false AND to_regclass('public.professionals') IS NOT NULL" 'Rollback 006 must remove its columns but retain professionals.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM pg_constraint WHERE conname='fk_specialty_seed_ownership_specialty' AND confdeltype='a')=1" 'Rollback 005 must restore the ownership FK behavior.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "to_regclass('public.professionals') IS NULL AND (SELECT count(*) FROM specialties)=7" 'Rollback 003 must remove professionals before seed rollback.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM specialties)=4" 'Rollback 004 did not retain 002 rows.'
    Own $fresh '004-seed-additional-specialties' 0; Own $fresh '002-seed-specialties' 4
    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM specialties)=0" '002-owned rows remain.'
    Own $fresh '002-seed-specialties' 0
    L $fresh @('rollback-count','--count','1')
    A $fresh "to_regclass('public.specialty_seed_ownership') IS NULL" 'Ownership table remains.'
    L $fresh @('rollback-count','--count','1')
    A $fresh "to_regclass('public.specialties') IS NULL" '001 did not remove specialties.'
    L $fresh @('update'); Seven $fresh
    Own $fresh '002-seed-specialties' 4; Own $fresh '004-seed-additional-specialties' 3
    Schema $fresh
    Write-Host 'PASS fresh apply, ownership, staged rollbacks, reapply, and schema tests.'

    $full = $databases[1]; NewDb $full; L $full @('update'); L $full @('rollback-count','--count','7')
    A $full "to_regclass('public.specialties') IS NULL AND to_regclass('public.professionals') IS NULL AND to_regclass('public.specialty_seed_ownership') IS NULL" 'Full rollback left domain tables.'
    A $full "(SELECT count(*) FROM databasechangelog WHERE id IN ('001-create-specialties','001a-create-specialty-seed-ownership','002-seed-specialties','003-create-professionals','004-seed-additional-specialties','005-cascade-deleted-specialty-ownership','006-add-professional-type-and-status'))=0" 'Full rollback left changeset history.'
    L $full @('update'); Seven $full
    Own $full '002-seed-specialties' 4; Own $full '004-seed-additional-specialties' 3
    Schema $full
    Write-Host 'PASS rollback-count=7, table/history removal, reapply, and schema tests.'

    Collision $databases[2] 'Medicina General' "'Medicina General'" '002-seed-specialties' 3 1 2
    Collision $databases[3] 'Neurología' $neurology '004-seed-additional-specialties' 2 5 3

    $legacy = $databases[4]; NewDb $legacy
    New-Item -ItemType Directory -Path (Join-Path $legacyRoot 'db\changelog') -Force | Out-Null
    Copy-Item (Join-Path $root 'tests\fixtures\legacy-changelog\*') (Join-Path $legacyRoot 'db\changelog') -Recurse
    $legacyMode = $true; L $legacy @('update')
    A $legacy "(SELECT count(*) FROM databasechangelog WHERE (id='002-seed-specialties' AND md5sum='9:f5719d18ef7771621c69be4f04fb4e73') OR (id='004-seed-additional-specialties' AND md5sum='9:3df6ef3fc67dc17d4114f63e16325e7a'))=2" 'Legacy checksums differ from expected.'
    $legacyMode = $false; L $legacy @('validate'); L $legacy @('update')
    A $legacy "to_regclass('public.specialty_seed_ownership') IS NOT NULL AND (SELECT count(*) FROM specialty_seed_ownership)=0" 'Legacy rows were backfilled.'
    Seven $legacy
    L $legacy @('rollback-count', '--count', '1')
    L $legacy @('rollback-count', '--count', '1')
    L $legacy @('rollback-count', '--count', '1')
    L $legacy @('rollback-count', '--count', '1')
    A $legacy "(SELECT count(*) FROM databasechangelog WHERE id='004-seed-additional-specialties')=0 AND (SELECT count(*) FROM specialties)=7" 'Legacy 004 rollback must remove history but preserve unowned rows.'
    L $legacy @('rollback-count', '--count', '1')
    A $legacy "to_regclass('public.professionals') IS NULL AND (SELECT count(*) FROM specialties)=7" 'Legacy 003 rollback changed the catalog or retained professionals.'
    L $legacy @('rollback-count', '--count', '1')
    A $legacy "(SELECT count(*) FROM databasechangelog WHERE id='002-seed-specialties')=0 AND (SELECT count(*) FROM specialties)=7" 'Legacy 002 rollback must remove history but preserve unowned rows.'
    Write-Host 'PASS legacy rollback removes migration history but preserves unowned seed rows.'

    $legacyFk = $databases[7]; NewDb $legacyFk
    $legacyMode = $true; L $legacyFk @('update')
    $neuroId = Scalar $legacyFk "SELECT id FROM specialties WHERE name=$neurology"
    P $legacyFk "INSERT INTO professionals(identity_user_id,license_number,specialty_id,years_experience) VALUES (900000002,'TEST-LEGACY-FK-001',$neuroId,0)"
    $legacyMount = "type=bind,source=$(Join-Path $legacyRoot 'db\changelog'),target=/liquibase/changelog,readonly"
    $legacyArgs = @('run', '--rm', '--network', $network, '--workdir', '/liquibase/changelog', '--mount', $legacyMount,
        'liquibase/liquibase:4.31', "--url=jdbc:postgresql://${container}:5432/$legacyFk", '--username=test_user',
        "--password=$password", '--changelog-file=db.changelog-master.yaml', 'rollback-count', '--count', '1')
    $oldPreference = $ErrorActionPreference
    try { $ErrorActionPreference = 'Continue'; $failure = & docker @legacyArgs 2>&1; $exitCode = $LASTEXITCODE }
    finally { $ErrorActionPreference = $oldPreference }
    if ($exitCode -eq 0 -or ($failure -join "`n") -notmatch 'fk_professionals_specialty') { throw 'Expected legacy seed rollback to be blocked by the professional FK.' }
    A $legacyFk "EXISTS (SELECT 1 FROM professionals WHERE license_number='TEST-LEGACY-FK-001') AND EXISTS (SELECT 1 FROM specialties WHERE id=$neuroId) AND EXISTS (SELECT 1 FROM databasechangelog WHERE id='004-seed-additional-specialties')" 'Blocked legacy rollback changed data or history.'
    P $legacyFk "DELETE FROM professionals WHERE license_number='TEST-LEGACY-FK-001'"
    L $legacyFk @('rollback-count', '--count', '1')
    A $legacyFk "NOT EXISTS (SELECT 1 FROM specialties WHERE id=$neuroId)" 'Legacy rollback did not remove the now-unreferenced row.'
    $legacyMode = $false
    Write-Host 'PASS historical FK blocks rollback until the professional reference is removed.'

    $fk = $databases[5]; NewDb $fk; L $fk @('update')
    $generalId = Scalar $fk "SELECT id FROM specialties WHERE name='Medicina General'"
    P $fk "INSERT INTO professionals(identity_user_id,license_number,specialty_id,years_experience,professional_type,status) VALUES (900000001,'TEST-ROLLBACK-002-001',$generalId,0,'GENERAL_PRACTITIONER','ACTIVE')"
    L $fk @('rollback-count', '--count', '3')
    A $fk "to_regclass('public.professionals') IS NULL AND EXISTS (SELECT 1 FROM specialties WHERE id=$generalId)" 'Professional must roll back before its referenced 002 specialty.'
    L $fk @('rollback-count', '--count', '1')
    A $fk "NOT EXISTS (SELECT 1 FROM specialties WHERE name='Neurología') AND EXISTS (SELECT 1 FROM specialties WHERE id=$generalId)" 'Rollback 004 changed the 002 specialty.'
    L $fk @('rollback-count', '--count', '1')
    A $fk "NOT EXISTS (SELECT 1 FROM specialties WHERE id=$generalId)" 'Rollback 002 did not remove its owned specialty.'
    Write-Host 'PASS professional referencing a 002 specialty is removed before seed rollback.'

    $adminDelete = $databases[6]; NewDb $adminDelete; L $adminDelete @('update-count', '--count', '6')
    $backfillSpecialtyId = Scalar $adminDelete "SELECT id FROM specialties WHERE name='Medicina General'"
    P $adminDelete "INSERT INTO professionals(identity_user_id,license_number,specialty_id,years_experience) VALUES (900000099,'TEST-MIGRATION-BACKFILL-006',$backfillSpecialtyId,0)"
    L $adminDelete @('update'); Schema $adminDelete
    A $adminDelete "EXISTS (SELECT 1 FROM professionals WHERE license_number='TEST-MIGRATION-BACKFILL-006' AND professional_type='GENERAL_PRACTITIONER' AND status='ACTIVE')" 'Migration 006 did not initialize existing professional values.'
    A $adminDelete "(SELECT count(*) FROM pg_constraint WHERE conname='fk_specialty_seed_ownership_specialty' AND confdeltype='c')=1" 'Ownership FK must cascade only its metadata row.'
    A $adminDelete "(SELECT count(*) FROM pg_constraint WHERE conname='fk_professionals_specialty' AND confdeltype='r')=1" 'Professional FK must remain restrictive.'
    $ownedId = Scalar $adminDelete "SELECT id FROM specialties WHERE name=$neurology"
    P $adminDelete "DELETE FROM specialties WHERE id=$ownedId"
    Own $adminDelete '004-seed-additional-specialties' 2
    A $adminDelete "NOT EXISTS (SELECT 1 FROM specialties WHERE id=$ownedId)" 'Administrator-deleted specialty remains.'
    $adminId = Scalar $adminDelete "INSERT INTO specialties(name,description) VALUES ($neurology,'administrator replacement') RETURNING id"
    if ($adminId -eq $ownedId) { throw 'Replacement specialty unexpectedly reused the deleted ID.' }
    L $adminDelete @('rollback-count','--count','1')
    A $adminDelete "to_regclass('public.professionals') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='professionals' AND column_name IN ('professional_type','status'))" 'Rollback 006 must remove its columns while retaining professionals.'
    L $adminDelete @('rollback-count','--count','1')
    A $adminDelete "(SELECT count(*) FROM pg_constraint WHERE conname='fk_specialty_seed_ownership_specialty' AND confdeltype='a')=1" 'Ownership FK rollback must restore NO ACTION.'
    L $adminDelete @('rollback-count','--count','1')
    L $adminDelete @('rollback-count','--count','1'); Own $adminDelete '004-seed-additional-specialties' 0
    A $adminDelete "EXISTS (SELECT 1 FROM specialties WHERE id=$adminId AND name=$neurology AND description='administrator replacement')" 'Seed rollback deleted the administrator replacement.'
    A $adminDelete "(SELECT count(*) FROM specialties)=5" 'Seed rollback left unexpected specialty rows.'
    Write-Host 'PASS unused specialty deletion cascades metadata only; seed rollback preserves administrator replacement.'
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
