# Building Plugd

You don't need this to use Plugd. Just [download it](https://github.com/lncch/Plugd/releases/latest/download/Plugd.dmg). This page is for people who want to change the code.

You need the Xcode command line tools and `brew install innoextract dylibbundler`. The first build also runs `tools/innoextract-x86.sh`, which fetches the Intel half of innoextract (hash-checked). Then:

    ./build.sh

There are test hooks that run without a window, for example with a fake adapter from ELM327-emulator:

    PLUGD_HOME=/tmp/empty Plugd.app/Contents/MacOS/Plugd --headless-setup
    PLUGD_HOME=/tmp/empty PLUGD_PORT=/dev/ttys008 Plugd.app/Contents/MacOS/Plugd --headless-open
    PLUGD_PORT=/dev/ttys008 Plugd.app/Contents/MacOS/Plugd --headless-adapter
    PLUGD_HOME=/tmp/empty Plugd.app/Contents/MacOS/Plugd --headless-update
    PLUGD_HOME=/tmp/empty Plugd.app/Contents/MacOS/Plugd --headless-report
    Plugd.app/Contents/MacOS/Plugd --self-test

FORScan's own installer crashes under Wine 11, so Plugd tries it first. If it fails, Plugd unpacks the same installer with innoextract and copies the files over unchanged.
