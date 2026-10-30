import AppKit
import XCTest
@testable import Launchpad

@MainActor
final class WindowLayoutTests: XCTestCase {
    private func makeScreen() throws -> NSScreen {
        try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
    }

    private func makeController() -> LaunchpadWindowController {
        LaunchpadWindowController(viewModel: LaunchpadViewModel(), interactive: true)
    }

    /// Windows that did not exist before the controller was built.
    private func windowsAdded(since before: Set<ObjectIdentifier>) -> [NSWindow] {
        let after = Set(NSApp.windows.map(ObjectIdentifier.init))
        let added = after.subtracting(before)
        return NSApp.windows.filter { added.contains(ObjectIdentifier($0)) }
    }

    func testOverlayWindowStopsAtTheDock() throws {
        let screen = try makeScreen()
        let controller = makeController()
        defer { controller.orderOut() }

        controller.updateFrame(screen)

        let reservation = DockReservation.current(for: screen)
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.frame, reservation.interactiveFrame(for: screen))
        XCTAssertEqual(window.frame.maxY, screen.frame.maxY)
        XCTAssertEqual(window.level, WindowLevels.aboveStatusBar)
        XCTAssertEqual(window.level.rawValue, 26)
        XCTAssertEqual(window.title, "Launchpad")
    }

    func testControllerCreatesTheDockBackdropWindows() throws {
        let screen = try makeScreen()
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))

        let controller = makeController()
        defer { controller.orderOut() }
        controller.updateFrame(screen)

        let titles = Set(windowsAdded(since: before).map(\.title))
        let reservation = DockReservation.current(for: screen)

        XCTAssertTrue(titles.contains("Launchpad"))
        XCTAssertEqual(
            titles.contains("Launchpad Dock Background"),
            reservation.backgroundFrame(for: screen) != nil
        )
        XCTAssertEqual(
            titles.contains("Launchpad Menu Bar Patch"),
            reservation.menuBarPatchFrame(for: screen) != nil
        )
    }

    func testDockBackdropSitsBelowTheDockAtTheReservedStrip() throws {
        let screen = try makeScreen()
        let reservation = DockReservation.current(for: screen)
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))

        let controller = makeController()
        defer { controller.orderOut() }
        controller.updateFrame(screen)

        let backgrounds = windowsAdded(since: before)
            .filter { $0.title == "Launchpad Dock Background" }

        guard let expected = reservation.backgroundFrame(for: screen) else {
            XCTAssertTrue(backgrounds.isEmpty)
            return
        }

        let window = try XCTUnwrap(backgrounds.first)
        XCTAssertEqual(window.frame, expected)
        XCTAssertEqual(window.level, WindowLevels.belowDock)
    }

    func testViewportMapsEachWindowOntoItsSliceOfTheScreen() throws {
        let screen = try makeScreen()
        let frame = screen.frame
        let bottom = DockReservation(edge: .bottom, thickness: 90)
        let left = DockReservation(edge: .left, thickness: 90)

        let mainBottom = bottom.interactiveFrame(for: screen)
        XCTAssertEqual(
            bottom.viewport(for: mainBottom, on: screen),
            CGRect(x: 0, y: 0, width: frame.width, height: frame.height - 90)
        )

        let strip = try XCTUnwrap(bottom.backgroundFrame(for: screen))
        XCTAssertEqual(
            bottom.viewport(for: strip, on: screen),
            CGRect(x: 0, y: frame.height - 91, width: frame.width, height: 91)
        )

        let mainLeft = left.interactiveFrame(for: screen)
        XCTAssertEqual(
            left.viewport(for: mainLeft, on: screen),
            CGRect(x: 90, y: 0, width: frame.width - 90, height: frame.height)
        )

        let patch = try XCTUnwrap(left.menuBarPatchFrame(for: screen))
        XCTAssertEqual(
            left.viewport(for: patch, on: screen).origin,
            CGPoint(x: 0, y: 0)
        )
    }

    func testInteractiveFrameUpdatesTheViewModelScreenSize() throws {
        let screen = try makeScreen()
        let viewModel = LaunchpadViewModel()
        let controller = LaunchpadWindowController(viewModel: viewModel, interactive: true)
        defer { controller.orderOut() }

        controller.updateFrame(screen)

        let reservation = DockReservation.current(for: screen)
        XCTAssertEqual(
            viewModel.screenSize,
            reservation.interactiveFrame(for: screen).size
        )
    }
}
