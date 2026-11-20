import Foundation
import Testing

@testable import Launchpad

struct UninstallScannerTests {
    private func makeHome() throws -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LaunchpadUninstall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func makeFile(_ url: URL, bytes: Int = 16) throws {
        try makeDirectory(url.deletingLastPathComponent())
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    private func makeApp(home: URL, bundleIdentifier: String?, name: String = "Dia") -> AppItem {
        AppItem(
            bundleIdentifier: bundleIdentifier,
            url: home.appendingPathComponent("Applications/\(name).app", isDirectory: true),
            name: name
        )
    }

    @Test
    func findsEveryKnownLocationInDisplayOrder() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let bundleIdentifier = "com.example.dia"
        try makeDirectory(home.appendingPathComponent("Applications/Dia.app", isDirectory: true))
        try makeDirectory(
            home.appendingPathComponent(
                "Library/Application Support/\(bundleIdentifier)",
                isDirectory: true
            )
        )
        try makeDirectory(
            home.appendingPathComponent("Library/Application Support/Dia", isDirectory: true)
        )
        try makeDirectory(
            home.appendingPathComponent("Library/Caches/\(bundleIdentifier)", isDirectory: true)
        )
        try makeFile(
            home.appendingPathComponent("Library/Preferences/\(bundleIdentifier).plist")
        )
        try makeDirectory(
            home.appendingPathComponent(
                "Library/Saved Application State/\(bundleIdentifier).savedState",
                isDirectory: true
            )
        )
        try makeDirectory(
            home.appendingPathComponent("Library/Containers/\(bundleIdentifier)", isDirectory: true)
        )
        try makeDirectory(
            home.appendingPathComponent("Library/WebKit/\(bundleIdentifier)", isDirectory: true)
        )

        let app = makeApp(home: home, bundleIdentifier: bundleIdentifier)
        let components = UninstallScanner.components(for: app, home: home)

        #expect(
            components.map(\.kind) == [
                .applicationFiles,
                .applicationSupport,
                .applicationSupport,
                .caches,
                .preferences,
                .savedState,
                .containers,
                .other
            ]
        )
        #expect(components.first?.url == app.url.standardizedFileURL)
        #expect(
            components.contains {
                $0.kind == .applicationSupport && $0.url.lastPathComponent == "Dia"
            }
        )
        #expect(
            components.contains {
                $0.url.lastPathComponent == "\(bundleIdentifier).plist"
            }
        )
    }

    @Test
    func withoutABundleIdentifierOnlyTheAppIsListed() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let app = makeApp(home: home, bundleIdentifier: nil)
        try makeDirectory(app.url)
        try makeDirectory(
            home.appendingPathComponent("Library/Application Support/Dia", isDirectory: true)
        )

        let components = UninstallScanner.components(for: app, home: home)

        #expect(components.map(\.kind) == [.applicationFiles])
        #expect(components.first?.url == app.url.standardizedFileURL)
    }

    @Test
    func anIdentifierMatchingTheNameIsNotListedTwice() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let app = makeApp(home: home, bundleIdentifier: "Dia")
        try makeDirectory(app.url)
        try makeDirectory(
            home.appendingPathComponent("Library/Application Support/Dia", isDirectory: true)
        )

        let components = UninstallScanner.components(for: app, home: home)
        let support = components.filter { $0.kind == .applicationSupport }

        #expect(support.count == 1)
        #expect(support.first?.url.lastPathComponent == "Dia")
    }

    @Test
    func unrelatedLibraryFoldersAreLeftOut() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let app = makeApp(home: home, bundleIdentifier: "com.example.dia")
        try makeDirectory(app.url)
        try makeDirectory(
            home.appendingPathComponent("Library/Application Support/Other", isDirectory: true)
        )
        try makeDirectory(
            home.appendingPathComponent("Library/Caches/com.example.other", isDirectory: true)
        )
        try makeFile(home.appendingPathComponent("Library/Preferences/com.example.other.plist"))

        let components = UninstallScanner.components(for: app, home: home)

        #expect(components.map(\.kind) == [.applicationFiles])
    }

    @Test
    func missingLocationsAreSkipped() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let app = makeApp(home: home, bundleIdentifier: "com.example.dia")
        try makeDirectory(app.url)

        let components = UninstallScanner.components(for: app, home: home)

        #expect(components.map(\.kind) == [.applicationFiles])
    }

    @Test
    func aMalformedIdentifierCannotEscapeTheLibrary() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let app = makeApp(home: home, bundleIdentifier: "../..")
        try makeDirectory(app.url)
        try makeDirectory(home.appendingPathComponent("Library", isDirectory: true))

        let components = UninstallScanner.components(for: app, home: home)

        #expect(components.map(\.kind) == [.applicationFiles])
        #expect(components.allSatisfy { $0.url == app.url.standardizedFileURL })
    }

    @Test
    func sizesAreMeasuredRecursively() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let folder = home.appendingPathComponent("Caches/Example", isDirectory: true)
        let first = folder.appendingPathComponent("a.bin")
        let second = folder.appendingPathComponent("nested/b.bin")
        try makeFile(first, bytes: 64_000)
        try makeFile(second, bytes: 64_000)

        #expect(UninstallSize.allocatedSize(of: first) > 0)
        #expect(UninstallSize.allocatedSize(of: folder) > UninstallSize.allocatedSize(of: first))
        #expect(UninstallSize.allocatedSize(of: home.appendingPathComponent("missing")) == 0)
    }

    @Test
    func zeroBytesReadsLikeTheReference() {
        #expect(UninstallSize.formatted(0) == "Zero KB")
        #expect(UninstallSize.formatted(1_500_000).contains("MB"))
    }
}

