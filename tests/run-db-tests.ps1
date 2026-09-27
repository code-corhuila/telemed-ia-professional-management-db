[CmdletBinding()]
param([string]$ComposeCommand = $env:COMPOSE_CMD)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ComposeCommand)) { $ComposeCommand = 'docker compose' }
if ($ComposeCommand -eq 'docker compose') { $composeAvailable = Get-Command docker -ErrorAction SilentlyContinue }
else { $composeAvailable = Get-Command $ComposeCommand -ErrorAction SilentlyContinue }
if (-not $composeAvailable) { throw 'Docker Desktop is required to run the database tests.' }

$root = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $root 'docker-compose.test.yml'
$project = "professional-db-test-$PID-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$composeArgs = @('-p', $project, '-f', $composeFile)
$previousPassword = $env:TEST_DB_PASSWORD
$previousUser = $env:TEST_DB_USER
$bytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
$env:TEST_DB_PASSWORD = [BitConverter]::ToString($bytes).Replace('-', '')
$env:TEST_DB_USER = 'test_user'

function Invoke-Compose([string[]]$Arguments) {
    if ($ComposeCommand -eq 'docker compose') { & docker compose @composeArgs @Arguments }
    else { & $ComposeCommand @composeArgs @Arguments }
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose failed with exit code $LASTEXITCODE." }
}
function Invoke-Liquibase([string[]]$Command) {
    Invoke-Compose (@('run', '--rm', 'liquibase') + $Command)
}
function Invoke-Sql([string]$Query) {
    $result = Invoke-Compose @('exec', '-T', '-e', "PGPASSWORD=$env:TEST_DB_PASSWORD", 'postgres',
        'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '--host=127.0.0.1',
        '-U', $env:TEST_DB_USER, '-d', 'professional_management_test', '-c', $Query)
    return ($result -join '').Trim()
}
function Assert-Sql([string]$Query, [string]$Message) {
    if ((Invoke-Sql $Query) -ne 't') { throw $Message }
}
function Assert-Schema {
    Invoke-Compose @('exec', '-T', '-e', "PGPASSWORD=$env:TEST_DB_PASSWORD", 'postgres',
        'psql', '-X', '-v', 'ON_ERROR_STOP=1', '--host=127.0.0.1', '-U', $env:TEST_DB_USER,
        '-d', 'professional_management_test', '-f', '/tests/professional-schema-tests.sql')
}

$failure = $null
Write-Host "Using isolated Docker Compose project: $project"
try {
    Invoke-Compose @('up', '-d', 'postgres')
    $update = Invoke-Liquibase @('update') | Out-String
    if ($update -notmatch '(?m)^\s*Run:\s+(\d+)\s*$' -or [int]$Matches[1] -ne 6) {
        throw 'Fresh Liquibase update did not apply all six changesets.'
    }
    Assert-Schema
    Assert-Sql 'SELECT (SELECT count(*) FROM databasechangelog)=6' 'Fresh update has incorrect changeset history.'

    $before = Invoke-Sql 'SELECT count(*) FROM databasechangelog'
    $again = Invoke-Liquibase @('update') | Out-String
    if ($again -notmatch '(?m)^\s*Run:\s+0\s*$') { throw 'Second update was not a no-op.' }
    if ((Invoke-Sql 'SELECT count(*) FROM databasechangelog') -ne $before) {
        throw 'Second update changed the databasechangelog.'
    }

    Invoke-Liquibase @('rollback-count', '6')
    Assert-Sql "SELECT to_regclass('public.specialties') IS NULL AND to_regclass('public.professionals') IS NULL AND to_regclass('public.specialty_seed_ownership') IS NULL" 'Domain tables remain after rollback.'
    Assert-Sql "SELECT count(*)=0 FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' AND table_name NOT IN ('databasechangelog','databasechangeloglock')" 'Unexpected domain tables remain.'
    Assert-Sql 'SELECT count(*)=0 FROM databasechangelog' 'Changeset history remains after rollback.'

    $reapply = Invoke-Liquibase @('update') | Out-String
    if ($reapply -notmatch '(?m)^\s*Run:\s+(\d+)\s*$' -or [int]$Matches[1] -ne 6) {
        throw 'Reapplication did not run all six changesets.'
    }
    Assert-Schema
    Assert-Sql 'SELECT count(*)=6 FROM databasechangelog' 'Reapplication did not restore all changesets.'
} catch {
    $failure = $_
} finally {
    try { Invoke-Compose @('down', '--volumes', '--remove-orphans') }
    catch {
        if ($null -eq $failure) { $failure = $_ }
        else { Write-Warning "Docker cleanup also failed: $_" }
    }
    if ($null -eq $previousPassword) { Remove-Item Env:\TEST_DB_PASSWORD -ErrorAction SilentlyContinue }
    else { $env:TEST_DB_PASSWORD = $previousPassword }
    if ($null -eq $previousUser) { Remove-Item Env:\TEST_DB_USER -ErrorAction SilentlyContinue }
    else { $env:TEST_DB_USER = $previousUser }
}
if ($null -ne $failure) { throw $failure }
Write-Host 'Fresh install, idempotent update, full rollback, and reapplication passed.'
