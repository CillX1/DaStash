; Inno Setup script that builds Questrig-Setup-<version>.exe.
; Build:  ISCC.exe installer\Questrig.iss  (optionally /DAppVersion=1.2.3)

#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif
#define AppSrc "..\Questrig"
#define PS "{sys}\WindowsPowerShell\v1.0\powershell.exe"

[Setup]
AppId=Questrig
AppName=Questrig
AppVersion={#AppVersion}
AppPublisher=Questrig
AppPublisherURL=https://github.com/CillX1/Questrig
AppSupportURL=https://github.com/CillX1/Questrig/issues
; Per-user install, no admin rights needed (same folder the old Install.ps1 used).
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Questrig
DisableDirPage=yes
DisableProgramGroupPage=yes
ArchitecturesInstallIn64BitMode=x64compatible arm64
OutputDir=Output
OutputBaseFilename=Questrig-Setup-{#AppVersion}
SetupIconFile={#AppSrc}\Questrig.ico
UninstallDisplayIcon={app}\Questrig.ico
UninstallDisplayName=Questrig
WizardStyle=modern
Compression=lzma2
SolidCompression=yes

[Tasks]
Name: desktopicon; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#AppSrc}\Questrig.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\dashboard.html"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\logo.svg"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\logo.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\Questrig.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\README.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\quiz\*"; DestDir: "{app}\quiz"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "Stop-Questrig.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\Move-From-GameDesk.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\Questrig"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Questrig.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\Questrig.ico"; Comment: "Questrig widget dashboard"; Flags: runminimized
Name: "{userdesktop}\Questrig"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Questrig.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\Questrig.ico"; Comment: "Questrig widget dashboard"; Flags: runminimized; Tasks: desktopicon

[Registry]
; Remove the Apps entry written by the older script-based installer, so Questrig isn't listed twice.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\Questrig"; Flags: deletekey dontcreatekey

[Run]
Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Questrig.ps1"""; WorkingDir: "{app}"; Description: "Start Questrig now"; Flags: postinstall nowait skipifsilent runhidden

[UninstallRun]
Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Stop-Questrig.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "StopQuestrig"

[UninstallDelete]
; Saved widgets/notes, the Claude key and the dashboard's browser profile.
Type: files; Name: "{app}\data.json"
Type: filesandordirs; Name: "{localappdata}\Questrig"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  ExtractTemporaryFile('Stop-Questrig.ps1');
  Exec(ExpandConstant('{#PS}'),
       '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Stop-Questrig.ps1') + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // Questrig used to be called GameDesk: bring its saved data over and remove the old app.
  ExtractTemporaryFile('Move-From-GameDesk.ps1');
  Exec(ExpandConstant('{#PS}'),
       '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Move-From-GameDesk.ps1') + '" -Dest "' + ExpandConstant('{app}') + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;

// Questrig switched off Ollama starting with Windows; turn it back on (before {localappdata}\Questrig is deleted).
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usUninstall) and FileExists(ExpandConstant('{localappdata}\Questrig\ollama-autostart-off')) then
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder', 'Ollama.lnk');
end;
