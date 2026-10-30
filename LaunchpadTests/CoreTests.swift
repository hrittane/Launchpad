import XCTest
@testable import Launchpad

final class SearchEngineTests: XCTestCase {
    private func app(_ name: String, id: String? = nil) -> AppItem {
        AppItem(
            id: id ?? name,
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            isSystemApp: false
        )
    }

    func testRankingPrioritizesPrefixThenWordPrefixThenSubstring() {
        let apps = [
            app("Screenshot"),
            app("The Calculator"),
            app("Calc Pro")
        ]

        let result = SearchEngine.search("calc", in: apps)
        XCTAssertEqual(result.map(\.name), ["Calc Pro", "The Calculator"])
    }

    func testPrefixBeatsSubstringAndAlphabetizesTies() {
        let apps = [
            app("Screenshot"),
            app("Shotgun"),
            app("Snapshot")
        ]

        let result = SearchEngine.search("shot", in: apps)
        XCTAssertEqual(result.map(\.name), ["Shotgun", "Screenshot", "Snapshot"])
    }

    func testSearchIsCaseAndDiacriticInsensitive() {
        let apps = [app("École"), app("Safari")]

        XCTAssertEqual(SearchEngine.search("ecole", in: apps).map(\.name), ["École"])
        XCTAssertEqual(SearchEngine.search("SAFARI", in: apps).map(\.name), ["Safari"])
    }

    func testFuzzyMatchingRequiresFourCharacters() {
        let apps = [app("Safari")]

        XCTAssertEqual(SearchEngine.search("safri", in: apps).map(\.name), ["Safari"])
        XCTAssertTrue(SearchEngine.search("saf", in: apps).isEmpty == false)
        XCTAssertTrue(SearchEngine.search("sfr", in: apps).isEmpty)
    }

    func testFuzzyDistanceThresholdIsOne() {
        XCTAssertEqual(SearchEngine.levenshteinDistance("safari", "safri", limit: 1), 1)
        XCTAssertEqual(SearchEngine.levenshteinDistance("safari", "saf", limit: 1), 2)
        XCTAssertGreaterThan(SearchEngine.levenshteinDistance("safari", "xyz", limit: 1), 1)
    }

    func testEmptyQueryReturnsNoResults() {
        XCTAssertTrue(SearchEngine.search("   ", in: [app("Safari")]).isEmpty)
    }

    func testDuplicateNamesAreDeterministicallyOrderedByID() {
        let apps = [app("Notes", id: "b"), app("Notes", id: "a")]
        XCTAssertEqual(SearchEngine.search("notes", in: apps).map(\.id), ["a", "b"])
    }
}

final class LayoutEngineTests: XCTestCase {
    private func app(_ name: String) -> AppItem {
        AppItem(
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            isSystemApp: false
        )
    }

    func testPageCountAndIndexMath() {
        XCTAssertEqual(LayoutEngine.pageCount(forItemCount: 0, capacity: 35), 1)
        XCTAssertEqual(LayoutEngine.pageCount(forItemCount: 1, capacity: 35), 1)
        XCTAssertEqual(LayoutEngine.pageCount(forItemCount: 35, capacity: 35), 1)
        XCTAssertEqual(LayoutEngine.pageCount(forItemCount: 36, capacity: 35), 2)
        XCTAssertEqual(LayoutEngine.pageCount(forItemCount: 70, capacity: 35), 2)
        XCTAssertEqual(LayoutEngine.pageIndex(forFlatIndex: 0, capacity: 35), 0)
        XCTAssertEqual(LayoutEngine.pageIndex(forFlatIndex: 34, capacity: 35), 0)
        XCTAssertEqual(LayoutEngine.pageIndex(forFlatIndex: 35, capacity: 35), 1)
    }

