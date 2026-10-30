import Foundation
import XCTest
@testable import Launchpad

@MainActor
final class SystemWallpaperTests: XCTestCase {
    private let aerialID = "4C108785-A7BA-422E-9C79-B0129F1D5550"

    func testDecodesAerialIdentifierFromEncodedOptions() throws {
        let data = try encodedOptions(id: aerialID)
        XCTAssertEqual(
            SystemWallpaper.aerialIdentifier(fromEncodedOptions: data),
            aerialID
        )
    }

    func testAutomaticPickerHasNoAerialIdentifier() throws {
        let data = try encodedOptions(id: "automatic")
        XCTAssertNil(SystemWallpaper.aerialIdentifier(fromEncodedOptions: data))
    }

    func testGenericDesktopFallbackIsDetected() {
        XCTAssertTrue(SystemWallpaper.isGenericFallback(
            URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")
        ))
        XCTAssertTrue(SystemWallpaper.isGenericFallback(
            URL(fileURLWithPath: "/System/Library/Wallpapers/.default/DefaultAerial.heic")
        ))
        XCTAssertFalse(SystemWallpaper.isGenericFallback(
            URL(fileURLWithPath: "/Users/me/Pictures/My Wallpaper.heic")
        ))
    }

    func testNeptuneProviderResolvesTheTahoeStill() throws {
        let options = try encodedOptions(id: "automatic")
        let store: [String: Any] = [
            "AllSpacesAndDisplays": [
                "Linked": [
                    "Content": [
                        "Choices": [
                            [
                                "Provider": "com.apple.NeptuneOneExtension",
                                "Files": [String]()
                            ]
                        ],
                        "EncodedOptionValues": options
                    ]
                ]
            ]
        ]

        let light = try XCTUnwrap(SystemWallpaper.resolveFromStore(store, appearance: .light))
        XCTAssertEqual(light.identity, "neptune:TahoeLight")
        XCTAssertGreaterThan(light.image.width, 0)

        let dark = try XCTUnwrap(SystemWallpaper.resolveFromStore(store, appearance: .dark))
        XCTAssertEqual(dark.identity, "neptune:TahoeDark")
        XCTAssertGreaterThan(dark.image.width, 0)
    }

    /// The public API returns the generic desktop for provider-backed
    /// wallpapers, so when it does, the store resolver must find the real one.
    func testCurrentDesktopWallpaperIsResolvedFromTheStore() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let source = try XCTUnwrap(SystemWallpaper.resolve(for: screen))
        print("WALLPAPER identity=\(source.identity) size=\(source.image.width)x\(source.image.height)")

        if let publicURL = NSWorkspace.shared.desktopImageURL(for: screen),
           SystemWallpaper.isGenericFallback(publicURL) {
            XCTAssertFalse(
                source.identity.hasPrefix("fallback:"),
                "Store resolution failed for a provider-backed wallpaper"
            )
        }
    }

    private func encodedOptions(id: String) throws -> Data {
        let plist: [String: Any] = [
            "values": [
                "appearance": [
                    "picker": [
                        "_0": ["id": id]
                    ]
                ]
            ]
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .binary,
            options: 0
        )
    }
}
