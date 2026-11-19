import AppKit

/// The menu bar status item: Show Launchpad, Settings, Quit.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onShow: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    init(
        onShow: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onShow = onShow
        self.onSettings = onSettings
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configure()
    }

    /// Hides or shows the menu bar item without destroying it.
    func setVisible(_ visible: Bool) {
        statusItem.isVisible = visible
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
            keyEquivalent: " "
        )
        show.keyEquivalentModifierMask = [.option]
        show.target = self
        menu.addItem(show)

        let settings = NSMenuItem(
            title: NSLocalizedString("Settings…", comment: "Status item"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
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

    @objc private func showSettings() {
        onSettings()
    }

    @objc private func quit() {
        onQuit()
    }
}
