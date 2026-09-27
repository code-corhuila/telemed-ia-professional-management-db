[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$id = [Guid]::NewGuid().ToString('N').Substring(0, 12)
$network = "seed-rollback-$id"
$container = "$network-postgres"
$databases = @('fresh', 'full', 'collision002', 'collision004', 'legacy', 'fk' |
    ForEach-Object { "seed_${_}_$id" })
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
function L([string]$Db, [string[]]$Command, [string]$File = 'db.changelog-master.yaml') {
    $source = if ($legacyMode) { Join-Path $legacyRoot 'db\changelog' } else { Join-Path $root 'db\changelog' }
    $mount = "type=bind,source=$source,target=/liquibase/changelog,readonly"
    D (@('run', '--rm', '--network', $network, '--workdir', '/liquibase/changelog',
        '--mount', $mount, 'liquibase/liquibase:4.31',
        "--url=jdbc:postgresql://${container}:5432/$Db", '--username=test_user',
        "--password=$password", "--changelog-file=$File") + $Command)
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
    A $fresh "(SELECT count(*) FROM databasechangelog WHERE id IN ('001-create-specialties','001a-create-specialty-seed-ownership','002-seed-specialties','003-create-professionals','004-seed-additional-specialties'))=5" 'Expected five changesets.'
    Seven $fresh; Own $fresh '002-seed-specialties' 4; Own $fresh '004-seed-additional-specialties' 3
    Schema $fresh

    L $fresh @('rollback-count','--count','1')
    A $fresh "(SELECT count(*) FROM specialties)=4" 'Rollback 004 did not retain 002 rows.'
    Own $fresh '004-seed-additional-specialties' 0; Own $fresh '002-seed-specialties' 4
    L $fresh @('rollback-count','--count','1')
    A $fresh "to_regclass('public.professionals') IS NULL" '003 must roll back before 002.'
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

    $full = $databases[1]; NewDb $full; L $full @('update'); L $full @('rollback-count','--count','5')
    A $full "to_regclass('public.specialties') IS NULL AND to_regclass('public.professionals') IS NULL AND to_regclass('public.specialty_seed_ownership') IS NULL" 'Full rollback left domain tables.'
    A $full "(SELECT count(*) FROM databasechangelog WHERE id IN ('001-create-specialties','001a-create-specialty-seed-ownership','002-seed-specialties','003-create-professionals','004-seed-additional-specialties'))=0" 'Full rollback left changeset history.'
    L $full @('update'); Seven $full
    Own $full '002-seed-specialties' 4; Own $full '004-seed-additional-specialties' 3
    Schema $full
    Write-Host 'PASS rollback-count=5, table/history removal, reapply, and schema tests.'

    Collision $databases[2] 'Medicina General' "'Medicina General'" '002-seed-specialties' 3 1 2
    Collision $databases[3] 'Neurología' $neurology '004-seed-additional-specialties' 2 5 4

    $legacy = $databases[4]; NewDb $legacy
    New-Item -ItemType Directory -Path (Join-Path $legacyRoot 'db\changelog') -Force | Out-Null
    Copy-Item (Join-Path $root 'tests\fixtures\legacy-changelog\*') (Join-Path $legacyRoot 'db\changelog') -Recurse
    $legacyMode = $true; L $legacy @('update')
    A $legacy "(SELECT count(*) FROM databasechangelog WHERE (id='002-seed-specialties' AND md5sum='9:f5719d18ef7771621c69be4f04fb4e73') OR (id='004-seed-additional-specialties' AND md5sum='9:3df6ef3fc67dc17d4114f63e16325e7a'))=2" 'Legacy checksums differ from expected.'
    $legacyMode = $false; L $legacy @('validate'); L $legacy @('update')
    A $legacy "to_regclass('public.specialty_seed_ownership') IS NOT NULL AND (SELECT count(*) FROM specialty_seed_ownership)=0" 'Legacy rows were backfilled.'
    Seven $legacy
    L $legacy @('rollback-count','--count','1')
    A $legacy "to_regclass('public.specialty_seed_ownership') IS NULL" 'Legacy ledger should roll back first.'
    L $legacy @('rollback-count','--count','1'); Seven $legacy
    L $legacy @('rollback-count','--count','1'); L $legacy @('rollback-count','--count','1'); Seven $legacy
    Write-Host 'PASS legacy checksums, empty ledger, no backfill, and guarded rollback.'

    $fk = $databases[5]; NewDb $fk; L $fk @('update')
    $neurologyId = Scalar $fk "SELECT id FROM specialties WHERE name=$neurology"
    P $fk "INSERT INTO professionals(identity_user_id,license_number,specialty_id,years_experience) VALUES (900000001,'TEST-OWNERSHIP-FK-001',$neurologyId,0)"
    $dockerArgs = @('run','--rm','--network',$network,'--workdir','/liquibase/changelog','--mount',"type=bind,source=$root\db\changelog,target=/liquibase/changelog,readonly",'liquibase/liquibase:4.31',"--url=jdbc:postgresql://${container}:5432/$fk",'--username=test_user',"--password=$password",'--changelog-file=db.changelog-master.yaml','rollback-count','--count','1')
    $oldEap = $ErrorActionPreference
    try { $ErrorActionPreference='Continue'; $failure = & docker @dockerArgs 2>&1; $exit = $LASTEXITCODE } finally { $ErrorActionPreference=$oldEap }
    if ($exit -eq 0 -or ($failure -join "`n") -notmatch 'fk_professionals_specialty') { throw 'Expected FK-restricted rollback failure.' }
    A $fk "EXISTS (SELECT 1 FROM professionals WHERE license_number='TEST-OWNERSHIP-FK-001')" 'Professional was deleted.'
    A $fk "EXISTS (SELECT 1 FROM specialties WHERE id=$neurologyId)" 'Referenced specialty was deleted.'
    Own $fk '004-seed-additional-specialties' 3
    P $fk "DELETE FROM professionals WHERE license_number='TEST-OWNERSHIP-FK-001'"
    L $fk @('rollback-count','--count','1'); Own $fk '004-seed-additional-specialties' 0
    Write-Host 'PASS FK restriction preserves professional, specialty, and ownership until retry.'
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
