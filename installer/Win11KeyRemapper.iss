; Inno Setup script for Windows 11 Key Remapper (Inno Setup 7, https://jrsoftware.org/isinfo.php)
;
; Built by the release workflow from the release folder (the same files as the
; zip), then signed through SignPath when that's set up:
;   ISCC.exe /DAppVersion=0.5.5 /DSourceDir=dist\Win11KeyRemapper-v0.5.5 installer\Win11KeyRemapper.iss
;
; - Per user, no admin rights: %LOCALAPPDATA%\Programs\Win11KeyRemapper. The
;   app keeps settings.ini in src\ there, writable.
; - The app runs on the bundled AutoHotkey runtime (Win11KeyRemapper.exe), so
;   the shortcuts start "Win11KeyRemapper.exe src\Win11KeyRemapper.ahk".
; - No Inno uninstaller: it would be an unsigned exe written on the user's PC,
;   and Smart App Control blocks those. Installed apps runs the app with
;   --uninstall instead (UninstallApp), which removes everything and asks
;   about the settings. That's why the uninstall entry is written by hand.
; - "Start with Windows" is the app's: it turns it on at its first run.

#ifndef AppVersion
  #error Pass the version: ISCC /DAppVersion=x.y.z /DSourceDir=<release folder>
#endif
#ifndef SourceDir
  #error Pass the release folder: ISCC /DSourceDir=<folder>
#endif

#define AppName "Windows 11 Key Remapper"
#define AppRepo "https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense"
#define UninstallKey "Software\Microsoft\Windows\CurrentVersion\Uninstall\Win11KeyRemapper"

[Setup]
AppId=Win11KeyRemapper
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Ricardokraus
AppPublisherURL={#AppRepo}
AppSupportURL={#AppRepo}/blob/main/SUPPORT.md
AppUpdatesURL={#AppRepo}/releases
AppCopyright=Copyright (c) 2026 Ricardo - MIT License
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
PrivilegesRequired=lowest
DefaultDirName={autopf}\Win11KeyRemapper
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
WizardStyle=modern dynamic
SetupIconFile=..\assets\icon.ico
Uninstallable=no
CreateUninstallRegKey=no
CloseApplications=no
Compression=lzma2
SolidCompression=yes
OutputDir=..\dist
OutputBaseFilename=Win11KeyRemapper-Setup-v{#AppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; settings.ini isn't in the release, so an update never touches it
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\Win11KeyRemapper.exe"; Parameters: """{app}\src\Win11KeyRemapper.ahk"""; WorkingDir: "{app}\src"; IconFilename: "{app}\assets\icon.ico"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\Win11KeyRemapper.exe"; Parameters: """{app}\src\Win11KeyRemapper.ahk"""; WorkingDir: "{app}\src"; IconFilename: "{app}\assets\icon.ico"; Tasks: desktopicon

[Registry]
; The Installed apps entry: uninstalling runs the app's own uninstall
Root: HKCU; Subkey: "{#UninstallKey}"; ValueType: string; ValueName: "DisplayName"; ValueData: "{#AppName}"
Root: HKCU; Subkey: "{#UninstallKey}"; ValueType: string; ValueName: "DisplayVersion"; ValueData: "{#AppVersion}"
Root: HKCU; Subkey: "{#UninstallKey}"; ValueType: string; ValueName: "Publisher"; ValueData: "Ricardokraus"
Root: HKCU; Subkey: "{#UninstallKey}"; ValueType: string; ValueName: "DisplayIcon"; ValueData: "{app}\assets\icon.ico"
Root: HKCU; Subkey: "{#UninstallKey}"; ValueType: string; ValueName: "InstallLocation"; ValueData: "{app}"
Root: HKCU; Subkey: "{#UninstallKey}"; ValueType: string; ValueName: "URLInfoAbout"; ValueData: "{#AppRepo}"
Root: HKCU; Subkey: "{#UninstallKey}"; ValueType: string; ValueName: "UninstallString"; ValueData: """{app}\Win11KeyRemapper.exe"" ""{app}\src\Win11KeyRemapper.ahk"" --uninstall"
Root: HKCU; Subkey: "{#UninstallKey}"; ValueType: dword; ValueName: "NoModify"; ValueData: 1
Root: HKCU; Subkey: "{#UninstallKey}"; ValueType: dword; ValueName: "NoRepair"; ValueData: 1

[Run]
Filename: "{app}\Win11KeyRemapper.exe"; Parameters: """{app}\src\Win11KeyRemapper.ahk"""; WorkingDir: "{app}\src"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
function FindWindow(ClassName, WindowName: String): HWND;
  external 'FindWindowW@user32.dll stdcall';

// Asks a running copy to exit (like its tray menu's Exit) and waits, so its
// files can be replaced. Its hidden window: "Windows 11 Key Remapper", or
// "Win11KeyRemapper.Instance" up to 0.5.2.
procedure CloseRunningApp;
var
  Wnd: HWND;
  Tries: Integer;
begin
  Tries := 0;
  repeat
    Wnd := FindWindow('AutoHotkey', 'Windows 11 Key Remapper');
    if Wnd = 0 then
      Wnd := FindWindow('AutoHotkey', 'Win11KeyRemapper.Instance');
    if Wnd <> 0 then
    begin
      if Tries mod 10 = 0 then
        PostMessage(Wnd, $0111, 65307, 0);   // WM_COMMAND, ID_FILE_EXIT
      Sleep(100);
    end;
    Tries := Tries + 1;
  until (Wnd = 0) or (Tries > 50);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  CloseRunningApp;
  Result := '';
end;
