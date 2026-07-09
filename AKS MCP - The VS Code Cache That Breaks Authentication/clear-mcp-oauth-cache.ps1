<#
.SYNOPSIS
  Clears VS Code's cached MCP OAuth dynamic auth provider registration (global state.vscdb)
  for the aks-mcp server (http://localhost:8000/mcp).

  Use this whenever the underlying Entra ID app registration's clientId changes (e.g. after
  recreating/switching app registrations) but VS Code keeps trying to authenticate with a
  stale/old clientId - VS Code caches the dynamically "registered" client per server URL and
  does not automatically pick up changes made server-side.

.NOTES
  - VS Code MUST be fully closed before running this script (state.vscdb is locked while running).
  - Safe to re-run; only touches entries related to "localhost:8000" (the aks-mcp server URL).
  - A timestamped backup of state.vscdb is created before any changes.
  - IMPORTANT: VS Code also keeps a "state.vscdb.backup" file next to state.vscdb and can restore
    from it on startup (e.g. after a crash/unclean exit or corruption detection). If that backup
    still contains the stale entries, VS Code can silently resurrect them after you "cleaned" the
    live db, making it look like the fix didn't take effect. This script cleans both files.
#>

$ErrorActionPreference = "Stop"

$serverUrlPattern = "aks-mcp.programmingwithwolfgang.com"
$globalStorageDir = "$env:APPDATA\Code\User\globalStorage"
$dbPath = Join-Path $globalStorageDir "state.vscdb"
$dbBackupPath = Join-Path $globalStorageDir "state.vscdb.backup"

# 1. Make sure VS Code is closed (file would be locked otherwise)
$codeProcesses = Get-Process -Name "Code" -ErrorAction SilentlyContinue
if ($codeProcesses) {
    Write-Host "VS Code appears to still be running (PID(s): $($codeProcesses.Id -join ', ')). Please close it fully and re-run this script." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $dbPath)) {
    Write-Host "state.vscdb not found at $dbPath" -ForegroundColor Yellow
    exit 1
}

# 2. Locate sqlite3.exe, install via winget if missing
$sqlite3 = Get-Command sqlite3 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $sqlite3) {
    $sqlite3 = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter "sqlite3.exe" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $sqlite3) {
    Write-Host "sqlite3.exe not found - installing via winget..." -ForegroundColor Cyan
    winget install --id SQLite.SQLite -e --accept-package-agreements --accept-source-agreements | Out-Null
    $sqlite3 = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter "sqlite3.exe" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $sqlite3) {
    throw "Could not find or install sqlite3.exe"
}

