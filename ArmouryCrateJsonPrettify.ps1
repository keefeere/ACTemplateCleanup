#requires -version 5.1

[CmdletBinding()]
param(
    [string]$RootPath = (Join-Path $env:LOCALAPPDATA 'Packages\B9ECED6F.ArmouryCrateSE_qmba6cd70vzyy\LocalState\GamepadCustomize'),
    [switch]$Apply,
    [ValidateSet('Tabs', 'Spaces')]
    [string]$Indent = 'Spaces',
    [ValidateRange(1, 8)]
    [int]$IndentSize = 2,
    [ValidateRange(20, 10000)]
    [int]$MaxInlineWidth = 250,
    [ValidateRange(0, 10000)]
    [int]$MaxInlineArrayWidth = 0,
    [ValidateRange(1, 50)]
    [int]$MultilineDepth = 3,
    [bool]$AddAir = $true,
    [ValidateRange(2, 200)]
    [int]$Depth = 100
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if ($MaxInlineArrayWidth -gt 0) {
    $MaxInlineWidth = $MaxInlineArrayWidth
}

$ColonSeparator = if ($AddAir) { ': ' } else { ':' }
$CommaSeparator = if ($AddAir) { ', ' } else { ',' }

function Read-TextUtf8 {
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Write-TextUtf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )

    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Get-IndentText {
    param([Parameter(Mandatory)][int]$Level)

    if ($Indent -eq 'Tabs') {
        return "`t" * $Level
    }

    return ' ' * ($Level * $IndentSize)
}

function Test-JsonScalar {
    param([AllowNull()][object]$Value)

    return $null -eq $Value -or
        $Value -is [string] -or
        $Value -is [char] -or
        $Value -is [bool] -or
        $Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int] -or
        $Value -is [uint32] -or
        $Value -is [long] -or
        $Value -is [uint64] -or
        $Value -is [single] -or
        $Value -is [double] -or
        $Value -is [decimal]
}

function Convert-JsonScalar {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return 'null'
    }

    if ($Value -is [string] -or $Value -is [char]) {
        return ($Value | ConvertTo-Json -Compress)
    }

    if ($Value -is [bool]) {
        if ($Value) {
            return 'true'
        }

        return 'false'
    }

    if ($Value -is [System.IFormattable]) {
        return $Value.ToString($null, [System.Globalization.CultureInfo]::InvariantCulture)
    }

    return ($Value | ConvertTo-Json -Compress)
}

function Format-JsonCompact {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][int]$Level
    )

    if ($Level -gt $Depth) {
        throw "JSON depth exceeds configured limit: $Depth"
    }

    if (Test-JsonScalar -Value $Value) {
        return Convert-JsonScalar -Value $Value
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $properties = @($Value.PSObject.Properties)

        if ($properties.Count -eq 0) {
            return '{}'
        }

        $parts = New-Object System.Collections.Generic.List[string]

        foreach ($property in $properties) {
            $name = Convert-JsonScalar -Value $property.Name
            $valueText = Format-JsonCompact -Value $property.Value -Level ($Level + 1)
            $parts.Add("$name$ColonSeparator$valueText")
        }

        if ($AddAir) {
            return '{ ' + (($parts.ToArray()) -join $CommaSeparator) + ' }'
        }

        return '{' + (($parts.ToArray()) -join $CommaSeparator) + '}'
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @($Value)

        if ($items.Count -eq 0) {
            return '[]'
        }

        $parts = New-Object System.Collections.Generic.List[string]

        foreach ($item in $items) {
            $parts.Add((Format-JsonCompact -Value $item -Level ($Level + 1)))
        }

        return '[' + (($parts.ToArray()) -join $CommaSeparator) + ']'
    }

    return Convert-JsonScalar -Value ([string]$Value)
}

