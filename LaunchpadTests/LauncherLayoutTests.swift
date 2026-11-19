import Foundation
import Testing

@testable import Launchpad

private func makeApp(_ name: String, removable: Bool = false) -> AppItem {
    let root = removable ? "/Applications" : "/System/Applications"
    return AppItem(
        bundleIdentifier: "com.test.\(name.replacingOccurrences(of: " ", with: ""))",
        url: URL(fileURLWithPath: "\(root)/\(name).app"),
        name: name
    )
}

struct LauncherLayoutTests {
    @Test
    func reconcileKeepsOrderAndAppendsNewApps() {
        let a = makeApp("Alpha")
        let b = makeApp("Bravo")
        let c = makeApp("Charlie")

        var layout = LauncherLayout(items: [.app(b.id), .app(a.id)])
        layout.reconcile(with: [c, a, b])

        #expect(layout.items == [.app(b.id), .app(a.id), .app(c.id)])
    }

    @Test
    func reconcileDropsMissingApps() {
        let a = makeApp("Alpha")
        let b = makeApp("Bravo")

        var layout = LauncherLayout(items: [.app(a.id), .app(b.id)])
        layout.reconcile(with: [a])

        #expect(layout.items == [.app(a.id)])
    }

    @Test
    func reconcileCollapsesOneAppFolderBackToTheApp() {
        let a = makeApp("Alpha")
        let b = makeApp("Bravo")
        let folder = AppFolder(name: "Utilities", appIDs: [a.id, b.id])

        var layout = LauncherLayout(items: [.folder(folder)])
        layout.reconcile(with: [a])

        #expect(layout.items == [.app(a.id)])
    }

    @Test
    func reconcileDropsEmptyFolders() {
        let a = makeApp("Alpha")
        let folder = AppFolder(name: "Utilities", appIDs: ["com.gone.App"])

        var layout = LauncherLayout(items: [.folder(folder)])
        layout.reconcile(with: [a])

        #expect(layout.items == [.app(a.id)])
    }

    @Test
    func moveReordersForward() {
        let items: [LauncherItem] = [.app("a"), .app("b"), .app("c"), .app("d")]
        var layout = LauncherLayout(items: items)

        let moved = layout.move(itemID: "app:a", toSlot: 2)
        #expect(moved)
        #expect(layout.items == [.app("b"), .app("c"), .app("a"), .app("d")])
    }

    @Test
    func moveReordersBackward() {
        let items: [LauncherItem] = [.app("a"), .app("b"), .app("c"), .app("d")]
        var layout = LauncherLayout(items: items)

        let moved = layout.move(itemID: "app:d", toSlot: 1)
        #expect(moved)
        #expect(layout.items == [.app("a"), .app("d"), .app("b"), .app("c")])
    }

    @Test
    func movingToTheSameSlotChangesNothing() {
        var layout = LauncherLayout(items: [.app("a"), .app("b")])
        let moved = layout.move(itemID: "app:a", toSlot: 0)
        #expect(!moved)
    }

    @Test
    func dropOnAppCreatesFolderAndRemovesBothSlots() {
        var layout = LauncherLayout(items: [.app("a"), .app("b"), .app("c")])

        let folderID = layout.drop(draggedID: "app:a", onto: "app:b", newFolderName: "Utilities")

        #expect(folderID != nil)
        #expect(layout.items.count == 2)
        #expect(layout.items[0].folder?.name == "Utilities")
        #expect(layout.items[0].folder?.appIDs == ["b", "a"])
        #expect(layout.items[1] == .app("c"))
    }

    @Test
    func dropOnFolderAddsTheAppToIt() {
        let folder = AppFolder(name: "Utilities", appIDs: ["a", "b"])
        var layout = LauncherLayout(items: [.folder(folder), .app("c")])

        let folderID = layout.drop(draggedID: "app:c", onto: "folder:\(folder.id.uuidString)", newFolderName: "Folder")

        #expect(folderID == folder.id)
        #expect(layout.items.count == 1)
        #expect(layout.items[0].folder?.appIDs == ["a", "b", "c"])
    }

