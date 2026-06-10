# SpectraWall

[![build](https://github.com/giggs-lynx/SpectraWall/actions/workflows/build.yml/badge.svg)](https://github.com/giggs-lynx/SpectraWall/actions/workflows/build.yml)
[![release](https://img.shields.io/github/v/release/giggs-lynx/SpectraWall)](https://github.com/giggs-lynx/SpectraWall/releases)
![platform](https://img.shields.io/badge/platform-macOS%2014.4%2B-lightgrey)
[![license](https://img.shields.io/github/license/giggs-lynx/SpectraWall)](LICENSE)

Audio-reactive desktop wallpaper for macOS. Live system audio drives Metal-rendered effects painted directly onto every connected display.

## Features

- **Three Metal effects** — `Spectrum` (96-bin chromatic FFT bars), `Orb` (amplitude-driven pulsing disc with glow), `Border` (vsync-driven trail with quintic-Bézier corners and beat-reactive echo).
- **System audio without a microphone** — taps the Core Audio output bus via [`CATapDescription`](https://developer.apple.com/documentation/coreaudio/catapdescription) (macOS 14.4+ Process Tap API). Choose between global system audio or any single running app.
- **Per-screen renderer** — each display owns its own `CAMetalDisplayLink` on a dedicated thread, so dual-screen ProMotion + 60Hz setups don't fight each other for the main runloop.
- **Scene / layer model** — stack any combination of effects, save scene presets, switch live from the menu bar.
- **Plugin-friendly architecture** — adding a fourth effect type touches one new file plus a single `EffectRegistry.register(...)` line. The renderer, coordinator, Codable layer, and UI dispatch all read from the registry.
- **Always-on perf instrumentation** — `RenderMetrics` emits a per-renderer heartbeat (fps / avg / max / cb-gap) at info-level OSLog, free unless you `log show` for it.
- Menu bar app (LSUIElement), optional launch-at-login, runs at `desktopWindow` level so other windows sit on top.

## Requirements

- macOS **14.4+** (Core Audio Process Tap API)
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen` — for generating `SpectraWall.xcodeproj` from `project.yml`

## Install

### Homebrew (recommended)

```bash
brew tap giggs-lynx/tap
brew install --cask spectrawall
```

The binary is unsigned. First launch goes through **System Settings → Privacy & Security → "Open Anyway"**.

### Build from source

```bash
git clone https://github.com/giggs-lynx/SpectraWall.git
cd SpectraWall
make project
open SpectraWall.xcodeproj
```

Build and run in Xcode (⌘R). Debug builds re-prompt the audio-tap permission every time the binary is recompiled (unsigned cdhash changes); Release builds keep the grant once given.

## Usage

1. Click the SpectraWall icon in the menu bar.
2. Pick an audio source — **System** (all output) or a specific running app.
3. Open **Settings…** to manage scenes, add/remove layers, tune per-effect parameters and colours.
4. Toggle per-display visibility under **General → Displays**.

Settings live in [XDG Base Directory](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) locations:

| Path | Purpose |
|---|---|
| `~/.config/spectrawall/config.json` | Global prefs (active scene, enabled display IDs, motion style, scene order) |
| `~/.config/spectrawall/scenes/scene-<uuid>.json` | One file per scene |
| `~/.local/state/spectrawall/state.json` | First-launch sentinel |

## Architecture

```
Audio path:
  CATapDescription tap (Core Audio)
   → Aggregate device + IO proc
   → handleAudioBuffer (interleaved L/R samples)
   → AudioAnalyzer (Accelerate vDSP FFT, 96 chromatic bins)
   → AudioDataBus (Combine PassthroughSubject<StereoBins>)
   → each effect's onAudio(_) on its renderer queue

Render path:
  CAMetalDisplayLink (per renderer, dedicated thread + runloop)
   → renderQueue.sync { renderer.draw(...) }
   → tick all frame clients (effect.onTick)
   → submit meshes per EffectType
   → encode pipelines grouped by type (back-to-front by renderOrder)

Plugin model:
  EffectRegistry.bootstrap() lazily on first access
   → register({Spectrum,Orb,Border}Effect.descriptor)
  EffectDescriptor knows:
   - displayName / iconAssetName / renderOrder
   - makeDefaultSettings / settingsCodec (Codable round-trip)
   - makeEffect (factory) / makeSettingsView (SwiftUI)
   - pipelineSpec (shader names + blend mode)
```

### Adding a new effect

1. Add a static member to `EffectType` (e.g. `static let ripple = EffectType(rawValue: "Ripple")`). The rawValue is the on-disk key.
2. Define an `EffectSettings`-conforming struct for its persistent parameters.
3. Write a SwiftUI settings section view for it.
4. Subclass `BaseEffect`, implement `onTick(_:)` / `onAudio(_:)` and any setting-change hooks.
5. Add shader functions to `Effects.metal` (or reuse existing ones).
6. Expose a `static let descriptor: EffectDescriptor` and append one `register(...)` call inside `EffectRegistry._bootstrapped`.

That's the whole surface — coordinator, renderer, `LayerSettings` Codable, popover menu and Settings panel all pick it up.

### Source layout

```
SpectraWall/
├── App/             AppDelegate, App entry, AppLog, AppConstants
├── Audio/           Core Audio tap + process monitor + Accelerate FFT + Combine bus
├── Metal/           EffectRenderer + EffectRendererRegistry + EffectsHostView
│                    + RenderMetrics + Effects.metal (shaders)
├── Model/           AppConfig / AppState / AppSettings / SceneSettings / LayerSettings
│                    + per-effect *Settings structs + ColorData + XDGStorage
├── Visualizer/      EffectsCoordinator + VisualizerSceneManager
│   └── Effects/     Effect protocol + BaseEffect + EffectType +
│                    EffectDescriptor + EffectRegistry + EffectSettingsCodec
│                    + {Spectrum,Orb,Border}Effect + BorderEffectGeometry
└── UI/              SwiftUI Settings panel + popover + reusable components
```

## Performance monitoring

`RenderMetrics` is always-on, zero-cost when no subscriber is attached:

```bash
log show --predicate 'subsystem == "com.spectrawall.app" AND category == "Render"' \
  --info --last 5m
```

Each renderer emits a heartbeat every ~2s:

```
[perf] display=2 fps=60.0 avg=1.7ms max=4.4ms slow8ms=0% (0/120)
       cb-gap-avg=16.66ms cb-gap-max=22.4ms
```

- `fps` / `avg` / `max` — frame timing on `renderQueue`
- `slow8ms` — fraction over the ProMotion budget
- `cb-gap-*` — interval between `CAMetalDisplayLink` callbacks (vsync delivery health)

## Releasing

```bash
make release 0.0.x
```

Verifies the working tree is clean and HEAD matches the pushed `origin/main`, then signs and pushes the `v0.0.x` tag. GitHub Actions takes it from there:
1. `make dist VERSION=0.0.x` — Release build, zip, sha256
2. Creates a GitHub Release with the zip attached
3. Updates `giggs-lynx/homebrew-tap`'s `Casks/spectrawall.rb` so `brew upgrade --cask spectrawall` picks it up

## License

MIT — see [LICENSE](LICENSE).
