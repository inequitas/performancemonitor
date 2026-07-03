# Changelog

### v0.3.5 — Battery card improvements *(2026-07-03)*
- **Battery overview card** shows an explicit "Charging" / "On Battery" status label, charging wattage clearly labelled as charging speed, and time remaining on battery — "0h 0m" suppressed when nearly full
- **Battery detail icon** reflects actual charge level (0 / 25 / 50 / 75 / 100%) and adds a bolt when charging, updating live
- **Periodic update checks** every 3 hours while the app is running

### v0.3.4 — In-app update checker *(2026-07-03)*
- **Updates tab** in Settings checks GitHub on launch and notifies when a new version is available
- **System notification** with three actions: Update Now, Remind Me Later, Skip This Version
- **One-click install** — downloads the release zip, replaces the app bundle, and relaunches automatically; falls back to revealing the new app in Finder if permissions prevent replacement
- **Configurable snooze** — set the "Remind Me Later" duration to 1, 3, 7, or 14 days from Settings → Updates
- **Settings window focus** fixed — no longer hides behind other apps on open
- **Settings window sizing** — all tabs now auto-size to their content, no scrolling required

### v0.3.3 — Extended temperature sensors, multi-generation Apple Silicon support *(2026-07-03)*
- **Extended SMC sensor coverage** across all Apple Silicon generations (M1 / M2 / M3 / M4) — CPU and GPU temperatures now read correctly on all chips including M3 (Te\*/Tf\* keys) and M4
- **Trackpad temperature** — Force Touch haptic actuator sensors (M3/M4 TD\* grid) averaged into a single Trackpad entry; individual palm-rest sensors shown on M1/M2
- **System group** — Trackpad, WiFi Proximity, Airport Proximity, Charger Proximity, and board sensors grouped under an expandable System row that starts open
- **Storage group** — SSD temperature shown with expandable sub-rows for Macs with multiple drives (up to 4 SSDs mapped)
- **Memory group** — Memory module temperatures shown with expandable sub-rows
- **Airflow temperatures** — Intake air temperature (TaLP / TaRF) shown alongside each fan's RPM in the Fans section
- **Battery thermistors** suppressed from temperature list (already shown in the Battery detail view)

### v0.3.2 — Butterfly charts, VPN indicator, temperature colours *(2026-07-03)*
- **Network and Disk detail charts** redesigned as butterfly charts: download/read grows upward, upload/write grows downward on a shared scale with max, midpoint, and 0 labels outside the chart area so they never overlap the data
- **VPN shield** always visible in the Network overview card — green when a VPN is active, blue specifically for FortiClient, grey when off
- **Temperature colour coding** in the Thermal and Battery detail views — CPU/GPU thresholds at 60 / 75 / 90 °C (green → yellow → orange → red); Battery at 35 / 45 / 55 °C

### v0.3.1 — Persistent settings *(2026-07-02)*
- All settings now survive restarts and app updates: panel order and visibility, alert toggles and thresholds, menu bar style and metric, refresh interval, card styles (area/gauge), dock visibility, and all other preferences
- Dock icon option fixed: no longer reappears after closing Settings
- Settings use `UserDefaults` with stable keys; new settings added in future versions default gracefully without breaking existing saved data

### v0.3.0 — Settings tabs, visual panel manager, configurable alerts *(2026-07-02)*
- **Settings redesigned** into four tabs: General, Metrics, Alerts, History, and Panels
- **Visual panel manager** — drag-and-drop mini grid in Settings → Panels mirrors the actual layout; drag any card to reorder, including moving Network and Bluetooth between grid rows; tap the eye icon to show or hide individual panels
- **Configurable alerts** — each metric (CPU, Memory, Disk, GPU, Thermal) has its own enable toggle and threshold slider; alerts are fully independent of each other
- **Unified panel layout** — full-width cards (Network, Bluetooth) can now be positioned anywhere in the overview, appearing between grid rows as you arrange them

### v0.2.2 — GPU utilization, menu bar sparkline, Settings fix *(2026-07-01)*
- **GPU utilization %** — live usage read from `IOAccelerator`; GPU card switches between chart, gauge, and info (GPU name + displays) views from the card menu
- **Menu bar sparkline** — mini live chart in the menu bar showing the last 30 seconds of the selected metric; toggle between sparkline and plain text in Settings → Menu bar style
- **Settings window** now opens in front correctly on menu bar-only apps

### v0.2.1 — Disk card redesign, UI polish *(2026-07-01)*
- **Disk card** replaced the unlabelled single sparkline with a labelled butterfly chart: read speed (indigo) grows upward, write speed (purple) grows downward, on a shared scale
- **Disk gauge mode** — new ring view showing disk used %, with free / total GB alongside
- **Chart styles simplified** — line and bar removed everywhere; only Area and Gauge remain
- **Centered values** across all overview cards (CPU, Memory, Thermal, Battery, GPU, Disk)

### v0.2.0 — SMC temperatures, fan readings, network connection indicators *(2026-07-01)*
- **Thermal card** on the main overview now shows CPU, GPU, and Battery temperatures simultaneously, each colour-coded
- **SMC temperature fix** — resolved a critical bug where `dataType` was read from the wrong IOKit response, causing temperatures to disappear entirely
- **Fan RPM fix** — corrected data-type decoding (float vs fixed-point) and key name detection; fans now labelled **Left** / **Right** on two-fan Macs
- **Fan control removed** — SMC writes require a root-level privileged helper; unprivileged writes return `kIOReturnError`. Fan speeds remain read-only.
- **Network connection indicators** — WiFi and Ethernet icons shown left of bandwidth speeds; primary connection is green, secondary (when both active) is white; updates in real time when connections change

### v0.1.1 *(2026-07-01)*
- Bluetooth battery percentage for AirPods (Left/Right/Case) and BLE devices (e.g. Logitech MX Master via GATT)
- Ring gauge chart style for CPU, Memory, and Disk cards

### v0.1.0 *(2026-07-01)*
- Initial release — CPU, Memory, Network, Disk, GPU, Battery, Bluetooth, Thermal overview
