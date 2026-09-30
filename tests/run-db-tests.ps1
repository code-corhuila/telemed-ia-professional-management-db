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
$previousUser = $env:TEST_DB_USER
$previousPassword = $env:TEST_DB_PASSWORD
$passwordBytes = New-Object byte[] 32
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $random.GetBytes($passwordBytes)
} finally {
    $random.Dispose()
}
$env:TEST_DB_USER = 'test_user'
$env:TEST_DB_PASSWORD = [BitConverter]::ToString($passwordBytes).Replace('-', '')
$testPassword = $env:TEST_DB_PASSWORD

function Format-ProcessArgument {
    param([string]$Value)

    if ($Value -match '[\s"]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }
    return $Value
}

function Invoke-IsolatedComposeDown {
    param(
        [string]$ComposeCommand,
        [string[]]$ComposeArgs,
        [string]$Password
    )

    # Built on System.Diagnostics.ProcessStartInfo instead of the "&" call operator so the
    # child process gets its own private copy of the environment, populated once here. That
    # copy is independent of this script's shared $env: block, so it cannot be affected by
    # whatever the main thread's own cleanup does to $env:TEST_DB_PASSWORD concurrently.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    if ($ComposeCommand -eq 'docker compose') {
        $startInfo.FileName = 'docker'
        $allArgs = @('compose') + $ComposeArgs + @('down', '--volumes', '--remove-orphans')
    } else {
        $startInfo.FileName = $ComposeCommand
        $allArgs = $ComposeArgs + @('down', '--volumes', '--remove-orphans')
    }
    $startInfo.Arguments = ($allArgs | ForEach-Object { Format-ProcessArgument $_ }) -join ' '
    $startInfo.EnvironmentVariables['TEST_DB_PASSWORD'] = $Password
    $startInfo.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Isolated Docker Compose cleanup exited with code $($process.ExitCode)."
    }
}

# Ctrl+C raises Console.CancelKeyPress, which PowerShell only dispatches once control
# returns to the engine - typically once the docker.exe call that is currently running
# finishes or is itself stopped. It does not interrupt a docker.exe invocation that is
# already in progress, and this script cannot make `Cancel = $true` reliably suppress
# .NET's default process termination in Windows PowerShell 5.1 (verified empirically:
# neither Register-ObjectEvent nor a direct CLR CancelKeyPress subscription kept the
# process alive after Ctrl+C in this host). So this handler is a best-effort race
# against the process being torn down, not a guaranteed or coordinated cleanup step, and
# it does not attempt to take control of the interrupt or force an early exit.
#
# Both this handler and the main `finally` below clean up via Invoke-IsolatedComposeDown
# with the password captured once into $testPassword (a local variable, not the shared,
# mutable $env:TEST_DB_PASSWORD block), so either one can run - in either order, or only
# one of them - without depending on the other having already run or on $env:TEST_DB_PASSWORD
# still holding this run's value. A "down" against a project that is already gone is a
# harmless no-op, so no shared state or coordination between the two is required.
$interruptSubscription = $null
try {
    $interruptSubscription = Register-ObjectEvent -InputObject ([Console]) -EventName 'CancelKeyPress' -MessageData @{
        ComposeCommand   = $ComposeCommand
        ComposeArgs      = $composeArgs
        PreviousUser     = $previousUser
        PreviousPassword = $previousPassword
        TestPassword     = $testPassword
    } -Action {
        $data = $Event.MessageData
        Write-Warning 'Interrupted. Attempting best-effort Docker Compose cleanup.'
        try {
            Invoke-IsolatedComposeDown -ComposeCommand $data.ComposeCommand -ComposeArgs $data.ComposeArgs -Password $data.TestPassword
        } catch {
            Write-Warning "Interrupt cleanup failed to run Docker Compose: $_"
        }
        if ($null -eq $data.PreviousUser) {
            Remove-Item Env:\TEST_DB_USER -ErrorAction SilentlyContinue
        } else {
            $env:TEST_DB_USER = $data.PreviousUser
        }
        if ($null -eq $data.PreviousPassword) {
            Remove-Item Env:\TEST_DB_PASSWORD -ErrorAction SilentlyContinue
        } else {
            $env:TEST_DB_PASSWORD = $data.PreviousPassword
        }
        # Intentionally not setting $Event.SourceEventArgs.Cancel and not forcing process
        # termination here: this lets the host's own normal Ctrl+C behavior proceed after
        # this cleanup runs, instead of this script deciding to end the whole PowerShell
        # session.
    }
} catch {
    Write-Warning "Could not register interrupt cleanup handler: $_"
}

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
        'exec', '-T', '-e', "PGPASSWORD=$env:TEST_DB_PASSWORD", 'postgres', 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
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
        'exec', '-T', '-e', "PGPASSWORD=$env:TEST_DB_PASSWORD", 'postgres', 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
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
    Assert-Sql "SELECT to_regclass('public.specialties') IS NULL AND to_regclass('public.professionals') IS NULL AND to_regclass('public.specialty_seed_ownership') IS NULL AND to_regclass('professional_management.specialties') IS NULL AND to_regclass('professional_management.professionals') IS NULL AND to_regclass('professional_management.specialty_seed_ownership') IS NULL" `
        'Domain tables remain after complete rollback.'
    Assert-Sql "SELECT NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='professional_management')" `
        'Professional Management schema remains after complete rollback.'
    Assert-Sql "SELECT (SELECT count(*) FROM information_schema.tables WHERE table_schema IN ('public','professional_management') AND table_type='BASE TABLE' AND table_name NOT IN ('databasechangelog','databasechangeloglock')) = 0" `
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
    # Always run cleanup here too, even if the interrupt handler above already ran (in
    # either order, since it runs on its own thread). This uses the same isolated
    # invocation and the locally-captured $testPassword instead of Invoke-Compose's
    # implicit dependence on $env:TEST_DB_PASSWORD, so it cannot fail with a "variable is
    # not set" interpolation error regardless of what the handler already did to that
    # shared, mutable environment variable. Running "down" again against a project the
    # handler already removed is a harmless no-op (nothing to remove), so no shared state
    # or coordination with the handler is needed to avoid duplicate work here.
    try {
        Invoke-IsolatedComposeDown -ComposeCommand $ComposeCommand -ComposeArgs $composeArgs -Password $testPassword
    } catch {
        if ($null -eq $failure) {
            $failure = $_
        } else {
            Write-Warning "Docker cleanup also failed: $_"
        }
    }
    if ($null -eq $previousUser) {
        Remove-Item Env:\TEST_DB_USER -ErrorAction SilentlyContinue
    } else {
        $env:TEST_DB_USER = $previousUser
    }
    if ($null -eq $previousPassword) {
        Remove-Item Env:\TEST_DB_PASSWORD -ErrorAction SilentlyContinue
    } else {
        $env:TEST_DB_PASSWORD = $previousPassword
    }
}

if ($interruptSubscription) {
    Unregister-Event -SourceIdentifier $interruptSubscription.Name -ErrorAction SilentlyContinue
    Remove-Job -Id $interruptSubscription.Id -Force -ErrorAction SilentlyContinue
}

if ($null -ne $failure) {
    throw $failure
}

Write-Host 'Fresh install, idempotent update, full rollback, and reapplication passed.'
