import AppKit

/// The menu bar status item: Show Launchpad, Settings, Quit.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onShow: () -> Void
    private let onQuit: () -> Void

    init(onShow: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onShow = onShow
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "square.grid.3x3.fill",
                accessibilityDescription: NSLocalizedString("Launchpad", comment: "Status item")
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = NSLocalizedString("Launchpad", comment: "Status item tooltip")
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let show = NSMenuItem(
            title: NSLocalizedString("Show Launchpad", comment: "Status item"),
            action: #selector(showLaunchpad),
            keyEquivalent: ""
        )
        show.target = self
        menu.addItem(show)

        let settings = NSMenuItem(
            title: NSLocalizedString("Settings…", comment: "Status item"),
            action: nil,
            keyEquivalent: ","
        )
        settings.isEnabled = false
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: NSLocalizedString("Quit Launchpad", comment: "Status item"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func showLaunchpad() {
        onShow()
    }

    @objc private func quit() {
        onQuit()
    }
}
