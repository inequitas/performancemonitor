import Foundation
import AppKit
import UserNotifications

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

    // Snooze duration setting — persisted, shown as a picker in the Updates tab
    @Published var snoozeDays: Int {
        didSet { UserDefaults.standard.set(snoozeDays, forKey: "updateSnoozeDays") }
    }

    let currentVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

    private let apiURL = URL(string: "https://api.github.com/repos/inequitas/performancemonitor/releases/latest")!

    // UserDefaults keys
    private static let snoozeUntilKey      = "updateSnoozeUntil"
    private static let neverVersionKey     = "updateNeverVersion"
    private static let notifiedVersionKey  = "updateLastNotifiedVersion"
    private static let snoozeDaysKey       = "updateSnoozeDays"

    // Notification identifiers
    private static let categoryID = "PERFORMANCE_UPDATE"
    private static let notifID    = "update_available"

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

        Task { await performCheck() }
    }

    func checkForUpdates() {
        Task { await performCheck() }
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
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

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

        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let zipPath = tmp.appendingPathComponent("update.zip")

            let (data, response) = try await URLSession.shared.data(from: downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                state = .error("Download failed — server returned an error.")
                return
            }
            try data.write(to: zipPath)

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

            let sh = Process()
            sh.executableURL = URL(fileURLWithPath: "/bin/sh")
            sh.arguments = [scriptURL.path]
            try sh.run()

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
        let parts = { (s: String) -> [Int] in s.split(separator: ".").compactMap { Int($0) } }
        let va = parts(a), vb = parts(b)
        for i in 0..<max(va.count, vb.count) {
            let ai = i < va.count ? va[i] : 0
            let bi = i < vb.count ? vb[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
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
