[CmdletBinding()]
param(
    [string]$ComposeCommand = $env:COMPOSE_CMD
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ComposeCommand)) {
    $ComposeCommand = 'docker compose'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $repositoryRoot 'docker-compose.test.yml'
$projectName = 'professional-management-db-test'
$env:PGPASSWORD = 'test_password'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker Desktop is required to run the database tests.'
}

$portInUse = Get-NetTCPConnection -LocalPort 5432 -State Listen -ErrorAction SilentlyContinue
if ($null -eq $portInUse) {
    $env:TEST_DB_PORT = '5432'
} else {
    $env:TEST_DB_PORT = '55432'
    Write-Warning 'Local port 5432 is in use; exposing the testing database on 55432 instead.'
}

function Invoke-Compose {
    param([string[]]$Arguments)

    if ($ComposeCommand -eq 'docker compose') {
        & docker compose @Arguments
    } else {
        & $ComposeCommand @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose command failed with exit code $LASTEXITCODE."
    }
}

Push-Location $repositoryRoot
try {
    Invoke-Compose @('-p', $projectName, '-f', $composeFile, 'up', '-d', 'postgres')
    Invoke-Compose @('-p', $projectName, '-f', $composeFile, 'run', '--rm', 'liquibase')

    $testContainer = "$projectName-test-runner"
    Invoke-Compose @(
        '-p', $projectName,
        '-f', $composeFile,
        'run', '--rm',
        '--name', $testContainer,
        '--entrypoint', 'psql',
        '-e', 'PGPASSWORD',
        'postgres',
        '--host=postgres',
        '--username=test_user',
        '--dbname=professional_management_test',
        '--file=/tests/professional-schema-tests.sql'
    )
} finally {
    Pop-Location
}

Write-Host 'Professional Management database tests passed in Docker.'
