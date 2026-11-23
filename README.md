# Widescreen

Media output for LED screens, projectors and monitors: videos, pictures, sound, slides, cameras and websites.

## Download

| Your computer | Download |
|---|---|
| Windows | [Widescreen.zip](https://github.com/sufyanyoussef10-beep/widescreen-updates/releases/latest/download/Widescreen.zip) |
| Mac with an Apple chip (M1, M2, M3, M4) | [Widescreen-Mac-Apple-chip.zip](https://github.com/sufyanyoussef10-beep/widescreen-updates/releases/download/mac-test-1/Widescreen-Mac-Apple-chip.zip) (first test build) |
| Mac with an Intel processor | [Widescreen-Mac-Intel.zip](https://github.com/sufyanyoussef10-beep/widescreen-updates/releases/download/mac-test-1/Widescreen-Mac-Intel.zip) (first test build) |

Not sure which Mac? Apple menu > **About This Mac**: it says "Chip: Apple M..." or "Processor: Intel...".

### Windows

1. Unzip the file anywhere (for example into `Documents`; not into Program Files).
2. Open the folder and double-click **Widescreen.exe**.
   The first time, Windows may show a blue box "Windows protected your PC", because the app is not registered with Microsoft: press **More info**, then **Run anyway**.

### Mac

1. Open the downloaded zip: **Widescreen** appears. Drag it into **Applications**.
2. Double-click **Widescreen**.
   The first time only: the app is not registered with Apple, so macOS asks before it opens it. Press **Done**, open **System Settings > Privacy & Security**, scroll down and press **Open Anyway**.
   On macOS 13 and 14: hold **Control** and click Widescreen, choose **Open**, then **Open** again.

The Mac version is new and still being tested. It needs macOS 13 or newer. PowerPoint files cannot be added on a Mac (export them as PDF).

## Updates

**Windows:** you install it once. When there is a new version, a green **Update** button appears at the right of the menu bar: press it, read what is new, and press **Update and restart**.

**Mac:** no automatic updates yet. A new build is a new download from this page.

## What is in a release

- `Widescreen.zip`: the whole Windows app, for a first install.
- `Widescreen-app.zip`: the Windows app without ffmpeg, a few megabytes. This is what a running copy downloads when it updates.
- `latest.json`: the version, what is new, and the size and SHA-256 fingerprint of both zips. A copy checks its download against it before it installs anything.

Only the finished app is here.

The downloads include [FFmpeg](https://ffmpeg.org), which Widescreen runs as a separate program to convert media. FFmpeg is free software under the GNU General Public License version 3. The Windows build comes unchanged from <https://github.com/yt-dlp/FFmpeg-Builds>, the Mac build from <https://github.com/jellyfin/jellyfin-ffmpeg>; the source code is at <https://github.com/FFmpeg/FFmpeg>.
