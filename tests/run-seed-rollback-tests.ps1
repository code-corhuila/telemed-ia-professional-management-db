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
    @($databases | Where-Object { $_ -notmatch "^seed_.+_$id$" }).Count -ne $kinds.Count -or
    @($databases | Select-Object -Unique).Count -ne $kinds.Count) {
    throw 'Test database names must be unique and include this run identifier.'
}
$scratch = Join-Path $env:TEMP $network
$legacyRoot = Join-Path $scratch 'legacy'
$passwordBytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($passwordBytes) } finally { $rng.Dispose() }
$password = [Convert]::ToBase64String($passwordBytes)
$fixture = 'pre-existing audit fixture'
$neurology = "U&'Neurolog\00EDa'"
$legacyMode = $false
$containerCreated = $false
$networkCreated = $false

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker is required.' }

function D([string[]]$dockerArgs) {
    & docker @dockerArgs
    if ($LASTEXITCODE -ne 0) { throw "Docker failed: $($dockerArgs -join ' ')" }
}
function P([string]$db, [string]$sql) {
    D @('exec', $container, 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
        '-U', 'test_user', '-d', $db, '-c', $sql)
}
function A([string]$db, [string]$condition, [string]$message) {
    $escaped = $message.Replace("'", "''")
    P $db "DO `$`$ BEGIN IF NOT ($condition) THEN RAISE EXCEPTION '$escaped'; END IF; END; `$`$;"
}
function Scalar([string]$db, [string]$sql) {
    $value = & docker exec $container psql -X -qAt -v ON_ERROR_STOP=1 -U test_user -d $db -c $sql
    if ($LASTEXITCODE -ne 0) { throw "Could not query $db." }
    return [long](($value | Where-Object { "$_".Trim() -match '^\d+$' } | Select-Object -Last 1).Trim())
}
function NewDb([string]$db) { P 'postgres' "CREATE DATABASE $db" }
function L([string]$db, [string[]]$command) {
    if ($legacyMode) {
        $source = Join-Path $legacyRoot 'db\changelog'
        $mount = "type=bind,source=$source,target=/liquibase/changelog,readonly"
        $work = '/liquibase/changelog'
        $file = 'db.changelog-master.yaml'
    } else {
        $mount = "type=bind,source=$root,target=/workspace,readonly"
        $work = '/workspace'
        $file = 'changelog/changelog-master.yaml'
    }
    D (@('run', '--rm', '--network', $network, '--workdir', $work, '--mount', $mount,
        'liquibase/liquibase:4.31', "--url=jdbc:postgresql://${container}:5432/$db",
        '--username=test_user', "--password=$password", "--changelog-file=$file") + $command)
}
function Own([string]$db, [string]$changeset, [int]$count) {
    A $db "(SELECT count(*) FROM specialty_seed_ownership WHERE changeset_id='$changeset')=$count" "Ownership mismatch: $changeset"
}
function Schema([string]$db) {
    D @('exec', $container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U',
        'test_user', '-d', $db, '--file=/tests/professional-schema-tests.sql')
}
function Collision([string]$db, [string]$name, [string]$nameSql, [string]$change,
    [int]$owned, [int]$rows, [int]$prefix) {
    NewDb $db
    L $db @('update-count', '--count', "$prefix")
    $id = Scalar $db "INSERT INTO specialties(name,description) VALUES ($nameSql,'$fixture') RETURNING id"
    L $db @('update-count', '--count', '1')
    A $db "EXISTS (SELECT 1 FROM specialties WHERE id=$id AND description='$fixture') AND NOT EXISTS (SELECT 1 FROM specialty_seed_ownership WHERE changeset_id='$change' AND specialty_id=$id)" "Pre-existing $name was changed or claimed."
    Own $db $change $owned
    L $db @('rollback-count', '--count', '1')
    A $db "EXISTS (SELECT 1 FROM specialties WHERE id=$id AND description='$fixture') AND (SELECT count(*) FROM specialties)=$rows" "$name rollback removed pre-existing data or left owned rows."
    Own $db $change 0
    Write-Host "PASS $change collision preserves pre-existing data and removes owned rows."
}

