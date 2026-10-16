<p align="center"><img src="GameDesk/logo.png" width="140" alt="GameDesk logo"></p>

<h1 align="center">GameDesk</h1>

<p align="center">
  <b>All your everyday and gaming widgets in one window.</b><br>
  A free widget dashboard for Windows 10 and 11.
</p>

<p align="center">
  <a href="https://github.com/CillX1/GameDesk/releases/latest"><img src="https://img.shields.io/github/v/release/CillX1/GameDesk?label=download&style=for-the-badge&color=6d28d9" alt="Download latest release"></a>
  <a href="https://github.com/CillX1/GameDesk/releases"><img src="https://img.shields.io/github/downloads/CillX1/GameDesk/total?style=for-the-badge" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=for-the-badge" alt="Windows 10 and 11">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/CillX1/GameDesk?style=for-the-badge" alt="License"></a>
</p>

<h3 align="center"><a href="https://github.com/CillX1/GameDesk/releases/latest">⬇ Download GameDesk for Windows</a></h3>

## Features

| | |
|---|---|
| 🎵 **Spotify** | Play, pause and skip with album art. Press play and Spotify starts hidden in the background. |
| 🤖 **AI chat** | A free AI that runs on your own PC (Ollama), or Claude with your own API key. |
| 📊 **PC stats** | CPU, RAM, disk, battery and ping at a glance. |
| 🎮 **Games** | Launch Steam, Xbox, Ubisoft, Epic, EA, Battle.net and more, plus your installed Steam games. |
| 🛠️ **Quick tools** | Windows shortcuts, weather, to-do list, timer and notes. |
| 🔗 **Quick links** | Your favourite websites one click away. Add or remove them with **Edit links**. |
| 🎨 **Customize** | Hide the widgets you don't need. |

## Install

1. Go to the [latest release](https://github.com/CillX1/GameDesk/releases/latest) and download `GameDesk-Setup-<version>.exe`.
2. Run it. It installs for your user only, so no admin rights are needed.
   The installer isn't code-signed, so Windows may say *"Windows protected your PC"*: click **More info**, then **Run anyway**.
3. GameDesk starts. Next time, open it from the Start menu or the desktop shortcut.

**Without the installer:** download `GameDesk-<version>.zip` from the same release, right-click it, choose **Extract All**, then double-click `Install GameDesk.bat`.

**Uninstall:** Settings > Apps > Installed apps > GameDesk > Uninstall. This also removes your saved widgets, notes and Claude key.

### Requirements

Windows 10 or 11 with Microsoft Edge (installed by default). Nothing else.

## AI chat

- **Free local AI:** install [Ollama](https://ollama.com/download), then in GameDesk's AI panel pick *Local AI* and click *Download (3.3 GB)*. It runs on your own PC and works offline; 16 GB of RAM or more is recommended.
- **Claude (optional):** pick *Claude* and paste an API key from [console.anthropic.com](https://console.anthropic.com) (Settings > API keys). API use is billed separately from a Claude Pro plan. The key is stored encrypted on your PC only (`%LOCALAPPDATA%\GameDesk\claude.key`).

## Privacy

GameDesk runs a small server on your own PC (`127.0.0.1` only) and opens the dashboard in an Edge app window. It doesn't send your data anywhere. Weather comes from open-meteo.com and Steam game pictures from Steam. Claude chat messages go to Anthropic's API only when you send them.

## Building from source

The app is plain PowerShell (`GameDesk/GameDesk.ps1`) plus one HTML page (`GameDesk/dashboard.html`); there's nothing to compile. To run it straight from the repo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File GameDesk\GameDesk.ps1
```

To build the installer, install [Inno Setup 6](https://jrsoftware.org/isinfo.php) and run:

```powershell
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" installer\GameDesk.iss
```

The installer lands in `installer\Output\`.

### Releasing

Bump `$version` in `GameDesk/Install.ps1`, then push a tag:

```powershell
git tag v1.5.0
git push origin v1.5.0
```

GitHub Actions ([`.github/workflows/release.yml`](.github/workflows/release.yml)) builds the installer and the zip and attaches both to a new GitHub release.

## License

GameDesk is free software under the [GNU GPL v3](LICENSE).
