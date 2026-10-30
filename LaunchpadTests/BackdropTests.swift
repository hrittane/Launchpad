import AppKit
import SwiftUI
import XCTest
@testable import Launchpad

/// Pixel checks for the wallpaper backdrop. The production view resolves the
/// desktop image through `WallpaperBackdrop`; the test injects a synthetic
/// saturated gradient through the same rendering path so the assertions do not
/// depend on the machine's wallpaper.
@MainActor
final class BackdropRenderingTests: XCTestCase {
    private let width = 160
    private let height = 100

    func testBackdropKeepsSaturationAndDimsByAboutAQuarter() throws {
        let input = try Self.verticalGradient(width: width, height: height)
        let viewModel = LaunchpadViewModel()
        let content = LaunchpadBackgroundSurface(
            viewModel: viewModel,
            reduceTransparencyOverride: false,
            wallpaperImage: input
        )
        .frame(width: CGFloat(width), height: CGFloat(height))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let output = try XCTUnwrap(renderer.cgImage)

        let inputStats = try Self.statistics(of: input)
        let outputStats = try Self.statistics(of: output)

        print(String(
            format: "BACKDROP saturation input=%.4f output=%.4f ratio=%.4f brightness input=%.4f output=%.4f ratio=%.4f hueDelta=%.4f",
            inputStats.saturation,
            outputStats.saturation,
            outputStats.saturation / inputStats.saturation,
            inputStats.brightness,
            outputStats.brightness,
            outputStats.brightness / inputStats.brightness,
            abs(outputStats.hue - inputStats.hue)
        ))

        // No desaturation: the black dimming layer scales all channels equally,
        // and the 1.1 saturation boost must survive the render.
        XCTAssertGreaterThanOrEqual(
            outputStats.saturation,
            inputStats.saturation * 0.85
        )

        // A flat black layer of 22-25% leaves 75-78% of the input brightness.
        XCTAssertGreaterThanOrEqual(
            outputStats.brightness,
            inputStats.brightness * 0.70
        )
        XCTAssertLessThanOrEqual(
            outputStats.brightness,
            inputStats.brightness * 0.90
        )

        // No blue/navy shift: the removed wash used to move the hue.
        XCTAssertLessThan(abs(outputStats.hue - inputStats.hue), 0.02)
    }

    func testReducedTransparencyIgnoresTheWallpaper() throws {
        let input = try Self.verticalGradient(width: width, height: height)
        let content = LaunchpadBackgroundSurface(
            viewModel: LaunchpadViewModel(),
            reduceTransparencyOverride: true,
            wallpaperImage: input
        )
        .frame(width: CGFloat(width), height: CGFloat(height))

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let output = try XCTUnwrap(renderer.cgImage)
        let stats = try Self.statistics(of: output)

        // Solid `Color(white: 0.12)` at 0.85 opacity over a transparent base.
        XCTAssertLessThan(stats.saturation, 0.02)
        XCTAssertLessThan(stats.brightness, 0.30)
    }

    /// Guards the hot path: SwiftUI body evaluation must only read the cache.
    /// Resolving and decoding the wallpaper belongs to `prepare(for:)`.
    func testBackdropBodyOnlyReadsThePreparedCache() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)

        WallpaperBackdrop.invalidate()
        XCTAssertNil(
            WallpaperBackdrop.blurredImage(for: screen),
            "An unprepared backdrop must not resolve the wallpaper"
        )

        WallpaperBackdrop.prepare(for: screen)
        let first = try XCTUnwrap(WallpaperBackdrop.blurredImage(for: screen))

        // A second prepare with an unchanged signature must reuse the same
        // rendered image instead of decoding and blurring again.
        WallpaperBackdrop.prepare(for: screen)
        let second = try XCTUnwrap(WallpaperBackdrop.blurredImage(for: screen))
        XCTAssertTrue(first === second)

        // A body pass must stay in the microsecond range; resolving the 24 MB
        // HEIC here would take about a second per call.
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<1_000 {
            _ = WallpaperBackdrop.blurredImage(for: screen)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print(String(format: "BACKDROP cache 1000 lookups=%.4fs", elapsed))
        XCTAssertLessThan(elapsed, 0.1)

        WallpaperBackdrop.invalidate()
        XCTAssertNil(WallpaperBackdrop.blurredImage(for: screen))
    }

    private struct PixelStatistics {
        var saturation: Double
        var brightness: Double
        var hue: Double
    }

    private static func verticalGradient(width: Int, height: Int) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))

        let top: (CGFloat, CGFloat, CGFloat) = (0.25, 0.2, 0.8)
        let bottom: (CGFloat, CGFloat, CGFloat) = (0.1, 0.3, 0.9)
        for y in 0..<height {
            let t = CGFloat(y) / CGFloat(max(1, height - 1))
            context.setFillColor(
                red: top.0 + (bottom.0 - top.0) * t,
                green: top.1 + (bottom.1 - top.1) * t,
                blue: top.2 + (bottom.2 - top.2) * t,
                alpha: 1
            )
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private static func statistics(of image: CGImage) throws -> PixelStatistics {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: height * bytesPerRow)
        defer { data.deallocate() }

        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // Start from opaque black. The reduced-transparency fixture is slightly
        // translucent, and uninitialized bytes would otherwise show through.
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var saturationSum = 0.0
        var brightnessSum = 0.0
        var hueSum = 0.0
        var weightedHueCount = 0.0

        for offset in stride(from: 0, to: height * bytesPerRow, by: 4) {
            let red = Double(data[offset]) / 255
            let green = Double(data[offset + 1]) / 255
            let blue = Double(data[offset + 2]) / 255

            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let delta = maximum - minimum

            saturationSum += maximum > 0 ? delta / maximum : 0
            brightnessSum += maximum

            if delta > 0 {
                var hue: Double
                if maximum == red {
                    hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
                } else if maximum == green {
                    hue = (blue - red) / delta + 2
                } else {
                    hue = (red - green) / delta + 4
                }
                hue /= 6
                if hue < 0 { hue += 1 }
                // Hue is circular; these fixtures stay in the blue range, so a
                // plain weighted mean is enough.
                hueSum += hue
                weightedHueCount += 1
            }
        }

        let pixelCount = Double(width * height)
        return PixelStatistics(
            saturation: saturationSum / pixelCount,
            brightness: brightnessSum / pixelCount,
            hue: weightedHueCount > 0 ? hueSum / weightedHueCount : 0
        )
    }
}
