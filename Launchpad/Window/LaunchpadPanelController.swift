import AppKit
import SwiftUI

/// Hosts the blurred backdrop and the SwiftUI interface.
final class LaunchpadContentView: NSView {
    private let backdropClip = NSView()
    private let backdrop = BackdropView()
    private let hosting: NSHostingView<LaunchpadView>
    private let model: AppModel
    private let onDismiss: () -> Void
    private let onLaunch: (AppItem) -> Void
    private let onFolderObscured: (Bool) -> Void
    private let folderDim: FolderDim

    /// Height of the strip at the top that belongs to the menu-bar cover.
    ///
    /// The backdrop stops below it, which leaves the top strip transparent: the
    /// cover window blurs the wallpaper exactly like the panel does, so the two
    /// halves join without a seam.
    var topInset: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    init(
        model: AppModel,
        folderDim: FolderDim,
        onDismiss: @escaping () -> Void,
        onLaunch: @escaping (AppItem) -> Void,
        onFolderObscured: @escaping (Bool) -> Void
    ) {
        self.model = model
        self.folderDim = folderDim
        self.onDismiss = onDismiss
        self.onLaunch = onLaunch
        self.onFolderObscured = onFolderObscured
        hosting = NSHostingView(
            rootView: LaunchpadView(
                model: model,
                onDismiss: onDismiss,
                onLaunch: onLaunch,
                onFolderObscured: onFolderObscured,
                folderDim: folderDim
            )
        )
        super.init(frame: .zero)
        wantsLayer = true

        backdropClip.wantsLayer = true
        backdropClip.layer?.masksToBounds = true
        backdropClip.addSubview(backdrop)

        addSubview(backdropClip)
        addSubview(hosting)
        hosting.frame = bounds
        backdropClip.frame = bounds
        backdrop.frame = bounds
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LaunchpadContentView is created programmatically")
    }

    override func layout() {
        super.layout()
        hosting.frame = bounds
        backdropClip.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(0, bounds.height - topInset)
        )
        backdrop.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    }

    /// Draws the desktop picture of `screen` behind the interface.
    func presentBackdrop(on screen: NSScreen) {
        backdrop.present(on: screen)
    }

    #if DEBUG
    /// Swaps the live blur for the opaque gradient and rebuilds the interface
    /// without the glass container so it can be rendered into a bitmap.
    func prepareForFallbackSnapshot() {
        DebugSnapshot.flattenGlass = true
        topInset = 0
        backdrop.forceFallbackForSnapshot()
        hosting.rootView = LaunchpadView(
            model: model,
            onDismiss: onDismiss,
            onLaunch: onLaunch,
            onFolderObscured: onFolderObscured,
            folderDim: folderDim
        )
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    #endif
}

/// Owns the panel: presents it on the screen under the mouse, animates it,
/// hides it and restores focus to the previously active application.
@MainActor
final class LaunchpadPanelController {
    private let model: AppModel
    private var window: LaunchpadWindow?
    private var coverWindow: MenuBarCoverWindow?
    private var previousApp: NSRunningApplication?
    private var escapeMonitor: Any?
    private var hideTask: Task<Void, Never>?
    private var pagingInterpreter = PagingGestureInterpreter()
    /// Recent horizontal scroll deltas, used to estimate release velocity so a
    /// quick flick still turns a page after a short travel.
    private var scrollSamples: [(time: TimeInterval, delta: CGFloat)] = []
    private let folderDim = FolderDim()

    init(model: AppModel) {
        self.model = model

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.type == .keyDown {
                return self.handleKeyDown(event)
            }
            return self.handleScrollWheel(event) ? nil : event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // An open alert (for example the uninstall confirmation) owns the
        // keyboard; the panel must not act on keys behind it.
        guard NSApp.modalWindow == nil else { return event }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return event
        }

        if event.keyCode == 53 {  // Escape
            return handleEscape()
        }

        if model.isSearching {
            switch event.keyCode {
            case 123:  // Left
                model.moveSearchSelection(by: -1)
                return nil
            case 124:  // Right
                model.moveSearchSelection(by: 1)
                return nil
            case 125:  // Down
                model.moveSearchSelection(by: model.columns)
                return nil
            case 126:  // Up
                model.moveSearchSelection(by: -model.columns)
                return nil
            case 36, 76:  // Return / keypad Enter
                launchSearchSelection()
                return nil
            case 51:  // Delete
                // While the pill owns the keyboard the field editor deletes;
                // during type-to-search the model owns the text instead.
                guard !isTextInputFocused else { return event }
                model.deleteLastSearchCharacter()
                return nil
            default:
                guard !isTextInputFocused, let characters = printableCharacters(from: event) else {
                    return event
                }
                model.appendToSearch(characters)
                return nil
            }
        }

