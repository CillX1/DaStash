# Closes a running OminiGameDesk (its PowerShell server and Edge window) so files can be replaced or removed.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*OminiGameDesk.ps1*' } |
    ForEach-Object {
        # Also end the Ollama server OminiGameDesk started (and its model runner).
        Get-CimInstance Win32_Process -Filter "Name='ollama.exe' AND ParentProcessId=$($_.ProcessId)" |
            ForEach-Object { taskkill.exe /PID $_.ProcessId /T /F | Out-Null }
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like '*OminiGameDesk\browser*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 800
