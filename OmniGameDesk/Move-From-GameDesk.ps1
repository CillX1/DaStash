# OmniGameDesk used to be called GameDesk. When GameDesk is installed, this moves its saved data over
# (widgets, notes, to-dos, links, the Claude key, Anti-Freeze settings) and removes the old app.
param([string]$Dest = (Join-Path $env:LOCALAPPDATA 'Programs\OmniGameDesk'))
$ErrorActionPreference = 'SilentlyContinue'
$old = Join-Path $env:LOCALAPPDATA 'Programs\GameDesk'
$oldData = Join-Path $env:LOCALAPPDATA 'GameDesk'
$newData = Join-Path $env:LOCALAPPDATA 'OmniGameDesk'
if (-not (Test-Path $old) -and -not (Test-Path $oldData)) { return }

# Close a running GameDesk, the Ollama server it started and its window.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*GameDesk.ps1*' } |
    ForEach-Object {
        Get-CimInstance Win32_Process -Filter "Name='ollama.exe' AND ParentProcessId=$($_.ProcessId)" |
            ForEach-Object { taskkill.exe /PID $_.ProcessId /T /F | Out-Null }
        Stop-Process -Id $_.ProcessId -Force
    }
Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like '*GameDesk\browser*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Milliseconds 800

# data.json (widgets, notes, to-dos, links, city, AI switch) lives next to the app.
New-Item -ItemType Directory -Force $Dest | Out-Null
if ((Test-Path "$old\data.json") -and -not (Test-Path "$Dest\data.json")) { Copy-Item "$old\data.json" "$Dest\data.json" }
# The Claude key, Anti-Freeze settings, the Ollama marker and the dashboard's browser profile.
if ((Test-Path $oldData) -and -not (Test-Path $newData)) { Move-Item $oldData $newData }

# Remove the old app: its own uninstaller when it was installed with the setup, otherwise by hand.
if (Test-Path "$old\unins000.exe") {
    Start-Process "$old\unins000.exe" -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait
}
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'GameDesk.lnk')
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'GameDesk.lnk')
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\GameDesk' -Recurse
Remove-Item $old -Recurse -Force
