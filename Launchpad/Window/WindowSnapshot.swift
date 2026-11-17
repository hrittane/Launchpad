#if DEBUG
import AppKit
import CoreGraphics

/// Captures the app's own window, including Liquid Glass, for development
/// snapshots. `CGWindowListCreateImage` is deprecated, so it is resolved at
/// runtime to keep the build warning-free.
enum WindowSnapshot {
    private typealias CreateImageFunction = @convention(c) (
        CGRect, UInt32, CGWindowID, UInt32
    ) -> Unmanaged<CGImage>?

    /// `CGWindowListOption.includingWindow` (1 << 3).
    private static let includingWindow: UInt32 = 1 << 3
    /// `CGWindowImageOption.boundsIgnoreFraming` (1 << 0) | `.bestResolution` (1 << 3).
    private static let imageOptions: UInt32 = (1 << 0) | (1 << 3)

    static func capture(windowNumber: Int) -> CGImage? {
        guard windowNumber > 0,
              let handle = dlopen(
                  "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                  RTLD_LAZY
              ),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImageFunction.self)
        guard let image = create(.null, includingWindow, CGWindowID(windowNumber), imageOptions) else {
            return nil
        }
        return image.takeRetainedValue()
    }

    /// Captures every on-screen window (wallpaper, Dock, our panel). Only used
    /// by the explicit `--screen` snapshot flag while developing.
    static func captureScreen() -> CGImage? {
        guard let handle = dlopen(
                  "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                  RTLD_LAZY
              ),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImageFunction.self)
        guard let image = create(.infinite, 1 << 0, 0, imageOptions) else { return nil }
        return image.takeRetainedValue()
    }
}
#endif
