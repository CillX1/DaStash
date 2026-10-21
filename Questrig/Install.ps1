# Installs Questrig for the current user. No admin rights needed.
$ErrorActionPreference = 'Stop'
$version = '2.0.0'
$src = $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'Programs\Questrig'
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

Write-Host "Installing Questrig $version ..."

# Close a running copy so its files can be replaced.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*Questrig.ps1*' } |
    ForEach-Object {
        # Also end the Ollama server Questrig started (and its model runner).
        Get-CimInstance Win32_Process -Filter "Name='ollama.exe' AND ParentProcessId=$($_.ProcessId)" |
            ForEach-Object { taskkill.exe /PID $_.ProcessId /T /F | Out-Null }
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like '*Questrig\browser*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

New-Item -ItemType Directory -Force $dest | Out-Null
# Questrig used to be called GameDesk: bring its saved data over and remove the old app.
& (Join-Path $src 'Move-From-GameDesk.ps1') -Dest $dest
foreach ($f in 'Questrig.ps1', 'dashboard.html', 'logo.svg', 'logo.png', 'Questrig.ico', 'Uninstall.ps1') {
    Copy-Item -LiteralPath (Join-Path $src $f) -Destination $dest -Force
}
# QuizDesk (the Quizzes widget): its scripts and the quizzes that come with it.
Copy-Item -LiteralPath (Join-Path $src 'quiz') -Destination $dest -Recurse -Force
# Files from a downloaded zip are marked "from the internet"; clear that so they can run.
Get-ChildItem -LiteralPath $dest -Recurse -File | Unblock-File

$sh = New-Object -ComObject WScript.Shell
function New-QuestrigShortcut($path) {
    $lnk = $sh.CreateShortcut($path)
    $lnk.TargetPath = $ps
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dest\Questrig.ps1`""
    $lnk.WorkingDirectory = $dest
    $lnk.WindowStyle = 7
    $lnk.IconLocation = "$dest\Questrig.ico"
    $lnk.Description = 'Questrig widget dashboard'
    $lnk.Save()
}
New-QuestrigShortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Questrig.lnk')
New-QuestrigShortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'Questrig.lnk')

# Show up in Settings > Apps > Installed apps, with an Uninstall button.
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Questrig'
New-Item -Path $key -Force | Out-Null
$props = @{
    DisplayName = 'Questrig'
    DisplayVersion = $version
    Publisher = 'Questrig'
    DisplayIcon = "$dest\Questrig.ico"
    InstallLocation = $dest
    UninstallString = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$dest\Uninstall.ps1`""
}
foreach ($k in $props.Keys) { Set-ItemProperty -Path $key -Name $k -Value $props[$k] }
Set-ItemProperty -Path $key -Name NoModify -Value 1 -Type DWord
Set-ItemProperty -Path $key -Name NoRepair -Value 1 -Type DWord

Write-Host 'Done! Questrig is on your Desktop and in the Start menu. Starting it now...'
Start-Process $ps -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$dest\Questrig.ps1`""
