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

    /// A point inside an item's dwell halo but outside its immediate icon
    /// zone: the boundary where a quick drop reorders and a hold merges.
    private func haloDropPoint(for index: Int, metrics: LayoutMetrics) -> CGPoint {
        let icon = metrics.iconFrame(at: index)
        let direct = metrics.mergeFrame(at: index)
        let halo = metrics.mergeHaloFrame(at: index)
        let y = min(halo.maxY - 1, direct.maxY + (halo.maxY - direct.maxY) / 2)
        return CGPoint(x: icon.midX, y: y)
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
        // Aim at the cell, not the icon: dropping directly on an app now
        // merges into a folder, so a reorder drop targets the surrounding gap.
        let cell = metrics.cellRect(at: 1)
        viewModel.updateDrag(location: CGPoint(x: cell.minX + 4, y: cell.midY))

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

        // Crossing into another cell still updates the projected layout. Aim
        // at the cell rather than the icon, since hovering an icon suppresses
        // the reorder preview in favour of a folder merge.
        let targetCell = metrics.cellRect(at: 7)
        viewModel.updateDrag(location: CGPoint(x: targetCell.minX + 4, y: targetCell.midY))
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

    func testDroppingAnAppOnAFolderMovesItInsideWithoutDuplicatingIt() {
        let viewModel = makeViewModel()
        let alpha = app("Alpha")
        let bravo = app("Bravo")
        let charlie = app("Charlie")
        let folder = FolderItem(name: "Tools", apps: [alpha, bravo])
        viewModel.seedLayoutForTesting([[.folder(folder), .app(charlie)]], page: 0)

        viewModel.beginDrag(entry: .app(charlie), page: 0, index: 1)
        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        viewModel.updateDrag(location: metrics.iconCenter(at: 0))

        XCTAssertEqual(viewModel.dragSession?.hoveredEntryID, LaunchpadEntry.folder(folder).id)
        XCTAssertNil(viewModel.reorderPreview, "a merge target hides the reflow preview")

        viewModel.endDrag()

        XCTAssertEqual(viewModel.pages.count, 1)
        XCTAssertEqual(viewModel.pages[0].count, 1)
        guard case .folder(let updated) = viewModel.pages[0][0] else {
            return XCTFail("Expected the folder to remain")
        }
        XCTAssertEqual(updated.apps.map(\.name), ["Alpha", "Bravo", "Charlie"])
        XCTAssertFalse(
            LayoutEngine.flatten(viewModel.pages).contains(.app(charlie)),
            "the dragged app must not also remain on the grid"
        )
    }

    func testDroppingAnAppOnAnotherCreatesAndOpensAFolder() {
        let viewModel = makeViewModel()
        let alpha = app("Alpha")
        let bravo = app("Bravo")
        let charlie = app("Charlie")
        viewModel.seedLayoutForTesting([[.app(alpha), .app(bravo), .app(charlie)]], page: 0)

        viewModel.beginDrag(entry: .app(alpha), page: 0, index: 0)
        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        // Drop immediately, without waiting for the dwell arm: macOS creates
        // the folder as soon as an app is released over another app.
        viewModel.updateDrag(location: metrics.iconCenter(at: 1))

        XCTAssertEqual(viewModel.dragSession?.hoveredEntryID, LaunchpadEntry.app(bravo).id)
        XCTAssertNil(viewModel.reorderPreview, "the merge target stays under the cursor")

        viewModel.endDrag()

        XCTAssertEqual(viewModel.pages.count, 1)
        XCTAssertEqual(viewModel.pages[0].count, 2)
        guard case .folder(let folder) = viewModel.pages[0][0] else {
            return XCTFail("Expected a folder in the target slot")
        }
        XCTAssertEqual(folder.name, FolderItem.defaultName)
        XCTAssertEqual(Set(folder.apps.map(\.name)), ["Alpha", "Bravo"])
        XCTAssertEqual(viewModel.pages[0][1], .app(charlie))

        let topLevel = LayoutEngine.flatten(viewModel.pages)
        XCTAssertFalse(topLevel.contains(.app(alpha)))
        XCTAssertFalse(topLevel.contains(.app(bravo)))

        // The panel is inserted collapsed and asks the view model to present it
        // once its first frame has been committed, so presentation is explicit
        // rather than racing the layout pass.
        XCTAssertEqual(viewModel.openFolderID, folder.id)
        XCTAssertFalse(viewModel.folderIsPresented)
        XCTAssertTrue(viewModel.folderTitleEditing)
        XCTAssertEqual(viewModel.folderTitleDraft, FolderItem.defaultName)

        viewModel.presentFolder()
        XCTAssertTrue(viewModel.folderIsPresented)
    }

    /// The direct merge zone covers the icon plus a small margin. Aiming near
    /// the edge of an icon must still create a folder; the old half-icon-radius
    /// circle only accepted drops near the exact centre.
    func testHoveringTheEdgeOfAnAppStillCreatesAFolder() {
        let viewModel = makeViewModel()
        let alpha = app("Alpha")
        let bravo = app("Bravo")
        let charlie = app("Charlie")
        viewModel.seedLayoutForTesting([[.app(alpha), .app(bravo), .app(charlie)]], page: 0)

        viewModel.beginDrag(entry: .app(alpha), page: 0, index: 0)
        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        let center = metrics.iconCenter(at: 1)
        // Just outside the old 50% engage radius, inside the direct icon zone.
        let hover = CGPoint(x: center.x + metrics.iconSize * 0.58, y: center.y)
        XCTAssertTrue(metrics.mergeFrame(at: 1).contains(hover))

        viewModel.updateDrag(location: hover)

        XCTAssertEqual(viewModel.dragSession?.hoveredEntryID, LaunchpadEntry.app(bravo).id)
        XCTAssertNil(viewModel.reorderPreview, "the merge target stays under the cursor")

        viewModel.endDrag()

        guard case .folder(let folder) = viewModel.pages[0].first else {
            return XCTFail("Expected the edge hover to create a folder")
        }
        XCTAssertEqual(Set(folder.apps.map(\.name)), ["Alpha", "Bravo"])
    }

    /// The hover affordance is a folder preview, not a ring or an empty folder
    /// shape. It shows only the app already in the target: the dragged app is
    /// drawn by the floating drag preview, so repeating it inside the folder
    /// would show the same icon twice.
    func testHoveringAnAppPreviewsTheFolderWithTheTargetApp() {
        let viewModel = makeViewModel()
        let alpha = app("Alpha")
        let bravo = app("Bravo")
        let charlie = app("Charlie")
        viewModel.seedLayoutForTesting([[.app(alpha), .app(bravo), .app(charlie)]], page: 0)

        viewModel.beginDrag(entry: .app(alpha), page: 0, index: 0)
        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        viewModel.updateDrag(location: metrics.iconCenter(at: 1))

        let preview = viewModel.mergePreviewApps(for: .app(bravo))
        XCTAssertEqual(preview?.map(\.name), ["Bravo"])
        XCTAssertNil(
            viewModel.mergePreviewApps(for: .app(charlie)),
            "only the hovered target should render a folder preview"
        )

        viewModel.endDrag()
        XCTAssertNil(viewModel.mergePreviewApps(for: .app(bravo)))
    }

    /// Dropping into an existing folder previews its current contents. The
    /// incoming app floats above the folder, so it is not repeated inside.
    func testHoveringAFolderPreviewsItsCurrentContents() {
        let viewModel = makeViewModel()
        let alpha = app("Alpha")
        let bravo = app("Bravo")
        let charlie = app("Charlie")
        let folder = FolderItem(name: "Tools", apps: [alpha, bravo])
        viewModel.seedLayoutForTesting([[.folder(folder), .app(charlie)]], page: 0)

        viewModel.beginDrag(entry: .app(charlie), page: 0, index: 1)
        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        viewModel.updateDrag(location: metrics.iconCenter(at: 0))

        let preview = viewModel.mergePreviewApps(for: .folder(folder))
        XCTAssertEqual(preview?.map(\.name), ["Alpha", "Bravo"])
    }

    /// The merge zone must not swallow the whole cell: the gap between icons is
    /// still a reorder target, and the target does not shift while approaching
    /// from that gap.
    func testHoveringTheGapBetweenIconsKeepsTheReorderPreview() {
        let viewModel = makeViewModel()
        let apps = (0..<22).map { app("Item\($0)") }
        let layout = LayoutEngine.paginate(
            apps.map(LaunchpadEntry.app),
            capacity: viewModel.settings.pageCapacity
        )
        viewModel.seedLayoutForTesting(layout, page: 0)
        viewModel.beginDrag(entry: .app(apps[0]), page: 0, index: 0)

        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        let cell = metrics.cellRect(at: 4)
        let gap = CGPoint(x: cell.minX + 4, y: cell.midY)
        XCTAssertFalse(metrics.mergeFrame(at: 4).contains(gap))

        viewModel.updateDrag(location: gap)

        XCTAssertNil(viewModel.dragSession?.hoveredEntryID)
        XCTAssertNotNil(viewModel.reorderPreview)
        XCTAssertEqual(
            viewModel.reorderPreview?.locations[viewModel.dragSession!.entry.id],
            .init(page: 0, index: 4)
        )
    }

    /// A quick drop in the wider halo still reorders. Only a deliberate pause
    /// there should turn into folder creation.
    func testQuickDropOnAFolderLabelStillReorders() {
        let viewModel = makeViewModel()
        let alpha = app("Alpha")
        let bravo = app("Bravo")
        let charlie = app("Charlie")
        let folder = FolderItem(name: "Tools", apps: [alpha, bravo])
        viewModel.seedLayoutForTesting([[.folder(folder), .app(charlie)]], page: 0)

        viewModel.beginDrag(entry: .app(charlie), page: 0, index: 1)
        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        let labelDrop = haloDropPoint(for: 0, metrics: metrics)
        XCTAssertFalse(metrics.mergeFrame(at: 0).contains(labelDrop))
        XCTAssertTrue(metrics.mergeHaloFrame(at: 0).contains(labelDrop))

        viewModel.updateDrag(location: labelDrop)

        XCTAssertNil(viewModel.dragSession?.hoveredEntryID)
        XCTAssertEqual(
            viewModel.dragSession?.mergeCandidateID,
            LaunchpadEntry.folder(folder).id,
            "the halo starts a dwell but does not merge yet"
        )
        XCTAssertNil(
            viewModel.dragSession?.mergeHighlightID,
            "a pending dwell must not promise a merge it will not commit"
        )
        XCTAssertNotNil(viewModel.reorderPreview, "a quick halo drop keeps reordering")

        viewModel.endDrag()

        guard case .app(let moved) = viewModel.pages[0].first else {
            return XCTFail("Expected a reorder rather than a merge")
        }
        XCTAssertEqual(moved.id, charlie.id)
        XCTAssertEqual(viewModel.pages[0].last, .folder(folder))
    }

    /// Holding in the halo is the deliberate folder gesture: it arms after the
    /// dwell, hides the reorder preview, and appends on release.
    func testHoldingOnAFolderLabelArmsAndAppendsToTheFolder() async throws {
        let viewModel = makeViewModel()
        let alpha = app("Alpha")
        let bravo = app("Bravo")
        let charlie = app("Charlie")
        let folder = FolderItem(name: "Tools", apps: [alpha, bravo])
        viewModel.seedLayoutForTesting([[.folder(folder), .app(charlie)]], page: 0)

        viewModel.beginDrag(entry: .app(charlie), page: 0, index: 1)
        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        let labelDrop = haloDropPoint(for: 0, metrics: metrics)

        viewModel.updateDrag(location: labelDrop)
        XCTAssertEqual(viewModel.dragSession?.mergeCandidateID, LaunchpadEntry.folder(folder).id)
        XCTAssertNil(viewModel.dragSession?.armedMergeTargetID)
        XCTAssertNil(viewModel.dragSession?.mergeHighlightID)

        try await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(viewModel.dragSession?.armedMergeTargetID, LaunchpadEntry.folder(folder).id)
        XCTAssertEqual(
            viewModel.dragSession?.mergeHighlightID,
            LaunchpadEntry.folder(folder).id,
            "the folder preview appears once the hold is armed"
        )
        XCTAssertNil(viewModel.reorderPreview, "arming returns the target under the pointer")

        viewModel.endDrag()

        guard case .folder(let updated) = viewModel.pages[0].first else {
            return XCTFail("Expected the folder to remain")
        }
        XCTAssertEqual(updated.apps.map(\.name), ["Alpha", "Bravo", "Charlie"])
        XCTAssertEqual(viewModel.pages[0].count, 1)
    }

    // MARK: Folder drag-out

    private func openFolder(_ folder: FolderItem, in viewModel: LaunchpadViewModel) {
        viewModel.openFolder(folder, anchor: .zero)
        viewModel.presentFolder()
    }

    private func dragOut(
        app: AppItem,
        folder: FolderItem,
        sourceIndex: Int,
        to location: CGPoint,
        in viewModel: LaunchpadViewModel
    ) {
        viewModel.beginFolderDrag(app: app, folderID: folder.id, sourceIndex: sourceIndex)
        viewModel.updateFolderDrag(location: location)
        XCTAssertEqual(viewModel.folderDragSession?.isOutside, true)
        viewModel.endFolderDrag()
    }

    /// A point inside `slot` that is also outside the opened folder panel.
    ///
    /// The 7 × 3 panel is large enough to cover the centers of the main grid's
    /// top row, including the drag hysteresis band around its edge. Drag-out
    /// tests therefore aim near the cell's leading edge, where the drop still
    /// resolves to the same slot but the pointer is genuinely over the grid.
    private func outsideDropPoint(
        inSlot slot: Int,
        in viewModel: LaunchpadViewModel
    ) -> CGPoint {
        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        let cell = metrics.cellRect(at: slot)
        // Match the view model's 10-pt hysteresis with a little slack.
        let panel = viewModel.folderPanelFrame().insetBy(dx: -11, dy: -11)
        let candidates = [
            CGPoint(x: cell.midX, y: cell.minY + 4),
            CGPoint(x: cell.minX + 4, y: cell.minY + 4),
            CGPoint(x: cell.maxX - 4, y: cell.minY + 4),
            CGPoint(x: cell.midX, y: cell.maxY - 4)
        ]
        for candidate in candidates
        where metrics.slot(at: candidate) == slot && !panel.contains(candidate) {
            return candidate
        }
        XCTFail("No drop point outside the folder panel for slot \(slot)")
        return CGPoint(x: cell.midX, y: cell.minY + 4)
    }

    func testDraggingAnAppOutOfALargeFolderInsertsItAtTheDropSlot() {
        let viewModel = makeViewModel()
        let alpha = app("Alpha")
        let bravo = app("Bravo")
        let charlie = app("Charlie")
        let folder = FolderItem(name: "Tools", apps: [alpha, bravo, charlie])
        viewModel.seedLayoutForTesting([[.folder(folder), .app(charlie)]])
        openFolder(folder, in: viewModel)

        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        let drop = outsideDropPoint(inSlot: 1, in: viewModel)
        XCTAssertEqual(metrics.slot(at: drop), 1)
        XCTAssertFalse(viewModel.folderPanelFrame().contains(drop))

        dragOut(app: alpha, folder: folder, sourceIndex: 0, to: drop, in: viewModel)

        XCTAssertNil(viewModel.openFolderID)
        XCTAssertEqual(viewModel.pages.count, 1)
        guard case .folder(let updated) = viewModel.pages[0][0] else {
            return XCTFail("The folder should survive while it still has two apps")
        }
        XCTAssertEqual(updated.apps.map(\.name), ["Bravo", "Charlie"])
        XCTAssertEqual(viewModel.pages[0][1], .app(alpha))
        XCTAssertEqual(viewModel.pages[0][2], .app(charlie))
    }

    func testDraggingTheLastAppOutDissolvesTheFolderAndKeepsTheSurvivorInItsSlot() {
        let viewModel = makeViewModel()
        let alpha = app("Alpha")
        let bravo = app("Bravo")
        let charlie = app("Charlie")
        let folder = FolderItem(name: "Tools", apps: [alpha, bravo])
        viewModel.seedLayoutForTesting([[.folder(folder), .app(charlie)]])
        openFolder(folder, in: viewModel)

        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        let drop = outsideDropPoint(inSlot: 3, in: viewModel)
        XCTAssertEqual(metrics.slot(at: drop), 3)

        dragOut(app: alpha, folder: folder, sourceIndex: 0, to: drop, in: viewModel)

        XCTAssertNil(viewModel.openFolderID)
        XCTAssertEqual(viewModel.pages.count, 1)
        XCTAssertEqual(viewModel.pages[0][0], .app(bravo), "the survivor keeps the folder's slot")
        XCTAssertEqual(viewModel.pages[0].count, 3)
        XCTAssertTrue(viewModel.pages[0].contains(.app(alpha)))
        XCTAssertTrue(viewModel.pages[0].contains(.app(charlie)))
        XCTAssertFalse(viewModel.pages[0].contains(where: { $0.folder != nil }))
    }

    func testDroppingOverAMarginSnapsToTheNearestSlotInsteadOfAppending() {
        let viewModel = makeViewModel()
        let alpha = app("Alpha")
        let bravo = app("Bravo")
        let charlie = app("Charlie")
        let folder = FolderItem(name: "Tools", apps: [alpha, bravo, charlie])
        viewModel.seedLayoutForTesting([[.folder(folder), .app(charlie)]])
        openFolder(folder, in: viewModel)

        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        let drop = CGPoint(x: metrics.gridRect.minX + 4, y: metrics.gridRect.minY + 4)
        dragOut(app: alpha, folder: folder, sourceIndex: 0, to: drop, in: viewModel)

        XCTAssertEqual(viewModel.pages[0].first, .app(alpha), "a margin drop snaps to slot zero")
        XCTAssertEqual(viewModel.pages[0].count, 3)
    }

    func testDroppingFromAFolderDoesNotRepaginateOtherPages() {
        let viewModel = makeViewModel()
        let alpha = app("Alpha")
        let bravo = app("Bravo")
        let charlie = app("Charlie")
        let delta = app("Delta")
        let echo = app("Echo")
        let folder = FolderItem(name: "Tools", apps: [alpha, bravo, charlie])
        viewModel.seedLayoutForTesting(
            [[.folder(folder), .app(charlie)], [.app(delta), .app(echo)]],
            page: 0
        )
        openFolder(folder, in: viewModel)

        let metrics = LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        let drop = outsideDropPoint(inSlot: 1, in: viewModel)
        XCTAssertEqual(metrics.slot(at: drop), 1)
        dragOut(
            app: alpha,
            folder: folder,
            sourceIndex: 0,
            to: drop,
            in: viewModel
        )

        XCTAssertEqual(viewModel.pages.count, 2)
        XCTAssertEqual(viewModel.pages[1], [.app(delta), .app(echo)])
    }

    func testOpenFolderWaitsForPresentationAndCloseCancelsAPendingPresent() {
        let viewModel = makeViewModel()
        let folder = FolderItem(name: "Tools", apps: [app("Alpha"), app("Bravo")])
        viewModel.seedLayoutForTesting([[.folder(folder)]])

        viewModel.openFolder(folder, anchor: .zero)
        XCTAssertEqual(viewModel.openFolderID, folder.id)
        XCTAssertFalse(viewModel.folderIsPresented, "opening must not present before the panel exists")

        viewModel.presentFolder()
        XCTAssertTrue(viewModel.folderIsPresented)

        viewModel.closeFolder(animated: false)
        XCTAssertNil(viewModel.openFolderID)
        XCTAssertFalse(viewModel.folderIsPresented)

        // A delayed present from an old panel must not reopen a closed folder.
        viewModel.openFolder(folder, anchor: .zero)
        viewModel.closeFolder(animated: false)
        viewModel.presentFolder()
        XCTAssertNil(viewModel.openFolderID)
        XCTAssertFalse(viewModel.folderIsPresented)
    }

    func testFolderDragPublishesOnlyWhenTheDropStateChanges() {
        let viewModel = makeViewModel()
        let alpha = app("Alpha")
        let bravo = app("Bravo")
        let charlie = app("Charlie")
        let folder = FolderItem(name: "Tools", apps: [alpha, bravo, charlie])
        viewModel.seedLayoutForTesting([[.folder(folder)]])
        openFolder(folder, in: viewModel)
        viewModel.beginFolderDrag(app: alpha, folderID: folder.id, sourceIndex: 0)

        let panel = viewModel.folderPanelFrame()
        let metrics = FolderMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
        let local = CGPoint(x: metrics.cellRect(at: 0).midX, y: metrics.cellRect(at: 0).midY)
        let first = CGPoint(x: panel.minX + local.x, y: panel.minY + local.y)
        viewModel.updateFolderDrag(location: first)

        var changes = 0
        let cancellable = viewModel.$folderDragSession.dropFirst().sink { _ in changes += 1 }

        // Moving inside one slot must not invalidate the overlay.
        viewModel.updateFolderDrag(location: CGPoint(x: first.x + 2, y: first.y + 2))
        XCTAssertEqual(changes, 0)

        // Crossing the panel edge is a discrete state change.
        let outside = CGPoint(x: metrics.gridRect.midX, y: metrics.gridRect.minY + 4)
        viewModel.updateFolderDrag(location: outside)
        XCTAssertEqual(changes, 1)

        // Continuing to move outside must not publish again.
        viewModel.updateFolderDrag(location: CGPoint(x: outside.x + 2, y: outside.y + 2))
        XCTAssertEqual(changes, 1)

        _ = cancellable
    }
}
