import AppKit
import Foundation
import os

/// Turns the custom grid drag into a real file drag once the pointer reaches
/// the Dock.
///
/// A real drag is what the Dock understands: its icons slide aside to open a
/// slot, the app can be dropped between existing tiles, and nothing has to be
/// written to the Dock's preferences or restarted. The drag image is the app's
/// own icon.
///
/// While the session is live a transparent guard sits above the Trash tile.
/// The guard is the only place where the drop is intercepted: it accepts the
/// file drag before the Dock's Trash can move the bundle, so the caller keeps
/// its chance to list the leftover files first.
@MainActor
final class DockDragSession: NSObject, NSDraggingSource {
    private let app: AppItem
    private weak var view: NSView?
    private let event: NSEvent
    private let finish: (Bool) -> Void
    private var guardWindow: TrashGuardWindow?
    private var guardView: TrashGuardView?
    private var droppedOnTrash = false
    private var didStart = false
    private var lastGuardUpdate: TimeInterval = 0
    private static let logger = Logger(
        subsystem: "com.example.Launchpad",
        category: "dock"
    )

    init(
        app: AppItem,
        view: NSView,
        event: NSEvent,
        finish: @escaping (Bool) -> Void
    ) {
        self.app = app
        self.view = view
        self.event = event
        self.finish = finish
    }

    func start() {
        guard !didStart, let view, let window = view.window else {
            finish(false)
            return
        }
        didStart = true
        let screenPoint = NSEvent.mouseLocation
        installTrashGuard(at: screenPoint)

        let item = NSDraggingItem(pasteboardWriter: app.url as NSURL)
        let side: CGFloat = 64
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        image.size = NSSize(width: side, height: side)

        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let point = view.convert(windowPoint, from: nil)
        item.setDraggingFrame(
            CGRect(
                x: point.x - side / 2,
                y: point.y - side / 2,
                width: side,
                height: side
            ),
            contents: image
        )

        Self.logger.info("Handing \(self.app.name, privacy: .public) to the Dock drag")
        let session = view.beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    /// The guard only exists for removable apps. A system app dropped on the
    /// Trash is left to macOS, which refuses to delete it.
    private func installTrashGuard(at point: CGPoint) {
        guard app.isRemovable else { return }
        guard let trash = DockDrop.trashFrame(at: point) else {
            Self.logger.notice("No Trash frame for \(self.app.name, privacy: .public)")
            return
        }
        moveGuard(to: trash.insetBy(dx: -8, dy: -8))
    }

    private func moveGuard(to frame: CGRect) {
        if let guardWindow {
            guardWindow.setFrame(frame, display: false)
            return
        }

        let guardView = TrashGuardView(
            frame: CGRect(origin: .zero, size: frame.size)
        )
        guardView.onDrop = { [weak self] in
            guard let self else { return false }
            Self.logger.info("Trash guard accepted \(self.app.name, privacy: .public)")
            droppedOnTrash = true
            return true
        }

        let window = TrashGuardWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = guardView
        window.orderFrontRegardless()
        self.guardView = guardView
        guardWindow = window
    }

    private func tearDown() {
        guardWindow?.orderOut(nil)
        guardWindow = nil
        guardView = nil
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.copy, .move]
    }

    func draggingSession(
        _ session: NSDraggingSession,
        movedTo screenPoint: NSPoint
    ) {
        guard let guardWindow else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastGuardUpdate >= 0.08,
              guardWindow.frame.insetBy(dx: -120, dy: -120).contains(screenPoint),
              let trash = DockDrop.trashFrame(at: screenPoint) else {
            return
        }
        lastGuardUpdate = now
        moveGuard(to: trash.insetBy(dx: -8, dy: -8))
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // A cancelled drag can also end over the Trash; only an actual drop
        // carries an operation from the destination. A missing bundle is the
        // second signal, in case the Dock moved it without reporting one.
        let touchedTrash = droppedOnTrash
            || ((!operation.isEmpty
                || !FileManager.default.fileExists(atPath: app.url.path))
                && DockDrop.isOverTrash(screenPoint))
        Self.logger.info(
            "Dock drag ended op=\(operation.rawValue) trash=\(touchedTrash)"
        )
        tearDown()
        // The drag manager is still unwinding here. Defer the panel (or the
        // catalog update) to the next run-loop turn so it cannot nest inside
        // the drag session's cleanup.
        perform(
            #selector(finishAfterDrag(_:)),
            with: NSNumber(value: touchedTrash),
            afterDelay: 0
        )
    }

    @objc private func finishAfterDrag(_ value: NSNumber) {
        finish(value.boolValue)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}

/// A borderless window that sits one level above the Dock, over the Trash only.
private final class TrashGuardWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        isMovable = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Int(kCGDockWindowLevel) + 1)
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Accepts the file drag over the Trash and paints the uninstall affordance.
private final class TrashGuardView: NSView {
    var onDrop: (() -> Bool)?
    private var isHighlighted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TrashGuardView is created programmatically")
    }

    override var isOpaque: Bool { false }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender) else { return [] }
        setHighlighted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        setHighlighted(false)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        accepts(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        setHighlighted(false)
        return onDrop?() ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        setHighlighted(false)
    }

    private func accepts(_ sender: any NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    private func setHighlighted(_ highlighted: Bool) {
        guard isHighlighted != highlighted else { return }
        isHighlighted = highlighted
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 2, dy: 2),
            xRadius: 12,
            yRadius: 12
        )
        NSColor.systemRed.withAlphaComponent(0.18).setFill()
        path.fill()
        NSColor.systemRed.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
