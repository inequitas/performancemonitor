# Performance Monitor

A lightweight macOS menu bar app that gives you real-time system metrics at a glance — CPU, memory, network, disk, GPU, battery, and Bluetooth, all in a clean popover interface.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.10-orange) ![Version](https://img.shields.io/badge/version-0.3.13-lightgrey)

---

## Requirements

- **Apple Silicon (M1 or later)** — this build is arm64-only and will not run on Intel Macs
- **macOS 14 (Sonoma) or later**

---

## What's new in v0.3.13

- **Dock icon fix, root cause** — the check for "is another window still open" was always true because of an always-visible internal status-bar window, so the Dock icon never actually got hidden again after opening Settings or a detail card; now fixed at the root

See [CHANGELOG.md](CHANGELOG.md) for the full version history.

---

## Features

### CPU
- Overall usage percentage updated every second
- Per-process breakdown (Top CPU) with usage normalized across all logical cores
- Performance and Efficiency core counts (Apple Silicon)
- Historical usage chart

### Memory
- Real-time breakdown: Used, Wired, Compressed, Free
- Memory pressure indicator
- Historical usage chart

### Network
- Live upload and download throughput
- Butterfly chart in detail view: download up, upload down, shared scale with axis labels
- VPN indicator: shield icon always visible — green (VPN on), blue (FortiClient), grey (off)
- Connection type indicator: WiFi and/or Ethernet icon; primary connection is green, secondary is white
- Local IP address (tap to copy)
- Public IP address (tap to copy)
- Wi-Fi SSID and signal strength in dBm with visual bar indicator
- Historical speed chart

### Disk
- Read and write throughput per second
- Free and total disk space
- Historical I/O chart

### GPU & Displays
- Live GPU utilization % via IOAccelerator (same source as Activity Monitor)
- Switchable card view: chart sparkline, ring gauge, or display info
- Connected display names with native pixel resolutions and Retina badge
- Quick link to Display Arrangement settings

### Battery
- Charge percentage and charging state
- Time remaining / time to full
- Battery health percentage and condition
- Cycle count and design cycle count
- Temperature, voltage, and amperage

### Bluetooth
- Connected and paired device list
- Battery percentage per device:
  - **AirPods** — Left, Right, and Case shown separately
  - **BLE devices** (e.g. Logitech MX Master) — battery read via GATT Battery Service

---

## Installation

1. Download the latest `Performance Monitor.app` from [Releases](https://github.com/inequitas/performancemonitor/releases)
2. Unzip and drag to `/Applications`
3. Launch — the app appears in your menu bar
4. Grant **Bluetooth** permission when prompted to see Bluetooth device info

> **Gatekeeper note:** The app is ad-hoc signed (no Apple Developer ID). On first launch, right-click the app → **Open** to bypass the unidentified developer warning.

---

## Beta releases

Beta builds let early testers try upcoming changes before they reach the stable channel.

- **Workflow:** new features are developed on the `beta` branch (branched from `main`). Beta builds are tagged `vX.Y.Z-beta.N` (e.g. `v1.1.0-beta.1`) and published as GitHub **pre-releases**. Stable releases are still tagged `vX.Y.Z` from `main`, as before.
- **Building a beta:** `bash build_app.sh --beta` produces "Performance Monitor Beta" with its own bundle ID (`com.performancemonitor.beta`, so its settings are separate from the stable app) and a badged icon. `scripts/release.sh X.Y.Z-beta.N --beta [--publish]` builds, tags, and publishes it as a pre-release.
- **Update channel:** each build embeds a `PMUpdateChannel` key (`stable` or `beta`) in its `Info.plist`. Stable installs only ever see stable releases (GitHub's "latest" endpoint never returns a pre-release). Beta installs check the full releases list and are offered the newest version — beta or stable — so a beta install eventually rolls onto the corresponding stable release once one ships. The channel is shown in Settings → Updates when running the beta build.

---

## Building from Source

Requires an Apple Silicon Mac, Xcode Command Line Tools, and Swift 5.10+.

```bash
git clone https://github.com/inequitas/performancemonitor.git
cd performancemonitor
bash build_app.sh
open ".build/bundle/Performance Monitor.app"
```

The build script compiles a release binary, assembles the `.app` bundle (under the hidden `.build/bundle/`, so Spotlight doesn't index it), embeds the icon, injects the version from `VERSION`, and applies an ad-hoc code signature. Only the signed `.zip` for distribution is written to `dist/`. Pass `--beta` to build the beta-channel variant instead.

---

## Permissions

| Permission | Why |
|---|---|
| Bluetooth | Read paired device names and battery levels |

No data is collected or transmitted. Everything runs locally.

---

### Menu Bar
- Configurable metric: CPU, Memory, Network, or Disk
- Two display styles: **Sparkline** (mini live chart + current value) or **Text only**
- Sparkline shows the last 30 seconds of history, updated every second

### Thermal & Fans
- CPU, GPU, and Battery temperatures read from the SMC via IOKit — works across all Apple Silicon (M1–M4)
- All three temperatures shown on the main overview card, colour-coded green → yellow → orange → red
- **Extended sensor detail** in the Thermal view: individual CPU cores, GPU clusters, Trackpad, Storage, Memory, and System board sensors
- Grouped rows with expandable chevrons — tap to see individual core or cluster readings
- System group (Trackpad, WiFi/Airport proximity, Charger) shown expanded by default
- Fan speeds (Left/Right) with min/max range, position bar, and intake airflow temperature
- System thermal pressure level (Nominal → Critical)

## Tech Stack

- **Swift / SwiftUI** — UI and app lifecycle
- **IOKit** — CPU, disk, battery, and HID device metrics
- **CoreWLAN** — Wi-Fi signal strength
- **IOBluetooth** — Paired Bluetooth device list
- **CoreBluetooth** — BLE GATT Battery Service reads
- **Swift Package Manager** — No Xcode project required
