# GameDesk was briefly called OmniGameDesk (version 2.0.0). When OmniGameDesk is installed, this moves its saved data
# back (widgets, notes, to-dos, links, the Claude key, Anti-Freeze settings) and removes it.
param([string]$Dest = (Join-Path $env:LOCALAPPDATA 'Programs\GameDesk'))
$ErrorActionPreference = 'SilentlyContinue'
$old = Join-Path $env:LOCALAPPDATA 'Programs\OmniGameDesk'
$oldData = Join-Path $env:LOCALAPPDATA 'OmniGameDesk'
$newData = Join-Path $env:LOCALAPPDATA 'GameDesk'
if (-not (Test-Path $old) -and -not (Test-Path $oldData)) { return }

# Close a running OmniGameDesk, the Ollama server it started and its window.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*OmniGameDesk.ps1*' } |
    ForEach-Object {
        Get-CimInstance Win32_Process -Filter "Name='ollama.exe' AND ParentProcessId=$($_.ProcessId)" |
            ForEach-Object { taskkill.exe /PID $_.ProcessId /T /F | Out-Null }
        Stop-Process -Id $_.ProcessId -Force
    }
Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like '*OmniGameDesk\browser*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Milliseconds 800

# data.json (widgets, notes, to-dos, links, city, AI switch) lives next to the app.
New-Item -ItemType Directory -Force $Dest | Out-Null
if ((Test-Path "$old\data.json") -and -not (Test-Path "$Dest\data.json")) { Copy-Item "$old\data.json" "$Dest\data.json" }
# The Claude key, Anti-Freeze settings, the Ollama marker and the dashboard's browser profile.
if ((Test-Path $oldData) -and -not (Test-Path $newData)) { Move-Item $oldData $newData }

# Remove OmniGameDesk: its own uninstaller when it was installed with the setup, otherwise by hand.
if (Test-Path "$old\unins000.exe") {
    Start-Process "$old\unins000.exe" -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait
}
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'OmniGameDesk.lnk')
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'OmniGameDesk.lnk')
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OmniGameDesk' -Recurse
Remove-Item $old -Recurse -Force
