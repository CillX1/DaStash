; Inno Setup script that builds DaStash-Setup-<version>.exe.
; Build:  ISCC.exe installer\DaStash.iss  (optionally /DAppVersion=1.2.3)

#ifndef AppVersion
  #define AppVersion "2.2.0"
#endif
#define AppSrc "..\DaStash"
#define PS "{sys}\WindowsPowerShell\v1.0\powershell.exe"

[Setup]
AppId=DaStash
AppName=DaStash
AppVersion={#AppVersion}
AppPublisher=DaStash
AppPublisherURL=https://github.com/CillX1/DaStash
AppSupportURL=https://github.com/CillX1/DaStash/issues
; Per-user install, no admin rights needed (same folder the old Install.ps1 used).
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\DaStash
DisableDirPage=yes
DisableProgramGroupPage=yes
ArchitecturesInstallIn64BitMode=x64compatible arm64
OutputDir=Output
OutputBaseFilename=DaStash-Setup-{#AppVersion}
SetupIconFile={#AppSrc}\DaStash.ico
UninstallDisplayIcon={app}\DaStash.ico
UninstallDisplayName=DaStash
WizardStyle=modern
Compression=lzma2
SolidCompression=yes

[Tasks]
Name: desktopicon; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#AppSrc}\DaStash.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\dashboard.html"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\logo.svg"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\logo.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\DaStash.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\README.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "Stop-DaStash.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\Move-From-Old-Names.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\DaStash"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\DaStash.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\DaStash.ico"; Comment: "DaStash widget dashboard"; Flags: runminimized
Name: "{userdesktop}\DaStash"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\DaStash.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\DaStash.ico"; Comment: "DaStash widget dashboard"; Flags: runminimized; Tasks: desktopicon

[Registry]
; Remove the Apps entry written by the older script-based installer, so DaStash isn't listed twice.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\DaStash"; Flags: deletekey dontcreatekey

[Run]
Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\DaStash.ps1"""; WorkingDir: "{app}"; Description: "Start DaStash now"; Flags: postinstall nowait skipifsilent runhidden

[UninstallRun]
Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Stop-DaStash.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "StopDaStash"

[UninstallDelete]
; Saved widgets/notes, the Claude key and the dashboard's browser profile.
Type: files; Name: "{app}\data.json"
Type: filesandordirs; Name: "{localappdata}\DaStash"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  ExtractTemporaryFile('Stop-DaStash.ps1');
  Exec(ExpandConstant('{#PS}'),
       '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Stop-DaStash.ps1') + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // DaStash used to be called GameDesk (and OmniGameDesk in 2.0.0): bring its saved data over and remove the old app.
  ExtractTemporaryFile('Move-From-Old-Names.ps1');
  Exec(ExpandConstant('{#PS}'),
       '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Move-From-Old-Names.ps1') + '" -Dest "' + ExpandConstant('{app}') + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;

// DaStash switched off Ollama starting with Windows; turn it back on (before {localappdata}\DaStash is deleted).
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usUninstall) and FileExists(ExpandConstant('{localappdata}\DaStash\ollama-autostart-off')) then
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder', 'Ollama.lnk');
end;
