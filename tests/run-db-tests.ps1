[CmdletBinding()]
param(
    [string]$ComposeCommand = $env:COMPOSE_CMD
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ComposeCommand)) {
    $ComposeCommand = 'docker compose'
}

if ($ComposeCommand -eq 'docker compose') {
    $composeAvailable = Get-Command docker -ErrorAction SilentlyContinue
} else {
    $composeAvailable = Get-Command $ComposeCommand -ErrorAction SilentlyContinue
}
if (-not $composeAvailable) {
    throw 'Docker Desktop is required to run the database tests.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $repositoryRoot 'docker-compose.test.yml'
$projectName = "professional-db-test-$PID-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$composeArgs = @('-p', $projectName, '-f', $composeFile)
$previousPassword = $env:TEST_DB_PASSWORD
$passwordBytes = New-Object byte[] 32
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $random.GetBytes($passwordBytes)
} finally {
    $random.Dispose()
}
$env:TEST_DB_PASSWORD = [BitConverter]::ToString($passwordBytes).Replace('-', '')

function Invoke-Compose {
    param([string[]]$Arguments)

    if ($ComposeCommand -eq 'docker compose') {
        & docker compose @composeArgs @Arguments
    } else {
        & $ComposeCommand @composeArgs @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose failed with exit code $LASTEXITCODE."
    }
}

function Invoke-Liquibase {
    param([string[]]$Command)

    Invoke-Compose (@('run', '--rm', 'liquibase') + $Command)
}

function Invoke-Sql {
    param([string]$Query)

    $result = Invoke-Compose (@(
        'exec', '-T', 'postgres', 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
        '--host=127.0.0.1', '-U', 'test_user', '-d', 'professional_management_test', '-c', $Query
    ))
    if ($LASTEXITCODE -ne 0) {
        throw 'PostgreSQL assertion query failed.'
    }
    return ($result -join '').Trim()
}

function Assert-Sql {
    param([string]$Query, [string]$Message)

    if ((Invoke-Sql $Query) -ne 't') {
        throw $Message
    }
}

function Assert-Schema {
    Invoke-Compose @(
        'exec', '-T', 'postgres', 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
        '--host=127.0.0.1',
        '-U', 'test_user', '-d', 'professional_management_test',
        '-f', '/tests/professional-schema-tests.sql'
    )
}

$failure = $null
Write-Host "Using isolated Docker Compose project: $projectName"
try {
    Invoke-Compose @('up', '-d', 'postgres')

    $firstUpdate = Invoke-Liquibase @('update') | Out-String
    if ($firstUpdate -notmatch '(?m)^\s*Run:\s+(\d+)\s*$') {
        throw 'Fresh Liquibase update did not report its changeset count.'
    }
    $expectedChangesets = [int]$Matches[1]
    if ($expectedChangesets -lt 1) {
        throw 'Fresh Liquibase update did not apply any changesets.'
    }

    Assert-Schema
    Assert-Sql "SELECT (SELECT count(*) FROM databasechangelog) = $expectedChangesets" `
        'Fresh update did not apply all reported changesets.'

    $appliedBefore = Invoke-Sql 'SELECT count(*) FROM databasechangelog'
    $secondUpdate = Invoke-Liquibase @('update') | Out-String
    if ($secondUpdate -notmatch '(?m)^\s*Run:\s+0\s*$') {
        throw 'Repeated Liquibase update did not report zero changesets.'
    }
    $appliedAfter = Invoke-Sql 'SELECT count(*) FROM databasechangelog'
    if ($appliedAfter -ne $appliedBefore) {
        throw 'Repeated update applied additional changesets.'
    }

    Invoke-Liquibase @('rollback-count', "$expectedChangesets")
    Assert-Sql "SELECT to_regclass('public.specialties') IS NULL AND to_regclass('public.professionals') IS NULL" `
        'Domain tables remain after complete rollback.'
    Assert-Sql "SELECT (SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' AND table_name NOT IN ('databasechangelog','databasechangeloglock')) = 0" `
        'Unexpected domain tables remain after complete rollback.'
    Assert-Sql 'SELECT (SELECT count(*) FROM databasechangelog) = 0' 'Liquibase changeset history remains after rollback.'

    $reapplication = Invoke-Liquibase @('update') | Out-String
    if ($reapplication -notmatch '(?m)^\s*Run:\s+(\d+)\s*$' -or [int]$Matches[1] -ne $expectedChangesets) {
        throw 'Reapplication did not run the complete changeset set.'
    }
    Assert-Schema
    Assert-Sql "SELECT (SELECT count(*) FROM databasechangelog) = $expectedChangesets" `
        'Reapplication did not restore all changesets.'
} catch {
    $failure = $_
} finally {
    try {
        Invoke-Compose @('down', '--volumes', '--remove-orphans')
    } catch {
        if ($null -eq $failure) {
            $failure = $_
        } else {
            Write-Warning "Docker cleanup also failed: $_"
        }
    }
    if ($null -eq $previousPassword) {
        Remove-Item Env:\TEST_DB_PASSWORD -ErrorAction SilentlyContinue
    } else {
        $env:TEST_DB_PASSWORD = $previousPassword
    }
}

if ($null -ne $failure) {
    throw $failure
}

Write-Host 'Fresh install, idempotent update, full rollback, and reapplication passed.'
