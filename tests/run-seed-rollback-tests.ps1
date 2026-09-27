[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$runId = [Guid]::NewGuid().ToString('N').Substring(0, 12)
$networkName = "professional-seed-rollback-$runId"
$postgresContainer = "$networkName-postgres"
$password = 'test_password'
$neurologyName = "Neurolog$([char]0x00ED)a"
$databaseNames = @(
    "seed_rollback_fresh_$runId",
    "seed_rollback_002_$runId",
    "seed_rollback_004_$runId"
)
$networkCreated = $false
$postgresCreated = $false
$changelogMount = "type=bind,source=$repositoryRoot\db\changelog,target=/liquibase/changelog,readonly"
$testsMount = "type=bind,source=$repositoryRoot\tests\sql,target=/tests,readonly"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker Desktop is required to run the seed rollback tests.'
}

function Invoke-Docker {
    param([string[]]$Arguments)

    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker command failed with exit code $LASTEXITCODE."
    }
}

function Invoke-Postgres {
    param(
        [string]$Database,
        [string[]]$Arguments
    )

    Invoke-Docker (@(
        'exec', $postgresContainer, 'psql',
        '--username=test_user',
        "--dbname=$Database",
        '--set=ON_ERROR_STOP=1'
    ) + $Arguments)
}

function Invoke-Liquibase {
    param(
        [string]$Database,
        [string]$Changelog = 'db.changelog-master.yaml',
        [string[]]$Command
    )

    $arguments = @(
        'run', '--rm', '--network', $networkName,
        '--workdir', '/liquibase/changelog',
        '--mount', $changelogMount,
        'liquibase/liquibase:4.31',
        "--url=jdbc:postgresql://${postgresContainer}:5432/$Database",
        '--username=test_user',
        "--password=$password",
        "--changelog-file=$Changelog"
    ) + $Command
    Invoke-Docker $arguments
}

function New-TestDatabase {
    param([string]$Database)

    Invoke-Postgres -Database 'postgres' -Arguments @(
        '--command', "CREATE DATABASE $Database;"
    )
}

function Assert-PreexistingSpecialty {
    param(
        [string]$Database,
        [string]$Name
    )

    $escapedName = $Name.Replace("'", "''")
    $escapedDescription = 'pre-existing audit fixture'
    $query = @"
DO `$`$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM specialties
        WHERE name = '$escapedName'
          AND description = '$escapedDescription'
    ) THEN
        RAISE EXCEPTION 'Pre-existing specialty was removed or changed: $escapedName';
    END IF;
END;
`$`$;
"@
    Invoke-Postgres -Database $Database -Arguments @('--command', $query)
}

function Assert-SevenSpecialties {
    param([string]$Database)

    Invoke-Postgres -Database $Database -Arguments @(
        '--command',
        "DO `$`$ BEGIN IF (SELECT COUNT(*) FROM specialties) <> 7 THEN RAISE EXCEPTION 'Expected seven specialties, found %', (SELECT COUNT(*) FROM specialties); END IF; END; `$`$;"
    )
}

try {
    Invoke-Docker @('network', 'create', $networkName) | Out-Null
    $networkCreated = $true

    Invoke-Docker @(
        'run', '--detach',
        '--name', $postgresContainer,
        '--network', $networkName,
        "--env=POSTGRES_USER=test_user",
        "--env=POSTGRES_PASSWORD=$password",
        '--env=POSTGRES_DB=postgres',
        '--mount', $testsMount,
        'postgres:16-alpine'
    ) | Out-Null
    $postgresCreated = $true

    $ready = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        & docker exec $postgresContainer pg_isready --username=test_user --dbname=postgres *> $null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) {
        throw 'Disposable PostgreSQL did not become ready.'
    }

    $freshDatabase = $databaseNames[0]
    New-TestDatabase -Database $freshDatabase
    Invoke-Liquibase -Database $freshDatabase -Command @('update')
    Assert-SevenSpecialties -Database $freshDatabase
    Invoke-Postgres -Database $freshDatabase -Arguments @(
        '--file=/tests/professional-schema-tests.sql'
    )
    Write-Host 'Fresh database update and schema tests passed.'

    Invoke-Liquibase -Database $freshDatabase -Command @(
        'rollback-count', '--count=4'
    )
    Invoke-Postgres -Database $freshDatabase -Arguments @(
        '--command',
        "DO `$`$ BEGIN IF to_regclass('public.specialties') IS NOT NULL OR to_regclass('public.professionals') IS NOT NULL THEN RAISE EXCEPTION 'Domain tables remain after full rollback'; END IF; IF (SELECT COUNT(*) FROM databasechangelog) <> 0 THEN RAISE EXCEPTION 'Liquibase changeset history remains after full rollback'; END IF; END; `$`$;"
    )
    Invoke-Liquibase -Database $freshDatabase -Command @('update')
    Assert-SevenSpecialties -Database $freshDatabase
    Invoke-Postgres -Database $freshDatabase -Arguments @(
        '--file=/tests/professional-schema-tests.sql'
    )
    Write-Host 'Full rollback, reapply, and schema tests passed.'

    $database002 = $databaseNames[1]
    New-TestDatabase -Database $database002
    Invoke-Liquibase -Database $database002 `
        -Changelog 'changes/001-create-specialties.sql' `
        -Command @('update')
    Invoke-Postgres -Database $database002 -Arguments @(
        '--command',
        "INSERT INTO specialties (name, description) VALUES ('Medicina General', 'pre-existing audit fixture');"
    )
    Invoke-Liquibase -Database $database002 -Command @('update')
    Invoke-Liquibase -Database $database002 -Command @(
        'rollback-count', '--count=1'
    )
    Assert-PreexistingSpecialty -Database $database002 -Name 'Medicina General'
    Assert-SevenSpecialties -Database $database002
    Invoke-Liquibase -Database $database002 -Command @(
        'rollback-count', '--count=2'
    )
    Assert-PreexistingSpecialty -Database $database002 -Name 'Medicina General'
    Assert-SevenSpecialties -Database $database002
    Write-Host 'Changeset 002 collision rollback test passed.'

    $database004 = $databaseNames[2]
    New-TestDatabase -Database $database004
    Invoke-Liquibase -Database $database004 `
        -Changelog 'changes/001-create-specialties.sql' `
        -Command @('update')
    Invoke-Postgres -Database $database004 -Arguments @(
        '--command',
        "INSERT INTO specialties (name, description) VALUES ('$neurologyName', 'pre-existing audit fixture');"
    )
    Invoke-Liquibase -Database $database004 -Command @('update')
    Invoke-Liquibase -Database $database004 -Command @(
        'rollback-count', '--count=1'
    )
    Assert-PreexistingSpecialty -Database $database004 -Name $neurologyName
    Assert-SevenSpecialties -Database $database004
    Write-Host 'Changeset 004 collision rollback test passed.'
} finally {
    if ($postgresCreated) {
        & docker rm --force --volumes $postgresContainer | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not remove disposable PostgreSQL container and volume.'
        }
    }
    if ($networkCreated) {
        & docker network rm $networkName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not remove disposable Docker network.'
        }
    }
}

Write-Host 'Seed rollback tests passed.'
