# OmniGameDesk - a widget dashboard for Windows.
# Runs a tiny local server (127.0.0.1 only) that the dashboard window talks to,
# then opens the dashboard in its own Edge app window. Closing the window stops everything.
param([switch]$CreateShortcut)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dataFile = Join-Path $root 'data.json'

if ($CreateShortcut) {
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'OmniGameDesk.lnk'))
    $lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$root\OmniGameDesk.ps1`""
    $lnk.WorkingDirectory = $root
    $lnk.WindowStyle = 7
    $lnk.IconLocation = "$root\OmniGameDesk.ico"
    $lnk.Save()
    Write-Host 'Shortcut "OmniGameDesk" created on your Desktop.'
    return
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GD {
    [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    [DllImport("kernel32.dll")] public static extern ulong GetTickCount64();
    [StructLayout(LayoutKind.Sequential)]
    public class MEMSTAT {
        public uint dwLength = 64; public uint dwMemoryLoad;
        public ulong ullTotalPhys; public ulong ullAvailPhys; public ulong ullTotalPageFile; public ulong ullAvailPageFile;
        public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual;
    }
    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx([In, Out] MEMSTAT m);
    [StructLayout(LayoutKind.Sequential)]
    public struct POWER { public byte ACLineStatus; public byte BatteryFlag; public byte BatteryLifePercent; public byte SystemStatusFlag; public int BatteryLifeTime; public int BatteryFullLifeTime; }
    [DllImport("kernel32.dll")] static extern bool GetSystemPowerStatus(out POWER p);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool LockWorkStation();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    // True when a window hasn't handled any input for 5 seconds (what Windows shows as "Not Responding").
    [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr hWnd);

    static long pIdle, pKernel, pUser;
    public static double Cpu() {
        long i, k, u; GetSystemTimes(out i, out k, out u);
        long di = i - pIdle, dt = (k - pKernel) + (u - pUser);
        pIdle = i; pKernel = k; pUser = u;
        if (dt <= 0) return 0;
        return Math.Round(100.0 * (dt - di) / dt, 1);
    }
    public static MEMSTAT Mem() { var m = new MEMSTAT(); GlobalMemoryStatusEx(m); return m; }
    public static POWER Power() { POWER p; GetSystemPowerStatus(out p); return p; }
    // Media keys are "extended" keys: flag 1 = extended, 2 = key up.
    public static void Key(byte vk) { keybd_event(vk, 0, 1, UIntPtr.Zero); keybd_event(vk, 0, 3, UIntPtr.Zero); }
    public static void Combo(byte mod, byte vk) {
        keybd_event(mod, 0, 0, UIntPtr.Zero); keybd_event(vk, 0, 0, UIntPtr.Zero);
        keybd_event(vk, 0, 2, UIntPtr.Zero); keybd_event(mod, 0, 2, UIntPtr.Zero);
    }
}
'@
[void][GD]::Cpu()

$singleInstance = [Threading.Mutex]::new($false, 'Local\OmniGameDesk')
$isFirst = try { $singleInstance.WaitOne(0) } catch [Threading.AbandonedMutexException] { $true }
if (-not $isFirst) {
    $w = Get-Process msedge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*OmniGameDesk*' } | Select-Object -First 1
    if ($w) { [void][GD]::ShowWindow($w.MainWindowHandle, 9); [void][GD]::SetForegroundWindow($w.MainWindowHandle) }
    return
}
# Windows PowerShell 5.1 otherwise wraps arrays as {value, Count} in JSON.
Remove-TypeData System.Array -ErrorAction SilentlyContinue

# ---------- Apps & games ----------
$wantedApps = @(
    'Claude', 'Spotify', 'Lenovo Vantage', 'Lenovo Legion Arena', 'Lenovo Now', 'Steam', 'XBOX', 'Ubisoft Connect',
    'Epic Games Launcher', 'EA', 'EA app', 'Battle.net', 'Riot Client', 'GOG GALAXY', 'Discord', 'AMD Software',
    'NVIDIA app', 'GeForce Experience', 'OBS Studio', 'Microsoft Teams', 'WhatsApp', 'Google Chrome', 'Microsoft Edge'
)
$apps = @{}
foreach ($a in Get-StartApps) {
    if ($wantedApps -contains $a.Name -and -not $apps.ContainsKey($a.Name)) { $apps[$a.Name] = $a.AppID }
}

function Get-SteamGames {
    $games = @{}
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { return @() }
    $libs = @($steam -replace '/', '\')
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\', '\') }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        Get-ChildItem (Join-Path $lib 'steamapps') -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue | ForEach-Object {
            $t = Get-Content $_.FullName -Raw
            $id = [regex]::Match($t, '"appid"\s+"(\d+)"').Groups[1].Value
            $name = [regex]::Match($t, '"name"\s+"([^"]+)"').Groups[1].Value
            if ($id -and $name -and $name -notmatch 'Redistributable|Steamworks|Proton|Runtime') { $games[$id] = $name }
        }
    }
    $games.GetEnumerator() | Sort-Object Value | ForEach-Object { [pscustomobject]@{ id = $_.Key; name = $_.Value } }
}
$steamGames = @(Get-SteamGames)

# Fixed list of Windows tools the dashboard may open - nothing else can be launched.
$tools = @{
    taskmgr = { Start-Process taskmgr.exe }
    settings = { Start-Process 'ms-settings:' }
    explorer = { Start-Process explorer.exe }
    calc = { Start-Process calc.exe }
    snip = { Start-Process 'ms-screenclip:' }
    gamebar = { [GD]::Combo(0x5B, 0x47) }          # Win+G
    sound = { Start-Process 'ms-settings:sound' }
    display = { Start-Process 'ms-settings:display' }
    power = { Start-Process 'ms-settings:powersleep' }
    battery = { Start-Process 'ms-settings:batterysaver' }
    bluetooth = { Start-Process 'ms-settings:bluetooth' }
    wifi = { Start-Process 'ms-settings:network-wifi' }
    gaming = { Start-Process 'ms-settings:gaming-gamemode' }
    update = { Start-Process 'ms-settings:windowsupdate' }
    downloads = { Start-Process explorer.exe (Join-Path $env:USERPROFILE 'Downloads') }
    lock = { [void][GD]::LockWorkStation() }
    spotifyshow = { Show-Spotify }
    spotifyhide = { Hide-Spotify }
}
$mediaKeys = @{ playpause = 0xB3; next = 0xB0; prev = 0xB1; volup = 0xAF; voldown = 0xAE; mute = 0xAD }
$pingHosts = [ordered]@{ 'Cloudflare' = '1.1.1.1'; 'Google' = '8.8.8.8'; 'Quad9' = '9.9.9.9' }

# ---------- Spotify via Windows media controls ----------
# Talks to Spotify's own media session, so buttons control Spotify (not whatever app played last)
# and we get the song, artist and album cover.
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$winrtHelpers = {
    $script:asTaskOp = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
    function Await-WinRT($op, [Type]$type, [int]$ms = 3000) {
        $task = $script:asTaskOp.MakeGenericMethod($type).Invoke($null, @($op))
        if ($task.Wait($ms)) { return $task.Result }
    }
    [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
    [void][Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]
    function Get-MediaManager { Await-WinRT ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]) }
    function Get-SpotifySession($mgr) { if ($mgr) { $mgr.GetSessions() | Where-Object { $_.SourceAppUserModelId -like '*Spotify*' } | Select-Object -First 1 } }
}
. $winrtHelpers
$mediaMgr = try { Get-MediaManager } catch { $null }
$spotifyExe = @("$env:LOCALAPPDATA\Microsoft\WindowsApps\Spotify.exe", "$env:APPDATA\Spotify\Spotify.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$script:spArt = @{ key = ''; bytes = $null; type = 'image/jpeg' }
$script:asStreamForRead = [System.IO.WindowsRuntimeStreamExtensions].GetMethod('AsStreamForRead', [Type[]]@([Windows.Storage.Streams.IInputStream]))

function Get-SpotifyNow {
    $s = try { Get-SpotifySession $mediaMgr } catch { $null }
    if (-not $s) { return $null }
    $p = Await-WinRT ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
    if (-not $p) { return $null }
    $key = "$($p.Artist)|$($p.Title)"
    if ($p.Thumbnail -and $script:spArt.key -ne $key) {
        try {
            $ras = Await-WinRT ($p.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
            # PowerShell can't bind the WinRT stream to these .NET helpers directly, so call them via reflection.
            $ms = New-Object IO.MemoryStream
            $script:asStreamForRead.Invoke($null, @($ras)).CopyTo($ms)
            $ct = try { [Windows.Storage.Streams.IContentTypeProvider].GetProperty('ContentType').GetValue($ras) } catch { $null }
            $script:spArt = @{ key = $key; bytes = $ms.ToArray(); type = $(if ($ct) { $ct } else { 'image/jpeg' }) }
        } catch { $script:spArt = @{ key = $key; bytes = $null; type = 'image/jpeg' } }
    }
    @{
        title = $p.Title; artist = $p.Artist; album = $p.AlbumTitle
        status = "$($s.GetPlaybackInfo().PlaybackStatus)"
        art = $(if ($script:spArt.bytes -and $script:spArt.key -eq $key) { [string][Math]::Abs($key.GetHashCode()) } else { $null })
    }
}

# Spotify's window handle while OmniGameDesk keeps it hidden (a hidden window has no MainWindowHandle, so remember it).
$script:spotifyHwnd = [IntPtr]::Zero
function Get-SpotifyVisibleWindow { Get-Process Spotify -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1 }
function Test-SpotifyHidden { $script:spotifyHwnd -ne [IntPtr]::Zero -and [GD]::IsWindow($script:spotifyHwnd) -and -not [GD]::IsWindowVisible($script:spotifyHwnd) }
function Hide-Spotify {
    $w = Get-SpotifyVisibleWindow
    if ($w) { $script:spotifyHwnd = $w.MainWindowHandle; [void][GD]::ShowWindow($w.MainWindowHandle, 0) }   # 0 = hide (no taskbar button)
}
function Show-Spotify([switch]$Minimized) {
    if (Test-SpotifyHidden) {
        [void][GD]::ShowWindow($script:spotifyHwnd, $(if ($Minimized) { 7 } else { 9 }))   # 7 = minimized, 9 = restore
        if (-not $Minimized) { [void][GD]::SetForegroundWindow($script:spotifyHwnd) }
        $script:spotifyHwnd = [IntPtr]::Zero
    } elseif (-not $Minimized -and $apps.ContainsKey('Spotify')) {
        Start-Process explorer.exe "shell:AppsFolder\$($apps['Spotify'])"
    }
}

# Starts Spotify as a hidden background process and begins playback (runs in a background runspace).
$spotifyStartWorker = {
    param($job, $exe, $helpers)
    try {
        . ([ScriptBlock]::Create($helpers))
        Start-Process $exe '--minimized'
        $mgr = Get-MediaManager
        $hideWindow = {
            $w = Get-Process Spotify -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
            if ($w) { $job.hwnd = [long]$w.MainWindowHandle; [void][GD]::ShowWindow($w.MainWindowHandle, 0) }
        }
        # Wait for Spotify's media session, hiding its window as soon as it appears.
        $deadline = (Get-Date).AddSeconds(30); $s = $null
        while ((Get-Date) -lt $deadline) {
            & $hideWindow
            if (-not $s) { $s = Get-SpotifySession $mgr }
            if ($s -and $job.hwnd) { break }
            if ($s -and (Get-Date) -gt $deadline.AddSeconds(-22)) { break }   # session ready; don't wait forever for a window
            Start-Sleep -Milliseconds 300
        }
        if (-not $s) {
            [GD]::Key(0xB3); $job.text = 'started'; $job.done = $true; return
        }
        Start-Sleep -Milliseconds 800
        for ($i = 0; $i -lt 6; $i++) {
            [void](Await-WinRT ($s.TryPlayAsync()) ([bool]))
            Start-Sleep -Milliseconds 700
            & $hideWindow
            if ("$($s.GetPlaybackInfo().PlaybackStatus)" -eq 'Playing') { $job.text = 'playing'; break }
        }
        # Spotify sometimes shows its window once it has finished loading; keep it hidden.
        for ($i = 0; $i -lt 6; $i++) { Start-Sleep -Milliseconds 500; & $hideWindow }
        if ($job.text -ne 'playing') { $job.error = 'Spotify started, but there was no song ready to play. Click "Show app" and pick a song once.' }
    } catch { $job.error = $_.Exception.Message }
    $job.done = $true
}

function Invoke-SpotifyControl([string]$k) {
    $s = try { Get-SpotifySession $mediaMgr } catch { $null }
    if ($s) {
        $op = switch ($k) { 'playpause' { $s.TryTogglePlayPauseAsync() } 'next' { $s.TrySkipNextAsync() } 'prev' { $s.TrySkipPreviousAsync() } }
        [void](Await-WinRT $op ([bool]))
        return @{ ok = $true }
    }
    if ($k -eq 'playpause' -and $spotifyExe -and -not (Get-Process Spotify -ErrorAction SilentlyContinue)) {
        return @{ ok = $true; starting = (Start-BackgroundJob $spotifyStartWorker $spotifyExe $winrtHelpers.ToString()) }
    }
    [GD]::Key([byte]$mediaKeys[$k])
    return @{ ok = $true }
}
function Get-Stats {
    $mem = [GD]::Mem()
    $pw = [GD]::Power()
    $c = [System.IO.DriveInfo]::new('C')
    $spAll = @(Get-Process Spotify -ErrorAction SilentlyContinue)
    $sp = $spAll | Where-Object { $_.MainWindowTitle } | Select-Object -First 1
    @{
        cpu = [GD]::Cpu()
        ramUsed = [math]::Round(($mem.ullTotalPhys - $mem.ullAvailPhys) / 1GB, 1)
        ramTotal = [math]::Round($mem.ullTotalPhys / 1GB, 1)
        ramPct = $mem.dwMemoryLoad
        diskFree = [math]::Round($c.AvailableFreeSpace / 1GB, 0)
        diskTotal = [math]::Round($c.TotalSize / 1GB, 0)
        uptimeMin = [math]::Floor([GD]::GetTickCount64() / 60000)
        battery = @{
            hasBattery = ($pw.BatteryFlag -ne 128 -and $pw.BatteryFlag -ne 255)
            pct = $pw.BatteryLifePercent
            plugged = ($pw.ACLineStatus -eq 1)
            charging = (($pw.BatteryFlag -band 8) -ne 0)
            minutesLeft = $(if ($pw.BatteryLifeTime -gt 0) { [math]::Round($pw.BatteryLifeTime / 60) } else { $null })
            saver = ($pw.SystemStatusFlag -eq 1)
        }
        spotify = @{
            running = $spAll.Count -gt 0
            title = $(if ($sp) { $sp.MainWindowTitle } else { '' })
            now = $(try { Get-SpotifyNow } catch { $null })
            hidden = [bool](Test-SpotifyHidden)
        }
    }
}

function Get-Pings {
    $tasks = @{}
    foreach ($k in $pingHosts.Keys) { $tasks[$k] = ([System.Net.NetworkInformation.Ping]::new()).SendPingAsync($pingHosts[$k], 900) }
    try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($tasks.Values), 2500) } catch {}
    foreach ($k in $pingHosts.Keys) {
        $t = $tasks[$k]
        $ms = $null
        if ($t.Status -eq 'RanToCompletion' -and $t.Result.Status -eq 'Success') { $ms = [int]$t.Result.RoundtripTime }
        [pscustomobject]@{ name = $k; host = $pingHosts[$k]; ms = $ms }
    }
}

# ---------- Claude chat ----------
# The API key is stored encrypted for this Windows user only (DPAPI), outside the app folder,
# so it is never part of a shared zip.
$claudeKeyFile = Join-Path $env:LOCALAPPDATA 'OmniGameDesk\claude.key'
$claudeModel = 'claude-opus-5-5'
$claudeSystem = 'You are Claude, answering inside OmniGameDesk, a small widget dashboard on the user''s Windows gaming PC. ' +
    'Keep answers short and easy to scan: lead with the answer, then brief details. Use simple Markdown (bold, lists, code blocks) only when it helps.'
$claudeJobs = @{}
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Get-ClaudeKey {
    if (-not (Test-Path $claudeKeyFile)) { return $null }
    try {
        $sec = (Get-Content $claudeKeyFile -Raw).Trim() | ConvertTo-SecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    } catch { return $null }
}

function Test-ClaudeKey([string]$key) {
    # Listing models is free, so it is a cheap way to check that a key works.
    $r = [Net.HttpWebRequest]::Create('https://api.anthropic.com/v1/models?limit=1')
    $r.Headers.Add('x-api-key', $key); $r.Headers.Add('anthropic-version', '2023-06-01'); $r.Timeout = 15000
    try { $r.GetResponse().Close(); return $null }
    catch [Net.WebException] {
        $resp = $_.Exception.Response
        if ($resp -and [int]$resp.StatusCode -in 401, 403) { return 'That key was not accepted. Check that you copied all of it.' }
        if ($resp) { return $null }   # other errors (e.g. overloaded) do not mean the key is wrong
        return 'Could not reach Claude. Are you online?'
    }
}

# Runs in a background runspace: streams the answer and appends text to $job.text as it arrives.
$claudeWorker = {
    param($job, $key, $body)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $req = [Net.HttpWebRequest]::Create('https://api.anthropic.com/v1/messages')
        $req.Method = 'POST'; $req.ContentType = 'application/json'
        $req.Headers.Add('x-api-key', $key)
        $req.Headers.Add('anthropic-version', '2023-06-01')
        $req.Headers.Add('anthropic-beta', 'server-side-fallback-2026-07-01')
        $req.Timeout = 300000; $req.ReadWriteTimeout = 300000
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $req.ContentLength = $bytes.Length
        $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
        try { $resp = $req.GetResponse() }
        catch [Net.WebException] {
            $r = $_.Exception.Response
            if ($r) {
                $raw = [IO.StreamReader]::new($r.GetResponseStream()).ReadToEnd()
                $msg = try { ($raw | ConvertFrom-Json).error.message } catch { $raw }
                $job.status = [int]$r.StatusCode; $job.error = "$msg"
            } else { $job.status = 0; $job.error = $_.Exception.Message }
            $job.done = $true; return
        }
        $rd = [IO.StreamReader]::new($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        while ($null -ne ($line = $rd.ReadLine())) {
            if (-not $line.StartsWith('data:')) { continue }
            $ev = $line.Substring(5).Trim() | ConvertFrom-Json
            switch ($ev.type) {
                'content_block_delta' { if ($ev.delta.type -eq 'text_delta') { $job.text += $ev.delta.text } }
                'message_delta' { if ($ev.delta.stop_reason) { $job.stop = $ev.delta.stop_reason } }
                'error' { $job.status = 0; $job.error = "$($ev.error.message)" }
            }
        }
        $rd.Close(); $resp.Close()
    } catch { $job.status = 0; $job.error = $_.Exception.Message }
    $job.done = $true
}

function Start-ClaudeJob($messages) {
    $payload = [ordered]@{
        model = $claudeModel
        max_tokens = 16000
        stream = $true
        fallbacks = 'default'
        output_config = @{ effort = 'low' }   # quick chat answers; the model still thinks when it needs to
        system = $claudeSystem
        messages = @($messages | ForEach-Object { [ordered]@{ role = $_.role; content = [string]$_.content } })
    }
    return Start-BackgroundJob $claudeWorker (Get-ClaudeKey) ($payload | ConvertTo-Json -Depth 6 -Compress)
}

# Runs a worker in a background runspace so the dashboard stays responsive; the page polls /api/claude/poll.
function Start-BackgroundJob($worker, $arg1, $arg2) {
    $job = [hashtable]::Synchronized(@{ text = ''; done = $false; error = $null; status = $null; stop = $null; progress = $null })
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript($worker).AddArgument($job).AddArgument($arg1).AddArgument($arg2)
    $job.ps = $ps
    $job.handle = $ps.BeginInvoke()
    $id = [guid]::NewGuid().ToString('N')
    $claudeJobs[$id] = $job
    return $id
}

# ---------- Local AI (Ollama) ----------
# Free and offline: a small open model running on this PC through Ollama (ollama.com).
$ollamaBase = 'http://127.0.0.1:11434'
$localModel = 'gemma3:4b'
$localModelName = 'Gemma 3'
$ollamaExe = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
$script:ollamaProc = $null   # the Ollama server OmniGameDesk started itself; stopped again when OmniGameDesk closes
# The on/off switch in the AI panel (saved by the dashboard in data.json). Off: OmniGameDesk doesn't start Ollama.
$script:ollamaOff = $false
try { $script:ollamaOff = [bool]([IO.File]::ReadAllText($dataFile) | ConvertFrom-Json).localAiOff } catch {}

function Test-OllamaRunning {
    try { $r = [Net.HttpWebRequest]::Create("$ollamaBase/api/tags"); $r.Timeout = 1200; $r.GetResponse().Close(); return $true } catch { return $false }
}

# Ollama only runs while OmniGameDesk is open: start it here unless it's already running (then it isn't ours to stop).
function Start-Ollama {
    if ($script:ollamaOff -or ($script:ollamaProc -and -not $script:ollamaProc.HasExited)) { return }
    $exe = if (Test-Path $ollamaExe) { $ollamaExe } else { (Get-Command ollama -ErrorAction SilentlyContinue).Source }
    if (-not $exe -or (Test-OllamaRunning)) { return }
    $script:ollamaProc = Start-Process $exe 'serve' -WindowStyle Hidden -PassThru
}

# -All (the panel's off switch) also stops an Ollama OmniGameDesk didn't start, e.g. its tray app.
function Stop-Ollama([switch]$All) {
    if ($script:ollamaProc -and -not $script:ollamaProc.HasExited) {
        # /T also ends the model runner (llama-server) Ollama started, which holds the model's memory.
        taskkill.exe /PID $script:ollamaProc.Id /T /F | Out-Null
    }
    if ($All) { Stop-Process -Name 'ollama app', 'ollama', 'llama-server' -Force -ErrorAction SilentlyContinue }
}

# OmniGameDesk starts Ollama when it opens, so Ollama no longer needs to start with Windows and hold memory all day.
# Switched off once, the same way Task Manager > Startup apps does it, so the user can turn it back on there
# (the marker file makes sure OmniGameDesk doesn't undo that). Uninstalling OmniGameDesk turns it back on.
function Disable-OllamaAutostart {
    $marker = Join-Path $env:LOCALAPPDATA 'OmniGameDesk\ollama-autostart-off'
    if ((Test-Path $marker) -or -not (Test-Path (Join-Path ([Environment]::GetFolderPath('Startup')) 'Ollama.lnk'))) { return }
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    # 03 = disabled, then the time it was switched off.
    Set-ItemProperty -Path $key -Name 'Ollama.lnk' -Type Binary -Value ([byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTime())))
    New-Item -ItemType File -Force $marker | Out-Null
}

function Get-LocalAiStatus {
    $installed = (Test-Path $ollamaExe) -or [bool](Get-Command ollama -ErrorAction SilentlyContinue)
    $running = $false; $hasModel = $false
    try {
        $r = [Net.HttpWebRequest]::Create("$ollamaBase/api/tags"); $r.Timeout = 1200
        $resp = $r.GetResponse()
        $tags = [IO.StreamReader]::new($resp.GetResponseStream()).ReadToEnd() | ConvertFrom-Json; $resp.Close()
        $running = $true
        $hasModel = [bool]($tags.models | Where-Object { $_.name -eq $localModel -or $_.model -eq $localModel })
    } catch {}
    if ($installed -and -not $running) { Start-Ollama }   # e.g. Ollama was installed while OmniGameDesk was open
    if ($installed) { try { Disable-OllamaAutostart } catch {} }
    @{ installed = $installed; running = $running; hasModel = $hasModel; off = $script:ollamaOff; model = $localModel; name = $localModelName }
}

# Streams an answer from Ollama (newline-delimited JSON).
$localWorker = {
    param($job, $base, $body)
    try {
        $req = [Net.HttpWebRequest]::Create("$base/api/chat")
        $req.Method = 'POST'; $req.ContentType = 'application/json'
        $req.Timeout = 600000; $req.ReadWriteTimeout = 600000
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $req.ContentLength = $bytes.Length
        $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
        try { $resp = $req.GetResponse() }
        catch [Net.WebException] {
            $r = $_.Exception.Response
            if ($r) {
                $raw = [IO.StreamReader]::new($r.GetResponseStream()).ReadToEnd()
                $job.status = [int]$r.StatusCode; $job.error = try { ($raw | ConvertFrom-Json).error } catch { $raw }
            } else { $job.status = 0; $job.error = 'The local AI is not running.' }
            $job.done = $true; return
        }
        $rd = [IO.StreamReader]::new($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        while ($null -ne ($line = $rd.ReadLine())) {
            if (-not $line.Trim()) { continue }
            $ev = $line | ConvertFrom-Json
            if ($ev.error) { $job.status = 500; $job.error = "$($ev.error)"; break }
            if ($ev.message.content) { $job.text += $ev.message.content }
            if ($ev.done) { $job.stop = $(if ($ev.done_reason -eq 'length') { 'max_tokens' } else { 'end_turn' }) }
        }
        $rd.Close(); $resp.Close()
    } catch { $job.status = 0; $job.error = $_.Exception.Message }
    $job.done = $true
}

function Start-LocalJob($messages) {
    $system = "You are OmniGameDesk AI, a helpful assistant built into OmniGameDesk, a widget dashboard on the user's Windows gaming PC. " +
        "You run locally on their PC (model: $localModelName), so you work offline and cannot browse the web. Today is $((Get-Date).ToString('dddd, d MMMM yyyy')). " +
        'Keep answers short and easy to scan: lead with the answer, then brief details. Use simple Markdown only when it helps. ' +
        'If you are not sure about a fact, say so instead of guessing.'
    $msgs = @([ordered]@{ role = 'system'; content = $system }) + @($messages | ForEach-Object { [ordered]@{ role = $_.role; content = [string]$_.content } })
    $payload = [ordered]@{ model = $localModel; messages = $msgs; stream = $true; keep_alive = '5m' }
    return Start-BackgroundJob $localWorker $ollamaBase ($payload | ConvertTo-Json -Depth 6 -Compress)
}

# Downloads the model through Ollama, reporting progress.
$pullWorker = {
    param($job, $base, $body)
    try {
        $req = [Net.HttpWebRequest]::Create("$base/api/pull")
        $req.Method = 'POST'; $req.ContentType = 'application/json'; $req.Timeout = 60000; $req.ReadWriteTimeout = 600000
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
        $rd = [IO.StreamReader]::new($req.GetResponse().GetResponseStream())
        while ($null -ne ($line = $rd.ReadLine())) {
            if (-not $line.Trim()) { continue }
            $ev = $line | ConvertFrom-Json
            if ($ev.error) { $job.error = "$($ev.error)"; break }
            if ($ev.total -and $ev.completed) { $job.progress = [math]::Floor(100 * $ev.completed / $ev.total) }
            $job.text = "$($ev.status)"
        }
        $rd.Close()
    } catch { $job.status = 0; $job.error = $_.Exception.Message }
    $job.done = $true
}

function Read-JsonBody($req) {
    $body = [IO.StreamReader]::new($req.InputStream, [Text.Encoding]::UTF8).ReadToEnd()
    if ($body.Length -gt 400KB) { throw 'too big' }
    return $body | ConvertFrom-Json
}

# ---------- Anti-freeze ----------
# Watches for programs that stop responding ("Not Responding") and for memory running out, while OmniGameDesk is open
# (minimized is fine). It can only help while Windows itself still runs: a full freeze from a driver or
# hardware problem stops OmniGameDesk too.
$afFile = Join-Path $env:LOCALAPPDATA 'OmniGameDesk\antifreeze.json'
$script:af = @{ auto = $false; autoSeconds = 30 }
try {
    $saved = Get-Content $afFile -Raw -ErrorAction Stop | ConvertFrom-Json
    $script:af.auto = [bool]$saved.auto
    if ($saved.autoSeconds -in 15, 30, 60, 120) { $script:af.autoSeconds = [int]$saved.autoSeconds }
} catch {}
$script:afHung = @{}                         # process id -> @{ name; title; since; noticed }
$script:afLog = [Collections.ArrayList]::new()
$script:afMemSince = $null; $script:afMemNoticed = $false
# Never ended by OmniGameDesk: Windows itself (ending these crashes or logs you out).
$afNever = 'explorer', 'dwm', 'csrss', 'winlogon', 'wininit', 'lsass', 'services', 'smss', 'svchost', 'System', 'Idle',
    'fontdrvhost', 'LogonUI', 'sihost', 'ShellExperienceHost', 'StartMenuExperienceHost', 'SearchHost', 'TextInputHost'

function Add-AfLog([string]$text) {
    [void]$script:afLog.Insert(0, @{ at = (Get-Date).ToString('HH:mm'); text = $text })
    while ($script:afLog.Count -gt 8) { $script:afLog.RemoveAt(8) }
}
# A Windows notification, so you hear about it even while OmniGameDesk is minimized.
function Show-AfNotice([string]$text) {
    try {
        if (-not $script:afIcon) {
            Add-Type -AssemblyName System.Windows.Forms, System.Drawing
            $script:afIcon = New-Object System.Windows.Forms.NotifyIcon
            $script:afIcon.Icon = New-Object System.Drawing.Icon (Join-Path $root 'OmniGameDesk.ico')
            $script:afIcon.Text = 'OmniGameDesk Anti-Freeze'
        }
        $script:afIcon.Visible = $true
        $script:afIcon.ShowBalloonTip(8000, 'OmniGameDesk Anti-Freeze', $text, [System.Windows.Forms.ToolTipIcon]::Warning)
    } catch {}
}
function Get-AfName($p) {
    $d = try { $p.MainModule.FileVersionInfo.FileDescription } catch { $null }
    if ($d) { $d } else { $p.ProcessName }
}
function Get-AfTopMemory {
    Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $afNever -notcontains $_.ProcessName -and $_.Id -ne $PID -and $_.MainWindowTitle -notlike '*OmniGameDesk*' } |
        Sort-Object WorkingSet64 -Descending | Select-Object -First 3 |
        ForEach-Object { @{ pid = $_.Id; name = (Get-AfName $_); mb = [int]($_.WorkingSet64 / 1MB) } }
}
function Update-AntiFreeze {
    $now = Get-Date; $seen = @{}
    foreach ($p in Get-Process | Where-Object { $_.MainWindowHandle -ne 0 }) {
        if ($afNever -contains $p.ProcessName -or $p.Id -eq $PID -or $p.MainWindowTitle -like '*OmniGameDesk*') { continue }
        if (-not [GD]::IsHungAppWindow($p.MainWindowHandle)) { continue }
        $seen[$p.Id] = $true
        if (-not $script:afHung.ContainsKey($p.Id)) {
            $script:afHung[$p.Id] = @{ name = (Get-AfName $p); title = $p.MainWindowTitle; since = $now; noticed = $false }
        }
    }
    foreach ($id in @($script:afHung.Keys)) {
        if (-not $seen.ContainsKey($id)) { $script:afHung.Remove($id); continue }
        $h = $script:afHung[$id]; $secs = [int]($now - $h.since).TotalSeconds
        if ($script:af.auto -and $secs -ge $script:af.autoSeconds) {
            Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
            Add-AfLog "Ended $($h.name) automatically (not responding for $secs s)"
            Show-AfNotice "$($h.name) stopped responding, so OmniGameDesk ended it."
            $script:afHung.Remove($id)
        } elseif (-not $h.noticed -and $secs -ge 10) {
            $h.noticed = $true
            Add-AfLog "$($h.name) stopped responding"
            Show-AfNotice "$($h.name) is not responding. Open OmniGameDesk to end it."
        }
    }
    $load = ([GD]::Mem()).dwMemoryLoad
    if ($load -ge 92) {
        if (-not $script:afMemSince) { $script:afMemSince = $now }
        elseif (-not $script:afMemNoticed -and ($now - $script:afMemSince).TotalSeconds -ge 10) {
            $script:afMemNoticed = $true
            Add-AfLog "Memory almost full ($load %)"
            Show-AfNotice "Memory is almost full ($load %). Your PC may freeze. Open OmniGameDesk to close a big app."
        }
    } else { $script:afMemSince = $null; $script:afMemNoticed = $false }
}
function Get-AntiFreeze {
    $now = Get-Date
    $load = ([GD]::Mem()).dwMemoryLoad
    $memAlert = [bool]$script:afMemSince -and ($now - $script:afMemSince).TotalSeconds -ge 10
    @{
        hungSupported = $true; auto = $script:af.auto; autoSeconds = $script:af.autoSeconds
        hung = @($script:afHung.GetEnumerator() | ForEach-Object { @{ pid = $_.Key; name = $_.Value.name; title = $_.Value.title; secs = [int]($now - $_.Value.since).TotalSeconds } })
        memory = @{ pct = $load; alert = $memAlert; top = @($(if ($memAlert) { Get-AfTopMemory })) }
        log = @($script:afLog)
    }
}

# ---------- HTTP server ----------
$token = [guid]::NewGuid().ToString('N')
$port = 47821
$listener = $null
for ($try = 0; $try -lt 20; $try++) {
    try {
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://127.0.0.1:$port/")
        $listener.Start()
        break
    } catch { $listener = $null; $port++ }
}
if (-not $listener) { throw 'Could not start the OmniGameDesk server.' }

function Send($ctx, [int]$code, [string]$body, [string]$type = 'application/json; charset=utf-8') {
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $ctx.Response.StatusCode = $code
    $ctx.Response.ContentType = $type
    $ctx.Response.Headers['Cache-Control'] = 'no-store'
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
}
function SendJson($ctx, $obj) { Send $ctx 200 (ConvertTo-Json -InputObject $obj -Depth 6 -Compress) }

function Handle($ctx) {
    $req = $ctx.Request
    $path = $req.Url.AbsolutePath
    if ($req.Headers['Host'] -ne "127.0.0.1:$port") { return Send $ctx 403 'forbidden' 'text/plain' }

    if ($path -eq '/') {
        return Send $ctx 200 ([IO.File]::ReadAllText((Join-Path $root 'dashboard.html'))) 'text/html; charset=utf-8'
    }
    if ($path -eq '/logo.svg') {
        return Send $ctx 200 ([IO.File]::ReadAllText((Join-Path $root 'logo.svg'))) 'image/svg+xml'
    }
    if ($path -eq '/api/spotify/art' -and $req.QueryString['t'] -eq $token) {
        # Album cover for <img>, which cannot send the X-Token header, so it takes the token in the URL.
        if (-not $script:spArt.bytes) { return Send $ctx 404 '' 'text/plain' }
        $ctx.Response.ContentType = $script:spArt.type
        $ctx.Response.Headers['Cache-Control'] = 'max-age=3600'
        $ctx.Response.OutputStream.Write($script:spArt.bytes, 0, $script:spArt.bytes.Length)
        return $ctx.Response.Close()
    }
    if ($req.Headers['X-Token'] -ne $token) { return Send $ctx 403 '{"error":"bad token"}' }
    $q = $req.QueryString

    switch ($path) {
        '/api/stats' { return SendJson $ctx (Get-Stats) }
        '/api/ping' { return SendJson $ctx @(Get-Pings) }
        '/api/freeze' { return SendJson $ctx (Get-AntiFreeze) }
        '/api/apps' {
            return SendJson $ctx @{ apps = @($apps.Keys | Sort-Object); steam = $steamGames }
        }
        '/api/store' {
            if ($req.HttpMethod -eq 'POST') {
                $body = [IO.StreamReader]::new($req.InputStream, [Text.Encoding]::UTF8).ReadToEnd()
                if ($body.Length -gt 1MB) { return Send $ctx 413 '{"error":"too big"}' }
                [void]($body | ConvertFrom-Json)   # refuse anything that isn't valid JSON
                [IO.File]::WriteAllText($dataFile, $body, [Text.UTF8Encoding]::new($false))
                return SendJson $ctx @{ ok = $true }
            }
            $data = if (Test-Path $dataFile) { [IO.File]::ReadAllText($dataFile) } else { '{}' }
            return Send $ctx 200 $data
        }
        '/api/claude/status' { return SendJson $ctx @{ hasKey = [bool](Get-ClaudeKey); model = $claudeModel; local = (Get-LocalAiStatus) } }
        '/api/claude/poll' {
            $job = $claudeJobs[$q['id']]
            if (-not $job) { return Send $ctx 404 '{"error":"unknown chat"}' }
            $out = @{ text = $job.text; done = $job.done; error = $job.error; status = $job.status; stop = $job.stop; progress = $job.progress }
            if ($job.hwnd) { $script:spotifyHwnd = [IntPtr][long]$job.hwnd }
            if ($job.done) { try { $job.ps.EndInvoke($job.handle) } catch {}; $job.ps.Dispose(); $claudeJobs.Remove($q['id']) }
            return SendJson $ctx $out
        }
    }
    if ($req.HttpMethod -ne 'POST') { return Send $ctx 405 '{"error":"use POST"}' }
    switch ($path) {
        '/api/claude/key' {
            $key = ([string](Read-JsonBody $req).key).Trim()
            if (-not $key) {
                Remove-Item $claudeKeyFile -ErrorAction SilentlyContinue
                return SendJson $ctx @{ ok = $true }
            }
            if ($key -notmatch '^sk-ant-[A-Za-z0-9_\-]{20,}$') { return SendJson $ctx @{ ok = $false; error = 'That doesn''t look like a Claude API key (they start with sk-ant-).' } }
            $problem = Test-ClaudeKey $key
            if ($problem) { return SendJson $ctx @{ ok = $false; error = $problem } }
            New-Item -ItemType Directory -Force (Split-Path $claudeKeyFile) | Out-Null
            ConvertTo-SecureString $key -AsPlainText -Force | ConvertFrom-SecureString | Set-Content $claudeKeyFile
            return SendJson $ctx @{ ok = $true }
        }
        '/api/ai/power' {
            # The on/off switch in the AI panel.
            $script:ollamaOff = $q['on'] -ne '1'
            if ($script:ollamaOff) { Stop-Ollama -All } else { Start-Ollama }
            return SendJson $ctx @{ ok = $true }
        }
        '/api/ai/pull' {
            if ($claudeJobs.Count -ge 3) { return Send $ctx 429 '{"error":"busy"}' }
            return SendJson $ctx @{ id = (Start-BackgroundJob $pullWorker $ollamaBase (@{ model = $localModel; stream = $true } | ConvertTo-Json -Compress)) }
        }
        '/api/claude/ask' {
            $ask = Read-JsonBody $req
            $local = $ask.engine -eq 'local'
            if (-not $local -and -not (Get-ClaudeKey)) { return Send $ctx 400 '{"error":"no key"}' }
            if ($claudeJobs.Count -ge 3) { return Send $ctx 429 '{"error":"busy"}' }
            $msgs = @($ask.messages)
            if ($msgs.Count -lt 1 -or $msgs.Count -gt 60 -or $msgs[-1].role -ne 'user') { return Send $ctx 400 '{"error":"bad chat"}' }
            for ($i = 0; $i -lt $msgs.Count; $i++) {
                $want = if ($i % 2) { 'assistant' } else { 'user' }
                if ($msgs[$i].role -ne $want -or -not ($msgs[$i].content -is [string]) -or -not $msgs[$i].content.Trim()) { return Send $ctx 400 '{"error":"bad chat"}' }
            }
            return SendJson $ctx @{ id = $(if ($local) { Start-LocalJob $msgs } else { Start-ClaudeJob $msgs }) }
        }
        '/api/media' {
            $k = $q['k']
            if (-not $mediaKeys.ContainsKey($k)) { return Send $ctx 400 '{"error":"unknown key"}' }
            if ($k -in 'playpause', 'next', 'prev') { return SendJson $ctx (Invoke-SpotifyControl $k) }
            [GD]::Key([byte]$mediaKeys[$k])
            return SendJson $ctx @{ ok = $true }
        }
        '/api/launch' {
            $id = $q['id']
            if ($apps.ContainsKey($id)) {
                $appId = $apps[$id]
                if ($appId -match '^[A-Za-z]:\\' -and (Test-Path $appId)) { Start-Process $appId }
                else { Start-Process explorer.exe "shell:AppsFolder\$appId" }
                return SendJson $ctx @{ ok = $true }
            }
            return Send $ctx 404 '{"error":"unknown app"}'
        }
        '/api/tool' {
            $id = $q['id']
            if (-not $tools.ContainsKey($id)) { return Send $ctx 404 '{"error":"unknown tool"}' }
            & $tools[$id]
            return SendJson $ctx @{ ok = $true }
        }
        '/api/freeze/kill' {
            # Only a program that is frozen right now, or one of the biggest memory users during a memory alert.
            $id = 0
            if (-not [int]::TryParse($q['pid'], [ref]$id)) { return Send $ctx 400 '{"error":"bad pid"}' }
            $allowed = $script:afHung.ContainsKey($id) -or ($script:afMemSince -and @(Get-AfTopMemory | Where-Object { $_.pid -eq $id }).Count)
            if (-not $allowed) { return Send $ctx 403 '{"error":"not allowed"}' }
            $p = Get-Process -Id $id -ErrorAction SilentlyContinue
            if ($p) { $name = Get-AfName $p; Stop-Process -Id $id -Force -ErrorAction SilentlyContinue; Add-AfLog "Ended $name" }
            $script:afHung.Remove($id)
            return SendJson $ctx @{ ok = $true }
        }
        '/api/freeze/auto' {
            $script:af.auto = $q['on'] -eq '1'
            $s = 0; if ([int]::TryParse($q['secs'], [ref]$s) -and $s -in 15, 30, 60, 120) { $script:af.autoSeconds = $s }
            New-Item -ItemType Directory -Force (Split-Path $afFile) | Out-Null
            $script:af | ConvertTo-Json -Compress | Set-Content $afFile
            return SendJson $ctx @{ ok = $true }
        }
        '/api/steam' {
            $id = $q['id']
            if ($id -notmatch '^\d{1,10}$') { return Send $ctx 400 '{"error":"bad id"}' }
            Start-Process "steam://rungameid/$id"
            return SendJson $ctx @{ ok = $true }
        }
        '/api/open' {
            # Opens a web page in your normal browser. Only https links are allowed.
            $u = $q['u']
            if ($u -notmatch '^https://[^\s"]+$') { return Send $ctx 400 '{"error":"https only"}' }
            Start-Process $u
            return SendJson $ctx @{ ok = $true }
        }
    }
    Send $ctx 404 '{"error":"not found"}'
}

# ---------- Open the window ----------
try { Start-Ollama } catch {}
try { Disable-OllamaAutostart } catch {}
$url = "http://127.0.0.1:$port/?t=$token"
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
$profileDir = Join-Path $env:LOCALAPPDATA 'OmniGameDesk\browser'
$browser = $null
if ($edge) {
    $browser = Start-Process $edge -PassThru -ArgumentList @(
        "--app=$url", "--user-data-dir=`"$profileDir`"", '--window-size=1500,960',
        '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--disable-sync',
        '--disable-background-networking', '--disable-component-update', '--disable-default-apps',
        '--disable-breakpad', '--no-pings', '--renderer-process-limit=1',
        '--disable-features=Translate,msEdgeSidebarV2,msHubApps,msShoppingTrigger,EdgeCollections,msEdgeShopping,AutofillServerCommunication,MediaRouter,OptimizationHints,SpareRendererForSitePerProcess'
    )
} else {
    Start-Process $url
}

function Test-WindowOpen {
    if (-not $browser) { return $true }
    if (-not $browser.HasExited) { return $true }
    $left = Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*OmniGameDesk\browser*" }
    return [bool]$left
}

$pending = $listener.BeginGetContext($null, $null)
$lastCheck = [DateTime]::Now
try {
    while ($true) {
        if ($pending.AsyncWaitHandle.WaitOne(400)) {
            $ctx = $listener.EndGetContext($pending)
            try { Handle $ctx } catch { try { Send $ctx 500 (ConvertTo-Json @{ error = "$_" } -Compress) } catch {} }
            $pending = $listener.BeginGetContext($null, $null)
        }
        if (([DateTime]::Now - $lastCheck).TotalSeconds -ge 3) {
            $lastCheck = [DateTime]::Now
            if (-not (Test-WindowOpen)) { break }
            try { Update-AntiFreeze } catch {}
        }
    }
} finally {
    # Never leave Spotify playing invisibly after OmniGameDesk closes: put it back on the taskbar (minimized).
    try { Show-Spotify -Minimized } catch {}
    try { Stop-Ollama } catch {}
    if ($script:afIcon) { $script:afIcon.Dispose() }
    $listener.Stop()
}
