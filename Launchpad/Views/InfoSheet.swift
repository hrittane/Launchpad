import AppKit
import SwiftUI

/// Native information sheet for an application. This replaces Finder
/// automation, so it works without Apple Events or Accessibility permission.
struct InfoSheet: View {
    let app: AppItem
    @ObservedObject var viewModel: LaunchpadViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                AppIconImage(path: app.filePath, size: 88, fallbackName: app.name)
                    .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(2)
                    Text(app.isSystemApp
                         ? String(localized: "System Application", comment: "Info sheet kind")
                         : String(localized: "Application", comment: "Info sheet kind"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let version = app.version {
                        Text(verbatim: "\(String(localized: "Version", comment: "Info sheet version label")) \(version)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                infoRow(
                    title: String(localized: "Bundle Identifier", comment: "Info sheet label"),
                    value: app.bundleIdentifier ?? String(localized: "Unknown", comment: "Info sheet unknown value")
                )
                infoRow(
                    title: String(localized: "Location", comment: "Info sheet label"),
                    value: app.url.deletingLastPathComponent().path
                )
                infoRow(
                    title: String(localized: "Full Path", comment: "Info sheet label"),
                    value: app.filePath
                )
                infoRow(
                    title: String(localized: "System App", comment: "Info sheet label"),
                    value: app.isSystemApp
                        ? String(localized: "Yes", comment: "Info sheet boolean")
                        : String(localized: "No", comment: "Info sheet boolean")
                )
            }

            Spacer(minLength: 0)

            HStack {
                Button {
                    dismiss()
                    viewModel.showInFinder(app)
                } label: {
                    Text("Show in Finder", comment: "Info sheet button")
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Close", comment: "Info sheet button")
                        .frame(minWidth: 70)
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }
}
