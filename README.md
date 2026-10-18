<p align="center"><img src="docs/img/icon.png" width="128" alt="OBDock icon"></p>

<h1 align="center">OBDock</h1>

<p align="center">Run FORScan (Ford/Mazda diagnostics, Windows only) on an Apple Silicon Mac.<br>Free, no Windows, no virtual machine.</p>

<p align="center"><a href="https://github.com/lncch/OBDock/releases/latest/download/OBDock.zip"><b>Download for Mac</b></a> · macOS 14+ · Apple Silicon · USB OBD adapter</p>

<p align="center"><img src="docs/img/setup.png" width="420" alt="Setup screen"> <img src="docs/img/main.png" width="420" alt="Main screen"></p>

OBDock sets up Wine, downloads FORScan from forscan.org, maps your USB OBD adapter to COM1, and opens FORScan with one button.

## Install

1. Download `OBDock.zip`, unzip it, and move OBDock to Applications.
2. Open it. macOS blocks it the first time because it isn't notarized yet: open System Settings → Privacy & Security and click **Open Anyway**.
3. Click **Set Up** and accept FORScan's license (about 2 minutes, ~230 MB download).
4. Plug in your adapter and click **Open FORScan**.
5. To give FORScan a file (license key, As-Built backup, profile), drop it on OBDock's **Files** box. FORScan sees it on drive **O:**. Files FORScan saves to O: show up in `Documents/OBDock`.

## Tested

| Car | Adapter | Reads | Writes (As-Built) |
|---|---|---|---|
| 2023 Ford Taurus, Middle East (Mondeo EVOS, 2021 MY) | ELM327 v1.5 clone, CH340, manual HS/MS switch | 22+ modules | yes, features added and confirmed in the car |

## Build

Needs the Xcode command line tools, `brew install innoextract dylibbundler`.

    ./build.sh

## Test hooks

    OBDOCK_HOME=/tmp/empty OBDock.app/Contents/MacOS/OBDock --headless-setup
    OBDOCK_HOME=/tmp/empty OBDOCK_PORT=/dev/ttys008 OBDock.app/Contents/MacOS/OBDock --headless-open

`OBDOCK_PORT` points at a fake adapter such as ELM327-emulator's pseudo-terminal.

## Why not the official installer?

FORScan's Inno Setup installer crashes under Wine 11 (access violation in kernel32 under WoW64, tested on Wine stable 11.0, devel 11.18, staging 11.18). OBDock tries it first. If it fails, it unpacks the same installer on your Mac with innoextract and copies its files unchanged.

FORScan is made by Alexey Savin. OBDock is not affiliated with FORScan or Ford.

## License

OBDock's code is MIT licensed (see `LICENSE`). FORScan, Wine and innoextract keep their own licenses (see `THIRD_PARTY.md`).
