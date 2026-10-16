; Inno Setup script that builds GameDesk-Setup-<version>.exe.
; Build:  ISCC.exe installer\GameDesk.iss  (optionally /DAppVersion=1.2.3)

#ifndef AppVersion
  #define AppVersion "1.6.0"
#endif
#define AppSrc "..\GameDesk"
#define PS "{sys}\WindowsPowerShell\v1.0\powershell.exe"

[Setup]
AppId=GameDesk
AppName=GameDesk
AppVersion={#AppVersion}
AppPublisher=GameDesk
AppPublisherURL=https://github.com/CillX1/GameDesk
AppSupportURL=https://github.com/CillX1/GameDesk/issues
; Per-user install, no admin rights needed (same folder the old Install.ps1 used).
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\GameDesk
DisableDirPage=yes
DisableProgramGroupPage=yes
ArchitecturesInstallIn64BitMode=x64compatible arm64
OutputDir=Output
OutputBaseFilename=GameDesk-Setup-{#AppVersion}
SetupIconFile={#AppSrc}\GameDesk.ico
UninstallDisplayIcon={app}\GameDesk.ico
UninstallDisplayName=GameDesk
WizardStyle=modern
Compression=lzma2
SolidCompression=yes

[Tasks]
Name: desktopicon; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#AppSrc}\GameDesk.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\dashboard.html"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\logo.svg"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\logo.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\GameDesk.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppSrc}\README.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "Stop-GameDesk.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\GameDesk"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\GameDesk.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\GameDesk.ico"; Comment: "GameDesk widget dashboard"; Flags: runminimized
Name: "{userdesktop}\GameDesk"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\GameDesk.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\GameDesk.ico"; Comment: "GameDesk widget dashboard"; Flags: runminimized; Tasks: desktopicon

[Registry]
; Remove the Apps entry written by the older script-based installer, so GameDesk isn't listed twice.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\GameDesk"; Flags: deletekey dontcreatekey

[Run]
Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\GameDesk.ps1"""; WorkingDir: "{app}"; Description: "Start GameDesk now"; Flags: postinstall nowait skipifsilent runhidden

[UninstallRun]
Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Stop-GameDesk.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "StopGameDesk"

[UninstallDelete]
; Saved widgets/notes, the Claude key and the dashboard's browser profile.
Type: files; Name: "{app}\data.json"
Type: filesandordirs; Name: "{localappdata}\GameDesk"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  ExtractTemporaryFile('Stop-GameDesk.ps1');
  Exec(ExpandConstant('{#PS}'),
       '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Stop-GameDesk.ps1') + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;
