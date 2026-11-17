import Foundation
import Testing

@testable import Launchpad

struct AppItemTests {
    @Test
    func identifierPrefersBundleIdentifier() {
        let item = AppItem(
            bundleIdentifier: "com.example.App",
            url: URL(fileURLWithPath: "/Applications/App.app"),
            name: "App"
        )
        #expect(item.id == "com.example.App")
        #expect(item.isSystem == false)
        #expect(item.isRemovable == true)
    }

    @Test
    func systemAppsAreNotRemovable() {
        let item = AppItem(
            bundleIdentifier: nil,
            url: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
            name: "Calculator"
        )
        #expect(item.id == "/System/Applications/Calculator.app")
        #expect(item.isSystem == true)
        #expect(item.isRemovable == false)
    }
}