# 3. Reusable cleanup routine - applied to BOTH state.vscdb and state.vscdb.backup.
#    VS Code can restore state.vscdb from state.vscdb.backup on startup (e.g. after an unclean
#    exit or corruption check), which would silently resurrect stale entries we just deleted from
#    the live db. So both files must be cleaned, or the backup must be removed entirely.
function Clear-McpOAuthCache {
    param(
        [Parameter(Mandatory)] [string]$TargetDbPath,
        [Parameter(Mandatory)] [string]$Sqlite3Path,
        [Parameter(Mandatory)] [string]$ServerUrlPattern
    )

    $label = Split-Path $TargetDbPath -Leaf

    # Backup first
    $backupPath = "$env:TEMP\$label.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -Path $TargetDbPath -Destination $backupPath -Force
    Write-Host "Backed up $label to $backupPath" -ForegroundColor Green

    # Filter dynamicAuthProviders JSON array, removing entries for this server
    $currentValue = & $Sqlite3Path $TargetDbPath "SELECT value FROM ItemTable WHERE key = 'dynamicAuthProviders';"
    if ($currentValue) {
        try {
            $providers = $currentValue | ConvertFrom-Json
            $filtered = @($providers | Where-Object { $_.providerId -notlike "*$ServerUrlPattern*" })

            $sqlFile = "$env:TEMP\clear_mcp_cache.sql"
            $sqlLines = @()

            if ($filtered.Count -eq 0) {
                $sqlLines += "DELETE FROM ItemTable WHERE key = 'dynamicAuthProviders';"
            }
            else {
                $newJson = ($filtered | ConvertTo-Json -Compress -AsArray) -replace "'", "''"
                $sqlLines += "UPDATE ItemTable SET value = '$newJson' WHERE key = 'dynamicAuthProviders';"
            }

            $sqlLines | Out-File -FilePath $sqlFile -Encoding utf8
            & $Sqlite3Path $TargetDbPath ".read $sqlFile"
            Write-Host "[$label] Updated/removed dynamicAuthProviders entry for $ServerUrlPattern" -ForegroundColor Green
        }
        catch {
            # Do NOT silently skip on parse failure - that leaves stale entries in place.
            # Fall back to nuking the whole key so a fresh registration is forced.
            Write-Host "[$label] Could not parse dynamicAuthProviders JSON - forcibly deleting the key instead: $_" -ForegroundColor Yellow
            & $Sqlite3Path $TargetDbPath "DELETE FROM ItemTable WHERE key = 'dynamicAuthProviders';"
        }
    }

    # Delete secret:// entries referencing this server URL
    $keysToDelete = & $Sqlite3Path -list $TargetDbPath "SELECT key FROM ItemTable WHERE key LIKE 'secret://%$ServerUrlPattern%';"
    if ($keysToDelete) {
        $deleteSqlFile = "$env:TEMP\clear_mcp_secrets.sql"
        $deleteLines = @()
        foreach ($key in $keysToDelete) {
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            $escapedKey = $key.Replace("'", "''")
            $deleteLines += "DELETE FROM ItemTable WHERE key = '$escapedKey';"
        }
        $deleteLines | Out-File -FilePath $deleteSqlFile -Encoding utf8
        & $Sqlite3Path $TargetDbPath ".read $deleteSqlFile"
        Write-Host "[$label] Deleted $($keysToDelete.Count) secret:// entr(y/ies) referencing $ServerUrlPattern" -ForegroundColor Green
    }
    else {
        Write-Host "[$label] No secret:// entries found referencing $ServerUrlPattern" -ForegroundColor Cyan
    }
}

Clear-McpOAuthCache -TargetDbPath $dbPath -Sqlite3Path $sqlite3 -ServerUrlPattern $serverUrlPattern

# 4. Do NOT try to surgically patch state.vscdb.backup - VS Code uses it as a recovery/fallback
#    copy, and if our edit doesn't take (e.g. a JSON quirk) it can silently reintroduce the exact
#    stale entry we just removed from the live db. Simplest and most reliable fix: back it up, then
#    delete it outright so there is nothing stale left for VS Code to recover from. VS Code
#    recreates this file on its own; it is not required for VS Code to function.
if (Test-Path $dbBackupPath) {
    $backupOfBackupPath = "$env:TEMP\state.vscdb.backup.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -Path $dbBackupPath -Destination $backupOfBackupPath -Force
    Write-Host "Backed up state.vscdb.backup to $backupOfBackupPath" -ForegroundColor Green
    Remove-Item -Path $dbBackupPath -Force
    Write-Host "Deleted state.vscdb.backup (VS Code will recreate it fresh from the cleaned state.vscdb)." -ForegroundColor Green
}
else {
    Write-Host "No state.vscdb.backup found - nothing to clean there." -ForegroundColor Cyan
}

# 5. Verify nothing referencing this server is left in state.vscdb
Write-Host "`nVerifying cleanup..." -ForegroundColor Cyan
$remaining = & $sqlite3 -list $dbPath "SELECT key FROM ItemTable WHERE key = 'dynamicAuthProviders' OR key LIKE 'secret://%$serverUrlPattern%';"
$remainingProviderHasServer = $false
foreach ($key in $remaining) {
    if ($key -eq 'dynamicAuthProviders') {
        $val = & $sqlite3 $dbPath "SELECT value FROM ItemTable WHERE key = 'dynamicAuthProviders';"
        if ($val -like "*$serverUrlPattern*") { $remainingProviderHasServer = $true }
    }
    else {
        $remainingProviderHasServer = $true
    }
}
if ($remainingProviderHasServer) {
    Write-Host "WARNING: state.vscdb still appears to reference $serverUrlPattern. Re-run this script or inspect manually." -ForegroundColor Red
}
else {
    Write-Host "Confirmed: no remaining $serverUrlPattern entries in state.vscdb." -ForegroundColor Green
}

Write-Host "`nDone. Make sure ALL VS Code windows/processes are closed (check Task Manager for lingering Code.exe), then reopen VS Code - it will perform a fresh OAuth discovery for the aks-mcp server." -ForegroundColor Green