    func testPaginateAlwaysReturnsAtLeastOnePage() {
        XCTAssertEqual(LayoutEngine.paginate([], capacity: 4), [[]])

        let entries = (0..<9).map { LaunchpadEntry.app(app("App\($0)")) }
        let pages = LayoutEngine.paginate(entries, capacity: 4)
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages.map(\.count), [4, 4, 1])
    }

    func testNormalizeDropsRemovedAppsAndAppendsNewAppsAlphabetically() {
        let a = app("Alpha")
        let b = app("Bravo")
        let c = app("Charlie")
        let d = app("Delta")
        let e = app("Echo")
        let missing = app("Missing")

        let pages: [PageLayout] = [
            [.app(b), .app(missing)],
            [.app(d)]
        ]

        let normalized = LayoutEngine.normalize(
            pages: pages,
            discovered: [a, b, c, d, e],
            capacity: 2
        )

        XCTAssertEqual(normalized.map { $0.map(\.displayName) }, [["Bravo"], ["Delta", "Alpha"], ["Charlie", "Echo"]])
        XCTAssertFalse(LayoutEngine.flatten(normalized).contains { $0.displayName == "Missing" })
    }

    func testNormalizeDissolvesSingleAppFolderAndReleasesApp() {
        let a = app("Alpha")
        let b = app("Bravo")
        let folder = FolderItem(name: "Tools", apps: [a])
        let pages: [PageLayout] = [[.folder(folder)]]

        let normalized = LayoutEngine.normalize(pages: pages, discovered: [a, b], capacity: 4)
        XCTAssertEqual(normalized, [[.app(a), .app(b)]])
    }

    func testNormalizeKeepsFolderWithTwoSurvivingApps() {
        let a = app("Alpha")
        let b = app("Bravo")
        let folder = FolderItem(name: "Tools", apps: [a, b])
        let normalized = LayoutEngine.normalize(
            pages: [[.folder(folder)]],
            discovered: [a, b],
            capacity: 4
        )

        guard case .folder(let result) = normalized[0][0] else {
            return XCTFail("Expected folder")
        }
        XCTAssertEqual(result.name, "Tools")
        XCTAssertEqual(result.apps.map(\.name), ["Alpha", "Bravo"])
    }

    func testNormalizeRepaginatesWhenCapacityShrinks() {
        let apps = (0..<6).map { app("App\($0)") }
        let pages: [PageLayout] = [apps.map(LaunchpadEntry.app)]

        let normalized = LayoutEngine.normalize(pages: pages, discovered: apps, capacity: 4)
        XCTAssertEqual(normalized.map(\.count), [4, 2])
    }

    func testFolderMergeRules() {
        let a = app("Alpha")
        let b = app("Bravo")

        XCTAssertNil(LayoutEngine.makeFolder(apps: [a]))
        XCTAssertEqual(LayoutEngine.makeFolder(apps: [a, b])?.apps.count, 2)
        XCTAssertNil(LayoutEngine.makeFolder(apps: [a, a]))

        let folder = LayoutEngine.makeFolder(apps: [a, b])!
        let withDuplicate = LayoutEngine.folder(folder, adding: a)
        XCTAssertEqual(withDuplicate.apps.count, 2)
        XCTAssertEqual(withDuplicate.apps.map(\.name), ["Alpha", "Bravo"])
    }

    func testFolderHonorsMaximumAppCount() {
        let apps = (0..<120).map { app("App\($0)") }
        let folder = LayoutEngine.makeFolder(apps: apps)
        XCTAssertEqual(folder?.apps.count, FolderItem.maximumAppCount)

        let full = folder!
        let extra = app("Extra")
        XCTAssertEqual(LayoutEngine.folder(full, adding: extra).apps.count, FolderItem.maximumAppCount)
    }

    func testFolderDissolvesWhenFewerThanTwoAppsRemain() {
        let a = app("Alpha")
        let b = app("Bravo")
        let c = app("Charlie")
        let folder = FolderItem(name: "Tools", apps: [a, b, c])

        guard case .folder(let two) = LayoutEngine.folder(folder, removingAppID: a.id) else {
            return XCTFail("Expected folder with two apps")
        }
        XCTAssertEqual(two.apps.map(\.name), ["Bravo", "Charlie"])

        guard case .dissolved(let released) = LayoutEngine.folder(two, removingAppID: b.id) else {
            return XCTFail("Expected folder to dissolve")
        }
        XCTAssertEqual(released.map(\.name), ["Charlie"])

        let single = FolderItem(name: "Tools", apps: [a])
        XCTAssertEqual(LayoutEngine.update(for: single), .dissolved([a]))
        XCTAssertEqual(LayoutEngine.update(for: FolderItem(name: "Empty")), .empty)
    }

    func testInsertAndRemoveMaintainOrder() {
        let a = app("Alpha")
        let b = app("Bravo")
        let c = app("Charlie")
        var pages: [PageLayout] = [[.app(a), .app(b)]]

        LayoutEngine.insert(.app(c), at: 0, index: 1, in: &pages, capacity: 4)
        XCTAssertEqual(pages[0].map(\.displayName), ["Alpha", "Charlie", "Bravo"])

        let removed = LayoutEngine.remove(entryID: LaunchpadEntry.app(c).id, from: &pages)
        XCTAssertEqual(removed?.displayName, "Charlie")
        XCTAssertEqual(pages[0].map(\.displayName), ["Alpha", "Bravo"])
    }

    /// A moved app is either placed somewhere by the caller or consumed by a
    /// folder. Returning it here made callers append a second copy after a
    /// folder merge or creation.
    func testRemoveAppDoesNotReturnTheTopLevelAppItRemoved() {
        let a = app("Alpha")
        let b = app("Bravo")
        var pages: [[LaunchpadEntry]] = [[.app(a), .app(b)]]

        let released = LayoutEngine.removeApp(appID: a.id, from: &pages)

        XCTAssertTrue(released.isEmpty)
        XCTAssertEqual(pages[0].map(\.displayName), ["Bravo"])
    }

    /// Dissolving a folder is the one case that does return apps: the survivor
    /// must be re-inserted into the grid by the caller.
    func testRemoveAppFromFolderReturnsOnlyDissolvedSurvivors() {
        let a = app("Alpha")
        let b = app("Bravo")
        let folder = FolderItem(name: "Tools", apps: [a, b])
        var pages: [[LaunchpadEntry]] = [[.folder(folder)]]

        let released = LayoutEngine.removeApp(appID: a.id, from: &pages)

        XCTAssertEqual(released, [.app(b)])
        XCTAssertTrue(pages[0].isEmpty)
    }

    func testInsertOverflowCreatesNextPage() {
        let apps = (0..<4).map { app("App\($0)") }
        let extra = app("Extra")
        var pages: [PageLayout] = [apps.map(LaunchpadEntry.app)]

        LayoutEngine.insert(.app(extra), at: 0, index: 4, in: &pages, capacity: 4)
        XCTAssertEqual(pages.map(\.count), [4, 1])
        XCTAssertEqual(pages[1].first?.displayName, "Extra")
    }
}

