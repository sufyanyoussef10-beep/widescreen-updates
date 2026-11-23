# Widescreen updates

New versions of Widescreen, the media-output app for LED screens, projectors and monitors (Windows 10 / 11).

Widescreen 1.9.5 and later look here by themselves. When a new version is out, a green **Update** button appears at the right of the menu bar: click it, read what is new, and press **Update and restart**. That is all.

## First install

1. Download **[Widescreen.zip](https://github.com/sufyanyoussef10-beep/widescreen-updates/releases/latest/download/Widescreen.zip)**.
2. Right-click the downloaded zip > **Extract All** > **Extract**. Put the folder on the Desktop, in Documents or on another disk (not in Program Files).
3. In the folder that opens, double-click **Widescreen.exe**.
   If Windows says "Windows protected your PC": click **More info** > **Run anyway**.

Nothing else has to be installed: Widescreen uses what Windows 10 and 11 already have.

## What is in a release

- `Widescreen.zip`: the whole app, for a first install.
- `Widescreen-app.zip`: the app without ffmpeg, a few megabytes. This is what a running copy downloads when it updates.
- `latest.json`: the version, what is new, and the size and SHA-256 fingerprint of both zips. A copy checks its download against it before it installs anything.

Only the finished app is here.

`Widescreen.zip` includes [FFmpeg](https://ffmpeg.org) (`tools\ffmpeg.exe`), which Widescreen runs as a separate program to convert media. FFmpeg is free software under the GNU General Public License version 3; this build comes unchanged from <https://github.com/yt-dlp/FFmpeg-Builds> and its source code is at <https://github.com/FFmpeg/FFmpeg>.
