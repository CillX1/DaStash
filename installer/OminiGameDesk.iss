; Inno Setup script that builds OminiGameDesk-Setup-<version>.exe.
; Build:  ISCC.exe installer\OminiGameDesk.iss  (optionally /DAppVersion=1.2.3)

#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif
#define AppSrc "..\OminiGameDesk"
#define PS "{sys}\WindowsPowerShell\v1.0\powershell.exe"

[Setup]
AppId=OminiGameDesk
AppName=OminiGameDesk
AppVersion={#AppVersion}
AppPublisher=OminiGameDesk
AppPublisherURL=https://github.com/CillX1/OminiGameDesk
AppSupportURL=https://github.com/CillX1/OminiGameDesk/issues
; Per-user install, no admin rights needed (same folder the old Install.ps1 used).
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\OminiGameDesk
DisableDirPage=yes
DisableProgramGroupPage=yes
ArchitecturesInstallIn64BitMode=x64compatible arm64
OutputDir=Output
OutputBaseFilename=OminiGameDesk-Setup-{#AppVersion}
SetupIconFile={#AppSrc}\OminiGameDesk.ico
UninstallDisplayIcon={app}\OminiGameDesk.ico
UninstallDisplayName=OminiGameDesk
WizardStyle=modern
Compression=lzma2
SolidCompression=yes

[Tasks]
Name: desktopicon; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#AppSrc}\OminiGameDesk.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\dashboard.html"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\logo.svg"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\logo.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\OminiGameDesk.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\README.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\quiz\*"; DestDir: "{app}\quiz"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "Stop-OminiGameDesk.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\Move-From-GameDesk.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\OminiGameDesk"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\OminiGameDesk.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\OminiGameDesk.ico"; Comment: "OminiGameDesk widget dashboard"; Flags: runminimized
Name: "{userdesktop}\OminiGameDesk"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\OminiGameDesk.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\OminiGameDesk.ico"; Comment: "OminiGameDesk widget dashboard"; Flags: runminimized; Tasks: desktopicon

[Registry]
; Remove the Apps entry written by the older script-based installer, so OminiGameDesk isn't listed twice.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\OminiGameDesk"; Flags: deletekey dontcreatekey

[Run]
Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\OminiGameDesk.ps1"""; WorkingDir: "{app}"; Description: "Start OminiGameDesk now"; Flags: postinstall nowait skipifsilent runhidden

[UninstallRun]
Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Stop-OminiGameDesk.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "StopOminiGameDesk"

[UninstallDelete]
; Saved widgets/notes, the Claude key and the dashboard's browser profile.
Type: files; Name: "{app}\data.json"
Type: filesandordirs; Name: "{localappdata}\OminiGameDesk"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  ExtractTemporaryFile('Stop-OminiGameDesk.ps1');
  Exec(ExpandConstant('{#PS}'),
       '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Stop-OminiGameDesk.ps1') + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // OminiGameDesk used to be called GameDesk: bring its saved data over and remove the old app.
  ExtractTemporaryFile('Move-From-GameDesk.ps1');
  Exec(ExpandConstant('{#PS}'),
       '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Move-From-GameDesk.ps1') + '" -Dest "' + ExpandConstant('{app}') + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;

// OminiGameDesk switched off Ollama starting with Windows; turn it back on (before {localappdata}\OminiGameDesk is deleted).
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usUninstall) and FileExists(ExpandConstant('{localappdata}\OminiGameDesk\ollama-autostart-off')) then
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder', 'Ollama.lnk');
end;