final class PageDragGeometryTests: XCTestCase {
    func testDragIsClampedToOnePageWidth() {
        XCTAssertEqual(
            PageDragGeometry.boundedOffset(translation: -3000, page: 1, pageCount: 3, width: 1000),
            -1000
        )
        XCTAssertEqual(
            PageDragGeometry.boundedOffset(translation: 3000, page: 1, pageCount: 3, width: 1000),
            1000
        )
    }

    func testFirstAndLastPageApplyRubberBandResistance() {
        let resistance = Metrics.rubberBandResistance
        XCTAssertEqual(
            PageDragGeometry.boundedOffset(translation: 200, page: 0, pageCount: 3, width: 1000),
            200 * resistance
        )
        XCTAssertEqual(
            PageDragGeometry.boundedOffset(translation: -200, page: 2, pageCount: 3, width: 1000),
            -200 * resistance
        )
        // Moving toward an existing neighbour is not resisted.
        XCTAssertEqual(
            PageDragGeometry.boundedOffset(translation: -200, page: 0, pageCount: 3, width: 1000),
            -200
        )
    }

    func testDistanceCommitMovesOnePage() {
        XCTAssertEqual(
            PageDragGeometry.targetPage(from: 1, translation: -300, velocity: 0, pageCount: 3, width: 1000),
            2
        )
        XCTAssertEqual(
            PageDragGeometry.targetPage(from: 1, translation: 300, velocity: 0, pageCount: 3, width: 1000),
            0
        )
        XCTAssertEqual(
            PageDragGeometry.targetPage(from: 1, translation: -100, velocity: 0, pageCount: 3, width: 1000),
            1
        )
    }

    func testVelocityCommitMovesOnePage() {
        XCTAssertEqual(
            PageDragGeometry.targetPage(from: 1, translation: -10, velocity: -600, pageCount: 3, width: 1000),
            2
        )
        XCTAssertEqual(
            PageDragGeometry.targetPage(from: 1, translation: 10, velocity: 600, pageCount: 3, width: 1000),
            0
        )
    }

    func testCommitStopsAtFirstAndLastPage() {
        XCTAssertEqual(
            PageDragGeometry.targetPage(from: 0, translation: 600, velocity: 0, pageCount: 3, width: 1000),
            0
        )
        XCTAssertEqual(
            PageDragGeometry.targetPage(from: 2, translation: -600, velocity: 0, pageCount: 3, width: 1000),
            2
        )
        XCTAssertEqual(
            PageDragGeometry.targetPage(from: 0, translation: -600, velocity: 0, pageCount: 1, width: 1000),
            0
        )
    }
}

