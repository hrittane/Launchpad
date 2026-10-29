import Combine
import XCTest
@testable import Launchpad

final class GridReorderTests: XCTestCase {
    private func app(_ name: String) -> AppItem {
        AppItem(
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            isSystemApp: false
        )
    }

    private func entry(_ name: String) -> LaunchpadEntry {
        .app(app(name))
    }

    private func layout(_ names: [String], capacity: Int) -> [PageLayout] {
        LayoutEngine.paginate(names.map(entry), capacity: capacity)
    }

    private func names(_ page: PageLayout) -> [String] {
        page.map(\.displayName)
    }

    func testSamePageForwardMoveLandsOnCursorSlot() {
        let pages = layout(["A", "B", "C", "D", "E", "F"], capacity: 6)
        let preview = GridReorder.preview(
            moving: entry("A").id,
            toPage: 0,
            slot: 3,
            in: pages,
            capacity: 6
        )

        XCTAssertEqual(preview.map { names($0.pages[0]) }, ["B", "C", "D", "A", "E", "F"])
        XCTAssertEqual(preview?.locations[entry("A").id], .init(page: 0, index: 3))
    }

    func testSamePageBackwardMoveLandsOnCursorSlot() {
        let pages = layout(["A", "B", "C", "D", "E", "F"], capacity: 6)
        let preview = GridReorder.preview(
            moving: entry("F").id,
            toPage: 0,
            slot: 1,
            in: pages,
            capacity: 6
        )

        XCTAssertEqual(preview.map { names($0.pages[0]) }, ["A", "F", "B", "C", "D", "E"])
        XCTAssertEqual(preview?.locations[entry("F").id], .init(page: 0, index: 1))
    }

    func testCrossPageForwardLandsExactlyOnCursorSlot() {
        let pages = layout((0..<14).map { "A\($0)" }, capacity: 6)

        for slot in 0..<6 {
            let preview = GridReorder.preview(
                moving: entry("A0").id,
                toPage: 1,
                slot: slot,
                in: pages,
                capacity: 6
            )
            XCTAssertEqual(
                preview?.locations[entry("A0").id],
                .init(page: 1, index: slot),
                "cursor slot \(slot) should place the icon at page 1, slot \(slot)"
            )
        }
    }

    func testCrossPageBackwardLandsExactlyOnCursorSlot() {
        let pages = layout((0..<14).map { "A\($0)" }, capacity: 6)
        let preview = GridReorder.preview(
            moving: entry("A7").id,
            toPage: 0,
            slot: 2,
            in: pages,
            capacity: 6
        )

        XCTAssertEqual(preview?.locations[entry("A7").id], .init(page: 0, index: 2))
        XCTAssertEqual(preview.map { names($0.pages[0]) }, ["A0", "A1", "A7", "A2", "A3", "A4"])
    }

    func testMovingLastItemToFirstPageKeepsPagesTightlyPacked() {
        let pages = layout((0..<13).map { "A\($0)" }, capacity: 6)
        XCTAssertEqual(pages.map(\.count), [6, 6, 1])

        let preview = GridReorder.preview(
            moving: entry("A12").id,
            toPage: 0,
            slot: 0,
            in: pages,
            capacity: 6
        )

        XCTAssertEqual(preview?.pages.map(\.count), [6, 6, 1])
        XCTAssertEqual(preview?.locations[entry("A12").id], .init(page: 0, index: 0))
        XCTAssertEqual(preview.map { names($0.pages[2]) }, ["A11"])
    }

    func testNoOpReturnsTheSamePackedLayout() {
        let pages = layout((0..<14).map { "A\($0)" }, capacity: 6)
        let preview = GridReorder.preview(
            moving: entry("A7").id,
            toPage: 1,
            slot: 1,
            in: pages,
            capacity: 6
        )

        XCTAssertEqual(preview?.pages, pages)
    }

    func testEveryPreviewLocationPointsAtItsEntry() {
        let pages = layout((0..<14).map { "A\($0)" }, capacity: 6)

        for slot in 0..<6 {
            guard let preview = GridReorder.preview(
                moving: entry("A3").id,
                toPage: 1,
                slot: slot,
                in: pages,
                capacity: 6
            ) else {
                return XCTFail("Expected a preview")
            }

            XCTAssertEqual(preview.locations.count, 14)
            for (id, location) in preview.locations {
                XCTAssertEqual(preview.pages[location.page][location.index].id, id)
            }
        }
    }

    func testCursorPastTheEndAppendsToTheLastPage() {
        let pages = layout(["A", "B", "C"], capacity: 6)
        let preview = GridReorder.preview(
            moving: entry("A").id,
            toPage: 0,
            slot: 5,
            in: pages,
            capacity: 6
        )

        XCTAssertEqual(preview.map { names($0.pages[0]) }, ["B", "C", "A"])
        XCTAssertEqual(preview?.locations[entry("A").id], .init(page: 0, index: 2))
    }
}

@MainActor
final class LaunchpadDragCommitTests: XCTestCase {
    private func app(_ name: String) -> AppItem {
        AppItem(
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            isSystemApp: false
        )
    }

