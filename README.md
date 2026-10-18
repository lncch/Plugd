# ScanBridge

Run FORScan (Ford/Mazda diagnostics, Windows only) on an Apple Silicon Mac. Free, no Windows, no virtual machine.

ScanBridge sets up Wine, downloads FORScan from forscan.org, maps your USB OBD adapter to COM1, and opens FORScan with one button.

## Tested

| Car | Adapter | Reads | Writes (As-Built) |
|---|---|---|---|
| 2023 Ford Taurus, Middle East (Mondeo EVOS, 2021 MY) | ELM327 v1.5 clone, CH340, manual HS/MS switch | 22+ modules | yes, features added and confirmed in the car |

## Build

Needs the Xcode command line tools, `brew install innoextract dylibbundler`.

    ./build.sh

## Test hooks

    SCANBRIDGE_HOME=/tmp/empty ScanBridge.app/Contents/MacOS/ScanBridge --headless-setup
    SCANBRIDGE_HOME=/tmp/empty SCANBRIDGE_PORT=/dev/ttys008 ScanBridge.app/Contents/MacOS/ScanBridge --headless-open

`SCANBRIDGE_PORT` points at a fake adapter such as ELM327-emulator's pseudo-terminal.

## Why not the official installer?

FORScan's Inno Setup installer crashes under Wine 11 (access violation in kernel32 under WoW64, tested on Wine stable 11.0, devel 11.18, staging 11.18). ScanBridge tries it first. If it fails, it unpacks the same installer on your Mac with innoextract and copies its files unchanged.

FORScan is made by Alexey Savin. ScanBridge is not affiliated with FORScan or Ford.
