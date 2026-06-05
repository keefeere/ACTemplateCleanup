# Armoury Crate SE Template Cleanup Toolkit

Small PowerShell toolkit for inspecting, cleaning, and formatting ASUS Armoury Crate SE gamepad customization JSON files.

This was built around a recurring Armoury Crate SE issue where empty gamepad profiles and duplicate templates keep coming back after the app is restarted. The scripts focus on the local `GamepadCustomize` data folder used by Armoury Crate SE.

## Scripts

- [ArmouryCrateGamepadCleanup.ps1](./ArmouryCrateGamepadCleanup.ps1)  
  Scans and cleans Armoury Crate SE `Profiles` and `Templates`.

- [ArmouryCrateJsonPrettify.ps1](./ArmouryCrateJsonPrettify.ps1)  
  Formats Armoury Crate SE JSON files into a readable compact style.

- [ArmouryCrateGamepadCleanupService.ps1](./ArmouryCrateGamepadCleanupService.ps1)  
  Service runner that periodically calls the cleanup script with `-Clean`.

- [Install-ArmouryCrateGamepadCleanupService.ps1](./Install-ArmouryCrateGamepadCleanupService.ps1)  
  Installs or updates the cleanup runner as a Windows service using NSSM.

## Important Warning

These scripts can delete Armoury Crate SE profile and template JSON files.

Make a backup before using them. Armoury Crate SE may also regenerate files while it is running, so close Armoury Crate SE before manual cleanup if you want predictable results.

The default Armoury Crate SE data path is resolved from the current user's local app data folder:

```powershell
$env:LOCALAPPDATA\Packages\B9ECED6F.ArmouryCrateSE_qmba6cd70vzyy\LocalState\GamepadCustomize
```

If your Armoury Crate SE package ID is different, pass `-BasePath` / `-RootPath` or update the package path in the scripts before running them.

## What Gets Cleaned

The cleanup script inspects these folders:

- `Profiles`
- `Templates`
- `SystemTemplates`
- `DefaultTemplates`
- `Presets`
- `CombKeys`

Only `Profiles` and `Templates` are deletion targets.

These folders are protected and only reported:

- `SystemTemplates`
- `DefaultTemplates`
- `Presets`
- `CombKeys`

System profiles are also protected. A profile is treated as system-owned if:

- the file name matches `_sys_*.json`, or
- its `TemplateId` starts with `_sys_`

## Cleanup Rules

The cleanup script classifies profiles and templates before deleting anything.

Profiles:

- `system`: kept
- `normal`: kept
- `empty`: deleted by action 1 and action 2

A non-system profile is considered empty if `Name` or `TemplateId` is blank.

Templates:

- linked templates referenced by kept normal/system profiles are kept
- unlinked/stale templates are deleted by action 1
- all user templates are deleted by action 2, except manually protected templates

Manual template protection:

- a template is manually protected when its JSON `Name` starts with `_`
- example: `"Name": "_My_Gamepad"`
- the file name does not matter; the protection is based on the `Name` field

This convention is useful for templates you want to keep even before assigning them to a game or app. It also tends to make the template appear near the top of the Armoury Crate SE template list.

## Quick Start

Open PowerShell and run commands from this folder:

```powershell
cd "path\to\ACTemplateCleanup"
```

Scan only:

```powershell
.\ArmouryCrateGamepadCleanup.ps1 -ScanOnly
```

Interactive cleanup menu:

```powershell
.\ArmouryCrateGamepadCleanup.ps1
```

Silent cleanup, action 1:

```powershell
.\ArmouryCrateGamepadCleanup.ps1 -Clean
```

Dry run:

```powershell
.\ArmouryCrateGamepadCleanup.ps1 -Clean -DryRun
```

## Cleanup Modes

Interactive mode shows the current state first, then offers:

1. Delete empty profiles and stale/unlinked templates.  
   Keeps system profiles, normal linked game/app templates, protected folders, and templates whose `Name` starts with `_`.

2. Delete all non-system profiles and user templates.  
   Keeps system profiles, protected folders, and templates whose `Name` starts with `_`.

Before either interactive deletion mode runs, the script prints the exact files that will be deleted and requires typing:

```text
DELETE
```

The `-Clean` switch runs action 1 without the menu. This is the mode used by the service runner.

## JSON Prettifier

Armoury Crate SE often writes dense single-line JSON. The prettifier rewrites JSON into a more readable format while keeping short arrays and short objects inline.

Default behavior is scan only:

```powershell
.\ArmouryCrateJsonPrettify.ps1
```

Apply formatting:

```powershell
.\ArmouryCrateJsonPrettify.ps1 -Apply
```

