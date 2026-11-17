import Foundation

/// Ranks installed applications against what the user typed.
///
/// The order mirrors Launchpad: names that start with the query first, then
/// names with a word that starts with it, then plain substrings, then initials
/// ("am" finds Activity Monitor).
enum SearchRanking {
    static func rank(_ apps: [AppItem], query: String, limit: Int = 60) -> [AppItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        let matches = apps.compactMap { app -> (AppItem, Int)? in
            guard let score = score(name: app.name.lowercased(), needle: needle) else { return nil }
            return (app, score)
        }

        let sorted = matches.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
        }

        return Array(sorted.prefix(limit).map(\.0))
    }

    static func score(name: String, needle: String) -> Int? {
        if name.hasPrefix(needle) { return 0 }

        let words = name.split(separator: " ")
        if words.contains(where: { $0.hasPrefix(needle) }) { return 1 }
        if name.contains(needle) { return 2 }

        let initials = String(words.compactMap(\.first))
        if initials.hasPrefix(needle) { return 3 }

        return nil
    }
}
