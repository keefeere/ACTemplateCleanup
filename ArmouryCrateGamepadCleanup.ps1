#requires -version 5.1

[CmdletBinding()]
param(
    [string]$BasePath = (Join-Path $env:LOCALAPPDATA 'Packages\B9ECED6F.ArmouryCrateSE_qmba6cd70vzyy\LocalState\GamepadCustomize'),
    [switch]$ScanOnly,
    [switch]$Clean,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$ProfilesPath = Join-Path $BasePath 'Profiles'
$TemplatesPath = Join-Path $BasePath 'Templates'
$SystemTemplatesPath = Join-Path $BasePath 'SystemTemplates'
$ProtectedFolderPaths = [ordered]@{
    SystemTemplates = $SystemTemplatesPath
    DefaultTemplates = Join-Path $BasePath 'DefaultTemplates'
    Presets = Join-Path $BasePath 'Presets'
    CombKeys = Join-Path $BasePath 'CombKeys'
}

function Read-JsonUtf8 {
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    return $text | ConvertFrom-Json
}

function Get-JsonFileRows {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $Path -Filter '*.json' -File | Sort-Object Name)
}

function Test-GuidText {
    param([AllowNull()][string]$Text)

    return -not [string]::IsNullOrWhiteSpace($Text) -and $Text -match '^[0-9a-fA-F-]{36}$'
}

function Test-SystemProfile {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [Parameter(Mandatory)]$Json
    )

    $templateId = if ($Json.PSObject.Properties.Name -contains 'TemplateId') { [string]$Json.TemplateId } else { '' }
    return $File.Name -like '_sys_*.json' -or $templateId -like '_sys_*'
}

