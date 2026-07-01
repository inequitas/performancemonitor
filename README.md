# Performance Monitor

A lightweight macOS menu bar app that gives you real-time system metrics at a glance — CPU, memory, network, disk, GPU, battery, and Bluetooth, all in a clean popover interface.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![Version](https://img.shields.io/badge/version-0.2.2-lightgrey)

---

## Releases

### v0.2.2 — GPU utilization, menu bar sparkline, Settings fix
- **GPU utilization %** — live usage read from `IOAccelerator`; GPU card switches between chart, gauge, and info (GPU name + displays) views from the card menu
- **Menu bar sparkline** — mini live chart in the menu bar showing the last 30 seconds of the selected metric; toggle between sparkline and plain text in Settings → Menu bar style
- **Settings window** now opens in front correctly on menu bar-only apps

### v0.2.1 — Disk card redesign, UI polish
- **Disk card** replaced the unlabelled single sparkline with a labelled butterfly chart: read speed (indigo) grows upward, write speed (purple) grows downward, on a shared scale
- **Disk gauge mode** — new ring view showing disk used %, with free / total GB alongside
- **Chart styles simplified** — line and bar removed everywhere; only Area and Gauge remain
- **Centered values** across all overview cards (CPU, Memory, Thermal, Battery, GPU, Disk)

### v0.2.0 — SMC temperatures, fan readings, network connection indicators
- **Thermal card** on the main overview now shows CPU, GPU, and Battery temperatures simultaneously, each colour-coded
- **SMC temperature fix** — resolved a critical bug where `dataType` was read from the wrong IOKit response, causing temperatures to disappear entirely
- **Fan RPM fix** — corrected data-type decoding (float vs fixed-point) and key name detection; fans now labelled **Left** / **Right** on two-fan Macs
- **Fan control removed** — SMC writes require a root-level privileged helper; unprivileged writes return `kIOReturnError`. Fan speeds remain read-only.
- **Network connection indicators** — WiFi and Ethernet icons shown left of bandwidth speeds; primary connection is green, secondary (when both active) is white; updates in real time when connections change

### v0.1.1
- Bluetooth battery percentage for AirPods (Left/Right/Case) and BLE devices (e.g. Logitech MX Master via GATT)
- Ring gauge chart style for CPU, Memory, and Disk cards

### v0.1.0
- Initial release — CPU, Memory, Network, Disk, GPU, Battery, Bluetooth, Thermal overview

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
- CPU, GPU, and Battery temperatures read from the SMC via IOKit
- All three temperatures shown on the main overview card
- Fan speeds (Left/Right) with min/max range and position bar
- System thermal pressure level (Nominal → Critical)

## Tech Stack

- **Swift / SwiftUI** — UI and app lifecycle
- **IOKit** — CPU, disk, battery, and HID device metrics
- **CoreWLAN** — Wi-Fi signal strength
- **IOBluetooth** — Paired Bluetooth device list
- **CoreBluetooth** — BLE GATT Battery Service reads
- **Swift Package Manager** — No Xcode project required
