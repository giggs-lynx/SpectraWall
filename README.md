# SpectraWall

Audio-reactive desktop visualizer for macOS that paints your desktop wallpaper with real-time sound.

## Overview

SpectraWall captures system audio (per-app or global) and renders dynamic visual effects directly on your desktop wallpaper. It supports multiple effects — spectrum bars, pulsing orbs, and glowing border trails — all driven by live audio analysis via Core Audio.

## Features

- **System-Wide & Per-App Audio Capture** — tap into any app's audio or the entire system output
- **Three Visual Effects**:
  - **Spectrum** — frequency bars with channel separation
  - **Orb** — pulsing circle that reacts to amplitude
  - **Border** — Metal-accelerated glowing border trail with neon glow shader, beat-reactive pulse echo
- **Multi-Display Support** — automatically spans all connected monitors
- **Scene/Layer Architecture** — stack multiple effects with independent settings
- **Menu Bar App** — runs in the menu bar with popover settings window
- **Launch at Login** — optional auto-start

## Requirements

- macOS 14.2+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Installation

```bash
git clone https://github.com/giggs-lynx/SpectraWall.git
cd SpectraWall
make project
open SpectraWall.xcodeproj
```

Build and run from Xcode (⌘R).

## Usage

1. Click the waveform icon in the menu bar
2. Choose an audio source (System or specific app)
3. Configure your scenes, layers, and effects in Settings
4. Effects render live on your desktop wallpaper

## Architecture

```
SpectraWall/
├── App/            # App entry, AppDelegate, desktop window setup
├── Audio/          # Core Audio tap, FFT analyzer, process monitor
├── Model/          # Configuration models (settings structs)
├── UI/             # SwiftUI settings views
│   ├── Components/ # Reusable UI components
│   └── Effects/    # Per-effect settings sections
├── Visualizer/     # SpriteKit scene and layer management
│   └── Effects/    # Spectrum, Orb, Border effects
└── Metal/          # Metal shader, trail renderer, renderer registry
```

## License

MIT — see [LICENSE](LICENSE) for details.