    private func makeViewModel() -> LaunchpadViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchpadDragTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let defaults = UserDefaults(suiteName: "LaunchpadDragTests-\(UUID().uuidString)")!
        let viewModel = LaunchpadViewModel(
            scanner: AppScanner(roots: []),
            layoutStore: LayoutStore(fileURL: directory.appendingPathComponent("layout.json")),
            settingsStore: SettingsStore(defaults: defaults, key: "test")
        )
        // Keep the grid small enough that 22 apps span two pages.
        viewModel.settings.columns = 5
        viewModel.settings.rows = 4
        return viewModel
    }

    func testCrossPageDropCommitsExactlyThePreviewedLayout() {
        let viewModel = makeViewModel()
        let apps = (0..<22).map { app("Item\($0)") }
        let capacity = viewModel.settings.pageCapacity
        let layout = LayoutEngine.paginate(apps.map(LaunchpadEntry.app), capacity: capacity)
        XCTAssertEqual(layout.map(\.count), [20, 2])

        // The item starts on page 0 and the user has flipped to page 1.
        viewModel.seedLayoutForTesting(layout, page: 1)
        let dragged = LaunchpadEntry.app(apps[0])
        viewModel.beginDrag(entry: dragged, page: 0, index: 0)

        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        viewModel.updateDrag(location: metrics.iconCenter(at: 1))

        let expected = GridReorder.preview(
            moving: dragged.id,
            toPage: 1,
            slot: 1,
            in: layout,
            capacity: capacity
        )
        XCTAssertEqual(viewModel.reorderPreview?.pages, expected?.pages)
        XCTAssertEqual(viewModel.reorderPreview?.locations[dragged.id], .init(page: 1, index: 1))

        viewModel.endDrag()

        XCTAssertNil(viewModel.reorderPreview)
        XCTAssertEqual(viewModel.pages, expected?.pages)
        XCTAssertEqual(viewModel.pages[1][1], dragged)
    }

    func testCancellingADragLeavesTheLayoutUntouched() {
        let viewModel = makeViewModel()
        let apps = (0..<22).map { app("Item\($0)") }
        let layout = LayoutEngine.paginate(
            apps.map(LaunchpadEntry.app),
            capacity: viewModel.settings.pageCapacity
        )

        viewModel.seedLayoutForTesting(layout, page: 1)
        viewModel.beginDrag(entry: .app(apps[0]), page: 0, index: 0)
        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        viewModel.updateDrag(location: metrics.iconCenter(at: 3))
        viewModel.cancelDrag()

        XCTAssertNil(viewModel.dragSession)
        XCTAssertNil(viewModel.reorderPreview)
        XCTAssertEqual(viewModel.pages, layout)
    }

    /// The drag icon follows the cursor through a dedicated observable, so a
    /// mouse move inside one cell must not invalidate the grid at all.
    func testMovingInsideOneCellDoesNotInvalidateTheGrid() {
        let viewModel = makeViewModel()
        let apps = (0..<22).map { app("Item\($0)") }
        let layout = LayoutEngine.paginate(
            apps.map(LaunchpadEntry.app),
            capacity: viewModel.settings.pageCapacity
        )
        viewModel.seedLayoutForTesting(layout, page: 0)
        viewModel.beginDrag(entry: .app(apps[0]), page: 0, index: 0)

        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        // A point near the bottom edge of the grid is inside one cell but far
        // from every icon centre, so no merge target is hovered.
        let point = CGPoint(x: metrics.gridRect.midX, y: metrics.gridRect.maxY - 2)

        var publishes = 0
        let cancellable = viewModel.objectWillChange.sink { publishes += 1 }
        defer { cancellable.cancel() }

        viewModel.updateDrag(location: point)
        let afterFirstMove = publishes
        XCTAssertGreaterThan(afterFirstMove, 0)

        viewModel.updateDrag(location: CGPoint(x: point.x + 2, y: point.y))
        XCTAssertEqual(publishes, afterFirstMove, "same-cell moves should not re-render the grid")
        XCTAssertEqual(viewModel.itemDrag.location, CGPoint(x: point.x + 2, y: point.y))

        // Crossing into another cell still updates the projected layout.
        viewModel.updateDrag(location: metrics.iconCenter(at: 7))
        XCTAssertGreaterThan(publishes, afterFirstMove)
        XCTAssertEqual(viewModel.reorderPreview?.locations[viewModel.dragSession!.entry.id], .init(page: 0, index: 7))
    }

    func testEndingOrCancellingADragResetsTheCursorPosition() {
        let viewModel = makeViewModel()
        let apps = (0..<22).map { app("Item\($0)") }
        let layout = LayoutEngine.paginate(
            apps.map(LaunchpadEntry.app),
            capacity: viewModel.settings.pageCapacity
        )
        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)

        viewModel.seedLayoutForTesting(layout, page: 0)
        viewModel.beginDrag(entry: .app(apps[0]), page: 0, index: 0)
        viewModel.updateDrag(location: metrics.iconCenter(at: 3))
        viewModel.endDrag()
        XCTAssertEqual(viewModel.itemDrag.location, .zero)

        viewModel.beginDrag(entry: .app(apps[1]), page: 0, index: 1)
        viewModel.updateDrag(location: metrics.iconCenter(at: 5))
        viewModel.cancelDrag()
        XCTAssertEqual(viewModel.itemDrag.location, .zero)
    }
}