function Test-EmptyProfile {
    param(
        [Parameter(Mandatory)]$Json,
        [Parameter(Mandatory)][bool]$IsSystem
    )

    if ($IsSystem) {
        return $false
    }

    $name = if ($Json.PSObject.Properties.Name -contains 'Name') { [string]$Json.Name } else { '' }
    $templateId = if ($Json.PSObject.Properties.Name -contains 'TemplateId') { [string]$Json.TemplateId } else { '' }

    return [string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($templateId)
}

function Test-GeneratedBlankTemplate {
    param(
        [Parameter(Mandatory)][string]$Id,
        [AllowNull()][string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $true
    }

    if ($Id.Length -ge 8) {
        $shortId = $Id.Substring(0, 8)
        return $Name.StartsWith($shortId, [System.StringComparison]::OrdinalIgnoreCase)
    }

    return $false
}

function Test-ManualProtectedTemplate {
    param([AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    return $Name.TrimStart().StartsWith('_', [System.StringComparison]::Ordinal)
}

function Get-ProtectedFolderRows {
    foreach ($entry in $ProtectedFolderPaths.GetEnumerator()) {
        $jsonFiles = Get-JsonFileRows -Path $entry.Value

        [pscustomobject]@{
            Folder = $entry.Key
            Path = $entry.Value
            Exists = Test-Path -LiteralPath $entry.Value -PathType Container
            JsonCount = $jsonFiles.Count
            Note = 'protected/ignored'
        }
    }
}

function Get-State {
    $profileRows = foreach ($file in Get-JsonFileRows -Path $ProfilesPath) {
        $json = Read-JsonUtf8 -Path $file.FullName
        $name = if ($json.PSObject.Properties.Name -contains 'Name') { [string]$json.Name } else { '' }
        $templateId = if ($json.PSObject.Properties.Name -contains 'TemplateId') { [string]$json.TemplateId } else { '' }
        $isSystem = Test-SystemProfile -File $file -Json $json
        $isEmpty = Test-EmptyProfile -Json $json -IsSystem $isSystem

        [pscustomobject]@{
            File = $file.Name
            FullName = $file.FullName
            Name = if ([string]::IsNullOrWhiteSpace($name)) { '<blank>' } else { $name }
            TemplateId = if ([string]::IsNullOrWhiteSpace($templateId)) { '<empty>' } else { $templateId }
            BaseId = if ($json.PSObject.Properties.Name -contains 'BaseId') { $json.BaseId } else { $null }
            Mode = if ($json.PSObject.Properties.Name -contains 'Mode') { $json.Mode } else { $null }
            GyroMode = if ($json.PSObject.Properties.Name -contains 'Gyro') { $json.Gyro.Mode } else { $null }
            IsEdited = if ($json.PSObject.Properties.Name -contains 'IsEdited') { $json.IsEdited } else { $null }
            IsEditedByUser = if ($json.PSObject.Properties.Name -contains 'IsEditedByUser') { $json.IsEditedByUser } else { $null }
            IsSystem = $isSystem
            IsEmpty = $isEmpty
            Kind = if ($isSystem) { 'system' } elseif ($isEmpty) { 'empty' } else { 'normal' }
        }
    }

    $templateRows = foreach ($file in Get-JsonFileRows -Path $TemplatesPath) {
        $json = Read-JsonUtf8 -Path $file.FullName
        $id = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $name = if ($json.PSObject.Properties.Name -contains 'Name') { [string]$json.Name } else { '' }
        $refs = @($profileRows | Where-Object { $_.TemplateId -eq $id })
        $normalRefs = @($refs | Where-Object { $_.Kind -eq 'normal' })
        $emptyRefs = @($refs | Where-Object { $_.Kind -eq 'empty' })
        $looksGeneratedBlank = Test-GeneratedBlankTemplate -Id $id -Name $name
        $isManualProtected = Test-ManualProtectedTemplate -Name $name

        $kind = if ($normalRefs.Count -gt 0) {
            'normal-linked'
        } elseif ($emptyRefs.Count -gt 0) {
            if ($isManualProtected) { 'manual-empty-linked' } else { 'empty-linked' }
        } elseif ($isManualProtected) {
            'manual-orphan'
        } elseif ($looksGeneratedBlank) {
            'empty-orphan'
        } else {
            'normal-orphan'
        }

        [pscustomobject]@{
            File = $file.Name
            FullName = $file.FullName
            Id = $id
            Name = if ([string]::IsNullOrWhiteSpace($name)) { '<blank>' } else { $name }
            Mode = if ($json.PSObject.Properties.Name -contains 'Mode') { $json.Mode } else { $null }
            GyroMode = if ($json.PSObject.Properties.Name -contains 'Gyro') { $json.Gyro.Mode } else { $null }
            IsEdited = if ($json.PSObject.Properties.Name -contains 'IsEdited') { $json.IsEdited } else { $null }
            IsEditedByUser = if ($json.PSObject.Properties.Name -contains 'IsEditedByUser') { $json.IsEditedByUser } else { $null }
            IsManualProtected = $isManualProtected
            RefCount = $refs.Count
            RefProfiles = (($refs | Select-Object -ExpandProperty File) -join ', ')
            Kind = $kind
        }
    }

    $systemTemplateRows = foreach ($file in Get-JsonFileRows -Path $SystemTemplatesPath) {
        $json = Read-JsonUtf8 -Path $file.FullName
        [pscustomobject]@{
            File = $file.Name
            FullName = $file.FullName
            Name = if ($json.PSObject.Properties.Name -contains 'Name' -and -not [string]::IsNullOrWhiteSpace([string]$json.Name)) { [string]$json.Name } else { '<blank>' }
            Mode = if ($json.PSObject.Properties.Name -contains 'Mode') { $json.Mode } else { $null }
            GyroMode = if ($json.PSObject.Properties.Name -contains 'Gyro') { $json.Gyro.Mode } else { $null }
            Kind = 'system-template'
        }
    }

    return [pscustomobject]@{
        Profiles = @($profileRows)
        Templates = @($templateRows)
        SystemTemplates = @($systemTemplateRows)
        ProtectedFolders = @(Get-ProtectedFolderRows)
    }
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)

    Write-Host ''
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Show-State {
    param([Parameter(Mandatory)]$State)

    Write-Section 'Summary'
    [pscustomobject]@{
        Profiles = $State.Profiles.Count
        NormalProfiles = @($State.Profiles | Where-Object Kind -eq 'normal').Count
        EmptyProfiles = @($State.Profiles | Where-Object Kind -eq 'empty').Count
        SystemProfiles = @($State.Profiles | Where-Object Kind -eq 'system').Count
        Templates = $State.Templates.Count
        NormalLinkedTemplates = @($State.Templates | Where-Object Kind -eq 'normal-linked').Count
        EmptyLinkedTemplates = @($State.Templates | Where-Object Kind -eq 'empty-linked').Count
        EmptyOrphanTemplates = @($State.Templates | Where-Object Kind -eq 'empty-orphan').Count
        NormalOrphanTemplates = @($State.Templates | Where-Object Kind -eq 'normal-orphan').Count
        ManualProtectedTemplates = @($State.Templates | Where-Object IsManualProtected -eq $true).Count
        SystemTemplates = $State.SystemTemplates.Count
        ProtectedFolders = $State.ProtectedFolders.Count
        ProtectedFolderJson = ($State.ProtectedFolders | Measure-Object -Property JsonCount -Sum).Sum
    } | Format-List

    Write-Section 'Profiles'
    $State.Profiles |
        Sort-Object Kind, Name, File |
        Select-Object Kind, File, Name, BaseId, TemplateId, Mode, GyroMode, IsEdited, IsEditedByUser |
        Format-Table -AutoSize

    Write-Section 'Templates'
    $State.Templates |
        Sort-Object Kind, Name, File |
        Select-Object Kind, File, Name, Mode, GyroMode, IsManualProtected, RefCount, RefProfiles |
        Format-Table -AutoSize

    Write-Section 'SystemTemplates'
    $State.SystemTemplates |
        Sort-Object File |
        Select-Object Kind, File, Name, Mode, GyroMode |
        Format-Table -AutoSize

    Write-Section 'Protected/Ignored Folders'
    $State.ProtectedFolders |
        Sort-Object Folder |
        Select-Object Folder, Exists, JsonCount, Note, Path |
        Format-Table -AutoSize
}

function Assert-PathInsideRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path

    if ($resolvedPath -ne $resolvedRoot -and -not $resolvedPath.StartsWith($resolvedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete outside expected root: $resolvedPath"
    }

    return $resolvedPath
}

function Remove-Rows {
    param(
        [Parameter(Mandatory)]$Rows,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Label
    )

    $items = @($Rows)
    if ($items.Count -eq 0) {
        Write-Host "No $Label to delete."
        return
    }

    Write-Host ''
    Write-Host "Deleting $($items.Count) ${Label}:" -ForegroundColor Yellow

    foreach ($row in $items) {
        $target = Assert-PathInsideRoot -Path $row.FullName -Root $Root
        Write-Host "  $($row.File)"

        if (-not $DryRun) {
            Remove-Item -LiteralPath $target -Force -ErrorAction Stop
        }
    }
}

function Write-DeletePlanRows {
    param(
        [Parameter(Mandatory)]$Rows,
        [Parameter(Mandatory)][string]$Label
    )

    $items = @($Rows)
    Write-Host ''
    Write-Host "$Label ($($items.Count)):" -ForegroundColor Yellow

    if ($items.Count -eq 0) {
        Write-Host '  <none>'
        return
    }

    foreach ($row in $items) {
        $details = @()

        if ($row.PSObject.Properties.Name -contains 'Kind') {
            $details += "kind=$($row.Kind)"
        }

        if ($row.PSObject.Properties.Name -contains 'Name') {
            $details += "name=$($row.Name)"
        }

        if ($row.PSObject.Properties.Name -contains 'TemplateId') {
            $details += "template=$($row.TemplateId)"
        }

        if ($row.PSObject.Properties.Name -contains 'RefCount') {
            $details += "refs=$($row.RefCount)"
        }

        if ($row.PSObject.Properties.Name -contains 'IsManualProtected' -and $row.IsManualProtected) {
            $details += 'manualProtected=true'
        }

        $suffix = if ($details.Count -gt 0) { "  [$($details -join '; ')]" } else { '' }
        Write-Host "  $($row.File)$suffix"
    }
}

function Confirm-DeletePlan {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)]$ProfileRows,
        [Parameter(Mandatory)]$TemplateRows,
        [string[]]$Warnings = @()
    )

    $profiles = @($ProfileRows)
    $templates = @($TemplateRows)
    $total = $profiles.Count + $templates.Count

    Write-Host ''
    Write-Host $Title -ForegroundColor Red

    foreach ($warning in $Warnings) {
        Write-Host $warning -ForegroundColor Red
    }

    Write-DeletePlanRows -Rows $profiles -Label 'Profiles to delete'
    Write-DeletePlanRows -Rows $templates -Label 'Templates to delete'

    if ($total -eq 0) {
        Write-Host ''
        Write-Host 'Nothing to delete.'
        return $false
    }

    Write-Host ''
    $confirm = Read-Host "Type DELETE to delete $total files"

    if ($confirm -ne 'DELETE') {
        Write-Host 'Cancelled.'
        return $false
    }

    return $true
}

function Invoke-CleanEmpty {
    param([switch]$Confirm)

    $state = Get-State
    $profilesToDelete = @($state.Profiles | Where-Object { $_.Kind -eq 'empty' })
    $profilesToKeep = @($state.Profiles | Where-Object { $_.Kind -eq 'normal' -or $_.Kind -eq 'system' })
    $keptTemplateIds = @($profilesToKeep | Where-Object { Test-GuidText $_.TemplateId } | Select-Object -ExpandProperty TemplateId -Unique)
    $templatesToDelete = @($state.Templates | Where-Object { $keptTemplateIds -notcontains $_.Id -and -not $_.IsManualProtected })

    if ($Confirm -and -not (Confirm-DeletePlan -Title 'Action 1 delete plan' -ProfileRows $profilesToDelete -TemplateRows $templatesToDelete)) {
        return
    }

    Remove-Rows -Rows $profilesToDelete -Root $ProfilesPath -Label 'empty profiles'
    Remove-Rows -Rows $templatesToDelete -Root $TemplatesPath -Label 'stale/unlinked templates'
}

function Invoke-CleanAllExceptSystem {
    param([switch]$Confirm)

    $state = Get-State
    $profilesToDelete = @($state.Profiles | Where-Object { $_.Kind -ne 'system' })
    $templatesToDelete = @($state.Templates | Where-Object { -not $_.IsManualProtected })

    if ($Confirm -and -not (Confirm-DeletePlan -Title 'Action 2 delete plan' -ProfileRows $profilesToDelete -TemplateRows $templatesToDelete -Warnings @(
        'This will delete all non-system profiles and user templates except templates whose Name starts with _.',
        'System profiles in Profiles\_sys_*.json and protected folders are kept.',
        'Protected folders: SystemTemplates, DefaultTemplates, Presets, CombKeys.',
        'Manual protected templates: Templates where Name starts with _.'
    ))) {
        return
    }

    Remove-Rows -Rows $profilesToDelete -Root $ProfilesPath -Label 'non-system profiles'
    Remove-Rows -Rows $templatesToDelete -Root $TemplatesPath -Label 'user templates'
}

function Show-Menu {
    Write-Host ''
    Write-Host 'Choose action:' -ForegroundColor Green
    Write-Host '  1. Delete empty profiles and stale/unlinked templates; keep normal game/app profiles/templates and templates whose Name starts with _.'
    Write-Host '  2. Delete all profiles/templates except system profiles/templates and templates whose Name starts with _.'
    Write-Host '     Protected folders are never deleted: SystemTemplates, DefaultTemplates, Presets, CombKeys.'
    Write-Host '  0. Exit without changes.'
    Write-Host ''
}

$state = Get-State
Show-State -State $state

if ($ScanOnly) {
    Write-Host ''
    Write-Host 'ScanOnly: no changes made.'
    exit 0
}

if ($Clean) {
    Write-Host ''
    Write-Host 'Clean: running action 1 without interactive menu.' -ForegroundColor Green
    Invoke-CleanEmpty

    Write-Section 'After'
    Show-State -State (Get-State)

    if ($DryRun) {
        Write-Host ''
        Write-Host 'DryRun was enabled: no files were actually deleted.' -ForegroundColor Yellow
    }

    exit 0
}

Show-Menu
$choice = Read-Host 'Enter 1, 2, or 0'

switch ($choice) {
    '1' { Invoke-CleanEmpty -Confirm }
    '2' { Invoke-CleanAllExceptSystem -Confirm }
    '0' { Write-Host 'No changes made.' }
    default { Write-Host 'Unknown choice. No changes made.' }
}

Write-Section 'After'
Show-State -State (Get-State)

if ($DryRun) {
    Write-Host ''
    Write-Host 'DryRun was enabled: no files were actually deleted.' -ForegroundColor Yellow
}
