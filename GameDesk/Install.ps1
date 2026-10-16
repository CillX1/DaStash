# Installs GameDesk for the current user. No admin rights needed.
$ErrorActionPreference = 'Stop'
$version = '1.6.0'
$src = $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'Programs\GameDesk'
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

Write-Host "Installing GameDesk $version ..."

# Close a running copy so its files can be replaced.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*GameDesk.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
    Where-Object { $_.CommandLine -like '*GameDesk\browser*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

New-Item -ItemType Directory -Force $dest | Out-Null
foreach ($f in 'GameDesk.ps1', 'dashboard.html', 'logo.svg', 'logo.png', 'GameDesk.ico', 'Uninstall.ps1') {
    Copy-Item -LiteralPath (Join-Path $src $f) -Destination $dest -Force
}
# Files from a downloaded zip are marked "from the internet"; clear that so they can run.
Get-ChildItem -LiteralPath $dest | Unblock-File

$sh = New-Object -ComObject WScript.Shell
function New-GameDeskShortcut($path) {
    $lnk = $sh.CreateShortcut($path)
    $lnk.TargetPath = $ps
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dest\GameDesk.ps1`""
    $lnk.WorkingDirectory = $dest
    $lnk.WindowStyle = 7
    $lnk.IconLocation = "$dest\GameDesk.ico"
    $lnk.Description = 'GameDesk widget dashboard'
    $lnk.Save()
}
New-GameDeskShortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'GameDesk.lnk')
New-GameDeskShortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'GameDesk.lnk')

# Show up in Settings > Apps > Installed apps, with an Uninstall button.
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\GameDesk'
New-Item -Path $key -Force | Out-Null
$props = @{
    DisplayName = 'GameDesk'
    DisplayVersion = $version
    Publisher = 'GameDesk'
    DisplayIcon = "$dest\GameDesk.ico"
    InstallLocation = $dest
    UninstallString = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$dest\Uninstall.ps1`""
}
foreach ($k in $props.Keys) { Set-ItemProperty -Path $key -Name $k -Value $props[$k] }
Set-ItemProperty -Path $key -Name NoModify -Value 1 -Type DWord
Set-ItemProperty -Path $key -Name NoRepair -Value 1 -Type DWord

Write-Host 'Done! GameDesk is on your Desktop and in the Start menu. Starting it now...'
Start-Process $ps -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$dest\GameDesk.ps1`""