@MainActor
struct UninstallModelTests {
    private func makeModel(
        sizes: [URL: Int64] = [:],
        isMeasuring: Bool = false
    ) -> UninstallModel {
        let appURL = URL(fileURLWithPath: "/Applications/Dia.app")
        let app = AppItem(
            bundleIdentifier: "com.example.dia",
            url: appURL,
            name: "Dia"
        )
        let components = [
            UninstallComponent(
                kind: .applicationFiles,
                name: "Dia",
                url: appURL
            ),
            UninstallComponent(
                kind: .caches,
                name: "com.example.dia",
                url: URL(fileURLWithPath: "/Users/test/Library/Caches/com.example.dia")
            ),
            UninstallComponent(
                kind: .caches,
                name: "Dia",
                url: URL(fileURLWithPath: "/Users/test/Library/Caches/Dia")
            )
        ]
        return UninstallModel(
            app: app,
            components: components,
            home: URL(fileURLWithPath: "/Users/test"),
            sizes: sizes,
            isMeasuring: isMeasuring
        )
    }

    @Test
    func everythingStartsSelectedAndExpanded() {
        let model = makeModel()

        #expect(model.allSelected)
        #expect(model.hasSelection)
        #expect(model.groups.map(\.kind) == [.applicationFiles, .caches])
        #expect(model.isExpanded(.caches))
        #expect(model.selectionState(for: .caches) == .all)
        #expect(model.selectionState(for: .applicationFiles) == .all)
    }

    @Test
    func togglingACategoryLeavesTheOtherCategoriesAlone() {
        let model = makeModel()

        model.toggleGroup(.caches)

        #expect(model.selectionState(for: .caches) == .none)
        #expect(model.selectionState(for: .applicationFiles) == .all)
        #expect(!model.allSelected)

        model.toggleGroup(.caches)

        #expect(model.allSelected)
    }

    @Test
    func aPartlySelectedCategoryReadsAsMixed() {
        let model = makeModel()
        let cache = model.components[1]

        model.toggle(cache)

        #expect(model.selectionState(for: .caches) == .some)
        #expect(!model.isSelected(cache))
        #expect(model.hasSelection)
    }

    @Test
    func allClearsAndRestoresEveryCheckbox() {
        let model = makeModel()

        model.toggleAll()
        #expect(!model.hasSelection)
        #expect(model.selectedComponents.isEmpty)

        model.toggleAll()
        #expect(model.allSelected)
        #expect(model.selectedComponents.count == model.components.count)
    }

    @Test
    func totalsFollowTheMeasuredSizes() {
        let layout = makeModel()
        let caches = layout.components.filter { $0.kind == .caches }
        let application = layout.components[0]
        let model = makeModel(
            sizes: [
                application.url: 1_000,
                caches[0].url: 200,
                caches[1].url: 300
            ]
        )

        #expect(model.totalBytes == 1_500)
        #expect(model.sizeText(for: application) == UninstallSize.formatted(1_000))

        model.toggleGroup(.caches)
        #expect(model.selectedComponents == [application])
    }

    @Test
    func pathsInsideHomeAreAbbreviated() {
        let model = makeModel()

        #expect(
            model.abbreviatedPath(
                URL(fileURLWithPath: "/Users/test/Library/Caches/com.example.dia")
            ) == "~/Library/Caches/com.example.dia"
        )
        #expect(
            model.abbreviatedPath(URL(fileURLWithPath: "/Applications/Dia.app"))
                == "/Applications/Dia.app"
        )
    }
}
