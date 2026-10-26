import AppKit
import SwiftUI

/// Fallback preferences window used only when the SwiftUI `Settings` scene is
/// not reachable through AppKit's responder chain.
final class PreferencesWindowController: NSWindowController {
    init(viewModel: LaunchpadViewModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Launchpad Preferences", comment: "Preferences window title")
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.contentView = NSHostingView(rootView: PreferencesView(viewModel: viewModel))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
