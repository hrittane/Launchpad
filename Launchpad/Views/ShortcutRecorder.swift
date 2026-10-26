import AppKit
import SwiftUI

/// AppKit-backed shortcut recorder. SwiftUI cannot observe raw key codes with
/// the fidelity a global shortcut needs, so this small NSView becomes first
/// responder and captures the next chord.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: KeyShortcut

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.shortcut = shortcut
        view.onChange = { newValue in
            context.coordinator.parent.shortcut = newValue
        }
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        context.coordinator.parent = self
        nsView.shortcut = shortcut
        nsView.onChange = { newValue in
            context.coordinator.parent.shortcut = newValue
        }
    }

    final class Coordinator {
        var parent: ShortcutRecorder

        init(_ parent: ShortcutRecorder) {
            self.parent = parent
        }
    }

    final class RecorderView: NSView {
        var shortcut: KeyShortcut = .launchpadDefault {
            didSet { needsDisplay = true }
        }
        var onChange: ((KeyShortcut) -> Void)?

        private var isRecording = false
        private var pendingModifiers: NSEvent.ModifierFlags = []

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            focusRingType = .none
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel(String(localized: "Global shortcut", comment: "Shortcut recorder accessibility label"))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
        }

        override func becomeFirstResponder() -> Bool {
            isRecording = true
            pendingModifiers = []
            needsDisplay = true
            return super.becomeFirstResponder()
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            pendingModifiers = []
            needsDisplay = true
            return super.resignFirstResponder()
        }

        override func flagsChanged(with event: NSEvent) {
            guard isRecording else {
                super.flagsChanged(with: event)
                return
            }
            pendingModifiers = KeyShortcut.modifiers(from: event.modifierFlags)
            needsDisplay = true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }

            // Escape cancels recording without changing the existing shortcut.
            if event.keyCode == 53 {
                isRecording = false
                window?.makeFirstResponder(nil)
                return
            }

            // Modifier-only keys are handled by flagsChanged.
            if KeyShortcut.modifierOnlyKeyCodes.contains(event.keyCode) {
                return
            }

            let displayKey = KeyShortcut.displayKey(for: event)
            guard !displayKey.isEmpty else {
                NSSound.beep()
                return
            }

            let newValue = KeyShortcut(
                keyCode: event.keyCode,
                modifierFlags: KeyShortcut.modifiers(from: event.modifierFlags).rawValue,
                displayKey: displayKey
            )
            shortcut = newValue
            onChange?(newValue)
            isRecording = false
            window?.makeFirstResponder(nil)
        }

        override func draw(_ dirtyRect: NSRect) {
            let bounds = self.bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)

            if isRecording {
                NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
            } else {
                NSColor.textBackgroundColor.withAlphaComponent(0.65).setFill()
            }
            path.fill()

            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = isRecording ? 1.5 : 1
            path.stroke()

            let text: String
            if isRecording {
                text = pendingModifiers.isEmpty
                    ? String(localized: "Type shortcut…", comment: "Shortcut recorder prompt")
                    : KeyShortcut.modifierSymbols(for: pendingModifiers)
            } else {
                text = shortcut.displayString
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let height = attributed.size().height
            attributed.draw(in: NSRect(
                x: 6,
                y: (bounds.height - height) / 2,
                width: max(1, bounds.width - 12),
                height: height
            ))
        }

        override func accessibilityValue() -> Any? {
            isRecording
                ? String(localized: "Recording", comment: "Shortcut recorder accessibility value")
                : shortcut.displayString
        }
    }
}

extension KeyShortcut {
    static let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// Human-readable key label captured when the user records a shortcut.
    static func displayKey(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36, 76: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Esc"
        case 64: return "F17"
        case 79: return "F18"
        case 80: return "F19"
        case 90: return "F20"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 115: return "Home"
        case 116: return "Page Up"
        case 117: return "Forward Delete"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "Page Down"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            break
        }

        let characters = event.charactersIgnoringModifiers ?? ""
        guard let first = characters.first, first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol else {
            return ""
        }
        return characters.uppercased()
    }
}
