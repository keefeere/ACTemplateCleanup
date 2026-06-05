#requires -version 5.1

[CmdletBinding()]
param(
    [int]$IntervalSeconds = 300,
    [int]$InitialDelaySeconds = 10,
    [string]$CleanupScript = (Join-Path $PSScriptRoot 'ArmouryCrateGamepadCleanup.ps1'),
    [string]$LogPath = (Join-Path $env:USERPROFILE 'ArmouryCrateGamepadCleanupService.log')
)

$ErrorActionPreference = 'Stop'

function Write-ServiceLog {
    param([Parameter(Mandatory)][string]$Message)

    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $line | Add-Content -LiteralPath $LogPath -Encoding UTF8
    Write-Host $line
}

function Invoke-CleanupOnce {
    if (-not (Test-Path -LiteralPath $CleanupScript -PathType Leaf)) {
        throw "Cleanup script not found: $CleanupScript"
    }

    Write-ServiceLog "cleanup start: $CleanupScript"
    & $CleanupScript -Clean | Out-Null
    Write-ServiceLog 'cleanup done'
}

if ($IntervalSeconds -lt 30) {
    throw 'IntervalSeconds must be at least 30.'
}

Write-ServiceLog "service runner started; interval=${IntervalSeconds}s; initialDelay=${InitialDelaySeconds}s"

if ($InitialDelaySeconds -gt 0) {
    Start-Sleep -Seconds $InitialDelaySeconds
}

while ($true) {
    try {
        Invoke-CleanupOnce
    } catch {
        Write-ServiceLog ("cleanup failed: " + $_.Exception.Message)
    }

    Start-Sleep -Seconds $IntervalSeconds
}
