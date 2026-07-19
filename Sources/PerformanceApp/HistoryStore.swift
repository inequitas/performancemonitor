import Foundation
import AppKit
import UniformTypeIdentifiers

/// Owns the on-disk history CSV: the application-support file location, the
/// append file handle, and the row-append + export logic. Extracted from
/// MetricsEngine so the data engine only has to call `append(...)` each tick.
///
/// Behaviour-preserving: the file path, header, and row formatting are
/// identical to the original engine implementation.
@MainActor
final class HistoryStore {

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerformanceApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.csv")
    }()
    private var fileHandle: FileHandle?

    /// Appends one sampled row to the on-disk history CSV. No-ops unless
    /// persistence is enabled. The file (with header) is created lazily on the
    /// first enabled append.
    func append(enabled: Bool,
                cpu: Double,
                memory: Double,
                download: Double,
                upload: Double,
                diskFree: Double) {
        guard enabled else { return }

        if fileHandle == nil {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                let header = "timestamp,cpu_percent,memory_gb,download_kbps,upload_kbps,disk_free_gb\n"
                try? header.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            fileHandle = try? FileHandle(forWritingTo: fileURL)
            fileHandle?.seekToEndOfFile()
        }

        let row = "\(Date().timeIntervalSince1970),\(cpu),\(memory),\(download),\(upload),\(diskFree)\n"
        if let data = row.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    /// Prompts for a destination and writes the engine's in-memory ring-buffer
    /// history to a CSV. Unchanged from the original `exportHistoryCSV()`.
    func exportCSV(cpu: [Double],
                   memory: [Double],
                   download: [Double],
                   upload: [Double],
                   diskRead: [Double],
                   diskWrite: [Double]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "performance-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "timestamp,cpu_percent,memory_gb,download_kbps,upload_kbps,disk_read_kbps,disk_write_kbps\n"
        let count = cpu.count
        for i in 0..<count {
            let mem = i < memory.count ? memory[i] : 0
            let down = i < download.count ? download[i] : 0
            let up = i < upload.count ? upload[i] : 0
            let dr = i < diskRead.count ? diskRead[i] : 0
            let dw = i < diskWrite.count ? diskWrite[i] : 0
            csv += "\(i),\(cpu[i]),\(mem),\(down),\(up),\(dr),\(dw)\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
