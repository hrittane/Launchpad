import Foundation
import Testing

@testable import Launchpad

struct IconProviderTests {
    @Test
    func appearanceKeyCombinesIconThemeAndInterfaceStyle() {
        #expect(IconProvider.appearanceKey(theme: "ClearLight", style: "Dark") == "ClearLight|Dark")
        #expect(IconProvider.appearanceKey(theme: "TintedDark", style: "Light") == "TintedDark|Light")
    }

    @Test
    func appearanceKeyFallsBackToNormalAndLight() {
        #expect(IconProvider.appearanceKey(theme: nil, style: nil) == "Default|Light")
    }

    @Test
    func switchingInterfaceStyleChangesTheKey() {
        let dark = IconProvider.appearanceKey(theme: "ClearLight", style: "Dark")
        let light = IconProvider.appearanceKey(theme: "ClearLight", style: nil)

        #expect(dark != light)
    }

    @Test
    func appearanceKeyReadsBothPreferences() throws {
        let suite = "IconProviderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("ClearLight", forKey: "AppleIconAppearanceTheme")
        defaults.set("Dark", forKey: "AppleInterfaceStyle")

        #expect(IconProvider.appearanceKey(defaults: defaults).hasPrefix("ClearLight|Dark"))

        defaults.set("Blue", forKey: "SLSIconAppearanceTintColorName")
        #expect(IconProvider.appearanceKey(defaults: defaults).contains("Blue"))
    }
}
