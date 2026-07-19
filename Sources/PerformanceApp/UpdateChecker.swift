import Foundation
import AppKit
import UserNotifications
import CryptoKit
import PerformanceAppCore

@MainActor
final class UpdateChecker: NSObject, ObservableObject {
    enum State {
        case idle
        case checking
        case upToDate
        case available(version: String, downloadURL: URL)
        case downloading
        case installing
        case error(String)
    }

    @Published var state: State = .idle
    @Published var lastChecked: Date?
    @Published var notificationsEnabled: Bool = true

    // Snooze duration setting — persisted, shown as a picker in the Updates tab
    @Published var snoozeDays: Int {
        didSet { UserDefaults.standard.set(snoozeDays, forKey: "updateSnoozeDays") }
    }

    let currentVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

    private let apiURL = URL(string: "https://api.github.com/repos/inequitas/performancemonitor/releases/latest")!

    // Ed25519 (Curve25519) public key for verifying update downloads, base64.
    // The matching private key lives only in scripts/private_key.txt (git-ignored)
    // and signs each release's .zip. Generated once by scripts/generate_keys.swift.
    // This app has no Apple Developer ID, so downloads are not notarised; this
    // signature check is what replaces Gatekeeper's trust guarantee (see below).
    private static let publicKeyBase64 = "5hWpqy+Ee2iiiZUPILmSQlVF/2kg3RSQxM47mZPmu1g="

    // Only these hosts may serve an update download or its signature. GitHub
    // release assets are served from github.com and redirected to
    // objects.githubusercontent.com; anything else is refused.
    private static let allowedDownloadHosts: Set<String> = ["github.com", "objects.githubusercontent.com"]

