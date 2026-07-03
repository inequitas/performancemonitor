# Performance Monitor

A lightweight macOS menu bar app that gives you real-time system metrics at a glance — CPU, memory, network, disk, GPU, battery, and Bluetooth, all in a clean popover interface.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![Version](https://img.shields.io/badge/version-0.3.6-lightgrey)

---

## What's new in v0.3.6

- **Primary network interface** highlighted in green and sorted to the top in both the overview IP list and network detail view
- **Ping server setting** in Settings → Metrics — choose between Apple (default), Cloudflare (1.1.1.1), Google (8.8.8.8), or Quad9 (9.9.9.9)
- **Notification permissions** requested at launch; status banner in Settings → Updates if disabled
- **Settings icon flicker** fixed — section icons no longer animate on each metrics update

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

## Building from Source

Requires Xcode Command Line Tools and Swift 5.9+.

```bash
git clone https://github.com/inequitas/performancemonitor.git
cd performancemonitor
bash build_app.sh
open "dist/Performance Monitor.app"
```

The build script compiles a release binary, assembles the `.app` bundle, embeds the icon, injects the version from `VERSION`, and applies an ad-hoc code signature.

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