        switch event.keyCode {
        case 123:  // Left arrow
            guard model.openFolder == nil else { return event }
            model.stepPage(by: -1)
            return nil
        case 124:  // Right arrow
            guard model.openFolder == nil else { return event }
            model.stepPage(by: 1)
            return nil
        default:
            break
        }

        // Type-to-search: the first printable character opens the search and
        // becomes its query. The field editor is not involved until the user
        // clicks the pill, so fast typing cannot lose characters to a focus
        // race.
        if model.openFolder == nil, let characters = printableCharacters(from: event) {
            guard !isTextInputFocused else { return event }
            model.beginSearch(with: characters)
            return nil
        }

        return event
    }

    /// The characters a key press would insert, or nil for control keys.
    private func printableCharacters(from event: NSEvent) -> String? {
        guard !event.modifierFlags.contains(.function),
              let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty,
              !characters.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else { return nil }
        return characters
    }

    /// True while a text field (the search pill or a folder name) owns the
    /// keyboard, in which case ordinary characters belong to it.
    private var isTextInputFocused: Bool {
        window?.firstResponder is NSTextView
    }

    /// Escape closes the transient layer it belongs to, innermost first.
    private func handleEscape() -> NSEvent? {
        if model.openFolderID != nil {
            model.closeFolder()
            return nil
        }
        if model.isEditing {
            model.endEditing()
            return nil
        }
        if model.isSearching {
            model.clearSearch()
            return nil
        }
        hide()
        return nil
    }

    private func launchSearchSelection() {
        guard let app = model.selectedSearchResult else { return }
        launch(app)
    }

    /// Trackpad swipes move the page strip with the fingers and commit on
    /// release. Classic mouse wheels have no phases and much smaller deltas, so
    /// they keep the discrete one-notch-one-page behaviour.
    private func handleScrollWheel(_ event: NSEvent) -> Bool {
        guard model.pageCount > 1,
              model.openFolderID == nil,
              !model.isSearching,
              model.draggingID == nil else { return false }
        guard event.momentumPhase.isEmpty else { return false }

        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        guard abs(deltaX) > 0 || event.hasPreciseScrollingDeltas else { return false }

        if event.hasPreciseScrollingDeltas {
            return handleFingerScroll(
                deltaX: deltaX,
                deltaY: deltaY,
                phase: Self.phase(for: event.phase),
                timestamp: event.timestamp
            )
        }

        let step = pagingInterpreter.consume(
            deltaX: deltaX,
            deltaY: deltaY,
            isPrecise: false,
            phase: Self.phase(for: event.phase)
        )
        if step != 0 {
            model.stepPage(by: step)
        }
        return abs(deltaX) >= abs(deltaY)
    }

    /// A finger swipe translates the strip live, so the next page slides in at
    /// the speed of the fingers instead of the panel jumping a whole page.
    private func handleFingerScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        phase: PagingGestureInterpreter.Phase,
        timestamp: TimeInterval
    ) -> Bool {
        let width = pageWidth
        switch phase {
        case .began:
            guard abs(deltaX) >= abs(deltaY) else { return false }
            scrollSamples.removeAll()
            recordScrollSample(deltaX, at: timestamp)
            model.beginPageGesture()
            model.updatePageGesture(deltaX: deltaX, pageWidth: width)
        case .changed:
            if !model.isPaging {
                guard abs(deltaX) >= abs(deltaY) else { return false }
                scrollSamples.removeAll()
                model.beginPageGesture()
            }
            recordScrollSample(deltaX, at: timestamp)
            model.updatePageGesture(deltaX: deltaX, pageWidth: width)
        case .ended:
            guard model.isPaging else { return false }
            let velocity = scrollVelocity(at: timestamp)
            scrollSamples.removeAll()
            model.endPageGesture(pageWidth: width, velocityX: velocity)
        case .cancelled:
            scrollSamples.removeAll()
            model.cancelPageGesture()
        case .other:
            return false
        }
        return abs(deltaX) >= abs(deltaY)
    }

    /// Records horizontal travel for the release-velocity estimate. Only the
    /// last `scrollVelocityWindow` seconds matter: a swipe that slowed down
    /// before the fingers lifted should not read as a flick.
    private func recordScrollSample(_ deltaX: CGFloat, at time: TimeInterval) {
        scrollSamples.append((time, deltaX))
        let cutoff = time - Self.scrollVelocityWindow
        while let first = scrollSamples.first, first.time < cutoff {
            scrollSamples.removeFirst()
        }
    }

    /// Horizontal release velocity in points per second, or zero when the
    /// fingers paused before lifting.
    private func scrollVelocity(at time: TimeInterval) -> CGFloat {
        guard let first = scrollSamples.first, let last = scrollSamples.last else { return 0 }
        guard time - last.time < 0.05 else { return 0 }
        let span = max(last.time - first.time, 0.008)
        let total = scrollSamples.reduce(CGFloat.zero) { $0 + $1.delta }
        let velocity = total / span
        return min(max(velocity, -8000), 8000)
    }

    private var pageWidth: CGFloat {
        screenUnderMouse()?.frame.width ?? window?.frame.width ?? 1
    }

    /// How far back the release-velocity estimate looks.
    private static let scrollVelocityWindow: TimeInterval = 0.12

    private static func phase(for phase: NSEvent.Phase) -> PagingGestureInterpreter.Phase {
        if phase.contains(.began) { return .began }
        if phase.contains(.changed) { return .changed }
        if phase.contains(.ended) { return .ended }
        if phase.contains(.cancelled) { return .cancelled }
        return .other
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    /// Opens `item` and gets out of the way. Focus is deliberately not handed
    /// back to the app that was frontmost before: the launched app should take
    /// it, which `NSWorkspace.OpenConfiguration.activates` arranges.
    func launch(_ item: AppItem) {
        AppLauncher.launch(item)
        hide(restoreFocus: false)
    }

    func show() {
        guard !isVisible else { return }
        guard let screen = screenUnderMouse() else { return }
        hideTask?.cancel()
        hideTask = nil

        if window == nil {
            window = makeWindow()
        }
        if coverWindow == nil {
            coverWindow = MenuBarCoverWindow(folderDim: folderDim)
        }
        guard let window, let coverWindow else { return }

        previousApp = NSWorkspace.shared.frontmostApplication

        window.setFrame(screen.frame, display: false)
        window.alphaValue = 0
        (window.contentView as? LaunchpadContentView)?.presentBackdrop(on: screen)
        model.notePresented()
        IconProvider.shared.prefetch(Array(model.catalog.apps.prefix(35)))

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        // An accessory app summoned by a hotkey is not allowed to take focus
        // with `activate()` alone, and an unfocused panel would never receive a
        // keystroke. The legacy option is still honoured by the window server.
        Self.takeFocus(NSRunningApplication.current)
        window.makeKey()

        // The menu bar is painted over rather than hidden: hiding it would take
        // the Dock with it, and the Dock stays visible under the panel.
        let coverHeight = coverWindow.present(over: screen)
        (window.contentView as? LaunchpadContentView)?.topInset = coverHeight ?? 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            if coverHeight != nil {
                coverWindow.alphaValue = 0
                coverWindow.animator().alphaValue = 1
            }
        }
    }

    func hide(restoreFocus: Bool = true) {
        guard let window, window.isVisible else { return }
        model.cancelPageGesture()

        let previous = previousApp
        let shouldRestore = restoreFocus && previous != nil
        previousApp = nil
        let cover = coverWindow

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            if let cover, cover.isVisible {
                cover.animator().alphaValue = 0
            }
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            window.orderOut(nil)
            window.alphaValue = 1
            cover?.orderOut(nil)
            cover?.alphaValue = 1
            if shouldRestore, let previous, !previous.isTerminated {
                Self.takeFocus(previous)
            }
        }
    }

    #if DEBUG
    var windowNumber: Int { window?.windowNumber ?? 0 }

    /// Rebuilds the interface in its flattened form for offscreen rendering.
    func prepareForFallbackSnapshot() {
        (window?.contentView as? LaunchpadContentView)?.prepareForFallbackSnapshot()
    }

    /// Renders the window's content into a PNG at 1× logical size.
    @discardableResult
    func writeFlattenedSnapshot(to url: URL) -> Bool {
        guard let window, let view = window.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }
    #endif

    // MARK: - Private

    /// `NSApplication.ActivationOptions.activateIgnoringOtherApps` is deprecated
    /// but still the only way for an accessory app to take focus when it is
    /// summoned by a hotkey rather than launched by the user. The option is
    /// spelled as a raw value so the deprecation warning stays out of the build.
    private static func takeFocus(_ application: NSRunningApplication) {
        let legacyFocus = NSApplication.ActivationOptions(rawValue: 1 << 1)
        application.activate(options: legacyFocus)
    }

    private func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.screens.first
    }

    private func makeWindow() -> LaunchpadWindow {
        let window = LaunchpadWindow()
        window.contentView = LaunchpadContentView(
            model: model,
            folderDim: folderDim,
            onDismiss: { [weak self] in self?.hide() },
            onLaunch: { [weak self] item in self?.launch(item) },
            onFolderObscured: { [weak self] obscured in
                self?.folderDim.setDimmed(obscured)
            }
        )
        return window
    }
}
