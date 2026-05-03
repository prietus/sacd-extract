# SACDRipper

A native macOS app for ripping SACDs from a networked PS3 or Sony Blu-ray
player (anything speaking the `sacd-ripper` protocol on TCP port 2002) to
ISO, DSF or DSDIFF.

Marketing site & downloads: **https://sacdripper.priet.us**

## What it does

- Auto-discovers the player on your LAN by parallel-probing port 2002.
- Drives `sacd_extract` (EuFlo's fork) under the hood — multichannel /
  stereo, DSF or DSDIFF or ISO, with concurrent ISO + DSF rips.
- Repairs corrupted ISOs (the "Fix ISO" mode patches DST frame headers in
  place).
- Live progress that doesn't freeze, native SwiftUI, signed + notarized.

## Requirements

- macOS 13 (Ventura) or newer, Apple Silicon
- Xcode 15+ if building from source
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building from source

```sh
git clone https://github.com/prietus/sacd-extract.git
cd sacd-extract

# Fetches the vendored sacd_extract binary into SACDRipper/Resources/.
./scripts/bootstrap.sh

cd SACDRipper
xcodegen generate
open SACDRipper.xcodeproj
```

Then ⌘R in Xcode.

## Cutting a release

`SACDRipper/release.sh` produces a Developer-ID-signed, notarized,
stapled `.app` and (optionally) publishes the zip and marketing site:

```sh
cd SACDRipper
./release.sh 0.1.0                          # full pipeline
NOTARIZE=0 ./release.sh 0.1.0               # skip notarization (dev only)
PUBLISH=0  ./release.sh 0.1.0               # notarize but don't upload
```

The script calls `scripts/bootstrap.sh` automatically before building, so
the vendored binary is always present and verified.

Pre-requisites for a real release:
- `notarytool-profile` keychain item (one-time:
  `xcrun notarytool store-credentials notarytool-profile --apple-id ... --team-id LFTD9T269J`)
- SSH access to the host that serves `sacdripper.priet.us`

## Project layout

```
.
├── SACDRipper/
│   ├── project.yml              # xcodegen spec
│   ├── Sources/                 # Swift sources (MIT)
│   │   ├── RipController.swift
│   │   ├── NetworkScanner.swift
│   │   ├── RipView.swift
│   │   └── ...
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   └── sacd_extract         # ← fetched by bootstrap, gitignored
│   └── release.sh
├── scripts/
│   └── bootstrap.sh             # downloads + verifies sacd_extract
├── THIRD_PARTY/
│   └── sacd_extract/            # provenance + GPL-3 license for the binary
├── LICENSE                      # MIT (Swift sources)
└── README.md
```

## Licensing

- **SACDRipper Swift sources** (`SACDRipper/`): MIT — see [LICENSE](LICENSE).
- **Bundled `sacd_extract` binary**: GPL-3.0 — see
  [THIRD_PARTY/sacd_extract/](THIRD_PARTY/sacd_extract/) for the license
  text, upstream source URL and pinned version. SACDRipper calls
  `sacd_extract` as a child process; there is no linking.

## Legal

Rip the discs you already own. SACDRipper does not bypass DRM that you do
not have authorization to bypass; SACD's DST encryption and copy-control
flags are handled by `sacd_extract` against players that have already
unlocked the disc.
