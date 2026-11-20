import AppKit
import Observation
import SwiftUI

/// State behind the uninstall confirmation panel.
@MainActor
@Observable
final class UninstallModel {
    enum SelectionState: Equatable {
        case none
        case some
        case all
    }

    struct Group: Identifiable {
        let kind: UninstallComponent.Kind
        let components: [UninstallComponent]

        var id: UninstallComponent.Kind { kind }
    }

    let app: AppItem
    let components: [UninstallComponent]
    let home: URL

    private(set) var sizes: [URL: Int64]
    private(set) var isMeasuring: Bool

    var selected: Set<URL>
    var expanded: Set<UninstallComponent.Kind>

    init(
        app: AppItem,
        components: [UninstallComponent],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        sizes: [URL: Int64] = [:],
        isMeasuring: Bool = true
    ) {
        self.app = app
        self.components = components
        self.home = home
        self.sizes = sizes
        self.isMeasuring = isMeasuring
        self.selected = Set(components.map(\.url))
        self.expanded = Set(components.map(\.kind))
    }

    var groups: [Group] {
        UninstallComponent.Kind.allCases.compactMap { kind in
            let items = components.filter { $0.kind == kind }
            return items.isEmpty ? nil : Group(kind: kind, components: items)
        }
    }

    var allSelected: Bool {
        !components.isEmpty && selected.count == components.count
    }

    var hasSelection: Bool {
        !selected.isEmpty
    }

    var selectedComponents: [UninstallComponent] {
        components.filter { selected.contains($0.url) }
    }

    var totalBytes: Int64 {
        components.reduce(0) { $0 + (sizes[$1.url] ?? 0) }
    }

    func isSelected(_ component: UninstallComponent) -> Bool {
        selected.contains(component.url)
    }

    func toggle(_ component: UninstallComponent) {
        if selected.contains(component.url) {
            selected.remove(component.url)
        } else {
            selected.insert(component.url)
        }
    }

    func selectionState(for kind: UninstallComponent.Kind) -> SelectionState {
        let urls = components.filter { $0.kind == kind }.map(\.url)
        let included = urls.reduce(0) { selected.contains($1) ? $0 + 1 : $0 }
        if included == 0 { return .none }
        return included == urls.count ? .all : .some
    }

    func toggleGroup(_ kind: UninstallComponent.Kind) {
        let urls = components.filter { $0.kind == kind }.map(\.url)
        if urls.allSatisfy({ selected.contains($0) }) {
            selected.subtract(urls)
        } else {
            selected.formUnion(urls)
        }
    }

    func toggleAll() {
        if allSelected {
            selected.removeAll()
        } else {
            selected = Set(components.map(\.url))
        }
    }

    func isExpanded(_ kind: UninstallComponent.Kind) -> Bool {
        expanded.contains(kind)
    }

    func toggleExpanded(_ kind: UninstallComponent.Kind) {
        if expanded.contains(kind) {
            expanded.remove(kind)
        } else {
            expanded.insert(kind)
        }
    }

    func sizeText(for component: UninstallComponent) -> String {
        guard let bytes = sizes[component.url] else { return "—" }
        return UninstallSize.formatted(bytes)
    }

    func abbreviatedPath(_ url: URL) -> String {
        let homePath = home.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") {
            return "~" + String(path.dropFirst(homePath.count))
        }
        return path
    }

    /// Walks every component off the main thread; the panel shows a spinner
    /// until the sizes arrive.
    func measure() async {
        guard isMeasuring else { return }
        let components = self.components
        let measured = await Task.detached(priority: .userInitiated) {
            var sizes: [URL: Int64] = [:]
            sizes.reserveCapacity(components.count)
            for component in components {
                sizes[component.url] = UninstallSize.allocatedSize(of: component.url)
            }
            return sizes
        }.value
        sizes = measured
        isMeasuring = false
    }
}

/// The white confirmation panel from frames 065–066.
struct UninstallDialogView: View {
    static let width: CGFloat = 420
    static let height: CGFloat = 300