    private static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedDownloadHosts.contains(host)
        else { return false }
        return true
    }

    // UserDefaults keys
    private static let snoozeUntilKey      = "updateSnoozeUntil"
    private static let neverVersionKey     = "updateNeverVersion"
    private static let notifiedVersionKey  = "updateLastNotifiedVersion"
    private static let snoozeDaysKey       = "updateSnoozeDays"
    private static let lastRunVersionKey   = "updateLastRunVersion"

    // Notification identifiers
    private static let categoryID = "PERFORMANCE_UPDATE"
    private static let notifID    = "update_available"

    private var periodicTimer: Timer?

    override init() {
        snoozeDays = UserDefaults.standard.integer(forKey: Self.snoozeDaysKey).nonZero ?? 7
        super.init()

        // Register notification category with three actions
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let updateAction = UNNotificationAction(identifier: "UPDATE_NOW",    title: "Update Now",          options: .foreground)
        let remindAction = UNNotificationAction(identifier: "REMIND_LATER",  title: "Remind Me Later",     options: [])
        let neverAction  = UNNotificationAction(identifier: "NEVER",         title: "Skip This Version",   options: .destructive)
        let category = UNNotificationCategory(identifier: Self.categoryID,
                                              actions: [updateAction, remindAction, neverAction],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])

        // Clear the notified-version record when the app itself has been updated,
        // so the next available version always triggers a fresh notification.
        let lastRun = UserDefaults.standard.string(forKey: Self.lastRunVersionKey)
        if lastRun != currentVersion {
            UserDefaults.standard.set(currentVersion, forKey: Self.lastRunVersionKey)
            UserDefaults.standard.removeObject(forKey: Self.notifiedVersionKey)
        }

        Task {
            // Request permission up-front at launch so the dialog appears while
            // the user is actively launching the app, not later when it fires silently.
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
            notificationsEnabled = granted
            await performCheck()
        }

        // Re-check every 3 hours while the app is running
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.performCheck() }
        }
    }

    func checkForUpdates() {
        Task { await performCheck() }
    }

    func refreshNotificationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsEnabled = status == .authorized
    }

    func downloadAndInstall(from downloadURL: URL) {
        Task { await performInstall(from: downloadURL) }
    }

    // MARK: - Private

    private func performCheck() async {
        state = .checking
        do {
            var req = URLRequest(url: apiURL)
            req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: req)
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = json["tag_name"] as? String,
                let assets = json["assets"] as? [[String: Any]],
                let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                let urlStr = zipAsset["browser_download_url"] as? String,
                let downloadURL = URL(string: urlStr)
            else {
                state = .error("Could not read release info from GitHub.")
                return
            }
            guard Self.isAllowedDownloadURL(downloadURL) else {
                state = .error("Update refused — download is not served from a trusted GitHub host.")
                return
            }
            lastChecked = Date()
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if isNewer(latest, than: currentVersion) {
                state = .available(version: latest, downloadURL: downloadURL)
                await sendUpdateNotification(version: latest, downloadURL: downloadURL)
            } else {
                state = .upToDate
            }
        } catch {
            state = .error("Network error: \(error.localizedDescription)")
        }
    }

    private func sendUpdateNotification(version: String, downloadURL: URL) async {
        // Don't notify if the user skipped this version
        if UserDefaults.standard.string(forKey: Self.neverVersionKey) == version { return }
        // Don't notify during snooze window
        if let snoozeUntil = UserDefaults.standard.object(forKey: Self.snoozeUntilKey) as? Date,
           Date() < snoozeUntil { return }
        // Don't re-notify for the same version in the same session
        if UserDefaults.standard.string(forKey: Self.notifiedVersionKey) == version { return }

        let center = UNUserNotificationCenter.current()
        let authStatus = await center.notificationSettings().authorizationStatus
        notificationsEnabled = authStatus == .authorized
        guard authStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Performance Monitor Update"
        content.body  = "Version \(version) is available — you're on \(currentVersion)."
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["version": version, "downloadURL": downloadURL.absoluteString]

        let request = UNNotificationRequest(identifier: Self.notifID, content: content, trigger: nil)
        try? await center.add(request)
        UserDefaults.standard.set(version, forKey: Self.notifiedVersionKey)
    }

    private func performInstall(from downloadURL: URL) async {
        state = .downloading
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerfMonUpdate-\(UUID().uuidString)")

        // Clean up the temp directory on every failure path. On success we set
        // `handedOff` before launching the installer script (which lives inside
        // tmp and runs after we quit), so the files survive until then.
        var handedOff = false
        defer { if !handedOff { try? FileManager.default.removeItem(at: tmp) } }

        do {
            // Reject anything not served from the trusted GitHub hosts, even if a
            // manipulated release pointed the download elsewhere.
            guard Self.isAllowedDownloadURL(downloadURL) else {
                state = .error("Update refused — download is not served from a trusted GitHub host.")
                return
            }

            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let zipPath = tmp.appendingPathComponent("update.zip")

            let (data, response) = try await URLSession.shared.data(from: downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                state = .error("Download failed — server returned an error.")
                return
            }
            try data.write(to: zipPath)

            // --- Cryptographic verification, BEFORE we unpack anything ---
            // The signature asset sits next to the zip as "<zip>.sig" in the same
            // release. We verify the raw zip bytes against the embedded public key.
            // This is the transition to signed updates: the first signed release
            // ships this code and its own .sig; from that release on, an update
            // with a missing or invalid signature is refused outright (fail-closed).
            guard let verifyingKey = try? Curve25519.Signing.PublicKey(
                    rawRepresentation: Data(base64Encoded: Self.publicKeyBase64) ?? Data()) else {
                state = .error("Update aborted — internal verification key is invalid.")
                return
            }

            guard let sigURL = URL(string: downloadURL.absoluteString + ".sig"),
                  Self.isAllowedDownloadURL(sigURL) else {
                state = .error("Update aborted — could not locate the signature file.")
                return
            }

            let signature: Data
            do {
                let (sigData, sigResponse) = try await URLSession.shared.data(from: sigURL)
                guard (sigResponse as? HTTPURLResponse)?.statusCode == 200,
                      let sigB64 = String(data: sigData, encoding: .utf8)?
                          .trimmingCharacters(in: .whitespacesAndNewlines),
                      let decoded = Data(base64Encoded: sigB64) else {
                    state = .error("Update aborted — signature is missing or unreadable. This release cannot be verified.")
                    return
                }
                signature = decoded
            } catch {
                state = .error("Update aborted — could not download the signature file.")
                return
            }

            guard verifyingKey.isValidSignature(signature, for: data) else {
                state = .error("Update aborted — the download failed signature verification and may have been tampered with.")
                return
            }
            // --- Verification passed: the zip bytes are authentic ---

            state = .installing

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", zipPath.path, "-d", tmp.path]
            unzip.standardOutput = Pipe()
            unzip.standardError = Pipe()
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else {
                state = .error("Failed to unzip the downloaded archive.")
                return
            }

            guard let newAppURL = try FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)
                    .first(where: { $0.pathExtension == "app" }) else {
                state = .error("App bundle not found inside downloaded archive.")
                return
            }

            let currentAppPath = Bundle.main.bundleURL.path
            let newAppPath     = newAppURL.path

            // Shell script runs after we quit: replace bundle, clear quarantine, relaunch.
            // Falls back to revealing the new app in Finder if permissions prevent replacement.
            //
            // `xattr -cr` (clearing the quarantine attribute) only runs here, AFTER the
            // download passed Ed25519 signature verification above. That ordering is the
            // whole point: this app has no Apple Developer ID, so the bundle isn't
            // notarised and Gatekeeper would otherwise block it. Our own signature check
            // has already established that the bytes are authentic and untampered, so
            // clearing quarantine at this stage is safe — the signature verification is
            // standing in for the trust Gatekeeper normally provides.
            let script = """
            #!/bin/bash
            sleep 1.5
            rm -rf \(q(currentAppPath)) && ditto \(q(newAppPath)) \(q(currentAppPath)) && xattr -cr \(q(currentAppPath))
            if [ $? -eq 0 ]; then
                open \(q(currentAppPath))
            else
                open -R \(q(newAppPath))
            fi
            """
            let scriptURL = tmp.appendingPathComponent("install.sh")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)

            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptURL.path]
            try chmod.run(); chmod.waitUntilExit()

            // Hand off to the installer script (it lives in tmp and runs after we
            // quit), so tmp must survive: suppress the cleanup defer from here on.
            handedOff = true

            let sh = Process()
            sh.executableURL = URL(fileURLWithPath: "/bin/sh")
            sh.arguments = [scriptURL.path]
            try sh.run()

            // Reset activation policy before quitting so no dock-icon flash on relaunch
            NSApp.setActivationPolicy(.accessory)
            NSApp.terminate(nil)
        } catch {
            state = .error("Install failed: \(error.localizedDescription)")
        }
    }

    private func handleNotificationAction(_ actionID: String, version: String, downloadURLStr: String) {
        switch actionID {
        case "UPDATE_NOW":
            if let url = URL(string: downloadURLStr) { downloadAndInstall(from: url) }
        case "REMIND_LATER":
            let snoozeInterval = TimeInterval(snoozeDays) * 86400
            UserDefaults.standard.set(Date().addingTimeInterval(snoozeInterval), forKey: Self.snoozeUntilKey)
            UserDefaults.standard.removeObject(forKey: Self.notifiedVersionKey)
        case "NEVER":
            UserDefaults.standard.set(version, forKey: Self.neverVersionKey)
        default:
            break
        }
    }

    private func q(_ s: String) -> String {
        "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func isNewer(_ a: String, than b: String) -> Bool {
        VersionComparison.isNewer(a, than: b)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension UpdateChecker: UNUserNotificationCenterDelegate {
    // Show banner even when the app is frontmost
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo   = response.notification.request.content.userInfo
        let version    = userInfo["version"] as? String ?? ""
        let urlStr     = userInfo["downloadURL"] as? String ?? ""
        let actionID   = response.actionIdentifier

        Task { @MainActor in
            self.handleNotificationAction(actionID, version: version, downloadURLStr: urlStr)
        }
        completionHandler()
    }
}

// MARK: - Helpers

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