try {
    D @('network', 'create', $network); $networkCreated = $true
    D @('run', '-d', '--name', $container, '--network', $network, '-e', 'POSTGRES_USER=test_user',
        '-e', "POSTGRES_PASSWORD=$password", '-e', 'POSTGRES_DB=postgres', '--mount',
        "type=bind,source=$root\tests\sql,target=/tests,readonly", 'postgres:16-alpine')
    $containerCreated = $true
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        & docker exec $container pg_isready -U test_user -d postgres *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) { throw 'Disposable PostgreSQL did not become ready.' }

    $fresh = $databases[0]; NewDb $fresh; L $fresh @('update'); L $fresh @('validate')
    A $fresh "(SELECT count(*) FROM databasechangelog)=6" 'Fresh update did not apply six changesets.'
    Own $fresh '002-seed-specialties' 4; Own $fresh '004-seed-additional-specialties' 3
    Schema $fresh; L $fresh @('update')
    A $fresh "(SELECT count(*) FROM databasechangelog)=6 AND (SELECT count(*) FROM specialties)=7" 'Second update was not idempotent.'
    Write-Host 'PASS fresh update, schema, ownership, and idempotent second update.'

    L $fresh @('rollback-count', '--count', '1')
    L $fresh @('rollback-count', '--count', '1')
    A $fresh "to_regclass('public.professionals') IS NULL AND (SELECT count(*) FROM specialties)=7" 'Professional table must roll back before the seeds.'
    L $fresh @('rollback-count', '--count', '1')
    A $fresh "(SELECT count(*) FROM specialties)=4" 'Rollback 004 did not leave 002 rows.'
    Own $fresh '004-seed-additional-specialties' 0; Own $fresh '002-seed-specialties' 4
    L $fresh @('rollback-count', '--count', '1')
    A $fresh "(SELECT count(*) FROM specialties)=0" 'Rollback 002 left owned rows.'
    L $fresh @('rollback-count', '--count', '1')
    A $fresh "to_regclass('public.specialty_seed_ownership') IS NULL" 'Ownership ledger remains after rollback.'
    L $fresh @('rollback-count', '--count', '1')
    A $fresh "to_regclass('public.specialties') IS NULL" 'Changeset 001 did not remove specialties.'
    L $fresh @('update'); Schema $fresh
    A $fresh "(SELECT count(*) FROM databasechangelog)=6 AND (SELECT count(*) FROM specialties)=7" 'Reapplication did not restore the schema.'
    Write-Host 'PASS staged rollback and reapplication.'

    $full = $databases[1]; NewDb $full; L $full @('update'); L $full @('rollback-count', '--count', '6')
    A $full "to_regclass('public.specialties') IS NULL AND to_regclass('public.professionals') IS NULL AND to_regclass('public.specialty_seed_ownership') IS NULL AND (SELECT count(*) FROM databasechangelog)=0" 'Full rollback left schema or history.'
    L $full @('update'); Schema $full
    Write-Host 'PASS complete rollback and reapplication.'

    Collision $databases[2] 'Medicina General' "'Medicina General'" '002-seed-specialties' 3 1 2
    Collision $databases[3] 'Neurología' $neurology '004-seed-additional-specialties' 2 5 3

    $legacy = $databases[4]; NewDb $legacy
    New-Item -ItemType Directory -Path (Join-Path $legacyRoot 'db\changelog') -Force | Out-Null
    Copy-Item (Join-Path $root 'tests\fixtures\legacy-changelog\*') (Join-Path $legacyRoot 'db\changelog') -Recurse
    $legacyMode = $true; L $legacy @('update'); $legacyMode = $false
    A $legacy "(SELECT count(*) FROM databasechangelog WHERE (id='002-seed-specialties' AND md5sum='9:f5719d18ef7771621c69be4f04fb4e73') OR (id='004-seed-additional-specialties' AND md5sum='9:3df6ef3fc67dc17d4114f63e16325e7a'))=2" 'Legacy seed checksums differ.'
    L $legacy @('validate'); L $legacy @('update')
    A $legacy "to_regclass('public.specialty_seed_ownership') IS NOT NULL AND (SELECT count(*) FROM specialty_seed_ownership)=0" 'Legacy rows must not be backfilled.'
    A $legacy "(SELECT count(*) FROM specialties)=7 AND (SELECT count(*) FROM databasechangelog)=6" 'Legacy forward update did not preserve the existing catalog and add new migrations.'
    L $legacy @('rollback-count', '--count', '1'); L $legacy @('rollback-count', '--count', '1')
    L $legacy @('rollback-count', '--count', '1')
    A $legacy "(SELECT count(*) FROM databasechangelog WHERE id='004-seed-additional-specialties')=0 AND (SELECT count(*) FROM specialties)=7" 'Legacy 004 rollback must remove history but preserve unowned rows.'
    L $legacy @('rollback-count', '--count', '1')
    A $legacy "to_regclass('public.professionals') IS NULL AND (SELECT count(*) FROM specialties)=7" 'Legacy 003 rollback changed the catalog or retained professionals.'
    L $legacy @('rollback-count', '--count', '1')
    A $legacy "(SELECT count(*) FROM databasechangelog WHERE id='002-seed-specialties')=0 AND (SELECT count(*) FROM specialties)=7" 'Legacy 002 rollback must remove history but preserve unowned rows.'
    L $legacy @('rollback-count', '--count', '1')
    A $legacy "to_regclass('public.specialties') IS NULL AND (SELECT count(*) FROM databasechangelog)=0" 'Complete legacy rollback did not remove the schema.'
    Write-Host 'PASS legacy forward compatibility; rollback preserves unowned seed rows until full table rollback.'

    $legacyFk = $databases[7]; NewDb $legacyFk
    $legacyMode = $true; L $legacyFk @('update')
    $neuroId = Scalar $legacyFk "SELECT id FROM specialties WHERE name=$neurology"
    P $legacyFk "INSERT INTO professionals(identity_user_id,license_number,specialty_id) VALUES (900000002,'TEST-LEGACY-FK-001',$neuroId)"
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
    Write-Host 'PASS legacy FK blocks destructive rollback until reference is removed.'

    $fk = $databases[5]; NewDb $fk; L $fk @('update')
    $generalId = Scalar $fk "SELECT id FROM specialties WHERE name='Medicina General'"
    P $fk "INSERT INTO professionals(identity_user_id,license_number,specialty_id) VALUES (900000001,'TEST-ROLLBACK-002-001',$generalId)"
    L $fk @('rollback-count', '--count', '2')
    A $fk "to_regclass('public.professionals') IS NULL AND EXISTS (SELECT 1 FROM specialties WHERE id=$generalId)" 'Professional must roll back before the referenced 002 specialty.'
    L $fk @('rollback-count', '--count', '1')
    A $fk "NOT EXISTS (SELECT 1 FROM specialties WHERE name='Neurología') AND EXISTS (SELECT 1 FROM specialties WHERE id=$generalId)" 'Rollback 004 changed the 002 specialty.'
    L $fk @('rollback-count', '--count', '1')
    A $fk "NOT EXISTS (SELECT 1 FROM specialties WHERE id=$generalId)" 'Rollback 002 did not remove its owned specialty.'
    Write-Host 'PASS a professional referencing 002 is removed before specialty seed rollback.'

    $admin = $databases[6]; NewDb $admin; L $admin @('update'); Schema $admin
    A $admin "(SELECT count(*) FROM pg_constraint WHERE conname='fk_specialty_seed_ownership_specialty' AND confdeltype='c')=1 AND (SELECT count(*) FROM pg_constraint WHERE conname='fk_professionals_specialty' AND confdeltype='r')=1" 'Specialty foreign key delete behavior is incorrect.'
    $ownedId = Scalar $admin "SELECT id FROM specialties WHERE name=$neurology"
    P $admin "DELETE FROM specialties WHERE id=$ownedId"
    Own $admin '004-seed-additional-specialties' 2
    $replacement = Scalar $admin "INSERT INTO specialties(name,description) VALUES ($neurology,'administrator replacement') RETURNING id"
    L $admin @('rollback-count', '--count', '1'); L $admin @('rollback-count', '--count', '1')
    L $admin @('rollback-count', '--count', '1')
    A $admin "EXISTS (SELECT 1 FROM specialties WHERE id=$replacement AND description='administrator replacement') AND (SELECT count(*) FROM specialties)=5" 'Seed rollback removed administrator data or left seed rows.'
    Write-Host 'PASS specialty deletion removes ownership metadata only; rollback preserves administrator replacement.'
} finally {
    if ($containerCreated) { D @('rm', '-fv', $container) }
    if ($networkCreated) { D @('network', 'rm', $network) }
    if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
}

Write-Host 'PASS all seed rollback integration scenarios.'
