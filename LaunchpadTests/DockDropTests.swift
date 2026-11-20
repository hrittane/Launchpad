import CoreGraphics
import Foundation
import Testing

@testable import Launchpad

struct DockGeometryTests {
    private func bottomDock(
        bar: CGRect? = CGRect(x: 100, y: 0, width: 800, height: 70),
        trash: CGRect? = CGRect(x: 860, y: 5, width: 40, height: 50)
    ) -> DockGeometry {
        DockGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 70, width: 1000, height: 730),
            barRect: bar,
            trashRect: trash,
            tileSize: 64
        )
    }

    @Test
    func reservedStripMatchesTheVisibleFrameGap() {
        let strip = bottomDock().strip
        #expect(strip == CGRect(x: 0, y: 0, width: 1000, height: 70))
    }

    @Test
    func hiddenDockHasNoReservedStrip() {
        let geometry = DockGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            barRect: nil,
            trashRect: nil,
            tileSize: 64
        )
        #expect(geometry.strip == nil)
    }

    @Test
    func barIsAnAddToDockTarget() {
        #expect(bottomDock().target(at: CGPoint(x: 500, y: 35)) == .addToDock)
    }

    @Test
    func trashWinsOverTheBarBehindIt() {
        #expect(bottomDock().target(at: CGPoint(x: 880, y: 30)) == .trash)
    }

    @Test
    func trailingEdgeIsTheTrashWhenAccessibilityIsUnavailable() {
        let geometry = bottomDock(trash: nil)
        #expect(geometry.target(at: CGPoint(x: 875, y: 35)) == .trash)
        #expect(geometry.target(at: CGPoint(x: 300, y: 35)) == .addToDock)
    }

    @Test
    func sideDockPutsTheTrashAtTheBottomOfTheBar() {
        let geometry = DockGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 70, y: 0, width: 930, height: 800),
            barRect: CGRect(x: 0, y: 100, width: 70, height: 600),
            trashRect: nil,
            tileSize: 64
        )
        #expect(geometry.target(at: CGPoint(x: 35, y: 115)) == .trash)
        #expect(geometry.target(at: CGPoint(x: 35, y: 400)) == .addToDock)
    }

    @Test
    func pointsAwayFromTheDockAreNotDrops() {
        #expect(bottomDock().target(at: CGPoint(x: 500, y: 400)) == nil)
        #expect(bottomDock().target(at: CGPoint(x: 20, y: 35)) == nil)

        let hidden = DockGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            barRect: nil,
            trashRect: nil,
            tileSize: 64
        )
        #expect(hidden.target(at: CGPoint(x: 500, y: 10)) == nil)
    }

    @Test
    func reservedStripIsADropTargetWhenTheBarCannotBeFound() {
        // The Dock may be excluded from the window list (or Accessibility may
        // be off), but the visible frame still reserves its strip.
        #expect(bottomDock(bar: nil, trash: nil).target(at: CGPoint(x: 500, y: 10)) == .addToDock)
    }
}

struct DockPinningTests {
    private func makeApp(
        path: String = "/Applications/Dia.app",
        identifier: String? = "com.example.dia"
    ) -> AppItem {
        AppItem(
            bundleIdentifier: identifier,
            url: URL(fileURLWithPath: path, isDirectory: true),
            name: "Dia"
        )
    }

    @Test
    func entryCarriesTheBundleURLAndIdentity() throws {
        let entry = DockPinning.entry(for: makeApp())
        let tile = try #require(entry["tile-data"] as? [String: Any])
        let file = try #require(tile["file-data"] as? [String: Any])

        #expect(entry["tile-type"] as? String == "file-tile")
        #expect(tile["file-label"] as? String == "Dia")
        #expect(tile["file-type"] as? Int == 41)
        #expect(tile["bundle-identifier"] as? String == "com.example.dia")
        #expect(file["_CFURLString"] as? String == "file:///Applications/Dia.app/")
        #expect(file["_CFURLStringType"] as? Int == 15)
    }

    @Test
    func addingIsIdempotent() {
        let app = makeApp()
        let first = DockPinning.adding(app, to: [])
        #expect(first?.count == 1)

        let second = first.flatMap { DockPinning.adding(app, to: $0) }
        #expect(second == nil)
    }

    @Test
    func aDifferentCopyOfTheSameBundleIsAlreadyPinned() {
        let existing = [
            DockPinning.entry(for: makeApp(path: "/System/Applications/Dia.app"))
        ]
        #expect(DockPinning.isPinned(makeApp(), among: existing))
    }

    @Test
    func anUnrelatedDockEntryIsNotPinned() {
        let existing = [
            DockPinning.entry(for: makeApp(path: "/Applications/Other.app", identifier: "com.example.other"))
        ]
        #expect(!DockPinning.isPinned(makeApp(), among: existing))
    }

    @Test
    func malformedEntriesAreIgnored() {
        let existing: [[String: Any]] = [
            [:],
            ["tile-data": "not a dictionary"],
            ["tile-data": ["file-data": ["_CFURLString": "https://example.com"]]]
        ]
        #expect(!DockPinning.isPinned(makeApp(), among: existing))
    }
}
