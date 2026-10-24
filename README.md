<p align="center"><img src="docs/img/icon.png" width="128" alt="Plugd icon"></p>

<h1 align="center">Plugd</h1>

<p align="center">FORScan on a Mac, for free.</p>

<p align="center"><a href="https://github.com/lncch/Plugd/releases/latest/download/Plugd.dmg"><b>Download for Mac</b></a> · macOS 14+ · Apple Silicon or Intel · USB or Bluetooth OBD adapter</p>

<p align="center"><img src="docs/img/setup.png" width="420" alt="Setup screen"> <img src="docs/img/main.png" width="420" alt="Main screen"></p>

I have a Ford Taurus, and every time I wanted to turn a feature on or off with FORScan I had to dig out a Windows laptop. FORScan is Windows only. The usual ways around that on a Mac cost money: CrossOver, or Parallels or downloading a whole VM.

So I made this app. It runs FORScan on my Mac through Wine (free software that runs Windows programs), and it does the annoying setup for you. You click Set Up, plug in your adapter, and click Open FORScan.

I've used it on my own car and it works.

If you like it, give it a ⭐. It helps other Ford owners find it.

## What it does

- Installs Wine and downloads FORScan from forscan.org (it doesn't ship FORScan itself)
- Finds your USB OBD adapter, or a paired Bluetooth one, and connects FORScan to it
- Gives FORScan a folder on your Mac (it shows up as drive O:) for license keys and As-Built backups
- Warns you when you don't have a backup yet
- Reads engine codes and battery voltage without opening FORScan
- Shows a live dashboard (RPM, speed, temperatures, fuel and more) while FORScan is closed
- Lives in the menu bar if you want, and can start at login
- Tells you when a new FORScan version is out, and when your license runs out

## Install

1. [Download Plugd.dmg](https://github.com/lncch/Plugd/releases/latest/download/Plugd.dmg), open it, and drag Plugd into Applications.
2. Open it. Plugd is notarized by Apple, so it opens like any other app.
3. Click **Set Up** and accept FORScan's license. It takes about 2 minutes and downloads about 230 MB.
4. Plug in your adapter and click **Open FORScan**.

Back up before you change anything, and keep a battery charger on the car while FORScan writes.

## Tested on

| Car | Adapter | Reads | Writes | Dashboard and codes |
|---|---|---|---|---|
| 2023 Ford Taurus, Middle East (Mondeo EVOS, 2021 MY) | cheap ELM327 v1.5 clone, CH340 chip, HS/MS switch | 22+ modules | yes, checked in the car | yes, v0.3.3 |

That's one car and one adapter. Intel Macs are new: setup is tested on a real Intel Mac (GitHub's Intel runner), but nobody has tried it with an adapter and a car yet. If you try it on yours, open an issue and tell me how it went.

Bluetooth adapters are new in 0.3.5 and nobody has tested one yet. Pair it in System Settings first. Bluetooth Classic adapters like the OBDLink MX+ can work. Bluetooth LE only ones can't, because macOS gives them no serial port. If you have one, please try it and open an issue.

## Credits

FORScan is made by Alexey Savin (forscan.org). I'm not connected to FORScan or Ford. Plugd's code is MIT licensed. FORScan, Wine and innoextract keep their own licenses (see `THIRD_PARTY.md`).

## Contact

Questions or feedback: plugd@almoayyad.dev, or open an issue.

More projects coming. Follow me on [GitHub](https://github.com/lncch) or [X (@1lnch)](https://x.com/1lnch).
