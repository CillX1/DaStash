# Removes OmniGameDesk, its shortcuts and its saved data.
$dest = Join-Path $env:LOCALAPPDATA 'Programs\OmniGameDesk'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*OmniGameDesk.ps1*' } |
    ForEach-Object {
        # Also end the Ollama server OmniGameDesk started (and its model runner).
        Get-CimInstance Win32_Process -Filter "Name='ollama.exe' AND ParentProcessId=$($_.ProcessId)" |
            ForEach-Object { taskkill.exe /PID $_.ProcessId /T /F | Out-Null }
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like '*OmniGameDesk\browser*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 800

Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'OmniGameDesk.lnk') -ErrorAction SilentlyContinue
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'OmniGameDesk.lnk') -ErrorAction SilentlyContinue
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OmniGameDesk' -Recurse -ErrorAction SilentlyContinue
# OmniGameDesk switched off Ollama starting with Windows; turn it back on.
if (Test-Path (Join-Path $env:LOCALAPPDATA 'OmniGameDesk\ollama-autostart-off')) {
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' -Name 'Ollama.lnk' -ErrorAction SilentlyContinue
}
Remove-Item (Join-Path $env:LOCALAPPDATA 'OmniGameDesk') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue

Add-Type -AssemblyName PresentationFramework
[void][System.Windows.MessageBox]::Show('OmniGameDesk has been uninstalled.', 'OmniGameDesk')
