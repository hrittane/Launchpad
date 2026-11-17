import Foundation
import Testing

@testable import Launchpad

private func makeApp(_ name: String) -> AppItem {
    AppItem(
        bundleIdentifier: "com.test.\(name.replacingOccurrences(of: " ", with: ""))",
        url: URL(fileURLWithPath: "/Applications/\(name).app"),
        name: name
    )
}

struct SearchRankingTests {
    @Test
    func prefixMatchesComeFirst() {
        let apps = [makeApp("Photo Booth"), makeApp("Clock"), makeApp("World Clock")]
        let results = SearchRanking.rank(apps, query: "cl")

        #expect(results.first?.name == "Clock")
        #expect(results.map(\.name) == ["Clock", "World Clock"])
    }

    @Test
    func wordPrefixesAndSubstringsBothMatch() {
        let apps = [makeApp("Console"), makeApp("Activity Monitor"), makeApp("Calculator")]

        let wordPrefix = SearchRanking.rank(apps, query: "monitor")
        #expect(wordPrefix.map(\.name) == ["Activity Monitor"])

        let substring = SearchRanking.rank(apps, query: "sol")
        #expect(substring.map(\.name) == ["Console"])
    }

    @Test
    func initialsMatch() {
        let apps = [makeApp("Activity Monitor"), makeApp("Ambient Mixer"), makeApp("Chess")]
        let results = SearchRanking.rank(apps, query: "am")

        #expect(results.map(\.name) == ["Ambient Mixer", "Activity Monitor"])
    }

    @Test
    func matchingIsCaseInsensitive() {
        let apps = [makeApp("Calendar")]
        #expect(SearchRanking.rank(apps, query: "CAL").map(\.name) == ["Calendar"])
    }

    @Test
    func emptyQueryReturnsNothing() {
        let apps = [makeApp("Calendar")]
        #expect(SearchRanking.rank(apps, query: "   ").isEmpty)
    }

    @Test
    func rankingRespectsTheLimit() {
        let apps = (1...10).map { makeApp("Test App \($0)") }
        #expect(SearchRanking.rank(apps, query: "test", limit: 3).count == 3)
    }

    @Test
    func tiesAreSortedByName() {
        let apps = [makeApp("Game Center"), makeApp("Game Center 2")]
        #expect(SearchRanking.rank(apps, query: "game").map(\.name) == ["Game Center", "Game Center 2"])
    }
}
