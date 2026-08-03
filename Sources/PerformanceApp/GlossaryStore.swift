import Foundation
import PerformanceAppCore

/// Loads the process glossary from the bundle and answers lookups for the UI.
///
/// The data lives in `Resources/Glossary/glossary.<lang>.json`, one file per
/// language, rather than in `Localizable.strings`. Descriptions run to a couple
/// of hundred characters each and there are close to a hundred of them, which
/// would swamp a strings file that is otherwise made of button labels. Keeping
/// them separate also means the glossary can grow without touching the key
/// parity that the UI strings depend on.
///
/// Loading is lazy and happens once. Nothing here runs on the metrics tick.
@MainActor
final class GlossaryStore {
    static let shared = GlossaryStore()

    private var loaded: ProcessGlossary?

    private init() {}

    var glossary: ProcessGlossary {
        if let loaded { return loaded }
        let g = Self.load()
        loaded = g
        return g
    }

    func entry(for name: String) -> GlossaryEntry? {
        glossary.lookup(name: name)
    }

    // MARK: - Loading

    private struct File: Decodable {
        struct Entry: Decodable {
            struct Match: Decodable {
                let name: String?
                let nameSuffix: String?
                let bundleID: String?
                let bundleIDPrefix: String?
                let pathPrefix: String?
                let pathSuffix: String?
            }
            let match: Match
            let title: String
            let category: String
            let vendor: String?
            let expectedHigh: Bool?
            let description: String
        }
        let version: Int
        let entries: [Entry]
    }

    /// Reads the file for the user's language, falling back to English. A
    /// missing or malformed file yields an empty glossary rather than a crash:
    /// the feature is additive, and a process list without explanations is the
    /// same list this app shipped for its first two versions.
    private static func load() -> ProcessGlossary {
        let preferred = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        // Chinese ships as zh-Hans, everything else as a two-letter code.
        let candidates = preferred == "zh" ? ["zh-Hans", "en"] : [preferred, "en"]

        for code in candidates {
            guard let url = Bundle.main.url(forResource: "glossary.\(code)",
                                            withExtension: "json",
                                            subdirectory: "Glossary")
                ?? Bundle.main.url(forResource: "glossary.\(code)", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(File.self, from: data)
            else { continue }
            return ProcessGlossary(entries: file.entries.compactMap(decode))
        }
        return ProcessGlossary(entries: [])
    }

    private static func decode(_ e: File.Entry) -> GlossaryEntry? {
        let match: GlossaryEntry.Match
        if let v = e.match.name { match = .name(v) }
        else if let v = e.match.nameSuffix { match = .nameSuffix(v) }
        else if let v = e.match.bundleID { match = .bundleID(v) }
        else if let v = e.match.bundleIDPrefix { match = .bundleIDPrefix(v) }
        else if let v = e.match.pathPrefix { match = .pathPrefix(v) }
        else if let v = e.match.pathSuffix { match = .pathSuffix(v) }
        else { return nil }

        guard let category = GlossaryEntry.Category(rawValue: e.category) else { return nil }

        return GlossaryEntry(match: match,
                             title: e.title,
                             category: category,
                             vendor: e.vendor,
                             expectedHigh: e.expectedHigh ?? false,
                             description: e.description)
    }
}