final class LayoutStoreTests: XCTestCase {
    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchpadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("layout.json")
    }

    private func app(_ name: String) -> AppItem {
        AppItem(
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            isSystemApp: false,
            bundleIdentifier: "com.example.\(name.lowercased())",
            version: "1.2"
        )
    }

    func testJSONRoundTripIncludesFolders() async throws {
        let url = try temporaryURL()
        let store = LayoutStore(fileURL: url)
        let pages: [PageLayout] = [
            [.app(app("Alpha")), .folder(FolderItem(name: "Tools", apps: [app("Bravo"), app("Charlie")]))],
            [.app(app("Delta"))]
        ]

        try await store.saveImmediately(pages)
        let loaded = await store.load()
        XCTAssertEqual(loaded, pages)
    }

    func testDebouncedSaveWritesEventually() async throws {
        let url = try temporaryURL()
        let store = LayoutStore(fileURL: url)
        await store.save([[.app(app("Echo"))]])

        try await Task.sleep(nanoseconds: 800_000_000)
        let loaded = await store.load()
        XCTAssertEqual(loaded.map { $0.map(\.displayName) }, [["Echo"]])
    }

    func testCorruptFileLoadsAsEmptyLayout() async throws {
        let url = try temporaryURL()
        try Data("not json".utf8).write(to: url)
        let store = LayoutStore(fileURL: url)

        let loaded = await store.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testMissingFileLoadsAsEmptyLayout() async throws {
        let url = try temporaryURL()
        let store = LayoutStore(fileURL: url)
        let loaded = await store.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testLayoutDocumentUsesStableJSONShape() async throws {
        let url = try temporaryURL()
        let store = LayoutStore(fileURL: url)
        try await store.saveImmediately([[.app(app("Alpha"))]])

        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["version"])
        XCTAssertNotNil(object?["pages"])
        XCTAssertFalse(data.isEmpty)
    }
}

final class LayoutMetricsTests: XCTestCase {
    private let screen = CGSize(width: 1440, height: 900)

    private func settings(iconSize: Double = 100, labelFontSize: Double = 12) -> AppSettings {
        AppSettings(
            columns: 7,
            rows: 5,
            iconSize: iconSize,
            labelFontSize: labelFontSize,
            showOnAllDisplays: false,
            hotCorner: .bottomRight,
            shortcut: .launchpadDefault,
            launchAtLogin: false
        )
    }

    /// The preferences slider caps at `maximumIconSize`; at that value the
    /// rendered icon is already as large as the cell and label allow, so a
    /// larger request must not change the result.
    func testMaximumIconSizeIsWhereTheRenderedIconStopsGrowing() {
        let probe = LayoutMetrics(screenSize: screen, settings: settings(iconSize: 128))
        let atMax = LayoutMetrics(screenSize: screen, settings: settings(iconSize: probe.maximumIconSize))
        let aboveMax = LayoutMetrics(screenSize: screen, settings: settings(iconSize: 128))

        XCTAssertEqual(atMax.iconSize, atMax.maximumIconSize, accuracy: 0.001)
        XCTAssertEqual(aboveMax.iconSize, atMax.iconSize, accuracy: 0.001)
    }

    func testRequestedSizesBelowTheMaximumStillChangeTheIcon() {
        let atMax = LayoutMetrics(screenSize: screen, settings: settings(iconSize: 100))
        let smaller = LayoutMetrics(screenSize: screen, settings: settings(iconSize: 80))

        XCTAssertEqual(smaller.iconSize, 80, accuracy: 0.001)
        XCTAssertLessThan(smaller.iconSize, atMax.iconSize)
    }

    /// With single-line labels the 32 pt vertical gap binds before the label
    /// block does, so the label size changes the block height without changing
    /// the icon cap at this reference size.
    func testLabelBlockHeightTracksLabelSize() {
        let normal = LayoutMetrics(screenSize: screen, settings: settings(labelFontSize: 12))
        let large = LayoutMetrics(screenSize: screen, settings: settings(labelFontSize: 15))

        XCTAssertGreaterThan(large.labelBlockHeight, normal.labelBlockHeight)
        XCTAssertEqual(large.maximumIconSize, normal.maximumIconSize, accuracy: 0.001)
        XCTAssertGreaterThan(large.itemBlockHeight, normal.itemBlockHeight)
    }
}

