import Foundation

/// Pure, deterministic search ranking.
///
/// Match tiers (best first):
/// 0. Name prefix (including an exact match)
/// 1. Word prefix
/// 2. Substring
/// 3. Fuzzy (Levenshtein distance ≤ 1, only for queries of 4+ characters)
enum SearchEngine {
    enum MatchRank: Int, Comparable {
        case prefix = 0
        case wordPrefix = 1
        case substring = 2
        case fuzzy = 3

        static func < (lhs: MatchRank, rhs: MatchRank) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Case- and diacritic-insensitive folding used for every comparison.
    static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }

    static func rank(name: String, query: String) -> MatchRank? {
        let normalizedName = normalized(name)
        let normalizedQuery = normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return nil }

        if normalizedName.hasPrefix(normalizedQuery) {
            return .prefix
        }

        let words = normalizedName.split { !$0.isLetter && !$0.isNumber }
        if words.contains(where: { $0.hasPrefix(normalizedQuery) }) {
            return .wordPrefix
        }

        if normalizedName.contains(normalizedQuery) {
            return .substring
        }

        // Fuzzy matching is intentionally conservative: short queries produce
        // too many false positives, so require at least four characters.
        guard normalizedQuery.count >= 4 else { return nil }
        let candidates = [normalizedName] + words.map(String.init)
        if candidates.contains(where: { levenshteinDistance($0, normalizedQuery, limit: 1) <= 1 }) {
            return .fuzzy
        }
        return nil
    }

    /// Returns matching apps ordered by rank, then localized name.
    static func search(_ query: String, in apps: [AppItem]) -> [AppItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return apps.compactMap { app -> (AppItem, MatchRank)? in
            guard let rank = rank(name: app.name, query: trimmed) else { return nil }
            return (app, rank)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            let comparison = lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.0.id < rhs.0.id
        }
        .map(\.0)
    }

    /// Levenshtein distance with an early exit when the result exceeds `limit`.
    static func levenshteinDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        if abs(a.count - b.count) > limit { return limit + 1 }

        // Names are short, so a straightforward full-row dynamic program is
        // faster than a banded one and has no stale-cell edge cases.
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i]
            current.reserveCapacity(b.count + 1)
            for j in 1...b.count {
                let insertion = current[j - 1] + 1
                let deletion = previous[j] + 1
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current.append(min(insertion, deletion, substitution))
            }
            previous = current
        }

        return previous[b.count]
    }
}
