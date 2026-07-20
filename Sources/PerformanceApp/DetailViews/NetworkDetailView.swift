import SwiftUI
import AppKit
import Charts
import PerformanceAppCore

struct NetworkButterflyChart: View {
    let downloadHistory: [Double]
    let uploadHistory:   [Double]
    let downloadSpeed:   Double
    let uploadSpeed:     Double

    private var sharedMax: Double { absoluteMax(downloadHistory, uploadHistory) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Throughput"), systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
            HStack {
                Label(formatSpeed(downloadSpeed), systemImage: "arrow.down")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(MetricTheme.networkDown)
                Spacer()
                Label(formatSpeed(uploadSpeed), systemImage: "arrow.up")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(MetricTheme.networkUp)
            }
            HStack(spacing: 4) {
                VStack(spacing: 0) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(formatSpeed(sharedMax)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatSpeed(sharedMax / 2)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 90)
                    Text(formatSpeed(0)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(height: 14)
                    VStack(alignment: .trailing, spacing: 0) {
                        Spacer()
                        Text(formatSpeed(sharedMax / 2)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatSpeed(sharedMax)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(height: 90)
                }
                .frame(width: 56)
                VStack(spacing: 0) {
                    MetricChart(values: downloadHistory, fixedMax: sharedMax, showAxes: false, showGridLines: true, fillFrame: true, color: MetricTheme.networkDown, style: .area, accessibilityDescription: String(localized: "Download speed history")) { formatSpeed($0) }
                        .frame(height: 90)
                    Color.primary.opacity(0.25).frame(height: 1).frame(height: 14)
                    MetricChart(values: uploadHistory, fixedMax: sharedMax, showAxes: false, showGridLines: true, fillFrame: true, color: MetricTheme.networkUp, style: .area, accessibilityDescription: String(localized: "Upload speed history")) { formatSpeed($0) }
                        .frame(height: 90)
                        .scaleEffect(y: -1)
                }
                .frame(height: 194)
            }
        }
    }
}

// MARK: - Network

struct NetworkDetailView: View {
    @ObservedObject var engine: MetricsEngine
    @State private var expandedInterfaces: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(String(localized: "Network"), systemImage: MetricsEngine.Panel.network.icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(MetricTheme.networkDown)

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(engine.isConnected ? Color.green : Color.red).frame(width: 9, height: 9)
                            .accessibilityHidden(true)
                        Text(engine.isConnected ? String(format: String(localized: "Connected — %@"), engine.connectionType) : String(localized: "No connection"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        if engine.isVPNActive {
                            Label(String(localized: "VPN"), systemImage: "lock.shield.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        InfoButton(text: String(localized: "Local IPs are read from the system network interfaces.\n\nVPN is detected by the presence of utun, ppp, or ipsec interfaces.\n\nPublic IP is fetched from api.ipify.org over HTTPS. Only your outbound request is sent — no other data. Refreshed every 5 minutes.\n\nConnectivity check is an HTTPS HEAD request to Apple's captive portal endpoint (captive.apple.com). This respects your system proxy settings. True ICMP ping requires root on macOS, so this is used instead."))
                    }
                    ForEach(engine.localInterfaces) { iface in
                        interfaceRow(iface)
                    }
                    Divider()
                    CopyableIPRow(icon: "globe", label: String(localized: "Public IP"), value: engine.publicIP ?? String(localized: "Looking up…"))
                }
            }

            if let rssi = engine.wifiRSSI {
                SectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(engine.wifiSSID ?? String(localized: "Wi-Fi"), systemImage: "wifi")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            InfoButton(text: String(localized: "Signal strength is measured in dBm (decibel-milliwatts) — a negative number where closer to zero is stronger.\n\n• Excellent (−50 dBm or better): Ideal. Full speed, no drops.\n• Good (−50 to −65 dBm): Reliable for video calls and large transfers.\n• Fair (−65 to −75 dBm): Usable but may slow down. Consider moving closer to your router.\n• Weak (below −75 dBm): Prone to disconnects and slow speeds.\n\nRead from CoreWLAN — same source as the macOS menu bar WiFi indicator."))
                        }
                        WiFiSignalBars(rssi: rssi)
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(String(localized: "Connectivity Check"), systemImage: "waveform.path.ecg")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let ms = engine.pingLatencyMs {
                            Text(String(format: "%.0f ms", ms))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(ms < 100 ? .green : ms < 300 ? .orange : .red)
                                .accessibilityValue(String(format: String(localized: "%ld milliseconds, %@"), Int(ms.rounded()), ms < 100 ? String(localized: "good") : ms < 300 ? String(localized: "fair") : String(localized: "poor")))
                        } else {
                            Text(String(localized: "Timeout")).font(.caption).foregroundStyle(.red)
                        }
                    }
                    MetricChart(values: engine.pingHistory, unit: "ms", showAxes: true, color: .teal, accessibilityDescription: String(localized: "Ping latency history")) { String(format: "%.0fms", $0) }
                        .frame(height: 60)
                }
            }

            SectionCard {
                NetworkButterflyChart(
                    downloadHistory: engine.downloadHistory,
                    uploadHistory: engine.uploadHistory,
                    downloadSpeed: engine.downloadSpeedKBps,
                    uploadSpeed: engine.uploadSpeedKBps
                )
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label(String(localized: "Top Network Usage"), systemImage: "network")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MetricTheme.networkDown)
                    if engine.topNetworkProcesses.isEmpty {
                        Text(String(localized: "Measuring…")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(engine.topNetworkProcesses) { proc in
                            HStack {
                                Text(proc.name).font(.caption).lineLimit(1)
                                Spacer()
                                Text(formatSpeed(proc.value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func interfaceRow(_ iface: LocalInterface) -> some View {
        let isExpanded = expandedInterfaces.contains(iface.id)
        let suffix = iface.prefixLength.map { "/\($0)" } ?? ""

        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded { expandedInterfaces.remove(iface.id) }
                    else          { expandedInterfaces.insert(iface.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iface.icon)
                        .font(.caption2)
                        .foregroundStyle(iface.isPrimary ? Color.green : Color.secondary)
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    Text(iface.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityValue(iface.isPrimary ? String(localized: "primary connection") : "")
                    Spacer()
                    if !isExpanded {
                        Text(iface.address + suffix)
                            .font(.caption.monospacedDigit())
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    CopyableIPRow(label: "IP", value: iface.address)
                    if let mask = iface.subnetMask {
                        CopyableIPRow(label: String(localized: "Subnet"), value: mask)
                    }
                    if let gw = iface.gateway {
                        CopyableIPRow(label: String(localized: "Gateway"), value: gw)
                    }
                    ForEach(engine.dnsServers, id: \.self) { dns in
                        CopyableIPRow(icon: "server.rack", label: "DNS", value: dns)
                    }
                }
                .padding(.leading, 22)
            }
        }
    }
}