function Format-JsonValue {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][int]$Level
    )

    if ($Level -gt $Depth) {
        throw "JSON depth exceeds configured limit: $Depth"
    }

    if (Test-JsonScalar -Value $Value) {
        return Convert-JsonScalar -Value $Value
    }

    $compact = Format-JsonCompact -Value $Value -Level $Level
    $forceMultiline = (($Level + 1) -lt $MultilineDepth)

    if ($Level -gt 0 -and -not $forceMultiline -and $compact.Length -le $MaxInlineWidth) {
        return $compact
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $properties = @($Value.PSObject.Properties)

        if ($properties.Count -eq 0) {
            return '{}'
        }

        $childIndent = Get-IndentText -Level ($Level + 1)
        $currentIndent = Get-IndentText -Level $Level
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('{')

        for ($i = 0; $i -lt $properties.Count; $i++) {
            $property = $properties[$i]
            $name = Convert-JsonScalar -Value $property.Name
            $valueText = Format-JsonValue -Value $property.Value -Level ($Level + 1)
            $suffix = if ($i -lt ($properties.Count - 1)) { ',' } else { '' }
            $lines.Add("$childIndent$name$ColonSeparator$valueText$suffix")
        }

        $lines.Add("$currentIndent}")
        return ($lines -join [Environment]::NewLine)
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @($Value)

        if ($items.Count -eq 0) {
            return '[]'
        }

        $childIndent = Get-IndentText -Level ($Level + 1)
        $currentIndent = Get-IndentText -Level $Level
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('[')

        for ($i = 0; $i -lt $items.Count; $i++) {
            $valueText = Format-JsonValue -Value $items[$i] -Level ($Level + 1)
            $suffix = if ($i -lt ($items.Count - 1)) { ',' } else { '' }
            $lines.Add("$childIndent$valueText$suffix")
        }

        $lines.Add("$currentIndent]")
        return ($lines -join [Environment]::NewLine)
    }

    return Convert-JsonScalar -Value ([string]$Value)
}

function Format-JsonText {
    param([Parameter(Mandatory)][string]$Text)

    $jsonObject = $Text | ConvertFrom-Json
    $pretty = Format-JsonValue -Value $jsonObject -Level 0

    if (-not $pretty.EndsWith([Environment]::NewLine)) {
        $pretty += [Environment]::NewLine
    }

    return $pretty
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
    $pathFull = (Resolve-Path -LiteralPath $Path).Path

    if ($pathFull.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $pathFull.Substring($rootFull.Length + 1)
    }

    return $pathFull
}

if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
    throw "RootPath does not exist: $RootPath"
}

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path
$jsonFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -Filter '*.json' -File -Recurse | Sort-Object FullName)

Write-Host ''
Write-Host "Root: $resolvedRoot" -ForegroundColor Cyan
Write-Host "JSON files found: $($jsonFiles.Count)" -ForegroundColor Cyan
Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'SCAN ONLY' })"
Write-Host "Indent: $Indent"
Write-Host "Max inline width: $MaxInlineWidth"
Write-Host "Multiline depth: $MultilineDepth"
Write-Host "Add air: $AddAir"
Write-Host ''

$results = New-Object System.Collections.Generic.List[object]

foreach ($file in $jsonFiles) {
    $relative = Get-RelativePath -Path $file.FullName -Root $resolvedRoot

    try {
        $original = Read-TextUtf8 -Path $file.FullName
        $pretty = Format-JsonText -Text $original
        $changed = $original -ne $pretty

        if ($changed -and $Apply) {
            Write-TextUtf8NoBom -Path $file.FullName -Text $pretty
        }

        $results.Add([pscustomobject]@{
            Status = if ($changed) { if ($Apply) { 'formatted' } else { 'would-format' } } else { 'already-pretty' }
            File = $relative
            SizeBefore = $file.Length
            SizeAfter = if ($changed) { $Utf8NoBom.GetByteCount($pretty) } else { $file.Length }
            Error = ''
        })
    } catch {
        $results.Add([pscustomobject]@{
            Status = 'invalid-json'
            File = $relative
            SizeBefore = $file.Length
            SizeAfter = $file.Length
            Error = $_.Exception.Message
        })
    }
}

$summary = [pscustomobject]@{
    Total = $results.Count
    AlreadyPretty = @($results | Where-Object Status -eq 'already-pretty').Count
    WouldFormat = @($results | Where-Object Status -eq 'would-format').Count
    Formatted = @($results | Where-Object Status -eq 'formatted').Count
    InvalidJson = @($results | Where-Object Status -eq 'invalid-json').Count
}

Write-Host '=== Summary ===' -ForegroundColor Cyan
$summary | Format-List

Write-Host ''
Write-Host '=== Files ===' -ForegroundColor Cyan
$results |
    Sort-Object Status, File |
    Select-Object Status, File, SizeBefore, SizeAfter, Error |
    Format-Table -AutoSize

if (-not $Apply) {
    Write-Host ''
    Write-Host 'No files were changed. Re-run with -Apply to write formatted JSON.' -ForegroundColor Yellow
}
