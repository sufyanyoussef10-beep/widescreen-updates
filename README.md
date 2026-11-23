# Widescreen

Media output for LED screens, projectors and monitors: videos, pictures, sound, slides, cameras and websites.

## Download

| Your computer | Download |
|---|---|
| Windows | [Widescreen.zip](https://github.com/sufyanyoussef10-beep/widescreen-updates/releases/latest/download/Widescreen.zip) |
| Mac (Apple or Intel chip) | [Widescreen-mac.dmg](https://github.com/sufyanyoussef10-beep/widescreen-updates/releases/latest/download/Widescreen-mac.dmg) |

Both links always give the newest version.

### Windows

1. Unzip the file anywhere (for example into `Documents`; not into Program Files).
2. Open the folder and double-click **Widescreen.exe**.
   The first time, Windows may show a blue box "Windows protected your PC", because the app is not registered with Microsoft: press **More info**, then **Run anyway**.

### Mac

1. Open the `.dmg` file.
2. Drag **Widescreen** onto the **Applications** folder (a newer version: choose **Replace**).
3. Open **Applications** and double-click **Widescreen**.
   The first time after every download: the app is not registered with Apple, so macOS asks before it opens it. Press **Done**, open **System Settings > Privacy & Security**, scroll down and press **Open Anyway**.
   On macOS 13 and 14: hold **Control** and click Widescreen, choose **Open**, then **Open** again.

The Mac version needs macOS 13 or newer. Every build is started and checked on a Mac before it is put here, but it has not been used in a show yet. PowerPoint files cannot be added on a Mac (export them as PDF).

## Updates

**Windows:** you install it once. When there is a new version, a green **Update** button appears at the right of the menu bar: press it, read what is new, and press **Update and restart**.

**Mac:** no update button yet. A new version is a new download from this page.

## What is here

- `Widescreen.zip`: the whole Windows app, for a first install.
- `Widescreen-app.zip` and `latest.json`: what a running Windows copy downloads when it updates, and the list (version, what is new, sizes and SHA-256 fingerprints) it checks its download against.
- `Widescreen-mac.dmg`: the Mac app for both kinds of Mac. It is made on one of GitHub's Mac machines by the recipe in `.github/workflows/mac.yml`, which first starts the app there and checks that it plays (`check/mac-check.mjs`). The pre-release `mac-test-1` holds the two files that disk image is made from; nobody needs to download them.

Only the finished app is here.

The downloads include [FFmpeg](https://ffmpeg.org), which Widescreen runs as a separate program to convert media. FFmpeg is free software under the GNU General Public License version 3. The Windows build comes unchanged from <https://github.com/yt-dlp/FFmpeg-Builds>, the Mac build from <https://github.com/jellyfin/jellyfin-ffmpeg>; the source code is at <https://github.com/FFmpeg/FFmpeg>.