    @Test
    func removingAnAppCollapsesATwoAppFolder() {
        let folder = AppFolder(name: "Utilities", appIDs: ["a", "b"])
        var layout = LauncherLayout(items: [.folder(folder)])

        let removed = layout.remove(appID: "a")
        #expect(removed)
        #expect(layout.items == [.app("b")])
    }

    @Test
    func removingTheLastFolderAppRemovesTheFolder() {
        let folder = AppFolder(name: "Utilities", appIDs: ["a"])
        var layout = LauncherLayout(items: [.folder(folder)])

        let removed = layout.remove(appID: "a")
        #expect(removed)
        #expect(layout.items.isEmpty)
    }

    @Test
    func removingATopLevelAppKeepsTheRest() {
        var layout = LauncherLayout(items: [.app("a"), .app("b")])
        let removed = layout.remove(appID: "a")
        #expect(removed)
        #expect(layout.items == [.app("b")])
    }

    @Test
    func renameFolderTrimsWhitespace() {
        let folder = AppFolder(name: "Utilities", appIDs: ["a", "b"])
        var layout = LauncherLayout(items: [.folder(folder)])

        layout.renameFolder(folder.id, to: "  Games  ")
        #expect(layout.folder(withID: folder.id)?.name == "Games")
    }

    @Test
    func renameFolderIgnoresEmptyNames() {
        let folder = AppFolder(name: "Utilities", appIDs: ["a", "b"])
        var layout = LauncherLayout(items: [.folder(folder)])

        layout.renameFolder(folder.id, to: "   ")
        #expect(layout.folder(withID: folder.id)?.name == "Utilities")
    }

    @Test
    func layoutSurvivesCodableRoundTrip() throws {
        let folder = AppFolder(name: "Games", appIDs: ["a", "b"])
        let layout = LauncherLayout(items: [.app("x"), .folder(folder)])

        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(LauncherLayout.self, from: data)

        #expect(decoded == layout)
    }

    @Test
    func decodesLayoutsSavedBeforePagesWereExplicit() throws {
        struct LegacyLayout: Encodable {
            let items: [LauncherItem]
        }

        let data = try JSONEncoder().encode(LegacyLayout(items: [.app("a"), .app("b")]))
        let decoded = try JSONDecoder().decode(LauncherLayout.self, from: data)

        #expect(decoded.items == [.app("a"), .app("b")])
        #expect(decoded.pageCount == 1)
    }

    @Test
    func movingToAnotherPageKeepsBothPagesSparse() {
        var layout = LauncherLayout(pages: [
            [.app("a"), .app("b")],
            [.app("c")]
        ])

        let moved = layout.move(itemID: "app:a", toPage: 1, offset: 1)

        #expect(moved)
        #expect(layout.items(onPage: 0) == [.app("b")])
        #expect(layout.items(onPage: 1) == [.app("c"), .app("a")])
        #expect(layout.pageCount == 2)
    }

    @Test
    func anAppendedPageHoldsASingleIcon() {
        var layout = LauncherLayout(items: [.app("a"), .app("b")])

        let appended = layout.appendEmptyPage()
        #expect(appended)
        #expect(layout.pageCount == 2)

        let moved = layout.move(itemID: "app:a", toPage: 1, offset: 0)
        #expect(moved)
        #expect(layout.items(onPage: 0) == [.app("b")])
        #expect(layout.items(onPage: 1) == [.app("a")])
    }

    @Test
    func trimmingRemovesOnlyEmptyTrailingPages() {
        var layout = LauncherLayout(pages: [
            [.app("a")],
            [.app("b")]
        ])
        let appended = layout.appendEmptyPage()
        #expect(appended)
        #expect(layout.pageCount == 3)

        let trimmed = layout.trimEmptyPages()
        #expect(trimmed)
        #expect(layout.pageCount == 2)
        #expect(layout.items(onPage: 1) == [.app("b")])
    }
}