    let model: UninstallModel
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
        }
        .onExitCommand(perform: onCancel)
        .task {
            await model.measure()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: model.app.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(model.isMeasuring ? "Calculating…" : UninstallSize.formatted(model.totalBytes))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.isMeasuring {
            ProgressView()
                .controlSize(.regular)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.components.isEmpty {
            Text("No related files were found.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.groups) { group in
                        groupView(group)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func groupView(_ group: UninstallModel.Group) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                checkbox(state: model.selectionState(for: group.kind)) {
                    model.toggleGroup(group.kind)
                }
                .accessibilityLabel(Text(group.kind.title))

                Button {
                    withAnimation(.snappy(duration: 0.15)) {
                        model.toggleExpanded(group.kind)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(group.kind.title)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Image(
                            systemName: model.isExpanded(group.kind)
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(model.isExpanded(group.kind) ? "Collapse" : "Expand")
                )
            }
            .padding(.horizontal, 8)
            .frame(height: 26)

            if model.isExpanded(group.kind) {
                ForEach(group.components) { component in
                    row(component)
                }
            }
        }
    }

    private func row(_ component: UninstallComponent) -> some View {
        HStack(spacing: 7) {
            Color.clear
                .frame(width: 17, height: 1)

            checkbox(state: model.isSelected(component) ? .all : .none) {
                model.toggle(component)
            }

            Image(nsImage: NSWorkspace.shared.icon(forFile: component.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 0) {
                Text(component.name)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.abbreviatedPath(component.url))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            Text(model.sizeText(for: component))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([component.url])
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
            .accessibilityLabel(Text("Show \(component.name) in Finder"))
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 7) {
            checkbox(state: allState) {
                model.toggleAll()
            }
            .disabled(model.isMeasuring)
            .accessibilityLabel(Text("All"))

            Text("All")
                .font(.system(size: 11.5))

            Spacer(minLength: 8)

            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)

            Button("Move to Trash", action: onConfirm)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isMeasuring || !model.hasSelection)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var allState: UninstallModel.SelectionState {
        if !model.hasSelection { return .none }
        return model.allSelected ? .all : .some
    }

    // MARK: - Checkboxes

    private func checkbox(
        state: UninstallModel.SelectionState,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol(for: state))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    state == .none
                        ? Color.secondary.opacity(0.45)
                        : Color.accentColor
                )
                .frame(width: 15, height: 15)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func symbol(for state: UninstallModel.SelectionState) -> String {
        switch state {
        case .none: "square"
        case .some: "minus.square.fill"
        case .all: "checkmark.square.fill"
        }
    }
}

/// Borderless panels need this override to take key status for the buttons.
final class UninstallDialogWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Runs the confirmation as an application-modal panel.
@MainActor
final class UninstallDialogController {
    private let model: UninstallModel

    init(app: AppItem, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.model = UninstallModel(
            app: app,
            components: UninstallScanner.components(for: app, home: home),
            home: home
        )
    }

    /// Returns the checked components, or `nil` when the user cancels.
    func run() -> [UninstallComponent]? {
        NSRunningApplication.current.activate(
            options: NSApplication.ActivationOptions(rawValue: 1 << 1)
        )

        let window = makeWindow()
        let response = NSApp.runModal(for: window)
        window.orderOut(nil)
        return response == .OK ? model.selectedComponents : nil
    }

    private func makeWindow() -> NSWindow {
        let view = UninstallDialogView(
            model: model,
            onCancel: { NSApp.stopModal(withCode: .cancel) },
            onConfirm: { NSApp.stopModal(withCode: .OK) }
        )
        let size = NSSize(
            width: UninstallDialogView.width,
            height: UninstallDialogView.height
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = UninstallDialogWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        // The reference dialog is white even over the dark backdrop.
        window.appearance = NSAppearance(named: .aqua)
        window.animationBehavior = .none
        window.center()
        return window
    }
}
