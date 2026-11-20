import Foundation
import Testing

@testable import Launchpad

private func makeTransferApp(_ name: String) -> AppItem {
    AppItem(
        bundleIdentifier: "com.test.transfer.\(name)",
        url: URL(fileURLWithPath: "/Applications/\(name).app"),
        name: name
    )
}

@MainActor
struct LayoutTransferTests {
    private func makeModel(apps: [AppItem]) -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchpadTransfer-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(
            catalog: AppCatalog(apps: apps),
            store: LayoutStore(directory: directory)
        )
        model.reconcile()
        return model
    }

    private func makeFolder() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchpadTransfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    @Test
    func exportRoundTripsPagesFoldersAndOrder() throws {
        let apps = ["Alpha", "Bravo", "Charlie"].map(makeTransferApp)
        let model = makeModel(apps: apps)
        model.performDrop(itemID: model.items[0].id, slot: 1, ontoIcon: true)
        model.closeFolder()

        let directory = try makeFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("layout.json")
        try model.exportLayout(to: url)

        let imported = makeModel(apps: apps)
        try imported.importLayout(from: url)

        #expect(imported.layout == model.layout)
    }

    @Test
    func importDropsMissingAppsAndAppendsNewOnes() throws {
        let alpha = makeTransferApp("Alpha")
        let bravo = makeTransferApp("Bravo")
        let charlie = makeTransferApp("Charlie")
        let source = makeModel(apps: [alpha, bravo])

        let directory = try makeFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("layout.json")
        try source.exportLayout(to: url)

        let target = makeModel(apps: [alpha, charlie])
        try target.importLayout(from: url)

        #expect(target.layout.representedAppIDs == Set([alpha.id, charlie.id]))
    }

    @Test
    func malformedFileLeavesTheGridUnchanged() throws {
        let model = makeModel(apps: [makeTransferApp("Alpha")])
        let before = model.layout

        let directory = try makeFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("broken.json")
        try Data("{ not a layout".utf8).write(to: url)

        #expect(throws: LayoutTransferError.self) {
            try model.importLayout(from: url)
        }
        #expect(model.layout == before)
    }
}
