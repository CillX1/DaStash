# Removes GameDesk, its shortcuts and its saved data.
$dest = Join-Path $env:LOCALAPPDATA 'Programs\GameDesk'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*GameDesk.ps1*' } |
    ForEach-Object {
        # Also end the Ollama server GameDesk started (and its model runner).
        Get-CimInstance Win32_Process -Filter "Name='ollama.exe' AND ParentProcessId=$($_.ProcessId)" |
            ForEach-Object { taskkill.exe /PID $_.ProcessId /T /F | Out-Null }
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like '*GameDesk\browser*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 800

Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'GameDesk.lnk') -ErrorAction SilentlyContinue
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'GameDesk.lnk') -ErrorAction SilentlyContinue
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\GameDesk' -Recurse -ErrorAction SilentlyContinue
# GameDesk switched off Ollama starting with Windows; turn it back on.
if (Test-Path (Join-Path $env:LOCALAPPDATA 'GameDesk\ollama-autostart-off')) {
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' -Name 'Ollama.lnk' -ErrorAction SilentlyContinue
}
Remove-Item (Join-Path $env:LOCALAPPDATA 'GameDesk') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue

Add-Type -AssemblyName PresentationFramework
[void][System.Windows.MessageBox]::Show('GameDesk has been uninstalled.', 'GameDesk')