Useful options:

```powershell
.\ArmouryCrateJsonPrettify.ps1 -Apply -Indent Spaces -IndentSize 2 -MaxInlineWidth 250 -MultilineDepth 3
```

Defaults:

- `RootPath`: the hardcoded Armoury Crate SE `GamepadCustomize` folder
- `Indent`: `Spaces`
- `IndentSize`: `2`
- `MaxInlineWidth`: `250`
- `MultilineDepth`: `3`
- `AddAir`: `$true`

`AddAir` controls spaces after commas and colons inside inline JSON fragments.

## Service Mode

The service runner repeatedly calls:

```powershell
ArmouryCrateGamepadCleanup.ps1 -Clean -BasePath "<GamepadCustomize path>"
```

Default interval:

```text
300 seconds
```

The service installer uses [NSSM](https://nssm.cc/) to run the PowerShell loop as a Windows service.

NSSM homepage:

```text
https://nssm.cc/
```

The installer looks for `nssm.exe` in common locations, including:

```text
C:\Windows\System32\nssm.exe
C:\Windows\Sysnative\nssm.exe
C:\Windows\SysWOW64\nssm.exe
C:\Windows\System32\nssm\nssm.exe
C:\nssm\win64\nssm.exe
C:\Tools\nssm.exe
```

Install or update the service from an elevated PowerShell window:

```powershell
.\Install-ArmouryCrateGamepadCleanupService.ps1 -NssmPath "$env:WINDIR\System32\nssm.exe" -IntervalSeconds 300
```

The installer captures the current user's Armoury Crate SE `GamepadCustomize` path and passes it to the service runner explicitly. This matters because Windows services may run under a service account whose `%LOCALAPPDATA%` is not the interactive user's `%LOCALAPPDATA%`.

Override the target folder if needed:

```powershell
.\Install-ArmouryCrateGamepadCleanupService.ps1 -BasePath "$env:LOCALAPPDATA\Packages\B9ECED6F.ArmouryCrateSE_qmba6cd70vzyy\LocalState\GamepadCustomize"
```

Default service name:

```text
ArmouryCrateGamepadCleanup
```

Default logs:

```text
<script directory>\ArmouryCrateGamepadCleanupService.log
%USERPROFILE%\ArmouryCrateGamepadCleanupService.stdout.log
%USERPROFILE%\ArmouryCrateGamepadCleanupService.stderr.log
```

Check service status:

```powershell
Get-Service -Name ArmouryCrateGamepadCleanup
```

Stop the service:

```powershell
nssm stop ArmouryCrateGamepadCleanup
```

Remove the service:

```powershell
nssm remove ArmouryCrateGamepadCleanup confirm
```

## Runtime Location Notes

The cleanup and prettifier scripts can be run directly from this repository folder.

The service scripts also default to their own script directory:

```text
directory containing the running .ps1 file
```

Specifically:

- `ArmouryCrateGamepadCleanupService.ps1` defaults to `ArmouryCrateGamepadCleanup.ps1` in the same folder
- `Install-ArmouryCrateGamepadCleanupService.ps1` defaults to `ArmouryCrateGamepadCleanupService.ps1` in the same folder
- the runner log defaults to the same folder as the runner script
- NSSM stdout/stderr logs default to `%USERPROFILE%`

If you want to run the service with scripts from another folder, pass `-RunnerScript` to the installer and pass `-CleanupScript` to the runner if needed.

## Recommended Workflow

1. Close Armoury Crate SE.
2. Back up the `GamepadCustomize` folder.
3. Run `.\ArmouryCrateGamepadCleanup.ps1 -ScanOnly`.
4. Review the profile/template classification.
5. Run `.\ArmouryCrateGamepadCleanup.ps1 -Clean -DryRun`.
6. Run `.\ArmouryCrateGamepadCleanup.ps1 -Clean`.
7. Start Armoury Crate SE and verify templates/profiles in the UI.
8. Install the service only after the manual cleanup behavior looks correct.

## Known Limitations

- The scripts do not modify Armoury Crate SE databases.
- The scripts do not clean `DefaultTemplates`, `Presets`, `SystemTemplates`, or `CombKeys`.
- Armoury Crate SE may regenerate files after updates, reinstallations, or UI actions.
- Factory/default templates shown by Armoury Crate SE may come from internal app state, not only from visible JSON files.
- The service is a simple periodic cleanup loop, not a file system watcher.

## Requirements

- Windows PowerShell 5.1
- Armoury Crate SE installed for the configured package path
- NSSM only if installing the service

## License

MIT License. See [LICENSE](./LICENSE).
