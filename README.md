# Fade Out

**Fade out the noise.**

Fade Out is a small, native macOS menu bar mixer. Lower one app without changing the others, mute a noisy call, and keep your preferred levels when those apps play again. There is no audio driver, extension, account, or dependency to install.

> Screenshots: menu bar mixer and permission flow coming with the first release.

## Features

- Master and per-app volume controls for launched apps; saved levels take effect when they play audio
- One-click mute, app icons, and a selectable output device
- Saved levels by bundle ID and optional launch at login
- Keyboard and VoiceOver labels, light and dark appearance
- No tap at 100% volume when master and app levels are both unchanged

Requires **macOS 14.2 or later**. Fade Out currently supports output formats that Core Audio exposes as 32-bit floating-point PCM with matching tap and output channel counts and sample rates. Some devices or protected audio may be unavailable.

## Install

### Build from source

Open `FadeOut.xcodeproj` itself in Xcode 16 or later, select the `FadeOut App` scheme, and Run. Do not open `Package.swift`; that file contains only the reusable audio core and test harness. For a command-line build:

```sh
xcodebuild -project FadeOut.xcodeproj -scheme "FadeOut App" -configuration Release \
  CODE_SIGNING_ALLOWED=NO build
```

The reusable audio engine is also a Swift package: `swift build` and `swift test` from this directory. The macOS app itself runs from `FadeOut.xcodeproj`. The tests use Swift Testing (Xcode 16+). `swift run FadeOutHarness` checks the DSP path, settings, and app grouping without requesting capture permission. `sh scripts/test_dsp.sh` checks planar/interleaved buffer routing.

### Releases

Download `FadeOut.app.zip` from this repository's Releases page when the first signed release is published. The release workflow also makes an unsigned universal build artifact for maintainers. Homebrew cask `fade-out` is planned and is not available yet.

An unsigned universal macOS DMG is provided with the GitHub release. The app is not signed or notarized, so macOS may require explicit approval to open it; it should not be presented as a signed public release.

## How it works

Core Audio reports processes that are actively running output. When you lower one, Fade Out creates a private process tap, places it in an aggregate device with your chosen output, and applies a smooth gain ramp in a C audio callback. The original process output is suppressed only while the tap is being read. Restoring a row and the master to 100% tears the tap down. The app uses HAL property listeners, not a polling loop.

The first adjustment triggers macOS's **System Audio Recording** permission request. Fade Out shows an explanation first. This permission is needed to capture and replay sound from adjusted apps; audio is processed on your Mac and is not recorded to a file or sent anywhere.

## FAQ

**Why is an app missing?** It appears when Core Audio reports active output. Start playback, then check the menu again. Some protected or unusual audio paths may not be tappable.

**Why did an adjustment fail?** Check System Settings → Privacy & Security → Screen & System Audio Recording and allow Fade Out. Quit and reopen after changing permission. A device whose format cannot be safely copied into the aggregate output is rejected with an error in the menu.

**Why does changing the output picker affect only adjusted apps?** At 100%, an app stays on its normal system route. Fade Out routes only sound passing through an active tap.

**What happens when headphones disconnect or the Mac sleeps?** The app listens for device changes and rebuilds active taps; it stops taps on sleep and recreates them after wake. If a device disappears, it falls back to the current default output.

## Contribute

See [CONTRIBUTING.md](CONTRIBUTING.md), [the architecture notes](docs/ARCHITECTURE.md), and [distribution notes](docs/DISTRIBUTION.md). The project is MIT licensed.

Made by Howl Dev
