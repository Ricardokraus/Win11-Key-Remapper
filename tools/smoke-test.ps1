<#
.SYNOPSIS
    End-to-end checks of a release, run by GitHub Actions (it starts the real
    app, so run it on a test machine only).

.DESCRIPTION
    1. The release folder: Win11KeyRemapper.exe (the bundled AutoHotkey
       runtime) starts the app through the launcher, and the app writes its
       settings.ini.
    2. The installer, if given: a silent install, the app started from the
       install folder, then the uninstall that Installed apps runs (--uninstall
       --quiet), which must leave only settings.ini; then again with
       --delete-settings, which must leave nothing.

.EXAMPLE
    ./tools/smoke-test.ps1 -Package dist\Win11KeyRemapper-v0.5.5 -Setup dist\Win11KeyRemapper-Setup-v0.5.5.exe
#>
param(
    [Parameter(Mandatory)] [string]$Package,
    [string]$Setup = ''
)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class SmokeWin {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
'@
$title = 'Windows 11 Key Remapper'

function Wait-App([int]$Seconds = 20) {           # the app's hidden window
    for ($i = 0; $i -lt $Seconds * 10; $i++) {
        if ([SmokeWin]::FindWindow('AutoHotkey', $title) -ne [IntPtr]::Zero) { return $true }
        Start-Sleep -Milliseconds 100
    }
    return $false
}
function Stop-App {                                 # like tray > Exit
    $h = [SmokeWin]::FindWindow('AutoHotkey', $title)
    if ($h -ne [IntPtr]::Zero) { [void][SmokeWin]::PostMessage($h, 0x111, [IntPtr]65307, [IntPtr]::Zero) }
    for ($i = 0; $i -lt 100 -and [SmokeWin]::FindWindow('AutoHotkey', $title) -ne [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 100 }
    Get-Process AutoHotkey*, Win11KeyRemapper -ErrorAction SilentlyContinue | Stop-Process -Force
}
function Check([bool]$Ok, [string]$What) {
    if ($Ok) { "ok    $What" } else { Stop-App; throw "FAILED: $What" }
}

$Package = (Resolve-Path $Package).Path
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'Windows 11 Key Remapper.lnk'

# ---- 1. The release folder ----
Start-Process "$Package\Win11KeyRemapper.exe" -WorkingDirectory $Package | Out-Null
Check (Wait-App) 'Win11KeyRemapper.exe starts the app (bundled runtime + launcher)'
Start-Sleep -Seconds 2
Check (Test-Path "$Package\src\settings.ini") 'first run writes src\settings.ini'
Stop-App
Remove-Item "$Package\src\settings.ini", $startup -ErrorAction SilentlyContinue

if (-not $Setup) { return }

# ---- 2. The installer ----
$app = "$env:LOCALAPPDATA\Programs\Win11KeyRemapper"
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Win11KeyRemapper'
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Windows 11 Key Remapper.lnk'

function Install([bool]$FirstRun) {
    $p = Start-Process (Resolve-Path $Setup).Path -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
    Check ($p.ExitCode -eq 0) "setup exit code 0 (got $($p.ExitCode))"
    Check ((Test-Path "$app\Win11KeyRemapper.exe") -and (Test-Path "$app\src\Win11KeyRemapper.ahk")) 'installed files'
    Check (Test-Path $menu) 'Start menu shortcut'
    Check ((Get-ItemProperty $key).UninstallString -like '*--uninstall') 'Installed apps entry runs the app''s uninstall'
    Start-Process "$app\Win11KeyRemapper.exe" -ArgumentList "`"$app\src\Win11KeyRemapper.ahk`"" -WorkingDirectory "$app\src" | Out-Null
    Check (Wait-App) 'the installed app starts'
    Start-Sleep -Seconds 2
    Check (Test-Path "$app\src\settings.ini") 'settings.ini there'
    if ($FirstRun) { Check (Test-Path $startup) 'first run turns on Start with Windows' }
    Stop-App
    Set-Content "$app\src\Win11KeyRemapper.log" 'log'
}
function Uninstall([string]$Extra) {               # what Installed apps runs, without questions
    $cmd = (Get-ItemProperty $key).UninstallString
    if ($cmd -notmatch '^"([^"]+)"\s+(.*)$') { throw "unexpected UninstallString: $cmd" }
    $p = Start-Process $Matches[1] -ArgumentList "$($Matches[2]) --quiet $Extra" -Wait -PassThru
    Start-Sleep -Seconds 8                          # the exe and the folders go a moment after it exits
}

Install $true
Uninstall ''
$left = @(Get-ChildItem $app -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Replace("$app\", '') })
Check (($left -join ',') -eq 'src\settings.ini') "uninstall keeps only settings.ini (left: $($left -join ', '))"
Check (-not (Test-Path $key) -and -not (Test-Path $menu) -and -not (Test-Path $startup)) 'uninstall removes the entry and the shortcuts'

Install $false
Uninstall '--delete-settings'
Check (-not (Test-Path $app)) 'uninstall with --delete-settings leaves nothing'
"all smoke tests passed"
