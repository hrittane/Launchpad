import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var panelController: LaunchpadPanelController?
    private var statusItemController: StatusItemController?
    private var resignObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NSApp.setActivationPolicy(.accessory)

        model.catalog.scanIfNeeded()

        let controller = LaunchpadPanelController(model: model)
        panelController = controller

        // Like the real Launchpad, the panel is modal in spirit: switching to
        // another application dismisses it instead of leaving it on screen.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak controller] _ in
            Task { @MainActor in
                guard let controller, controller.isVisible else { return }
                controller.hide(restoreFocus: false)
            }
        }

        statusItemController = StatusItemController(
            onShow: { [weak controller] in controller?.show() },
            onQuit: { NSApp.terminate(nil) }
        )

        #if DEBUG
        if !CommandLine.arguments.contains("--no-panel") {
            controller.show()
        }
        #else
        controller.show()
        #endif

        #if DEBUG
        handleSnapshotRequestIfNeeded(controller: controller)
        #endif
    }

    #if DEBUG
    /// `--snapshot <path>` renders one frame to disk and quits, so the UI can be
    /// compared against the reference frames without screen-recording access.
    private func handleSnapshotRequestIfNeeded(controller: LaunchpadPanelController) {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--snapshot"),
              arguments.index(after: flagIndex) < arguments.endIndex else { return }
        let path = arguments[arguments.index(after: flagIndex)]
        let url = URL(fileURLWithPath: path)

        Task { @MainActor in
            // Let the catalog scan, icon loads and entrance animation settle.
            try? await Task.sleep(for: .milliseconds(1800))

            if let pageIndex = integerArgument(after: "--page") {
                model.goToPage(pageIndex)
                try? await Task.sleep(for: .milliseconds(600))
            }

            if CommandLine.arguments.contains("--screen"),
               let image = WindowSnapshot.captureScreen(),
               let data = pngData(from: image, rejectingBlank: true) {
                try? data.write(to: url)
                reportSnapshot(wrote: true, url: url, mode: "full-screen")
                NSApp.terminate(nil)
                return
            }

            if let image = WindowSnapshot.capture(windowNumber: controller.windowNumber),
               let data = pngData(from: image, rejectingBlank: true) {
                try? data.write(to: url)
                reportSnapshot(wrote: true, url: url, mode: "window-server")
                NSApp.terminate(nil)
                return
            }

            controller.prepareForFallbackSnapshot()
            try? await Task.sleep(for: .milliseconds(450))
            let wrote = controller.writeFlattenedSnapshot(to: url)
            reportSnapshot(wrote: wrote, url: url, mode: "offscreen")
            NSApp.terminate(nil)
        }
    }

    /// Screen capture permission can turn blank frames into an all-zero image;
    /// those are rejected so the caller can fall back to offscreen rendering.
    private func pngData(from image: CGImage, rejectingBlank: Bool) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        if rejectingBlank && !containsVisibleContent(rep) { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func containsVisibleContent(_ rep: NSBitmapImageRep) -> Bool {
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 0, height > 0 else { return false }
        var visible = 0
        var sampled = 0
        for y in stride(from: 0, to: height, by: 24) {
            for x in stride(from: 0, to: width, by: 24) {
                sampled += 1
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.5,
                   color.redComponent + color.greenComponent + color.blueComponent > 0.15 {
                    visible += 1
                }
            }
        }
        return sampled > 0 && Double(visible) / Double(sampled) > 0.02
    }

    private func reportSnapshot(wrote: Bool, url: URL, mode: String) {
        let message = wrote ? "snapshot (\(mode)): \(url.path)\n" : "snapshot failed\n"
        FileHandle.standardError.write(Data(message.utf8))
    }

    private func integerArgument(after flag: String) -> Int? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.index(after: index) < arguments.endIndex else { return nil }
        return Int(arguments[arguments.index(after: index)])
    }
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
