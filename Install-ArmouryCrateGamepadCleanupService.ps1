#requires -version 5.1

[CmdletBinding()]
param(
    [string]$ServiceName = 'ArmouryCrateGamepadCleanup',
    [string]$NssmPath = '',
    [int]$IntervalSeconds = 300,
    [string]$RunnerScript = (Join-Path $PSScriptRoot 'ArmouryCrateGamepadCleanupService.ps1'),
    [string]$LogDirectory = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'

function Resolve-NssmPath {
    param([string]$ExplicitPath)

    $candidates = @()

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $candidates += $ExplicitPath
    }

    $cmd = Get-Command nssm.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $candidates += $cmd.Source
    }

    $candidates += @(
        'C:\Windows\System32\nssm.exe',
        'C:\Windows\Sysnative\nssm.exe',
        'C:\Windows\SysWOW64\nssm.exe',
        'C:\Windows\System32\nssm\nssm.exe',
        'C:\nssm\win64\nssm.exe',
        'C:\Tools\nssm.exe'
    )

    foreach ($path in ($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    throw 'nssm.exe not found. Pass -NssmPath with the full path to nssm.exe.'
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this installer from an elevated PowerShell window.'
    }
}

Assert-Admin

if (-not (Test-Path -LiteralPath $RunnerScript -PathType Leaf)) {
    throw "Runner script not found: $RunnerScript"
}

$runnerFullPath = (Resolve-Path -LiteralPath $RunnerScript).Path
$appDirectory = Split-Path -Parent $runnerFullPath
$nssm = Resolve-NssmPath -ExplicitPath $NssmPath
$powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$appParams = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -IntervalSeconds {1}' -f $runnerFullPath, $IntervalSeconds
$stdout = Join-Path $LogDirectory 'ArmouryCrateGamepadCleanupService.stdout.log'
$stderr = Join-Path $LogDirectory 'ArmouryCrateGamepadCleanupService.stderr.log'

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $existing) {
    & $nssm install $ServiceName $powerShell
}

& $nssm set $ServiceName Application $powerShell
& $nssm set $ServiceName AppParameters $appParams
& $nssm set $ServiceName AppDirectory $appDirectory
& $nssm set $ServiceName DisplayName 'Armoury Crate Gamepad Cleanup'
& $nssm set $ServiceName Description 'Periodically removes empty Armoury Crate SE gamepad profiles and stale/unlinked templates.'
& $nssm set $ServiceName Start SERVICE_AUTO_START
& $nssm set $ServiceName AppStdout $stdout
& $nssm set $ServiceName AppStderr $stderr
& $nssm set $ServiceName AppRotateFiles 1
& $nssm set $ServiceName AppRotateOnline 1
& $nssm set $ServiceName AppRotateSeconds 86400
& $nssm set $ServiceName AppRotateBytes 1048576
& $nssm set $ServiceName AppStopMethodConsole 15000

$service = Get-Service -Name $ServiceName
if ($service.Status -ne 'Running') {
    & $nssm start $ServiceName
}

Get-Service -Name $ServiceName | Format-List Name, DisplayName, Status, StartType
Write-Host "Installed with NSSM: $nssm"
Write-Host "Runner: $runnerFullPath"
Write-Host "IntervalSeconds: $IntervalSeconds"
Write-Host "Logs: $stdout ; $stderr"
