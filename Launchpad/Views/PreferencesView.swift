import AppKit
import SwiftUI

/// SwiftUI Preferences scene. Every change writes through the view model so it
/// is persisted and applied (hot key, hot corner, mirrors) immediately.
struct PreferencesView: View {
    @ObservedObject var viewModel: LaunchpadViewModel

    @State private var showResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                section(Text("Grid", comment: "Preferences section")) {
                    HStack {
                        Text("Columns", comment: "Preferences label")
                        Spacer()
                        Picker("", selection: binding(\.columns)) {
                            ForEach(5...9, id: \.self) { value in
                                Text(verbatim: "\(value)").tag(value)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 84)
                    }
                    HStack {
                        Text("Rows", comment: "Preferences label")
                        Spacer()
                        Picker("", selection: binding(\.rows)) {
                            ForEach(4...6, id: \.self) { value in
                                Text(verbatim: "\(value)").tag(value)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 84)
                    }
                    Text(
                        "Grid capacity: \(viewModel.settings.pageCapacity) items per page",
                        comment: "Preferences grid capacity caption"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                section(Text("Appearance", comment: "Preferences section")) {
                    sliderRow(
                        title: Text("Icon size", comment: "Preferences label"),
                        value: iconSizeBinding,
                        range: iconSizeRange,
                        step: 2,
                        valueText: "\(Int(iconSizeValue)) pt"
                    )
                    Text(
                        "The grid fits icons up to \(Int(iconSizeRange.upperBound)) pt at this label size and grid size.",
                        comment: "Icon size limit caption"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    sliderRow(
                        title: Text("Label size", comment: "Preferences label"),
                        value: binding(\.labelFontSize),
                        range: 11...15,
                        step: 1,
                        valueText: "\(Int(viewModel.settings.labelFontSize)) pt"
                    )
                    sliderRow(
                        title: Text("Blur intensity", comment: "Preferences label"),
                        value: binding(\.blurIntensity),
                        range: 0...1,
                        step: 0.05,
                        valueText: "\(Int(viewModel.settings.blurIntensity * 100))%"
                    )
                    Text(
                        "AppKit exposes blur materials rather than a Gaussian radius, so this control adjusts the backdrop's tint and dimming.",
                        comment: "Blur limitation caption"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                section(Text("Activation", comment: "Preferences section")) {
                    HStack {
                        Text("Global shortcut", comment: "Preferences label")
                        Spacer()
                        ShortcutRecorder(shortcut: binding(\.shortcut))
                            .frame(width: 170, height: 28)
                        Button {
                            viewModel.settings.shortcut = .launchpadDefault
                        } label: {
                            Text("Reset", comment: "Reset shortcut button")
                        }
                    }
                    HStack {
                        Text("Hot corner", comment: "Preferences label")
                        Spacer()
                        Picker("", selection: binding(\.hotCorner)) {
                            ForEach(HotCorner.allCases) { corner in
                                Text(corner.localizedName).tag(corner)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                    Toggle(
                        isOn: binding(\.showOnAllDisplays)
                    ) {
                        Text("Show on all displays", comment: "Preferences toggle")
                    }
                    Toggle(
                        isOn: launchAtLoginBinding
                    ) {
                        Text("Launch at login", comment: "Preferences toggle")
                    }
                    Text(
                        "Only the display under the cursor accepts input; other displays show a mirrored, non-interactive copy.",
                        comment: "Multi-display caption"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                section(Text("Data", comment: "Preferences section")) {
                    HStack {
                        Button {
                            showResetConfirmation = true
                        } label: {
                            Text("Reset Layout", comment: "Preferences button")
                        }
                        Button {
                            viewModel.clearIconCache()
                        } label: {
                            Text("Clear Icon Cache", comment: "Preferences button")
                        }
                        Spacer()
                    }
                    Button {
                        NSWorkspace.shared.open(LayoutStore.applicationSupportDirectory())
                    } label: {
                        Text("Show Data Folder", comment: "Preferences button")
                    }
                    Text(LayoutStore.defaultFileURL().path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                Text(
                    "Changes are saved automatically.",
                    comment: "Preferences footer"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
        }
        .frame(minWidth: 520, idealWidth: 520)
        .onAppear {
            clampIconSize()
        }
        .onChange(of: viewModel.settings.labelFontSize) { _ in
            clampIconSize()
        }
        .onChange(of: viewModel.settings.columns) { _ in
            clampIconSize()
        }
        .onChange(of: viewModel.settings.rows) { _ in
            clampIconSize()
        }
        .onChange(of: viewModel.screenSize) { _ in
            clampIconSize()
        }
        .alert(
            Text("Reset layout?", comment: "Reset confirmation title"),
            isPresented: $showResetConfirmation
        ) {
            Button(role: .destructive) {
                viewModel.resetLayout()
            } label: {
                Text("Reset", comment: "Reset confirmation button")
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", comment: "Cancel button")
            }
        } message: {
            Text(
                "This restores alphabetical order and removes all folders. App files are not affected.",
                comment: "Reset confirmation message"
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Launchpad", comment: "Preferences header title")
                    .font(.title2.weight(.semibold))
                Text("Application launcher", comment: "Preferences header subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// Current grid math, used to keep the icon-size slider inside the range
    /// that actually changes the rendered icons.
    private var layoutMetrics: LayoutMetrics {
        LayoutMetrics(screenSize: viewModel.screenSize, settings: viewModel.settings)
    }

    private var iconSizeRange: ClosedRange<Double> {
        let raw = Double(layoutMetrics.maximumIconSize)
        // Round up to the next 2 pt step so the top of the slider still reaches
        // the largest icon the grid can draw; every step below it is effective.
        let stepped = (raw / 2).rounded(.up) * 2
        return 64...min(128, max(64, stepped))
    }

    private var iconSizeValue: Double {
        min(max(viewModel.settings.iconSize, iconSizeRange.lowerBound), iconSizeRange.upperBound)
    }

    private var iconSizeBinding: Binding<Double> {
        Binding(
            get: { iconSizeValue },
            set: { newValue in
                var settings = viewModel.settings
                settings.iconSize = newValue
                viewModel.settings = settings
            }
        )
    }

    /// Keeps the stored value in the effective range after the label size or
    /// grid dimensions change the available icon space.
    private func clampIconSize() {
        let upper = iconSizeRange.upperBound
        guard viewModel.settings.iconSize > upper else { return }
        var settings = viewModel.settings
        settings.iconSize = upper
        viewModel.settings = settings
    }

    private func section<Content: View>(
        _ title: Text,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func sliderRow(
        title: Text,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(spacing: 4) {
            HStack {
                title
                Spacer()
                Text(verbatim: valueText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.launchAtLogin },
            set: { newValue in
                let applied = LaunchAtLoginService.setEnabled(newValue)
                var settings = viewModel.settings
                settings.launchAtLogin = applied ? newValue : LaunchAtLoginService.isEnabled
                viewModel.settings = settings
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.settings[keyPath: keyPath] },
            set: { newValue in
                var settings = viewModel.settings
                settings[keyPath: keyPath] = newValue
                viewModel.settings = settings
            }
        )
    }
}
