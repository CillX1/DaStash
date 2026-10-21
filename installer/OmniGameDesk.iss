; Inno Setup script that builds OmniGameDesk-Setup-<version>.exe.
; Build:  ISCC.exe installer\OmniGameDesk.iss  (optionally /DAppVersion=1.2.3)

#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif
#define AppSrc "..\OmniGameDesk"
#define PS "{sys}\WindowsPowerShell\v1.0\powershell.exe"

[Setup]
AppId=OmniGameDesk
AppName=OmniGameDesk
AppVersion={#AppVersion}
AppPublisher=OmniGameDesk
AppPublisherURL=https://github.com/CillX1/OmniGameDesk
AppSupportURL=https://github.com/CillX1/OmniGameDesk/issues
; Per-user install, no admin rights needed (same folder the old Install.ps1 used).
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\OmniGameDesk
DisableDirPage=yes
DisableProgramGroupPage=yes
ArchitecturesInstallIn64BitMode=x64compatible arm64
OutputDir=Output
OutputBaseFilename=OmniGameDesk-Setup-{#AppVersion}
SetupIconFile={#AppSrc}\OmniGameDesk.ico
UninstallDisplayIcon={app}\OmniGameDesk.ico
UninstallDisplayName=OmniGameDesk
WizardStyle=modern
Compression=lzma2
SolidCompression=yes

[Tasks]
Name: desktopicon; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#AppSrc}\OmniGameDesk.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\dashboard.html"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\logo.svg"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\logo.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\OmniGameDesk.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\README.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "Stop-OmniGameDesk.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\Move-From-GameDesk.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\OmniGameDesk"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\OmniGameDesk.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\OmniGameDesk.ico"; Comment: "OmniGameDesk widget dashboard"; Flags: runminimized
Name: "{userdesktop}\OmniGameDesk"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\OmniGameDesk.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\OmniGameDesk.ico"; Comment: "OmniGameDesk widget dashboard"; Flags: runminimized; Tasks: desktopicon

[Registry]
; Remove the Apps entry written by the older script-based installer, so OmniGameDesk isn't listed twice.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\OmniGameDesk"; Flags: deletekey dontcreatekey

[Run]
Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\OmniGameDesk.ps1"""; WorkingDir: "{app}"; Description: "Start OmniGameDesk now"; Flags: postinstall nowait skipifsilent runhidden

[UninstallRun]
Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Stop-OmniGameDesk.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "StopOmniGameDesk"

[UninstallDelete]
; Saved widgets/notes, the Claude key and the dashboard's browser profile.
Type: files; Name: "{app}\data.json"
Type: filesandordirs; Name: "{localappdata}\OmniGameDesk"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  ExtractTemporaryFile('Stop-OmniGameDesk.ps1');
  Exec(ExpandConstant('{#PS}'),
       '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Stop-OmniGameDesk.ps1') + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // OmniGameDesk used to be called GameDesk: bring its saved data over and remove the old app.
  ExtractTemporaryFile('Move-From-GameDesk.ps1');
  Exec(ExpandConstant('{#PS}'),
       '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Move-From-GameDesk.ps1') + '" -Dest "' + ExpandConstant('{app}') + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;

// OmniGameDesk switched off Ollama starting with Windows; turn it back on (before {localappdata}\OmniGameDesk is deleted).
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usUninstall) and FileExists(ExpandConstant('{localappdata}\OmniGameDesk\ollama-autostart-off')) then
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder', 'Ollama.lnk');
end;
