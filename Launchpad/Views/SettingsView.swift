import AppKit
import Observation
import SwiftUI

/// Navigation state shared by the settings window and the launcher's
/// permission banner. The banner can ask the window to open on General and
/// flag the Accessibility row, which keeps that row highlighted in red until
/// the user clicks it.
@MainActor
@Observable
final class SettingsNavigation {
    var tab: SettingsTab = .general
    var highlightsAccessibility = false
}

/// The floating settings panel. It is a borderless window with its own tab
/// strip and red close button, matching the reference frames rather than the
/// standard macOS Settings window.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let navigation = SettingsNavigation()

    init(
        model: AppModel,
        settings: LaunchpadSettings
    ) {
        let window = SettingsPanelWindow()
        let view = SettingsView(
            model: model,
            settings: settings,
            navigation: navigation,
            onClose: { [weak window] in window?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 560, height: 640))
        window.minSize = NSSize(width: 520, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.styleMask = [.borderless]
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController is created programmatically")
    }

    /// - Parameter focusAccessibility: opens General with the Accessibility row
    ///   highlighted, used by the launcher's permission banner.
    func present(focusAccessibility: Bool = false) {
        guard let window else { return }
        if focusAccessibility {
            navigation.tab = .general
            navigation.highlightsAccessibility = true
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

/// Borderless windows refuse key status by default; the settings panel needs it
/// for the text-free controls and for Escape to close it.
final class SettingsPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct SettingsView: View {
    let model: AppModel
    @Bindable var settings: LaunchpadSettings
    let navigation: SettingsNavigation
    let onClose: () -> Void

    @State private var isTrusted = false
    @State private var hasInstalledCopy = false
    @State private var installError: String?
    @State private var showsResetLayoutAlert = false

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider().opacity(0.5)

            ScrollView {
                tabContent
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
            .scrollIndicators(.automatic)
        }
        .frame(width: 560, height: 640)
        .background(panelBackground)
        .overlay(alignment: .topLeading) { closeButton }
        .onExitCommand(perform: onClose)
        .task {
            hasInstalledCopy = AccessibilityAccess.isInstalled
            while !Task.isCancelled {
                isTrusted = AccessibilityAccess.isTrusted
                hasInstalledCopy = AccessibilityAccess.isInstalled
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: isTrusted) { _, trusted in
            if trusted {
                navigation.highlightsAccessibility = false
            }
            guard trusted, settings.suppressDesktopSwipe else { return }
            _ = TrackpadGestureBlocker.shared.installIfTrusted()
        }
        .alert("Reset the layout?", isPresented: $showsResetLayoutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { model.resetLayout() }
        } message: {
            Text("Folders, custom order and page splits will be removed. Apps are added back in catalog order.")
        }
    }

    // MARK: - Panel chrome

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.55))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Circle()
                .fill(Color(red: 1.0, green: 0.37, blue: 0.34))
                .frame(width: 12, height: 12)
                .overlay {
                    Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .padding(14)
        .help("Close")
        .accessibilityLabel(Text("Close settings"))
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        navigation.tab = item
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(navigation.tab == item ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        if navigation.tab == item {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.10), radius: 4, y: 1)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Tabs

    @ViewBuilder
    private var tabContent: some View {
        switch navigation.tab {
        case .general:
            generalTab
        case .interface:
            interfaceTab
        case .advanced:
            advancedTab
        case .about:
            aboutTab
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Launch") {
                toggleRow("Open with ⌥Space", isOn: $settings.hotKeyEnabled)
                toggleRow("Open at a screen corner", isOn: $settings.hotCornerEnabled)
                if settings.hotCornerEnabled {
                    pickerRow("Corner", selection: $settings.hotCorner) {
                        ForEach(LaunchpadSettings.HotCorner.allCases) { corner in
                            Text(corner.title).tag(corner)
                        }
                    }
                }
                toggleRow("Pinch with four fingers", isOn: $settings.pinchEnabled)
                toggleRow("Tap on chassis", isOn: $settings.tapOnChassisEnabled)
                    .disabled(true)
                    .opacity(0.5)
                    .help("Coming in a later update")
                caption(
                    "Pinch needs Accessibility and “Block system gestures while open”. "
                        + "Turning it off hands macOS's Apps pinch back to the system. "
                        + "Tapping the chassis is coming in a later update."
                )
            }

            group("Trackpad") {
                toggleRow(
                    "Block system gestures while open",
                    isOn: $settings.suppressDesktopSwipe
                )
                caption(
                    "While Launchpad is open, two-, three-, four- and five-finger swipes page "
                        + "the grid, and the desktop swipe, Mission Control and Show Desktop stand "
                        + "down. With “Pinch with four fingers” on, macOS's own Apps view is also "
                        + "disabled so it cannot open instead of Launchpad; turning that off gives "
                        + "its pinch back. Spotlight stays available on ⌘Space. Requires Accessibility."
                )
            }

            group("Accessibility") {
                accessibilityRow
            }

            group("Menu Bar") {
                toggleRow("Show menu bar icon", isOn: $settings.showMenuBarIcon)
            }
        }
    }

    private var interfaceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Grid") {
                segmentedRow("Columns", selection: $settings.columns, values: LaunchpadSettings.columnChoices)
                segmentedRow("Rows", selection: $settings.rows, values: LaunchpadSettings.rowChoices)
                caption("Changing the grid reflows your pages.")
                sliderRow(
                    "Icon size",
                    value: $settings.iconScale,
                    range: 0.75...1.3,
                    step: 0.05,
                    format: { "\(Int(($0 * 100).rounded()))%" }
                )
                sliderRow(
                    "Label size",
                    value: $settings.labelScale,
                    range: 0.75...1.4,
                    step: 0.05,
                    format: { "\(Int(($0 * 100).rounded()))%" }
                )
                toggleRow("Show app names", isOn: $settings.showLabels)
            }

            group("Background") {
                toggleRow("Blur wallpaper", isOn: $settings.blurWallpaper)
                sliderRow(
                    "Dim",
                    value: $settings.backgroundDim,
                    range: 0...0.6,
                    step: 0.02,
                    format: { "\(Int(($0 * 100).rounded()))%" }
                )
            }
        }
    }

    private var advancedTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Layout") {
                buttonRow("Reset layout") {
                    showsResetLayoutAlert = true
                }
            }

            group("Settings") {
                buttonRow("Restore default settings") {
                    settings.resetToDefaults()
                }
            }

            group("Accessibility") {
                buttonRow("Open Accessibility settings") {
                    AccessibilityAccess.openSettings()
                }
                buttonRow("Show Launchpad in Finder") {
                    AccessibilityAccess.revealInFinder()
                }
                buttonRow("Reinstall gesture blocker") {
                    TrackpadGestureBlocker.shared.uninstall()
                    if settings.suppressDesktopSwipe {
                        _ = TrackpadGestureBlocker.shared.installIfTrusted()
                    }
                    isTrusted = AccessibilityAccess.isTrusted
                }
            }
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 58, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 84, height: 84)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }

            Text("Launchpad")
                .font(.title2.weight(.semibold))

            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(
                "A native macOS 26 Launchpad: a paged app grid, folders, search, "
                    + "Liquid Glass and trackpad paging."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)

            Text("Built with SwiftUI and AppKit. No analytics, no network.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Rows

    private var accessibilityRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isTrusted ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility access")
                        .font(.system(size: 13))
                    Text(isTrusted ? "Granted" : "Required to block system gestures")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if isTrusted {
                    Button("Open Settings") {
                        navigation.highlightsAccessibility = false
                        AccessibilityAccess.openSettings()
                    }
                    .controlSize(.small)
                } else {
                    Button("Enable") {
                        grantAccess()
                    }
                    .controlSize(.small)
                }
            }

            if !isTrusted {
                HStack(spacing: 12) {
                    Button("Show in Finder") {
                        AccessibilityAccess.revealInFinder()
                    }
                    if !AccessibilityAccess.isRunningInstalledCopy, !hasInstalledCopy {
                        Button("Install in Applications") {
                            installCopy()
                        }
                    }
                    if hasInstalledCopy, !AccessibilityAccess.isRunningInstalledCopy {
                        Button("Relaunch from Applications") {
                            AccessibilityAccess.relaunchFromApplications()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .controlSize(.small)
                .buttonStyle(.link)

                Text(accessGuidance)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(navigation.highlightsAccessibility ? Color.red.opacity(0.10) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    Color.red,
                    lineWidth: navigation.highlightsAccessibility ? 2 : 0
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .simultaneousGesture(
            TapGesture().onEnded {
                navigation.highlightsAccessibility = false
            }
        )
    }

    /// The instructions depend on where the app is running from: the list only
    /// shows a copy the user can identify, and a stale entry from a previous
    /// build may need to be removed.
    private var accessGuidance: String {
        if let installError {
            return installError
        }
        if hasInstalledCopy, !AccessibilityAccess.isRunningInstalledCopy {
            return "Launchpad is installed in Applications. Use Relaunch from Applications, "
                + "then grant access to that copy."
        }
        return "Enable opens System Settings and turns on Launchpad under Accessibility. "
            + "If the switch already looks on but blocking does nothing, Enable refreshes it."
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5).padding(.leading, 14)
        }
    }

    private func pickerRow<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            Picker("", selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5).padding(.leading, 14)
        }
    }

    private func segmentedRow(
        _ title: String,
        selection: Binding<Int>,
        values: [Int]
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            Picker("", selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 126)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5).padding(.leading, 14)
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer(minLength: 12)
                Text(format(value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5).padding(.leading, 14)
        }
    }

    private func buttonRow(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Button(title, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5).padding(.leading, 14)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
    }

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Helpers

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    private func grantAccess() {
        navigation.highlightsAccessibility = false
        AccessibilityAccess.grant()
    }

    private func installCopy() {
        do {
            _ = try AccessibilityAccess.installInApplications()
            installError = nil
            hasInstalledCopy = true
        } catch {
            installError = error.localizedDescription
        }
    }
}

enum SettingsTab: CaseIterable, Identifiable {
    case general
    case interface
    case advanced
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .interface: return "Interface"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .interface: return "square.grid.3x3"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}
