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

@MainActor
struct AppModelEditingTests {
    private func makeModel(apps: [AppItem]) -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchpadTests-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(catalog: AppCatalog(apps: apps), store: LayoutStore(directory: directory))
        model.reconcile()
        return model
    }

    @Test
    func reconcileBuildsTheGridFromTheCatalog() {
        let model = makeModel(apps: [makeApp("Alpha"), makeApp("Bravo")])

        #expect(model.items.count == 2)
        #expect(model.pageCount == 1)
    }

    @Test
    func editingTogglesAndClearsSearch() {
        let model = makeModel(apps: [makeApp("Alpha")])
        model.beginSearch(with: "a")

        model.beginEditing()
        #expect(model.isEditing)
        #expect(!model.isSearching)

        model.endEditing()
        #expect(!model.isEditing)
    }

    @Test
    func dropOnIconCreatesAFolderHoldingBothApps() {
        let alpha = makeApp("Alpha")
        let bravo = makeApp("Bravo")
        let model = makeModel(apps: [alpha, bravo])

        let first = model.items[0].id
        model.performDrop(itemID: first, slot: 1, ontoIcon: true)

        #expect(model.items.count == 1)
        #expect(model.items[0].folder?.appIDs == [bravo.id, alpha.id])
    }

    @Test
    func dropOutsideAnIconReordersInstead() {
        let model = makeModel(apps: [makeApp("Alpha"), makeApp("Bravo"), makeApp("Charlie")])
        let first = model.items[0].id

        model.performDrop(itemID: first, slot: 2, ontoIcon: false)

        #expect(model.items[2] == .app(model.appsByID.values.first { $0.name == "Alpha" }!.id))
    }

    @Test
    func appendingTypedCharactersExtendsTheQuery() {
        let model = makeModel(apps: [makeApp("Calendar"), makeApp("Calculator")])

        model.beginSearch(with: "c")
        model.appendToSearch("a")
        model.appendToSearch("l")

        #expect(model.searchQuery == "cal")
        #expect(model.searchResults.map(\.name) == ["Calculator", "Calendar"])
        #expect(model.searchSelection == 0)
    }

    @Test
    func appendingWithoutAnActiveSearchStartsOne() {
        let model = makeModel(apps: [makeApp("Calendar")])

        model.appendToSearch("cal")

        #expect(model.searchQuery == "cal")
    }

    @Test
    func deletingShortensTheQueryAndClearsTheSelection() {
        let model = makeModel(apps: [makeApp("Calendar"), makeApp("Calculator")])
        model.beginSearch(with: "cal")
        model.moveSearchSelection(by: 1)

        model.deleteLastSearchCharacter()

        #expect(model.searchQuery == "ca")
        #expect(model.searchSelection == 0)
    }

    @Test
    func deletingTheLastCharacterEndsTheSearch() {
        let model = makeModel(apps: [makeApp("Calendar")])
        model.beginSearch(with: "c")

        model.deleteLastSearchCharacter()

        #expect(!model.isSearching)
    }

    @Test
    func searchSelectionStaysInRange() {
        let model = makeModel(apps: [makeApp("Calendar"), makeApp("Calculator"), makeApp("Chess")])
        model.beginSearch(with: "cal")

        #expect(model.searchResults.count == 2)
        model.moveSearchSelection(by: -5)
        #expect(model.searchSelection == 0)
        model.moveSearchSelection(by: 1)
        #expect(model.searchSelection == 1)
        model.moveSearchSelection(by: 9)
        #expect(model.searchSelection == 1)
        #expect(model.selectedSearchResult?.name == model.searchResults[1].name)
    }

    @Test
    func layoutIsPersistedBetweenModels() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchpadPersist-\(UUID().uuidString)", isDirectory: true)
        let store = LayoutStore(directory: directory)
        let apps = [makeApp("Alpha"), makeApp("Bravo"), makeApp("Charlie")]

        let first = AppModel(catalog: AppCatalog(apps: apps), store: store)
        first.reconcile()
        let alphaID = first.items[0].id
        first.performDrop(itemID: alphaID, slot: 2, ontoIcon: false)

        let second = AppModel(catalog: AppCatalog(apps: apps), store: store)
        second.reconcile()

        #expect(second.items.map(\.id) == first.items.map(\.id))
    }

    @Test
    func draggingAnAppOutOfAFolderPlacesItOnTheGrid() {
        let alpha = makeApp("Alpha")
        let bravo = makeApp("Bravo")
        let charlie = makeApp("Charlie")
        let model = makeModel(apps: [alpha, bravo, charlie])

        let alphaItemID = model.items[0].id
        model.performDrop(itemID: alphaItemID, slot: 1, ontoIcon: true)
        #expect(model.items.count == 2)
        #expect(model.items[0].folder?.appIDs.count == 2)

        model.moveAppOutOfFolder(appID: alpha.id, toSlot: 2)

        #expect(model.items.count == 3)
        #expect(model.items[0].appIDs == [bravo.id])
        #expect(model.items[2].appIDs == [alpha.id])
    }

    @Test
    func draggingOutOfAThreeAppFolderKeepsTheFolder() {
        let apps = ["Alpha", "Bravo", "Charlie", "Delta"].map { makeApp($0) }
        let model = makeModel(apps: apps)

        model.performDrop(itemID: model.items[0].id, slot: 1, ontoIcon: true)
        model.performDrop(itemID: model.items[1].id, slot: 0, ontoIcon: true)
        #expect(model.items[0].folder?.appIDs.count == 3)

        model.moveAppOutOfFolder(appID: apps[0].id, toSlot: 1)

        #expect(model.items.count == 3)
        #expect(model.items[0].folder?.appIDs == [apps[1].id, apps[2].id])
        #expect(model.items[1].appIDs == [apps[0].id])
    }

    @Test
    func removingAnAppAlsoUpdatesThePersistedLayout() {
        let apps = [makeApp("Alpha"), makeApp("Bravo")]
        let model = makeModel(apps: apps)

        model.remove(appID: apps[0].id)

        #expect(model.items.count == 1)
        #expect(model.items[0].appIDs == [apps[1].id])
    }
}
