# Third-party software

Plugd downloads or bundles these. It ships none of FORScan's files.

| Software | How it is used | License |
|---|---|---|
| FORScan (Alexey Savin) | Downloaded by the user from forscan.org; license shown and accepted in the app | FORScan EULA |
| Wine (Gcenx macOS builds) | Downloaded at setup from github.com/Gcenx/macOS_Wine_builds | LGPL 2.1+ |
| innoextract 1.9 | Bundled, unpacks the official FORScan installer on the user's Mac; built from source by tools/innoextract.sh | zlib |
| Boost 1.92 | Linked into innoextract | Boost Software License 1.0 |
| xz / liblzma 5.8.4 | Linked into innoextract | 0BSD |
| Sparkle 2.10.0 (sparkle-project.org) | Bundled, updates Plugd itself; full notice in Sparkle-LICENSE.txt next to this file | MIT, plus the notices in that file |