/// Ratios for the macOS 26 full-bleed launcher: a 7 x 5 grid that runs nearly
/// edge to edge, an icon near 5.6% of the screen width, and a search pill and
/// page-dot row that stay clear of the grid.
final class FullScreenLayoutTests: XCTestCase {
    private let screens = [
        CGSize(width: 1440, height: 900),
        CGSize(width: 1920, height: 1200)
    ]

    func testCellAndIconRatiosMatchTheTargetAtBothReferenceSizes() {
        for screen in screens {
            let metrics = LayoutMetrics(screenSize: screen, settings: .default)
            let cellWidthRatio = metrics.cellWidth / screen.width
            let cellHeightRatio = metrics.cellHeight / screen.height
            let iconRatio = metrics.iconSize / screen.width

            print(String(
                format: "LAYOUT %.0fx%.0f cellWidth=%.4f cellHeight=%.4f icon=%.4f iconPt=%.2f",
                screen.width,
                screen.height,
                cellWidthRatio,
                cellHeightRatio,
                iconRatio,
                metrics.iconSize
            ))

            XCTAssertEqual(cellWidthRatio, 0.132, accuracy: 0.015)
            XCTAssertEqual(cellHeightRatio, 0.165, accuracy: 0.015)
            XCTAssertEqual(iconRatio, 0.056, accuracy: 0.006)
        }
    }

    func testAllIconFramesStayInsideTheScreen() {
        for screen in screens {
            let metrics = LayoutMetrics(screenSize: screen, settings: .default)
            let bounds = CGRect(origin: .zero, size: screen)

            for index in 0..<(metrics.columns * metrics.rows) {
                let frame = metrics.iconFrame(at: index)
                XCTAssertTrue(
                    bounds.contains(frame),
                    "Icon \(index) at \(frame) left the \(screen) screen"
                )
            }
        }
    }

    func testSearchPillAndPageDotsDoNotOverlapTheGrid() {
        for screen in screens {
            let metrics = LayoutMetrics(screenSize: screen, settings: .default)

            let searchRect = CGRect(
                x: (screen.width - metrics.searchSize.width) / 2,
                y: metrics.searchTopOffset,
                width: metrics.searchSize.width,
                height: metrics.searchSize.height
            )
            let dotDiameter = Metrics.pageDotDiameter * metrics.scale
            let dotRow = CGRect(
                x: 0,
                y: metrics.pageDotCenterY - dotDiameter / 2,
                width: screen.width,
                height: dotDiameter
            )

            XCTAssertFalse(
                searchRect.intersects(metrics.gridRect),
                "Search pill \(searchRect) overlaps grid \(metrics.gridRect) at \(screen)"
            )
            XCTAssertFalse(
                dotRow.intersects(metrics.gridRect),
                "Page dots \(dotRow) overlap grid \(metrics.gridRect) at \(screen)"
            )
            XCTAssertLessThan(metrics.gridRect.maxY, metrics.pageDotCenterY)
        }
    }
}

final class AppSettingsTests: XCTestCase {
    private func settings(labelFontSize: Double) -> AppSettings {
        AppSettings(
            columns: 7,
            rows: 5,
            iconSize: 96,
            labelFontSize: labelFontSize,
            showOnAllDisplays: false,
            hotCorner: .bottomRight,
            shortcut: .launchpadDefault,
            launchAtLogin: false
        )
    }

    func testLabelFontSizeIsClamped() {
        XCTAssertEqual(settings(labelFontSize: 4).labelFontSize, 6, accuracy: 0.0001)
        XCTAssertEqual(settings(labelFontSize: 20).labelFontSize, 15, accuracy: 0.0001)
    }

    func testDefaultIconSizeMatchesTheFullBleedMetric() {
        XCTAssertEqual(AppSettings.default.iconSize, Double(Metrics.defaultIconSize))
        XCTAssertEqual(AppSettings.default.iconSize, 81, accuracy: 0.0001)
    }

    /// Settings written before the backdrop sliders were removed still carry
    /// `blurIntensity` and `transparency`. Unknown keys must be ignored rather
    /// than failing the decode.
    func testLegacyBackdropKeysAreIgnored() throws {
        let encoded = try JSONEncoder().encode(AppSettings.default)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["blurIntensity"] = 0.85
        object["transparency"] = 0.4
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertEqual(decoded, AppSettings.default)
    }
}
